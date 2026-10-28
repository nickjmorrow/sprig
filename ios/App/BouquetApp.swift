import BouquetCore
import SwiftUI

@main
struct BouquetApp: App {
    @StateObject private var engine: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        Self.applyLaunchSettings()
        #endif
        let store = (try? LocalStore.shared()) ?? (try! LocalStore.inMemory())
        _engine = StateObject(wrappedValue: SyncEngine(store: store, settings: { ServerSettings.load() }))
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.faint)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task(id: scenePhase) {
                    // Pull every minute while the app is open.
                    while scenePhase == .active && !Task.isCancelled {
                        await engine.sync()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
    }

    #if DEBUG
    /// Simulator runs can point at a local server: SIMCTL_CHILD_BOUQUET_SERVER / SIMCTL_CHILD_BOUQUET_TOKEN.
    private static func applyLaunchSettings() {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["BOUQUET_SERVER"], let token = environment["BOUQUET_TOKEN"] else { return }
        ServerSettings(baseURL: URL(string: server), token: token).save()
    }
    #endif
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Inbox", systemImage: "tray") {
                ItemListView(location: .inbox, title: "Bouquet")
            }
            Tab("Feed", systemImage: "dot.radiowaves.up.forward") {
                ItemListView(location: .feed, title: "Feed")
            }
            Tab("Archive", systemImage: "archivebox") {
                ItemListView(location: .archive, title: "Archive")
            }
        }
    }
}
