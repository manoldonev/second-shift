#!/usr/bin/env bash
# claim-issue.sh — atomically swap `ready-for-dev` -> `in-progress` on a GitHub
# issue, REST two-call form, with the silent-failed-add guard.
#
# Single source of truth for the claim swap (was inline model-executed
# prose in SKILL.md / stages/1-intake.md). Extracting it removes the
# transcription-error surface #170 hardened and gives the failed-add abort path an
# automated regression test (#183, claim-selftest.sh) — which #170's AC#3 could not
# satisfy while the swap was prose.
#
# Scope: the REST two-call fallback ONLY (the path live when the Projects-classic
# GraphQL deprecation breaks `gh issue edit` — see SKILL.md "Canonical REST forms").
# The single-call atomic `gh issue edit --add-label in-progress --remove-label
# ready-for-dev` form is inherently safe (one API call, no intermediate zero-label
# window, no confirm step) and stays a documented one-line alternative — not here.
#
# Why add-before-remove AND confirm-before-remove (SKILL.md "Label-swap ordering
# rule"): removing `ready-for-dev` first leaves a crash window where the issue
# carries neither label — invisible to the queue AND unclaimed (silently lost).
# Adding first fixes the ordering; but a SILENTLY-failed add (e.g. a dropped
# `--input -` -> HTTP 422) followed by a successful remove reaches the same
# zero-label window. So we confirm `in-progress` is in the add response body
# BEFORE issuing the `ready-for-dev` DELETE.
#
# Usage:
#   claim-issue.sh <ISSUE_NUMBER>
#
# Env:
#   GH_BOT / tracker.bot.envVar — optional override for the wrapper path; resolved
#             by tools/gh-bot.sh (the single ladder). Injectable so the selftest can
#             substitute a mock wrapper (claim-selftest.sh) under a bot-enabled config.
#   SECOND_SHIFT_CONFIG / SECOND_SHIFT_REPO_ROOT — forwarded to gh-bot.sh.
#
# Exit codes (the contract claim-selftest.sh and the prose call-sites pin):
#   0  claimed       — `in-progress` added AND `ready-for-dev` removed.
#   1  aborted       — the add did not apply; `ready-for-dev` left intact (no DELETE
#                      issued). This is a bare stop: nothing was mutated to undo.
#   2  usage error   — no issue number.
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible (the selftest
# runs there).

set -uo pipefail

ISSUE="${1:-}"; shift || true
# Label vocabulary (config tracker.labels; #11) — the caller passes the resolved
# names, defaulting to the shipped queue/claimed labels when omitted.
QUEUE_LABEL="ready-for-dev"
CLAIMED_LABEL="in-progress"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue)   QUEUE_LABEL="${2:-}"; shift 2 ;;
    --claimed) CLAIMED_LABEL="${2:-}"; shift 2 ;;
    *) echo "[claim-issue] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  echo "[claim-issue] usage: claim-issue.sh <issue-number>" >&2
  exit 2
fi

# Single resolver (#92) — no private ladder. Mock seam: set the env var named by
# tracker.bot.envVar (default GH_BOT) under a bot-enabled SECOND_SHIFT_CONFIG.
_RESOLVER="$(cd "$(dirname "$0")" && pwd)/gh-bot.sh"
if [[ ! -f "$_RESOLVER" ]]; then
  echo "[claim-issue] gh-bot.sh not found at $_RESOLVER" >&2
  exit 1
fi
GH_BOT="$(bash "$_RESOLVER" --path)" || {
  echo "[claim-issue] bot wrapper unresolved (see gh-bot --status)" >&2
  exit 1
}

# 1. ADD the claimed label; capture the resulting label-name array (the add-labels
#    POST returns the issue's full label set; `--jq '[.[].name]'` reduces it to names).
ADDED=$(jq -nc --arg l "$CLAIMED_LABEL" '{labels: [$l]}' \
  | "$GH_BOT" api -X POST "repos/{owner}/{repo}/issues/$ISSUE/labels" --input - --jq '[.[].name]')

# 2. Confirm the add applied BEFORE removing the queue label. The decision is the
#    response-body CONTENT (does it contain the claimed label?), not the HTTP status —
#    an empty body, a 422 error object, or any array lacking the label all abort.
if [[ "$ADDED" == *"\"$CLAIMED_LABEL\""* ]]; then
  :  # add confirmed — safe to remove the queue label
else
  echo "[claim-issue] '$CLAIMED_LABEL' add did not apply ($ADDED) — aborting, leaving '$QUEUE_LABEL' intact" >&2
  exit 1
fi

# 3. Remove the queue label.
"$GH_BOT" api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/$QUEUE_LABEL"

echo "[claim-issue] claimed #$ISSUE ('$CLAIMED_LABEL' added, '$QUEUE_LABEL' removed)"
