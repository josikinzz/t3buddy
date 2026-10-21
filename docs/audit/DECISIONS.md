# Audit decisions

Final judgement on the nine lanes in this folder, 2026-10-20, branch `chore/agent-friendly` from `0fa5ef6`.
Priority: agent-friendliness first (one AGENTS.md, one fast verify command, a code map, dead code gone,
behavior tests), then real bugs, then perf. Canon in `docs/pet-status-spec.md`, `DESIGN.md` and the
roadmap is fixed: orbits, `?`/`!` marks, eggs, seeds, glints, moods, nod, queue seeds, ring tuck,
rounded favicons, the Grok Bot usage card, `!` owned by the thread's bot.

A REJECT is a judgement for this run, not a claim the lane was wrong, unless the reason says so.
"Follow-up" marks a real issue left for its own change.

## Findings

### docs-agents

| # | Verdict | Reason |
|---|---|---|
| P1.1 stale required reading | ACCEPT | AGENTS gets a reading order with the status spec as canon; README and DESIGN lines that describe held questions and outage swallows are corrected. |
| P1.2 wrong connection architecture | ACCEPT | README connection and troubleshooting text follows the real route: `server-runtime.json` discovery, sidecar, loopback SSE, app relay. |
| P1.3 README gives `!` to the owner | ACCEPT | One line; contradicts the standing rule at spec:509-511. |
| P2.1 no map of the feed code | ACCEPT | AGENTS gets one code map; README links to it instead of keeping a second one. |
| P2.2 plan reads as a shipped interface | ACCEPT | Status banner on the spec naming `FeedSchema.swift` as the wire contract; the helper now rejects unknown flags such as `--replay` (FS8). |
| P2.3 run/install can show an old bundle | ACCEPT | Docs say to package before judging a change; the packaged-check also requires the helper and page (BI2). |
| P2.4 verify coverage unclear | ACCEPT | AGENTS says what each verify mode covers and what stays manual (screenshots, soak). |

### tests-ci

| # | Verdict | Reason |
|---|---|---|
| 1 page adapter never executed | ACCEPT in part | Node behavior tests drive the real `feed.js`, `motion.js` and `effects.js` in the verify command. The WKWebView smoke replay is rejected for now: it needs a GUI host harness the check target cannot reach (see SA3). |
| 2 restart drill outside verify | ACCEPT | `scripts/verify.sh --full` builds, then runs the drill against the just-built helper. `--full` is the merge gate. |
| 3 no CI | REJECT | Cannot be verified without pushing, and a workflow file lands in the public tree; the owner decides that. |
| 4 motion lint is spelling-bound | ACCEPT | The clock-times-rate rule also catches `cos`; a Node test checks `Phase` stays continuous through a rate change at six hours of uptime. |
| 5 `?`/`!` test reads source text | ACCEPT | Replace with a Node test that drives `createOrbit` and reads `asks()[].kind`, if a small DOM stub runs it; otherwise keep the old check and say so. |
| 6 fragmented caches, no focused rerun | ACCEPT | One `scripts/verify.sh` with an overridable scratch path, per-stage timings and a check-name filter. `check_widget.sh` is removed and its callers are migrated. |

### build-install

| # | Verdict | Reason |
|---|---|---|
| packaging deletes the live bundle first | REJECT | Real but rare, and fixing it needs a packaging and launch drill this run may not do (no install, no `outputs/`). Follow-up. |
| run/install reuse stale or partial bundles | ACCEPT | The packaged predicate also requires the helper and `Pet/index.html`; README says to package before judging a change. Freshness tracking is not added. |
| privacy scan skips paths and binaries | ACCEPT in part | Added and renamed paths go through the same term scan. A reviewed media manifest is rejected as heavier than the risk. |
| intermediate commits hide private text | ACCEPT | `--check` scans each new commit's diff, not only the net one. |
| LaunchAgent replace has no recovery | REJECT | Needs a launchctl drill; installing is out of bounds for this run. Follow-up. |
| check never validates the release artifact | REJECT | Needs a packaging gate in an isolated output folder; follow-up with the packaging fix. |

### dead-code

| # | Verdict | Reason |
|---|---|---|
| 1 Local Models samples unused memory | ACCEPT | No consumer, a refresh cost, and a sampler error can overwrite model status. Process Memory keeps the sampler. |
| 2 model picker activation chain | ACCEPT | No caller in the app; no package outside this repo depends on these libraries (searched `~/Projects/*/Package.swift`). Remove activation and its tests; keep loaded-model detection, unload and host normalization. |
| 3 two update triggers per runtime | REJECT | Timing-sensitive UI, no measured cost; removing one needs on-screen verification of busy states. |

