import SwiftUI

struct PlansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0

    private var plannedPosts: [PhotoPost] {
        store.originals.filter { store.plannedPostIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("计划状态", selection: $selection) {
                    Text("待拍摄 \(plannedPosts.count)").tag(0)
                    Text("已交作业 \(store.currentUserPosts.filter { $0.kind == .assignment }.count)").tag(1)
                    Text("收藏").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(16)

                if plannedPosts.isEmpty {
                    ContentUnavailableView("还没有拍摄计划", systemImage: "bookmark", description: Text("从作品详情加入一个想复刻的作品"))
                } else {
                    List {
                        ForEach(plannedPosts) { post in
                            HStack(alignment: .top, spacing: 12) {
                                NavigationLink(destination: PostDetailView(postID: post.id)) {
                                    PostPhotoView(post: post).frame(width: 82, height: 82).clipShape(RoundedRectangle(cornerRadius: 13))
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(post.title).font(.subheadline.weight(.semibold))
                                    Text(post.location.name).font(.caption).foregroundStyle(.secondary)
                                    Text(post.location.advice).font(.caption2).foregroundStyle(.secondary)
                                    NavigationLink(destination: PublishView(original: post)) {
                                        Label("交作业", systemImage: "camera").font(.caption.weight(.semibold))
                                    }.buttonStyle(.borderedProminent).tint(LumenTheme.ink).padding(.top, 3)
                                }
                                Spacer()
                            }.padding(.vertical, 7)
                        }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("拍摄计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { LumenWordmark() } }
        }
    }
}
