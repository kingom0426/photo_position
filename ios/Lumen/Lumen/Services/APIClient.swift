import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据"
        case .server(let message): message
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://chenxi-edu.com/api")!
    private let session = URLSession.shared
    private let userID = "me"

    func fetchPosts() async throws -> [RemotePost] {
        let response: PostList = try await request(path: "posts")
        return response.items
    }

    func toggleLike(postID: UUID) async throws -> LikeResponse {
        try await request(path: "posts/\(postID.uuidString)/like", method: "PUT")
    }

    func togglePlan(postID: UUID) async throws -> PlanResponse {
        try await request(path: "posts/\(postID.uuidString)/plan", method: "PUT")
    }

    func addComment(postID: UUID, text: String) async throws -> RemoteComment {
        try await request(
            path: "posts/\(postID.uuidString)/comments",
            method: "POST",
            body: ["content": text]
        )
    }

    func publish(_ post: PhotoPost, imageData: Data) async throws -> RemotePost {
        let signature: UploadSignature = try await request(
            path: "uploads/presign",
            method: "POST",
            body: ["fileName": "photo.jpg", "mimeType": "image/jpeg", "variant": "original"]
        )
        guard let uploadURL = URL(string: signature.uploadUrl) else { throw APIError.invalidResponse }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, uploadResponse) = try await session.upload(for: uploadRequest, from: imageData)
        guard let http = uploadResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("照片上传到 OSS 失败")
        }

        let payload = CreatePostPayload(post: post, objectKey: signature.objectKey, objectURL: signature.objectUrl)
        return try await request(path: "posts", method: "POST", encodableBody: payload)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(userID, forHTTPHeaderField: "x-user-id")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await perform(request)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        encodableBody: Body
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(userID, forHTTPHeaderField: "x-user-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(encodableBody)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ServerError.self, from: data)
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
        let displayUrl: String?
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
    let allowRemake: Bool
    let shootingNotes: String
    let editingNotes: String
    let reusedNotes: String
    let adjustedNotes: String
    let assignmentNotes: String
    let isRecommended: Bool
    let likeCount: Int
    let liked: Bool
    let planned: Bool
    let createdAt: String
    let metadata: Metadata
    let location: Location

    func localPost() -> PhotoPost {
        PhotoPost(
            id: id,
            kind: kind == "ASSIGNMENT" ? .assignment : .original,
            originalID: originalId,
            authorID: author.id,
            authorName: author.name,
            authorAvatar: author.name.first.map(String.init) ?? "摄",
            city: author.city ?? location.city,
            title: title,
            summary: description,
            imageData: nil,
            imageURL: image.displayUrl.flatMap(URL.init(string:)),
            seedArtwork: nil,
            createdAt: Self.parseDate(createdAt),
            likeCount: max(likeCount - (liked ? 1 : 0), 0),
            tags: [],
            allowRemake: allowRemake,
            location: PhotoLocation(
                name: location.name,
                city: location.city,
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
            isRecommended: isRecommended
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
        let displayUrl: String
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
        let privacy: String
        let latitude: Double?
        let longitude: Double?
        let advice: String
    }

    let kind: String
    let originalId: UUID?
    let title: String
    let description: String
    let image: Image
    let allowRemake: Bool
    let shootingNotes: String
    let editingNotes: String
    let reusedNotes: String
    let adjustedNotes: String
    let assignmentNotes: String
    let metadata: Metadata
    let location: Location

    init(post: PhotoPost, objectKey: String, objectURL: String) {
        kind = post.kind == .assignment ? "ASSIGNMENT" : "ORIGINAL"
        originalId = post.originalID
        title = post.title
        description = post.summary
        image = Image(objectKey: objectKey, originalUrl: objectURL, displayUrl: objectURL, thumbnailUrl: objectURL)
        allowRemake = post.allowRemake
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
        let name: String
        let avatarUrl: String?
    }
    let id: UUID
    let content: String
    let author: Author
}

private struct ServerError: Decodable {
    let error: String
}
