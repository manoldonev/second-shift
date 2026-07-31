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
FIX="$HERE/tools/plan-lint-fixtures"

[[ -x "$STATECTL" ]] || { echo "[scenario-liveness] FATAL: $STATECTL not executable"; exit 99; }
[[ -f "$SCENARIO_LIB" ]] || { echo "[scenario-liveness] FATAL: $SCENARIO_LIB missing"; exit 99; }
[[ -x "$VERIFYCTL" ]] || { echo "[scenario-liveness] FATAL: $VERIFYCTL not executable"; exit 99; }
[[ -f "$LINT" ]] || { echo "[scenario-liveness] FATAL: $LINT missing"; exit 99; }
[[ -x "$PRED_GATE" ]] || { echo "[scenario-liveness] FATAL: $PRED_GATE not executable"; exit 99; }
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
rc_receipt=$(sct_rc comment-add "$KEY" --marker code-review --url "https://github.example/c/code-review")
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
sct comment-add "$KEY" --marker code-review --url "https://github.example/c/code-review" >/dev/null
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
sct comment-add "$KEY" --marker code-review --url "https://github.example/c/code-review" >/dev/null
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
sct comment-add "$KEY" --marker doc-update --url "https://github.example/c/doc-update" >/dev/null
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
sct comment-add "$KEY" --marker code-review --url "https://github.example/c/code-review" >/dev/null
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
  "configVersion": 1,
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
printf '%s' '{"configVersion":1,"tracker":{"type":"jira","writes":false}}' > "$TMP/jira-zero-config.json"
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
  sct comment-add "$PG_A" --marker claimed --url "https://example.invalid/c/$PG_A" >/dev/null
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
sct comment-add "$PG_B" --marker claimed --url "https://example.invalid/c/$PG_B" >/dev/null
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
  sct comment-add "$PG_A" --marker claimed --url "https://example.invalid/c/$PG_A" >/dev/null
fi
pg_a_receipt=$(sct get "$PG_A" '.comments.claimed // empty')
[[ "$pg_rc_closed" -eq 0 && -f "$STATECTL_STATE_DIR/$PG_A.json" && -n "$pg_a_receipt" ]] \
  && pass "(pg-nv) non-vacuity: the same path with the predecessor CLOSED does write the state file + receipt — the skip came from the gate (AC-6)" \
  || fail "(pg-nv) non-vacuity — rc=$pg_rc_closed file=$([[ -f "$STATECTL_STATE_DIR/$PG_A.json" ]] && echo y || echo n) receipt='$pg_a_receipt'"

echo
echo "[scenario-liveness] summary: $PASS passed, $FAIL failed"
exit $FAIL
