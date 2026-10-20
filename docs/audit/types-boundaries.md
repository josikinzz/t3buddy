# Types, contracts, and module boundaries audit

Audited 2026-10-20 at `0fa5ef6`. Scope is the feed-to-pet contract, Swift-to-JS bridge, configuration, and representable invalid states. No code, installed app, or `outputs/` changes.

No P0 or P1 is established by this audit. The P2 findings below are ordered by correctness risk, then agent maintenance cost. A malformed-input demonstration is not evidence that the current helper emits that input.

Throughput checkpoint: n/a, read-only investigation.

## Contract map

`T3MCP` parses external tool data. `T3ThreadSource` and `GrokOrbitSource` produce `FeedReading`. `FeedWorld` owns reconciliation and emits typed `FeedChange` values. `FeedServer` serializes them to SSE. `FeedClient` and `FeedRelay` assemble JSON for `PetLayer`, which invokes `window.t3boii.feed`. `feed.js` turns events and state into `orbit.js` snapshots. The reverse bridge reports readiness, hit regions, position, errors, and local links.

The Swift event enum is already a useful discriminated contract. Keep that strength. The gaps occur where its guarantees stop, where observations use unconstrained strings, and where the specification describes different bytes.

## 1. P2. The relay bypasses the typed feed contract and version gate

Evidence:

- `Sources/ModelWidgetCore/Feed/FeedStream.swift:54` accepts raw frame data. Every kind except `state` and `reset` becomes an event. Lines 68-70 concatenate that data into JSON.
- `Sources/LocalModelWidget/FeedClient.swift:105` decodes a state only when adopting a different helper PID. It checks `source == .live`, not `v`. Lines 111-113 advance the resume cursor and relay subsequent frames without decoding them.
- `Sources/ModelWidgetCore/Feed/FeedSchema.swift:226` uses synthesized `Codable` for `FeedState`. Its `v` is mutable at line 229. Setting the initializer's version does not validate decoded versions.
- `Resources/Pet/feed.js:21` checks only that `state.orbs` is an array. Line 29 defaults a missing source to `live`. `Sources/LocalModelWidget/PetLayer.swift:141` passes the assembled JSON as a JavaScript argument.

Why it hurts. An agent can add an enum case or change a state shape and still pass Swift compilation while the page silently interprets incompatible data. Independently running sidecars make version skew a supported topology, not just a theoretical remote client. Invalid frames can advance the resume cursor before the page receives a usable update.

Confirmed check. An in-memory import of the actual `createFeed` accepted `{v:999, seq:1, source:'live', orbs:[], limits:[]}` and called its consumer. No version negotiation occurs there. The existing relay check at `Tests/ModelWidgetChecks/FeedServerChecks.swift:98` even uses an event missing its required `seq`, `at`, and `id`, so that check does not prove the typed wire contract.

Concrete fix. Parse SSE into a typed state-or-event frame at one ingress boundary. Validate the supported version before adoption or cursor advancement. Define an explicit policy for unknown SSE event names and future event variants. Retain the last valid scene on invalid input and expose the rejection. Give JS checked declarations derived from the same schema, with a small runtime parser for browser-only inputs.

Blast radius. `FeedClient`, `FeedRelay`, feed serialization, page reload replay, fallback handoff, and JS fixtures. Preserve event ordering and 100 ms batching. Check unsupported versions, malformed frames, unknown variants, and cursor behavior through the actual relay and page adapter. Do not scatter validation through animation functions.

## 2. P2. The named feed specification describes an incompatible protocol

Evidence:

- `docs/pet-status-spec.md:260` describes versioned events with ISO timestamps, `src`, `confidence`, a nested `data` object, and `thread.started` names.
- `Sources/ModelWidgetCore/Feed/FeedSchema.swift:139` defines flat event keys. Lines 144-148 emit numeric timestamps and `started`. There is no event version, `src`, or `confidence` field.
- `docs/pet-status-spec.md:292` describes an object-valued `source`, project-indexed icons, and orb `life`, `ask`, and `activityText` fields.
- `Sources/ModelWidgetCore/Feed/FeedSchema.swift:232` uses a string-valued source. `Sources/ModelWidgetCore/OrbitSnapshot.swift:34` keeps an icon on each orb and uses `state`, `waitingFor`, `activity`, and `level` instead.
- `Resources/Pet/pet.js:1871` recognizes staleness only when `snapshot.source === 'stale'`.

Why it hurts. An agent building the planned native source or a replacement client from the requested spec gets incompatible names, nesting, and time units. The document's opening says nothing has been built at `docs/pet-status-spec.md:3`, although these components now exist. It does not distinguish historical design from the implemented contract.

Confirmed check. Passing the spec's `{source:{status:'stale', since:'...'}}` through the actual page adapter forwards an object. The shipped consumer's strict comparison with `'stale'` is false. The initial helper-adoption decoder would reject that shape instead, so this check demonstrates incompatibility, not a proven full transport incident.

