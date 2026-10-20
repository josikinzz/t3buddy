# Dead-code audit

Audited 2026-10-20 at `0fa5ef6`. Read-only investigation of tracked source,
tests, scripts, resources, and entry points. No P0 or P1 finding established.
The findings below are P2 maintenance work, ordered by value to agents.
No code was changed and no deletion is authorized by this report.

## P2 findings

### 1. Local Models still samples memory that its card no longer consumes

- Evidence. `Sources/ModelWidgetCore/WidgetViewModel.swift:7` publishes memory;
  lines 14, 16, and 29 retain the sampler and sample on refresh. Line 58 samples
  again after unloading. `Sources/LocalModelWidget/DesktopPanelRuntime.swift:27`
  injects `SystemMemorySampler`. The entire presentation factory at
  `Sources/LocalModelWidgetPanel/DesktopPanelPresentation.swift:19` reads only
  active identity, busy state, and status text. The view at
  `Sources/LocalModelWidget/DesktopPanelView.swift:26` renders that presentation.
  The old memory assertion survives at `Tests/ModelWidgetChecks/main.swift:179`.
- Why it hurts. Agents must trace a second memory pipeline with no visible
  consumer. It performs live work and publishes changes on the three-second
  refresh cadence. A sampler error also replaces Local Models status with an
  unrelated memory error through `WidgetViewModel.swift:33`, even after model
  refresh succeeded. That failure path is inferred from source, not reproduced.
- Concrete fix. Remove memory state, sampler injection, and sampling from
  `WidgetViewModel`, its runtime constructor, and its fixtures. Preserve model
  status and unload handling. Do not remove the shared sampler or memory types.
- Blast radius. Public `WidgetViewModel` initializer and property, test fixture
  constructors, and local-model status behavior. Process Memory remains a live
  consumer through `Sources/LocalModelWidget/ProcessPanelRuntime.swift:27` and
  `Sources/LocalModelWidgetPanel/ProcessPanelPresentation.swift:76`.
  Verify model refresh/unload with a failing former sampler and retain the
  process-memory assertions. External consumers of the public library are unknown.

### 2. The former model picker leaves a product-unreachable loading path

- Evidence. `Sources/ModelWidgetCore/WidgetViewModel.swift:38` exposes `activate`;
  `Sources/ModelWidgetCore/LocalModelSession.swift:101` and line 106 implement
  activation. `LocalModelSession.swift:163` unloads other models and loads the
  target. The shipped intent enum at
  `Sources/LocalModelWidget/DesktopPanelRuntime.swift:7` has only Unload and Quit;
  `Sources/LocalModelWidget/DesktopPanelView.swift:28` wires only Unload.
  Searches across the app and panel sources find no `.activate(` or
  `.activateModel(` call. Tests still invoke them at
  `Tests/ModelWidgetChecks/main.swift:82`, 217, 243, 262, 265, and 320.
- Why it hurts. Tests make an unavailable UI operation look like supported
  product behavior. Agents inherit loading states, pending selection, and
  provider load methods when the current card only reports and unloads.
  Related inventory work remains live at
  `Sources/ModelWidgetCore/LocalModelSession.swift:179`: every reconciliation
  enumerates and annotates installed models, although the current presentation
  does not consume the list. This is unused product output, not an unreachable
  function. The library products in `Package.swift:11` mean outside use is unknown.
- Concrete fix. First establish whether the public loading API has consumers
  outside this checkout. If none, remove the activation chain and loading-only
  state, then trim installed-model enumeration from the dashboard refresh path.
  If the API is intentionally retained, separate the dashboard's loaded-model
  refresh from the picker API and explicitly label the latter as library-only.
  The upcoming desktop phase alone does not prove a current consumer.
- Blast radius. `WidgetViewModel`, `LocalModelSession`, `ModelProvider`, the
  Bonsai/Magnitude/Ollama adapters, mocks, and activation tests. Do not delete
  whole clients. Loaded-model detection, Unload, offline-host handling, and the
  existing multi-host normalization policy remain live. In particular,
  `LocalModelSession.swift:180` still calls normalization; removing inventory
  work must preserve that behavior rather than quietly changing its policy.
  Retain refresh, busy-unload, and externally-loaded-model checks.

### 3. Two runtimes duplicate both their adapter pattern and update triggers

- Evidence. `Sources/LocalModelWidget/DesktopPanelRuntime.swift:32` observes
  `objectWillChange` and queues a presentation rebuild. Lines 59 and 71 also
  rebuild after action and refresh. The same structure appears at
  `Sources/LocalModelWidget/ProcessPanelRuntime.swift:33`, 60, and 72.
  Both view models publish state, so one refresh can schedule observer rebuilds
  as well as its explicit final rebuild. Duplicate paths are source-confirmed;
  their runtime frequency and cost were not measured.
