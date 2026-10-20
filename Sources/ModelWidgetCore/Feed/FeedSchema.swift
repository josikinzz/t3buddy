import Foundation

/// What one source saw in one successful poll. A source it could not read gives no reading at all,
/// which `FeedWorld` treats as "unknown", never as its threads ending.
public struct FeedReading: Equatable, Sendable {
    /// Everything this source puts around T3boii right now.
    public var orbs: [Orb]
    /// Orbs whose thread T3 reported ended this poll, with the status it reported (`completed`,
    /// `interrupted`, ...). Only these are swallowed; an orb that just stops being listed fades.
    public var ended: [String: String]
    /// Each orb's timeline item count, from which the world derives how busy it is.
    public var itemCounts: [String: Int]
    /// Messages that arrived in a thread since the previous reading, oldest first.
    public var messages: [FeedMessage]
    /// Failed orbs whose thread the owner has dealt with in T3 (settled or archived).
    public var seen: Set<String>
    public var limits: [ProviderLimit]
    /// Orbs that were there before the source could see them (a thread's history read for the
    /// first time): they join the scene without a start.
    public var known: Set<String>

    /// T3's enabled scheduled tasks (flag `seeds`), or nil when they were not read this poll.
    public var seeds: [FeedSeed]?
    /// The first reading after T3 restarted or its token changed. It is the truth from then on, but
    /// nothing in it is news: the world takes it without a single event (spec §2.5 rule 11).
    public var resync: Bool
    /// A fresh source still working through its first reads, a few per poll. It is not a whole
    /// reading yet, and the world takes none until it is: a feed that just started never fades an
    /// orb it simply has not reached, and stays lagging, so a client keeps what it shows.
    public var warming: Bool

    public init(orbs: [Orb] = [], ended: [String: String] = [:], itemCounts: [String: Int] = [:], messages: [FeedMessage] = [], seen: Set<String> = [], limits: [ProviderLimit] = [], known: Set<String> = [], seeds: [FeedSeed]? = nil, resync: Bool = false, warming: Bool = false) {
        self.orbs = orbs
        self.resync = resync
        self.warming = warming
        self.seeds = seeds
        self.known = known
        self.ended = ended
        self.itemCounts = itemCounts
        self.messages = messages
        self.seen = seen
        self.limits = limits
    }
}

/// A scheduled task, shown as a seed on a small halo over his head (flag `seeds`). Times are
/// seconds since 1970; a seed ripens toward `next` and drops into his T3 when `lastRun` moves on.
public struct FeedSeed: Codable, Equatable, Sendable {
    public var id: String
    public var provider: String
    public var next: Double?
    public var lastRun: Double?
    public var failed: Bool
    /// The orb of the thread its runs go to, when it is bound to one.
    public var orbId: String?

    public init(id: String, provider: String, next: Double? = nil, lastRun: Double? = nil, failed: Bool = false, orbId: String? = nil) {
        self.id = id
        self.provider = provider
        self.next = next
        self.lastRun = lastRun
        self.failed = failed
        self.orbId = orbId
    }
}

public struct FeedMessage: Equatable, Sendable {
    public var orbId: String
    public var from: FeedSender

    public init(orbId: String, from: FeedSender) {
        self.orbId = orbId
        self.from = from
    }
}

/// Who sent a message, as far as T3 records it: its owner, or anything else (a delegating
/// parent, an MCP caller, a bot), which T3 does not tell apart.
public enum FeedSender: String, Codable, Sendable {
    case user
    case agent
}

/// Whether the feed is current.
public enum FeedSourceStatus: String, Codable, Sendable {
    /// The last poll succeeded within `FeedWorld.laggingAfter`.
    case live
    /// Polls have failed for a few seconds, or none has read T3 yet: nothing visible changes yet.
    case lagging
    /// No good poll for `FeedWorld.staleAfter`: T3boii's orbs hold their breath and nothing spawns or is swallowed.
    case stale
}

/// One thing that happened, for the page to animate. The page's scene follows `FeedState`; events
/// only choose how a change looks, so a missed event means a plain transition, never a wrong scene.
public struct FeedEvent: Equatable, Sendable {
    public var seq: Int
    /// When the sidecar observed it, in seconds since 1970.
    public var at: Double
    public var change: FeedChange

    public init(seq: Int, at: Double, change: FeedChange) {
        self.seq = seq
        self.at = at
        self.change = change
    }
}

public enum FeedChange: Equatable, Sendable {
    public enum StartCause: String, Codable, Sendable {
        case new
        case resumed
    }

    /// Out of the T3 on his forehead (or out of its parent, for a subagent).
    case started(id: String, cause: StartCause)
    /// T3 said the thread ended: he swallows it.
    case finished(id: String, status: String)
    /// It stopped being listed without T3 saying it ended (deleted, archived, out of view): it fades.
    case vanished(id: String)
    case failed(id: String)
    case failureSeen(id: String)
    case message(id: String, from: FeedSender, fromQueue: Bool)
    case queue(id: String, count: Int)
    case askOpened(id: String, kind: Orb.WaitingFor)
    case askClosed(id: String)
    case snoozed(id: String, until: Double)
    case woke(id: String)
    case providerChanged(id: String, from: String, to: String)
    case modelChanged(id: String, from: String, to: String)
    case prChanged(id: String, state: Orb.PullRequestState?)
    case limitStarted(ProviderLimit)
    case limitCleared(ProviderLimit)
    case source(FeedSourceStatus)
}

