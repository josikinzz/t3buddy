# Tests and CI audit

Read-only audit of working-tree sources at `0fa5ef6`, 20 October 2026.
Only this report was written. No build, app launch, installation, publication,
output inspection, or product mutation was performed.

Throughput checkpoint: n/a, read-only investigation.

## Overview

`scripts/check_widget.sh:8-10` lints generated plists in a temporary directory,
runs the `ModelWidgetChecks` executable, then builds the package.
`Tests/ModelWidgetChecks/main.swift:577-604` catches check failures and exits 1.
This is a useful existing gate. Its main weakness is incomplete execution coverage,
especially where Swift hands state to the JavaScript pet.

No P0 found. P1 means a green gate can miss a regression in core pet behavior.
P2 means weaker automation, misleading coverage, or avoidable agent friction.
The findings below describe verification defects, not reproduced product bugs.

## P1 findings

### 1. The gate never executes the pet page or its feed adapter

Evidence. `Tests/ModelWidgetChecks/PetLayerChecks.swift:7-103` checks geometry,
hit rectangles, and window policy without constructing a WKWebView.
`Tests/ModelWidgetChecks/OrbitStateChecks.swift:75-83` evaluates only an extracted
table. `Package.swift:31-36` declares a Swift executable check target.
No check source mentions `WKWebView` or `createFeed`.
The planned page replay in `docs/pet-status-spec.md:768-771` is absent.

Why it hurts. `Resources/Pet/feed.js:15-29` decides which disappearing orbs fade
and which may be swallowed. Swift-side event correctness cannot prove that this
adapter consumes events correctly, that module imports work, or that the page
still loads. A broken page can survive the Swift checks and build.

Concrete fix. Add behavioral checks that execute the real `createFeed` with a
capturing consumer. Cover disappearance without terminal evidence, explicit
finish, event-only batches followed by state, reset, and repeat delivery.
For example, remove both `a` and `b` from a shown state with only `finished a`;
the consumer must receive `fade == ["b"]`. Follow with another state batch to
prove that finish evidence is cleared. Add a bounded WKWebView smoke replay
that loads the actual module graph, captures JS errors, and checks final orb ids
and modes. A JS-only adapter test is useful but does not replace this load test.

Blast radius. Check target and page-test fixtures; production behavior need not
change. WKWebView requires macOS and can need a GUI-capable runner. Keep pure
adapter cases cheap, report unavailable browser coverage explicitly, and never
let a skipped page test masquerade as a complete pass.

### 2. The real helper restart drill is outside the verify command

Evidence. `scripts/check_widget.sh:8-10` never invokes the drill.
`Tests/ModelWidgetChecks/FeedWorldChecks.swift:87-97` supplies `resync = true`
directly. It proves the model's response, not that the MCP source detects a
restart or renewed token and sets that flag.
`scripts/t3_restart_drill.py:164-165,190-226` exercises the real helper against
a fake T3 through restart, dropped session, token renewal, and subsequent finish.

Why it hurts. The documented canon can regress in discovery, auth, or source
integration while the model-level resync fixture stays green. Agents following
the single advertised command receive no warning about this unrun coverage.

Concrete fix. Make the complete verification path run the drill after building,
passing the just-built helper path explicitly. Preserve the normal-finish
positive controls as well as the no-false-finish assertions. Prefer bounded
waits for observed conditions over fixed success delays, while retaining explicit
observation windows where absence of an event is the assertion.

Blast radius. Check script, drill, and Python prerequisite documentation.
The drill already isolates its T3 home and token in a temporary directory
(`scripts/t3_restart_drill.py:2-5`). Its declared `take()` windows sum to 66 s
(`:191-222`), excluding other work. This is a static sum, not measured runtime.
Expose clearly named fast and complete modes if necessary; merge verification
must include the complete mode. Do not silently add that delay to every edit loop.

## P2 findings

### 3. No tracked CI runs the gate

Evidence. `git ls-files .github .gitlab-ci.yml Jenkinsfile azure-pipelines.yml`
returns no paths. `README.md:129` asks a human to run the script.
`scripts/publish.sh:105-109` checks publication privacy and identity before push,
without invoking behavioral checks. These are distinct checks, not substitutes.

Why it hurts. A locally forgotten check has no repository-owned automated
backstop. Agents cannot point to a repeatable CI result for the published tree.
External checks configured outside the repository were not inspected.

Concrete fix. Add a macOS CI job that calls the same complete verification
entry point, with a documented Swift version and bounded job timeout. Cache
build products by runner, toolchain, and package inputs. Keep installation,
signing, secrets, real T3 access, and publication out of the job.

Blast radius. Workflow and verify-command configuration. It adds CI cost and
requires a macOS runner. Preserve `scripts/publish.sh` as the only push path,
including its squash, noreply, and privacy rules. CI must not publish private
local history or become a new deployment path.

### 4. Motion enforcement recognizes spellings, not variable-rate behavior

