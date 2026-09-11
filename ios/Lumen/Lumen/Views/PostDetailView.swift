import SwiftUI
import MapKit

struct PostDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let postID: UUID
    var scrollToComments = false
    @State private var commentText = ""
    @State private var showingImage = false
    @State private var didApplyInitialScroll = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        Group {
            if let post = store.post(id: postID) {
                let isOwnPost = store.isAuthenticated && post.authorID == store.currentUser.id
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                        Button { showingImage = true } label: {
                            DetailPostPhotoView(post: post)
                                .frame(height: min(UIScreen.main.bounds.height * 0.62, UIScreen.main.bounds.width * 1.25))
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topLeading) {
                                Text("ORIGINAL · \(post.id.uuidString.prefix(4))").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.white)
                                    .padding(.leading, 9).overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 2) }.padding(18)
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.title).font(.title2.weight(.semibold))
                                    Text("\(post.authorName) · \(chineseDateTime(post.createdAt))").font(.caption)
                                }.foregroundStyle(.white).padding(18)
                            }
                            .accessibilityLabel("查看大图")

                        DetailSection {
                            HStack(spacing: 11) {
                                NavigationLink {
                                    UserSpaceView(user: UserProfile(
                                        id: post.authorID,
                                        name: post.authorName,
                                        avatar: post.authorAvatar,
                                        city: post.city.isEmpty ? post.location.city : post.city,
                                        bio: ""
                                    ))
                                } label: {
                                    HStack(spacing: 11) {
                                        AvatarView(text: post.authorAvatar)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(post.authorName).font(.subheadline.weight(.semibold))
                                            Text("\(post.city) · 摄影爱好者").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if !isOwnPost {
                                    Button(store.isFollowing(post.authorID) ? "已关注" : "关注") { store.toggleFollow(post.authorID) }
                                        .buttonStyle(.bordered).tint(LumenTheme.ink)
                                }
                            }
                            Text(post.summary).font(.subheadline).lineSpacing(5).padding(.top, 14)
                        }

                        DetailSection {
                            SectionLabel(title: "拍摄配方", trailing: post.metadata.source == .manual ? "手动填写" : "EXIF 已确认")
                            MetadataGrid(metadata: post.metadata).padding(.top, 14)
                        }

                        DetailSection {
                            SectionLabel(title: "拍摄思路")
                            Text(post.shootingNotes.isEmpty ? "作者暂未补充拍摄思路。" : post.shootingNotes).font(.subheadline).lineSpacing(5).padding(.top, 12)
                            if !post.editingNotes.isEmpty {
                                Text("后期：\(post.editingNotes)").font(.caption).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 10)
                            }
                        }

                        if let coordinate = post.location.coordinate {
                            DetailSection {
                                SectionLabel(title: "拍摄地图", trailing: post.location.privacy == .approximate ? "模糊区域 · 非精确机位" : "点击查看")
                                ZStack {
                                    Map(initialPosition: .region(MKCoordinateRegion(
                                        center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                                    ))) {
                                        Annotation(mapAnnotationTitle(for: post), coordinate: coordinate) {
                                            VStack(spacing: 3) {
                                                PostPhotoView(post: post)
                                                    .frame(width: 52, height: 52)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .stroke(.white, lineWidth: 2.5)
                                                    }
                                                Text(post.title)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(LumenTheme.ink)
                                                    .lineLimit(1)
                                                    .frame(maxWidth: 96)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 4)
                                                    .background(.regularMaterial, in: Capsule())
                                            }
                                            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                                        }
                                    }
                                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                                    .allowsHitTesting(false)

                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            store.showPostOnMap(post.id)
                                        }
                                }
                                .frame(height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.top, 12)

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(LumenTheme.accent)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("定位地址")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(post.location.name.isEmpty ? post.location.city : post.location.name)
                                                .font(.subheadline)
                                                .lineLimit(3)
                                        }
                                    }

                                    Divider()
                                        .padding(.leading, 27)

                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "text.alignleft")
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("详细地址")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(post.location.detailedAddress.isEmpty ? "未填写" : post.location.detailedAddress)
                                                .font(.subheadline)
                                                .foregroundStyle(post.location.detailedAddress.isEmpty ? .secondary : .primary)
                                                .lineLimit(3)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                            }
                        }

                        if post.location.coordinate == nil {
                            DetailSection {
                                SectionLabel(title: "拍摄地图")
                                Label("拍摄地点未公开或尚未填写", systemImage: "location.slash")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 12)
                                if isOwnPost {
                                    Text("编辑作品，选择拍摄地点并确认公开后，将在这里和地图页显示。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 6)
                                }
                            }
                        }

                        let assignments = store.assignments(for: post.id)
                        DetailSection {
                            SectionLabel(title: "复刻作业", trailing: "\(assignments.count) 份")
                            if assignments.isEmpty {
                                Text("还没有人提交作业，成为第一个复刻者。").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                            } else {
                                ForEach(assignments) { assignment in
                                    NavigationLink(destination: AssignmentCompareView(assignmentID: assignment.id)) {
                                        HStack(spacing: 12) {
                                            PostPhotoView(post: assignment).frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 12))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("\(assignment.authorName)的作业").font(.subheadline.weight(.semibold))
                                                Text("\(assignment.isRecommended ? "原作者推荐 · " : "")\(assignment.adjusted)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }.padding(.top, 12)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                            DetailSection {
                                SectionLabel(title: "评论", trailing: "\(store.comments(for: post.id).count) 条")
                                VStack(spacing: 14) {
                                    ForEach(store.comments(for: post.id)) { comment in
                                        HStack(alignment: .top, spacing: 10) {
                                            NavigationLink {
                                                UserSpaceView(user: UserProfile(
                                                    id: comment.authorID,
                                                    name: comment.authorName,
                                                    avatar: comment.authorAvatar,
                                                    city: "",
                                                    bio: ""
                                                ))
                                            } label: {
                                                AvatarView(text: comment.authorAvatar, size: 30)
                                            }
                                            .buttonStyle(.plain)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(comment.authorName).font(.caption.weight(.semibold))
                                                Text(comment.text).font(.caption)
                                            }
                                            Spacer()
                                        }
                                    }
                                }.padding(.top, 12)
                                HStack {
                                    TextField("友善、具体地交流拍摄经验", text: $commentText).textFieldStyle(.roundedBorder)
                                    Button("发送") {
                                        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !text.isEmpty else { return }
                                        guard store.requireAuthentication() else { return }
                                        store.addComment(postID: post.id, text: text)
                                        commentText = ""
                                    }.buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                                }.padding(.top, 14)
                            }
                            .id("comments")
                        }
                    }
                    .task {
                        await store.loadComments(postID: post.id)
                        guard scrollToComments, !didApplyInitialScroll else { return }
                        didApplyInitialScroll = true
                        await Task.yield()
                        await Task.yield()
                        withAnimation(.easeInOut(duration: 0.28)) {
                            scrollProxy.scrollTo("comments", anchor: .top)
                        }
                    }
                }
                .background(LumenTheme.surface)
                .safeAreaInset(edge: .bottom) {
                    Group {
                        if isOwnPost {
                            HStack(spacing: 10) {
                                NavigationLink(destination: PublishView(editing: post)) {
                                    Label("快速编辑", systemImage: "square.and.pencil")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(LumenTheme.ink)

                                Button(role: .destructive) {
                                    showingDeleteConfirmation = true
                                } label: {
                                    if isDeleting {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Label("删除作品", systemImage: "trash")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isDeleting)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            let myAssignment = store.isAuthenticated ? store.assignment(for: post.id, authorID: store.currentUser.id) : nil
                            if let myAssignment {
                                NavigationLink(destination: AssignmentCompareView(assignmentID: myAssignment.id)) { Label("查看我的作业", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            } else if store.isPlanned(post.id) {
                                NavigationLink(destination: PublishView(original: post)) { Label("交作业", systemImage: "camera").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            } else {
                                Button { store.togglePlan(post.id) } label: { Label("我想拍", systemImage: "bookmark").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
                }
                .navigationTitle("作品详情")
                .navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented: $showingImage) {
                    ZoomablePostPhotoView(post: post, isPresented: $showingImage)
                }
                .confirmationDialog(
                    "确认删除这张作品？",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("删除作品", role: .destructive) {
                        Task {
                            isDeleting = true
                            do {
                                try await store.deletePost(post.id)
                                dismiss()
                            } catch {
                                deleteError = error.localizedDescription
                                isDeleting = false
                            }
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("删除后作品将不再展示，此操作无法撤销。")
                }
                .alert("删除失败", isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )) {
                    Button("知道了", role: .cancel) {}
                } message: {
                    Text(deleteError ?? "")
                }
            } else {
                ContentUnavailableView("作品不存在", systemImage: "photo", description: Text("它可能已被删除或暂时不可见"))
            }
        }
    }

    private func chineseDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func mapAnnotationTitle(for post: PhotoPost) -> String {
        post.title
    }
}

private struct DetailPostPhotoView: View {
    let post: PhotoPost

    var body: some View {
        ZStack {
            Color.black
            Group {
                if let data = post.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let imageURL = post.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else if phase.error != nil {
                            PhotoPlaceholderView()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                } else {
                    PhotoPlaceholderView()
                }
            }
        }
        .clipped()
    }
}

private struct ZoomablePostPhotoView: View {
    let post: PhotoPost
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            OriginalPostPhotoView(post: post)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2
                        lastScale = scale
                    }
                }
                .ignoresSafeArea()

            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding()
        }
    }
}

private struct OriginalPostPhotoView: View {
    let post: PhotoPost

    var body: some View {
        ZStack {
            Color.black
            if let data = post.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let imageURL = post.originalImageURL ?? post.displayImageURL ?? post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            } else {
                PhotoPlaceholderView()
            }
        }
        .clipped()
    }
}

struct DetailSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .overlay(alignment: .bottom) { Divider() }
    }
}
