#!/usr/bin/env bash
# statectl-selftest.sh — fixture-based verification of statectl.sh's contract.
#
# Runs against in-memory fixtures in a fresh tmp directory; never invokes a real
# pipeline run. Independent of any pipeline state on disk.
#
# Usage:
#   .claude/skills/run/statectl-selftest.sh
#
# Env:
#   SKIP_STRESS=1   skips the optional stress section (CI environments where
#                   parallel-write tests are too flaky)
#
# Exit code = number of failed tests (0 = all pass).

set -uo pipefail

# Sibling plugin files resolve against this script's own dir (skills/run/).
# Post-pluginization the scripts no longer live under a consumer .claude tree.
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
STATECTL="${SKILL_DIR}/statectl.sh"
STATE_SCHEMA="${SKILL_DIR}/state-schema.md"
MAXSLICE="${SKILL_DIR}/tools/max-pushed-slice.sh"
FIXTURES_DIR="${SKILL_DIR}/statectl-selftest-fixtures"

[[ -x "$STATECTL" ]] || { echo "[self-test] FATAL: $STATECTL not executable"; exit 99; }
[[ -f "$STATE_SCHEMA" ]] || { echo "[self-test] FATAL: $STATE_SCHEMA missing"; exit 99; }
[[ -f "$MAXSLICE" ]] || { echo "[self-test] FATAL: $MAXSLICE missing"; exit 99; }
[[ -d "$FIXTURES_DIR" ]] || { echo "[self-test] FATAL: $FIXTURES_DIR missing"; exit 99; }

TMPDIR_ST=$(mktemp -d -t statectl-selftest.XXXXXX)
trap 'rm -rf "$TMPDIR_ST"' EXIT INT TERM
cd "$TMPDIR_ST" || exit 99
mkdir -p .claude/pipeline-state
# Pin the state dir to the fixture tmp dir. Without this, statectl resolves the
# MAIN checkout's .claude/pipeline-state via git (state_dir, #153) and the
# fixtures would hit real pipeline state. Relative-path assertions below keep
# working because cwd == TMPDIR_ST.
export STATECTL_STATE_DIR="$TMPDIR_ST/.claude/pipeline-state"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: run statectl, capture stdout and exit code.
sct() {
  "$STATECTL" "$@" 2>/dev/null
}
sct_err() {
  # shellcheck disable=SC2069 # deliberate stderr-only capture: stderr -> stdout, original stdout discarded
  "$STATECTL" "$@" 2>&1 >/dev/null
}
sct_rc() {
  "$STATECTL" "$@" >/dev/null 2>&1
  echo "$?"
}

