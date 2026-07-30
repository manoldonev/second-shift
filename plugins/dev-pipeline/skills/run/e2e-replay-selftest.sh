#!/usr/bin/env bash
# e2e-replay-selftest.sh — the E2E tier: replay a whole pipeline run with real tool
# execution at every mechanical seam.
#
# WHAT MAKES THIS A DIFFERENT TIER
# --------------------------------
# scenario-liveness-selftest.sh already proves a composed verdict path reaches a terminal
# write, but it gets there on HAND-PLANTED evidence: scenario-lib.sh's complete_stage
# writes each comment receipt as the literal `https://github.example/c/<marker>`. Nothing
# in the repo ever produced a receipt the way a run produces one, so the whole
# post-a-comment -> read html_url -> record-the-receipt chain was untested.
#
# Here every receipt is MINTED by executing a tool: production `claim-issue.sh` under a
# mock bot wrapper for the claim, and an executed `gh` shim returning canned html_urls for
# the comment and PR posts. Stages 4/5/8 run the real production Workflow `.mjs` bodies
# through the runtime shim (via workflows/e2e-workflow-leg.mjs). The stage-1 verdict
# payload comes from a fixture, not inline JSON. Nothing here asserts against a value this
# harness typed in as the expected answer.
#
# SCOPE BOUNDARY — READ BEFORE EXTENDING
# --------------------------------------
# This asserts the MECHANICAL SHADOW of the stage prose, never the prose. A model-free CI
# cannot execute a stage document, and headless driver mode was deliberately retired
# (statectl.sh resolve_writer: "Only `skill` is valid now that driver/headless mode is
# retired"). Concretely:
#
#   - The CLAIM leg executes production code. claim-issue.sh is a real script and
#     `GH_BOT` is its documented injection seam (the same one claim-selftest.sh uses).
#   - The COMMENT and PR legs do NOT. No production script owns those posts — they live
#     only in the stage docs (stages/9-open-pr.md), so the invocation SHAPE below is
#     harness-owned and can drift from the prose without anything here going red. What is
#     genuinely proven is the seam the prose feeds: a URL minted by an executed tool,
#     carried into statectl, and accepted by the completion gates. Extracting production
#     post-comment/open-pr tools would close the gap; that is a hot-path change, not a
#     test change, and is deliberately not done here.
#
# TWO SHIM SEAMS, NOT ONE. A `gh` PATH shim cannot intercept `$GH_BOT` — that resolves to
# an absolute wrapper path under ~/.config (claim-issue.sh's resolution order), so PATH is
# never consulted. Both seams are therefore installed: GH_BOT for wrapper calls, PATH for
# bare-`gh` call sites. Getting this wrong is silent: the claim would hit the real gh.
#
# Scenarios:
#   1  no-split replay   init -> stages 1..9, every receipt minted -> mark-completed ACCEPTED
#   2  negative          stage-9 completion REFUSED while the pr receipt is absent, then
#                        accepted once minted (scenario 1's green is not vacuous)
#   3  crash-recovery    session-id switch (the seam self-anchors the span on the
#                        resuming session's first write) -> stage-8 re-entry -> terminal write
#
# macOS ships bash 3.2 as /bin/bash and the macos CI lane forces it; this script stays 3.2
# compatible (no associative arrays, no mapfile, no ${var^^}).
#
# Exit code = number of failed checks (repo selftest convention).

set -uo pipefail
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST BRANCH_PREFIX

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATECTL="$HERE/statectl.sh"
SCENARIO_LIB="$HERE/scenario-lib.sh"
CLAIM="$HERE/tools/claim-issue.sh"
LEG="$HERE/workflows/e2e-workflow-leg.mjs"
FIXTURES="$HERE/e2e-replay-fixtures"

