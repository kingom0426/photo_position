import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @State private var tabRootIDs = Array(repeating: UUID(), count: 5)

    var body: some View {
        TabView(selection: $store.selectedTab) {
            HomeView()
                .id(tabRootIDs[0])
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            MapScreen()
                .id(tabRootIDs[1])
                .tabItem { Label("地图", systemImage: "map") }
                .tag(1)
            NavigationStack {
                if store.isAuthenticated {
                    PublishView()
                } else {
                    GuestGateView(
                        title: "登录后发布作品",
                        description: "浏览无需登录，发布作品或作业需要账号。"
                    )
                }
            }
                .id(tabRootIDs[2])
                .tabItem {
                    Label {
                        Text("发布")
                    } icon: {
                        Image(uiImage: Self.publishTabIcon)
                    }
                }
                .tag(2)
            PlansView()
                .id(tabRootIDs[3])
                .tabItem { Label("计划", systemImage: "bookmark") }
                .tag(3)
            ProfileView()
                .id(tabRootIDs[4])
                .tabItem { Label("我的", systemImage: "person") }
                .tag(4)
        }
        .tint(LumenTheme.ink)
        .task {
            locationService.requestCurrentLocation()
            await store.start()
        }
        .onChange(of: locationService.city) { _, city in
            if let city, !city.isEmpty { store.updateCurrentCity(city) }
        }
        .onChange(of: store.selectedTab) { _, selectedTab in
            guard tabRootIDs.indices.contains(selectedTab) else { return }
            tabRootIDs[selectedTab] = UUID()
        }
        .onChange(of: store.mapFocusPostID) { _, postID in
            guard postID != nil else { return }
            tabRootIDs[1] = UUID()
        }
        .sheet(isPresented: $store.showingAuthentication) {
            AuthView().environmentObject(store)
        }
    }

    // Preserve the accent even when the native tab bar renders unselected items gray.
    private static let publishTabIcon: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.image { _ in
            UIColor(LumenTheme.accent).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 32, height: 32), cornerRadius: 10).fill()
            let plus = UIBezierPath()
            plus.move(to: CGPoint(x: 16, y: 8))
            plus.addLine(to: CGPoint(x: 16, y: 24))
            plus.move(to: CGPoint(x: 8, y: 16))
            plus.addLine(to: CGPoint(x: 24, y: 16))
            plus.lineWidth = 3
            plus.lineCapStyle = .round
            UIColor.white.setStroke()
            plus.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }()
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore())
            .environmentObject(LocationService())
    }
}
