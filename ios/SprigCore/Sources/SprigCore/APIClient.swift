import Foundation

public enum APIError: LocalizedError, Equatable {
    case notConfigured
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Add the server address and token in Settings."
        case let .http(status, message): message.isEmpty ? "The server answered \(status)." : message
        }
    }
}

/// Talks to the Sprig server's JSON API.
public struct APIClient: Sendable {
    public let settings: ServerSettings
    public let session: URLSession

    public init(settings: ServerSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    struct NewItem: Encodable { let url: String }
    struct PatchBody: Encodable { let changes: PatchChanges; let at: Date }
    struct TopicList: Codable { let topics: [String] }
    struct NewFeed: Encodable { let url: String }
    struct ErrorBody: Decodable { let detail: DetailText }

    /// FastAPI sends `detail` as a string, or as a list of validation errors.
    enum DetailText: Decodable {
        case text(String)
        case errors([[String: AnyDecodable]])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .errors((try? container.decode([[String: AnyDecodable]].self)) ?? [])
            }
        }

        var message: String {
            switch self {
            case let .text(text): text
            case let .errors(errors): errors.compactMap { $0["msg"]?.text }.joined(separator: "; ")
            }
        }
    }

    struct AnyDecodable: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            text = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (some Encodable)? = nil as Never?,
        timeout: TimeInterval = 30
    ) async throws -> Response {
        guard settings.isConfigured, let baseURL = settings.baseURL else { throw APIError.notConfigured }
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        if let hostHeader = settings.hostHeader, !hostHeader.isEmpty {
            request.setValue(hostHeader, forHTTPHeaderField: "Host")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONCoding.encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONCoding.decoder.decode(ErrorBody.self, from: data))?.detail.message ?? ""
            throw APIError.http(status: status, message: message)
        }
        if Response.self == Empty.self { return Empty() as! Response }
        return try JSONCoding.decoder.decode(Response.self, from: data)
    }

    struct Empty: Decodable {}

    public func changes(since seq: Int) async throws -> ChangesResponse {
        try await send("GET", "api/changes", query: [URLQueryItem(name: "since", value: String(seq))])
    }

    public func createItem(url: URL, timeout: TimeInterval = 30) async throws -> Item {
        try await send("POST", "api/items", body: NewItem(url: url.absoluteString), timeout: timeout)
    }

    public func patch(id: String, changes: PatchChanges, at: Date, timeout: TimeInterval = 30) async throws -> Item {
        try await send("PATCH", "api/items/\(id)", body: PatchBody(changes: changes, at: at), timeout: timeout)
    }

    public func retry(id: String) async throws -> Item {
        try await send("POST", "api/items/\(id)/retry")
    }

    public func putTopics(_ topics: [String]) async throws -> [String] {
        let list: TopicList = try await send("PUT", "api/topics", body: TopicList(topics: topics))
        return list.topics
    }

    public func addFeed(url: URL) async throws -> Feed {
        try await send("POST", "api/feeds", body: NewFeed(url: url.absoluteString))
    }

    public func deleteFeed(id: String) async throws {
        let _: Empty = try await send("DELETE", "api/feeds/\(id)")
    }
}
