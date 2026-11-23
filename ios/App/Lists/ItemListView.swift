import SprigCore
import SwiftUI

/// Inbox, Feed or Archive: the filter bar, then the matching items, newest first.
struct ItemListView: View {
    let location: Location
    let title: String
    @Binding var path: [Item]

    @EnvironmentObject private var engine: SyncEngine
    @State private var items: [Item] = []
    @State private var topics: [String] = []
    @State private var filter: ItemFilter
    @State private var searchText = ""
    @State private var showingSettings = false
    @AppStorage private var savedFilter: String

    init(location: Location, title: String, path: Binding<[Item]>) {
        self.location = location
        self.title = title
        _path = path
        _savedFilter = AppStorage(wrappedValue: "", "filter.\(location.rawValue)")
        _filter = State(initialValue: ItemFilter(location: location))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(items) { item in
                        // A hidden link under the row keeps the tap target without List's chevron.
                        ItemRow(item: item, searchTerms: filter.searchTerms)
                            .background { NavigationLink(value: item) { EmptyView() }.opacity(0) }
                            .swipeActions(edge: .leading) { leadingSwipe(item) }
                            .swipeActions(edge: .trailing) { trailingSwipe(item) }
                    }
                } header: {
                    FilterBar(filter: $filter, topics: chipTopics, showsFavorites: location == .archive)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                        .background(Theme.bg)
                }
            }
            .listStyle(.plain)
            .overlay { if items.isEmpty { emptyState } }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Search")
            .task(id: searchText) { await applySearch() }
            .navigationDestination(for: Item.self) { item in ReaderView(itemID: item.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
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
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyMessage)
        }
        .padding(.top, 180)
        .allowsHitTesting(false)
    }

    private var isFiltered: Bool {
        filter.isSearching || filter.range != .any || filter.topic != nil || filter.favoritesOnly
    }

    private var emptySymbol: String {
        if isFiltered { return filter.isSearching ? "magnifyingglass" : "line.3.horizontal.decrease" }
        switch location {
        case .inbox: return "tray"
        case .feed: return "dot.radiowaves.up.forward"
        case .archive: return "archivebox"
        }
    }

    private var emptyTitle: String {
        if filter.isSearching { return "No Results" }
        if isFiltered { return "Nothing Matches" }
        switch location {
        case .inbox: return "Inbox Zero"
        case .feed: return "All Caught Up"
        case .archive: return "Nothing Archived"
        }
    }

    private var emptyMessage: String {
        if filter.isSearching { return "No stories in this tab match your search." }
        if isFiltered { return "Try another reading time or topic." }
        switch location {
        case .inbox: return "Share a link to Sprig to save it here."
        case .feed: return "No new posts. Add feeds in Settings."
        case .archive: return "Stories you archive land here."
        }
    }

    @ViewBuilder
    private func leadingSwipe(_ item: Item) -> some View {
        switch location {
        case .inbox:
            Button { engine.archive(item) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(.indigo)
        case .feed:
            Button { engine.update(item, PatchChanges(location: .inbox)) } label: { Label("Keep", systemImage: "tray.and.arrow.down") }
                .tint(Theme.accent)
        case .archive:
            Button { engine.update(item, PatchChanges(location: .inbox)) } label: { Label("Inbox", systemImage: "tray") }
                .tint(.blue)
        }
    }

    @ViewBuilder
    private func trailingSwipe(_ item: Item) -> some View {
        switch location {
        case .inbox, .archive:
            Button { engine.update(item, PatchChanges(favorite: !item.favorite)) } label: {
                Label(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.slash" : "star")
            }
            .tint(Theme.star)
        case .feed:
            Button { engine.archive(item) } label: { Label("Archive", systemImage: "archivebox") }
                .tint(.indigo)
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

    /// Waits for a pause in typing, so a fast typist doesn't search the whole tab on every key.
    private func applySearch() async {
        if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        guard !Task.isCancelled else { return }
        filter.query = searchText
    }

    private func loadTopics() {
        topics = (try? engine.store.topics()) ?? []
    }

    private func restoreFilter() {
        guard let data = savedFilter.data(using: .utf8),
              var saved = try? JSONDecoder().decode(ItemFilter.self, from: data),
              saved.location == location else { return }
        saved.query = filter.query
        filter = saved
    }

    private func saveFilter() {
        savedFilter = String(decoding: (try? JSONEncoder().encode(filter)) ?? Data(), as: UTF8.self)
    }
}
