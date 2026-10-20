import AppKit
import Foundation
import ImageIO
import ModelWidgetCore

extension ModelWidgetChecks {
    static func grokRosterChecks(_ suite: inout CheckSuite) async {
        // 2026-10-14 18:00:00 local-ish epoch; every fixture time is relative to it.
        let now = Date(timeIntervalSince1970: 1_792_022_400)
        let nowMs = Int(now.timeIntervalSince1970 * 1000)

        suite.check("Grok blob names are lowercase unpadded base32 of their persistence keys") {
            try expectEqual(GrokRosterReader.blobFileName(forKey: "sand.client.slice.ui-layout"), "onqw4zbomnwgszlooqxhg3djmnss45ljfvwgc6lpov2a.blob")
            try expectEqual(GrokRosterReader.persistenceKey(forBlobFileName: "onqw4zbomnwgszlooqxhg3djmnss45ljfvwgc6lpov2a.blob"), "sand.client.slice.ui-layout")
            try expect(GrokRosterReader.persistenceKey(forBlobFileName: "not base32!.blob") == nil, "Junk names must not decode")
        }

        suite.check("Grok fixture roster parses into orbs with avatar photo and colour") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "a1", name: "Alpha", color: "violet", photoKey: "photo-a1", lastActivityMs: nowMs - 30_000),
                GrokFixture.agent(id: "a2", name: "beta", color: "blue", photoKey: nil, lastActivityMs: nowMs - 60_000)
            ])
            try fixture.writeAvatar(key: "photo-a1", side: 720)
            try fixture.writeDaemon(inflight: 0)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs.map(\.id), ["grok:a1", "grok:a2"])
            try expect(orbs.allSatisfy { $0.source == .grok && $0.provider == "grokBot" && $0.state == .active }, "Recent agents are active Grok orbs")
            try expectEqual(orbs.map(\.label), ["Alpha", "beta"])

            let photo = orbs[0].projectIcon
            try expectEqual(photo.kind, .image)
            try expectEqual(photo.color, "#9159FE")
            let src = photo.src ?? ""
            try expect(src.hasPrefix("data:image/"), "Avatar must be a data URL, got \(src.prefix(30))")
            let image = try decodeDataURLImage(src)
            try expect(image.width <= 96 && image.height <= 96, "Avatar must be downscaled to 96 px, got \(image.width)x\(image.height)")

            try expectEqual(orbs[1].projectIcon, OrbIcon.monogram("B", color: "#1084FE"))
        }

        suite.check("Grok agents count as active only within the last 3 minutes") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "fresh", name: "Fresh", color: "green", photoKey: nil, lastActivityMs: nowMs - 179_000),
                GrokFixture.agent(id: "stale", name: "Stale", color: "green", photoKey: nil, lastActivityMs: nowMs - 181_000),
                GrokFixture.agent(id: "ancient", name: "Ancient", color: "", photoKey: nil, lastActivityMs: nowMs - 86_400_000)
            ])
            try fixture.writeDaemon(inflight: 0)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs.map(\.id), ["grok:fresh"])
        }

        suite.check("Grok transcript replica entries refresh an agent the roster has not caught up with") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "talker", name: "Talker", color: "magenta", photoKey: nil, lastActivityMs: nowMs - 7_200_000),
                GrokFixture.agent(id: "quiet", name: "Quiet", color: "gray", photoKey: nil, lastActivityMs: nowMs - 7_200_000)
            ])
            try fixture.writeReplica(agentId: "talker", entryTimesMs: [nowMs - 3_600_000, nowMs - 20_000], persistedAtMs: nowMs - 18_000)
            // A bulk resync rewrites old transcripts: new file, old entries. It must not wake the agent.
            try fixture.writeReplica(agentId: "quiet", entryTimesMs: [nowMs - 7_200_000], persistedAtMs: nowMs - 5_000)
            try fixture.writeDaemon(inflight: 0)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs.map(\.id), ["grok:talker"])
            try expectEqual(orbs[0].projectIcon, OrbIcon.monogram("T", color: "#FF309B"))
        }

        suite.check("Grok awaitingUserResponse shows the agent as waiting") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "asks", name: "Asks", color: "yellow", photoKey: nil, lastActivityMs: nowMs - 10_000,
                                  awaiting: ["tabId": "t1", "reason": "question", "since": nowMs - 10_000]),
                GrokFixture.agent(id: "parked", name: "Parked", color: "red", photoKey: nil, lastActivityMs: nowMs - 3_540_000,
                                  awaiting: ["tabId": "t2", "reason": "approval", "since": nowMs - 3_540_000])
            ])
            try fixture.writeDaemon(inflight: 0)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs.map(\.id), ["grok:asks", "grok:parked"])
            try expect(orbs.allSatisfy { $0.state == .waiting }, "Agents awaiting the user must be waiting, even when their last activity is old")
        }

        suite.check("Grok waiting agent orbits only while its question is under an hour old") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "abandoned", name: "Abandoned", color: "red", photoKey: nil, lastActivityMs: nowMs - 3_660_000,
                                  awaiting: ["tabId": "t1", "reason": "question", "since": nowMs - 3_660_000]),
                GrokFixture.agent(id: "busy", name: "Busy", color: "blue", photoKey: nil, lastActivityMs: nowMs - 30_000,
                                  awaiting: ["tabId": "t2", "reason": "question", "since": nowMs - 7_200_000]),
                GrokFixture.agent(id: "nosince", name: "No since", color: "blue", photoKey: nil, lastActivityMs: nowMs - 7_200_000,
                                  awaiting: ["tabId": "t3", "reason": "question"]),
                GrokFixture.agent(id: "iso", name: "ISO", color: "green", photoKey: nil, lastActivityMs: nowMs - 7_200_000,
                                  awaiting: ["tabId": "t4", "reason": "question", "since": ISO8601DateFormatter().string(from: now.addingTimeInterval(-120))])
            ])
            try fixture.writeDaemon(inflight: 0)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs.map(\.id), ["grok:busy", "grok:iso"])
            // A stale question on an agent that is working again shows the work, not the question.
            try expectEqual(orbs.map(\.state), [.active, .waiting])
        }

        suite.check("Grok replica with an unknown schema is ignored for activity, with a notice") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "talker", name: "Talker", color: "magenta", photoKey: nil, lastActivityMs: nowMs - 7_200_000)
            ])
            try fixture.writeReplica(agentId: "talker", entryTimesMs: [nowMs - 20_000], persistedAtMs: nowMs - 18_000, schemaVersion: 2)
            try fixture.writeDaemon(inflight: 0)
            var notices: [String] = []
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now) { notices.append($0) }
            try expectEqual(orbs.map(\.id), [])
            try expectEqual(notices.count, 1)
            try expect(notices[0].contains("replica schema version 2"), "notice names the replica version: \(notices[0])")
        }

        await suite.check("Grok source logs an unknown replica schema once and encodes each avatar once") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "a1", name: "Alpha", color: "violet", photoKey: "photo-a1", lastActivityMs: nowMs - 10_000),
                GrokFixture.agent(id: "a2", name: "Beta", color: "blue", photoKey: nil, lastActivityMs: nowMs - 7_200_000)
            ])
            try fixture.writeReplica(agentId: "a2", entryTimesMs: [nowMs - 5_000], persistedAtMs: nowMs - 5_000, schemaVersion: 9)
            try fixture.writeAvatar(key: "photo-a1", side: 200)
            try fixture.writeDaemon(inflight: 0)
            let counter = NoticeCounter()
            let source = GrokOrbitSource(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, isAppRunning: { true }, notice: counter.add)
            for _ in 0..<3 { try expectEqual(await source.orbs(now: now)?.map(\.id), ["grok:a1"]) }
            try expectEqual(counter.count, 1)

            let cache = GrokAvatarCache()
            let file = fixture.avatars.appendingPathComponent("photo-a1")
            let first = cache.dataURL(file)
            try expect(first?.hasPrefix("data:image/") == true, "cached avatar is a data URL")
            try expectEqual(cache.dataURL(file), first)
            try expectEqual(cache.encodeCount, 1)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
            _ = cache.dataURL(file)
            try expectEqual(cache.encodeCount, 2)
        }

        suite.check("Grok inflight work with no recent agent shows one generic orb") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "old", name: "Old", color: "blue", photoKey: nil, lastActivityMs: nowMs - 600_000)
            ])
            try fixture.writeDaemon(inflight: 2)
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(orbs, [Orb(id: "grok:inflight", source: .grok, projectIcon: .bundled("./badges/grokBot.png"), provider: "grokBot", state: .active, label: "Grok Bot")])

            // With a recent agent the generic orb steps aside.
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "busy", name: "Busy", color: "blue", photoKey: nil, lastActivityMs: nowMs - 5_000)
            ])
            let withAgent = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now)
            try expectEqual(withAgent.map(\.id), ["grok:busy"])

            // Inflight work still shows when the roster itself is unreadable.
            let bare = try GrokFixture()
            try bare.writeDaemon(inflight: 1)
            try expectEqual(GrokRosterReader.read(persistenceFolder: bare.persistence, daemonState: bare.daemon, now: now).map(\.id), ["grok:inflight"])
        }

        suite.check("Grok inflight orb wears the bundled Grok Bot app icon, with no ring") {
            let icon = GrokRosterReader.inflightOrb.projectIcon
            try expectEqual(icon, OrbIcon.bundled("./badges/grokBot.png"))
            try expectEqual(icon.kind, .image)
            try expectEqual(icon.color, nil)
            try expectEqual(GrokRosterReader.inflightOrb.provider, "grokBot")
            // The page resolves the path against Resources/Pet, so the file must ship there.
            let page = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Pet").standardizedFileURL
            try expect(FileManager.default.fileExists(atPath: page.appendingPathComponent("badges/grokBot.png").path), "Resources/Pet/badges/grokBot.png ships with the page")
        }

        suite.check("Grok schema version 5 yields no orbs, one log line, and no crash") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "a1", name: "Alpha", color: "violet", photoKey: nil, lastActivityMs: nowMs - 5_000)
            ], schemaVersion: 5)
            try fixture.writeDaemon(inflight: 3)
            var notices: [String] = []
            let orbs = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now) { notices.append($0) }
            try expectEqual(orbs, [])
            try expectEqual(notices.count, 1)
            try expect(notices[0].contains("5"), "The log line names the version it refused")
        }

        suite.check("Grok missing folder, missing daemon file, or garbage stay silent and empty") {
            let fixture = try GrokFixture()
            var notices: [String] = []
            let missing = GrokRosterReader.read(persistenceFolder: fixture.persistence.appendingPathComponent("nope"), daemonState: fixture.daemon, now: now) { notices.append($0) }
            try expectEqual(missing, [])
            try FileManager.default.createDirectory(at: fixture.persistence, withIntermediateDirectories: true)
            let rosterName = GrokRosterReader.blobFileName(forKey: "sand.client.slice.account.grok%7Cuser_x.roster.last-roster")
            try Data("{not json".utf8).write(to: fixture.persistence.appendingPathComponent(rosterName))
            try Data("[]".utf8).write(to: fixture.daemon)
            let garbage = GrokRosterReader.read(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, now: now) { notices.append($0) }
            try expectEqual(garbage, [])
            try expectEqual(notices, [])
        }

        await suite.check("Grok source logs an unsupported schema once, not on every poll") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [], schemaVersion: 5)
            try fixture.writeDaemon(inflight: 0)
            let counter = NoticeCounter()
            let source = GrokOrbitSource(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, isAppRunning: { true }, notice: { counter.add($0) })
            _ = await source.orbs(now: now)
            _ = await source.orbs(now: now)
            try expectEqual(counter.count, 1)
        }

        await suite.check("Grok source empties quietly while Grok Bot is not running") {
            let fixture = try GrokFixture()
            try fixture.writeRoster(agents: [
                GrokFixture.agent(id: "a1", name: "Alpha", color: "violet", photoKey: nil, lastActivityMs: nowMs - 5_000)
            ])
            try fixture.writeDaemon(inflight: 1)
            let closed = GrokOrbitSource(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, isAppRunning: { false })
            try expectEqual(await closed.orbs(now: now), [])
            let open = GrokOrbitSource(persistenceFolder: fixture.persistence, daemonState: fixture.daemon, isAppRunning: { true })
            try expectEqual(await open.orbs(now: now)?.map(\.id), ["grok:a1"])
        }
    }
}

