import Darwin
import Foundation

public enum TokenProvider: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case kimi

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        }
    }

    /// A model name in a log that belongs to another provider, e.g. Kimi routed through Claude Code by CLI Proxy.
    static func forModel(_ model: String?, default fallback: TokenProvider) -> TokenProvider {
        guard let model = model?.lowercased() else { return fallback }
        if model.contains("kimi") { return .kimi }
        if model.hasPrefix("gpt-") || model.contains("codex") { return .codex }
        if model.hasPrefix("claude") { return .claude }
        return fallback
    }
}

/// Token counts by kind. `input` is fresh (uncached) input.
public struct TokenCounts: Equatable, Hashable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    /// Fresh input plus output: the part the graph stacks.
    public var fresh: Int { input + output }

    public var isEmpty: Bool { input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0 }

    public mutating func add(_ other: TokenCounts) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
    }

    func subtracting(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(input: input - other.input, output: output - other.output, cacheRead: cacheRead - other.cacheRead, cacheWrite: cacheWrite - other.cacheWrite)
    }

    func fieldwiseMax(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(input: max(input, other.input), output: max(output, other.output), cacheRead: max(cacheRead, other.cacheRead), cacheWrite: max(cacheWrite, other.cacheWrite))
    }
}

/// Tokens one provider used in one clock hour.
public struct TokenBucket: Equatable, Hashable, Sendable {
    public let provider: TokenProvider
    public let hour: Date
    public var counts: TokenCounts

    public init(provider: TokenProvider, hour: Date, counts: TokenCounts) {
        self.provider = provider
        self.hour = hour
        self.counts = counts
    }

    /// Fresh input plus output: the part the graph stacks.
    public var fresh: Int { counts.fresh }
}

/// Which session log shape a root holds.
public enum TokenLogFormat: Hashable, Sendable {
    /// Claude Code: `<config>/projects/**/*.jsonl`, assistant lines carrying `message.usage`.
    case claudeCode
    /// Codex: `<codex home>/sessions/**/rollout-*.jsonl`, `event_msg` lines with a cumulative `token_count`.
    case codexRollout
    /// Kimi Code: `<kimi home>/sessions/**/wire.jsonl`, `usage.record` lines with per-turn usage.
    case kimiWire

    var needle: [UInt8] {
        switch self {
        case .claudeCode: return Array(#""usage":{"#.utf8)
        case .codexRollout: return Array(#""token_count""#.utf8)
        case .kimiWire: return Array(#""usage.record""#.utf8)
        }
    }

    func accepts(fileName name: String) -> Bool {
        guard name.hasSuffix(".jsonl") else { return false }
        switch self {
        case .claudeCode: return true
        case .codexRollout: return name.hasPrefix("rollout-")
        case .kimiWire: return name == "wire.jsonl"
        }
    }
}

public struct TokenLogSource: Sendable, Equatable {
    public let format: TokenLogFormat
    public let root: URL

    public init(format: TokenLogFormat, root: URL) {
        self.format = format
        self.root = root
    }

    public static func == (lhs: TokenLogSource, rhs: TokenLogSource) -> Bool {
        lhs.format == rhs.format && lhs.root.standardizedFileURL.path == rhs.root.standardizedFileURL.path
    }

    /// Every session log root present on this machine: `~/.claude` plus any `~/.claude-*` or `CLAUDE_CONFIG_DIR`,
    /// `~/.codex` plus any `~/.codex-*` or `CODEX_HOME` (live and archived sessions), and `~/.kimi-code` or `~/.kimi`.
    public static func defaults(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [TokenLogSource] {
        let dotDirectories = ((try? fileManager.contentsOfDirectory(atPath: home.path)) ?? []).sorted()
        func homes(_ name: String, env: String) -> [URL] {
            var urls = [home.appendingPathComponent(".\(name)")]
            urls += dotDirectories.filter { $0.hasPrefix(".\(name)-") }.map { home.appendingPathComponent($0) }
            if let configured = environment[env], configured.isEmpty == false {
                urls.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath))
            }
            return urls
        }

        var sources: [TokenLogSource] = []
        for url in homes("claude", env: "CLAUDE_CONFIG_DIR") {
            sources.append(TokenLogSource(format: .claudeCode, root: url.appendingPathComponent("projects")))
        }
        for url in homes("codex", env: "CODEX_HOME") {
            sources.append(TokenLogSource(format: .codexRollout, root: url.appendingPathComponent("sessions")))
            sources.append(TokenLogSource(format: .codexRollout, root: url.appendingPathComponent("archived_sessions")))
        }
        for url in [home.appendingPathComponent(".kimi-code"), home.appendingPathComponent(".kimi")] {
            sources.append(TokenLogSource(format: .kimiWire, root: url.appendingPathComponent("sessions")))
        }

        var unique: [TokenLogSource] = []
        for source in sources where unique.contains(source) == false {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: source.root.path, isDirectory: &isDirectory), isDirectory.boolValue {
                unique.append(source)
            }
        }
        return unique
    }
}

public struct TokenScanStats: Equatable, Sendable {
    /// Log files modified inside the window.
    public var filesSeen = 0
    /// Files this refresh opened because they grew, are new, or were truncated.
    public var filesRead = 0
    public var bytesRead: Int64 = 0
    /// Lines longer than the reader's line cap, skipped without being parsed.
    public var linesSkipped = 0
    public var duration: TimeInterval = 0

