#!/usr/bin/env bash
# score-review.sh — deterministic, model-free scorer for the seeded-defect review harness.
#
# WHY THIS EXISTS: after the StructuredOutput-stall fix converts dispatchers, the stall
# count is trivially zero and proves nothing. The real acceptance question is "did the cure
# lobotomize the reviewer?" — and that must be MEASURED, not asserted. This scorer is the
# measurement: it takes a reviewer's findings (JSON) and the planted-mutant manifest, and
# reports which planted defects the review detected, which it missed, and how many
# false-positive lines it produced against the precision traps. Detection parity against a
# recorded baseline is the shipping gate for every stall-cure PR; a survived planted
# blocker (mutation-testing vocabulary: the mutant outlived the test) fails acceptance.
#
# The scorer itself costs zero tokens and runs in CI (its selftest is model-free); the
# token-costing part — dispatching real reviewers over the fixture plan — is operator-run
# via stall-probe.mjs, and this script scores the captured output.
#
# INPUT
#   $1  findings JSON — either {findings:[...]} or a bare [...] array. Finding fields are
#       read tolerantly: severity, file, title, description|message|claim.
#   $2  manifest TSV (default: review-harness-fixtures/review-harness-manifest.tsv):
#       id  kind(detect|precision)  class  regexA  regexB  note
#       detect rows:    DETECTED when ONE finding line matches regexA AND regexB (grep -Ei)
#       precision rows: every finding line matching regexA AND regexB is a FALSE POSITIVE
#
# OUTPUT (machine-parseable, one line per row + summary):
#   mutant <id> <class>: DETECTED|MISSED
#   precision <id> <class>: OK|FP=<n>
#   harness-score: detected=<n>/<total> fp=<m> findings=<count>
#
# Exit code: 0 when inputs are well-formed (the score is data, not a verdict — gating
# logic lives with the caller that compares against a baseline); 2 on malformed input.
#
# Bash 3.2 compatible; jq is the only dependency (repo-standard).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINDINGS_JSON="${1:-}"
MANIFEST="${2:-$SCRIPT_DIR/review-harness-fixtures/review-harness-manifest.tsv}"

if [[ -z "$FINDINGS_JSON" || ! -f "$FINDINGS_JSON" ]]; then
  echo "score-review: usage: score-review.sh <findings.json> [manifest.tsv]" >&2
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "score-review: manifest not found: $MANIFEST" >&2
  exit 2
fi

# One line per finding: "severity | file | title | description". Tolerant of both
# {findings:[...]} and bare arrays, and of message/claim in place of description.
LINES="$(jq -r '
  (if type == "array" then . else (.findings // []) end)
  | .[]
  | [ (.severity // ""), (.file // ""), (.title // ""),
      (.description // .message // .claim // "") ]
  | join(" | ")
' "$FINDINGS_JSON" 2>/dev/null)" || {
  echo "score-review: $FINDINGS_JSON is not parseable findings JSON" >&2
  exit 2
}
FINDING_COUNT=0
[[ -n "$LINES" ]] && FINDING_COUNT="$(printf '%s\n' "$LINES" | grep -c .)"

DETECTED=0
TOTAL=0
FP=0

while IFS=$'\t' read -r id kind cls regexA regexB _note; do
  case "$id" in ''|\#*) continue ;; esac
  matches=""
  if [[ -n "$LINES" ]]; then
    matches="$(printf '%s\n' "$LINES" | grep -Ei -- "$regexA" 2>/dev/null | grep -Eic -- "$regexB" 2>/dev/null || true)"
  fi
  matches="${matches:-0}"
  if [[ "$kind" == "detect" ]]; then
    TOTAL=$((TOTAL + 1))
    if [[ "$matches" -gt 0 ]]; then
      echo "mutant $id $cls: DETECTED"
      DETECTED=$((DETECTED + 1))
    else
      echo "mutant $id $cls: MISSED"
    fi
  elif [[ "$kind" == "precision" ]]; then
    if [[ "$matches" -gt 0 ]]; then
      echo "precision $id $cls: FP=$matches"
      FP=$((FP + matches))
    else
      echo "precision $id $cls: OK"
    fi
  else
    echo "score-review: unknown kind '$kind' for row $id" >&2
    exit 2
  fi
done < "$MANIFEST"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "score-review: manifest has zero detect rows — refusing a vacuous score" >&2
  exit 2
fi

echo "harness-score: detected=$DETECTED/$TOTAL fp=$FP findings=$FINDING_COUNT"
exit 0