### types-boundaries

| # | Verdict | Reason |
|---|---|---|
| 1 relay bypasses version gate | REJECT | Helper and app ship in one bundle; no observed skew. A typed SSE ingress is a redesign without a failing case. |
| 2 spec describes another protocol | ACCEPT | Same fix as DA P2.2: banner plus pointer to the Swift schema. |
| 3 unknown subagent status counts as finished | ACCEPT | Breaks "unknown is not finished". A moon ends only on the spec's terminal statuses (spec:146); anything else fades. |
| 4 orb types admit contradictions | REJECT | Type redesign across producers with no observed bad payload. |
| 5 bridge constants have no owner | REJECT | Values agree today; a fix needs config injection or another source-text check (the pattern TC5 removes). |
| 6 misspelled flags pass silently | ACCEPT | `FeedFlags` reports unknown names; the helper refuses them and the app logs them. |

### swift-app

| # | Verdict | Reason |
|---|---|---|
| P1 Keychain migration deletes before durable save | ACCEPT | Small: delete the old item only after the file write succeeds and reads back. |
| P1 content rules fail open | REJECT | Failing closed blanks the pet when a static rule list fails to compile; the page loads only bundled files. Revisit with a retry. |
| P2 app host outside the check target | REJECT | Target restructuring; follow-up once the desktop phase settles the host. |
| P2 installer accepts an incomplete package | ACCEPT | Same fix as BI2. |
| P2 Connect T3 shows no result | REJECT | A UI feature and product call, not cleanup. |
| P2 subscription timers leak on restart | ACCEPT | Invalidate before scheduling, like the three peer runtimes. |

### feed-sidecar

| # | Verdict | Reason |
|---|---|---|
| 1 discovery cannot publish first file | REJECT | False: `FileManager.replaceItemAt` installs a missing destination on macOS (measured, `/tmp/t3audit/rep/r.swift`). |
| 2 discarded poll consumes resync | ACCEPT | A cancelled read keeps its resync owed and returns nothing. A restart's cancellations must never swallow. |
| 3 quiet streams go stale | ACCEPT | Pings count as hearing the helper; the in-app fallback relies on its own world's staleness once it has read T3. |
| 4 reconnect can miss state changes | ACCEPT | Every reconnect gets the current state; the relay already drops an unchanged one. |
| 5 fallback and helper share no budget | REJECT | Cross-process ownership is a design project; follow-up. |
| 6 recent-list limit loses finishes | REJECT | Per-thread probes spend the 3/s budget; the miss fades, which is canon-safe. Follow-up. |
| 7 session retry skips bucket and count | ACCEPT | The retry waits for the bucket and is counted like any call. |
| 8 `--replay` silently runs live | ACCEPT | Unknown flags are refused before any source is built. |

### pet-web

| # | Verdict | Reason |
|---|---|---|
| 1 cancelled glints keep their flight slot | ACCEPT | Three vanished targets stop every later glint. Effects report an ended flight either way; only an arrival gulps. |
| 2 startup replay skips seeds and staleness | ACCEPT | One function applies a snapshot, live or buffered. |
| 3 Reduce Motion misses CSS | ACCEPT in part | CSS animations follow the same reduced flag as JS. The seed drop stays as it is: canon promises only a still halo. |
| 4 no executable web check | ACCEPT in part | Same as TC1: Node tests in verify; the full page runner is a follow-up. |
| 5 seed crack material leaks | ACCEPT | Dispose it with the seed; shared geometry stays. |
| 6 stale comments steer agents back | ACCEPT | Fix the `orbit.js` header and the `pet.js` holding comment; spec banner covers the plan. |

### perf

| # | Verdict | Reason |
|---|---|---|
| P1 warm-up discards the first seed read | ACCEPT | The roadmap's slow-seeds gap: hold the read seeds until the first published reading. |
| P1 source deadline is cooperative | REJECT | Shipped sources cancel through URLSession and sleeps; the engine check covers a hanging source; startup latency is owner-approved. |
| P2 idle wakes at display rate | REJECT | Unmeasured; needs a benchmark before touching the frame loop. |
| P2 per-frame allocations | REJECT | Unmeasured; risk to every pose. |
| P2 three full-viewport canvases | REJECT | The full-desktop phase reshapes these surfaces; profile then. |
| P2 seed crack material | ACCEPT | Duplicate of PW5. |
| P2 no runtime perf evidence | REJECT | Worth building with the desktop phase, not in a cleanup. |

