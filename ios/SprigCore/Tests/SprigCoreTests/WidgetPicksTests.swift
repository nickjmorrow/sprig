import Foundation
import Testing
@testable import SprigCore

private func item(_ id: String, progress: Double = 0, status: Status = .ready, seq: Int = 1) -> Item {
    var item = makeItem(id: id, seq: seq)
    item.progress = progress
    item.status = status
    return item
}

@Test func startedItemsComeFirstMostRecentlyTouched() {
    let inbox = [item("old", progress: 0.4, seq: 3), item("new", progress: 0.2, seq: 9), item("read", progress: 1, seq: 5)]
    let picks = WidgetPicks(inbox: inbox, seed: 1)
    #expect(picks.continueReading.map(\.id) == ["new", "read", "old"])
    #expect(picks.suggestions.isEmpty)
}

@Test func aBounceIsNotStarted() {
    let picks = WidgetPicks(inbox: [item("bounced", progress: 0.02)], seed: 1)
    #expect(picks.continueReading.isEmpty)
    #expect(picks.suggestions.map(\.id) == ["bounced"])
}

@Test func suggestionsSkipItemsThatAreFetchingOrFailed() {
    let inbox = [item("ready"), item("web", status: .webOnly), item("pending", status: .pending), item("failed", status: .failed)]
    let picks = WidgetPicks(inbox: inbox, seed: 1)
    #expect(Set(picks.suggestions.map(\.id)) == ["ready", "web"])
}

@Test func sameSeedSameSuggestions() {
    let inbox = (0..<20).map { item("item\($0)") }
    let first = WidgetPicks(inbox: inbox, seed: 42).suggestions.map(\.id)
    #expect(WidgetPicks(inbox: inbox, seed: 42).suggestions.map(\.id) == first)
    #expect(WidgetPicks(inbox: inbox, seed: 43).suggestions.map(\.id) != first)
}

@Test func picksComeFromTheInboxOnly() throws {
    let store = try LocalStore.inMemory()
    var archived = makeItem(id: "archived", location: .archive)
    archived.progress = 0.5
    try store.upsert([makeItem(id: "inbox"), archived, makeItem(id: "feed", location: .feed)])
    let picks = try store.widgetPicks(seed: 1)
    #expect(picks.continueReading.isEmpty)
    #expect(picks.suggestions.map(\.id) == ["inbox"])
}

@Test func rowsGoToStartedItemsButKeepOneSuggestion() {
    let picks = WidgetPicks(
        continueReading: (0..<4).map { item("started\($0)", progress: 0.5) },
        suggestions: (0..<4).map { item("new\($0)") }
    )
    #expect(picks.limited(to: 1).continueReading.count == 1)
    #expect(picks.limited(to: 1).suggestions.isEmpty)
    #expect(picks.limited(to: 2).continueReading.count == 1)
    #expect(picks.limited(to: 2).suggestions.count == 1)
    #expect(picks.limited(to: 6).continueReading.count == 4)
    #expect(picks.limited(to: 6).suggestions.count == 2)
    let nothingNew = WidgetPicks(continueReading: picks.continueReading, suggestions: [])
    #expect(nothingNew.limited(to: 2).continueReading.count == 2)
    let nothingStarted = WidgetPicks(continueReading: [], suggestions: picks.suggestions)
    #expect(nothingStarted.limited(to: 2).suggestions.count == 2)
}
