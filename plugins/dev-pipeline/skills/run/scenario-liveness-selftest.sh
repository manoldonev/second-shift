#!/usr/bin/env bash
# scenario-liveness-selftest.sh — composed-path liveness for the pipeline's declared verdicts.
#
# NOT per-tool fixture accretion. Every other selftest in this tree verifies one
# component's own contract; this one asserts that a COMPOSED pipeline path still
# reaches its terminal state. The bug class it guards is contracts contradicting
# each other ACROSS components while every per-tool selftest stays green — how the
# (since-retired) stacked-PR path died in #204 with a fully green suite.
#
# Scenarios:
#
#   no-split     init -> stages 1..3 -> plan-lint over a real fixture plan
#                -> stages 4..9 -> mark-completed ACCEPTED (the terminal write)
#   sub-issues   the declared carve-out: success-shaped, no mark-failed, status
#                stays in_progress, and mark-completed correctly REFUSES
#   failure      intake-spec-blocked via build-failure-context -> terminal `failed`
#   breaker      real verifyctl charges TEST_FAILURE to exhaustion (twice, no clean
#                run between) -> mark-failed approach-failure-circuit-breaker ->
#                terminal `failed`
#   exhausted    review-rounds --exhausted -> stage 9 -> mark-completed ACCEPTED
#   be-fe-pair   per-repo worktrees + per-repo stage-6 attestation + per-repo
#                checkpoint 7 + the stage-8 cross-boundary escape hatch
#                -> mark-completed ACCEPTED (top-level `completed`)
#   predecessor  the sub-issues-sequential pre-claim ordering backstop: an open
#                predecessor skips WITHOUT claiming (no claim receipt, no state
#                file), a closed one claims, and the pair is proven non-vacuous
#
# Scope boundary: scenarios exercise the MECHANICAL chain. Agent-prose gates (the
# scope reviewer, review-lead synthesis) appear only as their mechanical shadows —
# the state writes their outcomes produce. A model-free harness cannot execute
# prose; it CAN assert that the prose's declared state protocol composes.
#
# ---------------------------------------------------------------------------
# Reach boundary — what is deliberately NOT scenarioed, and why.
#
# Stated so the next reach audit is a DIFF of this list rather than a
# re-derivation. The two groups are NOT interchangeable: (A) is settled, (B) is
# debt. Collapsing them into one list is how deferred debt starts reading as a
# deliberate exclusion, which is the failure this list exists to prevent.
#
# (A) Out of reach BY CONTRACT — nothing to add until the contract itself changes:
#   - Design mode (design-source-unreachable at stages 1/3, render-verify-unavailable
#     degradation, the designPlanReview sub-status). The mode is contractually
#     interactive/MCP-backed and headless fail-closes by design (state-schema.md
#     "Design Mode"); design-sync-selftest.mjs covers the engine enum drift.
#   - Stage 10 (cleanup). It has no stage status, so there is no state shadow to
#     assert against.
#
# (B) Uncovered, TRACKED — reachable today; absence here is debt, not a decision:
#   - failureContext.reason paths with no composed driver: worktree-missing (stage-8
#     resume), targetRepos-ambiguous and fe-repo-unreachable (be-fe-pair pre-stage-1),
#     intake-needs-human-input (stage 1), ext-workflow-failed (the EP-6 stageWorkflows
#     blocking class). statectl-selftest.sh covers several as enum-ACCEPTANCE writes,
#     which is not the same as driving them from the triggering component.
#   - scope-blocker-no-code-remedy (the stage-8 short-circuit marker).
#   - Crash-recovery composition — PARTIALLY DISCHARGED (#217), one clause of four.
#     The resume leg (a session-identity switch -> pipeline-session-add -> stage-8
#     re-entry -> terminal write) is now a scenario in e2e-replay-selftest.sh, which
#     owns it because it needs that file's minted-receipt machinery. Since #260 the
#     pause span on that leg is recorded by statectl's shared write seam rather than
#     by an explicit first-write subcommand, so the scenario drives it by switching
#     $CLAUDE_CODE_SESSION_ID and asserts the single span and its anchor — there is
#     no longer a first-write ordering contract for a composed test to get wrong. STILL
#     UNCOVERED, here and there: reclaim --release quarantine -> fresh init; init's
#     stale-artifact quarantine. Those two remain per-command statectl-selftest cases
#     with no composed driver. Do NOT collapse this entry to "covered" — most of it is
#     still debt.
#   - Production Workflow .mjs dispatch ladders. Those belong on the runtime shim
#     (workflows/runtime-shim-selftest.mjs), not here.
# ---------------------------------------------------------------------------
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
VERIFYCTL="$HERE/verifyctl.sh"
LINT="$HERE/tools/plan-lint.sh"
PRED_GATE="$HERE/tools/predecessor-gate.sh"
TRACKER_CHECK="$HERE/tools/tracker-reconcile-check.sh"
FIX="$HERE/tools/plan-lint-fixtures"

[[ -x "$STATECTL" ]] || { echo "[scenario-liveness] FATAL: $STATECTL not executable"; exit 99; }
[[ -f "$SCENARIO_LIB" ]] || { echo "[scenario-liveness] FATAL: $SCENARIO_LIB missing"; exit 99; }
[[ -x "$VERIFYCTL" ]] || { echo "[scenario-liveness] FATAL: $VERIFYCTL not executable"; exit 99; }
[[ -f "$LINT" ]] || { echo "[scenario-liveness] FATAL: $LINT missing"; exit 99; }
[[ -x "$PRED_GATE" ]] || { echo "[scenario-liveness] FATAL: $PRED_GATE not executable"; exit 99; }
[[ -x "$TRACKER_CHECK" ]] || { echo "[scenario-liveness] FATAL: $TRACKER_CHECK not executable"; exit 99; }
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
# Pin the writing session identity (#260) — see statectl-selftest.sh's note. Every
# scenario here composes a single-session run, so a fixed id keeps them same-session
# and no scenario should ever grow a pauseSpans entry. Inheriting the harness's id
# would work today by accident; pinning it makes that a decision.
#
# Since #123 the pin also fixes SESSION REGISTRATION: the seam records this id into
# pipelineSessions[] on each scenario's first state write, so every scenario carries
# exactly one session record. No scenario asserts on that field — these are
# verdict-path tests, not cost-accounting ones — but the pin is what holds the count
# at one instead of letting it vary with whichever session ran the suite.
export CLAUDE_CODE_SESSION_ID="1ffe6e55-0000-4000-8000-000000000001"
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

# Same shape for the Stage-6 verifyctl attestation: drive the IDENTICAL recipe with
# the sidecar plant suppressed, and stage 6 must not complete. Without this the
# scenario would stay green with the attestation gate deleted, since the recipe now
# plants a sidecar on every run.
#
# The assertion reads STATE, not an exit code: complete_stage discards set-stage's
# rc (`sct … >/dev/null`), so `.stages."6".status` is the only observable — the same
# posture as (ns3), which reads mark-completed's effect rather than its rc.
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5; do complete_stage "$KEY" "$n"; done
SCENARIO_SKIP_VERIFY_SIDECAR=1 complete_stage "$KEY" 6
s6=$(sct get "$KEY" '.stages."6".status')
[[ "$s6" != "completed" ]] \
  && pass "(ns4) non-vacuity: stage 6 is REFUSED with no verifyctl sidecar (the attestation gate is live)" \
  || fail "(ns4) stage 6 completed with no verifyctl attestation — the attestation gate is inert"

# …and the same leg DOES complete once the sidecar is planted, so (ns4) pins the
# sidecar's absence rather than some unrelated breakage in the stage-6 recipe.
complete_stage "$KEY" 6
s6=$(sct get "$KEY" '.stages."6".status')
[[ "$s6" == "completed" ]] \
  && pass "(ns5) the same stage-6 leg completes once the sidecar is planted (AC-3)" \
  || fail "(ns5) stage 6 did not complete with a sidecar present — status='$s6'"

# Stage-8 skill-load ORDERING, composed. complete_stage's stage-8 leg loads
# review-lead BEFORE recording the code-review receipt, so the green run above
# already proves the correct order still reaches terminal. This is the other
# direction: a run that authors its synthesis FIRST cannot launder the load
# afterwards, because the receipt write itself now refuses — and with no receipt
# the stage cannot close, so mark-completed stays unreachable.
#
# Scenario-tier rather than per-tool: it asserts that a COMPOSED run is stopped by
# the two gates acting together (comment-add's precondition + the stage-8 receipt
# leg), which is the property the presence-only gate lacked.
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5 6 7; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 8 --status started >/dev/null
sct review-rounds "$KEY" --set 1 >/dev/null
rc_receipt=$(sct_rc comment-add "$KEY" --marker code-review --url "https://github.example/issues/$KEY#issuecomment-105")
sct set-stage "$KEY" 8 --status completed >/dev/null
s8=$(sct get "$KEY" '.stages."8".status')
write_report "$KEY"
write_eval "$KEY"
rc_term=$(sct_rc mark-completed "$KEY")
[[ "$rc_receipt" -ne 0 && "$s8" != "completed" && "$rc_term" -ne 0 ]] \
  && pass "(ns6) non-vacuity: synthesis-before-skill-load is REFUSED its receipt, so stage 8 never closes and terminal is unreachable" \
  || fail "(ns6) inverted stage-8 order wrongly reached terminal — rc_receipt=$rc_receipt s8='$s8' rc_term=$rc_term"

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

# ======================================================= exhausted-review ===
# A review-exhausted run is opened as a draft and STILL terminates (the marker
# table's "exhausted-after-3-rounds" case). Before this scenario the exhaustion
# flag was asserted only in isolation (vp9); whether the terminal gates ACCEPT
# such a run was unproven composition.

echo "[scenario-liveness] exhausted-review: an exhausted run still reaches terminal completed"
KEY=9004
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5 6 7; do complete_stage "$KEY" "$n"; done

# Stage 8 is driven inline rather than via complete_stage: the helper plants
# `review-rounds --set 1`, and the path under test is three rounds ending in
# --exhausted. The remaining stage-8 evidence matches the helper's.
sct set-stage "$KEY" 8 --status started >/dev/null
sct review-rounds "$KEY" --set 3 --exhausted >/dev/null
sct skill-load-add "$KEY" --stage 8 --skill review-toolkit:review-lead >/dev/null
sct comment-add "$KEY" --marker code-review --url "https://github.example/issues/$KEY#issuecomment-105" >/dev/null
stage_evidence "$KEY" 8
sct set-stage "$KEY" 8 --status completed >/dev/null

complete_stage "$KEY" 9
write_report "$KEY"
write_eval "$KEY"
rc=$(sct_rc mark-completed "$KEY")
status=$(sct get "$KEY" '.status')
exhausted=$(sct get "$KEY" '.codeReviewExhausted // false')
[[ "$rc" -eq 0 && "$status" == "completed" && "$exhausted" == "true" ]] \
  && pass "(xr1) exhausted-review TERMINAL: mark-completed accepted, status=completed, exhaustion flag intact (AC-2)" \
  || fail "(xr1) exhausted-review terminal — rc=$rc status='$status' exhausted='$exhausted' err='$(sct_err mark-completed "$KEY")'"

# Non-vacuity: the terminal acceptance above must come from the run being
# COMPLETE, not from the exhaustion flag waiving anything. Same recipe, stage 9
# never completed -> still refused.
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5 6 7; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 8 --status started >/dev/null
sct review-rounds "$KEY" --set 3 --exhausted >/dev/null
sct skill-load-add "$KEY" --stage 8 --skill review-toolkit:review-lead >/dev/null
sct comment-add "$KEY" --marker code-review --url "https://github.example/issues/$KEY#issuecomment-105" >/dev/null
stage_evidence "$KEY" 8
sct set-stage "$KEY" 8 --status completed >/dev/null
write_report "$KEY"
write_eval "$KEY"
rc=$(sct_rc mark-completed "$KEY")
[[ "$rc" -ne 0 ]] \
  && pass "(xr2) non-vacuity: an exhausted run with stage 9 incomplete is still REFUSED terminal" \
  || fail "(xr2) exhausted run wrongly accepted with stage 9 incomplete — the exhausted scenario is vacuous"

# ==================================================== be-fe-pair to terminal ===
# The pair topology's per-repo pieces each have a per-tool suite; what none of
# them proves is that a pair run REACHES a terminal write. That is the same
# all-green-units/unproven-composition posture the stacked-PR path had before #204.
# Terminal here means the TOP-LEVEL status, not a per-repo write — a per-repo
# stage-8 write is exactly the coverage that already existed.

echo "[scenario-liveness] be-fe-pair: a two-repo run reaches terminal completed"
KEY=9006
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
sct target-repos-set "$KEY" --repos "be fe" >/dev/null
complete_stage "$KEY" 1
sct set-stage "$KEY" 2 --status started >/dev/null
sct worktree-set "$KEY" --repo be --path ".claude/worktrees/be-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
sct worktree-set "$KEY" --repo fe --path ".claude/worktrees/fe-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
# Flat mirror of the primary target — what Stage 2 writes so the middle stages,
# which still read the flat fields, operate on the primary repo.
sct worktree-set "$KEY" --path ".claude/worktrees/be-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
stage_evidence "$KEY" 2
sct set-stage "$KEY" 2 --status completed >/dev/null
for n in 3 4 5; do complete_stage "$KEY" "$n"; done

