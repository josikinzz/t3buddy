# Docs and agent ergonomics audit

Audited 2026-10-20 at local HEAD `0fa5ef6`. Lane limited to documentation,
onboarding, command discovery, and codebase navigation. No P0 findings.
Priorities reflect the cost of an agent following the docs literally.
P1 can cause an incorrect fix or canon regression. P2 wastes work or weakens verification.

Throughput checkpoint: n/a, read-only investigation.

## Findings

### P1.1 Required reading can teach agents to restore rejected behavior

- Evidence. `AGENTS.md:3-4` requires DESIGN before visible changes but does not
  link either pet spec. `README.md:23` says a waiting thread is held out.
  `DESIGN.md:239` says two missing polls mean a finished agent is swallowed.
  `DESIGN.md:251` still describes the held-out demo beat.
  `docs/pet-status-spec.md:15-18` requires floating question marks and worry shapes.
  `AGENTS.md:23` explicitly forbids swallowing on unknown state.
  `Resources/Pet/feed.js:16-24` distinguishes finished events from plain fades.
- Why it hurts. An agent implementing a visual fix from mandatory reading can
  reintroduce held questions or completion during outages. This is a direct
  conflict among instructions, not a request to redesign the pet.
- Concrete fix. Add a short precedence and reading-order section to AGENTS,
  linking the status spec and naming its decisions as constraints. Reconcile
  the stale README and DESIGN descriptions with those decisions. Label historical
  descriptions as historical instead of silently treating them as requirements.
- Blast radius. Agent instructions, README behavior, DESIGN emotes and demo text.
  Preserve lifecycle semantics, visuals, and existing demo animations. No runtime
  change is needed to correct these descriptions.

### P1.2 Connection onboarding diagnoses the wrong architecture and port

- Evidence. `README.md:43` says the address is fixed at port 3773 and requires
  a source edit to change it. `README.md:84` describes five-second app polling.
  `README.md:112-125` repeats the fixed-port prerequisite and probe.
  `Sources/ModelWidgetCore/Feed/T3ServerIdentity.swift:16-28` reads the runtime
  identity and loopback origin. `Sources/ModelWidgetCore/T3ThreadSource.swift:461-468`
  updates the client origin. `Sources/LocalModelWidget/FeedSupervisor.swift:35-38`
  locates the helper, and `Sources/LocalModelWidget/FeedClient.swift:7-14` describes
  SSE discovery, stale state, and in-process fallback.
- Why it hurts. A healthy T3 on its discovered port can fail the documented
  prerequisite. An agent may edit `defaultOrigin`, restart T3 unnecessarily,
  or investigate the app while the helper is the failing component.
- Concrete fix. Replace the connection and troubleshooting sections with the
  actual route. Runtime identity discovery leads to sidecar MCP reads, then
  authenticated loopback feed, Swift relay, and page reconciliation. Document
  the fallback separately. Distinguish T3 OAuth credentials from the feed bearer
  token. Provide probes that report status without printing either secret.
- Blast radius. README requirements, setup, diagnostics, and architecture text.
  Keep the current loopback restriction, read-only MCP scope, OAuth flow, and
  standalone relationship to T3. Do not patch T3 or read its database.

### P1.3 README assigns bot approvals to the owner

- Evidence. `README.md:23` groups pending questions and approvals as threads
  waiting on the user. `docs/pet-status-spec.md:509-511` explicitly says the
  owning bot decides a `!` approval; it is not a request to Josie. The owner's private
  roadmap repeats that standing rule.
- Why it hurts. Agents using the README as the product contract can escalate
  routine bot decisions to Josie or write misleading status documentation.
- Concrete fix. Distinguish question marks from approval marks in the README
  and link the standing rule from AGENTS. Preserve its stated exceptions for
  spending, publishing, sending, and destructive or irreversible actions.
- Blast radius. Agent routing instructions and the README pet description.
  This is a documentation correction, not authorization to change approval
  policy or bypass any tool-level permission requirement.

### P2.1 Neither entry point maps the current feed implementation

- Evidence. `README.md:154-170` maps the Swift libraries, app, and pet directory
  but omits `Sources/T3boiiFeed` and the feed chain.
  `Package.swift:14,27-30` declares the helper product and target.
  `docs/pet-status-spec.md:82-87` proposes names such as `T3PollingSource` and
  `WorldModel`, while the helper constructs `T3ThreadSource` and `FeedEngine`
  at `Sources/T3boiiFeed/main.swift:35-37`.
- Why it hurts. New agents must rediscover the process boundary and translate
  planned names into shipped files before making a scoped change. Searching
  the plan's symbols does not reliably find the owner of the behavior.
- Concrete fix. Extend the README map with helper entry point, `FeedEngine`,
  `FeedWorld`, `FeedSchema`, `FeedServer`, `FeedSupervisor`, `FeedClient`,
  `PetLayer`, `feed.js`, `orbit.js`, and the relevant check files. Link it from
  AGENTS. Separate current ownership from the implementation plan's proposed map.
- Blast radius. Navigation docs only. Do not rename modules to match the old plan
  or duplicate detailed contracts in AGENTS. Keep `CLAUDE.md` linked to AGENTS.

### P2.2 Plans present unimplemented debugging features as usable interfaces

