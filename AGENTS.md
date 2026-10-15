# Agents working in this repo

A macOS dashboard plus T3boii, a 3D desk pet in a WKWebView (`Resources/Pet/*.js`). Read
`DESIGN.md` before any visible change and `PRODUCT.md` for what it is for.

- Check: `scripts/check_widget.sh` (all checks, then the app build). It must be green before a merge.
- Publish to GitHub: `scripts/publish.sh` (`--dry-run` to preview). Nothing else pushes.

## Rules and what enforces them

When the owner corrects you, fix the mistake and add its rule here. If the rule was already
here and nothing enforces it, that is a repeat: enforce it in the same change. Drop a rule
once its mistake can't happen.

| Rule | Enforced by |
|---|---|
| This checkout's history is private. Publish only with `scripts/publish.sh`, which squashes `main`'s tree onto `origin/main` as one noreply-authored commit. Never push `main` or force-push to `origin`. | `.githooks/pre-push` runs `scripts/publish.sh --check`: it refuses a history rewrite, any non-noreply identity, and private terms. Needs `git config core.hooksPath .githooks` in each clone. |
| Demo and test data use generic names (`demo-app`, `docs-site`, `/Users/tester`), never the owner's real projects, paths, emails or hostnames. | The same scan, at publish time: home path, user name, hostnames, local git email, and `~/Projects` folder names the public tree doesn't already mention. |
| Anything that shakes, shivers, shudders or purrs uses `tremble(t, rate)` from `Resources/Pet/motion.js`. | `PetMotionChecks`: fails any raw `Math.sin(t * N)` faster than `TREMBLE_MAX_RATE` in the pet scripts. |
| Everything that comes out of T3boii is 3D and lit like him. No flat vector stickers, speech bubbles or tooltips. | Nothing; judgment. See `DESIGN.md`, Desk Pet. Check it with a screenshot. |
| Do exactly what was asked. A demo uses only animations that already exist. | Nothing; judgment. |