    public init() {}
}

public struct TokenUsageSnapshot: Equatable, Sendable {
    /// Non-empty buckets inside the window, ordered by hour then provider.
    public let buckets: [TokenBucket]
    public let stats: TokenScanStats
    public let scannedAt: Date

    public init(buckets: [TokenBucket], stats: TokenScanStats, scannedAt: Date) {
        self.buckets = buckets
        self.stats = stats
        self.scannedAt = scannedAt
    }
}

/// Reads Claude Code, Codex, and Kimi session logs and buckets their token usage by hour.
///
/// The reader keeps a byte offset per file (keyed by device and inode, so a moved file is not reread) and on each
/// refresh reads only complete lines appended since the last one. A file that shrank is reread from the start and
/// replaces its earlier contribution. Only files modified inside the window are opened.
///
/// The file scan runs on a dedicated dispatch queue, not on the actor, so reading many large logs never holds a
/// Swift-concurrency pool thread. A line longer than `maxLineBytes` is skipped and counted, not buffered.
public actor TokenUsageReader {
    /// Longest line the reader buffers; Claude logs can carry a pasted image or a huge tool result on one line.
    public static let defaultMaxLineBytes = 32 << 20

    public let sources: [TokenLogSource]
    public let windowHours: Int
    public let maxLineBytes: Int

    private var files: [FileKey: FileState] = [:]
    private var pathKeys: [String: FileKey] = [:]
    /// Claude streams one message over several lines and resumed sessions copy history, so usage is kept per message id.
    private var claudeMessages: [String: ClaudeMessage] = [:]
    private var claudeBuckets: [BucketKey: TokenCounts] = [:]
    /// The refresh in progress; a second caller waits for it instead of interleaving at the scan's suspension point.
    private var running: Task<TokenUsageSnapshot, Never>?

    public init(sources: [TokenLogSource] = TokenLogSource.defaults(), days: Int = 7, maxLineBytes: Int = defaultMaxLineBytes) {
        self.sources = sources
        self.windowHours = days * 24
        self.maxLineBytes = max(1, maxLineBytes)
    }

    public func refresh(now: Date = Date()) async -> TokenUsageSnapshot {
        if let running {
            return await running.value
        }
        let task = Task { await self.performRefresh(now: now) }
        running = task
        let snapshot = await task.value
        running = nil
        return snapshot
    }

    private func performRefresh(now: Date) async -> TokenUsageSnapshot {
        let started = Date()
        var stats = TokenScanStats()
        let currentHour = Self.hourIndex(now.timeIntervalSince1970)
        let firstHour = currentHour - windowHours + 1
        let modifiedSince = Date(timeIntervalSince1970: TimeInterval(firstHour) * 3600)

        var seen = Set<FileKey>()
        var jobs: [ScanJob] = []
        for source in sources {
            for candidate in Self.candidates(in: source, modifiedSince: modifiedSince) {
                stats.filesSeen += 1
                if let key = pathKeys[candidate.path], let state = files[key], state.size == candidate.size {
                    seen.insert(key)
                    continue
                }
                var info = stat()
                guard stat(candidate.path, &info) == 0 else { continue }
                let key = FileKey(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
                let size = Int64(info.st_size)
                guard seen.insert(key).inserted else { continue }
                pathKeys[candidate.path] = key
                var state = files[key] ?? FileState(format: source.format)
                if size < state.offset {
                    state = FileState(format: source.format)
                }
                files[key] = state
                guard size != state.size else { continue }
                jobs.append(ScanJob(
                    key: key,
                    path: candidate.path,
                    format: source.format,
                    offset: state.offset,
                    codexTotal: state.codexTotal,
                    insideSkippedLine: state.insideSkippedLine,
                    maxLineBytes: maxLineBytes
                ))
            }
        }

        let results = await Self.scan(jobs, firstHour: firstHour)
        for result in results {
            guard var state = files[result.key] else { continue }
            if result.offset == 0 {
                state.contributions = [:]
            }
            stats.filesRead += 1
            stats.bytesRead += result.bytesRead
            stats.linesSkipped += result.linesSkipped
            state.offset = result.newOffset
            state.size = result.size
            state.codexTotal = result.codexTotal
            state.insideSkippedLine = result.endsInsideSkippedLine
            for record in result.records {
                if let id = record.messageID {
                    addClaude(id: id, key: record.key, counts: record.counts)
                } else {
                    state.contributions[record.key, default: TokenCounts()].add(record.counts)
                }
            }
            files[result.key] = state
        }

        prune(firstHour: firstHour, seen: seen)
        stats.duration = Date().timeIntervalSince(started)
        return TokenUsageSnapshot(buckets: buckets(firstHour: firstHour), stats: stats, scannedAt: now)
    }

    // MARK: - Aggregation

    private func addClaude(id: String, key: BucketKey, counts: TokenCounts) {
        guard var message = claudeMessages[id] else {
            claudeMessages[id] = ClaudeMessage(key: key, counts: counts)
            claudeBuckets[key, default: TokenCounts()].add(counts)
            return
        }
        // Later streamed lines repeat the message with output so far; keep the largest of each field.
        let merged = message.counts.fieldwiseMax(counts)
        claudeBuckets[message.key, default: TokenCounts()].add(merged.subtracting(message.counts))
        message.counts = merged
        claudeMessages[id] = message
    }

    private func prune(firstHour: Int, seen: Set<FileKey>) {
        claudeMessages = claudeMessages.filter { $0.value.key.hour >= firstHour }
        claudeBuckets = claudeBuckets.filter { $0.key.hour >= firstHour }
        for (key, var state) in files {
            state.contributions = state.contributions.filter { $0.key.hour >= firstHour }
            if seen.contains(key) == false && state.contributions.isEmpty {
                files[key] = nil
            } else {
                files[key] = state
            }
        }
        pathKeys = pathKeys.filter { files[$0.value] != nil }
    }

    private func buckets(firstHour: Int) -> [TokenBucket] {
        var totals = claudeBuckets
        for state in files.values {
            for (key, counts) in state.contributions {
                totals[key, default: TokenCounts()].add(counts)
            }
        }
        return totals
            .filter { $0.key.hour >= firstHour && $0.value.isEmpty == false }
            .sorted { $0.key.hour == $1.key.hour ? $0.key.provider.sortIndex < $1.key.provider.sortIndex : $0.key.hour < $1.key.hour }
            .map { key, counts in
                TokenBucket(provider: key.provider, hour: Date(timeIntervalSince1970: TimeInterval(key.hour) * 3600), counts: counts)
            }
    }

    // MARK: - File discovery

    private struct Candidate {
        let path: String
        let size: Int64
    }

    private static func candidates(in source: TokenLogSource, modifiedSince: Date) -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: source.root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [Candidate] = []
        for case let url as URL in enumerator where source.format.accepts(fileName: url.lastPathComponent) {
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let modified = values.contentModificationDate,
                modified >= modifiedSince
            else { continue }
            found.append(Candidate(path: url.path, size: Int64(values.fileSize ?? 0)))
        }
        return found
    }

    // MARK: - Parallel scan

    /// Reads the files in parallel on `scanQueue` and resumes the actor when every file is done.
    /// `concurrentPerform` caps the width at the core count; the calling actor is free while it runs.
    private static func scan(_ jobs: [ScanJob], firstHour: Int) async -> [ScanResult] {
        guard jobs.isEmpty == false else { return [] }
        return await withCheckedContinuation { continuation in
            scanQueue.async {
                let box = ResultBox(count: jobs.count)
                DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
                    box.set(index, TokenLogScanner.scan(jobs[index], firstHour: firstHour))
                }
                continuation.resume(returning: box.results.compactMap { $0 })
            }
        }
    }