- Evidence. `docs/pet-status-spec.md:3` still says nothing has been built.
  Its `:75-78` describes `--record` and `--replay` debugging modes, and `:828`
  asks for a recording through `--replay`. The current CLI parses serving modes,
  flags, T3 home, and token file at `Sources/T3boiiFeed/main.swift:16-36`, then
  runs the live engine at `:63-74,96-102`. There is no record/replay dispatch there.
  `docs/pet-status-spec.md:292` also describes `source` as an object, while
  `Sources/ModelWidgetCore/Feed/FeedSchema.swift:226-244` uses `FeedSourceStatus`.
- Why it hurts. Copying planned flags can produce a live session rather than a
  replay. The same document mixes approved behavior, proposed contracts, and
  historical implementation steps, inviting agents to infer unsupported features.
- Concrete fix. Keep the plan as a dated plan. Add an implementation-status
  note and a linked current CLI/schema reference derived from the actual parser
  and Codable types. Mark record/replay as unavailable until implemented.
  Give example payloads only for the currently encoded contract.
- Blast radius. Spec annotations and current reference docs. Preserve approved
  semantics and original proposal provenance. Do not implement CLI features or
  change the wire format merely to make the plan read as current.

### P2.3 Run and install instructions can validate an older bundle

- Evidence. `README.md:129-131` tells agents to check, then run or install.
  `scripts/run_widget.sh:7-11` and `scripts/install_launch_agent.sh:7-9` only
  package if `deployment_app_is_packaged` is false. That predicate checks for
  an executable and Info.plist, not source freshness, at `scripts/deployment.sh:111-113`.
  `scripts/package_app.sh:8-23` is the separate release rebuild and resource copy.
- Why it hurts. With an existing bundle, an agent can pass checks on current
  source but inspect the previous UI and conclude its change had no effect.
- Concrete fix. Document the current distinction between checking source,
  explicitly packaging current source, opening an existing bundle, and installing
  login startup. Put packaging before run/install when validating a changed app.
  Document `DEPLOYMENT_OUTPUT_DIR` from `scripts/deployment.sh:6-7` for isolated
  packaging when a task permits it. Make side effects explicit beside commands.
- Blast radius. README build and agent setup instructions. No script change is
  proposed in this lane. Packaging replaces the selected bundle and installation
  changes LaunchAgent state, so neither belongs in a read-only audit.

### P2.4 Verification instructions do not separate runnable checks from planned gates

- Evidence. `AGENTS.md:6` calls `scripts/check_widget.sh` all checks, but that
  script only lints generated plists, runs `ModelWidgetChecks`, and builds at
  `scripts/check_widget.sh:8-10`. AGENTS names a separate restart drill at `:23`.
  Its invocation and default helper path are only in `scripts/t3_restart_drill.py:7,19`.
  `docs/pet-status-spec.md:768-771` plans a WKWebView feed integration check,
  while `Tests/ModelWidgetChecks/PetLayerChecks.swift:6-29` checks geometry.
  The synthetic-clock harness has no invocation at `docs/pet-status-spec.md:780-784`;
  `docs/pet-hud-design-proposal.md:489-490` locates it in owner memory, outside the repo.
- Why it hurts. Agents cannot discover a complete reproducible verification
  route. A green script can be misreported as browser, motion, restart-drill,
  or soak acceptance. This finding concerns documentation of coverage, not
  whether the implementation passes those gates.
- Concrete fix. Add a verification guide linked from AGENTS and README. For
  each runnable gate, name its command, prerequisites, outputs, and coverage.
  Include the fake-T3 drill and its helper build prerequisite. Mark screenshot,
  synthetic-clock, and soak gates as unavailable or manual until their actual
  invocation is recorded. Link any existing harness rather than inventing one.
- Blast radius. Verification docs and spec status labels. Preserve the required
  pre-merge check. Do not claim unrun acceptance or copy private harness notes
  into public docs without reviewing their contents.

## Constraints that fixes must preserve

- `docs/pet-status-spec.md:6-24` preserves standalone sidecar architecture,
  forehead starts, swallowed finishes, no settled display or belly glow,
  messages from behind, floating questions, worry shapes, eggs, and moons.
- `AGENTS.md:19-23` preserves accumulated motion phases, bounded tremble,
  lit 3D effects, and positive completion evidence. An outage is never a finish.
- `docs/pet-status-spec.md:511` preserves bot-owned approvals and its exceptions.
- The owner's private roadmap
  records seeds and queue beads on by default, seeds falling into the T3,
  the newest-question nod, and acceptance of roughly 22 seconds to first orbs.
  The defaults are also encoded at `Sources/ModelWidgetCore/Feed/FeedFlags.swift:8`.
- `docs/pet-status-spec.md:3,6` supersedes the old island/weather proposal for
  this work. The upcoming full-desktop phase in the audit brief does not itself
  approve those old designs. Document its new decisions separately when supplied.
- `AGENTS.md:17-18,24` preserves private history, the publish-only script route,
  generic test data, and demos using existing animations. Do not replace the
  `CLAUDE.md -> AGENTS.md` symlink with a divergent instruction copy.

## Coverage and verification limits

Inspected root docs, both pet specs, the supplied roadmap, package targets,
deployment scripts, helper entry point, feed transport/schema, page reconciliation,
and representative checks. Findings describe source/document contradictions.
No app, sidecar, install, packaging, check suite, network probe, screenshot harness,
or soak was run. Proposed fixes have not been implemented or runtime-verified.
Existing untracked media was left alone. Only this audit file was written.

Applied Prove It Works by comparing instructions against their actual entry points
and checking the final artifact. Applied blast-radius analysis to bound each fix
to docs and identify canon it must preserve. Technical-writing and unslop shaped
the report. No runtime safety claim rests on a proposed documentation fix.
