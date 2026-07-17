import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var posts: [PhotoPost]
    @Published private(set) var comments: [PhotoComment]
    @Published private(set) var likedPostIDs: Set<UUID>
    @Published private(set) var plannedPostIDs: Set<UUID>
    @Published private(set) var followedUserIDs: Set<String>
    @Published var currentUser: CurrentUser
    @Published private(set) var syncError: String?

    private let saveURL: URL
    private let api = APIClient.shared

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        saveURL = directory.appendingPathComponent("state.json")

        if let data = try? Data(contentsOf: saveURL),
           let saved = try? JSONDecoder().decode(PersistedState.self, from: data) {
            posts = saved.posts
            comments = saved.comments
            likedPostIDs = saved.likedPostIDs
            plannedPostIDs = saved.plannedPostIDs
            followedUserIDs = saved.followedUserIDs
            currentUser = saved.currentUser
        } else {
            let seed = SeedData.makeState()
            posts = seed.posts
            comments = seed.comments
            likedPostIDs = seed.likedPostIDs
            plannedPostIDs = seed.plannedPostIDs
            followedUserIDs = seed.followedUserIDs
            currentUser = seed.currentUser
        }
    }

    var originals: [PhotoPost] { posts.filter { $0.kind == .original }.sorted { $0.createdAt > $1.createdAt } }
    var currentUserPosts: [PhotoPost] { posts.filter { $0.authorID == currentUser.id }.sorted { $0.createdAt > $1.createdAt } }

    func post(id: UUID) -> PhotoPost? { posts.first { $0.id == id } }
    func assignments(for originalID: UUID) -> [PhotoPost] { posts.filter { $0.kind == .assignment && $0.originalID == originalID } }
    func comments(for postID: UUID) -> [PhotoComment] { comments.filter { $0.postID == postID }.sorted { $0.createdAt < $1.createdAt } }
    func isLiked(_ id: UUID) -> Bool { likedPostIDs.contains(id) }
    func isPlanned(_ id: UUID) -> Bool { plannedPostIDs.contains(id) }
    func isFollowing(_ id: String) -> Bool { followedUserIDs.contains(id) }

    func toggleLike(_ id: UUID) {
        if !likedPostIDs.insert(id).inserted { likedPostIDs.remove(id) }
        persist()
        Task {
            do {
                let result = try await api.toggleLike(postID: id)
                if result.liked { likedPostIDs.insert(id) } else { likedPostIDs.remove(id) }
                if let index = posts.firstIndex(where: { $0.id == id }) {
                    posts[index].likeCount = max(result.likeCount - (result.liked ? 1 : 0), 0)
                }
                persist()
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func togglePlan(_ id: UUID) {
        if !plannedPostIDs.insert(id).inserted { plannedPostIDs.remove(id) }
        persist()
        Task {
            do {
                let result = try await api.togglePlan(postID: id)
                if result.planned { plannedPostIDs.insert(id) } else { plannedPostIDs.remove(id) }
                persist()
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func toggleFollow(_ id: String) {
        if !followedUserIDs.insert(id).inserted { followedUserIDs.remove(id) }
        persist()
    }

    func addComment(postID: UUID, text: String) {
        comments.append(PhotoComment(id: UUID(), postID: postID, authorName: currentUser.name, authorAvatar: currentUser.avatar, text: text, createdAt: Date()))
        persist()
        Task {
            do {
                _ = try await api.addComment(postID: postID, text: text)
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func publish(_ post: PhotoPost) {
        posts.insert(post, at: 0)
        if let originalID = post.originalID { plannedPostIDs.insert(originalID) }
        persist()
    }

    func publishToServer(_ post: PhotoPost, imageData: Data) async throws {
        let remote = try await api.publish(post, imageData: imageData)
        let published = remote.localPost()
        posts.insert(published, at: 0)
        if remote.liked { likedPostIDs.insert(published.id) }
        if remote.planned { plannedPostIDs.insert(published.id) }
        persist()
    }

    func sync() async {
        do {
            let remote = try await api.fetchPosts()
            guard !remote.isEmpty else { return }
            posts = remote.map { $0.localPost() }
            likedPostIDs = Set(remote.filter(\.liked).map(\.id))
            plannedPostIDs = Set(remote.filter(\.planned).map(\.id))
            syncError = nil
            persist()
        } catch {
            syncError = error.localizedDescription
        }
    }

    func reset() {
        let seed = SeedData.makeState()
        posts = seed.posts
        comments = seed.comments
        likedPostIDs = seed.likedPostIDs
        plannedPostIDs = seed.plannedPostIDs
        followedUserIDs = seed.followedUserIDs
        currentUser = seed.currentUser
        persist()
    }

    private func persist() {
        let state = PersistedState(posts: posts, comments: comments, likedPostIDs: likedPostIDs, plannedPostIDs: plannedPostIDs, followedUserIDs: followedUserIDs, currentUser: currentUser)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}
