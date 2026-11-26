import SprigCore
import SwiftUI

/// Sidebar (Inbox, Feed, Archive), the story list, and the reader.
struct MacRootView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.openSettings) private var openSettings
    @State private var location: Location? = .inbox
    @State private var selectedID: Item.ID?
    @State private var items: [Item] = []
    @State private var isSearchFocused = false
    @State private var isConfigured = ServerSettings.load(from: .standard).isConfigured
    @AppStorage("reader.fontStep") private var fontStep = 0

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            MacItemList(location: location ?? .inbox, selection: $selectedID, items: $items, isSearchFocused: $isSearchFocused)
                .id(location)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 520)
        } detail: {
            detail
        }
        // The Story menu's single-key shortcuts would otherwise fire while typing a search.
        .focusedSceneValue(\.storyActions, isSearchFocused ? nil : actions)
        .onChange(of: location) { selectedID = nil }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            isConfigured = ServerSettings.load(from: .standard).isConfigured
        }
    }

    private var sidebar: some View {
        List(selection: $location) {
            SidebarRow(title: "Inbox", systemImage: "tray", location: .inbox, countsUnread: true).tag(Location.inbox)
            SidebarRow(title: "Feed", systemImage: "dot.radiowaves.up.forward", location: .feed, countsUnread: true).tag(Location.feed)
            SidebarRow(title: "Archive", systemImage: "archivebox", location: .archive, countsUnread: false).tag(Location.archive)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        .safeAreaInset(edge: .bottom) { syncStatus }
    }

    private var syncStatus: some View {
        Group {
            if engine.isSyncing {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }
            } else if let error = engine.lastError {
                Text(error).foregroundStyle(.red)
            } else if let lastSync = engine.lastSync {
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.dim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var detail: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !isConfigured {
                VStack(spacing: 12) {
                    Text("Connect to your Sprig server").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Add its address and a token in Settings.").foregroundStyle(Theme.dim)
                    Button("Open Settings") { openSettings() }
                }
            } else if let selectedID {
                MacReaderView(itemID: selectedID)
                    .id(selectedID)
            } else {
                ContentUnavailableView("No Story Selected", systemImage: "doc.plaintext", description: Text("Pick a story from the list."))
            }
        }
    }

    // MARK: Story menu

    private var actions: StoryActions? {
        guard let item = items.first(where: { $0.id == selectedID }) else { return nil }
        let engine = engine
        let archiveItem: Action = { engine.archive(item) }
        let inboxItem: Action = { engine.update(item, PatchChanges(location: .inbox)) }
        let archive: Action? = item.location == .archive ? nil : archiveItem
        let moveToInbox: Action? = item.location == .inbox ? nil : inboxItem
        let toggleStar: Action = { engine.update(item, PatchChanges(favorite: !item.favorite)) }
        let markUnread: Action = { engine.update(item, PatchChanges(progress: 0)) }
        let openOriginal: Action = { if let url = URL(string: item.url) { NSWorkspace.shared.open(url) } }
        let copy: Action = { copyLink(to: item) }
        let next: Action = { step(1) }
        let previous: Action = { step(-1) }
        return StoryActions(
            item: item, archive: archive, moveToInbox: moveToInbox, toggleStar: toggleStar,
            markUnread: markUnread, openOriginal: openOriginal, copyLink: copy, next: next, previous: previous
        )
    }

    private func step(_ offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        let target = index + offset
        if items.indices.contains(target) { selectedID = items[target].id }
    }
}

/// A sidebar entry, with a count of the stories you haven't finished where that means something.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let location: Location
    let countsUnread: Bool
    @EnvironmentObject private var engine: SyncEngine
    @State private var count = 0

    var body: some View {
        Label(title, systemImage: systemImage)
            .badge(count)
            .task { if countsUnread { await observe() } }
    }

    private func observe() async {
        while !Task.isCancelled {
            do {
                for try await items in engine.store.observe(ItemFilter(location: location)) {
                    count = items.filter { !$0.isFinished }.count
                }
            } catch {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
