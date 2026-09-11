import Foundation
import UIKit

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据"
        case .server(let message): message
        case .authenticationRequired: "请先登录后再进行此操作"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://chenxi-edu.com/api")!
    private let session = URLSession.shared
    private let tokenKey = "lumen.auth.token"

    var hasSession: Bool { authToken != nil }

    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    func fetchPosts(
        feed: String = "recommended",
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusKm: Double? = nil,
        authorID: String? = nil,
        filters: Set<String> = []
    ) async throws -> [RemotePost] {
        var query = [URLQueryItem(name: "feed", value: feed), URLQueryItem(name: "limit", value: "50")]
        if let latitude { query.append(URLQueryItem(name: "latitude", value: String(latitude))) }
        if let longitude { query.append(URLQueryItem(name: "longitude", value: String(longitude))) }
        if let radiusKm { query.append(URLQueryItem(name: "radiusKm", value: String(radiusKm))) }
        if let authorID, !authorID.isEmpty {
            query.append(URLQueryItem(name: "authorId", value: authorID))
        }
        if !filters.isEmpty {
            query.append(URLQueryItem(name: "filters", value: filters.sorted().joined(separator: ",")))
        }
        let response: PostList = try await request(path: "posts", queryItems: query)
        return response.items
    }

    func search(_ query: String) async throws -> RemoteSearchResult {
        try await request(
            path: "discovery/search",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
    }

    func fetchDefaultTags() async throws -> [RemoteTag] {
        let response: RemoteTagList = try await request(path: "discovery/tags")
        return response.items
    }

    func fetchNotifications() async throws -> NotificationList {
        try await request(path: "notifications", authenticated: true)
    }

    func markNotificationRead(_ id: UUID) async throws {
        try await noContentRequest(
            path: "notifications/\(id.uuidString)/read",
            method: "PUT",
            authenticated: true
        )
    }

    func markAllNotificationsRead() async throws {
        try await noContentRequest(
            path: "notifications/read-all",
            method: "PUT",
            authenticated: true
        )
    }

    func toggleLike(postID: UUID) async throws -> LikeResponse {
        try await request(path: "posts/\(postID.uuidString)/like", method: "PUT", authenticated: true)
    }

    func togglePlan(postID: UUID) async throws -> PlanResponse {
        try await request(path: "posts/\(postID.uuidString)/plan", method: "PUT", authenticated: true)
    }

    func fetchFollowing() async throws -> [RemotePublicUser] {
        let response: FollowingList = try await request(path: "users/following", authenticated: true)
        return response.items
    }

    func toggleFollow(userID: String) async throws -> FollowResponse {
        try await request(path: "users/\(userID)/follow", method: "PUT", authenticated: true)
    }

    func addComment(postID: UUID, text: String) async throws -> RemoteComment {
        try await request(
            path: "posts/\(postID.uuidString)/comments",
            method: "POST",
            body: ["content": text],
            authenticated: true
        )
    }

    func fetchComments(postID: UUID) async throws -> [RemoteComment] {
        let response: CommentList = try await request(
            path: "posts/\(postID.uuidString)/comments"
        )
        return response.items
    }

    func fetchUserConsent() async throws -> ConsentDocument {
        try await request(path: "auth/consent")
    }

    func register(
        email: String,
        password: String,
        nickname: String,
        consentAccepted: Bool,
        consentVersion: String,
        verificationCode: String
    ) async throws -> AuthResponse {
        let response: AuthResponse = try await request(
            path: "auth/register",
            method: "POST",
            encodableBody: RegisterPayload(
                email: email,
                password: password,
                nickname: nickname,
                consentAccepted: consentAccepted,
                consentVersion: consentVersion,
                verificationCode: verificationCode
            ),
            authenticated: false
        )
        authToken = response.token
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await request(
            path: "auth/login",
            method: "POST",
            encodableBody: LoginPayload(email: email, password: password),
            authenticated: false
        )
        authToken = response.token
        return response
    }

    func sendRegistrationCode(email: String) async throws -> String {
        let response: AuthMessage = try await request(path: "auth/email-code", method: "POST",
            encodableBody: EmailPayload(email: email), authenticated: false)
        return response.message
    }

    func forgotPassword(email: String) async throws -> String {
        let response: AuthMessage = try await request(path: "auth/forgot-password", method: "POST",
            encodableBody: EmailPayload(email: email), authenticated: false)
        return response.message
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        let _: AuthMessage = try await request(path: "auth/me/password", method: "PUT",
            encodableBody: ChangePasswordPayload(oldPassword: oldPassword, newPassword: newPassword), authenticated: true)
        authToken = nil
    }

    func currentUser() async throws -> RemoteUser {
        try await request(path: "auth/me", authenticated: true)
    }

    func updateAvatar(imageData: Data) async throws -> RemoteUser {
        let avatarData = squareAvatarJPEG(imageData)
        let uploaded = try await upload(avatarData, variant: "avatar")
        return try await request(
            path: "auth/me/avatar",
            method: "PUT",
            encodableBody: AvatarPayload(
                objectKey: uploaded.objectKey,
                avatarUrl: uploaded.objectUrl
            ),
            authenticated: true
        )
    }

    func updateNickname(_ nickname: String) async throws -> RemoteUser {
        try await request(
            path: "auth/me/profile",
            method: "PUT",
            encodableBody: ProfilePayload(nickname: nickname),
            authenticated: true
        )
    }

    func updateBio(_ bio: String) async throws -> RemoteUser {
        try await request(
            path: "auth/me/bio",
            method: "PUT",
            encodableBody: BioPayload(bio: bio),
            authenticated: true
        )
    }

    func logout() {
        guard let token = authToken else { return }
        authToken = nil
        Task {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: request)
        }
    }

    func publish(_ post: PhotoPost, imageData: Data) async throws -> RemotePost {
        let images = try await uploadVariants(imageData)
        let payload = CreatePostPayload(post: post, images: images)
        return try await request(path: "posts", method: "POST", encodableBody: payload)
    }

    func update(_ post: PhotoPost, imageData: Data?) async throws -> RemotePost {
        let images: UploadedImages?
        if let imageData {
            images = try await uploadVariants(imageData)
        } else {
            images = nil
        }
        let payload = CreatePostPayload(post: post, images: images)
        return try await request(path: "posts/\(post.id.uuidString)", method: "PUT", encodableBody: payload)
    }

    func delete(postID: UUID) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("posts/\(postID.uuidString)"))
        request.httpMethod = "DELETE"
        try authorize(&request, required: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server("删除作品失败（\(http.statusCode)）")
        }
    }

    private func uploadVariants(_ imageData: Data) async throws -> UploadedImages {
        let original = try await upload(imageData, variant: "original")
        let displayData = resizedJPEG(imageData, longestEdge: 1280, quality: 0.82)
        let thumbnailData = resizedJPEG(imageData, longestEdge: 480, quality: 0.76)
        async let display = upload(displayData, variant: "display")
        async let thumbnail = upload(thumbnailData, variant: "thumbnail")
        return try await UploadedImages(original: original, display: display, thumbnail: thumbnail)
    }

    private func upload(_ imageData: Data, variant: String) async throws -> UploadSignature {
        let signature: UploadSignature = try await request(
            path: "uploads/presign",
            method: "POST",
            body: ["fileName": "photo.jpg", "mimeType": "image/jpeg", "variant": variant],
            authenticated: true
        )
        guard let uploadURL = URL(string: signature.uploadUrl) else { throw APIError.invalidResponse }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, uploadResponse) = try await session.upload(for: uploadRequest, from: imageData)
        guard let http = uploadResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("照片上传到 OSS 失败")
        }
        return signature
    }

    private func resizedJPEG(_ data: Data, longestEdge: CGFloat, quality: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        guard longest > longestEdge else { return image.jpegData(compressionQuality: quality) ?? data }
        let scale = longestEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: quality) ?? data
    }

    private func squareAvatarJPEG(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale = max(512 / image.size.width, 512 / image.size.height)
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: (512 - drawSize.width) / 2,
            y: (512 - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        let rendered = UIGraphicsImageRenderer(
            size: CGSize(width: 512, height: 512),
            format: format
        ).image { _ in
            image.draw(in: drawRect)
        }
        return rendered.jpegData(compressionQuality: 0.84) ?? data
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        authenticated: Bool = false,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(path: path, queryItems: queryItems))
        request.httpMethod = method
        try authorize(&request, required: authenticated)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await perform(request)
    }

    private func noContentRequest(
        path: String,
        method: String,
        authenticated: Bool
    ) async throws {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        try authorize(&request, required: authenticated)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server("服务器请求失败（\(http.statusCode)）")
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        let url = baseURL.appendingPathComponent(path)
        guard !queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        encodableBody: Body,
        authenticated: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        try authorize(&request, required: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(encodableBody)
        return try await perform(request)
    }

    private func authorize(_ request: inout URLRequest, required: Bool) throws {
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else if required {
            throw APIError.authenticationRequired
        }
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ServerError.self, from: data)
            if http.statusCode == 404, request.url?.path.contains("/auth/") == true {
                throw APIError.server("账号服务尚未部署，请升级后端服务后重试")
            }
            throw APIError.server(error?.error ?? "服务器请求失败（\(http.statusCode)）")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

struct PostList: Decodable {
    let items: [RemotePost]
}

struct RemotePost: Decodable {
    struct Author: Decodable {
        let id: String
        let name: String
        let avatarUrl: String?
        let city: String?
    }

    struct ImageInfo: Decodable {
        let originalUrl: String?
        let displayUrl: String?
        let thumbnailUrl: String?
    }

    struct Metadata: Decodable {
        let camera: String
        let lens: String
        let focalLengthMm: Double?
        let aperture: Double?
        let shutterSeconds: Double?
        let iso: Int?
        let capturedAt: String?
        let source: String
    }

    struct Location: Decodable {
        let name: String
        let city: String
        let detailedAddress: String?
        let privacy: String
        let latitude: Double?
        let longitude: Double?
        let advice: String
    }

    let id: UUID
    let kind: String
    let originalId: UUID?
    let author: Author
    let title: String
    let description: String
    let image: ImageInfo
    let tags: [String]
    let allowRemake: Bool
    let shootingNotes: String
    let editingNotes: String
    let reusedNotes: String
    let adjustedNotes: String
    let assignmentNotes: String
    let isRecommended: Bool
    let likeCount: Int
    let commentCount: Int
    let liked: Bool
    let planned: Bool
    let createdAt: String
    let metadata: Metadata
    let location: Location
    let distanceKm: Double?

    func localPost() -> PhotoPost {
        PhotoPost(
            id: id,
            kind: kind == "ASSIGNMENT" ? .assignment : .original,
            originalID: originalId,
            authorID: author.id,
            authorName: author.name,
            authorAvatar: author.avatarUrl ?? author.name.first.map(String.init) ?? "摄",
            city: author.city ?? location.city,
            title: title,
            summary: description,
            imageData: nil,
            imageURL: (image.thumbnailUrl ?? image.displayUrl ?? image.originalUrl).flatMap(URL.init(string:)),
            displayImageURL: (image.displayUrl ?? image.originalUrl).flatMap(URL.init(string:)),
            originalImageURL: image.originalUrl.flatMap(URL.init(string:)),
            createdAt: Self.parseDate(createdAt),
            likeCount: max(likeCount - (liked ? 1 : 0), 0),
            commentCount: commentCount,
            tags: tags,
            allowRemake: allowRemake,
            location: PhotoLocation(
                name: location.name,
                city: location.city,
                detailedAddress: location.detailedAddress ?? "",
                privacy: Self.privacy(location.privacy),
                latitude: location.latitude,
                longitude: location.longitude,
                advice: location.advice
            ),
            metadata: CaptureMetadata(
                camera: metadata.camera,
                lens: metadata.lens,
                focalLength: metadata.focalLengthMm.map { "\(Self.compact($0)) mm" } ?? "",
                aperture: metadata.aperture.map { "f/\(Self.compact($0))" } ?? "",
                shutterSpeed: Self.shutter(metadata.shutterSeconds),
                iso: metadata.iso.map(String.init) ?? "",
                capturedAt: metadata.capturedAt ?? "",
                latitude: location.latitude,
                longitude: location.longitude,
                source: metadata.source == "EXIF" ? .exif : (metadata.source == "USER_CONFIRMED" ? .confirmed : .manual)
            ),
            shootingNotes: shootingNotes,
            editingNotes: editingNotes,
            reused: reusedNotes,
            adjusted: adjustedNotes,
            assignmentNotes: assignmentNotes,
            isRecommended: isRecommended,
            distanceKm: distanceKm
        )
    }

    private static func parseDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? Date()
    }

    private static func privacy(_ value: String) -> LocationPrivacy {
        switch value {
        case "EXACT": .exact
        case "APPROXIMATE": .approximate
        default: .hidden
        }
    }

    private static func compact(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func shutter(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        if seconds < 1 { return "1/\(Int((1 / seconds).rounded())) s" }
        return "\(compact(seconds)) s"
    }
}

private struct CreatePostPayload: Encodable {
    struct Image: Encodable {
        let objectKey: String
        let originalUrl: String
        let displayObjectKey: String
        let displayUrl: String
        let thumbnailObjectKey: String
        let thumbnailUrl: String
    }
    struct Metadata: Encodable {
        let camera: String
        let lens: String
        let focalLengthMm: Double?
        let aperture: Double?
        let shutterSeconds: Double?
        let iso: Int?
        let capturedAt: String?
        let source: String
    }
    struct Location: Encodable {
        let name: String
        let city: String
        let detailedAddress: String
        let privacy: String
        let latitude: Double?
        let longitude: Double?
        let advice: String
    }

    let kind: String
    let originalId: UUID?
    let title: String
    let description: String
    let image: Image?
    let tags: [String]
    let allowRemake: Bool
    let shootingNotes: String
    let editingNotes: String
    let reusedNotes: String
    let adjustedNotes: String
    let assignmentNotes: String
    let metadata: Metadata
    let location: Location

    init(post: PhotoPost, images: UploadedImages?) {
        kind = post.kind == .assignment ? "ASSIGNMENT" : "ORIGINAL"
        originalId = post.originalID
        title = post.title
        description = post.summary
        if let images {
            image = Image(
                objectKey: images.original.objectKey,
                originalUrl: images.original.objectUrl,
                displayObjectKey: images.display.objectKey,
                displayUrl: images.display.objectUrl,
                thumbnailObjectKey: images.thumbnail.objectKey,
                thumbnailUrl: images.thumbnail.objectUrl
            )
        } else {
            image = nil
        }
        allowRemake = post.allowRemake
        tags = post.tags
        shootingNotes = post.shootingNotes
        editingNotes = post.editingNotes
        reusedNotes = post.reused
        adjustedNotes = post.adjusted
        assignmentNotes = post.assignmentNotes
        metadata = Metadata(
            camera: post.metadata.camera,
            lens: post.metadata.lens,
            focalLengthMm: Self.number(post.metadata.focalLength),
            aperture: Self.number(post.metadata.aperture),
            shutterSeconds: Self.shutterSeconds(post.metadata.shutterSpeed),
            iso: Int(post.metadata.iso.filter(\.isNumber)),
            capturedAt: post.metadata.capturedAt.isEmpty ? nil : post.metadata.capturedAt,
            source: post.metadata.source == .exif ? "EXIF" : (post.metadata.source == .confirmed ? "USER_CONFIRMED" : "MANUAL")
        )
        location = Location(
            name: post.location.name,
            city: post.location.city,
            detailedAddress: post.location.detailedAddress,
            privacy: post.location.privacy == .exact ? "EXACT" : (post.location.privacy == .approximate ? "APPROXIMATE" : "PRIVATE"),
            latitude: post.location.latitude,
            longitude: post.location.longitude,
            advice: post.location.advice
        )
    }

    private static func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: "f/", with: "").replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces))
    }

    private static func shutterSeconds(_ value: String) -> Double? {
        let cleaned = value.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
        let parts = cleaned.split(separator: "/")
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            return numerator / denominator
        }
        return Double(cleaned)
    }
}

