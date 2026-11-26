import Foundation
import Testing
@testable import SprigCore

@MainActor
@Test func archiveCanBeUndone() throws {
    let store = try LocalStore.inMemory()
    let engine = SyncEngine(store: store, settings: { ServerSettings() })
    let item = makeItem(id: "a", location: .feed)
    try store.upsert([item])

    engine.archive(item, progress: 1)
    #expect(try store.item(id: "a")?.location == .archive)
    #expect(try store.item(id: "a")?.progress == 1)
    #expect(engine.lastArchived?.from == .feed)

    engine.undoArchive()
    #expect(try store.item(id: "a")?.location == .feed)
    #expect(engine.lastArchived == nil)
}

@MainActor
@Test func dismissingAnOldOfferKeepsTheNewOne() throws {
    let store = try LocalStore.inMemory()
    let engine = SyncEngine(store: store, settings: { ServerSettings() })
    let first = makeItem(id: "1"), second = makeItem(id: "2")
    try store.upsert([first, second])
    engine.archive(first)
    let old = try #require(engine.lastArchived)
    engine.archive(second)
    engine.dismissUndo(old)
    #expect(engine.lastArchived?.item.id == "2")
    // Archiving something already archived offers nothing new.
    engine.archive(try #require(try store.item(id: "1")))
    #expect(engine.lastArchived?.item.id == "2")
}
