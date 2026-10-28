import Foundation
import GRDB

public struct PendingPatch: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var itemId: String
    public var changes: PatchChanges
    public var at: Date

    public static let databaseTableName = "pendingPatch"

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct PendingShare: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var url: String
    public var createdAt: Date

    public static let databaseTableName = "pendingShare"

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// The phone's copy of everything, plus changes and shares waiting to reach the server.
public final class LocalStore: Sendable {
    public let db: DatabaseQueue

    public init(db: DatabaseQueue) throws {
        self.db = db
        try Self.migrator.migrate(db)
    }

    public static func inMemory() throws -> LocalStore {
        try LocalStore(db: DatabaseQueue())
    }

    /// The database in the App Group container, so the share extension can queue links in it.
    public static func shared() throws -> LocalStore {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try LocalStore(db: DatabaseQueue(path: container.appending(path: "bouquet.sqlite").path()))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("url", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("location", .text).notNull().indexed()
                t.column("status", .text).notNull()
                t.column("title", .text)
                t.column("author", .text)
                t.column("site", .text)
                t.column("publishedAt", .text)
                t.column("savedAt", .datetime).notNull()
                t.column("excerpt", .text).notNull()
                t.column("contentHtml", .text).notNull()
                t.column("wordCount", .integer).notNull()
                t.column("minutes", .integer).notNull()
                t.column("topics", .jsonText).notNull()
                t.column("topicsSource", .text).notNull()
                t.column("favorite", .boolean).notNull()
                t.column("progress", .double).notNull()
                t.column("feedId", .text)
                t.column("deleted", .boolean).notNull()
                t.column("seq", .integer).notNull()
            }
            try db.create(table: "pendingPatch") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemId", .text).notNull()
                t.column("changes", .jsonText).notNull()
                t.column("at", .datetime).notNull()
            }
            try db.create(table: "pendingShare") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: Items

    static func fetchItems(_ db: Database, _ filter: ItemFilter) throws -> [Item] {
        var request = Item
            .filter(Column("location") == filter.location.rawValue && Column("deleted") == false)
            .order(Column("savedAt").desc)
        if filter.favoritesOnly {
            request = request.filter(Column("favorite") == true)
        }
        return try request.fetchAll(db).filter(filter.matches)
    }

    public func items(_ filter: ItemFilter) throws -> [Item] {
        try db.read { try Self.fetchItems($0, filter) }
    }

    public func observe(_ filter: ItemFilter) -> AsyncValueObservation<[Item]> {
        ValueObservation.tracking { try Self.fetchItems($0, filter) }.values(in: db)
    }

    public func item(id: String) throws -> Item? {
        try db.read { try Item.fetchOne($0, key: id) }
    }

    public func upsert(_ items: [Item]) throws {
        try db.write { db in
            for item in items { try item.upsert(db) }
        }
    }

    public func delete(ids: [String]) throws {
        try db.write { db in _ = try Item.deleteAll(db, keys: ids) }
    }

    // MARK: Sync bookkeeping

    private func value<T: Codable>(_ key: String, as type: T.Type) throws -> T? {
        try db.read { db in
            guard let text = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [key]) else { return nil }
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        }
    }

    private func setValue<T: Codable>(_ value: T, for key: String) throws {
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try db.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", arguments: [key, text])
        }
    }

    public func lastSeq() throws -> Int { try value("lastSeq", as: Int.self) ?? 0 }
    public func setLastSeq(_ seq: Int) throws { try setValue(seq, for: "lastSeq") }
    public func topics() throws -> [String] { try value("topics", as: [String].self) ?? [] }
    public func setTopics(_ topics: [String]) throws { try setValue(topics, for: "topics") }
    public func feeds() throws -> [Feed] { try value("feeds", as: [Feed].self) ?? [] }
    public func setFeeds(_ feeds: [Feed]) throws { try setValue(feeds, for: "feeds") }

    // MARK: Queues

    /// Applies the change locally right away and remembers to send it.
    public func change(_ itemID: String, _ changes: PatchChanges, at: Date = Date()) throws {
        try db.write { db in
            guard var item = try Item.fetchOne(db, key: itemID) else { return }
            changes.apply(to: &item)
            try item.update(db)
            var patch = PendingPatch(itemId: itemID, changes: changes, at: at)
            try patch.insert(db)
        }
    }

    public func pendingPatches() throws -> [PendingPatch] {
        try db.read { try PendingPatch.order(Column("id")).fetchAll($0) }
    }

    public func removePatch(_ patch: PendingPatch) throws {
        _ = try db.write { try PendingPatch.deleteOne($0, key: patch.id) }
    }

    public func enqueueShare(url: URL) throws {
        try db.write { db in
            var share = PendingShare(url: url.absoluteString, createdAt: Date())
            try share.insert(db)
        }
    }

    public func pendingShares() throws -> [PendingShare] {
        try db.read { try PendingShare.order(Column("id")).fetchAll($0) }
    }

    public func removeShare(_ share: PendingShare) throws {
        _ = try db.write { try PendingShare.deleteOne($0, key: share.id) }
    }
}
