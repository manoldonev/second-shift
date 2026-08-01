#!/usr/bin/env bash
# tracker-reconcile-check.sh — resume-time reconcile check for a non-terminal pipeline
# state file (second-shift#149). Pure logic: no network, no `gh`, no statectl reads.
#
# A run can die in the Stage-9 tail (after `gh pr create`, before `pr-add` /
# `mark-completed`), leaving `.claude/pipeline-state/{issue}.json` at `status:
# in_progress` even though the tracker already shows the issue closed via a merged PR.
# That is not corruption — the file accurately records where the session stopped — but
# resuming into stage work on an issue that already shipped is wrong, and the stale file
# also pollutes perf-retro's corpus (it still has a `stages` object and isn't yet
# `*-released-*`).
#
# SKILL.md "Resume logic" rule 2 (`status: in_progress`) owns the one tracker read —
#
#   gh issue view <issue> --json closed,closedByPullRequestsReferences \
#     --jq '[(.closed|tostring), (.closedByPullRequestsReferences[0].number // ""|tostring), \
#            (.closedByPullRequestsReferences[0].url // "")] | @tsv'
#
# — and feeds the result plus the state file's own `.status` into this tool's `verdict`
# mode, mirroring predecessor-gate.sh's extract/verdict split so the selftest and the
# liveness scenario run with zero network and nothing to mock.
#
# Usage:
#   tracker-reconcile-check.sh verdict <run-status> <tracker-closed> [<pr-number> <pr-url>]
#
# <run-status>:      exactly one of  in_progress | completed | failed  (case-sensitive)
# <tracker-closed>:  exactly one of  true | false                      (case-sensitive)
# <pr-number> <pr-url>: the tracker's `closedByPullRequestsReferences[0]`, if any.
#                        Both required together; supplying exactly one is a usage error.
#
# Verdicts (all print `verdict=<value>` on stdout; reconcile-recommended additionally
# prints `closingPrNumber=<n>` and `closingPrUrl=<u>`):
#
#   not-applicable         run-status is completed|failed — nothing to reconcile.
#   resume-normal          run-status is in_progress and either the tracker isn't
#                           closed, or it's closed without a linked/merging PR — resume
#                           `currentStage` exactly as today.
#   reconcile-recommended  run-status is in_progress AND the tracker is closed AND a
#                           closing PR is named — the caller should quarantine via
#                           `statectl reclaim <issue> --release`, post one comment
#                           naming the PR and stating no eval/report was synthesized,
#                           and STOP rather than resume stage work.
#
# Exit:
#   0  not-applicable or resume-normal.
#   2  usage error (unknown mode, missing/unknown run-status or tracker-closed value,
#      exactly one of the PR pair given, stray args) — never a silent resume-normal.
#   4  reconcile-recommended.
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible (the selftest
# drift-check runs there).

set -uo pipefail

MODE="${1:-}"

usage() {
  echo "[tracker-reconcile-check] usage: tracker-reconcile-check.sh verdict <in_progress|completed|failed> <true|false> [<pr-number> <pr-url>]" >&2
}

case "$MODE" in
  verdict)
    RUN_STATUS="${2:-}"
    TRACKER_CLOSED="${3:-}"
    PR_NUMBER="${4:-}"
    PR_URL="${5:-}"

    if [[ $# -gt 5 ]]; then
      echo "[tracker-reconcile-check] verdict takes at most 4 arguments; got: ${*:2}" >&2
      exit 2
    fi

    case "$RUN_STATUS" in
      completed|failed)
        echo "verdict=not-applicable"
        exit 0
        ;;
      in_progress)
        : # fall through to tracker-closed handling below
        ;;
      "")
        echo "[tracker-reconcile-check] verdict requires a run-status argument (in_progress|completed|failed)" >&2
        exit 2
        ;;
      *)
        echo "[tracker-reconcile-check] unknown run-status: '$RUN_STATUS' (want in_progress|completed|failed)" >&2
        exit 2
        ;;
    esac

    case "$TRACKER_CLOSED" in
      true|false)
        : # valid
        ;;
      "")
        echo "[tracker-reconcile-check] verdict requires a tracker-closed argument (true|false)" >&2
        exit 2
        ;;
      *)
        echo "[tracker-reconcile-check] unknown tracker-closed value: '$TRACKER_CLOSED' (want true|false)" >&2
        exit 2
        ;;
    esac

    # Two independent presence checks, not a single line pairing both directions: a
    # paired one-line OR of the two negated tests mutates into its own logical converse
    # under a whole-line flag swap (OR is commutative across the two symmetric clauses)
    # — a semantic no-op that no selftest could ever kill.
    pr_number_set=false
    [[ -n "$PR_NUMBER" ]] && pr_number_set=true
    pr_url_set=false
    [[ -n "$PR_URL" ]] && pr_url_set=true
    if [[ "$pr_number_set" != "$pr_url_set" ]]; then
      echo "[tracker-reconcile-check] pr-number and pr-url must be given together (got number='$PR_NUMBER' url='$PR_URL')" >&2
      exit 2
    fi

    if [[ "$TRACKER_CLOSED" == "true" && -n "$PR_NUMBER" ]]; then
      echo "verdict=reconcile-recommended"
      echo "closingPrNumber=$PR_NUMBER"
      echo "closingPrUrl=$PR_URL"
      exit 4
    fi

    echo "verdict=resume-normal"
    exit 0
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    echo "[tracker-reconcile-check] unknown mode: '$MODE'" >&2
    usage
    exit 2
    ;;
esac
