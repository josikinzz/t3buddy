import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func feedWorldChecks(_ suite: inout CheckSuite) async {
        let icon = OrbIcon.monogram("WS", color: "#000000")
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
        func orb(_ id: String, _ state: Orb.State = .active, parent: String? = nil, waitingFor: Orb.WaitingFor? = nil, provider: String = "claudeAgent", model: String? = nil, snoozedUntil: Double? = nil, queue: Int? = nil, source: Orb.Source = .t3) -> Orb {
            Orb(id: id, parentId: parent, source: source, projectIcon: icon, provider: provider, state: state, waitingFor: waitingFor, model: model, snoozedUntil: snoozedUntil, queue: queue)
        }
        func kinds(_ events: [FeedEvent]) -> [String] {
            events.compactMap { event -> String? in
                switch event.change {
                case let .started(id, cause): return "started \(id) \(cause.rawValue)"
                case let .finished(id, status): return "finished \(id) \(status)"
                case let .vanished(id): return "vanished \(id)"
                case let .failed(id): return "failed \(id)"
                case let .failureSeen(id): return "seen \(id)"
                case let .message(id, from, fromQueue): return "message \(id) \(from.rawValue)\(fromQueue ? " queued" : "")"
                case let .queue(id, count): return "queue \(id) \(count)"
                case let .askOpened(id, kind): return "ask \(id) \(kind.rawValue)"
                case let .askClosed(id): return "answered \(id)"
                case let .snoozed(id, _): return "snoozed \(id)"
                case let .woke(id): return "woke \(id)"
                case let .providerChanged(id, from, to): return "provider \(id) \(from)>\(to)"
                case let .modelChanged(id, from, to): return "model \(id) \(from)>\(to)"
                case let .prChanged(id, state): return "pr \(id) \(state?.rawValue ?? "none")"
                case let .limitStarted(limit): return "limit \(limit.provider)"
                case let .limitCleared(limit): return "cleared \(limit.provider)"
                case .source: return nil
                }
            }
        }
        func t3(_ orbs: [Orb], ended: [String: String] = [:], messages: [FeedMessage] = [], seen: Set<String> = [], counts: [String: Int] = [:], limits: [ProviderLimit] = []) -> [Orb.Source: FeedReading?] {
            [.t3: FeedReading(orbs: orbs, ended: ended, itemCounts: counts, messages: messages, seen: seen, limits: limits)]
        }

        suite.check("Feed: lagging until T3 is read in full; the first whole reading only sets the scene; later starts and T3-reported ends are events") {
            var world = FeedWorld()
            try expectEqual(world.state.source, .lagging)
            var partial = FeedReading(orbs: [orb("t3:b")])
            partial.warming = true
            try expectEqual(kinds(world.absorb([.t3: partial], now: at(-2))), [])
            try expectEqual(world.state.orbs.map(\.id), [])
            try expectEqual(world.state.source, .lagging)
            try expectEqual(kinds(world.absorb(t3([orb("t3:a")]), now: at(0))), [])
            try expectEqual(world.state.orbs.map(\.id), ["t3:a"])
            try expectEqual(world.state.source, .live)
            try expectEqual(kinds(world.absorb(t3([orb("t3:a"), orb("t3:b")]), now: at(2))), ["started t3:b new"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:b")], ended: ["t3:a": "completed"]), now: at(4))), ["finished t3:a completed"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a"), orb("t3:b")]), now: at(6))), ["started t3:a resumed"])
        }

        suite.check("Feed: seeds are kept between the polls that read them, and an empty list clears them") {
            var world = FeedWorld()
            let seed = FeedSeed(id: "task-1", provider: "codex", next: 100)
            _ = world.absorb([.t3: FeedReading(orbs: [orb("t3:a")], seeds: [seed])], now: at(0))
            try expectEqual(world.state.seeds, [seed])
            _ = world.absorb(t3([orb("t3:a")]), now: at(2))
            try expectEqual(world.state.seeds, [seed])
            _ = world.absorb(t3([orb("t3:a")]), now: at(4))
            _ = world.absorb([.t3: nil], now: at(6))
            try expectEqual(world.state.seeds, [seed])
            _ = world.absorb([.t3: FeedReading(orbs: [orb("t3:a")], seeds: [])], now: at(8))
            try expectEqual(world.state.seeds, [])
            try expect(!FeedJSON.encode(FeedState()).contains("seeds"), "a feed that does not read seeds sends no seeds key")
        }

        suite.check("Feed: T3 down for 40 s ends nothing and goes stale; a thread that ended meanwhile is swallowed once after") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a"), orb("t3:b")]), now: at(0))
            var statuses: [FeedSourceStatus] = []
            for step in 1...20 {
                let events = world.absorb([.t3: nil], now: at(Double(step) * 2))
                try expectEqual(kinds(events), [])
                for case let .source(status) in events.map(\.change) { statuses.append(status) }
            }
            try expectEqual(statuses, [.lagging, .stale])
            try expectEqual(world.state.orbs.map(\.id), ["t3:a", "t3:b"])
            let back = world.absorb(t3([orb("t3:b")], ended: ["t3:a": "completed"]), now: at(42))
            try expectEqual(kinds(back), ["finished t3:a completed"])
            try expectEqual(world.state.source, .live)
            try expectEqual(kinds(world.absorb(t3([orb("t3:b")]), now: at(44))), [])
        }

        suite.check("Feed: after a T3 restart or token change the resync reading sets the scene without one event, and swallows nothing later") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a"), orb("t3:b"), orb("t3:c", .waiting, waitingFor: .input)]), now: at(0))
            _ = world.absorb([.t3: nil], now: at(2))
            var resync = FeedReading(orbs: [orb("t3:b", provider: "codex"), orb("t3:new")], ended: ["t3:a": "cancelled", "t3:c": "interrupted"], messages: [FeedMessage(orbId: "t3:b", from: .user)])
            resync.resync = true
            try expectEqual(kinds(world.absorb([.t3: resync], now: at(30))), [])
            try expectEqual(world.state.orbs.map(\.id), ["t3:b", "t3:new"])
            try expectEqual(world.state.orbs.first?.provider, "codex")
            try expectEqual(kinds(world.absorb(t3([orb("t3:b", provider: "codex"), orb("t3:new")], ended: ["t3:a": "cancelled", "t3:c": "interrupted"]), now: at(32))), [])
            try expectEqual(kinds(world.absorb(t3([orb("t3:b", provider: "codex")], ended: ["t3:new": "completed"]), now: at(34))), ["finished t3:new completed"])
        }

        suite.check("Feed: polls the call bucket slows to one every 8 s stay live") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a")]), now: at(0))
            var statuses: [FeedSourceStatus] = []
            for second in 1...40 {
                let events = second % 8 == 0 ? world.absorb(t3([orb("t3:a")]), now: at(Double(second))) : world.tick(now: at(Double(second)))
                for case let .source(status) in events.map(\.change) { statuses.append(status) }
            }
            try expectEqual(statuses, [])
        }

        suite.check("Feed: an orb that stops being listed without T3 saying it ended fades after two readings, never swallowed") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a"), orb("t3:b")]), now: at(0))
            try expectEqual(kinds(world.absorb(t3([orb("t3:b")]), now: at(2))), [])
            try expectEqual(world.state.orbs.map(\.id), ["t3:a", "t3:b"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:b")]), now: at(4))), ["vanished t3:a"])
        }

        suite.check("Feed: a subagent is swallowed only on an ending status; idle or a status this client does not know just fades") {
            let statuses = ["sa-done": "completed", "sa-cancelled": "cancelled", "sa-idle": "idle", "sa-unknown": "future_status", "sa-running": "running"]
            let items = statuses.keys.sorted().enumerated().map { position, key in
                T3TimelineItem(position: position, itemId: key, type: "subagent", status: statuses[key]!)
            }
            var tracker = T3ActivityTracker()
            tracker.absorb(T3ThreadActivity(threadId: "th", status: T3ThreadStatus(rawValue: "running"), activeRunId: nil, pendingRequestCount: 0, itemCount: items.count, items: items, nextPosition: items.count - 1, hasMore: false), read: .init(afterPosition: nil, limit: 100))
            let satellites = statuses.keys.sorted().map { orb("t3:\($0)", parent: "t3:p") }
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:p")] + satellites), now: at(0))
            let stillListed = [orb("t3:p"), orb("t3:sa-running", parent: "t3:p")]
            try expectEqual(kinds(world.absorb(t3(stillListed, ended: T3OrbMapper.endedSubagents(tracker.currentSubagents)), now: at(2))), ["finished t3:sa-cancelled cancelled", "finished t3:sa-done completed"])
            try expectEqual(kinds(world.absorb(t3(stillListed), now: at(4))), ["vanished t3:sa-idle", "vanished t3:sa-unknown"])
        }

        suite.check("Feed: failure, the owner settling it, and a retry that mends it") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a"), orb("t3:b")]), now: at(0))
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", .failed), orb("t3:b")]), now: at(2))), ["failed t3:a"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", .failed), orb("t3:b", .failed)], seen: ["t3:a"]), now: at(4))), ["failed t3:b", "seen t3:a"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", .failed), orb("t3:b")]), now: at(6))), ["started t3:b resumed"])
        }

        suite.check("Feed: questions and approvals open and close; a thread that starts already asking says so") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a")]), now: at(0))
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", .waiting, waitingFor: .input)]), now: at(2))), ["ask t3:a input"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", .waiting, waitingFor: .approval)]), now: at(4))), ["ask t3:a approval"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a")]), now: at(6))), ["answered t3:a"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a"), orb("t3:b", .waiting, waitingFor: .input)]), now: at(8))), ["started t3:b new", "ask t3:b input"])
        }

        suite.check("Feed: messages say who sent them; one taken off the queue says so") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a", queue: 2)]), now: at(0))
            let events = world.absorb(t3([orb("t3:a", queue: 1)], messages: [FeedMessage(orbId: "t3:a", from: .user)]), now: at(2))
            try expectEqual(kinds(events), ["queue t3:a 1", "message t3:a user queued"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", queue: 1)], messages: [FeedMessage(orbId: "t3:a", from: .agent)]), now: at(4))), ["message t3:a agent"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a")], messages: [FeedMessage(orbId: "t3:gone", from: .user)]), now: at(6))), ["queue t3:a 0"])
        }

        suite.check("Feed: snoozing, waking, provider and model changes; nothing on first sight") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:a", provider: "codex", model: "gpt-6.1-sol")]), now: at(0))
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", provider: "codex", model: "gpt-6.1-sol", snoozedUntil: 4_000_600)]), now: at(2))), ["snoozed t3:a"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", provider: "codex", model: "gpt-6.1-sol")]), now: at(4))), ["woke t3:a"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", provider: "claudeAgent", model: "claude-opus-5-5")]), now: at(6))), ["provider t3:a codex>claudeAgent", "model t3:a gpt-6.1-sol>claude-opus-5-5"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a", provider: "claudeAgent", model: "claude-sonnet-5-5")]), now: at(8))), ["model t3:a claude-opus-5-5>claude-sonnet-5-5"])
        }

        suite.check("Feed: subagent moons start and finish; a Grok agent missing from a good roster read has finished") {
            var world = FeedWorld()
            let grok = { (orbs: [Orb]) -> FeedReading? in FeedReading(orbs: orbs) }
            _ = world.absorb([.t3: FeedReading(orbs: [orb("t3:p")]), .grok: grok([orb("grok:a", source: .grok)])], now: at(0))
            let spawned = world.absorb([.t3: FeedReading(orbs: [orb("t3:p"), orb("t3:m", parent: "t3:p")]), .grok: grok([orb("grok:a", source: .grok)])], now: at(2))
            try expectEqual(kinds(spawned), ["started t3:m new"])
            let done = world.absorb([.t3: FeedReading(orbs: [orb("t3:p")], ended: ["t3:m": "completed"]), .grok: grok([])], now: at(4))
            try expectEqual(kinds(done), ["finished grok:a quiet", "finished t3:m completed"])
            // Grok Bot unreadable keeps its agents.
            _ = world.absorb([.grok: grok([orb("grok:b", source: .grok)])], now: at(6))
            try expectEqual(kinds(world.absorb([.t3: FeedReading(orbs: [orb("t3:p")]), .grok: nil], now: at(8))), [])
            try expectEqual(world.state.orbs.map(\.id), ["grok:b", "t3:p"])
        }

        suite.check("Feed: a thread's level climbs with its item rate within about 20 s and settles within a minute of stopping") {
            var world = FeedWorld()
            var count = 0
            var levels: [Double] = []
            for step in 0...45 {
                if step <= 15 { count += 2 }
                _ = world.absorb(t3([orb("t3:a")], counts: ["t3:a": count]), now: at(Double(step) * 2))
                levels.append(world.state.orbs[0].level ?? -1)
            }
            try expectEqual(levels[0], 0)
            try expect(levels[10] >= 0.9, "60 items a minute for 20 s reads as busy, got \(levels[10])")
            try expect(zip(levels.dropFirst(), levels).prefix(14).allSatisfy { $0 >= $1 }, "the level only climbs while the thread stays busy: \(levels)")
            try expect(levels[45] <= 0.2, "a minute idle settles it, got \(levels[45])")
        }

        suite.check("Feed: limits start and clear once per episode; events and state round-trip through JSON") {
            var world = FeedWorld()
            let limit = ProviderLimit(provider: "kimi", since: 3_999_000)
            _ = world.absorb(t3([orb("t3:a")]), now: at(0))
            let started = world.absorb(t3([orb("t3:a")], limits: [limit]), now: at(2))
            try expectEqual(kinds(started), ["limit kimi"])
            try expectEqual(kinds(world.absorb(t3([orb("t3:a")], limits: [limit]), now: at(4))), [])
            let cleared = world.absorb(t3([orb("t3:a")]), now: at(6))
            try expectEqual(kinds(cleared), ["cleared kimi"])
            let all = started + cleared + world.absorb(t3([orb("t3:a", .waiting, waitingFor: .input, queue: 1)], messages: [FeedMessage(orbId: "t3:a", from: .user)]), now: at(8))
            let decoded = try JSONDecoder().decode([FeedEvent].self, from: Data(FeedJSON.encode(all).utf8))
            try expectEqual(decoded, all)
            try expectEqual(try JSONDecoder().decode(FeedState.self, from: Data(FeedJSON.encode(world.state).utf8)), world.state)
            try expect(FeedJSON.encode(started[0]).contains(#""kind":"limit.started""#), "events carry their kind on the wire")
        }

        suite.check("Feed: subagents found in a thread's history join quietly; ones that start later launch") {
            var world = FeedWorld()
            _ = world.absorb(t3([orb("t3:p")]), now: at(0))
            var reading = FeedReading(orbs: [orb("t3:p"), orb("t3:old", parent: "t3:p")], known: ["t3:old"])
            try expectEqual(kinds(world.absorb([.t3: reading], now: at(2))), [])
            reading = FeedReading(orbs: [orb("t3:p"), orb("t3:old", parent: "t3:p"), orb("t3:new", parent: "t3:p")])
            try expectEqual(kinds(world.absorb([.t3: reading], now: at(4))), ["started t3:new new"])
        }

        suite.check("Feed: a thread's messages count only once its history has been read to the end") {
            func item(_ position: Int, _ type: String = "assistant_message", by: String? = nil) -> T3TimelineItem {
                T3TimelineItem(position: position, itemId: "i\(position)", type: type, status: "completed", createdBy: by)
            }
            func page(_ items: [T3TimelineItem], count: Int, more: Bool) -> T3ThreadActivity {
                T3ThreadActivity(threadId: "th", status: T3ThreadStatus(rawValue: "running"), activeRunId: nil, pendingRequestCount: 0, itemCount: count, items: items, nextPosition: items.last?.position, hasMore: more)
            }
            var tracker = T3ActivityTracker()
            tracker.absorb(page([item(0, "user_message", by: "user"), item(1)], count: 4, more: true), read: .init(afterPosition: nil, limit: 2))
            tracker.pruneFinished()
            tracker.absorb(page([item(2, "user_message", by: "agent"), item(3)], count: 4, more: false), read: .init(afterPosition: 1, limit: 2))
            try expectEqual(tracker.arrivals.count, 0)
            tracker.pruneFinished()
            tracker.absorb(page([item(4, "user_message", by: "user")], count: 5, more: false), read: .init(afterPosition: 3, limit: 100))
            try expectEqual(tracker.arrivals.map(\.itemId), ["i4"])
        }
    }
}
