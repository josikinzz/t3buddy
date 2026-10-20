# Build, install, and publish audit

Audited 2026-10-20. Scope is build scripts, app packaging, LaunchAgent lifecycle,
backup policy, and public publication. No code or installed state was changed.
No P0 found. Findings below are source-confirmed failure paths, not live reproductions.

## Overview

`Package.swift:13-15` exposes the app, `t3boii-feed`, and the executable check suite.
`scripts/deployment.sh:5-33` centralizes paths, identity, and LaunchAgent settings.
The app lives in `outputs/`, rather than being copied to Applications.
The LaunchAgent executes that bundle's binary directly and uses the checkout as its
working directory (`scripts/deployment.sh:77-97`). Moving or deleting the checkout
therefore affects the installed service.

## Prioritized findings

### P1. Packaging destroys the live bundle before validating its replacement

- Evidence. `scripts/package_app.sh:8-24` builds both products, deletes the destination
  at line 11, then copies files and signs. `scripts/deployment.sh:18-23,77-80` makes
  that same destination the login service's executable. No staging, backup, rollback,
  or retention logic exists in the tracked scripts.
- Why it hurts. A copy, disk-space, or signing failure leaves a partial replacement
  after removing the known working bundle. A running app can also encounter replaced
  resources or restart its helper from the replacement path. Agents cannot safely
  treat packaging as a disposable build step.
- Concrete fix. Build and sign a sibling staging bundle, verify its required contents,
  then perform a controlled replacement with rollback. Before replacement, preserve
  a timestamped known working app. Prune only after successful verification, keeping
  the newest two app backups as approved in the roadmap at lines 98-99.
- Blast radius. Packaging destination, running WKWebView resources, helper restarts,
  login launch, and recovery. Preserve the existing bundle identifier and user data.
  Test interrupted copy/sign and failed launch before adopting the replacement flow.

### P1. Run and install silently reuse stale or incomplete bundles

- Evidence. `scripts/deployment.sh:111-113` accepts any executable plus `Info.plist`.
  `scripts/run_widget.sh:7-11` and `scripts/install_launch_agent.sh:7-9` skip packaging
  when that predicate succeeds. It does not require the helper, resources, valid
  signature, or correspondence to current source. `README.md:129-130` tells agents
  to check, then run/install, without a mandatory packaging step.
- Why it hurts. After changing source, a green check followed by the documented install
  can relaunch yesterday's app. A pre-sidecar or partial bundle also passes. The helper
  resolver needs an executable helper (`Sources/LocalModelWidget/FeedSupervisor.swift:35-38`),
  and the pet needs its page (`Sources/LocalModelWidget/PetLayer.swift:35-39`).
- Concrete fix. Make artifact reuse explicit. Report source/build identity and validate
  helper, resource manifest, plist, and signature before reuse. Offer a documented
  rebuild path that includes dirty source bytes in its identity, rather than HEAD alone.
- Blast radius. Run/install semantics and agent verification. Keep intentional reuse
  available without rebuilding on every login. Test old, missing-helper, missing-page,
  and changed-source bundles independently.

### P1. The privacy scan excludes paths and binary contents

- Evidence. `scripts/publish.sh:74-76` scans only diff lines starting with `+`, excluding
  `+++` headers, plus commit messages. New filenames occur in excluded headers or
  diff metadata. Git's binary-difference message does not start with `+`.
- Why it hurts. An otherwise generic file with a private project name in its filename
  passes the text filter. A screenshot containing private thread text also passes.
  This repository tracks raster/media assets, so the gap matters to agent-produced
  evidence as well as source. The scan is narrower than the rule in `AGENTS.md:18`.
- Concrete fix. Scan added/renamed paths separately with NUL-safe parsing. Require an
  explicit reviewed media manifest for new binary assets, with provenance and a
  privacy check. Keep the text scan and fail visibly on unreviewed binary additions.
- Blast radius. Publication and pre-push checks. Existing pet models, sounds, and media
  need a reviewed baseline. Do not remove approved assets or publish private allowlists.

### P1. A multi-commit push can hide private text in intermediate history

- Evidence. `scripts/publish.sh:65-72` checks every new commit's identities, but
  `scripts/publish.sh:75` scans only the net base-to-tip diff for content.
  `.githooks/pre-push:7-10` passes arbitrary pushed ranges to that checker.
- Why it hurts. With noreply identities, commit A can add a private term and commit B
  can remove it. The net diff contains no term, but the pushed history retains A.
  The intended single-commit publisher avoids this case. The general pre-push guard
  does not enforce that topology.
- Concrete fix. Inspect each introduced commit's paths/content, or require exactly the
  approved single-parent publication shape for origin updates. Add a fixture where
  the tip is clean but an intermediate commit contains a private term.
- Blast radius. Hook acceptance and `--check` callers, including new branches. Preserve
  public ancestry, noreply identities, and the single squashed publication workflow.

### P2. LaunchAgent replacement has no recovery after a failed bootstrap

- Evidence. `scripts/install_launch_agent.sh:14-21` overwrites the installed plist,
  ignores bootout errors, and then bootstraps/enables/kickstarts under `set -e`.
  `scripts/uninstall_launch_agent.sh:7-9` ignores both lifecycle errors before removing
  the plist. Shared wrappers are in `scripts/deployment.sh:119-140`.
- Why it hurts. A bootstrap failure after successful bootout leaves the service down
  and the previous plist overwritten. Conversely, a failed bootout during uninstall
  can leave a running service after its configuration was removed.
- Concrete fix. Validate a staged plist before replacement. Distinguish an absent job
  from other launchctl errors, preserve previous configuration, restore on failed
  activation, and verify the resulting loaded/unloaded state. Retain raw exit codes.
