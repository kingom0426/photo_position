import SwiftUI

struct AssignmentCompareView: View {
    @EnvironmentObject private var store: AppStore
    let assignmentID: UUID
    @State private var commentText = ""
    @State private var enlargedPost: PhotoPost?
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        Group {
            if let assignment = store.post(id: assignmentID), let originalID = assignment.originalID, let original = store.post(id: originalID) {
                let isOwnAssignment = store.isAuthenticated && assignment.authorID == store.currentUser.id
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { proxy in
                            let columnWidth = (proxy.size.width - 2) / 2
                            HStack(alignment: .top, spacing: 2) {
                                comparisonPhoto(
                                    post: original,
                                    label: "原作 · \(original.authorName)",
                                    width: columnWidth
                                )
                                comparisonPhoto(
                                    post: assignment,
                                    label: "作业 · \(assignment.authorName)",
                                    width: columnWidth
                                )
                            }
                        }
                        .frame(height: comparisonHeight)
                        DetailSection {
                            HStack { Text("这次的调整").font(.headline); Spacer(); if assignment.isRecommended { Text("原作者推荐").font(.caption2.weight(.semibold)).foregroundStyle(.green) } }
                            VStack(alignment: .leading, spacing: 9) {
                                Text("沿用：\(assignment.reused.isEmpty ? "未填写" : assignment.reused)")
                                Text("调整：\(assignment.adjusted.isEmpty ? "未填写" : assignment.adjusted)")
                                Text(assignment.assignmentNotes).foregroundStyle(.secondary)
                            }.font(.subheadline).lineSpacing(4).padding(.top, 12)
                        }
                        DetailSection { SectionLabel(title: "作业参数"); MetadataGrid(metadata: assignment.metadata).padding(.top, 14) }
                        DetailSection {
                            SectionLabel(title: "评论", trailing: "\(store.comments(for: assignment.id).count) 条")
                            ForEach(store.comments(for: assignment.id)) { comment in
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
                                    VStack(alignment: .leading, spacing: 3) { Text(comment.authorName).font(.caption.weight(.semibold)); Text(comment.text).font(.caption) }
                                    Spacer()
                                }.padding(.top, 12)
                            }
                            HStack {
                                TextField("写下你的点评", text: $commentText).textFieldStyle(.roundedBorder)
                                Button("发送") {
                                    let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !text.isEmpty else { return }
                                    guard store.requireAuthentication() else { return }
                                    store.addComment(postID: assignment.id, text: text); commentText = ""
                                }.buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            }.padding(.top, 14)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Group {
                        if isOwnAssignment {
                            HStack(spacing: 10) {
                                NavigationLink(destination: PublishView(original: original, editing: assignment)) {
                                    Label("快速编辑作业", systemImage: "square.and.pencil")
                                }
                                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                                    if isDeleting { ProgressView() } else { Label("删除作业", systemImage: "trash") }
                                }
                                .disabled(isDeleting)
                            }
                        } else if store.isAuthenticated {
                            NavigationLink(destination: PublishView(original: original)) { Label("我也来拍", systemImage: "camera") }
                        } else {
                            Button { store.showingAuthentication = true } label: {
                                Label("登录后参与", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(LumenTheme.ink).frame(maxWidth: .infinity).padding(12).background(.ultraThinMaterial)
                }
                .navigationTitle("原作与作业")
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("确认删除这份作业？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                    Button("删除作业", role: .destructive) {
                        Task {
                            isDeleting = true
                            do {
                                try await store.deletePost(assignment.id)
                            } catch {
                                deleteError = error.localizedDescription
                                isDeleting = false
                            }
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("删除后这份作业将不再公开展示，且无法恢复。")
                }
                .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                    Button("好", role: .cancel) {}
                } message: { Text(deleteError ?? "") }
                .fullScreenCover(item: $enlargedPost) { post in
                    AssignmentZoomPhotoView(post: post)
                }
            } else {
                ContentUnavailableView("作业不存在", systemImage: "rectangle.split.2x1")
            }
        }
    }

    private var comparisonHeight: CGFloat {
        let width = (UIScreen.main.bounds.width - 2) / 2
        return width * 4 / 3 + 62
    }

    private func comparisonPhoto(post: PhotoPost, label: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                enlargedPost = post
            } label: {
                PostPhotoView(post: post)
                    .frame(width: width, height: width * 4 / 3)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.48), in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.weight(.semibold))
                Text([post.metadata.focalLength, post.metadata.aperture, post.metadata.shutterSpeed].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(10)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}

private struct AssignmentZoomPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let post: PhotoPost
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            zoomPhoto
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

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding()
        }
    }

    @ViewBuilder
    private var zoomPhoto: some View {
        if let data = post.imageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
        } else if let url = post.originalImageURL ?? post.displayImageURL ?? post.imageURL {
            AsyncImage(url: url) { phase in
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