# Stage 6 inline: a pair run needs a per-repo verifySummary AND a per-repo
# verifyctl attestation for EVERY target (both gates iterate targetRepos).
befe_stage6() {  # $1 = key; plants both targets' summary + sidecar
  local k="$1" r
  sct set-stage "$k" 6 --status started >/dev/null
  for r in be fe; do
    sct verify-summary-set "$k" --repo "$r" --json '{"format":"clean","test":"passed"}' >/dev/null
    write_verify_sidecar "$k" "$r"
  done
  stage_evidence "$k" 6
  sct set-stage "$k" 6 --status completed >/dev/null
}
befe_stage6 "$KEY"
s6=$(sct get "$KEY" '.stages."6".status')
[[ "$s6" == "completed" ]] \
  && pass "(bf1) pair stage 6 completes with a per-repo summary + attestation for every target" \
  || fail "(bf1) pair stage 6 — status='$s6' err='$(sct_err set-stage "$KEY" 6 --status completed)'"

# Stage 7: the per-repo checkpoint shape (perRepo map), composed from the
# per-repo builder exactly as the dual-target stage doc composes it.
sct set-stage "$KEY" 7 --status started >/dev/null
PERREPO=$(
  for r in be fe; do
    sct build-checkpoint-7-perrepo --repo "$r" --branch "claude/acme-$KEY" \
      --head "beefcafe$KEY" --worktree ".claude/worktrees/$r-$KEY" \
      --changed-files '[]' --verify-summary '{"format":"clean","test":"passed"}'
  done | jq -s 'reduce .[] as $x ({}; .perRepo += $x.perRepo)'
)
CP7=$(jq --arg k "$KEY" '. + {ticketKey:$k, targetRepos:["be","fe"], planPath:"docs/plans/acme-9006.md", deviations:[]}' <<< "$PERREPO")
sct checkpoint "$KEY" 7 --json "$CP7" >/dev/null
sct comment-add "$KEY" --marker doc-update --url "https://github.example/issues/$KEY#issuecomment-104" >/dev/null
stage_evidence "$KEY" 7
sct set-stage "$KEY" 7 --status completed >/dev/null
perrepo_keys=$(sct get "$KEY" '.stageCheckpoint."7".perRepo | keys | join(",")')
[[ "$perrepo_keys" == "be,fe" ]] \
  && pass "(bf2) pair checkpoint 7 carries both targets under perRepo" \
  || fail "(bf2) perRepo keys='$perrepo_keys'"

# Stage 8: the primary repo records rounds; the SECONDARY repo goes through the
# cross-boundary escape hatch (which also exempts the review-lead skill-load gate).
sct set-stage "$KEY" 8 --status started >/dev/null
sct review-rounds "$KEY" --set 1 >/dev/null
sct skill-load-add "$KEY" --stage 8 --skill review-toolkit:review-lead >/dev/null
sct cross-boundary-review-add "$KEY" --repo fe --status completed-in-session \
  --worktree ".claude/worktrees/fe-$KEY" --note "secondary reviewed in session" >/dev/null
sct comment-add "$KEY" --marker code-review --url "https://github.example/issues/$KEY#issuecomment-105" >/dev/null
stage_evidence "$KEY" 8
sct set-stage "$KEY" 8 --status completed >/dev/null

# #243: a pair run's stage 9 requires .prs keyed by repo id for EVERY target
# (the 9.prsRepoKeyed leg) — record both PRs as Stage 9's per-repo loop does.
sct pr-add "$KEY" --repo be --branch "claude/acme-$KEY" --url "https://github.example/pr/be" >/dev/null
sct pr-add "$KEY" --repo fe --branch "claude/acme-$KEY" --url "https://github.example/pr/fe" >/dev/null
complete_stage "$KEY" 9
write_report "$KEY"
write_eval "$KEY"
rc=$(sct_rc mark-completed "$KEY")
status=$(sct get "$KEY" '.status')
cbr=$(sct get "$KEY" '.crossBoundaryReviews | length')
[[ "$rc" -eq 0 && "$status" == "completed" && "$cbr" == "1" ]] \
  && pass "(bf3) be-fe-pair TERMINAL: mark-completed accepted, top-level status=completed (AC-3)" \
  || fail "(bf3) pair terminal — rc=$rc status='$status' crossBoundaryReviews=$cbr err='$(sct_err mark-completed "$KEY")'"

# Non-vacuity: the per-target attestation gate must be what carried (bf1). Drive
# the IDENTICAL recipe with ONE target's sidecar suppressed — stage 6 must refuse.
# Suppressing `fe` (not `be`) also proves the gate iterates every target rather
# than checking only the first.
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
sct target-repos-set "$KEY" --repos "be fe" >/dev/null
complete_stage "$KEY" 1
sct set-stage "$KEY" 2 --status started >/dev/null
sct worktree-set "$KEY" --repo be --path ".claude/worktrees/be-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
sct worktree-set "$KEY" --repo fe --path ".claude/worktrees/fe-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
sct worktree-set "$KEY" --path ".claude/worktrees/be-$KEY" --branch "claude/acme-$KEY" --base main >/dev/null
stage_evidence "$KEY" 2
sct set-stage "$KEY" 2 --status completed >/dev/null
for n in 3 4 5; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 6 --status started >/dev/null
for r in be fe; do
  sct verify-summary-set "$KEY" --repo "$r" --json '{"format":"clean","test":"passed"}' >/dev/null
done
write_verify_sidecar "$KEY" be     # fe's attestation deliberately absent
stage_evidence "$KEY" 6
sct set-stage "$KEY" 6 --status completed >/dev/null
s6=$(sct get "$KEY" '.stages."6".status')
[[ "$s6" != "completed" ]] \
  && pass "(bf4) non-vacuity: pair stage 6 is REFUSED when one target has no attestation" \
  || fail "(bf4) pair stage 6 completed with a missing per-target attestation — the gate is inert"

# =============================================== circuit breaker (real verifyctl) ===
# Composes three components that had only ever been tested against themselves:
# verifyctl's sidecar accounting, statectl's verifyAttempts budget, and the
# terminal mark-failed write.
#
# HONEST SCOPE — read before extending. The breaker's TRIGGER ("two consecutive
# TEST_FAILURE budget exhaustions with no clean run in between", stages/6-verify.md)
# is agent prose and is NOT derivable from persisted state: verifyctl evaluates
# `count >= 2` BEFORE charging, so the counter is monotonic and every exhausted
# run emits an identical exit-4 verdict; verify-attempts has no reset; and the
# sidecar carries no clean-run marker. So this scenario drives the REAL chain up
# to the edge of that prose — real verifyctl, real charging, two real consecutive
# exhaustions — and then asserts the state shadow the prose's decision produces.
# It does NOT re-implement the trigger predicate: a harness-authored predicate
# cannot fail on a production edit and would read as composition coverage while
# proving nothing (the tautology this file exists to avoid).

echo "[scenario-liveness] breaker: real verifyctl exhaustion -> approach-failure-circuit-breaker -> terminal failed"
KEY=9005
BRK="$TMP/breaker"
BRK_MARKERS="$BRK/markers"
mkdir -p "$BRK_MARKERS" "$BRK/bin" "$BRK/work/src"

# `yarn` PATH shim — the technique proven in verifyctl-selftest.sh. Never runs a
# real suite; behavior is driven by marker files.
cat > "$BRK/bin/yarn" <<'SHIM'
#!/usr/bin/env bash
M="${VERIFYCTL_TEST_MARKERS:?}"
SCRIPT="${1:-}"; shift || true
case "$SCRIPT" in
  test) [[ -f "$M/FAIL_TEST" ]] && { echo "FAIL src/thing.spec.ts"; exit 1; }; exit 0 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$BRK/bin/yarn"

cat > "$BRK/cfg.json" <<'CFG'
{
  "configVersion": 2,
  "tracker": { "type": "github" },
  "topology": { "type": "monorepo", "repos": { "mono": { "path": ".", "baseBranch": "main" } } },
  "commands": {
    "mono": {
      "lint": null, "lintAutofixes": false, "typecheck": null,
      "test": "yarn test", "format": null
    }
  }
}
CFG

BRK_WORK="$BRK/work"
git -C "$BRK_WORK" init -q -b main 2>/dev/null \
  || { git -C "$BRK_WORK" init -q && git -C "$BRK_WORK" checkout -qb main; }
git -C "$BRK_WORK" config user.email t@t
git -C "$BRK_WORK" config user.name t
echo '{"devDependencies":{}}' > "$BRK_WORK/package.json"
mkdir -p "$BRK_WORK/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BRK_WORK/node_modules/.bin/prettier"
chmod +x "$BRK_WORK/node_modules/.bin/prettier"
echo "export const x = 1" > "$BRK_WORK/src/thing.ts"
git -C "$BRK_WORK" add -A
git -C "$BRK_WORK" commit -qm init
# Branch off the base so the merge-base diff is non-empty and the SUITE lane is
# selected (a .ts outside .claude/ is non-inert).
git -C "$BRK_WORK" checkout -qb feature

reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
BRK_STATE="$STATECTL_STATE_DIR/$KEY.json"
# worktreePath is written ABSOLUTE via raw jq — fixture-only, matching
# verifyctl-selftest.sh: production paths are repo-relative via worktree-set, and
# verifyctl passes an absolute value through unchanged.
jq --arg wt "$BRK_WORK" '.worktreePath = $wt | .worktreeBase = "main"' "$BRK_STATE" > "$BRK_STATE.tmp"
mv "$BRK_STATE.tmp" "$BRK_STATE"
sct set-stage "$KEY" 6 --status started >/dev/null
touch "$BRK_MARKERS/FAIL_TEST"

# Charging is RETROSPECTIVE and needs a fresh HEAD. verifyctl charges the classes
# recorded in the EXISTING sidecar — i.e. the previous run's failures — because a
# re-invocation after a failed run IS the fix attempt being counted; and it writes
# `chargedHead` before incrementing, skipping the charge when that already equals
# HEAD. So the first run charges nothing (no prior sidecar), and a "fix" commit
# between attempts is required — which is what the real Stage-5 -> 6 loop does.
# Consequence, and the reason the ticket's "double TEST_FAILURE" phrasing is
# wrong: exhaustion surfaces on the FOURTH invocation, not the second.
brk_run() {  # $1 = a label used to make the commit unique; sets BRK_RC/BRK_VERDICT
  echo "// $1" >> "$BRK_WORK/src/thing.ts"
  git -C "$BRK_WORK" add -A
  git -C "$BRK_WORK" commit -qm "fix attempt $1"
  BRK_VERDICT=$(SECOND_SHIFT_CONFIG="$BRK/cfg.json" VERIFYCTL_TEST_MARKERS="$BRK_MARKERS" \
    PATH="$BRK/bin:$PATH" "$VERIFYCTL" run "$KEY" 2>/dev/null)
  BRK_RC=$?
}

brk_run a; rc1=$BRK_RC
brk_run b; rc2=$BRK_RC
brk_run c; rc3=$BRK_RC
n_after3=$(sct get "$KEY" '.verifyAttempts.TEST_FAILURE // 0')
[[ "$rc1" -ne 0 && "$rc2" -ne 0 && "$rc3" -ne 0 \
   && "$rc1" -ne 4 && "$rc2" -ne 4 && "$rc3" -ne 4 && "$n_after3" == "2" ]] \
  && pass "(cb1) failing runs charge TEST_FAILURE to the budget (2) without exhausting — real charging, real budget" \
  || fail "(cb1) charging — rc1=$rc1 rc2=$rc2 rc3=$rc3 TEST_FAILURE=$n_after3"

brk_run d; rc4=$BRK_RC; v4="$BRK_VERDICT"
brk_run e; rc5=$BRK_RC
cls=$(jq -r '.class // ""' <<< "$v4" 2>/dev/null)
stat4=$(jq -r '.status // ""' <<< "$v4" 2>/dev/null)
n_after5=$(sct get "$KEY" '.verifyAttempts.TEST_FAILURE // 0')
# The counter stays at 2 across both exhaustions: exit 4 precedes the charge. That
# is precisely why "two consecutive exhaustions" cannot be read back from state,
# and why the trigger stays prose (see the scope note above).
[[ "$rc4" -eq 4 && "$rc5" -eq 4 && "$cls" == "TEST_FAILURE" \
   && "$stat4" == "budget-exhausted" && "$n_after5" == "2" ]] \
  && pass "(cb2) two CONSECUTIVE budget exhaustions (exit 4, class TEST_FAILURE) with no clean run between" \
  || fail "(cb2) exhaustion — rc4=$rc4 rc5=$rc5 class='$cls' status='$stat4' TEST_FAILURE=$n_after5"

# The prose gate fires here. Its mechanical shadow — the terminal write — is what
# this harness can and does assert.
FCTX=$(sct build-failure-context --reason approach-failure-circuit-breaker --stage 6 \
  --kv failureClass=TEST_FAILURE --kv errorTail="FAIL src/thing.spec.ts")
rc=$(sct_rc mark-failed "$KEY" --reason approach-failure-circuit-breaker --stage 6 --json "$FCTX")
status=$(sct get "$KEY" '.status')
reason=$(sct get "$KEY" '.failureContext.reason')
stage6=$(sct get "$KEY" '.stages."6".status')
fclass=$(sct get "$KEY" '.failureContext.failureClass')
[[ "$rc" -eq 0 && "$status" == "failed" && "$reason" == "approach-failure-circuit-breaker" \
   && "$stage6" == "failed" && "$fclass" == "TEST_FAILURE" ]] \
  && pass "(cb3) breaker TERMINAL: status=failed, reason recorded, stage 6 marked failed (AC-1)" \
  || fail "(cb3) breaker terminal — rc=$rc status='$status' reason='$reason' stage6='$stage6' class='$fclass'"

