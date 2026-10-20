import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func providerLimitChecks(_ suite: inout CheckSuite) async {
        let t0 = Date(timeIntervalSince1970: 2_000_000)

        // MARK: Detection

        suite.check("Limit errors from every provider read as limits, in T3's own words") {
            // Each as T3 recorded it ending a run (title, text), from real timelines.
            let limits: [(String, String)] = [
                ("Usage limit reached", "You’ve hit your usage limit. Visit https://chatgpt.com/settings/usage to purchase more credits or try again at Oct 19th, 2026 10:58 PM."),
                ("Provider error", "Selected model is at capacity. Please try a different model."),
                ("Usage limit reached", "Claude API rate limit reached. Try again later."),
                ("Provider error", "Authentication required: 403 You've reached your 5-hour usage limit. Your quota will reset when the current 5-hour window ends."),
                ("Provider error", #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
                ("Provider error", #"{"type":"error","status":429,"error":{"type":"rate_limit_error","message":"Too many requests"}}"#),
                ("Provider error", "insufficient_quota: You exceeded your current quota, please check your plan and billing details.")
            ]
            for (title, text) in limits {
                try expect(ProviderLimitText.isLimit(errorItem(5, title: title, text: text)), "\(text) is a limit")
            }
            // T3's title alone says so even when the text is cut short.
            try expect(ProviderLimitText.isLimit(errorItem(5, title: "Usage limit reached", text: "")), "T3's title marks a limit")
            // A failed subagent's text is its error.
            let failedSubagent = T3TimelineItem(position: 6, itemId: "s", subagentId: "node:s", type: "subagent", status: "failed", title: "Fix preparation publication safety",
                                                text: "You’ve hit your usage limit. Visit https://chatgpt.com/settings/usage to purchase more credits")
            try expect(ProviderLimitText.isLimit(failedSubagent), "a subagent that died of a limit")
        }

        suite.check("Other failures, and chat or output that merely mentions limits, are not limits") {
            let errors = [
                "Claude gave up after repeated API errors.",
                "Workspace preparation failed during provision worktree: Git command failed in GitVcsDriver.createWorktree: git worktree add failed (branch_already_exists)",
                "Insufficient context allowance for the provider handoff. Compact the target conversation or use a larger-context model.",
                #"{"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-astra' model is not supported when using Codex with a ChatGPT account."}}"#,
                "workspace routing discovery timed out"
            ]
            for text in errors {
                try expect(!ProviderLimitText.isLimit(errorItem(5, title: "Provider error", text: text)), "\(text) is not a limit")
            }
            let words = "API Error: Request rejected (429) · rate_limit_error: This request would exceed your account's rate limit."
            let notErrors = [
                T3TimelineItem(position: 1, itemId: "a", type: "assistant_message", status: "completed", text: words),
                T3TimelineItem(position: 2, itemId: "u", type: "user_message", status: "completed", text: "when any provider hits a rate/usage limit, T3boii cries"),
                T3TimelineItem(position: 3, itemId: "c", type: "command_execution", status: "failed", text: "$ curl -sf https://api.example.com\ncurl: (22) The requested URL returned error: 429"),
                T3TimelineItem(position: 4, itemId: "s", subagentId: "node:s", type: "subagent", status: "completed", title: "Add rate limit handling", text: "Added a rate limiter."),
                T3TimelineItem(position: 5, itemId: "e", type: "error", status: "completed", title: "Usage limit reached", text: "")
            ]
            for item in notErrors {
                try expect(!ProviderLimitText.isLimit(item), "\(item.type) (\(item.status)) is not a limit")
            }
        }

        suite.check("A limit is the thread's state only until something happens in it again") {
            let runs = ["run:3": "claudeAgent"]
            let limited = errorItem(206, title: "Usage limit reached", text: "Claude API rate limit reached. Try again later.", run: "run:3")
            let found = ProviderLimitText.latestLimit(in: [message(204, "user_message"), message(205, "assistant_message", "API Error: Request rejected (429)"), limited], runProviders: runs)
            try expectEqual(found?.item.position, 206)
            try expectEqual(found?.providerInstanceId, "claudeAgent")
            // The owner sends another message: the thread is going again.
            try expect(ProviderLimitText.latestLimit(in: [message(207, "user_message", "try now")], runProviders: [:], current: found) == nil, "a new message clears it")
            // An item read again, or an earlier one, changes nothing.
            try expectEqual(ProviderLimitText.latestLimit(in: [message(150, "reasoning"), limited], runProviders: [:], current: found)?.item.position, 206)
            // The tracker carries it across reads.
            var tracker = T3ActivityTracker()
            tracker.absorb(activity([message(10, "reasoning"), errorItem(11, title: "Provider error", text: "Selected model is at capacity.", run: "run:1")], next: 11, runs: ["run:1": "codex"]), read: .init(afterPosition: nil, limit: 100))
            try expectEqual(tracker.limit?.providerInstanceId, "codex")
            tracker.absorb(activity([], next: nil), read: .init(afterPosition: 11, limit: 100))
            try expect(tracker.limit != nil, "an empty read keeps it")
            tracker.absorb(activity([message(12, "reasoning")], next: 12), read: .init(afterPosition: 11, limit: 100))
            try expect(tracker.limit == nil, "new work clears it")
        }

        suite.check("A limit belongs to the provider whose run it ended, by its badge id") {
            // A real failed read: the thread is on Claude now, but its last run (the one refused) was Codex's.
            let read = try T3Payload.threadActivity(try MCPWire.toolPayload(try MCPWire.response(id: 9, body: Data(handedOffRead.utf8), contentType: "application/json")))
            try expectEqual(read.runProviders["run:thread:mcp%3Ah:ordinal:4"], "codex")
            let limit = ProviderLimitText.latestLimit(in: read.items, runProviders: read.runProviders)
            try expectEqual(limit?.providerInstanceId, "codex")
            let kinds = ["codex": "codex", "claudeAgent": "claudeAgent", "kimi": "acpRegistry", "opencode": "opencode"]
            try expectEqual(T3OrbMapper.providerId(instance: limit?.providerInstanceId, driverKinds: kinds), "codex")
            // Kimi runs on T3's ACP registry driver: its badge is its instance id.
            try expectEqual(T3OrbMapper.providerId(instance: "kimi", driverKinds: kinds), "kimi")
            try expectEqual(T3OrbMapper.providerId(instance: "opencode", driverKinds: kinds), "opencode")
            try expectEqual(T3OrbMapper.providerId(instance: nil, driverKinds: kinds), "generic")
            // A subagent's error says whose words they are.
            try expectEqual(ProviderLimitText.providerHint("You’ve hit your usage limit. Visit https://chatgpt.com/settings/usage"), "codex")
            try expectEqual(ProviderLimitText.providerHint("upgrade your plan: https://www.kimi.com/membership/subscription"), "kimi")
            try expectEqual(ProviderLimitText.providerHint("Claude API rate limit reached."), "claudeAgent")
            try expectEqual(ProviderLimitText.providerHint("Selected model is at capacity."), nil)
        }

        suite.check("The time a provider gives to come back is read when it gives one") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let until = ProviderLimitText.until(in: "You’ve hit your usage limit. … or try again at Oct 19th, 2026 10:58 PM.", at: t0)
            try expectEqual(until, calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 22, minute: 58)))
            try expectEqual(ProviderLimitText.until(in: "Rate limited. Try again in 20 minutes.", at: t0), t0.addingTimeInterval(1200))
            try expectEqual(ProviderLimitText.until(in: "Claude API rate limit reached. Try again later.", at: t0), nil)
        }

        // MARK: Episodes

        suite.check("One limit episode per provider, however many threads hit it and however often they are read") {
            var episodes = ProviderLimitEpisodes()
            let a = ProviderLimitEpisodes.Sighting(provider: "codex", at: t0)
            let b = ProviderLimitEpisodes.Sighting(provider: "codex", at: t0.addingTimeInterval(20))
            let first = episodes.update(sightings: [b, a], progress: [], now: t0.addingTimeInterval(25))
            try expectEqual(first, [ProviderLimit(provider: "codex", since: t0.timeIntervalSince1970)])
            // Read again on every poll: still the one episode, same key.
            for poll in 1...6 {
                try expectEqual(episodes.update(sightings: [a, b], progress: [], now: t0.addingTimeInterval(25 + 5 * Double(poll))), first)
            }
            // Another thread of the same provider later on: the same episode.
            let c = ProviderLimitEpisodes.Sighting(provider: "codex", at: t0.addingTimeInterval(200))
            try expectEqual(episodes.update(sightings: [c], progress: [], now: t0.addingTimeInterval(205)), first)
            // Another provider: its own episode.
            let claude = ProviderLimitEpisodes.Sighting(provider: "claudeAgent", at: t0.addingTimeInterval(210))
            try expectEqual(episodes.update(sightings: [claude], progress: [], now: t0.addingTimeInterval(212)).map(\.provider), ["claudeAgent", "codex"])
            // A limit from long before anyone looked is history.
            var fresh = ProviderLimitEpisodes()
            try expectEqual(fresh.update(sightings: [a], progress: [], now: t0.addingTimeInterval(ProviderLimitEpisodes.freshness + 1)), [])
        }

        suite.check("A limit clears when the provider works again, when its time passes, or after a quiet spell, and does not come back") {
            let a = ProviderLimitEpisodes.Sighting(provider: "codex", at: t0)
            // Recovery: a running Codex thread still updating a minute after the limit.
            var episodes = ProviderLimitEpisodes()
            _ = episodes.update(sightings: [a], progress: [], now: t0.addingTimeInterval(5))
            let early = ProviderLimitEpisodes.Progress(provider: "codex", at: t0.addingTimeInterval(30))
            try expectEqual(episodes.update(sightings: [a], progress: [early], now: t0.addingTimeInterval(35)).count, 1)
            let otherProvider = ProviderLimitEpisodes.Progress(provider: "claudeAgent", at: t0.addingTimeInterval(120))
            try expectEqual(episodes.update(sightings: [a], progress: [otherProvider], now: t0.addingTimeInterval(125)).count, 1)
            let working = ProviderLimitEpisodes.Progress(provider: "codex", at: t0.addingTimeInterval(90))
            try expectEqual(episodes.update(sightings: [a], progress: [working], now: t0.addingTimeInterval(130)), [])
            // The failed thread is still reported with the old limit: that episode is over.
            try expectEqual(episodes.update(sightings: [a], progress: [], now: t0.addingTimeInterval(135)), [])
            // A new limit later is a new episode, with a new key.
            let again = ProviderLimitEpisodes.Sighting(provider: "codex", at: t0.addingTimeInterval(300))
            try expectEqual(episodes.update(sightings: [a, again], progress: [], now: t0.addingTimeInterval(305)), [ProviderLimit(provider: "codex", since: t0.timeIntervalSince1970 + 300)])

            // The time the provider gave passes.
            var timed = ProviderLimitEpisodes()
            let until = ProviderLimitEpisodes.Sighting(provider: "kimi", at: t0, until: t0.addingTimeInterval(120))
            try expectEqual(timed.update(sightings: [until], progress: [], now: t0.addingTimeInterval(5)), [ProviderLimit(provider: "kimi", since: t0.timeIntervalSince1970, until: t0.timeIntervalSince1970 + 120)])
            try expectEqual(timed.update(sightings: [until], progress: [], now: t0.addingTimeInterval(121)), [])

            // Nothing more heard of it for a while.
            var quiet = ProviderLimitEpisodes()
            _ = quiet.update(sightings: [a], progress: [], now: t0.addingTimeInterval(5))
            try expectEqual(quiet.update(sightings: [], progress: [], now: t0.addingTimeInterval(ProviderLimitEpisodes.quietLimit - 1)).count, 1)
            try expectEqual(quiet.update(sightings: [], progress: [], now: t0.addingTimeInterval(ProviderLimitEpisodes.quietLimit)), [])
        }

        // MARK: Orbs and snapshot

        suite.check("Orbs a limit hit are marked with its provider, their satellites too; the JSON says so only for them") {
            let face = OrbIcon.monogram("WS", color: "#000000")
            let orbs = [
                Orb(id: "t3:a", source: .t3, projectIcon: face, provider: "codex", state: .failed),
                Orb(id: "t3:a1", parentId: "t3:a", source: .t3, projectIcon: face, provider: "codex"),
                Orb(id: "t3:a1x", parentId: "t3:a1", source: .t3, projectIcon: face, provider: "codex"),
                Orb(id: "t3:b", source: .t3, projectIcon: face, provider: "codex"),
                Orb(id: "t3:c", source: .t3, projectIcon: face, provider: "claudeAgent"),
                Orb(id: "t3:c1", parentId: "t3:c", source: .t3, projectIcon: face, provider: "claudeAgent")
            ]
            let marked = ProviderLimitText.mark(orbs, hits: ["t3:a": "codex", "t3:c1": "codex"])
            try expectEqual(marked.filter { $0.limited == true }.map(\.id), ["t3:a", "t3:a1", "t3:a1x", "t3:c1"])
            try expectEqual(marked.map(\.limitProvider), ["codex", "codex", "codex", nil, nil, "codex"])
            try expectEqual(marked.map(\.id), orbs.map(\.id))
            let json = FeedJSON.encode(FeedState(orbs: Array(marked.prefix(4)), limits: [ProviderLimit(provider: "codex", since: 2_000_000.5)]))
            try expect(json.contains(#""limits":[{"provider":"codex","since":2000000.5}]"#), json)
            try expect(json.contains(#""limitProvider":"codex","limited":true"#), json)
            try expectEqual(json.components(separatedBy: #""limited""#).count - 1, 3)
            try expectEqual(FeedJSON.encode(FeedState(orbs: orbs)).contains("limited"), false)
        }

        suite.check("A limited orb keeps its identity and its place in the feed") {
            let face = OrbIcon.monogram("WS", color: "#000000")
            let start = Date(timeIntervalSince1970: 2_000_000)
            var world = FeedWorld()
            let parent = Orb(id: "t3:p", source: .t3, projectIcon: face, provider: "codex")
            let child = Orb(id: "t3:p1", parentId: "t3:p", source: .t3, projectIcon: face, provider: "codex")
            _ = world.absorb([.t3: FeedReading(orbs: [parent, child])], now: start)
            let limited = ProviderLimitText.mark([parent, child], hits: ["t3:p": "codex"])
            _ = world.absorb([.t3: FeedReading(orbs: limited)], now: start.addingTimeInterval(2))
            try expectEqual(world.state.orbs.map(\.id), ["t3:p", "t3:p1"])
            // Its thread drops out of T3's list for a poll: kept as it last was, still limited.
            _ = world.absorb([.t3: FeedReading(orbs: [])], now: start.addingTimeInterval(4))
            try expectEqual(world.state.orbs.map(\.limited), [true, true])
        }
    }
}

// MARK: Fixtures

private func errorItem(_ position: Int, title: String, text: String, run: String? = nil) -> T3TimelineItem {
    T3TimelineItem(position: position, itemId: "turn-item:error:\(position)", runId: run, type: "error", status: "failed", title: title, text: text, updatedAt: Date(timeIntervalSince1970: 2_000_000))
}

private func message(_ position: Int, _ type: String, _ text: String = "…") -> T3TimelineItem {
    T3TimelineItem(position: position, itemId: "turn-item:\(position)", type: type, status: "completed", text: text)
}

private func activity(_ items: [T3TimelineItem], next: Int?, runs: [String: String] = [:]) -> T3ThreadActivity {
    T3ThreadActivity(threadId: "t", status: T3ThreadStatus(rawValue: "running"), activeRunId: nil, pendingRequestCount: 0, itemCount: 12, items: items, nextPosition: next, hasMore: false, runProviders: runs)
}

/// Shaped like a real `t3_thread_read` (activity view, `runLimit: 1`) of a thread on Claude whose
/// last run, Codex's, was refused for Codex's usage limit.
private let handedOffRead = #"{"jsonrpc":"2.0","id":9,"result":{"structuredContent":{"thread":{"threadId":"mcp:h","projectId":"p","title":"Lamp keeper","status":"failed","latestRunId":"run:thread:mcp%3Ah:ordinal:4","activeRunId":null,"providerInstanceId":"claudeAgent","model":"claude-opus-5-5","itemCount":90,"pendingRequestCount":0},"recentRuns":[{"runId":"run:thread:mcp%3Ah:ordinal:4","ordinal":4,"status":"failed","providerInstanceId":"codex","model":"gpt-6.1-sol","requestedAt":"2026-10-14T18:49:00.000Z","startedAt":"2026-10-14T18:49:00.100Z","completedAt":"2026-10-14T18:50:01.000Z"}],"items":[{"position":88,"itemId":"turn-item:message:88","runId":"run:thread:mcp%3Ah:ordinal:4","type":"user_message","status":"completed","title":null,"text":"Keep going on the lamp keeper.","updatedAt":"2026-10-14T18:49:00.000Z"},{"position":89,"itemId":"turn-item:provider:codex:native-item:terminal-failure","runId":"run:thread:mcp%3Ah:ordinal:4","type":"error","status":"failed","title":"Usage limit reached","text":"You’ve hit your usage limit. Visit https://chatgpt.com/settings/usage to purchase more credits or try again at Oct 19th, 2026 10:58 PM.","updatedAt":"2026-10-14T18:50:00.900Z"}],"nextPosition":89,"hasMore":false}}}"#
