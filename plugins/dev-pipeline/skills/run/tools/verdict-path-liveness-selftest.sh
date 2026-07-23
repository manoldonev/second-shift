#!/usr/bin/env bash
# verdict-path-liveness-selftest.sh — verdict-path liveness for `stacked-prs` (#204).
#
# NOT per-tool fixture accretion: one deterministic, model-free scenario that
# drives a 2-slice decomposition through the MECHANICAL gate chain and asserts
# the `stacked-prs` verdict can reach its terminal state ("all slices clean").
# The bug class this guards against is contracts contradicting each other
# ACROSS components while every per-tool selftest stays green — the composed
# path, not the parts. Chain exercised:
#
#   statectl init → intake-brief → slice-partition-set → slice-set (slice 1)
#     → plan-lint Check 3 slice mode (slice plan passes; full-ticket plan fails)
#     → slice-scope.sh graded-union assembly (the scope-dispatch input)
#     → stop-condition evaluation (codeReviewExhausted predicate)
#     → slice 2 → final-slice completeness (union == full snapshot)
#
# The LLM-judged half of the scope gate (the reviewer agent) cannot run in
# model-free CI; its mechanical substrate — the partition, the integrity
# verdicts, the graded union, the diff-base selection input — is what this
# test pins. Same pattern should eventually cover `no-split` / `sub-issues`.
#
# Exit code = number of failed checks (repo selftest convention).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
STATECTL="$SKILL_DIR/statectl.sh"
LINT="$HERE/plan-lint.sh"
SCOPE="$HERE/slice-scope.sh"
FIX="$HERE/plan-lint-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATECTL_STATE_DIR="$TMP/pipeline-state"
ISSUE=4242
STATE="$STATECTL_STATE_DIR/$ISSUE.json"

sct() { bash "$STATECTL" "$@"; }
lint_rc() { set +e; bash "$LINT" "$@" >/dev/null 2>&1; echo $?; set -e; }

echo "[verdict-path-liveness] stacked-prs: intake writes"

# ---- Stage-1 intent snapshot: 4 ACs, partitioned into 2 slices --------------
sct init "$ISSUE" --run-id liveness-test >/dev/null
sct intake-brief "$ISSUE" --brief-path null --acceptance-criteria '[
  {"id":"AC-1","text":"schema field lands","negative":false,"source":"explicit"},
  {"id":"AC-2","text":"service consumes field","negative":false,"source":"explicit"},
  {"id":"AC-3","text":"endpoint exposes field","negative":false,"source":"explicit"},
  {"id":"AC-4","text":"worker backfills field","negative":false,"source":"explicit"}
]' >/dev/null
sct slice-partition-set "$ISSUE" --json \
  '[{"slice":1,"acIds":["AC-1","AC-2"]},{"slice":2,"acIds":["AC-3","AC-4"]}]' >/dev/null
[[ -f "$STATE" ]] \
  && pass "(vp1) intake writes: snapshot + partition persisted" \
  || fail "(vp1) state file missing at $STATE"

# ---- Slice 1: loop preamble + plan gate -------------------------------------
echo "[verdict-path-liveness] slice 1: plan gate"
sct slice-set "$ISSUE" --current 1 --branch claude/acme-4242 \
  --worktree-base main --pr-base main >/dev/null

mkplan() { # mkplan <out> <rows...> — the valid fixture with its AC rows swapped for the caller's
  local out="$1"; shift
  grep -v '^| AC-' "$FIX/valid-plan.md" > "$out.notable"
  printf '%s\n' "$@" > "$out.rows"
  # macOS awk rejects newlines in -v values — read the rows from a file instead.
  awk -v rowsfile="$out.rows" '
    /^\| AC ID/ { print; getline; print; while ((getline l < rowsfile) > 0) print l; next }
    { print }
  ' "$out.notable" > "$out"
  rm -f "$out.notable" "$out.rows"
}

mkplan "$TMP/slice1.md" \
  '| AC-1 | schema field lands | 1 | selftest (AC-1) |' \
  '| AC-2 | service consumes field | 2 | selftest (AC-2) |'
