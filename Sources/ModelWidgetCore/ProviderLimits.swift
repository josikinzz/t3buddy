import Foundation

// Providers hitting a rate or usage limit, read from T3's timelines, for T3boii to cry over.
//
// The signal is T3's own record of a failed turn: when a provider refuses work, T3 ends the run
// with an `error` timeline item (status `failed`) whose title and text are the provider's words:
// "Usage limit reached" / "You've hit your usage limit … try again at Oct 19th, 2026 10:58 PM."
// (Codex), "Usage limit reached" / "Claude API rate limit reached." (Claude), "Provider error" /
// "… You've reached your 5-hour usage limit …" (Kimi), "Provider error" / "Selected model is at
// capacity." (Codex). Only failed `error` items (and failed subagent items, whose text is the
// subagent's error) are read, never what an agent or the owner says, so a chat about rate limits
// is not one. The run that failed names the provider (T3 keeps each run's provider; a thread
// handed to another provider keeps its old one on the thread).

/// A provider at a rate or usage limit right now: one per episode (see `ProviderLimitEpisodes`).
public struct ProviderLimit: Codable, Equatable, Sendable {
    /// The provider id orbs carry for their badge (`codex`, `claudeAgent`, `kimi`, ...).
    public var provider: String
    /// When the episode was first seen, in seconds since 1970. With `provider` it is the episode's
    /// stable key: the page cries once per key.
    public var since: Double
    /// When the provider said the limit lifts, if it said.
    public var until: Double?

    public init(provider: String, since: Double, until: Double? = nil) {
        self.provider = provider
        self.since = since
        self.until = until
    }
}

/// A timeline item where a provider refused work for a limit, and the provider instance whose run it ended.
public struct T3LimitItem: Equatable, Sendable {
    public var item: T3TimelineItem
    public var providerInstanceId: String?

    public init(item: T3TimelineItem, providerInstanceId: String?) {
        self.item = item
        self.providerInstanceId = providerInstanceId
    }
}

public enum ProviderLimitText {
    /// Provider words for a rate or usage limit, matched case-insensitively.
    static let patterns: [String] = [
        #"usage limit"#, #"rate[ _-]?limit"#, #"at capacity"#, #"overloaded"#, #"\b429\b"#, #"too many requests"#,
        #"limit reached"#, #"(?:reached|hit|exceeded) (?:your|the) [\w\s-]{0,24}limit"#,
        #"insufficient[_ ]quota"#, #"quota (?:exceeded|reached|will reset|has been)"#, #"exceeded (?:your |the )?(?:current )?quota"#, #"out of quota"#,
        #"out of credits"#, #"credits? (?:exhausted|depleted|run out)"#
    ]
    private static let regex = try? NSRegularExpression(pattern: patterns.joined(separator: "|"), options: [.caseInsensitive])

