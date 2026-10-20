import Foundation

/// Which T3 server is running and where: `~/.t3/userdata/server-runtime.json`, the only T3 local
/// state the feed reads. A new `pid` or `startedAt` means T3 restarted.
public struct T3ServerIdentity: Equatable, Sendable {
    public var pid: Int
    public var startedAt: String
    public var origin: URL

    public init(pid: Int, startedAt: String, origin: URL) {
        self.pid = pid
        self.startedAt = startedAt
        self.origin = origin
    }

    public static func file(t3Home: URL) -> URL {
        t3Home.appendingPathComponent("userdata/server-runtime.json")
    }

    /// The identity in `url`, or nil when it is missing or unreadable (T3 is down or starting).
    public static func read(from url: URL) -> T3ServerIdentity? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, let startedAt = object["startedAt"] as? String else { return nil }
        let origin = (object["origin"] as? String).flatMap(URL.init(string:))
            ?? (object["port"] as? Int).flatMap { URL(string: "http://127.0.0.1:\($0)") }
        guard let origin, origin.host == "127.0.0.1" || origin.host == "localhost" else { return nil }
        return T3ServerIdentity(pid: pid, startedAt: startedAt, origin: origin)
    }

    public func isSameServer(as other: T3ServerIdentity) -> Bool {
        pid == other.pid && startedAt == other.startedAt
    }
}
