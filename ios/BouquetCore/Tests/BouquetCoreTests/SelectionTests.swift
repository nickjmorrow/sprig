import Testing
@testable import BouquetCore

@Test func theNextStoryDownTakesOver() {
    #expect(nextSelection(after: "b", old: ["a", "b", "c"], new: ["a", "c"]) == "c")
}

@Test func theLastStoryFallsBackToTheOneAbove() {
    #expect(nextSelection(after: "c", old: ["a", "b", "c"], new: ["a", "b"]) == "b")
}

@Test func theOnlyStoryLeavesNothingSelected() {
    #expect(nextSelection(after: "a", old: ["a"], new: []) == nil)
}

@Test func aStoryStillInTheListStaysSelected() {
    #expect(nextSelection(after: "b", old: ["a", "b", "c"], new: ["a", "b", "c"]) == "b")
}

@Test func skipsNeighboursThatLeftToo() {
    #expect(nextSelection(after: "b", old: ["a", "b", "c", "d"], new: ["a", "d"]) == "d")
    #expect(nextSelection(after: "c", old: ["a", "b", "c", "d"], new: ["a"]) == "a")
}

@Test func aStoryThatWasNeverListedSelectsNothing() {
    #expect(nextSelection(after: "z", old: ["a", "b"], new: ["a"]) == nil)
}
