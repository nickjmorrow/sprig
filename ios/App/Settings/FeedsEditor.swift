import BouquetCore
import SwiftUI

struct FeedsEditor: View {
    @EnvironmentObject private var engine: SyncEngine
    @State private var feeds: [Feed] = []
    @State private var newURL = ""
    @State private var error: String?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Feed address", text: $newURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add", action: add).disabled(URL(string: newURL)?.host() == nil)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                ForEach(feeds) { feed in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feed.title ?? feed.url).foregroundStyle(Theme.text)
                        Text(feed.lastError ?? feed.site ?? feed.url)
                            .font(.caption)
                            .foregroundStyle(feed.lastError == nil ? Theme.dim : .red)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Deleting a feed removes its posts you didn't keep or star.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Feeds")
        .onAppear(perform: load)
        .onChange(of: engine.lastSync) { load() }
    }

    private func load() {
        feeds = ((try? engine.store.feeds()) ?? []).sorted { ($0.title ?? $0.url) < ($1.title ?? $1.url) }
    }

    private func add() {
        guard let url = URL(string: newURL.trimmingCharacters(in: .whitespaces)) else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                _ = try await engine.api.addFeed(url: url)
                newURL = ""
                error = nil
                await engine.sync()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        Task {
            do {
                for feed in doomed { try await engine.api.deleteFeed(id: feed.id) }
                await engine.sync()
            } catch {
                self.error = error.localizedDescription
                load()
            }
        }
    }
}