private struct UploadedImages {
    let original: UploadSignature
    let display: UploadSignature
    let thumbnail: UploadSignature
}

struct RemoteUser: Decodable {
    let id: String
    let username: String?
    let email: String?
    let phone: String?
    let nickname: String
    let avatarUrl: String?
    let city: String
    let bio: String

    func localUser() -> CurrentUser {
        CurrentUser(
            id: id,
            email: email ?? username ?? phone ?? "",
            name: nickname,
            avatar: avatarUrl ?? nickname.first.map(String.init) ?? "摄",
            city: city,
            bio: bio
        )
    }
}

struct AuthResponse: Decodable {
    let token: String
    let expiresAt: String
    let user: RemoteUser
    let newlyRegistered: Bool?
}

struct ConsentDocument: Decodable {
    let type: String
    let version: String
    let title: String
    let effectiveDate: String
    let content: String
    let documentSha256: String
}

struct FollowingList: Decodable {
    let items: [RemotePublicUser]
}

struct RemotePublicUser: Decodable {
    let id: String
    let nickname: String
    let avatarUrl: String?
    let city: String
    let bio: String

    func localProfile() -> UserProfile {
        UserProfile(
            id: id,
            name: nickname,
            avatar: avatarUrl ?? nickname.first.map(String.init) ?? "摄",
            city: city,
            bio: bio
        )
    }
}

