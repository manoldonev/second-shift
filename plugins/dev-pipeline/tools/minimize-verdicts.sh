#!/usr/bin/env bash
# minimize-verdicts.sh — collapse a PR's earlier verdict comments as outdated, so the one that binds
# is the one a human sees expanded (#946). Shared by both posting paths: run.sh calls it once a
# verdict binds, the manual /dev-pipeline:review calls it after its verdict comment is posted.
#
# Usage:
#   GH=<gh or the bot wrapper> minimize-verdicts.sh [--repo <owner/name>] <pr> <kept-comment-id>
#
# A verdict comment is one whose first line is exactly `verdict: approve` or `verdict: needs-work`
# (run.sh verdict()'s predicate). Minimized: every such comment on the PR posted before the kept one
# (a lower comment id) by a lane author — a Bot, or the account $GH writes as (run.sh's B10 filter).
# A stranger's verdict-shaped comment, every notice and the kept comment itself are left alone.
# Minimize, never edit or delete: the history stays one click away.
#
# Writes go through $GH only (default: gh); a failure is reported, never retried as another identity.
#
# Exit: 0 every earlier verdict minimized (or none to minimize) · 1 the comments could not be read,
# the kept id is not a lane verdict, or a minimize failed (stderr names each) · 2 usage.
# stdout: one line per comment minimized, `minimized <id>`.
set -uo pipefail

GH="${GH:-gh}"
REPO=""
[ "${1:-}" = --repo ] && { REPO="${2:-}"; shift 2; }
PR="${1:-}"; KEPT="${2:-}"
case "$PR$KEPT" in *[!0-9]*|"") echo "usage: minimize-verdicts.sh [--repo <owner/name>] <pr> <kept-comment-id>" >&2; exit 2 ;; esac
[ -n "$PR" ] && [ -n "$KEPT" ] || { echo "usage: minimize-verdicts.sh [--repo <owner/name>] <pr> <kept-comment-id>" >&2; exit 2; }

if [ -z "$REPO" ]; then
  REPO="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || { echo "the repo slug could not be read" >&2; exit 1; }
fi
me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
raw="$("$GH" api "repos/$REPO/issues/$PR/comments" --paginate 2>/dev/null)" || { echo "the comments of PR #$PR could not be read" >&2; exit 1; }
# --paginate may print one array per page: flatten whatever arrived into one
comments="$(printf '%s' "$raw" | jq -s '[.[][]]' 2>/dev/null)" || { echo "the comments of PR #$PR could not be parsed" >&2; exit 1; }

# shellcheck disable=SC2016  # $me and $k are jq variables
lane_verdicts='.[] | select((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))
  | select(((.body // "") | split("\n")[0] | sub("\r$";"")) | test("^verdict: (approve|needs-work)$"))'
printf '%s' "$comments" | jq -e --arg me "$me" --argjson k "$KEPT" "[$lane_verdicts | select(.id == \$k)] | length > 0" >/dev/null \
  || { echo "comment $KEPT is not a lane verdict on PR #$PR — nothing minimized" >&2; exit 1; }
targets="$(printf '%s' "$comments" | jq -r --arg me "$me" --argjson k "$KEPT" "$lane_verdicts | select(.id < \$k) | \"\(.id)\t\(.node_id)\"")"

rc=0
while IFS=$'\t' read -r id node; do
  [ -n "$id" ] || continue
  # shellcheck disable=SC2016  # $id is a GraphQL variable, not a shell one
  if err="$("$GH" api graphql -f query='mutation($id: ID!) { minimizeComment(input: {subjectId: $id, classifier: OUTDATED}) { minimizedComment { isMinimized } } }' -f id="$node" 2>&1 >/dev/null)"; then
    echo "minimized $id"
  else
    echo "comment $id NOT minimized — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)" >&2; rc=1
  fi
done <<EOF
$targets
EOF
exit "$rc"
