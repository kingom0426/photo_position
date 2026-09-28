import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var selection = 0
    @State private var isSearchVisible = false
    @State private var feedPosts: [PhotoPost] = []
    @State private var selectedFilters: Set<String> = []
    @State private var nearbyRadius = 5.0
    @State private var searchResults = GroupedSearchResults()
    @State private var isLoadingFeed = false
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredPosts: [PhotoPost] {
        feedPosts
    }

    private var followedUsers: [UserProfile] {
        let users = store.followedUsers
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return users }
        return users.filter {
            [$0.name, $0.city]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    if isSearchVisible {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("搜索作品、地点、摄影师", text: $searchText)
                                .focused($isSearchFieldFocused)
                                .submitLabel(.search)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(LumenTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isSearchVisible && !searchText.isEmpty {
                        groupedSearchContent
                            .frame(width: proxy.size.width)
                    } else {
                        discoveryControls
                        if filteredPosts.isEmpty {
                            ContentUnavailableView(
                                isLoadingFeed ? "正在加载作品" : emptyFeedTitle,
                                systemImage: "photo.on.rectangle",
                                description: Text(emptyFeedDescription)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 280)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredPosts) { post in
                                    FeedPostCard(
                                        post: post,
                                        cardWidth: proxy.size.width
                                    )
                                }
                            }
                            .frame(width: proxy.size.width)
                            .padding(.bottom, 18)
                        }
                    }
                }
                .refreshable {
                    await refreshHome()
                }
                .background(feedBackground)
                .simultaneousGesture(homeSwipeGesture)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                homeHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(LumenTheme.surface.ignoresSafeArea())
        }
        .id(homeNavigationIdentity)
        .task(id: feedReloadIdentity) {
            await loadFeed()
        }
        .task(id: searchText) {
            await runSearch()
        }
        .task(id: notificationPollingIdentity) {
            await pollNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.isAuthenticated else { return }
            Task { await store.loadNotifications() }
        }
    }

    private var homeHeader: some View {
        ZStack {
            HStack(spacing: 24) {
                homeTab(title: "推荐", index: 0)
                homeTab(title: "关注", index: 1)
                homeTab(title: "附近", index: 2)
            }

            HStack(spacing: 0) {
                HomeBrandMark()
                Spacer()
                NavigationLink {
                    NotificationCenterView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 18, weight: .semibold))
                        if store.unreadNotificationCount > 0 {
                            Text(store.unreadNotificationCount > 99 ? "99+" : "\(store.unreadNotificationCount)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red, in: Capsule())
                                .offset(x: 7, y: -7)
                        }
                    }
                    .foregroundStyle(LumenTheme.ink)
                    .frame(width: 42, height: 48)
                }
                .buttonStyle(.plain)
                Button(action: toggleSearch) {
                    Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LumenTheme.ink)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSearchVisible ? "关闭搜索" : "搜索")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 54)
        .background(LumenTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func homeTab(title: String, index: Int) -> some View {
        Button {
            selectHomeTab(index)
        } label: {
            Text(title)
                .font(.system(size: 17, weight: selection == index ? .semibold : .regular))
                .foregroundStyle(selection == index ? LumenTheme.ink : Color.secondary)
                .frame(height: 48)
                .overlay(alignment: .bottom) {
                Capsule()
                    .fill(LumenTheme.ink)
                    .frame(width: 24, height: 3)
                    .opacity(selection == index ? 1 : 0)
                    .padding(.bottom, 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var homeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 50 else {
                    return
                }
                let next = value.translation.width < 0 ? min(selection + 1, 2) : max(selection - 1, 0)
                selectHomeTab(next)
            }
    }

    private func selectHomeTab(_ index: Int) {
        guard index != selection else { return }
        if index == 1 && !store.requireAuthentication() {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = index
        }
    }

    private var discoveryControls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickFilters, id: \.id) { filter in
                        Button {
                            if !selectedFilters.insert(filter.id).inserted {
                                selectedFilters.remove(filter.id)
                            }
                        } label: {
                            Label(filter.title, systemImage: filter.icon)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .frame(height: 34)
                                .foregroundStyle(selectedFilters.contains(filter.id) ? Color.white : LumenTheme.ink)
                                .background(
                                    selectedFilters.contains(filter.id) ? LumenTheme.accent : LumenTheme.surface,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(LumenTheme.divider, lineWidth: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            if selection == 2 {
                HStack {
                    Label("按当前位置召回", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach([1.0, 3.0, 5.0, 10.0, 20.0], id: \.self) { radius in
                            Button("\(Int(radius)) km") { nearbyRadius = radius }
                        }
                    } label: {
                        Text("半径 \(Int(nearbyRadius)) km")
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 9)
        .background(feedBackground)
    }

    private var groupedSearchContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if isSearching {
                ProgressView("正在搜索")
                    .frame(maxWidth: .infinity)
                    .padding(30)
            } else if searchResults.isEmpty {
                ContentUnavailableView(
                    "没有找到相关内容",
                    systemImage: "magnifyingglass",
                    description: Text("试试作品名、地点、摄影师或标签")
                )
                .frame(minHeight: 280)
            } else {
                if !searchResults.posts.isEmpty {
                    searchSectionTitle("作品")
                    ForEach(searchResults.posts) { post in
                        NavigationLink {
                            post.kind == .original
                                ? AnyView(PostDetailView(postID: post.id))
                                : AnyView(AssignmentCompareView(assignmentID: post.id))
                        } label: {
                            searchPostRow(post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !searchResults.locations.isEmpty {
                    searchSectionTitle("地点")
                    ForEach(searchResults.locations) { location in
                        Button {
                            store.selectedTab = 1
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .frame(width: 34, height: 34)
                                    .background(Color(.systemGray6), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.name.isEmpty ? location.city : location.name)
                                        .foregroundStyle(LumenTheme.ink)
                                        .lineLimit(1)
                                    Text("\(location.city) · \(location.postCount) 个作品")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 62)
                            .background(LumenTheme.surface)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !searchResults.users.isEmpty {
                    searchSectionTitle("摄影师")
                    ForEach(searchResults.users) { user in
                        NavigationLink {
                            UserSpaceView(user: UserProfile(
                                id: user.id,
                                name: user.name,
                                avatar: user.avatar,
                                city: user.city,
                                bio: user.bio
                            ))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(text: user.avatar, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(user.name).foregroundStyle(LumenTheme.ink)
                                    Text(user.city.isEmpty ? user.bio : user.city)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 62)
                            .background(LumenTheme.surface)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !searchResults.tags.isEmpty {
                    searchSectionTitle("标签")
                    FlowTagRows(tags: searchResults.tags.map(\.name))
                        .padding(16)
                        .background(LumenTheme.surface)
                }
            }
        }
    }

    private func searchSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(feedBackground)
    }

    private func searchPostRow(_ post: PhotoPost) -> some View {
        HStack(spacing: 12) {
            PostPhotoView(post: post)
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(.subheadline.weight(.semibold)).foregroundStyle(LumenTheme.ink)
                Text("\(post.authorName) · \(post.location.city)")
                    .font(.caption).foregroundStyle(.secondary)
                if !post.tags.isEmpty {
                    Text(post.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption2).foregroundStyle(LumenTheme.accent)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 82)
        .background(LumenTheme.surface)
    }

    private var quickFilters: [(id: String, title: String, icon: String)] {
        [
            ("night", "夜景", "moon.stars"),
            ("street", "街拍", "figure.walk"),
            ("architecture", "建筑", "building.2"),
            ("mobile", "手机可拍", "iphone"),
            ("complete", "完整参数", "camera.aperture"),
            ("distance", "距我 5km", "location")
        ]
    }

    private var feedReloadIdentity: String {
        let coordinate = locationService.coordinate
        return [
            String(selection),
            selectedFilters.sorted().joined(separator: ","),
            String(nearbyRadius),
            coordinate.map { String(format: "%.4f", $0.latitude) } ?? "",
            coordinate.map { String(format: "%.4f", $0.longitude) } ?? "",
            store.isAuthenticated ? store.currentUser.id : "guest"
        ].joined(separator: "|")
    }

    private var notificationPollingIdentity: String {
        store.isAuthenticated ? store.currentUser.id : "guest-notifications"
    }

    private var emptyFeedTitle: String {
        switch selection {
        case 1: "关注的摄影师还没有新动态"
        case 2: "附近暂时没有作品"
        default: "暂无推荐作品"
        }
    }

    private var emptyFeedDescription: String {
        switch selection {
        case 1: "关注摄影师后，他们的新作品和作业会直接显示在这里"
        case 2: "试试扩大召回半径或清空筛选条件"
        default: "稍后再来看看，或调整快捷筛选"
        }
    }

    private func loadFeed() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        let coordinate = locationService.coordinate
        let needsLocation = selection == 2 || selectedFilters.contains("distance")
        if let refreshedPosts = await store.loadFeed(
            feed: selection == 1 ? "following" : (selection == 2 ? "nearby" : "recommended"),
            latitude: needsLocation ? coordinate?.latitude : nil,
            longitude: needsLocation ? coordinate?.longitude : nil,
            radiusKm: selection == 2 ? nearbyRadius : (selectedFilters.contains("distance") ? 5 : nil),
            filters: selectedFilters
        ) {
            feedPosts = refreshedPosts
        }
    }

    private func refreshHome() async {
        if isSearchVisible && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = await store.search(searchText)
        } else {
            await loadFeed()
        }
        if store.isAuthenticated {
            await store.loadNotifications()
        }
    }

    private func pollNotifications() async {
        guard store.isAuthenticated else { return }
        while !Task.isCancelled {
            await store.loadNotifications()
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchVisible, !query.isEmpty else {
            searchResults = GroupedSearchResults()
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            searchResults = await store.search(query)
        } catch {
            return
        }
        isSearching = false
    }

    @ViewBuilder
    private var followedUsersContent: some View {
        if followedUsers.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "还没有关注用户" : "没有找到相关用户",
                systemImage: "person.2",
                description: Text(searchText.isEmpty
                    ? "在作品详情关注摄影师后，会显示在这里"
                    : "换个关键词试试")
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(followedUsers) { user in
                    NavigationLink {
                        UserSpaceView(user: user)
                    } label: {
                        HStack(spacing: 13) {
                            AvatarView(text: user.avatar, size: 52)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(user.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(LumenTheme.ink)
                                Text(user.city.isEmpty ? "城市未填写" : user.city)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 76)
                        .background(LumenTheme.surface)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 81)
                }
            }
            .padding(.bottom, 18)
        }
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchVisible.toggle()
        }
        if isSearchVisible {
            Task { @MainActor in
                await Task.yield()
                isSearchFieldFocused = true
            }
        } else {
            searchText = ""
            isSearchFieldFocused = false
        }
    }

    private var feedBackground: Color {
        LumenTheme.canvas
    }

    private var homeNavigationIdentity: String {
        store.isAuthenticated ? store.currentUser.id : "guest-home"
    }
}

private struct FlowTagRows: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text("# \(tag)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(.systemGray6), in: Capsule())
                }
            }
        }
    }
}

struct NotificationCenterView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if !store.isAuthenticated {
                GuestGateView(
                    title: "登录后查看通知",
                    description: "新作业、评论、点赞和关注会显示在这里。"
                )
            } else if store.notifications.isEmpty {
                ContentUnavailableView(
                    "还没有通知",
                    systemImage: "bell",
                    description: Text("收到社区互动后会及时提醒你")
                )
            } else {
                List(store.notifications) { notification in
                    if notification.type == "FOLLOW" {
                        notificationRow(notification)
                            .contentShape(Rectangle())
                            .onTapGesture { store.markNotificationRead(notification) }
                    } else {
                        NavigationLink {
                            Group {
                                if notification.type == "ASSIGNMENT", let sourceID = notification.sourcePostID {
                                    AssignmentCompareView(assignmentID: sourceID)
                                } else if let postID = notification.targetPostID {
                                    PostDetailView(postID: postID)
                                } else {
                                    ContentUnavailableView("内容不可用", systemImage: "exclamationmark.circle")
                                }
                            }
                            .onAppear { store.markNotificationRead(notification) }
                        } label: {
                            notificationRow(notification)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.unreadNotificationCount > 0 {
                Button("全部已读") { store.markAllNotificationsRead() }
            }
        }
        .task {
            while !Task.isCancelled {
                await store.loadNotifications()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
        .refreshable { await store.loadNotifications() }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(text: notification.actorAvatar, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                    Spacer()
                    if !notification.isRead {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                    }
                }
                Text(notification.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(relativeTime(notification.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct HomeBrandMark: View {
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(LumenTheme.ink, lineWidth: 1.6)
                    .frame(width: 27, height: 20)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(LumenTheme.ink)
                            .frame(width: 9, height: 2)
                            .offset(x: 4, y: -3)
                    }
                Circle()
                    .stroke(LumenTheme.ink, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(LumenTheme.ink)
                    .frame(width: 3, height: 3)
                Circle()
                    .fill(LumenTheme.ink)
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: 8, y: -5)
            }
            Text("光迹")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(LumenTheme.ink)
        }
        .padding(.horizontal, 3)
        .frame(height: 34)
        .frame(width: 88, height: 48, alignment: .leading)
        .accessibilityLabel("光迹")
    }
}

struct UserSpaceView: View {
    @EnvironmentObject private var store: AppStore
    let user: UserProfile
    @State private var loadedPosts: [PhotoPost]?
    @State private var isLoading = false

    private var originalPosts: [PhotoPost] {
        (loadedPosts ?? store.posts)
            .filter { $0.kind == .original && $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    AvatarView(text: user.avatar, size: 78)
                    Text(user.name)
                        .font(.title3.weight(.semibold))
                    Text(user.city.isEmpty ? "城市未填写" : user.city)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text("\(originalPosts.count) 个作品")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if user.id != store.currentUser.id {
                        Button(store.isFollowing(user.id) ? "取消关注" : "关注") {
                            store.toggleFollow(user.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LumenTheme.ink)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(LumenTheme.surface)

                if isLoading && originalPosts.isEmpty {
                    ProgressView("正在加载作品")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 280)
                } else if originalPosts.isEmpty {
                    ContentUnavailableView(
                        "还没有原创作品",
                        systemImage: "photo.on.rectangle",
                        description: Text("该用户暂未发布原创作品")
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 280)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(originalPosts) { post in
                            NavigationLink {
                                PostDetailView(postID: post.id)
                            } label: {
                                HStack(spacing: 13) {
                                    PostPhotoView(post: post)
                                        .frame(width: 96, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(post.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(LumenTheme.ink)
                                            .lineLimit(2)
                                        Text(post.location.displayAddress.isEmpty ? post.location.city : post.location.displayAddress)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(chineseDate(post.createdAt))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(LumenTheme.surface)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .background(LumenTheme.canvas)
        .navigationTitle("用户空间")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: user.id) {
            isLoading = true
            loadedPosts = await store.loadPosts(authorID: user.id)
            isLoading = false
        }
    }

    private func chineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

private struct FeedPostCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingDetail = false
    @State private var detailStartsAtComments = false
    @State private var likeBurstToken = 0
    @State private var showingUnfollowConfirmation = false
    @State private var followEffectToken = 0
    @State private var followEffectIsFollowing = false
    let post: PhotoPost
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
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
                            AvatarView(text: post.authorAvatar, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(post.authorName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(LumenTheme.ink)
                                Text(shootingTimeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    if !isOwnPost && !store.isFollowing(post.authorID) {
                        Button {
                            if store.isFollowing(post.authorID) {
                                showingUnfollowConfirmation = true
                            } else {
                                store.toggleFollow(post.authorID)
                                showFollowEffect(isFollowing: true)
                            }
                        } label: {
                            Text("关注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 58, height: 32)
                                .background(
                                    LumenTheme.ink,
                                    in: Capsule()
                                )
                                .overlay {
                                    if followEffectToken > 0 {
                                        FollowActionBurst(isFollowing: followEffectIsFollowing)
                                            .id(followEffectToken)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            PostPhotoView(post: post)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if !post.tags.isEmpty || post.distanceKm != nil {
                            Text(discoveryText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }

                        Text(metadataText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 30)
                    .padding(.bottom, 13)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: openDetail)

            HStack(spacing: 0) {
                Button {
                    let shouldCelebrate = store.isAuthenticated && !store.isLiked(post.id)
                    store.toggleLike(post.id)
                    if shouldCelebrate {
                        likeBurstToken += 1
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: store.isLiked(post.id) ? "heart.fill" : "heart")
                        Text("\(post.likeCount + (store.isLiked(post.id) ? 1 : 0))")
                    }
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if likeBurstToken > 0 {
                            LikeConfettiBurst()
                                .id(likeBurstToken)
                                .allowsHitTesting(false)
                        }
                    }
                }

                Rectangle()
                    .fill(.black.opacity(0.08))
                    .frame(width: 1, height: 18)

                HStack(spacing: 7) {
                    Image(systemName: "bubble")
                    Text("\(post.commentCount)")
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: openComments)

                Rectangle().fill(.black.opacity(0.08)).frame(width: 1, height: 18)
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("\(store.assignments(for: post.id).count)")
                }
                .frame(maxWidth: .infinity)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .frame(height: 46)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.black.opacity(0.07))
                    .frame(height: 0.5)
            }
            .padding(.top, 8)
        }
        .frame(width: cardWidth)
        .background(LumenTheme.surface)
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.045), lineWidth: 0.5)
        }
        .navigationDestination(isPresented: $showingDetail) {
            if post.kind == .original {
                PostDetailView(
                    postID: post.id,
                    scrollToComments: detailStartsAtComments
                )
            } else {
                AssignmentCompareView(assignmentID: post.id)
            }
        }
        .confirmationDialog(
            "确认取消关注 \(post.authorName)？",
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button("取消关注", role: .destructive) {
                store.toggleFollow(post.authorID)
                showFollowEffect(isFollowing: false)
            }
            Button("暂不取消", role: .cancel) {}
        }
    }

    private func openDetail() {
        detailStartsAtComments = false
        showingDetail = true
    }

    private func openComments() {
        detailStartsAtComments = true
        showingDetail = true
    }

    private func showFollowEffect(isFollowing: Bool) {
        followEffectIsFollowing = isFollowing
        followEffectToken += 1
    }

    private var metadataText: String {
        let values = [
            post.metadata.focalLength,
            post.metadata.aperture,
            post.metadata.shutterSpeed,
            post.metadata.iso.isEmpty
                ? ""
                : "ISO \(post.metadata.iso.replacingOccurrences(of: "ISO ", with: ""))"
        ].filter { !$0.isEmpty }
        return values.isEmpty ? "参数未记录" : values.joined(separator: "  ·  ")
    }

    private var discoveryText: String {
        var values = post.tags.prefix(3).map { "#\($0)" }
        if let distance = post.distanceKm {
            values.append(distance < 1
                ? "\(Int((distance * 1000).rounded()))m"
                : String(format: "%.1fkm", distance))
        }
        return values.joined(separator: "  ")
    }

    private var isOwnPost: Bool {
        store.isAuthenticated && post.authorID == store.currentUser.id
    }

    private var shootingTimeText: String {
        guard !post.metadata.capturedAt.isEmpty else {
            return chineseDateTime(post.createdAt)
        }
        let input = post.metadata.capturedAt
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: input)
            ?? ISO8601DateFormatter().date(from: input) {
            return chineseDateTime(date)
        }
        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: input) {
                return chineseDateTime(date)
            }
        }
        return input
    }

    private func chineseDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

private struct FollowActionBurst: View {
    let isFollowing: Bool
    @State private var animated = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: animated ? cos(angle(for: index)) * 30 : 0,
                        y: animated ? sin(angle(for: index)) * 22 : 0
                    )
                    .scaleEffect(animated ? 0.2 : 1)
                    .opacity(animated ? 0 : 1)
            }

            Image(systemName: isFollowing ? "checkmark" : "minus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isFollowing ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    isFollowing ? LumenTheme.accent : Color(.systemGray5),
                    in: Circle()
                )
                .scaleEffect(animated ? 1.35 : 0.45)
                .opacity(animated ? 0 : 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                animated = true
            }
        }
    }

    private func angle(for index: Int) -> CGFloat {
        CGFloat(index) * (.pi * 2 / 8)
    }

    private func color(for index: Int) -> Color {
        if !isFollowing {
            return index.isMultiple(of: 2) ? Color.gray : Color(.systemGray3)
        }
        let colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple]
        return colors[index % colors.count]
    }
}

private struct LikeConfettiBurst: View {
    @State private var exploded = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: index.isMultiple(of: 3) ? 6 : 4, height: index.isMultiple(of: 3) ? 6 : 4)
                    .offset(
                        x: exploded ? cos(angle(for: index)) * radius(for: index) : 0,
                        y: exploded ? sin(angle(for: index)) * radius(for: index) : 0
                    )
                    .scaleEffect(exploded ? 0.25 : 1)
                    .opacity(exploded ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.72)) {
                exploded = true
            }
        }
    }

    private func angle(for index: Int) -> CGFloat {
        CGFloat(index) * (.pi * 2 / 12) - .pi / 2
    }

    private func radius(for index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? 34 : 27
    }

    private func color(for index: Int) -> Color {
        let colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple]
        return colors[index % colors.count]
    }
}
