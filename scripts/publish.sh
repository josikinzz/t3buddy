#!/usr/bin/env bash
# The one way to publish to the public GitHub repo (origin).
#
# This checkout's history is private: commits carry the machine's hostname email and once
# carried real project names. The public repo has its own history, one squashed commit per
# publish, authored by the GitHub noreply identity. Never push main to origin.
#
#   scripts/publish.sh ["message"]   commit main's tree onto origin/main as one noreply
#                                    commit, scan it, and push it (message defaults to the
#                                    subjects of the local commits since the last publish)
#   scripts/publish.sh --dry-run ["message"]
#                                    the same, but print the commit instead of pushing it
#   scripts/publish.sh --check BASE TIP
#                                    scan the commits in BASE..TIP (BASE may be empty for
#                                    a new branch); .githooks/pre-push runs this on every push
#
# The scan learns what is private from this machine instead of a tracked list (which would
# itself publish it): the home path, user name, hostnames, the local git email, and the
# names of folders in ~/Projects that the public tree doesn't already mention.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBLIC_NAME="josikinzz"
PUBLIC_EMAIL="108291224+josikinzz@users.noreply.github.com"
SOURCE_BRANCH="main"
PROJECTS_DIR="${PUBLISH_PROJECTS_DIR:-$HOME/Projects}"
EMPTY_TREE="$(git hash-object -t tree /dev/null)"

fail() { printf 'publish: %s\n' "$*" >&2; exit 1; }

private_terms() {   # one fixed string per line; $1 = the public base the push builds on
  local base="$1" user host email name
  user="$(id -un)"
  printf '%s\n' "$HOME" "/Users/$user"
  for host in "$(scutil --get LocalHostName 2>/dev/null || true)" "$(scutil --get ComputerName 2>/dev/null || true)" "$(hostname -s)"; do
    [ -n "$host" ] && printf '%s\n' "$host"
  done
  email="$(git var GIT_AUTHOR_IDENT | sed -E 's/.*<([^>]*)>.*/\1/')"
  case "$email" in *@users.noreply.github.com) ;; *) printf '%s\n' "$email" ;; esac
  [ -d "$PROJECTS_DIR" ] || return 0
  for name in "$PROJECTS_DIR"/*; do
    name="$(basename "$name")"; name="${name%.*}"
    [ "${#name}" -ge 5 ] || continue
    [ "$name" = "$(basename "$ROOT")" ] && continue
    grep -qixF -e "$name" /usr/share/dict/words 2>/dev/null && continue   # an ordinary word
    # Already public, so not a new leak (and not a false alarm on ordinary words).
    if [ -n "$base" ] && git grep -qiwF -e "$name" "$base" -- . 2>/dev/null; then continue; fi
    printf '%s\n' "$name"
  done
}

check_range() {   # $1 = public base (may be empty), $2 = tip
  local base="$1" tip="$2" commits problems="" terms added hits commit ident
  if [ -n "$base" ]; then
    git cat-file -e "$base^{commit}" 2>/dev/null || fail "unknown public commit $base; run git fetch origin first"
    git merge-base --is-ancestor "$base" "$tip" || fail "$tip rewrites the public history at $base. Publish with scripts/publish.sh, which builds on origin/main; never force-push."
    commits="$(git rev-list "$base..$tip")"
  else
    commits="$(git rev-list "$tip" --not --remotes=origin)"
  fi
  [ -n "$commits" ] || return 0

  for commit in $commits; do
    for ident in "$(git show -s --format='%ae' "$commit")" "$(git show -s --format='%ce' "$commit")"; do
      case "$ident" in
        *@users.noreply.github.com) ;;
        *) problems+="  $(git show -s --format='%h %s' "$commit" | cut -c1-80): identity <$ident>"$'\n' ;;
      esac
    done
  done

  terms="$(private_terms "$base" | grep -v '^$' || true)"
  # Each commit's own diff, not only the net one: a term added in one commit and removed in the
  # next is still in the history that gets pushed.
  added="$( { git diff --no-color "${base:-$EMPTY_TREE}" "$tip" | grep -E '^\+' | grep -vE '^\+\+\+ ' || true; }
    for commit in $commits; do
      { git diff-tree --no-color -r -p -m --root --no-commit-id "$commit" | grep -E '^\+' | grep -vE '^\+\+\+ ' || true; }
      git show -s --format='%B' "$commit"
    done)"
  hits="$(printf '%s\n' "$added" | grep -oiwF -f <(printf '%s\n' "$terms") | sort -fu || true)"
  [ -n "$hits" ] && problems+="$(printf '  private term: %s\n' $hits)"$'\n'

  # Added and renamed file names are scanned too (NUL-separated, so any name is safe). An
  # underscore counts as a separator here, since a file name rarely has a space between words.
  local path path_hits
  for commit in $commits; do
    while IFS= read -r -d '' path; do
      path_hits="$(printf '%s\n' "${path//_/ }" | grep -oiwF -f <(printf '%s\n' "$terms") | sort -fu || true)"
      [ -n "$path_hits" ] && problems+="$(printf '  private term in a file name (%s): %s\n' "$(git show -s --format='%h' "$commit")" "$(printf '%s' "$path_hits" | tr '\n' ' ')")"$'\n'
    done < <(git diff-tree -r -z --name-only --diff-filter=AR -M -m --root --no-commit-id "$commit")
  done

  [ -z "$problems" ] && return 0
  printf 'publish: refusing to publish %s..%s:\n%s' "${base:0:7}" "${tip:0:7}" "$problems" >&2
  printf 'Publish with scripts/publish.sh (noreply identity, one squashed commit); remove private terms from the tree first.\n' >&2
  exit 1
}

if [ "${1:-}" = "--check" ]; then
  check_range "${2:-}" "${3:?--check needs BASE TIP}"
  exit 0
fi

dry_run=""; [ "${1:-}" = "--dry-run" ] && { dry_run=1; shift; }
git fetch --quiet origin main
base="$(git rev-parse origin/main)"
tree="$(git rev-parse "$SOURCE_BRANCH^{tree}")"
[ "$tree" != "$(git rev-parse "$base^{tree}")" ] || { echo "publish: origin/main already matches $SOURCE_BRANCH"; exit 0; }

message="${1:-}"
if [ -z "$message" ]; then
  since="$(git log -1 --format='%(trailers:key=Published-from,valueonly)' "$base" | tr -d '[:space:]')"
  range="$SOURCE_BRANCH"; [ -n "$since" ] && git cat-file -e "$since^{commit}" 2>/dev/null && range="$since..$SOURCE_BRANCH"
  message="$(git log --no-merges -n 20 --format='%s' "$range")"
  [ -n "$message" ] || fail "no message; pass one: scripts/publish.sh \"what changed\""
fi
message+=$'\n\n'"Published-from: $(git rev-parse --short "$SOURCE_BRANCH")"

commit="$(GIT_AUTHOR_NAME="$PUBLIC_NAME" GIT_AUTHOR_EMAIL="$PUBLIC_EMAIL" GIT_COMMITTER_NAME="$PUBLIC_NAME" GIT_COMMITTER_EMAIL="$PUBLIC_EMAIL" \
  git commit-tree "$tree" -p "$base" -m "$message")"
check_range "$base" "$commit"
if [ -n "$dry_run" ]; then git show --stat --format="%h %an <%ae>%n%n%B" "$commit"; exit 0; fi
git push origin "$commit:refs/heads/main"
echo "publish: origin/main is now $(git rev-parse --short "$commit")"
