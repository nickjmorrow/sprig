import Foundation
import GRDB

public enum Location: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case inbox, feed, archive
}

public enum Status: String, Codable, Sendable, DatabaseValueConvertible {
    case pending, ready, failed
    case webOnly = "web_only"
}

public enum Kind: String, Codable, Sendable, DatabaseValueConvertible {
    case article, tweet
}

/// One saved thing, mirrored from the server.
public struct Item: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var url: String
    public var kind: Kind
    public var location: Location
    public var status: Status
    public var title: String?
    public var author: String?
    public var site: String?
    /// Shown as-is: feeds and pages give anything from a bare date to a full timestamp.
    public var publishedAt: String?
    public var savedAt: Date
    public var excerpt: String
    public var contentHtml: String
    public var wordCount: Int
    public var minutes: Int
    public var topics: [String]
    public var topicsSource: String
    public var favorite: Bool
    public var progress: Double
    public var feedId: String?
    public var deleted: Bool
    public var seq: Int

    public static let databaseTableName = "item"

    public var displayTitle: String { title ?? url }
    public var displaySite: String { site ?? URL(string: url)?.host() ?? url }
}

public struct Feed: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var url: String
    public var title: String?
    public var site: String?
    public var lastChecked: String?
    public var lastError: String?
}

public struct ChangesResponse: Codable, Sendable {
    public var seq: Int
    public var items: [Item]
    public var topics: [String]
    public var feeds: [Feed]
    /// The server can't send just the changes (this device missed purged deletions, or the
    /// server's database was restored): items is everything, and replaces what's here.
    public var reset: Bool

    enum CodingKeys: String, CodingKey { case seq, items, topics, feeds, reset }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        items = try container.decode([Item].self, forKey: .items)
        topics = try container.decode([String].self, forKey: .topics)
        feeds = try container.decode([Feed].self, forKey: .feeds)
        reset = try container.decodeIfPresent(Bool.self, forKey: .reset) ?? false
    }
}

/// The fields of an item you can change from the phone. Only the set ones are sent.
public struct PatchChanges: Codable, Equatable, Sendable {
    public var location: Location?
    public var favorite: Bool?
    public var progress: Double?
    public var topics: [String]?

    public init(location: Location? = nil, favorite: Bool? = nil, progress: Double? = nil, topics: [String]? = nil) {
        self.location = location
        self.favorite = favorite
        // The reader's rubber-band bounce reports slightly negative scroll positions.
        self.progress = progress.map { min(1, max(0, $0)) }
        self.topics = topics
    }

    public func apply(to item: inout Item) {
        if let location { item.location = location }
        if let favorite { item.favorite = favorite }
        if let progress { item.progress = min(1, max(0, progress)) }
        if let topics {
            item.topics = topics
            item.topicsSource = "you"
        }
    }
}

public enum JSONCoding {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 time: \(text)"))
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: text) ?? plain.date(from: text)
    }
}
