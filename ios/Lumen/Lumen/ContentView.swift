import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            MapScreen()
                .tabItem { Label("地图", systemImage: "map") }
                .tag(1)
            NavigationStack { PublishView() }
                .tabItem { Label("发布", systemImage: "plus.app.fill") }
                .tag(2)
            PlansView()
                .tabItem { Label("计划", systemImage: "bookmark") }
                .tag(3)
            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(4)
        }
        .tint(LumenTheme.ink)
        .task { await store.sync() }
    }
}

#Preview {
    ContentView().environmentObject(AppStore())
}
