import BouquetCore
import SwiftUI

@main
struct BouquetMacApp: App {
    @StateObject private var engine: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        Self.applyLaunchSettings()
        #endif
        let store = (try? Self.openStore()) ?? (try! LocalStore.inMemory())
        _engine = StateObject(wrappedValue: SyncEngine(store: store, settings: { ServerSettings.load(from: .standard) }))
    }

    var body: some Scene {
        Window("Bouquet", id: "main") {
            MacRootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 900, minHeight: 560)
                .task(id: scenePhase) {
                    // Pull every minute while the window is in front.
                    while scenePhase == .active && !Task.isCancelled {
                        await engine.sync()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            StoryCommands()
            CommandGroup(after: .toolbar) {
                Button("Sync Now") { Task { await engine.sync() } }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            MacSettingsView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    /// Application Support/Bouquet/bouquet.sqlite, inside the sandbox container.
    private static func openStore() throws -> LocalStore {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Bouquet", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try LocalStore.onDisk(path: folder.appending(path: "bouquet.sqlite").path())
    }

    #if DEBUG
    /// A local server for development: run with BOUQUET_SERVER and BOUQUET_TOKEN in the environment.
    private static func applyLaunchSettings() {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["BOUQUET_SERVER"], let token = environment["BOUQUET_TOKEN"] else { return }
        ServerSettings(baseURL: URL(string: server), token: token).save(to: .standard)
    }
    #endif
}
