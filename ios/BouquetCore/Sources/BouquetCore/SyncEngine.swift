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
        // Each phase runs even if an earlier one failed, so one stuck send can't stop the pull.
        var problems: [String] = []
        for phase in [sendShares, sendPatches] {
            do {
                problems += try await phase()
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        do {
            try await pullChanges()
            lastSync = Date()
        } catch {
            problems.append(error.localizedDescription)
        }
        lastError = problems.first
    }

    /// The server will never accept this request as sent (bad input, unknown item): drop it rather
    /// than retry forever. Auth, timeouts, rate limits and server errors are worth retrying.
    static func isPermanent(_ error: Error) -> Bool {
        guard case let APIError.http(status, _) = error else { return false }
        return (400..<500).contains(status) && ![401, 408, 429].contains(status)
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

    /// Returns why any were dropped; throws (keeping the rest queued) when the server can't be reached.
    private func sendShares() async throws -> [String] {
        var rejected: [String] = []
        for share in try store.pendingShares() {
            guard let url = URL(string: share.url) else {
                try store.removeShare(share)
                continue
            }
            do {
                try store.upsert([try await api.createItem(url: url)])
            } catch where Self.isPermanent(error) {
                rejected.append("Couldn't save \(share.url): \(error.localizedDescription)")
            }
            try store.removeShare(share)
        }
        return rejected
    }

    private func sendPatches() async throws -> [String] {
        var rejected: [String] = []
        for patch in try store.pendingPatches() {
            var accepted: Item?
            do {
                accepted = try await api.patch(id: patch.itemId, changes: patch.changes, at: patch.at)
            } catch where Self.isPermanent(error) {
                // A 404 means the item is gone on the server; the pull removes it here too.
                if case APIError.http(404, _) = error {} else { rejected.append(error.localizedDescription) }
            }
            try store.removePatch(patch)
            if var item = accepted {
                // The server's answer wins (it may have kept a newer value), except for changes still queued.
                for later in try store.pendingPatches() where later.itemId == item.id {
                    later.changes.apply(to: &item)
                }
                try store.upsert([item])
            }
        }
        return rejected
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
        if changes.reset {
            try store.replaceAll(with: live)
        } else {
            try store.upsert(live)
            try store.delete(ids: deletedIDs)
        }
        try store.setTopics(changes.topics)
        try store.setFeeds(changes.feeds)
        try store.setLastSeq(changes.seq)
    }
}
