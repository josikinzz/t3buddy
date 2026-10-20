#!/usr/bin/env bash
# The one verify command. `--full` (the merge gate) adds the T3 restart drill.
#   scripts/verify.sh [--full] [NAME]   NAME runs only the checks and tests whose name contains it
#   (plain text, any case); a NAME that matches nothing fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/deployment.sh"
cd "$ROOT"

full=0
filter=""
for arg in "$@"; do
  case "$arg" in
    --full) full=1 ;;
    -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "verify: unknown option $arg" >&2; exit 2 ;;
    *) filter="$arg" ;;
  esac
done

command -v node >/dev/null || { echo "verify: node is required for the pet tests (Tests/Pet)" >&2; exit 2; }

summary=()
stage() {
  local name="$1"; shift
  local started=$SECONDS
  echo "== $name"
  local status=0
  "$@" || status=$?
  summary+=("$(printf '%-12s %3ss  exit %s' "$name" $((SECONDS - started)) "$status")")
  if [[ $status -ne 0 ]]; then
    printf '%s\n' "${summary[@]}"
    echo "verify: $name failed" >&2
    exit "$status"
  fi
}

# Every file AGENTS.md names must exist, so its map cannot drift from the tree.
agent_map() {
  local files missing=0 name
  files="$(git ls-files; find Tests/Pet -name '*.mjs' 2>/dev/null)"
  for name in $(grep -oE '`[A-Za-z0-9_./*-]+\.(swift|js|mjs|md|sh|py)`|`(Sources|Resources|Tests|scripts|docs)/[^` ]*`' AGENTS.md | tr -d '`' | sort -u); do
    if [[ "$name" =~ ^(Sources|Resources|Tests|scripts|docs)/ ]]; then
      compgen -G "$name" >/dev/null && continue
    else
      local pattern="${name//./\\.}"
      grep -qE "(^|/)${pattern//\*/[^/]*}\$" <<<"$files" && continue
    fi
    echo "AGENTS.md names $name, which is not in the tree"
    missing=1
  done
  return $missing
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift_checks() {
  "$DEPLOYMENT_BUILD_DIR/debug/ModelWidgetChecks" ${filter:+"$filter"} | tee "$work/checks.log"
  return "${PIPESTATUS[0]}"
}

# Node reads a name pattern as a regex; escaping NAME and adding /i gives Swift's plain, any-case match.
pet_tests() {
  local pattern=()
  if [[ -n "$filter" ]]; then pattern=(--test-name-pattern="/$(printf '%s' "$filter" | sed 's/[][\\.*^$?+(){}|/]/\\&/g')/i"); fi
  node --test ${pattern[@]+"${pattern[@]}"} --test-reporter=spec --test-reporter-destination=stdout \
    --test-reporter=tap --test-reporter-destination="$work/pet.tap" 'Tests/Pet/*.test.mjs'
}

# Filtered out tests are absent from the TAP, and a file none of whose tests ran shows as one
# result named after the file.
matched() {
  local swift pet
  swift="$(sed -nE 's/^All ([0-9]+) checks matching.*/\1/p' "$work/checks.log")"
  pet="$(grep -E '^ *(not )?ok [0-9]+ - ' "$work/pet.tap" | grep -cvE '\.test\.mjs$' || true)"
  echo "$(( ${swift:-0} + pet ))"
}

stage plists deployment_check_generated_plists
stage map agent_map
stage publish scripts/publish_check_drill.sh
stage build swift build --scratch-path "$DEPLOYMENT_BUILD_DIR"
stage checks swift_checks
stage pet pet_tests
if [[ $full -eq 1 ]]; then
  stage drill python3 scripts/t3_restart_drill.py "$DEPLOYMENT_BUILD_DIR/debug/t3boii-feed"
fi

printf '%s\n' "${summary[@]}"
if [[ -n "$filter" ]]; then
  count="$(matched)"
  [[ $count -gt 0 ]] || { echo "verify: no check or test name contains \"$filter\"" >&2; exit 1; }
  echo "verify: passed, $count checks and tests matching \"$filter\" (not a merge gate)"
elif [[ $full -eq 1 ]]; then
  echo "verify: all passed, restart drill included (merge gate)"
else
  echo "verify: all passed (run --full before a merge)"
fi
