import SwiftUI
import MapKit
import CoreLocation

struct MapScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedPostID: UUID?
    @State private var isLoadingPosts = true
    @State private var selectedAddress = ""
    @State private var addressLookupToken = UUID()
    @State private var didCenterOnUser = false
    @State private var awaitingCurrentLocation = false
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.8617, longitude: 104.1954), span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 28))
    )

    private var mappedPosts: [PhotoPost] {
        store.originals.filter { $0.location.coordinate != nil }
    }

    private var selectedPost: PhotoPost? {
        selectedPostID.flatMap { store.post(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(mappedPosts) { post in
                        if let coordinate = post.location.coordinate {
                            Annotation(annotationTitle(for: post), coordinate: coordinate) {
                                Button {
                                    select(post, coordinate: coordinate)
                                    withAnimation { camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))) }
                                } label: {
                                    mapMarker(for: post)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onChange(of: locationService.coordinate?.latitude) { _, _ in
                    if awaitingCurrentLocation, let coordinate = locationService.coordinate {
                        awaitingCurrentLocation = false
                        centerMap(on: coordinate)
                    } else {
                        centerOnUserIfNeeded()
                    }
                }

                VStack {
                    if mappedPosts.isEmpty {
                        VStack(spacing: 5) {
                            Text(isLoadingPosts ? "正在加载拍摄地点…" : "还没有公开拍摄地点的作品")
                                .font(.subheadline.weight(.semibold))
                            if !isLoadingPosts {
                                Text("在发布或编辑作品时选择并公开拍摄地点，即可显示作品标记。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                VStack(alignment: .trailing, spacing: 12) {
                Button {
                    centerOnCurrentLocation()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LumenTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回到当前位置")
                .frame(maxWidth: .infinity, alignment: .trailing)

                if let selectedPost {
                    NavigationLink(destination: PostDetailView(postID: selectedPost.id)) {
                        HStack(spacing: 13) {
                            PostPhotoView(post: selectedPost)
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(selectedPost.title)
                                    .font(.headline)
                                    .foregroundStyle(LumenTheme.ink)
                                    .lineLimit(1)
                                Text("作者：\(selectedPost.authorName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Label(displayAddress(for: selectedPost), systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Label(shootingTime(for: selectedPost), systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(16)
            }
            .navigationTitle("地图找机位")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                locationService.requestCurrentLocation()
                if !focusRequestedPostIfNeeded() {
                    centerOnUserIfNeeded()
                }
                _ = await store.loadFeed(feed: "recommended", latitude: nil, longitude: nil, radiusKm: nil, filters: [])
                isLoadingPosts = false
                _ = focusRequestedPostIfNeeded()
            }
        }
    }

    @discardableResult
    private func focusRequestedPostIfNeeded() -> Bool {
        guard let postID = store.mapFocusPostID,
              let post = store.post(id: postID),
              let coordinate = post.location.coordinate else { return false }
        select(post, coordinate: coordinate)
        didCenterOnUser = true
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        ))
        store.consumeMapFocus()
        return true
    }

    private func select(_ post: PhotoPost, coordinate: CLLocationCoordinate2D) {
        selectedPostID = post.id
        let storedAddress = post.location.displayAddress
        if !storedAddress.isEmpty {
            selectedAddress = storedAddress
            return
        }

        selectedAddress = ""
        let token = UUID()
        addressLookupToken = token
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "zh_CN")
        ) { placemarks, _ in
            DispatchQueue.main.async {
                guard addressLookupToken == token,
                      let placemark = placemarks?.first else { return }
                selectedAddress = LocationService.address(from: placemark)
            }
        }
    }

    private func displayAddress(for post: PhotoPost) -> String {
        if post.location.privacy == .approximate { return "模糊区域 · 非精确机位" }
        if !selectedAddress.isEmpty {
            return selectedAddress
        }
        if !post.location.displayAddress.isEmpty {
            return post.location.displayAddress
        }
        return "正在获取具体地址…"
    }

    private func annotationTitle(for post: PhotoPost) -> String {
        post.title
    }

    private func mapMarker(for post: PhotoPost) -> some View {
        let isSelected = selectedPostID == post.id
        let likes = post.likeCount + (store.isLiked(post.id) ? 1 : 0)
        return VStack(spacing: 3) {
            PostPhotoView(post: post)
                .frame(width: isSelected ? 58 : 50, height: isSelected ? 58 : 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? LumenTheme.accent : .white, lineWidth: isSelected ? 3 : 2.5)
                }
            HStack(spacing: 3) {
                Text(post.title)
                    .lineLimit(1)
                if likes > 0 {
                    Text("🔥 \(likes)")
                        .opacity(min(1, 0.45 + Double(likes) * 0.1))
                        .scaleEffect(min(1.2, 0.94 + CGFloat(likes) * 0.025))
                }
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LumenTheme.ink)
                .frame(maxWidth: 132)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .shadow(color: .black.opacity(0.2), radius: 7, y: 4)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private func shootingTime(for post: PhotoPost) -> String {
        let rawValue = post.metadata.capturedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawValue.isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: rawValue)
                ?? ISO8601DateFormatter().date(from: rawValue) {
                return chineseDateTime(date)
            }

            for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
                let parser = DateFormatter()
                parser.locale = Locale(identifier: "zh_CN")
                parser.dateFormat = format
                if let date = parser.date(from: rawValue) {
                    return chineseDateTime(date)
                }
            }
        }
        return chineseDateTime(post.createdAt)
    }

    private func chineseDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func centerOnUserIfNeeded() {
        guard !didCenterOnUser, let coordinate = locationService.coordinate else { return }
        didCenterOnUser = true
        centerMap(on: coordinate)
    }

    private func centerOnCurrentLocation() {
        awaitingCurrentLocation = true
        locationService.requestCurrentLocation()
        if let coordinate = locationService.coordinate {
            awaitingCurrentLocation = false
            centerMap(on: coordinate)
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        didCenterOnUser = true
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            ))
        }
    }
}
