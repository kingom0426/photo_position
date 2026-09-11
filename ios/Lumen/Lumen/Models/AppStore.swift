import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var posts: [PhotoPost] = []
    @Published private(set) var comments: [PhotoComment] = []
    @Published private(set) var likedPostIDs: Set<UUID> = []
    @Published private(set) var plannedPostIDs: Set<UUID> = []
    @Published private(set) var followedUserIDs: Set<String> = []
    @Published private(set) var followedUsers: [UserProfile] = []
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadNotificationCount = 0
    @Published private(set) var defaultTags: [SearchTag] = []
    @Published private(set) var currentUser: CurrentUser = .guest
    @Published private(set) var isAuthenticated = false
    @Published var showingAuthentication = false
    @Published var selectedTab = 0
    @Published private(set) var mapFocusPostID: UUID?
    @Published private(set) var syncError: String?

    private let api = APIClient.shared
    private let cachedUserKey = "lumen.auth.cached-user"
    private var pendingReadNotificationIDs: Set<UUID> = []

    init() {
        guard api.hasSession,
              let data = UserDefaults.standard.data(forKey: cachedUserKey),
              let user = try? JSONDecoder().decode(CurrentUser.self, from: data) else {
            return
        }
        currentUser = user
        isAuthenticated = true
    }

    var originals: [PhotoPost] {
        posts.filter { $0.kind == .original }.sorted { $0.createdAt > $1.createdAt }
    }

    var currentUserPosts: [PhotoPost] {
        guard isAuthenticated else { return [] }
        return posts.filter { $0.authorID == currentUser.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func post(id: UUID) -> PhotoPost? { posts.first { $0.id == id } }
    func assignments(for originalID: UUID) -> [PhotoPost] {
        posts.filter { $0.kind == .assignment && $0.originalID == originalID }
    }
    func assignment(for originalID: UUID, authorID: String) -> PhotoPost? {
        assignments(for: originalID).first { $0.authorID == authorID }
    }
    func comments(for postID: UUID) -> [PhotoComment] {
        comments.filter { $0.postID == postID }.sorted { $0.createdAt < $1.createdAt }
    }
    func isLiked(_ id: UUID) -> Bool { likedPostIDs.contains(id) }
    func isPlanned(_ id: UUID) -> Bool {
        guard post(id: id)?.authorID != currentUser.id else { return false }
        return plannedPostIDs.contains(id)
    }
    func isFollowing(_ id: String) -> Bool {
        id != currentUser.id && followedUserIDs.contains(id)
    }

    func showPostOnMap(_ postID: UUID) {
        selectedTab = 1
        Task { @MainActor [weak self] in
            await Task.yield()
            await Task.yield()
            self?.mapFocusPostID = postID
        }
    }

    func consumeMapFocus() {
        mapFocusPostID = nil
    }

    func start() async {
        if api.hasSession {
            do {
                currentUser = try await api.currentUser().localUser()
                isAuthenticated = true
                cacheCurrentUser()
            } catch {
                api.logout()
                currentUser = .guest
                isAuthenticated = false
                clearCachedUser()
            }
        }
        await sync()
        await loadDefaultTags()
        if isAuthenticated {
            await loadNotifications()
        }
    }

    func requireAuthentication() -> Bool {
        guard isAuthenticated else {
            showingAuthentication = true
            return false
        }
        return true
    }

    func fetchUserConsent() async throws -> ConsentDocument {
        try await api.fetchUserConsent()
    }

    func register(
        email: String,
        password: String,
        nickname: String,
        consentAccepted: Bool,
        consentVersion: String,
        verificationCode: String
    ) async throws {
        let response = try await api.register(
            email: email,
            password: password,
            nickname: nickname,
            consentAccepted: consentAccepted,
            consentVersion: consentVersion,
            verificationCode: verificationCode
        )
        currentUser = response.user.localUser()
        isAuthenticated = true
        showingAuthentication = false
        cacheCurrentUser()
        Task { await sync() }
        Task { await loadNotifications() }
    }

    func login(email: String, password: String) async throws {
        let response = try await api.login(email: email, password: password)
        currentUser = response.user.localUser()
        isAuthenticated = true
        showingAuthentication = false
        cacheCurrentUser()
        Task { await sync() }
        Task { await loadNotifications() }
    }

    func logout() {
        currentUser = .guest
        isAuthenticated = false
        likedPostIDs = []
        plannedPostIDs = []
        followedUserIDs = []
        followedUsers = []
        notifications = []
        unreadNotificationCount = 0
        pendingReadNotificationIDs = []
        showingAuthentication = false
        clearCachedUser()
        api.logout()
    }

    func sendRegistrationCode(email: String) async throws -> String {
        try await api.sendRegistrationCode(email: email)
    }

    func forgotPassword(email: String) async throws -> String {
        try await api.forgotPassword(email: email)
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        try await api.changePassword(oldPassword: oldPassword, newPassword: newPassword)
        logout()
    }

    func toggleLike(_ id: UUID) {
        guard requireAuthentication() else { return }
        if !likedPostIDs.insert(id).inserted { likedPostIDs.remove(id) }
        Task {
            do {
                let result = try await api.toggleLike(postID: id)
                if result.liked { likedPostIDs.insert(id) } else { likedPostIDs.remove(id) }
                if let index = posts.firstIndex(where: { $0.id == id }) {
                    posts[index].likeCount = max(result.likeCount - (result.liked ? 1 : 0), 0)
                }
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func togglePlan(_ id: UUID) {
        guard requireAuthentication() else { return }
        guard post(id: id)?.authorID != currentUser.id else {
            plannedPostIDs.remove(id)
            return
        }
        if !plannedPostIDs.insert(id).inserted { plannedPostIDs.remove(id) }
        Task {
            do {
                let result = try await api.togglePlan(postID: id)
                if result.planned { plannedPostIDs.insert(id) } else { plannedPostIDs.remove(id) }
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func toggleFollow(_ id: String) {
        guard requireAuthentication() else { return }
        guard id != currentUser.id else {
            followedUserIDs.remove(id)
            followedUsers.removeAll { $0.id == id }
            return
        }
        let wasFollowing = followedUserIDs.contains(id)
        setFollowState(!wasFollowing, userID: id)
        Task {
            do {
                let result = try await api.toggleFollow(userID: id)
                setFollowState(result.following, userID: id)
            } catch {
                setFollowState(wasFollowing, userID: id)
                syncError = error.localizedDescription
            }
        }
    }

    func addComment(postID: UUID, text: String) {
        guard requireAuthentication() else { return }
        comments.append(PhotoComment(
            id: UUID(), postID: postID, authorID: currentUser.id, authorName: currentUser.name,
            authorAvatar: currentUser.avatar, text: text, createdAt: Date()
        ))
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index].commentCount += 1
        }
        Task {
            do {
                _ = try await api.addComment(postID: postID, text: text)
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func loadComments(postID: UUID) async {
        do {
            let loaded = try await api.fetchComments(postID: postID)
                .map { $0.localComment(postID: postID) }
            comments.removeAll { $0.postID == postID }
            comments.append(contentsOf: loaded)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].commentCount = loaded.count
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    @discardableResult
    func publishToServer(_ post: PhotoPost, imageData: Data) async throws -> PhotoPost {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        let remote = try await api.publish(post, imageData: imageData)
        var published = remote.localPost()
        // Keep the just-uploaded image locally so the new card renders immediately.
        // A later sync/relaunch naturally switches to the server thumbnail URL.
        published.imageData = imageData
        posts.insert(published, at: 0)
        if remote.liked { likedPostIDs.insert(published.id) }
        if remote.planned { plannedPostIDs.insert(published.id) }
        if published.kind == .assignment, let originalID = published.originalID {
            plannedPostIDs.remove(originalID)
        }
        return published
    }

    func updateOnServer(_ post: PhotoPost, replacing existing: PhotoPost, imageData: Data?) async throws {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        let remote = try await api.update(post, imageData: imageData)
        var updated = remote.localPost()
        updated.imageData = imageData ?? existing.imageData
        guard let index = posts.firstIndex(where: { $0.id == existing.id }) else { return }
        posts[index] = updated
    }

    func deletePost(_ postID: UUID) async throws {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        guard post(id: postID)?.authorID == currentUser.id else {
            throw APIError.server("只能删除自己的作品")
        }
        try await api.delete(postID: postID)
        posts.removeAll { $0.id == postID }
        comments.removeAll { $0.postID == postID }
        likedPostIDs.remove(postID)
        plannedPostIDs.remove(postID)
        if mapFocusPostID == postID {
            mapFocusPostID = nil
        }
    }

    func updateCurrentCity(_ city: String) {
        guard isAuthenticated, !city.isEmpty, currentUser.city != city else { return }
        currentUser.city = city
    }

    func updateAvatar(imageData: Data) async throws {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        let user = try await api.updateAvatar(imageData: imageData)
        currentUser = user.localUser()
        cacheCurrentUser()
        for index in posts.indices where posts[index].authorID == currentUser.id {
            posts[index].authorAvatar = currentUser.avatar
        }
        for index in comments.indices where comments[index].authorName == currentUser.name {
            comments[index].authorAvatar = currentUser.avatar
        }
    }

    func updateNickname(_ nickname: String) async throws {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        let previousName = currentUser.name
        let user = try await api.updateNickname(nickname)
        currentUser = user.localUser()
        cacheCurrentUser()
        for index in posts.indices where posts[index].authorID == currentUser.id {
            posts[index].authorName = currentUser.name
        }
        for index in comments.indices where comments[index].authorName == previousName {
            comments[index].authorName = currentUser.name
        }
    }

    func updateBio(_ bio: String) async throws {
        guard requireAuthentication() else { throw APIError.authenticationRequired }
        let user = try await api.updateBio(bio)
        currentUser = user.localUser()
        cacheCurrentUser()
    }

    func sync() async {
        do {
            let remote = try await api.fetchPosts()
            posts = remote.map { $0.localPost() }
            likedPostIDs = Set(remote.filter(\.liked).map(\.id))
            plannedPostIDs = Set(remote.filter(\.planned).map(\.id))
            if isAuthenticated {
                followedUsers = try await api.fetchFollowing().map { $0.localProfile() }
                followedUserIDs = Set(followedUsers.map(\.id))
            } else {
                followedUsers = []
                followedUserIDs = []
            }
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    func loadFeed(
        feed: String,
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double?,
        filters: Set<String>
    ) async -> [PhotoPost]? {
        do {
            let remote = try await api.fetchPosts(
                feed: feed,
                latitude: latitude,
                longitude: longitude,
                radiusKm: radiusKm,
                filters: filters
            )
            let loaded = remote.map { $0.localPost() }
            likedPostIDs.formUnion(remote.filter(\.liked).map(\.id))
            plannedPostIDs.formUnion(remote.filter(\.planned).map(\.id))
            mergePosts(loaded)
            syncError = nil
            return loaded
        } catch {
            syncError = error.localizedDescription
            return nil
        }
    }

    func loadPosts(authorID: String) async -> [PhotoPost]? {
        do {
            let remote = try await api.fetchPosts(authorID: authorID)
            let loaded = remote.map { $0.localPost() }
            likedPostIDs.formUnion(remote.filter(\.liked).map(\.id))
            plannedPostIDs.formUnion(remote.filter(\.planned).map(\.id))
            mergePosts(loaded)
            syncError = nil
            return loaded
        } catch {
            syncError = error.localizedDescription
            return nil
        }
    }

    func search(_ query: String) async -> GroupedSearchResults {
        do {
            let remote = try await api.search(query)
            let loadedPosts = remote.posts.map { $0.localPost() }
            likedPostIDs.formUnion(remote.posts.filter(\.liked).map(\.id))
            plannedPostIDs.formUnion(remote.posts.filter(\.planned).map(\.id))
            mergePosts(loadedPosts)
            return GroupedSearchResults(
                posts: loadedPosts,
                locations: remote.locations.map {
                    SearchLocation(
                        name: $0.name,
                        city: $0.city,
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        postCount: $0.postCount
                    )
                },
                users: remote.users.map { $0.localProfile() },
                tags: remote.tags.map { SearchTag(name: $0.name, usageCount: $0.usageCount) }
            )
        } catch {
            syncError = error.localizedDescription
            return GroupedSearchResults()
        }
    }

    func loadDefaultTags() async {
        do {
            defaultTags = try await api.fetchDefaultTags()
                .map { SearchTag(name: $0.name, usageCount: $0.usageCount) }
        } catch {
            if defaultTags.isEmpty {
                defaultTags = ["夜景", "街拍", "建筑", "人像", "风光", "城市", "自然", "手机可拍"]
                    .map { SearchTag(name: $0, usageCount: 0) }
            }
        }
    }

    func loadNotifications() async {
        guard isAuthenticated else { return }
        do {
            let response = try await api.fetchNotifications()
            notifications = response.items.map {
                var notification = $0.localNotification()
                if pendingReadNotificationIDs.contains(notification.id) {
                    notification.isRead = true
                }
                return notification
            }
            unreadNotificationCount = notifications.filter { !$0.isRead }.count
        } catch {
            syncError = error.localizedDescription
        }
    }

    func markNotificationRead(_ notification: AppNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }),
              !notifications[index].isRead else { return }
        pendingReadNotificationIDs.insert(notification.id)
        notifications[index].isRead = true
        unreadNotificationCount = max(unreadNotificationCount - 1, 0)
        Task {
            do {
                try await api.markNotificationRead(notification.id)
                pendingReadNotificationIDs.remove(notification.id)
            } catch {
                pendingReadNotificationIDs.remove(notification.id)
                await loadNotifications()
            }
        }
    }

    func markAllNotificationsRead() {
        let unreadIDs = Set(notifications.filter { !$0.isRead }.map(\.id))
        pendingReadNotificationIDs.formUnion(unreadIDs)
        notifications = notifications.map {
            var value = $0
            value.isRead = true
            return value
        }
        unreadNotificationCount = 0
        Task {
            do {
                try await api.markAllNotificationsRead()
                pendingReadNotificationIDs.subtract(unreadIDs)
            } catch {
                pendingReadNotificationIDs.subtract(unreadIDs)
                await loadNotifications()
            }
        }
    }

    private func mergePosts(_ loaded: [PhotoPost]) {
        for post in loaded {
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = post
            } else {
                posts.append(post)
            }
        }
        posts.sort { $0.createdAt > $1.createdAt }
    }

    private func cacheCurrentUser() {
        guard let data = try? JSONEncoder().encode(currentUser) else { return }
        UserDefaults.standard.set(data, forKey: cachedUserKey)
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
    }

    private func setFollowState(_ following: Bool, userID: String) {
        if following {
            followedUserIDs.insert(userID)
            guard !followedUsers.contains(where: { $0.id == userID }),
                  let post = posts.first(where: { $0.authorID == userID }) else { return }
            followedUsers.append(UserProfile(
                id: userID,
                name: post.authorName,
                avatar: post.authorAvatar,
                city: post.city.isEmpty ? post.location.city : post.city,
                bio: ""
            ))
        } else {
            followedUserIDs.remove(userID)
            followedUsers.removeAll { $0.id == userID }
        }
    }
}
