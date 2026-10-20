# Pet web audit

Audited 2026-10-20 at `0fa5ef6`. Scope is `Resources/Pet/pet.js`, `orbit.js`,
`index.html`, `motion.js`, `effects.js`, and `skinning.js`, including marks,
scheduled seeds, queue seeds, eggs, and glints. Feed and native code were read
only to establish contracts. No P0 found. One P1 and five P2 findings follow.

Read-only investigation. Only this report was written. No app, build, server,
installed copy, or `outputs/` was touched. Existing untracked media was preserved.
Throughput checkpoint is n/a, read-only investigation.

## Overview and ownership

`pet.js:459` creates WebGL effects and `pet.js:462` creates the DOM orbit.
`pet.js:1673` owns the frame loop. Its order is pose, orbit, glints, marks,
queue seeds, PR rings, scheduled seeds, transient effects, then rendering.
`orbit.js:190` owns orb records and layout. `effects.js:37` owns 3D objects.
`motion.js:21` supplies accumulated phases. `skinning.js:55` repairs model weights.

The key concept is two renderers sharing page coordinates. DOM spheres, icons,
labels, and click regions coexist with lit WebGL marks and effects. Moving every
orb into WebGL would be a separate product change, not an audit cleanup.

## P1 findings

### 1. Cancelled glints permanently consume flight capacity

- Evidence. `pet.js:883` blocks launches when `glints.flying.size >= 3`.
  `pet.js:886` reserves that capacity. `pet.js:899` returns null when the target
  disappears. `effects.js:488` removes that effect, but `effects.js:489` calls
  `arrive` only when a position exists. The reservation is released only by
  `landGlint` at `pet.js:919`.
- Impact. Three disappeared targets can disable every later message glint for
  the page's lifetime. A future message to a stranded ID merely folds into its
  abandoned record at `pet.js:872`. This makes the HUD silently stop reporting
  messages and makes agent debugging misleading because WebGL has no flights.
- Repro. Launch glints, remove their target orbs before arrival, and repeat for
  three distinct IDs. Send a message to a surviving orb. It never launches.
  This includes demo reset and targets removed during a fast terminal transition.
- Proof run. Executed the shipped `effects.stepGlints` function in Node VM with
  a null target and no-op renderer operations. Result was zero effects and zero
  completion callbacks. Executed the shipped `pet.stepGlints` with three stranded
  reservations and one live waiting target. Result was zero launches and one
  still waiting. This proves the bookkeeping branches, not a rendered app repro.
- Fix. Give effects an unconditional completion/cancellation callback that
  releases the matching flight record. Only successful arrival should gulp.
  Release by record identity so an old callback cannot delete a newer flight.
  Prune `lastGulp` for removed targets too; `pet.js:921` only adds entries.
- Blast radius. Message folding, the global cap, per-orb spacing, queue consumption,
  and demo resets. Verify cancellation does not gulp, eat a queue seed, or produce
  rings. Verify the fourth target launches and a reused ID can receive messages.

## P2 findings

### 2. Startup replay skips part of the snapshot contract

- Evidence. `pet.js:1873` buffers the snapshot before the orbit exists.
  `pet.js:474` replays only `orbit.update` and `onLimits`. Normal application
  also sets orbit staleness at `pet.js:1872`, handles seeds at `pet.js:1875`,
  and sends messages at `pet.js:1876`.
- Impact. Initial scheduled seeds disappear until another snapshot arrives.
  A stale snapshot received before model load greys the DOM but leaves the new
  orbit's `feedStale` false, so its activity breathing can disagree with the feed.
  Agents must discover two subtly different snapshot application paths.
- Proof run. Invoked the shipped bridge `update` in Node VM before orbit creation
  with one seed. The pending snapshot retained the seed. The startup replay block
  contains no seed handler. The roadmap already records delayed startup seeds as
  a known gap; it is not a newly measured launch delay here.
- Fix. Apply buffered state through one shared snapshot application function once
  both renderers exist. Explicitly choose whether pre-ready message events are
  replayed or discarded; avoid emitting duplicate historical animations when the
  host re-sends state after ready.
- Blast radius. First launch, model-load latency, stale recovery, seeds, and bridge
  ready replay. Check a seed-only first state and a stale first state without a
  second feed message. Do not change the owner-accepted overall launch latency.

### 3. Reduce Motion does not reach CSS or seed drop motion

- Evidence. `pet.js:740` forwards the setting only to the orbit.
  `index.html:74` runs an infinite waiting pulse; `index.html:100` starts the egg
  transitions, and `index.html:112` defines mending animations. No reduced-motion
  selector or media rule exists in that stylesheet.
  `effects.js:585` stops seed laps when reduced, but `effects.js:609` still moves
  a dropping seed into the forehead and regrows it. `pet.js:951` does not gate drops.
- Impact. The host toggle and `?reduced` cannot consistently select a still/fade
  presentation. Egg transforms continue after JS selects its reduced path.
  Seed-drop reduction is a consistency recommendation; the current seed canon
  explicitly promises only a still halo. Slow question glow remains allowed.
- Repro. With Reduce Motion enabled, keep an orb waiting, retry a failed orb,
  or advance a seed's `lastRun`. Source paths still select the CSS animations or
  interpolated seed flight. This was traced statically, not captured on screen.
- Fix. Expose the resolved host-or-media setting as one document attribute and
  gate CSS with it. Give seed drops a still flash/fade path. Check switching the
  setting during an animation as well as loading with it already enabled.
