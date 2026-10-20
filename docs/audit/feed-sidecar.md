# Feed sidecar audit

Audited 2026-10-20 at `0fa5ef6ea9baa9a3e797e1d520577e3faf340ddd`.
Read-only investigation. Only this report was written. No P0 finding.

## Scope and operating model

`T3ThreadSource` reads MCP into `FeedReading`. `FeedEngine` polls sources and
passes readings to `FeedWorld`, which derives state and events. `FeedServer`
serves them over authenticated loopback SSE. `FeedClient` batches the stream
through `FeedRelay` to `Resources/Pet/feed.js`, with an in-app polling fallback.
The fallback is included only where it affects sidecar ownership and handoff.
Rendering, dashboard features, deployment, and the desktop phase are outside this lane.

Evidence below is source-traced unless explicitly marked executed. Proposed
regression cases have not been run. Priority reflects user-visible correctness
and the risk of an agent trusting a misleading interface.

## P1 findings

### 1. Discovery cannot publish its first file

- Evidence. `Sources/ModelWidgetCore/Feed/FeedDiscovery.swift:33-38` creates a
  temporary file and unconditionally calls `replaceItemAt` on `feed.json`.
  That API replaces an existing item. No branch installs a missing destination.
  `Sources/T3boiiFeed/main.swift:98-105` treats a save error as fatal.
- Repro. Start the serving helper with no discovery file, including after a clean
  shutdown removes it at `FeedDiscovery.swift:42-44`. The initial replacement
  fails and the helper exits. This filesystem repro was not executed.
- Impact. A normal launch can fall into supervisor retries and in-app fallback.
  Agents inspecting the app can mistake fallback success for a healthy helper.
- Fix. Atomically rename the permission-restricted temporary file onto the
  destination, handling failure and cleanup. Test absent and existing targets.
- Blast radius. Discovery publication, startup, restart, and helper attachment.
  Preserve the lock, mode 0600, per-start token, and PID-checked removal.

### 2. A discarded poll can consume the restart resync

- Evidence. `Sources/ModelWidgetCore/Feed/FeedEngine.swift:143-152` takes the first
  task-group result and cancels the other. `Sources/ModelWidgetCore/T3ThreadSource.swift:438-440`
  clears `resyncReason` before the engine accepts the reading. Optional reads
  swallow cancellation through `try?`, including `T3ThreadSource.swift:855` and
  `T3ThreadSource.swift:887`. There is no cancellation check before returning.
- Repro trace. Keep an old active orb, restart T3, and delay an optional read
  across the eight-second deadline. The timer wins. Cancellation lets the source
  finish building a resync reading, clear the flag, and return a discarded value.
  The next ordinary reading reports the cancellation as terminal evidence.
  `Sources/ModelWidgetCore/Feed/FeedWorld.swift:82-87` then emits `finished`.
- Impact. Slow recovery can swallow restart cancellations, violating approved
  canon. The log can claim a silent resync that the world never received.
- Fix. Commit the source's resync generation only when its reading is accepted.
  At minimum preserve it on cancellation and on warming readings that the world
  rejects at `FeedWorld.swift:35`. Test timeout during optional reads after restart.
- Blast radius. Source cursor updates, deadline handling, world reconciliation,
  and the restart drill. Preserve later genuine finishes after recovery.

### 3. Healthy quiet streams become permanently stale in the app

- Evidence. `Sources/ModelWidgetCore/Feed/FeedEngine.swift:134-139` publishes only
  changes. `Sources/ModelWidgetCore/Feed/FeedServer.swift:141-145` sends comment
  pings. `Sources/LocalModelWidget/FeedClient.swift:96-97` updates only
  `helperHeardAt` for those lines. `heardAt` changes only on data frames at
  `FeedClient.swift:111-113`, but `FeedClient.swift:119-121` uses it to mark stale.
- Repro trace. Hold a live, unchanged snapshot for over 20 seconds while healthy
  polls and ten-second pings continue. The client marks it stale. Later identical
  successful polls emit no state to restore live status. The fallback path has
  the same unchanged-batch problem at `FeedClient.swift:158-165`.
- Impact. Quiet working threads look disconnected. Agents investigating the
  source are misled even when `/v1/state` remains live.
