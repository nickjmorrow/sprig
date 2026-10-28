import Foundation

/// Keeps the phone's copy and the server in step: sends queued shares and changes, then pulls
/// everything that changed since the last pull.
@MainActor
public final class SyncEngine: ObservableObject {
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isSyncing = false

    public let store: LocalStore
    private let settings: () -> ServerSettings
    private let session: URLSession
    private var pendingSync: Task<Void, Never>?

    public init(store: LocalStore, settings: @escaping () -> ServerSettings, session: URLSession = .shared) {
        self.store = store
        self.settings = settings
        self.session = session
    }

    public var api: APIClient { APIClient(settings: settings(), session: session) }

    public func sync() async {
        guard settings().isConfigured else {
            lastError = APIError.notConfigured.errorDescription
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await sendShares()
            try await sendPatches()
            try await pullChanges()
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pulls without sending first; still keeps local changes that haven't reached the server.
    public func pull() async {
        do {
            try await pullChanges()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Syncs a moment from now, so a burst of changes goes out together.
    public func syncSoon(after delay: Duration = .seconds(1)) {
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    public func update(_ item: Item, _ changes: PatchChanges) {
        do {
            try store.change(item.id, changes)
            syncSoon()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sendShares() async throws {
        for share in try store.pendingShares() {
            guard let url = URL(string: share.url) else {
                try store.removeShare(share)
                continue
            }
            let item = try await api.createItem(url: url)
            try store.upsert([item])
            try store.removeShare(share)
        }
    }

    private func sendPatches() async throws {
        for patch in try store.pendingPatches() {
            do {
                _ = try await api.patch(id: patch.itemId, changes: patch.changes, at: patch.at)
            } catch APIError.http(status: 404, _) {
                // The item is gone on the server; the pull removes it here too.
            }
            try store.removePatch(patch)
        }
    }

    private func pullChanges() async throws {
        let changes = try await api.changes(since: try store.lastSeq())
        let pending = try store.pendingPatches()
        var live: [Item] = []
        var deletedIDs: [String] = []
        for var item in changes.items {
            if item.deleted {
                deletedIDs.append(item.id)
                continue
            }
            for patch in pending where patch.itemId == item.id {
                patch.changes.apply(to: &item)
            }
            live.append(item)
        }
        try store.upsert(live)
        try store.delete(ids: deletedIDs)
        try store.setTopics(changes.topics)
        try store.setFeeds(changes.feeds)
        try store.setLastSeq(changes.seq)
    }
}