    private static let scanQueue = DispatchQueue(label: "local.codex.LocalModelWidget.token-scan", qos: .utility)

    static func hourIndex(_ seconds: TimeInterval) -> Int {
        Int((seconds / 3600).rounded(.down))
    }
}

// MARK: - Internal state

struct FileKey: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct BucketKey: Hashable, Sendable {
    let provider: TokenProvider
    let hour: Int
}

/// Codex `total_token_usage`, cumulative over one rollout file. Kept as `TokenCounts` with OpenAI's meaning of
/// `input`: it includes the cached input that `cacheRead` also counts.
typealias CodexTotal = TokenCounts

private struct ClaudeMessage {
    let key: BucketKey
    var counts: TokenCounts
}

private struct FileState {
    let format: TokenLogFormat
    /// Byte offset just past the last complete line read.
    var offset: Int64 = 0
    /// File size at the last read, so an unchanged file is skipped without opening it.
    var size: Int64 = -1
    var codexTotal: CodexTotal?
    /// The last read stopped inside an over-long line; the next read drops bytes up to its newline.
    var insideSkippedLine = false
    /// Codex and Kimi usage this file added, so a truncated file can be reread without doubling.
    var contributions: [BucketKey: TokenCounts] = [:]

    init(format: TokenLogFormat) {
        self.format = format
    }
}

