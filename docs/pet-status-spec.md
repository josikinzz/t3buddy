# T3boii status feed and pet behaviour: implementation plan

Status: plan, October 16 2026, since built in large part. It supersedes the environment parts of `docs/pet-hud-design-proposal.md`.

Read it for the decisions and the canon below, which still hold. Its examples of code, wire format and command-line options are the plan, not the shipped interface: the feed's wire contract is `Sources/ModelWidgetCore/Feed/FeedSchema.swift`, the helper's options are in `Sources/T3boiiFeed/main.swift` (there is no `--record` or `--replay`), and `AGENTS.md` maps the code. Where `DESIGN.md` and this plan differ on a visible detail, `DESIGN.md` is the later word.

Josie's decisions, as this plan reads them:
- There is no environment: no weather, island or background. The work goes into T3boii himself.
- It stands alone from T3 Code. There are no T3 patches. A **sidecar** polls T3, diffs what it sees into events, and serves a live feed. A native T3 event stream can replace the polling later without changing the feed.
- No beams between threads, because the sender of a message is unknown.
- The canon:
  - A thread **starts** out of the psychic T3 on his forehead.
  - A thread that **finishes** is sucked into his mouth.
  - Settled is never shown, and there is no belly glow.
- New orb behaviour:
  - An orb's orbit speed and pulse follow its activity, capped.
  - A message flies in as a glint from **behind him**, and the orb gulps it.
  - Queued messages are beads behind the orb.
  - A pending question floats as a question mark. He does not hold it.
  - A failed thread floats as a cracked, sputtering shape.
  - A snoozed thread is an egg at his feet that hatches.
  - Subagents are moons.
  - A provider change flips the logo.
  - A PR gets a ring.
- His mood is one of: dozy, focused, satisfied, fretful.
- Halo seeds for scheduled tasks are a flagged prototype.

Sections:
- §1 summarises today's code.
- §2 is the sidecar.
- §3 is the feed schema.
- §4 is the state machines.
- §5 is the animation spec.
- §6 lists the changes file by file.
- §7 is the test plan.
- §8 is the PRs.
- §9 is pushback and risks.

---

## 1. Today, in brief (what this plan changes)

**Data path**
- `OrbitRuntime.swift` polls T3's MCP server (`POST 127.0.0.1:3773/mcp`) and Grok Bot's local files every 5 s, inside the app. It sends `window.t3boii.update({orbs, limits})` to the page whenever the snapshot changes.
- **Outages are treated as finished.** A source that fails returns `[]`. Its last orbs are kept for 6 s (`OrbitSourceFallback`). After two polls without an orb (`OrbitRemovalHold`), the orb is **swallowed as if finished**.
  - So a T3 restart or an expired token longer than about 15 s makes him swallow every orb and dance.
  - The sidecar fixes this: an orb only finishes on positive evidence (§2.5).

**Page**
- Orbs are DOM spheres in two layers (`#orbits-back` behind the canvas, `#orbits` in front). The energy lines are 2D canvases.
- A waiting orb is **held in his hands** (`HOLD_POSE`, `holdAnchor`, `pet.js:103, 926, 1369-1372`; `orbit.js:478-492`). This plan removes that.
- A failed orb is red glass sitting just outside ring 0 (`orbit.js:493-517`).
- **Two buzz hazards for "speed follows activity":**
  - The ring angle chases `spec.speed * t` (`orbit.js:543`; moons at `:524-527`). If the speed varies, the goal sweeps through cycles, which is the same failure as the old sway buzz.
  - Breathing is a CSS animation chosen by `data-pace` (`index.html:64-65`). Switching between busy (1.15 s) and quiet (3.2 s) restarts it, so the orb snaps mid-breath. That already happens today.

---

## 2. The sidecar: `t3boii-feed`

### 2.1 Process model

- **Binary and packaging:**
  - A new SwiftPM executable target, `T3boiiFeed`, producing a `t3boii-feed` binary in this package.
  - It reuses `ModelWidgetCore`: the MCP client (`T3MCP.swift`), OAuth/pairing (`T3ThreadSource.swift:95-252`), the token store (`T3TokenFile.swift`), `GrokRosterReader`, `ProviderLimits` and `ProjectIconResolver`.
  - `scripts/package_app.sh` copies it to `LocalModelWidget.app/Contents/Helpers/t3boii-feed` and signs it with the app.
- **Who runs it:**
  - The app's new `FeedSupervisor` launches the helper as a child with `--parent-pid <pid>`.
  - The sidecar watches the parent with `DispatchSource.makeProcessSource(.exit)` and exits when the app exits, so it is never orphaned.
  - `--standalone` disables that, for a LaunchAgent later or for running it by hand.
- **One instance:**
  - It takes an `flock` on `~/Library/Application Support/LocalModelWidget/feed.lock`.
  - A second instance exits with code 3.
  - The supervisor then attaches to the running one, through the discovery file.
- **Discovery file:** `~/Library/Application Support/LocalModelWidget/feed.json`, written atomically with mode 0600: `{v:1, pid, port, token, startedAt, version}`.
- **Restarts:** when the helper exits unexpectedly, the supervisor restarts it after 1, 2, 4, 8, 16, 32, then 60 s. The backoff resets after 5 min of uptime.
- **Debug modes:**
  - `t3boii-feed --tap` prints the event stream as NDJSON to stdout and serves nothing.
  - `--record <dir>` saves every MCP response with its timing, for replay fixtures (§7).
  - `--replay <dir>` serves a recorded session on a synthetic clock.

### 2.2 Sources inside the sidecar

```
FeedSource (protocol)            -> emits Observation batches into the WorldModel
 ├─ T3PollingSource              (MCP polling; this plan)
 ├─ T3NativeStreamSource         (later: T3 event cursor; §2.9)
 └─ GrokRosterSource             (Grok Bot persistence files; today's GrokRosterReader)
WorldModel  --diff-->  FeedEvent log (ring buffer)  -->  FeedServer (HTTP/SSE)
```

- A source never emits events directly. It reports **observations**: "thread X was seen with these fields at time t, from a poll that succeeded for project P".
- The `WorldModel` owns the state, and `SnapshotDiff` (§2.5) is the only thing that produces events. Swapping polling for a native stream (§2.9) therefore changes only the source.

### 2.3 Poll cadence and budget

The scheduler wakes every 250 ms and spends from a **token bucket**: capacity 10, refilled at **3 calls/s**. That is the sustained ceiling, against a 5 s cadence today that already uses up to about 30 calls per poll. At most 3 calls are in flight, and each call times out at 5 s.

| Job | Call | Period | Priority | Gate |
|---|---|---|---|---|
| Hot list | `t3_thread_list {projectId, statuses: [preparing, queued, starting, running, waiting], includeSubagents, limit: 100}` | **2 s** per hot project | P0 | Project is hot: an active, failed-unseen, asking or snoozed thread, or an update in the last 10 min |
| Cold list | Same call | 20 s per project, round-robin; 60 s for projects with no thread updated in 24 h | P2 | — |
| Drop-out probe | `t3_thread_read {threadId, limit: 1, runLimit: 1}` | Immediately, when an active thread disappears from a successful hot list | P0 | Gives **positive** terminal evidence (§2.5) |
| Activity read | `t3_thread_read {view: activity, afterPosition, limit: 50, maxCharsPerItem: 160, runLimit: 1}` | Only when the list's `itemCount` or `status` changed since the last read; at least 1.5 s apart per thread | P1 | **Gating on `itemCount` makes quiet threads cost nothing** |
| First read of a new thread | Same, last 100 items | Once | P1 | — |
| Pending requests | `t3_pending_request_list {threadId}` | 3 s while `pendingRequestCount > 0` | P1 | — |
| Queue | `t3_queue_list {threadId}` | 6 s for up to 6 running threads that had a user message in the last 10 min | P3 | Flag `queue` (§9) |
| Snoozed | `t3_thread_list {projectId, snoozed: true, limit: 20}` | 30 s per project, round-robin | P3 | — |
| PRs | `list_thread_pull_requests {threadId}` | 60 s for threads with `linkedPullRequest` set (at most 10) | P3 | Flag `pr` (§9) |
| Schedules | `list_scheduled_tasks {}` | 60 s | P3 | Flag `seeds` |
| Projects | `t3_project_list` | 120 s, and at start | P2 | — |
| Capabilities / environment | `orchestrator_capabilities`, `t3_environment_read` | 10 min | P4 | — |
| Server identity | Read `~/.t3/userdata/server-runtime.json` (`port`, `origin`, `pid`, `startedAt`, `serverVersion`) | 10 s | — | Local file read, no MCP call |

