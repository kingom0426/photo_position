import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject private var store: AppStore
    let postID: UUID
    @State private var commentText = ""

    var body: some View {
        Group {
            if let post = store.post(id: postID) {
                ScrollView {
                    VStack(spacing: 0) {
                        PostPhotoView(post: post)
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)
                            .overlay(alignment: .topLeading) {
                                Text("ORIGINAL · \(post.id.uuidString.prefix(4))").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.white)
                                    .padding(.leading, 9).overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 2) }.padding(18)
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.title).font(.title2.weight(.semibold))
                                    Text("\(post.authorName) · \(post.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                                }.foregroundStyle(.white).padding(18)
                            }

                        DetailSection {
                            HStack(spacing: 11) {
                                AvatarView(text: post.authorAvatar)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(post.authorName).font(.subheadline.weight(.semibold))
                                    Text("\(post.city) · 摄影爱好者").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(store.isFollowing(post.authorID) ? "已关注" : "关注") { store.toggleFollow(post.authorID) }
                                    .buttonStyle(.bordered).tint(LumenTheme.ink)
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

                        DetailSection {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.location.name).font(.subheadline.weight(.semibold))
                                    Text("\(post.location.privacy.title)\(post.location.advice.isEmpty ? "" : " · \(post.location.advice)")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if post.location.privacy != .hidden { Image(systemName: "location.fill").foregroundStyle(LumenTheme.accent) }
                            }.padding(14).background(LumenTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
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
                                        AvatarView(text: comment.authorAvatar, size: 30)
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
                                    store.addComment(postID: post.id, text: text)
                                    commentText = ""
                                }.buttonStyle(.borderedProminent).tint(LumenTheme.ink)
                            }.padding(.top, 14)
                        }
                    }
                }
                .background(LumenTheme.surface)
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 10) {
                        Button { store.togglePlan(post.id) } label: { Label(store.isPlanned(post.id) ? "已加入计划" : "加入计划", systemImage: store.isPlanned(post.id) ? "bookmark.fill" : "bookmark") }
                            .buttonStyle(.bordered).tint(LumenTheme.ink).frame(maxWidth: .infinity)
                        NavigationLink(destination: PublishView(original: post)) { Label("交作业", systemImage: "camera") }
                            .buttonStyle(.borderedProminent).tint(LumenTheme.ink).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
                }
                .navigationTitle("作品详情")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("作品不存在", systemImage: "photo", description: Text("它可能已被删除或暂时不可见"))
            }
        }
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
