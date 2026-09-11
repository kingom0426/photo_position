import SwiftUI

@main
struct LumenApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(locationService)
                .preferredColorScheme(.light)
        }
    }
}