- **Startup probe:** call `t3_thread_list` once with no `projectId`. If a non-thread caller gets every project from that, one hot-list call replaces the per-project calls. The tool's description only says what happens for the calling thread's project, so this is unknown until tried.
- **Adaptive backoff:**
  - If the median call latency over the last 20 calls passes 1.5 s, or T3 returns 429 or 503, every period doubles (capped at 4×).
  - Periods relax by a factor of 0.8 every 30 s once healthy.
- **Expected steady load:**
  - 2 hot projects with 6 active threads: about 1 hot-list call/s, plus about 1 to 2 activity reads/s while threads are busy, plus a cold-list trickle.
  - That is about 2 to 3 calls/s, against about 6/s peaks today.
  - §7 measures it.

### 2.4 Observations collected per thread

| Field | Source |
|---|---|
| `threadId`, `projectId`, `title`, `parentThreadId`, `relationshipToParent`, `creationSource` | List |
| `status` | List; drop-out probe |
| `providerInstanceId`, `model` | List |
| `itemCount`, `updatedAt` | List |
| `snoozed`, `snoozedUntil` | Snoozed list |
| `linkedPullRequest` | List (unverified shape) |
| `pendingRequestCount`, `activeRunId` | Read |
| Pending request kind | Newest unresolved activity item of type `user_input_request` (question), `approval_request` (approval) or `secret_request` (question variant), or a `proposed_plan` in plan mode (approval variant). Fallback: the existing count-minus-questions inference |
| New `user_message` items | Read: `position`, `runId`, `createdBy`, `creationSource`, `updatedAt` |
| Activity phrase | Read (today's `T3OrbitState` logic, ≤44 characters) |
| Subagent items | Read (today's moon logic, `T3MCP.swift:157, 191-197`) |
| Terminal error text | Read: `error` items, fed to `ProviderLimits` (limit vs failure) |
| Queue count | Queue list |
| PR state | PR list |

### 2.5 The diff: snapshots into events

The diff keeps per-thread `ThreadState` (§4.1 gives the derived lifecycle) and compares each observation batch to it. The rules:

1. **Unknown is not finished.**
   - `thread.finished` is emitted only when a thread was observed with a terminal status: `completed`, `interrupted`, `cancelled`, `rolled_back`, or `idle` for a thread that is not a provider-native subagent.
   - The evidence comes from a successful list or from the drop-out probe.
   - A thread missing from a *failed* poll, or from a list whose project call failed, changes nothing.
   - A thread that simply vanishes from a successful list, and whose probe returns not found or archived, gets `thread.vanished`. The pet fades it; it does not swallow it.
2. **Failure** is a terminal `failed` status. `ProviderLimits` decides between `limit.*` (the existing crying and dissolve) and `thread.failed`.
3. **Start:**
   - `thread.started` fires on the first observation of a thread in an active status, or on a known thread going from terminal back to active.
   - The `cause` is `new` or `resumed`.
   - Activity before the first observation is not replayed.
4. **Messages:**
   - A `user_message` item with a `position` above the last one seen emits `thread.message {from}`:
     - `from: "user"` when `createdBy == "user"`;
     - otherwise `from: "agent"`, which covers delegating parents, `t3_thread_send` from any MCP client, and Grok bots.
   - **Suppressed:**
     - the first user message of a thread's first run (that is the START prompt);
     - every message found on a thread's first read, except the newest when its run is the active run and it arrived within 30 s. That one plays after the spawn, as the message that woke the thread.
5. **Questions:**
   - `thread.ask.opened {kind}` fires when `pendingRequestCount` goes from 0 to more than 0. `kind` is `question` or `approval`.
   - `thread.ask.closed` fires when it returns to 0.
   - A count that opens and closes within one poll is emitted as both, and the pet guarantees a minimum display time (§5).
6. **Snooze:**
   - `thread.snoozed {until}` fires when `snoozed` becomes true.
   - `thread.woke` fires when it becomes false, or when `now ≥ until` and the next snoozed list confirms it.
7. **Provider and model:**
   - `thread.provider.changed {from, to}` fires when `providerInstanceId` changes between two successful observations.
   - `thread.model.changed` fires on a model change with the same provider.
   - Neither fires on first sight.
8. **Activity:**
   - `rate` is items per minute: the `itemCount` delta over the elapsed time, smoothed by an exponential moving average with a 20 s time constant.
   - `activity = clamp01(ln(1 + rate) / ln(1 + 30))`, so 30 or more items a minute reads as 1.
   - It is a state field, not an event. It is sent when it changes by at least 0.05.
9. **Queue:** a `queue` count change emits `thread.queue {count}`. A decrease with a new user message in the same batch emits `thread.message {from, fromQueue: true}`, which eats the front bead.
10. **Moons:**
    - `moon.started` and `moon.finished` come from today's subagent logic. Delegated-task threads are moons of their parent.
    - The parent stays in orbit while any moon is active (today's `holdingParents`).
11. **Server restart:** if `server-runtime.json`'s `pid` or `startedAt` changes, the sidecar invalidates its MCP session and cursors, and re-reads everything. **It emits no lifecycle events from that re-read alone**: the rebuilt state reconciles silently (§2.7).
12. **Settled and archived:**
    - These are never shown.
    - An unseen failure whose thread becomes `settled` or archived counts as **seen** (`thread.failure.seen`), so the cracked shape retires once Josie has dealt with it in T3.

### 2.6 Transport to the pet

- **Server:** HTTP on `127.0.0.1:<ephemeral port>` (Network.framework `NWListener`, IPv4 loopback only).

| Endpoint | Purpose |
|---|---|
| `GET /v1/health` | `{ok, version, source: {status, lastOkAt}}` |
| `GET /v1/state` | The full `FeedState` (§3.2) with its `seq` |
| `GET /v1/events` | SSE stream (`text/event-stream`). Each event is `id: <seq>` followed by `data: <FeedEvent JSON>`. Honours `Last-Event-ID`: replays from a 2,000-event or 15-minute ring buffer, or sends `event: reset` with the full state when the gap is too old. Heartbeat comment every 10 s |
| `POST /v1/connect` | Asks the sidecar to mint a T3 pairing (the gear menu's "Connect T3") |

- **Auth:**
  - Every request needs `Authorization: Bearer <token>` from `feed.json` (a 32-byte random value, regenerated each start).
  - Requests carrying any `Origin` header are refused, so no browser page can reach it.
  - `Host` must be `127.0.0.1:<port>`, as a DNS-rebinding guard.
- **The app relays to the page:**
  - `FeedClient` (URLSession `bytes(for:)` over SSE) receives events.
  - It batches them every 100 ms into `window.t3boii.feed({events:[…]})`.
  - On connect, page reload or reset it sends `window.t3boii.feed({state})`.
  - **The page keeps its offline content blocker** (`PetLayer.swift:106` blocks http and ws). It never talks to the network, and the token never enters the page.
  - "The pet subscribes" therefore means the app subscribes on the page's behalf.

### 2.7 Failure and staleness

`source.status` is a state field, plus a `source.status` event when it changes. Each status has a sidecar behaviour and a pet behaviour:

| Status | When | Sidecar | Pet |
|---|---|---|---|
| `live` | Last full hot cycle succeeded within 6 s | — | Normal |
| `lagging` | 6 to 20 s since the last good hot cycle | Backoff (§2.3) | Nothing visible |
| `stale` | More than 20 s | Keeps state, emits no lifecycle events | Orbs **hold their breath**: pulse amplitude eases to 0 over 2 s, speed eases to the base rate, and they desaturate 25%. Nothing spawns or is swallowed |
| `offline` | Connection refused or `server-runtime.json` missing for more than 20 s | Retries every 5 s, then 15 s | As stale, and orbs dim to 60% |
| `unauthorized` | 401/403, token retired | Mints a new pairing at most every 15 min (today's throttle) | As offline |

- **Recovery:**
  - The first good cycle after `stale` or `offline` is diffed against the kept state with rule 1 intact.
  - Threads that ended during the outage get `thread.finished` and are swallowed, staggered.
  - Threads that started during it get `thread.started`.
  - Nothing is swallowed only for having been unknown.
- **Sidecar crash:** the app keeps the last state, shows `stale` after 20 s, and resubscribes with `Last-Event-ID` after the supervisor restarts the helper. The helper's ring buffer starts empty, so the client receives a `reset`.

### 2.8 T3 auth

- The sidecar takes over today's OAuth/pairing code and token file: `~/Library/Application Support/LocalModelWidget/t3-mcp-token.json`, scope `orchestration:read`, read-only.
- After the switch the app never touches the token, so there is one writer.
- "Connect T3" posts `/v1/connect`.

### 2.9 Swapping to a native T3 stream

- **Probe:**
  - At connect, the sidecar checks the MCP tool list and resource capabilities for an event cursor: a tool like `t3_events_since` or a subscribable resource.
  - `--source auto|poll|native` defaults to `auto`.
- **`T3NativeStreamSource`:**
  - Maps T3 events into the same observations.
  - T3's internal event names, seen read-only in this audit, would be mapped. For example:
    - `run.updated` → status;
    - `thread.message-sent` → message;
    - `runtime-request.updated` → ask opened or closed;
    - `thread.snoozed` / `thread.unsnoozed`;
    - `thread.model-selection-updated`, `thread.provider-switched` → provider;
    - `thread.pull-request-synced` → PR;
    - `subagent.updated` → moons;
    - `turn-item.updated` → activity and messages.
  - It still runs a **reconcile poll every 60 s** (hot list only). Any mismatch emits corrective events and is logged.
- **Unchanged by the swap:** the feed schema, the `WorldModel`, the diff rules, the app and the page.
- **Never read T3's database.** The only T3 local state the sidecar reads is `server-runtime.json`, which is small, flat and keyed, and used only for discovery and restart detection. `statev2.sqlite` is private: its schema has already moved from v1 to v2, it runs in WAL mode, and it holds about 4.9 million events (one count took over 2 minutes). The sidecar must not read it.

---

## 3. Feed schema (v1)

### 3.1 Event envelope

```jsonc
{ "v": 1, "seq": 1842, "at": "2026-10-16T09:12:03.412Z",   // observed time
  "src": "poll" | "native" | "grok",
  "kind": "thread.started",
  "id": "t3:<threadId>",                                    // orb key (moons: t3:<subagentKey>)
  "confidence": "exact" | "inferred",
  "data": { … } }
```

| `kind` | `data` |
|---|---|
| `thread.started` | `{cause: "new"\|"resumed", parentId?}` |
| `thread.finished` | `{status: "completed"\|"interrupted"\|"cancelled"\|"rolled_back"\|"idle"}` |
| `thread.vanished` | `{}` |
| `thread.failed` | `{message?}` (≤120 characters) |
| `thread.failure.seen` | `{via: "settled"\|"archived"\|"hover"}` (hover comes from the page, below) |
| `thread.message` | `{from: "user"\|"agent", fromQueue?: true}` |
| `thread.queue` | `{count}` |
| `thread.ask.opened` | `{kind: "question"\|"approval"}` |
| `thread.ask.closed` | `{}` |
| `thread.snoozed` | `{until}` |
| `thread.woke` | `{}` |
| `thread.provider.changed` | `{from, to}` |
| `thread.model.changed` | `{from, to}` |
| `thread.pr.changed` | `{state: "none"\|"pending"\|"pass"\|"fail"}` |
| `moon.started` / `moon.finished` | `{parentId}` |
| `limit.started` / `limit.cleared` | `{provider, until?}` |
| `seed.ripening` / `seed.fired` | `{taskId}` (flag `seeds`) |
| `source.status` | `{status, since}` |

### 3.2 State (`/v1/state`, and `feed({state})` for the page)

```jsonc
{ "v": 1, "seq": 1842, "source": { "status": "live", "since": "…" },
  "projects": { "<projectId>": { "title": "…", "icon": { "kind": "image"|"monogram", "src"?, "text"?, "color"? } } },
  "orbs": [ {
    "id": "t3:…", "parentId"?: "t3:…", "source": "t3"|"grok", "projectId": "…",
    "provider": "claudeAgent", "model": "claude-opus-5-5",
    "life": "working" | "asking" | "failed" | "snoozed",     // §4.1; finished orbs are absent
    "ask"?: { "kind": "question"|"approval", "since": "…" },
    "fail"?: { "since": "…", "seen": false },
    "snooze"?: { "until": "…" },
    "activity": 0.42, "activityText": "running swift build",
    "queue": 0, "pr": "none",
    "label": "widgets · Refine orb reactions", "link": "http://127.0.0.1:3773/…",
    "limited"?: true, "limitProvider"?: "kimi"
  } ],
  "limits": [ { "provider": "kimi", "since": "…", "until"?: "…" } ],
  "seeds"?: [ { "taskId": "…", "title": "…", "nextRunAt": "…", "lastRunStatus": "…", "provider": "…" } ]
}
```

- Icons go once per project in `projects`, not on every orb.
- The page → app → sidecar path stays one-way. The page's existing `post()` reports hovers and clicks on failed shapes to the app, which keeps "seen" locally, as today. The sidecar is not told.
- **Principle: state is truth, events are choreography.**
  - The page reconciles its scene to `state`.
  - Events only choose *how* a change is animated: swallow rather than fade, a glint, a flip.
  - A missed event means a plain transition, never a wrong scene.

---

## 4. State machines

### 4.1 Per orb (main thread orbs)

```
              thread.started (forehead)
   (none) ─────────────────────────────▶ KINDLING ──1.6 s──▶ ORBITING ◀─────────────┐
                                                               │  ▲                    │
                     thread.ask.opened ────────────────────────┤  │ thread.ask.closed │
                                                               ▼  │                    │
                                                              ASKING                   │
     thread.failed (from ORBITING / ASKING / KINDLING) ──▶ FAULTED ──thread.started──▶ MENDING ─┘
                                                              │ seen
                                                              ▼
                                                           FADING ──20 s──▶ (none)
     thread.snoozed (from any live state) ──▶ EGG ──thread.woke──▶ HATCHING ──▶ ORBITING | ASKING | FAULTED | SWALLOW
     thread.finished (from ORBITING / ASKING / MENDING) ──▶ SWALLOW ──1.3 s──▶ (none)
     limit (existing) ──▶ DISSOLVING ──2.7 s──▶ (none)
     thread.vanished ──▶ VANISHING (fade 0.6 s) ──▶ (none)
     state reconcile without an event: appear (fade in at slot, 0.5 s) / disappear (fade 0.6 s)
```

**Transition rules**
- **Leaving ASKING:**
  - On finished: the question mark's hook retracts (0.3 s) and the bare orb is swallowed from where it floats.
  - On failed: the hook shatters into 3 to 5 amber chips, and the orb moves to FAULTED.
- **EGG while the thread works:**
  - A snoozed thread usually isn't working, so ask, fail and finish events while it is snoozed are kept as the target and played after HATCHING.
  - T3 itself wakes a snoozed thread early when it asks, fails or completes, so `woke` normally arrives in the same batch.
- **FAULTED to MENDING:** a retry of the same thread (`thread.started {cause: "resumed"}`) does not spawn a second orb.
  - A thin psychic beam runs from his forehead T3 to the shard (0.5 s).
  - The cracks fill with violet light and seal (0.6 s).
  - The red drains to clear glass (0.4 s), and the orb returns to its slot (1.0 s).
  - One orb per thread is preserved, and the energy still comes from his forehead, as the canon requires.
- **Grok Bot agents** use the same machine. `awaitingUserResponse` maps to ASKING (question), and inactivity for more than 3 min maps to SWALLOW (today's rule).

**Orthogonal overlays** (valid in ORBITING, and in ASKING where noted):
- **Pulse and speed:** driven by `activity`.
- **Glints:** arrive at ORBITING and ASKING orbs. In KINDLING they are deferred until KINDLING ends.
- **Queue beads:** in ORBITING they trail the orb. In ASKING they hang under the question mark's dot.
- **Provider flip and PR ring:** in ORBITING and ASKING.

**Moons:** MOON_RISING (out of the parent, 0.9 s) → MOON → MOON_RETURNING (into the parent, 0.9 s, with a parent gulp). A moon whose parent leaves goes with the parent (today's behaviour). Moons have no ASKING or EGG states; a delegated child that asks shows on its parent as a small amber glint on the moon only.

### 4.2 The pet's mood

**Inputs**, recomputed on every feed batch and every 1 s:
- `active`: main orbs that are KINDLING, ORBITING, ASKING or MENDING, plus moons.
- `fleet`: the mean of the top 5 orbs' `activity`.
- `unseenFailures`: count.
- `oldestAsk`: seconds.
- `lastMeal`: the time of the last SWALLOW.
- `limits`: active limits.

| Mood | Enter | Exit | Minimum dwell |
|---|---|---|---|
| **Dozy** | `active = 0` for 8 s | `active ≥ 1` | 3 s; after 75 s (37 s at night) it deepens into the **existing sleep** |
| **Focused** | `active ≥ 3`, or `fleet ≥ 0.15` with `active ≥ 1` | `active = 0`, or `fleet < 0.08` with `active < 3` for 10 s | 4 s |
| **Satisfied** | A SWALLOW finishing (instant) | 5 s after the last swallow; +2 s for each further swallow within the window, capped at 10 s | — (transient) |
| **Fretful** | `unseenFailures ≥ 1`, or `oldestAsk ≥ 20 s` | Both clear | 4 s |
| Neutral (awake) | `active ≥ 1`, below the Focused thresholds | — | — |

- **Precedence:** overlays first, then Fretful > Satisfied > Focused > Neutral > Dozy.
- **Overlays:** the existing Crying (limits), Handled (drag, pet, spin, dizzy) and Celebrating (the all-done dance) override the mood's body layers, while the face still blends.
- **Satisfied over Fretful:** Satisfied lets him savour a meal while something is wrong. Fretful's target weight is held at 0.3 during Satisfied, never 0, so worry doesn't vanish while he chews.
- **Blending:**
  - Each mood is a parameter vector (§5.10).
  - The rendered face and body are the weighted sum.
  - Weights follow critically damped springs with ω = 2.5 rad/s (about 1.2 s to settle). Satisfied enters with ω = 6.
  - Nothing steps.

---

## 5. Animation spec

**Conventions**
- Times are seconds.
- "Orb" means the orb diameter (`ORB` in `orbit.js`). "R" means his ball radius.
- Easings are the existing `easeOut`, `easeIn`, `easeInOut` (cubic) and `easeOutBack` (c = 1.6), plus `spring(ω, ζ)`, a critically damped (ζ = 1) or bouncy (ζ = 0.55) second-order follower stepped by `dt`.

**The buzz rule** (from `CLAUDE.md`), applied here:
- Every rate that can change is a **phase accumulated by `dt`**. No new code may write `sin(t * k)`, `speed * t`, or `t * TAU / (…)` with a variable `k` or period.
- Shakes and shivers go through `tremble(t, rate)` (cap 40 rad/s).
- A rocking wobble is a shake for this purpose: it uses `tremble()` with a fixed rate and only its *amplitude* ramps.
- **RM** below means Reduce Motion.

### 5.1 START: out of his forehead (canon, existing; polish)

1. **Anticipation, 0.25:** the forehead T3 brightens 0 → 0.6 (`easeIn`) before the orb appears. His head tips back 2°.
2. **Kindle and fly, 1.6 (existing):** three psychic ripples; the orb kindles as hazy light for 0.3, then spirals out (`easeOutBack`) to its slot. The T3 decays over 0.8 after release.
3. **Caps and coalescing:**
   - Simultaneous starts are staggered 0.35 apart.
   - More than 3 starts within 1.0 share **one** bigger flare: 4 ripples, glow ×1.3, with the orbs leaving 0.2 apart.
   - At most 6 orbs are in KINDLING at once; the rest queue.
4. **Message after spawn:** for `cause: resumed` with a message, the glint (§5.4) plays 0.3 after the orb settles.
5. **RM:** the T3 glows 0.4, the orb fades in at its slot over 0.6, and there are no ripples.

### 5.2 FINISH: swallowed (canon, existing; polish)

1. **Order:** existing. A 0.3 tug, a stretch, then a 1.3 spiral into the mouth; swallows are staggered 0.22 apart, with wind.
2. **From ASKING:** the hook retracts first, over 0.3 with `easeIn`.
3. **From EGG:** it hatches first (§5.8).
4. **After:** the gulp pulse (existing), then **Satisfied** (§4.2). The last orb triggers the all-done dance (existing).
5. **Caps:** at most 4 orbs in flight to the mouth. A larger batch is swallowed in waves 0.9 apart, as in the demo.
6. **RM:** the orb fades toward the mouth over 0.6, his mouth opens 30%, then a smile.

### 5.3 Working: speed and pulse follow activity

`a` is the orb's `activity`, from 0 to 1, followed with `spring(ω = 1.2)`, so a burst ramps over about 3 s instead of jumping.

**Ring speed**
- Each ring keeps `ring.phase += spec.speed * mult * dt * motion`, where `mult = 1 + 0.6 * ā`.
- `ā` is the mean of `a` over the ring's ORBITING orbs.
- **Cap:** `mult ≤ 1.6`, so the fastest ring-0 lap is 22/1.6 = 13.75 s. Outer rings scale by √(1+k) as now.
- The orb goal becomes `ring.phase + slot` in place of `spec.speed * t * motion + slot` (`orbit.js:543`). Moons get the same treatment (`:524-527`), with `mult = 1 + 0.5 * a(moon)` capped at 1.5.

**Per-orb surge**
- Within its slot, an orb leads or lags by `lead = 0.25 * (a − ā) * slotSpacing`, followed with `spring(ω = 0.8)`, capped at ±0.25 slot.
- A busy orb visibly presses ahead of its neighbours without ever passing them. See §9, item 5.

**Pulse**
- The orb keeps `pulse.phase += TAU * dt / period`, where `period = lerp(3.4, 0.95, a)`, never below **0.95 s**.
- Scale is `1 + amp * (0.5 − 0.5 cos phase)`, with `amp = lerp(0.012, 0.05, a)`, capped at **5%**.
- Brightness rises by up to +12% at the crest when `a > 0.6`.
- **This replaces the CSS `breathe` animation** (`index.html:64-67`). The pulse is written from JS as a `--pulse` custom property, only when it changes by ≥ 0.002, so the busy-to-quiet switch no longer restarts the animation and snaps.

**Stale** (no activity for 3 min; existing `STALE_S`): drift out and dim, unchanged, eased by the same springs.

**Activity text trails:** unchanged.

**RM:** rings stand still (as now). The pulse becomes a brightness step: 3 levels by `a`, crossfaded over 0.6. There is no surge.

### 5.4 Message arrived: a glint from behind him, gulped by the orb

**Origin:** a point on a disc of radius 0.6 R, **0.4 R behind his body centre** in depth, at the angle of the target orb ±25°. It starts hidden by his silhouette.

**Path, 0.85 (`easeInOut`)**
- The glint moves outward behind him.
- It crosses his silhouette edge at 35% of its path, still in `#orbits-back` and so occluded.
- From there it curves to the orb's current, moving position: its target is re-read every frame (pursuit), with the arc bulging away from his body by 0.3 orb.
- If the target orb is on the near side (`depth > 0`), the glint hops to `#orbits` at the silhouette crossing, the same layer swap orbs already do.

**Glint**
- A bright bead 0.16 orb across with a 0.6-orb tail of 8 fading motes.
- **Colour:** `from: user` is warm white `#FFF1D0`; `from: agent` (agents, MCP callers, bots) is cool cyan `#7FDBFF`.
- Both keep clear of amber (asking), red (failed), violet (his own psychic light) and green (PR pass).

**Gulp, on arrival**
- The orb squashes along the glint's direction: 1 → 0.9 over 0.06 (`easeOut`), → 1.08 over 0.14, then `spring(ω = 14, ζ = 0.55)` back to 1.
- A glint-coloured flash on the glass: 0 → 0.8 → 0 over 0.25.
- One faint ring ripples outward from the orb (0.4).

**Caps**
- At most 3 glints in flight overall.
- At least 0.6 s between gulps for any one orb.
- Overflow folds into the next glint, which grows ×1.25 (once) and gains a second ring.

**Gaze:** his eyes flick to the orb at the gulp, a 0.15 saccade, if nothing higher in the gaze priority holds them.

**RM:** no flight. The orb flashes in the glint colour (0.3) and the gulp becomes a 3% scale pulse.

### 5.5 Queued messages: beads behind the orb

- **Placement:** up to 3 beads trail the orb along its recent path, the same path the activity trail uses.
  - Each bead is 0.22 orb, 0.34 orb apart, the first 0.62 orb behind the orb's centre.
  - They use the glint's glass bead look and colour (the queue is the user's, so warm white, unless `from` is known to be an agent).
- **More than 3:** the third bead grows to 0.3 orb. There is no numeral.
- **Motion:** each bead follows the one ahead with `spring(ω = 6)`, so the string has lag and sways naturally with orbit speed. There is no independent oscillation.
- **Eating:** on `thread.message {fromQueue}`, the front bead slides into the orb over 0.35 (`easeIn`) and the orb gulps (§5.4). The other beads move up with `spring(ω = 8)`.
- **Cancelled from the queue:** the count drops without a message, and the last bead fades and shrinks (0.4).
- **In ASKING:** the beads hang in a short column under the question mark's dot, 0.3 orb apart, swaying with the bob.
- **RM:** static beads. Eating is a fade (0.3) plus the RM gulp.

### 5.6 Question pending: the orb becomes a floating question mark

**Where**
- An **ask arc** around his upper body.
- Slots alternate left and right of his head at radius 1.35 R from the ball centre, starting at ±35° above horizontal and stepping 22° downward per slot.
- 6 slots; beyond that, a second arc at 1.7 R and 0.8× scale.
- Slots go to the oldest ask first. The ask arc and the worry zone (§5.7) never share space.
- **He does not hold them.** `HOLD_POSE` and `holdAnchor` are no longer used for asking.

**Morph, 0.9 total**
1. **Leave, 0.0 – 0.5:** the orb leaves its ring on an `easeOutBack` arc to its slot, scaling to 0.62. It is now the **dot** of the question mark, keeping its project icon and provider badge. It is still the clickable DOM orb, and a click opens the thread (today's `openLink`).
2. **Grow, 0.3 – 0.9:** the **hook** grows upward from just above the dot.
   - It is a 3D tube along a "?" curve, `TubeGeometry` with radius 0.11 orb and a total height of 1.5 orb.
   - It is amber glass (`MeshPhysicalMaterial`, clearcoat 1, transmission-free, emissive `#FFB340` at 0.35) and lit like him.
   - It is revealed by `drawRange`, the same technique as the tear streaks, with `easeOut`.
   - Its base anchors to the dot's projected position (§6, shared projector).
3. **Approval:** the hook is a straight bar instead of a curve, an "!".

**Who answers (standing rule):** A "!" approval is owned by the thread's owning bot, which decides it itself and does not wait on Josie; only spending, publishing, sending, or destructive/irreversible actions come to her. The "!" shows the bot is deciding; it is not a request to Josie.

**Idle**
- The whole mark bobs with its own phase: a fixed 2.4 s period and 0.06 orb amplitude.
- It sways ±4° with a fixed 3.1 s period.
- The amber emissive pulses 0.25 ↔ 0.45 over a fixed 2.0 s.
- Different marks get different phase offsets, so they never pulse in sync.

**Escalation by age** (the only thing that grows)
- From 60 s the pulse range widens to 0.2 ↔ 0.6.
- From 5 min the slot creeps 0.15 R closer to his face.
- No faster rates, ever.

**Minimum display:** once formed, a mark stays at least 1.2 s, so a question answered within a poll still reads.

**Answered:** the hook retracts down into the dot (0.35, `easeIn`). The dot regrows to 1.0 and returns to its ring slot (1.0, `easeInOut`), and its trail resumes.

**His reaction:** a new mark makes him glance at it (0.2 saccade, 0.8 dwell). He then glances at the oldest mark every 4 to 7 s while Fretful (§5.10). There is no body hold.

**RM:** the orb fades out of its ring and the full question mark fades in at the slot (0.5). No bob or sway, but a slow brightness pulse.

### 5.7 Error or failure: a cracked, sputtering shape near him

**Where:** a **worry zone** below and beside him, at 1.25 R from the ball centre, 30° to 60° below horizontal, alternating sides, 4 slots, then a second row.

**Leave, 0.8**
- The existing jolt (`crack-jolt`, 0.6) plays at the ring position first.
- Then an `easeOutBack` flight to the worry slot.

**Shape:** today's red glass with its crack, plus:
- a **chipped silhouette** (a CSS `clip-path` polygon taking one notch out, with the angle varied per orb);
- scale 0.85.

**Sputter**
- At random intervals of 1.6 to 3.2 s (event times, not a sine), it emits a burst of 3 to 6 ember chips. These are 3D, reusing `effects.js` shard and ember materials, at 40% of the dying-orb count.
- A 0.12 opacity flicker accompanies each burst (1 → 0.65 → 1).
- Between bursts it holds a low `tremble(t, 34)` shiver at 1.5% amplitude (the existing rate).
- Sputters stop once seen.

**He reacts:** flinch and frown, as now (`upset`). He feeds Fretful.

**Seen:** hover for 0.6, a click, or `thread.failure.seen` from T3 (settled or archived). The shape greys, sinks and fades over 20 (existing).

**Retry:** MENDING (§4.1).

**RM:** no flight (fade to the slot, 0.5), no chips, no shiver. A static crack and a slow dim pulse.

### 5.8 Snoozed: an egg at his feet

**Where**
- An **egg row** on a shallow arc 0.35 R below his feet, centred, with eggs 0.95 orb apart, up to 6.
- Beyond that, older eggs tuck behind at 0.8×, then 0.6× (no numerals).
- Ordered by wake time, soonest in the middle.

**Into the egg, 1.1**
- The orb leaves its slot and descends (`easeInOut`).
- On the way it elongates into an egg: CSS `border-radius: 50% 50% 50% 50% / 58% 58% 42% 42%`, with `scaleY` 1 → 1.18 and `scaleX` 1 → 0.92 over the last 0.5.
- A frosted shell fades in, 0 → 1 (a `backdrop` blur plus a white inner gradient, which is the existing glass bubble frosted). The project icon shows dimly through it.

**Rest:** a very slow breath on its own fixed phase, period 6 s, 1% scale.

**Wake approaching** (from `until − 60 s`)
- It rocks with `tremble(t, 5)` (about 0.8 Hz) on rotation, amplitude ramping 0 → 6° by `until`.
- From `until − 20 s`, a little hop every 6 s (a 0.06 orb jump, 0.35 duration).

**Hatch, on `thread.woke`, 1.6 total**
1. **Crack, 0.3:** crack lines draw across the shell (an SVG stroke reveal) with one strong `tremble` rock.
2. **Split, 0.6:** the shell splits into two 3D half-shells (`effects.js` lathe-geometry halves, glossy frost material). They fall 0.4 orb, tumbling, and fade.
3. **Pop and fly, 0.35 then 0.9:** the orb pops up with `easeOutBack` from 0.8 to 1.0 and flies to its target state's place: its ring slot, its ask slot, its worry slot, or straight into SWALLOW.

**If the thread is idle when it wakes:** see §9, item 1. The default is a hatch, then a 1.0 hover, then SWALLOW.

**RM:** the egg is a static frosted orb at the feet. There is no rocking, but an amber rim glow brightens in the last 60 s. Hatching is a crossfade (0.6).

### 5.9 Subagents: moons (existing; polish)

- **Out:** existing. Moons are 0.5 scale on their own rings (5 + 3k per ring). They rise out of the parent over 0.9, and the parent gets a 4% swell (0.2).
- **Speed:** each moon ring phase is accumulated by `dt` (§5.3), with `mult ≤ 1.5`.
- **Done:** the moon returns into the parent (0.9, `easeIn`) and the parent **gulps** it, using the same gulp as §5.4 at 60% strength.
- **RM:** existing (fades).

### 5.10 Mood parameter vectors (his face and body)

All values are targets that the blend weights (§4.2) mix together. Parameters marked "existing" already exist in `pet.js`.

| Parameter | Dozy | Neutral | Focused | Satisfied | Fretful |
|---|---|---|---|---|---|
| Lid droop (existing lid bias) | 0.38 | 0.08 | 0.02 | 0.22 (contented squint) | 0.06 |
| Smile morph (existing) | 0.05 | 0.12 | 0.08 | 0.55, lopsided (existing `odd` for the first 2.2) | 0 |
| Frown (existing `uFrown`) | 0 | 0 | 0.12 (concentration) | 0 | 0.45 + 0.1·severity |
| Breath period | 5.5 | 4.0 | 3.0 → 2.4 with `fleet` | 4.4, with one big exhale 0.6 s after entering | 2.6, shallower (amp ×0.7) |
| Float offset | −0.02 | 0 | +0.01 (plus existing power) | +0.015 | −0.01 |
| Blink interval and duration | 5–8 s, slow 0.25 | 3–5 s, 0.15 | 2–4 s, 0.12 | 4–6 s, 0.18 | 1.5–3 s irregular, 0.12 |
| Gaze | Slow wander, often half-closed | Existing follow | Existing darting between orbs (`busy`) | Toward the viewer, soft | Glances at asks and failures every 4–7 s, between viewer and problem |
| Body | Head droop 4° | — | Lean forward 3° toward the orbit centre | Little settle-bounce on entry (0.04, `spring ζ = 0.55`) | Shoulders up 0.08 rad, arms slightly in |
| Mouth tremble | — | — | — | — | Existing frown tremble, rate 14, at 0.5 of today's amplitude |

- `severity = clamp01(0.3·unseenFailures + oldestAsk/600)`.
- Breath and bob periods change through their existing phase accumulators (`sway.breath`, `sway.bob`), so mood changes are buzz-free.
- **RM:** the faces still blend (they are not motion). Body leans become 25% (today's RM amplitude), and gaze glances stop unless an event prompts them.

### 5.11 Provider or model change: logo flip and colour flash

**Provider change** (on `thread.provider.changed`)
- The provider badge rotates `rotateY` 0 → 90° (0.18, `easeIn`).
- At 90° it swaps to the new provider's badge.
- It rotates 90° → 0 (0.24, `easeOutBack`).
- At the swap, a rim flash in the **new** provider's colour runs over the orb: 0 → 0.9 → 0 over 0.6 (`easeOut`).

| Provider | Flash colour |
|---|---|
| claudeAgent | `#D97757` |
| codex | `#0A84FF` |
| kimi | `#40C8E0` |
| antigravity | `#FF6FB1` |
| opencode | `#C9CED6` |
| grok, grokBot | `#F5F5F7` |
| Other | `#8E8E93` |

**Model change only:** no flip, just a flash at 50% intensity over 0.4.

**RM:** the badge swaps with a 0.3 crossfade, and the flash runs at 40% with no motion.

### 5.12 PR and CI: a ring on the orb (flag `pr`)

- A thin ring at 1.2 orb diameter, 2 px at 36 px orb size, scaling with it.
- It is tilted to match the orb's ring tilt and shaded with a highlight on the lit side, so it reads as a band rather than a flat circle.

| State | Ring |
|---|---|
| `pending` | Silver at 40%, with a highlight running round it on a fixed 2.4 s lap |
| `pass` | `#30D158`, steady |
| `fail` | `#FF453A` with one 20° gap and a faint 0.8 s glow pulse (a fixed period) |
| `none`, closed or merged | Fades out over 0.6 |

- A change of state crossfades over 0.5.
- **RM:** no running highlight.

### 5.13 Halo seeds: scheduled tasks (prototype, flag `seeds`, on by default)

- **Where:** each enabled scheduled task is a **seed**, a glossy teardrop 0.28 orb long, on a high halo above his head.
  - The halo's radius is 0.55 R, centred 0.35 R above the top of his head, and tilted 0.2 rad.
  - It turns on a fixed 40 s lap. There are at most 8 seeds.
- **Colour:** the tint of the task's provider.
- **Ripening:** glow `= smoothstep(300, 0, secondsToNextRun)`, so it ripens over the last 5 minutes.
- **Fired** (`seed.fired`): the seed drops into his forehead T3 (0.6, `easeIn`), the T3 flares, and if the run creates a thread, that thread's START plays from the same flare. If the task is bound to an existing thread, the seed instead becomes a glint into that thread's orb.
- **Last run failed:** a hairline crack on the seed.
- **RM:** static seeds; ripening is brightness only.
- Josie judges this prototype.

### 5.14 Limits (unchanged)

The existing crying, glum mood and dissolve stay as they are. They are not part of these decisions. Crying is an overlay over every mood.

### 5.15 Performance budget for this work

- **Idle:** 30 fps, as now. Keep the existing lively 60 fps triggers and add glints in flight, hatches and morphs.
- **New WebGL meshes:**
  - ≤ 6 question hooks, each one draw call, sharing one material instance per kind.
  - Egg halves only while they exist.
  - Ember chips at 40% of today's dying-orb count.
- **New DOM elements:** glints as one pooled element each (at most 3), beads (at most 3 per orb).
- **Style writes:** the JS pulse writes one custom property per orb per frame, only when it changes by ≥ 0.002.
- **Budget:**
  - JS ≤ 2 ms per frame at idle with 20 orbs, ≤ 4 ms while lively.
  - No more than 2 more draw calls than today at idle.
  - Measured with a `?perf` overlay.

---

## 6. What changes, file by file

### New

| File | What |
|---|---|
| `Sources/ModelWidgetCore/Feed/FeedSchema.swift` | `FeedEvent`, `FeedState`, `OrbState` and `Life` Codable types, with sorted-key JSON (§3) |
| `Sources/ModelWidgetCore/Feed/WorldModel.swift` | Per-thread `ThreadState`, observations, the derived `life` |
| `Sources/ModelWidgetCore/Feed/SnapshotDiff.swift` | The rules of §2.5, pure and clock-injected |
| `Sources/ModelWidgetCore/Feed/ActivityRate.swift` | The `itemCount`-based exponential moving average and its normalisation |
| `Sources/ModelWidgetCore/Feed/PollScheduler.swift` | Token bucket, job table, adaptive backoff (§2.3), on a clock that tests can drive |
| `Sources/ModelWidgetCore/Feed/FeedSource.swift` | The `FeedSource` protocol; `T3PollingSource` built from today's `T3ThreadSource` pieces; `GrokRosterSource` |
| `Sources/ModelWidgetCore/Feed/T3NativeStreamSource.swift` | A stub: capability probe and event mapping table, returning "unavailable" until T3 offers a cursor |
| `Sources/ModelWidgetCore/Feed/T3ServerIdentity.swift` | Reads `server-runtime.json` and detects restarts |
| `Sources/T3boiiFeed/main.swift` | CLI (`--parent-pid`, `--standalone`, `--tap`, `--record`, `--replay`, `--source`, `--flags queue,pr,seeds`), lock, discovery file, parent watch |
| `Sources/T3boiiFeed/FeedServer.swift` | `NWListener` HTTP: `/v1/health`, `/v1/state`, `/v1/events` (SSE with `Last-Event-ID`), `/v1/connect`; bearer, Origin and Host checks; ring buffer |
| `Sources/LocalModelWidget/FeedSupervisor.swift` | Launches, attaches to, restarts and stops the helper |
| `Sources/LocalModelWidget/FeedClient.swift` | SSE client; 100 ms batching; relays to `PetLayer`; staleness when the helper is gone |
| `Resources/Pet/feed.js` | The page's feed model: reconciles `state`, routes events into a **choreographer** (per-orb transition queues; global caps for spawns, swallows and glints; minimum display times) |
| `Resources/Pet/mood.js` | §4.2 and §5.10: inputs, thresholds, springs, parameter vectors |
| `Tests/ModelWidgetChecks/FeedDiffChecks.swift`, `FeedServerChecks.swift`, `PollSchedulerChecks.swift` | §7 |
| `Tests/ModelWidgetChecks/Fixtures/feed/…` | Recorded MCP sessions and expected event logs |

### Changed

| File | Change |
|---|---|
| `Package.swift` | Add the `T3boiiFeed` executable target (depends on `ModelWidgetCore`) and its product |
| `scripts/package_app.sh` | Build and copy `t3boii-feed` into `Contents/Helpers/`, then sign |
| `scripts/verify.sh` | Unchanged in shape: the new checks run inside `ModelWidgetChecks`, and `swift build` builds the helper |
| `Sources/ModelWidgetCore/T3ThreadSource.swift`, `T3MCP.swift`, `T3OrbitState.swift` | Split the transport and auth (kept) from orb assembly (moves into `T3PollingSource` and `WorldModel`). Add decoding for `model`, `snoozed`, `snoozedUntil`, `settled`, `linkedPullRequest`, item `createdBy`/`creationSource`, `user_input_request`/`approval_request`/`secret_request`/`proposed_plan` kinds; add the queue, snoozed-list and PR calls |
| `Sources/ModelWidgetCore/OrbitSnapshot.swift`, `OrbitSource.swift` | `OrbitSnapshot`, `OrbitRemovalHold` and `OrbitSourceFallback` are retired once the feed is the default (the feed's rule 1 replaces them). `Orb` stays only for `demo` |
| `Sources/ModelWidgetCore/GrokRosterReader.swift` | Wrapped by `GrokRosterSource`; maps `awaitingUserResponse` to an ask |
| `Sources/LocalModelWidget/OrbitRuntime.swift` | Replaced by `FeedSupervisor` + `FeedClient`. In-process polling stays behind the defaults key `petFeedMode = inprocess` for one release as a fallback, then is deleted |
| `Sources/LocalModelWidget/PetLayer.swift` | New `feed(json)` bridge call (`window.t3boii.feed`); the ready handler re-sends state. Content blocker unchanged |
| `Sources/LocalModelWidget/main.swift` (or wherever "Connect T3" is wired) | "Connect T3" posts to the sidecar |
| `Resources/Pet/orbit.js` | Accumulated ring phase plus surge (§5.3, replacing `:524-527, :543`); a JS pulse with `--pulse` (§5.3); new modes ASKING (ask arc, dot), FAULTED worry zone plus sputter scheduling, EGG row plus hatch, MENDING; glint flights and the back-to-front layer hop; queue beads; badge flip; PR ring; remove the `holdAnchor` path (`:478-492`); `update()` kept as a compatibility shim that feeds `feed.js` |
| `Resources/Pet/pet.js` | Remove the `HOLD_POSE` hold for waiting (`:1283, 1368-1373`, the `holdAnchor` export); hook `mood.js` vectors into `pose()` (lids, smile, frown, breath and bob period through the existing phase accumulators, float, blink, gaze, lean); new gaze targets (ask marks, worry shapes, gulping orb); a shared `projectToStage(world)` / `stageToWorld(x, y, depth)` projector used by `orbit.js` and `effects.js`; register `feed`; mouse "seen" posts unchanged |
| `Resources/Pet/effects.js` | Question hook and "!" bar (tube, `drawRange` reveal); egg half-shells; sputter ember bursts (a smaller variant of the existing shards); mend beam (a thin version of the ripple shader as a line); seeds (flagged) |
| `Resources/Pet/motion.js` | Add `class Phase { advance(dt, rate) }` and `spring(state, target, ω, ζ, dt)`. `tremble` is unchanged |
| `Resources/Pet/index.html` | Remove the `data-pace` CSS `breathe` animations (`:64-67`) and `.orb[data-state="waiting"]` hold-era styles (`:73-80`); add egg, frost, chipped, ring, flip and bead styles; load `feed.js` and `mood.js` |
| `Resources/Pet/demo.js` | After the new behaviours land, update the demo beats (ask marks, worry shape, glints, eggs) **only with Josie's go-ahead** (the "demo uses existing animations" rule) |
| `Tests/ModelWidgetChecks/PetMotionChecks.swift` | New static rules (§7.2) |
| `Tests/ModelWidgetChecks/OrbitStateChecks.swift`, `OrbitChecks.swift` | Move to feed fixtures; keep the existing assertions that still apply |
| `DESIGN.md` (Desk Pet) | Rewrite **Needs you** (floating question marks, not held), **Failure** (worry zone, sputter, mend), and **Orbs** (activity speed and pulse); add **Messages**, **Queue**, **Snooze**, **Provider change**, **PR ring**, **Mood** and **Feed staleness**. Each PR updates its own part |
| `PRODUCT.md` | "holding out a thread that needs you" becomes "a floating question mark for a thread that needs you" |
| `CLAUDE.md` rule table | Add: "An orb is swallowed only on positive terminal evidence; unknown is not finished", enforced by `FeedDiffChecks` outage fixtures. Add: "Orb pulse and orbit speed advance a phase by `dt`; no `data-pace` CSS animations", enforced by `PetMotionChecks` |

---

## 7. Test and acceptance plan

### 7.1 Swift checks (in `ModelWidgetChecks`, run by `scripts/verify.sh`)

- **`FeedDiffChecks`:** replays recorded MCP response sequences on a synthetic clock and asserts the exact event log. Fixtures:
  1. Start, work, finish (`completed`): `started` then `finished`.
  2. **T3 restart for 40 s** (connection refused, then a new `server-runtime.json` pid): **no `finished`**; `source.status` goes stale → offline → live.
  3. Token expiry (401) for 3 polls: no lifecycle events.
  4. A thread that ends during an outage: exactly one `finished`, after recovery.
  5. A thread deleted (vanished, probe not found): `vanished`, never `finished`.
  6. A failure with a Kimi weekly-limit error: `limit.started`, not `thread.failed`. A plain error: `thread.failed`.
  7. Failed, then settled: `thread.failure.seen {via: settled}`.
  8. Failed, then resumed: `started {cause: resumed}`, which the page renders as MENDING.
  9. Question opened and closed within one poll: both events, in order.
  10. An approval: `ask.opened {kind: approval}`, using the `approval_request` item.
  11. Messages:
      - a user message mid-run: `message {from: user}`;
      - a `thread-send` from MCP: `{from: agent}`;
      - the first-run prompt: suppressed;
      - the wake message on an idle thread: `started {resumed}` then `message`.
  12. Queue 2 → 1 with a new message: `message {fromQueue}`. Queue 1 → 0 without one: `queue {count: 0}` only.
  13. Snooze, then wake: `snoozed {until}` then `woke`; the wobble window is derived by the page.
  14. Provider change between runs: `provider.changed`. Model change: `model.changed`. First sight: neither.
  15. Moons: native subagent item running → done, and a delegated-task child: `moon.started` / `moon.finished`, with no duplicate for the delegated pair.
  16. Activity: an `itemCount` ramp from 0 to 60 a minute gives `activity` climbing smoothly to 1 within 20 s ± 5 s, and decaying.
- **`PollSchedulerChecks`:** simulate 19 projects, 20 active threads (8 busy), 2 waiting, 3 snoozed and 10 minutes.
  - Average ≤ 3 calls/s, burst ≤ 10.
  - Every hot project is listed at least every 2.5 s.
  - A busy thread's activity is read at least every 3 s.
  - A quiet thread makes no activity reads.
  - With 1.5 s injected latency, the periods double.
- **`FeedServerChecks`:**
  - No bearer: 401. Any `Origin`: 403. A bad `Host`: 421.
  - `Last-Event-ID` inside the buffer replays exactly the missed events.
  - Outside the buffer: `reset` with the state.
  - A heartbeat arrives within 11 s.
  - Two clients receive the same sequence.
- **`PetLayerChecks`** (in-process WKWebView):
  - Load the page.
  - Apply `feed({state})` and then 200 fixture events.
  - Assert no JS errors, and that the page's `state()` matches the final state: orb ids, modes, ask slots, egg count.

### 7.2 Static motion rules (`PetMotionChecks`)

- **Existing:** raw fast sines, and sines of the clock over a parenthesised period.
- **New:** fail any `speed * t`, `* t * motion` or `sin(t * <identifier>)` in `Resources/Pet/*.js` whose multiplier is not a `const` literal. Rates that vary must go through `Phase`.
- **New:** fail any `animation:` rule in `index.html` under a `[data-pace` selector, or a `--pulse` written from CSS keyframes.
- **New:** fail a `tremble(` whose rate argument is not a literal ≤ `TREMBLE_MAX_RATE`.

### 7.3 Motion and screenshot harness

This is the headless Chrome, synthetic-clock harness, serving `Resources/` and pumping frames at 1000/60 ms.

**Uptime:** each scenario runs at clock offsets of 0 and **6 h** (simulated uptime), at 30 and 60 fps.

**Metrics with pass thresholds**
- **Buzz:** per-orb and per-bone direction changes per second ≤ 2.0 outside tremble windows, through an activity ramp from 0 → 1 → 0 over 30 s and mood switches every 5 s. (The October investigation measured 15/s for the old bug.)
- **Speed cap:** maximum ring angular velocity ≤ base × 1.6 + 1%; moons ≤ × 1.5.
- **Pulse cap:** period ≥ 0.95 s, amplitude ≤ 5%.
- **No overtaking:** the angular order of the orbs on a ring is the same at every frame, and no two orbs are closer than 0.85 orb in stage space.
- **Glint cap:** at most 3 in flight with a burst of 10 messages to one orb, and at least 0.6 s between gulps.
- **Ask layout:** 8 simultaneous asks fill 6 + 2 slots; there is no overlap with the worry zone or the egg row; each dot's projected position stays within 1 px of its hook base at every frame.
- **Minimum display:** an ask opened and closed in the same batch is visible for at least 1.2 s.

**Screenshot sets** (per state, start / middle / end), each also with `?reduced`:
- START (single, and coalesced ×5)
- FINISH, plus Satisfied
- glint from user and from agent, on near-side and far-side orbs
- queue of 1, 3 and 5, and eating one
- question and approval: forming, idle, escalated, answered
- failure: leave, sputter, seen-fade, mend
- egg: in, rest, wobble, hatch into orbit, ask, swallow
- moon return
- provider flip
- PR ring states
- moods: Dozy, Focused, Satisfied, Fretful, and Fretful + Satisfied
- stale and offline

**Performance:** with `?perf`, 20 orbs, 4 asks, 2 failures and 3 eggs, JS ≤ 2 ms per frame at idle on this machine, and draw calls ≤ today's count + 2 at idle.

### 7.4 Live soak (before making the feed the default)

- **Run:** the sidecar against the real T3 for 24 h with `--tap` logging, alongside the old in-process runtime with its snapshots logged.
- **Compare:**
  - every thread the old runtime swallowed while T3 was reachable has a `finished` within 10 s;
  - there are **zero** `finished` events for threads T3 still lists as active;
  - zero events during the deliberate T3 restart in the soak.
- **Measure:**
  - MCP call rate: average ≤ 3/s;
  - sidecar CPU: < 0.5% on average;
  - sidecar RSS: < 60 MB;
  - feed latency from T3's `updatedAt` to the event's `at`: median ≤ 2.5 s, p95 ≤ 6 s.

### 7.5 Owner acceptance

For each visible PR, Josie reviews:
- the screenshot set;
- a 20 to 40 s screen recording of the real app driven by `scripts/demo.sh`-style fixture injection (a replay of a recorded session through `t3boii-feed --replay`).

`DESIGN.md` is updated in the same PR.

---

## 8. PR-sized steps

Each PR leaves `scripts/verify.sh` green and is published only with `scripts/publish.sh`.

**PR 1: Feed core (no visible change)**
- Scope: `FeedSchema`, `WorldModel`, `SnapshotDiff`, `ActivityRate`, `PollScheduler`; fixtures recorded with a small recorder; `FeedDiffChecks` and `PollSchedulerChecks`.
- Accept: fixtures 1 to 16 pass.

**PR 2: Sidecar binary**
- Scope: the `T3boiiFeed` target, `FeedServer`, `T3PollingSource`, `GrokRosterSource`, server identity, auth moved (the token file is shared but written only by the sidecar when it runs); `--tap`, `--record`, `--replay`; packaging; `FeedServerChecks`.
- The app is not wired yet.
- Accept: `t3boii-feed --tap` against real T3 for 1 h shows sane events; soak instrumentation in place.

**PR 3: App relay, behind a flag; then the default**
- Scope: `FeedSupervisor`, `FeedClient`, `PetLayer.feed`; `feed.js` reconciling `state` and translating events to today's animations (spawn, swallow, wait, fail, dissolve) through the compatibility path.
- The only behaviour change is **staleness**: no mass swallow on an outage.
- Defaults key `petFeedMode` is `sidecar` | `inprocess`. After the 24 h soak (§7.4), flip the default to `sidecar`.
- Adds the "unknown is not finished" `CLAUDE.md` rule.
- Accept: soak criteria met; T3 restart and token expiry cause no swallows.

**PR 4: Motion foundation**
- Scope: `Phase` and `spring` in `motion.js`; ring phase accumulators; the JS pulse replacing CSS `breathe`; new `PetMotionChecks` rules.
- No visual change yet beyond removing the busy-to-quiet snap.
- Accept: 6 h-uptime buzz metrics pass; screenshots match today.

**PR 5: Activity-driven orbit and pulse**
- Scope: §5.3 (ring multiplier, surge, pulse period and amplitude) and moon speed; `activity` from the feed.
- Accept: caps and no-overtaking metrics; Josie's look at a busy-orbit recording.

**PR 6: Mood**
- Scope: `mood.js`, the four moods with blending, Satisfied after swallows, Fretful inputs (failures, plus asks once PR 7 lands; it uses `waiting` until then).
- Accept: mood screenshots; buzz metrics with mood switches every 5 s.

**PR 7: Questions float (he no longer holds them)**
- Scope: the ASKING mode, ask arc, dot plus 3D hook ("?" and "!"), escalation, minimum display, answered reverse morph; remove `HOLD_POSE` and `holdAnchor` for waiting; the shared projector in `pet.js`; `DESIGN.md` Needs you rewritten; `PRODUCT.md` line.
- Accept: ask layout metrics; RM set; Josie.

**PR 8: Failures in the worry zone, plus mend**
- Scope: the FAULTED zone, chipped silhouette, sputter bursts, seen via settled, MENDING on resume.
- Accept: screenshots; mend from a fixture.

**PR 9: Messages and queue**
- Scope: glint from behind with the layer hop and gulp; colours; caps; queue beads (flag `queue`, default on if the soak's call budget holds).
- Accept: glint metrics; screenshots on near and far orbs.

**PR 10: Snooze eggs**
- Scope: the EGG row, rest, wobble window, hatch into each target state.
- Accept: replay of a snooze fixture with the wake 90 s out; screenshots.

**PR 11: Provider flip, plus PR ring**
- Scope: the flip and flash (always on); the PR ring (flag `pr`, **off until one real linked-PR payload has been recorded and its check fields confirmed**).
- Accept: flip screenshots; PR ring from a recorded fixture.

**PR 12: Halo seeds prototype**
- Scope: flag `seeds`, off by default, with a demo toggle.
- Accept: Josie decides whether it ships.

**PR 13: Demo refresh**
- Scope: update `demo.js` beats to show the new states, with Josie's go-ahead.

**Order and dependencies**
- PRs 1 → 2 → 3 are the critical path.
- PR 4 can run in parallel with PRs 1 to 3.
- PRs 5 to 11 depend on PRs 3 and 4 but are independent of each other, apart from PR 6 using PR 7's asks.
- **Size:** about 3 weeks of focused work for PRs 1 to 11.

---

## 9. Pushback and risks

1. **Snoozed is an inbox state, not work.**
   - In T3, snoozing defers a thread in your inbox. It is usually idle or completed, and none is snoozed right now.
   - Showing eggs therefore puts **non-working** threads back around him, which cuts against "settled is not shown".
   - When an idle egg wakes, the canon makes it hatch and then be swallowed straight away. That reads oddly: born, then eaten.
   - My default: eggs only for threads snoozed while they still had something live (an active status, an ask or an unseen failure), plus at most 6 others. **Josie should confirm** whether every snoozed thread gets an egg, and what an idle hatch does: swallow (default) or fade.
2. **Glints aren't real-time, and "agent vs external" is one colour.**
   - Message detection depends on reading the thread's activity, which is gated by `itemCount`. A glint lands 2 to 4 s after the message.
   - A message to an idle thread first shows as a START from his forehead, then the glint, because that's how T3 behaves: the message restarts the thread.
   - Agents, MCP callers and bots all record `createdBy: agent` with an anonymous client id, so they can't be told apart without a T3 change.
3. **Queues cost per-thread calls, and their timing is fuzzy.**
   - `t3_queue_list` is per thread. I gate it to recently messaged running threads every 6 s, so a bead can appear up to 6 s late or be missed entirely if a queued message is consumed within one interval.
   - Queues are also rare in practice. The plan puts queues behind a flag and keeps them only if the soak shows the budget holds.
4. **PR/CI is unverified and, on this machine, unused.**
   - No thread here has a linked PR, because this workflow publishes with `scripts/publish.sh`. I could not confirm that `list_thread_pull_requests` returns check state.
   - The ring stays behind a flag until a real payload is recorded. It may never show for Josie.
5. **Per-orb speed conflicts with shared rings.**
   - If every orb's angular speed followed its own activity, busy orbs would overtake quiet ones on the same ring and collide.
   - So: **ring** speed follows the ring's mean activity (capped at ×1.6), and each orb **surges ahead or lags within its slot** (±0.25 slot). Individual activity is mostly carried by the pulse.
   - If Josie wants truly independent speeds, orbs would need their own lanes (one ring per orb), which doesn't fit 20 orbs.
6. **"He does not hold questions" weakens the strongest needs-you signal.**
   - The held, bouncing orb with his gaze going back and forth is the most noticeable thing he does today.
   - Floating amber question marks, Fretful mood, glances and escalation by age replace it.
   - If questions still get missed in practice, I'd restore a **brief** gesture (he points or nods toward the newest mark for 1.5 s) rather than the hold.
7. **The question mark is half DOM, half WebGL.**
   - The dot is the DOM orb (it keeps its icon and click target); the hook is a lit 3D tube. They must stay aligned across two renderers, so a shared projector and a 1 px alignment check are planned.
   - The same applies to egg shells and glints crossing his silhouette.
   - The lasting fix is to move orbs into WebGL, which is out of scope here and called out as follow-up.
8. **Approvals are partly inferred.**
   - `t3_pending_request_list` lists questions only. The "!" relies on `approval_request` items or the count-minus-questions fallback, so a mislabelled kind is possible.
   - Secret requests show as "?". Proposed plans awaiting approval show as "!".
   - Standing rule: a "!" approval is owned by the thread's owning bot, which decides it itself and does not wait on Josie; only spending, publishing, sending, or destructive/irreversible actions come to her (§5.6).
9. **The sidecar is real added complexity.**
   - It adds a process, a loopback port, a token, codesigning and a supervisor.
   - The same `FeedSource` / `WorldModel` / diff could run as an in-process actor, with the HTTP server added later. That would be a simpler PR 3 with the same swap path.
   - I've planned the sidecar as decided, but kept `petFeedMode = inprocess` as an escape hatch. If the sidecar costs more than it saves, we can stay in-process without losing anything in the schema.
10. **T3 local state is not stable enough to read.** Beyond `server-runtime.json` (for port and restart detection), the sidecar reads nothing from `~/.t3`. Its database is private, recently re-schemed, in WAL mode, and huge.
11. **There are two existing bugs worth fixing early, whatever happens to the rest:**
    - A T3 outage or token expiry longer than about 15 s makes him swallow every orb and dance (`OrbitRuntime` fallback plus removal hold). PR 3 fixes it; a 10-line stopgap in `OrbitRuntime` could land sooner.
    - Orb breathing snaps when a thread goes between busy and quiet, because the CSS animation restarts. PR 4 fixes it.
12. **Provider-native subagent threads report `idle`.** Moons still rely on today's heuristic of reading the parent's `subagent` items and matching child threads by id suffix or title. It is fragile against T3 changes, so it is pinned by fixture 15.
13. **Polling load on T3.** The 2 s hot cadence is faster than today's 5 s. `itemCount` gating should keep the total *lower* than today, but if T3 shows strain, the adaptive backoff and a `--hot-period` flag are the levers. The soak measures it.
14. **Limits are untouched.** The decisions don't mention them, so crying and dissolve stay exactly as they are.