Concrete fix. Preserve the approved behavior, but designate one current wire reference beside the schema. Mark the plan's examples as historical or link them to that reference. Generate representative event and state examples from Swift and consume them in JS contract checks. Record time units, omitted versus null fields, source status shape, and compatibility rules explicitly. Do not rewrite the implementation to match old examples by default.

Blast radius. Agent onboarding, replay fixtures, future native-stream adapters, `/v1/state` clients, demos, and contract tests. This is a protocol documentation correction, not permission to change canon or add the older proposal's environment.

## 3. P2. Terminal evidence is an arbitrary string, and unknown moon statuses can become finishes

Evidence:

- `Sources/ModelWidgetCore/Feed/FeedSchema.swift:10` represents positive terminal evidence as `[String: String]`. Line 118 allows `.finished(id:status:)` with any string.
- `Sources/ModelWidgetCore/T3MCP.swift:210` recognizes only `pending`, `running`, and `waiting` as active timeline work.
- `Sources/ModelWidgetCore/T3ThreadSource.swift:744` classifies a subagent as ended whenever it is neither active nor failed. An unrecognized status therefore qualifies as an ending.
- `Sources/ModelWidgetCore/Feed/FeedWorld.swift:85` trusts any value in `reading.ended` and emits `.finished`. `Resources/Pet/feed.js:16` accepts the event without examining its status. `Resources/Pet/orbit.js:459` then permits a mouth departure rather than a fade.

Why it hurts. The central "unknown is not finished" guarantee depends on callers remembering which strings count as evidence. A new T3 timeline status can cross the subagent path as positive completion even though this client does not understand it. A native source has the same unsafe construction API.

Repro and limit. In a source trace, change a previously active native subagent's next timeline status to an unrecognized value such as `future_status`. It fails both predicates at line 744 and enters `ended`. The page check also confirmed that `finished(status:'running')` suppresses the normal fade. The Swift source-to-world scenario was traced, not executed. No live unknown-status occurrence was observed.

Concrete fix. Parse known terminal statuses into a closed `TerminalEvidence` type at the T3 boundary. Preserve unknown raw statuses separately and never infer terminal evidence as the complement of active statuses. Give Grok's successful-roster disappearance an explicit evidence case. Let only that validated type construct a finish observation or event.

Blast radius. Thread drop-out probes, timeline parsing, `T3ActivityTracker`, subagent mapping, `FeedReading`, world reconciliation, Grok disappearance, and restart drills. Check known completions, unknown statuses, provider-native `idle` threads, failures, and restart resync separately. Preserve Grok's documented successful-roster exception at `FeedWorld.swift:8`.

## 4. P2. Orb and icon types admit contradictory payloads

Evidence:

- `Sources/ModelWidgetCore/OrbitSnapshot.swift:37` stores `state` separately from optional `waitingFor`. Lines 50-52 store optional `limited` separately from `limitProvider`. The public initializer at line 64 accepts every combination, and all fields remain mutable.
- `Sources/ModelWidgetCore/OrbitSnapshot.swift:93` stores icon `kind`, `src`, and `text` independently. The initializer at line 101 permits an image with no source or a monogram with no text.
- `Sources/ModelWidgetCore/OrbitSnapshot.swift:55` describes a bounded `level`, but represents it as an unconstrained optional `Double`. Queue counts are unconstrained integers at line 61.
- `Sources/ModelWidgetCore/Feed/FeedSchema.swift:252` turns every encoding failure into the valid JSON literal `null`, hiding the distinction between absent data and invalid numeric data.

Why it hurts. Agents must discover and maintain cross-field rules in every producer, fixture, and animation consumer. The compiler accepts combinations that the comments disallow. Non-finite values can also erase a whole encoded payload without a diagnostic at the encoding API.

Confirmed check. The actual page adapter forwarded an active orb with `waitingFor:'approval'`, `limited:false`, a nonempty `limitProvider`, and `queue:-3` unchanged. This establishes representability and missing boundary enforcement. It does not establish that normal Swift producers currently generate that combination.

Concrete fix. Use an associated-value lifecycle for active, waiting-with-optional-known-kind, and failed states. Keep unknown waiting kind valid. Represent a refusal as one optional value containing its provider. Use image and monogram icon variants with required payloads, plus validated finite activity and nonnegative queue values. Preserve the existing JSON shape with custom encoding if needed. Make serialization failure explicit instead of returning `null`.

Blast radius. Both source mappers, failure retention, world diffs, demos, icon resolution, provider-limit handling, and Swift/JS fixtures. Preserve legitimate snooze and failure combinations rather than inventing a new exclusive lifecycle. Do not close the provider namespace to a fixed enum because custom providers are supported.

## 5. P2. Bridge shapes and cross-language constants have no single owner

Evidence:

