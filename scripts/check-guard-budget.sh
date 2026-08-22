#!/usr/bin/env bash
# check-guard-budget.sh — PR-time guard: guard/test shell mass stays under its ratcheting
# ceiling (#641, Phase 0 of the 2026-08-22 backlog recalibration).
#
# THE PROBLEM THIS CATCHES. docs/pipeline-manifesto.md's P2/P3 gate every growth principle
# mechanically and P4/P5 ("as much as it takes, and none more" / "every word earns its place")
# not at all — the document says so in its own text, calling itself "a judgment aid... not
# itself a gate". Nothing anywhere caps how much guard/test shell the tree carries. This is the
# mechanical counterpart: a committed ceiling (tools/guard-budget.tsv) that a PR cannot cross
# without either deleting guard mass elsewhere or raising the ceiling in the open, with a reason.
#
# THE CLASSIFICATION. A .sh file counts as guard/test when its basename matches `*-selftest.sh`,
# `check-*.sh` or `*-lint.sh`, or it is a lean-gate.sh (`*/skills/*/lean-gate.sh`), or it is one
# of the named standing-guard entry points: run-selftests.sh, mutation-sweep.sh, gate-ablation.sh.
# Product shell not matching any of those is "the rest" and is never counted. Both this script
# and its selftest read the SAME classify() function, so a fixture in the selftest is provably
# testing the rule this gate actually enforces.
#
# THE TWO CHECKS:
#   1. measured guard/test mass at HEAD > the committed ceiling  -> red, naming the overage.
#   2. the committed ceiling rose since the PR's merge-base with no reason column recorded
#      alongside the raise -> red. A ceiling that only ever went down needs no reason; a raise
#      does, so the escape hatch for a genuinely new guard stays visible at review.
# A ceiling measuring OVER the tree (guard mass shrank) is not an error — it prints an advisory
# naming the lower value an operator can ratchet down as an ordinary reviewed edit (see the
# ratchet note in tools/guard-budget.tsv and this PR's "Known trades").
#
# Usage: check-guard-budget.sh <base-ref>   (e.g. origin/main)
# Exit 0 = under ceiling (possibly with an advisory); 1 = over ceiling, or ceiling raised with no
#          reason; 2 = usage/environment error.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

BASE="${1:?usage: check-guard-budget.sh <base-ref>}"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "[guard-budget] cannot resolve merge-base of $BASE and HEAD" >&2; exit 2; }

TSV="tools/guard-budget.tsv"
[ -f "$TSV" ] || { echo "[guard-budget] no ceiling recorded at $TSV" >&2; exit 2; }

# classify() is the single source of truth for "guard/test .sh" — the header above and the
# selftest both describe exactly this predicate, nothing narrower or broader.
classify() { # classify <root> — every guard/test .sh path under root, one per line
  find "$1" -type f \( \
      -name '*-selftest.sh' -o \
      -name 'check-*.sh' -o \
      -name '*-lint.sh' -o \
      -path '*/skills/*/lean-gate.sh' -o \
      -name 'run-selftests.sh' -o \
      -name 'mutation-sweep.sh' -o \
      -name 'gate-ablation.sh' \
    \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
}

measure() { # measure <root> — total line count across classify()'s files under root
  classify "$1" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l | tr -d ' '
}

# ceiling_row <tsv-path> — prints "ceiling<TAB>reason" for the first non-comment, non-blank
# data row. Empty output means the file carries no data row (unreadable / not yet committed).
ceiling_row() {
  awk -F'\t' '
    /^[ \t]*#/ { next }
    { gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 == "") next; print $1 "\t" $3; exit }
  ' "$1" 2>/dev/null
}

HEAD_ROW="$(ceiling_row "$TSV")"
[ -n "$HEAD_ROW" ] || { echo "[guard-budget] $TSV carries no data row" >&2; exit 2; }
HEAD_CEILING="${HEAD_ROW%%$'\t'*}"
HEAD_REASON="${HEAD_ROW#*$'\t'}"
case "$HEAD_CEILING" in ''|*[!0-9]*) echo "[guard-budget] $TSV ceiling column '$HEAD_CEILING' is not a number" >&2; exit 2 ;; esac

# The raise-without-reason check: only meaningful when a prior committed ceiling exists.
BASE_TSV_CONTENT="$(git show "$MERGE_BASE:$TSV" 2>/dev/null)" || BASE_TSV_CONTENT=""
if [ -n "$BASE_TSV_CONTENT" ]; then
  BASE_ROW="$(printf '%s\n' "$BASE_TSV_CONTENT" | ceiling_row /dev/stdin)"
  BASE_CEILING="${BASE_ROW%%$'\t'*}"
  case "$BASE_CEILING" in ''|*[!0-9]*) BASE_CEILING="" ;; esac
  if [ -n "$BASE_CEILING" ] && [ "$HEAD_CEILING" -gt "$BASE_CEILING" ] && [ -z "$(printf '%s' "$HEAD_REASON" | tr -d '[:space:]')" ]; then
    echo "[guard-budget] ✗ $TSV ceiling raised from $BASE_CEILING to $HEAD_CEILING with no reason recorded — a raise needs a stated reason in the same diff (docs/plans/second-shift-641-lean.md)." >&2
    exit 1
  fi
fi

MEASURED="$(measure .)"

if [ "$MEASURED" -gt "$HEAD_CEILING" ]; then
  echo "[guard-budget] ✗ guard/test shell is over budget: measured $MEASURED lines, ceiling $HEAD_CEILING (over by $((MEASURED - HEAD_CEILING)))." >&2
  echo "[guard-budget]   Delete guard mass, or raise $TSV's ceiling in the open with a reason." >&2
  exit 1
fi

if [ "$MEASURED" -lt "$HEAD_CEILING" ]; then
  echo "[guard-budget] under budget: measured $MEASURED lines, ceiling $HEAD_CEILING. Advisory: ratchet $TSV down to $MEASURED when convenient — a lowered ceiling needs no reason, but raising it back does, in the same diff."
else
  echo "[guard-budget] at budget: measured $MEASURED lines, ceiling $HEAD_CEILING."
fi
exit 0
