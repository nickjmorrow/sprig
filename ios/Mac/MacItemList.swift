import BouquetCore
import SwiftUI

/// The middle column: filter bar, then the location's stories, newest first.
struct MacItemList: View {
    let location: Location
    @Binding var selection: Item.ID?
    @Binding var items: [Item]

    @EnvironmentObject private var engine: SyncEngine
    @State private var topics: [String] = []
    @State private var filter: ItemFilter
    @AppStorage private var savedFilter: String

    init(location: Location, selection: Binding<Item.ID?>, items: Binding<[Item]>) {
        self.location = location
        _selection = selection
        _items = items
        _savedFilter = AppStorage(wrappedValue: "", "filter.\(location.rawValue)")
        _filter = State(initialValue: ItemFilter(location: location))
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                ItemRow(item: item)
                    .tag(item.id)
                    .listRowBackground(Theme.bg)
                    .listRowSeparatorTint(Theme.line)
                    .contextMenu { menu(for: item) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(filter: $filter, topics: chipTopics, showsFavorites: location == .archive)
        }
        .overlay { if items.isEmpty { emptyState } }
        .navigationTitle(title)
        .task(id: filter) { await observe() }
        .onChange(of: filter) { saveFilter() }
        .onChange(of: items.map(\.id)) { old, new in advanceSelection(old: old, new: new) }
        .onChange(of: engine.lastSync) { loadTopics() }
        .onAppear {
            restoreFilter()
            loadTopics()
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
        VStack(spacing: 8) {
            Image(systemName: location == .archive ? "archivebox" : "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Theme.faint)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
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
    private func menu(for item: Item) -> some View {
        switch location {
        case .inbox:
            Button("Archive", systemImage: "archivebox") { engine.update(item, PatchChanges(location: .archive)) }
        case .feed:
            Button("Keep in Inbox", systemImage: "tray.and.arrow.down") { engine.update(item, PatchChanges(location: .inbox)) }
            Button("Archive", systemImage: "archivebox") { engine.update(item, PatchChanges(location: .archive)) }
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
