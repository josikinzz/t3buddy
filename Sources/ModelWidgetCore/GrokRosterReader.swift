import AppKit
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Turns Grok Bot's persisted client state into orbs, read-only.
///
/// Grok Bot (bundle `com.anysphere.sand`) keeps one JSON file per persistence key in
/// `~/Library/Application Support/Grok Bot/sand-client-persistence/`, named by the key in lowercase,
/// unpadded RFC 4648 base32 plus `.blob`. Two keys matter here, both scoped by account
/// (`sand.client.slice.account.<account>.`):
/// - `roster.last-roster`: `{"schemaVersion":4,"value":{"rows":[agent]}}`. An agent row carries `id`, `name`,
///   `avatarColor` (a palette name), `avatarPhoto` (`{"kind":"file","key":…}` or null), `lastActivityAt` (epoch ms),
///   `awaitingUserResponse` (null, or `{tabId, reason, since}`), `isGroup` and `isHiddenFromSidebar`.
/// - `transcript.replicas.<agentId>`: `{"schemaVersion":1,"value":{"entries":[{timestampMs,…}],"persistedAt":…}}`.
///   The roster's `lastActivityAt` lags for agents that talk to other agents, while the replica gains the entry
///   within seconds, so an agent's activity time is the later of the two. A replica's file time and `persistedAt`
///   are not used: a resync rewrites every replica at once with old entries. A replica with another schema
///   version is ignored (one log line), and the roster's time alone counts.
/// Avatar photos are PNG files named by their key in the sibling `roster-avatars/` folder.
/// `~/.grokbot/local-exec-daemon.json` reports `inflightCount`, the live work counter.
public enum GrokRosterReader {
    public static let supportedSchemaVersion = 4
    /// An agent is active when its last activity falls within this window.
    public static let activeWindow: TimeInterval = 3 * 60
    /// An agent waits on the owner only while `awaitingUserResponse.since` is this recent; an older
    /// question has been abandoned, and the agent no longer orbits for it.
    public static let waitingWindow: TimeInterval = 60 * 60
    public static let supportedReplicaSchemaVersion = 1
    /// The id of the generic orb shown when the daemon reports work but no agent is recent.
    public static let inflightOrbID = "grok:inflight"
    /// Grok Bot orbs wear Grok Bot's own app icon as their badge (`badges/grokBot.png`), apart from the xAI mark
    /// that T3's `grok` provider threads carry.
    public static let providerID = "grokBot"
    /// Grok Bot's app icon, bundled with the pet page; the generic inflight orb's face.
    public static let appIconPath = "./badges/grokBot.png"
    static let avatarPixelSize = 96

    static let accountPrefix = "sand.client.slice.account."
    private static let rosterSuffix = ".roster.last-roster"
    private static let replicaInfix = ".transcript.replicas."
    private static let logger = Logger(subsystem: "local.codex.LocalModelWidget", category: "Orbit")

    /// Grok Bot's avatar palette (`avatarColor` ids), copied from the app's bundle. Unknown or empty falls back to gray.
    static let palette: [String: String] = [
        "black": "#000000", "brown": "#936439", "red": "#FF263C", "orange": "#FF6700",
        "yellow": "#FF9800", "green": "#00C972", "cyan": "#00BCA6", "blue": "#1084FE",
        "violet": "#9159FE", "magenta": "#FF309B", "gray": "#777777"
    ]

    public static func read(persistenceFolder: URL, daemonState: URL, now: Date) -> [Orb] {
        read(persistenceFolder: persistenceFolder, daemonState: daemonState, now: now, notice: logNotice)
    }

    /// `notice` receives a line when the roster's or a replica's schema is not supported.
    /// `avatars` caches encoded avatar photos between reads.
    public static func read(persistenceFolder: URL, daemonState: URL, now: Date, avatarCache: GrokAvatarCache? = nil, notice: (String) -> Void) -> [Orb] {
        let inflight = inflightCount(daemonState)
        let roster: Roster
        switch loadRoster(in: persistenceFolder) {
        case .missing:
            return inflight > 0 ? [inflightOrb] : []
        case let .unsupported(version):
            notice("Grok Bot roster schema version \(version.map(String.init) ?? "unknown") is not supported (expected \(supportedSchemaVersion)); showing no Grok orbs")
            return []
        case let .loaded(loaded):
            roster = loaded
        }

        let cutoff = now.addingTimeInterval(-activeWindow)
        let waitingCutoff = now.addingTimeInterval(-waitingWindow)
        let avatars = persistenceFolder.deletingLastPathComponent().appendingPathComponent("roster-avatars", isDirectory: true)
        var orbs: [Orb] = []
        var anyRecent = false
        for agent in roster.agents where !agent.isGroup && !agent.isHidden {
            var lastActivity = agent.lastActivity
            if let replica = roster.replicas[agent.id], let latest = latestEntry(in: replica, notBefore: cutoff, notice: notice) {
                lastActivity = max(lastActivity ?? latest, latest)
            }
            let recent = lastActivity.map { $0 >= cutoff } ?? false
            anyRecent = anyRecent || recent
            let waiting = agent.awaitingUser && (agent.awaitingSince.map { $0 >= waitingCutoff } ?? false)
            guard recent || waiting else { continue }
            orbs.append(Orb(
                id: "grok:\(agent.id)",
                source: .grok,
                projectIcon: icon(for: agent, avatars: avatars, cache: avatarCache),
                provider: providerID,
                state: waiting ? .waiting : .active,
                label: agent.name
            ))
        }
        if !anyRecent, inflight > 0 {
            orbs.append(inflightOrb)
        }
        return orbs
    }

