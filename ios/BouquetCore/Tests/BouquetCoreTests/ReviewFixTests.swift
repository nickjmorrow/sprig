import Foundation
import GRDB
import Testing
@testable import BouquetCore

@Test func progressIsClampedWhenApplied() {
    var item = makeItem()
    PatchChanges(progress: -0.03).apply(to: &item)
    #expect(item.progress == 0)
    PatchChanges(progress: 1.4).apply(to: &item)
    #expect(item.progress == 1)
    #expect(PatchChanges(progress: -0.5).progress == 0)
}

@Test func listsSkipArticleBodiesButTheReaderGetsThem() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([makeItem(id: "a")])
    #expect(try store.items(ItemFilter(location: .inbox)).first?.contentHtml == "")
    #expect(try store.item(id: "a")?.contentHtml == "<p>hi</p>")
}

@Test func sharedDatabaseWorksFromTwoProcesses() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite").path()
    let app = try LocalStore.onDisk(path: path)
    let shareExtension = try LocalStore.onDisk(path: path)
    let share = try shareExtension.enqueueShare(url: URL(string: "https://example.com/a")!)
    #expect(share.id != nil)
    #expect(try app.pendingShares().map(\.url) == ["https://example.com/a"])
}

// In SyncTests' serialized suite: these share StubProtocol's handler.
extension SyncTests {

    @Test func rejectedPatchIsDroppedAndThePullStillRuns() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        try store.upsert([item])
        engine.update(item, PatchChanges(topics: ["Gone"]))
        StubProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (422, Data(#"{"detail":"unknown topics: Gone"}"#.utf8)) : (200, changesJSON(seq: 5, items: [item]))
        }
        await engine.sync()
        #expect(try store.pendingPatches().isEmpty)
        #expect(try store.lastSeq() == 5)
        #expect(engine.lastError?.contains("unknown topics") == true)
    }

    @Test func serverErrorKeepsThePatchButStillPulls() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        try store.upsert([item])
        engine.update(item, PatchChanges(favorite: true))
        StubProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (503, Data()) : (200, changesJSON(seq: 6, items: [item]))
        }
        await engine.sync()
        #expect(try store.pendingPatches().count == 1)
        #expect(try store.lastSeq() == 6)
    }

    @Test func rejectedShareIsDropped() async throws {
        let (engine, store) = try makeEngine()
        try store.enqueueShare(url: URL(string: "https://example.com/a")!)
        StubProtocol.handler = { request in
            request.url?.path == "/api/items" ? (422, Data()) : (200, changesJSON(seq: 1, items: []))
        }
        await engine.sync()
        #expect(try store.pendingShares().isEmpty)
    }

    @Test func patchResponseCorrectsALosingLocalValue() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        try store.upsert([item])
        engine.update(item, PatchChanges(favorite: true))
        // The server kept a newer "false" from another device and doesn't bump seq.
        StubProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (200, itemJSON(item)) : (200, changesJSON(seq: 1, items: []))
        }
        await engine.sync()
        #expect(try store.item(id: "a")?.favorite == false)
    }

    @Test func resetReplacesEverythingLocal() async throws {
        let (engine, store) = try makeEngine()
        try store.upsert([makeItem(id: "ghost"), makeItem(id: "kept")])
        try store.setLastSeq(500)
        StubProtocol.handler = { _ in
            var body = try! JSONSerialization.jsonObject(with: changesJSON(seq: 9, items: [makeItem(id: "kept")])) as! [String: Any]
            body["reset"] = true
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        await engine.sync()
        #expect(try store.items(ItemFilter(location: .inbox)).map(\.id) == ["kept"])
        #expect(try store.lastSeq() == 9)
    }
}
