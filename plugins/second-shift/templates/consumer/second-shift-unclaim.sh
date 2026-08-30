#!/usr/bin/env bash
# second-shift-unclaim.sh — release the pipeline's run-state labels when a tracker item
# closes. Committed into a consumer repo by /second-shift:onboard, and run by this
# repo's own `issues: [closed]` workflow straight out of the marketplace checkout.
#
# THE GAP THIS FILLS. The claimed label is added at claim (claim-issue.sh) and was
# removed by nothing. The lane's step-9 prose said the session drops it, and no session can
# reliably be there to: the label goes stale when the ITEM CLOSES, and nothing guarantees a
# lane session is running at that moment — the pr's closing reference can close the item long
# after close-out finished, and a hand-closed item never had a session at all. So the release
# is bound to the close event instead: deterministic, session-free, and it covers both.
#
# WHICH LABELS. The two RUN-STATE roles, claimed and queue. The queue label is normally
# dropped by the claim swap, but a crashed swap leaves it on an item that then closes,
# and that is the same leftover state. The blockers list is deliberately NOT touched: it
# holds `epic`, a permanent classification rather than run state, and a hardcoded `epic`
# exception against a consumer-redefinable list would silently miss.
#
# LABEL RESOLUTION. The names are config-driven, and the config is not always readable
# from CI: the marketplace repo gitignores its own (it carries machine-local bot
# identifiers). So resolution is live-when-readable, default-when-not — a consumer repo
# commits its config and gets the configured names; the marketplace repo falls through to
# the shipped defaults, which are its real labels. Nothing is substituted at install
# time, so there is no rendered copy to drift.
#
# Usage:
#   second-shift-unclaim.sh <issue-number>
#
# Env:
#   GH_TOKEN                 forwarded to gh (the workflow passes the job token).
#   GH_REPO                  the owner/repo gh resolves the placeholders against.
#   SECOND_SHIFT_CONFIG      override the resolved config path (the selftest seam).
#   SECOND_SHIFT_REPO_ROOT   override the repo root used to find the config.
#
# Exit codes (the contract second-shift-unclaim-selftest.sh pins):
#   0  released, or a stated no-op (no label vocabulary applies; the item carried
#      neither label; a label lost a race and was already gone).
#   1  a real failure — the issue's labels could not be read, or a removal failed for
#      a reason other than the label being absent. A broken token must surface here
#      rather than pass as "nothing to do".
#   2  usage error — no issue number, or one that is not a number.
#
# macOS ships /bin/bash 3.2 as the stock shell and the selftest runs there; this file
# stays 3.2-compatible. No `set -e`: the arms below decide their own exits.
set -uo pipefail

say() { echo "[second-shift-unclaim] $1"; }

ISSUE="${1:-}"
case "$ISSUE" in
  ''|*[!0-9]*)
    echo "[second-shift-unclaim] usage: second-shift-unclaim.sh <issue-number>" >&2
    exit 2
    ;;
esac

# Both are preinstalled on ubuntu-latest. Missing either is a loud failure, never a
# silent skip: guessing the tracker vocabulary here could write to a tracker that
# declares it takes no writes.
for tool in jq gh; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    say "FAIL: $tool is not on PATH — cannot resolve or release the run-state labels"
    exit 1
  fi
done

ROOT="${SECOND_SHIFT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
CONFIG="${SECOND_SHIFT_CONFIG:-$ROOT/.claude/second-shift.config.json}"

# Same shape as lean-gate.sh's resolver, deliberately: an absent, unparseable or
# key-less config yields the shipped default rather than an error.
#
# THE MARKETPLACE REPO ITSELF HAS NO READABLE CONFIG HERE — it gitignores its own,
# because that file carries machine-local bot identifiers — so its workflow runs entirely
# on these defaults, and nothing reconciles them against the real vocabulary. The failure
# is silent but low-cost and self-announcing: rename a label away from a default and this
# stops stripping it, whose symptom is exactly the stale label this script exists to
# clear, visible on the very next close. A consumer repo commits its config and is
# resolved live, so this applies to the canary alone.
cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

WRITES="$(cfg '.tracker.writes' 'true')"
if [ "$WRITES" = "false" ]; then
  say "no-op: tracker.writes is false — this tracker takes no writes"
  exit 0
fi

TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
if [ "$TRACKER_TYPE" != "github" ]; then
  say "no-op: tracker.type is '$TRACKER_TYPE' — the label roles are github-only vocabulary"
  exit 0
fi

CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
say "run-state labels resolve to '$CLAIMED_LABEL' and '$QUEUE_LABEL' on issue #$ISSUE"

# Read once, before writing anything. An item carrying neither label is the COMMON case,
# so it must be a real no-op — not two writes whose errors we agree to tolerate after.
ERRF="$(mktemp)"
if ! LABELS_JSON="$(gh api "repos/{owner}/{repo}/issues/$ISSUE/labels" 2>"$ERRF")"; then
  say "FAIL: could not read the labels on issue #$ISSUE — $(head -1 "$ERRF" 2>/dev/null)"
  rm -f "$ERRF"
  exit 1
fi
rm -f "$ERRF"

release_one() { # release_one <label> -> 0 released or stated no-op, 1 real failure
  local label="$1" encoded errf
  if ! printf '%s' "$LABELS_JSON" | jq -e --arg l "$label" 'map(.name) | index($l) != null' >/dev/null 2>&1; then
    say "no-op: issue #$ISSUE does not carry '$label' — nothing to release"
    return 0
  fi
  # Percent-encode: a configured label may contain a space or a slash, and the label is
  # a PATH segment here. Encoding it is what makes a multi-word label removable at all.
  encoded="$(jq -rn --arg s "$label" '$s|@uri')"
  errf="$(mktemp)"
  if gh api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/$encoded" >/dev/null 2>"$errf"; then
    say "released '$label' from issue #$ISSUE"
    rm -f "$errf"
    return 0
  fi
  # The read above and this delete are not one atomic operation, so a concurrent removal
  # lands here. That is the same outcome we wanted, not a failure.
  if grep -qiE 'HTTP 404|Not Found|Label does not exist' "$errf" 2>/dev/null; then
    say "no-op: '$label' was already gone from issue #$ISSUE — removed between the read and the delete"
    rm -f "$errf"
    return 0
  fi
  say "FAIL: could not remove '$label' from issue #$ISSUE — $(head -1 "$errf" 2>/dev/null)"
  rm -f "$errf"
  return 1
}

# Both are always attempted and the exit is worst-wins: a token that can remove one label
# but not the other is a half-cleared issue, and skipping the second on the first failure
# would hide half of it.
FAILED=0
release_one "$CLAIMED_LABEL" || FAILED=1
release_one "$QUEUE_LABEL" || FAILED=1
exit "$FAILED"
