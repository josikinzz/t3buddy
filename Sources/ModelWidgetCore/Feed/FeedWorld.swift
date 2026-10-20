import Foundation

/// Turns successive source readings into `FeedState` plus the events between them.
///
/// The one rule everything else serves: unknown is not finished. A source with no reading keeps
/// its orbs as they were. An orb leaves with `finished` (he swallows it) only when its source said
/// it ended; one that just stops being listed leaves with `vanished` (it fades) after `missLimit`
/// readings without it. Grok Bot agents are the exception: the roster lists every agent, so one
/// missing from a good roster read has gone quiet, and that is its ending. A resync reading (T3
/// restarted, or its token changed) replaces its source's orbs without any event: one it no longer
/// lists just fades on the page, since a restart's cancellations are not endings worth a swallow.
public struct FeedWorld: Sendable {
    public static let missLimit = 2
    /// Past the slowest healthy cycle: a poll the call bucket paces can take about 6 s
    /// (`T3ThreadSource.pollTimeBudget` plus a call), then the 2 s wait.
    public static let laggingAfter: TimeInterval = 10
    public static let staleAfter: TimeInterval = 20

    /// Lagging until T3 has been read once, so a client can tell a feed that knows nothing yet.
    public private(set) var state = FeedState(source: .lagging)
    private var misses: [String: Int] = [:]
    private var rates: [String: ActivityRate] = [:]
    private var lastGood: [Orb.Source: Date] = [:]
    private var ended: [String] = []

    public init() {}

