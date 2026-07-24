#!/usr/bin/env bash
# slice-scope.sh — graded-AC-union derivation for the stacked-PR slice partition.
#
# Usage: slice-scope.sh <state-path> [--slice N]
#
# Reads the state file's Stage-1 AC->slice partition (`decomposition.slices[]`,
# see state-schema.md "Stacked-PR AC partition") and emits, for slice N
# (default: the state's `currentSlice`), the graded scope: the union of acIds
# for slices 1..N (the stacked branch contains slices 1..N cumulatively, so
# grading the union against a diff anchored at slice 1's base stays honest).
#
# Output (stdout):
#   line 1  — integrity verdict: `ok` | `no-partition` | `union-mismatch`
#   line 2+ — the graded AC ids, one per line (only when the verdict is `ok`)
#
# Verdicts:
#   ok             — partition present and its acIds union equals the
#                    acceptanceCriteria[] snapshot id set; graded ids follow.
#   no-partition   — state carries no decomposition.slices (or no snapshot):
#                    the run is not slice-scoped; consumers keep full-ticket
#                    behavior.
#   union-mismatch — partition present but its union does NOT equal the
#                    snapshot id set (missing or unknown AC). Slice-scoping is
#                    VOID for the run — consumers fall back to full-ticket
#                    grading (fail-closed: degradation grades more, never less).
#
# The reviewer-side half of the integrity contract (snapshot vs the AC set
# derived from the live issue body) cannot be checked here — no tracker access
# by design; scope-completeness-reviewer performs it per its inline copy.
#
# Consumers: Stage 8 scope-gate slice mode (stages/8-code-review.md) and
# scenario-liveness-selftest.sh (its stacked-prs scenario).
#
# Exit: 0 on any verdict (a verdict is data, not an error), 2 on usage/IO error.
set -euo pipefail

STATE="${1:-}"
SLICE_ARG=""
[[ -n "$STATE" ]] || { echo "slice-scope: usage: slice-scope.sh <state-path> [--slice N]" >&2; exit 2; }
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slice) SLICE_ARG="${2:-}"; shift 2 ;;
    *) echo "slice-scope: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[[ -f "$STATE" ]] || { echo "slice-scope: state file not found: $STATE" >&2; exit 2; }
jq empty "$STATE" 2>/dev/null || { echo "slice-scope: unparseable state file: $STATE" >&2; exit 2; }
if [[ -n "$SLICE_ARG" ]]; then
  [[ "$SLICE_ARG" =~ ^[1-9][0-9]*$ ]] || { echo "slice-scope: --slice must be a positive integer, got '$SLICE_ARG'" >&2; exit 2; }
fi

jq -r --arg n "$SLICE_ARG" '
  (.decomposition.slices // []) as $slices
  | (.acceptanceCriteria // [] | map(.id)) as $snap
  | if ($slices | length) == 0 or ($snap | length) == 0 then
      "no-partition"
    elif ([$slices[].acIds[]] | sort | unique) != ($snap | sort | unique) then
      "union-mismatch"
    else
      (if $n == "" then (.currentSlice // ($slices | length)) else ($n | tonumber) end) as $cur
      | "ok", ([$slices[] | select(.slice <= $cur) | .acIds[]] | .[])
    end
' "$STATE"