- `Sources/LocalModelWidget/PetLayer.swift:99` constructs startup config as `[String: Any]`. Line 183 switches on untyped message dictionaries. Unknown message types silently disappear at line 211.
- `Resources/Pet/pet.js:117` hardcodes the handler name. Lines 141-142 independently interpret the startup position. Line 1744 constructs the hit-region message, including a viewport the Swift receiver does not decode.
- `Sources/LocalModelWidgetPanel/PetLayerGeometry.swift:29` explicitly requires its `stageSize` to track JS `KEEP`. The Swift value is 640 by 760 at line 32 and the JS copy is at `Resources/Pet/pet.js:70`.
- `Sources/ModelWidgetCore/Feed/FeedWorld.swift:17` and `Sources/LocalModelWidget/FeedClient.swift:19` independently define a 20-second stale threshold.
- `Tests/ModelWidgetChecks/PetLayerChecks.swift:63` derives expected clamp results from the Swift constant. It does not compare that constant with JS.

Why it hurts. A bridge rename compiles while the receiver falls through. A one-sided keep-size change makes native restoration and JS clamping disagree, producing a position jump on startup or reload. The current values agree. These are maintenance hazards, not observed mismatches. The two stale clocks measure different things, so equal values alone do not prove they should be merged.

Concrete fix. Define typed host configuration and page-message variants with explicit decode errors. Inject the shared keep dimensions through configuration, or generate both definitions from one small contract. Name source freshness and transport silence separately, documenting their relationship. Add a cross-language compatibility check for message names and coordinate units rather than tests that repeat each side independently.

Blast radius. Startup readiness, reload replay, pointer capture, drag persistence, screen resizing, reduced-motion and sound settings, and stale display. Preserve CSS-pixel top-left coordinates and AppKit conversion. Keep the rendering `STAGE` dimensions separate from `KEEP`. A future full-desktop phase should extend these contracts without moving T3 polling into the page.

## 6. P2. Configuration accepts misspelled features as successful configuration

Evidence:

- `Sources/ModelWidgetCore/Feed/FeedFlags.swift:12` returns `Set<String>`. Line 16 accepts every positive name and silently ignores removal of an unknown name.
- `Sources/T3boiiFeed/main.swift:32` parses helper flags. `Sources/LocalModelWidget/FeedClient.swift:141` parses the fallback defaults. Both consume selected string names through `contains`.
- `Sources/LocalModelWidget/FeedSupervisor.swift:63` forwards the same raw defaults string to the helper, so the parsing policy is shared even though it is permissive.

Why it hurts. For example, `-seed` appears to succeed but leaves `seeds` enabled. A newly added feature can also be accepted without any consumer, so agents cannot tell a typo from a supported setting by inspecting the parsed result.

Concrete fix. Return typed feature values plus diagnostics for unknown tokens. Make the CLI reject invalid input with a useful message. For persisted defaults, report the invalid token and apply a documented fallback. Keep one parser for both paths and preserve the comma-separated add/remove syntax.

Blast radius. CLI startup, supervisor arguments, fallback configuration, and flag checks. Keep queue and seeds enabled by default. The `pr` reader is deliberately deferred in the roadmap; accepting `pr` must not be mistaken for proof that PR polling exists. Do not implement that other feature as part of this fix.

## Canon and boundaries that fixes must preserve

- `docs/pet-status-spec.md:5` records standalone operation with no T3 patches, forehead starts, mouth finishes, no settled display, no belly glow, floating questions and failures, and moons for subagents. Lines 145-184 require positive finish evidence and silent restart reconciliation.
- `docs/pet-status-spec.md:155` distinguishes owner messages from everything else. Do not infer a sender thread or add thread-to-thread beams while that identity is unknown.
- `docs/pet-status-spec.md:313` makes state authoritative and events choreography. Lost events must cost animation, not correctness. Keep the page offline and its token absent as required at line 205.
- `DESIGN.md:226` requires 3D, lit effects. Existing Reduce Motion and phase-based motion rules remain in force. Type cleanup does not authorize visual redesign.
- The roadmap's Canon and 16 October decisions preserve queue and seeds on by default, seeds falling into his T3, and the existing approval ownership rule. Its PR reader remains deferred pending real payload evidence.
- The older HUD proposal's environment plan at `docs/pet-hud-design-proposal.md:16` is superseded by `docs/pet-status-spec.md:3`. The user's upcoming full-desktop phase is future context, not authority to restore those old mechanics during this audit.

## Verification and limits

Read the named specs, `DESIGN.md`, `PRODUCT.md`, the roadmap, producer and consumer code, and relevant checks. Applied Type System Discipline to identify invalid constructions and Boundary Discipline to recommend one ingress parser. Used blast-radius tracing across Swift serialization, SSE, JS, and the reverse bridge.

Ran Node with source read into a data-URL module, importing the actual `Resources/Pet/feed.js`. Four assertions passed and demonstrated the invalid cases recorded above. The command wrote no test file or generated artifact. Swift scenarios and proposed fixes remain source-traced, not runtime-proven.

Did not run the app, sidecar, build, restart drill, or `scripts/check_widget.sh`. This is not merge acceptance. A skill-requested cross-provider explainer was rejected by automatic approval review because it could export private source to an unverified destination. No child task ran; the audit continued locally. No independent review is claimed.