- Why it hurts. An agent must account for two synchronization mechanisms and
  maintain near-identical timer, observer, and task code in two places. It is
  unclear which mechanism owns intermediate busy states and final state.
- Concrete fix. Choose one presentation-update owner in each runtime. The
  smallest candidate is keeping the deferred observer and removing redundant
  explicit final rebuilds, after verifying notification coverage. Keep initial
  presentation construction. Do not introduce a generic runtime framework just
  to merge these two files.
- Blast radius. Local Models and Process Memory presentation timing, busy-button
  feedback, and final status after Unload or Force Quit. Keep deferred handling
  because `objectWillChange` precedes mutation. Verify intermediate and final
  states before deleting a path; static duplication is not proof that either
  synchronization strategy can be removed without checking timing.

## Canon and apparent leftovers that must stay

- `docs/pet-status-spec.md:9` establishes forehead starts, swallow only on real
  finish, no settled threads, no belly glow, floating questions/errors, and no
  flat stickers or tooltips. Limits behavior stays per line 661. Never remove
  state retention or restart resync as redundant bookkeeping.
- `FeedClient` fallback is live at
  `Sources/LocalModelWidget/FeedClient.swift:125` and creates the same feed engine
  at line 143. It is not a duplicate obsolete orbit implementation. The proposed
  single token writer at `docs/pet-status-spec.md:230` is not evidence that this
  implemented recovery path is dead.
- Queue and seeds are approved defaults with explicit opt-outs at
  `Sources/ModelWidgetCore/Feed/FeedFlags.swift:8` and in the owner's private
  roadmap. Keep `-queue` and `-seeds`.
  The seed prototype remains specified at `docs/pet-status-spec.md:649`.
- PR rings are deliberately waiting for real payload evidence, per
  `docs/pet-status-spec.md:884` and roadmap line 78. `pr` currently has no source
  acquisition wiring in `Sources/T3boiiFeed/main.swift:36`; that is an unfinished
  approved gate, not authorization to delete the renderer or turn it on.
- The older HUD proposal contains future systems and superseded behavior.
  Its open questions at `docs/pet-hud-design-proposal.md:650` are not permission
  to restore belly glow, settled orbs, or hand-held questions against later canon.
  Preserve the document as design history rather than treating it as executable
  feature configuration. The full-desktop phase is outside this cleanup lane.
- Debug and demo hooks have real entry points. `pet.js:1931` handles `?fake`,
  line 1941 handles `?debug`, and `PetDemoTrigger.swift` is constructed at
  `Sources/LocalModelWidget/main.swift:41`. Demo must use existing animations.
  Attention/chatter code is live gaze behavior at `pet.js:1186`, not a leftover
  speech-bubble implementation despite older naming and comments.
- Do not prune assets by literal filename hits alone. All shipped MP3s have
  `CLIPS` entries; `Resources/Pet/sounds.js:63` constructs their fetch paths.
  `Resources/Pet/vendor/three/examples/jsm/loaders/GLTFLoader.js:68` and line 69
  import both utility files. Favicons and the Apple touch icon are linked at
  `Resources/Pet/index.html:4`. Benchmark HTML and Markdown are both intentional
  lookup candidates at `Sources/LocalModelWidget/BenchmarkDoc.swift:30`.
  No whole unused tracked file or asset was established in this pass.

## Evidence and limits

- Used tracked-file inventory, declaration/token scans, caller searches, and
  source tracing through app, sidecar, page, tests, and packaging. Checked the
  named specs and roadmap. Old `OrbitRemovalHold` and `OrbitSourceFallback`
  implementations are already absent; their remaining mentions describe history.
- Ran in-memory Python assertions confirming no app/panel activation calls,
  no Local Models presentation reads of memory/models/pending selection, both
  duplicated update paths, and sound-registry coverage. A first broad assertion
  also matched the live Process Memory view model; narrowed it by consumer type.
- Static evidence does not prove external API non-use or dynamic UI timing.
  No build, app execution, check suite, packaging, or asset regeneration ran.
  `scripts/check_widget.sh` (since replaced by `scripts/verify.sh --full`) remains the required gate for any later code change.
  `outputs/`, the installed app, and pre-existing screenshots were untouched.
- Minimize Reader Load shaped the recommendations to remove misleading state
  and duplicate owners. Blast-radius analysis kept shared live consumers and
  public API uncertainty explicit. Unslop and technical-writing shaped this report.
- Automatic approval review rejected a Claude delegation because private-source
  egress to that provider was not specifically authorized. No delegated result
  was used; the audit continued locally.