# Non-vacuity: exit 4 must come from the failing suite, not from the fixture.
# Same repo, same config, marker cleared, a FRESH key so the budget starts at 0.
rm -f "$BRK_MARKERS/FAIL_TEST"
KEY=9007
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
BRK_STATE="$STATECTL_STATE_DIR/$KEY.json"
jq --arg wt "$BRK_WORK" '.worktreePath = $wt | .worktreeBase = "main"' "$BRK_STATE" > "$BRK_STATE.tmp"
mv "$BRK_STATE.tmp" "$BRK_STATE"
brk_run clean
n_clean=$(sct get "$KEY" '.verifyAttempts.TEST_FAILURE // 0')
[[ "$BRK_RC" -eq 0 && "$n_clean" == "0" ]] \
  && pass "(cb4) non-vacuity: a passing suite exits 0 and charges nothing (exit 4 tracked the failure)" \
  || fail "(cb4) clean run — rc=$BRK_RC TEST_FAILURE=$n_clean"

# ---------------------------------------------------------------------------
# Scenario: waived-run (#243) — a run that forced past a gate cannot reach the
# terminal `completed` write without explicit operator acceptance, and an
# autonomous-mode run cannot force at all. Composed-path, not per-tool: the
# per-invocation refusal/append invariants live in statectl-selftest.sh
# (fr*/am*/wv*/wfr*); what THIS scenario proves is that the waiver machinery and
# the terminal gates COMPOSE — a forced mid-walk bypass survives seven later
# stage transitions and still blocks the terminal write until --accept-waivers.

echo "[scenario-liveness] waived-run: a forced gate bypass blocks the terminal write until accepted"
KEY=9006
reset_state
sct init "$KEY" --run-id "scenario-liveness-$$" --mode auto >/dev/null

# (wv-auto) The autonomous arm: with state .mode=auto (exactly what the pipeline
# pre-flight records) and no env override, --force is refused outright — the
# executor cannot self-waive inside its own run.
err=$(sct_err set-stage "$KEY" 2 --status started --force --force-reason "scenario waived-run attempted autonomous self-waiver")
rc=$(sct_rc set-stage "$KEY" 2 --status started --force --force-reason "scenario waived-run attempted autonomous self-waiver")
[[ "$rc" -eq 1 && "$err" == *"refused in autonomous mode"* ]] \
  && pass "(wv-auto) autonomous run cannot force: state .mode=auto refuses the waiver outright" \
  || fail "(wv-auto) rc=$rc err='$err'"

# Attended path: the operator re-stamps interactive (the documented recovery),
# walks 1-8 green, then forces stage 9 closed without its pr receipt — the
# completion-evidence:9.commentReceipt.pr leg fires and is waived on record.
sct init "$KEY" --run-id ignored --mode interactive >/dev/null
for n in 1 2 3 4 5 6 7 8; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 9 --status started >/dev/null
sct set-stage "$KEY" 9 --status completed --force --force-reason "scenario waived-run operator skips the pr receipt" >/dev/null
waiver_n=$(sct get "$KEY" '.waivers // [] | length')
write_report_waived "$KEY"
write_eval "$KEY"

# The terminal write refuses — including under --force — while the waiver stands.
rc_plain=$(sct_rc mark-completed "$KEY")
rc_forced=$(sct_rc mark-completed "$KEY" --force --force-reason "scenario waived-run attempts to bypass the waiver refusal")
[[ "$waiver_n" -ge 1 && "$rc_plain" -eq 1 && "$rc_forced" -eq 1 ]] \
  && pass "(wv-block) waived run cannot reach terminal completed: plain and forced mark-completed both refused" \
  || fail "(wv-block) waivers=$waiver_n rc_plain=$rc_plain rc_forced=$rc_forced"

# Explicit acceptance is the ONLY exit: --accept-waivers completes the run and
# the acceptance itself is durable state.
rc=$(sct_rc mark-completed "$KEY" --accept-waivers)
status=$(sct get "$KEY" '.status')
acc_count=$(sct get "$KEY" '.waiversAccepted.count // 0')
[[ "$rc" -eq 0 && "$status" == "completed" && "$acc_count" -ge 1 ]] \
  && pass "(wv-accept) --accept-waivers is the only exit: terminal completed with waiversAccepted recorded" \
  || fail "(wv-accept) rc=$rc status='$status' acc_count=$acc_count"

# ---------------------------------------------------------------------------
# Scenario: jira zero-evidence guard (#243 AC-7) — the regression this issue
# exists to close: under tracker.writes:false the comment-receipt legs are
# exempt BY CONTRACT, and before #243 stages 3/7/9 carried no other evidence,
# so a read-only-tracker run closed a third of the pipeline on nothing but the
# executor's word. Composed: one walk, all three stages, each refused on zero
# evidence and completed on the tracker-independent state evidence — with not
# one comment posted.

echo "[scenario-liveness] jira-zero-evidence: stages 3/7/9 cannot close on nothing under a read-only tracker"
KEY=9007
reset_state
printf '%s' '{"configVersion": 2,"tracker":{"type":"jira","writes":false}}' > "$TMP/jira-zero-config.json"
export SECOND_SHIFT_CONFIG="$TMP/jira-zero-config.json"
sct init "$KEY" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 3 --status started >/dev/null
rc3_no=$(sct_rc set-stage "$KEY" 3 --status completed)
stage_evidence "$KEY" 3
rc3_ev=$(sct_rc set-stage "$KEY" 3 --status completed)
for n in 4 5 6; do complete_stage "$KEY" "$n"; done
sct set-stage "$KEY" 7 --status started >/dev/null
rc7_no=$(sct_rc set-stage "$KEY" 7 --status completed)
sct checkpoint "$KEY" 7 --json "$(jq -c --arg k "$KEY" '.ticketKey = $k' <<< "$VALID_PAYLOAD")" >/dev/null
stage_evidence "$KEY" 7
rc7_ev=$(sct_rc set-stage "$KEY" 7 --status completed)
complete_stage "$KEY" 8
sct set-stage "$KEY" 9 --status started >/dev/null
rc9_no=$(sct_rc set-stage "$KEY" 9 --status completed)
stage_evidence "$KEY" 9
rc9_ev=$(sct_rc set-stage "$KEY" 9 --status completed)
gated_receipts=$(sct get "$KEY" '.comments // {} | (has("plan") or has("doc-update") or has("pr"))')
unset SECOND_SHIFT_CONFIG
[[ "$rc3_no" -eq 1 && "$rc3_ev" -eq 0 && "$rc7_no" -eq 1 && "$rc7_ev" -eq 0 && "$rc9_no" -eq 1 && "$rc9_ev" -eq 0 ]] \
  && pass "(jz1) jira zero-evidence guard: stages 3/7/9 each refused empty and completed on state evidence (AC-7)" \
  || fail "(jz1) jira guard — 3:$rc3_no/$rc3_ev 7:$rc7_no/$rc7_ev 9:$rc9_no/$rc9_ev"

# Non-vacuity: none of the three gated stages carries a comment receipt — the
# evidence that closed them was tracker-independent state, not a laundered
# receipt. (complete_stage plants receipts for stages 1/8 regardless of the
# tracker; those are fixture artifacts outside the stages under test.)
[[ "$gated_receipts" == "false" ]] \
  && pass "(jz2) non-vacuity: no plan/doc-update/pr receipt exists on the jira walk" \
  || fail "(jz2) a gated-stage receipt exists on a writes:false walk"

# =================================== predecessor gate: pre-claim ordering (AC-6) ===
# The sub-issues-sequential backstop. Ordering normally works by keeping blocked
# successors OUT of the queue (sequential sub-issues N>1 are created without the
# queue label); this gate catches the EARLY-LABELED successor that reaches the queue
# anyway. What must compose: the gate's verdict and the CLAIM WRITES, so that a
# blocked candidate leaves behind none of the claim's durable traces.
#
# The assertion target is the "not picked up" shape — no claim receipt and NO state
# file at all. That is deliberately distinct from the two other non-completing
# shapes this suite already covers: the `failed` terminal (a state file exists,
# status=failed) and the sub-issues carve-out (a state file exists, status stays
# in_progress). A blocked successor must look like neither: nothing was claimed, so
# nothing was written.
#
# Scope boundary (see the header): Stage 1's queue loop is PROSE executed via `gh`,
# so it is not drivable here and is deliberately NOT re-implemented — a harness-side
# copy of the loop could never fail on a Stage-1 edit. What IS drivable is the
# mechanical shadow: the real tool's verdict per candidate, and the state each
# verdict does or does not produce. The two candidates below are therefore driven
# straight-line, not in a loop.

echo "[scenario-liveness] predecessor: open predecessor skips pre-claim; closed one claims"
reset_state

# The successor's body, exactly the shape create-sub-tickets writes for a sequential
# sub-issue N>1 (Part-of anchor + both trailers).
PG_BODY=$'Part of #9030\n\nWork for the second sub-issue.\n\nPredecessor: #9031\nSuccessor: #9033'

# --- candidate A: predecessor OPEN -> skip-blocked, claim nothing ----------------
PG_A=9032
pg_extract=$(printf '%s\n' "$PG_BODY" | bash "$PRED_GATE" extract 2>/dev/null)
pg_pred=$(printf '%s\n' "$pg_extract" | sed -n 's/^predecessor=//p')
[[ "$pg_pred" == "9031" ]] \
  && pass "(pg-x1) extract lifts the predecessor key off a real sequential sub-issue body (AC-6)" \
  || fail "(pg-x1) extract — got '$pg_pred' (want 9031)"

# The stage doc pays the predecessor-state read only because a key was printed; the
# state itself is fixture input here (the tool is pure logic — nothing to mock).
bash "$PRED_GATE" verdict open >/dev/null 2>&1; pg_rc_open=$?
if [[ "$pg_rc_open" -eq 0 ]]; then
  # Would-be claim writes. Guarded by the verdict, exactly as Stage 1 guards them.
  sct init "$PG_A" --run-id "scenario-liveness-$$" >/dev/null
  sct comment-add "$PG_A" --marker claimed --url "https://example.invalid/issues/$PG_A#issuecomment-1" >/dev/null
fi
[[ "$pg_rc_open" -eq 3 ]] \
  && pass "(pg-skip1) open predecessor -> verdict exit 3 (skip-blocked, do not claim) (AC-6)" \
  || fail "(pg-skip1) open predecessor — rc=$pg_rc_open (want 3)"

[[ ! -f "$STATECTL_STATE_DIR/$PG_A.json" ]] \
  && pass "(pg-skip2) blocked successor leaves NO state file — the not-picked-up shape, not \`failed\` and not the carve-out (AC-6)" \
  || fail "(pg-skip2) a state file exists for the blocked successor $PG_A"

# --- candidate B: the next queue candidate, unblocked -> claims -----------------
# Its own body carries no Predecessor trailer, so the conditional predecessor-state
# read is never paid and the run proceeds. This is the mechanical shadow of "advance
# to the next candidate": A produced nothing, B produced the claim.
PG_B=9034
PG_B_BODY=$'An ordinary queued issue with no ordering trailers.'
pg_b_extract=$(printf '%s\n' "$PG_B_BODY" | bash "$PRED_GATE" extract 2>/dev/null)
[[ -z "$pg_b_extract" ]] \
  && pass "(pg-go1) a candidate with no trailers prints nothing — the predecessor-state read is never paid (AC-6)" \
  || fail "(pg-go1) unblocked candidate — got '$pg_b_extract' (want empty)"

sct init "$PG_B" --run-id "scenario-liveness-$$" >/dev/null
sct comment-add "$PG_B" --marker claimed --url "https://example.invalid/issues/$PG_B#issuecomment-1" >/dev/null
pg_b_receipt=$(sct get "$PG_B" '.comments.claimed // empty')
[[ -f "$STATECTL_STATE_DIR/$PG_B.json" && -n "$pg_b_receipt" ]] \
  && pass "(pg-go2) the next candidate claims: state file + claim receipt both exist (AC-6)" \
  || fail "(pg-go2) next candidate — file=$([[ -f "$STATECTL_STATE_DIR/$PG_B.json" ]] && echo y || echo n) receipt='$pg_b_receipt'"

# --- non-vacuity ---------------------------------------------------------------
# (pg-skip2) asserts an ABSENCE, which would pass trivially if this harness simply
# never wrote a state file for $PG_A. Drive the IDENTICAL path with only the
# predecessor's state flipped to `closed`: the same guarded writes must now produce
# the file. If this case cannot flip, (pg-skip2) proves nothing and must not be
# counted toward AC-6. Precondition-variation, per (ss6)/(ns3) — the suite never
# deletes or mutates production code on disk to make a point.
bash "$PRED_GATE" verdict closed >/dev/null 2>&1; pg_rc_closed=$?
if [[ "$pg_rc_closed" -eq 0 ]]; then
  sct init "$PG_A" --run-id "scenario-liveness-$$" >/dev/null
  sct comment-add "$PG_A" --marker claimed --url "https://example.invalid/issues/$PG_A#issuecomment-1" >/dev/null
