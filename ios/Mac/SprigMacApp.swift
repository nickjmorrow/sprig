import SprigCore
import SwiftUI

@main
struct SprigMacApp: App {
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
        Window("Sprig", id: "main") {
            MacRootView()
                .environmentObject(engine)
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
                .tint(Theme.accent)
        }
    }

    /// Application Support/Sprig/sprig.sqlite, inside the sandbox container.
    private static func openStore() throws -> LocalStore {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Sprig", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try LocalStore.onDisk(path: folder.appending(path: "sprig.sqlite").path())
    }

    #if DEBUG
    /// A local server for development: run with SPRIG_SERVER and SPRIG_TOKEN in the environment.
    private static func applyLaunchSettings() {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["SPRIG_SERVER"], let token = environment["SPRIG_TOKEN"] else { return }
        ServerSettings(baseURL: URL(string: server), token: token).save(to: .standard)
    }
    #endif
}
