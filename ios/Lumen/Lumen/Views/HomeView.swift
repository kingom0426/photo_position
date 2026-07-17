import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selection = 0

    private var filteredPosts: [PhotoPost] {
        let all = store.posts.sorted {
            if $0.kind != $1.kind { return $0.kind == .original }
            return $0.createdAt > $1.createdAt
        }
        guard !searchText.isEmpty else { return all }
        return all.filter { post in
            [post.title, post.summary, post.authorName, post.city, post.location.name, post.tags.joined(separator: " ")]
                .joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("内容流", selection: $selection) {
                    Text("推荐").tag(0)
                    Text("关注").tag(1)
                    Text("附近").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredPosts.enumerated()), id: \.element.id) { index, post in
                        FeedPostCard(post: post, index: index)
                    }
                }
            }
            .background(LumenTheme.surface)
            .searchable(text: $searchText, prompt: "搜索作品、地点、摄影师")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LumenWordmark() }
                ToolbarItem(placement: .topBarTrailing) { Button(action: {}) { Image(systemName: "bell") } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FeedPostCard: View {
    @EnvironmentObject private var store: AppStore
    let post: PhotoPost
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                AvatarView(text: post.authorAvatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName).font(.subheadline.weight(.semibold))
                    Text("\(post.city) · \(post.createdAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if post.isRecommended {
                    Text("原作者推荐").font(.caption2.weight(.semibold)).foregroundStyle(.green).padding(.horizontal, 9).padding(.vertical, 5).background(.green.opacity(0.10), in: Capsule())
                } else {
                    Button(store.isFollowing(post.authorID) ? "已关注" : "关注") { store.toggleFollow(post.authorID) }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 13)

            NavigationLink {
                if post.kind == .original { PostDetailView(postID: post.id) } else { AssignmentCompareView(assignmentID: post.id) }
            } label: {
                PostPhotoView(post: post)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text("\(post.kind == .original ? "FIELD NOTE" : "REMAKE") · \(String(format: "%02d", index + 1))")
                            .font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.white)
                            .padding(.leading, 9).overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 2) }
                            .padding(18)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.title).font(.title2.weight(.semibold))
                            Text("\(post.location.name.uppercased()) · \(post.kind == .original ? "\(store.assignments(for: post.id).count) REMAKES" : "ASSIGNMENT")")
                                .font(.system(size: 9, weight: .medium)).tracking(1)
                        }.foregroundStyle(.white).padding(18)
                    }
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Text(post.kind == .original ? "SHOOTING NOTE" : "REMAKE STUDY").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                Text(post.summary).font(.subheadline).lineSpacing(5)
                HStack(spacing: 9) {
                    ForEach([post.metadata.focalLength, post.metadata.aperture, post.metadata.shutterSpeed, post.metadata.iso].filter { !$0.isEmpty }, id: \.self) { item in
                        Text(item).font(.caption).foregroundStyle(.secondary)
                        if item != [post.metadata.focalLength, post.metadata.aperture, post.metadata.shutterSpeed, post.metadata.iso].filter({ !$0.isEmpty }).last { Divider().frame(height: 12) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)

            HStack {
                Button { store.toggleLike(post.id) } label: { Label("\(post.likeCount + (store.isLiked(post.id) ? 1 : 0))", systemImage: store.isLiked(post.id) ? "heart.fill" : "heart") }
                Spacer()
                Label("\(store.comments(for: post.id).count)", systemImage: "bubble")
                Spacer()
                if post.kind == .original {
                    Button { store.togglePlan(post.id) } label: { Label(store.isPlanned(post.id) ? "已在计划" : "待复刻", systemImage: store.isPlanned(post.id) ? "bookmark.fill" : "bookmark") }
                } else if let originalID = post.originalID {
                    NavigationLink("查看原作", destination: PostDetailView(postID: originalID))
                }
            }
            .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(LumenTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }
}
