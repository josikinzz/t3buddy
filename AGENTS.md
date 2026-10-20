# Agents working in this repo

A macOS dashboard plus T3boii, a 3D desk pet that shows T3 Code's threads as orbs around him. A
helper process, `t3boii-feed`, reads T3 over MCP and serves a feed; the app relays it to the pet's
WKWebView page (`Resources/Pet/*.js`). `CLAUDE.md` is a link to this file.

## Read first

1. `docs/pet-status-spec.md`: the owner's decisions and the pet's canon (its opening list and the
   standing rule on `!` approvals). Canon wins over any other text.
2. `DESIGN.md` before any visible change; it is the latest word on how things look and move.
   `PRODUCT.md` says what the app is for.
3. `docs/pet-hud-design-proposal.md` is history. Build nothing from it. A full-desktop environment
   phase is planned; it gets its own written decisions, and until they exist there is no
   environment.

The shipped feed contract is `Sources/ModelWidgetCore/Feed/FeedSchema.swift`, not the spec's
examples.

## Verify

| Command | Runs | Time (warm) |
|---|---|---|
| `scripts/verify.sh` | plist lint, AGENTS.md map, publish-scan drill, `swift build`, Swift checks, Node pet tests | about 10 s |
| `scripts/verify.sh NAME` | only checks and tests whose name contains NAME (plain text, any case); fails if none does | less |
| `scripts/verify.sh --full` | the above plus the T3 restart drill against a fake T3 | about 2 min |

`--full` must be green before a merge. Each stage prints its time and exit code. Nothing here
covers the rendered page, the WKWebView host, packaging or the LaunchAgent: check a visible change
with a screenshot, and run `scripts/package_app.sh` before judging a change in the app, because
`run_widget.sh` reuses whatever bundle exists.

## Map

The feed, in the order data flows:

| Step | File | Owns |
|---|---|---|
| Read T3 | `Sources/ModelWidgetCore/T3ThreadSource.swift`, `T3MCP.swift`, `Feed/T3ServerIdentity.swift` | MCP calls, OAuth token, thread → orb mapping, restart detection |
| Read Grok Bot | `GrokRosterReader.swift` | Grok Bot agents as orbs |
| Poll | `Feed/FeedEngine.swift`, `Feed/CallBucket.swift` | poll cadence, per-source deadline, the 3 calls/s cap |
| Reconcile | `Feed/FeedWorld.swift` | the authoritative state, lifecycle events, "unknown is not finished" |
| Wire shape | `Feed/FeedSchema.swift`, `OrbitSnapshot.swift`, `Feed/FeedFlags.swift` | state and event JSON, feature flags |
| Serve | `Feed/FeedServer.swift`, `Feed/FeedDiscovery.swift`, `Sources/T3boiiFeed/main.swift` | loopback SSE, `feed.json`, the helper's options |
| Relay | `Sources/LocalModelWidget/FeedSupervisor.swift`, `FeedClient.swift`, `Feed/FeedStream.swift` | running the helper, in-app fallback polling, 100 ms batches |
| Host | `Sources/LocalModelWidget/PetLayer.swift`, `Sources/LocalModelWidgetPanel/PetLayerGeometry.swift` | the pet window, click-through, the JS bridge |
| Page | `Resources/Pet/feed.js` | turning events and state into orbit updates; swallow only on `finished` |
| | `orbit.js` | orbs, rings, marks, eggs, labels, hit regions (DOM canvases) |
| | `effects.js` | lit 3D effects: glints, marks, seeds, rings |
| | `pet.js`, `mood.js`, `motion.js`, `skinning.js`, `sounds.js`, `demo.js` | the rig, frame loop, moods, motion primitives, sound, demo |

Cards: `Sources/ModelWidgetCore` reads (`LocalModelSession`, `SubscriptionUsage`, `TokenUsage`,
`SystemProcessSampler`), `Sources/LocalModelWidgetPanel` lays out, `Sources/LocalModelWidget` shows
(`*Runtime.swift` polls, `*View.swift` draws). Checks live in `Tests/ModelWidgetChecks` (one file
per area, registered in `main.swift`) and `Tests/Pet`.

## Publish

`scripts/publish.sh` (`--dry-run` to preview) is the only way anything reaches GitHub. Its privacy
scan is drilled by `scripts/publish_check_drill.sh`, which verify runs.

## Rules and what enforces them

When the owner corrects you, fix the mistake and add its rule here. If the rule was already
here and nothing enforces it, that is a repeat: enforce it in the same change. Drop a rule
once its mistake can't happen.

| Rule | Enforced by |
|---|---|
| This checkout's history is private. Publish only with `scripts/publish.sh`, which squashes `main`'s tree onto `origin/main` as one noreply-authored commit. Never push `main` or force-push to `origin`. | `.githooks/pre-push` runs `scripts/publish.sh --check`: it refuses a history rewrite, any non-noreply identity, and private terms. Needs `git config core.hooksPath .githooks` in each clone. |
| Demo and test data use generic names (`demo-app`, `docs-site`, `/Users/tester`), never the owner's real projects, paths, emails or hostnames. | The same scan, at publish time: home path, user name, hostnames, local git email, and `~/Projects` folder names the public tree doesn't already mention. |
| Anything that shakes, shivers, shudders or purrs uses `tremble(t, rate)` from `Resources/Pet/motion.js`. | `PetMotionChecks`: fails any raw `Math.sin(t * N)` faster than `TREMBLE_MAX_RATE` in the pet scripts; `Tests/Pet/motion.test.mjs` holds `tremble` to its cap. |
| A sway whose pace changes (with power, sleep, mood) keeps its own phase and advances it by `dt`. Never `Math.sin(t * TAU / (…))`: on a clock hours old, a pace change sweeps it through dozens of cycles, a buzz. | `PetMotionChecks`: fails a sine or cosine of the clock over a parenthesised period in the pet scripts. |
| Orbit laps and orb breaths whose rate can change advance a `Phase` (`motion.js`) by `dt`; never `speed * t`, and no CSS keyframes on `[data-pace]`. | `PetMotionChecks`: "advance a Phase, never the clock times that rate" and "Orb breaths come from orbit.js"; `Tests/Pet/motion.test.mjs` runs a `Phase` through a rate change six hours in. |
| Everything that comes out of T3boii is 3D and lit like him. No flat vector stickers, speech bubbles or tooltips. | Nothing; judgment. See `DESIGN.md`, Desk Pet. Check it with a screenshot. |
| Unknown is not finished. An orb is swallowed only when T3 says its thread ended, never because T3 was unreachable, slow, restarted or refused the token. A restart's cancellations fade. | `FeedWorldChecks`: "T3 down for 40 s ends nothing", "fades after two readings, never swallowed" and "the resync reading sets the scene without one event"; `scripts/verify.sh --full` runs the helper through a T3 restart, a restart whose first poll misses its deadline, and a token change against a fake T3; `Tests/Pet/feed.test.mjs`: the page swallows only after a `finished` event. |
| A `!` approval belongs to the thread's own bot to decide. Only spending, publishing, sending, or destructive or irreversible actions go to the owner. | Nothing; judgment. See `docs/pet-status-spec.md`, "Who answers". |
| Do exactly what was asked. A demo uses only animations that already exist. | Nothing; judgment. |
