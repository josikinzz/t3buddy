import Foundation

/// Something the feed reads each poll: T3 Code threads or Grok Bot agents.
/// nil means it could not be read, which says nothing about its threads.
public protocol FeedSource: Sendable {
    var source: Orb.Source { get }
    func reading(now: Date) async -> FeedReading?
}

extension T3ThreadSource: FeedSource {
    public nonisolated var source: Orb.Source { .t3 }
}

extension GrokOrbitSource: FeedSource {
    public nonisolated var source: Orb.Source { .grok }
    public func reading(now: Date) async -> FeedReading? {
        await orbs(now: now).map { FeedReading(orbs: $0) }
    }
}

/// Polls the sources, folds each poll into `FeedWorld`, and keeps the last events for subscribers
/// that reconnect (`events(after:)`). One engine per process; `run()` is its only loop.
public actor FeedEngine {
    /// A source that takes longer than this counts as unread this poll.
    public static let sourceDeadline: TimeInterval = 8
    public static let busyInterval: TimeInterval = 2
    public static let quietInterval: TimeInterval = 5
    /// After consecutive polls where T3 could not be read.
    public static let backoff: [TimeInterval] = [4, 8, 15]
    public static let bufferSize = 2000
    static let slowPoll: TimeInterval = 3

    private let sources: [FeedSource]
    private let deadline: TimeInterval
    private let log: @Sendable (String) -> Void
    private var world = FeedWorld()
    private var buffer: [FeedEvent] = []
    private var subscribers: [UUID: AsyncStream<FeedBatch>.Continuation] = [:]
    private var failures = 0
    private var wakeRequested = false

    public init(sources: [FeedSource], deadline: TimeInterval = FeedEngine.sourceDeadline, log: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }) {
        self.sources = sources
        self.deadline = deadline
        self.log = log
    }

    public var state: FeedState { world.state }

    /// Events after `seq`, or nil when the buffer no longer reaches back that far (the subscriber
    /// should take the state again). A `seq` ahead of the feed (an earlier sidecar's) is also nil.
    public func events(after seq: Int) -> [FeedEvent]? {
        guard seq <= world.state.seq else { return nil }
        guard seq < world.state.seq else { return [] }
        guard let first = buffer.first, first.seq <= seq + 1 else { return nil }
        return buffer.filter { $0.seq > seq }
    }

    /// The state now with the events after `seq` (as `events(after:)`), read together so a poll
    /// cannot pair newer events with an older state.
    public func resume(after seq: Int?) -> (state: FeedState, missed: [FeedEvent]?) {
        (world.state, seq.flatMap(events(after:)))
    }

    /// Every change from now on: each poll or tick that changed the state, with its events.
    public func subscribe() -> (id: UUID, stream: AsyncStream<FeedBatch>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<FeedBatch>.makeStream(bufferingPolicy: .bufferingNewest(64))
        subscribers[id] = continuation
        return (id, stream)
    }

    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)?.finish()
    }

    /// One poll of every source, each within `sourceDeadline`.
    @discardableResult
    public func poll(now: Date = Date()) async -> [FeedEvent] {
        let started = Date()
        var readings: [Orb.Source: FeedReading?] = [:]
        let deadline = deadline
        await withTaskGroup(of: (Orb.Source, FeedReading?).self) { group in
            for source in sources {
                group.addTask {
                    let reading = await Self.withDeadline(deadline) { await source.reading(now: now) }
                    return (source.source, reading ?? nil)
                }
            }
            for await (source, reading) in group { readings[source] = reading }
        }
        failures = (readings[.t3] ?? nil) == nil ? failures + 1 : 0
        let took = Date().timeIntervalSince(started)
        if took > Self.slowPoll { log("t3boii-feed: a poll took \(String(format: "%.1f", took)) s") }
        let before = world.state
        return publish(world.absorb(readings, now: now.addingTimeInterval(took)), since: before)
    }

    public func tick(now: Date = Date()) -> [FeedEvent] {
        let before = world.state
        return publish(world.tick(now: now), since: before)
    }

    /// Polls until cancelled: every `busyInterval` while there are orbs, `quietInterval` without,
    /// slower while T3 cannot be read. `pollNow()` cuts a wait short.
    public func run() async {
        async let ticks: Void = runTicks()
        while !Task.isCancelled {
            await poll()
            await sleep(nextInterval())
        }
        await ticks
    }

    /// Cuts the current wait short, for a client that just connected.
    public func pollNow() {
        wakeRequested = true
    }

    func nextInterval() -> TimeInterval {
        if failures > 0 { return Self.backoff[min(failures, Self.backoff.count) - 1] }
        return world.state.orbs.isEmpty ? Self.quietInterval : Self.busyInterval
    }

    private func runTicks() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = tick()
        }
    }

    private func sleep(_ interval: TimeInterval) async {
        let until = Date().addingTimeInterval(interval)
        while !wakeRequested, !Task.isCancelled, Date() < until {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        wakeRequested = false
    }

    private func publish(_ events: [FeedEvent], since before: FeedState) -> [FeedEvent] {
        guard !events.isEmpty || world.state != before else { return events }
        buffer += events
        if buffer.count > Self.bufferSize { buffer.removeFirst(buffer.count - Self.bufferSize) }
        let batch = FeedBatch(events: events, state: world.state)
        for continuation in subscribers.values { continuation.yield(batch) }
        return events
    }

    static func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