    /// One poll: a reading per source, nil for a source that could not be read.
    public mutating func absorb(_ readings: [Orb.Source: FeedReading?], now: Date) -> [FeedEvent] {
        var changes: [FeedChange] = []
        var orbs = Dictionary(uniqueKeysWithValues: state.orbs.map { ($0.id, $0) })
        var limits = state.limits
        var seeds = state.seeds
        for (source, reading) in readings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let reading, !reading.warming else { continue }
            let primed = lastGood[source] != nil
            lastGood[source] = now
            let found = absorb(reading, from: source, primed: primed, into: &orbs, now: now)
            if !reading.resync { changes += found }
            if source == .t3 {
                if !reading.resync { changes += Self.limitChanges(from: limits, to: reading.limits) }
                limits = reading.limits
                if let read = reading.seeds { seeds = read }
            }
        }
        let status = sourceStatus(now: now, polled: Set(readings.keys))
        if status != state.source { changes.append(.source(status)) }
        return commit(changes, orbs: orbs, limits: limits, seeds: seeds, status: status, now: now)
    }

    /// Re-judges staleness between polls, for a feed whose polls stopped arriving.
    public mutating func tick(now: Date) -> [FeedEvent] {
        let status = sourceStatus(now: now, polled: Set(lastGood.keys))
        guard status != state.source else { return [] }
        return commit([.source(status)], orbs: Dictionary(uniqueKeysWithValues: state.orbs.map { ($0.id, $0) }), limits: state.limits, seeds: state.seeds, status: status, now: now)
    }

    private mutating func absorb(_ reading: FeedReading, from source: Orb.Source, primed: Bool, into orbs: inout [String: Orb], now: Date) -> [FeedChange] {
        var changes: [FeedChange] = []
        var incoming = Dictionary(reading.orbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, count) in reading.itemCounts {
            rates[id, default: ActivityRate()].observe(count: count, at: now)
        }
        for id in incoming.keys.sorted() {
            guard var orb = incoming[id] else { continue }
            orb.level = rates[id]?.level
            incoming[id] = orb
            misses[id] = nil
            if let before = orbs[id] {
                changes += Self.differences(before, orb)
            } else if primed, !reading.known.contains(id) {
                if orb.state == .failed {
                    changes.append(.failed(id: id))
                } else {
                    changes.append(.started(id: id, cause: ended.contains(id) ? .resumed : .new))
                    if orb.state == .waiting, let kind = orb.waitingFor { changes.append(.askOpened(id: id, kind: kind)) }
                    if let until = orb.snoozedUntil { changes.append(.snoozed(id: id, until: until)) }
                }
            }
            orbs[id] = orb
        }
        for (id, orb) in orbs.sorted(by: { $0.key < $1.key }) where orb.source == source && incoming[id] == nil {
            if reading.resync {
                // Dropped quietly here, so no later reading can swallow it for this ending.
            } else if let status = reading.ended[id] ?? (source == .grok ? "quiet" : nil) {
                changes.append(.finished(id: id, status: status))
                remember(ended: id)
            } else {
                let count = (misses[id] ?? 0) + 1
                guard count >= Self.missLimit else {
                    misses[id] = count
                    continue
                }
                changes.append(.vanished(id: id))
            }
            orbs[id] = nil
            misses[id] = nil
            rates[id] = nil
        }
        for message in reading.messages where orbs[message.orbId] != nil {
            let fromQueue = changes.contains { if case let .queue(id, _) = $0 { return id == message.orbId } else { return false } }
            changes.append(.message(id: message.orbId, from: message.from, fromQueue: fromQueue))
        }
        for id in reading.seen.sorted() where orbs[id]?.state == .failed {
            changes.append(.failureSeen(id: id))
        }
        return changes
    }

    /// What changed in an orb that stayed.
    static func differences(_ before: Orb, _ after: Orb) -> [FeedChange] {
        let id = after.id
        var changes: [FeedChange] = []
        if before.state != .failed, after.state == .failed { changes.append(.failed(id: id)) }
        if before.state == .failed, after.state != .failed { changes.append(.started(id: id, cause: .resumed)) }
        let askedBefore = before.state == .waiting ? before.waitingFor : nil
        let askedAfter = after.state == .waiting ? after.waitingFor : nil
        if let kind = askedAfter, askedBefore != kind { changes.append(.askOpened(id: id, kind: kind)) }
        if askedBefore != nil, askedAfter == nil { changes.append(.askClosed(id: id)) }
        if let until = after.snoozedUntil, before.snoozedUntil == nil { changes.append(.snoozed(id: id, until: until)) }
        if before.snoozedUntil != nil, after.snoozedUntil == nil { changes.append(.woke(id: id)) }
        if before.provider != after.provider { changes.append(.providerChanged(id: id, from: before.provider, to: after.provider)) }
        if let from = before.model, let to = after.model, from != to { changes.append(.modelChanged(id: id, from: from, to: to)) }
        if (before.queue ?? 0) != (after.queue ?? 0) { changes.append(.queue(id: id, count: after.queue ?? 0)) }
        if before.pr != after.pr { changes.append(.prChanged(id: id, state: after.pr)) }
        return changes
    }

    private static func limitChanges(from old: [ProviderLimit], to new: [ProviderLimit]) -> [FeedChange] {
        let key = { (limit: ProviderLimit) in "\(limit.provider)@\(limit.since)" }
        let oldKeys = Set(old.map(key))
        let newKeys = Set(new.map(key))
        return new.filter { !oldKeys.contains(key($0)) }.map(FeedChange.limitStarted)
            + old.filter { !newKeys.contains(key($0)) }.map(FeedChange.limitCleared)
    }

    private func sourceStatus(now: Date, polled: Set<Orb.Source>) -> FeedSourceStatus {
        guard let t3 = lastGood[.t3] else { return polled.contains(.t3) ? .lagging : state.source }
        let age = now.timeIntervalSince(t3)
        return age < Self.laggingAfter ? .live : age < Self.staleAfter ? .lagging : .stale
    }

    private mutating func remember(ended id: String) {
        ended.removeAll { $0 == id }
        ended.append(id)
        if ended.count > 500 { ended.removeFirst(ended.count - 500) }
    }

    private mutating func commit(_ changes: [FeedChange], orbs: [String: Orb], limits: [ProviderLimit], seeds: [FeedSeed]?, status: FeedSourceStatus, now: Date) -> [FeedEvent] {
        let at = (now.timeIntervalSince1970 * 1000).rounded() / 1000
        var seq = state.seq
        let events = changes.map { change -> FeedEvent in
            seq += 1
            return FeedEvent(seq: seq, at: at, change: change)
        }
        state = FeedState(seq: seq, source: status, orbs: orbs.values.sorted { ($0.source.rawValue, $0.id) < ($1.source.rawValue, $1.id) }, limits: limits, seeds: seeds)
        return events
    }
}

/// How busy a thread is, from how fast its timeline grows: items a minute, smoothed over about 12 s.
public struct ActivityRate: Sendable, Equatable {
    public static let smoothing: TimeInterval = 12
    /// Items a minute that read as fully busy.
    public static let busy = 30.0

    private var lastCount: Int?
    private var lastAt: Date?
    public private(set) var perMinute = 0.0

    public init() {}

    public mutating func observe(count: Int, at now: Date) {
        defer { lastCount = count; lastAt = now }
        guard let lastCount, let lastAt else { return }
        let elapsed = now.timeIntervalSince(lastAt)
        guard elapsed > 0 else { return }
        let rate = Double(max(0, count - lastCount)) / elapsed * 60
        perMinute += (rate - perMinute) * (1 - exp(-elapsed / Self.smoothing))
    }

    /// 0 ... 1 in steps of 0.05, so small wobbles in the rate do not re-send the state.
    public var level: Double {
        let raw = min(1, log(1 + perMinute) / log(1 + Self.busy))
        return (raw * 20).rounded() / 20
    }
}