[[ -x "$STATECTL" ]] || { echo "[e2e-replay] FATAL: $STATECTL not executable"; exit 99; }
[[ -f "$SCENARIO_LIB" ]] || { echo "[e2e-replay] FATAL: $SCENARIO_LIB missing"; exit 99; }
[[ -f "$CLAIM" ]] || { echo "[e2e-replay] FATAL: $CLAIM missing"; exit 99; }
[[ -f "$LEG" ]] || { echo "[e2e-replay] FATAL: $LEG missing"; exit 99; }
[[ -d "$FIXTURES" ]] || { echo "[e2e-replay] FATAL: $FIXTURES missing"; exit 99; }
# node absent is a FAIL, never a silent green — the repo convention (see
# workflows/workflows-mjs-selftest.sh). Skipping would report success for legs that never ran.
command -v node >/dev/null 2>&1 || { echo "[e2e-replay] FAIL: node is required to drive the stage-4/5/8 legs" >&2; exit 1; }

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t e2e-replay.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/.claude/pipeline-state"
export STATECTL_STATE_DIR="$TMP/.claude/pipeline-state"

# Pin the writing session identity (#260) — see statectl-selftest.sh's note. `sct`
# passes the ambient environment through, so inheriting the harness's own session id
# would make every write same-session and scenario 3's resume would record nothing.
# Scenario 3 reassigns this to $E2E_SESSION_RESUMED at the resume point.
export CLAUDE_CODE_SESSION_ID="e2e5e551-0000-4000-8000-000000000001"
E2E_SESSION_RESUMED="e2e5e551-0000-4000-8000-000000000002"

# Absolute path, resolved from BASH_SOURCE above, so the cd below cannot break it.
# shellcheck source=/dev/null
. "$SCENARIO_LIB"
cd "$TMP" || exit 99

# ---- the two gh seams ---------------------------------------------------------------
# One implementation, installed twice: as `gh` on PATH (bare-gh call sites) and as the
# GH_BOT wrapper (every write the pipeline routes through the bot). Both append to
# $GH_LOG, so a scenario can assert WHAT was executed, not just what came back.
#
# Counter-suffixed URLs are load-bearing: identical canned URLs would let a hand-planted
# literal masquerade as a minted one, which is the exact confusion this tier removes.
MOCKBIN="$TMP/bin"
GH_LOG="$TMP/gh.log"
GH_SEQ="$TMP/gh.seq"
mkdir -p "$MOCKBIN"
: > "$GH_LOG"
echo 0 > "$GH_SEQ"

cat > "$MOCKBIN/gh" <<EOF
#!/usr/bin/env bash
# Canned gh. Behavior is switched on the argv shape, mirroring the real call sites.
set -uo pipefail
echo "\$*" >> "$GH_LOG"
n=\$(cat "$GH_SEQ"); n=\$((n + 1)); echo "\$n" > "$GH_SEQ"
ALL="\$*"
# --input - - consume stdin, or the producer (jq -nc | gh) dies on SIGPIPE.
case "\$ALL" in *"--input -"*) cat >/dev/null ;; esac
case "\$ALL" in
  *"-X POST"*"/labels"*)   printf '["in-progress"]\n' ;;
  *"-X DELETE"*"/labels"*) printf '[]\n' ;;
  *"-X POST"*"/comments"*) printf 'https://github.test/o/r/issues/9101#issuecomment-%s\n' "\$n" ;;
  *"pr create"*)           printf 'https://github.test/o/r/pull/%s\n' "\$n" ;;
  *"-X PATCH"*"/pulls/"*)  printf 'https://github.test/o/r/pull/%s\n' "\$n" ;;
  *)                       printf '\n' ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/gh"
cp "$MOCKBIN/gh" "$MOCKBIN/gh-as-bot.sh"
chmod +x "$MOCKBIN/gh-as-bot.sh"
export PATH="$MOCKBIN:$PATH"
export GH_BOT="$MOCKBIN/gh-as-bot.sh"

# mint_comment <issue> — POST a comment through the bot wrapper and echo the html_url.
# This is the harness-owned invocation shape flagged in the scope boundary above.
mint_comment() {
  local issue="$1" body
  body=$(mktemp "$TMP/comment.XXXXXX")
  printf '<!-- dev-pipeline -->\nreplay\n' > "$body"
  "$GH_BOT" api -X POST "repos/{owner}/{repo}/issues/$issue/comments" -F body=@"$body" --jq '.html_url'
  rm -f "$body"
}

