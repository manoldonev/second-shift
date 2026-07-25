#!/usr/bin/env bash
# scenario-liveness-selftest.sh — verdict-path liveness for the pipeline's four verdicts.
#
# NOT per-tool fixture accretion. Every other selftest in this tree verifies one
# component's own contract; this one asserts that a COMPOSED pipeline path still
# reaches its terminal state. The bug class it guards is contracts contradicting
# each other ACROSS components while every per-tool selftest stays green — how the
# stacked-prs path died in #204 with a fully green suite.
#
# Scenarios (one per declared verdict):
#
#   no-split     init -> stages 1..3 -> plan-lint over a real fixture plan
#                -> stages 4..9 -> mark-completed ACCEPTED (the terminal write)
#   sub-issues   the declared carve-out: success-shaped, no mark-failed, status
#                stays in_progress, and mark-completed correctly REFUSES
#   failure      intake-spec-blocked via build-failure-context -> terminal `failed`
#   stacked-prs  the 11 checks migrated from tools/verdict-path-liveness-selftest.sh
#
# Scope boundary: scenarios exercise the MECHANICAL chain. Agent-prose gates (the
# scope reviewer, review-lead synthesis) appear only as their mechanical shadows —
# the state writes their outcomes produce. A model-free harness cannot execute
# prose; it CAN assert that the prose's declared state protocol composes.
#
# The full-green-run recipe is NOT re-enumerated here — complete_stage /
# complete_run_vs come from scenario-lib.sh, shared with statectl-selftest.sh.
#
# Exit code = number of failed checks (repo selftest convention).

# `-uo pipefail` (no `-e`), matching statectl-selftest.sh: these scenarios assert on
# non-zero exit codes as first-class outcomes (a refused mark-completed, a rejected
# plan), so a global `-e` would abort the harness on its own passing cases.
set -uo pipefail
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST BRANCH_PREFIX

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATECTL="$HERE/statectl.sh"
SCENARIO_LIB="$HERE/scenario-lib.sh"
LINT="$HERE/tools/plan-lint.sh"
SCOPE="$HERE/tools/slice-scope.sh"
FIX="$HERE/tools/plan-lint-fixtures"

[[ -x "$STATECTL" ]] || { echo "[scenario-liveness] FATAL: $STATECTL not executable"; exit 99; }
[[ -f "$SCENARIO_LIB" ]] || { echo "[scenario-liveness] FATAL: $SCENARIO_LIB missing"; exit 99; }
[[ -f "$LINT" ]] || { echo "[scenario-liveness] FATAL: $LINT missing"; exit 99; }
[[ -f "$SCOPE" ]] || { echo "[scenario-liveness] FATAL: $SCOPE missing"; exit 99; }
[[ -d "$FIX" ]] || { echo "[scenario-liveness] FATAL: $FIX missing"; exit 99; }

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t scenario-liveness.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/.claude/pipeline-state"
# Pin the state dir BEFORE sourcing the lib — its helpers key their file writes and
# resets on this value rather than a relative path, so the harness need not cd.
export STATECTL_STATE_DIR="$TMP/.claude/pipeline-state"
cd "$TMP" || exit 99

# Absolute path, resolved above from BASH_SOURCE, so the cd cannot break it.
# shellcheck source=/dev/null
. "$SCENARIO_LIB"

lint_rc() { bash "$LINT" "$@" >/dev/null 2>&1; echo $?; }

# mkplan <out> <rows...> — the valid fixture with its AC rows swapped for the caller's.
mkplan() {
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

# ============================================================ no-split liveness ===
# The headline guarantee: a clean single-PR run reaches `completed`. Every gate the
# nine stages impose must compose, or the terminal write is refused.

echo "[scenario-liveness] no-split: full green run reaches terminal completed"
KEY=9001
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3; do complete_stage "$KEY" "$n"; done

# Delta over complete_run_vs: a REAL fixture plan is threaded through plan-lint
# between stages 3 and 4, matching where the Stage-4 hard gate actually runs.
sct intake-brief "$KEY" --brief-path null --acceptance-criteria '[
  {"id":"AC-1","text":"harness reaches terminal state","negative":false,"source":"explicit"},
  {"id":"AC-2","text":"gates compose across stages","negative":false,"source":"explicit"}
]' >/dev/null
mkplan "$TMP/nosplit-plan.md" \
  '| AC-1 | harness reaches terminal state | 1 | selftest (AC-1) |' \
  '| AC-2 | gates compose across stages | 2 | selftest (AC-2) |'
