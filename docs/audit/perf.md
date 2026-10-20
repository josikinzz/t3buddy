# Performance audit

Source audit at `0fa5ef6`, 2026-10-20. Only this report was written.
No app launch, build, live MCP calls, installed-app inspection, or output generation.
CPU, GPU time, allocation bytes per frame, RSS, and actual startup timings are unknown.
The owner's approximately 22-80 s report is context, not a measurement from this audit.
No P0 found. Priorities below reflect source-backed impact, not measured speedups.

Throughput checkpoint is n/a, read-only investigation.
Explain the Number keeps source-derived rates separate from runtime measurements.
Blast-radius analysis below stops at source evidence. Proposed fixes are untested.

## P1. Seed warm-up consumes freshness before anything is published

- Evidence. `Sources/ModelWidgetCore/T3ThreadSource.swift:718-733` fetches seeds,
  sets `seedsReadAt`, and can return them with `warming: true`.
  `Sources/ModelWidgetCore/Feed/FeedWorld.swift:35` discards warming readings before
  copying seeds at line 43. The source does not retain that seed payload for reuse.
  `T3ThreadSource.swift:360` makes the next fetch eligible after 60 s.
- Impact. A successful startup read is thrown away. The first live orb snapshot
  can lack seeds until the next scheduled read. Agents tuning render startup
  would be optimizing the wrong subsystem. The roadmap explicitly records this
  gap in the owner's private roadmap, outside this repository.
- Fix. Cache the last successful seed observation in the source and include it in
  the first non-warming reading. Preserve nil as unread and [] as known empty.
  Do not bypass the world warm-up guard for thread observations.
- Blast radius. Scheduled-task freshness, seed failure state, flag-off behavior,
  initial state and reconnect. Verify a warming seed fetch followed by a live
  reading before 60 s, without a second scheduled-task call or synthetic launch.

## P1. The source deadline is cooperative, while mandatory work ignores the poll budget

- Evidence. `Sources/ModelWidgetCore/Feed/FeedEngine.swift:143-155` races work
  against sleep in a structured task group, then cancels the loser. The group
  still waits for its children to finish. `T3ThreadSource.swift:539-591` runs
  metadata, project pages, and each project's active pages serially. The active
  listing loop has no `pollHasTime` or cancellation check. Its optional recent
  branch can also run regardless of budget when `left` or resync is true.
  `T3ThreadSource.swift:313-315` budgets optional starts for 5 s.
- Impact. The advertised 8 s source deadline is not a hard upper bound for
  arbitrary FeedSource implementations. A cancellation-ignoring source can
  delay all publication at `FeedEngine.swift:76-86`, including healthy sources.
  URLSession and bucket sleeps do cooperate with cancellation, so this is not
  evidence that every HTTP timeout overruns. Many projects and pages still put
  mandatory serial work ahead of the first usable snapshot.
- Fix. Define cancellation and elapsed-budget semantics for FeedSource. Check
  cancellation between pages/projects and propagate it through optional reads.
  If splitting mandatory discovery across polls, carry explicit coverage so
  an unvisited project cannot imply a thread ended. Keep warm-up event suppression.
- Blast radius. First state, resync, project discovery, disappearance detection,
  and healthy Grok delivery. Verify a fake cancellation-ignoring source, slow
  paginated projects, and restart during discovery. Bound completion without
  leaving detached poll tasks accumulating.
- Canon constraint. The owner's private roadmap says roughly 22 s
  launch-to-orbs is acceptable. Do not turn that approved latency into a demand
  for a new startup animation or premature partial thread events.

## P2. Idle rendering still wakes at display cadence

- Evidence. `Resources/Pet/pet.js:1661-1706` always queues the next rAF, then
  rejects frames before the 30 or 60 fps threshold. Constants are at lines 72-73.
  Sleep changes the pose but does not select a lower frame rate at line 1678.
- Impact. Idle and Reduce Motion retain display-rate JS wakeups even when no
  frame is drawn. This matters for a persistent desktop companion and gives
  agents a misleading distinction between drawn fps and scheduler activity.
  The CPU saving from changing it is unmeasured.
- Fix. Schedule the next idle deadline with a timer followed by rAF. Cancel both
  on pause. Let input and visible transitions preempt idle waiting for 60 fps.
  Keep phase advancement based on dt and reset timing correctly on resume.
- Blast radius. Pointer response, spawn flights, swallow staggering, hit regions,
  occlusion, and Reduce Motion. Verify callback counts separately from render
  counts on 60 Hz and high-refresh displays, plus pause/resume and live input.
- Canon constraint. Preserve the approved 30 fps idle and 60 fps lively behavior
  in `DESIGN.md:249` and `docs/pet-status-spec.md:667`. The older proposal's
  12/24 fps world budget is not authority to lower those rates.

## P2. Bone transforms and effect bridges allocate during every drawn frame

- Evidence. `Resources/Pet/pet.js:216-221` constructs a quaternion, Euler, and
  cloned quaternion per `delta` invocation. The pose loop calls it per affected
  bone at line 1572, with eye calls at line 1589. Lines 1693-1700 additionally
  create temporary vectors, quaternions, and bridge objects for effects.
  `Resources/Pet/effects.js:583` allocates a set and mapped array on seed updates,
  and line 604 creates home vectors per seed.
- Impact. Allocation churn scales with bones, effects, and rendered fps. Garbage
  collection may interrupt motion. Source proves repeated allocations, not their
  byte count or that GC is currently a bottleneck.