# mint_pr <branch> — open a draft PR through the bot wrapper and echo the URL.
mint_pr() {
  "$GH_BOT" pr create --draft --head "$1" --title t --body b
}

# ================================================================ scenario 1 + 2 ===
# The no-split replay. Stages 1..9 with the receipt at each mandated marker minted by an
# executed tool, then the terminal write. Scenario 2 (the negative case) is interleaved at
# stage 9 rather than run separately: the refusal is only meaningful against a run that is
# otherwise complete, and re-walking eight stages to assert it once would double the
# runtime for no extra coverage.

echo "[e2e-replay] scenario 1: no-split replay, every receipt minted by an executed tool"
KEY=9101
BRANCH="claude/acme-$KEY"
reset_state
sct init "$KEY" --run-id "e2e-replay-$$" >/dev/null

# ---- stage 1: claim executes PRODUCTION claim-issue.sh, verdict comes from a fixture --
sct set-stage "$KEY" 1 --status started >/dev/null
GH_BOT="$GH_BOT" bash "$CLAIM" "$KEY" >/dev/null 2>&1
claim_rc=$?
[[ "$claim_rc" -eq 0 ]] && pass "(s1a) production claim-issue.sh claims under the bot-wrapper seam" \
  || fail "(s1a) claim-issue.sh rc=$claim_rc (want 0)"
# The add-before-DELETE ordering is the whole point of that script; assert the executed
# order, not just the exit code. A reversed swap leaves a zero-label window.
add_line=$(grep -n -- '-X POST repos/{owner}/{repo}/issues/'"$KEY"'/labels' "$GH_LOG" | head -1 | cut -d: -f1)
del_line=$(grep -n -- '-X DELETE repos/{owner}/{repo}/issues/'"$KEY"'/labels' "$GH_LOG" | head -1 | cut -d: -f1)
if [[ -n "$add_line" && -n "$del_line" && "$add_line" -lt "$del_line" ]]; then
  pass "(s1b) claim executed ADD before DELETE (no zero-label window)"
else
  fail "(s1b) claim label order add=$add_line del=$del_line (want add < del, both present)"
fi

CP1=$(jq -c '.checkpoint1' "$FIXTURES/no-split.json")
AC=$(jq -c '.acceptanceCriteria' "$FIXTURES/no-split.json")
sct checkpoint "$KEY" 1 --json "$CP1" >/dev/null
sct intake-brief "$KEY" --brief-path null --acceptance-criteria "$AC" >/dev/null
sct skill-load-add "$KEY" --stage 1 --skill intake-toolkit:intake-orchestrator >/dev/null
sct comment-add "$KEY" --marker claimed --url "$(mint_comment "$KEY")" >/dev/null
sct comment-add "$KEY" --marker intake --url "$(mint_comment "$KEY")" >/dev/null
stage_evidence "$KEY" 1
sct set-stage "$KEY" 1 --status completed >/dev/null
[[ "$(sct get "$KEY" '.stages["1"].status')" == "completed" ]] \
  && pass "(s1c) stage 1 completes on fixture verdict + minted receipts" \
  || fail "(s1c) stage 1 did not complete"
[[ "$(sct get "$KEY" '.acceptanceCriteria | length')" == "2" ]] \
  && pass "(s1d) the fixture AC snapshot is persisted (2 criteria)" \
  || fail "(s1d) AC snapshot not persisted from the fixture"

# ---- stage 2 ----
sct set-stage "$KEY" 2 --status started >/dev/null
sct worktree-set "$KEY" --path ".claude/worktrees/acme-$KEY" --branch "$BRANCH" >/dev/null
sct pipeline-session-add "$KEY" --session-id "11111111-1111-4111-8111-111111111111" --source interactive >/dev/null
stage_evidence "$KEY" 2
sct set-stage "$KEY" 2 --status completed >/dev/null

# ---- stage 3 ----
sct set-stage "$KEY" 3 --status started >/dev/null
sct comment-add "$KEY" --marker plan --url "$(mint_comment "$KEY")" >/dev/null
stage_evidence "$KEY" 3
sct set-stage "$KEY" 3 --status completed >/dev/null