- Blast radius. Login startup, disabled state, rollback, and explicit uninstall.
  Test absent, loaded, disabled, and bootstrap-failure cases using isolated paths and
  a launchctl test adapter before any real service drill.

### P2. The required check does not validate the packaged release artifact

- Evidence. `scripts/check_widget.sh:8-10` lints temporary rendered plists, runs debug
  `ModelWidgetChecks`, then builds debug products. Release copying/signing occurs
  only in `scripts/package_app.sh:8-24`, which never runs the checks. Resources are
  optional at packaging time (`scripts/package_app.sh:18-21`).
- Why it hurts. A green required check does not prove that release packaging contains
  the helper and pet assets, or that the resulting signed bundle is usable. Missing
  Resources can still produce a successfully signed bundle.
- Concrete fix. Add a non-installing artifact verification mode using an isolated
  output directory. Check both release binaries, required assets, generated metadata,
  and signature. Exercise it as a distinct packaging gate and keep the existing
  check command's role clear. Fail packaging if required resources are absent.
- Blast radius. Build time, fixture setup, and release verification. Never point this
  gate at the active outputs bundle. A runtime screenshot/feed check remains separate.

## Existing publish flow, precisely

1. `scripts/publish.sh:22-29` always uses this checkout and local `main`. It does not
   publish the current branch, index, or dirty working tree. Its public identity is
   fixed in the script. It does not require a clean tree or run the widget checks.
2. Normal and `--dry-run` modes both fetch `origin main`, resolve `origin/main`, and
   compare its tree with local `main` (`scripts/publish.sh:90-94`). Equal trees exit
   without creating a publication commit.
3. An explicit first message argument wins. Otherwise, it reads the public base's
   `Published-from` trailer, uses that local commit as a log boundary if resolvable,
   and takes at most 20 non-merge subjects. Without a usable trailer it takes the
   latest 20 from `main` (`scripts/publish.sh:96-102`).
4. It appends a short local-main SHA as `Published-from`, then uses `git commit-tree`
   with the exact main tree and public base as its sole parent. Both author and
   committer use the configured noreply identity (`scripts/publish.sh:103-106`).
   No local branch is advanced by this operation.
5. `check_range` requires base ancestry and noreply author/committer emails. It learns
   private terms from home paths, hostnames, local author email, and Projects names.
   Projects names shorter than five characters, this repo's own name, dictionary words,
   and names already mentioned in the public base are exempt. `PUBLISH_PROJECTS_DIR`
   overrides the directory (`scripts/publish.sh:28,33-76`).
6. `--dry-run` prints the generated commit and stat after scanning, then exits. It
   still fetches and writes a commit object. It is not an offline, zero-write preview
   (`scripts/publish.sh:91,105-108`). It does not package, install, or push.
7. Normal mode pushes the generated commit SHA to `origin`'s `refs/heads/main` with
   no force flag (`scripts/publish.sh:109`). A remote race can reject that push.
   Local `main` remains private and distinct from the public history.
8. `--check BASE TIP` takes a separate early branch with no fetch or commit creation
   (`scripts/publish.sh:85-88`). An empty base enumerates commits not already reachable
   from origin refs (`scripts/publish.sh:61`). This is not a widget build check.
9. `.githooks/pre-push:5-10` scans each non-deletion update and skips deletion updates.
   It ignores remote identity and ref names. It is a scan, not proof that the publisher
   was used. It requires `core.hooksPath=.githooks`, which is configured here but is
   clone-local (`AGENTS.md:17`). No tracked clone setup installs that configuration.

## Canon and boundaries that must survive fixes

- Keep the separate, app-supervised sidecar, bundled in `Contents/Helpers`, with
  `--parent-pid`, single-instance behavior, and standalone support. Do not patch T3
  (`docs/pet-status-spec.md:7,61-74`). Do not introduce a second login helper by accident.
- Keep app identity, saved settings, pairing data, and feed discovery compatible.
  A packaging or backup operation must not copy private support data into public assets.
- Preserve forehead starts, positive-evidence swallowing, no settled display or belly
  glow, nearby questions/errors, and activity caps (`docs/pet-status-spec.md:9-23,145-149`).
  App/helper restart or unavailable T3 must not become a finish signal (`AGENTS.md:23`).
- Preserve approved defaults and operations. The owner's private
  roadmap records timestamped backup,
  newest-two retention, seeds/queue on, the question nod, and acceptable startup delay.
- The status spec supersedes the proposal's environment parts
  (`docs/pet-status-spec.md:3-7`). This audit does not authorize an environment redesign.
  The upcoming full-desktop phase in the brief requires its own updated scope.
- Keep publication through `scripts/publish.sh` only, with private local history,
  a public-base parent, and noreply identity (`AGENTS.md:7,17`). A build or install is
  not publication permission. Do not replace this workflow with a direct main push.

## Verification and limits

Read tracked scripts, package manifest, agent/product/design instructions, the relevant
spec sections, roadmap decisions, and helper/resource consumers. `bash -n` passed for
`scripts/*.sh` and `.githooks/pre-push`. Current hooksPath is `.githooks`.
No deployment/publish tests were found by searching `Tests` for deployment, package_app,
publish.sh, launch.agent, Info.plist, or backup.

No build, packaging, install, launchctl, publish mode, network call, or app execution was
run. No contents of `outputs/`, backups, or the installed app were inspected or changed.
Actual backup count, installed version, signature health, and live launch state are
unknown. Existing untracked media were left alone.

Prove It Works shaped verification of the actual report and its cited source paths.
Blast-radius analysis stopped at source tracing under the read-only restriction.
Recommended failure drills above remain unrun.