- Blast radius. Questions, mending, eggs, seed drops, and demo `?reduced` scenarios.
  Preserve the normal-motion canon and keep the status signals visible.

### 4. Web behavior lacks the executable check promised by the spec

- Evidence. `docs/pet-status-spec.md:768` calls for loading the page and applying
  200 fixture events. `docs/pet-status-spec.md:780` specifies a synthetic-clock
  motion harness. `Tests/ModelWidgetChecks/PetLayerChecks.swift:6` instead starts
  native geometry checks. `PetMotionChecks.swift:5` reads source text and checks
  regex rules. `scripts/check_widget.sh:9` runs the Swift checks and then builds.
  No checked-in browser runner was found in the tracked file inventory.
- Impact. A green check cannot establish JS startup, DOM/WebGL alignment, lifecycle
  cancellation, or rig rendering. Agents changing marks, eggs, or glints have no
  repeatable behavioral gate, and findings 1 and 2 survive the current checks.
- Fix. Add a web-only fixture runner against the actual page. Start with launch,
  cancellation recovery, first-state seeds, reduced motion, and question-dot
  alignment. Use controlled time and generic fixtures. Connect it to the normal
  check command after it is deterministic; label visual/manual gates separately.
- Blast radius. Web test setup and check orchestration. Avoid real T3, installed
  app access, private project data, and tests that only search for implementation
  strings. Coordinate runner wiring with the repository-checks lane.

### 5. Removed scheduled seeds leak their crack material

- Evidence. `effects.js:591` allocates a distinct `MeshBasicMaterial` for every
  seed's crack. `effects.js:584` removes a seed and disposes only `s.material`.
  The crack material is never disposed there. Shared seed geometries are separate.
- Impact. Rendered failed seeds can leave GPU material resources allocated after
  schedules disappear or flags hide seeds. This is a lifecycle ownership trap
  for agents copying the existing removal pattern. Magnitude was not measured.
- Repro. Render a failed seed, remove it from the list, and repeat with new IDs.
  Observe disposal events or renderer program retention after completed renders.
  Allocation/removal asymmetry is source-confirmed; GPU retention was not run.
- Fix. Dispose `s.crack.material` when removing that seed, preferably through a
  seed-specific cleanup helper. Keep shared `seedGeometry` and `seedCrack` alive.
- Blast radius. Scheduled seed removal and flag changes. Queue seeds share the
  geometries, so disposing shared geometry per seed would introduce a new bug.

### 6. Stale behavioral guidance can steer agents back into rejected behavior

- Evidence. `orbit.js:27` still says the first waiting orb is held in his hands.
  `pet.js:786` retains a holding-out comment beside the ask state.
  `docs/pet-status-spec.md:3` says nothing has been built, and its PR 12 plan at
  `docs/pet-status-spec.md:887` still describes seeds as off by default.
  Current `DESIGN.md:234` describes the default-on seed presentation.
- Impact. An agent following the file header or implementation plan can restore
  the rejected hold pose, remove shipped features, or disable approved defaults.
- Fix. Replace obsolete web comments with current ownership and state transitions.
  Add a short status/supersession notice to the plan, distinguishing historical
  proposals from current decisions. Link to the current design and roadmap.
  Keep model-specific skinning assumptions documented rather than generalizing
  them into the upcoming desktop environment work.
- Blast radius. Agent onboarding and future refactors. Documentation changes
  must preserve historical decisions without presenting them as current work.

## Canon and boundaries that fixes must preserve

- `docs/pet-status-spec.md:5` records standalone operation without T3 patches.
  The page remains offline and receives no token, per spec line 205.
- Forehead launch; mouth swallow only on positive finish evidence; unknown is
  never finished. Settled threads stay hidden. No belly glow. See spec lines
  9-12 and `DESIGN.md:228`. Compatibility `update` still has removal semantics;
  do not replace the positive-evidence feed path with raw snapshot subtraction.
- Questions float near him as lit 3D marks, with the orb as the dot. He never
  holds them. Failures wait in the worry zone and mend on retry. Approvals remain
  the owning bot's responsibility under the spec's standing rule.
- Preserve capped activity motion, `Phase` integration, and `tremble` rate limits.
  Preserve glints from behind, three-flight and 0.6-second caps, queue folding,
  six snoozed eggs, and PR rings disabled until real payload validation.
- The roadmap's 16 October decisions approve brighter glints, default-on seeds
  and queue beads, and a 0.7-second question nod. Seeds fall into the forehead;
  they do not launch outward. Everything emitted stays 3D and lit like him.
- Environment, weather, island, and background are deferred in the current specs.
  The user identifies a forthcoming full-desktop phase; this audit neither blocks
  that new phase nor treats the older environment proposal as approval to build it.
  No inter-thread beams while sender identity is unknown. Demos use existing acts.

## Verification limits

Source inspection and memory-only Node VM branch experiments support this report.
The VM experiments stubbed renderer operations and did not load the complete page.
An initial Node invocation rejected an unsupported module flag; the CommonJS VM
run then succeeded. No browser, screenshot, GPU measurement, live feed, Swift
suite, or full app check ran. The build/check command writes build artifacts and
was deliberately left unrun under this audit's single-file-write boundary.
No independent delegated review completed. Automatic approval review rejected the
skill's Claude explainer because repository source would reach another provider.
The audit continued locally without retrying that export.

Minimize Reader Load shaped findings 2 and 6 by targeting duplicate state paths
and contradictory guidance. Blast-radius tracing kept each proposed fix tied to
its consumers; runtime proof is limited to the VM branches described above.