struct ScanJob: Sendable {
    let key: FileKey
    let path: String
    let format: TokenLogFormat
    let offset: Int64
    let codexTotal: CodexTotal?
    var insideSkippedLine = false
    var maxLineBytes = TokenUsageReader.defaultMaxLineBytes
}

struct ScanRecord: Sendable {
    let key: BucketKey
    let counts: TokenCounts
    /// Set for Claude lines, which are deduplicated by message id across files.
    let messageID: String?
}

struct ScanResult: Sendable {
    let key: FileKey
    let offset: Int64
    let newOffset: Int64
    let size: Int64
    let bytesRead: Int64
    let codexTotal: CodexTotal?
    let records: [ScanRecord]
    let linesSkipped: Int
    let endsInsideSkippedLine: Bool
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var results: [ScanResult?]

    init(count: Int) {
        results = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ result: ScanResult?) {
        lock.lock()
        results[index] = result
        lock.unlock()
    }
}

private extension TokenProvider {
    var sortIndex: Int { TokenProvider.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Line scanning

/// Reads complete lines from an offset, finds candidate lines by a byte needle, and parses only those.
///
/// The buffer starts at 4 MiB and doubles for a long line up to `job.maxLineBytes`. A line that fills the cap
/// without a newline is dropped: its bytes are consumed up to the next newline without being kept, and it is
/// counted in `linesSkipped` once its newline arrives (possibly in a later refresh).
enum TokenLogScanner {
    private static let chunkSize = 4 << 20

    static func scan(_ job: ScanJob, firstHour: Int) -> ScanResult? {
        let descriptor = open(job.path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        let size = Int64(info.st_size)
        let restart = job.offset > size
        let start = restart ? 0 : job.offset
        guard lseek(descriptor, off_t(start), SEEK_SET) >= 0 else { return nil }

        var parser = LineParser(format: job.format, firstHour: firstHour, codexTotal: start == 0 ? nil : job.codexTotal)
        let cap = max(1, job.maxLineBytes)
        var buffer = [UInt8](repeating: 0, count: min(chunkSize, cap))
        var filled = 0
        var consumed: Int64 = 0
        var bytesRead: Int64 = 0
        var skipping = restart ? false : job.insideSkippedLine
        var linesSkipped = 0
        let needle = job.format.needle

        func drop(_ count: Int) {
            consumed += Int64(count)
            if count < filled {
                buffer.withUnsafeMutableBytes { raw in
                    let base = raw.baseAddress!
                    memmove(base, base + count, filled - count)
                }
            }
            filled -= count
        }

        while true {
            if filled == buffer.count {
                if buffer.count >= cap {
                    // One line fills the whole cap: stop keeping it and skip to its newline.
                    drop(filled)
                    skipping = true
                } else {
                    buffer.append(contentsOf: [UInt8](repeating: 0, count: min(buffer.count, cap - buffer.count)))
                }
            }
            let count = buffer.withUnsafeMutableBytes { raw in
                read(descriptor, raw.baseAddress! + filled, raw.count - filled)
            }
            guard count > 0 else { break }
            bytesRead += Int64(count)
            filled += count

            if skipping {
                let newline: Int? = buffer.withUnsafeBytes { raw in
                    memchr(raw.baseAddress!, 0x0A, filled).map { raw.baseAddress!.distance(to: UnsafeRawPointer($0)) }
                }
                guard let newline else {
                    drop(filled)
                    continue
                }
                drop(newline + 1)
                skipping = false
                linesSkipped += 1
            }

            let complete: Int = buffer.withUnsafeBytes { raw in
                let base = raw.bindMemory(to: UInt8.self).baseAddress!
                var end = filled
                while end > 0, base[end - 1] != 0x0A { end -= 1 }
                guard end > 0 else { return 0 }
                parser.parseRegion(base, count: end, needle: needle)
                return end
            }
            if complete > 0 {
                drop(complete)
            }
        }

        return ScanResult(
            key: job.key,
            offset: start,
            newOffset: start + consumed,
            size: size,
            bytesRead: bytesRead,
            codexTotal: parser.codexTotal,
            records: parser.records,
            linesSkipped: linesSkipped,
            endsInsideSkippedLine: skipping
        )
    }
}

struct LineParser {
    let format: TokenLogFormat
    let firstHour: Int
    var codexTotal: CodexTotal?
    var records: [ScanRecord] = []

    init(format: TokenLogFormat, firstHour: Int, codexTotal: CodexTotal?) {
        self.format = format
        self.firstHour = firstHour
        self.codexTotal = codexTotal
    }

    /// `base[0..<count]` ends with a newline. Only lines containing `needle` are decoded.
    mutating func parseRegion(_ base: UnsafePointer<UInt8>, count: Int, needle: [UInt8]) {
        let end = base + count
        var cursor = base
        needle.withUnsafeBufferPointer { needleBytes in
            while cursor < end {
                guard let hit = memmem(cursor, end - cursor, needleBytes.baseAddress, needleBytes.count) else { return }
                let hitPointer = UnsafePointer(hit.assumingMemoryBound(to: UInt8.self))
                var lineStart = hitPointer
                while lineStart > cursor, lineStart[-1] != 0x0A { lineStart -= 1 }
                let remaining = end - hitPointer
                let newline = UnsafePointer(memchr(hitPointer, 0x0A, remaining)!.assumingMemoryBound(to: UInt8.self))
                parseLine(Data(bytes: lineStart, count: newline - lineStart))
                cursor = newline + 1
            }
        }
    }

    mutating func parseLine(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        switch format {
        case .claudeCode: parseClaude(object)
        case .codexRollout: parseCodex(object)
        case .kimiWire: parseKimi(object)
        }
    }

    private mutating func parseClaude(_ object: [String: Any]) {
        guard
            object["type"] as? String == "assistant",
            let message = object["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let id = message["id"] as? String,
            let hour = (object["timestamp"] as? String).flatMap(Self.hour(iso:)),
            hour >= firstHour
        else { return }
        let counts = TokenCounts(
            input: int(usage["input_tokens"]),
            output: int(usage["output_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            cacheWrite: int(usage["cache_creation_input_tokens"])
        )
        guard counts.isEmpty == false else { return }
        let provider = TokenProvider.forModel(message["model"] as? String, default: .claude)
        records.append(ScanRecord(key: BucketKey(provider: provider, hour: hour), counts: counts, messageID: id))
    }

    private mutating func parseCodex(_ object: [String: Any]) {
        guard
            object["type"] as? String == "event_msg",
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let info = payload["info"] as? [String: Any],
            let usage = info["total_token_usage"] as? [String: Any]
        else { return }
        // Totals are cumulative per rollout; repeated events carry the same total, so count only the growth.
        let total = CodexTotal(
            input: int(usage["input_tokens"]),
            output: int(usage["output_tokens"]),
            cacheRead: int(usage["cached_input_tokens"]),
            cacheWrite: int(usage["cache_write_input_tokens"])
        )
        let previous = codexTotal ?? CodexTotal()
        codexTotal = total
        guard let hour = (object["timestamp"] as? String).flatMap(Self.hour(iso:)), hour >= firstHour else { return }
        // Count only the growth; a total that went down (a rewrite) counts as zero growth.
        let growth = total.subtracting(previous).fieldwiseMax(TokenCounts())
        // OpenAI's input_tokens includes cached input.
        let counts = TokenCounts(
            input: max(0, growth.input - growth.cacheRead - growth.cacheWrite),
            output: growth.output,
            cacheRead: growth.cacheRead,
            cacheWrite: growth.cacheWrite
        )
        guard counts.isEmpty == false else { return }
        records.append(ScanRecord(key: BucketKey(provider: .codex, hour: hour), counts: counts, messageID: nil))
    }

    private mutating func parseKimi(_ object: [String: Any]) {
        guard
            object["type"] as? String == "usage.record",
            let usage = object["usage"] as? [String: Any],
            let millis = object["time"] as? NSNumber
        else { return }
        // `turn` is the only scope seen; skip anything that announces itself as a running total.
        if let scope = object["usageScope"] as? String, ["session", "total", "cumulative"].contains(scope) { return }
        let hour = TokenUsageReader.hourIndex(millis.doubleValue / 1000)
        guard hour >= firstHour else { return }
        let counts = TokenCounts(
            input: int(usage["inputOther"]),
            output: int(usage["output"]),
            cacheRead: int(usage["inputCacheRead"]),
            cacheWrite: int(usage["inputCacheCreation"])
        )
        guard counts.isEmpty == false else { return }
        let provider = TokenProvider.forModel(object["model"] as? String, default: .kimi)
        records.append(ScanRecord(key: BucketKey(provider: provider, hour: hour), counts: counts, messageID: nil))
    }

    private func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// Hour index for `YYYY-MM-DDTHH:MM:SS[.fff](Z|±HH:MM)` without a date formatter.
    static func hour(iso text: String) -> Int? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19, bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54 || bytes[10] == 0x20 else {
            return ISO8601DateFormatter().date(from: text).map { TokenUsageReader.hourIndex($0.timeIntervalSince1970) }
        }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(bytes[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16)
        else { return nil }
        // Offset suffix after optional fraction.
        var index = 19
        if index < bytes.count, bytes[index] == 0x2E {
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        var offsetMinutes = 0
        if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D, index + 6 <= bytes.count,
           let offsetHour = number(index + 1..<index + 3), let offsetMinute = number(index + 4..<index + 6) {
            offsetMinutes = (offsetHour * 60 + offsetMinute) * (bytes[index] == 0x2D ? -1 : 1)
        }
        let days = daysFromCivil(year: year, month: month, day: day)
        let minutes = days * 1440 + hour * 60 + minute - offsetMinutes
        return Int((Double(minutes) / 60).rounded(.down))
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