extension FeedEvent: Codable {
    private enum Keys: String, CodingKey {
        case seq, at, kind, id, cause, status, from, fromQueue, count, ask, until, to, state, provider, since
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(at, forKey: .at)
        switch change {
        case let .started(id, cause):
            try c.encode("started", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(cause, forKey: .cause)
        case let .finished(id, status):
            try c.encode("finished", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(status, forKey: .status)
        case let .vanished(id):
            try c.encode("vanished", forKey: .kind); try c.encode(id, forKey: .id)
        case let .failed(id):
            try c.encode("failed", forKey: .kind); try c.encode(id, forKey: .id)
        case let .failureSeen(id):
            try c.encode("failure.seen", forKey: .kind); try c.encode(id, forKey: .id)
        case let .message(id, from, fromQueue):
            try c.encode("message", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(from, forKey: .from)
            if fromQueue { try c.encode(true, forKey: .fromQueue) }
        case let .queue(id, count):
            try c.encode("queue", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(count, forKey: .count)
        case let .askOpened(id, kind):
            try c.encode("ask.opened", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(kind, forKey: .ask)
        case let .askClosed(id):
            try c.encode("ask.closed", forKey: .kind); try c.encode(id, forKey: .id)
        case let .snoozed(id, until):
            try c.encode("snoozed", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(until, forKey: .until)
        case let .woke(id):
            try c.encode("woke", forKey: .kind); try c.encode(id, forKey: .id)
        case let .providerChanged(id, from, to):
            try c.encode("provider.changed", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        case let .modelChanged(id, from, to):
            try c.encode("model.changed", forKey: .kind); try c.encode(id, forKey: .id); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        case let .prChanged(id, state):
            try c.encode("pr.changed", forKey: .kind); try c.encode(id, forKey: .id); try c.encodeIfPresent(state, forKey: .state)
        case let .limitStarted(limit):
            try c.encode("limit.started", forKey: .kind); try c.encode(limit.provider, forKey: .provider); try c.encode(limit.since, forKey: .since); try c.encodeIfPresent(limit.until, forKey: .until)
        case let .limitCleared(limit):
            try c.encode("limit.cleared", forKey: .kind); try c.encode(limit.provider, forKey: .provider); try c.encode(limit.since, forKey: .since)
        case let .source(status):
            try c.encode("source", forKey: .kind); try c.encode(status, forKey: .status)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        at = try c.decode(Double.self, forKey: .at)
        let kind = try c.decode(String.self, forKey: .kind)
        func id() throws -> String { try c.decode(String.self, forKey: .id) }
        switch kind {
        case "started": change = .started(id: try id(), cause: try c.decode(FeedChange.StartCause.self, forKey: .cause))
        case "finished": change = .finished(id: try id(), status: try c.decode(String.self, forKey: .status))
        case "vanished": change = .vanished(id: try id())
        case "failed": change = .failed(id: try id())
        case "failure.seen": change = .failureSeen(id: try id())
        case "message": change = .message(id: try id(), from: try c.decode(FeedSender.self, forKey: .from), fromQueue: try c.decodeIfPresent(Bool.self, forKey: .fromQueue) ?? false)
        case "queue": change = .queue(id: try id(), count: try c.decode(Int.self, forKey: .count))
        case "ask.opened": change = .askOpened(id: try id(), kind: try c.decode(Orb.WaitingFor.self, forKey: .ask))
        case "ask.closed": change = .askClosed(id: try id())
        case "snoozed": change = .snoozed(id: try id(), until: try c.decode(Double.self, forKey: .until))
        case "woke": change = .woke(id: try id())
        case "provider.changed": change = .providerChanged(id: try id(), from: try c.decode(String.self, forKey: .from), to: try c.decode(String.self, forKey: .to))
        case "model.changed": change = .modelChanged(id: try id(), from: try c.decode(String.self, forKey: .from), to: try c.decode(String.self, forKey: .to))
        case "pr.changed": change = .prChanged(id: try id(), state: try c.decodeIfPresent(Orb.PullRequestState.self, forKey: .state))
        case "limit.started": change = .limitStarted(ProviderLimit(provider: try c.decode(String.self, forKey: .provider), since: try c.decode(Double.self, forKey: .since), until: try c.decodeIfPresent(Double.self, forKey: .until)))
        case "limit.cleared": change = .limitCleared(ProviderLimit(provider: try c.decode(String.self, forKey: .provider), since: try c.decode(Double.self, forKey: .since)))
        case "source": change = .source(try c.decode(FeedSourceStatus.self, forKey: .status))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown feed event \(kind)")
        }
    }
}

/// One change: its events, then the state they lead to.
public struct FeedBatch: Equatable, Sendable {
    public var events: [FeedEvent]
    public var state: FeedState

    public init(events: [FeedEvent], state: FeedState) {
        self.events = events
        self.state = state
    }
}

/// Everything around T3boii now: what the page reconciles its scene to.
public struct FeedState: Codable, Equatable, Sendable {
    public static let version = 1

    public var v: Int
    /// The last event this state includes, so a subscriber can ask for what came after.
    public var seq: Int
    public var source: FeedSourceStatus
    public var orbs: [Orb]
    public var limits: [ProviderLimit]
    /// Scheduled tasks, only when the feed reads them (flag `seeds`).
    public var seeds: [FeedSeed]?

    public init(seq: Int = 0, source: FeedSourceStatus = .live, orbs: [Orb] = [], limits: [ProviderLimit] = [], seeds: [FeedSeed]? = nil) {
        self.v = Self.version
        self.seq = seq
        self.source = source
        self.orbs = orbs
        self.limits = limits
        self.seeds = seeds
    }
}

public enum FeedJSON {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
