import Foundation

/// The time picker's ranges. Each item lands in exactly one, by its rounded minutes.
public enum TimeRange: String, Codable, Sendable, CaseIterable {
    case any, under5, from5to15, from15to30, over30

    public var label: String {
        switch self {
        case .any: "Any"
        case .under5: "Under 5"
        case .from5to15: "5–15"
        case .from15to30: "15–30"
        case .over30: "30+"
        }
    }

    public func contains(_ minutes: Int) -> Bool {
        switch self {
        case .any: true
        case .under5: minutes < 5
        case .from5to15: (5..<15).contains(minutes)
        case .from15to30: (15..<30).contains(minutes)
        case .over30: minutes >= 30
        }
    }
}

public struct ItemFilter: Equatable, Codable, Sendable {
    public var location: Location
    public var range: TimeRange
    public var topic: String?
    public var favoritesOnly: Bool
    /// Words typed in the search field. Left out of saved filters, so a search ends when the app does.
    public var query = ""

    enum CodingKeys: String, CodingKey { case location, range, topic, favoritesOnly }

    public init(location: Location, range: TimeRange = .any, topic: String? = nil, favoritesOnly: Bool = false) {
        self.location = location
        self.range = range
        self.topic = topic
        self.favoritesOnly = favoritesOnly
    }

    public func matches(_ item: Item) -> Bool {
        guard item.location == location, !item.deleted, range.contains(item.minutes) else { return false }
        if favoritesOnly && !item.favorite { return false }
        if let topic, !item.topics.contains(topic) { return false }
        return true
    }

    public var searchTerms: [String] { Search.terms(in: query) }
    public var isSearching: Bool { !searchTerms.isEmpty
    }
}
