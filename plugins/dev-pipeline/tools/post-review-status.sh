#!/usr/bin/env bash
# post-review-status.sh — the manual /dev-pipeline:review's `second-shift/review` commit status, posted only
# on a verdict body that passes verdict-check.sh (#991). run.sh checks the body it bound before its own
# status post; this is the same gate for the session that posts by hand.
#
# Usage:
#   GH=<gh or the bot wrapper> post-review-status.sh [--repo <owner/name>] <pr> <sha> <body-file> \
#       <record-at-head> <record-at-first> <target-url>
#
# Re-runs the checker on the POSTED body. A passing body posts `success` (approve) or `failure`
# (needs-work) on <sha> under context `second-shift/review`, linking <target-url>. A failing body posts
# nothing and prints the failed rules. It does nothing else: minimizing earlier verdicts, the head
# re-check and `gh pr ready` stay with the session.
#
# Writes go through $GH only (default: gh); a failure is reported, never retried as another identity.
#
# Exit: 0 posted · 1 the body breaks a rule (stdout: the failed rules; nothing posted) · 2 usage, or the
# checker could not evaluate (nothing posted) · 3 the post itself failed (stderr: gh's error).
set -uo pipefail

GH="${GH:-gh}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=""
[ "${1:-}" = --repo ] && { REPO="${2:-}"; shift 2; }
usage() { echo "usage: post-review-status.sh [--repo <owner/name>] <pr> <sha> <body-file> <record-at-head> <record-at-first> <target-url>" >&2; exit 2; }
[ $# -eq 6 ] || usage
PR="$1"; SHA="$2"; BODY="$3"; URL="$6"
case "$PR" in ''|*[!0-9]*) usage ;; esac
case "$SHA" in ''|*[!0-9a-f]*) usage ;; esac
[ -n "$URL" ] || usage

rules="$(bash "$HERE/verdict-check.sh" "$BODY" "$4" "$5")"; rc=$?
case "$rc" in
  0) : ;;
  1) echo "second-shift/review NOT posted on $SHA: the verdict breaks these rules of the verdict grammar:"; printf '%s\n' "$rules" | sed 's/^/- /'; exit 1 ;;
  *) echo "second-shift/review NOT posted on $SHA: the verdict could not be checked (verdict-check.sh exit $rc)" >&2; exit 2 ;;
esac

case "$(head -n 1 "$BODY" | tr -d '\r')" in
  "verdict: approve")    state=success; desc="approved at this head — see the verdict" ;;
  "verdict: needs-work") state=failure; desc="needs-work at this head — see the verdict" ;;
  *) echo "second-shift/review NOT posted on $SHA: line 1 of $BODY is not a verdict line" >&2; exit 2 ;;
esac
if [ -z "$REPO" ]; then
  REPO="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || { echo "second-shift/review NOT posted on $SHA: the repo slug could not be read" >&2; exit 3; }
fi
if ! err="$("$GH" api -X POST "repos/$REPO/statuses/$SHA" -f "state=$state" -f "context=second-shift/review" -f "target_url=$URL" -f "description=$desc" 2>&1 >/dev/null)"; then
  echo "second-shift/review NOT posted on $SHA — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)" >&2; exit 3
fi
echo "second-shift/review=$state posted on $SHA"
