#!/usr/bin/env bash
# second-shift-unclaim.sh — release the pipeline's claimed label when a tracker item
# closes. Committed into a consumer repo by /second-shift:onboard, and run by this
# repo's own `issues: [closed]` workflow straight out of the marketplace checkout.
#
# THE GAP THIS FILLS. The claimed label is added at claim (claim-issue.sh) and was
# removed by nothing. The lane's step-9 prose said the session drops it, but milestone 5
# requires an OPEN pr, so it runs strictly pre-merge — the one moment the label is
# CORRECT. The stale window opens at merge, when the pr's closing reference closes the
# item and no session is running to notice. So the release is bound to the close event
# instead: deterministic, session-free, and it also covers a hand-closed item.
#
# LABEL RESOLUTION. The name is config-driven, and the config is not always readable
# from CI: the marketplace repo gitignores its own (it carries machine-local bot
# identifiers). So resolution is live-when-readable, default-when-not — a consumer repo
# commits its config and gets the configured name; the marketplace repo falls through to
# the shipped default, which is its real label. Nothing is substituted at install time,
# so there is no rendered copy to drift.
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
#   0  released, or a stated no-op (no claimed label vocabulary; item never claimed;
#      the label lost a race and was already gone).
#   1  a real failure — the issue's labels could not be read, or the removal failed for
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
    say "FAIL: $tool is not on PATH — cannot resolve or release the claimed label"
    exit 1
  fi
done

ROOT="${SECOND_SHIFT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
CONFIG="${SECOND_SHIFT_CONFIG:-$ROOT/.claude/second-shift.config.json}"

# Same shape as lean-gate.sh's resolver, deliberately: an absent, unparseable or
# key-less config yields the shipped default rather than an error.
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
  say "no-op: tracker.type is '$TRACKER_TYPE' — the claimed label is github-only vocabulary"
  exit 0
fi

LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
say "claimed label resolves to '$LABEL' on issue #$ISSUE"

# Read before writing. An item that was never claimed is the COMMON case, so it must be
# a real no-op — not a write whose error we agree to tolerate afterwards.
ERRF="$(mktemp)"
if ! LABELS_JSON="$(gh api "repos/{owner}/{repo}/issues/$ISSUE/labels" 2>"$ERRF")"; then
  say "FAIL: could not read the labels on issue #$ISSUE — $(head -1 "$ERRF" 2>/dev/null)"
  rm -f "$ERRF"
  exit 1
fi
rm -f "$ERRF"

if ! printf '%s' "$LABELS_JSON" | jq -e --arg l "$LABEL" 'map(.name) | index($l) != null' >/dev/null 2>&1; then
  say "no-op: issue #$ISSUE does not carry '$LABEL' — nothing to release"
  exit 0
fi

# Percent-encode: a configured label may contain a space or a slash, and the label is a
# PATH segment here. Encoding it is what makes a multi-word label removable at all.
ENCODED="$(jq -rn --arg s "$LABEL" '$s|@uri')"
ERRF="$(mktemp)"
if gh api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/$ENCODED" >/dev/null 2>"$ERRF"; then
  say "released '$LABEL' from issue #$ISSUE"
  rm -f "$ERRF"
  exit 0
fi

# The read above and this delete are not one atomic operation, so a concurrent removal
# lands here. That is the same outcome we wanted, not a failure.
if grep -qiE 'HTTP 404|Not Found|Label does not exist' "$ERRF" 2>/dev/null; then
  say "no-op: '$LABEL' was already gone from issue #$ISSUE — removed between the read and the delete"
  rm -f "$ERRF"
  exit 0
fi

say "FAIL: could not remove '$LABEL' from issue #$ISSUE — $(head -1 "$ERRF" 2>/dev/null)"
rm -f "$ERRF"
exit 1
