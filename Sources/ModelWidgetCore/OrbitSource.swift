import Foundation

/// Something that puts orbs in T3boii's orbit: T3 Code threads (`T3ThreadSource`) and Grok Bot agents (`GrokOrbitSource`).
/// A source that is not running, unreachable or unauthorised returns `[]` and does not throw.
public protocol OrbitSource: Sendable {
    func orbs(now: Date) async -> [Orb]
}

extension OrbitSnapshot {
    /// One snapshot from every source's orbs: the first orb with an id wins, and orbs are
    /// ordered by source then id, so an unchanged set compares equal whatever order sources answered in.
    public static func merged(_ lists: [[Orb]]) -> OrbitSnapshot {
        var seen = Set<String>()
        var orbs: [Orb] = []
        for orb in lists.joined() where seen.insert(orb.id).inserted {
            orbs.append(orb)
        }
        orbs.sort { ($0.source.rawValue, $0.id) < ($1.source.rawValue, $1.id) }
        return OrbitSnapshot(orbs: orbs)
    }

    /// The JSON the page's `window.t3boii.update(snapshot)` takes. Keys are sorted so equal snapshots encode identically.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return #"{"orbs":[]}"# }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Which orbs spawn and which are reabsorbed between two snapshots.
public enum OrbitDiff {
    public static func diff(old: OrbitSnapshot, new: OrbitSnapshot) -> (added: [String], removed: [String]) {
        let oldIds = Set(old.orbs.map(\.id))
        let newIds = Set(new.orbs.map(\.id))
        return (
            added: new.orbs.map(\.id).filter { !oldIds.contains($0) },
            removed: old.orbs.map(\.id).filter { !newIds.contains($0) }
        )
    }
}

/// Remembers the last snapshot sent to the page, so the page only hears about changes.
public struct OrbitChangeGate: Sendable {
    public private(set) var last: OrbitSnapshot?

    public init() {}

    /// The JSON to send when `snapshot` differs from the last one sent, else nil.
    public mutating func jsonIfChanged(_ snapshot: OrbitSnapshot) -> String? {
        guard snapshot != last else { return nil }
        last = snapshot
        return snapshot.json()
    }

    /// Forget the last snapshot, for a page that reloaded and lost its state.
    public mutating func reset() {
        last = nil
    }
}

/// Polling several orbit sources so that one stuck source never holds up the others.
public enum OrbitPolling {
    /// Runs `work` in its own task and returns its result, or nil once `seconds` pass first.
    /// The work is not awaited past the deadline: it finishes (or not) on its own.
    public static func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
        let gate = OnceGate<T?>()
        return await withCheckedContinuation { continuation in
            gate.continuation = continuation
            Task { gate.resume(await work()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                gate.resume(nil)
            }
        }
    }

    private final class OnceGate<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        var continuation: CheckedContinuation<Value, Never>?

        func resume(_ value: Value) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}

/// Which orbs a source contributes when a poll of it timed out: its last good orbs, but only
/// while they are at most one poll interval old, so a hung source empties instead of freezing.
public struct OrbitSourceFallback: Sendable {
    public let maxAge: TimeInterval
    private var lastGood: [Int: (orbs: [Orb], at: Date)] = [:]

    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    /// `result` is the source's orbs, or nil when its poll timed out or was still running.
    public mutating func resolve(source: Int, result: [Orb]?, now: Date) -> [Orb] {
        if let result {
            lastGood[source] = (result, now)
            return result
        }
        guard let last = lastGood[source], now.timeIntervalSince(last.at) <= maxAge else { return [] }
        return last.orbs
    }
}

/// Debounces orbs leaving the orbit, so a gap in what the sources report never reads as a thread
/// finishing and starting again. An orb missing from a poll stays, as it last was, until it has been
/// missing from `missLimit` polls in a row (a thread between two turns, a read that failed, a source
/// that timed out); one that comes back meanwhile is the same orb. An orb another orb names as its
/// parent stays while that child is in orbit, so satellites never fall out onto the halo.
public struct OrbitRemovalHold: Sendable {
    public static let defaultMissLimit = 2

    public let missLimit: Int
    private var known: [String: (orb: Orb, misses: Int)] = [:]

    public init(missLimit: Int = OrbitRemovalHold.defaultMissLimit) {
        self.missLimit = max(1, missLimit)
    }

    /// One poll's merged snapshot in, the snapshot to show out.
    public mutating func apply(_ snapshot: OrbitSnapshot) -> OrbitSnapshot {
        let incoming = Set(snapshot.orbs.map(\.id))
        for orb in snapshot.orbs { known[orb.id] = (orb, 0) }
        for (id, entry) in known where !incoming.contains(id) {
            known[id] = (entry.orb, entry.misses + 1)
        }
        var shown = Set(known.filter { $0.value.misses < missLimit }.keys)
        // Parents of anything shown stay, however long they have been missing.
        var queue = shown.compactMap { known[$0]?.orb.parentId }
        while let id = queue.popLast() {
            guard !shown.contains(id), let entry = known[id] else { continue }
            shown.insert(id)
            if let parent = entry.orb.parentId { queue.append(parent) }
        }
        known = known.filter { shown.contains($0.key) }
        return OrbitSnapshot.merged([known.values.map(\.orb)])
    }
}
