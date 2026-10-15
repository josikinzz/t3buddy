import Foundation
import JavaScriptCore
import ModelWidgetCore

extension ModelWidgetChecks {
    static func orbitStateChecks(_ suite: inout CheckSuite) async {
        let project = T3Project(id: "p", title: "widgets", workspaceRoot: "/tmp/widgets")
        let icon = OrbIcon.monogram("WS", color: "#000000")

        // MARK: Status → state

        suite.check("T3 status maps to an orb state for every status, pending requests making it wait") {
            let expected: [(String, Orb.State?, Orb.State?)] = [
                // status, no pending request, a pending request
                ("preparing", .active, .waiting),
                ("queued", .active, .waiting),
                ("starting", .active, .waiting),
                ("running", .active, .waiting),
                // T3 holds a finished turn as `waiting` while its own background work or children run.
                ("waiting", .active, .waiting),
                ("failed", .failed, .failed),
                ("completed", nil, nil),
                ("interrupted", nil, nil),
                ("cancelled", nil, nil),
                ("rolled_back", nil, nil),
                ("idle", nil, nil),
                ("from-a-newer-t3", nil, nil)
            ]
            for (status, quiet, asking) in expected {
                let mapped = T3ThreadStatus(rawValue: status)
                try expect(mapped.orbState(pendingRequests: 0) == quiet, "\(status) without a request → \(String(describing: quiet)), got \(String(describing: mapped.orbState(pendingRequests: 0)))")
                try expect(mapped.orbState(pendingRequests: 2) == asking, "\(status) with requests → \(String(describing: asking))")
            }
        }

        suite.check("A thread read with a pending request turns its orb into a waiting orb") {
            let activity = try T3Payload.threadActivity(try toolPayload(threadReadResponse))
            try expectEqual(activity.threadId, "parent-1")
            try expectEqual(activity.pendingRequestCount, 1)
            try expectEqual(activity.activeRunId, "run:thread:parent-1:ordinal:3")
            try expectEqual(activity.nextPosition, 12)
            let parent = T3Thread(threadId: "parent-1", title: "orbit work", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent")
            let waiting = T3OrbMapper.orbs(project: project, threads: [parent], icon: icon, pendingRequests: ["parent-1": activity.pendingRequestCount])
            try expectEqual(waiting.map(\.state), [.waiting])
            let answered = T3OrbMapper.orbs(project: project, threads: [parent], icon: icon, pendingRequests: ["parent-1": 0])
            try expectEqual(answered.map(\.state), [.active])
        }

        suite.check("A held orb asks with a \"?\" when its thread wants your input, and alerts with \"!\" for an approval") {
            // `t3_pending_request_list` lists only questions; `pendingRequestCount` counts approvals too.
            let questions = try T3Payload.pendingQuestionIds(try toolPayload(wrap(#"{"requestIds":["request:q1"]}"#)))
            try expectEqual(questions, ["request:q1"])
            let parent = T3Thread(threadId: "parent-1", title: "orbit work", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent")
            func held(requests: Int, questions: Int) -> Orb? {
                T3OrbMapper.orbs(project: project, threads: [parent], icon: icon, pendingRequests: ["parent-1": requests], pendingQuestions: ["parent-1": questions]).first
            }
            try expectEqual(held(requests: 1, questions: 1)?.waitingFor, .input)
            try expectEqual(held(requests: 2, questions: 1)?.waitingFor, .input)
            try expectEqual(held(requests: 1, questions: 0)?.waitingFor, .approval)
            try expectEqual(held(requests: 0, questions: 0)?.waitingFor, nil)
            let json = String(decoding: try JSONEncoder().encode(OrbitSnapshot(orbs: held(requests: 1, questions: 1).map { [$0] } ?? [])), as: UTF8.self)
            try expect(json.contains(#""waitingFor":"input""#), "the page receives waitingFor: \(json)")

            // The page draws the mark from orbit.js's WAIT_MARK table.
            let orbit = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Pet/orbit.js").standardizedFileURL
            let source = try String(contentsOf: orbit, encoding: .utf8)
            guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix("const WAIT_MARK = ") }),
                  let table = line.dropFirst("const WAIT_MARK = ".count).split(separator: ";").first,
                  let marks = JSContext()?.evaluateScript("(\(table))")?.toDictionary() as? [String: String] else {
                throw CheckFailure.message("orbit.js has no WAIT_MARK table")
            }
            try expectEqual(marks[Orb.WaitingFor.input.rawValue], "?")
            try expectEqual(marks[Orb.WaitingFor.approval.rawValue], "!")
        }

        // MARK: Failed retention

        suite.check("A failed orb stays 60 s from first sight, then goes for good") {
            let t0 = Date(timeIntervalSince1970: 2_000_000)
            var retention = FailedOrbRetention()
            try expectEqual(retention.update(activeIds: ["t3:a"], failed: [], now: t0), [])
            // Seen active, then failed: shown from the poll that sees it.
            let failedA = FailedOrbRetention.Candidate(id: "t3:a", updatedAt: t0.addingTimeInterval(-3_600))
            try expectEqual(retention.update(activeIds: [], failed: [failedA], now: t0.addingTimeInterval(5)), ["t3:a"])
            try expectEqual(retention.update(activeIds: [], failed: [failedA], now: t0.addingTimeInterval(64)), ["t3:a"])
            try expectEqual(retention.update(activeIds: [], failed: [failedA], now: t0.addingTimeInterval(65)), [])
            try expectEqual(retention.update(activeIds: [], failed: [failedA], now: t0.addingTimeInterval(500)), [])
            // A failure from before the widget looked is history, not news.
            let old = FailedOrbRetention.Candidate(id: "t3:old", updatedAt: t0.addingTimeInterval(400))
            try expectEqual(retention.update(activeIds: [], failed: [old], now: t0.addingTimeInterval(500)), [])
            // One that failed between polls (never seen active) still shows while it is fresh.
            let quick = FailedOrbRetention.Candidate(id: "t3:quick", updatedAt: t0.addingTimeInterval(495))
            try expectEqual(retention.update(activeIds: [], failed: [quick], now: t0.addingTimeInterval(500)), ["t3:quick"])
            try expectEqual(retention.update(activeIds: [], failed: [quick], now: t0.addingTimeInterval(561)), [])
            // Active again, then failed again: a new 60 s.
            try expectEqual(retention.update(activeIds: ["t3:a"], failed: [], now: t0.addingTimeInterval(600)), [])
            try expectEqual(retention.update(activeIds: [], failed: [failedA], now: t0.addingTimeInterval(605)), ["t3:a"])
        }

        suite.check("The mapper shows a failed thread only while retention keeps it") {
            let failed = T3Thread(threadId: "f1", title: "broke", status: T3ThreadStatus(rawValue: "failed"), providerInstanceId: "codex")
            try expectEqual(T3OrbMapper.orbs(project: project, threads: [failed], icon: icon).map(\.id), [])
            let shown = T3OrbMapper.orbs(project: project, threads: [failed], icon: icon, failedShown: ["t3:f1"])
            try expectEqual(shown.map(\.state), [.failed])
        }

        // MARK: Subagents

        suite.check("A delegated child thread carries its parent's orb id; a native subagent shell is skipped") {
            let threads = try T3Payload.threads(try toolPayload(threadListResponse)).items
            try expectEqual(threads.map(\.creationSource), ["web", "mcp", "provider"])
            try expectEqual(threads[1].updatedAt, T3Payload.date("2026-10-15T00:47:25.181Z"))
            try expectEqual(threads[2].isProviderNativeSubagent, true)
            let orbs = T3OrbMapper.orbs(project: project, threads: threads, icon: icon)
            try expectEqual(orbs.map(\.id), ["t3:parent-1", "t3:mcp:child-1"])
            try expectEqual(orbs.map(\.parentId), [nil, "t3:parent-1"])
        }

        suite.check("Running subagents in the activity view become satellites carrying the parent's id") {
            let activity = try T3Payload.threadActivity(try toolPayload(threadReadResponse))
            let parent = T3Thread(threadId: "parent-1", title: "orbit work", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent")
            let satellites = T3OrbMapper.subagentOrbs(parent: parent, project: project, items: activity.items, icon: icon, driverKinds: ["claudeAgent": "claudeAgent"], failedShown: ["t3:node:provider:claudeAgent:native-item:task%3Abroke"]) {
                "http://127.0.0.1:3773/env/\($0)"
            }
            try expectEqual(satellites.map(\.id), [
                "t3:node:provider:claudeAgent:native-item:task%3Aaaa111",
                "t3:node:provider:claudeAgent:native-item:task%3Abroke",
                "t3:node:provider:claudeAgent:native-item:task%3Abbb222"
            ])
            try expect(satellites.allSatisfy { $0.parentId == "t3:parent-1" }, "every satellite carries its parent's id")
            try expectEqual(satellites.map(\.state), [.active, .failed, .active])
            try expectEqual(satellites[0].label, "widgets · Review the diff")
            try expectEqual(satellites[2].label, "widgets · subagent")
            try expectEqual(satellites[0].provider, "claudeAgent")
            try expectEqual(satellites[0].link, "http://127.0.0.1:3773/env/parent-1")
        }

        suite.check("A Claude subagent's satellite trails what its own thread is doing") {
            let parent = T3Thread(threadId: "6d82", title: "vibration", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent")
            // Shaped like T3 Code 0.0.46-nightly.20261015: the parent's `subagent` item and the idle thread T3 keeps for it.
            let claude = T3TimelineItem(position: 192, itemId: "turn-item:provider:claudeAgent:native-item:task%3Aa5b0%3Asubagent", subagentId: "node:provider:claudeAgent:native-item:task%3Aa5b0", type: "subagent", status: "running", title: "Status tails for subagent orbs", text: "Status tails for subagent orbs")
            let codex = T3TimelineItem(position: 437, itemId: "turn-item:provider:codex:native-item:call_d1aa%3A01a1410f-2d32", subagentId: "node:provider:codex:native-item:call_d1aa%3A01a1410f-2d32", type: "subagent", status: "running", title: "/root/review_runtime")
            func native(_ id: String, _ title: String, provider: String, parent: String = "6d82") -> T3Thread {
                T3Thread(threadId: id, title: title, status: T3ThreadStatus(rawValue: "idle"), providerInstanceId: provider, parentThreadId: parent, relationshipToParent: "subagent", creationSource: "provider", itemCount: 58)
            }
            let claudeThread = native("thread:provider:claudeAgent:native-thread:provider-thread%3Aprovider%3AclaudeAgent%3Anative-thread%3Apending%253Arun%253Athread%253A6d82%253Aordinal%253A6%3Aa5b0", "Status tails for subagent orbs", provider: "claudeAgent")
            let sibling = native("thread:provider:claudeAgent:native-thread:provider-thread%3Apending%3Aa338", "Limit crying", provider: "claudeAgent")
            let codexThread = native("thread:provider:codex:native-thread:01a1410f-2d32", "/root/review_runtime", provider: "codex")
            let listed = [sibling, codexThread, claudeThread, native("thread:elsewhere%3Aa5b0", "Status tails for subagent orbs", provider: "claudeAgent", parent: "other")]
            try expectEqual(T3OrbMapper.subagentThread(for: claude, parentThreadId: "6d82", among: listed)?.threadId, claudeThread.threadId)
            try expectEqual(T3OrbMapper.subagentThread(for: codex, parentThreadId: "6d82", among: listed)?.threadId, codexThread.threadId)
            // Its own thread's tail says what it is doing, in T3boii's words.
            let tail = [
                T3TimelineItem(position: 56, itemId: "a", type: "reasoning", status: "completed", title: "Thinking"),
                T3TimelineItem(position: 57, itemId: "b", type: "command_execution", status: "running", text: "$ cd /tmp/w && swift build 2>&1 | tail"),
                T3TimelineItem(position: 55, itemId: "c", type: "assistant_message", status: "completed", text: "Old news.")
            ]
            try expectEqual(T3ActivityPhrase.latest(in: tail), "running swift build")
            let orbs = T3OrbMapper.subagentOrbs(parent: parent, project: project, items: [claude, codex], icon: icon, driverKinds: ["claudeAgent": "claudeAgent"], activity: [claude.orbKey: "running swift build"])
            try expectEqual(orbs.map(\.activity), ["running swift build", nil])
            try expectEqual(orbs.map(\.parentId), ["t3:6d82", "t3:6d82"])

            // Not read yet: what it last reported to its parent, never its task or a prompt.
            func reported(_ text: String?, status: String = "running") -> String? {
                var item = claude
                item.text = text
                item.status = status
                return T3OrbMapper.subagentOrbs(parent: parent, project: project, items: [item], icon: icon, failedShown: [T3OrbMapper.orbId(item.orbKey)]).first?.activity
            }
            try expectEqual(reported("Running Check sounds, effects, and sad usage"), "running check sounds, effects, and sad usage")
            try expectEqual(reported("Reading /Users/tester/widgets/Resources/Pet/orbit.js"), "reading orbit.js")
            try expectEqual(reported("Status tails for subagent orbs"), nil)
            try expectEqual(reported("You are reviewing the diff.\nRead every file."), nil)
            try expectEqual(reported(String(repeating: "x", count: T3ActivityPhrase.readChars)), nil)
            try expectEqual(reported("Running Check sounds", status: "failed"), nil)

            // A delegated subagent is a thread of its own and trails its own activity too.
            let delegated = T3Thread(threadId: "thread:delegated-task:lids", title: "lids", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent", parentThreadId: "6d82", relationshipToParent: "subagent", creationSource: "mcp")
            let child = T3OrbMapper.orbs(project: project, threads: [delegated], icon: icon, activity: [delegated.threadId: "reading pet.js"])
            try expectEqual(child.map(\.activity), ["reading pet.js"])
            try expectEqual(child.map(\.parentId), ["t3:6d82"])
        }

        suite.check("Activity tracker reads the tail once, then new items plus windows around running subagents") {
            var tracker = T3ActivityTracker()
            typealias Read = T3ActivityTracker.Read
            // First poll: the last 400 of 505 items, a page at a time.
            try expectEqual(tracker.plannedReads(itemCount: 505), [Read(afterPosition: 104, limit: 100), Read(afterPosition: 204, limit: 100), Read(afterPosition: 304, limit: 100), Read(afterPosition: 404, limit: 100)])
            try expectEqual(T3ActivityTracker().plannedReads(itemCount: 30), [Read(afterPosition: nil, limit: 100)])
            tracker.absorb(page(items: [subagent(150, "s1", "running")], next: 204), read: Read(afterPosition: 104, limit: 100))
            tracker.absorb(page(items: [], next: 304), read: Read(afterPosition: 204, limit: 100))
            tracker.absorb(page(items: [subagent(320, "s2", "completed")], next: 404), read: Read(afterPosition: 304, limit: 100))
            tracker.absorb(page(items: [subagent(495, "s3", "running"), item(504)], next: 504), read: Read(afterPosition: 404, limit: 100))
            try expectEqual(tracker.scannedThrough, 504)
            try expectEqual(tracker.currentSubagents.filter(\.isWorkActive).map(\.orbKey), ["node:s1", "node:s3"])

            // Next poll: new items after 504, and one window from just before each running subagent.
            tracker.pruneFinished()
            try expectEqual(tracker.currentSubagents.map(\.orbKey), ["node:s1", "node:s3"])
            try expectEqual(tracker.plannedReads(itemCount: 510), [Read(afterPosition: 504, limit: 100), Read(afterPosition: 147, limit: 100), Read(afterPosition: 492, limit: 12)])
            tracker.absorb(page(items: [item(505)], next: 505), read: Read(afterPosition: 504, limit: 100))
            tracker.absorb(page(items: [item(148), subagent(150, "s1", "completed"), item(247)], next: 247), read: Read(afterPosition: 147, limit: 100))
            tracker.absorb(page(items: [subagent(495, "s3", "running"), item(504)], next: 504), read: Read(afterPosition: 492, limit: 12))
            try expectEqual(tracker.scannedThrough, 505)
            try expectEqual(tracker.currentSubagents.filter(\.isWorkActive).map(\.orbKey), ["node:s3"])

            // A running subagent missing from three re-reads of its window is dropped.
            for _ in 0..<3 {
                tracker.pruneFinished()
                tracker.absorb(page(items: [item(493), item(500)], next: 500), read: Read(afterPosition: 492, limit: 13))
            }
            try expectEqual(tracker.currentSubagents.map(\.orbKey), [])
        }

        // MARK: Token and polling

        suite.check("A thread's newest timeline item becomes a few words for T3boii's speech bubble") {
            func say(_ type: String, title: String? = nil, text: String? = nil) -> String? {
                T3ActivityPhrase.phrase(T3TimelineItem(position: 0, itemId: "i", type: type, status: "running", title: title, text: text))
            }
            try expectEqual(say("dynamic_tool", title: "Read /Users/tester/widgets/Resources/Pet/pet.js"), "reading pet.js")
            try expectEqual(say("dynamic_tool", title: "Edit /tmp/orbit.js"), "editing orbit.js")
            try expectEqual(say("command_execution", text: "$ cd /tmp/x && swift build --scratch-path .build\nCompiling"), "running swift build")
            try expectEqual(say("command_execution", text: "$ FOO=1 python3 - <<'EOF'"), "running python3")
            try expectEqual(say("command_execution", text: "$ git status --short"), "running git status")
            try expectEqual(say("reasoning", title: "Thinking", text: "Hmm"), "thinking…")
            try expectEqual(say("assistant_message", text: "I'm reading the pet code first; next I'll check the bridge. Then more."), "“I'm reading the pet code first; next…”")
            try expectEqual(say("dynamic_tool", text: #"{"toolName": "mcp__t3-code__t3_thread_read", "input": {}}"#), "using t3 thread read")
            try expectEqual(say("subagent", title: "Review the diff"), "delegating: Review the diff")
            try expect(say("dynamic_tool") == nil, "an item with nothing to say says nothing")

            var tracker = T3ActivityTracker()
            let first = T3TimelineItem(position: 4, itemId: "a", type: "command_execution", status: "completed", text: "$ npm test")
            let second = T3TimelineItem(position: 5, itemId: "b", type: "reasoning", status: "running", title: "Thinking")
            tracker.absorb(page(items: [first, second], next: 5), read: .init(afterPosition: 3, limit: 100))
            try expectEqual(tracker.latestPhrase, "thinking…")
            // A window re-read behind the newest item does not take it back.
            tracker.absorb(page(items: [first], next: 4), read: .init(afterPosition: 3, limit: 2))
            try expectEqual(tracker.latestPhrase, "thinking…")
            let thread = T3Thread(threadId: "t", title: "orbit", status: T3ThreadStatus(rawValue: "running"), updatedAt: Date(timeIntervalSince1970: 1_800_000_000.25))
            let orb = T3OrbMapper.orbs(project: project, threads: [thread], icon: icon, activity: ["t": "thinking…"]).first
            try expectEqual(orb?.activity, "thinking…")
            try expectClose(orb?.activeAt ?? 0, 1_800_000_000.25)
        }

        suite.check("The session id comes out of T3's bearer token, and only a safe one") {
            let token = T3MCPToken(accessToken: bearer(["v": 1, "kind": "session", "sid": "be31f15f-b8ce-479f-af6d-0dac7865fe06"]), expiresAt: nil)
            try expectEqual(token.sessionId, "be31f15f-b8ce-479f-af6d-0dac7865fe06")
            try expectEqual(T3MCPToken(accessToken: bearer(["v": 1, "kind": "session", "sid": "--all"]), expiresAt: nil).sessionId, nil)
            try expectEqual(T3MCPToken(accessToken: bearer(["v": 1, "kind": "refresh", "sid": "x"]), expiresAt: nil).sessionId, nil)
            try expectEqual(T3MCPToken(accessToken: "opaque", expiresAt: nil).sessionId, nil)
            try expect(!T3CLILocator.isSafeArgument("a b") && !T3CLILocator.isSafeArgument("x;rm") && T3CLILocator.isSafeArgument("abc-123"), "argument rule")
        }

        suite.check("The token file is private, atomic, and keeps the client id and sessions to revoke") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("t3token-\(UUID().uuidString)/LocalModelWidget")
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            let url = folder.appendingPathComponent("t3-mcp-token.json")
            let store = T3TokenFileStore(url: url)
            try expect(!store.exists, "no file yet")
            try expectEqual(store.load(), T3MCPCredentials())
            let token = T3MCPToken(accessToken: bearer(["v": 1, "kind": "session", "sid": "old-session"]), expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
            store.save(T3MCPCredentials(token: token, clientId: "client-1"))
            let folderMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
            let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            try expectEqual(folderMode?.intValue, 0o700)
            try expectEqual(fileMode?.intValue, 0o600)
            try expectEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["t3-mcp-token.json"])

            var reloaded = T3TokenFileStore(url: url).load()
            try expectEqual(reloaded, T3MCPCredentials(token: token, clientId: "client-1"))
            reloaded.retireToken()
            try expectEqual(reloaded, T3MCPCredentials(token: nil, clientId: "client-1", staleSessionIds: ["old-session"]))
        }

        await suite.check("A hung orbit source misses its deadline and falls back for one interval only") {
            let fast = await OrbitPolling.withDeadline(1) { 7 }
            try expectEqual(fast, 7)
            let started = Date()
            let hung: Int? = await OrbitPolling.withDeadline(0.05) {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return 1
            }
            try expectEqual(hung, nil)
            try expect(Date().timeIntervalSince(started) < 2, "the deadline returns without waiting for the work")

            let t0 = Date(timeIntervalSince1970: 3_000_000)
            var fallback = OrbitSourceFallback(maxAge: 6)
            let orbs = [Orb(id: "t3:a", source: .t3, projectIcon: icon, provider: "codex")]
            try expectEqual(fallback.resolve(source: 0, result: orbs, now: t0), orbs)
            try expectEqual(fallback.resolve(source: 0, result: nil, now: t0.addingTimeInterval(5)), orbs)
            try expectEqual(fallback.resolve(source: 0, result: nil, now: t0.addingTimeInterval(10)), [])
            try expectEqual(fallback.resolve(source: 1, result: nil, now: t0), [])
        }

        // MARK: Orb identity

        suite.check("A thread keeps its orb id across turns, messages and status changes") {
            func listed(_ status: String, run: Int, updated: Double) -> T3Thread {
                T3Thread(threadId: "mcp:efd", title: "polish", status: T3ThreadStatus(rawValue: status), providerInstanceId: "claudeAgent", itemCount: 1000 + run, updatedAt: Date(timeIntervalSince1970: updated))
            }
            let turns = [listed("running", run: 40, updated: 1), listed("waiting", run: 40, updated: 2), listed("queued", run: 41, updated: 3), listed("running", run: 41, updated: 4)]
            let ids = turns.flatMap { T3OrbMapper.orbs(project: project, threads: [$0], icon: icon).map(\.id) }
            try expectEqual(ids, Array(repeating: "t3:mcp:efd", count: 4))
        }

        suite.check("A delegated task is one orb: its thread, not its node in the parent's timeline as well") {
            let key = "command%3Amcp%3A4fc5%3Adelegate-task%3Alids"
            let node = T3TimelineItem(position: 978, itemId: "turn-item:delegated-task:\(key)", subagentId: "node:delegated-task:\(key)", type: "subagent", status: "running", title: "Fix lids")
            let native = subagent(979, "provider:claudeAgent:native-item:task%3Aa1", "running")
            try expect(!node.isSubagent && node.isDelegatedTask, "the delegated-task node must not be a satellite of its own")
            var tracker = T3ActivityTracker()
            tracker.absorb(T3ThreadActivity(threadId: "mcp:efd", status: T3ThreadStatus(rawValue: "completed"), activeRunId: nil, pendingRequestCount: 0, itemCount: 980, items: [node, native], nextPosition: 979, hasMore: false), read: .init(afterPosition: 900, limit: 100))
            try expectEqual(tracker.currentSubagents.map(\.orbKey), ["node:provider:claudeAgent:native-item:task%3Aa1"])
            let parent = T3Thread(threadId: "mcp:efd", title: "polish", status: T3ThreadStatus(rawValue: "completed"), providerInstanceId: "claudeAgent")
            let satellites = T3OrbMapper.subagentOrbs(parent: parent, project: project, items: [node, native], icon: icon)
            try expectEqual(satellites.map(\.id), ["t3:node:provider:claudeAgent:native-item:task%3Aa1"])
        }

        suite.check("A parent whose turn ended stays in orbit, active, while its satellites and delegated tasks work") {
            let parent = T3Thread(threadId: "mcp:efd", title: "polish", status: T3ThreadStatus(rawValue: "completed"), providerInstanceId: "claudeAgent")
            let delegated = T3Thread(threadId: "thread:delegated-task:lids", title: "lids", status: T3ThreadStatus(rawValue: "running"), providerInstanceId: "claudeAgent", parentThreadId: "mcp:efd", relationshipToParent: "subagent", creationSource: "mcp")
            let threads = T3OrbMapper.orbs(project: project, threads: [parent, delegated], icon: icon)
            try expectEqual(threads.map(\.id), ["t3:thread:delegated-task:lids"])
            let satellites = T3OrbMapper.subagentOrbs(parent: parent, project: project, items: [subagent(5, "sounds", "running")], icon: icon)
            let known = ["t3:mcp:efd": T3OrbMapper.threadOrb(project: project, thread: parent, state: .active, icon: icon)]
            let held = T3OrbMapper.holdingParents(threads + satellites) { known[$0] }
            try expectEqual(held.map(\.id).sorted(), ["t3:mcp:efd", "t3:node:sounds", "t3:thread:delegated-task:lids"])
            try expectEqual(held.first { $0.id == "t3:mcp:efd" }?.state, .active)
            try expectEqual(held.first { $0.id == "t3:mcp:efd" }?.parentId, nil)
            // A parent T3 no longer knows leaves its children circling T3boii rather than inventing one.
            try expectEqual(T3OrbMapper.holdingParents(satellites) { _ in nil }.map(\.id), ["t3:node:sounds"])
        }

        suite.check("An orb missing from one poll stays as it was; missing from two polls it goes") {
            func orb(_ id: String, parent: String? = nil, activity: String? = nil) -> Orb {
                Orb(id: id, parentId: parent, source: .t3, projectIcon: icon, provider: "claudeAgent", activity: activity)
            }
            var hold = OrbitRemovalHold()
            let full = OrbitSnapshot(orbs: [orb("t3:a", activity: "reading pet.js"), orb("t3:b")])
            try expectEqual(hold.apply(full), full)
            // A gap between two turns, a failed read, a timed-out source: same orb, last data.
            try expectEqual(hold.apply(OrbitSnapshot(orbs: [orb("t3:b")])), full)
            let back = OrbitSnapshot(orbs: [orb("t3:a", activity: "running swift build"), orb("t3:b")])
            try expectEqual(hold.apply(back), back)
            // A real finish: gone after the second poll without it.
            try expectEqual(hold.apply(OrbitSnapshot(orbs: [orb("t3:b")])).orbs.map(\.id), ["t3:a", "t3:b"])
            try expectEqual(hold.apply(OrbitSnapshot(orbs: [orb("t3:b")])).orbs.map(\.id), ["t3:b"])
            // A whole empty poll is a gap too.
            try expectEqual(hold.apply(OrbitSnapshot()).orbs.map(\.id), ["t3:b"])
            try expectEqual(hold.apply(OrbitSnapshot()).orbs, [])
        }

        suite.check("A parent missing from the snapshot is held while its satellites are in orbit") {
            func orb(_ id: String, parent: String? = nil) -> Orb {
                Orb(id: id, parentId: parent, source: .t3, projectIcon: icon, provider: "claudeAgent")
            }
            var hold = OrbitRemovalHold()
            _ = hold.apply(OrbitSnapshot(orbs: [orb("t3:p"), orb("t3:s1", parent: "t3:p"), orb("t3:s2", parent: "t3:s1")]))
            for _ in 0..<5 {
                let shown = hold.apply(OrbitSnapshot(orbs: [orb("t3:s2", parent: "t3:s1")]))
                try expectEqual(shown.orbs.map(\.id), ["t3:p", "t3:s1", "t3:s2"])
            }
            _ = hold.apply(OrbitSnapshot())
            try expectEqual(hold.apply(OrbitSnapshot()).orbs, [])
        }
    }
}

// MARK: Fixtures

private func toolPayload(_ response: String) throws -> Data {
    try MCPWire.toolPayload(try MCPWire.response(id: 9, body: Data(response.utf8), contentType: "application/json"))
}

private func bearer(_ claims: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: claims)
    return T3MCPAuth.base64URL(data) + ".c2lnbmF0dXJl"
}

private func item(_ position: Int) -> T3TimelineItem {
    T3TimelineItem(position: position, itemId: "turn-item:\(position)", type: "reasoning", status: "completed")
}

private func subagent(_ position: Int, _ task: String, _ status: String) -> T3TimelineItem {
    T3TimelineItem(position: position, itemId: "turn-item:\(task):subagent", subagentId: "node:\(task)", type: "subagent", status: status, title: task)
}

private func page(items: [T3TimelineItem], next: Int?) -> T3ThreadActivity {
    T3ThreadActivity(threadId: "p", status: T3ThreadStatus(rawValue: "running"), activeRunId: "r", pendingRequestCount: 0, itemCount: 506, items: items, nextPosition: next, hasMore: false)
}

/// A JSON-RPC `tools/call` response whose text block is `payload`.
private func wrap(_ payload: String) -> String {
    let encoded = try! JSONSerialization.data(withJSONObject: [payload])
    let quoted = String(decoding: encoded, as: UTF8.self).dropFirst().dropLast()
    return #"{"jsonrpc":"2.0","id":9,"result":{"content":[{"type":"text","text":"# + quoted + #"}],"isError":false}}"#
}

/// Shaped like a real `t3_thread_list` with `includeSubagents` (T3 Code 0.0.46-nightly.20261014.3118):
/// a web thread, a delegated `mcp` child, and a provider-native subagent shell listed as `idle`.
private let threadListResponse = wrap(#"{"projectId":"p","currentThreadId":null,"threads":[{"threadId":"parent-1","title":"orbit work","createdBy":"user","creationSource":"web","status":"running","latestRunId":"run:thread:parent-1:ordinal:3","providerInstanceId":"claudeAgent","model":"claude-opus-5-5","settled":false,"snoozed":false,"parentThreadId":null,"relationshipToParent":null,"itemCount":12,"createdAt":"2026-10-14T22:35:35.503Z","updatedAt":"2026-10-15T00:47:25.181Z"},{"threadId":"mcp:child-1","title":"delegated review","createdBy":"agent","creationSource":"mcp","status":"running","latestRunId":"run:thread:mcp%3Achild-1:ordinal:1","providerInstanceId":"codex","model":"gpt-6.1-sol","parentThreadId":"parent-1","relationshipToParent":"subagent","itemCount":4,"createdAt":"2026-10-15T00:40:00.000Z","updatedAt":"2026-10-15T00:47:25.181Z"},{"threadId":"thread:provider:claudeAgent:native-thread:provider-thread%3Aaaa111","title":"Review the diff","createdBy":"agent","creationSource":"provider","status":"idle","latestRunId":null,"providerInstanceId":"claudeAgent","parentThreadId":"parent-1","relationshipToParent":"subagent","itemCount":16,"createdAt":"2026-10-15T00:46:57.406Z","updatedAt":"2026-10-15T00:47:25.178Z"}],"nextCursor":null,"total":3}"#)

/// Shaped like a real `t3_thread_read` with `view: "activity"`: the thread detail (with
/// `pendingRequestCount`) and timeline items, four of them `subagent` items.
private let threadReadResponse = wrap(#"{"thread":{"threadId":"parent-1","projectId":"p","title":"orbit work","status":"running","latestRunId":"run:thread:parent-1:ordinal:3","activeRunId":"run:thread:parent-1:ordinal:3","providerInstanceId":"claudeAgent","parentThreadId":null,"relationshipToParent":null,"runCount":3,"itemCount":13,"pendingRequestCount":1,"archived":false,"settled":false},"recentRuns":[{"runId":"run:thread:parent-1:ordinal:3","ordinal":3,"status":"running","providerInstanceId":"claudeAgent","model":"claude-opus-5-5","requestedAt":"2026-10-15T00:45:52.877Z","startedAt":"2026-10-15T00:45:52.908Z","completedAt":null}],"items":[{"position":8,"visibility":"local","sourceThreadId":"parent-1","itemId":"turn-item:provider:claudeAgent:native-item:toolu_1","runId":"run:thread:parent-1:ordinal:3","messageId":null,"type":"command_execution","status":"completed","title":null,"text":"$","textTruncated":true,"nextTextOffset":1,"updatedAt":"2026-10-15T00:46:32.847Z"},{"position":9,"visibility":"local","sourceThreadId":"parent-1","itemId":"turn-item:provider:claudeAgent:native-item:task%3Aaaa111%3Asubagent","subagentId":"node:provider:claudeAgent:native-item:task%3Aaaa111","runId":"run:thread:parent-1:ordinal:3","messageId":null,"type":"subagent","status":"running","title":"Review the diff","text":"R","textTruncated":true,"nextTextOffset":1,"updatedAt":"2026-10-15T00:47:35.900Z"},{"position":10,"visibility":"local","sourceThreadId":"parent-1","itemId":"turn-item:provider:claudeAgent:native-item:task%3Adone%3Asubagent","subagentId":"node:provider:claudeAgent:native-item:task%3Adone","runId":"run:thread:parent-1:ordinal:3","type":"subagent","status":"completed","title":"Finished helper","text":"F","textTruncated":true,"updatedAt":"2026-10-15T00:47:10.000Z"},{"position":11,"visibility":"local","sourceThreadId":"parent-1","itemId":"turn-item:provider:claudeAgent:native-item:task%3Abroke%3Asubagent","subagentId":"node:provider:claudeAgent:native-item:task%3Abroke","runId":"run:thread:parent-1:ordinal:3","type":"subagent","status":"failed","title":"Broken helper","text":"B","textTruncated":true,"updatedAt":"2026-10-15T00:47:20.000Z"},{"position":12,"visibility":"local","sourceThreadId":"parent-1","itemId":"turn-item:provider:claudeAgent:native-item:task%3Abbb222%3Asubagent","subagentId":"node:provider:claudeAgent:native-item:task%3Abbb222","runId":"run:thread:parent-1:ordinal:3","type":"subagent","status":"pending","title":"","text":"","textTruncated":false,"nextTextOffset":null,"updatedAt":"2026-10-15T00:47:35.379Z"}],"nextPosition":12,"hasMore":false}"#)