fi
pg_a_receipt=$(sct get "$PG_A" '.comments.claimed // empty')
[[ "$pg_rc_closed" -eq 0 && -f "$STATECTL_STATE_DIR/$PG_A.json" && -n "$pg_a_receipt" ]] \
  && pass "(pg-nv) non-vacuity: the same path with the predecessor CLOSED does write the state file + receipt — the skip came from the gate (AC-6)" \
  || fail "(pg-nv) non-vacuity — rc=$pg_rc_closed file=$([[ -f "$STATECTL_STATE_DIR/$PG_A.json" ]] && echo y || echo n) receipt='$pg_a_receipt'"

# =================================== tracker reconcile check: resume (#149) ========
# A run whose session died in the Stage-9 tail (after `gh pr create`, before `pr-add`
# / `mark-completed`) leaves `status: in_progress` even though the tracker already
# shows the issue closed via a merged PR. What must compose: the pure-logic verdict
# tool's decision, feeding `statectl reclaim --release` (the pre-existing quarantine
# mechanism, unmodified here) — and reclaim's own attended-only `--force` gate must
# still hold, so an autonomous reconcile never force-quarantines a run that might
# still be within the staleness grace window.
#
# Two shapes, mirroring statectl-selftest.sh's (rec3)/(rec5): a stale run quarantines
# cleanly; a fresh run's plain (non-forced) reclaim attempt is refused and the state
# file is left untouched — proving the reconcile logic does not silently bypass
# reclaim's existing safety gate to force a quarantine.

echo "[scenario-liveness] tracker-reconcile: stale in_progress + tracker-closed-via-PR quarantines; fresh does not"
TRK=9040

# --- stale case: reconcile-recommended -> reclaim --release succeeds -----------
reset_state
sct init "$TRK" --run-id "scenario-liveness-$$" >/dev/null

trk_verdict=$(bash "$TRACKER_CHECK" verdict in_progress true 155 https://example.invalid/pull/155 2>/dev/null)
trk_rc=$?
[[ "$trk_rc" -eq 4 && "$trk_verdict" == $'verdict=reconcile-recommended\nclosingPrNumber=155\nclosingPrUrl=https://example.invalid/pull/155' ]] \
  && pass "(trk1) tracker-closed-via-PR on an in_progress run -> reconcile-recommended, rc=4, PR fields carried (#149)" \
  || fail "(trk1) tracker check — rc=$trk_rc verdict='$trk_verdict'"

# --threshold-min 0 makes a fresh run immediately stale, same idiom as (rec3) —
# the composed path never depends on real wall-clock time.
rel=$("$STATECTL" reclaim "$TRK" --release --threshold-min 0 2>/dev/null)
rel_rc=$?
released_to=$(jq -r '.quarantinedTo // ""' <<< "$rel" 2>/dev/null)
rel_count=$(find "$STATECTL_STATE_DIR" -maxdepth 1 -name "${TRK}-released-*.json" | wc -l | tr -d ' ')
[[ "$rel_rc" -eq 0 && ! -f "$STATECTL_STATE_DIR/$TRK.json" && "$rel_count" == "1" && "$released_to" == "$TRK-released-"*".json" ]] \
  && pass "(trk2) reconcile-recommended -> reclaim --release quarantines: original gone, one {key}-released-*.json exists (#149)" \
  || fail "(trk2) reclaim --release after reconcile — rc=$rel_rc released_to='$released_to' count=$rel_count"

# perf-retro's corpus filter excludes `*-released-*` by name alone (SKILL.md
# "Step 1: Gather the corpus") — assert the quarantined name actually matches the
# same glob the corpus loop tests, so this scenario proves the corpus-corruption
# angle is closed, not merely that reclaim renamed something.
case "$released_to" in
  *-released-*) pass "(trk3) quarantined filename matches perf-retro's \`*-released-*\` corpus exclusion (#149)" ;;
  *)            fail "(trk3) quarantined filename '$released_to' does NOT match \`*-released-*\`" ;;
esac
find "$STATECTL_STATE_DIR" -maxdepth 1 -name "${TRK}-released-*.json" -delete

# --- fresh case: reconcile-recommended -> plain reclaim --release is refused ----
# Non-vacuity for (trk2): drive the identical reconcile-recommended verdict against
# a run reclaim does NOT consider stale (default 30-min threshold, no backdating),
# and the state file must survive untouched — the reconcile path must not force
# past reclaim's own attended-only gate just because the tracker says so.
TRK2=9041
reset_state
sct init "$TRK2" --run-id "scenario-liveness-$$" >/dev/null

