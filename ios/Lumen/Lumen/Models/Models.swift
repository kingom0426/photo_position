import Foundation
import CoreLocation

enum PostKind: String, Codable {
    case original
    case assignment
}

enum LocationPrivacy: String, Codable, CaseIterable, Identifiable {
    case exact
    case approximate
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: "精确地点"
        case .approximate: "模糊区域"
        case .hidden: "不公开"
        }
    }
}

struct CaptureMetadata: Codable, Equatable {
    var camera = ""
    var lens = ""
    var focalLength = ""
    var aperture = ""
    var shutterSpeed = ""
    var iso = ""
    var capturedAt = ""
    var latitude: Double?
    var longitude: Double?
    var source: MetadataSource = .manual

    enum MetadataSource: String, Codable {
        case exif
        case confirmed
        case manual
    }

    var recognizedCount: Int {
        [camera, lens, focalLength, aperture, shutterSpeed, iso].filter { !$0.isEmpty }.count
    }
}

struct PhotoLocation: Codable, Equatable {
    var name: String
    var city: String
    var detailedAddress: String = ""
    var privacy: LocationPrivacy
    var latitude: Double?
    var longitude: Double?
    var advice: String

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayAddress: String {
        let positioning = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let manual = detailedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPositioning = positioning.contains("未公开") ? "" : positioning
        let validManual = manual.contains("未公开") ? "" : manual
        if validPositioning.isEmpty { return validManual }
        if validManual.isEmpty || validPositioning.contains(validManual) { return validPositioning }
        return "\(validPositioning) \(validManual)"
    }
}

struct PhotoPost: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: PostKind
    var originalID: UUID?
    var authorID: String
    var authorName: String
    var authorAvatar: String
    var city: String
    var title: String
    var summary: String
    var imageData: Data?
    var imageURL: URL? = nil
    var displayImageURL: URL? = nil
    var originalImageURL: URL? = nil
    var createdAt: Date
    var likeCount: Int
    var commentCount: Int
    var tags: [String]
    var allowRemake: Bool
    var location: PhotoLocation
    var metadata: CaptureMetadata
    var shootingNotes: String
    var editingNotes: String
    var reused: String
    var adjusted: String
    var assignmentNotes: String
    var isRecommended: Bool
    var distanceKm: Double? = nil
}

struct PhotoComment: Identifiable, Codable, Equatable {
    var id: UUID
    var postID: UUID
    var authorID: String
    var authorName: String
    var authorAvatar: String
    var text: String
    var createdAt: Date
}

struct CurrentUser: Codable {
    var id = ""
    var email = ""
    var name = "未登录"
    var avatar = "访"
    var city = ""
    var bio = ""

    static let guest = CurrentUser()
}

struct UserProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var avatar: String
    var city: String
    var bio: String
}

struct AppNotification: Identifiable, Codable, Equatable {
    var id: UUID
    var type: String
    var title: String
    var body: String
    var actorID: String
    var actorName: String
    var actorAvatar: String
    var targetPostID: UUID?
    var sourcePostID: UUID?
    var isRead: Bool
    var createdAt: Date
}

struct SearchLocation: Identifiable, Equatable {
    var id: String { "\(city)-\(name)" }
    var name: String
    var city: String
    var latitude: Double?
    var longitude: Double?
    var postCount: Int
}

struct SearchTag: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var usageCount: Int
}

struct GroupedSearchResults {
    var posts: [PhotoPost] = []
    var locations: [SearchLocation] = []
    var users: [UserProfile] = []
    var tags: [SearchTag] = []

    var isEmpty: Bool {
        posts.isEmpty && locations.isEmpty && users.isEmpty && tags.isEmpty
    }
}

struct PersistedState: Codable {
    var posts: [PhotoPost]
    var comments: [PhotoComment]
    var likedPostIDs: Set<UUID>
    var plannedPostIDs: Set<UUID>
    var followedUserIDs: Set<String>
}