# ---- stage 4: the verdict comes from EXECUTING plan-review.mjs ----
sct set-stage "$KEY" 4 --status started >/dev/null
LEG4=$(node "$LEG" plan-review 2>"$TMP/leg4.err")
leg4_rc=$?
LEG4_OVERALL=$(printf '%s' "$LEG4" | jq -r '.overall // "MISSING"' 2>/dev/null)
if [[ "$leg4_rc" -eq 0 && "$LEG4_OVERALL" == "pass" ]]; then
  pass "(s4a) production plan-review.mjs executed and returned overall=pass"
else
  fail "(s4a) plan-review leg rc=$leg4_rc overall='$LEG4_OVERALL' ($(tail -1 "$TMP/leg4.err" 2>/dev/null))"
fi
# All three built-in gates must appear in the ledger even when skipped — pipeline-retro
# audits coverage from the return value alone.
[[ "$(printf '%s' "$LEG4" | jq -r '.gates | length' 2>/dev/null)" == "3" ]] \
  && pass "(s4b) all three built-in plan gates appear in the returned ledger" \
  || fail "(s4b) plan-review gate ledger is not 3 entries"
sct plan-review-set "$KEY" --overall "$LEG4_OVERALL" >/dev/null
stage_evidence "$KEY" 4
sct set-stage "$KEY" 4 --status completed >/dev/null
[[ "$(sct get "$KEY" '.stages["4"].planReview.overall')" == "pass" ]] \
  && pass "(s4c) the executed verdict is what reached state (not a typed-in literal)" \
  || fail "(s4c) stages.4.planReview.overall did not come from the leg"

# ---- stage 5: mutation-gate.mjs executes; this repo has no mutation surface ----
sct set-stage "$KEY" 5 --status started >/dev/null
LEG5=$(node "$LEG" mutation-gate 2>"$TMP/leg5.err")
leg5_rc=$?
LEG5_OVERALL=$(printf '%s' "$LEG5" | jq -r '.overall // "MISSING"' 2>/dev/null)
if [[ "$leg5_rc" -eq 0 && "$LEG5_OVERALL" != "infra" && "$LEG5_OVERALL" != "MISSING" ]]; then
  pass "(s5a) production mutation-gate.mjs executed (overall=$LEG5_OVERALL, not the infra path)"
else
  fail "(s5a) mutation-gate leg rc=$leg5_rc overall='$LEG5_OVERALL' ($(tail -1 "$TMP/leg5.err" 2>/dev/null))"
fi
# The nested propose goes through the injected workflow() global — the 8th shim parameter.
[[ "$(printf '%s' "$LEG5" | jq -r '.nestedDispatches' 2>/dev/null)" == "1" ]] \
  && pass "(s5b) the nested propose dispatched through the injected workflow() global" \
  || fail "(s5b) mutation-gate did not dispatch its nested propose"
sct stage-substatus "$KEY" --stage 5 --key unitTestMutationReview --value completed >/dev/null
sct checkpoint "$KEY" 5 --json '{"changedFiles":["a.sh"],"commits":["deadbeef"]}' >/dev/null
stage_evidence "$KEY" 5
sct set-stage "$KEY" 5 --status completed >/dev/null

# ---- stage 6 ----
sct set-stage "$KEY" 6 --status started >/dev/null
sct verify-summary-set "$KEY" --json '{"format":"clean","test":"passed"}' >/dev/null
write_verify_sidecar "$KEY"
stage_evidence "$KEY" 6
sct set-stage "$KEY" 6 --status completed >/dev/null

# ---- stage 7: the payload is BUILT by statectl, not an inline literal ----
# build-checkpoint-7 is a real validating builder; scenario-lib's VALID_PAYLOAD is a
# constant. Using the builder is what makes this seam "real tool execution" rather than a
# hand-written blob that happens to satisfy the schema.
sct set-stage "$KEY" 7 --status started >/dev/null
CP7=$(sct build-checkpoint-7 --issue "$KEY" --branch "$BRANCH" --head "abc123" \
  --worktree ".claude/worktrees/acme-$KEY" \
  --plan "docs/plans/acme-$KEY.md" \
  --changed-files '["a.sh"]' \
  --verify-summary '{"format":"clean","test":"passed"}' \
  --doc-updater-findings "no stale docs found" \
  --free-note "replayed by e2e-replay-selftest")