trk2_rc=$(bash "$TRACKER_CHECK" verdict in_progress true 200 https://example.invalid/pull/200 >/dev/null 2>&1; echo $?)
[[ "$trk2_rc" -eq 4 ]] \
  && pass "(trk4) same reconcile-recommended verdict on a run reclaim does NOT consider stale" \
  || fail "(trk4) tracker check on the fresh fixture — rc=$trk2_rc (want 4)"

rc_rel_fresh=$(sct_rc reclaim "$TRK2" --release)
[[ "$rc_rel_fresh" -ne 0 && -f "$STATECTL_STATE_DIR/$TRK2.json" ]] \
  && pass "(trk5) non-vacuity: plain (non-forced) reclaim --release on a fresh run is refused, state file untouched — reconcile never bypasses reclaim's own gate (#149)" \
  || fail "(trk5) fresh reclaim --release — rc=$rc_rel_fresh file-present=$([[ -f "$STATECTL_STATE_DIR/$TRK2.json" ]] && echo y || echo n)"

# ─────────────────────────────────────────────────────────────────────────────
# LEAN LEGS (run-lean) — the composed progress-file line chain and gate exit codes
# across the three verdict paths.
#
# These are the assertion site for the failure economics the issue pins in PROSE but
# no AC-n carries: the fix budget of 3, the 4th-red hard stop, the abort record, and
# counters surviving re-entry. A per-tool fixture proves one gate in isolation; only a
# composed leg proves the CHAIN a real run walks.
#
# The all-green leg is also AC-15's assertion site: the claim is executed by the session
# following SKILL.md rather than by a gate, so this is where the second bot-wrapper write
# is checked (the label swap itself is claim-issue.sh's contract, proven by claim-selftest.sh).
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "── lean legs (run-lean)"

# $HERE, not BASH_SOURCE: this suite cd's to $TMP above, so BASH_SOURCE is relative by the
# time we get here and would resolve against the temp dir. $HERE was captured absolutely
# before that cd for exactly this reason.
#
# Absence is a FAILURE, not a skip. run-lean ships in this repo, so a missing gate means the
# legs below never ran — and a skipped leg reporting PASS is the vacuous green this whole
# suite exists to prevent. (It bit these very legs once: a bad path resolved to a skip and
# the suite reported 32/32 having asserted nothing about lean.)
LEAN_GATE="$HERE/../run-lean/lean-gate.sh"
if [[ ! -x "$LEAN_GATE" ]]; then
  fail "(lean) lean-gate.sh not found or not executable at $LEAN_GATE — the lean legs did not run"
else
  LEAN_TREE="$TMP/lean-tree"
  mkdir -p "$LEAN_TREE/docs/plans" "$LEAN_TREE/.claude/audit"
  git -C "$LEAN_TREE" init -q
  LEAN_CFG="$TMP/lean-config.json"
  cat > "$LEAN_CFG" <<'LEANCFG'
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
LEANCFG
  LEAN_PROG="$TMP/lean-progress.md"
  # No Open Regions section, so milestone 1's pause-and-ask check (#374) no-ops before it would
  # ever need a live `gh issue view` or comment-trail fetch — these legs are zero-network by
  # construction, same reasoning as lean-gate-selftest.sh's own default. --issue-file is FIRST,
  # so a leg's own --issue-file in "$@" is a later occurrence and overrides it.
  LEAN_ISSUE_NOREGIONS="$TMP/lean-issue-noregions.json"
  printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$LEAN_ISSUE_NOREGIONS"
  # #416: the build-role precondition reads an entry attestation these legs must now COMPOSE,
  # not seed — which means a live per-session ledger and a session id the legs control. Pinning
  # it here (rather than inheriting the ambient one) is what makes the legs behave identically
  # in a Claude Code session, where CLAUDE_CODE_SESSION_ID is exported, and in CI, where it is
  # not: the fixture's session identity is always the fixture's.
  LEAN_SID="sess-lean-build"
  printf '{"tool":"Bash"}\n' > "$LEAN_TREE/.claude/audit/$LEAN_SID.jsonl"
  lean_gate() { ( cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
                  CLAUDE_CODE_SESSION_ID="$LEAN_SID" \
                  bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 ); }
  lean_count() { if [[ -f "$LEAN_PROG" ]]; then local n; n=$(grep -cF "$1" "$LEAN_PROG" 2>/dev/null) || n=0; echo "$n"; else echo 0; fi; }

  LEAN_SPEC="$LEAN_TREE/docs/plans/acme-77-lean.md"
  LEAN_VERDICT="$LEAN_TREE/docs/plans/acme-77-lean-verdict.md"

  # The verdict record is REVIEW-authored throughout these legs. run-lean's build session
  # cannot produce it, so a leg composing a build-authored record would compose a state no
  # real run can reach — and the chain would prove nothing about the run it claims to model.
  # The build identities are seeded explicitly rather than left to the gate's stamping, so
  # the authorship comparison has two known sides in every leg.
  lean_seed_progress() { # lean_seed_progress <build-run-id> <build-session-id>
    rm -f "$LEAN_PROG"
    { echo "# lean run — issue 77"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$LEAN_PROG"
    # The entry attestation comes from the REAL `entry` subcommand, never a seeded line: a
    # hand-written row would keep every leg green after the writer and the reader drifted apart,
    # which is the shape of failure #416 itself was.
    lean_gate entry 77 >/dev/null 2>&1
  }
  # The same header WITHOUT the attestation — the state a run that skipped step 1 is in, and the
  # only thing the refusal leg below varies.
  lean_seed_unattested() { # lean_seed_unattested <build-run-id> <build-session-id>
    rm -f "$LEAN_PROG"
    { echo "# lean run — issue 77"; echo ""; echo "run_id: $1"; echo "session_id: $2"; } > "$LEAN_PROG"
  }
  # Milestone 4 binds the record to a tree: it must be COMMITTED and nothing but the record
  # itself may have changed since. So the legs commit, and each verdict write advances a round
  # counter — an identical re-write stages nothing, which would leave the record holding an
  # earlier round's commit while the tree moved on and red the leg on freshness instead of on
  # what it composes.
  git -C "$LEAN_TREE" config user.email lean@example.invalid
  git -C "$LEAN_TREE" config user.name lean-scenario
  printf '.claude/\n' > "$LEAN_TREE/.gitignore"
  lean_commit() { git -C "$LEAN_TREE" add -A >/dev/null 2>&1
                  git -C "$LEAN_TREE" commit -q --allow-empty -m "${1:-lean fixture}" >/dev/null 2>&1; }
  lean_commit "lean fixture tree"
  # The patch-id freshness arm measures the branch's diff from merge-base(origin/<base>, HEAD),
  # so the fixture carries the remote-tracking ref a real checkout would have. Leg 7 composes
  # that arm; every other leg writes records without the key and takes the SHA fallback.
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main HEAD
  # `reviewed_head` is resolved BEFORE the commit, which is the shape a real round has: the
  # reviewer reads the current head, names it, and commits the record on top of it. Resolving it
  # after would name the record's own commit and leave the declared arm asserting nothing.
  LEAN_ROUND=0
  lean_write_verdict() { # lean_write_verdict <verdict> <run-id> <session-id> [reviewed-head]
    LEAN_ROUND=$((LEAN_ROUND + 1))
    printf 'verdict=%s\nrun_id: %s\nsession_id: %s\nrounds: %s\nreviewed_head: %s\n' \
      "$1" "$2" "$3" "$LEAN_ROUND" "${4:-$(git -C "$LEAN_TREE" rev-parse HEAD)}" > "$LEAN_VERDICT"
    lean_commit "review verdict $1 (round $LEAN_ROUND)"
  }

  # ---- leg 1: all-green -> exit artifacts ----------------------------------
  lean_seed_progress r-lean-1 sess-lean-build
  printf '# spec\n\n- AC-1: a thing\n' > "$LEAN_SPEC"
  # The spec is committed on its OWN, before the review reads it. `lean_commit` stages
  # everything, so folding it into the verdict commit would put a code change inside the record's
  # commit — a shape review-lean step 6 forbids and both freshness arms refuse. What is left is
  # the state a real branch is in the moment the review session has pushed: the record's commit
  # is the head, and the head it names is the commit right below it.
  lean_commit "build session pushes the spec"
  lean_write_verdict approve r-lean-review-1 sess-lean-review
  cat > "$TMP/lean-pr.json" <<'LEANPR'
[{ "number": 5, "url": "https://example.invalid/pr/5", "isDraft": false,
   "body": "Closes #77\n\nSpec: docs/plans/acme-77-lean.md" }]
LEANPR
  cat > "$TMP/lean-comments.json" <<'LEANC'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-lean-1 -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-77-lean-verdict.md" }]
LEANC
  lean_gate 1 77 >/dev/null 2>&1; g1=$?
  lean_gate 2 77 >/dev/null 2>&1; g2=$?
  lean_gate 3 77 >/dev/null 2>&1; g3=$?
  lean_gate 4 77 >/dev/null 2>&1; g4=$?
  lean_gate 5 77 --pr-file "$TMP/lean-pr.json" --comments-file "$TMP/lean-comments.json" >/dev/null 2>&1; g5=$?
  [[ "$g1$g2$g3$g4$g5" == "00000" ]] \
    && pass "(lean-green) milestones 1-5 all exit 0 on a complete run" \
    || fail "(lean-green) exit codes were $g1$g2$g3$g4$g5, expected 00000"

  lean_sat=0
  for m in 1 2 3 4 5; do
    [[ "$(lean_count "| milestone-$m | satisfied")" -eq 1 ]] && lean_sat=$((lean_sat + 1))
  done
  [[ "$lean_sat" -eq 5 ]] \
    && pass "(lean-green) the progress-file chain carries exactly one satisfied line per milestone" \
    || fail "(lean-green) expected 5 single satisfied lines, got $lean_sat"

  # #392, green-with-notice verdict path. This fixture configures no verify lane at all, so the
  # chain above only reaches milestone 3's green gate through the `allowUnverified` opt-out —
  # a green run that verified nothing, legitimate solely because it was DECLARED. The
  # declaration has to survive into the artifact a reconcile reads; without this assertion the
  # opt-out path is traversed by the composed run and pinned by nothing.
  [[ "$(lean_count "| milestone-3 | skipped | no verifying lane configured")" -eq 1 ]] \
    && pass "(lean-zv-skip) the declared zero-lane opt-out composes into a recorded progress line" \
    || fail "(lean-zv-skip) the composed green run left no opt-out record in $LEAN_PROG"

  # AC-15's second write. What is pinned is not "a comment exists" but that it is
  # BOT-authored and carries the run id — an operator-posted comment is invisible to the
  # merge-boundary gate's trust filter, so it would not be evidence at all.
  claim_ok=$(jq -r '[ .[] | select(.user.type == "Bot")
                          | select((.body // "") | test("stage:[[:space:]]*lean-claimed"))
                          | select((.body // "") | test("run_id:[[:space:]]*[A-Za-z0-9._-]+")) ] | length' \
             "$TMP/lean-comments.json")
  [[ "$claim_ok" -ge 1 ]] \
    && pass "(lean-claim) the claim trail carries a bot-authored lean-claimed marker with a run id (AC-15)" \
    || fail "(lean-claim) no bot-authored lean-claimed comment with a run id"

  # The marker must be lean-DISTINCT: a bare `stage: claimed` would pollute the pipeline
  # chain gate's run-family selection if this issue later runs through full `run`.
  polluting=$(jq -r '[ .[] | select((.body // "") | test("stage:[[:space:]]*claimed[[:space:]]*-->")) ] | length' \
              "$TMP/lean-comments.json")
  [[ "$polluting" -eq 0 ]] \
    && pass "(lean-claim) the marker is lean-distinct — no bare 'stage: claimed' to pollute pipeline family selection" \
    || fail "(lean-claim) a bare 'stage: claimed' marker would pollute pipeline family selection"

  # ---- leg 2: budget exhaustion -> abort record ----------------------------
  lean_seed_progress r-lean-1 sess-lean-build
  mv "$LEAN_VERDICT" "$TMP/held-lean-verdict.md"
  lean_rcs=""
  for _ in 1 2 3 4; do lean_gate 4 77 >/dev/null 2>&1; lean_rcs="$lean_rcs$?"; done
  [[ "$lean_rcs" == "1114" ]] \
    && pass "(lean-budget) 3 fix attempts then a 4th-red hard stop (rc=4) — the prose-only fix budget, asserted" \
    || fail "(lean-budget) exit sequence was $lean_rcs, expected 1114"
  [[ "$(lean_count 'budget-exhausted')" -ge 1 ]] \
    && pass "(lean-budget) the abort record lands in the progress file" \
    || fail "(lean-budget) no budget-exhausted record written"
  [[ "$(lean_count '| milestone-4 | satisfied')" -eq 0 ]] \
    && pass "(lean-budget) an exhausted milestone records no satisfied line — an abort is not a pass" \
    || fail "(lean-budget) an exhausted milestone was also recorded satisfied"

  # ---- leg 3: needs-work -> fix-loop re-entry ------------------------------
  # Round 2 arrives from a NEW review context, so it carries a new review identity — that is
  # what "a new review context produces the next verdict" means in artifact terms.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict needs-work r-lean-review-1 sess-lean-review
  lean_gate 4 77 >/dev/null 2>&1; nw1=$?
  lean_write_verdict approve r-lean-review-2 sess-lean-review-2
  lean_gate 4 77 >/dev/null 2>&1; nw2=$?
  [[ "$nw1" -eq 1 && "$nw2" -eq 0 ]] \
    && pass "(lean-fixloop) a needs-work verdict blocks (rc=1) and re-entry after the fix passes (rc=0)" \
    || fail "(lean-fixloop) expected rc 1 then 0, got $nw1 then $nw2"
  [[ "$(lean_count '| milestone-4 | attempt |')" -eq 1 ]] \
    && pass "(lean-fixloop) the failed round is still counted after re-entry (counters survive resume)" \
    || fail "(lean-fixloop) the surviving attempt counter was lost across re-entry"

  # ---- leg 4: P10 — the same chain reds on a build-authored verdict ---------
  # The composed counterpart to lean-gate-selftest's (n) cases. Everything else in leg 1 is
  # left exactly as it was; ONLY the verdict's authorship changes, so a green here would mean
  # the milestone-4 link in the chain is not carrying the check at all.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-1 sess-lean-review
  lean_gate 4 77 >/dev/null 2>&1; auth1=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; auth2=$?
  [[ "$auth1" -eq 1 && "$auth2" -eq 1 ]] \
    && pass "(lean-authorship) the chain reds when the verdict carries the build run's id or names its session" \
    || fail "(lean-authorship) expected rc 1 and 1, got $auth1 then $auth2"

  # ---- leg 5: the chain reds on a STALE verdict, and a new round clears it --
  # The composed counterpart to lean-gate-selftest's (t) cases, and the one failure this
  # separation created rather than removed: with review in its own session, "verdict, then
  # more commits" is the ordinary shape of the needs-work loop, so an approve for an earlier
  # head reaching a green chain is the default outcome unless something binds the two.
  # Everything else in leg 1 is left as it was; ONLY a later commit is added.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-3 sess-lean-review-3
  lean_gate 4 77 >/dev/null 2>&1; fresh1=$?
  printf '# spec\n\n- AC-1: a thing\n- AC-2: added after the review\n' > "$LEAN_SPEC"
  lean_commit "code lands after the verdict"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; fresh2=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-4 sess-lean-review-4
  lean_gate 4 77 >/dev/null 2>&1; fresh3=$?
  [[ "$fresh1" -eq 0 && "$fresh2" -eq 1 && "$fresh3" -eq 0 ]] \
    && pass "(lean-freshness) a verdict covering the head passes, one predating a later commit reds, a new round clears it" \
    || fail "(lean-freshness) expected rc 0/1/0, got $fresh1 then $fresh2 then $fresh3"

  # ---- leg 6: the chain reds on a verdict that DECLARES an earlier head -----
  # Leg 5 composes the INFERRED freshness arm — git decides which commit carries the record.
  # This leg composes the DECLARED one, and it is constructed so leg 5's arm is GREEN over it:
  # the record is committed LAST, so its commit IS the head and nothing but the record differs
  # from it. Only the head the record NAMES is stale. That is not a contrived shape — it is what
  # a review round produces whenever a fix lands while the review is still running, and it is
  # the residual the inferred arm cannot see. Everything else is left as leg 1 had it.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_stale_head="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  printf '# spec\n\n- AC-1: a thing\n- AC-3: landed while the review was running\n' > "$LEAN_SPEC"
  lean_commit "code lands between the review and the record"
  lean_write_verdict approve r-lean-review-5 sess-lean-review-5 "$lean_stale_head"
  lean_gate 4 77 >/dev/null 2>&1; decl1=$?
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-6 sess-lean-review-6
  lean_gate 4 77 >/dev/null 2>&1; decl2=$?
  [[ "$decl1" -eq 1 && "$decl2" -eq 0 ]] \
    && pass "(lean-declared) a record whose own commit IS the head still reds when it names an earlier reviewed_head, and a re-declared round clears it" \
    || fail "(lean-declared) expected rc 1 then 0, got $decl1 then $decl2"

  # ...and the migration arm: a record with no reviewed_head at all is refused, not grandfathered.
  lean_seed_progress r-lean-1 sess-lean-build
  printf 'verdict=approve\nrun_id: r-lean-review-7\nsession_id: sess-lean-review-7\nrounds: 7\n' > "$LEAN_VERDICT"
  lean_commit "a key-less record, as written before reviewed_head existed"
  lean_gate 4 77 >/dev/null 2>&1; decl3=$?
  [[ "$decl3" -eq 1 ]] \
    && pass "(lean-declared) a verdict record predating the reviewed_head key is refused, not grandfathered" \
    || fail "(lean-declared) expected rc=1 on a key-less record, got $decl3"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-8 sess-lean-review-8

  # ---- leg 7: the PATCH-ID declared arm, composed across a real rebase ------
  # Legs 5 and 6 compose the two freshness arms over records that carry no `reviewed_patch_id`,
  # so both take the SHA fallback. This leg composes the arm records written by the current
  # writer actually take — and it composes it across the operation that arm exists for.
  #
  # The record comes from the REAL `verdict` subcommand rather than a printf: the id it stamps is
  # the thing milestone 4 recomputes, so a leg that hand-wrote one would compose a record no
  # review session produces. The write is refused unless the review identity is distinct from the
  # build's on both axes, which is why the two are seeded explicitly here as everywhere else.
  lean_seed_progress r-lean-1 sess-lean-build
  rm -f "$LEAN_TREE/.claude/pipeline-state/77-review-run-id"
  ( cd "$LEAN_TREE" && SECOND_SHIFT_CONFIG="$LEAN_CFG" LEAN_PROGRESS_FILE="$LEAN_PROG" \
    CLAUDE_CODE_SESSION_ID=sess-lean-review-9 RUN_ID=r-lean-review-9 \
    bash "$LEAN_GATE" verdict 77 --pr 5 --verdict approve >/dev/null 2>&1 ); pid_write=$?
  lean_commit "review session commits its patch-id-keyed record"
  lean_gate 4 77 >/dev/null 2>&1; pid1=$?

  # A REAL rebase onto a base that moved with content. A same-tree base would leave the pre- and
  # post-rebase trees identical, so the SHA arm would pass too and the leg would compose nothing.
  lean_branch="$(git -C "$LEAN_TREE" symbolic-ref --short HEAD 2>/dev/null)"
  lean_pre_rebase="$(git -C "$LEAN_TREE" rev-parse HEAD)"
  git -C "$LEAN_TREE" branch -f lean-base refs/remotes/origin/main >/dev/null 2>&1
  git -C "$LEAN_TREE" checkout -q lean-base 2>/dev/null
  printf 'the base moved while the review was in flight\n' > "$LEAN_TREE/base-moved.txt"
  git -C "$LEAN_TREE" add base-moved.txt >/dev/null 2>&1
  git -C "$LEAN_TREE" commit -q -m 'base advances' >/dev/null 2>&1
  git -C "$LEAN_TREE" update-ref refs/remotes/origin/main lean-base
  git -C "$LEAN_TREE" checkout -q "$lean_branch" 2>/dev/null
  git -C "$LEAN_TREE" rebase -q lean-base >/dev/null 2>&1; lean_rebased=$?
  # The SHA arm would red here: the pre-rebase commit is still an object in this repo, but its
  # tree now differs from the head by the base's commit. If that diff is empty the leg is vacuous.
  lean_sha_would_red="$(git -C "$LEAN_TREE" diff --name-only "$lean_pre_rebase" HEAD 2>/dev/null)"
  lean_seed_progress r-lean-1 sess-lean-build
  lean_gate 4 77 >/dev/null 2>&1; pid2=$?

  # ...and the arm is still a gate: a commit after the approve moves the patch and reds it.
  lean_seed_progress r-lean-1 sess-lean-build
  printf '# spec\n\n- AC-1: a thing\n- AC-4: landed after the approve\n' > "$LEAN_SPEC"
  lean_commit "code lands after the approve"
  lean_gate 4 77 >/dev/null 2>&1; pid3=$?

  [[ "$pid_write" -eq 0 && "$lean_rebased" -eq 0 && -n "$lean_sha_would_red" \
     && "$pid1" -eq 0 && "$pid2" -eq 0 && "$pid3" -eq 1 ]] \
    && pass "(lean-patch-id) a review-written record passes, survives a rebase the SHA arm would have redded, and still reds once a commit changes the branch" \
    || fail "(lean-patch-id) write=$pid_write rebase=$lean_rebased sha-arm-diff='$lean_sha_would_red' rcs=$pid1/$pid2/$pid3, expected 0/0/nonempty/0/0/1"

  # Restore the SHA-fallback shape the remaining legs were written against.
  lean_seed_progress r-lean-1 sess-lean-build
  lean_write_verdict approve r-lean-review-10 sess-lean-review-10

  # ---- non-vacuity ---------------------------------------------------------
  # An all-green leg that stays green over a broken tree proves nothing.
  lean_seed_progress r-lean-1 sess-lean-build
  mv "$LEAN_SPEC" "$TMP/held-lean-spec.md"
  lean_gate 1 77 >/dev/null 2>&1; lean_nv=$?
  [[ "$lean_nv" -ne 0 ]] \
    && pass "(lean-nv) non-vacuity: the same leg reds when the spec is absent" \
    || fail "(lean-nv) milestone-1 passed with no spec — the lean legs are vacuous"
  mv "$TMP/held-lean-spec.md" "$LEAN_SPEC"

  # ---- leg 3b: the entry precondition, composed (#416) ----------------------
  # CLAUDE.md: a new gate contract extends the liveness scenario for every verdict path it
  # touches. This is that leg. The per-tool suite proves the refusal in isolation against one
  # milestone; what only a composed leg can show is that a run which skipped step 1 is stopped
  # at the call a REAL run makes — `all`, the whole-progression entry point a resume re-enters
  # through — and stopped there WITHOUT charging a fix attempt, before any milestone body runs.
  #
  # The tree here is fully green: leg 1 above just walked milestones 1-5 to completion on it.
  # So the ONLY thing that reds this is the missing row, which is what makes the pairing below
  # evidence rather than coincidence.
  lean_seed_unattested r-lean-1 sess-lean-build
  lean_gate all 77 >/dev/null 2>&1; ea_all=$?
  lean_gate 4 77 >/dev/null 2>&1; ea_m4=$?
  ea_attempts=$(grep -cF '| milestone-' "$LEAN_PROG" 2>/dev/null) || ea_attempts=0
  # ...and the same tree, one `entry` call later, walks the whole progression again.
  lean_seed_progress r-lean-1 sess-lean-build
  ea_healed_out="$(lean_gate 1 77)"; ea_healed=$?
  [[ "$ea_all" -eq 2 && "$ea_m4" -eq 2 && "$ea_attempts" -eq 0 && "$ea_healed" -eq 0 ]] \
    && pass "(lean-entry) an unattested run is refused at 'all' and at a milestone with exit 2, records nothing, and self-heals after one idempotent entry call" \
    || fail "(lean-entry) all=$ea_all m4=$ea_m4 milestone-lines=$ea_attempts healed=$ea_healed, expected 2/2/0/0: $ea_healed_out"

  # ---- leg 4: the jira adapter, composed end to end ------------------------
  # The three adapter branch sites are proven in ISOLATION by lean-gate-selftest.sh's (n*)
  # cases. What only a composed leg can show is that they CHAIN: that the progress file
  # cmd_claim creates while making zero tracker writes is the same file milestones 1-5 later
  # satisfy, and that the milestones documented as adapter-INSENSITIVE really are — under an
  # alphanumeric ticket key, where every derived path (docs/plans/acme-ACME-7-lean.md) has a
  # different shape than the numeric case the other legs walk. Those are prose claims at
  # three surfaces with no oracle behind them until here.
  LEAN_CFG_J="$TMP/lean-config-jira.json"
  cat > "$LEAN_CFG_J" <<'LEANCFGJ'
{
  "tracker": { "type": "jira", "writes": false, "branchPrefix": "abc/", "keyPattern": "[A-Z]+-[0-9]+" },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } }
}
LEANCFGJ
  LEAN_PROG_J="$TMP/lean-progress-jira.md"
  LEAN_JKEY="ACME-7"
  # env -u GH_BOT is load-bearing, not hygiene: the github arm dies on `${GH_BOT:?}`, so a leg
  # that completes without it in the environment is evidence the jira arm never reached there.
  # CLAUDE_CODE_SESSION_ID is the BUILD identity — `claim` stamps it into the progress file, and
  # milestone 4 compares it against the review session id in the committed record.
  lean_gate_j() { ( cd "$LEAN_TREE" && env -u GH_BOT SECOND_SHIFT_CONFIG="$LEAN_CFG_J" \
                    LEAN_PROGRESS_FILE="$LEAN_PROG_J" RUN_ID="r-lean-j" \
                    CLAUDE_CODE_SESSION_ID="sess-lean-jira-build" bash "$LEAN_GATE" "$@" 2>&1 ); }
  lean_count_j() { if [[ -f "$LEAN_PROG_J" ]]; then local n; n=$(grep -cF "$1" "$LEAN_PROG_J" 2>/dev/null) || n=0; echo "$n"; else echo 0; fi; }

  rm -f "$LEAN_PROG_J" "$LEAN_TREE/.claude/pipeline-state/$LEAN_JKEY-run-id"
  printf '{"tool":"Bash"}\n' > "$LEAN_TREE/.claude/audit/sess-lean-jira-build.jsonl"
  printf '# spec\n\n- AC-1: a thing\n' > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean.md"
  # The spec commits FIRST and on its own. `lean_commit` stages everything, so one combined
  # commit would put a code change inside the verdict's commit — a shape review-lean step 6
  # forbids, and one both freshness arms refuse.
  lean_commit "jira leg: build session pushes the spec"
  # P10 applies to the jira arm unchanged — the adapter moves the tracker WRITE, never the
  # authorship separation. So the record is REVIEW-authored (a session id distinct from the
  # build one `claim` stamps into the progress file below) and COMMITTED, or milestone 4
  # refuses it on authorship/freshness before the adapter is ever reached. `reviewed_head` is
  # the head as of the review, resolved before the record's own commit.
  printf 'verdict=approve\nrun_id: r-lean-jreview\nsession_id: sess-lean-jira-review\nrounds: 1\nreviewed_head: %s\n' \
    "$(git -C "$LEAN_TREE" rev-parse HEAD)" \
    > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean-verdict.md"
  lean_commit "jira leg: review verdict"
  cat > "$TMP/lean-pr-jira.json" <<LEANPRJ
[{ "number": 6, "url": "https://example.invalid/pr/6", "isDraft": false,
   "body": "Summary.\n\nSpec: docs/plans/acme-$LEAN_JKEY-lean.md\nVerdict: docs/plans/acme-$LEAN_JKEY-lean-verdict.md\n\n### Jira Items\n\nCloses [$LEAN_JKEY]\n" }]
LEANPRJ
  # EMPTY, not merely comment-less: under tracker.writes: false there is no trail to read, and
  # the same empty trail is a hard failure on the github legs above. That contrast IS the leg.
  echo '[]' > "$TMP/lean-comments-none.json"

  # `entry` FIRST, as SKILL.md step 1 orders it and as the precondition now requires — the
  # jira arm's claim is a build-role subcommand like any other.
  lean_gate_j entry "$LEAN_JKEY" >/dev/null 2>&1; je=$?
  lean_gate_j claim "$LEAN_JKEY" >/dev/null 2>&1; jc=$?
  lean_gate_j 1 "$LEAN_JKEY" >/dev/null 2>&1; j1=$?
  lean_gate_j 2 "$LEAN_JKEY" >/dev/null 2>&1; j2=$?
  lean_gate_j 3 "$LEAN_JKEY" >/dev/null 2>&1; j3=$?
  lean_gate_j 4 "$LEAN_JKEY" >/dev/null 2>&1; j4=$?
  lean_gate_j 5 "$LEAN_JKEY" --pr-file "$TMP/lean-pr-jira.json" \
              --comments-file "$TMP/lean-comments-none.json" >/dev/null 2>&1; j5=$?
  [[ "$je$jc$j1$j2$j3$j4$j5" == "0000000" ]] \
    && pass "(lean-jira) entry + claim + milestones 1-5 all exit 0 under tracker.type: jira, with no GH_BOT and an empty comment trail" \
    || fail "(lean-jira) exit codes were $je$jc$j1$j2$j3$j4$j5, expected 0000000"

  lean_sat_j=0
  for m in 1 2 3 4 5; do
    [[ "$(lean_count_j "| milestone-$m | satisfied")" -eq 1 ]] && lean_sat_j=$((lean_sat_j + 1))
  done
  [[ "$lean_sat_j" -eq 5 ]] \
    && pass "(lean-jira) the chain lands in the SAME progress file cmd_claim created — one satisfied line per milestone" \
    || fail "(lean-jira) expected 5 single satisfied lines in the claim-created file, got $lean_sat_j"

  # The claim writes nothing to the tracker, so the run-id anchor in this file is the only
  # thing left tying the run together. If it is absent the jira arm has no record at all.
  [[ "$(lean_count_j '| claim | tracker=jira |')" -eq 1 && "$(lean_count_j 'run_id: r-lean-j')" -ge 1 ]] \
    && pass "(lean-jira) the write-free claim still records the claim line and the run-id anchor" \
    || fail "(lean-jira) the jira claim left no claim line or no run-id anchor"

  # ---- non-vacuity for the jira leg ---------------------------------------
  # Under jira the verdict-record reference moved from the closing comment INTO the PR body.
  # Strip it and the leg must red — otherwise this leg would pass on a PR carrying no link to
  # the artifact the whole gate exists to surface.
  cat > "$TMP/lean-pr-jira-nv.json" <<LEANPRJNV
[{ "number": 6, "url": "https://example.invalid/pr/6", "isDraft": false,
   "body": "Summary.\n\nSpec: docs/plans/acme-$LEAN_JKEY-lean.md\n\n### Jira Items\n\nCloses [$LEAN_JKEY]\n" }]
LEANPRJNV
  lean_gate_j 5 "$LEAN_JKEY" --pr-file "$TMP/lean-pr-jira-nv.json" \
              --comments-file "$TMP/lean-comments-none.json" >/dev/null 2>&1; jnv=$?
  [[ "$jnv" -ne 0 ]] \
    && pass "(lean-jira-nv) non-vacuity: the same leg reds when the PR body drops the verdict-record path" \
    || fail "(lean-jira-nv) milestone-5 passed under jira with no verdict reference anywhere — the leg is vacuous"

  # P10 is NOT adapter-scoped, and this is where that is asserted rather than assumed. The
  # adapter moves the tracker WRITE; it must not become a second way to author your own
  # verdict. Re-write the record carrying the BUILD session id and milestone 4 must refuse on
  # the jira arm exactly as it does on github.
  printf 'verdict=approve\nrun_id: r-lean-j\nsession_id: sess-lean-jira-build\nrounds: 2\n' \
    > "$LEAN_TREE/docs/plans/acme-$LEAN_JKEY-lean-verdict.md"
  lean_commit "jira leg: build-authored verdict (must be refused)"
  lean_gate_j 4 "$LEAN_JKEY" >/dev/null 2>&1; jp10=$?
  [[ "$jp10" -ne 0 ]] \
    && pass "(lean-jira-p10) a build-authored verdict is refused on the jira arm too — the adapter is no authorship loophole" \
    || fail "(lean-jira-p10) milestone-4 accepted a verdict carrying the build session id under jira"

  # ---- branch-name composition (#413) — the resolved name reaching the run's own record ----
  # lean-gate-selftest.sh's (e*)/(n0b) prove the formula against a milestone-1-created header.
  # What only a composed leg shows is that the name the run is ACTUALLY keyed by is the one
  # `cmd_claim` wrote — a different creation site, reached through the adapter, under an
  # alphanumeric key whose lowercasing must apply to the branch and to nothing else. The
  # artifact paths in the same header are the control: a blanket lowercase would move them too,
  # and every one of them is a committed file this leg's milestones already found.
  lean_jbranch="$(grep '^branch:' "$LEAN_PROG_J" 2>/dev/null | awk '{print $2}')"
  lean_jspec="$(grep '^spec:' "$LEAN_PROG_J" 2>/dev/null | awk '{print $2}')"
  [[ "$lean_jbranch" == "abc/acme-7" && "$lean_jspec" == "docs/plans/acme-ACME-7-lean.md" ]] \
    && pass "(lean-branch-name) the claim-created record carries <branchPrefix><lowercased key>, with artifact paths keyed verbatim" \
    || fail "(lean-branch-name) branch='$lean_jbranch' spec='$lean_jspec', expected abc/acme-7 and docs/plans/acme-ACME-7-lean.md"

  # ...and the composed REFUSAL. With tracker.branchPrefix unset and no identifier detectable,
  # the run's front door must stop before it writes anything: no placeholder branch, and no
  # progress record for a run that has no name to work under. Asserted as a terminal NON-write,
  # the only shape that separates "refused" from "refused after recording a claim" — the latter
  # leaves a reconcilable-looking record behind for a run that never started.
  LEAN_CFG_NOPFX="$TMP/lean-config-noprefix.json"
  jq 'del(.tracker.branchPrefix)' "$LEAN_CFG_J" > "$LEAN_CFG_NOPFX"
  LEAN_PROG_NOPFX="$TMP/lean-progress-noprefix.md"
  rm -f "$LEAN_PROG_NOPFX"
  lean_nopfx_out="$( cd "$LEAN_TREE" && env -u GH_BOT SECOND_SHIFT_CONFIG="$LEAN_CFG_NOPFX" \
                     LEAN_PROGRESS_FILE="$LEAN_PROG_NOPFX" RUN_ID="r-lean-nopfx" \
                     CLAUDE_CODE_SESSION_ID="sess-lean-nopfx" bash "$LEAN_GATE" claim "$LEAN_JKEY" 2>&1 )"
  lean_nopfx_rc=$?
  if [[ "$lean_nopfx_rc" -eq 2 && ! -f "$LEAN_PROG_NOPFX" ]] \
     && ! printf '%s' "$lean_nopfx_out" | grep -q 'claude/acme-'; then
    pass "(lean-branch-refusal) an unresolvable prefix stops claim at rc=2 with no progress record and no placeholder branch"
  else
    fail "(lean-branch-refusal) rc=$lean_nopfx_rc record=$([[ -f "$LEAN_PROG_NOPFX" ]] && echo present || echo absent): $lean_nopfx_out"
  fi

  # ---- extraLanes composition (#379) — the skip and red verdict paths, end to end --------
  # NOT a duplicate of lean-gate-selftest.sh's per-tool AC coverage (that suite drives
  # milestone 3 alone against dozens of shapes): this is the composed-verdict-path
  # obligation the repo's own testing rule names — a fresh, isolated tree because legs 1-7
  # and the jira sub-section above leave $LEAN_TREE mid-rebase/branch-switched, unrelated to
  # this composition.
  EL_TREE="$TMP/lean-el-tree"
  mkdir -p "$EL_TREE/docs/plans" "$EL_TREE/.claude/audit"
  git -C "$EL_TREE" init -q
  git -C "$EL_TREE" config user.email lean-el@example.invalid
  git -C "$EL_TREE" config user.name lean-el-scenario
  printf '.claude/\n' > "$EL_TREE/.gitignore"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture base" >/dev/null 2>&1
  git -C "$EL_TREE" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$EL_TREE/src"
  printf 'x\n' > "$EL_TREE/src/App.tsx"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el fixture change" >/dev/null 2>&1

  EL_ISSUE="$TMP/lean-el-issue.json"
  printf '{"body": "# issue\\n\\nNo Open Regions section here.\\n"}' > "$EL_ISSUE"
  el_cfg() { # el_cfg <label> <extraLanes-json>
    local out="$TMP/lean-el-cfg-$1.json"
    jq --argjson el "$2" '.commands.acme.extraLanes = $el' "$LEAN_CFG" > "$out" 2>/dev/null
    printf '%s' "$out"
  }
  EL_SID="sess-lean-el-build"
  printf '{"tool":"Bash"}\n' > "$EL_TREE/.claude/audit/$EL_SID.jsonl"
  el_gate() { # el_gate <config-file> <progress-file> <args...>
    local cfg="$1" prog="$2"; shift 2
    ( cd "$EL_TREE" && SECOND_SHIFT_CONFIG="$cfg" LEAN_PROGRESS_FILE="$prog" \
      CLAUDE_CODE_SESSION_ID="$EL_SID" bash "$LEAN_GATE" --issue-file "$EL_ISSUE" "$@" 2>&1 )
  }
  # Each extraLanes case gets its own progress file, so each composes its own `entry` first.
  el_attest() { el_gate "$1" "$2" entry 777 >/dev/null 2>&1; }

  # skip: a non-matching `when` composes into a fully green run, exactly like (lean-green)
  # above — extraLanes must not silently block a run it has nothing to say about.
  EL_SPEC="$EL_TREE/docs/plans/acme-777-lean.md"
  EL_VERDICT="$EL_TREE/docs/plans/acme-777-lean-verdict.md"
  printf '# spec\n\n- AC-1: a thing\n' > "$EL_SPEC"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el: spec" >/dev/null 2>&1
  printf 'verdict=approve\nrun_id: r-el-review\nsession_id: sess-el-review\nrounds: 1\nreviewed_head: %s\n' \
    "$(git -C "$EL_TREE" rev-parse HEAD)" > "$EL_VERDICT"
  git -C "$EL_TREE" add -A >/dev/null 2>&1 && git -C "$EL_TREE" commit -q -m "el: verdict" >/dev/null 2>&1
  cat > "$TMP/lean-el-pr.json" <<LEANELPR
[{ "number": 9, "url": "https://example.invalid/pr/9", "isDraft": false,
   "body": "Closes #777\n\nSpec: docs/plans/acme-777-lean.md" }]
LEANELPR
  cat > "$TMP/lean-el-comments.json" <<LEANELC
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-el-1 -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-777-lean-verdict.md" }]
LEANELC
  EL_CFG_SKIP="$(el_cfg skip '[{"name":"scoped","when":["docs/nomatch/**/*.md"],"commands":["echo should-not-run"],"failureClass":"TEST_FAILURE"}]')"
  EL_PROG_SKIP="$TMP/lean-el-prog-skip.md"
  el_attest "$EL_CFG_SKIP" "$EL_PROG_SKIP"
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 1 777 >/dev/null 2>&1; els1=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 2 777 >/dev/null 2>&1; els2=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 3 777 >/dev/null 2>&1; els3=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 4 777 >/dev/null 2>&1; els4=$?
  el_gate "$EL_CFG_SKIP" "$EL_PROG_SKIP" 5 777 --pr-file "$TMP/lean-el-pr.json" \
          --comments-file "$TMP/lean-el-comments.json" >/dev/null 2>&1; els5=$?
  [[ "$els1$els2$els3$els4$els5" == "00000" ]] \
    && pass "(lean-el-skip) a non-matching extraLanes 'when' composes into a fully green run (milestones 1-5)" \
    || fail "(lean-el-skip) exit codes were $els1$els2$els3$els4$els5, expected 00000"
  el_skip_n=$(grep -cF "milestone-3 | skipped | extra lane 'scoped'" "$EL_PROG_SKIP" 2>/dev/null) || el_skip_n=0
  [[ "$el_skip_n" -ge 1 ]] \
    && pass "(lean-el-skip) the skip composes with a recorded progress-file line, not a silent pass" \
    || fail "(lean-el-skip) no skip line recorded in the composed run"

  # red: a failing extraLane composes the same way a fixed-key failure already does — 'all'
  # stops at milestone 3 and never reaches 4/5, the composition obligation the fixed-key
  # legs above never exercise for extraLanes specifically. A fresh progress file: the point
  # is what THIS run records, not what the skip leg above already left behind.
  EL_CFG_RED="$(el_cfg red '[{"name":"boom","commands":["exit 3"],"failureClass":"TEST_FAILURE"}]')"
  EL_PROG_RED="$TMP/lean-el-prog-red.md"
  el_attest "$EL_CFG_RED" "$EL_PROG_RED"
  out="$(el_gate "$EL_CFG_RED" "$EL_PROG_RED" all 777)"; elr=$?
  if [[ "$elr" -ne 0 ]] && printf '%s' "$out" | grep -q 'stopped at milestone-3'; then
    pass "(lean-el-red) a failing extraLane composes into 'all' stopping at milestone-3"
  else fail "(lean-el-red) expected 'all' to stop at milestone-3, got rc=$elr: $out"; fi
  el_red_n=$(grep -cF '| milestone-4 | satisfied' "$EL_PROG_RED" 2>/dev/null) || el_red_n=0
  [[ "$el_red_n" -eq 0 ]] \
    && pass "(lean-el-red) milestone-4 is never recorded satisfied when extraLanes reds milestone-3 first" \
    || fail "(lean-el-red) milestone-4 was recorded satisfied despite milestone-3 failing"

  # ---- zero configured verify lanes (#392) — the RED verdict path, composed -------------
  # (lean-el-red) above proves a milestone-3 red composes when a lane RAN and failed. This
  # guard reds when no lane was ever configured, which is the opposite trigger and reachable
  # by a different predicate. It needs its own leg because every lean fixture in this suite
  # carries `allowUnverified: true` to reach a green chain at all — strip the opt-out and
  # nothing else, and the guard's red branch is the only thing that moved. Reuses the EL
  # substrate: same isolated tree, same spec/verdict commits, no extraLanes anywhere.
  ZV_CFG="$TMP/lean-zv-cfg.json"
  jq 'del(.commands.acme.allowUnverified)' "$LEAN_CFG" > "$ZV_CFG"
  ZV_PROG="$TMP/lean-zv-prog.md"
  el_attest "$ZV_CFG" "$ZV_PROG"
  out="$(el_gate "$ZV_CFG" "$ZV_PROG" all 777)"; zvr=$?
  if [[ "$zvr" -ne 0 ]] && printf '%s' "$out" | grep -q 'stopped at milestone-3' \
     && printf '%s' "$out" | grep -q 'no verifying lane configured'; then
    pass "(lean-zv-red) an undeclared zero-verify-lane config composes into 'all' stopping at milestone-3"
  else fail "(lean-zv-red) expected 'all' to stop at milestone-3 naming the zero-lane reason, got rc=$zvr: $out"; fi
  zv_red_n=$(grep -cF '| milestone-4 | satisfied' "$ZV_PROG" 2>/dev/null) || zv_red_n=0
  [[ "$zv_red_n" -eq 0 ]] \
    && pass "(lean-zv-red) milestone-4 is never recorded satisfied when the zero-lane guard reds milestone-3" \
    || fail "(lean-zv-red) milestone-4 was recorded satisfied despite the zero-lane guard failing"
  # ---- design legs (#394) — the armed lane composed across all three verdict paths -------
  # Per-tool fixtures prove each armed assertion against a fixture. What only a composed leg
  # proves is that the armed lane rides the SAME chain everything else does: the same fix
  # budget, the same hard stop, the same milestone-4 handoff, the same milestone-5 terminal
  # write. An armed run that quietly grew its own failure economics would be invisible to
  # lean-gate-selftest.sh, which drives each milestone alone.
  #
  # Its OWN tree and config: every leg above ran unarmed, and arming is config-keyed, so the
  # shared LEAN_CFG cannot carry a provider without changing what those legs compose.
  LEAN_DTREE="$TMP/lean-dtree"
  mkdir -p "$LEAN_DTREE/docs/plans" "$LEAN_DTREE/.claude"
  git -C "$LEAN_DTREE" init -q
  git -C "$LEAN_DTREE" config user.email lean@example.invalid
  git -C "$LEAN_DTREE" config user.name lean-scenario
  printf '.claude/\n' > "$LEAN_DTREE/.gitignore"
  LEAN_DSTUB="$TMP/lean-render-stub.sh"
  LEAN_DMODE="$TMP/lean-render-mode"
  cat > "$LEAN_DSTUB" <<LEANSTUB
#!/usr/bin/env bash
MODEF="$LEAN_DMODE"
LEANSTUB
  cat >> "$LEAN_DSTUB" <<'LEANSTUB'
route=""; state=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --route) route="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    --out)   out="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
mode=ok; [ -f "$MODEF" ] && mode="$(cat "$MODEF")"
case "$mode" in
  fail) echo "render harness unavailable" >&2; exit 5 ;;
  *)    printf 'PNG-%s-%s\n' "$route" "$state" > "$out" ;;
esac
exit 0
LEANSTUB
  LEAN_DCFG="$TMP/lean-config-design.json"
  cat > "$LEAN_DCFG" <<LEANDCFG
{
  "tracker": { "branchPrefix": "claude/acme-", "labels": { "queue": "ready-for-dev", "claimed": "in-progress" } },
  "topology": { "repos": { "acme": { "path": ".", "baseBranch": "main" } } },
  "paths": { "plansDir": "docs/plans", "pipelineStateDir": ".claude/pipeline-state" },
  "commands": { "acme": { "lint": null, "typecheck": null, "test": null, "allowUnverified": true } },
  "design": { "provider": "figma",
              "liveRender": { "command": "bash $LEAN_DSTUB --route {route} --state {state} --out {out}" } }
}
LEANDCFG
  LEAN_DPROG="$TMP/lean-progress-design.md"
  LEAN_DSPEC="$LEAN_DTREE/docs/plans/acme-88-lean.md"
  LEAN_DSID="sess-lean-d-build"
  mkdir -p "$LEAN_DTREE/.claude/audit"
  printf '{"tool":"Bash"}\n' > "$LEAN_DTREE/.claude/audit/$LEAN_DSID.jsonl"
  lean_dgate() { ( cd "$LEAN_DTREE" && SECOND_SHIFT_CONFIG="$LEAN_DCFG" LEAN_PROGRESS_FILE="$LEAN_DPROG" \
                   CLAUDE_CODE_SESSION_ID="$LEAN_DSID" \
                   bash "$LEAN_GATE" --issue-file "$LEAN_ISSUE_NOREGIONS" "$@" 2>&1 ); }
  lean_dcommit() { git -C "$LEAN_DTREE" add -A >/dev/null 2>&1
                   git -C "$LEAN_DTREE" commit -q --allow-empty -m "${1:-lean design fixture}" >/dev/null 2>&1; }
  lean_dseed() { rm -f "$LEAN_DPROG"
                 { echo "# lean run — issue 88"; echo ""; echo "run_id: r-lean-d"; echo "session_id: sess-lean-d-build"; } > "$LEAN_DPROG"
                 lean_dgate entry 88 >/dev/null 2>&1; }
  lean_dverdict() { # lean_dverdict <session> <run-id> [args...]
    local sid="$1" rid="$2"; shift 2
    rm -f "$LEAN_DTREE/.claude/pipeline-state/88-review-run-id"
    ( unset RUN_ID; cd "$LEAN_DTREE" && SECOND_SHIFT_CONFIG="$LEAN_DCFG" LEAN_PROGRESS_FILE="$LEAN_DPROG" \
      CLAUDE_CODE_SESSION_ID="$sid" RUN_ID="$rid" bash "$LEAN_GATE" verdict 88 "$@" 2>&1 )
  }
  {
    printf '# spec\n\n- AC-1: a thing\n\n## Design\n\nHandoff: https://design.example.invalid/f/a\n\n'
    printf '| RS-n | route | state | AC refs |\n| --- | --- | --- | --- |\n'
    printf '| RS-1 | prospects | default | AC-1 |\n| RS-2 | prospects | filters expanded | AC-1 |\n'
  } > "$LEAN_DSPEC"
  lean_dcommit "base"
  git -C "$LEAN_DTREE" update-ref refs/remotes/origin/main HEAD
  printf 'the work\n' > "$LEAN_DTREE/subject.txt"
  lean_dcommit "the build session pushes the armed spec"

  # ---- design leg 1: a blocking render red walks the SAME budget to the hard stop --------
  # D-2's whole point: there is no degraded state, so an unreachable render harness spends the
  # milestone's attempts and hard-stops exactly as a failing test suite does. If the armed lane
  # had its own economics this sequence would not be 1/1/1/4.
  lean_dseed
  printf 'fail\n' > "$LEAN_DMODE"
  lean_drcs=""
  for _ in 1 2 3 4; do lean_dgate 3 88 >/dev/null 2>&1; lean_drcs="$lean_drcs$?"; done
  [[ "$lean_drcs" == "1114" ]] \
    && pass "(lean-design-budget) a blocking render failure spends the shared 3-attempt budget and hard-stops (rc=4)" \
    || fail "(lean-design-budget) exit sequence was $lean_drcs, expected 1114"
  lean_darmed=$(grep -cF '| milestone-3 | armed |' "$LEAN_DPROG" 2>/dev/null) || lean_darmed=0
  lean_dattempts=$(grep -cF '| milestone-3 | attempt |' "$LEAN_DPROG" 2>/dev/null) || lean_dattempts=0
  [[ "$lean_darmed" -eq 1 && "$lean_dattempts" -eq 4 ]] \
    && pass "(lean-design-budget) the armed record is written once and counts for nothing — 4 attempts, 1 lock" \
    || fail "(lean-design-budget) armed=$lean_darmed attempts=$lean_dattempts, expected 1 and 4"

  # ---- design leg 2: the receipt commits, then milestone 4 refuses an unscored verdict ----
  printf 'ok\n' > "$LEAN_DMODE"
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1; ld_render=$?
  lean_dcommit "the render receipt"
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1; ld_green=$?
  [[ "$ld_render" -eq 1 && "$ld_green" -eq 0 ]] \
    && pass "(lean-design-render) the receipt reds until committed, then the same evaluation passes" \
    || fail "(lean-design-render) expected rc 1 then 0, got $ld_render then $ld_green"

  # A review round that scored no fidelity: the handoff must round-trip, not certify.
  lean_dseed
  lean_dverdict sess-lean-d-review r-lean-d-review --pr 8 --verdict approve >/dev/null 2>&1
  lean_dcommit "a verdict that scored no fidelity"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_nofid=$?

  # ...and a stale receipt under an otherwise-fresh verdict — D-10's backstop, composed.
  lean_dseed
  lean_dverdict sess-lean-d-review2 r-lean-d-review2 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "a verdict scoring fidelity pass"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_pass=$?
  printf 'a fix lands after the render\n' > "$LEAN_DTREE/subject.txt"
  lean_dcommit "a fix, leaving the receipt behind"
  lean_dseed
  lean_dverdict sess-lean-d-review3 r-lean-d-review3 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "an honest record on top of a stale receipt"
  lean_dseed
  lean_dgate 4 88 >/dev/null 2>&1; ld_stale=$?
  [[ "$ld_nofid" -eq 1 && "$ld_pass" -eq 0 && "$ld_stale" -eq 1 ]] \
    && pass "(lean-design-verdict) milestone 4 refuses an unscored verdict, passes a scored one, and refuses a stale receipt under a fresh verdict" \
    || fail "(lean-design-verdict) expected rc 1/0/1, got $ld_nofid/$ld_pass/$ld_stale"

  # ---- design leg 3: post-approve, `all` reaches the milestone-5 terminal write ----------
  # The livelock this ordering exists to prevent: the mandated pre-close sweep re-evaluates
  # milestone 3 AFTER the approve, and a re-render there would rewrite the receipt inside
  # reviewed_patch_id and void the verdict the run just earned. So the sweep must pass on the
  # binding alone — with the PNGs deleted, which is also every fresh-worktree resume.
  lean_dseed
  lean_dgate 3 88 >/dev/null 2>&1
  lean_dcommit "the re-rendered receipt for the fixed head"
  lean_dseed
  lean_dverdict sess-lean-d-review4 r-lean-d-review4 --pr 8 --verdict approve --fidelity pass >/dev/null 2>&1
  lean_dcommit "the round-2 record on the fresh receipt"
  rm -rf "$LEAN_DTREE/.claude/lean-renders/88"
  cat > "$TMP/lean-design-pr.json" <<'LEANDPR'
[{ "number": 8, "url": "https://example.invalid/pr/8", "isDraft": false,
   "body": "Closes #88\n\nSpec: docs/plans/acme-88-lean.md" }]
LEANDPR
  cat > "$TMP/lean-design-comments.json" <<'LEANDC'
[{ "user": { "type": "Bot" }, "created_at": "2026-01-01T00:00:00Z",
   "body": "<!-- run_id: r-lean-d -->\n<!-- stage: lean-claimed -->" },
 { "user": { "type": "Bot" }, "created_at": "2026-01-02T00:00:00Z",
   "body": "Done. Verdict record: docs/plans/acme-88-lean-verdict.md" }]
LEANDC
  lean_dseed
  lean_dgate 1 88 >/dev/null 2>&1; ldf1=$?
  lean_dgate 2 88 >/dev/null 2>&1; ldf2=$?
  lean_dgate 3 88 >/dev/null 2>&1; ldf3=$?
  lean_dgate 4 88 >/dev/null 2>&1; ldf4=$?
  lean_dgate 5 88 --pr-file "$TMP/lean-design-pr.json" \
             --comments-file "$TMP/lean-design-comments.json" >/dev/null 2>&1; ldf5=$?
  [[ "$ldf1$ldf2$ldf3$ldf4$ldf5" == "00000" ]] \
    && pass "(lean-design-terminal) post-approve, milestones 1-5 all exit 0 with every rendered PNG deleted" \
    || fail "(lean-design-terminal) exit codes were $ldf1$ldf2$ldf3$ldf4$ldf5, expected 00000"
  [[ ! -d "$LEAN_DTREE/.claude/lean-renders/88" ]] \
    && pass "(lean-design-terminal) and nothing re-rendered — the receipt's binding alone carried the sweep" \
    || fail "(lean-design-terminal) the post-approve sweep re-rendered, which would void the verdict it just earned"

  # ---- non-vacuity for the design legs ---------------------------------------------------
  # The whole block would stay green if arming never took. Disarm the spec on a run that
  # already armed and the same chain must red — at milestone 1, before any of it.
  {
    printf '# spec\n\n- AC-1: a thing\n\n## Design\n\nDesign: none — reconsidered mid-run.\n'
  } > "$LEAN_DSPEC"
  lean_dgate 1 88 >/dev/null 2>&1; ld_nv=$?
  [[ "$ld_nv" -ne 0 ]] \
    && pass "(lean-design-nv) non-vacuity: the same chain reds when the armed spec is disarmed mid-run" \
    || fail "(lean-design-nv) a mid-run disarm passed milestone 1 — the design legs are vacuous"
fi


# ================================ ledger corroboration composes to terminal (#272) ===
# The corroboration legs are the newest thing standing between a stage and its
# completion write, and they fire on EVERY stage 1-9. A per-tool selftest proves
# the verdicts; only a composed run proves the nine gates still compose to a
# terminal `completed` with corroboration active — the exact failure mode the
# stacked-PR path died of, where every component was green against itself.

echo "[scenario-liveness] ledger corroboration: a fully-corroborated run still reaches terminal"

LC_LEDGER="$TMP/audit"
mkdir -p "$LC_LEDGER"
LC_SESSION="5e1f7e57-0000-4000-8000-0000000000c0"

# One ledger backing every claim a full green run makes: a main-loop Read per
# stage file, the two mandated skill loads, and the stage-8 dispatch pair. The
# Read timestamps deliberately PRECEDE every startedAt this suite writes — that is
# the real ordering (the executor reads the stage file before it can run the
# mark-started), and it is why the stage-file leg is windowless.
{
  for f in 1-intake 2-worktree 3-write-plan 4-plan-review 5-implement 6-verify 7-doc-update 8-code-review 9-open-pr; do
    printf '{"ts":"2026-01-01T00:00:00Z","session_id":"s","event":"PostToolUse","tool":"Read","subagent":"","target":"/cache/skills/run/stages/%s.md","outcome":"ok"}\n' "$f"
  done
  printf '%s\n' '{"ts":"2036-01-01T00:00:00Z","session_id":"s","event":"PostToolUse","tool":"Skill","subagent":"","target":"intake-toolkit:intake-orchestrator","outcome":"ok"}'
  printf '%s\n' '{"ts":"2036-01-01T00:00:00Z","session_id":"s","event":"PostToolUse","tool":"Skill","subagent":"","target":"review-toolkit:review-lead","outcome":"ok"}'
  printf '%s\n' '{"ts":"2036-01-01T00:00:00Z","session_id":"s","event":"PostToolUse","tool":"Workflow","subagent":"","target":"/cache/skills/run/workflows/code-review.mjs","outcome":"ok"}'
  printf '%s\n' '{"ts":"2036-01-01T00:00:00Z","session_id":"s","event":"SubagentStop","tool":"","subagent":"review-toolkit:security-reviewer","target":"","outcome":"ok"}'
} > "$LC_LEDGER/$LC_SESSION.jsonl"

LC_KEY=9010
reset_state
export STATECTL_LEDGER_DIR="$LC_LEDGER"
sct init "$LC_KEY" --run-id "scenario-liveness-$$" >/dev/null
sct pipeline-session-add "$LC_KEY" --session-id "$LC_SESSION" --source interactive >/dev/null
for n in 1 2 3 4 5 6 7 8 9; do complete_stage "$LC_KEY" "$n"; done
write_report "$LC_KEY"
write_eval "$LC_KEY"
rc=$(sct_rc mark-completed "$LC_KEY")
status=$(sct get "$LC_KEY" '.status')
lc_all=$(sct get "$LC_KEY" '[.stages[] | .ledgerCorroboration] | unique | join(",")')
[[ "$rc" -eq 0 && "$status" == "completed" && "$lc_all" == "corroborated" ]] \
  && pass "(lcs1) corroboration TERMINAL: all nine stages corroborated, mark-completed accepted (AC-1, AC-8)" \
  || fail "(lcs1) corroborated run to terminal — rc=$rc status='$status' values='$lc_all'"

# Non-vacuity. (lcs1) would stay green if the legs never actually ran, so drive the
# IDENTICAL path with one row removed: the stage-8 Skill row. The same composed run
# must now be REFUSED at stage 8 and never reach terminal. Precondition-variation,
# per (ns3)/(pg-nv) — nothing on disk in production code is mutated to make a point.
grep -v 'review-toolkit:review-lead' "$LC_LEDGER/$LC_SESSION.jsonl" > "$LC_LEDGER/$LC_SESSION.trimmed"
mv "$LC_LEDGER/$LC_SESSION.trimmed" "$LC_LEDGER/$LC_SESSION.jsonl"
reset_state
sct init "$LC_KEY" --run-id "scenario-liveness-$$" >/dev/null
sct pipeline-session-add "$LC_KEY" --session-id "$LC_SESSION" --source interactive >/dev/null
for n in 1 2 3 4 5 6 7; do complete_stage "$LC_KEY" "$n"; done
complete_stage "$LC_KEY" 8
s8=$(sct get "$LC_KEY" '.stages."8".status')
write_report "$LC_KEY"
write_eval "$LC_KEY"
rc_nv=$(sct_rc mark-completed "$LC_KEY")
[[ "$s8" != "completed" && "$rc_nv" -ne 0 ]] \
  && pass "(lcs2) non-vacuity: removing the review-lead ledger row refuses stage 8 and blocks terminal (AC-1)" \
  || fail "(lcs2) non-vacuity — stage8='$s8' mark-completed rc=$rc_nv"

# The fail-open must ALSO compose: a consumer with no audit hook has no ledger at
# all, and the whole pipeline must still reach terminal — visibly uncorroborated,
# never silently "corroborated". This is the arm that keeps corroboration additive.
reset_state
export STATECTL_LEDGER_DIR="$TMP/audit-absent"
LC_KEY2=9011
sct init "$LC_KEY2" --run-id "scenario-liveness-$$" >/dev/null
for n in 1 2 3 4 5 6 7 8 9; do complete_stage "$LC_KEY2" "$n"; done
write_report "$LC_KEY2"
write_eval "$LC_KEY2"
rc=$(sct_rc mark-completed "$LC_KEY2")
status=$(sct get "$LC_KEY2" '.status')
lc_all=$(sct get "$LC_KEY2" '[.stages[] | .ledgerCorroboration] | unique | join(",")')
[[ "$rc" -eq 0 && "$status" == "completed" && "$lc_all" == "uncorroborated" ]] \
  && pass "(lcs3) fail-open composes: no ledger → terminal completed, every stage visibly uncorroborated (AC-2)" \
  || fail "(lcs3) fail-open to terminal — rc=$rc status='$status' values='$lc_all'"

unset STATECTL_LEDGER_DIR
echo
echo "[scenario-liveness] summary: $PASS passed, $FAIL failed"
exit $FAIL
