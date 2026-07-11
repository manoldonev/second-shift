#!/usr/bin/env bash
# claim-issue.sh — atomically swap `ready-for-dev` -> `in-progress` on a GitHub
# issue, REST two-call form, with the silent-failed-add guard.
#
# Single source of truth for the Stage 1.A claim swap (was inline model-executed
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
#   GH_BOT  — the bot wrapper invoked for the writes. When unset, defaults to
#             $HOME/.config/<consumer-repo-dir-basename>/gh-as-bot.sh (the path
#             install-gh-bot.sh provisions; SECOND_SHIFT_REPO_ROOT overrides the
#             root the basename derives from). Injectable so the selftest can
#             substitute a mock wrapper (claim-selftest.sh).
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

ISSUE="${1:-}"

# Resolve the bot wrapper path. An explicit GH_BOT always wins (the selftest's
# mock seam). Otherwise, config tracker.bot.wrapperPath wins (the explicit path
# install-gh-bot.sh also writes to — reader/writer agree, closing the "derived
# wrong once" gap). Else derive $HOME/.config/<consumer-repo-dir-basename>/gh-as-bot.sh
# — the path install-gh-bot.sh provisions by default. The basename comes from the
# consumer repo root: SECOND_SHIFT_REPO_ROOT if set, else the main checkout derived
# from `git rev-parse --git-common-dir` (worktree-safe). Falls back to $HOME/.config
# if no root can be resolved (never in normal Stage-1 use, which runs in-repo).
if [[ -z "${GH_BOT:-}" ]]; then
  _root="${SECOND_SHIFT_REPO_ROOT:-}"
  if [[ -z "$_root" ]]; then
    _common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    [[ -n "$_common" ]] && _root="$(dirname "$(cd "$_common" && pwd)")"
  fi
  _cfg="${SECOND_SHIFT_CONFIG:-${_root:+$_root/.claude/second-shift.config.json}}"
  _wrap=""
  if [[ -n "$_cfg" && -f "$_cfg" ]] && command -v jq >/dev/null; then
    _wrap="$(jq -r '.tracker.bot.wrapperPath // empty' "$_cfg" 2>/dev/null)"
  fi
  if [[ -n "$_wrap" ]]; then
    GH_BOT="${_wrap/#\~/$HOME}"
  elif [[ -n "$_root" ]]; then
    GH_BOT="$HOME/.config/$(basename "$_root")/gh-as-bot.sh"
  else
    GH_BOT="$HOME/.config/gh-as-bot.sh"
  fi
fi

if [[ -z "$ISSUE" ]]; then
  echo "[claim-issue] usage: claim-issue.sh <issue-number>" >&2
  exit 2
fi

# 1. ADD `in-progress`; capture the resulting label-name array (the add-labels POST
#    returns the issue's full label set; `--jq '[.[].name]'` reduces it to names).
ADDED=$(echo '{"labels":["in-progress"]}' \
  | "$GH_BOT" api -X POST "repos/{owner}/{repo}/issues/$ISSUE/labels" --input - --jq '[.[].name]')

# 2. Confirm the add applied BEFORE removing the queue label. The decision is the
#    response-body CONTENT (does it contain `in-progress`?), not the HTTP status —
#    an empty body, a 422 error object, or any array lacking the label all abort.
case "$ADDED" in
  *'"in-progress"'*) ;;  # add confirmed — safe to remove the queue label
  *)
    echo "[claim-issue] in-progress add did not apply ($ADDED) — aborting, leaving ready-for-dev intact" >&2
    exit 1
    ;;
esac

# 3. Remove `ready-for-dev`.
"$GH_BOT" api -X DELETE "repos/{owner}/{repo}/issues/$ISSUE/labels/ready-for-dev"

echo "[claim-issue] claimed #$ISSUE (in-progress added, ready-for-dev removed)"