    /// Whether `text` reads as a rate or usage limit.
    public static func matches(_ text: String) -> Bool {
        guard let regex, !text.isEmpty else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether a timeline item is a provider refusing work for a limit: a failed `error` item (or a
    /// failed subagent, whose text is its error) in limit words. Messages are never limits.
    public static func isLimit(_ item: T3TimelineItem) -> Bool {
        guard item.isFailed, item.type == "error" || item.type == "subagent" else { return false }
        return matches(item.text ?? "") || (item.type == "error" && matches(item.title ?? ""))
    }

    /// The newest limit in `items` that nothing has followed since: a later message, tool call or
    /// thought means the thread got going again. `current` is what an earlier read found.
    /// `runProviders` maps run id to provider instance id (`T3ThreadActivity.runProviders`).
    public static func latestLimit(in items: [T3TimelineItem], runProviders: [String: String], current: T3LimitItem? = nil) -> T3LimitItem? {
        var limit = current
        for item in items.sorted(by: { $0.position < $1.position }) where item.position >= (limit?.item.position ?? -1) {
            if item.type == "error", isLimit(item) {
                limit = T3LimitItem(item: item, providerInstanceId: item.runId.flatMap { runProviders[$0] } ?? limit?.providerInstanceId)
            } else if let held = limit, item.position > held.item.position, item.type != "error",
                      item.type == "user_message" || T3ActivityPhrase.phrase(item) != nil {
                limit = nil
            }
        }
        return limit
    }

    /// When the provider says to come back: "try again at Oct 19th, 2026 10:58 PM" (local time), or
    /// "try again in 20 minutes" from `at`, when the item was written.
    public static func until(in text: String, at: Date) -> Date? {
        let lower = text.lowercased()
        if let range = lower.range(of: #"try again at ([a-z]{3,9}) (\d{1,2})(?:st|nd|rd|th)?,? (\d{4}),? (\d{1,2}:\d{2}) ?([ap]m)"#, options: .regularExpression) {
            let words = lower[range].dropFirst("try again at ".count).replacingOccurrences(of: #"(\d)(?:st|nd|rd|th)"#, with: "$1", options: .regularExpression)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            for format in ["MMM d, yyyy h:mm a", "MMMM d, yyyy h:mm a", "MMM d, yyyy h:mma", "MMM d yyyy h:mm a"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: words) { return date }
            }
        }
        if let range = lower.range(of: #"try again in (\d+) ?(second|sec|s|minute|min|m|hour|hr|h)"#, options: .regularExpression) {
            let parts = lower[range].dropFirst("try again in ".count)
            let amount = Double(parts.prefix { $0.isNumber }) ?? 0
            let unit = parts.drop { $0.isNumber || $0 == " " }
            let scale: Double = unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1
            return at.addingTimeInterval(amount * scale)
        }
        return nil
    }

    /// The provider whose words these are, when they say: a subagent's error can come from another
    /// provider than its parent thread's.
    public static func providerHint(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("chatgpt.com") || lower.contains("openai") { return "codex" }
        if lower.contains("kimi.com") || lower.contains("moonshot") { return "kimi" }
        if lower.contains("anthropic") || lower.contains("claude") { return "claudeAgent" }
        return nil
    }

    /// `orbs` with the ones that hit a limit marked: `hits` maps orb id to the provider that refused
    /// it. A marked orb's satellites go with it, wearing its provider.
    public static func mark(_ orbs: [Orb], hits: [String: String]) -> [Orb] {
        guard !hits.isEmpty else { return orbs }
        let byId = Dictionary(orbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func provider(_ orb: Orb, depth: Int = 0) -> String? {
            if let hit = hits[orb.id] { return hit }
            guard depth < 64, let parentId = orb.parentId, let parent = byId[parentId] else { return nil }
            return provider(parent, depth: depth + 1)
        }
        return orbs.map { orb in
            guard let limited = provider(orb) else { return orb }
            var orb = orb
            orb.limited = true
            orb.limitProvider = limited
            return orb
        }
    }
}

/// Turns sightings of limits into episodes: one per provider from its first sighting until it
/// clears, so T3boii cries once per limit however many threads hit it and however often they are
/// read again.
///
/// An episode ends when the provider is seen working again (a running thread of it updated at
/// least `recoveryProof` after its last limit), when the time the provider gave passes, or after
/// `quietLimit` with no new sighting. Sightings an ended episode already covered never open
/// another; a later one opens a new episode with a new key.
public struct ProviderLimitEpisodes: Sendable {
    /// An episode with no new sighting this long is over.
    public static let quietLimit: TimeInterval = 10 * 60
    /// A limit older than this when first read is history, not news (a relaunch, an old thread).
    public static let freshness: TimeInterval = 10 * 60
    /// Work this long after the last limit shows the provider has recovered.
    public static let recoveryProof: TimeInterval = 60

    public struct Sighting: Equatable, Sendable {
        public var provider: String
        /// When the provider refused (the timeline item's time).
        public var at: Date
        public var until: Date?

        public init(provider: String, at: Date, until: Date? = nil) {
            self.provider = provider
            self.at = at
            self.until = until
        }
    }

    /// A thread of `provider` doing work at `at`.
    public struct Progress: Equatable, Sendable {
        public var provider: String
        public var at: Date

        public init(provider: String, at: Date) {
            self.provider = provider
            self.at = at
        }
    }

    private struct Episode: Sendable {
        var since: Date
        var last: Date
        var until: Date?
    }

    private var open: [String: Episode] = [:]
    /// Per provider, sightings at or before this belong to an episode that has ended.
    private var spentThrough: [String: Date] = [:]

    public init() {}

    /// One poll: the limits seen and the work seen. Returns the providers at a limit now.
    public mutating func update(sightings: [Sighting], progress: [Progress], now: Date) -> [ProviderLimit] {
        for sighting in sightings.sorted(by: { $0.at < $1.at }) {
            guard now.timeIntervalSince(sighting.at) < Self.freshness,
                  sighting.at > (spentThrough[sighting.provider] ?? .distantPast) else { continue }
            if var episode = open[sighting.provider] {
                episode.last = max(episode.last, sighting.at)
                if let until = sighting.until { episode.until = max(episode.until ?? until, until) }
                open[sighting.provider] = episode
            } else {
                open[sighting.provider] = Episode(since: sighting.at, last: sighting.at, until: sighting.until)
            }
        }
        for (provider, episode) in open {
            let working = progress.contains { $0.provider == provider && $0.at.timeIntervalSince(episode.last) >= Self.recoveryProof }
            let lifted = episode.until.map { now >= $0 } ?? false
            let quiet = now.timeIntervalSince(episode.last) >= Self.quietLimit
            guard working || lifted || quiet else { continue }
            open[provider] = nil
            spentThrough[provider] = max(spentThrough[provider] ?? .distantPast, episode.last)
        }
        return open.sorted { $0.key < $1.key }.map { provider, episode in
            ProviderLimit(provider: provider, since: Self.seconds(episode.since), until: episode.until.map(Self.seconds))
        }
    }

    /// Seconds since 1970 to the millisecond, as orbs carry `activeAt`.
    private static func seconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded() / 1000
    }
}