- Fix. Reuse scratch Euler/quaternion objects for synchronous bone calculations.
  Precompute immutable inverse rest rotations. Reuse effect scratch values only
  after checking whether callees retain them. Move membership reconciliation
  to snapshot changes while keeping positional animation per frame.
- Blast radius. All poses, eye alignment, seed motion, effect anchors, and
  reference ownership. Compare identical synthetic-clock poses and frame-time
  distributions before and after. Never share mutable scratch across retained
  anchors or asynchronous callbacks.

## P2. Three full-viewport canvas backing stores scale with the desktop

- Evidence. `Resources/Pet/orbit.js:1063-1074` sizes front, back, and label
  canvases to `innerWidth * dpr` by `innerHeight * dpr`, capped at DPR 2.
  Dirty rectangles reduce clears at line 1070 but not backing dimensions.
  The pet WebGL renderer already limits itself to STAGE at `pet.js:157-158`.
- Impact. The 2D backing area grows with window area and DPR squared, even for
  a small pet. A full-desktop phase magnifies this cost. GPU residency, buffering,
  and compositing overhead are unknown. Do not assume the WebGL canvas is also
  full-screen or claim full-screen clears on every frame.
- Fix. Bound each 2D backing store to its drawable content, with explicit origin
  transforms and overflow margins. Profile before choosing the larger WebGL
  orb migration proposed in the older HUD document.
- Blast radius. Front/back depth, glow clipping, trails, question labels, screen
  edge layout, hit testing, resize, and mixed-DPR displays. Check screenshots
  and click alignment for outer rings, asks, and flights across canvas bounds.

## P2. Seed removal misses a separately owned material

- Evidence. `Resources/Pet/effects.js:591` constructs a MeshBasicMaterial for each
  seed's crack mesh. The retained record at line 597 omits that mesh. Removal at
  line 584 disposes only `s.material` before detaching the group.
- Impact. A failed seed whose crack has rendered can leave renderer resources
  undisposed after removal. This is a resource-lifetime defect, not proof of
  measured process-memory growth. Unrendered hidden materials may never acquire
  GPU resources. The missing crack reference also belongs to the behavior lane.
- Fix. Retain the crack mesh and dispose its private material on seed removal.
  Keep shared `seedGeometry` and `seedCrack` geometry alive for other seeds.
- Blast radius. Scheduled seed churn and failed-seed presentation. Exercise
  repeated add, failure, draw, remove cycles and inspect renderer resources and
  heap retention after warm-up. Avoid disposing shared geometry per seed.

## P2. There is no comparable runtime performance evidence for agents

- Evidence. `Resources/Pet/pet.js:1704` records only rendered-frame count.
  `Resources/Pet/skinning.js:58-80` logs the skinning stage in isolation.
  `Sources/T3boiiFeed/main.swift:40-47` logs cumulative logical tool calls.
  `T3ThreadSource.swift:56-73` counts once before initialization and a possible
  session-expiry retry, so these are not HTTP-request counts.
  `docs/pet-status-spec.md:677,809` calls for a perf overlay and workload budget.
- Impact. Agents cannot distinguish startup discovery, model preparation,
  frame CPU, canvas work, GPU work, GC, and feed pressure from one elapsed time.
  `CallBucket.swift:7` caps each client's logical calls at a sustained 3/s with
  burst capacity 10. It is not a process-wide or HTTP-request cap. Fallback creates
  a separate source at `Sources/LocalModelWidget/FeedClient.swift:142-143`, so
  helper and fallback can overlap until a live helper state is accepted.
- Fix. Add an opt-in bounded metrics collector and repeatable generic fixture.
  Record startup milestones through first live orbs and first seeds, frame CPU
  percentiles, callbacks versus renders, draw calls, allocation samples, and
  memory plateau under churn. Separate logical calls, HTTP requests, bucket
  waits, retries, and helper/fallback ownership. Use native GPU profiling for
  GPU time. Report run count, spread, display/DPR, workload, and limiter.
- Blast radius. Diagnostics must stay off by default, avoid thread contents and
  tokens, and not retain unbounded frame histories. Preserve existing feed caps
  and backoff rather than increasing call rate to hide latency.

## Behavior that performance work must preserve

- `docs/pet-status-spec.md:3-24` supersedes the environment proposal. No weather,
  island, background, belly glow, settled display, or guessed sender beams.
  Forehead births, mouth finishes, subagent moons, questions, failures, eggs,
  and queue beads keep their meanings. Upcoming desktop scope is not approval
  to import the old environment design.
- `Resources/Pet/feed.js:4-6,16-29` reserves swallowing for finished events.
  Unknown, warming, missing, restarting, and unreachable are not finished.
  Keep sidecar separation, offline page, and MCP-only T3 observations from
  `docs/pet-status-spec.md:7,205,251`. Do not read T3's database for speed.
- Preserve lit 3D effects, fixed camera, Reduce Motion, motion phase continuity,
  and pause on occlusion/screen sleep. Keep `tremble()` for rapid motion.
  Performance changes require visual and behavior checks as well as timings.

## Verification boundary

This audit traced producers, consumers, lifetime cleanup, and scheduling in source.
No benchmark was run, so no performance budget is claimed passed or failed.
No leak magnitude, per-frame allocation count, or cause of the reported 22 s is
established. The 80 s seed symptom has a matching source path and roadmap note,
but was not reproduced here. No code, outputs, installed app, or existing image
artifacts were changed. A future implementation must run relevant focused checks
and `scripts/check_widget.sh` (since replaced by `scripts/verify.sh --full`) before merge.
