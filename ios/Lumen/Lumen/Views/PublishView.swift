import SwiftUI
import PhotosUI
import UIKit
import CoreLocation

struct PublishView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss

    let original: PhotoPost?
    let editingPost: PhotoPost?

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
    @State private var selectedTags: [String]
    @State private var customTag = ""
    @State private var locationName: String
    @State private var locationCity: String
    @State private var detailedAddress: String
    @State private var showingPublishedAlert = false
    @State private var publishedPostID: UUID?
    @State private var errorMessage: String?
    @State private var isPublishing = false
    @State private var locationPrivacy: LocationPrivacy
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var showingLocationPicker = false
    @State private var hasAttemptedPublish = false
    @State private var showingRequiredFieldsAlert = false
    @State private var requiredFieldsMessage = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, summary, shootingNotes, editingNotes, reused, adjusted, assignmentNotes
        case camera, lens, focalLength, aperture, shutter, iso, location, detailedAddress
    }

    init(original: PhotoPost? = nil, editing: PhotoPost? = nil) {
        self.original = original
        editingPost = editing
        _metadata = State(initialValue: editing?.metadata ?? CaptureMetadata())
        _title = State(initialValue: editing?.title ?? "")
        _summary = State(initialValue: editing?.summary ?? "")
        _shootingNotes = State(initialValue: editing?.shootingNotes ?? "")
        _editingNotes = State(initialValue: editing?.editingNotes ?? "")
        _reused = State(initialValue: editing?.reused ?? "")
        _adjusted = State(initialValue: editing?.adjusted ?? "")
        _assignmentNotes = State(initialValue: editing?.assignmentNotes ?? "")
        _selectedTags = State(initialValue: editing?.tags ?? [])
        _locationName = State(initialValue: editing?.location.name ?? "")
        _locationCity = State(initialValue: editing?.location.city ?? "")
        // Legacy approximate locations must never become exact implicitly.
        _locationPrivacy = State(initialValue: editing == nil || editing?.location.privacy == .exact ? .exact : .hidden)
        _locationLatitude = State(initialValue: editing?.location.latitude)
        _locationLongitude = State(initialValue: editing?.location.longitude)
        _detailedAddress = State(initialValue: editing?.location.detailedAddress ?? "")
    }

    private var isAssignment: Bool { original != nil }
    private var isEditing: Bool { editingPost != nil }
    private var hasPhoto: Bool { imageData != nil || editingPost != nil }
    private var missingFields: [PublishValidation.RequiredField] {
        PublishValidation.missingFields(hasPhoto: hasPhoto, isAssignment: isAssignment, title: title)
    }

    var body: some View {
        ScrollViewReader { proxy in
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
                    if hasPhoto {
                        GeometryReader { geometry in
                            ZStack {
                                Color.black
                                if let imageData, let image = UIImage(data: imageData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                } else if let editingPost {
                                    PostPhotoView(post: editingPost)
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .frame(width: 16, height: 16)
                                    Text("更换照片")
                                        .lineLimit(1)
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .fixedSize(horizontal: true, vertical: false)
                                .background(.regularMaterial, in: Capsule())
                                .padding(12)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .frame(height: 330)
                    } else {
                        VStack(spacing: 12) {
                            if isLoadingPhoto { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.largeTitle) }
                            Text(isAssignment ? "上传你的拍摄成果" : "选择一张满意的照片").font(.headline)
                            Text("系统会自动读取可用的 EXIF 拍摄参数").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 230)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto || isPublishing)
                .onChange(of: selectedItem) { _, item in Task { await loadPhoto(item) } }
                if hasAttemptedPublish && missingFields.contains(.photo) {
                    Label("请选择一张照片", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("照片（必选）")
            }
            .id(PublishValidation.RequiredField.photo)

            if isAssignment {
                Section("复刻说明") {
                    TextField("我沿用了：机位、时间、参数…", text: $reused, axis: .vertical).focused($focusedField, equals: .reused)
                    TextField("我做了调整：焦段、构图…", text: $adjusted, axis: .vertical).focused($focusedField, equals: .adjusted)
                    TextField("拍摄心得", text: $assignmentNotes, axis: .vertical).lineLimit(3...6).focused($focusedField, equals: .assignmentNotes)
                }
            } else {
                Section("作品内容") {
                    TextField("作品标题（必填）", text: $title).focused($focusedField, equals: .title)
                        .id(PublishValidation.RequiredField.title)
                    if hasAttemptedPublish && missingFields.contains(.title) {
                        Label("请填写作品标题", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                    TextField("作品说明（可选）", text: $summary, axis: .vertical).lineLimit(3...6).focused($focusedField, equals: .summary)
                    TextField("拍摄思路（可选）", text: $shootingNotes, axis: .vertical).lineLimit(3...6).focused($focusedField, equals: .shootingNotes)
                    TextField("后期说明（可选）", text: $editingNotes, axis: .vertical).lineLimit(2...5).focused($focusedField, equals: .editingNotes)
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.defaultTags) { tag in
                            Button {
                                toggleTag(tag.name)
                            } label: {
                                Text(tag.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .foregroundStyle(selectedTags.contains(tag.name) ? Color.white : LumenTheme.ink)
                                    .background(
                                        selectedTags.contains(tag.name) ? LumenTheme.ink : Color(.systemGray6),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("自定义标签", text: $customTag)
                    Button("添加") {
                        let value = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, selectedTags.count < 5, !selectedTags.contains(value) else { return }
                        selectedTags.append(value)
                        customTag = ""
                    }
                    .disabled(customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTags.count >= 5)
                }
                if !selectedTags.isEmpty {
                    Text("已选择：\(selectedTags.joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("作品标签（最多 5 个）")
            }

            Section {
                if metadata.recognizedCount > 0 {
                    Label("已从照片识别 \(metadata.recognizedCount) 项参数，请确认是否准确", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else {
                    Label("未识别到 EXIF，可手动补充", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                TextField("相机", text: $metadata.camera).focused($focusedField, equals: .camera)
                TextField("镜头", text: $metadata.lens).focused($focusedField, equals: .lens)
                HStack {
                    TextField("焦段", text: $metadata.focalLength).focused($focusedField, equals: .focalLength)
                    TextField("光圈", text: $metadata.aperture).focused($focusedField, equals: .aperture)
                }
                HStack {
                    TextField("快门", text: $metadata.shutterSpeed).focused($focusedField, equals: .shutter)
                    TextField("ISO", text: $metadata.iso).keyboardType(.numberPad).focused($focusedField, equals: .iso)
                }
            } header: {
                Text("拍摄参数")
            } footer: {
                Text("参数来自照片 EXIF 或手动填写，发布时视为由你确认。")
            }

            Section {
                Button {
                    focusedField = nil
                    locationPrivacy = locationPrivacy == .hidden ? .exact : .hidden
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: locationPrivacy == .hidden ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(locationPrivacy == .hidden ? LumenTheme.accent : .secondary)
                        Text("隐藏地址")
                            .foregroundStyle(LumenTheme.ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(locationPrivacy == .hidden ? "已勾选" : "未勾选")
            } footer: {
                Text(locationPrivacy == .hidden ? "地址已隐藏，发布时不保存拍摄地点、详细地址和坐标。" : "默认公开拍摄地址；如不希望展示，请勾选隐藏地址。")
            }

            if locationPrivacy != .hidden {
            Section {
                Button {
                    focusedField = nil
                    showingLocationPicker = true
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "location.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(LumenTheme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("拍摄地点")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(locationName.isEmpty ? "未填写拍摄地点，点击选择" : locationName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LumenTheme.ink)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                if locationLatitude != nil && locationLongitude != nil {
                    Button("清除拍摄地点", role: .destructive) {
                        locationLatitude = nil; locationLongitude = nil
                        locationName = ""; locationCity = ""; detailedAddress = ""
                    }
                }
                if let original, original.location.coordinate != nil {
                    Button("在地图上确认原作地点") { showingLocationPicker = true }
                }
                TextField("详细地址（楼层、门牌、机位说明等）", text: $detailedAddress, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .detailedAddress)
            } header: {
                Text("拍摄地点")
            } footer: {
                Text("将公开所选坐标、地点名称和详细地址。请选择照片的实际拍摄地点，当前位置不会自动填入。")
            }
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    if isPublishing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(isEditing ? "保存修改" : (isAssignment ? "发布作业" : "发布作品"), systemImage: isEditing ? "checkmark.circle.fill" : (isAssignment ? "camera.fill" : "arrow.up.circle.fill"))
                        .frame(maxWidth: .infinity)
                    }
                }
                // Keep this tappable for incomplete forms so validation can explain what is missing.
                .disabled(isPublishing || isLoadingPhoto)
            } footer: {
                Text(isLoadingPhoto ? "照片正在读取，请稍候。" : (isAssignment ? "请选择照片；公开地址时需选择拍摄地点。" : "照片和作品标题必填；公开地址时需选择拍摄地点。"))
            }
        }
        .disabled(isPublishing)
        .background(BackgroundKeyboardDismissView())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditing ? "编辑作品" : (isAssignment ? "提交作业" : "发布作品"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            NavigationStack {
                LocationPickerView(
                    initialCoordinate: selectedCoordinate,
                    confirmationTitle: "使用并公开此拍摄地点"
                ) { selection in
                    locationPrivacy = .exact
                    locationLatitude = selection.coordinate.latitude
                    locationLongitude = selection.coordinate.longitude
                    locationName = selection.name
                    locationCity = selection.city
                    if !selection.city.isEmpty {
                        store.updateCurrentCity(selection.city)
                    }
                }
            }
        }
        .navigationDestination(item: $publishedPostID) { postID in
            if isAssignment {
                AssignmentCompareView(assignmentID: postID)
            } else {
                PostDetailView(postID: postID)
            }
        }
        .alert(isEditing ? "保存成功" : "发布成功", isPresented: $showingPublishedAlert) {
            Button("完成") {
                if isAssignment || isEditing { dismiss() } else { resetForm() }
            }
        } message: { Text(isEditing ? "作品信息已更新。" : (isAssignment ? "作业已关联到原作。" : "作品已保存到云端。")) }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
        .alert("请补全必填项", isPresented: $showingRequiredFieldsAlert) {
            Button("去补充") {
                guard let first = missingFields.first else { return }
                withAnimation { proxy.scrollTo(first, anchor: .center) }
                if first == .title { focusedField = .title }
            }
        } message: { Text(requiredFieldsMessage) }
        }
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
            // A replacement photo invalidates the previous photo's location.
            locationLatitude = metadata.latitude
            locationLongitude = metadata.longitude
            locationName = metadata.latitude != nil && metadata.longitude != nil ? "照片中的拍摄地点" : ""
            locationCity = ""
            detailedAddress = ""
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
        guard !isPublishing, !isLoadingPhoto else { return }
        focusedField = nil
        hasAttemptedPublish = true
        guard missingFields.isEmpty else {
            requiredFieldsMessage = missingFields.map(\.reminder).joined(separator: "\n")
            showingRequiredFieldsAlert = true
            return
        }
        guard locationPrivacy == .hidden || (locationLatitude != nil && locationLongitude != nil) else {
            errorMessage = "请先选择实际拍摄地点，或勾选“隐藏地址”后发布。"
            return
        }
        isPublishing = true
        defer { isPublishing = false }
        let user = store.currentUser
        let location = PhotoLocation(
            name: locationPrivacy == .hidden ? "" : locationName,
            city: locationPrivacy == .hidden ? "" : locationCity,
            detailedAddress: locationPrivacy == .exact ? detailedAddress : "",
            privacy: locationPrivacy,
            latitude: locationPrivacy == .hidden ? nil : locationLatitude,
            longitude: locationPrivacy == .hidden ? nil : locationLongitude,
            advice: editingPost?.location.advice ?? ""
        )
        let post = PhotoPost(
            id: editingPost?.id ?? UUID(), kind: isAssignment ? .assignment : .original, originalID: original?.id,
            authorID: user.id, authorName: user.name, authorAvatar: user.avatar, city: user.city,
            title: isAssignment ? "\(original?.title ?? "原作") · 复刻作业" : title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: isAssignment ? (assignmentNotes.isEmpty ? "完成了一次复刻练习。" : assignmentNotes) : (summary.isEmpty ? "分享一张新的摄影作品。" : summary),
            imageData: imageData, imageURL: editingPost?.imageURL, createdAt: editingPost?.createdAt ?? Date(),
            likeCount: editingPost?.likeCount ?? 0, commentCount: editingPost?.commentCount ?? 0,
            tags: selectedTags, allowRemake: !isAssignment,
            location: location, metadata: metadata, shootingNotes: shootingNotes, editingNotes: editingNotes,
            reused: reused, adjusted: adjusted, assignmentNotes: assignmentNotes, isRecommended: editingPost?.isRecommended ?? false
        )
        do {
            if let editingPost {
                try await store.updateOnServer(post, replacing: editingPost, imageData: self.imageData)
            } else if let imageData {
                let published = try await store.publishToServer(post, imageData: imageData)
                resetForm()
                publishedPostID = published.id
                return
            }
            showingPublishedAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetForm() {
        locationLatitude = nil; locationLongitude = nil; locationPrivacy = .exact
        hasAttemptedPublish = false
        requiredFieldsMessage = ""
        selectedItem = nil; imageData = nil; metadata = CaptureMetadata(); title = ""; summary = ""; shootingNotes = ""; editingNotes = ""; selectedTags = []; customTag = ""; locationName = ""; locationCity = ""; detailedAddress = ""
    }

    private var selectedCoordinate: CLLocationCoordinate2D {
        if let latitude = locationLatitude, let longitude = locationLongitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        if let coordinate = original?.location.coordinate ?? locationService.coordinate {
            return coordinate
        }
        return CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
    }

    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else if selectedTags.count < 5 {
            selectedTags.append(tag)
        }
    }
}

enum PublishValidation {
    enum RequiredField: Hashable {
        case photo, title

        var reminder: String {
            switch self {
            case .photo: return "请选择一张照片"
            case .title: return "请填写作品标题"
            }
        }
    }

    static func missingFields(hasPhoto: Bool, isAssignment: Bool, title: String) -> [RequiredField] {
        var missing: [RequiredField] = []
        if !hasPhoto { missing.append(.photo) }
        if !isAssignment && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append(.title)
        }
        return missing
    }
}

private enum PhotoLoadError: LocalizedError {
    case emptyData
    var errorDescription: String? { "无法读取所选照片" }
}

private struct BackgroundKeyboardDismissView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async { context.coordinator.install(in: view.window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.install(in: uiView.window) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private lazy var recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        func install(in window: UIWindow?) {
            guard let window, self.window !== window else { return }
            uninstall()
            self.window = window
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
        }

        func uninstall() {
            window?.removeGestureRecognizer(recognizer)
            window = nil
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIControl {
                    return false
                }
                view = current.superview
            }
            return true
        }
    }
}