rc=$(lint_rc "$TMP/nosplit-plan.md" "$STATECTL_STATE_DIR/$KEY.json")
[[ "$rc" -eq 0 ]] \
  && pass "(ns1) stage-3/4 boundary: real fixture plan passes plan-lint against the live snapshot" \
  || fail "(ns1) plan-lint on the no-split fixture plan — rc=$rc"

for n in 4 5 6 7 8 9; do complete_stage "$KEY" "$n"; done
write_report "$KEY"
write_eval "$KEY"
rc=$(sct_rc mark-completed "$KEY")
status=$(sct get "$KEY" '.status')
[[ "$rc" -eq 0 && "$status" == "completed" ]] \
  && pass "(ns2) no-split TERMINAL: mark-completed accepted, status=completed" \
  || fail "(ns2) no-split terminal write — rc=$rc status='$status' err='$(sct_err mark-completed "$KEY")'"

# Liveness is only meaningful if the gate can still refuse: drop stage 9's receipt
# and the same run must NOT reach terminal. Without this the scenario would stay
# green even if every precondition were deleted.
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5 6 7 8; do complete_stage "$KEY" "$n"; done
write_report "$KEY"
write_eval "$KEY"
rc=$(sct_rc mark-completed "$KEY")
[[ "$rc" -ne 0 ]] \
  && pass "(ns3) non-vacuity: an incomplete run is REFUSED terminal (stage 9 never completed)" \
  || fail "(ns3) incomplete run wrongly accepted terminal — the no-split scenario is vacuous"

# ========================================================== sub-issues carve-out ===
# Declared carve-out (stages/1-intake.md): success-shaped, NOT state-terminated.
# NOTE the honest scope — statectl.sh carries NO verdict-aware handling of
# `sub-issues` (grep returns zero hits), so the refusal asserted below is
# statectl's GENERIC incompleteness gate, not a sub-issues-aware one. What this
# scenario pins is the declared SHAPE: no mark-failed, status stays in_progress.

echo "[scenario-liveness] sub-issues: carve-out shape is accepted and not terminalized"
KEY=9002
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
# Pass the verdict explicitly — complete_stage defaults to no-split, which would
# make this scenario assert against a checkpoint contradicting the path under test.
complete_stage "$KEY" 1 sub-issues

verdict=$(sct get "$KEY" '.stageCheckpoint."1".verdict')
status=$(sct get "$KEY" '.status')
fctx=$(sct get "$KEY" '.failureContext')
[[ "$verdict" == "sub-issues" && "$status" == "in_progress" && "$fctx" == "null" ]] \
  && pass "(si1) carve-out shape: verdict=sub-issues, status stays in_progress, no failureContext" \
  || fail "(si1) carve-out shape — verdict='$verdict' status='$status' failureContext='$fctx'"

rc=$(sct_rc mark-completed "$KEY")
status=$(sct get "$KEY" '.status')
[[ "$rc" -ne 0 && "$status" == "in_progress" ]] \
  && pass "(si2) mark-completed REFUSES the split (generic incompleteness gate), status untouched" \
  || fail "(si2) split wrongly terminalized — rc=$rc status='$status'"

# ============================================================= failure-path ===
# One representative mark-failed flow reaching terminal `failed` from stage 1.
# No enum sweeping — statectl-selftest.sh owns per-reason coverage; this asserts
# only that the composition (build-failure-context -> mark-failed) lands.

