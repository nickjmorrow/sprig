import Foundation
import Testing
@testable import BouquetCore

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func makeItem(
    id: String = UUID().uuidString,
    location: Location = .inbox,
    minutes: Int = 5,
    topics: [String] = [],
    favorite: Bool = false,
    savedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    seq: Int = 1
) -> Item {
    Item(
        id: id, url: "https://example.com/\(id)", kind: .article, location: location, status: .ready,
        title: "Title \(id)", author: nil, site: "example.com", publishedAt: nil, savedAt: savedAt,
        excerpt: "", contentHtml: "<p>hi</p>", wordCount: minutes * 238, minutes: minutes, topics: topics,
        topicsSource: "claude", favorite: favorite, progress: 0, feedId: nil, deleted: false, seq: seq
    )
}

@Test func rangeBoundaries() {
    #expect(TimeRange.under5.contains(4))
    #expect(!TimeRange.under5.contains(5))
    #expect(TimeRange.from5to15.contains(5))
    #expect(TimeRange.from5to15.contains(14))
    #expect(TimeRange.from15to30.contains(15))
    #expect(TimeRange.from15to30.contains(29))
    #expect(TimeRange.over30.contains(30))
    #expect(TimeRange.any.contains(500))
    #expect(TimeRange.allCases.map(\.label) == ["Any", "Under 5", "5–15", "15–30", "30+"])
}

@Test func filterMatches() {
    var filter = ItemFilter(location: .inbox)
    #expect(filter.matches(makeItem()))
    #expect(!filter.matches(makeItem(location: .archive)))
    filter.range = .from15to30
    #expect(!filter.matches(makeItem(minutes: 5)))
    #expect(filter.matches(makeItem(minutes: 20)))
    filter.topic = "AI"
    #expect(!filter.matches(makeItem(minutes: 20, topics: ["Science"])))
    #expect(filter.matches(makeItem(minutes: 20, topics: ["Science", "AI"])))
    var favorites = ItemFilter(location: .archive, favoritesOnly: true)
    #expect(!favorites.matches(makeItem(location: .archive)))
    #expect(favorites.matches(makeItem(location: .archive, favorite: true)))
    favorites.favoritesOnly = false
    #expect(favorites.matches(makeItem(location: .archive)))
}

@Test func decodesServerJSON() throws {
    let response = try JSONCoding.decoder.decode(ChangesResponse.self, from: fixtureData("changes"))
    #expect(response.topics.first == "AI")
    #expect(response.feeds.first?.title == "Simon Willison's Weblog")
    let article = try #require(response.items.first { $0.site == "brandur.org" })
    #expect(article.minutes == 16)
    #expect(article.kind == .article && article.location == .inbox && article.status == .ready)
    #expect(article.publishedAt == "2017-08-16")
    #expect(article.savedAt.timeIntervalSince1970 > 1_790_000_000)
    #expect(response.items.contains { $0.status == .webOnly })
    #expect(response.items.contains { $0.kind == .tweet })
}

@Test func patchChangesApplyAndEncodeOnlySetFields() throws {
    var item = makeItem()
    let changes = PatchChanges(location: .archive, favorite: true)
    changes.apply(to: &item)
    #expect(item.location == .archive && item.favorite)
    let json = try #require(String(data: JSONCoding.encoder.encode(changes), encoding: .utf8))
    #expect(json.contains("\"location\":\"archive\"") && !json.contains("progress"))
}

@Test func encodesTimesAsUTCWithZ() throws {
    let body = try JSONCoding.encoder.encode(["at": Date(timeIntervalSince1970: 1_800_000_000.25)])
    #expect(String(data: body, encoding: .utf8) == #"{"at":"2027-01-15T08:00:00.250Z"}"#)
}
