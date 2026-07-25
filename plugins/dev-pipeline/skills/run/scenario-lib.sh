#!/usr/bin/env bash
# scenario-lib.sh — shared scenario mechanics for the statectl-driven selftests.
#
# NOT a selftest: the filename deliberately does NOT match the CI discovery glob
# (`*-selftest.sh`), so CI never executes this file directly. It is sourced by
# BOTH statectl-selftest.sh (per-command contract coverage) and
# scenario-liveness-selftest.sh (composed verdict-path liveness) so the
# full-green-run recipe has exactly one definition — the composed per-stage
# precondition set is far larger than any prose summary of it, and duplicating it
# is how the two drift apart.
#
# It has no dedicated selftest by design: it is pure mechanics with no independent
# contract, and every CI run exercises it through both callers (25+ call sites in
# statectl-selftest.sh, four verdict paths in the liveness harness). A dedicated
# fixture test would be exactly the per-tool accretion this file's ticket removes.
#
# Contract for callers — set BEFORE sourcing:
#   STATECTL            path to statectl.sh
#   STATECTL_STATE_DIR  exported; the tmp pipeline-state dir the fixtures write to
#
# Source it by an ABSOLUTE path resolved from the caller's own BASH_SOURCE, and do
# so BEFORE `cd`-ing into a tmp dir — a relative source after the cd resolves
# against the tmp dir and fails.
#
# Defines no `pass` / `fail` and runs no assertions: reporting belongs to each
# caller, so the two can keep their own counters and output style.

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
# Keyed on $STATECTL_STATE_DIR rather than a relative `.claude/pipeline-state`, so
# the lib works for a caller that cds into its fixture root AND one that does not.
reset_state() {
  # `:?` guard, not bare expansion: `set -u` catches an UNSET var but not an empty
  # one, and an empty value here would expand the globs to `/*.json` at filesystem
  # root. Both current callers set it from `mktemp -d`, but this lib exists to be
  # sourced by future scenarios too — fail loudly instead of deleting.
  : "${STATECTL_STATE_DIR:?reset_state: STATECTL_STATE_DIR must be set to a non-empty fixture dir}"
  # *.md clears the run report (and any quarantined copy) too — otherwise a
  # report leaks across cases and init's stale-report quarantine fires on it.
  rm -f "$STATECTL_STATE_DIR"/*.json "$STATECTL_STATE_DIR"/*.tmp "$STATECTL_STATE_DIR"/*.md
}

# Helper: plant the verifyctl sidecar the Stage-6 completion gate requires
# (`require_verify_sidecar` in statectl.sh). That gate attests verifyctl actually
# RAN; these fixtures never invoke it, so the sidecar is stubbed here — once, in
# the shared recipe, rather than at every call site that walks stage 6.
#
# The stem comes from `statectl state-path` (minus `.json`), NOT from string
# composition on $key: the gate derives the filename through state_path, which
# lowercases the key exactly as verifyctl does. A fixture composing
# "${STATECTL_STATE_DIR}/${key}-verify.json" would diverge for any non-lowercase
# key — and non-numeric jira-style keys do appear among the callers — producing a
# plant the gate cannot see and a red that looks like a gate bug.
#
# $2 (optional) — a repo id, for a be-fe-pair per-target sidecar.
# SCENARIO_SKIP_VERIFY_SIDECAR=1 suppresses the write: the non-vacuity case in
# scenario-liveness-selftest.sh must drive the SAME recipe with no attestation,
# which it cannot do by omitting a plant that lives inside the recipe.
write_verify_sidecar() {
  [[ "${SCENARIO_SKIP_VERIFY_SIDECAR:-0}" == "1" ]] && return 0
  local key="$1" repo="${2:-}" stem run_id
  stem=$(sct state-path "$key") || return 0
  stem="${stem%.json}"
  run_id=$(sct get "$key" '.runId // ""')
  printf '{"runId":"%s","headSha":"scenariolib000000","chargedHead":"","at":"1970-01-01T00:00:00Z","failedClasses":[],"status":"pass"}\n' \
    "$run_id" > "${stem}${repo:+-$repo}-verify.json"
}

# Helper: start + complete one stage with the minimal evidence its completion
# precondition requires (the imperative stage machine refuses a bare
# `--status completed`). Stages 3/7/9 carry only the comment-receipt leg;
# stage 7's checkpoint is written where a case needs it (validate_stage7_payload
# applies there).
#
# $3 (optional) — the stage-1 checkpoint verdict, default `no-split`. A scenario
# driving a non-no-split verdict MUST pass its own, otherwise it asserts liveness
# against a stage-1 checkpoint that contradicts the path under test.
complete_stage() {
  local key="$1" n="$2" verdict="${3:-no-split}"
  sct set-stage "$key" "$n" --status started >/dev/null
  case "$n" in
    1) sct checkpoint "$key" 1 --json "{\"verdict\":\"$verdict\",\"preflight\":{\"baseBranch\":\"main\",\"workingTreeClean\":true,\"guardOutcome\":\"proceed-clean\"}}" >/dev/null
       sct skill-load-add "$key" --stage 1 --skill intake-toolkit:intake-orchestrator >/dev/null
       sct comment-add "$key" --marker claimed --url "https://github.example/c/claimed" >/dev/null
       sct comment-add "$key" --marker intake --url "https://github.example/c/intake" >/dev/null ;;
    2) sct worktree-set "$key" --path ".claude/worktrees/acme-$key" --branch "claude/acme-$key" >/dev/null ;;
    3) sct comment-add "$key" --marker plan --url "https://github.example/c/plan" >/dev/null ;;
    4) sct plan-review-set "$key" --overall pass >/dev/null ;;
    5) sct checkpoint "$key" 5 --json '{"changedFiles":[]}' >/dev/null ;;
    6) sct verify-summary-set "$key" --json '{"format":"clean","test":"passed"}' >/dev/null
       write_verify_sidecar "$key" ;;
    7) sct checkpoint "$key" 7 --json "$VALID_PAYLOAD" >/dev/null
       sct comment-add "$key" --marker doc-update --url "https://github.example/c/doc-update" >/dev/null ;;
    8) sct review-rounds "$key" --set 1 >/dev/null
       sct skill-load-add "$key" --stage 8 --skill review-toolkit:review-lead >/dev/null
       sct comment-add "$key" --marker code-review --url "https://github.example/c/code-review" >/dev/null ;;
    9) sct comment-add "$key" --marker pr --url "https://github.example/c/pr" >/dev/null ;;
  esac
  sct set-stage "$key" "$n" --status completed >/dev/null
}

# Helper: write a valid self-eval file for <key> (the mark-completed eval gate).
# Scores exactly the five locked criteria from eval-criteria.md with binary
# values — the shape the criteria-shape gate enforces.
write_eval() {
  local key="$1"
  printf '{"ticketKey":%s,"criteria":{"target_confirmation":"PASS","plan_grounding":"PASS","implementation_resilience":"N/A","scope_compliance":"PASS","review_precision":"PASS"}}\n' "$key" \
    > "$STATECTL_STATE_DIR/${key}-eval.json"
}

# Helper: write a plausible run report for <key> (the mark-completed report gate).
write_report() {
  local key="$1"
  printf '<!-- dev-pipeline-report -->\n\n# Run report — #%s\n\nPR: https://example.com/pr/1\n' "$key" \
    > "$STATECTL_STATE_DIR/${key}-report.md"
}

# Acme single-repo Stage 7 checkpoint payload — flat fields, no perRepo wrapper.
# NOTE: worktreePath here is intentionally absolute. checkpoint/build-checkpoint-7
# store a copy of an already-validated worktreePath and do NOT flow through
# worktree-set, so the repo-relative path-form guard (ws5) does not apply to these
# checkpoint fixtures — they exercise the payload-shape checks in isolation. The
# canonical repo-relative form is enforced only at the worktree-set writer (see
# cmd_worktree_set in statectl.sh and state-schema.md "Worktree").
VALID_PAYLOAD='{"ticketKey":"9999","branch":"claude/acme-9999","headSha":"abc123","worktreePath":"/tmp/x","deviations":[]}'

# Helper: walk all 9 stages but set Stage-6 verifySummary to $2 (raw JSON), and
# charge one TEST_FAILURE when $3 == "tf". Leaves the run at in_progress with all
# stages completed and the run report written — so the resilience value-check is
# the only terminal gate under test.
complete_run_vs() {
  local key="$1" vs="$2" tf="${3:-}"
  reset_state
  sct init "$key" --run-id "selftest-run-$$" >/dev/null
  for n in 1 2 3 4 5; do complete_stage "$key" "$n"; done
  sct set-stage "$key" 6 --status started >/dev/null
  sct verify-summary-set "$key" --json "$vs" >/dev/null
  write_verify_sidecar "$key"
  [[ "$tf" == "tf" ]] && sct verify-attempts "$key" --incr TEST_FAILURE >/dev/null
  sct set-stage "$key" 6 --status completed >/dev/null
  for n in 7 8 9; do complete_stage "$key" "$n"; done
  write_report "$key"
}
