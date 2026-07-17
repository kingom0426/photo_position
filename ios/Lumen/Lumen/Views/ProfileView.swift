import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        AvatarView(text: store.currentUser.avatar, size: 76)
                        Text(store.currentUser.name).font(.title3.weight(.semibold))
                        Text("\(store.currentUser.city) · \(store.currentUser.bio)").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            stat("\(store.currentUserPosts.filter { $0.kind == .original }.count)", "作品")
                            stat("\(store.currentUserPosts.filter { $0.kind == .assignment }.count)", "作业")
                            stat("\(store.currentUserPosts.reduce(0) { $0 + $1.likeCount })", "获赞")
                        }.padding(.top, 14)
                    }.frame(maxWidth: .infinity).padding(.vertical, 26)

                    Divider()
                    if store.currentUserPosts.isEmpty {
                        ContentUnavailableView("发布第一张作品", systemImage: "camera", description: Text("分享拍摄参数和你的创作经验")).frame(minHeight: 320)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                            ForEach(store.currentUserPosts) { post in
                                NavigationLink(destination: post.kind == .original ? AnyView(PostDetailView(postID: post.id)) : AnyView(AssignmentCompareView(assignmentID: post.id))) {
                                    PostPhotoView(post: post).aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    Button(role: .destructive) { showingResetAlert = true } label: { Label("恢复初始演示数据", systemImage: "arrow.counterclockwise") }
                        .padding(.vertical, 28)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { LumenWordmark() } }
            .alert("恢复演示数据？", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) {}
                Button("恢复", role: .destructive) { store.reset() }
            } message: { Text("本机发布的内容会被清除。") }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) { Text(value).font(.title3.weight(.semibold)); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}
