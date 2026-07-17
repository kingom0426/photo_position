import SwiftUI

struct AssignmentCompareView: View {
    @EnvironmentObject private var store: AppStore
    let assignmentID: UUID
    @State private var commentText = ""

    var body: some View {
        Group {
            if let assignment = store.post(id: assignmentID), let originalID = assignment.originalID, let original = store.post(id: originalID) {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            comparisonPhoto(post: original, label: "原作 · \(original.authorName)")
                            comparisonPhoto(post: assignment, label: "作业 · \(assignment.authorName)")
                        }
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
                                    AvatarView(text: comment.authorAvatar, size: 30)
                                    VStack(alignment: .leading, spacing: 3) { Text(comment.authorName).font(.caption.weight(.semibold)); Text(comment.text).font(.caption) }
                                    Spacer()
                                }.padding(.top, 12)
                            }
                            HStack {
                                TextField("写下你的点评", text: $commentText).textFieldStyle(.roundedBorder)
                                Button("发送") {
                                    let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !text.isEmpty else { return }
                                    store.addComment(postID: assignment.id, text: text); commentText = ""
                                }.buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            }.padding(.top, 14)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    NavigationLink(destination: PublishView(original: original)) { Label("我也来拍", systemImage: "camera") }
                        .buttonStyle(.borderedProminent).tint(LumenTheme.ink).frame(maxWidth: .infinity).padding(12).background(.ultraThinMaterial)
                }
                .navigationTitle("原作与作业")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("作业不存在", systemImage: "rectangle.split.2x1")
            }
        }
    }

    private func comparisonPhoto(post: PhotoPost, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PostPhotoView(post: post).aspectRatio(3.0 / 4.0, contentMode: .fit)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.weight(.semibold))
                Text([post.metadata.focalLength, post.metadata.aperture, post.metadata.shutterSpeed].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(10)
        }.frame(maxWidth: .infinity)
    }
}
