import Foundation
import Testing
@testable import SprigCore

@Test func readingToTheEndOnThisVisitArchives() {
    #expect(Item.readToEnd(from: 0.2, to: 1, in: .inbox))
    #expect(Item.readToEnd(from: 0, to: 0.99, in: .feed))
    // Not far enough, already finished before, or already archived.
    #expect(!Item.readToEnd(from: 0, to: 0.9, in: .inbox))
    #expect(!Item.readToEnd(from: 1, to: 1, in: .inbox))
    #expect(!Item.readToEnd(from: 0, to: 1, in: .archive))
}

@MainActor
@Test func archiveCanBeUndone() throws {
    let store = try LocalStore.inMemory()
    let engine = SyncEngine(store: store, settings: { ServerSettings() })
    let item = makeItem(id: "a", location: .feed)
    try store.upsert([item])

    engine.archive(item, progress: 1, automatically: true)
    #expect(try store.item(id: "a")?.location == .archive)
    #expect(try store.item(id: "a")?.progress == 1)
    #expect(engine.lastArchived?.from == .feed && engine.lastArchived?.automatically == true)

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
