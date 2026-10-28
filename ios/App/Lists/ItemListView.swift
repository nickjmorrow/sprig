import BouquetCore
import SwiftUI

/// Inbox, Feed or Archive: the filter bar, then the matching items, newest first.
struct ItemListView: View {
    let location: Location
    let title: String

    @EnvironmentObject private var engine: SyncEngine
    @State private var items: [Item] = []
    @State private var topics: [String] = []
    @State private var filter: ItemFilter
    @State private var showingSettings = false
    @AppStorage private var savedFilter: String

    init(location: Location, title: String) {
        self.location = location
        self.title = title
        _savedFilter = AppStorage(wrappedValue: "", "filter.\(location.rawValue)")
        _filter = State(initialValue: ItemFilter(location: location))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        // A hidden link under the row keeps the tap target without List's chevron.
                        ItemRow(item: item)
                            .background { NavigationLink(value: item) { EmptyView() }.opacity(0) }
                            .listRowBackground(Theme.bg)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions(edge: .leading) { leadingSwipe(item) }
                            .swipeActions(edge: .trailing) { trailingSwipe(item) }
                    }
                } header: {
                    FilterBar(filter: $filter, topics: chipTopics, showsFavorites: location == .archive)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .overlay { if items.isEmpty { emptyState } }
            .navigationTitle(title)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .navigationDestination(for: Item.self) { item in ReaderView(itemID: item.id) }
            .toolbar {
                if location == .inbox {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                            .tint(Theme.dim)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .refreshable { await engine.sync() }
            .task(id: filter) { await observe() }
            .onChange(of: filter) { saveFilter() }
            .onChange(of: engine.lastSync) { loadTopics() }
            .onAppear {
                restoreFilter()
                loadTopics()
            }
        }
    }

    private var chipTopics: [String] {
        topics + (items.contains { $0.topics.contains("Other") } || filter.topic == "Other" ? ["Other"] : [])
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: location == .archive ? "archivebox" : "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Theme.faint)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 160)
        .allowsHitTesting(false)
    }

    private var emptyMessage: String {
        if filter.range != .any || filter.topic != nil || filter.favoritesOnly { return "Nothing matches this filter." }
        switch location {
        case .inbox: return "Nothing here.\nShare a link to Bouquet."
        case .feed: return "No new posts.\nAdd feeds in Settings."
        case .archive: return "Nothing archived yet."
        }
    }

    @ViewBuilder
    private func leadingSwipe(_ item: Item) -> some View {
        switch location {
        case .inbox:
            Button { engine.update(item, PatchChanges(location: .archive)) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(Theme.line)
        case .feed:
            Button { engine.update(item, PatchChanges(location: .inbox)) } label: { Label("Keep", systemImage: "tray.and.arrow.down") }
                .tint(Theme.accent)
        case .archive:
            Button { engine.update(item, PatchChanges(location: .inbox)) } label: { Label("Inbox", systemImage: "tray") }
                .tint(Theme.line)
        }
    }

    @ViewBuilder
    private func trailingSwipe(_ item: Item) -> some View {
        switch location {
        case .inbox, .archive:
            Button { engine.update(item, PatchChanges(favorite: !item.favorite)) } label: {
                Label(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.slash" : "star")
            }
            .tint(Theme.accent)
        case .feed:
            Button { engine.update(item, PatchChanges(location: .archive)) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(Theme.line)
        }
    }

    private func observe() async {
        // Keep showing the last good list if the database hiccups, and start watching again.
        while !Task.isCancelled {
            do {
                for try await latest in engine.store.observe(filter) {
                    items = latest
                }
            } catch {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func loadTopics() {
        topics = (try? engine.store.topics()) ?? []
    }

    private func restoreFilter() {
        guard let data = savedFilter.data(using: .utf8),
              let saved = try? JSONDecoder().decode(ItemFilter.self, from: data),
              saved.location == location else { return }
        filter = saved
    }

    private func saveFilter() {
        savedFilter = String(decoding: (try? JSONEncoder().encode(filter)) ?? Data(), as: UTF8.self)
    }
}
