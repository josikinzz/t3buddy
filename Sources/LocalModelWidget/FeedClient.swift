import Foundation
import ModelWidgetCore

/// Subscribes to the feed on the page's behalf and hands it `{events, state}` at most every
/// `batchInterval` (`window.t3boii.feed`). The page stays offline and never sees the token.
///
/// It finds the feed through `feed.json` and resumes with `Last-Event-ID` after a drop. When the
/// helper it follows has sent nothing, pings included, for `staleAfter`, the page is told its state
/// is stale, so nothing on it spawns or is swallowed while nobody knows. A helper that cannot read
/// T3 says so in its own state.
///
/// When the helper is gone for `fallbackAfterGone`, or alive but silent for `fallbackAfterSilent`,
/// the app polls T3 itself with its own `FeedEngine` (same sources, same call cap) and relays that
/// instead, until a helper is back. Either one takes over the page only once its state is live:
/// a feed that has not read T3 yet knows less than the page, and its empty state would fade every orb.
actor FeedClient {
    /// Posted by the gear menu's "Connect T3" item.
    static let connectT3Notification = Notification.Name("T3boiiConnectT3")
    static let batchInterval: TimeInterval = 0.1
    static let staleAfter: TimeInterval = 20
    /// Pings come every 10 s; a stream this quiet has died without closing.
    static let silenceLimit: TimeInterval = 25
    static let fallbackAfterGone: TimeInterval = 3
    /// A helper not seen yet may still be starting (a freshly signed one takes seconds).
    static let launchGrace: TimeInterval = 10
    static let fallbackAfterSilent: TimeInterval = 15

    /// The message for the page, and the full state as of it.
    private let deliver: @MainActor @Sendable (String, String?) -> Void
    /// Told when the helper is alive but has stopped answering, so its supervisor can replace it.
    private let helperHung: @MainActor @Sendable () -> Void
    private let session: URLSession
    private var relay = FeedRelay()
    private var heardAt = Date()
    private var task: Task<Void, Never>?

    /// When the helper was last heard from (any byte), and last seen alive in `feed.json`.
    private var helperHeardAt = Date().addingTimeInterval(launchGrace)
    private var helperAliveAt = Date().addingTimeInterval(launchGrace)
    /// The helper process the page follows, and its last event id for `Last-Event-ID`. A new
    /// process (or any after a fallback) must send a live state before the page follows it.
    private var followedHelper: Int32?
    private var helperSeq: Int?
    private var fallback: (engine: FeedEngine, t3: T3ThreadSource, task: Task<Void, Never>, since: Date)?
    private var fallbackRead = false

    init(deliver: @escaping @MainActor @Sendable (String, String?) -> Void, helperHung: @escaping @MainActor @Sendable () -> Void = {}) {
        self.deliver = deliver
        self.helperHung = helperHung
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.silenceLimit
        configuration.timeoutIntervalForResource = .infinity
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
        Task { await flushLoop() }
        Task { await watchLoop() }
    }

    /// "Connect T3": the helper fetches a new token.
    func connectT3() async -> Bool {
        guard let feed = FeedDiscovery.load() else { return false }
        guard let (data, _) = try? await session.data(for: feed.request("POST", "/v1/connect", timeout: 30)) else { return false }
        return String(decoding: data, as: UTF8.self).contains(#""connected":true"#)
    }

    /// The owner's projects for the demo, or nil (the page borrows faces from the orbit).
    func demoPayload() async -> String? {
        guard let feed = FeedDiscovery.load(), let (data, _) = try? await session.data(for: feed.request("GET", "/v1/demo", timeout: 10)) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return text == "null" ? nil : text
    }

    private func run() async {
        while !Task.isCancelled {
            if let feed = FeedDiscovery.load(), feed.isAlive {
                await listen(to: feed)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func listen(to feed: FeedDiscovery) async {
        var request = feed.request("GET", "/v1/events", timeout: Self.silenceLimit)
        if followedHelper == feed.pid, let helperSeq { request.setValue(String(helperSeq), forHTTPHeaderField: "Last-Event-ID") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            var parser = FeedStreamParser()
            var line: [UInt8] = []
            for try await byte in bytes {
                guard byte == UInt8(ascii: "\n") else { line.append(byte); continue }
                helperHeardAt = Date()
                if let frame = parser.take(Substring(decoding: line, as: UTF8.self)) { take(frame, from: feed.pid) }
                if followedHelper == feed.pid { heardAt = helperHeardAt }
                line.removeAll(keepingCapacity: true)
            }
        } catch {
            // Dropped or timed out: the loop reconnects and resumes after the last event.
        }
    }

    private func take(_ frame: FeedStreamParser.Frame, from pid: Int32) {
        if followedHelper != pid {
            guard frame.kind != "message", (try? JSONDecoder().decode(FeedState.self, from: Data(frame.data.utf8)))?.source == .live else { return }
            followedHelper = pid
            endFallback()
        }
        if let id = frame.id { helperSeq = id }
        relay.take(frame)
    }

    private func flushLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Self.batchInterval * 1_000_000_000))
            var message = relay.flush()
            // The app's own engine, once it has read T3, judges lagging and stale itself, ticks included.
            let ownFeed = fallback != nil && fallbackRead
            if message == nil, !ownFeed, Date().timeIntervalSince(heardAt) > Self.staleAfter { message = relay.markStale() }
            if let message { await deliver(message, relay.currentState) }
        }
    }

    /// Once a second: start the fallback when the helper is gone or silent.
    private func watchLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let now = Date()
            if FeedDiscovery.load()?.isAlive == true { helperAliveAt = now }
            guard fallback == nil else { continue }
            let gone = now.timeIntervalSince(helperAliveAt) >= Self.fallbackAfterGone
            let silent = now.timeIntervalSince(helperHeardAt) >= Self.fallbackAfterSilent
            guard gone || silent else { continue }
            startFallback(reason: gone ? "is gone" : "stopped answering")
            if !gone { await helperHung() }
        }
    }

    private func startFallback(reason: String) {
        let flags = FeedFlags.parse(UserDefaults.standard.string(forKey: "petFeedFlags"))
        if !flags.unknown.isEmpty { NSLog("T3boii: petFeedFlags names no feed part (\(flags.unknown.joined(separator: ", "))); ignoring it") }
        let t3 = T3ThreadSource(tokenStore: T3TokenFileStore(), icons: ProjectIconResolver(transcodeToPNG: ProjectIconResolver.pngFromImageFile), readsQueues: flags.contains("queue"), readsSeeds: flags.contains("seeds"))
        let engine = FeedEngine(sources: [t3, GrokOrbitSource()])
        followedHelper = nil
        let task = Task { [weak self] in
            let (_, batches) = await engine.subscribe()
            let polling = Task { await engine.run() }
            for await batch in batches {
                guard !Task.isCancelled else { break }
                await self?.take(batch)
            }
            polling.cancel()
        }
        fallback = (engine, t3, task, Date())
        NSLog("T3boii: the feed helper \(reason); the app is polling T3 itself until it is back")
    }

    private func take(_ batch: FeedBatch) {
        // Until the fallback has read T3 it knows less than the page does: leave the page's state be.
        guard fallback != nil, fallbackRead || batch.state.source == .live else { return }
        if !fallbackRead { NSLog("T3boii: the app's own polling read T3: \(batch.state.orbs.count) orbs") }
        fallbackRead = true
        for event in batch.events { relay.take(.init(kind: "message", id: event.seq, data: FeedJSON.encode(event))) }
        relay.take(.init(kind: "state", id: batch.state.seq, data: FeedJSON.encode(batch.state)))
    }

    private func endFallback() {
        guard let fallback else { return }
        fallback.task.cancel()
        let t3 = fallback.t3
        let since = fallback.since
        self.fallback = nil
        fallbackRead = false
        Task {
            let calls = await t3.toolCalls
            NSLog("T3boii: the feed helper is back after \(Int(Date().timeIntervalSince(since))) s; the app's own polling stopped (\(calls) T3 calls)")
        }
    }
}