    @Sendable public static func logNotice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    // MARK: Blob names

    private static let base32Alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    public static func blobFileName(forKey key: String) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in Array(key.utf8) {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(base32Alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(base32Alphabet[(buffer << (5 - bits)) & 31])
        }
        return output + ".blob"
    }

    public static func persistenceKey(forBlobFileName name: String) -> String? {
        guard name.hasSuffix(".blob") else { return nil }
        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in name.dropLast(5) {
            guard let value = base32Alphabet.firstIndex(of: character) else { return nil }
            buffer = ((buffer << 5) | value) & 0xFFFF
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // MARK: Roster

    struct Agent {
        var id: String
        var name: String
        var color: String
        var photoKey: String?
        var lastActivity: Date?
        var awaitingUser: Bool
        var awaitingSince: Date?
        var isGroup: Bool
        var isHidden: Bool
    }

    struct Roster {
        var agents: [Agent]
        var replicas: [String: URL]
    }

    enum RosterLoad {
        case missing
        case unsupported(Int?)
        case loaded(Roster)
    }

    static func loadRoster(in folder: URL) -> RosterLoad {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return .missing }
        var rosters: [(account: String, url: URL, modified: Date)] = []
        var replicaFiles: [(account: String, agent: String, url: URL)] = []
        for name in names {
            guard let key = persistenceKey(forBlobFileName: name), key.hasPrefix(accountPrefix) else { continue }
            let url = folder.appendingPathComponent(name)
            if key.hasSuffix(rosterSuffix) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                rosters.append((String(key.dropLast(rosterSuffix.count)), url, modified))
            } else if let range = key.range(of: replicaInfix) {
                replicaFiles.append((String(key[..<range.lowerBound]), String(key[range.upperBound...]), url))
            }
        }
        // One account is signed in; if several left rosters behind, the newest is the live one.
        guard let newest = rosters.max(by: { $0.modified < $1.modified }),
              let data = try? Data(contentsOf: newest.url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .missing
        }
        let version = (object["schemaVersion"] as? NSNumber)?.intValue
        guard version == supportedSchemaVersion else { return .unsupported(version) }
        guard let rows = (object["value"] as? [String: Any])?["rows"] as? [[String: Any]] else { return .missing }

        let agents = rows.compactMap { row -> Agent? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            let photo = row["avatarPhoto"] as? [String: Any]
            let awaiting = row["awaitingUserResponse"]
            return Agent(
                id: id,
                name: (row["name"] as? String) ?? "",
                color: (row["avatarColor"] as? String) ?? "",
                photoKey: photo?["kind"] as? String == "file" ? photo?["key"] as? String : nil,
                lastActivity: millisecondsDate(row["lastActivityAt"]),
                awaitingUser: awaiting is [String: Any] || (awaiting as? Bool) == true,
                awaitingSince: sinceDate((awaiting as? [String: Any])?["since"]),
                isGroup: (row["isGroup"] as? Bool) ?? false,
                isHidden: (row["isHiddenFromSidebar"] as? Bool) ?? false
            )
        }
        var replicas: [String: URL] = [:]
        for file in replicaFiles where file.account == newest.account {
            replicas[file.agent] = file.url
        }
        return .loaded(Roster(agents: agents, replicas: replicas))
    }

    /// The newest transcript entry time, or nil. A replica written before `notBefore` cannot hold a newer entry,
    /// so it is skipped without decoding.
    static func latestEntry(in replica: URL, notBefore cutoff: Date, notice: (String) -> Void = { _ in }) -> Date? {
        if let modified = try? replica.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < cutoff {
            return nil
        }
        guard let data = try? Data(contentsOf: replica),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let version = (object["schemaVersion"] as? NSNumber)?.intValue
        guard version == supportedReplicaSchemaVersion else {
            notice("Grok Bot transcript replica schema version \(version.map(String.init) ?? "unknown") is not supported (expected \(supportedReplicaSchemaVersion)); using roster activity only")
            return nil
        }
        guard let entries = (object["value"] as? [String: Any])?["entries"] as? [[String: Any]] else {
            return nil
        }
        return entries.compactMap { millisecondsDate($0["timestampMs"]) }.max()
    }

