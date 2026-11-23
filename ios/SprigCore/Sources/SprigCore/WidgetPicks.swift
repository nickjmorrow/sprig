import Foundation

/// What the home-screen widget shows: Inbox items you've started, then random ones you haven't.
public struct WidgetPicks: Equatable, Sendable {
    public var continueReading: [Item]
    public var suggestions: [Item]

    /// Below this, an opened article only bounced a little: it counts as not started.
    public static let startedProgress = 0.03

    public init(continueReading: [Item], suggestions: [Item]) {
        self.continueReading = continueReading
        self.suggestions = suggestions
    }

    /// Started items come most recently touched first: the server gives every change, saved
    /// progress included, a new seq. Suggestions skip items still fetching or that failed.
    public init(inbox: [Item], seed: UInt64) {
        continueReading = inbox
            .filter { $0.progress >= Self.startedProgress }
            .sorted { $0.seq > $1.seq }
        var generator = SeededGenerator(seed: seed)
        suggestions = inbox
            .filter { $0.progress < Self.startedProgress && ($0.status == .ready || $0.status == .webOnly) }
            .shuffled(using: &generator)
    }

    /// Fits a widget with room for `rows` items: started ones first, but with two or more rows,
    /// one is kept for a suggestion when there is one.
    public func limited(to rows: Int) -> WidgetPicks {
        let suggestionRows = rows > 1 && !suggestions.isEmpty ? 1 : 0
        let started = Array(continueReading.prefix(rows - suggestionRows))
        return WidgetPicks(continueReading: started, suggestions: Array(suggestions.prefix(rows - started.count)))
    }
}

extension LocalStore {
    public func widgetPicks(seed: UInt64) throws -> WidgetPicks {
        WidgetPicks(inbox: try items(ItemFilter(location: .inbox)), seed: seed)
    }
}

/// SplitMix64: the same seed gives the same shuffle, so the widget doesn't reshuffle on every reload.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