cp7_rc=$?
if [[ "$cp7_rc" -eq 0 && -n "$CP7" ]]; then
  pass "(s7a) statectl build-checkpoint-7 produced the stage-7 payload"
else
  fail "(s7a) build-checkpoint-7 rc=$cp7_rc"
fi
sct checkpoint "$KEY" 7 --json "$CP7" >/dev/null
[[ "$(sct get "$KEY" '.stageCheckpoint["7"].docUpdaterFindings')" == "no stale docs found" ]] \
  && pass "(s7b) the built payload round-trips into state (docUpdaterFindings carried)" \
  || fail "(s7b) built checkpoint-7 fields did not reach state"
sct comment-add "$KEY" --marker doc-update --url "$(mint_comment "$KEY")" >/dev/null
stage_evidence "$KEY" 7
sct set-stage "$KEY" 7 --status completed >/dev/null

# ---- stage 8 ----
sct set-stage "$KEY" 8 --status started >/dev/null
LEG8=$(node "$LEG" code-review 2>"$TMP/leg8.err")
leg8_rc=$?
LEG8_VERDICT=$(printf '%s' "$LEG8" | jq -r '.verdict // "MISSING"' 2>/dev/null)
if [[ "$leg8_rc" -eq 0 && "$LEG8_VERDICT" == "approve" ]]; then
  pass "(s8a) production code-review.mjs executed and returned a parsed verdict"
else
  fail "(s8a) code-review leg rc=$leg8_rc verdict='$LEG8_VERDICT' ($(tail -1 "$TMP/leg8.err" 2>/dev/null))"
fi
[[ "$(printf '%s' "$LEG8" | jq -r '.dark' 2>/dev/null)" == "0" ]] \
  && pass "(s8b) no reviewer went dark on the canned round" \
  || fail "(s8b) code-review reported a dark reviewer on canned input"
# The review-lead load must precede the code-review receipt (statectl's ordering gate).
sct review-rounds "$KEY" --set 1 >/dev/null
sct skill-load-add "$KEY" --stage 8 --skill review-toolkit:review-lead >/dev/null
sct comment-add "$KEY" --marker code-review --url "$(mint_comment "$KEY")" >/dev/null
stage_evidence "$KEY" 8
sct set-stage "$KEY" 8 --status completed >/dev/null

# ---- stage 9 + scenario 2 (the negative case) ----
echo "[e2e-replay] scenario 2: the pr-receipt completion gate REFUSES before it accepts"
sct set-stage "$KEY" 9 --status started >/dev/null
PR_URL=$(mint_pr "$BRANCH")
sct pr-add "$KEY" --branch "$BRANCH" --url "$PR_URL" >/dev/null
# Refusal FIRST, with the pr receipt deliberately absent. Without this the green run below
# is indistinguishable from a harness that cannot fail.
rc=$(sct_rc set-stage "$KEY" 9 --status completed)
[[ "$rc" != "0" ]] && pass "(s9a) stage 9 completion is REFUSED while the pr receipt is absent (rc=$rc)" \
  || fail "(s9a) stage 9 completed with no pr receipt — the completion gate is not firing"
sct comment-add "$KEY" --marker pr --url "$(mint_comment "$KEY")" >/dev/null
stage_evidence "$KEY" 9
rc=$(sct_rc set-stage "$KEY" 9 --status completed)
[[ "$rc" == "0" ]] && pass "(s9b) the same write is ACCEPTED once the receipt is minted" \
  || fail "(s9b) stage 9 still refused after the receipt landed (rc=$rc)"

# ---- terminal write ----
write_eval "$KEY"
write_report "$KEY"
rc=$(sct_rc mark-completed "$KEY")
[[ "$rc" == "0" ]] && pass "(s9c) mark-completed ACCEPTED — the replay reaches a terminal write" \
  || fail "(s9c) mark-completed refused (rc=$rc)"
[[ "$(sct get "$KEY" '.status')" == "completed" ]] \
  && pass "(s9d) terminal status is completed" \
  || fail "(s9d) terminal status is '$(sct get "$KEY" '.status')'"