rc=$(lint_rc "$TMP/slice1.md" "$STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(vp2) slice-1 plan (this slice's ACs only) passes plan-lint slice mode" \
  || fail "(vp2) slice-1 plan — rc=$rc"

mkplan "$TMP/fullticket.md" \
  '| AC-1 | schema field lands | 1 | selftest (AC-1) |' \
  '| AC-2 | service consumes field | 2 | selftest (AC-2) |' \
  '| AC-3 | endpoint exposes field | 3 | selftest (AC-3) |' \
  '| AC-4 | worker backfills field | 4 | selftest (AC-4) |'
rc=$(lint_rc "$TMP/fullticket.md" "$STATE")
[[ "$rc" -eq 1 ]] \
  && pass "(vp3) full-ticket table on slice 1 rejected (fabricated coverage)" \
  || fail "(vp3) full-ticket table — rc=$rc (expected 1)"

# ---- Slice 1: scope-dispatch item-list assembly -----------------------------
echo "[verdict-path-liveness] slice 1: scope-dispatch assembly"
out=$(bash "$SCOPE" "$STATE" --slice 1)
verdict=$(head -n1 <<< "$out")
graded=$(tail -n +2 <<< "$out" | paste -sd, -)
[[ "$verdict" == "ok" && "$graded" == "AC-1,AC-2" ]] \
  && pass "(vp4) slice-1 graded union = AC-1,AC-2 (integrity ok)" \
  || fail "(vp4) slice-1 union — verdict=$verdict graded=$graded"

# Tampered partition (an AC vanishes from the union) → union-mismatch, void.
jq '.decomposition.slices[1].acIds = ["AC-3"]' "$STATE" > "$TMP/tampered.json"
verdict=$(bash "$SCOPE" "$TMP/tampered.json" --slice 1 | head -n1)
[[ "$verdict" == "union-mismatch" ]] \
  && pass "(vp5) tampered partition → union-mismatch (slice-scoping void, fail-closed)" \
  || fail "(vp5) tampered partition — verdict=$verdict"

# ---- Slice 1 → 2: stop-condition evaluation ---------------------------------
echo "[verdict-path-liveness] stop-condition evaluation"
# Clean slice-1 review: one round, NOT exhausted → loop must proceed.
sct review-rounds "$ISSUE" --set 1 >/dev/null
exhausted=$(sct get "$ISSUE" '.codeReviewExhausted // false')
[[ "$exhausted" == "false" ]] \
  && pass "(vp6) clean review (round 1, no --exhausted) → loop proceeds to slice 2" \
  || fail "(vp6) clean review — codeReviewExhausted=$exhausted"

# ---- Slice 2 (final): completeness is NOT weakened --------------------------
echo "[verdict-path-liveness] slice 2: final-slice completeness"
sct slice-set "$ISSUE" --current 2 --branch claude/acme-4242-pr2 \
  --prior-branch claude/acme-4242 --worktree-base claude/acme-4242 \
  --pr-base claude/acme-4242 >/dev/null
out=$(bash "$SCOPE" "$STATE")   # default slice = currentSlice = 2
verdict=$(head -n1 <<< "$out")
graded=$(tail -n +2 <<< "$out" | sort | paste -sd, -)
snap=$(sct get "$ISSUE" '.acceptanceCriteria | map(.id) | sort | join(",")')
[[ "$verdict" == "ok" && "$graded" == "$snap" ]] \
  && pass "(vp7) final slice grades the COMPLETE ticket (union == snapshot)" \
  || fail "(vp7) final slice — graded=$graded snap=$snap"

mkplan "$TMP/slice2.md" \
  '| AC-3 | endpoint exposes field | 1 | selftest (AC-3) |' \
  '| AC-4 | worker backfills field | 2 | selftest (AC-4) |'
rc=$(lint_rc "$TMP/slice2.md" "$STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(vp8) slice-2 plan (its own ACs) passes plan-lint slice mode" \
  || fail "(vp8) slice-2 plan — rc=$rc"

# Exhaustion on the final slice still stops the loop (the stop predicate is intact).
sct review-rounds "$ISSUE" --set 3 --exhausted >/dev/null
exhausted=$(sct get "$ISSUE" '.codeReviewExhausted // false')
[[ "$exhausted" == "true" ]] \
  && pass "(vp9) --exhausted still trips the stop predicate (guard not weakened)" \
  || fail "(vp9) exhausted predicate — codeReviewExhausted=$exhausted"

# Terminal reachability: with clean slices the walk above hit every mechanical
# gate and no gate blocked a non-final slice on a later slice's AC — the
# stacked-prs verdict has a live path to its "all slices clean" terminal.
echo
echo "[verdict-path-liveness] summary: $PASS passed, $FAIL failed"
exit $FAIL
