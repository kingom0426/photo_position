import Foundation

enum SeedData {
    static let bundID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let lakeID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let streetID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let assignmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    static func makeState() -> PersistedState {
        let calendar = Calendar.current
        let now = Date()
        let bund = PhotoPost(
            id: bundID, kind: .original, originalID: nil, authorID: "u2", authorName: "林屿", authorAvatar: "林", city: "上海",
            title: "月升陆家嘴", summary: "提前查好月升方位，日落后约 25 分钟是天空和建筑亮度最接近的时刻。建议带脚架，避开周末人流。",
            imageData: nil, seedArtwork: .bund, createdAt: calendar.date(byAdding: .day, value: -1, to: now)!, likeCount: 286,
            tags: ["城市风光", "蓝调时刻"], allowRemake: true,
            location: PhotoLocation(name: "外滩观景平台", city: "上海", privacy: .exact, latitude: 31.239, longitude: 121.490, advice: "建议 18:40–19:20"),
            metadata: CaptureMetadata(camera: "Sony A7 IV", lens: "FE 24–70mm F2.8 GM II", focalLength: "70 mm", aperture: "f/8", shutterSpeed: "1/2 s", iso: "ISO 100", capturedAt: "2026-07-11 18:42", source: .confirmed),
            shootingNotes: "使用长焦压缩月亮与建筑的距离。先确定月升方位，再微调机位，让月亮从楼群右侧进入画面。",
            editingNotes: "降低高光，轻微增加阴影中的冷色，保留建筑灯光的暖色。", reused: "", adjusted: "", assignmentNotes: "", isRecommended: false
        )
        let lake = PhotoPost(
            id: lakeID, kind: .original, originalID: nil, authorID: "u3", authorName: "沈禾", authorAvatar: "沈", city: "杭州",
            title: "北山街晨雾", summary: "雨后清晨的湖面容易出现薄雾，使用中长焦保留层次。",
            imageData: nil, seedArtwork: .lake, createdAt: calendar.date(byAdding: .day, value: -3, to: now)!, likeCount: 194,
            tags: ["自然", "晨雾"], allowRemake: true,
            location: PhotoLocation(name: "北山街临湖步道", city: "杭州", privacy: .approximate, latitude: 30.255, longitude: 120.150, advice: "建议日出前 30 分钟"),
            metadata: CaptureMetadata(camera: "Fujifilm X-T5", lens: "XF 50–140mm", focalLength: "92 mm", aperture: "f/5.6", shutterSpeed: "1/160 s", iso: "ISO 400", capturedAt: "2026-07-10 05:26", source: .confirmed),
            shootingNotes: "沿湖寻找前景比较干净的位置，曝光以雾气高光不过曝为准。", editingNotes: "降低对比度，让雾气层次保持柔和。",
            reused: "", adjusted: "", assignmentNotes: "", isRecommended: false
        )
        let street = PhotoPost(
            id: streetID, kind: .original, originalID: nil, authorID: "u4", authorName: "周野", authorAvatar: "周", city: "上海",
            title: "雨夜武康路", summary: "雨停后的十五分钟，路面反光最完整。低机位可以拉长灯光倒影。",
            imageData: nil, seedArtwork: .street, createdAt: calendar.date(byAdding: .day, value: -4, to: now)!, likeCount: 158,
            tags: ["街拍", "雨夜"], allowRemake: true,
            location: PhotoLocation(name: "武康路街区", city: "上海", privacy: .approximate, latitude: 31.205, longitude: 121.438, advice: "建议雨停后 15 分钟"),
            metadata: CaptureMetadata(camera: "Leica Q3", lens: "Summilux 28mm", focalLength: "28 mm", aperture: "f/2", shutterSpeed: "1/125 s", iso: "ISO 1600", capturedAt: "2026-07-09 21:15", source: .confirmed),
            shootingNotes: "注意来车，站在人行道内取景。利用招牌和车灯制造冷暖对比。", editingNotes: "压低整体曝光，局部提高路面倒影。",
            reused: "", adjusted: "", assignmentNotes: "", isRecommended: false
        )
        let assignment = PhotoPost(
            id: assignmentID, kind: .assignment, originalID: bundID, authorID: "u4", authorName: "周野", authorAvatar: "周", city: "上海",
            title: "月升陆家嘴 · 复刻作业", summary: "沿用原作机位和蓝调时间，把焦段改成 85mm，让月亮与建筑的比例更突出。",
            imageData: nil, seedArtwork: .bund, createdAt: now, likeCount: 52, tags: [], allowRemake: false,
            location: bund.location,
            metadata: CaptureMetadata(camera: "Canon EOS R6 II", lens: "RF 85mm F2", focalLength: "85 mm", aperture: "f/8", shutterSpeed: "1/4 s", iso: "ISO 160", capturedAt: "2026-07-12 18:48", source: .confirmed),
            shootingNotes: "", editingNotes: "", reused: "原作机位、拍摄时间和光圈", adjusted: "焦段改为 85mm，快门提高到 1/4 秒",
            assignmentNotes: "当天风比较大，提高快门后建筑轮廓更稳定。", isRecommended: true
        )
        let comments = [
            PhotoComment(id: UUID(), postID: bundID, authorName: "阿澈", authorAvatar: "澈", text: "参数和时间都很清楚，已经加入周末计划。", createdAt: now),
            PhotoComment(id: UUID(), postID: assignmentID, authorName: "林屿", authorAvatar: "林", text: "构图更集中，月亮位置很好。下次可以再提前一点到。", createdAt: now)
        ]
        return PersistedState(posts: [bund, lake, street, assignment], comments: comments, likedPostIDs: [], plannedPostIDs: [bundID, lakeID], followedUserIDs: [], currentUser: CurrentUser())
    }
}
