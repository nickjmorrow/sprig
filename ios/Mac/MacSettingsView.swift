import SprigCore
import SwiftUI

/// ⌘, : the server, topics and feeds.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            ServerTab()
                .tabItem { Label("Server", systemImage: "server.rack") }
            NavigationStack { TopicsEditor() }
                .tabItem { Label("Topics", systemImage: "tag") }
            NavigationStack { FeedsEditor() }
                .tabItem { Label("Feeds", systemImage: "dot.radiowaves.up.forward") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ServerTab: View {
    @EnvironmentObject private var engine: SyncEngine
    @State private var address = ""
    @State private var token = ""
    @State private var hostHeader = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("https://your-server:8454"))
                    .autocorrectionDisabled()
                SecureField("Token", text: $token)
                TextField("Host header", text: $hostHeader, prompt: Text("optional"))
                    .autocorrectionDisabled()
            } footer: {
                Text("Make a token on Edgar with: sprig token add roland")
            }
            Section {
                Button("Sync Now") { save(); Task { await engine.sync() } }
                if engine.isSyncing {
                    ProgressView().controlSize(.small)
                } else if let error = engine.lastError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else if let lastSync = engine.lastSync {
                    Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(.secondary).font(.footnote)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: address) { save() }
        .onChange(of: token) { save() }
        .onChange(of: hostHeader) { save() }
        .onDisappear { Task { await engine.sync() } }
    }

    private func load() {
        let settings = ServerSettings.load(from: .standard)
        address = settings.baseURL?.absoluteString ?? ""
        token = settings.token
        hostHeader = settings.hostHeader ?? ""
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        ServerSettings(
            baseURL: trimmed.isEmpty ? nil : URL(string: trimmed),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            hostHeader: hostHeader.isEmpty ? nil : hostHeader
        ).save(to: .standard)
    }
}