struct RemoteTag: Decodable {
    let name: String
    let usageCount: Int
}

private struct RemoteTagList: Decodable {
    let items: [RemoteTag]
}

struct RemoteSearchLocation: Decodable {
    let name: String
    let city: String
    let latitude: Double?
    let longitude: Double?
    let postCount: Int
}

struct RemoteSearchResult: Decodable {
    let posts: [RemotePost]
    let locations: [RemoteSearchLocation]
    let users: [RemotePublicUser]
    let tags: [RemoteTag]
}

struct NotificationList: Decodable {
    let items: [RemoteNotification]
    let unreadCount: Int
}

struct RemoteNotification: Decodable {
    struct Actor: Decodable {
        let id: String
        let name: String
        let avatarUrl: String?
    }

    let id: UUID
    let type: String
    let title: String
    let body: String
    let actor: Actor
    let targetPostId: UUID?
    let sourcePostId: UUID?
    let read: Bool
    let createdAt: String

    func localNotification() -> AppNotification {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AppNotification(
            id: id,
            type: type,
            title: title,
            body: body,
            actorID: actor.id,
            actorName: actor.name,
            actorAvatar: actor.avatarUrl ?? actor.name.first.map(String.init) ?? "摄",
            targetPostID: targetPostId,
            sourcePostID: sourcePostId,
            isRead: read,
            createdAt: formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) ?? Date()
        )
    }
}