# ---- AC-1's real assertion: NO receipt was hand-planted -------------------------------
# scenario-lib.sh plants `https://github.example/...`; every URL in this run came out of
# the shim as `https://github.test/...` with a distinct sequence number. Both halves
# matter — the first proves nothing was copied from the old library, the second proves the
# URLs were minted per-call rather than a single constant reused.
PLANTED=$(sct get "$KEY" '[.comments[], (.prs[]?.url // empty)] | map(select(test("github\\.example"))) | length')
[[ "$PLANTED" == "0" ]] && pass "(ac1a) no receipt carries a hand-planted github.example URL" \
  || fail "(ac1a) $PLANTED receipt(s) still hand-planted"
MINTED=$(sct get "$KEY" '[.comments[], (.prs[]?.url // empty)] | map(select(test("github\\.test"))) | length')
[[ "$MINTED" == "7" ]] && pass "(ac1b) all 7 receipts (6 comments + 1 PR) were minted by the shim" \
  || fail "(ac1b) minted receipt count is $MINTED (want 7)"
UNIQ=$(sct get "$KEY" '[.comments[], (.prs[]?.url // empty)] | unique | length')
[[ "$UNIQ" == "7" ]] && pass "(ac1c) every minted receipt is distinct (per-call, not one constant)" \
  || fail "(ac1c) only $UNIQ distinct receipts among 7 (a reused constant would pass ac1b)"
grep -q 'pr create --draft' "$GH_LOG" \
  && pass "(ac1d) the PR URL came from an executed 'pr create --draft'" \
  || fail "(ac1d) no pr create in the gh call log"

# ================================================================ scenario 3 ===
# Crash-recovery resume. scenario-liveness-selftest.sh records this composition as
# uncovered debt; it lands here because it needs the minted-receipt machinery above.
#
# The pause span is SELF-ANCHORING at statectl's shared write seam (#260): the seam
# re-reads the on-disk predecessor, takes `from` = that pre-write .lastUpdatedAt (the
# dying session's final write) and stamps `to` = now. There is no first-write ordering
# requirement any more — whichever subcommand the resuming session calls first carries
# the span, and its anchor cannot be the resuming session's own write, because the
# stored session id only changes after the span is recorded.
# Asserting the anchor, not merely that a span exists, is what makes this a real guard.

echo "[e2e-replay] scenario 3: crash-recovery resume through stage-8 re-entry"
RKEY=9102
RBRANCH="claude/acme-$RKEY"
reset_state
sct init "$RKEY" --run-id "e2e-replay-resume-$$" >/dev/null
for n in 1 2 3 4 5 6 7; do complete_stage "$RKEY" "$n"; done
# The ORIGINAL session, as Stage 2 records it. complete_stage does not write one (it
# plants only completion evidence), and without it the resume below would be comparing
# against an empty set — (r4) would read 1 and look like a pass-by-accident.
sct pipeline-session-add "$RKEY" --session-id "11111111-1111-4111-8111-111111111111" --source interactive >/dev/null
[[ "$(sct get "$RKEY" '.stages["7"].status')" == "completed" ]] \
  && pass "(r1) the interrupted run is parked at stage 7 completed" \
  || fail "(r1) could not park the run at stage 7"

DYING_WRITE=$(sct get "$RKEY" '.lastUpdatedAt')
# THE RESUME. There is no pause call to make: statectl's shared write seam records
# the span on whichever subcommand this fresh session writes first, so the resume is
# driven purely by switching the session identity (#260).
#
# The switch REASSIGNS the suite variable rather than prefixing one call. That is
# load-bearing: a single-call override would revert the very next write to the
# original id, which the seam would read as a SECOND cross-session transition and
# record a second span — turning (r8)'s single-span assertion red at the terminal
# write, several subcommands later. A resume changes the owning session for the rest
# of the leg, and the test has to model it that way.
#
# now_iso is second-resolution; sleep so the span has a measurable width.
sleep 1
CLAUDE_CODE_SESSION_ID="$E2E_SESSION_RESUMED"
sct pipeline-session-add "$RKEY" --session-id "22222222-2222-4222-8222-222222222222" --source interactive >/dev/null
SPAN_FROM=$(sct get "$RKEY" '.pauseSpans[-1].from')
[[ "$SPAN_FROM" == "$DYING_WRITE" ]] \
  && pass "(r2) the resuming session's FIRST write anchors the span on the dying session's last write" \
  || fail "(r2) pause span from='$SPAN_FROM' want='$DYING_WRITE'"
