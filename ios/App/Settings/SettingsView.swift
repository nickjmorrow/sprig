import SprigCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var hostHeader = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-server:8454", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token", text: $token)
                    TextField("Host header (optional)", text: $hostHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("Make a token on Edgar with: sprig token add iphone")
                }
                Section {
                    Button("Sync now") { save(); Task { await engine.sync() } }
                    if engine.isSyncing {
                        ProgressView()
                    } else if let error = engine.lastError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    } else if let lastSync = engine.lastSync {
                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(Theme.dim).font(.footnote)
                    }
                }
                Section {
                    NavigationLink("Topics") { TopicsEditor() }
                    NavigationLink("Feeds") { FeedsEditor() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                        Task { await engine.sync() }
                    }
                }
            }
            .onAppear(perform: load)
        }
        .presentationBackground(Theme.bg)
    }

    private func load() {
        let settings = ServerSettings.load()
        address = settings.baseURL?.absoluteString ?? ""
        token = settings.token
        hostHeader = settings.hostHeader ?? ""
    }

    private func save() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        ServerSettings(
            baseURL: trimmed.isEmpty ? nil : URL(string: trimmed),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            hostHeader: hostHeader.isEmpty ? nil : hostHeader
        ).save()
    }
}
