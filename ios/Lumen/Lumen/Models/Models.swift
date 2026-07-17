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

enum SeedArtwork: String, Codable {
    case bund
    case lake
    case street
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
    var privacy: LocationPrivacy
    var latitude: Double?
    var longitude: Double?
    var advice: String

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
    var seedArtwork: SeedArtwork?
    var createdAt: Date
    var likeCount: Int
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
}

struct PhotoComment: Identifiable, Codable, Equatable {
    var id: UUID
    var postID: UUID
    var authorName: String
    var authorAvatar: String
    var text: String
    var createdAt: Date
}

struct CurrentUser: Codable {
    var id = "me"
    var name = "小野同学"
    var avatar = "野"
    var city = "上海"
    var bio = "用镜头记录城市光线"
}

struct PersistedState: Codable {
    var posts: [PhotoPost]
    var comments: [PhotoComment]
    var likedPostIDs: Set<UUID>
    var plannedPostIDs: Set<UUID>
    var followedUserIDs: Set<String>
    var currentUser: CurrentUser
}
