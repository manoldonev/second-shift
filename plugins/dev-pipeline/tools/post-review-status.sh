#!/usr/bin/env bash
# post-review-status.sh — the manual /dev-pipeline:review's `second-shift/review` commit status, posted only
# on a verdict body that passes verdict-check.sh (#991). run.sh checks the body it bound before its own
# status post; this is the same gate for the session that posts by hand.
#
# Usage:
#   GH=<gh or the bot wrapper> post-review-status.sh [--repo <owner/name>] <pr> <sha> <body-file> \
#       <record-at-head> <record-at-first> <target-url>
#   GH=<gh or the bot wrapper> post-review-status.sh [--repo <owner/name>] --recheck <comment-id> <pr> <sha> \
#       <record-at-head> <record-at-first> <target-url>
#
# Re-runs the checker on the POSTED body. A passing body posts `success` (approve) or `failure`
# (needs-work) on <sha> under context `second-shift/review`, linking <target-url>. A failing body posts
# nothing and prints the failed rules. It does nothing else: minimizing earlier verdicts, the head
# re-check and `gh pr ready` stay with the session.
#
# --recheck is for a verdict comment edited after it was posted: the body is read by comment id through
# $GH, then checked as above. There a failing body, or an approve's red plan coverage, posts `error` on
# <sha> instead of nothing, so the status no longer attests a body that changed under it; the
# description names the first failed rule.
#
# An approve is also held to the plan's AC coverage (#1039 D-10): plan-coverage.sh beside this script runs
# on <record-at-first> and the plan beside <record-at-head> (`<x>-decisions.md` → `<x>-plan.md`, the
# checked-out head's), with <record-at-head> as its `--head` so an AC added after the baseline
# under a recorded departure counts (#1085), and a red one posts nothing, as a body that breaks
# a rule does. Not-applicable (a record with no Test intent, a ticket with no AC block) posts as before. A
# needs-work posts `failure` whatever the coverage. On this path a session runs it, not the scheduler: it
# binds a merge only where branch protection requires `second-shift/review`.
#
# Writes go through $GH only (default: gh); a failure is reported, never retried as another identity.
#
# Exit: 0 posted · 1 the body breaks a rule, or an approve's plan coverage is red (stdout: the failed rules
# or the coverage report; nothing posted, or `error` under --recheck) · 2 usage, or a check could not
# evaluate, or under --recheck the comment could not be read (nothing posted) · 3 a post failed (stderr:
# gh's error).
set -uo pipefail

GH="${GH:-gh}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=""
RECHECK=""
[ "${1:-}" = --repo ] && { REPO="${2:-}"; shift 2; }
usage() {
  echo "usage: post-review-status.sh [--repo <owner/name>] <pr> <sha> <body-file> <record-at-head> <record-at-first> <target-url>" >&2
  echo "       post-review-status.sh [--repo <owner/name>] --recheck <comment-id> <pr> <sha> <record-at-head> <record-at-first> <target-url>" >&2
  exit 2
}
if [ "${1:-}" = --recheck ]; then
  [ $# -eq 7 ] || usage
  RECHECK="$2"; case "$RECHECK" in ''|*[!0-9]*) usage ;; esac
  PR="$3"; SHA="$4"; BODY=""; set -- "$3" "$4" "" "$5" "$6" "$7"
else
  [ $# -eq 6 ] || usage
  PR="$1"; SHA="$2"; BODY="$3"
fi
URL="$6"
case "$PR" in ''|*[!0-9]*) usage ;; esac
case "$SHA" in ''|*[!0-9a-f]*) usage ;; esac
[ -n "$URL" ] || usage

repo_slug() {
  [ -n "$REPO" ] && return 0
  REPO="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
  [ -n "$REPO" ]
}
post() { # post <state> <description>
  local err
  if ! err="$("$GH" api -X POST "repos/$REPO/statuses/$SHA" -f "state=$1" -f "context=second-shift/review" -f "target_url=$URL" -f "description=$2" 2>&1 >/dev/null)"; then
    echo "second-shift/review NOT posted on $SHA — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)" >&2; exit 3
  fi
  echo "second-shift/review=$1 posted on $SHA"
}
refuse() { # refuse <first failed rule>: nothing on the plain path, `error` under --recheck; exit 1 either way
  [ -n "$RECHECK" ] || exit 1
  repo_slug || { echo "second-shift/review NOT posted on $SHA: the repo slug could not be read" >&2; exit 3; }
  local d="re-check failed: $1"
  post error "${d:0:140}"
  exit 1
}

if [ -n "$RECHECK" ]; then
  repo_slug || { echo "second-shift/review NOT posted on $SHA: the repo slug could not be read, so comment $RECHECK was not read" >&2; exit 2; }
  BODY="$(mktemp "${TMPDIR:-/tmp}/post-review-status.XXXXXX")" || exit 2
  trap 'rm -f "$BODY"' EXIT
  if ! err="$("$GH" api "repos/$REPO/issues/comments/$RECHECK" --jq .body 2>&1 > "$BODY")"; then
    echo "second-shift/review NOT posted on $SHA: comment $RECHECK could not be read — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)" >&2; exit 2
  fi
fi

rules="$(bash "$HERE/verdict-check.sh" "$BODY" "$4" "$5")"; rc=$?
case "$rc" in
  0) : ;;
  1) echo "second-shift/review NOT posted on $SHA: the verdict breaks these rules of the verdict grammar:"; printf '%s\n' "$rules" | sed 's/^/- /'; refuse "$(printf '%s\n' "$rules" | head -n 1)" ;;
  *) echo "second-shift/review NOT posted on $SHA: the verdict could not be checked (verdict-check.sh exit $rc)" >&2; exit 2 ;;
esac

case "$(head -n 1 "$BODY" | tr -d '\r')" in
  "verdict: approve")    state=success; desc="approved at this head — see the verdict" ;;
  "verdict: needs-work") state=failure; desc="needs-work at this head — see the verdict" ;;
  *) echo "second-shift/review NOT posted on $SHA: line 1 of $BODY is not a verdict line" >&2; exit 2 ;;
esac
if [ "$state" = success ]; then
  plan="${4%-decisions.md}-plan.md"   # beside the record, as run.sh places it (D-4)
  cov="$(bash "$HERE/plan-coverage.sh" --head "$4" "$5" "$plan" 2>&1)"; rc=$?
  case "$rc" in
    0|3) : ;;
    1) echo "second-shift/review NOT posted on $SHA: the approve's plan coverage is red (plan-coverage.sh, the record at its first commit, the record at the head and $plan):"; printf '%s\n' "$cov" | sed 's/^/- /'
       refuse "$(printf '%s\n' "$cov" | grep -m 1 'RED' || printf 'plan coverage is red')" ;;
    *) echo "second-shift/review NOT posted on $SHA: the plan coverage could not be checked (plan-coverage.sh exit $rc): $(printf '%s' "$cov" | tr '\n' ' ' | cut -c1-300)" >&2; exit 2 ;;
  esac
fi
repo_slug || { echo "second-shift/review NOT posted on $SHA: the repo slug could not be read" >&2; exit 3; }
post "$state" "$desc"
