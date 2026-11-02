import BouquetCore
import SwiftUI
import WidgetKit

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
                .onChange(of: engine.lastSync) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: scenePhase) {
                    // Catches changes made offline, which don't move lastSync.
                    if scenePhase == .background { WidgetCenter.shared.reloadAllTimelines() }
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
    @EnvironmentObject private var engine: SyncEngine
    @State private var tab = Location.inbox
    @State private var paths: [Location: [Item]] = [:]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                ItemListView(location: .inbox, title: "Bouquet", path: path(.inbox))
            }
            Tab("Feed", systemImage: "dot.radiowaves.up.forward", value: .feed) {
                ItemListView(location: .feed, title: "Feed", path: path(.feed))
            }
            Tab("Archive", systemImage: "archivebox", value: .archive) {
                ItemListView(location: .archive, title: "Archive", path: path(.archive))
            }
        }
        .onOpenURL(perform: open)
    }

    private func path(_ location: Location) -> Binding<[Item]> {
        Binding { paths[location, default: []] } set: { paths[location] = $0 }
    }

    /// bouquet://item/<id>, from the widget: opens that item in the reader.
    private func open(_ url: URL) {
        guard url.scheme == "bouquet", url.host() == "item",
              let id = url.pathComponents.last, let item = try? engine.store.item(id: id) else { return }
        tab = item.location
        paths[item.location] = [item]
    }
}