private final class NoticeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add(_: String) { lock.withLock { value += 1 } }
}

/// A throwaway Grok Bot data root laid out like the real one: `sand-client-persistence/*.blob` beside `roster-avatars/<key>`.
private struct GrokFixture {
    let root: URL
    var persistence: URL { root.appendingPathComponent("sand-client-persistence") }
    var avatars: URL { root.appendingPathComponent("roster-avatars") }
    var daemon: URL { root.appendingPathComponent("local-exec-daemon.json") }
    private let account = "sand.client.slice.account.grok%7Cuser_fixture"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grok-roster-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func agent(id: String, name: String, color: String, photoKey: String?, lastActivityMs: Int, awaiting: [String: Any]? = nil) -> [String: Any] {
        [
            "id": id, "name": name, "description": "", "title": "",
            "avatarShape": "pebble", "avatarColor": color, "avatarVersion": "v1",
            "avatarPhoto": photoKey.map { ["kind": "file", "key": $0] as [String: Any] } ?? NSNull(),
            "createdAt": lastActivityMs - 1_000_000, "updatedAt": lastActivityMs,
            "lastActivityAt": lastActivityMs, "localActivityAt": lastActivityMs - 1_000_000,
            "awaitingUserResponse": awaiting ?? NSNull(),
            "hasUnread": false, "unreadCount": 0, "isHiddenFromSidebar": false,
            "harness": "temporal", "isGroup": false, "memberIds": [String]()
        ]
    }

