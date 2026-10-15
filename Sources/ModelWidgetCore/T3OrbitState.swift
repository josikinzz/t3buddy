import Foundation

/// How long a failed orb stays in the orbit: from the poll that first sees it failed, for
/// `duration` seconds, then never again unless it becomes active once more.
///
/// A failure counts as recent when this source saw the orb active on its previous poll, or
/// when T3 updated it within `duration` (a thread that failed before any poll caught it
/// active). So relaunching the widget does not bring back every failure in T3's history.
public struct FailedOrbRetention: Sendable {
    public static let defaultDuration: TimeInterval = 60

    public let duration: TimeInterval
    private var firstSeenFailed: [String: Date] = [:]
    private var expired: Set<String> = []
    private var lastActive: Set<String> = []

    public init(duration: TimeInterval = FailedOrbRetention.defaultDuration) {
        self.duration = duration
    }

    public struct Candidate: Equatable, Sendable {
        public var id: String
        /// When T3 last changed it, if known.
        public var updatedAt: Date?

        public init(id: String, updatedAt: Date? = nil) {
            self.id = id
            self.updatedAt = updatedAt
        }
    }

    /// One poll: `activeIds` are the orbs in orbit right now, `failed` the orbs T3 reports failed.
    /// Returns the failed orb ids to show.
    public mutating func update(activeIds: Set<String>, failed: [Candidate], now: Date) -> Set<String> {
        // An orb that is active again can fail again later.
        for id in activeIds {
            firstSeenFailed[id] = nil
            expired.remove(id)
        }
        var shown: Set<String> = []
        for candidate in failed where !activeIds.contains(candidate.id) && !expired.contains(candidate.id) {
            if let first = firstSeenFailed[candidate.id] {
                if now.timeIntervalSince(first) < duration {
                    shown.insert(candidate.id)
                } else {
                    firstSeenFailed[candidate.id] = nil
                    expired.insert(candidate.id)
                }
                continue
            }
            let fresh = candidate.updatedAt.map { now.timeIntervalSince($0) < duration } ?? false
            if lastActive.contains(candidate.id) || fresh {
                firstSeenFailed[candidate.id] = now
                shown.insert(candidate.id)
            } else {
                expired.insert(candidate.id)
            }
        }
        // A failure that left T3's failed list stops being tracked.
        let failedIds = Set(failed.map(\.id))
        firstSeenFailed = firstSeenFailed.filter { failedIds.contains($0.key) }
        lastActive = activeIds
        return shown
    }
}

/// Follows one active thread's activity timeline to find the provider-native subagents
/// (Claude's Agent tool, workflow agents) running inside it, with as few reads as it can.
///
/// T3 appends timeline items and updates them in place, so a running subagent keeps its
/// position while its status changes. Each poll reads new items once (`afterPosition` = the
/// last position seen) and re-reads only the windows around subagents still running. The
/// first poll of a thread reads its last `bootstrapItems` items.
public struct T3ActivityTracker: Sendable {
    public static let pageSize = 100
    public static let bootstrapItems = 400
    /// Positions re-read before a running subagent, in case T3 shifts items a little.
    static let margin = 2
    /// A running subagent missing from this many re-reads of its window is dropped.
    static let missLimit = 3

    public struct Read: Equatable, Sendable {
        /// `afterPosition` for `t3_thread_read`; nil reads from the start.
        public var afterPosition: Int?
        public var limit: Int

        public init(afterPosition: Int?, limit: Int) {
            self.afterPosition = afterPosition
            self.limit = limit
        }

        var range: ClosedRange<Int> {
            let first = (afterPosition ?? -1) + 1
            return first...(first + limit - 1)
        }
    }

