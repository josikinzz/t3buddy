# Swift app audit

Audited 2026-10-20 at `0fa5ef6`. Scope is the macOS window, WebView host,
LaunchAgent integration, and usage-card hosting. No code or installation changes.
No P0 found. Two P1 findings and four P2 findings follow.

## Overview and evidence limits

`main.swift:13-37` composes four card runtimes, `DashboardRuntime`, `PetLayer`,
`FeedSupervisor`, and `FeedClient`. The panel hosts SwiftUI. The pet hosts a local
page and receives feed JSON through native JavaScript evaluation. The supervisor
owns a helper process; the client can temporarily poll in-process.

This is a source audit, not runtime acceptance. Failure paths below are traced
from implementation, not reproduced against the running app. No build, checks,
Keychain access, network calls, launchctl mutation, or app launch was performed.
`scripts/check_widget.sh:8-10` writes build artifacts, so it was deliberately not
run under this task's one-file write restriction. Suggested checks are future work.
Blast-radius claims stop at source evidence, level 2 of the blast-radius skill.
The optional cross-provider investigation helper was rejected by automatic
approval review over private-source exposure. No delegated result was used.

## Findings

### P1. Migration deletes the Keychain token without proving durable storage

- Evidence. `Sources/LocalModelWidget/FeedSupervisor.swift:134-140` calls `save`
  and then `SecItemDelete`. Deletion also runs if the stored data cannot decode.
  `Sources/ModelWidgetCore/T3TokenFile.swift:72-80` catches write failures and
  returns no success result. Migration logs success regardless of that failure.
- Failure trace. A readable legacy token plus an unwritable destination causes
  `save` to log an error, followed by deletion of the only durable old copy.
  A malformed legacy payload is deleted without any replacement save.
- Why it hurts. The next launch loses authentication and agents debugging it
  see a misleading migration-success message. Recoverable storage failure becomes
  destructive migration.
- Concrete fix. Give the migration a throwing durable-save operation. Delete the
  legacy item only after successful encoding, write, and independent file readback.
  Keep unreadable or undecodable legacy data. Check and report deletion failure.
- Blast radius. One-time startup authentication migration and the token-store
  interface. Preserve noninteractive Keychain lookup, file modes, and current
  automatic pairing behavior. Do not move credentials into the WebView.
- Future check. Inject write failure and malformed payloads into a migration
  harness. Assert no delete call. On success, verify disk before allowing delete.

### P1. Offline page policy fails open when rule compilation fails

- Evidence. `Sources/LocalModelWidget/PetLayer.swift:104-118` logs a failed
  `compileContentRuleList` result, then loads the page anyway. Navigation policy
  at `PetLayer.swift:324-325` only checks navigation requests, not every script
  subresource fetch. `docs/pet-status-spec.md:205` requires the page to stay offline.
- Failure trace. If compilation returns no rule list, the local page loads with
  no installed content blocker. A future asset or script that fetches HTTP is
  then outside the documented offline protection. No current exfiltration was
  established by this audit.
- Why it hurts. Agents can trust an offline guarantee that is absent on its
  error path. Resource-loading changes can silently weaken the native boundary.
- Concrete fix. Do not load the page until the blocker is installed. Surface a
  recoverable startup error and use bounded retry. Keep native feed delivery.
- Blast radius. Pet startup and reload failure handling only. Do not block the
  native loopback feed client or external opening of valid T3 thread links.
- Future check. Inject a compiler failure and assert no page load. With a valid
  blocker, prove a local fixture renders while its HTTP subresource is blocked.

### P2. App-host behavior is outside the executable check target

- Evidence. `Package.swift:23-25` owns all app-host classes in the executable.
  `Package.swift:31-36` gives `ModelWidgetChecks` only Core and Panel dependencies.
  `Tests/ModelWidgetChecks/PetLayerChecks.swift:1-29` checks geometry helpers.
  `docs/pet-status-spec.md:768` calls for in-process WKWebView checks.
- Why it hurts. Agents can pass the named checks and compile while breaking
  native message handling, ready-state replay, blocker installation, or helper
  recovery. Pure hit-test checks cannot prove native click-through behavior.
- Concrete fix. Make the host testable through a small app-host library or a
  dedicated host harness with injected page loader, process launcher, and storage.
  Keep entry-point composition in the executable. Add behavior checks for the
  two P1 failure paths first, then ready/reload and live-helper handoff.
- Blast radius. SwiftPM target boundaries, imports, and the check entry point.
  Preserve app product names, bundled resource lookup, helper packaging, and
  MainActor ownership. Avoid extracting every view into speculative interfaces.
- Future check. The check command must invoke actual host code and catch an
  intentionally broken blocker failure branch. Native mouse routing still needs
  a real macOS smoke test.

### P2. Installer accepts an incomplete package as ready to launch

- Evidence. `scripts/deployment.sh:111-113` checks only the main executable and
  Info.plist. `scripts/install_launch_agent.sh:7-9` skips packaging on that result.
  `scripts/package_app.sh:14-20` separately installs the helper and resources.
  `Sources/LocalModelWidget/PetLayer.swift:123-131` can conceal missing bundled
  resources by using the source checkout. `FeedSupervisor.swift:54-56` similarly
  falls back when the helper is missing.
- Failure trace. A partial or old bundle containing the executable and plist but
  lacking `Contents/Helpers/t3boii-feed` or `Resources/Pet/index.html` passes the
  readiness predicate. Installation then enables that bundle without rebuilding.