[[ "$(sct get "$RKEY" '.pauseSpans | length')" == "1" ]] \
  && pass "(r3) exactly one closed pause span is recorded" \
  || fail "(r3) pauseSpans length is $(sct get "$RKEY" '.pauseSpans | length')"

# A resume runs in a DIFFERENT Claude session; Stage 9 attributes cost per session.id, so
# a resume that records nothing contributes zero rows and its cost silently vanishes.
# (That same write is the one that carried the span above — the seam has no ordering
# requirement, so the session record and the span ride together.)
[[ "$(sct get "$RKEY" '.pipelineSessions | length')" == "2" ]] \
  && pass "(r4) the resuming session is recorded alongside the original" \
  || fail "(r4) pipelineSessions length is $(sct get "$RKEY" '.pipelineSessions | length')"

# Stage-8 re-entry hydrates from stageCheckpoint["7"] — the entire context contract for a
# fresh session. Asserting the object EXISTS is the load-bearing half: it did not, for any
# key but 9999, until the scenario-lib re-key fix that this case forced.
HYDRATED=$(sct get "$RKEY" '.stageCheckpoint["7"].branch')
[[ -n "$HYDRATED" && "$HYDRATED" != "null" ]] \
  && pass "(r5) stage-8 re-entry can hydrate branch from stageCheckpoint[7]" \
  || fail "(r5) stageCheckpoint[7] carries no branch to resume from"
# The checkpoint must belong to THIS run. A payload keyed to another ticket is rejected by
# `checkpoint`, and that rejection is what used to leave the object absent entirely.
[[ "$(sct get "$RKEY" '.stageCheckpoint["7"].ticketKey')" == "$RKEY" ]] \
  && pass "(r5b) the hydrated checkpoint is keyed to this run, not a fixture constant" \
  || fail "(r5b) stageCheckpoint[7].ticketKey is '$(sct get "$RKEY" '.stageCheckpoint["7"].ticketKey')' (want $RKEY)"
sct set-stage "$RKEY" 8 --status started >/dev/null
LEG8R=$(node "$LEG" code-review 2>/dev/null)
[[ "$(printf '%s' "$LEG8R" | jq -r '.verdict' 2>/dev/null)" == "approve" ]] \
  && pass "(r6) the resumed stage-8 leg executes production code-review.mjs" \
  || fail "(r6) resumed code-review leg did not return a verdict"
sct review-rounds "$RKEY" --set 1 >/dev/null
sct skill-load-add "$RKEY" --stage 8 --skill review-toolkit:review-lead >/dev/null
sct comment-add "$RKEY" --marker code-review --url "$(mint_comment "$RKEY")" >/dev/null
stage_evidence "$RKEY" 8
sct set-stage "$RKEY" 8 --status completed >/dev/null

sct set-stage "$RKEY" 9 --status started >/dev/null
sct pr-add "$RKEY" --branch "$RBRANCH" --url "$(mint_pr "$RBRANCH")" >/dev/null
sct comment-add "$RKEY" --marker pr --url "$(mint_comment "$RKEY")" >/dev/null
stage_evidence "$RKEY" 9
sct set-stage "$RKEY" 9 --status completed >/dev/null
write_eval "$RKEY"
write_report "$RKEY"
rc=$(sct_rc mark-completed "$RKEY")
[[ "$rc" == "0" ]] && pass "(r7) the resumed run reaches a terminal write" \
  || fail "(r7) resumed mark-completed refused (rc=$rc)"
[[ "$(sct get "$RKEY" '.pauseSpans | length')" == "1" ]] \
  && pass "(r8) the pause span survives to the terminal state (retro evidence)" \
  || fail "(r8) pause span lost before the terminal write"


echo
echo "[e2e-replay] $PASS passed, $FAIL failed"
exit "$FAIL"
