import Foundation
import Testing
@testable import SprigCore

/// Answers URLSession requests from the test instead of the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = body
        }
        Self.requests.append(request)
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
}

let settings = ServerSettings(baseURL: URL(string: "http://hub.test:8792"), token: "t", hostHeader: nil)

func itemJSON(_ item: Item) -> Data { try! JSONCoding.encoder.encode(item) }

func changesJSON(seq: Int, items: [Item], deletedIDs: [String] = []) -> Data {
    var rows = items.map { try! JSONSerialization.jsonObject(with: itemJSON($0)) as! [String: Any] }
    for id in deletedIDs {
        var row = rows.first ?? (try! JSONSerialization.jsonObject(with: itemJSON(makeItem(id: id))) as! [String: Any])
        row["id"] = id
        row["deleted"] = true
        rows.append(row)
    }
    let body: [String: Any] = ["seq": seq, "items": rows, "topics": ["AI", "Science"], "feeds": []]
    return try! JSONSerialization.data(withJSONObject: body)
}

@MainActor
func makeEngine() throws -> (SyncEngine, LocalStore) {
    let store = try LocalStore.inMemory()
    let engine = SyncEngine(store: store, settings: { settings }, session: stubSession())
    return (engine, store)
}

@Suite(.serialized)
@MainActor
struct SyncTests {
    init() {
        StubProtocol.handler = nil
        StubProtocol.requests = []
    }

    @Test func pullStoresItemsTopicsAndSeq() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        StubProtocol.handler = { _ in (200, changesJSON(seq: 7, items: [item])) }
        await engine.sync()
        #expect(engine.lastError == nil)
        #expect(try store.items(ItemFilter(location: .inbox)).map(\.id) == ["a"])
        #expect(try store.lastSeq() == 7)
        #expect(try store.topics() == ["AI", "Science"])
        #expect(StubProtocol.requests.last?.url?.query == "since=0")
        #expect(StubProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test func deletedRowsRemoveLocally() async throws {
        let (engine, store) = try makeEngine()
        try store.upsert([makeItem(id: "gone")])
        StubProtocol.handler = { _ in (200, changesJSON(seq: 3, items: [], deletedIDs: ["gone"])) }
        await engine.sync()
        #expect(try store.items(ItemFilter(location: .inbox)).isEmpty)
    }

    @Test func pendingPatchSurvivesFailedSync() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        try store.upsert([item])
        engine.update(item, PatchChanges(location: .archive))
        #expect(try store.items(ItemFilter(location: .archive)).map(\.id) == ["a"])

        StubProtocol.handler = { _ in (500, Data()) }
        await engine.sync()
        #expect(try store.pendingPatches().count == 1)
        #expect(engine.lastError != nil)

        var archived = item
        archived.location = .archive
        StubProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (200, itemJSON(archived)) : (200, changesJSON(seq: 9, items: [archived]))
        }
        await engine.sync()
        #expect(try store.pendingPatches().isEmpty)
        #expect(engine.lastError == nil)
        let patch = try #require(StubProtocol.requests.first { $0.httpMethod == "PATCH" })
        #expect(patch.url?.path == "/api/items/a")
        let body = try #require(patch.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("\"location\":\"archive\"") && body.contains("\"at\""))
    }

    @Test func localChangeNotOverwrittenByStaleServerRow() async throws {
        let (engine, store) = try makeEngine()
        let item = makeItem(id: "a")
        try store.upsert([item])
        engine.update(item, PatchChanges(favorite: true))
        // The patch fails, but the pull still brings the server's older row.
        StubProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (503, Data()) : (200, changesJSON(seq: 2, items: [item]))
        }
        await engine.pull()
        #expect(try store.item(id: "a")?.favorite == true)
    }

    @Test func shareQueuedOfflineIsSentLater() async throws {
        let (engine, store) = try makeEngine()
        try store.enqueueShare(url: URL(string: "https://example.com/new")!)
        StubProtocol.handler = { _ in (500, Data()) }
        await engine.sync()
        #expect(try store.pendingShares().count == 1)

        StubProtocol.handler = { request in
            request.url?.path == "/api/items" ? (201, itemJSON(makeItem(id: "new"))) : (200, changesJSON(seq: 1, items: []))
        }
        await engine.sync()
        #expect(try store.pendingShares().isEmpty)
        let post = try #require(StubProtocol.requests.last { $0.httpMethod == "POST" })
        #expect(String(data: post.httpBody ?? Data(), encoding: .utf8)?.contains("https:\\/\\/example.com\\/new") == true
            || String(data: post.httpBody ?? Data(), encoding: .utf8)?.contains("https://example.com/new") == true)
    }

    @Test func notConfiguredDoesNothing() async throws {
        let store = try LocalStore.inMemory()
        let engine = SyncEngine(store: store, settings: { ServerSettings() }, session: stubSession())
        await engine.sync()
        #expect(StubProtocol.requests.isEmpty)
        #expect(engine.lastError == "Add the server address and token in Settings.")
    }
}
