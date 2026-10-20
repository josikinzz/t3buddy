import Foundation

/// How the app finds a running feed: `feed.json` beside the T3 token, mode 0600, written by the
/// sidecar once it listens and removed when it exits. The lock file next to it keeps it to one sidecar.
public struct FeedDiscovery: Codable, Equatable, Sendable {
    public static let version = 1

    public var v: Int
    public var pid: Int32
    public var port: UInt16
    public var token: String
    public var startedAt: Double
    public var version: String

    public init(pid: Int32, port: UInt16, token: String, startedAt: Date, version: String) {
        self.v = Self.version
        self.pid = pid
        self.port = port
        self.token = token
        self.startedAt = startedAt.timeIntervalSince1970.rounded()
        self.version = version
    }

    public static var folder: URL { T3TokenFileStore.defaultURL.deletingLastPathComponent() }
    public static var defaultURL: URL { folder.appendingPathComponent("feed.json") }
    public static var lockURL: URL { folder.appendingPathComponent("feed.lock") }

    public static func load(from url: URL = defaultURL) -> FeedDiscovery? {
        guard let data = try? Data(contentsOf: url), let found = try? JSONDecoder().decode(FeedDiscovery.self, from: data), found.v == version else { return nil }
        return found
    }

    public func save(to url: URL = FeedDiscovery.defaultURL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".feed-\(pid).json")
        manager.createFile(atPath: temporary.path, contents: Data(FeedJSON.encode(self).utf8), attributes: [.posixPermissions: 0o600])
        _ = try manager.replaceItemAt(url, withItemAt: temporary)
    }

    /// Removes the file if it still describes this process.
    public static func remove(pid: Int32, at url: URL = defaultURL) {
        guard load(from: url)?.pid == pid else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// A random bearer token: 32 bytes as hex.
    public static func newToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}
