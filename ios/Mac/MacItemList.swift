import SprigCore
import SwiftUI

/// The middle column: filter bar, then the location's stories, newest first.
struct MacItemList: View {
    let location: Location
    @Binding var selection: Item.ID?
    @Binding var items: [Item]
    @Binding var isSearchFocused: Bool

    @EnvironmentObject private var engine: SyncEngine
    @State private var topics: [String] = []
    @State private var filter: ItemFilter
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool
    @AppStorage private var savedFilter: String

    init(location: Location, selection: Binding<Item.ID?>, items: Binding<[Item]>, isSearchFocused: Binding<Bool>) {
        self.location = location
        _selection = selection
        _items = items
        _isSearchFocused = isSearchFocused
        _savedFilter = AppStorage(wrappedValue: "", "filter.\(location.rawValue)")
        _filter = State(initialValue: ItemFilter(location: location))
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                ItemRow(item: item, searchTerms: filter.searchTerms)
                    .tag(item.id)
                    .contextMenu { menu(for: item) }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                searchField
                FilterBar(filter: $filter, topics: chipTopics, showsFavorites: location == .archive)
            }
            .background(.bar)
        }
        .overlay { if items.isEmpty { emptyState } }
        .safeAreaInset(edge: .bottom, spacing: 0) { UndoArchiveBar() }
        .navigationTitle(title)
        .onChange(of: searchFieldFocus) { isSearchFocused = searchFieldFocus }
        .task(id: searchText) { await applySearch() }
        .task(id: filter) { await observe() }
        .onChange(of: filter) { saveFilter() }
        .onChange(of: items.map(\.id)) { old, new in advanceSelection(old: old, new: new) }
        .onChange(of: engine.lastSync) { loadTopics() }
        .onAppear {
            restoreFilter()
            loadTopics()
        }
    }

    /// Sits right above the list it narrows. ⌘F jumps here; Escape clears it and goes back to the list.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField("Search \(title)", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocus)
                .onExitCommand {
                    searchText = ""
                    searchFieldFocus = false
                }
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.dim)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background {
            Button("Find") { searchFieldFocus = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }

    private var title: String {
        switch location {
        case .inbox: "Inbox"
        case .feed: "Feed"
        case .archive: "Archive"
        }
    }

    private var chipTopics: [String] {
        topics + (items.contains { $0.topics.contains("Other") } || filter.topic == "Other" ? ["Other"] : [])
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filter.isSearching ? "No Results" : title, systemImage: filter.isSearching ? "magnifyingglass" : emptySymbol)
        } description: {
            Text(emptyMessage)
        }
        .allowsHitTesting(false)
    }

    private var emptySymbol: String {
        switch location {
        case .inbox: "tray"
        case .feed: "dot.radiowaves.up.forward"
        case .archive: "archivebox"
        }
    }

    private var emptyMessage: String {
        if filter.isSearching { return "No stories in this tab match your search." }
        if filter.range != .any || filter.topic != nil || filter.favoritesOnly { return "Nothing matches this filter." }
        switch location {
        case .inbox: return "Share a link to Sprig to save it here."
        case .feed: return "No new posts. Add feeds in Settings."
        case .archive: return "Stories you archive land here."
        }
    }

    @ViewBuilder
    private func menu(for item: Item) -> some View {
        switch location {
        case .inbox:
            Button("Archive", systemImage: "archivebox") { engine.archive(item) }
        case .feed:
            Button("Keep in Inbox", systemImage: "tray.and.arrow.down") { engine.update(item, PatchChanges(location: .inbox)) }
            Button("Archive", systemImage: "archivebox") { engine.archive(item) }
        case .archive:
            Button("Move to Inbox", systemImage: "tray") { engine.update(item, PatchChanges(location: .inbox)) }
        }
        Button(item.favorite ? "Unstar" : "Star", systemImage: item.favorite ? "star.slash" : "star") {
            engine.update(item, PatchChanges(favorite: !item.favorite))
        }
        Button("Mark as Unread", systemImage: "circlebadge") { engine.update(item, PatchChanges(progress: 0)) }
        Button("Open Original", systemImage: "safari") {
            if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
        }
    }

    /// When the selected story is archived or moved, select the one after it. A story that only
    /// dropped out because the filter changed just clears the selection.
    private func advanceSelection(old: [String], new: [String]) {
        guard let selected = selection, !new.contains(selected) else { return }
        let moved = (try? engine.store.item(id: selected)).flatMap { $0 }.map { $0.location != location || $0.deleted } ?? true
        selection = moved ? nextSelection(after: selected, old: old, new: new) : nil
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
