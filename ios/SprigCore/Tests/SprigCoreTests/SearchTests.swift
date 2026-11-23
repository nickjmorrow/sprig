import Foundation
import Testing
@testable import SprigCore

private func searchItem(_ id: String, title: String = "Untitled", author: String? = nil, body: String = "<p>hi</p>",
                        location: Location = .inbox, topics: [String] = []) -> Item {
    var item = makeItem(id: id, location: location, topics: topics)
    item.title = title
    item.author = author
    item.contentHtml = body
    return item
}

private func search(_ store: LocalStore, _ query: String, in location: Location = .inbox, topic: String? = nil) throws -> [String] {
    var filter = ItemFilter(location: location, topic: topic)
    filter.query = query
    return try store.items(filter).map(\.id).sorted()
}

@Test func searchFindsTitlesAuthorsAndArticleText() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([
        searchItem("title", title: "The Log: What every engineer should know"),
        searchItem("author", author: "Jay Kreps"),
        searchItem("body", body: "<p>Kafka keeps an <em>append-only</em> log.</p>"),
        searchItem("none"),
    ])
    #expect(try search(store, "log") == ["body", "title"])
    #expect(try search(store, "KREPS") == ["author"])
    #expect(try search(store, "append-only") == ["body"])
    #expect(try search(store, "") == ["author", "body", "none", "title"])
    #expect(try search(store, "   ") == ["author", "body", "none", "title"])
}

@Test func searchNeedsEveryWordSomewhere() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([
        searchItem("both", title: "Kafka internals", body: "<p>About the log.</p>"),
        searchItem("one", title: "Kafka on the beach"),
    ])
    #expect(try search(store, "kafka log") == ["both"])
}

@Test func searchIgnoresMarkupAndReadsEntities() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([
        searchItem("markup", body: #"<div class="figure"><p>Plain words</p></div>"#),
        searchItem("entity", body: "<p>AT&amp;T and caf&eacute;s</p>"),
    ])
    #expect(try search(store, "figure").isEmpty)
    #expect(try search(store, "div").isEmpty)
    #expect(try search(store, "AT&T") == ["entity"])
    #expect(try search(store, "plain words") == ["markup"])
}

@Test func searchStaysInsideTheTabAndItsFilters() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([
        searchItem("inbox", title: "Rust tips", topics: ["Programming"]),
        searchItem("archived", title: "Rust tips", location: .archive),
        searchItem("other-topic", title: "Rust on bridges", topics: ["Science"]),
    ])
    #expect(try search(store, "rust", topic: "Programming") == ["inbox"])
    #expect(try search(store, "rust", in: .archive) == ["archived"])
}

@Test func searchTreatsLikeWildcardsAsText() throws {
    let store = try LocalStore.inMemory()
    try store.upsert([searchItem("percent", title: "100% done"), searchItem("plain", title: "1000 done")])
    #expect(try search(store, "100%") == ["percent"])
    #expect(try search(store, "_") == [])
}

@Test func savedFiltersLeaveTheSearchOut() throws {
    var filter = ItemFilter(location: .inbox, topic: "AI")
    filter.query = "kafka"
    let decoded = try JSONDecoder().decode(ItemFilter.self, from: JSONEncoder().encode(filter))
    #expect(decoded.query == "" && decoded.topic == "AI")
    // Filters saved before search existed still load.
    let old = Data(#"{"location":"inbox","range":"any","favoritesOnly":false}"#.utf8)
    #expect(try JSONDecoder().decode(ItemFilter.self, from: old).query == "")
}

@Test func searchResultsCarryThePassageThatMatched() throws {
    let store = try LocalStore.inMemory()
    let longIntro = Array(repeating: "filler", count: 30).joined(separator: " ")
    try store.upsert([
        searchItem("body", title: "Testing LLM apps", body: "<p>\(longIntro) Good <b>evals</b> start from real failures.</p>"),
        searchItem("title-only", title: "Evals in practice"),
    ])
    var filter = ItemFilter(location: .inbox)
    filter.query = "evals"
    let results = Dictionary(uniqueKeysWithValues: try store.items(filter).map { ($0.id, $0.excerpt) })
    #expect(results["body"] == "…filler filler filler filler filler filler filler Good evals start from real failures.")
    #expect(results["title-only"] == "")
    filter.query = ""
    #expect(try store.items(filter).allSatisfy { $0.excerpt == "" })
}

@Test func passageIsCutToLength() {
    let text = "Evals " + Array(repeating: "word", count: 200).joined(separator: " ")
    let passage = Search.passage(in: text, around: ["evals"])!
    #expect(passage.hasPrefix("Evals word") && passage.hasSuffix("word…") && passage.count <= 221)
}