    /// `since` as epoch milliseconds, or an ISO 8601 string.
    private static func sinceDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        return millisecondsDate(value)
    }

    private static func millisecondsDate(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, !(value is Bool) else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }

    static func inflightCount(_ daemonState: URL) -> Int {
        guard let data = try? Data(contentsOf: daemonState),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return (object["inflightCount"] as? NSNumber)?.intValue ?? 0
    }

    // MARK: Icons

    /// The generic orb: Grok Bot's app icon as its face and its badge.
    public static var inflightOrb: Orb {
        Orb(id: inflightOrbID, source: .grok, projectIcon: .bundled(appIconPath), provider: providerID, state: .active, label: "Grok Bot")
    }

    static func icon(for agent: Agent, avatars: URL, cache: GrokAvatarCache? = nil) -> OrbIcon {
        let color = palette[agent.color] ?? palette["gray"]!
        if let key = agent.photoKey, !key.contains("/"),
           let dataURL = cache?.dataURL(avatars.appendingPathComponent(key)) ?? avatarDataURL(avatars.appendingPathComponent(key)) {
            return .image(dataURL: dataURL, ring: color)
        }
        let initial = agent.name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "G"
        return .monogram(initial, color: color)
    }

    /// The photo downscaled to at most 96 px: JPEG when opaque, PNG when it has alpha.
    public static func avatarDataURL(_ file: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: avatarPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let opaque: Bool
        switch thumbnail.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: opaque = true
        default: opaque = false
        }
        let type = opaque ? UTType.jpeg : UTType.png
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, opaque ? [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:\(type.preferredMIMEType ?? "image/png");base64,\((output as Data).base64EncodedString())"
    }
}

/// Encoded avatar photos by file, kept while the file's modification time is unchanged, so a
/// poll every few seconds does not decode and re-encode every photo.
public final class GrokAvatarCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (modified: Date, dataURL: String?)] = [:]
    private let encode: (URL) -> String?
    /// How many times a photo was encoded (for checks).
    public private(set) var encodeCount = 0

    public init(encode: @escaping (URL) -> String? = GrokRosterReader.avatarDataURL) {
        self.encode = encode
    }

    public func dataURL(_ file: URL) -> String? {
        // Not URL resource values: a URL caches those, and this must see a replaced photo.
        let modified = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) ?? .distantPast
        lock.lock()
        if let entry = entries[file.path], entry.modified == modified {
            lock.unlock()
            return entry.dataURL
        }
        lock.unlock()
        let dataURL = encode(file)
        lock.lock()
        encodeCount += 1
        entries[file.path] = (modified, dataURL)
        lock.unlock()
        return dataURL
    }
}

/// The live Grok Bot orbit source. Reads the real paths on each call; contributes nothing while Grok Bot is closed.
/// One of the feed's sources (`FeedEngine`), next to the T3 thread source. A roster it cannot
/// read is nil, never an empty orbit; Grok Bot not running is `[]`.
public actor GrokOrbitSource {
    public static let bundleIdentifier = "com.anysphere.sand"

    public static var defaultPersistenceFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence", isDirectory: true)
    }

    public static var defaultDaemonState: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grokbot/local-exec-daemon.json")
    }

    private let persistenceFolder: URL
    private let daemonState: URL
    private let isAppRunning: @Sendable () -> Bool
    private let notice: @Sendable (String) -> Void
    private var loggedNotices: Set<String> = []
    private let avatarCache = GrokAvatarCache()

    public init(
        persistenceFolder: URL = GrokOrbitSource.defaultPersistenceFolder,
        daemonState: URL = GrokOrbitSource.defaultDaemonState,
        isAppRunning: @escaping @Sendable () -> Bool = GrokOrbitSource.grokBotIsRunning,
        notice: @escaping @Sendable (String) -> Void = GrokRosterReader.logNotice
    ) {
        self.persistenceFolder = persistenceFolder
        self.daemonState = daemonState
        self.isAppRunning = isAppRunning
        self.notice = notice
    }

    public func orbs(now: Date) async -> [Orb]? {
        guard isAppRunning() else { return [] }
        var notices: [String] = []
        let orbs = GrokRosterReader.read(persistenceFolder: persistenceFolder, daemonState: daemonState, now: now, avatarCache: avatarCache) { notices.append($0) }
        // The roster is re-read every poll; an unsupported schema is logged once per process.
        for message in notices where loggedNotices.insert(message).inserted {
            notice(message)
        }
        return orbs
    }

    @Sendable public static func grokBotIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
