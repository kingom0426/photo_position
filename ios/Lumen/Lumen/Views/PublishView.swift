import SwiftUI
import PhotosUI
import UIKit

struct PublishView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let original: PhotoPost?

    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var metadata = CaptureMetadata()
    @State private var isLoadingPhoto = false
    @State private var title = ""
    @State private var summary = ""
    @State private var shootingNotes = ""
    @State private var editingNotes = ""
    @State private var reused = ""
    @State private var adjusted = ""
    @State private var assignmentNotes = ""
    @State private var locationName: String
    @State private var privacy: LocationPrivacy
    @State private var allowRemake = true
    @State private var showingPublishedAlert = false
    @State private var errorMessage: String?
    @State private var isPublishing = false

    init(original: PhotoPost? = nil) {
        self.original = original
        _locationName = State(initialValue: original?.location.name ?? "")
        _privacy = State(initialValue: original?.location.privacy ?? .exact)
    }

    private var isAssignment: Bool { original != nil }
    private var canPublish: Bool { imageData != nil && (isAssignment || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        Form {
            if let original {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REMAKE OF").font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
                            Text(original.title).font(.headline)
                        }
                        Spacer()
                        Text("已关联").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                }
            }

            Section {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    if let imageData, let image = UIImage(data: imageData) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 330).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            Label("更换照片", systemImage: "photo").font(.caption.weight(.semibold)).padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if isLoadingPhoto { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.largeTitle) }
                            Text(isAssignment ? "上传你的拍摄成果" : "选择一张满意的照片").font(.headline)
                            Text("系统会自动读取可用的 EXIF 拍摄参数").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 230)
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: selectedItem) { _, item in Task { await loadPhoto(item) } }
            }

            if isAssignment {
                Section("复刻说明") {
                    TextField("我沿用了：机位、时间、参数…", text: $reused, axis: .vertical)
                    TextField("我做了调整：焦段、构图…", text: $adjusted, axis: .vertical)
                    TextField("拍摄心得", text: $assignmentNotes, axis: .vertical).lineLimit(3...6)
                }
            } else {
                Section("作品内容") {
                    TextField("作品标题", text: $title)
                    TextField("作品说明", text: $summary, axis: .vertical).lineLimit(3...6)
                    TextField("拍摄思路", text: $shootingNotes, axis: .vertical).lineLimit(3...6)
                    TextField("后期说明（可选）", text: $editingNotes, axis: .vertical).lineLimit(2...5)
                }
            }

            Section {
                if metadata.recognizedCount > 0 {
                    Label("已从照片识别 \(metadata.recognizedCount) 项参数，请确认是否准确", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else {
                    Label("未识别到 EXIF，可手动补充", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                TextField("相机", text: $metadata.camera)
                TextField("镜头", text: $metadata.lens)
                HStack { TextField("焦段", text: $metadata.focalLength); TextField("光圈", text: $metadata.aperture) }
                HStack { TextField("快门", text: $metadata.shutterSpeed); TextField("ISO", text: $metadata.iso) }
            } header: {
                Text("拍摄参数")
            } footer: {
                Text("参数来自照片 EXIF 或手动填写，发布时视为由你确认。")
            }

            Section("地点与权限") {
                TextField("拍摄地点", text: $locationName)
                Picker("地点公开范围", selection: $privacy) {
                    ForEach(LocationPrivacy.allCases) { option in Text(option.title).tag(option) }
                }
                if !isAssignment { Toggle("允许其他用户复刻并提交作业", isOn: $allowRemake) }
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    if isPublishing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(isAssignment ? "发布作业" : "发布作品", systemImage: isAssignment ? "camera.fill" : "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canPublish || isPublishing)
            }
        }
        .navigationTitle(isAssignment ? "提交作业" : "发布作品")
        .navigationBarTitleDisplayMode(.inline)
        .alert("发布成功", isPresented: $showingPublishedAlert) {
            Button("完成") {
                if isAssignment { dismiss() } else { resetForm() }
            }
        } message: { Text(isAssignment ? "作业已关联到原作。" : "作品已保存到云端。") }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let originalData = try await item.loadTransferable(type: Data.self) else { throw PhotoLoadError.emptyData }
            metadata = EXIFReader.read(from: originalData)
            imageData = compressedJPEG(from: originalData)
            if metadata.source == .exif { metadata.source = .confirmed }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compressedJPEG(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }

    private func publish() async {
        guard let imageData else { return }
        isPublishing = true
        defer { isPublishing = false }
        let user = store.currentUser
        let location = PhotoLocation(
            name: locationName.isEmpty ? "地点未公开" : locationName,
            city: original?.location.city ?? user.city,
            privacy: privacy,
            latitude: metadata.latitude ?? original?.location.latitude,
            longitude: metadata.longitude ?? original?.location.longitude,
            advice: original?.location.advice ?? ""
        )
        let post = PhotoPost(
            id: UUID(), kind: isAssignment ? .assignment : .original, originalID: original?.id,
            authorID: user.id, authorName: user.name, authorAvatar: user.avatar, city: user.city,
            title: isAssignment ? "\(original?.title ?? "原作") · 复刻作业" : title,
            summary: isAssignment ? (assignmentNotes.isEmpty ? "完成了一次复刻练习。" : assignmentNotes) : (summary.isEmpty ? "分享一张新的摄影作品。" : summary),
            imageData: imageData, seedArtwork: nil, createdAt: Date(), likeCount: 0, tags: [], allowRemake: isAssignment ? false : allowRemake,
            location: location, metadata: metadata, shootingNotes: shootingNotes, editingNotes: editingNotes,
            reused: reused, adjusted: adjusted, assignmentNotes: assignmentNotes, isRecommended: false
        )
        do {
            try await store.publishToServer(post, imageData: imageData)
            showingPublishedAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetForm() {
        selectedItem = nil; imageData = nil; metadata = CaptureMetadata(); title = ""; summary = ""; shootingNotes = ""; editingNotes = ""; locationName = ""
    }
}

private enum PhotoLoadError: LocalizedError {
    case emptyData
    var errorDescription: String? { "无法读取所选照片" }
}
