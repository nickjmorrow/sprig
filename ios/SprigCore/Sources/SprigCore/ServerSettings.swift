import Foundation

public let appGroupID = "group.com.nicholai.sprig"

/// Where the server is. Shared with the share extension through the App Group's defaults.
public struct ServerSettings: Codable, Equatable, Sendable {
    public var baseURL: URL?
    public var token: String
    /// For a Mac with Tailscale DNS off: reach the server by IP and send its name here.
    public var hostHeader: String?

    public init(baseURL: URL? = nil, token: String = "", hostHeader: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.hostHeader = hostHeader
    }

    public var isConfigured: Bool { baseURL != nil && !token.isEmpty }

    private static let key = "serverSettings"

    public static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> ServerSettings {
        guard let data = defaults?.data(forKey: key),
              let settings = try? JSONDecoder().decode(ServerSettings.self, from: data) else { return ServerSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) {
        defaults?.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