Evidence. `Tests/ModelWidgetChecks/PetMotionChecks.swift:35-36` explicitly passes
uppercase names and `speed * this.t`. The variable-clock pattern at `:84`
recognizes selected names and `sin`, but not `cos(t * rate)` or `velocity * t`.
`petScripts()` excludes `motion.js` at `:76-78`; no behavioral check executes
`Phase.advance` or `tremble` in `Resources/Pet/motion.js:10-22`.

Why it hurts. An agent can accidentally reintroduce clock-dependent motion under
a different expression while retaining a green lint. Editing the exempt primitive
can also defeat every caller guard. Uppercase spelling does not prove a rate is
constant. The invariant is continuity when the rate changes after long uptime.

Concrete fix. Keep the cheap static rules and add negative controls for alternate
spellings. Execute the real motion primitives and activity-driven orbit update
with a synthetic clock at zero and six hours, changing rates at 30 and 60 fps.
Assert phase continuity and the existing speed and pulse caps specified in
`docs/pet-status-spec.md:784-790`. A parser can improve static diagnostics, but
must not become the sole evidence for motion behavior.

Blast radius. Motion tests and a reusable runtime harness. Do not rewrite motion
or retune approved animation to satisfy a new test. Establish fixture expectations
from the contract, with allowed tremble windows and Reduce Motion covered.
The in-memory probe here replayed the literal regex with Python and matched
`Math.sin(t * rate)` but not `Math.cos(t * rate)` or `velocity * t`.
It was not a run of Swift Regex or a rendered-motion reproduction.

### 5. The question-mark test pins a private table's source formatting

Evidence. `Tests/ModelWidgetChecks/OrbitStateChecks.swift:77-80` requires a line
starting exactly `const ASK_MARK = ` and splits the initializer on `;`.
The real consumer is `Resources/Pet/orbit.js:1591`.

Why it hurts. A multiline formatting change fails even with identical behavior.
Conversely, a correct table passes if the renderer ignores or reverses its lookup.
The test proves an internal value, not what the user sees.

Concrete fix. Drive the page with input and approval orbs and assert their exposed
mark kinds through the running renderer. Include an unknown-kind fallback case.
Reuse the page harness from finding 1 rather than adding another source extractor.

Blast radius. One assertion block and page-test observability. Keep `?` for input
and `!` for approval. Preserve the orb-as-dot geometry and Reduce Motion behavior;
this is a test replacement, not a visual redesign.

### 6. Verify paths fragment caches and offer no focused rerun

Evidence. `README.md:52-54` advertises default `.build` and `.build-dev` commands,
while `scripts/check_widget.sh:9-10` uses the scratch directory hard-coded in
`scripts/deployment.sh:8`. That assignment overwrites an environment override.
`Tests/ModelWidgetChecks/main.swift:552-569,577-594` registers and runs every
check sequentially, without selection or per-check timing.

Why it hurts. An agent following different documented commands can rebuild into
different caches. A narrow correction still runs every suite, and a slow check
has no duration in its result. Actual command speed and its dominant cost are
unknown in this audit; two Swift invocations alone do not prove duplicate compiling.

Concrete fix. Document one canonical verify command with an overridable check
scratch path, shared across its build and run steps. Add named suite selection
for local reruns and per-stage durations, preserving raw exit codes. Keep the
unfiltered complete command as the merge gate. Measure cold and warm runs before
changing build order or introducing parallel execution.

Blast radius. Check runner, shell entry point, and README. Preserve packaging's
artifact paths and explicitly pass the matching helper to the restart drill.
Keep stateful checks serial unless their shared fixtures are isolated first.
Minimize Reader Load favors one command over more wrappers or competing recipes.

## Canon and scope that fixes must preserve

- `docs/pet-status-spec.md:6-24` establishes the standalone sidecar, forehead
  starts, mouth finishes, no settled display or belly glow, and diegetic orb acts.
  `:145-146,181` requires positive terminal evidence and silent restart resync.
- The canon in the owner's private roadmap also forbids flat stickers,
  bubbles, and tooltips. Questions float near him; errors use the worry zone.
- Later owner decisions in that roadmap at `:71,99-100` turn seeds and queue
  beads on by default and accept roughly 22 s startup. Do not turn the older
  proposal's flagged defaults into regression expectations or optimize startup
  as an unapproved behavior change.
- `docs/pet-status-spec.md:3` supersedes the earlier HUD environment proposal.
  The owner's private roadmap defers environment work. The upcoming
  full-desktop phase is outside this audit; these findings do not decide its scope.
- Preserve `tremble`, phase integration, Reduce Motion, and the existing motion
  guards. Test Behavior, Not Implementation calls for observable coverage beside
  these guards, not wholesale deletion of policy lint.

## Verification and limits

Read the runner, check files, deployment and publication scripts, specs, and
roadmap. A delegated read-only explainer independently confirmed the missing
restart gate, unexecuted page adapter, and brittle table extraction.
`bash -n` passed for `check_widget.sh` and `deployment.sh`; Python parsed the
restart drill with `ast.parse`. The regex probe and source inventory wrote no files.
No full check suite, restart drill, browser replay, CI run, benchmark, or live soak
was run. Cold/warm timings, current suite pass status, and runtime blast-radius
claims remain unverified under the one-file-only boundary.