**Totals.** 55 findings: 36 accepted (4 of them in part), 19 rejected.

## Plan

Each step is its own commit, and `scripts/verify.sh` (or, until it exists, `check_widget.sh`) is
green after each.

1. This file.
2. Verify command: `scripts/verify.sh` replaces `check_widget.sh`, adds Node pet tests, per-stage
   timings, a check filter and `--full` with the restart drill (TC1, TC2, TC4, TC6).
3. Subtract: drop Local Models memory sampling and the activation chain (DC1, DC2).
4. Agent docs: AGENTS.md with reading order, code map and verify modes; README, DESIGN and spec
   corrections; stale pet comments (DA all, TB2, PW6).
5. Sidecar fixes, each with a check where the code has a seam: reconnect state, quiet stale,
   resync on cancel, terminal statuses, session retry, flags and CLI, seed warm-up (FS2-4, FS7-8,
   TB3, TB6, PF1).
6. Pet fixes with Node tests: glint release, seed crack, snapshot replay, Reduce Motion CSS,
   `?`/`!` behavior test (PW1-3, PW5, TC5).
7. App and scripts: Keychain migration, subscription timers, packaged predicate, publish scan
   (SA1, SA6, BI2, BI3, BI4).

## Outcome

All 36 accepted findings shipped as planned; `scripts/verify.sh --full` is green on the tip
(2 min 3 s: drill 106 s, the rest about 15 s). Departures from the plan, each a judgement call:

- `pr` is no longer an accepted feed flag name, because nothing reads pull requests yet; the helper
  refuses it and the app ignores it. Add it to `FeedFlags.known` when the PR reader lands.
- Under Reduce Motion the failure jolt (`crack-jolt`) is off too; `DESIGN.md` already promised no
  shiver there.
- Installed-model enumeration stays: Magnitude needs it for loaded-model sizes, and DC2 did not
  ask for it.
- The restart drill gained a restart whose first poll misses the 8 s deadline. With the FS2 fix
  removed, it swallows the cancelled thread and fails (checked by hand).
- `scripts/publish_check_drill.sh` drills the publish scan and runs in every verify.
- The audit lanes cited a private roadmap path, which `publish.sh` refused; scrubbed in review
  round 1 below.

## Review round 1

`review-1-code.md` and `review-1-ergonomics.md`. All five findings addressed; none dismissed.

| Finding | Verdict | Reason |
|---|---|---|
| blocker: private project names and paths in `docs/audit` | ADDRESSED | Lanes say "the owner's private roadmap" instead of its path; the HUD proposal's real project name (on `main` before this branch) is gone too. The publish scan of the tip now passes. |
| should-fix: token readback fails on fractional-second expiry | ADDRESSED | Confirmed red with a new check; the readback compares the bytes written, not decoded values. |
| should-fix: NAME is text in Swift, a regex in Node | ADDRESSED | Node gets NAME escaped and case-insensitive; `(` and upper case now work in both. A self-test of `verify.sh` was not added: the hand-checked cases are in the commit. |
| should-fix: an unmatched NAME passes | ADDRESSED | verify counts the Swift checks and Node tests that ran and fails at zero. |
| nit: lanes prescribe `check_widget.sh` | ADDRESSED | The three forward-looking lines name `verify.sh --full`; lines citing the old script as evidence stay as history. |

## Review: shoggoth pet

`review-shoggoth.md`, on `feat/shoggoth-pet`. All three findings addressed; none dismissed.

| Finding | Verdict | Reason |
|---|---|---|
| should-fix: ooze ignores the head and the body's deformation | ADDRESSED | Ooze points are stored at rest and moved each frame by a JS copy of the vertex shader's deformation; a new `weep` still checks the copy against the GPU (under 1 mm) with the head turned 18.8°, and capture fails if they disagree. A track whose first ray missed its eye is now skipped. |
| should-fix: the eye-flower never blinks or squints | ADDRESSED | One lid function serves both eye materials; the flower's 8 eyes close toward their spokes on the same lid state. A Node test reads the real texture from the GLB; a `blink` still shows it closed. |
| should-fix: `pet_stills.py compare` passes on missing or different evidence | ADDRESSED | It now fails on an empty set, a missing PNG or state, and any byte difference; checked on four hand-made cases. |
| owner ask: busy-state white blobs | ADDRESSED in part | Below full power the glow keeps pupils and irises showing. At 15 and over the eyes are still white across, as DESIGN.md says; changing that is the owner's call. |

T3boii's 11 stills stayed byte-identical through every fix (`compare` exit 0).