    func writeRoster(agents: [[String: Any]], schemaVersion: Int = 4) throws {
        let object: [String: Any] = ["schemaVersion": schemaVersion, "value": ["rows": agents]]
        try writeBlob(key: "\(account).roster.last-roster", object: object)
    }

    func writeReplica(agentId: String, entryTimesMs: [Int], persistedAtMs: Int, schemaVersion: Int = 1) throws {
        let entries = entryTimesMs.enumerated().map { index, time -> [String: Any] in
            ["kind": "message", "id": "e\(index)", "role": "assistant", "isStreaming": false, "timestampMs": time, "seq": index]
        }
        let object: [String: Any] = ["schemaVersion": schemaVersion, "value": ["entries": entries, "epochHint": NSNull(), "acceptedSequenceHint": NSNull(), "persistedAt": persistedAtMs]]
        try writeBlob(key: "\(account).transcript.replicas.\(agentId)", object: object)
    }

    func writeAvatar(key: String, side: Int) throws {
        try FileManager.default.createDirectory(at: avatars, withIntermediateDirectories: true)
        // An opaque RGB PNG, like the 720 px photos Grok Bot stores.
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let url = avatars.appendingPathComponent(key)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw CheckFailure.message("Fixture avatar did not write") }
    }

    func writeDaemon(inflight: Int) throws {
        let object: [String: Any] = ["pid": 1, "startedAt": 0, "servingAt": 0, "inflightCount": inflight, "generation": 0]
        try JSONSerialization.data(withJSONObject: object).write(to: daemon)
    }

    private func writeBlob(key: String, object: [String: Any]) throws {
        try FileManager.default.createDirectory(at: persistence, withIntermediateDirectories: true)
        let url = persistence.appendingPathComponent(GrokRosterReader.blobFileName(forKey: key))
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
}

private func decodeDataURLImage(_ src: String) throws -> CGImage {
    guard let comma = src.firstIndex(of: ","),
          let data = Data(base64Encoded: String(src[src.index(after: comma)...])),
          let image = NSBitmapImageRep(data: data)?.cgImage else {
        throw CheckFailure.message("Avatar data URL does not decode to an image")
    }
    return image
}
