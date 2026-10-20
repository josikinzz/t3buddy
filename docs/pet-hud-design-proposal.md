# T3boii as a diegetic HUD: design proposal

Status: proposal, October 16 2026, kept as history. `docs/pet-status-spec.md` superseded its environment, and parts of its orb language were decided differently there; do not build from this document.

## 0. The short version

T3boii already handles the story of a single thread well. Orbs spawn from his forehead, he swallows finished threads, holds out a thread that needs you, frowns at a failed one and cries at a limit. Nothing in the scene tells the story of the fleet or of your quota. You can't see whether the whole machine is healthy or straining, how much Claude, Codex or Kimi you have left, whether anything is talking to anything else, or whether the data is even live. Those are the gaps worth closing, in this order:

1. **A world around him.** A small floating island under him, and a soft sky that fades to nothing at its edge (never a box). The real clock sets its light. Its **weather is the health of your fleet**, not the weather outside: fog means T3 is unreachable, a storm means a provider limit, drizzle and lightning mean recent failures, frost means something has waited on you too long, overcast means quota pressure, wind means throughput, and a clear sky means all is well.
2. **Lanterns as quota meters.** One candle lantern per provider that has a quota. Wax height is the weekly window remaining, the flame is the 5-hour window remaining, and the flicker is the live burn rate. At a limit the flame goes out, at the same moment he starts to cry. When the window resets he relights it with a spark from his forehead.
3. **Mood as one continuous model.** The weather and his face are driven by three smoothed drives: load, health and energy. The scene then always agrees with itself.
4. **A second pass on the orb language.** Each provider gets a rim colour. The orb shows what kind of work the thread is doing (thinking swirls, a file change ripples, a search pings, compaction squeezes the orb). Comets carry messages: from you they come out of the screen, from another thread they arc from its orb, from a bot they fall from the sky.
5. **Server asks.** T3 is already event-sourced. One read-only event cursor, plus the sender recorded on each message, would remove most of the polling and guesswork.
6. **A pet-model contract** (a manifest with semantic bones, sockets, morphs and capabilities), so models after T3boii plug in without forking the behaviour code.

**Recommended Phase 1: the world layer.** That is the island, time of day, the weather state machine and the provider lanterns, plus the mood drives behind them. Every input already exists in the Swift app, so it needs no change to T3, and it fills the biggest "watch it and know" gap. Details are in §9.

---

## 1. What exists today (audit)

### 1.1 Data path

- **Transport:** MCP Streamable HTTP, polled. Each call is a `POST http://127.0.0.1:3773/mcp`; there is no websocket. Auth is headless OAuth with PKCE, using a pairing code minted with `t3 auth pairing create --scope orchestration:read`. The token lives at `~/Library/Application Support/LocalModelWidget/t3-mcp-token.json` (mode 0600). See `Sources/ModelWidgetCore/T3ThreadSource.swift:95-252` and `T3TokenFile.swift`.
- **Cadence:** a poll every **5 s** (`OrbitRuntime.swift`). Each source has a 4.5 s deadline. An orb leaves only after it has been missing from 2 polls in a row. A source that times out keeps its last orbs for 6 s. There is no backoff: an error empties the orbit and logs once.
- **Calls per poll:**
  - `t3_project_list`
  - `t3_thread_list` per project, twice: once for the active statuses and once for 15 recent terminal threads, with `includeSubagents`
  - up to 24 incremental `t3_thread_read(view: activity, maxCharsPerItem: 160)`, plus failure and subagent tail reads
  - `t3_pending_request_list`, only when `pendingRequestCount > 0`
  - `orchestrator_capabilities` and `t3_environment_read`, every 10 min
- **Fields actually used:** `threadId`, `title`, `status`, `providerInstanceId`, `parentThreadId`, `relationshipToParent`, `creationSource`, `itemCount` and `updatedAt`, plus each activity item's type, status, title and text.
  - These are fetched but **unused**: `model`, `settled`, `snoozed`, `createdBy`, `latestRunId`, `branch`, `worktreePath` and `linkedPullRequest`.
- **Status mapping:** `preparing`, `queued`, `starting`, `running` and `waiting` become an active orb. That orb is `waiting` if a request is pending: "?" for a question, otherwise "!" for an approval. `failed` becomes a failed orb for 60 s. Every other status (`completed`, `idle`, `interrupted`, `cancelled`, `rolled_back`) makes no orb, so the orb is swallowed. See `T3MCP.swift:114-128`.
- **Workarounds already in the code:**
  - T3 lists provider-native subagents as `idle`, so their state comes from the parent's `subagent` timeline items.
  - A delegated task appears twice, so it is de-duplicated.
  - Rate limits are found with a regex over error text (`ProviderLimits.swift`).
  - Approvals can't be listed, so the approval count is the pending count minus the questions.
- **Bridge:** `window.t3boii.update({orbs, limits})`, sent only when the snapshot changes. Each orb carries `id`, `parentId`, `source` (t3 or grok), `projectIcon`, `provider`, `state`, `waitingFor`, `label`, `link`, `activity` (≤44 characters), `activeAt`, `limited` and `limitProvider`. See `OrbitSnapshot.swift`.
- **Other sources:**
  - Grok Bot's roster, read from its local persistence.
  - Token usage from Claude, Codex and Kimi logs (every 60 s, hourly buckets).
  - Subscription windows from the provider APIs (every 300 s): Claude's 5-hour, weekly, Opus, Sonnet and Fable windows; Codex's 5-hour and weekly; Kimi's 5-hour, weekly and monthly.
  - Local models (every 3 s), and memory and processes (every 3 s).
  - **None of the usage or quota data reaches the pet.** It only feeds the SwiftUI cards.

### 1.2 Renderer and rig

- **Renderer:** three.js r186 in a transparent WKWebView canvas, 900×980 CSS px. MSAA, ACES tone mapping, `low-power` GPU preference.
  - There are no shadows and no post-processing; glow comes from shader patches and additive sprites.
  - Five lights: hemisphere, warm key, violet rim, blue rim and front fill. The **camera never moves**.
- **Orbs are DOM elements, not 3D.** CSS spheres sit in a front layer and a back layer, each with a full-viewport 2D canvas for the energy lines, and those canvases redraw every rendered frame. This is the largest cost on the orbit side.
- **T3-rigged.glb** (12.5 MB):
  - `T3_Body_Face`: about 62.8k tris, morphs `Mouth_Open` and `Smile`.
  - `Lid_L` and `Lid_R`: 2k tris each, with blink morphs at 25, 50, 75 and 100%.
  - Three 2048² JPEG textures (base, ORM and normal), about 64 MB on the GPU with mips.
  - One skin of 47 joints (`Bone_000…042`, `ShoulderBlend_L/R`, `Eye_L/R`). The bones have generic names: their roles were inferred from position and from how `pet.js` uses them.
  - **No animation clips at all.** Every motion is procedural (`pose()`, `pet.js:1231-1451`).
  - Bones with no driver, free for secondary motion: the top-of-head chain `Bone_028→025`, the belly helpers `Bone_002/015/016`, and the side helpers `Bone_030/029/032/031`.
  - There are no hand or mouth sockets. The forehead, mouth and cheek anchors are found by raycasting at load time.