- Fix. Separate transport liveness from source freshness. Let pings refresh the
  transport clock, preserve explicit source staleness, and restore the last
  authoritative source status after a transient transport loss. Give fallback
  successful-poll liveness too. Test an unchanged live feed for at least 60 seconds.
- Blast radius. Client watchdogs and stale visuals. A responsive helper must still
  show stale when T3 itself cannot be read.

### 4. Reconnect can lose state changes with no new event

- Evidence. `Sources/ModelWidgetCore/Feed/FeedWorld.swift:149-156` increments `seq`
  only for events. Activity, seeds, and silent resync can change state at the same
  sequence. `Sources/ModelWidgetCore/Feed/FeedEngine.swift:48-52` returns no missed
  events for an equal cursor. `Sources/ModelWidgetCore/Feed/FeedServer.swift:121-124`
  sends state only when missed events are nonempty.
- Repro trace. Disconnect at sequence N. While disconnected, perform a silent
  resync or change only activity or seeds, leaving sequence N. Reconnect with
  `Last-Event-ID: N`. The response has no state until another change occurs.
- Impact. The page can retain removed orbs or outdated activity indefinitely.
  Event-cursor tests alone cannot prove snapshot recovery.
- Fix. Always send a current snapshot on reconnect, even with an empty replay.
  Capture subscription, snapshot, and replay consistently so concurrent polls
  cannot pair newer events with an older snapshot. Test both equal-cursor changes
  and a poll interleaved with stream setup.
- Blast radius. SSE framing and relay ordering. Do not invent lifecycle events
  just to advance the cursor or animate silent reconciliation.

### 5. Fallback and recovering helper share neither call budget nor auth ownership

- Evidence. `Sources/LocalModelWidget/FeedClient.swift:140-154` starts a new source
  and engine. It stops them only when a helper supplies a live state at
  `FeedClient.swift:105-109`. Meanwhile `Sources/T3boiiFeed/main.swift:36-37,102`
  polls independently. Each client owns a fresh bucket at
  `Sources/ModelWidgetCore/T3ThreadSource.swift:12,413`.
  Both also load, mint, save, and revoke shared credentials at
  `T3ThreadSource.swift:495-509,523-536`; the token-store lock is instance-local
  at `Sources/ModelWidgetCore/T3TokenFile.swift:48`.
- Repro trace. Start fallback while the helper is absent, then bring the helper
  back while both have sustained work. Both poll until helper warmup completes.
  With expired credentials, both can mint from the same saved credential state
  and overwrite it. Exact request rates and auth churn were not measured.
- Impact. The combined load can exceed the intended three-call sustained cap.
  Credential races can trigger extra token changes, resyncs, or failed reconnects.
  Per-client rate logs hide the combined load.
- Fix. Give polling and credential minting explicit cross-process ownership and
  a handoff protocol. Preserve the last scene while transferring ownership.
  Test helper recovery during fallback with expired credentials and count actual
  requests across both processes. Preserve fallback availability.
- Blast radius. Helper startup, fallback recovery, token rotation, Connect T3,
  and multiple app instances. The serving-only `feed.lock` does not cover fallback.

## P2 findings

### 6. The recent-list limit loses confirmed finishes during bursts

- Evidence. `Sources/ModelWidgetCore/T3ThreadSource.swift:575-588` detects departed
  active threads but fetches only 15 recent threads and ignores `nextCursor`.
  `T3ThreadSource.swift:739-743` derives terminal evidence only from that subset.
  `Sources/ModelWidgetCore/Feed/FeedWorld.swift:85-94` fades an unconfirmed absence
  after two good readings. The spec requires a per-thread drop-out probe at
  `docs/pet-status-spec.md:101`.
- Repro trace. Complete 16 or more listed threads in one project between polls.
  A departed thread outside the recent page has no terminal evidence. If it stays
  outside the page, it vanishes rather than being swallowed.
- Impact. Large parallel agent runs lose completion signals. A limit on recent
  history silently becomes a limit on lifecycle accuracy.
- Fix. Queue explicit reads for departed IDs under the existing bucket. Preserve
  unknown state while a probe is pending. Fade only confirmed disappearance or
  the approved absence policy. Test more than 15 simultaneous completions.
- Blast radius. Poll scheduling, recent caches, and finish latency. A failed or
  not-found probe must never fabricate a finish.

### 7. Session retries bypass the call bucket and accounting