    /// Subagent items by orb key, from the latest read that showed them.
    public private(set) var subagents: [String: T3TimelineItem] = [:]
    /// The newest item that says what the thread is doing, and those words.
    public private(set) var latest: T3TimelineItem?
    public private(set) var latestPhrase: String?
    /// The last position read; the next forward read starts after it.
    public private(set) var scannedThrough: Int?
    /// The provider refused the thread's latest work for a rate or usage limit, and nothing has
    /// happened in it since (`ProviderLimitText.latestLimit`).
    public private(set) var limit: T3LimitItem?
    private var misses: [String: Int] = [:]

    public init() {}

    /// The reads for this poll, the forward read first (it also refreshes the thread's
    /// pending request count). `itemCount` is the thread's item count from `t3_thread_list`.
    public func plannedReads(itemCount: Int?) -> [Read] {
        let page = Self.pageSize
        guard let scanned = scannedThrough else {
            let count = max(0, itemCount ?? 0)
            let start = max(0, count - Self.bootstrapItems)
            var reads: [Read] = []
            var first = start
            repeat {
                reads.append(Read(afterPosition: first == 0 ? nil : first - 1, limit: page))
                first += page
            } while first < count
            return reads
        }
        var reads = [Read(afterPosition: scanned >= 0 ? scanned : nil, limit: page)]
        // Running subagents behind the forward read, grouped into windows of one page each.
        let positions = subagents.values.filter { $0.isWorkActive && $0.position <= scanned }.map(\.position).sorted()
        var index = 0
        while index < positions.count {
            let first = max(0, positions[index] - Self.margin)
            let last = min(scanned, first + page - 1)
            reads.append(Read(afterPosition: first == 0 ? nil : first - 1, limit: last - first + 1))
            while index < positions.count, positions[index] <= last { index += 1 }
        }
        return reads
    }

    /// Takes in one read's page. Call once per planned read, in order.
    public mutating func absorb(_ activity: T3ThreadActivity, read: Read) {
        var seen: Set<String> = []
        for item in activity.items where item.position >= (latest?.position ?? -1) {
            guard let phrase = T3ActivityPhrase.phrase(item) else { continue }
            latest = item
            latestPhrase = phrase
        }
        limit = ProviderLimitText.latestLimit(in: activity.items, runProviders: activity.runProviders, current: limit)
        for item in activity.items where item.isSubagent {
            subagents[item.orbKey] = item
            misses[item.orbKey] = nil
            seen.insert(item.orbKey)
        }
        // A running subagent whose window came back without it has moved or gone.
        let positions = activity.items.map(\.position)
        if let low = positions.min(), let high = positions.max() {
            let covered = max(low, read.range.lowerBound)...max(max(low, read.range.lowerBound), min(high, read.range.upperBound))
            for (key, item) in subagents where item.isWorkActive && !seen.contains(key) && covered.contains(item.position) {
                let count = (misses[key] ?? 0) + 1
                if count >= Self.missLimit {
                    subagents[key] = nil
                    misses[key] = nil
                } else {
                    misses[key] = count
                }
            }
        }
        if let next = activity.nextPosition {
            scannedThrough = max(scannedThrough ?? next, next)
        } else if scannedThrough == nil, activity.items.isEmpty {
            // An empty thread (or an empty tail): start after whatever exists.
            scannedThrough = activity.itemCount - 1
        }
    }

    /// Forgets subagents that finished on an earlier poll; call at the start of each poll.
    public mutating func pruneFinished() {
        subagents = subagents.filter { $0.value.isWorkActive }
        misses = misses.filter { subagents[$0.key] != nil }
    }

    /// Subagent items as of the latest reads, oldest first.
    public var currentSubagents: [T3TimelineItem] {
        subagents.values.sorted { $0.position < $1.position }
    }
}

/// A few words on what a thread is doing, from its newest timeline item, in T3boii's voice:
/// "reading pet.js", "running swift build", "thinking…", or the start of what the agent said.
public enum T3ActivityPhrase {
    /// Characters of each item's text to read: enough for a command line or a first sentence.
    public static let readChars = 160
    public static let maxLength = 44

