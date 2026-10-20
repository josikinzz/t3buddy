#!/usr/bin/env bash
# Runs `publish.sh --check` against throwaway repos with a made-up private project name, and
# fails unless it refuses what it must refuse and passes a clean range. It touches nothing but
# a temp folder: no fetch, no push, no real project names.
#
#   scripts/publish_check_drill.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/publish-drill.XXXXXX")"
trap 'rm -rf "$work"' EXIT

TERM_NAME="zorbquux"
mkdir -p "$work/projects/$TERM_NAME"
export PUBLISH_PROJECTS_DIR="$work/projects"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=tester GIT_COMMITTER_NAME=tester
export GIT_AUTHOR_EMAIL=1+tester@users.noreply.github.com GIT_COMMITTER_EMAIL=1+tester@users.noreply.github.com

repo="$work/repo"
git init -q -b main "$repo"
mkdir "$repo/scripts"
cp "$SCRIPT_DIR/publish.sh" "$repo/scripts/publish.sh"
cd "$repo"

commit() { git add -A && git commit -q -m "$1"; }
check() { ./scripts/publish.sh --check "$1" "$2" 2>"$work/err"; }
failures=0
expect_refused() {   # $1 = name, $2 = base, $3 = tip, $4 = text the refusal must contain
  if check "$2" "$3"; then
    echo "FAIL $1: the range was accepted"; failures=$((failures + 1))
  elif grep -q "$4" "$work/err"; then
    echo "PASS $1"
  else
    echo "FAIL $1: refused without saying '$4'"; cat "$work/err"; failures=$((failures + 1))
  fi
}
expect_accepted() {
  if check "$2" "$3"; then echo "PASS $1"; else echo "FAIL $1: refused"; cat "$work/err"; failures=$((failures + 1)); fi
}

echo "demo-app" > README.md
commit "Start demo-app"
base="$(git rev-parse HEAD)"

echo "a second line about demo-app" >> README.md
commit "Describe demo-app"
expect_accepted "a clean range passes" "$base" "$(git rev-parse HEAD)"

git checkout -q -b added-then-removed "$base"
echo "see $TERM_NAME for details" >> README.md
commit "Add a note"
git revert --no-edit HEAD >/dev/null
expect_refused "a term added in one commit and removed in the next is caught" "$base" "$(git rev-parse HEAD)" "private term: $TERM_NAME"
[ -z "$(git diff "$base" HEAD)" ] || { echo "FAIL fixture: the tip should equal the base tree"; failures=$((failures + 1)); }

git checkout -q -b term-in-name "$base"
echo "x" > "notes-$TERM_NAME.txt"
commit "Add a file"
expect_refused "a file name containing a term is caught" "$base" "$(git rev-parse HEAD)" "private term in a file name"

git checkout -q -b renamed-and-gone "$base"
echo "x" > "$TERM_NAME.txt"
commit "Add a file"
git rm -q "$TERM_NAME.txt"
commit "Remove it again"
expect_refused "a file added in one commit and deleted in the next is caught" "$base" "$(git rev-parse HEAD)" "private term in a file name"

git checkout -q -b renamed "$base"
git mv README.md "${TERM_NAME}_readme.md"
commit "Rename the readme"
expect_refused "a rename to a name containing a term is caught" "$base" "$(git rev-parse HEAD)" "private term in a file name"

git checkout -q -b odd-names "$base"
printf 'x' > "$(printf 'two\nlines.txt')"
printf 'x' > "a b (1).txt"
commit "Add files with unusual names"
expect_accepted "unusual but clean file names pass" "$base" "$(git rev-parse HEAD)"

git checkout -q -b not-noreply "$base"
echo "more" >> README.md
git add -A
GIT_AUTHOR_EMAIL=someone@example.com git commit -q -m "Wrong identity"
expect_refused "a non-noreply identity is still refused" "$base" "$(git rev-parse HEAD)" "identity"

git checkout -q main
published="$(git rev-parse main)"
git checkout -q -b rewrites "$base"
echo "different" > README.md
commit "Different second commit"
expect_refused "a rewrite of the public history is still refused" "$published" "$(git rev-parse HEAD)" "rewrites the public history"

if [ "$failures" -ne 0 ]; then echo "$failures drill check(s) failed"; exit 1; fi
echo "publish --check drill passed"
