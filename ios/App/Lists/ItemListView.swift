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
    /// False until the first read from the database, so a full list never flashes its empty state.
    @State private var hasLoaded = false
    @FocusState private var isSearching: Bool
    @AppStorage private var savedFilter: String

    init(location: Location, title: String, path: Binding<[Item]>) {
        self.location = location
        self.title = title
        _path = path
        _savedFilter = AppStorage(wrappedValue: "", "filter.\(location.rawValue)")
        // Restored here, not after appearing: the bar would otherwise draw once with the defaults and jump.
        _filter = State(initialValue: Self.savedFilter(for: location))
    }

    static func savedFilter(for location: Location) -> ItemFilter {
        guard let data = UserDefaults.standard.string(forKey: "filter.\(location.rawValue)")?.data(using: .utf8),
              var saved = try? JSONDecoder().decode(ItemFilter.self, from: data),
              saved.location == location else { return ItemFilter(location: location) }
        saved.query = ""
        return saved
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(items) { item in
                    // A hidden link under the row keeps the tap target without List's chevron.
                    ItemRow(item: item, searchTerms: filter.searchTerms)
                        .background { NavigationLink(value: item) { EmptyView() }.opacity(0) }
                        .contextMenu { Button("Copy Link", systemImage: "link") { copyLink(to: item) } }
                        .swipeActions(edge: .leading) { leadingSwipe(item) }
                        .swipeActions(edge: .trailing) { trailingSwipe(item) }
                }
            }
            .listStyle(.plain)
            // One fixed header instead of a navigation bar: search and Settings, then the filters.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    searchRow
                    FilterBar(filter: $filter, topics: chipTopics, showsFavorites: location == .archive)
                }
                .padding(.top, 6)
                .background(Theme.bg)
            }
            .overlay { if hasLoaded && items.isEmpty { emptyState } }
            .navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: searchText) { await applySearch() }
            .navigationDestination(for: Item.self) { item in ReaderView(itemID: item.id) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .refreshable { await engine.sync() }
            .task(id: filter) { await observe() }
            .onChange(of: filter) { saveFilter() }
            .onChange(of: engine.lastSync) { loadTopics() }
            .onAppear {
                // Read once before the first frame, so switching tabs shows the list at once.
                loadTopics()
                if !hasLoaded {
                    items = (try? engine.store.items(filter)) ?? []
                    hasLoaded = true
                }
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Search \(title)", text: $searchText)
                    .focused($isSearching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { searchText = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Theme.control))
            if isSearching {
                Button("Cancel") {
                    searchText = ""
                    isSearching = false
                }
            } else {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.2), value: isSearching)
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

    private func saveFilter() {
        savedFilter = String(decoding: (try? JSONEncoder().encode(filter)) ?? Data(), as: UTF8.self)
    }
}