echo "[scenario-liveness] failure-path: intake-spec-blocked reaches terminal failed"
KEY=9003
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
sct set-stage "$KEY" 1 --status started >/dev/null
FCTX=$(sct build-failure-context --reason intake-spec-blocked --stage 1 \
  --kv outcome=true-blockers --kv-lines blockers="spec omits the error contract")
rc=$(sct_rc mark-failed "$KEY" --reason intake-spec-blocked --stage 1 --json "$FCTX")
status=$(sct get "$KEY" '.status')
reason=$(sct get "$KEY" '.failureContext.reason')
stage1=$(sct get "$KEY" '.stages."1".status')
[[ "$rc" -eq 0 && "$status" == "failed" && "$reason" == "intake-spec-blocked" && "$stage1" == "failed" ]] \
  && pass "(fp1) failure TERMINAL: status=failed, reason recorded, stage 1 marked failed" \
  || fail "(fp1) failure terminal write — rc=$rc status='$status' reason='$reason' stage1='$stage1'"

blockers=$(sct get "$KEY" '.failureContext.blockers | type')
[[ "$blockers" == "array" ]] \
  && pass "(fp2) build-failure-context --kv-lines composed into a JSON array in the terminal write" \
  || fail "(fp2) blockers field type='$blockers' (expected array)"

# ============================================================== stacked-prs ===
# Migrated verbatim (labels preserved) from tools/verdict-path-liveness-selftest.sh,
# which this harness replaces. Chain exercised:
#   init -> intake-brief -> slice-partition-set -> slice-set (slice 1)
#     -> plan-lint Check 3 slice mode -> slice-scope.sh graded-union assembly
#     -> stop-condition evaluation -> slice 2 -> final-slice completeness

echo "[scenario-liveness] stacked-prs: intake writes"
ISSUE=4242
STATE="$STATECTL_STATE_DIR/$ISSUE.json"
reset_state
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

echo "[scenario-liveness] stacked-prs: slice 1 plan gate"
sct slice-set "$ISSUE" --current 1 --branch claude/acme-4242 \
  --worktree-base main --pr-base main >/dev/null

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

echo "[scenario-liveness] stacked-prs: slice 1 scope-dispatch assembly"
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

# No partition at all (every non-stacked run — the tool's most common invocation)
# → no-partition, and consumers keep full-ticket behavior.
jq 'del(.decomposition)' "$STATE" > "$TMP/nopart.json"
verdict=$(bash "$SCOPE" "$TMP/nopart.json" | head -n1)
[[ "$verdict" == "no-partition" ]] \
  && pass "(vp5b) state without decomposition.slices → no-partition" \
  || fail "(vp5b) no partition — verdict=$verdict"

# Usage/IO errors → exit 2 with a message (missing state file; non-integer --slice).
bash "$SCOPE" "$TMP/does-not-exist.json" >/dev/null 2>&1; rc_missing=$?
bash "$SCOPE" "$STATE" --slice foo >/dev/null 2>&1; rc_badslice=$?
[[ "$rc_missing" -eq 2 && "$rc_badslice" -eq 2 ]] \
  && pass "(vp5c) usage/IO errors (missing state, non-integer --slice) → exit 2" \
  || fail "(vp5c) usage errors — rc_missing=$rc_missing rc_badslice=$rc_badslice"

echo "[scenario-liveness] stacked-prs: stop-condition evaluation"
# Clean slice-1 review: one round, NOT exhausted → loop must proceed.
sct review-rounds "$ISSUE" --set 1 >/dev/null
exhausted=$(sct get "$ISSUE" '.codeReviewExhausted // false')
[[ "$exhausted" == "false" ]] \
  && pass "(vp6) clean review (round 1, no --exhausted) → loop proceeds to slice 2" \
  || fail "(vp6) clean review — codeReviewExhausted=$exhausted"

echo "[scenario-liveness] stacked-prs: slice 2 final-slice completeness"
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

echo
echo "[scenario-liveness] summary: $PASS passed, $FAIL failed"
exit $FAIL