struct FollowResponse: Decodable {
    let following: Bool
}

private struct RegisterPayload: Encodable {
    let email: String
    let password: String
    let nickname: String
    let consentAccepted: Bool
    let consentVersion: String
    let verificationCode: String
}

private struct LoginPayload: Encodable {
    let email: String
    let password: String
}

private struct EmailPayload: Encodable { let email: String }
private struct AuthMessage: Decodable { let message: String }
private struct ChangePasswordPayload: Encodable {
    let oldPassword: String
    let newPassword: String
}

private struct AvatarPayload: Encodable {
    let objectKey: String
    let avatarUrl: String
}

private struct ProfilePayload: Encodable {
    let nickname: String
}

private struct BioPayload: Encodable {
    let bio: String
}

private struct EmptyResponse: Decodable {}

struct UploadSignature: Decodable {
    let objectKey: String
    let uploadUrl: String
    let objectUrl: String
}

struct LikeResponse: Decodable {
    let liked: Bool
    let likeCount: Int
}

struct PlanResponse: Decodable {
    let planned: Bool
}

struct RemoteComment: Decodable {
    struct Author: Decodable {
        let id: String
        let name: String
        let avatarUrl: String?
    }
    let id: UUID
    let content: String
    let createdAt: String
    let author: Author

    func localComment(postID: UUID) -> PhotoComment {
        PhotoComment(
            id: id,
            postID: postID,
            authorID: author.id,
            authorName: author.name,
            authorAvatar: author.avatarUrl ?? author.name.first.map(String.init) ?? "摄",
            text: content,
            createdAt: Self.parseDate(createdAt)
        )
    }

    private static func parseDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? Date()
    }
}

private struct CommentList: Decodable {
    let items: [RemoteComment]
}

private struct ServerError: Decodable {
    let error: String
}