# Helper: reset state file between tests.
reset_state() {
  rm -f .claude/pipeline-state/*.json .claude/pipeline-state/*.tmp
}

# Helper: start + complete one stage with the minimal evidence its completion
# precondition requires (the imperative stage machine refuses a bare
# `--status completed`). Stages 3/7/9 have no precondition; stage 7's checkpoint
# is written where a case needs it (validate_stage7_payload applies there).
complete_stage() {
  local key="$1" n="$2"
  sct set-stage "$key" "$n" --status started >/dev/null
  case "$n" in
    1) sct checkpoint "$key" 1 --json '{"verdict":"no-split"}' >/dev/null ;;
    2) sct worktree-set "$key" --path ".claude/worktrees/acme-$key" --branch "claude/acme-$key" >/dev/null ;;
    4) sct plan-review-set "$key" --overall pass >/dev/null ;;
    5) sct checkpoint "$key" 5 --json '{"changedFiles":[]}' >/dev/null ;;
    6) sct verify-summary-set "$key" --json '{"format":"clean"}' >/dev/null ;;
    7) sct checkpoint "$key" 7 --json "$VALID_PAYLOAD" >/dev/null ;;
    8) sct review-rounds "$key" --set 1 >/dev/null ;;
  esac
  sct set-stage "$key" "$n" --status completed >/dev/null
}

# Helper: write a plausible self-eval file for <key> (the mark-completed eval gate).
write_eval() {
  local key="$1"
  printf '{"ticketKey":%s,"criteria":{"plan_grounding":"PASS"}}\n' "$key" \
    > ".claude/pipeline-state/${key}-eval.json"
}

# Acme single-repo Stage 7 checkpoint payload — flat fields, no perRepo wrapper.
# NOTE: worktreePath here is intentionally absolute. checkpoint/build-checkpoint-7
# store a copy of an already-validated worktreePath and do NOT flow through
# worktree-set, so the repo-relative path-form guard (ws5) does not apply to these
# checkpoint fixtures — they exercise the payload-shape checks in isolation. The
# canonical repo-relative form is enforced only at the worktree-set writer (see
# cmd_worktree_set in statectl.sh and state-schema.md "Worktree").
VALID_PAYLOAD='{"ticketKey":"9999","branch":"claude/acme-9999","headSha":"abc123","worktreePath":"/tmp/x","deviations":[]}'

# ============================================================ core (must-pass) ===

echo "[self-test] core — 100 cases"

# (a) init on absent state file → creates minimal valid state
reset_state
out=$(sct init 9999 --run-id "selftest-run-$$")
content=$(cat .claude/pipeline-state/9999.json)
if [[ "$out" == "state=created" ]] \
   && [[ "$(jq -r '.status' <<< "$content")" == "in_progress" ]] \
   && [[ "$(jq -r '.ticketKey' <<< "$content")" == "9999" ]] \
   && [[ "$(jq -r '.startedAt | length > 0' <<< "$content")" == "true" ]] \
   && [[ "$(jq -r '.stages | length' <<< "$content")" == "0" ]]; then
  pass "(a) init on absent → creates with state=created + minimal shape"
else
  fail "(a) init on absent — got stdout='$out' content='$content'"
fi

# (b) init on existing in_progress → no-op + stdout indicator
out=$(sct init 9999 --run-id "selftest-run-$$")
if [[ "$out" == "state=existing-in_progress" ]]; then
  pass "(b) init on existing in_progress → state=existing-in_progress"
else
  fail "(b) init on existing in_progress — got stdout='$out'"
fi

# (c) init on existing failed → no-op + stdout indicator (NEVER rejects)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
out=$(sct init 9999 --run-id "selftest-run-$$")
rc=$?
if [[ "$out" == "state=existing-failed" && $rc -eq 0 ]]; then
  pass "(c) init on existing failed → state=existing-failed (rc=0)"
else
  fail "(c) init on existing failed — got stdout='$out' rc=$rc"
fi

# (y1) init without --run-id → rejected with --run-id required (D3)
reset_state
err=$(sct_err init 9999)
rc=$(sct_rc init 9999)
if [[ $rc -ne 0 ]] \
   && echo "$err" | grep -q -- "--run-id required" \
   && [[ ! -f .claude/pipeline-state/9999.json ]]; then
  pass "(y1) init missing --run-id → rejected, no state file written"
else
  fail "(y1) init missing --run-id — rc=$rc err='$err' file-exists=$(test -f .claude/pipeline-state/9999.json && echo yes || echo no)"
fi

# (y2) init --run-id <id> → persisted at top-level .runId
reset_state
sct init 9999 --run-id "test-run-abc" >/dev/null
persisted=$(jq -r '.runId' .claude/pipeline-state/9999.json)
if [[ "$persisted" == "test-run-abc" ]]; then
  pass "(y2) init --run-id → persisted to top-level runId"
else
  fail "(y2) init --run-id — got runId='$persisted'"
fi

# (y3) init on existing in_progress with different --run-id → idempotent (runId preserved, D3)
out=$(sct init 9999 --run-id "test-run-different")
persisted=$(jq -r '.runId' .claude/pipeline-state/9999.json)
if [[ "$out" == "state=existing-in_progress" ]] && [[ "$persisted" == "test-run-abc" ]]; then
  pass "(y3) init on existing with different --run-id → runId preserved"
else
  fail "(y3) init on existing different --run-id — stdout='$out' runId='$persisted'"
fi

# (g) set-stage 3 --status started from currentStage:2, stages.2.completed → succeeds
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
complete_stage 9999 1
complete_stage 9999 2
out_rc=$(sct_rc set-stage 9999 3 --status started)
cur=$(sct get 9999 .currentStage)
status3=$(sct get 9999 '.stages."3".status')
if [[ "$out_rc" == "0" && "$cur" == "3" && "$status3" == "in_progress" ]]; then
  pass "(g) set-stage forward (2→3) → atomic bundle"
else
  fail "(g) set-stage forward — rc=$out_rc cur=$cur status3=$status3"
fi

# (h) set-stage 3 --status started re-entry → preserves startedAt
ts_before=$(sct get 9999 '.stages."3".startedAt')
sleep 1
sct set-stage 9999 3 --status started >/dev/null
ts_after=$(sct get 9999 '.stages."3".startedAt')
last_updated=$(sct get 9999 .lastUpdatedAt)
if [[ "$ts_before" == "$ts_after" && "$last_updated" > "$ts_after" ]]; then
  pass "(h) set-stage re-entry — startedAt preserved, lastUpdatedAt bumped"
else
  fail "(h) set-stage re-entry — before='$ts_before' after='$ts_after' last='$last_updated'"
fi

# (i) set-stage 7 --status started from currentStage:3 → rejects (forward-skip > 1)
err=$(sct_err set-stage 9999 7 --status started)
rc=$(sct_rc set-stage 9999 7 --status started)
if [[ "$rc" != "0" && "$err" == *"forward-skip > 1 rejected"* ]]; then
  pass "(i) set-stage forward-skip > 1 → rejected"
else
  fail "(i) set-stage forward-skip > 1 — rc=$rc err='$err'"
fi

# (j) set-stage 3 --status completed with no startedAt → rejects
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
# Manually set currentStage but not stages.3.startedAt — set-stage refuses completed
err=$(sct_err set-stage 9999 3 --status completed)
rc=$(sct_rc set-stage 9999 3 --status completed)
if [[ "$rc" != "0" && "$err" == *"cannot complete stage 3 with no startedAt"* ]]; then
  pass "(j) set-stage completed with no startedAt → rejected"
else
  fail "(j) set-stage completed with no startedAt — rc=$rc err='$err'"
fi

# (k) set-stage 3 --status started when stages.3.completedAt set → rejects
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
complete_stage 9999 1
complete_stage 9999 2
sct set-stage 9999 3 --status started >/dev/null
sct set-stage 9999 3 --status completed >/dev/null
err=$(sct_err set-stage 9999 3 --status started)
rc=$(sct_rc set-stage 9999 3 --status started)
if [[ "$rc" != "0" && "$err" == *"cannot re-start a completed stage"* ]]; then
  pass "(k) set-stage re-start completed stage → rejected"
else
  fail "(k) set-stage re-start completed — rc=$rc err='$err'"
fi

# (mono1) monotonic guard: start stage 3 while stage 2 is in_progress → rejects.
# diff==1 (currentStage=2, target=3) so the forward-skip>1 guard does NOT fire —
# the monotonic guard is the discriminating reject (reproduces the #217 overlap).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
complete_stage 9999 1
sct set-stage 9999 2 --status started >/dev/null
# stage 2 left in_progress (NOT completed)
err=$(sct_err set-stage 9999 3 --status started)
rc=$(sct_rc set-stage 9999 3 --status started)
if [[ "$rc" == "1" && "$err" == *"cannot start stage 3 while stage 2 is not completed"* ]]; then
  pass "(mono1) start-N while N-1 in_progress → rejected (rc=1)"
else
  fail "(mono1) monotonic reject — rc=$rc err='$err'"
fi

# (mono2) monotonic guard: after stage 2 completes, start stage 3 → allowed.
sct worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999" >/dev/null
sct set-stage 9999 2 --status completed >/dev/null
rc=$(sct_rc set-stage 9999 3 --status started)
cur=$(sct get 9999 .currentStage)
if [[ "$rc" == "0" && "$cur" == "3" ]]; then
  pass "(mono2) start-N after N-1 completed → allowed"
else
  fail "(mono2) monotonic allow — rc=$rc cur=$cur"
fi

# (mono3) --force escapes the monotonic guard: stage 2 in_progress, start 3 --force.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
complete_stage 9999 1
sct set-stage 9999 2 --status started >/dev/null
rc=$(sct_rc set-stage 9999 3 --status started --force)
cur=$(sct get 9999 .currentStage)
if [[ "$rc" == "0" && "$cur" == "3" ]]; then
  pass "(mono3) --force overrides monotonic guard → allowed"
else
  fail "(mono3) monotonic --force — rc=$rc cur=$cur"
fi

# (mono4) base case: first set-stage 1 --status started on fresh init → allowed
# (N==1, no stages.0, no currentStage; the guard must not brick the first write).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
rc=$(sct_rc set-stage 9999 1 --status started)
cur=$(sct get 9999 .currentStage)
if [[ "$rc" == "0" && "$cur" == "1" ]]; then
  pass "(mono4) start-1 on fresh init (no stage 0) → allowed"
else
  fail "(mono4) monotonic base case — rc=$rc cur=$cur"
fi

# (mono5) scope proof: --force does NOT escape the terminal-state guard. Flip to
# completed (the mk_completed trick, defined later for the #154 block — inline the
# jq here since it precedes that helper). set-stage's terminal guard is inline
# (NOT require_mutable), dying with "cannot mutate" — assert that substring, never
# "terminal", which set-stage's path never emits.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
jq '.status = "completed"' .claude/pipeline-state/9999.json > .claude/pipeline-state/9999.json.tmp \
  && mv .claude/pipeline-state/9999.json.tmp .claude/pipeline-state/9999.json
err=$(sct_err set-stage 9999 2 --status started --force)
rc=$(sct_rc set-stage 9999 2 --status started --force)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$err" == *"cannot mutate"* && "$status_after" == "completed" ]]; then
  pass "(mono5) --force does NOT escape terminal guard → rejected (cannot mutate)"
else
  fail "(mono5) monotonic --force scope — rc=$rc err='$err' status='$status_after'"
fi

# (mono6) base case, N>1 with stages.N-1 ABSENT → allowed. Distinct from mono4
# (N==1): here start stage 2 immediately after init, before stage 1 ever exists.
# jq '.stages[$p].status // ""' yields "" for the absent entry, the guard is not
# entered, and the call is allowed (a hand-edited / crash-corrupted state where an
# intermediate stage entry is missing must not brick on this guard).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
rc=$(sct_rc set-stage 9999 2 --status started)
cur=$(sct get 9999 .currentStage)
if [[ "$rc" == "0" && "$cur" == "2" ]]; then
  pass "(mono6) start-N (N>1) with stages.N-1 absent → allowed"
else
  fail "(mono6) monotonic absent N-1 — rc=$rc cur=$cur"
fi

# (mono7) predecessor in `failed` state (not just in_progress) → rejected. The
# guard predicate is `!= completed`, so a failed N-1 blocks too; the message says
# "is not completed", not "in_progress". Guards against a regression to a
# hardcoded `== in_progress` check. Flip stage 1 to failed via jq (no statectl
# primitive marks a single stage failed without going terminal).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
jq '.stages["1"].status = "failed"' .claude/pipeline-state/9999.json > .claude/pipeline-state/9999.json.tmp \
  && mv .claude/pipeline-state/9999.json.tmp .claude/pipeline-state/9999.json
err=$(sct_err set-stage 9999 2 --status started)
rc=$(sct_rc set-stage 9999 2 --status started)
if [[ "$rc" == "1" && "$err" == *"cannot start stage 2 while stage 1 is not completed"* && "$err" == *"status=failed"* ]]; then
  pass "(mono7) start-N while N-1 failed → rejected (is not completed, status=failed)"
else
  fail "(mono7) monotonic failed predecessor — rc=$rc err='$err'"
fi

# (l) checkpoint 7 --json <valid Stage 7 payload> → succeeds
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
rc=$(sct_rc checkpoint 9999 7 --json "$VALID_PAYLOAD")
got=$(sct get 9999 '.stageCheckpoint."7".ticketKey')
if [[ "$rc" == "0" && "$got" == "9999" ]]; then
  pass "(l) checkpoint 7 valid payload → succeeded"
else
  fail "(l) checkpoint 7 valid — rc=$rc got='$got'"
fi

# (m) checkpoint 7 --json <missing branch> → rejects (single-repo flat schema)
bad_payload='{"ticketKey":"9999","headSha":"abc","worktreePath":"/tmp/x","deviations":[]}'
err=$(sct_err checkpoint 9999 7 --json "$bad_payload")
rc=$(sct_rc checkpoint 9999 7 --json "$bad_payload")
if [[ "$rc" != "0" && "$err" == *"branch"* ]]; then
  pass "(m) checkpoint 7 missing branch → rejected"
else
  fail "(m) checkpoint 7 missing branch — rc=$rc err='$err'"
fi

# (q) mark-failed without --stage and no currentStage → omits stage from failureContext
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
# Don't call set-stage; currentStage is absent
sct mark-failed 9999 --reason non-main-base-autonomous >/dev/null
has_stage=$(sct get 9999 '.failureContext | has("stage")')
reason=$(sct get 9999 .failureContext.reason)
status_now=$(sct get 9999 .status)
if [[ "$has_stage" == "false" && "$reason" == "non-main-base-autonomous" && "$status_now" == "failed" ]]; then
  pass "(q) mark-failed pre-Stage-1 → failureContext WITHOUT stage; status=failed"
else
  fail "(q) mark-failed pre-Stage-1 — has_stage=$has_stage reason='$reason' status=$status_now"
fi

# (q1) mark-failed on a completed run → rejects without --force (terminal-state guard)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
# Manually mark completed (no statectl primitive for this; tests the guard)
jq '.status = "completed"' .claude/pipeline-state/9999.json > .claude/pipeline-state/9999.json.tmp \
  && mv .claude/pipeline-state/9999.json.tmp .claude/pipeline-state/9999.json
err=$(sct_err mark-failed 9999 --reason plan-reviewer-block)
rc=$(sct_rc mark-failed 9999 --reason plan-reviewer-block)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" != "0" && "$err" == *"terminal"* && "$status_after" == "completed" ]]; then
  pass "(q1) mark-failed on completed run → rejected (status preserved)"
else
  fail "(q1) mark-failed on completed — rc=$rc err='$err' status_after='$status_after'"
fi


# (q2) get is read-only — state file on disk unchanged after read
reset_state
printf '%s' '{"ticketKey":"9999","status":"in_progress","stageCheckpoint":{"7":{"x":1}}}' \
  > .claude/pipeline-state/9999.json
before_hash=$(shasum .claude/pipeline-state/9999.json | awk '{print $1}')
sct get 9999 .status >/dev/null
after_hash=$(shasum .claude/pipeline-state/9999.json | awk '{print $1}')
if [[ "$before_hash" == "$after_hash" ]]; then
  pass "(q2) get is read-only → file unchanged after read"
else
  fail "(q2) get MUTATED the file (before=$before_hash after=$after_hash)"
fi

# (q3) mark-failed --reason worktree-creation-failed --stage 2 → Stage-2 enum accepted,
#      gitError payload carried through, status=failed (the new failure path from #147)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 2 --status started >/dev/null
sct mark-failed 9999 --reason worktree-creation-failed --stage 2 \
  --json "$(sct build-failure-context --reason worktree-creation-failed --stage 2 --kv gitError='fatal: boom')" >/dev/null
reason=$(sct get 9999 .failureContext.reason)
stage=$(sct get 9999 .failureContext.stage)
giterr=$(sct get 9999 .failureContext.gitError)
status_now=$(sct get 9999 .status)
if [[ "$reason" == "worktree-creation-failed" && "$stage" == "2" \
      && "$giterr" == "fatal: boom" && "$status_now" == "failed" ]]; then
  pass "(q3) mark-failed worktree-creation-failed (Stage 2) → reason+stage+gitError+status correct"
else
  fail "(q3) mark-failed worktree-creation-failed — reason='$reason' stage='$stage' gitError='$giterr' status=$status_now"
fi

# (mps) max-pushed-slice.sh — the shared slice-derivation helper used by Stage 1
#       seeding and the Stage 2 resume sanity guard (#147). Guards against the
#       ref-prefix-strip bug that made the old inline loops always return 0.
mps() { printf '%s\n' "$1" | bash "$MAXSLICE" "$2" 2>/dev/null; }
# Full refs/heads/ form (as `git ls-remote | awk '{print $2}'` emits):
mps_full=$'refs/heads/claude/acme-42\nrefs/heads/claude/acme-42-pr2\nrefs/heads/claude/acme-42-pr3'
got=$(mps "$mps_full" 42)
[[ "$got" == "3" ]] && pass "(mps1) full refs/heads form, slices 1-3 → 3" \
  || fail "(mps1) full refs/heads form → got '$got' (want 3)"
# Unsuffixed branch only → slice 1 (the prefix-strip bug returned 0 here):
got=$(mps $'refs/heads/claude/acme-42' 42)
[[ "$got" == "1" ]] && pass "(mps2) unsuffixed branch only → 1" \
  || fail "(mps2) unsuffixed branch → got '$got' (want 1)"
# Short-name form (no refs/heads/ prefix):
got=$(mps $'claude/acme-42-pr2' 42)
[[ "$got" == "2" ]] && pass "(mps3) short-name form → 2" \
  || fail "(mps3) short-name form → got '$got' (want 2)"
# No matching ref (fresh run) → 0:
got=$(mps "" 42)
[[ "$got" == "0" ]] && pass "(mps4) no refs → 0" \
  || fail "(mps4) no refs → got '$got' (want 0)"
# Sibling-issue noise must NOT inflate the count (420, 7 are not issue 42):
got=$(mps $'refs/heads/claude/acme-420\nrefs/heads/claude/acme-420-pr5\nrefs/heads/claude/acme-7' 42)
[[ "$got" == "0" ]] && pass "(mps5) sibling-issue refs filtered → 0" \
  || fail "(mps5) sibling-issue refs → got '$got' (want 0)"
# Missing issue-number arg → usage error (rc=2):
rc=0; printf '' | bash "$MAXSLICE" >/dev/null 2>&1 || rc=$?
[[ "$rc" == "2" ]] && pass "(mps6) missing issue arg → usage error rc=2" \
  || fail "(mps6) missing issue arg → rc=$rc (want 2)"

# (psa1) pipeline-session-add: first call appends; second call same sid is idempotent
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
SID1="11111111-2222-4333-8444-555555555555"
sct pipeline-session-add 9999 --session-id "$SID1" --source interactive >/dev/null
sct pipeline-session-add 9999 --session-id "$SID1" --source interactive >/dev/null
count=$(sct get 9999 '.pipelineSessions | length')
first_src=$(sct get 9999 '.pipelineSessions[0].source')
first_sid=$(sct get 9999 '.pipelineSessions[0].sessionId')
if [[ "$count" == "1" && "$first_sid" == "$SID1" && "$first_src" == "interactive" ]]; then
  pass "(psa1) pipeline-session-add → first appends, second same-sid is idempotent"
else
  fail "(psa1) pipeline-session-add idempotency — count=$count sid=$first_sid src=$first_src"
fi

# (psa2) pipeline-session-add: second different sid appends a new record
SID2="66666666-7777-4888-8999-aaaaaaaaaaaa"
sct pipeline-session-add 9999 --session-id "$SID2" --source interactive >/dev/null
count=$(sct get 9999 '.pipelineSessions | length')
second_src=$(sct get 9999 '.pipelineSessions[1].source')
if [[ "$count" == "2" && "$second_src" == "interactive" ]]; then
  pass "(psa2) pipeline-session-add → second distinct sid appends"
else
  fail "(psa2) pipeline-session-add second distinct sid — count=$count src=$second_src"
fi

# (psa3) pipeline-session-add: malformed session id (too short, not a UUID) is rejected
err=$(sct_err pipeline-session-add 9999 --session-id short)
rc=$(sct_rc pipeline-session-add 9999 --session-id short)
if [[ "$rc" != "0" && "$err" == *"not a native session UUID"* ]]; then
  pass "(psa3) pipeline-session-add malformed sid → rejected"
else
  fail "(psa3) pipeline-session-add malformed sid — rc=$rc err='$err'"
fi

# (psa4) pipeline-session-add: invalid --source is rejected
err=$(sct_err pipeline-session-add 9999 --session-id "$SID1" --source not-a-source)
rc=$(sct_rc pipeline-session-add 9999 --session-id "$SID1" --source not-a-source)
if [[ "$rc" != "0" && "$err" == *"--source must be 'interactive'"* ]]; then
  pass "(psa4) pipeline-session-add invalid source → rejected"
else
  fail "(psa4) pipeline-session-add invalid source — rc=$rc err='$err'"
fi

# (psa5) pipeline-session-add: --source omitted is allowed; record's source is null
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct pipeline-session-add 9999 --session-id "$SID1" >/dev/null
src=$(sct get 9999 '.pipelineSessions[0].source')
if [[ "$src" == "null" ]]; then
  pass "(psa5) pipeline-session-add omitted source → record source=null"
else
  fail "(psa5) pipeline-session-add omitted source — got src='$src'"
fi

# (va1) verify-attempts: first incr creates the class at 1 and echoes it
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
out=$(sct verify-attempts 9999 --incr TYPE_ERROR)
stored=$(sct get 9999 '.verifyAttempts.TYPE_ERROR')
if [[ "$out" == "1" && "$stored" == "1" ]]; then
  pass "(va1) verify-attempts first incr → 1 (echoed and stored)"
else
  fail "(va1) verify-attempts first incr — echoed='$out' stored='$stored'"
fi

# (va2) verify-attempts: second incr of same class → 2
out=$(sct verify-attempts 9999 --incr TYPE_ERROR)
if [[ "$out" == "2" ]]; then
  pass "(va2) verify-attempts second incr same class → 2"
else
  fail "(va2) verify-attempts second incr — got '$out'"
fi

# (va3) verify-attempts: a distinct class increments independently
out=$(sct verify-attempts 9999 --incr TEST_FAILURE)
te=$(sct get 9999 '.verifyAttempts.TYPE_ERROR')
if [[ "$out" == "1" && "$te" == "2" ]]; then
  pass "(va3) verify-attempts distinct class is independent (TEST_FAILURE=1, TYPE_ERROR still 2)"
else
  fail "(va3) verify-attempts distinct class — TEST_FAILURE='$out' TYPE_ERROR='$te'"
fi

# (va4) verify-attempts: unknown failure class is rejected
err=$(sct_err verify-attempts 9999 --incr NOT_A_CLASS)
rc=$(sct_rc verify-attempts 9999 --incr NOT_A_CLASS)
if [[ "$rc" != "0" && "$err" == *"--incr must be one of"* ]]; then
  pass "(va4) verify-attempts invalid class → rejected"
else
  fail "(va4) verify-attempts invalid class — rc=$rc err='$err'"
fi

# (psa6) pipeline-session-add: a synthetic RUN_ID-derived id (the old, never-matching
# format) is rejected — regression guard for the cost-tracking session-id mismatch bug.
err=$(sct_err pipeline-session-add 9999 --session-id "2026-06-08T214945Z-Mac-edf895c0-slice1-stage2")
rc=$(sct_rc pipeline-session-add 9999 --session-id "2026-06-08T214945Z-Mac-edf895c0-slice1-stage2")
if [[ "$rc" != "0" && "$err" == *"not a native session UUID"* ]]; then
  pass "(psa6) pipeline-session-add RUN_ID-derived sid → rejected"
else
  fail "(psa6) pipeline-session-add RUN_ID-derived sid — rc=$rc err='$err'"
fi

# (sls1) slice-set: slice 1 happy path → fields written, priorSliceBranch=null
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct slice-set 9999 \
  --current 1 --branch claude/acme-9999 \
  --worktree-base main --pr-base main >/dev/null
cur=$(sct get 9999 .currentSlice)
sb=$(sct get 9999 .sliceBranch)
psb=$(sct get 9999 .priorSliceBranch)
wb=$(sct get 9999 .worktreeBase)
pb=$(sct get 9999 .prBase)
if [[ "$cur" == "1" && "$sb" == "claude/acme-9999" && "$psb" == "null" \
   && "$wb" == "main" && "$pb" == "main" ]]; then
  pass "(sls1) slice-set slice 1 → all five fields written, priorSliceBranch=null"
else
  fail "(sls1) slice-set slice 1 — cur=$cur sb=$sb psb=$psb wb=$wb pb=$pb"
fi

# (sls2) slice-set: slice 2 happy path → priorSliceBranch required, fields written
sct slice-set 9999 \
  --current 2 --branch claude/acme-9999-pr2 \
  --prior-branch claude/acme-9999 \
  --worktree-base claude/acme-9999 --pr-base claude/acme-9999 >/dev/null
cur=$(sct get 9999 .currentSlice)
psb=$(sct get 9999 .priorSliceBranch)
pb=$(sct get 9999 .prBase)
if [[ "$cur" == "2" && "$psb" == "claude/acme-9999" && "$pb" == "claude/acme-9999" ]]; then
  pass "(sls2) slice-set slice 2 → priorSliceBranch + prBase point at slice 1"
else
  fail "(sls2) slice-set slice 2 — cur=$cur psb=$psb pb=$pb"
fi

# (sls3) slice-set: slice 1 with --prior-branch → rejected
err=$(sct_err slice-set 9999 \
  --current 1 --branch claude/acme-9999 \
  --prior-branch claude/acme-9999 \
  --worktree-base main --pr-base main)
rc=$(sct_rc slice-set 9999 \
  --current 1 --branch claude/acme-9999 \
  --prior-branch claude/acme-9999 \
  --worktree-base main --pr-base main)
if [[ "$rc" != "0" && "$err" == *"omitted when --current is 1"* ]]; then
  pass "(sls3) slice-set slice 1 with --prior-branch → rejected"
else
  fail "(sls3) slice-set slice 1 + prior — rc=$rc err='$err'"
fi

# (sls4) slice-set: slice 2 WITHOUT --prior-branch → rejected
err=$(sct_err slice-set 9999 \
  --current 2 --branch claude/acme-9999-pr2 \
  --worktree-base main --pr-base main)
rc=$(sct_rc slice-set 9999 \
  --current 2 --branch claude/acme-9999-pr2 \
  --worktree-base main --pr-base main)
if [[ "$rc" != "0" && "$err" == *"required when --current > 1"* ]]; then
  pass "(sls4) slice-set slice 2 without --prior-branch → rejected"
else
  fail "(sls4) slice-set slice 2 no prior — rc=$rc err='$err'"
fi

# (sls5) slice-set: non-integer --current → rejected
err=$(sct_err slice-set 9999 \
  --current foo --branch x --worktree-base main --pr-base main)
rc=$(sct_rc slice-set 9999 \
  --current foo --branch x --worktree-base main --pr-base main)
if [[ "$rc" != "0" && "$err" == *"positive integer"* ]]; then
  pass "(sls5) slice-set non-integer --current → rejected"
else
  fail "(sls5) slice-set non-integer current — rc=$rc err='$err'"
fi

# (b1) build-failure-context happy path: --kv-lines splits on \n, output is full failureContext JSON
reset_state
out=$(sct build-failure-context --reason plan-reviewer-block --stage 4 --kv-lines "blockers=line1
line2")
reason=$(jq -r '.reason' <<< "$out")
stage=$(jq -r '.stage' <<< "$out")
arr=$(jq -c '.blockers' <<< "$out")
if [[ "$reason" == "plan-reviewer-block" && "$stage" == "4" && "$arr" == '["line1","line2"]' ]]; then
  pass "(b1) build-failure-context happy path → full failureContext JSON with split blockers"
else
  fail "(b1) build-failure-context happy path — reason='$reason' stage='$stage' arr='$arr'"
fi

# (b2) build-failure-context invalid --reason → rejected with [statectl-error]
err=$(sct_err build-failure-context --reason not-a-real-reason --kv x=y)
rc=$(sct_rc build-failure-context --reason not-a-real-reason --kv x=y)
if [[ "$rc" != "0" && "$err" == *"invalid --reason"* ]]; then
  pass "(b2) build-failure-context invalid reason → rejected"
else
  fail "(b2) build-failure-context invalid reason — rc=$rc err='$err'"
fi

# (b3) build-checkpoint-7 happy path: output round-trips through cmd_checkpoint
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
built=$(sct build-checkpoint-7 \
  --issue 9999 --branch claude/acme-9999 --head abc123 --worktree /tmp/x \
  --plan docs/plans/acme-9999.md --free-note "" --doc-updater-findings "")
# Spot-check key fields, then feed into cmd_checkpoint as defense-in-depth
issue=$(jq -r '.ticketKey' <<< "$built")
branch=$(jq -r '.branch' <<< "$built")
rc_check=$(sct_rc checkpoint 9999 7 --json "$built")
if [[ "$issue" == "9999" && "$branch" == "claude/acme-9999" && "$rc_check" == "0" ]]; then
  pass "(b3) build-checkpoint-7 happy path → round-trips through cmd_checkpoint"
else
  fail "(b3) build-checkpoint-7 happy path — issue='$issue' branch='$branch' checkpoint_rc=$rc_check"
fi

# (b4) build-checkpoint-7 invalid deviation kind → rejected at builder (not at consumer)
err=$(sct_err build-checkpoint-7 \
  --issue 9999 --branch claude/acme-9999 --head abc --worktree /tmp/x \
  --deviations '[{"kind":"bogus","planSection":"x","note":"y"}]')
rc=$(sct_rc build-checkpoint-7 \
  --issue 9999 --branch claude/acme-9999 --head abc --worktree /tmp/x \
  --deviations '[{"kind":"bogus","planSection":"x","note":"y"}]')
if [[ "$rc" != "0" && "$err" == *"kind"* ]]; then
  pass "(b4) build-checkpoint-7 invalid deviation kind → rejected at builder"
else
  fail "(b4) build-checkpoint-7 invalid deviation kind — rc=$rc err='$err'"
fi

# (b5) build-failure-context --kv-num with non-numeric value → rejected
err=$(sct_err build-failure-context --reason stale-branch-autonomous --kv-num count=abc)
rc=$(sct_rc build-failure-context --reason stale-branch-autonomous --kv-num count=abc)
if [[ "$rc" != "0" && "$err" == *"not numeric"* ]]; then
  pass "(b5) build-failure-context --kv-num non-numeric → rejected"
else
  fail "(b5) build-failure-context --kv-num non-numeric — rc=$rc err='$err'"
fi

# (b6) build-failure-context duplicate key across mixed --kv types → rejected
err=$(sct_err build-failure-context --reason plan-reviewer-block --kv x=1 --kv-num x=2)
rc=$(sct_rc build-failure-context --reason plan-reviewer-block --kv x=1 --kv-num x=2)
if [[ "$rc" != "0" && "$err" == *"duplicate key"* ]]; then
  pass "(b6) build-failure-context duplicate key across mixed --kv types → rejected"
else
  fail "(b6) build-failure-context duplicate key — rc=$rc err='$err'"
fi

# (b7) build-checkpoint-7 missing required field → rejected
err=$(sct_err build-checkpoint-7 --issue 9999 --branch claude/acme-9999 --worktree /tmp/x)
rc=$(sct_rc build-checkpoint-7 --issue 9999 --branch claude/acme-9999 --worktree /tmp/x)
if [[ "$rc" != "0" && "$err" == *"required"* ]]; then
  pass "(b7) build-checkpoint-7 missing required --head → rejected"
else
  fail "(b7) build-checkpoint-7 missing required --head — rc=$rc err='$err'"
fi

# (b8) build-failure-context --kv-lines: trailing newlines stripped by the
# parse_kv_pair → command-substitution path. Documents the de-facto contract:
# "line1\nline2\n" reaches jq as "line1\nline2", yielding ["line1","line2"].
out=$(sct build-failure-context --reason plan-reviewer-block --kv-lines "blockers=line1
line2
")
arr=$(jq -c '.blockers' <<< "$out")
if [[ "$arr" == '["line1","line2"]' ]]; then
  pass "(b8) build-failure-context --kv-lines trailing newline → stripped (no empty trailing element)"
else
  fail "(b8) build-failure-context --kv-lines trailing newline — arr='$arr'"
fi

# (ws1) worktree-set happy path → both fields + lastUpdatedAt in one atomic bundle
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999" >/dev/null
wt=$(sct get 9999 '.worktreePath')
br=$(sct get 9999 '.branch')
if [[ "$wt" == ".claude/worktrees/acme-9999" && "$br" == "claude/acme-9999" ]]; then
  pass "(ws1) worktree-set → worktreePath + branch written atomically"
else
  fail "(ws1) worktree-set — wt='$wt' br='$br'"
fi

# (ws2) worktree-set missing --branch → rejected (relative path so the missing-arg
# reject is what fires, keeping the whole worktree-set block consistent with ws1/ws3/ws4)
err=$(sct_err worktree-set 9999 --path ".claude/worktrees/acme-9999")
rc=$(sct_rc worktree-set 9999 --path ".claude/worktrees/acme-9999")
if [[ "$rc" != "0" && "$err" == *"missing"* ]]; then
  pass "(ws2) worktree-set missing --branch → rejected"
else
  fail "(ws2) worktree-set missing --branch — rc=$rc err='$err'"
fi

# (ws2b) worktree-set missing --path → rejected (symmetric to ws2; proves the
# --path slot is independently parsed and checked)
err=$(sct_err worktree-set 9999 --branch "claude/acme-9999")
rc=$(sct_rc worktree-set 9999 --branch "claude/acme-9999")
if [[ "$rc" != "0" && "$err" == *"missing"* ]]; then
  pass "(ws2b) worktree-set missing --path → rejected"
else
  fail "(ws2b) worktree-set missing --path — rc=$rc err='$err'"
fi

# (ws3) worktree-set with no state file → rejected (init must run first).
# Path is repo-relative so this case exercises the no-state-file reject, not the
# path-form reject (ws5).
reset_state
err=$(sct_err worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999")
rc=$(sct_rc worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999")
if [[ "$rc" != "0" && "$err" == *"no state file"* ]]; then
  pass "(ws3) worktree-set on absent state → rejected"
else
  fail "(ws3) worktree-set absent state — rc=$rc err='$err'"
fi

# (ws4) worktree-set per-slice overwrite (stacked-PR mode) → both fields replaced
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999" >/dev/null
sct worktree-set 9999 --path ".claude/worktrees/acme-9999-pr2" --branch "claude/acme-9999-pr2" >/dev/null
wt=$(sct get 9999 '.worktreePath')
br=$(sct get 9999 '.branch')
if [[ "$wt" == ".claude/worktrees/acme-9999-pr2" && "$br" == "claude/acme-9999-pr2" ]]; then
  pass "(ws4) worktree-set per-slice overwrite → both fields replaced"
else
  fail "(ws4) worktree-set overwrite — wt='$wt' br='$br'"
fi

# (ws5) worktree-set with an absolute path → rejected (canonical form is repo-relative).
# Guards against re-introducing the schema↔behavior drift fixed in issue #152.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
err=$(sct_err worktree-set 9999 --path "/abs/wt/acme-9999" --branch "claude/acme-9999")
rc=$(sct_rc worktree-set 9999 --path "/abs/wt/acme-9999" --branch "claude/acme-9999")
if [[ "$rc" != "0" && "$err" == *"relative"* ]]; then
  pass "(ws5) worktree-set absolute path → rejected"
else
  fail "(ws5) worktree-set absolute path — rc=$rc err='$err'"
fi

# (pa1) pr-add happy path → creates .prs map with url entry
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct pr-add 9999 --branch "claude/acme-9999" --url "https://github.com/o/r/pull/1" >/dev/null
url=$(sct get 9999 '.prs."claude/acme-9999".url')
if [[ "$url" == "https://github.com/o/r/pull/1" ]]; then
  pass "(pa1) pr-add → .prs[branch].url written"
else
  fail "(pa1) pr-add — url='$url'"
fi

# (pa2) pr-add second branch → both entries retained (stacked-PR accumulation)
sct pr-add 9999 --branch "claude/acme-9999-pr2" --url "https://github.com/o/r/pull/2" >/dev/null
count=$(sct get 9999 '.prs | length')
url1=$(sct get 9999 '.prs."claude/acme-9999".url')
if [[ "$count" == "2" && "$url1" == "https://github.com/o/r/pull/1" ]]; then
  pass "(pa2) pr-add second branch → accumulates (2 entries, first intact)"
else
  fail "(pa2) pr-add accumulate — count=$count url1='$url1'"
fi

# (pa3) pr-add same branch → url overwritten, no duplicate entry
sct pr-add 9999 --branch "claude/acme-9999" --url "https://github.com/o/r/pull/9" >/dev/null
count=$(sct get 9999 '.prs | length')
url1=$(sct get 9999 '.prs."claude/acme-9999".url')
if [[ "$count" == "2" && "$url1" == "https://github.com/o/r/pull/9" ]]; then
  pass "(pa3) pr-add same branch → overwrites url (idempotent for retries)"
else
  fail "(pa3) pr-add overwrite — count=$count url1='$url1'"
fi

# (pa4) pr-add non-https url → rejected at record time
err=$(sct_err pr-add 9999 --branch "b" --url "not-a-url")
rc=$(sct_rc pr-add 9999 --branch "b" --url "not-a-url")
if [[ "$rc" != "0" && "$err" == *"https://"* ]]; then
  pass "(pa4) pr-add non-https url → rejected"
else
  fail "(pa4) pr-add non-https — rc=$rc err='$err'"
fi

# (pa5) pr-add missing --url → rejected
err=$(sct_err pr-add 9999 --branch "b")
rc=$(sct_rc pr-add 9999 --branch "b")
if [[ "$rc" != "0" && "$err" == *"missing"* ]]; then
  pass "(pa5) pr-add missing --url → rejected"
else
  fail "(pa5) pr-add missing --url — rc=$rc err='$err'"
fi

# (pause1) pause-add → appends ONE closed span; from = prior .lastUpdatedAt
# (self-anchor), to = now, from < to. now_iso is second-resolution, so sleep 1
# to guarantee a measurable gap. ISO-8601 fixed-width Z timestamps sort
# lexicographically == chronologically, so `<` in [[ ]] is a valid time compare.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
prev=$(sct get 9999 '.lastUpdatedAt')
sleep 1
sct pause-add 9999 --reason session-resume >/dev/null
count=$(sct get 9999 '.pauseSpans | length')
pfrom=$(sct get 9999 '.pauseSpans[0].from')
pto=$(sct get 9999 '.pauseSpans[0].to')
preason=$(sct get 9999 '.pauseSpans[0].reason')
if [[ "$count" == "1" && "$preason" == "session-resume" && "$pfrom" == "$prev" ]] && [[ "$pfrom" < "$pto" ]]; then
  pass "(pause1) pause-add → one closed span, from=prior lastUpdatedAt, from<to"
else
  fail "(pause1) pause-add — count=$count reason=$preason from=$pfrom prev=$prev to=$pto"
fi

# (pause2) pause-add is require_mutable-guarded: rejected on a terminal run
# without --force, succeeds with --force (#154 consistency; NOT exempt like
# pipeline-session-add).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
err=$(sct_err pause-add 9999 --reason session-resume)
rc=$(sct_rc pause-add 9999 --reason session-resume)
rcforce=$(sct_rc pause-add 9999 --reason session-resume --force)
if [[ "$rc" != "0" && "$err" == *"terminal"* && "$rcforce" == "0" ]]; then
  pass "(pause2) pause-add on terminal run → rejected without --force, succeeds with --force"
else
  fail "(pause2) pause-add terminal guard — rc=$rc rcforce=$rcforce err='$err'"
fi

# (pause3) stage-times.sh is pause-aware: against the committed pause/resume
# fixture, the effective total is < wall by ~the pause, and the straddling
# stage's effective duration shrinks. Drives AC #7 (fixture in a committed
# location; asserted end-to-end through the tool via STATECTL_STATE_DIR).
PAUSE_FIXTURE_DIR="${SKILL_DIR}/tools/stage-times-fixtures"
STAGE_TIMES="${SKILL_DIR}/tools/stage-times.sh"
st_out=$(STATECTL_STATE_DIR="$PAUSE_FIXTURE_DIR" bash "$STAGE_TIMES" acme-89-pause 2>&1)
total_line=$(grep '^total:' <<< "$st_out")
stage5_line=$(grep '^  5 ' <<< "$st_out")
if [[ "$total_line" == *"45 min effective"* && "$total_line" == *"wall 260 min"* && "$stage5_line" == *"15 min"* ]]; then
  pass "(pause3) stage-times.sh pause-aware → effective<wall (total 45<260 min, stage5 15 min)"
else
  fail "(pause3) stage-times pause-aware — total='$total_line' stage5='$stage5_line'"
fi

# (rr1) review-rounds happy path → codeReviewRounds written, exhausted untouched.
# init does not seed codeReviewExhausted — the schema default is by-absence
# (consumers check `== true`), so a plain --set must leave it absent/false.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct review-rounds 9999 --set 2 >/dev/null
rounds=$(sct get 9999 '.codeReviewRounds')
exhausted=$(sct get 9999 '.codeReviewExhausted // false')
updated=$(sct get 9999 '.lastUpdatedAt | length > 0')
if [[ "$rounds" == "2" && "$exhausted" == "false" && "$updated" == "true" ]]; then
  pass "(rr1) review-rounds --set 2 → codeReviewRounds=2, exhausted stays false"
else
  fail "(rr1) review-rounds happy path — rounds='$rounds' exhausted='$exhausted' updated='$updated'"
fi

# (rr2) review-rounds --set out of range → rejected (rc=1, value-validation class)
err=$(sct_err review-rounds 9999 --set 4)
rc=$(sct_rc review-rounds 9999 --set 4)
if [[ "$rc" == "1" && "$err" == *"[statectl-error]"* && "$err" == *"1, 2, or 3"* ]]; then
  pass "(rr2) review-rounds --set 4 → rejected (rc=1)"
else
  fail "(rr2) review-rounds range reject — rc=$rc err='$err'"
fi

# (rr2b) review-rounds missing --set → rejected (rc=3, arg-shape class)
err=$(sct_err review-rounds 9999)
rc=$(sct_rc review-rounds 9999)
if [[ "$rc" == "3" && "$err" == *"missing"* ]]; then
  pass "(rr2b) review-rounds missing --set → rejected (rc=3)"
else
  fail "(rr2b) review-rounds missing --set — rc=$rc err='$err'"
fi

# (rr2c) review-rounds unknown arg → rejected (rc=3, arg-shape class)
rc=$(sct_rc review-rounds 9999 --set 2 --bogus)
err=$(sct_err review-rounds 9999 --set 2 --bogus)
if [[ "$rc" == "3" && "$err" == *"unknown arg"* ]]; then
  pass "(rr2c) review-rounds unknown arg → rejected (rc=3)"
else
  fail "(rr2c) review-rounds unknown arg — rc=$rc err='$err'"
fi

# (rr2d) review-rounds empty --set "" → treated as missing flag (rc=3), not a
# range reject — the [[ -n ]] guard fires before the ^[1-3]$ range check
# (plan-review warning #2)
rc=$(sct_rc review-rounds 9999 --set "")
err=$(sct_err review-rounds 9999 --set "")
if [[ "$rc" == "3" && "$err" == *"missing"* ]]; then
  pass "(rr2d) review-rounds empty --set → missing-flag reject (rc=3)"
else
  fail "(rr2d) review-rounds empty --set — rc=$rc err='$err'"
fi

# (rr3) review-rounds --exhausted → both fields written in one atomic bundle
sct review-rounds 9999 --set 3 --exhausted >/dev/null
rounds=$(sct get 9999 '.codeReviewRounds')
exhausted=$(sct get 9999 '.codeReviewExhausted')
if [[ "$rounds" == "3" && "$exhausted" == "true" ]]; then
  pass "(rr3) review-rounds --set 3 --exhausted → both fields written"
else
  fail "(rr3) review-rounds exhausted — rounds='$rounds' exhausted='$exhausted'"
fi

# (rr4) overwrite-on-retry: re-running --set with a new round count overwrites
# the previous value (idempotent for retries, mirroring pr-add's URL overwrite)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct review-rounds 9999 --set 1 >/dev/null
sct review-rounds 9999 --set 2 >/dev/null
rounds_mid=$(sct get 9999 '.codeReviewRounds')
sct review-rounds 9999 --set 3 >/dev/null
rounds_final=$(sct get 9999 '.codeReviewRounds')
if [[ "$rounds_mid" == "2" && "$rounds_final" == "3" ]]; then
  pass "(rr4) review-rounds overwrite-on-retry → round count replaced each write"
else
  fail "(rr4) review-rounds overwrite — rounds_mid='$rounds_mid' rounds_final='$rounds_final'"
fi

# (rr6) additive-only invariant (resume-critical, plan-review warning #1):
# a later plain --set never resets a previously-set codeReviewExhausted=true
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct review-rounds 9999 --set 3 --exhausted >/dev/null
sct review-rounds 9999 --set 2 >/dev/null
rounds=$(sct get 9999 '.codeReviewRounds')
exhausted=$(sct get 9999 '.codeReviewExhausted')
if [[ "$rounds" == "2" && "$exhausted" == "true" ]]; then
  pass "(rr6) exhaustion survives later plain --set (additive-only invariant)"
else
  fail "(rr6) review-rounds additive-only — rounds='$rounds' exhausted='$exhausted'"
fi

# (rr5) review-rounds with no state file → rejected (init must run first)
reset_state
err=$(sct_err review-rounds 9999 --set 1)
rc=$(sct_rc review-rounds 9999 --set 1)
if [[ "$rc" == "2" && "$err" == *"no state file"* ]]; then
  pass "(rr5) review-rounds on absent state → rejected"
else
  fail "(rr5) review-rounds absent state — rc=$rc err='$err'"
fi

# (mc1) mark-completed happy path → terminal status + lastUpdatedAt in one bundle
# (walks all 9 stages with evidence + writes the self-eval — the terminal gates)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
for n in 1 2 3 4 5 6 7 8 9; do complete_stage 9999 "$n"; done
write_eval 9999
sct mark-completed 9999 >/dev/null
status=$(sct get 9999 '.status')
updated=$(sct get 9999 '.lastUpdatedAt | length > 0')
if [[ "$status" == "completed" && "$updated" == "true" ]]; then
  pass "(mc1) mark-completed → status=completed"
else
  fail "(mc1) mark-completed happy path — status='$status' updated='$updated'"
fi

# (mc2) mark-completed on terminal state → rejected without --force, allowed with
err=$(sct_err mark-completed 9999)
rc=$(sct_rc mark-completed 9999)
rc_force=$(sct_rc mark-completed 9999 --force)
if [[ "$rc" == "1" && "$err" == *"terminal"* && "$rc_force" == "0" ]]; then
  pass "(mc2) mark-completed on terminal → rejected; --force overrides"
else
  fail "(mc2) mark-completed terminal guard — rc=$rc rc_force=$rc_force err='$err'"
fi

# (mc2b) mark-completed unknown arg → rejected (rc=3, arg-shape class)
rc=$(sct_rc mark-completed 9999 --bogus)
err=$(sct_err mark-completed 9999 --bogus)
if [[ "$rc" == "3" && "$err" == *"unknown arg"* ]]; then
  pass "(mc2b) mark-completed unknown arg → rejected (rc=3)"
else
  fail "(mc2b) mark-completed unknown arg — rc=$rc err='$err'"
fi

# (mc3) mark-completed on failed state → rejected without --force (same guard)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
rc=$(sct_rc mark-completed 9999)
status=$(sct get 9999 '.status')
if [[ "$rc" == "1" && "$status" == "failed" ]]; then
  pass "(mc3) mark-completed on failed state → rejected, status untouched"
else
  fail "(mc3) mark-completed on failed — rc=$rc status='$status'"
fi

# (mc4) mark-completed with no state file → rejected (init must run first)
reset_state
rc=$(sct_rc mark-completed 9999)
err=$(sct_err mark-completed 9999)
if [[ "$rc" == "2" && "$err" == *"no state file"* ]]; then
  pass "(mc4) mark-completed on absent state → rejected"
else
  fail "(mc4) mark-completed absent state — rc=$rc err='$err'"
fi

# ============ (rm) shared terminal-state guard on the stage-mutators (#154) ====
# The six subcommands that previously had NO terminal check now route through
# require_mutable: each rejects a post-terminal mutation with rc=1 (status
# preserved) and accepts it under --force. Mirrors the (q1)/(mc2) templates.
# rc is asserted == 1 (the guard's exact exit), distinguishing it from arg-shape
# errors (rc=3).

# Flip the fixture to a terminal status without a statectl primitive (same trick
# as (q1) line ~236) — exercises the guard against a real completed run.
mk_completed() {
  jq '.status = "completed"' .claude/pipeline-state/9999.json > .claude/pipeline-state/9999.json.tmp \
    && mv .claude/pipeline-state/9999.json.tmp .claude/pipeline-state/9999.json
}

# (rm1) worktree-set
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc worktree-set 9999 --path .claude/worktrees/acme-9999 --branch claude/acme-9999)
err=$(sct_err worktree-set 9999 --path .claude/worktrees/acme-9999 --branch claude/acme-9999)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$err" == *"terminal"* && "$status_after" == "completed" ]]; then
  pass "(rm1) worktree-set on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm1) worktree-set terminal guard — rc=$rc err='$err' status='$status_after'"
fi
rc_force=$(sct_rc worktree-set 9999 --path .claude/worktrees/acme-9999 --branch claude/acme-9999 --force)
branch_set=$(sct get 9999 '.branch')
if [[ "$rc_force" == "0" && "$branch_set" == "claude/acme-9999" ]]; then
  pass "(rm1f) worktree-set --force on terminal → applied (branch written)"
else
  fail "(rm1f) worktree-set --force — rc=$rc_force branch='$branch_set'"
fi

# (rm2) pr-add
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc pr-add 9999 --branch b --url https://example.com/pr/1)
err=$(sct_err pr-add 9999 --branch b --url https://example.com/pr/1)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$err" == *"terminal"* && "$status_after" == "completed" ]]; then
  pass "(rm2) pr-add on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm2) pr-add terminal guard — rc=$rc err='$err' status='$status_after'"
fi
rc_force=$(sct_rc pr-add 9999 --branch b --url https://example.com/pr/1 --force)
url_set=$(sct get 9999 '.prs.b.url')
if [[ "$rc_force" == "0" && "$url_set" == "https://example.com/pr/1" ]]; then
  pass "(rm2f) pr-add --force on terminal → applied (url written)"
else
  fail "(rm2f) pr-add --force — rc=$rc_force url='$url_set'"
fi

# (rm3) review-rounds — the exact subcommand the #151 retro caught firing post-terminal
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc review-rounds 9999 --set 2)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$status_after" == "completed" ]]; then
  pass "(rm3) review-rounds on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm3) review-rounds terminal guard — rc=$rc status='$status_after'"
fi
rc_force=$(sct_rc review-rounds 9999 --set 2 --force)
rounds_set=$(sct get 9999 '.codeReviewRounds')
if [[ "$rc_force" == "0" && "$rounds_set" == "2" ]]; then
  pass "(rm3f) review-rounds --force on terminal → applied (count written)"
else
  fail "(rm3f) review-rounds --force — rc=$rc_force rounds='$rounds_set'"
fi

# (rm4) verify-attempts
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc verify-attempts 9999 --incr FORMAT)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$status_after" == "completed" ]]; then
  pass "(rm4) verify-attempts on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm4) verify-attempts terminal guard — rc=$rc status='$status_after'"
fi
out_force=$(sct verify-attempts 9999 --incr FORMAT --force)
rc_force=$?
if [[ "$rc_force" == "0" && "$out_force" == "1" ]]; then
  pass "(rm4f) verify-attempts --force on terminal → applied (count=1 echoed)"
else
  fail "(rm4f) verify-attempts --force — rc=$rc_force out='$out_force'"
fi

# (rm5) slice-set
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc slice-set 9999 --current 1 --branch claude/acme-9999 --worktree-base main --pr-base main)
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$status_after" == "completed" ]]; then
  pass "(rm5) slice-set on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm5) slice-set terminal guard — rc=$rc status='$status_after'"
fi
rc_force=$(sct_rc slice-set 9999 --current 1 --branch claude/acme-9999 --worktree-base main --pr-base main --force)
slice_set=$(sct get 9999 '.currentSlice')
if [[ "$rc_force" == "0" && "$slice_set" == "1" ]]; then
  pass "(rm5f) slice-set --force on terminal → applied (currentSlice written)"
else
  fail "(rm5f) slice-set --force — rc=$rc_force currentSlice='$slice_set'"
fi

# (rm6) checkpoint
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc checkpoint 9999 5 --json '{"x":1}')
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$status_after" == "completed" ]]; then
  pass "(rm6) checkpoint on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm6) checkpoint terminal guard — rc=$rc status='$status_after'"
fi
rc_force=$(sct_rc checkpoint 9999 5 --json '{"x":1}' --force)
ckpt_set=$(sct get 9999 '.stageCheckpoint["5"].x')
if [[ "$rc_force" == "0" && "$ckpt_set" == "1" ]]; then
  pass "(rm6f) checkpoint --force on terminal → applied (payload written)"
else
  fail "(rm6f) checkpoint --force — rc=$rc_force ckpt='$ckpt_set'"
fi

# (rm7) pipeline-session-add is EXEMPT (#154 D3): a post-terminal cost backfill is
# legitimate (cost-tracking-setup.md). It must mutate a completed run WITHOUT --force.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mk_completed
rc=$(sct_rc pipeline-session-add 9999 --session-id aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee --source interactive)
sid_set=$(sct get 9999 '.pipelineSessions[0].sessionId')
if [[ "$rc" == "0" && "$sid_set" == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" ]]; then
  pass "(rm7) pipeline-session-add on terminal → applied WITHOUT --force (exempt)"
else
  fail "(rm7) pipeline-session-add exemption — rc=$rc sessionId='$sid_set'"
fi

# (rm8) deviations-add — a stage-mutator (Stage-8 review-fix write), so it is
# guarded like the other six: rejected post-terminal without --force, applied
# with. The Stage-7 checkpoint is written while in_progress so the has7 guard
# (which runs AFTER require_mutable) does not mask the terminal rejection.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct checkpoint 9999 7 --json "$VALID_PAYLOAD" >/dev/null
mk_completed
rc=$(sct_rc deviations-add 9999 --kind scope-creep --note "post-terminal")
status_after=$(jq -r '.status' .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$status_after" == "completed" ]]; then
  pass "(rm8) deviations-add on terminal → rejected (rc=1, status preserved)"
else
  fail "(rm8) deviations-add terminal guard — rc=$rc status='$status_after'"
fi
rc_force=$(sct_rc deviations-add 9999 --kind scope-creep --note "post-terminal" --force)
len_set=$(sct get 9999 '.stageCheckpoint."7".deviations | length')
if [[ "$rc_force" == "0" && "$len_set" == "1" ]]; then
  pass "(rm8f) deviations-add --force on terminal → applied (deviation appended)"
else
  fail "(rm8f) deviations-add --force — rc=$rc_force len='$len_set'"
fi

# (sd1) state-dir resolution is cwd-independent under STATECTL_STATE_DIR:
# invoking from an unrelated subdirectory still targets the fixture state dir.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
mkdir -p "$TMPDIR_ST/elsewhere"
status=$(cd "$TMPDIR_ST/elsewhere" && sct get 9999 '.status')
if [[ "$status" == "in_progress" ]]; then
  pass "(sd1) state dir cwd-independent (subdir invocation finds fixture state)"
else
  fail "(sd1) state dir cwd-independence — status='$status'"
fi

# (sd2) without STATECTL_STATE_DIR, the dir derives from the consumer root
# (SECOND_SHIFT_REPO_ROOT override, else $PWD's git-common-dir), NOT from cwd
# ad-hoc: the error path for a nonexistent issue names an absolute path under
# that root, never the cwd-relative legacy form. Post-pluginization the anchor
# is the CONSUMER repo (the script lives in the plugin checkout), so this pins
# the override rather than relying on the script's own git checkout.
err=$(STATECTL_STATE_DIR="" SECOND_SHIFT_REPO_ROOT="$TMPDIR_ST/consumer" "$STATECTL" get 999999 '.status' 2>&1 >/dev/null)
if [[ "$err" == *"$TMPDIR_ST/consumer/.claude/pipeline-state/999999.json"* ]]; then
  pass "(sd2) unset STATECTL_STATE_DIR → consumer-root (SECOND_SHIFT_REPO_ROOT) absolute state dir"
else
  fail "(sd2) state-dir derivation — err='$err'"
fi

# (mk1) valid_stage_marker: documented markers accepted, retired + junk rejected.
# The validator is not CLI-reachable (statectl posts no comments), so source the
# generated region out of the committed file and probe the function directly.
marker_region=$(sed -n '/^# >>> generated: valid_stage_marker >>>$/,/^# <<< generated: valid_stage_marker <<<$/p' "$STATECTL")
eval "$marker_region"
mk_ok=1
for m in claimed intake plan plan-review verify doc-update code-review pr; do
  valid_stage_marker "$m" || { echo "    (mk1) documented marker '$m' REJECTED"; mk_ok=0; }
done
for m in implementation bogus ""; do
  valid_stage_marker "$m" && { echo "    (mk1) invalid marker '$m' ACCEPTED"; mk_ok=0; }
done
if [[ $mk_ok -eq 1 ]]; then
  pass "(mk1) valid_stage_marker — 8 documented markers accepted; 'implementation'/junk rejected"
else
  fail "(mk1) valid_stage_marker — see above"
fi

# (mk2) marker-emission parity: every `stage: X` token the stage files + SKILL.md
# emit must be in the closed enum. This is the real drift guard for the marker
# vocabulary — a stage file growing an undocumented marker fails here.
emitted=$(grep -ohE 'stage: [a-z][a-z-]*' \
  "${SKILL_DIR}/stages/"*.md \
  "${SKILL_DIR}/SKILL.md" \
  | sed 's/^stage: //' | sort -u)
mk2_ok=1
mk2_count=0
while IFS= read -r m; do
  [[ -n "$m" ]] || continue
  mk2_count=$((mk2_count+1))
  valid_stage_marker "$m" || { echo "    (mk2) emitted marker '$m' not in the closed enum (state-schema.md Stage-comment markers)"; mk2_ok=0; }
done <<< "$emitted"
if [[ $mk2_ok -eq 1 && $mk2_count -ge 8 ]]; then
  pass "(mk2) marker-emission parity — $mk2_count distinct emitted markers, all documented"
else
  fail "(mk2) marker-emission parity — ok=$mk2_ok distinct=$mk2_count (expected >= 8, all valid)"
fi

# deviations-add cases. INTENTIONAL STATE CHAIN: da1 inits + writes
# stageCheckpoint["7"] + appends one deviation; da2 (rejected before any write)
# and da3 (asserts length==2 after a second append) run against da1's
# accumulated state on purpose — do NOT insert a reset_state between da1 and da3
# or da3's append-not-overwrite assertion loses its meaning. da4 also inherits
# the state but its arg-shape check fires before any state read, so it is
# independent in effect. da5 onward reset_state and stand alone.
#
# (da1) deviations-add happy path → appended to stageCheckpoint["7"].deviations
# with introducedAtStage=8 and the optional --file field; requires a Stage-7
# checkpoint to exist first (single-ledger append model).
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct checkpoint 9999 7 --json "$VALID_PAYLOAD" >/dev/null
sct deviations-add 9999 --kind scope-creep --note "added a helper script not in the plan" --file tools/x.sh >/dev/null
len=$(sct get 9999 '.stageCheckpoint."7".deviations | length')
kind=$(sct get 9999 '.stageCheckpoint."7".deviations[0].kind')
stage=$(sct get 9999 '.stageCheckpoint."7".deviations[0].introducedAtStage')
file=$(sct get 9999 '.stageCheckpoint."7".deviations[0].file')
if [[ "$len" == "1" && "$kind" == "scope-creep" && "$stage" == "8" && "$file" == "tools/x.sh" ]]; then
  pass "(da1) deviations-add happy path → appended with introducedAtStage=8"
else
  fail "(da1) deviations-add happy path — len='$len' kind='$kind' stage='$stage' file='$file'"
fi

# (da2) deviations-add invalid --kind → rejected (rc=1, value-validation class).
err=$(sct_err deviations-add 9999 --kind bogus --note x)
rc=$(sct_rc deviations-add 9999 --kind bogus --note x)
if [[ "$rc" == "1" && "$err" == *"[statectl-error]"* && "$err" == *"invalid --kind"* ]]; then
  pass "(da2) deviations-add invalid --kind → rejected (rc=1)"
else
  fail "(da2) deviations-add invalid kind — rc=$rc err='$err'"
fi

# (da3) deviations-add second call → APPENDS (array length 2, order preserved) —
# proves it is additive, never an overwrite.
sct deviations-add 9999 --kind deferred --note "second deviation" >/dev/null
len=$(sct get 9999 '.stageCheckpoint."7".deviations | length')
k0=$(sct get 9999 '.stageCheckpoint."7".deviations[0].kind')
k1=$(sct get 9999 '.stageCheckpoint."7".deviations[1].kind')
if [[ "$len" == "2" && "$k0" == "scope-creep" && "$k1" == "deferred" ]]; then
  pass "(da3) deviations-add second call → appends (length 2, order preserved)"
else
  fail "(da3) deviations-add append — len='$len' k0='$k0' k1='$k1'"
fi

# (da4) deviations-add missing --note → rejected (rc=3, arg-shape class).
err=$(sct_err deviations-add 9999 --kind surprise)
rc=$(sct_rc deviations-add 9999 --kind surprise)
if [[ "$rc" == "3" && "$err" == *"missing"* ]]; then
  pass "(da4) deviations-add missing --note → rejected (rc=3)"
else
  fail "(da4) deviations-add missing --note — rc=$rc err='$err'"
fi

# (da5) deviations-add with no Stage-7 checkpoint → rejected (rc=1) — the append
# target must already exist; the subcommand never conjures a checkpoint.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
err=$(sct_err deviations-add 9999 --kind scope-creep --note "no checkpoint yet")
rc=$(sct_rc deviations-add 9999 --kind scope-creep --note "no checkpoint yet")
if [[ "$rc" == "1" && "$err" == *"stageCheckpoint"* && "$err" == *"absent"* ]]; then
  pass "(da5) deviations-add without Stage-7 checkpoint → rejected (rc=1)"
else
  fail "(da5) deviations-add no-checkpoint — rc=$rc err='$err'"
fi

# (da6) deviations-add invalid --stage (out of {1..9}) → rejected (rc=1).
err=$(sct_err deviations-add 9999 --kind scope-creep --note x --stage 10)
rc=$(sct_rc deviations-add 9999 --kind scope-creep --note x --stage 10)
if [[ "$rc" == "1" && "$err" == *"[statectl-error]"* && "$err" == *"--stage"* ]]; then
  pass "(da6) deviations-add invalid --stage → rejected (rc=1)"
else
  fail "(da6) deviations-add invalid --stage — rc=$rc err='$err'"
fi

# (da7) deviations-add non-numeric --line → rejected (rc=1).
err=$(sct_err deviations-add 9999 --kind scope-creep --note x --line abc)
rc=$(sct_rc deviations-add 9999 --kind scope-creep --note x --line abc)
if [[ "$rc" == "1" && "$err" == *"[statectl-error]"* && "$err" == *"--line"* ]]; then
  pass "(da7) deviations-add non-numeric --line → rejected (rc=1)"
else
  fail "(da7) deviations-add non-numeric --line — rc=$rc err='$err'"
fi

# ============================================ unit-test mutation subcommands ===

echo
echo "[self-test] unit-test mutation subcommands — 9 cases"

# (ut1) unit-test-surface-set happy path → .unitTestSurface written verbatim.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 3 --status started >/dev/null
sct unit-test-surface-set 9999 --json '{"applicable":true,"action":"strengthen","mutationTargets":["userId filter"]}' >/dev/null
content=$(cat .claude/pipeline-state/9999.json)
if [[ "$(jq -r '.unitTestSurface.action' <<< "$content")" == "strengthen" \
   && "$(jq -r '.unitTestSurface.applicable' <<< "$content")" == "true" ]]; then
  pass "(ut1) unit-test-surface-set → .unitTestSurface persisted"
else
  fail "(ut1) unit-test-surface-set — content='$content'"
fi

# (ut2) unit-test-surface-set with invalid JSON → rejected, surface untouched.
err=$(sct_err unit-test-surface-set 9999 --json 'not json')
if [[ "$err" == *"not valid JSON"* ]] \
   && [[ "$(jq -r '.unitTestSurface.action' < .claude/pipeline-state/9999.json)" == "strengthen" ]]; then
  pass "(ut2) unit-test-surface-set invalid JSON → rejected (prior value preserved)"
else
  fail "(ut2) unit-test-surface-set invalid JSON — err='$err'"
fi

# (ut3) stage-substatus happy path → stages.5.unitTestMutationReview set.
sct set-stage 9999 5 --status started >/dev/null
sct stage-substatus 9999 --stage 5 --key unitTestMutationReview --value executing >/dev/null
val=$(jq -r '.stages."5".unitTestMutationReview' < .claude/pipeline-state/9999.json)
if [[ "$val" == "executing" ]]; then
  pass "(ut3) stage-substatus → stages.5.unitTestMutationReview=executing"
else
  fail "(ut3) stage-substatus — got '$val'"
fi

# (ut4) stage-substatus invalid value → rejected (rc=1), prior value preserved.
rc=$(sct_rc stage-substatus 9999 --stage 5 --key unitTestMutationReview --value bogus)
val=$(jq -r '.stages."5".unitTestMutationReview' < .claude/pipeline-state/9999.json)
if [[ "$rc" == "1" && "$val" == "executing" ]]; then
  pass "(ut4) stage-substatus invalid value → rejected (rc=1, prior preserved)"
else
  fail "(ut4) stage-substatus invalid value — rc=$rc val='$val'"
fi

# (ut5) stage-substatus unsupported (stage,key) pair → rejected (rc=1).
rc=$(sct_rc stage-substatus 9999 --stage 5 --key bogusKey --value executing)
if [[ "$rc" == "1" ]]; then
  pass "(ut5) stage-substatus unsupported (stage,key) → rejected (rc=1)"
else
  fail "(ut5) stage-substatus unsupported pair — rc=$rc"
fi

# (ut6) mutation-audit-set happy path → .mutationReviewAudit written.
sct mutation-audit-set 9999 --json '{"mutationScore":{"killed":2,"survived":0},"finalDisposition":"pass"}' >/dev/null
killed=$(jq -r '.mutationReviewAudit.mutationScore.killed' < .claude/pipeline-state/9999.json)
if [[ "$killed" == "2" ]]; then
  pass "(ut6) mutation-audit-set → .mutationReviewAudit persisted"
else
  fail "(ut6) mutation-audit-set — killed='$killed'"
fi

# (ut7) the three new failure reasons are accepted by mark-failed (valid_failure_reason).
reset_state
sct init 9998 --run-id "selftest-run-$$" >/dev/null
rc=$(sct_rc mark-failed 9998 --reason unit-test-mutation-reviewer-block --stage 5)
if [[ "$rc" == "0" && "$(jq -r '.failureContext.reason' < .claude/pipeline-state/9998.json)" == "unit-test-mutation-reviewer-block" ]]; then
  pass "(ut7) mark-failed accepts unit-test-mutation-reviewer-block"
else
  fail "(ut7) mark-failed unit-test-mutation-reviewer-block — rc=$rc"
fi

# (ut8) the other two new reasons are also in the enum.
reset_state; sct init 9997 --run-id "r$$" >/dev/null
rc1=$(sct_rc mark-failed 9997 --reason unit-test-surface-ambiguous --stage 3)
reset_state; sct init 9996 --run-id "r$$" >/dev/null
rc2=$(sct_rc mark-failed 9996 --reason unit-test-plan-reviewer-block --stage 4)
if [[ "$rc1" == "0" && "$rc2" == "0" ]]; then
  pass "(ut8) mark-failed accepts unit-test-surface-ambiguous + unit-test-plan-reviewer-block"
else
  fail "(ut8) mark-failed new reasons — rc1=$rc1 rc2=$rc2"
fi

# (ut9) terminal-state guard — stage-substatus on a failed run rejected without --force.
reset_state
sct init 9995 --run-id "r$$" >/dev/null
sct set-stage 9995 5 --status started >/dev/null
sct mark-failed 9995 --reason unit-test-mutation-reviewer-block --stage 5 >/dev/null
rc=$(sct_rc stage-substatus 9995 --stage 5 --key unitTestMutationReview --value completed)
rcf=$(sct_rc stage-substatus 9995 --stage 5 --key unitTestMutationReview --value completed --force)
if [[ "$rc" == "1" && "$rcf" == "0" ]]; then
  pass "(ut9) stage-substatus terminal guard (reject w/o --force, apply with --force)"
else
  fail "(ut9) stage-substatus terminal guard — rc=$rc rcf=$rcf"
fi

# ---- Design Mode (#199): designPlanReview sub-status + design-source-unreachable reason ----

# (df1) stage-substatus happy path → stages.5.designPlanReview accepts each value.
reset_state
sct init 9994 --run-id "r$$" >/dev/null
sct set-stage 9994 5 --status started >/dev/null
sct stage-substatus 9994 --stage 5 --key designPlanReview --value implementing >/dev/null
sct stage-substatus 9994 --stage 5 --key designPlanReview --value verifying >/dev/null
sct stage-substatus 9994 --stage 5 --key designPlanReview --value implemented >/dev/null
val=$(jq -r '.stages."5".designPlanReview' < .claude/pipeline-state/9994.json)
if [[ "$val" == "implemented" ]]; then
  pass "(df1) stage-substatus → stages.5.designPlanReview accepts implementing|verifying|implemented (terminal=implemented)"
else
  fail "(df1) stage-substatus designPlanReview — got '$val'"
fi

# (df2) designPlanReview invalid value → rejected (rc=1), prior value preserved.
rc=$(sct_rc stage-substatus 9994 --stage 5 --key designPlanReview --value bogus)
val=$(jq -r '.stages."5".designPlanReview' < .claude/pipeline-state/9994.json)
if [[ "$rc" == "1" && "$val" == "implemented" ]]; then
  pass "(df2) stage-substatus designPlanReview invalid value → rejected (rc=1, prior preserved)"
else
  fail "(df2) stage-substatus designPlanReview invalid value — rc=$rc val='$val'"
fi

# (df3) mark-failed accepts design-source-unreachable (Stage 1 hard stop), reason+stage recorded.
reset_state
sct init 9993 --run-id "r$$" >/dev/null
rc=$(sct_rc mark-failed 9993 --reason design-source-unreachable --stage 1)
reason=$(jq -r '.failureContext.reason' < .claude/pipeline-state/9993.json)
stage=$(jq -r '.failureContext.stage' < .claude/pipeline-state/9993.json)
if [[ "$rc" == "0" && "$reason" == "design-source-unreachable" && "$stage" == "1" ]]; then
  pass "(df3) mark-failed accepts design-source-unreachable (Stage 1) → reason+stage recorded"
else
  fail "(df3) mark-failed design-source-unreachable — rc=$rc reason='$reason' stage='$stage'"
fi

# (df4) terminal-state guard — designPlanReview on a failed run rejected without --force, applied with.
reset_state
sct init 9992 --run-id "r$$" >/dev/null
sct set-stage 9992 5 --status started >/dev/null
sct mark-failed 9992 --reason design-source-unreachable --stage 1 >/dev/null
rc=$(sct_rc stage-substatus 9992 --stage 5 --key designPlanReview --value implemented)
rcf=$(sct_rc stage-substatus 9992 --stage 5 --key designPlanReview --value implemented --force)
if [[ "$rc" == "1" && "$rcf" == "0" ]]; then
  pass "(df4) stage-substatus designPlanReview terminal guard (reject w/o --force, apply with --force)"
else
  fail "(df4) stage-substatus designPlanReview terminal guard — rc=$rc rcf=$rcf"
fi

# ==================================== stage machine: completion preconditions ===

echo
echo "[self-test] stage machine — completion preconditions + terminal gates"

# (sc1) stage 1 completed without stageCheckpoint["1"] → refused; with → allowed
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
err=$(sct_err set-stage 9999 1 --status completed)
rc=$(sct_rc set-stage 9999 1 --status completed)
sct checkpoint 9999 1 --json '{"verdict":"no-split"}' >/dev/null
rc2=$(sct_rc set-stage 9999 1 --status completed)
if [[ "$rc" == "1" && "$err" == *'stageCheckpoint["1"] is missing'* && "$rc2" == "0" ]]; then
  pass "(sc1) stage-1 completion precondition — refused without checkpoint, allowed with"
else
  fail "(sc1) stage-1 precondition — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc2) stage 2 completed without worktree-set → refused; with → allowed
sct set-stage 9999 2 --status started >/dev/null
rc=$(sct_rc set-stage 9999 2 --status completed)
err=$(sct_err set-stage 9999 2 --status completed)
sct worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999" >/dev/null
rc2=$(sct_rc set-stage 9999 2 --status completed)
if [[ "$rc" == "1" && "$err" == *"worktreePath/branch missing"* && "$rc2" == "0" ]]; then
  pass "(sc2) stage-2 completion precondition — refused without worktree-set, allowed with"
else
  fail "(sc2) stage-2 precondition — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc3) stage 4 completed without stages.4.planReview.overall → refused; with → allowed
complete_stage 9999 3
sct set-stage 9999 4 --status started >/dev/null
rc=$(sct_rc set-stage 9999 4 --status completed)
err=$(sct_err set-stage 9999 4 --status completed)
sct plan-review-set 9999 --overall fix-and-go >/dev/null
rc2=$(sct_rc set-stage 9999 4 --status completed)
if [[ "$rc" == "1" && "$err" == *"planReview.overall is not recorded"* && "$rc2" == "0" ]]; then
  pass "(sc3) stage-4 completion precondition — refused without plan-review-set, allowed with"
else
  fail "(sc3) stage-4 precondition — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc4) stage 5: checkpoint leg + unit-test sub-status leg + designDriven leg
sct set-stage 9999 5 --status started >/dev/null
rc_nockpt=$(sct_rc set-stage 9999 5 --status completed)
sct checkpoint 9999 5 --json '{"changedFiles":[]}' >/dev/null
rc_plain=$(sct_rc set-stage 9999 5 --status completed)   # no unitTestSurface, no designDriven → allowed
if [[ "$rc_nockpt" == "1" && "$rc_plain" == "0" ]]; then
  pass "(sc4a) stage-5 checkpoint leg — refused without stageCheckpoint[\"5\"], allowed with (no conditional surfaces)"
else
  fail "(sc4a) stage-5 checkpoint leg — rc_nockpt=$rc_nockpt rc_plain=$rc_plain"
fi

# (sc4b) unit-test-applicable run: sub-status must be terminal "completed"
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
for n in 1 2 3 4; do complete_stage 9999 "$n"; done
sct unit-test-surface-set 9999 --json '{"applicable":true,"action":"strengthen"}' >/dev/null
sct set-stage 9999 5 --status started >/dev/null
sct checkpoint 9999 5 --json '{"changedFiles":[]}' >/dev/null
sct stage-substatus 9999 --stage 5 --key unitTestMutationReview --value reviewing >/dev/null
rc=$(sct_rc set-stage 9999 5 --status completed)
err=$(sct_err set-stage 9999 5 --status completed)
sct stage-substatus 9999 --stage 5 --key unitTestMutationReview --value completed >/dev/null
rc2=$(sct_rc set-stage 9999 5 --status completed)
if [[ "$rc" == "1" && "$err" == *"unitTestMutationReview not at terminal"* && "$rc2" == "0" ]]; then
  pass "(sc4b) stage-5 unit-test leg — non-terminal sub-status refused, terminal allowed"
else
  fail "(sc4b) stage-5 unit-test leg — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc4c) designDriven run: designPlanReview must be terminal "implemented"
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
sct checkpoint 9999 1 --json '{"verdict":"no-split","designDriven":true}' >/dev/null
sct set-stage 9999 1 --status completed >/dev/null
for n in 2 3 4; do complete_stage 9999 "$n"; done
sct set-stage 9999 5 --status started >/dev/null
sct checkpoint 9999 5 --json '{"changedFiles":[]}' >/dev/null
sct stage-substatus 9999 --stage 5 --key designPlanReview --value verifying >/dev/null
rc=$(sct_rc set-stage 9999 5 --status completed)
err=$(sct_err set-stage 9999 5 --status completed)
sct stage-substatus 9999 --stage 5 --key designPlanReview --value implemented >/dev/null
rc2=$(sct_rc set-stage 9999 5 --status completed)
if [[ "$rc" == "1" && "$err" == *"designPlanReview not at terminal"* && "$rc2" == "0" ]]; then
  pass "(sc4c) stage-5 design leg — non-terminal designPlanReview refused, implemented allowed"
else
  fail "(sc4c) stage-5 design leg — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc5) stage 6 completed without top-level verifySummary → refused; string OK too
complete_stage 9999 5
sct set-stage 9999 6 --status started >/dev/null
rc=$(sct_rc set-stage 9999 6 --status completed)
err=$(sct_err set-stage 9999 6 --status completed)
sct verify-summary-set 9999 --json '"skipped (inert diff — no JS/TS surface)"' >/dev/null
rc2=$(sct_rc set-stage 9999 6 --status completed)
if [[ "$rc" == "1" && "$err" == *"verifySummary is missing"* && "$rc2" == "0" ]]; then
  pass "(sc5) stage-6 completion precondition — refused without verify-summary-set, INERT string allowed"
else
  fail "(sc5) stage-6 precondition — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc6) stage 8 completed without codeReviewRounds → refused; with → allowed
complete_stage 9999 7
sct set-stage 9999 8 --status started >/dev/null
rc=$(sct_rc set-stage 9999 8 --status completed)
err=$(sct_err set-stage 9999 8 --status completed)
sct review-rounds 9999 --set 1 >/dev/null
rc2=$(sct_rc set-stage 9999 8 --status completed)
if [[ "$rc" == "1" && "$err" == *"no codeReviewRounds recorded"* && "$rc2" == "0" ]]; then
  pass "(sc6) stage-8 completion precondition — refused without review-rounds, allowed with"
else
  fail "(sc6) stage-8 precondition — rc=$rc rc2=$rc2 err='$err'"
fi

# (sc7) --force bypasses a completion precondition (crash-recovery escape)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
rc=$(sct_rc set-stage 9999 1 --status completed --force)
if [[ "$rc" == "0" ]]; then
  pass "(sc7) --force bypasses completion precondition"
else
  fail "(sc7) --force bypass — rc=$rc"
fi

# (mcg1) mark-completed with an incomplete stage → refused, names the gaps
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
for n in 1 2 3 4 5 6 7 8; do complete_stage 9999 "$n"; done   # stage 9 missing
write_eval 9999
err=$(sct_err mark-completed 9999)
rc=$(sct_rc mark-completed 9999)
if [[ "$rc" == "1" && "$err" == *"stages [9] are not completed"* ]]; then
  pass "(mcg1) mark-completed incomplete-stages gate — refused, gap named"
else
  fail "(mcg1) all-stages gate — rc=$rc err='$err'"
fi

# (mcg2) mark-completed with no eval file → refused (fail-closed)
complete_stage 9999 9
rm -f .claude/pipeline-state/9999-eval.json
err=$(sct_err mark-completed 9999)
rc=$(sct_rc mark-completed 9999)
if [[ "$rc" == "1" && "$err" == *"self-eval"*"is missing"* ]]; then
  pass "(mcg2) mark-completed eval gate — refused without self-eval"
else
  fail "(mcg2) eval gate — rc=$rc err='$err'"
fi

# (mcg3) implausible eval (empty criteria / wrong issue) → refused
echo '{}' > .claude/pipeline-state/9999-eval.json
rc_empty=$(sct_rc mark-completed 9999)
printf '{"ticketKey":1234,"criteria":{"x":"PASS"}}\n' > .claude/pipeline-state/9999-eval.json
rc_wrong=$(sct_rc mark-completed 9999)
write_eval 9999
rc_ok=$(sct_rc mark-completed 9999)
if [[ "$rc_empty" == "1" && "$rc_wrong" == "1" && "$rc_ok" == "0" ]]; then
  pass "(mcg3) mark-completed eval plausibility — empty/wrong-issue refused, valid allowed"
else
  fail "(mcg3) eval plausibility — rc_empty=$rc_empty rc_wrong=$rc_wrong rc_ok=$rc_ok"
fi

# (mcg4) --force does NOT bypass the all-stages / eval gates
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
complete_stage 9999 1
rc=$(sct_rc mark-completed 9999 --force)
if [[ "$rc" == "1" ]]; then
  pass "(mcg4) mark-completed --force does NOT bypass the completeness gate"
else
  fail "(mcg4) --force no-bypass — rc=$rc"
fi

# (iq1) init stale-eval quarantine: leftover {issue}-eval.json renamed, not readable by the gate
reset_state
write_eval 9999
out=$(sct init 9999 --run-id "selftest-run-$$")
stale_count=$(find .claude/pipeline-state -maxdepth 1 -name '9999-eval-stale-*.json' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$out" == "state=created" && ! -f .claude/pipeline-state/9999-eval.json && "$stale_count" == "1" ]]; then
  pass "(iq1) init quarantines a stale self-eval (renamed, original gone)"
else
  fail "(iq1) init stale-eval quarantine — out='$out' stale_count=$stale_count"
fi
rm -f .claude/pipeline-state/9999-eval-stale-*.json

# (prs1) plan-review-set: valid values accepted, block/other rejected
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
rc_pass=$(sct_rc plan-review-set 9999 --overall pass)
got=$(sct get 9999 '.stages."4".planReview.overall')
rc_block=$(sct_rc plan-review-set 9999 --overall block)
rc_bogus=$(sct_rc plan-review-set 9999 --overall bogus)
if [[ "$rc_pass" == "0" && "$got" == "pass" && "$rc_block" == "1" && "$rc_bogus" == "1" ]]; then
  pass "(prs1) plan-review-set — pass/fix-and-go accepted, block/bogus rejected"
else
  fail "(prs1) plan-review-set — rc_pass=$rc_pass got=$got rc_block=$rc_block rc_bogus=$rc_bogus"
fi

# (vss1) verify-summary-set: object + non-empty string accepted; empty string / bad JSON rejected
rc_obj=$(sct_rc verify-summary-set 9999 --json '{"format":"clean","test":"passed"}')
rc_str=$(sct_rc verify-summary-set 9999 --json '"skipped (inert diff — no JS/TS surface)"')
rc_empty=$(sct_rc verify-summary-set 9999 --json '""')
rc_bad=$(sct_rc verify-summary-set 9999 --json 'not-json')
got_type=$(sct get 9999 '.verifySummary | type')
if [[ "$rc_obj" == "0" && "$rc_str" == "0" && "$rc_empty" == "1" && "$rc_bad" != "0" && "$got_type" == "string" ]]; then
  pass "(vss1) verify-summary-set — object/string accepted, empty/bad-JSON rejected"
else
  fail "(vss1) verify-summary-set — rc_obj=$rc_obj rc_str=$rc_str rc_empty=$rc_empty rc_bad=$rc_bad type=$got_type"
fi

# (va4) verify-attempts accepts PLAN_CMD_FAILURE (the in-session class); still rejects bogus
rc_plan=$(sct_rc verify-attempts 9999 --incr PLAN_CMD_FAILURE)
count=$(sct get 9999 '.verifyAttempts.PLAN_CMD_FAILURE')
rc_bogus=$(sct_rc verify-attempts 9999 --incr NOT_A_CLASS)
if [[ "$rc_plan" == "0" && "$count" == "1" && "$rc_bogus" == "1" ]]; then
  pass "(va4) verify-attempts — PLAN_CMD_FAILURE accepted, bogus class rejected"
else
  fail "(va4) verify-attempts PLAN_CMD_FAILURE — rc_plan=$rc_plan count=$count rc_bogus=$rc_bogus"
fi

# (qp1) quality-pass-set: valid running/completed accepted; missing runId / bad status rejected;
#       terminal-state guarded
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
rc_run=$(sct_rc quality-pass-set 9999 --json '{"runId":"r1","status":"running"}')
rc_done=$(sct_rc quality-pass-set 9999 --json '{"runId":"r1","status":"completed","outcome":"no-candidates"}')
got=$(sct get 9999 '.stages."6".qualityPass.outcome')
rc_norun=$(sct_rc quality-pass-set 9999 --json '{"status":"running"}')
rc_badst=$(sct_rc quality-pass-set 9999 --json '{"runId":"r1","status":"partying"}')
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
rc_term=$(sct_rc quality-pass-set 9999 --json '{"runId":"r1","status":"completed"}')
if [[ "$rc_run" == "0" && "$rc_done" == "0" && "$got" == "no-candidates" \
      && "$rc_norun" == "1" && "$rc_badst" == "1" && "$rc_term" == "1" ]]; then
  pass "(qp1) quality-pass-set — valid writes accepted, missing-runId/bad-status/terminal rejected"
else
  fail "(qp1) quality-pass-set — rc_run=$rc_run rc_done=$rc_done got=$got rc_norun=$rc_norun rc_badst=$rc_badst rc_term=$rc_term"
fi

# (qp2) build-checkpoint-7 --quality-pass-summary passthrough (+ default {} and non-object reject)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
qps='{"runId":"r1","status":"completed","outcome":"applied","commitSha":"abc","applied":["x"],"suggestions":[]}'
built=$(sct build-checkpoint-7 --issue 9999 --branch b --head h --worktree /tmp/x --quality-pass-summary "$qps")
got_outcome=$(jq -r '.qualityPassSummary.outcome' <<< "$built")
built_default=$(sct build-checkpoint-7 --issue 9999 --branch b --head h --worktree /tmp/x)
got_default=$(jq -c '.qualityPassSummary' <<< "$built_default")
rc_bad=$(sct_rc build-checkpoint-7 --issue 9999 --branch b --head h --worktree /tmp/x --quality-pass-summary '"nope"')
if [[ "$got_outcome" == "applied" && "$got_default" == "{}" && "$rc_bad" == "1" ]]; then
  pass "(qp2) build-checkpoint-7 quality-pass-summary — passthrough, {} default, non-object rejected"
else
  fail "(qp2) checkpoint-7 qps — outcome=$got_outcome default=$got_default rc_bad=$rc_bad"
fi

# (mg) mutation-gate computeVerdict — extract the pure verdict block from the
# workflow script (between its >>> verdict >>> sentinels) and execute it under
# node against fixture execution arrays. Proves the verdict mapping (survivors
# win; zero-verified guard; entry-based budget skip; clean pass) without a
# Workflow runtime. Gated on node invocability (same posture as the doctor's 5b).
MG_MJS="${SKILL_DIR}/workflows/mutation-gate.mjs"
if node --version >/dev/null 2>&1 && [[ -f "$MG_MJS" ]]; then
  verdict_block=$(sed -n '/^\/\/ >>> verdict/,/^\/\/ <<< verdict/p' "$MG_MJS")
  if [[ -z "$verdict_block" ]]; then
    fail "(mg) computeVerdict — sentinel block not found in mutation-gate.mjs"
  else
    mg_out=$(node -e "
$verdict_block
const t = (label, executions, want) => {
  const got = computeVerdict(executions).overall
  console.log(got === want ? 'ok ' + label : 'BAD ' + label + ' got=' + got + ' want=' + want)
}
t('survivors-win', [{status:'killed'},{status:'survived'},{status:'infra'}], 'survived-blockers')
t('zero-verified-guard', [{status:'unparseable'},{status:'unapplied'}], 'infra')
t('infra-aborts', [{status:'killed'},{status:'infra'},{status:'skipped-after-infra'}], 'infra')
t('partial-budget', [{status:'killed'},{status:'skipped-budget'}], 'budget-skipped')
t('clean-pass', [{status:'killed'},{status:'killed'},{status:'unapplied'}], 'pass')
t('empty-pass', [], 'pass')
" 2>&1)
    if grep -q "BAD" <<< "$mg_out" || ! grep -q "ok clean-pass" <<< "$mg_out"; then
      fail "(mg) computeVerdict — $mg_out"
    else
      pass "(mg) mutation-gate computeVerdict — verdict mapping holds ($(grep -c '^ok ' <<< "$mg_out") fixtures)"
    fi
  fi
else
  echo "  SKIP: (mg) computeVerdict — node not invokable or mutation-gate.mjs absent"
fi

# ==================================== intake-brief + plan-structure-invalid (PR D) ===

echo
echo "[self-test] intake-brief — AC snapshot + brief pointer"

AC_OK='[{"id":"AC-1","text":"credited","negative":false,"source":"explicit"},{"id":"AC-2","text":"no credit","negative":true,"source":"derived"}]'

# (ib-a) valid write → briefPath + acceptanceCriteria persisted, echoes AC count
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
cnt=$(sct intake-brief 9999 --brief-path ".claude/pipeline-state/9999-brief.md" --acceptance-criteria "$AC_OK")
bp=$(sct get 9999 '.briefPath')
n=$(sct get 9999 '.acceptanceCriteria | length')
neg=$(sct get 9999 '.acceptanceCriteria[1].negative')
if [[ "$cnt" == "2" && "$bp" == ".claude/pipeline-state/9999-brief.md" && "$n" == "2" && "$neg" == "true" ]]; then
  pass "(ib-a) intake-brief valid write — briefPath + AC snapshot persisted, false negative preserved, count echoed"
else
  fail "(ib-a) intake-brief valid — cnt=$cnt bp=$bp n=$n neg=$neg"
fi

# (ib-b) null brief path → JSON null; empty AC array accepted
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
cnt=$(sct intake-brief 9999 --brief-path null --acceptance-criteria '[]')
bp_type=$(sct get 9999 '.briefPath | type')
if [[ "$cnt" == "0" && "$bp_type" == "null" ]]; then
  pass "(ib-b) intake-brief null brief + empty AC → briefPath JSON null, count 0"
else
  fail "(ib-b) intake-brief null — cnt=$cnt bp_type=$bp_type"
fi

# (ib-c) bad id pattern → rejected
rc=$(sct_rc intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"X1","text":"t","negative":false,"source":"explicit"}]')
err=$(sct_err intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"X1","text":"t","negative":false,"source":"explicit"}]')
if [[ "$rc" != "0" && "$err" == *"must match ^AC-"* ]]; then
  pass "(ib-c) intake-brief bad id pattern → rejected"
else
  fail "(ib-c) intake-brief bad id — rc=$rc err='$err'"
fi

# (ib-d) duplicate ids → rejected
rc=$(sct_rc intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"AC-1","text":"a","negative":false,"source":"explicit"},{"id":"AC-1","text":"b","negative":false,"source":"derived"}]')
err=$(sct_err intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"AC-1","text":"a","negative":false,"source":"explicit"},{"id":"AC-1","text":"b","negative":false,"source":"derived"}]')
if [[ "$rc" != "0" && "$err" == *"unique"* ]]; then
  pass "(ib-d) intake-brief duplicate ids → rejected"
else
  fail "(ib-d) intake-brief dup ids — rc=$rc err='$err'"
fi

# (ib-e) bad source enum + non-boolean negative → rejected
rc_src=$(sct_rc intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"AC-1","text":"t","negative":false,"source":"guessed"}]')
rc_neg=$(sct_rc intake-brief 9999 --brief-path null --acceptance-criteria '[{"id":"AC-1","text":"t","negative":"yes","source":"explicit"}]')
if [[ "$rc_src" != "0" && "$rc_neg" != "0" ]]; then
  pass "(ib-e) intake-brief bad source / non-boolean negative → rejected"
else
  fail "(ib-e) intake-brief enum guards — rc_src=$rc_src rc_neg=$rc_neg"
fi

# (ib-f) terminal-state guard: no intent snapshot after the run goes terminal
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
rc=$(sct_rc intake-brief 9999 --brief-path null --acceptance-criteria '[]')
if [[ "$rc" != "0" ]]; then
  pass "(ib-f) intake-brief on terminal state → rejected"
else
  fail "(ib-f) intake-brief terminal — rc=$rc"
fi

# (ib-g) plan-structure-invalid is a valid closed-enum reason (builder + mark-failed)
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
built=$(sct build-failure-context --reason plan-structure-invalid --stage 4 --kv-lines violations="missing section: Reuse inventory")
rc_build=$?
rc_mf=$(sct_rc mark-failed 9999 --reason plan-structure-invalid --stage 4 --json "$built")
got_reason=$(sct get 9999 '.failureContext.reason')
if [[ "$rc_build" == "0" && "$rc_mf" == "0" && "$got_reason" == "plan-structure-invalid" ]]; then
  pass "(ib-g) plan-structure-invalid accepted by builder + mark-failed"
else
  fail "(ib-g) plan-structure-invalid — rc_build=$rc_build rc_mf=$rc_mf reason=$got_reason"
fi

# ============================================ tracker keyPattern validation (both adapters) ===

echo
echo "[self-test] tracker keyPattern — one statectl, tracker-shaped init validation"

# Config lives OUTSIDE pipeline-state (reset_state only wipes pipeline-state/*.json).
# STATECTL_STATE_DIR stays pinned, so state files still land in the fixture dir;
# config_file() resolves SECOND_SHIFT_CONFIG independently for the keyPattern read.
KP_CFG="$TMPDIR_ST/kp-config.json"

# --- JIRA adapter: keyPattern "[A-Z]+-[0-9]+" ---
printf '{"configVersion":1,"tracker":{"type":"jira","keyPattern":"[A-Z]+-[0-9]+"},"topology":{"type":"standalone","repos":{"be":{"path":".","baseBranch":"main"}}},"commands":{"be":{}}}\n' > "$KP_CFG"
export SECOND_SHIFT_CONFIG="$KP_CFG"

reset_state
rc_jira_ok=$(sct_rc init GH-540 --run-id "selftest-run-$$")
jira_key_field=$(jq -r '.ticketKey // ""' .claude/pipeline-state/gh-540.json 2>/dev/null)
reset_state
rc_jira_bad=$(sct_rc init nope --run-id "selftest-run-$$")
reset_state
rc_jira_numeric=$(sct_rc init 9999 --run-id "selftest-run-$$")   # numeric is malformed for a JIRA pattern
if [[ "$rc_jira_ok" == "0" && "$jira_key_field" == "gh-540" \
   && "$rc_jira_bad" != "0" && "$rc_jira_numeric" != "0" ]]; then
  pass "(kp-a) jira keyPattern — GH-540 accepted (lowercased state), 'nope'/'9999' rejected"
else
  fail "(kp-a) jira keyPattern — ok=$rc_jira_ok key=$jira_key_field bad=$rc_jira_bad numeric=$rc_jira_numeric"
fi

# --- GitHub adapter: keyPattern "[0-9]+" ---
printf '{"configVersion":1,"tracker":{"type":"github","keyPattern":"[0-9]+"},"topology":{"type":"standalone","repos":{"be":{"path":".","baseBranch":"main"}}},"commands":{"be":{}}}\n' > "$KP_CFG"
reset_state
rc_gh_ok=$(sct_rc init 9999 --run-id "selftest-run-$$")
reset_state
rc_gh_bad=$(sct_rc init PROJ-1 --run-id "selftest-run-$$")
if [[ "$rc_gh_ok" == "0" && "$rc_gh_bad" != "0" ]]; then
  pass "(kp-b) github keyPattern — 9999 accepted, 'PROJ-1' rejected"
else
  fail "(kp-b) github keyPattern — ok=$rc_gh_ok bad=$rc_gh_bad"
fi

# --- No keyPattern → accept any non-empty key (backward-compatible) ---
printf '{"configVersion":1,"tracker":{"type":"github"},"topology":{"type":"standalone","repos":{"be":{"path":".","baseBranch":"main"}}},"commands":{"be":{}}}\n' > "$KP_CFG"
reset_state
rc_nopat_num=$(sct_rc init 9999 --run-id "selftest-run-$$")
reset_state
rc_nopat_jira=$(sct_rc init GH-540 --run-id "selftest-run-$$")
if [[ "$rc_nopat_num" == "0" && "$rc_nopat_jira" == "0" ]]; then
  pass "(kp-c) no keyPattern — any non-empty key accepted (both shapes)"
else
  fail "(kp-c) no keyPattern — num=$rc_nopat_num jira=$rc_nopat_jira"
fi

unset SECOND_SHIFT_CONFIG
reset_state

# --- JIRA-keyed fixtures: statectl surface is tracker-agnostic (jira adapter) ---
# The fixtures were produced by walking statectl itself under a jira config
# (ticketKey "gh-540", jdoe/gh-540 branches) — proving read/get/mutate/terminal
# all key off ticketKey without a hardcoded numeric assumption.
reset_state
cp "$FIXTURES_DIR/jira-completed-run.json" .claude/pipeline-state/gh-540.json
kf=$(sct get gh-540 '.ticketKey')
st=$(sct get gh-540 '.status')
br=$(sct get gh-540 '.branch')
rc_read=$(sct_rc get gh-540 '.stages."9".status')
if [[ "$kf" == "gh-540" && "$st" == "completed" && "$br" == "jdoe/gh-540" && "$rc_read" == "0" ]]; then
  pass "(kp-d) jira completed fixture — read/get key off ticketKey (gh-540, jdoe/ branch)"
else
  fail "(kp-d) jira completed fixture — key=$kf status=$st branch=$br rc=$rc_read"
fi

# Mid-pipeline JIRA fixture drives to terminal: mutate (stage 6+) + eval gate all
# accept a JIRA key. Proves the terminal completeness/eval gate is key-agnostic.
reset_state
cp "$FIXTURES_DIR/jira-in-progress-mid-pipeline.json" .claude/pipeline-state/gh-540.json
complete_stage gh-540 6
sct set-stage gh-540 7 --status started >/dev/null
sct checkpoint gh-540 7 --json '{"ticketKey":"gh-540","branch":"jdoe/gh-540","headSha":"abc","worktreePath":".claude/worktrees/jdoe-gh-540","deviations":[]}' >/dev/null
sct set-stage gh-540 7 --status completed >/dev/null
complete_stage gh-540 8
sct set-stage gh-540 9 --status started >/dev/null
sct set-stage gh-540 9 --status completed >/dev/null
rc_no_eval=$(sct_rc mark-completed gh-540)     # eval file absent → refused
printf '{"ticketKey":"gh-540","criteria":{"plan_grounding":"PASS"}}\n' > .claude/pipeline-state/gh-540-eval.json
rc_eval=$(sct_rc mark-completed gh-540)         # JIRA-keyed eval present → accepted
final_status=$(sct get gh-540 '.status')
if [[ "$rc_no_eval" != "0" && "$rc_eval" == "0" && "$final_status" == "completed" ]]; then
  pass "(kp-e) jira mid-pipeline fixture → terminal — eval gate keys off ticketKey (gh-540)"
else
  fail "(kp-e) jira mid-pipeline fixture — rc_no_eval=$rc_no_eval rc_eval=$rc_eval status=$final_status"
fi
reset_state

# ========================================================== drift-check (must-pass) ===

echo
echo "[self-test] drift-check — 5 enums (r1+r5+marker via regenerate-and-diff, r3/r4 via fixture mirror)"

drift_pass=1

# ---- (r1+r5+marker) regenerate-and-diff: valid_failure_reason + valid_deviation_kind + valid_stage_marker ----
# Replaces the previous (r1) doc↔statectl bidirectional drift-check and the (r5)
# documented-value acceptance loop. The generator at tools/gen-statectl-validators.sh
# reads the closed enums from state-schema.md and emits a complete rewritten
# statectl.sh. The committed statectl.sh must byte-match a fresh regeneration —
# if it doesn't, the schema and the helper have drifted.
#
# Minimum-count sanity guards against a silent generator-parser bug (e.g., a regex
# that drops rows but still emits a syntactically valid case body): if both files
# round-trip clean because they agree by construction, the diff alone won't catch it.

GENERATOR="${SKILL_DIR}/tools/gen-statectl-validators.sh"
if [[ ! -x "$GENERATOR" ]]; then
  echo "    DRIFT (r1+r5): generator not found or not executable at $GENERATOR"
  drift_pass=0
else
  gen_tmp=$(mktemp -t statectl-regen.XXXXXX)
  if ! bash "$GENERATOR" > "$gen_tmp" 2>/dev/null; then
    echo "    DRIFT (r1+r5): generator failed to run cleanly"
    drift_pass=0
  else
    # Minimum-count sanity: count case-branch lines inside each generated region.
    reason_count=$(awk '/^# >>> generated: valid_failure_reason >>>$/,/^# <<< generated: valid_failure_reason <<<$/' "$gen_tmp" \
      | grep -cE '^    \|?[a-z][a-z0-9-]+')
    kind_count=$(awk '/^# >>> generated: valid_deviation_kind >>>$/,/^# <<< generated: valid_deviation_kind <<<$/' "$gen_tmp" \
      | grep -cE '^    \|?[a-z][a-z0-9-]+')
    if (( reason_count < 5 )); then
      echo "    DRIFT (r1): generator emitted only $reason_count failureContext.reason values (expected >= 5)"
      drift_pass=0
    fi
    if (( kind_count < 4 )); then
      echo "    DRIFT (r5): generator emitted only $kind_count deviations[].kind values (expected >= 4)"
      drift_pass=0
    fi
    marker_count=$(awk '/^# >>> generated: valid_stage_marker >>>$/,/^# <<< generated: valid_stage_marker <<<$/' "$gen_tmp" \
      | grep -cE '^    \|?[a-z][a-z0-9-]+')
    if (( marker_count < 8 )); then
      echo "    DRIFT (marker): generator emitted only $marker_count stage-comment marker values (expected >= 8)"
      drift_pass=0
    fi
    # Byte-equal regenerate-and-diff against the committed file.
    if ! diff -q "$gen_tmp" "$STATECTL" >/dev/null 2>&1; then
      echo "    DRIFT (r1+r5): regenerator output differs from committed statectl.sh"
      echo "    Recover: bash $GENERATOR > statectl.sh.new && mv statectl.sh.new $STATECTL"
      drift_pass=0
    fi
  fi
  rm -f "$gen_tmp"
fi

# ---- (r3-r4) The smaller enums.
#
# These enums live in descriptive prose / inline code in state-schema.md (not in
# parseable tables), so the drift-check mirrors what statectl accepts here and the
# fixture re-asserts those values at every run. When state-schema.md or statectl
# changes any of these enums, this list MUST be updated in the same commit; the
# test header below names the doc anchors to keep in sync.

# (r3) top-level status — state-schema.md `Implementation + Review` section
DOC_TOP_STATUS=(in_progress completed failed)

# (r4) stages.N.status — state-schema.md `stages` section
# shellcheck disable=SC2034 # doc-parity anchor: kept in lockstep with state-schema.md even though (r4) probes via DOC_TOP_STATUS's identical set
DOC_STAGE_STATUS=(in_progress completed failed)

probe_status() {
  local status="$1"  # in_progress | completed | failed
  reset_state
  sct init 9999 --run-id "selftest-run-$$" >/dev/null
  jq --arg s "$status" '.status = $s' .claude/pipeline-state/9999.json > .claude/pipeline-state/9999.json.tmp \
    && mv .claude/pipeline-state/9999.json.tmp .claude/pipeline-state/9999.json
  sct_rc set-stage 9999 1 --status started
}

# (r3) top-level status: only in_progress should be accepted by set-stage
for s in "${DOC_TOP_STATUS[@]}"; do
  rc=$(probe_status "$s")
  if [[ "$s" == "in_progress" ]]; then
    if [[ "$rc" != "0" ]]; then
      echo "    DRIFT (top-level status): 'in_progress' was REJECTED by set-stage guard"
      drift_pass=0
    fi
  else
    if [[ "$rc" == "0" ]]; then
      echo "    DRIFT (top-level status): '$s' was ACCEPTED by set-stage guard (should refuse non-in_progress)"
      drift_pass=0
    fi
  fi
done

# (r5-invalid) deviations[].kind: regenerate-and-diff (above) proves the committed
# encoding agrees with state-schema.md, but does NOT prove the live helper rejects
# out-of-band values. Keep one invalid-kind probe.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
bad_dev_payload='{"ticketKey":"9999","branch":"claude/acme-9999","headSha":"abc","worktreePath":"/tmp/x","deviations":[{"kind":"bogus","planSection":"x","note":"y"}]}'
rc=$(sct_rc checkpoint 9999 7 --json "$bad_dev_payload")
if [[ "$rc" == "0" ]]; then
  echo "    DRIFT (deviations.kind): invalid value 'bogus' was ACCEPTED"
  drift_pass=0
fi

# (r4) stages.N.status: round-trip probe.
reset_state
sct init 9999 --run-id "selftest-run-$$" >/dev/null
sct set-stage 9999 1 --status started >/dev/null
got_inprogress=$(sct get 9999 '.stages."1".status')
sct checkpoint 9999 1 --json '{"verdict":"no-split"}' >/dev/null   # stage-1 completion evidence
sct set-stage 9999 1 --status completed >/dev/null
got_completed=$(sct get 9999 '.stages."1".status')
sct set-stage 9999 2 --status started >/dev/null
sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
got_failed=$(sct get 9999 '.stages."2".status')
if [[ "$got_inprogress" != "in_progress" || "$got_completed" != "completed" || "$got_failed" != "failed" ]]; then
  echo "    DRIFT (stages.N.status): round-trip produced unexpected values (got '$got_inprogress' / '$got_completed' / '$got_failed')"
  drift_pass=0
fi

if [[ $drift_pass -eq 1 ]]; then
  pass "(r) drift-check — r1+r5 regenerate-and-diff clean; r3/r4 fixture mirror agrees"
else
  fail "(r) drift-check — divergence (see above)"
fi

# ============================================================ optional stress ===

if [[ "${SKIP_STRESS:-0}" != "1" ]]; then
  echo
  echo "[self-test] stress — 5 cases (set SKIP_STRESS=1 to skip)"

  # (s) Two parallel set-stage writes → loser observes winner's state cleanly
  reset_state
  sct init 9999 --run-id "selftest-run-$$" >/dev/null
  complete_stage 9999 1
  sct set-stage 9999 2 --status started >/dev/null
  sct worktree-set 9999 --path ".claude/worktrees/acme-9999" --branch "claude/acme-9999" >/dev/null
  ( sct set-stage 9999 2 --status completed >/dev/null ) &
  ( sct set-stage 9999 2 --status completed >/dev/null ) &
  wait
  status2=$(sct get 9999 '.stages."2".status')
  if [[ "$status2" == "completed" ]]; then
    pass "(s) parallel set-stage writes — final state clean ($status2)"
  else
    fail "(s) parallel set-stage — final status='$status2'"
  fi

  # (u) kill -9 mid-rename via STATECTL_TEST_PAUSE_BEFORE_MV → primary state file unchanged
  reset_state
  sct init 9999 --run-id "selftest-run-$$" >/dev/null
  sct set-stage 9999 1 --status started >/dev/null
  sct checkpoint 9999 1 --json '{"verdict":"no-split"}' >/dev/null   # evidence, so the write path actually runs
  before_hash=$(shasum .claude/pipeline-state/9999.json | awk '{print $1}')
  STATECTL_TEST_PAUSE_BEFORE_MV=1 \
    "$STATECTL" set-stage 9999 1 --status completed >/dev/null 2>&1 &
  KPID=$!
  sleep 1
  kill -9 "$KPID" 2>/dev/null
  wait "$KPID" 2>/dev/null || true
  after_hash=$(shasum .claude/pipeline-state/9999.json | awk '{print $1}')
  if [[ "$before_hash" == "$after_hash" ]]; then
    pass "(u) kill -9 mid-rename — primary state file unchanged"
    # Cleanup the orphaned tmp
    rm -f .claude/pipeline-state/*.tmp
  else
    fail "(u) kill -9 mid-rename — primary file changed (before=$before_hash after=$after_hash)"
  fi

  # (v) mark-failed --reason <invalid> → rejects
  reset_state
  sct init 9999 --run-id "selftest-run-$$" >/dev/null
  err=$(sct_err mark-failed 9999 --reason not-a-real-reason)
  rc=$(sct_rc mark-failed 9999 --reason not-a-real-reason)
  if [[ "$rc" != "0" && "$err" == *"invalid --reason"* ]]; then
    pass "(v) mark-failed invalid reason → rejected"
  else
    fail "(v) mark-failed invalid reason — rc=$rc err='$err'"
  fi

  # (w) mark-failed on already-failed state without --force → rejects
  reset_state
  sct init 9999 --run-id "selftest-run-$$" >/dev/null
  sct mark-failed 9999 --reason plan-reviewer-block >/dev/null
  err=$(sct_err mark-failed 9999 --reason stale-branch-autonomous)
  rc=$(sct_rc mark-failed 9999 --reason stale-branch-autonomous)
  if [[ "$rc" != "0" && "$err" == *"terminal"* ]]; then
    pass "(w) mark-failed double-failure without --force → rejected"
  else
    fail "(w) mark-failed double — rc=$rc err='$err'"
  fi

  # (x) STATECTL_WRITER=bogus → rejects
  err=$(STATECTL_WRITER=bogus "$STATECTL" init 9999 2>&1 >/dev/null)
  rc=$?
  if [[ "$rc" != "0" && "$err" == *"invalid STATECTL_WRITER"* ]]; then
    pass "(x) STATECTL_WRITER=bogus → rejected"
  else
    fail "(x) STATECTL_WRITER=bogus — rc=$rc err='$err'"
  fi
else
  echo
  echo "[self-test] stress — SKIPPED (SKIP_STRESS=1)"
fi

echo
echo "[self-test] summary: $PASS passed, $FAIL failed"
exit $FAIL
