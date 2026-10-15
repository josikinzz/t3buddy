import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

extension ModelWidgetChecks {
    static func tokenUsageChecks(_ suite: inout CheckSuite) async {
        // 2026-10-14T15:30:00Z; every fixture line below falls in the 15:00 UTC hour.
        let now = Date(timeIntervalSince1970: 1_791_991_800)
        let hour = Date(timeIntervalSince1970: 1_791_990_000)
        let stamp = "2026-10-14T15:12:05.250Z"

        func claudeLine(id: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int, model: String = "claude-opus-5-5", timestamp: String = stamp) -> String {
            #"{"parentUuid":null,"type":"assistant","timestamp":"\#(timestamp)","message":{"id":"\#(id)","model":"\#(model)","role":"assistant","content":[{"type":"text","text":"a \"usage\":{ inside text"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"service_tier":"standard"}}}"#
        }
        func codexLine(input: Int, cached: Int, output: Int, timestamp: String = stamp) -> String {
            #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"total_tokens":2}}}}"#
        }
        func kimiLine(other: Int, output: Int, cacheRead: Int, cacheCreation: Int, millis: Int64 = 1_791_990_725_000) -> String {
            #"{"type":"usage.record","agentId":"main","model":"kimi-code/k3","usage":{"inputOther":\#(other),"output":\#(output),"inputCacheRead":\#(cacheRead),"inputCacheCreation":\#(cacheCreation)},"usageScope":"turn","time":\#(millis)}"#
        }

        func makeRoots() throws -> (base: URL, claude: URL, codex: URL, kimi: URL) {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("token-usage-checks-\(UUID().uuidString)")
            let claude = base.appendingPathComponent("claude/projects/-Users-x-proj")
            let codex = base.appendingPathComponent("codex/sessions/2026/10/14")
            let kimi = base.appendingPathComponent("kimi/sessions/wd_x/session_1/agents/main")
            for dir in [claude, codex, kimi] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return (base, claude, codex, kimi)
        }
        func reader(_ base: URL) -> TokenUsageReader {
            TokenUsageReader(sources: [
                TokenLogSource(format: .claudeCode, root: base.appendingPathComponent("claude/projects")),
                TokenLogSource(format: .codexRollout, root: base.appendingPathComponent("codex/sessions")),
                TokenLogSource(format: .kimiWire, root: base.appendingPathComponent("kimi/sessions"))
            ])
        }
        func write(_ lines: [String], to url: URL, trailingNewline: Bool = true) throws {
            try (lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).write(to: url, atomically: false, encoding: .utf8)
        }
        func append(_ text: String, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        func bucket(_ snapshot: TokenUsageSnapshot, _ provider: TokenProvider) -> TokenBucket? {
            snapshot.buckets.first { $0.provider == provider && $0.hour == hour }
        }

        await suite.check("token usage parses one line per provider into its hour and fields") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            try write([claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)], to: roots.claude.appendingPathComponent("s.jsonl"))
            try write([codexLine(input: 1_000, cached: 600, output: 50)], to: roots.codex.appendingPathComponent("rollout-2026-10-14T15-00-00-a.jsonl"))
            try write([kimiLine(other: 7, output: 8, cacheRead: 900, cacheCreation: 3)], to: roots.kimi.appendingPathComponent("wire.jsonl"))
            let snapshot = await reader(roots.base).refresh(now: now)
            try expectEqual(bucket(snapshot, .claude), TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 10, output: 20, cacheRead: 300, cacheWrite: 40)))
            // Codex input_tokens includes cached reads, so fresh input is input minus cached.
            try expectEqual(bucket(snapshot, .codex), TokenBucket(provider: .codex, hour: hour, counts: TokenCounts(input: 400, output: 50, cacheRead: 600, cacheWrite: 0)))
            try expectEqual(bucket(snapshot, .kimi), TokenBucket(provider: .kimi, hour: hour, counts: TokenCounts(input: 7, output: 8, cacheRead: 900, cacheWrite: 3)))
            try expectEqual(snapshot.buckets.count, 3)
            try expectEqual(snapshot.stats.filesRead, 3)
        }

        await suite.check("token usage counts a duplicated Claude message id once, keeping its largest usage") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            try write([
                claudeLine(id: "msg_1", input: 10, output: 5, cacheRead: 300, cacheWrite: 40),
                claudeLine(id: "msg_1", input: 10, output: 5, cacheRead: 300, cacheWrite: 40),
                claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)
            ], to: roots.claude.appendingPathComponent("a.jsonl"))
            // A resumed session copies the same message into another file.
            try write([claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)], to: roots.claude.appendingPathComponent("b.jsonl"))
            let snapshot = await reader(roots.base).refresh(now: now)
            try expectEqual(bucket(snapshot, .claude), TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 10, output: 20, cacheRead: 300, cacheWrite: 40)))
        }

        await suite.check("token usage adds nothing on a second read of unchanged files") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            try write([claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)], to: roots.claude.appendingPathComponent("s.jsonl"))
            try write([codexLine(input: 1_000, cached: 600, output: 50)], to: roots.codex.appendingPathComponent("rollout-a.jsonl"))
            try write([kimiLine(other: 7, output: 8, cacheRead: 900, cacheCreation: 3)], to: roots.kimi.appendingPathComponent("wire.jsonl"))
            let tokens = reader(roots.base)
            let first = await tokens.refresh(now: now)
            let second = await tokens.refresh(now: now)
            try expectEqual(second.buckets, first.buckets)
            try expectEqual(second.stats.filesRead, 0)
            try expectEqual(second.stats.bytesRead, 0)
        }

        await suite.check("token usage reads only an appended line, as a per-turn delta for Codex") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            let claudeFile = roots.claude.appendingPathComponent("s.jsonl")
            let codexFile = roots.codex.appendingPathComponent("rollout-a.jsonl")
            let kimiFile = roots.kimi.appendingPathComponent("wire.jsonl")
            try write([claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)], to: claudeFile)
            try write([codexLine(input: 1_000, cached: 600, output: 50)], to: codexFile)
            try write([kimiLine(other: 7, output: 8, cacheRead: 900, cacheCreation: 3)], to: kimiFile)
            let tokens = reader(roots.base)
            _ = await tokens.refresh(now: now)

            let claudeAppend = claudeLine(id: "msg_2", input: 1, output: 2, cacheRead: 3, cacheWrite: 4) + "\n"
            try append(claudeAppend, to: claudeFile)
            // Codex totals are cumulative; a repeated total (rate-limit refresh) adds nothing.
            try append(codexLine(input: 1_500, cached: 1_000, output: 80) + "\n" + codexLine(input: 1_500, cached: 1_000, output: 80) + "\n", to: codexFile)
            try append(kimiLine(other: 1, output: 1, cacheRead: 1, cacheCreation: 1) + "\n", to: kimiFile)
            let snapshot = await tokens.refresh(now: now)
            try expectEqual(bucket(snapshot, .claude), TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 11, output: 22, cacheRead: 303, cacheWrite: 44)))
            try expectEqual(bucket(snapshot, .codex), TokenBucket(provider: .codex, hour: hour, counts: TokenCounts(input: 500, output: 80, cacheRead: 1_000, cacheWrite: 0)))
            try expectEqual(bucket(snapshot, .kimi), TokenBucket(provider: .kimi, hour: hour, counts: TokenCounts(input: 8, output: 9, cacheRead: 901, cacheWrite: 4)))
            try expectEqual(snapshot.stats.filesRead, 3)
            let appendedBytes = claudeAppend.utf8.count
            try expect(snapshot.stats.bytesRead < appendedBytes * 4, "Refresh must read only appended bytes, read \(snapshot.stats.bytesRead)")
        }

        await suite.check("token usage leaves a partial trailing line until it is complete") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            let file = roots.claude.appendingPathComponent("s.jsonl")
            let line = claudeLine(id: "msg_1", input: 10, output: 20, cacheRead: 300, cacheWrite: 40)
            let cut = line.index(line.startIndex, offsetBy: line.count / 2)
            try write([String(line[..<cut])], to: file, trailingNewline: false)
            let tokens = reader(roots.base)
            let partial = await tokens.refresh(now: now)
            try expect(partial.buckets.isEmpty, "A partial line must not count")
            try append(String(line[cut...]), to: file)
            let stillPartial = await tokens.refresh(now: now)
            try expect(stillPartial.buckets.isEmpty, "A line without its newline must not count")
            try append("\n", to: file)
            let complete = await tokens.refresh(now: now)
            try expectEqual(bucket(complete, .claude), TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 10, output: 20, cacheRead: 300, cacheWrite: 40)))
        }

        await suite.check("token usage drops lines older than 7 days and rereads a truncated file without doubling") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            let codexFile = roots.codex.appendingPathComponent("rollout-a.jsonl")
            try write([
                codexLine(input: 5_000, cached: 0, output: 500, timestamp: "2026-10-01T10:00:00Z"),
                codexLine(input: 6_000, cached: 400, output: 600)
            ], to: codexFile)
            let tokens = reader(roots.base)
            let first = await tokens.refresh(now: now)
            // Only the in-window delta counts: 1000 input (400 cached), 100 output.
            try expectEqual(first.buckets, [TokenBucket(provider: .codex, hour: hour, counts: TokenCounts(input: 600, output: 100, cacheRead: 400, cacheWrite: 0))])
            try write([codexLine(input: 50, cached: 0, output: 5)], to: codexFile)
            let rewritten = await tokens.refresh(now: now)
            try expectEqual(rewritten.buckets, [TokenBucket(provider: .codex, hour: hour, counts: TokenCounts(input: 50, output: 5, cacheRead: 0, cacheWrite: 0))])
        }

        await suite.check("token usage routes a Kimi model in a Claude log to Kimi") {
            let roots = try makeRoots()
            defer { try? FileManager.default.removeItem(at: roots.base) }
            try write([claudeLine(id: "msg_k", input: 1, output: 2, cacheRead: 0, cacheWrite: 0, model: "kimi-k3")], to: roots.claude.appendingPathComponent("s.jsonl"))
            let snapshot = await reader(roots.base).refresh(now: now)
            try expectEqual(snapshot.buckets.map(\.provider), [.kimi])
        }

        suite.check("token card stacks fresh input plus output and keeps cache reads apart") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let yesterday = hour.addingTimeInterval(-86_400)
            let buckets = [
                TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 100, output: 50, cacheRead: 734_000, cacheWrite: 10)),
                TokenBucket(provider: .codex, hour: hour, counts: TokenCounts(input: 30, output: 20, cacheRead: 5_000, cacheWrite: 0)),
                TokenBucket(provider: .kimi, hour: yesterday, counts: TokenCounts(input: 1_000, output: 0, cacheRead: 0, cacheWrite: 0))
            ]
            let card = TokenUsagePresentation.make(buckets: buckets, now: now, calendar: calendar)
            try expectEqual(card.todayTotal, 200)
            try expectEqual(card.todayText, "200")
            try expectEqual(card.hours.count, 168)
            try expectEqual(card.hours.last, hour)
            try expectEqual(card.freshPoints.count, 168 * TokenProvider.allCases.count)
            let current = card.freshPoints.filter { $0.hour == hour }
            try expectEqual(current.map(\.tokens), [150, 50, 0])
            try expectEqual(card.cachePoints.first { $0.hour == hour }?.tokens, 739_000)
            try expect(card.freshPoints.allSatisfy { $0.tokens < 10_000 }, "Cache reads must not stack into the fresh area")
            try expectEqual(card.legend.map(\.provider), [.claude, .codex, .kimi])
            try expectEqual(card.legend.map(\.today), [150, 50, 0])
            try expectEqual(TokenUsagePresentation.compact(1_234_567), "1.2M")
            try expectEqual(TokenUsagePresentation.compact(45_600), "45.6k")
        }
    }
}