- **Behaviour:** layered scalar blends plus one-shot `act` slots. There is no formal state machine.
  - Layers: power, load, psychic spawn, swallow, dance, sleep, fidgets, petting, drag and ragdoll, spin and dizzy, hold, upset, cry, workload, chatter.
  - Gaze has a 15-level priority list.
  - Easing comes from `smooth`, `approach`, cubic curves and `easeOutBack`.
  - Bob and breath already advance by phase (the repo's buzz rule); `tremble()` caps shakes at 40 rad/s.
- **Frame rate:** 60 fps while lively, otherwise 30. Rendering pauses when hidden, occluded or the screen sleeps.
  - **Catch:** idle frames are skipped *inside* the rAF callback, so the callback still wakes at display rate (up to 120 Hz on ProMotion) just to decide not to draw.
- **Reduce Motion:** handled thoroughly already, with amplitudes ×0.25, fades instead of flights, and no particles.
- **Environment:** none. The background is transparent, and "time of day" only changes exposure, sleepiness and lid droop.

### 1.3 Constraints any design must respect

- **Frame:** `DESIGN.md` says he floats freely, with no box, card, frame or window edge. A background has to be an object or an atmosphere that fades to nothing, never a rectangle.
- **Style:** everything is 3D and lit like him. No flat stickers, speech bubbles or tooltips.
- **Purpose:** `PRODUCT.md` says calm, glanceable, and easy to ignore until needed. Weather has to stay quiet.
- **Motion rules (`CLAUDE.md`):** shakes go through `tremble()`, and a sway whose pace varies keeps its own phase. Both apply to every new weather, flame and orb motion.
- **Scale:** this machine routinely runs 7 or more threads at once in one project, and one project has over 1,500 threads in total. The orbit has to degrade gracefully past about 20 orbs, which is already "the most he can hold".

---

## 2. Signal catalogue: what T3 exposes

Sources: the T3 MCP tools, called read-only during this audit, and the server's own state. I opened `~/.t3/userdata/statev2.sqlite` read-only, only to list which events and item types exist. **The widget must never read that database.** It is private, its schema changes, and one count query took over 2 minutes.

T3 is event-sourced. Selected event types and their counts: `thread.message-sent` (15.9k), `context-transfer.created` (1.6k), `thread.pull-request-synced` (2.3k), `thread.visited` (8.7k), `thread.settled` (1.5k), `thread.pinned` and `thread.snoozed`, `plan.updated`, `checkpoint.captured`, `thread.turn-diff-completed`, `runtime-request.updated`, `thread.provider-switched`, `thread.model-selection-updated`. Timeline item types, by count:

- **Common:** `command_execution` 130k, `reasoning` 65k, `assistant_message` 35k, `dynamic_tool` 21k, `user_message` 5.7k, `file_change` 4.0k, `checkpoint` 3.9k.
- **Less common:** `notification` 2.1k, `subagent` 2.0k, `web_search` 1.3k, `compaction` 376, `error` 289, `todo_list` 162, `run_interrupt_request` / `run_interrupt_result`.
- **Rare:** `user_input_request` 52, `handoff` 20, `approval_request` 17, `file_search`, `secret_request`, `proposed_plan`.

**Detectable today?** ✅ means via MCP, cheaply. 🟡 means partial, expensive, or inferred. ❌ means not exposed. **Widget** means the widget already uses it.

| Signal | Today | How | Widget | What the server could add |
|---|---|---|---|---|
| Thread run status (all 11 values) | ✅ | `t3_thread_list` `status`; `t3_thread_read` `recentRuns[].status` with requested, started and completed times | Active set plus failed | Provider-native subagent threads report `idle`; report their real status |
| Settled / settledAt | ✅ | `t3_thread_list` | ❌ | — |
| Archived | 🟡 | `t3_thread_read.archived`; archived threads seem to drop out of the list | ❌ | `archived` in the list, or an event |
| Snoozed / snoozedUntil | ✅ | `t3_thread_list`; `snoozed:true` filter | ❌ | — |
| Pinned | ❌ | `thread.pinned` events exist server-side only | ❌ | `pinned` in the list |
| Unread / visited | ❌ | `thread.visited` events, `mark_unread` organise action | ❌ | `unread` and `lastVisitedAt` in the list |
| Provider and model per thread | ✅ | `providerInstanceId` and `model` in the list; driver kind and display name via `orchestrator_capabilities` (9 instances: codex, claudeAgent, cursor, grok, opencode, antigravity, kimi, muse, pi) | Provider only | — |
| Provider switch mid-thread | 🟡 | `recentRuns[].providerInstanceId` differs between runs | ❌ | Event via a cursor (§8) |
| Provider installed or disabled | ✅ | `orchestrator_capabilities.providers[].constraints` | ❌ | — |
| Runtime / interaction mode (plan mode) | ✅ | List fields | ❌ | — |
| Parent → child, delegated or native | ✅ | `parentThreadId`, `relationshipToParent:"subagent"`, `creationSource` (provider means native, mcp means delegated); `subagent` items in the parent | ✅ | Real status for native children |
| Workflows (Claude multi-agent) | 🟡 | A workflow coordinator appears as a `subagent` item (`t3_workflow_stop` takes its `subagentId`) | As a subagent | `kind: workflow`, phase n of m, agent count |
| Thread → thread message (`t3_thread_send`) | 🟡 | `user_message` with `createdBy:"agent"`, `creationSource:"mcp"`, `messageId` = `message:mcp:client%3A<clientId>:thread-send:<clientRequestId>`. Only the MCP **client id** is recorded, not the sending thread | ❌ | `sender {kind: user\|thread\|mcpClient\|scheduler\|webhook, threadId?, clientName?}` on every user message |
| Messages from outside MCP callers (Grok bots, scripts) | 🟡 | Same shape as above; the client id could be resolved to its OAuth `client_name` server-side, but not by us | ❌ | Same `sender` field |
| Messages from you | ✅ | `user_message` with `createdBy:"user"`, `creationSource:"web"` | ❌ | — |
| Forks | ❌ | `t3_thread_fork` exists, but no `forkedFrom` field was seen in list or read | ❌ | `forkedFromThreadId` / `forkPoint` |
| Merge-backs and context transfers | 🟡 | `t3_thread_transfers(threadId)`, one call per thread; `handoff` items | ❌ | Events via a cursor |
| Queued messages | 🟡 | `t3_queue_list(threadId)`, one call per thread | ❌ | `queuedCount` in the list |
| Pending user questions | ✅ | `pendingRequestCount` + `t3_pending_request_list` | ✅ | — |
| Approval requests | 🟡 | Inferred as count minus questions; `approval_request` items | Inferred "!" | List approvals too, with a `kind` for each request |
| Secret requests | 🟡 | `secret_request` items | ❌ | Same `kind` |
| Proposed plan awaiting approval | 🟡 | `proposed_plan` items, plan interaction mode | ❌ | Same `kind` |
| Worktree and branch | ✅ | `t3_thread_read` `branch` and `worktreePath`; `t3_worktree_list` | ❌ | In the list, to save reads |
| Linked PRs | 🟡 | `linkedPullRequest` in the list; `list_thread_pull_requests` gives host state and stack chains. Not seen live: there are no linked PRs on this machine | ❌ | Check summary (pending, passing, failing, conflict) in the list |
| CI check state | 🟡 | The server knows it (`watch_pull_request` wakes on check failures, and `thread.pull-request-synced` events exist); whether the read tools return it is unverified | ❌ | As above |
| Preview tabs and devices | 🟡 | `t3_preview_list` and `device_list` are scoped to the *calling* thread; the widget isn't a thread | ❌ | Per-thread `previewOpen` |
| Scheduled tasks | ✅ | `list_scheduled_tasks` (every project when called from outside a thread): `nextRunAt`, `lastRunStatus`, `enabled`, `schedule.type`. 7 exist | ❌ | — |
| Activity item type and status | ✅ | Incremental `t3_thread_read(view: activity)` | Activity phrase only | — |
| Activity rate (pulse) | ✅ | `itemCount` delta between polls | Only via `activeAt` | — |
| Compaction | ✅ | `compaction` items | ❌ | Context fill %, so the orb's fullness could show it |
| Todo progress | 🟡 | `todo_list` items (payload shape unverified) | ❌ | `todo {done, total}` |
| Diffs and checkpoints | 🟡 | `checkpoint` items; `thread.turn-diff-completed` events | ❌ | Lines changed per turn |
| Rate limits | 🟡 | Regex over `error` item text, e.g. Kimi's "403 You've reached your weekly (7-day) usage limit" | ✅ | Typed failure: `{reason: rateLimit, provider, window, resetsAt}` |
| Token usage | ❌ via MCP | The widget scans local logs. T3 runs **its own** scanner (`usage-scan-cache-v5.json`, sources claude, codex, grok and pi; `usage-model-rates.json`) | Cards only | `t3_usage_read`: tokens and cost per provider and model per hour |
| Quota windows (5-hour, weekly, monthly) | ❌ via MCP | The widget calls the provider APIs itself | Cards only | Fold into `t3_usage_read` |
| Timestamps | ✅ | Thread created and updated, run requested, started and completed, item updated, settledAt, snoozedUntil | Partly | — |
| Server reachability and version | ✅ | Request failures; `t3_environment_read` | Silently empty | — |
| Your presence | ✅ off MCP | macOS idle time (Swift already samples it for `IdleAppHider`) | ❌ | — |
| Grok Bot agents | ✅ off MCP | Grok Bot's persistence: roster, `awaitingUserResponse`, `inflightCount` | ✅ | — |
| Local models, memory pressure | ✅ off MCP | Bonsai, Magnitude and Ollama HTTP; Mach VM stats | Cards only | — |

---

## 3. Design principles for the HUD

1. **Three glance distances.** From across the room, light and weather tell you whether things are fine. From a glance at the screen, his pose and the orbit tell you who is working and whether anyone needs you. Hover and look, and an orb's trail and micro-motion tell you what that thread is doing.
2. **One meaning per channel.** No channel carries two meanings.
   - **Hue:** provider (orb rim, comet, candle flame).
   - **Material and placement:** thread state (glass that is clear, cracked red, frosted or held).
   - **Motion rhythm:** activity.
   - **Weather:** fleet health.
   - **Key light:** time of day.
   - **Props:** quota.
   - Reserved hues that no provider may use: **amber** means needs you, **red** means failed, **violet** is T3boii himself (his T3 sigil and psychic light), and **green** means success. Colour is never the only signal: each state also has a pose, a position or a glyph.
3. **Events are moments, states are places.** A failure, a message or a completion is a short animation (one beat). A lasting condition becomes a position, a material or a weather state that stays until it changes. A watcher who missed a moment can still read the state.
4. **Calm by default.** At most one strong animation at a time, ranked by priority. Weather intensity is capped. Nothing loops faster than a breath unless it is a tremble.
5. **The pet reacts; the world reports.** The world carries the information. T3boii's body adds emotion on top. Neither contradicts the other, because both read the same mood drives (§4.8).

---

## 4. Visual language

### 4.1 The world: island, atmosphere and time of day

**Recommendation:** a small floating island that he hovers above. It is mossy rock with a thin rim of soft grass, about 1.4× his width, sits about 0.25 body heights below his feet, and is lit like he is. Behind him is an **atmosphere disc**, a camera-facing spherical gradient whose opacity falls from about 0.35 at the centre to 0 well inside the canvas, so no edge ever shows. Weather lives inside that volume.

- **Why an island:**
  - It gives the props (lanterns, embers, plant) somewhere to sit without floating stickers.
  - It gives weather a surface to land on: wet sheen, frost, snow dust.
  - It grounds him without a box.
  - It reads as a terrarium, the "virtual pet you watch".
- **Hit testing:** the island is click-through. Only the lanterns take hover. Hovering one brightens it, he glances at it, and you hear a soft sound. Clicking a lantern opens the Subscription card.
- **"World: Full / Minimal / Off"** in the gear menu:
  - Minimal drops the island and atmosphere and hangs the lanterns from a thin ring below him.
  - Off is today's look.
- **Time of day (the real clock):**
  - The key light swings from east to west through the day.
  - Colour temperature runs from about 2,700 K at dawn and dusk to 5,500 K at noon, then to cool moonlight at night.
  - The atmosphere tint goes pale gold in the morning, clear at noon, rose and amber at sunset, and indigo at night.
  - At night a few dim stars sit in the atmosphere, with the moon in its real phase (computed locally and cheaply).
  - Today's drowsiness and lid droop at night stay as they are.
  - Light changes are lerped over minutes, never stepped.

### 4.2 Weather: the fleet's health

The weather is a **state machine with one dominant condition and up to two modifiers**, re-evaluated every poll. Each condition has a minimum dwell of 30 s, so it never flickers, and a 6 to 12 s crossfade, with every rate phase-advanced.

| Priority | Condition | Driven by | Weather | Clears when |
|---|---|---|---|---|
| 1 | **Blind** | T3 unreachable, or the snapshot is stale for more than 20 s (the source failing, a 401, the token expiring) | Fog rolls in and everything desaturates. He squints into it, his gaze searching | The data flows again (the fog lifts over 4 s) |
| 2 | **Storm** | Any provider limit active (`limits[]`) | Dark low cloud over the island and heavy rain; that provider's lantern is out. He cries (the existing behaviour) | The limit clears. A **rainbow** arcs for 8 s, and the lantern relights |
| 3 | **Drizzle** | Failed threads not yet seen, or failures in the last 10 min | Light rain, with intensity set by the count (1, 2 to 3, 4+). **Each new failure gives one lightning flicker inside the cloud** (no full-canvas flash) | You have seen all failed orbs, plus 2 min |
| 4 | **Frost** | A thread has waited on you for more than 5 min | Frost creeps in from the island's rim, growing with the wait (5, 10 and 20 min steps); a few slow snowflakes fall after 10 min. The held orb itself frosts over | The thread is answered (the frost melts into drips) |
| 5 | **Overcast** | Quota pressure: any 5-hour window above 80% or weekly above 90% | Thin high haze, and the key light cools and softens | Usage falls back, or the window resets |
| mod | **Wind** | Aggregate throughput: activity items per minute across all threads, smoothed over 60 s | Motes and grass streaming; wind strength is the throughput. It never gusts faster than the phase rule allows | — |
| mod | **Fireflies** | Night and at least 1 agent working | 6 to 24 fireflies, by agent count, drifting near the orbs | — |
| mod | **Heat shimmer** | macOS memory pressure is high (data the Process card already has) | A faint refraction shimmer above the island | — |
| 6 | **Clear** | Nothing above | A calm, clear sky for the time of day | — |
| event | **Sunbreak** | The last agent finishes after a run of 3 or more | A shaft of light on the island during the existing all-done dance | After 6 s |

**Real local weather is deliberately left out.** The window sits on a desktop that already has a real window and a weather app. Weather that means *your agents* is the point of a diegetic HUD.

### 4.3 Orbits

**Layout:** keep the halo rings, and make radius and order mean something.

- **Ring 0 is "hot"**: threads with activity in the last 20 s. Outer rings are quieter, and stale threads drift beyond, as they already do. A thread moves between rings with a 1.2 s eased transfer. Each ring keeps a constant angular speed; an orb changes ring by retargeting its radius, never its speed, because of the buzz rule.
- **Project constellations:** orbs from the same project sit next to each other on their ring, joined by a faint filament of light (the thread colour at 15%), so a burst of one project's work reads as one group.
- **Cap at 20 orbs**, his existing "most he can hold". Above that, the lowest-priority orbs of the largest project fuse into a **cluster orb**: a lumpy glass grape whose lumpiness grows with the number fused, with no numeral, as the design rules already say. Priority, highest first: needs you, failed, hot, quiet, stale. Hovering the cluster fans it out.
- **Size:** the base size stays as it is. A thread with satellites is 8% larger. The model makes the glass a little denser (opus-class and sol-class models get a slightly heavier glass look), but never changes the size by more than 5%.

**Provider rim colour.** A thin 3D rim light on each orb, and the same colour on its comets and its lantern flame. The logo badge stays, so colour is never the only cue.

| Provider | Rim | Notes |
|---|---|---|
| claudeAgent | `#D97757` terracotta | Matches the Claude logo and the Tokens card |
| codex | `#0A84FF` system blue | Matches the dashboard |
| kimi | `#40C8E0` system teal | Matches the dashboard |
| antigravity | `#FF6FB1` rose | Keeps clear of T3's violet and the amber "needs you" |
| opencode | `#C9CED6` silver | No hue |
| grok, grokBot | `#F5F5F7` white rim on black glass | Monochrome, matching the brand |
| cursor, pi, muse, generic | `#8E8E93` graphite | — |

Claude's terracotta sits near amber. "Needs you" still reads, because a waiting orb is always **held in his hands, pulsing, with a glyph**, never just tinted.

**Activity micro-motion.** This is the orb's "body language" for the newest item type, taken from the incremental activity reads the widget already makes:

| Item | Orb behaviour |
|---|---|
| `reasoning` | A slow nebula swirl inside the glass (with a phase-advanced rate) |
| `command_execution`, running | A tiny spark ticking around the rim; a failed command gives one dull flicker (not red, since it isn't fatal) |
| `file_change` | An ink-drop ripple across the surface |
| `web_search`, `file_search` | One soft sonar ring expanding outward |
| `assistant_message` | A gentle flare; the trail text updates (as now) |
| `dynamic_tool` (MCP tools) | A small spark at the rim |
| `compaction` | The orb squeezes to 85% with an inward ring, then springs back ("context squeeze") |
| `todo_list` | Up to 8 tiny lit beads around its equator showing done out of total (needs the payload checked) |
| `checkpoint` | A faint notch of light left on the ring path, which fades over 30 s |
| Non-fatal `error` | One red spark that dies at once |

**Breathing rate** comes from the activity rate (the `itemCount` delta per poll) instead of only `activeAt`. Busy breathes fast, quiet breathes slow, and stale dims and drifts, as now.

### 4.4 Lifecycle: status by status

| Status or event | Visual |
|---|---|
| `preparing`, `queued`, `starting` | The orb kindles in his T3 as today but **waits at his forehead as a dim, unlit bead** until it is running. Waiting for a worktree or queue reads as "about to" |
| `running` | Normal orb, on the ring its recency puts it on |
| `waiting`, run held open for children | Normal orb (the existing hold logic) |
| Waiting on you (question, approval, secret, plan) | Held in his hands (existing). Glyph: `?` question, `!` approval, a small 3D key for a secret, `!` for a plan. **Escalation:** from 2 min he looks at you more and holds it out further toward the camera; from 5 min the orb frosts and the island frost starts (§4.2) |
| `completed` | The orb **ripens**: one 400 ms clear-gold shimmer. Then he swallows it as today, after it has been missing for 2 polls. The swallowed result becomes **warm light in his belly** (below) |
| Settled or visited | The belly light for that thread is absorbed with a small contented exhale |
| `interrupted` (you stopped it) | No swallow. The orb deflates a little, he lowers it with a small shrug, and it fades. It was not food and it was not a failure |
| `cancelled` | It fades into a puff of grey motes where it is |
| `rolled_back` | The orb **rewinds**: it retraces its trail backwards (the trail text unwinds), then pops softly |
| `failed` | Existing behaviour (flinch, red glass, frown until seen), plus a lightning flicker and a drizzle step in the weather |
| Rate-limited | Existing behaviour (he cries, the orb is eaten by embers), plus a storm, and that provider's lantern goes out |
| Snoozed while active | The orb parks on the island, dim, breathing slowly; it rises and rejoins when `snoozedUntil` passes |
| Pinned (needs the server) | Rides slot 0 at the top of ring 0, with a fine star glint |
| Archived | Same as settled |
| Forked (needs the server) | **Budding:** a daughter orb pinches off the parent, using the existing spawn spring |
| Provider switched (needs the server) | The rim colour sweeps around the orb from the old colour to the new one over 1 s |

**Belly glow as an unread indicator.** His belly holds a soft inner light whose size is the number of completed threads you haven't visited, in the colours of their providers, mixed. It needs `unread` or `lastVisitedAt` from T3. Until then, each glow fades over 10 min. It answers "did anything finish while I was away?" from across the room, and it costs no orb space.

### 4.5 Traffic: comets and beams

A comet has a small glossy 3D bead as its head (lit like him) and a tail of additive motes in the sender's colour. Flight time is 0.9 to 1.6 s along an arc, and it ends in a ripple on the receiver. At most 3 are in flight at once; bursts merge into a thicker comet.

| Traffic | Detectable | Path |
|---|---|---|
| **You → thread** (`createdBy:user`) | ✅ | It comes **out of the screen**: a soft pulse travels from the camera into the orb, getting smaller as it goes, then ripples. Diegetically, you poked it |
| **Parent → subagent** (spawn) | ✅ | Existing satellite spawn, plus a thin bright tether for 0.6 s |
| **Subagent → parent** (result) | ✅ | The satellite flies home (existing) and the parent flares once as it "receives" |
| **Thread → thread** (`t3_thread_send`, handoff) | 🟡 the sender is unknown | Should arc from the sender's orb to the receiver's. **Until T3 records the sender**, render it as "outside" (next row) |
| **Bot or outside client → thread** (MCP client, Grok bots) | 🟡 | It falls **from the sky above the atmosphere**, coloured by the client (a Grok Bot avatar colour where we can match it, otherwise silver) |
| **Scheduler → thread** | 🟡 | It launches from that task's ember on the island (§4.6) |
| **Context transfer / merge-back** | 🟡 one call per thread | A ribbon of motes flows from the source orb to the target orb for 1.5 s, and the target does a mini-gulp |
| **Queued messages** | 🟡 one call per thread | Up to 3 small beads trail the orb like a necklace, and the next is used up when its turn starts. More than 3 shows as one larger bead |

### 4.6 PRs, CI, scheduled tasks, worktrees, previews

- **Linked PR:** a thin Saturn-style band around the orb.
  - Checks pending: a light runs round it.
  - Passing: a steady green glint.
  - Failing: a red cracked segment.
  - Conflict: the band jitters, through `tremble()`.
  - Merged: the band closes into a bright ring that floats up and briefly crowns T3boii, then fades. It is rare and celebratory.
  - This workflow publishes with `scripts/publish.sh` and has **no linked PRs today**, so it is Phase 3.
- **Scheduled tasks:** an **ember stone** on the island rim for each enabled task (up to 6).
  - It glows brighter through the last 5 min before `nextRunAt`.
  - It launches a comet when it fires.
  - It is cracked if its last run failed; disabled tasks are cold grey or hidden.
  - This is detectable today and cheap: one call every 60 s.
- **Worktree:** threads that share a worktree share their constellation filament. The main checkout gets none. Low priority.
- **Preview tab or simulator open:** the orb gains a small glossy lens facet with a blurred screen glow. It needs per-thread scoping on the server. Low priority.
- **Local models (optional delight):** a loaded Bonsai model shows as a literal tiny bonsai on the island, lit, with leaves stirring. Ollama and Magnitude get a small glowing seed stone. Unloading one dims it.

### 4.7 Usage meters

**Criteria:**
- reads at a glance, and its direction is unambiguous;
- shows **two timescales** (5-hour and weekly) at once;
- has a natural **reset ritual**;
- has a small motion cost;
- fits the 3D-lit style;
- scales to 3 or 4 providers.

| Idea | Glance | Direction | 2 timescales | Reset story | Motion cost | Verdict |
|---|---|---|---|---|---|---|
| **Candle** (Josie's) | Good | Unambiguous (it burns down) | Wax plus flame | Relight | Flame flicker only | **Yes, as a lantern** |
| **Plant growing or wilting** (Josie's) | Medium | **Ambiguous**: does growth mean "used more" (good work) or "has more" (quota)? Wilting reads as sadness, not "running low" | Awkward | Regrowing takes too long to read | Low | Use it for *today's work* instead (below) |
| Hourglass | Good | Clear | Upper vs lower bulb | A flip | Sand particles | Suggests time, not usage; it would fall while idle |
| Moon phase | Poor for 3 providers | Clear | Only one | Lunar | None | Already used for the real moon |
| Liquid inside his body | Great | Clear | One | Refill | Low | Overloads his body; already used for power and swell |
| Battery bars | Great | Clear | — | — | — | Not diegetic; that's the card's job |

**Recommendation: provider lanterns.** A small glass lantern on the island for each provider with quota data (Claude, Codex, Kimi; providers without quota APIs get none).

- **Wax height** = the **weekly** window remaining, the slow reserve. When several weekly windows exist (Claude's Opus, Sonnet and Fable weeklies), the most constraining one drives the wax. A thin taper beside it appears only when a model-specific weekly passes 70%.
- **Flame height and brightness** = the **5-hour** window remaining, the burst capacity. Below 15% the flame gutters, as a phase-advanced flicker.
- **Flame liveliness** = the live **burn rate** for that provider, from the token scan in the last 5 min. A calm flame means idle; a dancing flame with rising sparks means heavy use. Wax drips while burning fast.
- **Limit hit:** the flame snuffs out with a curl of smoke, at the moment he starts to cry. A dim ember shows on the wick and grows brighter as `resets_at` approaches.
- **Reset:** he turns, a thin violet spark leaves his T3 (the same psychic light as an orb spawn), and the wick catches. At the weekly reset a fresh candle rises from the lantern's base.
- **Kimi's monthly window:** the lantern glass slowly clouds when it passes 80%.
- **Data:** `SubscriptionUsage` (every 300 s) and `TokenUsage` (every 60 s) already exist. They need sending to the pet in a `world.quotas` block, and token buckets of 1 minute for the last hour (they are hourly now).

**Secondary: a garden for today's work (optional, Phase 3).** One plant on the island grows through the day with total tokens, measured against your 7-day median. It buds at 50% of the median, blooms at 100%, and its flowers are tinted by each provider's share. At local midnight it folds back to a sprout. It **never wilts for quota**; it is the positive "look what got done" meter, which keeps Josie's plant idea where its direction is clear.

### 4.8 The pet: mood, idle and reactions

**Mood drives** are computed each poll and smoothed with time constants of 20 to 120 s. Both the weather and his face read them.

- **Load (arousal):** active count plus throughput.
- **Health (valence):** recent completions, minus recent failures, minus active limits, minus the needs-you wait time.
- **Energy:** time of day, how long since you were last at the machine (macOS idle time), and sleep pressure.

| Load / Health | Body and face (parameters that exist today) |
|---|---|
| High / high: **"in the zone"** | Floats higher, eyes darting over orbs, slight smile, crisp blinks |
| High / low: **strained** | Frown, faster breath, sinks a little, glances at the problem orbs. A small 3D sweat bead at the temple appears only after 2 min |
| Low / high: **content** | Relaxed lids, easy smile, more fidgets |
| Low / low: **glum** | Heavy lids, low gaze, a slow sigh every 40 to 60 s |
| Low energy | Drowsy droop, yawns, then the existing sleep |

**New idle acts**, built from existing bones, procedural, weighted at random with cooldowns, and gated by mood and time:

- **Counting:** his gaze hops from orb to orb with tiny nods.
- **Polishing an orb:** he pulls one in, wipes it with a hand, and lets it go.
- **Tending a lantern:** he cups a hand around a guttering flame.
- **Sitting on the island edge,** legs dangling. This is his nighttime idle.
- **Juggling two satellites** briefly, when content.
- **Peeking at the camera.**

**Reactions:**

| Event | Reaction |
|---|---|
| A comet from you | He looks at the camera, then follows the comet to its orb |
| A comet from outside | He looks up at the sky |
| A lantern relights | A small satisfied nod |
| Fog | He squints and leans forward, searching |
| Frost | He shivers slightly, via `tremble()`, rate 18 |

---

## 5. Signal → visual (master table)

| Signal | Layer | Visual | Phase |
|---|---|---|---|
| T3 unreachable or stale | World | Fog, desaturation; he squints | 1 |
| Provider limit | World + pet + prop | Storm, cry (existing), lantern snuffed, ember countdown, rainbow on clear | 1 |
| Recent or unseen failures | World | Drizzle by count; a lightning flicker per new failure | 1 |
| Needs you for more than 5 min | World + orb | Frost on the island and the held orb; snow after 10 min | 1 |
| Quota pressure | World | Overcast haze, cooler key light | 1 |
| Throughput | World | Wind strength (motes, grass) | 1 |
| Night with agents working | World | Fireflies | 1 |
| Memory pressure | World | Heat shimmer | 1 |
| Time of day, moon | World | Key light angle and temperature, atmosphere tint, stars, real moon phase | 1 |
| 5-hour quota remaining | Prop | Lantern flame height | 1 |
| Weekly quota remaining | Prop | Lantern wax height, plus model tapers | 1 |
| Burn rate | Prop | Flame liveliness, sparks, wax drips | 1 |
| Quota reset | Prop + pet | He relights it with a psychic spark | 1 |
| Load / health / energy | Pet | Mood blend, idle act choice | 1 |
| Thread active / queued / starting | Orb | Ring by recency / dim bead at his forehead | 2 |
| Provider | Orb | Rim colour, comet colour, flame colour (plus the logo, as now) | 2 |
| Model | Orb | Glass density (subtle) | 2 |
| Item type | Orb | Swirl, spark, ripple, ping, flare, squeeze, beads, notch | 2 |
| Activity rate | Orb | Breathing rate | 2 |
| Completed | Orb + pet | Ripens, swallowed (existing), belly light | 2 |
| Unread completions | Pet | Size and colour of the belly light | 2 (exact once T3 exposes unread) |
| Interrupted / cancelled / rolled back | Orb | Deflate and shrug / grey puff / rewind | 2 |
| Needs-you kinds and escalation | Orb + pet | `?` `!` key; held further out, then frost | 2 |
| Message from you / outside / thread | Traffic | Comet out of the screen / from the sky / from the sender's orb | 2 (thread-to-thread once T3 records the sender) |
| Subagent spawn and result | Traffic | Tether / flight home and flare | 2 |
| Queued messages | Orb | Necklace beads | 2 |
| More than 20 orbs | Orbit | Project constellations; cluster orb | 2 |
| Context transfer, merge-back | Traffic | Ribbon of motes, mini-gulp | 3 |
| Scheduled tasks | Prop | Ember stones; launch comet | 3 |
| Linked PR and CI | Orb | Saturn band: running light, glint, crack, crown on merge | 3 |
| Snoozed / pinned / fork / provider switch | Orb | Parked asleep on the island / slot 0 glint / budding / rim sweep | 3–4 |
| Worktree, preview | Orb | Shared filament, lens facet | 4 |
| Today's tokens | Prop | Garden plant | 3 |
| Local model loaded | Prop | Bonsai or seed stone | 3 |

---

## 6. Animation polish plan

### 6.1 Architecture

Split the work into modules under `Resources/Pet/`:

- `world.js`: island, atmosphere, light, weather, props.
- `mood.js`: drives, from the snapshot.
- `behaviour.js`: mode state machine plus act scheduler.
- `traffic.js`: comets.
- `body.js`: the per-model adapter (§7).

`pet.js` becomes composition and the render loop. The behaviour layer emits **intents** (gaze target, expression vector, gesture name and weight, body offsets). Only `body.js` touches bones and morphs.

### 6.2 State machine

A small hierarchical machine replaces today's implicit precedence.

- **Top-level modes:** `Asleep`, `Drowsy`, `Awake`, `Attending` (holding a waiting orb), `Distressed` (crying or limit), `Celebrating` (dance), `Handled` (drag, pet, spin).
- **Rules for modes:**
  - Each mode has entry and exit transitions, a minimum dwell (hysteresis), and an interrupt priority: `Handled` > `Distressed` > `Attending` > `Celebrating` > `Awake` > `Drowsy` > `Asleep`.
  - Inside `Awake`, the act scheduler picks idle acts.
  - The continuous layers (breath, bob, gaze, mood face, secondary motion) run in every mode.

### 6.3 Blending

Today, acts are timers through `smooth()`, so interrupting one mid-way can pop. The fix:

- Make every act and mode weight a **spring-driven parameter**.
  - Critically damped (ζ = 1) to settle.
  - ζ ≈ 0.6 where a gesture should overshoot.
- Make every pose contribution an additive delta multiplied by its weight, which the `add()` and `delta()` pipeline already supports.
- An interrupt retargets the weights instead of cutting them.
- Mode crossfades run 0.3 to 0.8 s.

### 6.4 Easing and timing rules

These go in `DESIGN.md` once adopted.

- **Anticipation:** 80 to 150 ms in the opposite direction before any gesture bigger than 10°.
- **Main action:** ease-out cubic, or `easeOutBack` (c ≈ 1.6) for playful beats.
- **Follow-through:** springs.
- **Moving holds:** no pose freezes. Holds keep 2 to 3% drift from noise.
- **Overlap:** the head lags the body by 60 to 120 ms; the arms lag by 100 to 180 ms (the spring chains already provide this).
- **Eyes:** saccades of 30 to 60 ms, fixations of 200 to 600 ms with micro-saccades, and a blink coupled to large gaze shifts.

### 6.5 Secondary motion with unused bones

- Spring the top-of-head chain `Bone_028→025` as a soft tuft that lags head motion.
- Drive the belly helpers `Bone_002/015/016` with breath and with the landing after a hop.
- Add volume-preserving squash and stretch of the ball body along velocity, ±4%, in the existing vertex patch.
- Make the lantern flames, grass and motes respond to his motion through a shared wind field.

### 6.6 Noise and the buzz rule

- Add `noise1(phase)` (1D simplex) to `motion.js`, plus a `Phase` accumulator helper (`advance(dt, rate)`).
- Idle drift, flame flicker, weather gusts and orb swirls all sample noise at *accumulated* phase, never `t * rate`.
- Extend `PetMotionChecks` to the new files, and flag any `noise1(t * …)`, so the rule stays enforced, per the `CLAUDE.md` practice.

### 6.7 Camera

**Keep it fixed.** He is a screen-fixed desktop object. Moving the camera shifts the whole world inside a frameless window, which feels like sloshing and churns the hit regions. Depth comes from parallax *inside* the scene: weather layers move at different rates with the wind. There is no dolly, no shake, and no mouse parallax.

### 6.8 Performance budget (Apple silicon, WKWebView)

| Mode | fps | JS per frame | GPU per frame | Draw calls | Particles |
|---|---|---|---|---|---|
| Asleep, nothing changing | 12 | ≤ 1 ms | ≤ 1.5 ms | ≤ 25 | Frozen or slow |
| Idle, awake | 24 (from 30) | ≤ 1.5 ms | ≤ 2 ms | ≤ 30 | ≤ 300 |
| Lively (flights, petting, storm onset) | 60 | ≤ 4 ms | ≤ 5 ms | ≤ 90 | ≤ 800 |

- **Schedule idle frames properly.** When not lively, request the next frame with `setTimeout(frameDue)`, then rAF, instead of a rAF that wakes at display rate and returns early.
- **One instanced draw per particle system:**
  - rain ≤ 400 streaks;
  - snow ≤ 250;
  - motes ≤ 150;
  - fireflies ≤ 24;
  - comet tails pooled.
- **Phase 3: move orbs and energy lines into WebGL.**
  - Orbs become instanced glass spheres with icon and logo atlases.
  - Strands become instanced ribbons.
  - Trails stay text, drawn into a small SDF glyph atlas.
  - This removes two viewport-sized 2D canvases repainted every frame. It is also the only way orbs can truly be "lit like him".
- **Textures:** KTX2/Basis, or downscale the normal and ORM maps to 1024². That frees about 40 MB of GPU memory.
- **Power:** Swift passes `isLowPowerModeEnabled` and the thermal state. Under either, cap at 20 fps and halve the particles.
- **Measure:**
  - Add a `?perf` overlay.
  - Reuse the headless-Chrome synthetic-clock harness to simulate 24 h of uptime, and check for buzz and drift. The harness is described in the owner's agent memory notes, not in the repo.

### 6.9 Reduce Motion

Every new system has a still form:

- **Weather** becomes static tableaux: tint, still clouds, static frost, fog without drift, rain shown as a darker sky and a wet sheen, no lightning.
- **Comets** become a brief glow at both ends.
- **Flames** hold still; their height and brightness still encode quota.
- **Orb micro-motion** becomes brightness steps.
- **Idle acts:** only "counting", with gaze only.
- **The mood face** still shows.

---

## 7. Pet-model contract (for swappable pets)

Each pet is a folder `Resources/Pet/models/<id>/` containing `<id>.glb` and a `pet.json`:

```jsonc
{
  "id": "t3boii", "name": "T3boii", "glb": "T3-rigged.glb",
  "scale": 1.0,
  "body": { "center": [0.015, 1.07, 0], "radius": 0.66 },
  "roles": {                       // semantic role -> bone name
    "root": "Bone_000", "pelvis": "Bone_001",
    "spine": ["Bone_014", "Bone_013", "Bone_012"], "head": "Bone_011",
    "armL": ["Bone_041", "Bone_040", "Bone_039", "Bone_038"],
    "armR": ["Bone_036", "Bone_035", "Bone_034", "Bone_033"],
    "legL": ["Bone_010", "Bone_009", "Bone_008", "Bone_007"],
    "legR": ["Bone_006", "Bone_005", "Bone_004", "Bone_003"],
    "eyeL": "Eye_L", "eyeR": "Eye_R",
    "secondary": { "tuft": ["Bone_028", "Bone_027", "Bone_026", "Bone_025"],
                   "belly": ["Bone_002", "Bone_015", "Bone_016"] }
  },
  "sockets": {                     // empty nodes in the GLB, or raycast hints
    "forehead": { "raycast": [0, 1.3, 1] }, "mouth": { "raycast": [0, 0.95, 1] },
    "handL": "Bone_038", "handR": "Bone_033", "belly": { "offset": [0, 0.9, 0.4] },
    "headTop": "Bone_025", "feet": "Bone_000"
  },
  "morphs": {
    "blinkL": ["Blink_L_25", "Blink_L_50", "Blink_L_75", "Blink_L"],
    "blinkR": ["Blink_R_25", "Blink_R_50", "Blink_R_75", "Blink_R"],
    "mouthOpen": "Mouth_Open", "smile": "Smile",
    "frown": null, "pucker": null          // null -> shader fallback or skip
  },
  "emissive": { "sigil": { "vertexBake": "t3Bloom" }, "eyes": "sprite-stencil" },
  "clips": {},                     // optional baked clips by gesture name, see below
  "capabilities": { "hold": true, "dance": true, "cry": true, "lids": true,
                    "sleepPose": "float", "swallow": true },
  "limits": { "shoulder": [-1.1, 1.4], "eyeYaw": 0.35, "eyeRollUnderLid": 0.45 },
  "loadHooks": ["smoothSkinning", "bindLidsToFace", "bakeT3Bloom"],
  "palette": { "psychic": "#8b5cf6" },
  "sfx": "deep-soft"
}
```

**Minimum for a pet to load:**
- the roles `root`, `head`, and either `spine` or `pelvis`;
- the sockets `forehead` (spawn) and `mouth` (swallow), or `capabilities.swallow: false`, in which case finished orbs fade into its aura;
- one blink method: morphs, lid geometry, or `lids: false` with eye-scale blinks.

**Capability fallbacks:**
- No hands means `hold: false`: a waiting orb hovers in front of its face by telekinesis, with its glow tethered to the forehead socket.
- No `cry` means the tear effects are skipped and the face only droops.

**Clips are optional.** If a model ships baked clips, `body.js` plays them through `AnimationMixer` on top of the procedural base, as additive layers, by gesture name. The names are T3boii's acts plus OpenAI's Codex-pet state set, so a model built for one maps to the other:

| Codex pet state | Our intent / gesture |
|---|---|
| `idle` | Awake + idle layers |
| `running` | Load-driven "working" layer |
| `waiting` | `Attending` (hold) |
| `failed` | Upset flinch / `Distressed` |
| `review` | Counting / attentive lean |
| `waving` | Greeting when you return (new: the macOS idle time ends) |
| `jumping` | Hop act |
| `running-left` / `running-right` | Drag tilt (only while handled) |

**Checks:** add a `PetModelChecks` that loads each `pet.json` and checks it against its GLB (bones exist, morph names exist, sockets resolve, the bounds are sane). It runs in `scripts/verify.sh`, so a broken model fails the build instead of the desktop.

**How we differ from Codex pets:** those are 2D sprite atlases (192×208 cells, nine fixed rows) and show one agent's state. T3boii is 3D, procedural and data-driven, and reports the whole fleet. The contract keeps that advantage: a new model brings a body, and every behaviour comes free.

---

## 8. What to ask T3 for, ranked

1. **A read-only event cursor:** `t3_events_since({cursor, types?, projectIds?})`, or an MCP resource subscription. T3 is already event-sourced, so this exposes its events (`thread.*`, `run.*`, `message-sent`, `context-transfer`, `pull-request-synced`, `runtime-request`). It would take latency from 5 s to under 0.5 s, retire most of the 24-reads-per-poll budget and the tail-read heuristics, and make comets exact.
2. **Message provenance:** `sender {kind, threadId?, clientName?}` on every `user_message`, and on `thread.message-sent`. This is what makes real thread-to-thread and bot-to-thread comets possible.
3. **Typed limits and usage:**
   - A terminal failure should carry `reason: rateLimit | capacity | auth | …`, `provider`, `window` and `resetsAt`, which replaces the regex in `ProviderLimits.swift`.
   - Add `t3_usage_read`, reusing T3's own usage scanner (hourly tokens and cost per provider and model) and, ideally, the quota windows.
4. **Thread-list enrichments:** `unread` and `lastVisitedAt`, `pinned`, `archived`, `pendingRequestKinds {question, approval, secret, plan}`, `queuedCount`, `lastItemType`, `branch` and `worktreePath`, a PR check summary, `forkedFromThreadId`, and `contextFill`.
5. **Approvals in `t3_pending_request_list`**, with `kind`.
6. **Real status for provider-native subagent threads**, instead of `idle`.
7. **Workflow progress:** `kind: workflow`, phase n of m, live agent count.
8. **Per-thread token use and context-window fill**, so an orb's fullness could show how close a thread is to compaction.

---

## 9. Phased build plan

### Phase 0: groundwork (small, no visible change)

- **Snapshot v2.** Keep `orbs` and `limits` as they are, and add:
  - **Per orb:** `model`, `pulse` (items per minute), `lastItemType`, `inbound` (the origin of the newest user message: user or mcp), and a `status` detail (`queued`, `starting`, `interrupted`, `cancelled`, `rolled_back` exits).
  - **A `world` block:**
    - `connection {ok, staleSec}`
    - `quotas[] {provider, fiveHour {used, resetsAt}, weekly {used, resetsAt}, extra[]}`
    - `burn[] {provider, tokensPerMin}`
    - `failures {unseen, last10m}`
    - `needsYouSec`, the longest wait
    - `memoryPressure`
    - `userIdleSec`
    - `scheduled[] {id, nextRunAt, lastRunStatus}`, for Phase 3
  - Time and moon phase are computed in JS.
- **Swift:** send `SubscriptionUsage` and `TokenUsage` to the pet; add 1-minute token buckets for the last hour; send low-power and thermal state.
- **Motion:** add `Phase` and `noise1` to `motion.js`, and extend `PetMotionChecks`.
- **Checks:** `OrbitStateChecks` fixtures for the new fields.

### Phase 1 (recommended): the world layer, "weather and lanterns"

- **Scope:**
  - Island and atmosphere disc, plus the World Full / Minimal / Off setting.
  - Time-of-day light: key light angle and temperature, atmosphere tint, stars, moon.
  - The weather state machine: Blind, Storm, Drizzle with lightning flicker, Frost, Overcast, Clear; the Wind, Fireflies and Shimmer modifiers; Sunbreak.
  - Provider lanterns: weekly wax, 5-hour flame, burn liveliness, snuff at a limit, psychic relight.
  - `mood.js` drives feeding his existing face and pose parameters.
  - Reduced-motion still forms, the performance budget and idle scheduling, and a `DESIGN.md` update (Desk Pet: World, Weather, Lanterns).
- **Why this first:**
  - It closes the biggest gap: the fleet, quota and connection stories are invisible today.
  - It needs **no change to T3**; every input is already in the app.
  - It is the most striking change, and the clearest difference from Codex's sprite pets.
  - It leaves the orb code, which recent work has just stabilised, untouched.
- **Acceptance:**
  - Harness screenshots of every weather state and lantern state, by day and by night.
  - A 24 h synthetic-uptime run with no buzz, measured by direction changes per second, as in the October buzz investigation.
  - Idle CPU no higher than today, ≤ 30 draw calls at idle, and 24 fps idle with real `setTimeout` scheduling.
  - Reduce Motion screenshots for each state.
  - `scripts/verify.sh` green.
- **Size:** about 2 weeks of focused work, in four PR-sized steps: world shell and light; weather machine; lanterns; mood.

### Phase 2: orb language v2

Provider rims, item-type micro-motion, pulse-based breathing, forehead beads for queued and starting threads, the completion ripen plus belly light, the interrupted, cancelled and rolled-back exits, needs-you kinds and escalation, comets (from you, from outside, parent and child), queue beads, project constellations and the cluster orb. Start the `behaviour.js` / `body.js` seam here, so that intents and not bones are the interface.

### Phase 3: rendering migration and secondary signals

Orbs and energy lines move into instanced WebGL, textures are compressed, then PR bands, scheduled-task embers, context-transfer ribbons, the garden plant and local-model props.

### Phase 4: server asks land

Swap polling for the event cursor, add true thread-to-thread comets from provenance, exact unread belly light, typed limits, and `t3_usage_read` replacing the provider scraping where possible.

### Phase 5: pet models

`pet.json` and the `PetBody` adapter, T3boii ported as the reference, `PetModelChecks`, a model picker in the gear menu, then a second model to prove the contract.

---

## 10. Open questions for Josie

1. **The island.** It changes his silhouette and needs a `DESIGN.md` amendment ("no box" holds; "free-floating" becomes floating above his own island). Is the Minimal mode (lanterns on a ring, no island) the right fallback?
2. **Weather sounds.** Following the existing rule (only while the mouse rests on him), would a distant rumble with lightning and soft rain be welcome, or should weather stay silent?
3. **Completion.** Should finished threads stay visible longer as "ripe" orbs until you look at them, or is the belly light enough? This proposal keeps the swallow you already like.
4. **Which quota windows count.** Should Claude's Fable weekly count toward the wax, or only show as a taper?
5. **Asking T3.** Are you able to ask the T3 maintainers for the event cursor and message provenance? They unlock most of Phases 2 and 4.
