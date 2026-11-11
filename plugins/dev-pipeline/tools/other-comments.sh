#!/usr/bin/env bash
# other-comments.sh — counts a PR's comments by authors other than the lane, as of a given time, for
# verdict-join.sh's --other-comments flag.
#
# Usage:
#   GH=<gh> other-comments.sh [--repo <owner/name>] [-C <dir>] <pr> <at> <out-file>
#
# Counted: issue comments and inline review comments created at or before <at>, and reviews submitted at or before
# it whose body is not empty (an empty one only wraps its inline comments). Not counted: the login $GH reads as, and
# <appName>[bot] whenever tracker.bot.app.appName resolves, as bot-commit.sh resolves it from <dir> (default: .).
# <at> is ISO-8601 UTC, the form of GitHub's times, so the two compare as strings.
#
# Exit: 0 {at, total, by_author} written to <out-file> · 1 a read failed (stderr names it), and <out-file> does not
# exist, so no 0 stands for a failure · 2 usage.
set -uo pipefail

GH="${GH:-gh}"
REPO="" DIR="."
usage() { echo "usage: other-comments.sh [--repo <owner/name>] [-C <dir>] <pr> <at> <out-file>" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2 ;;
    -C) [ $# -ge 2 ] || usage; DIR="$2"; shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] || usage
PR="$1" AT="$2" OUT="$3"
case "$PR" in ''|*[!0-9]*) usage ;; esac
[[ "$AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || usage
rm -f "$OUT"
fail() { echo "other-comments: $*" >&2; exit 1; }

MAIN_ROOT=""
if [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then MAIN_ROOT="$SECOND_SHIFT_REPO_ROOT"
elif common="$(cd "$DIR" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"; then MAIN_ROOT="$(cd "$DIR" && cd "$common" && cd .. && pwd)"; fi
CFG=""
for c in "${SECOND_SHIFT_CONFIG:-}" "$DIR/.claude/second-shift.config.json" "${MAIN_ROOT:+$MAIN_ROOT/.claude/second-shift.config.json}"; do
  [ -n "$c" ] && [ -f "$c" ] && { CFG="$c"; break; }
done
APP=""
[ -z "$CFG" ] || APP="$(jq -r '.tracker.bot.app.appName // empty' "$CFG" 2>/dev/null)"
LOCAL="${MAIN_ROOT:+$MAIN_ROOT/.claude/second-shift.config.local.json}"
if [ -n "$LOCAL" ] && [ -f "$LOCAL" ]; then l="$(jq -r '.tracker.bot.app.appName // empty' "$LOCAL" 2>/dev/null)"; [ -z "$l" ] || APP="$l"; fi
BOT=""; [ -z "$APP" ] || BOT="${APP}[bot]"

if [ -z "$REPO" ]; then
  REPO="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" && [ -n "$REPO" ] || fail "the repo slug could not be read"
fi
ME="$("$GH" api user --jq .login 2>/dev/null)" && [ -n "$ME" ] || fail "the login of the gh it reads with could not be read"

logins() { # logins <api path> <time field> <true when an empty body is not counted>
  local raw
  raw="$("$GH" api "$1" --paginate 2>/dev/null)" || return 1
  # --paginate prints one array per page
  printf '%s' "$raw" | jq -sr --arg at "$AT" --arg f "$2" --argjson nb "$3" '
    if length > 0 and all(.[]; type == "array") then add[] else error("not a list") end
    | select((.[$f] | type) == "string" and .[$f] <= $at)
    | select(($nb | not) or ((.body // "") | test("\\S")))
    | .user.login // "ghost"'
}
IC="$(logins "repos/$REPO/issues/$PR/comments" created_at false)" || fail "the issue comments of PR #$PR could not be read"
RC="$(logins "repos/$REPO/pulls/$PR/comments" created_at false)" || fail "the inline review comments of PR #$PR could not be read"
RV="$(logins "repos/$REPO/pulls/$PR/reviews" submitted_at true)" || fail "the reviews of PR #$PR could not be read"

tmp="$OUT.tmp.$$"
printf '%s\n%s\n%s\n' "$IC" "$RC" "$RV" | jq -Rsc --arg at "$AT" --arg me "$ME" --arg bot "$BOT" '
  split("\n") | map(select(. != "" and . != $me and . != $bot))
  | {at: $at, total: length, by_author: (group_by(.) | map({key: .[0], value: length}) | from_entries)}' > "$tmp" \
  && mv "$tmp" "$OUT" || { rm -f "$tmp"; fail "the count could not be written to $OUT"; }