- Why it hurts. Agents get a successful installation of an incomplete artifact.
  A development checkout may hide the packaging defect until the app moves.
- Concrete fix. Validate every required runtime component before installation,
  including the helper executable and pet entry page. Verify bundle signature.
  Repackage or fail clearly when validation fails. Do not imply file presence
  proves freshness; define freshness separately if the installer promises it.
- Blast radius. Packaging and LaunchAgent preflight. Retain unbundled dev lookup
  and in-process recovery as deliberate runtime resilience, not package validation.
- Future check. Use synthetic bundle manifests and a fake launchctl to prove
  a missing helper or page prevents bootstrap. Do not test on the installed app.

### P2. Connect T3 has no user-visible result and bypasses the active fallback

- Evidence. `Sources/LocalModelWidget/SubscriptionPanelView.swift:26` posts a
  notification. `Sources/LocalModelWidget/main.swift:36-37` only logs its result.
  `FeedClient.swift:64-67` always posts to discovered helper metadata, while
  `FeedClient.swift:140-154` can own an active in-process T3 source instead.
- Failure trace. With a missing or unresponsive helper and fallback active,
  clicking Connect T3 returns false or times out through the helper path. The
  card shows no pending state, success, or failure. Automatic fallback pairing
  may later recover, but the explicit action did not reach that active source.
- Why it hurts. Users cannot tell whether the control worked. Agents diagnosing
  recovery must correlate system logs with hidden transport ownership.
- Concrete fix. Return a typed connection result to observable settings state.
  Show pending and failure status in the existing menu. Route explicit reconnect
  to the active source, or state clearly that helper recovery is required.
- Blast radius. Settings intent routing, FeedClient, and fallback source API.
  Preserve read-only pairing scope, throttling, and the rule that unknown feed
  state never becomes a finish. Do not expose tokens or technical logs in UI.
- Future check. Fake helper absent, helper HTTP failure, and fallback active.
  Assert one visible result and the correct reconnect destination for each.

### P2. Subscription refresh startup leaks timers on repeated calls

- Evidence. `Sources/LocalModelWidget/SubscriptionPanelRuntime.swift:27-34`
  schedules two repeating timers without invalidating the previous pair.
  `TokenUsageRuntime.swift:33-36`, `DesktopPanelRuntime.swift:62-65`, and
  `ProcessPanelRuntime.swift:44-47` invalidate before scheduling instead.
  `DashboardRuntime.swift:62-66` exposes startup for all four runtimes.
- Failure trace. Call subscription `startRefreshing()` twice. The run loop keeps
  both original timers, while the fields retain only the replacement pair.
  The refresh guard prevents concurrent reads but not duplicated future ticks.
- Why it hurts. An agent reusing dashboard startup during lifecycle work can
  create duplicate polling and callbacks without an obvious ownership error.
  Current `main.swift:22` calls startup once, so this is a latent lifecycle defect.
- Concrete fix. Invalidate both timers before scheduling, matching peer runtimes.
  Add explicit stop/deinit cleanup if runtimes gain a shorter lifecycle.
- Blast radius. Subscription-card polling only. Keep the 300-second account and
  60-second Grok cadences, stale-value retention, and privacy-preserving row UI.
- Future check. Start twice under a controllable scheduler and assert one timer
  at each cadence. Verify one refresh after a scheduled tick.

## Canon and boundaries future fixes must preserve

- `docs/pet-status-spec.md:3-24` supersedes the older proposal's environment
  section. Keep T3 independent, with no T3 patches. The sidecar owns the feed.
  The requested upcoming desktop phase is future scope, not permission to revive
  the proposal's island or weather during host cleanup.
- `docs/pet-status-spec.md:9-19` preserves forehead spawn, mouth swallow only on
  real completion, no settled threads, no belly glow, floating question marks
  rather than held questions, and cracked floating failures. Outages, restart,
  refusal, and slowness must not produce completion animations.
- The owner's private roadmap confirms that canon and the
  later seeds-on-by-default decision. Seeds fall into the T3. Do not replace them
  with new launch-out animations. The older spec's prototype wording is stale.
- Keep the page offline and credentials native, as required by
  `docs/pet-status-spec.md:205`. Keep the camera fixed per
  `docs/pet-hud-design-proposal.md:462-464`. Preserve Reduce Motion, sleep pause,
  native materials, compact cards, and explicit destructive-action labels.
- Keep the pet nonactivating and click-through outside reported hit regions.
  Keep desktop and float levels deliberate. Multi-display and occlusion behavior
  need native validation before changing window-level or screen-selection policy.
- No installed-app, LaunchAgent, outputs, feed-schema, renderer, usage-reader,
  or T3 changes are authorized by this audit. Other lanes own those internals.

## Method and remaining gates

Boundary Discipline focused findings on storage and WebKit failure paths.
Minimize Reader Load favored a narrow host test seam over broad refactoring.
Prove It Works required checking this report's actual references and write scope.
The blast-radius skill was used for affected-consumer tracing; its runtime proof
step remains unrun under the one-file restriction. No-comments' mutation workflow
was skipped because this audit authorizes no code or comment edits.

Before any fixes merge, run `scripts/check_widget.sh` (since replaced by `scripts/verify.sh --full`) and the focused checks
above in an authorized implementation lane. Exercise WebView termination and
reload, helper crash and fallback, screen sleep and wake, Reduce Motion, native
click-through, and LaunchAgent install/uninstall in a disposable environment.
No such gate is claimed green here.
