import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func feedServerChecks(_ suite: inout CheckSuite) async {
        let icon = OrbIcon.monogram("DA", color: "#000000")
        func orb(_ id: String) -> Orb { Orb(id: id, source: .t3, projectIcon: icon, provider: "claudeAgent") }
        let source = ScriptedFeedSource([
            FeedReading(orbs: [orb("t3:a")]),
            FeedReading(orbs: [orb("t3:a"), orb("t3:b")]),
            FeedReading(orbs: [orb("t3:b")], ended: ["t3:a": "completed"]),
            FeedReading(orbs: [orb("t3:b")], seeds: [FeedSeed(id: "seed:demo-app", provider: "codex")])
        ])
        let engine = FeedEngine(sources: [source], log: { _ in })
        let token = FeedDiscovery.newToken()
        let server = FeedServer(engine: engine, token: token)
        guard let port = try? await server.start() else {
            suite.check("Feed server: listens on loopback") { throw CheckFailure.message("could not listen") }
            return
        }
        defer { server.stop() }
        for _ in 0..<3 { await engine.poll() }

        func raw(_ head: String, until marker: String? = nil) async -> String {
            let task = URLSession.shared.streamTask(withHostName: "127.0.0.1", port: Int(port))
            task.resume()
            try? await task.write(Data((head + "\r\n\r\n").utf8), timeout: 2)
            var text = ""
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                guard let (data, done) = try? await task.readData(ofMinLength: 1, maxLength: 65536, timeout: 1) else { break }
                if let data { text += String(decoding: data, as: UTF8.self) }
                if done { break }
                if let marker, text.contains(marker) { break }
            }
            task.cancel()
            return text
        }
        let host = "Host: 127.0.0.1:\(port)"
        let auth = "Authorization: Bearer \(token)"

        await suite.check("Feed server: refuses a missing or wrong token, a foreign Host, and any Origin") {
            try expect(await raw("GET /v1/state HTTP/1.1\r\n\(host)").hasPrefix("HTTP/1.1 401"), "no token is refused")
            try expect(await raw("GET /v1/state HTTP/1.1\r\n\(host)\r\nAuthorization: Bearer \(token.dropLast())\(token.hasSuffix("0") ? "1" : "0")").hasPrefix("HTTP/1.1 401"), "a wrong token is refused")
            try expect(await raw("GET /v1/state HTTP/1.1\r\nHost: attacker.example:\(port)\r\n\(auth)").hasPrefix("HTTP/1.1 403"), "a rebound name is refused")
            try expect(await raw("GET /v1/state HTTP/1.1\r\n\(host)\r\n\(auth)\r\nOrigin: http://127.0.0.1:\(port)").hasPrefix("HTTP/1.1 403"), "a page's request is refused")
            let state = await raw("GET /v1/state HTTP/1.1\r\n\(host)\r\n\(auth)")
            try expect(state.hasPrefix("HTTP/1.1 200") && state.contains(#""id":"t3:b""#) && !state.contains(#""id":"t3:a""#), "the state is served: \(state.prefix(120))")
        }

        await suite.check("Feed server: a reconnecting subscriber gets what it missed, or a reset when that is gone") {
            let missed = await raw("GET /v1/events HTTP/1.1\r\n\(host)\r\n\(auth)\r\nLast-Event-ID: 1", until: #""kind":"finished""#)
            try expect(missed.contains("text/event-stream"), "events stream")
            try expect(!missed.contains("event: reset") && !missed.contains("id: 1\n"), "nothing already seen is resent")
            try expect(missed.contains(#""kind":"finished""#), "the swallow it missed is replayed")
            let reset = await raw("GET /v1/events HTTP/1.1\r\n\(host)\r\n\(auth)\r\nLast-Event-ID: 999", until: "event: reset")
            try expect(reset.contains("event: reset") && reset.contains(#""id":"t3:b""#), "an id from another feed gets the state")
            let fresh = await raw("GET /v1/events?after=0 HTTP/1.1\r\n\(host)\r\n\(auth)", until: #""kind":"finished""#)
            try expect(fresh.contains(#""kind":"started""#) && fresh.contains(#""kind":"finished""#), "after=0 replays the whole buffer")
        }

        await suite.check("Feed server: a subscriber reconnecting at the current seq gets the state, even when only its seeds changed") {
            let seq = await engine.state.seq
            await engine.poll()
            try expectEqual(await engine.state.seq, seq)
            let resumed = await raw("GET /v1/events HTTP/1.1\r\n\(host)\r\n\(auth)\r\nLast-Event-ID: \(seq)", until: "seed:demo-app")
            try expect(resumed.contains("event: state") && resumed.contains(#""id":"seed:demo-app""#), "the new seeds arrive: \(resumed.suffix(160))")
            try expect(!resumed.contains("event: reset"), "a cursor still in the buffer is not reset")
        }
    }
}

extension ModelWidgetChecks {
    static func feedEngineChecks(_ suite: inout CheckSuite) async {
        await suite.check("Feed engine: a source that hangs misses its deadline and counts as unread, and the other source still lands") {
            let icon = OrbIcon.monogram("DA", color: "#000000")
            let grok = ScriptedFeedSource([FeedReading(orbs: [Orb(id: "grok:a", source: .grok, projectIcon: icon, provider: "grokBot")])], source: .grok)
            let t3 = ScriptedFeedSource([FeedReading(orbs: [Orb(id: "t3:a", source: .t3, projectIcon: icon, provider: "codex")])], hang: 30)
            let engine = FeedEngine(sources: [t3, grok], deadline: 0.2, log: { _ in })
            let started = Date()
            await engine.poll()
            try expect(Date().timeIntervalSince(started) < 2, "the poll did not wait for the hung source")
            try expectEqual(await engine.state.orbs.map(\.id), ["grok:a"])
            try expectEqual(await engine.state.source, .lagging)
        }

        suite.check("Call bucket: a feed that calls as fast as it can averages 3 T3 calls a second, and no second has more than 13 (a burst of 10)") {
            var bucket = CallBucket.t3
            let start = Date(timeIntervalSince1970: 0)
            var now = start
            var made: [TimeInterval] = []
            while now.timeIntervalSince(start) < 600 {
                now = now.addingTimeInterval(bucket.take(now: now) + 0.02)
                made.append(now.timeIntervalSince(start))
            }
            try expect(Double(made.count) / 600 <= 3.02, "\(made.count) calls in 10 minutes")
            for (i, at) in made.enumerated() {
                let inSecond = made[i...].prefix { $0 < at + 1 }.count
                try expect(inSecond <= 13, "\(inSecond) calls in the second from \(at)")
            }
            let quiet = bucket.take(now: now.addingTimeInterval(60))
            try expectEqual(quiet, 0)
        }

        await suite.check("MCP client: a call retried because T3 dropped the session waits for the call bucket and is counted like any call") {
            SessionDroppingMCP.reset()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SessionDroppingMCP.self]
            let client = T3MCPClient(origin: URL(string: "http://t3.test")!, session: URLSession(configuration: configuration), bucket: CallBucket(capacity: 1, rate: 4))
            await client.setToken("demo-token")
            _ = try await client.callTool("t3_project_list")
            try expectEqual(await client.sessionsLost, 1)
            try expectEqual(await client.calls, 2)
            try expectEqual(await client.callsByTool, ["t3_project_list": 2])
            let sent = SessionDroppingMCP.toolCalls
            try expectEqual(sent.count, 2)
            try expect(sent[1].timeIntervalSince(sent[0]) >= 0.2, "the retry waited for the bucket: \(sent[1].timeIntervalSince(sent[0])) s")
        }

        suite.check("Feed relay: SSE frames become one page message per batch; an unchanged state is not resent; a silent feed goes stale") {
            var parser = FeedStreamParser()
            var relay = FeedRelay()
            let stream = "id: 4\ndata: {\"kind\":\"vanished\"}\n\n: ping\n\nevent: state\nid: 4\ndata: {\"limits\":[],\"orbs\":[],\"seq\":4,\"source\":\"live\",\"v\":1}\n\n"
            for line in stream.split(separator: "\n", omittingEmptySubsequences: false) {
                if let frame = parser.take(line) { relay.take(frame) }
            }
            try expectEqual(relay.lastSeq, 4)
            try expectEqual(relay.flush(), #"{"events":[{"kind":"vanished"}],"state":{"limits":[],"orbs":[],"seq":4,"source":"live","v":1}}"#)
            try expectEqual(relay.flush(), nil)
            relay.take(.init(kind: "state", id: 4, data: #"{"limits":[],"orbs":[],"seq":4,"source":"live","v":1}"#))
            try expectEqual(relay.flush(), nil)
            try expect(relay.markStale()?.contains(#""source":"stale""#) == true, "a silent feed marks its state stale")
            try expectEqual(relay.markStale(), nil)
        }
    }
}

/// T3's MCP endpoint, dropping the first session it opens (a 404 to its next call), and noting
/// when each `tools/call` arrives.
final class SessionDroppingMCP: URLProtocol {
    static var toolCalls: [Date] = []
    static var sessions = 0

    static func reset() {
        toolCalls = []
        sessions = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let message = (try? JSONSerialization.jsonObject(with: Self.body(of: request))) as? [String: Any] ?? [:]
        var status = 202
        var headers = ["Content-Type": "application/json"]
        var reply: [String: Any]?
        switch message["method"] as? String {
        case "initialize":
            Self.sessions += 1
            status = 200
            headers["Mcp-Session-Id"] = "session-\(Self.sessions)"
            reply = ["jsonrpc": "2.0", "id": message["id"] ?? 0, "result": ["protocolVersion": "2025-06-18", "capabilities": [String: Any]()]]
        case "tools/call":
            Self.toolCalls.append(Date())
            if request.value(forHTTPHeaderField: "Mcp-Session-Id") == "session-1" {
                status = 404
            } else {
                status = 200
                reply = ["jsonrpc": "2.0", "id": message["id"] ?? 0, "result": ["content": [["type": "text", "text": "{}"]]]]
            }
        default:
            break
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

/// Hands out readings in order, then repeats the last.
actor ScriptedFeedSource: FeedSource {
    nonisolated let source: Orb.Source
    private var readings: [FeedReading?]
    private let hang: TimeInterval

    init(_ readings: [FeedReading?], source: Orb.Source = .t3, hang: TimeInterval = 0) {
        self.readings = readings
        self.source = source
        self.hang = hang
    }

    func reading(now: Date) async -> FeedReading? {
        if hang > 0 { try? await Task.sleep(nanoseconds: UInt64(hang * 1_000_000_000)) }
        return readings.count > 1 ? readings.removeFirst() : readings.first ?? nil
    }
}