    /// Tool names (Claude's and Codex's) and how he says them.
    private static let verbs: [String: String] = [
        "read": "reading", "edit": "editing", "multiedit": "editing", "write": "writing", "notebookedit": "editing",
        "grep": "searching for", "glob": "looking for", "bash": "running", "webfetch": "fetching", "websearch": "searching for",
        "task": "delegating", "agent": "delegating", "todowrite": "updating its todos", "apply_patch": "editing", "shell": "running"
    ]
    /// Programs whose first argument is a subcommand worth saying: "git status", "swift build".
    private static let subcommandTools: Set<String> = ["git", "swift", "npm", "pnpm", "yarn", "bun", "cargo", "go", "make", "docker", "gh", "xcodebuild", "uv", "pip", "brew", "node", "deno", "kubectl"]

    public static func phrase(_ item: T3TimelineItem) -> String? {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let text = item.text ?? ""
        switch item.type {
        case "reasoning":
            return "thinking…"
        case "assistant_message":
            return quote(text)
        case "user_message":
            return "reading your message"
        case "command_execution":
            return command(text).map { "running \($0)" } ?? title.map(tool)
        case "subagent":
            return clip("delegating: \(title ?? "a subagent")")
        case "web_search":
            return "searching the web"
        default:
            if let title, title.lowercased() != "thinking" { return tool(title) }
            if let name = toolName(text) { return clip("using \(name)") }
            return nil
        }
    }

    /// "Read /a/b/pet.js" -> "reading pet.js"; an unknown tool keeps its title, lowercased.
    static func tool(_ title: String) -> String {
        let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = verbs[parts[0].lowercased()] else { return clip(title.prefix(1).lowercased() + title.dropFirst()) }
        guard parts.count > 1 else { return verb }
        var argument = parts[1].trimmingCharacters(in: .whitespaces)
        if argument.contains("/"), !argument.contains(" ") { argument = (argument as NSString).lastPathComponent }
        if verb == "running" { return command(argument).map { "running \($0)" } ?? clip("running \(argument)") }
        return clip("\(verb) \(argument)")
    }

    /// The program a command line runs, past any `cd … &&`: "swift build", "grep", "python3".
    static func command(_ text: String) -> String? {
        var line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if line.hasPrefix("$ ") { line.removeFirst(2) }
        let segments = line.components(separatedBy: CharacterSet(charactersIn: ";|&")).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let segment = segments.first(where: { !$0.isEmpty && !$0.hasPrefix("cd ") && !$0.hasPrefix("export ") }) else { return nil }
        // Leading `NAME=value` assignments are not the program.
        let words = segment.split(separator: " ").map(String.init).drop { $0.contains("=") && !$0.hasPrefix("-") }.map { $0 }
        guard let first = words.first else { return nil }
        let program = (first as NSString).lastPathComponent
        guard program.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil else { return nil }
        if subcommandTools.contains(program), words.count > 1, words[1].range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil {
            return "\(program) \(words[1])"
        }
        return program
    }

    /// The agent's own words, cut to its first sentence and quoted.
    static func quote(_ text: String) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        var sentence = flat
        if let end = flat.range(of: #"[.!?:](\s|$)"#, options: .regularExpression) { sentence = String(flat[..<end.lowerBound]) }
        return "“\(clip(sentence, room: maxLength - 2))”"
    }

    /// `"toolName": "mcp__t3-code__t3_thread_read"` -> "t3 thread read".
    static func toolName(_ text: String) -> String? {
        guard let range = text.range(of: #""toolName"\s*:\s*"([^"]+)""#, options: .regularExpression) else { return nil }
        var name = String(text[range]).components(separatedBy: "\"").dropLast().last ?? ""
        if name.hasPrefix("mcp__") { name = name.components(separatedBy: "__").last ?? name }
        name = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Cut at a word boundary to fit, with an ellipsis.
    static func clip(_ text: String, room: Int = maxLength) -> String {
        guard text.count > room else { return text }
        var cut = String(text.prefix(room - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > room / 2 { cut = String(cut[..<space]) }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-")) + "…"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