- Evidence. `Sources/ModelWidgetCore/T3ThreadSource.swift:54-57` spends one token
  and increments counters once. The session-expiry retry at
  `T3ThreadSource.swift:62-67` sends another `tools/call` without either operation.
  `Sources/T3boiiFeed/main.swift:40-45` reports those logical-call counters.
- Repro trace. Make a session-bearing tool request return 404, then let its
  retried request succeed. Two tool requests are sent for one recorded call and
  one reservation. Repeated session loss defeats the advertised wire-rate cap.
- Impact. Agents can report compliant measurements while omitting retry traffic.
- Fix. Reserve budget and count each actual tool-request attempt, including
  retries. Keep handshake traffic separate and observable. Test repeated 404s
  with request timestamps, not just `CallBucket.take` in isolation.
- Blast radius. MCP recovery latency, accounting, and existing rate assertions.
  Preserve the single session-recovery retry and capacity-ten burst policy.

### 8. Documented replay options silently run live polling

- Evidence. `docs/pet-status-spec.md:76-78` describes `--record` and `--replay`.
  `Sources/T3boiiFeed/main.swift:16-36` parses selected flags but rejects no
  unknown options. It constructs live sources regardless. The spec still says
  "Nothing here has been built" at `docs/pet-status-spec.md:3`, despite the
  implemented sidecar. The actual CLI has no help path.
- Repro trace. `t3boii-feed --standalone --replay /missing-fixture` passes the mode
  guard and starts the normal live source, using default credentials unless
  separately overridden. This command was deliberately not executed.
- Impact. An agent following the spec can make live MCP and auth calls while
  believing it is replaying fixtures. Agents also cannot tell which planned
  protocol fields and scheduler guarantees are implemented.
- Fix. Reject unknown or unsupported options before constructing sources. Add
  side-effect-free help and an implemented-contract reference linked from the
  plan. Implement offline replay separately, with no default auth access.
- Blast radius. CLI scripts, investigation workflows, and fixture tooling.
  Preserve existing tap, parent-PID, standalone, flags, and fake-T3 overrides.

## Canon that fixes must preserve

- `docs/pet-status-spec.md:5-24` records the approved body and orb vocabulary.
  Forehead starts, mouth finishes, moons, glints from behind, question marks,
  cracked failures, eggs, provider flips, and flagged seeds remain intact.
- `docs/pet-status-spec.md:145-149,181` and `AGENTS.md:23` make unknown
  different from finished. Outages, slow polls, token rejection, and restart
  cancellations must not trigger swallowing. Missing threads fade safely.
- `docs/pet-status-spec.md:7,246-251` keeps the helper standalone, with public MCP
  reads and only `server-runtime.json` for local T3 discovery. Never read T3's DB
  or patch T3 to solve these issues. A future native stream preserves the contract.
- Preserve bearer auth, exact loopback Host checks, refusal of Origin, and the
  offline page relay at `Sources/ModelWidgetCore/Feed/FeedServer.swift:107-113`
  and `docs/pet-status-spec.md:196-206`. Tokens stay outside page JavaScript.
- The older HUD proposal's environment ideas are superseded by the status spec
  (`docs/pet-status-spec.md:3-6`). The newly mentioned desktop phase is separate
  work, not authorization to redesign this feed or revive older visuals.

## Verification and limits

Executed an in-memory Node import of the actual `Resources/Pet/feed.js`.
Assertions passed for eventless removal producing `fade: [id]` and explicit
`finished` producing no fade override. No test files or generated files were written.
This proves the page boundary's choice, not the Swift failure traces above.

Read `FeedWorldChecks`, `FeedServerChecks`, and the fake-T3 restart drill.
Their existing cases do not exercise discarded resyncs, unchanged-stream
freshness, same-cursor snapshot recovery, first discovery installation, or
cross-process fallback ownership. The drill's fake source returns empty
timelines immediately (`scripts/t3_restart_drill.py:127-143`).
No Swift build, full check script, live soak, restart drill, installed-app run,
or runtime timing measurement was performed under the one-file write limit.
Proposed fixes remain unimplemented and unverified.
A supplementary delegated explanation was stopped before returning a verdict.
No independent acceptance is claimed.

Boundary Discipline kept validation and ownership recommendations at MCP, file,
and SSE boundaries. Blast-radius tracing followed their effects through the
Swift relay into the actual page adapter. Throughput checkpoint is n/a for this
read-only investigation.
