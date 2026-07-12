#!/usr/bin/env bash
# statectl.sh — load-bearing state-machine invariants for the dev-pipeline skill.
#
# Owns: state file lifecycle (init/read), stage lifecycle writes (atomic
# start/end field bundles), Stage 7 checkpoint write (with payload schema validation),
# failure writes (atomic failureContext + status=failed bundle with closed-enum
# reason), and writer-suffix isolation via $STATECTL_WRITER.
#
# Terminal-state guard (require_mutable): every mutating subcommand refuses to
# overwrite a completed/failed run unless --force is passed — EXCEPT set-stage
# (stricter: its terminal/forward-skip/re-start guards have NO --force escape;
# re-entering a stage on a terminal run is never valid recovery) and
# pipeline-session-add (exempt: a post-terminal cost backfill is legitimate). See
# require_mutable's definition for the rationale. set-stage DOES take --force, but
# it escapes ONLY the monotonic stage-progression guard (start-N while N-1 not
# completed) and the per-stage completion-evidence preconditions (see
# stage_completion_preconditions) for genuine crash-recovery — never the
# terminal-state guard.
#
# Imperative stage machine: `set-stage N --status completed` is refused unless
# the state carries the evidence stage N's mandated work actually happened
# (stage_completion_preconditions), and `mark-completed` is refused unless all
# stages 1-9 completed AND a plausible self-eval file exists (NOT bypassed by
# --force). Enforcement by refusal, not prose — see state-schema.md.
#
# Does NOT own:
#   costBlockApplied (written only by pipeline-cost-block.sh — intentionally
#   external; the sole exception to the ownership rule, see state-schema.md)
#
# Usage:
#   statectl.sh init <issue-number>
#   statectl.sh get <issue-number> <jq-path>
#   statectl.sh set-stage <issue-number> <N> --status started|completed [--force]
#   statectl.sh checkpoint <issue-number> <N> --json <payload> [--force]
#   statectl.sh worktree-set <issue-number> --path <worktreePath> --branch <branch> [--force]
#   statectl.sh pr-add <issue-number> --branch <branch> --url <pr-url> [--force]
#   statectl.sh review-rounds <issue-number> --set <1-3> [--exhausted] [--force]
#   statectl.sh deviations-add <issue-number> --kind <enum> --note <s> [--plan-section <s>] [--file <f>] [--line <n>] [--stage <N>] [--force]
#   statectl.sh verify-attempts <issue-number> --incr <FAILURE_CLASS> [--force]
#   statectl.sh intake-brief <issue-number> --brief-path <path|null> --acceptance-criteria '<json-array>'
#   statectl.sh plan-review-set <issue-number> --overall <pass|fix-and-go> [--force]
#   statectl.sh verify-summary-set <issue-number> --json <verifySummary> [--force]
#   statectl.sh quality-pass-set <issue-number> --json <payload> [--force]
#   statectl.sh mark-failed <issue-number> --reason <reason> [--stage <N>] [--json <details>] [--force]
#   statectl.sh mark-completed <issue-number> [--force]
#   statectl.sh build-failure-context --reason <enum> [--stage <N>] [--kv k=v]... [--kv-num k=v]... [--kv-lines k=v]...
#   statectl.sh build-checkpoint-7 --issue <N> --branch <B> --head <H> --worktree <W> \
#     [--plan <P>] [--changed-files <json>] [--verify-summary <json>] [--deviations <json>] \
#     [--free-note <s>] [--plan-risks <json>] [--doc-updater-findings <md>] \
#     [--quality-pass-summary <json>]
#
# Env contract:
#   STATECTL_WRITER  = skill (default)
#   STATECTL_STATE_DIR  = explicit pipeline-state dir override (used by the
#                         selftest fixtures; unset in production — the dir is
#                         derived from the script's main checkout, see state_dir)
#   STATECTL_TEST_PAUSE_BEFORE_MV  = 1  (test-only; pauses 5s before mv for kill-mid-write fixtures)
#
# Mirrors closed enums from state-schema.md (see drift-check in statectl-selftest.sh):
#   - failureContext.reason index (state-schema.md `### failureContext.reason index`)
#   - stages.N.status, top-level status (in_progress | completed | failed)
#   - deviations[].kind (scope-creep | alternate-approach | deferred | surprise)
#   - stage-comment markers (state-schema.md `#### Stage-comment markers`)
#
# Closed-enum changes require a corresponding edit to the validators below
# AND the docs; the drift-check self-test fixture enforces parity.
#
# Helper-failure contract: all errors print to stderr with `[statectl-error] ` prefix
# and exit non-zero. Statectl never writes failureContext.reason="statectl-error"
# (would require a schema-enum addition; out of scope for the initial PR).
#
# Single-repo: this pipeline operates on one consumer repo per run (see SKILL.md Known Limitations).
# This helper has no cross-repo machinery — Stage 7 payload validates flat
# branch/headSha/worktreePath fields directly, with no perRepo wrapper.

set -uo pipefail

# ---------------------------------------------------------------- shared utils ---

die() {
  echo "[statectl-error] $*" >&2
  exit "${EXIT_CODE:-1}"
}

# Resolve writer suffix from STATECTL_WRITER (default: skill).
# Only `skill` is valid now that driver/headless mode is retired; the var is kept
# as the single tmp-file suffix chokepoint and to reject typos eagerly.
resolve_writer() {
  local w="${STATECTL_WRITER:-skill}"
  case "$w" in
    skill) echo "$w" ;;
    *) EXIT_CODE=3 die "invalid STATECTL_WRITER: '$w' (must be skill)" ;;
  esac
}

# Server-clock ISO-8601 UTC timestamp. The pipeline contract bans model-generated
# timestamps; this is the single chokepoint.
now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Resolve the pipeline-state directory. Precedence:
#   1. $STATECTL_STATE_DIR — explicit override (selftest fixtures).
#   2. The CONSUMER repo's main checkout, derived from $PWD via
#      `git rev-parse --git-common-dir` ($SECOND_SHIFT_REPO_ROOT overrides).
#      Worktree-safe: a worktree cwd still resolves to the main checkout,
#      because crash-recovery state must outlive worktree removal (Stage 10).
#      Post-pluginization this script lives in the PLUGIN checkout, so the
#      pre-extraction script-location anchor would resolve to the wrong repo;
#      the pipeline contract is that statectl is always invoked from the
#      consumer repo or one of its worktrees. The state subdir defaults to
#      .claude/pipeline-state; config paths.pipelineStateDir overrides
#      (config: <root>/.claude/second-shift.config.json or $SECOND_SHIFT_CONFIG).
#   3. cwd-relative fallback (legacy behavior) if git resolution fails.
state_dir() {
  if [[ -n "${STATECTL_STATE_DIR:-}" ]]; then
    printf '%s\n' "$STATECTL_STATE_DIR"
    return 0
  fi
  local root="" common_dir cfg rel=".claude/pipeline-state"
  if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
    root="$SECOND_SHIFT_REPO_ROOT"
  elif common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
    # --git-common-dir may return a relative path; normalize against $PWD.
    common_dir="$(cd "$common_dir" && pwd)"
    root="$(dirname "$common_dir")"
  fi
  if [[ -n "$root" ]]; then
    cfg="${SECOND_SHIFT_CONFIG:-$root/.claude/second-shift.config.json}"
    if [[ -f "$cfg" ]]; then
      rel="$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$cfg" 2>/dev/null)" \
        || rel=".claude/pipeline-state"
    fi
    printf '%s\n' "$root/$rel"
    return 0
  fi
  printf '%s\n' ".claude/pipeline-state"
}

# Resolve the consumer-repo config file path (or empty if unresolvable/absent).
# Mirrors state_dir's root derivation: explicit $SECOND_SHIFT_CONFIG wins, else
# <repo-root>/.claude/second-shift.config.json via the git-common-dir anchor.
config_file() {
  if [[ -n "${SECOND_SHIFT_CONFIG:-}" ]]; then
    printf '%s\n' "$SECOND_SHIFT_CONFIG"
    return 0
  fi
  local root="" common_dir
  if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
    root="$SECOND_SHIFT_REPO_ROOT"
  elif common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
    common_dir="$(cd "$common_dir" && pwd)"
    root="$(dirname "$common_dir")"
  fi
  [[ -n "$root" ]] && printf '%s\n' "$root/.claude/second-shift.config.json"
}

# Tracker-shaped key validation (config tracker.keyPattern). When the consumer
# repo declares a keyPattern, a fresh `init` key must match it anchored end-to-end
# (github "[0-9]+", jira "[A-Z]+-[0-9]+", etc.) — a malformed key is rejected
# before any state is written, so one statectl serves both trackers without a
# hardcoded numeric assumption. Absent config / absent pattern = accept any
# non-empty key (backward-compatible with the pre-config selftests). The key is
# matched case-insensitively against the pattern so a lowercased JIRA key
# (proj-123) still satisfies an upper-case pattern.
validate_ticket_key() {
  local key="$1"
  local cfg pattern
  cfg=$(config_file)
  [[ -n "$cfg" && -f "$cfg" ]] || return 0
  pattern=$(jq -r '.tracker.keyPattern // empty' "$cfg" 2>/dev/null) || return 0
  [[ -n "$pattern" ]] || return 0
  # Anchor the pattern and compare case-insensitively (bash regex).
  local lower_key lower_pat
  lower_key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  lower_pat=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
  [[ "$lower_key" =~ ^(${lower_pat})$ ]] \
    || { EXIT_CODE=3 die "init: ticket key '$key' does not match config tracker.keyPattern '$pattern'"; }
}

# State-file path for a given ticket key. The key is lowercased defensively in case
# a future caller passes a non-numeric slice suffix (`123-pr2`) or a JIRA key
# (`PROJ-123`); pure-numeric keys pass through unchanged.
state_path() {
  local raw="$1"
  local key
  key=$(echo "$raw" | tr '[:upper:]' '[:lower:]')
  echo "$(state_dir)/${key}.json"
}

# `state-path <ticket>` — print the resolved state-file ABSOLUTE path (honors
# paths.pipelineStateDir + the ticket-key lowercasing rule). Read-only: it does
# not require the file to exist. Stages that must locate the state file (e.g. the
# Stage-4 plan gate handing it to plan-lint.sh) call this instead of
# reconstructing the literal `.claude/pipeline-state/${KEY}.json`, which ignores
# both pipelineStateDir and the lowercasing and so breaks Jira / custom-dir consumers.
cmd_state_path() {
  local key="${1:-}"
  [[ -n "$key" ]] || { EXIT_CODE=3 die "state-path: usage: state-path <ticket-key>"; }
  state_path "$key"
}

# Write atomically via writer-suffixed tmp file.
# $1 = issue number, $2 = new JSON content
atomic_write() {
  local key="$1"
  local content="$2"
  local writer
  writer=$(resolve_writer)
  local state
  state=$(state_path "$key")
  local tmp="${state}.${writer}.tmp"
  mkdir -p "$(dirname "$state")"
  printf '%s\n' "$content" > "$tmp" || { EXIT_CODE=2 die "could not write $tmp"; }
  # Test-only hook for kill-mid-write fixtures
  if [[ "${STATECTL_TEST_PAUSE_BEFORE_MV:-}" == "1" ]]; then
    sleep 5
  fi
  mv "$tmp" "$state" || { EXIT_CODE=2 die "could not rename $tmp → $state"; }
}

# Read state file. Returns JSON content on stdout.
read_state() {
  local key="$1"
  local state
  state=$(state_path "$key")
  [[ -f "$state" ]] || { EXIT_CODE=2 die "no state file at $state"; }
  local raw
  raw=$(cat "$state")
  jq empty <<< "$raw" 2>/dev/null \
    || { EXIT_CODE=2 die "could not parse state file at $state (corrupt JSON?)"; }
  printf '%s\n' "$raw"
}

# Terminal-state guard (shared). Refuse to mutate a completed/failed run unless
# --force was passed; only `in_progress` (or an absent/empty status, defensively)
# is freely mutable. Centralizes the check that mark-failed/mark-completed
# carried inline, and that the stage-boundary / mid-stage mutators
# (worktree-set, pr-add, review-rounds, verify-attempts, slice-set, checkpoint)
# previously lacked entirely — the corruption gap #154 closes. set-stage is
# intentionally NOT routed through this helper (its terminal guard is stricter:
# inline, with no --force escape, because re-entering a stage on a terminal run is
# never valid recovery). set-stage's own --force escapes only its monotonic
# stage-progression guard (start-N while N-1 not completed), never this terminal
# guard. pipeline-session-add is intentionally exempt (a documented post-terminal
# cost backfill is legitimate — see its subcommand comment).
# Args: <current-state-json> <force 0|1> <subcmd-name-for-error>.
require_mutable() {
  local current_json="$1" force="$2" subcmd="$3"
  local top_status
  top_status=$(jq -r '.status // ""' <<< "$current_json")
  if [[ "$top_status" != "in_progress" && "$top_status" != "" && "$force" -ne 1 ]]; then
    EXIT_CODE=1 die "$subcmd: state is terminal (status=$top_status); pass --force to overwrite"
  fi
}

# Post-Run Eval fail-closed gate (SKILL.md "Post-Run Eval"): the terminal
# `completed` write is refused unless the run's self-eval exists and is a
# plausible score (parseable JSON, non-empty .criteria, matching .ticketKey —
# enough to defeat `touch`/`echo {}` without inventing an eval schema; the
# scored template in eval-criteria.md carries both fields — read-only against
# that LOCKED file). Deliberately NOT called from mark-failed: its call sites
# across stages 1-9 do not write an eval first, and gating them would strand
# aborting runs `in_progress` with no failureContext. The abort-path eval
# remains a prose contract audited by pipeline-retro.
require_eval_file() {
  local key="$1"
  local lower state eval_file
  lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
  state=$(state_path "$key")
  eval_file="$(dirname "$state")/${lower}-eval.json"
  [[ -f "$eval_file" ]] \
    || { EXIT_CODE=1 die "mark-completed: terminal write refused — self-eval $eval_file is missing. Score the run against eval-criteria.md and write it FIRST (SKILL.md 'Post-Run Eval', fail-closed), then retry."; }
  jq -e --arg k "$lower" '(.criteria | type == "object" and length > 0) and ((.ticketKey | tostring) == $k)' "$eval_file" >/dev/null 2>&1 \
    || { EXIT_CODE=1 die "mark-completed: $eval_file exists but is not a valid self-eval (needs parseable JSON with non-empty .criteria and .ticketKey == \"$lower\")"; }
}

# Per-stage completion-evidence preconditions (imperative stage machine): a
# `set-stage N --status completed` write is refused unless the state carries the
# evidence that stage N's mandated work actually happened. Deterministic state
# reads only; conditional applicability comes from the flags the run itself
# recorded (unitTestSurface, stageCheckpoint["1"].designDriven). --force
# bypasses these the same way it bypasses the monotonic guard (crash-recovery
# escape). Stages 3, 7, and 9 have no entry: Stage 3's plan is enforced by
# Stage 4's lint gate + reviewer, Stage 7's checkpoint is validated at write by
# validate_stage7_payload, Stage 9 by mark-completed's terminal gates.
stage_completion_preconditions() {
  local n="$1"
  local current="$2"
  case "$n" in
    1)
      jq -e '(.stageCheckpoint // {})["1"] | type == "object"' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 1 — stageCheckpoint[\"1\"] is missing (write the Stage-1 checkpoint first); --force for crash-recovery"; }
      ;;
    2)
      jq -e '(.worktreePath | type == "string" and length > 0) and (.branch | type == "string" and length > 0)' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 2 — worktreePath/branch missing (call worktree-set first, per its ordering contract); --force for crash-recovery"; }
      ;;
    4)
      jq -e '.stages["4"].planReview.overall | type == "string" and length > 0' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 4 — stages.4.planReview.overall is not recorded (dispatch the plan-review workflow and record its consolidated verdict via plan-review-set first); --force for crash-recovery"; }
      ;;
    5)
      jq -e '(.stageCheckpoint // {})["5"] | type == "object"' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 5 — stageCheckpoint[\"5\"] is missing (write the Stage-5 checkpoint first); --force for crash-recovery"; }
      jq -e '(((.unitTestSurface.applicable // false) and ((.unitTestSurface.action // "skip") != "skip")) | not)
             or (.stages["5"].unitTestMutationReview == "completed")' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 5 — unit-test-applicable run with stages.5.unitTestMutationReview not at terminal \"completed\" (a non-terminal sub-status under a completed stage is a swallowed stall); --force for crash-recovery"; }
      jq -e '(((.stageCheckpoint // {})["1"].designDriven // false) | not)
             or (.stages["5"].designPlanReview == "implemented")' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 5 — designDriven run with stages.5.designPlanReview not at terminal \"implemented\"; --force for crash-recovery"; }
      ;;
    6)
      jq -e '.verifySummary | (type == "object") or (type == "string" and length > 0)' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 6 — top-level verifySummary is missing (write it from the verifyctl verdict JSON via verify-summary-set, on both lanes); --force for crash-recovery"; }
      ;;
    8)
      jq -e '(.codeReviewRounds // 0) >= 1' <<< "$current" >/dev/null \
        || { EXIT_CODE=1 die "set-stage: cannot complete stage 8 — no codeReviewRounds recorded (run the review loop and record the round count via review-rounds); --force for crash-recovery"; }
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------- validators ---

# failureContext.reason — a closed, generated enum (see the generated region
# below for the current value set). Mirrors state-schema.md
# `### failureContext.reason index`. Single-repo pipeline: multi-repo failure
# reasons (target ambiguation, FE-repo reachability, user identifier detection)
# do not apply and are intentionally not part of the enum.
# >>> generated: valid_failure_reason >>>
# Generated by .claude/skills/run/tools/gen-statectl-validators.sh from state-schema.md
# Do not hand-edit. Regenerate: bash .claude/skills/run/tools/gen-statectl-validators.sh > statectl.sh.new && mv statectl.sh.new statectl.sh
valid_failure_reason() {
  case "$1" in
    non-main-base-autonomous \
    |worktree-creation-failed \
    |plan-reviewer-block \
    |approach-failure-circuit-breaker \
    |stale-branch-autonomous \
    |worktree-missing \
    |unit-test-surface-ambiguous \
    |plan-structure-invalid \
    |unit-test-plan-reviewer-block \
    |unit-test-mutation-reviewer-block \
    |design-source-unreachable \
    |ext-workflow-failed) return 0 ;;
    *) return 1 ;;
  esac
}
# <<< generated: valid_failure_reason <<<

# stages.N.status and top-level status — 3 values
valid_status() {
  case "$1" in
    in_progress|completed|failed) return 0 ;;
    *) return 1 ;;
  esac
}

# deviations[].kind — 4 values (validated only within Stage 7 checkpoint payloads)
# >>> generated: valid_deviation_kind >>>
# Generated by .claude/skills/run/tools/gen-statectl-validators.sh from state-schema.md
# Do not hand-edit. Regenerate: bash .claude/skills/run/tools/gen-statectl-validators.sh > statectl.sh.new && mv statectl.sh.new statectl.sh
valid_deviation_kind() {
  case "$1" in
    scope-creep \
    |alternate-approach \
    |deferred \
    |surprise) return 0 ;;
    *) return 1 ;;
  esac
}
# <<< generated: valid_deviation_kind <<<

# stage-comment markers — the `<!-- stage: X -->` issue-comment vocabulary.
# Mirrors state-schema.md `#### Stage-comment markers`. Not on any statectl
# write path (statectl does not post comments); consumed by the selftest's
# marker-emission parity case and available to future comment-posting helpers.
# >>> generated: valid_stage_marker >>>
# Generated by .claude/skills/run/tools/gen-statectl-validators.sh from state-schema.md
# Do not hand-edit. Regenerate: bash .claude/skills/run/tools/gen-statectl-validators.sh > statectl.sh.new && mv statectl.sh.new statectl.sh
valid_stage_marker() {
  case "$1" in
    claimed \
    |intake \
    |plan \
    |plan-review \
    |verify \
    |doc-update \
    |code-review \
    |pr) return 0 ;;
    *) return 1 ;;
  esac
}
# <<< generated: valid_stage_marker <<<

# Validate a Stage 7 checkpoint payload (JSON on stdin). Other stages get JSON-parse-only.
# Flat single-repo schema: branch, headSha, worktreePath as top-level string fields.
validate_stage7_payload() {
  local key="$1"
  local payload="$2"
  # JSON parse
  local parsed
  parsed=$(jq '.' <<< "$payload" 2>/dev/null) \
    || die "checkpoint payload is not valid JSON"
  # ticketKey matches file
  local payload_key
  payload_key=$(jq -r '.ticketKey // ""' <<< "$parsed")
  [[ "$payload_key" == "$key" ]] || die "checkpoint payload ticketKey ('$payload_key') does not match state file ticketKey ('$key')"
  # Required flat fields
  for f in branch headSha worktreePath; do
    jq -e --arg f "$f" '.[$f] | type == "string" and length > 0' <<< "$parsed" >/dev/null \
      || die "checkpoint payload .$f missing or empty"
  done
  # deviations validation (if non-empty)
  local dev_count
  dev_count=$(jq '.deviations | if type == "array" then length else -1 end' <<< "$parsed")
  [[ "$dev_count" -ge 0 ]] || die "checkpoint payload deviations must be an array"
  if [[ "$dev_count" -gt 0 ]]; then
    local kinds
    kinds=$(jq -r '.deviations[].kind // ""' <<< "$parsed")
    while IFS= read -r kind; do
      valid_deviation_kind "$kind" \
        || die "checkpoint payload has deviation with invalid kind '$kind' (allowed: scope-creep, alternate-approach, deferred, surprise)"
    done <<< "$kinds"
  fi
}

# ---------------------------------------------------------------- subcommands ---

cmd_init() {
  local key="${1:-}"
  [[ -n "$key" ]] || { EXIT_CODE=3 die "init: missing <ticket-key>"; }
  shift || true
  # Strict positional-first: <ticket-key> THEN --run-id <id>. If --run-id
  # precedes the positional, it gets consumed as the ticket key above and
  # the flag parse below trips on missing-flag.
  local run_id=""
  while (( $# > 0 )); do
    case "$1" in
      --run-id)
        run_id="${2:-}"
        shift 2 || { EXIT_CODE=3 die "init: --run-id missing value"; }
        ;;
      *)
        EXIT_CODE=3 die "init: unrecognized argument: $1"
        ;;
    esac
  done
  [[ -n "$run_id" ]] || { EXIT_CODE=3 die "init: --run-id required"; }
  validate_ticket_key "$key"
  local state
  state=$(state_path "$key")
  if [[ -f "$state" ]]; then
    # Idempotent: read existing status, report state, do not mutate.
    # --run-id is ignored here — top-level runId is set once at init and never overwritten (D3).
    local existing
    existing=$(read_state "$key") || exit $?
    local status
    status=$(jq -r '.status // "unknown"' <<< "$existing")
    echo "state=existing-${status}"
    return 0
  fi
  local lower
  lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
  # Stale-eval quarantine: a brand-new run must not be able to satisfy the
  # mark-completed eval gate with a previous run's self-score (the "re-run from
  # scratch" / cleared-state path). Rename, don't delete — the old score stays
  # inspectable.
  local eval_file
  eval_file="$(dirname "$state")/${lower}-eval.json"
  if [[ -f "$eval_file" ]]; then
    local stale_dest
    stale_dest="$(dirname "$state")/${lower}-eval-stale-$(now_iso | tr -d ':').json"
    mv "$eval_file" "$stale_dest" \
      || { EXIT_CODE=2 die "init: could not quarantine stale self-eval $eval_file"; }
    echo "[statectl] init: quarantined stale self-eval -> $(basename "$stale_dest")" >&2
  fi
  local now
  now=$(now_iso)
  local payload
  payload=$(jq -n --arg key "$lower" --arg now "$now" --arg run_id "$run_id" '{
    ticketKey: $key,
    runId: $run_id,
    status: "in_progress",
    startedAt: $now,
    lastUpdatedAt: $now,
    stages: {}
  }')
  atomic_write "$key" "$payload"
  echo "state=created"
}

cmd_get() {
  local key="${1:-}"
  local jq_path="${2:-}"
  [[ -n "$key" && -n "$jq_path" ]] || { EXIT_CODE=3 die "get: missing <issue-number> or <jq-path>"; }
  local content
  content=$(read_state "$key") || exit $?
  jq -r "$jq_path" <<< "$content" 2>/dev/null \
    || { EXIT_CODE=3 die "get: invalid jq path '$jq_path'"; }
}

cmd_set_stage() {
  local key="${1:-}"; shift || true
  local n="${1:-}"; shift || true
  local status="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="${2:-}"; shift 2 ;;
      # --force escapes two guards: the monotonic stage-progression guard on the
      # --status started path, and the completion-evidence preconditions on the
      # --status completed path (both genuine crash-recovery escapes). It never
      # escapes startedAt-must-exist (a correctness invariant, never something to
      # force past) nor the inline terminal-state guard on either path.
      --force)  force=1; shift ;;
      *) EXIT_CODE=3 die "set-stage: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$n" && -n "$status" ]] || { EXIT_CODE=3 die "set-stage: missing <issue-number> <N> --status started|completed"; }
  [[ "$n" =~ ^[1-9]$ ]] || { EXIT_CODE=1 die "set-stage: N must be in {1..9}, got '$n'"; }
  [[ "$status" == "started" || "$status" == "completed" ]] \
    || { EXIT_CODE=3 die "set-stage: --status must be 'started' or 'completed', got '$status'"; }

  local current
  current=$(read_state "$key") || exit $?
  local top_status
  top_status=$(jq -r '.status // ""' <<< "$current")
  [[ "$top_status" == "in_progress" || "$top_status" == "" ]] \
    || { EXIT_CODE=1 die "set-stage: top-level status is '$top_status', cannot mutate (use init or clear state)"; }

  local cur_stage
  cur_stage=$(jq -r '.currentStage // ""' <<< "$current")
  local now
  now=$(now_iso)

  if [[ "$status" == "started" ]]; then
    # Forward-skip > 1 guard (re-entry N==cur_stage and one-step forward N==cur_stage+1 allowed;
    # backward N<cur_stage also allowed for Stage 8 review-loop pseudo-reruns).
    if [[ -n "$cur_stage" && "$cur_stage" != "null" ]]; then
      local diff=$((n - cur_stage))
      if [[ $diff -gt 1 ]]; then
        EXIT_CODE=1 die "set-stage: forward-skip > 1 rejected (currentStage=$cur_stage, target=$n)"
      fi
    fi
    # stages.N.completedAt must not be set
    local completed_at
    completed_at=$(jq -r --arg n "$n" '.stages[$n].completedAt // ""' <<< "$current")
    [[ -z "$completed_at" || "$completed_at" == "null" ]] \
      || { EXIT_CODE=1 die "set-stage: stages.$n.completedAt is set; cannot re-start a completed stage (no --replay flag in this version)"; }
    # Monotonic stage-progression guard: cannot start stage N while N-1 is not
    # `completed`. Mechanically prevents the stage-overlap class (started-N while
    # N-1 still in_progress → mis-attributed wall-clock, negative inter-stage gaps).
    # Base case: N==1 (prev==0, no stage 0) and any N whose stages[N-1] is absent
    # are allowed — the first `set-stage 1 --status started` of every run has no
    # currentStage and no stages.0, so it must pass. Composes with the forward-skip
    # guard above: re-entry (N==cur_stage) and backward (N<cur_stage) review-loop
    # transitions have an already-`completed` N-1, so this is benign there; it bites
    # only the forward N==cur_stage+1 case where N-1 is still in_progress.
    # --force escapes THIS guard only (genuine crash-recovery where a prior session
    # left N-1 in_progress on disk) — it does NOT escape the terminal-state guard
    # above (re-entering a stage on a completed/failed run is never valid recovery),
    # nor the forward-skip / re-start-completed guards.
    local prev=$((n - 1))
    if [[ "$prev" -ge 1 && "$force" -ne 1 ]]; then
      local prev_status
      prev_status=$(jq -r --arg p "$prev" '.stages[$p].status // ""' <<< "$current")
      if [[ -n "$prev_status" && "$prev_status" != "null" && "$prev_status" != "completed" ]]; then
        EXIT_CODE=1 die "set-stage: cannot start stage $n while stage $prev is not completed (status=$prev_status); pass --force for crash-recovery"
      fi
    fi
    # Atomic field bundle (started): preserve existing startedAt if present
    local new_state
    new_state=$(jq --arg n "$n" --arg now "$now" '
      .currentStage = ($n | tonumber)
      | .stages[$n] = (.stages[$n] // {})
      | .stages[$n].status = "in_progress"
      | (if .stages[$n].startedAt then . else .stages[$n].startedAt = $now end)
      | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "set-stage: jq mutation failed"; }
    atomic_write "$key" "$new_state"
  else
    # completed: stages.N.startedAt must be set
    local started_at
    started_at=$(jq -r --arg n "$n" '.stages[$n].startedAt // ""' <<< "$current")
    [[ -n "$started_at" && "$started_at" != "null" ]] \
      || { EXIT_CODE=1 die "set-stage: cannot complete stage $n with no startedAt (must call --status started first)"; }
    # Completion-evidence preconditions (imperative stage machine): refuse to
    # close a stage whose mandated evidence is absent from state. --force is the
    # crash-recovery escape.
    if [[ "$force" -ne 1 ]]; then
      stage_completion_preconditions "$n" "$current"
    fi
    # Atomic field bundle (completed): does NOT advance currentStage
    local new_state
    new_state=$(jq --arg n "$n" --arg now "$now" '
      .stages[$n].status = "completed"
      | .stages[$n].completedAt = $now
      | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "set-stage: jq mutation failed"; }
    atomic_write "$key" "$new_state"
  fi
}

cmd_checkpoint() {
  local key="${1:-}"; shift || true
  local n="${1:-}"; shift || true
  local payload="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  payload="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "checkpoint: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$n" && -n "$payload" ]] || { EXIT_CODE=3 die "checkpoint: missing <issue-number> <N> --json <payload>"; }
  [[ "$n" =~ ^[1-9]$ ]] || { EXIT_CODE=1 die "checkpoint: N must be in {1..9}"; }
  # JSON parse + Stage 7 schema validation
  jq '.' <<< "$payload" >/dev/null 2>&1 || die "checkpoint: --json payload is not valid JSON"
  if [[ "$n" == "7" ]]; then
    local lower
    lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    validate_stage7_payload "$lower" "$payload"
  fi
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "checkpoint"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg n "$n" --arg now "$now" --argjson p "$payload" '
    .stageCheckpoint = (.stageCheckpoint // {})
    | .stageCheckpoint[$n] = $p
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "checkpoint: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_pipeline_session_add() {
  # Append a (sessionId, launchedAt, source) record to .pipelineSessions[].
  # Idempotent: if sessionId is already present, the entry is left as-is and
  # the subcommand returns 0. Consumed by pipeline-cost-block.sh at Stage 9
  # to attribute OTel metrics across all sessions that contributed to the run.
  #
  # TERMINAL-GUARD EXEMPTION (#154): deliberately NOT routed through
  # require_mutable, unlike the six stage-mutators. A post-terminal append is a
  # legitimate, documented operation — cost-tracking-setup.md describes a manual
  # backfill (`statectl pipeline-session-add <issue> --session-id <uuid>`) run
  # AFTER a completed run when cost attribution was skipped. Guarding it would
  # force a --force on a routine recovery command. It is the one mutating
  # subcommand with a real post-terminal use, so it stays freely mutable.
  #
  # Usage:
  #   statectl pipeline-session-add <issue-number> --session-id <id> [--source <s>]
  # where source ∈ {interactive} (or empty → null). The pipeline only ever emits
  # `interactive`; the value is recorded for OTel attribution, not branched on.
  local key="${1:-}"; shift || true
  local sid="" source=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) sid="${2:-}"; shift 2 ;;
      --source)     source="${2:-}"; shift 2 ;;
      *) EXIT_CODE=3 die "pipeline-session-add: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$sid" ]] || { EXIT_CODE=3 die "pipeline-session-add: missing <issue-number> or --session-id"; }
  # Shape check: the id must be a native Claude Code session UUID (8-4-4-4-12 hex),
  # which is exactly the form the OTel exporter emits as `session.id`. Anything else
  # (an unexpanded "$VAR", an empty string, or a synthetic non-UUID string) can never
  # match a collector datapoint, so the cost block would silently skip — reject it here
  # at record time instead.
  [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
    || { EXIT_CODE=1 die "pipeline-session-add: --session-id '$sid' is not a native session UUID (8-4-4-4-12 hex, as emitted by the OTel collector as session.id)"; }
  case "$source" in
    ""|interactive) ;;
    *) EXIT_CODE=1 die "pipeline-session-add: --source must be 'interactive' (or empty), got '$source'" ;;
  esac
  local current
  current=$(read_state "$key") || exit $?
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg sid "$sid" --arg src "$source" --arg now "$now" '
    (.pipelineSessions // []) as $existing
    | if any($existing[]; .sessionId == $sid)
      then .  # idempotent — sessionId already recorded
      else .pipelineSessions = ($existing + [
             { sessionId: $sid,
               launchedAt: $now,
               source: (if $src == "" then null else $src end) }
           ])
      end
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "pipeline-session-add: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_verify_attempts() {
  # Increment the Stage-6 retry counter for a failure class. verifyAttempts is a
  # map {class -> count} and is the one field written MID-stage (incremented on
  # each fix attempt) rather than at a stage boundary. Creates the class at 1 on
  # first use; does not cap (the per-class budget + circuit-breaker logic live in
  # Stage 6). Prints the new count to stdout so the caller can compare it against
  # the retry budget.
  #
  # Usage:
  #   statectl verify-attempts <issue-number> --incr <FAILURE_CLASS>
  # where FAILURE_CLASS ∈ {FORMAT, LINT_AUTOFIX, TYPE_ERROR, TEST_FAILURE,
  # PLAN_CMD_FAILURE, INFRA} (the Stage-6 failure-classification table). The
  # four suite classes are charged EXCLUSIVELY by verifyctl.sh (its sidecar
  # owns fix-attempt detection); PLAN_CMD_FAILURE (plan-specific verification
  # commands) is the in-session carve-out. Hand-authored enum, deliberately NOT
  # in the gen-statectl-validators generated set (it is a command-classification
  # vocabulary, not a state-schema closed enum).
  local key="${1:-}"; shift || true
  local cls="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --incr) cls="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "verify-attempts: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$cls" ]] || { EXIT_CODE=3 die "verify-attempts: missing <issue-number> or --incr <FAILURE_CLASS>"; }
  case "$cls" in
    FORMAT|LINT_AUTOFIX|TYPE_ERROR|TEST_FAILURE|PLAN_CMD_FAILURE|INFRA) ;;
    *) EXIT_CODE=1 die "verify-attempts: --incr must be one of {FORMAT, LINT_AUTOFIX, TYPE_ERROR, TEST_FAILURE, PLAN_CMD_FAILURE, INFRA}, got '$cls'" ;;
  esac
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "verify-attempts"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg cls "$cls" --arg now "$now" '
    .verifyAttempts = ((.verifyAttempts // {}) | .[$cls] = ((.[$cls] // 0) + 1))
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "verify-attempts: jq mutation failed"; }
  atomic_write "$key" "$new_state"
  # Echo the new count for the caller's per-class budget comparison.
  jq -r --arg cls "$cls" '.verifyAttempts[$cls]' <<< "$new_state"
}

cmd_slice_set() {
  # Persist the five stacked-PR slice fields atomically. Called at Stage 1
  # (initial seed from derivation) and at the start of each slice iteration.
  # currentSlice is authoritative on resume (see state-schema.md precedence
  # rule); this subcommand is the only writer.
  #
  # Usage:
  #   statectl slice-set <issue-number> --current N --branch <sliceBranch> \
  #     [--prior-branch <priorSliceBranch>] --worktree-base <ref> --pr-base <ref>
  local key="${1:-}"; shift || true
  local current="" branch="" prior="" wbase="" pbase=""
  local prior_set=0 force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --current)        current="${2:-}"; shift 2 ;;
      --branch)         branch="${2:-}"; shift 2 ;;
      --prior-branch)   prior="${2:-}"; prior_set=1; shift 2 ;;
      --worktree-base)  wbase="${2:-}"; shift 2 ;;
      --pr-base)        pbase="${2:-}"; shift 2 ;;
      --force)          force=1; shift ;;
      *) EXIT_CODE=3 die "slice-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$current" && -n "$branch" && -n "$wbase" && -n "$pbase" ]] \
    || { EXIT_CODE=3 die "slice-set: missing <issue-number> or required flag (--current --branch --worktree-base --pr-base)"; }
  [[ "$current" =~ ^[1-9][0-9]*$ ]] \
    || { EXIT_CODE=1 die "slice-set: --current must be a positive integer, got '$current'"; }
  # Slice 1 ⇒ prior-branch must be unset/empty; slice N>1 ⇒ prior-branch must be set.
  if [[ "$current" -eq 1 ]]; then
    [[ "$prior_set" -eq 0 || -z "$prior" ]] \
      || { EXIT_CODE=1 die "slice-set: --prior-branch must be omitted when --current is 1 (got '$prior')"; }
  else
    [[ -n "$prior" ]] \
      || { EXIT_CODE=1 die "slice-set: --prior-branch required when --current > 1 (got slice $current)"; }
  fi
  local current_state
  current_state=$(read_state "$key") || exit $?
  require_mutable "$current_state" "$force" "slice-set"
  local now
  now=$(now_iso)
  local prior_json
  if [[ -n "$prior" ]]; then
    prior_json=$(jq -nc --arg p "$prior" '$p')
  else
    prior_json='null'
  fi
  local new_state
  new_state=$(jq --argjson c "$current" --arg b "$branch" --argjson pb "$prior_json" \
                 --arg wbase "$wbase" --arg pbase "$pbase" --arg now "$now" '
    .currentSlice     = $c
    | .sliceBranch    = $b
    | .priorSliceBranch = $pb
    | .worktreeBase   = $wbase
    | .prBase         = $pbase
    | .lastUpdatedAt  = $now
  ' <<< "$current_state") || { EXIT_CODE=2 die "slice-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_worktree_set() {
  # Persist the Stage 2 boundary fields atomically. ORDERING CONTRACT: this
  # call MUST precede `set-stage 2 --status completed`, so a completed Stage 2
  # always implies worktreePath/branch are present — closing the crash window
  # the Stage 8 resume entry asserts on (see state-schema.md "Worktree").
  # Stacked-PR mode overwrites both fields per slice by design.
  #
  # Usage:
  #   statectl worktree-set <issue-number> --path <worktreePath> --branch <branch>
  local key="${1:-}"; shift || true
  local path="" branch="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)   path="${2:-}"; shift 2 ;;
      --branch) branch="${2:-}"; shift 2 ;;
      --force)  force=1; shift ;;
      *) EXIT_CODE=3 die "worktree-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$path" && -n "$branch" ]] \
    || { EXIT_CODE=3 die "worktree-set: missing <issue-number>, --path, or --branch"; }
  # Canonical form is repo-relative (see state-schema.md "Worktree"): the pipeline
  # always operates from repo root, so every consumer resolves worktreePath against
  # it. Reject an absolute path (leading '/') so the schema↔behavior drift this guard
  # was added for (issue #152) cannot silently return. Checked after the missing-arg
  # guard and before read_state — pure arg-shape validation (EXIT_CODE=3).
  [[ "$path" != /* ]] \
    || { EXIT_CODE=3 die "worktree-set: --path must be repo-relative (no leading '/'): '$path'"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "worktree-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg p "$path" --arg b "$branch" --arg now "$now" '
    .worktreePath = $p
    | .branch = $b
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "worktree-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_pr_add() {
  # Record a PR URL under .prs[branch] atomically. Same ordering contract as
  # worktree-set: MUST precede `set-stage 9 --status completed`. Re-running
  # for the same branch overwrites the URL (idempotent for retries); distinct
  # branches accumulate (one entry per slice in stacked-PR runs). Consumed by
  # pipeline-cost-block.sh to know which PRs to amend.
  #
  # Usage:
  #   statectl pr-add <issue-number> --branch <branch> --url <pr-url>
  local key="${1:-}"; shift || true
  local branch="" url="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="${2:-}"; shift 2 ;;
      --url)    url="${2:-}"; shift 2 ;;
      --force)  force=1; shift ;;
      *) EXIT_CODE=3 die "pr-add: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$branch" && -n "$url" ]] \
    || { EXIT_CODE=3 die "pr-add: missing <issue-number>, --branch, or --url"; }
  # Loose shape check: a non-https value here can never be a PR URL the cost
  # block (or a human) can follow — reject at record time, mirroring the
  # fail-at-write posture of pipeline-session-add's UUID check.
  [[ "$url" =~ ^https:// ]] \
    || { EXIT_CODE=1 die "pr-add: --url must start with https:// (got '$url')"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "pr-add"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg b "$branch" --arg u "$url" --arg now "$now" '
    .prs = (.prs // {})
    | .prs[$b] = { url: $u }
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "pr-add: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_review_rounds() {
  # Persist the Stage 8 review counters atomically. `--set` is mandatory on
  # every write (clean path and exhaustion path both record the round count);
  # `--exhausted` additionally writes codeReviewExhausted=true in the same
  # bundle. ADDITIVE-ONLY: this subcommand never writes
  # codeReviewExhausted:false — the field defaults to false at init, and a
  # later plain `--set N` leaves a previously-set true intact (exhaustion is
  # a terminal marker for the run; resume logic depends on it surviving).
  # Re-running --set overwrites the round count (idempotent for retries,
  # mirroring pr-add's URL overwrite).
  #
  # Usage:
  #   statectl review-rounds <issue-number> --set <1-3> [--exhausted]
  local key="${1:-}"; shift || true
  local rounds="" exhausted="false" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --set)       rounds="${2:-}"; shift 2 ;;
      --exhausted) exhausted="true"; shift ;;
      --force)     force=1; shift ;;
      *) EXIT_CODE=3 die "review-rounds: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$rounds" ]] \
    || { EXIT_CODE=3 die "review-rounds: missing <issue-number> or --set"; }
  # Inline numeric range guard (like slice-set's positive-integer check) —
  # NOT a generated closed-enum validator; the round budget lives in Stage 8.
  [[ "$rounds" =~ ^[1-3]$ ]] \
    || { EXIT_CODE=1 die "review-rounds: --set must be 1, 2, or 3 (got '$rounds')"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "review-rounds"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --argjson n "$rounds" --argjson exhausted "$exhausted" --arg now "$now" '
    .codeReviewRounds = $n
    | (if $exhausted then .codeReviewExhausted = true else . end)
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "review-rounds: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_pause_add() {
  # Append one CLOSED pause span to .pauseSpans[] at a crash-recovery resume.
  # A pause is the idle gap between a dying session's last state write and the
  # resuming session's first write (e.g. session-quota exhaustion → resume hours
  # later). There is no explicit pause event in the autonomous flow; instead one
  # closed span is recorded at each resume.
  #
  # SELF-ANCHORING: reads `from` = current .lastUpdatedAt (the dying session's
  # final write, still intact), stamps `to` = now. There is deliberately NO
  # --from arg — the subcommand IS the capture, so the "read `from` before it is
  # overwritten" footgun cannot occur. This is why pause-add MUST be the FIRST
  # state write on resume, before set-stage / pipeline-session-add (both bump
  # .lastUpdatedAt and would zero the anchor).
  #
  # `--reason` is a FREE STRING (sole value today: session-resume) — informational
  # only, NOT a generated closed enum (like pipelineSessions[].source), so it
  # stays off the gen-statectl-validators.sh drift contract.
  #
  # GUARDED via require_mutable (a pause is always mid-run); --force escape for
  # #154 consistency. NOT exempt like pipeline-session-add.
  #
  # Usage:
  #   statectl pause-add <issue-number> --reason <r> [--force]
  local key="${1:-}"; shift || true
  local reason="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --force)  force=1; shift ;;
      *) EXIT_CODE=3 die "pause-add: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$reason" ]] \
    || { EXIT_CODE=3 die "pause-add: missing <issue-number> or --reason"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "pause-add"
  local from now
  from=$(jq -r '.lastUpdatedAt // empty' <<< "$current")
  [[ -n "$from" ]] \
    || { EXIT_CODE=1 die "pause-add: state has no .lastUpdatedAt to anchor the pause span"; }
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg from "$from" --arg to "$now" --arg reason "$reason" '
    .pauseSpans = ((.pauseSpans // []) + [ { from: $from, to: $to, reason: $reason } ])
    | .lastUpdatedAt = $to
  ' <<< "$current") || { EXIT_CODE=2 die "pause-add: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_deviations_add() {
  # Append one kind-validated deviation to stageCheckpoint["7"].deviations[].
  # SINGLE LEDGER: the Stage-7 checkpoint writes deviations[] at Stage 7
  # (build-checkpoint-7 / cmd_checkpoint); Stage 8 review-fixes APPEND here so
  # retro and Stage-8 consumers read one array — there is no stageCheckpoint["8"]
  # deviations slot. Reuses valid_deviation_kind directly (it is a free-standing
  # validator, NOT gated on stage 7 the way validate_stage7_payload is), so a
  # Stage-8 deviation gets the same closed-enum kind check. APPEND-ONLY: never
  # rewrites or removes existing entries.
  #
  # Requires stageCheckpoint["7"] to already exist (Stage 8 always follows Stage
  # 7); erroring otherwise prevents a malformed checkpoint from being conjured.
  #
  # Usage:
  #   statectl deviations-add <issue-number> --kind <kind> --note <s> \
  #     [--plan-section <s>] [--file <f>] [--line <n>] [--stage <N>] [--force]
  local key="${1:-}"; shift || true
  local kind="" note="" plan_section="" file="" line="" stage="8" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)         kind="${2:-}"; shift 2 ;;
      --note)         note="${2:-}"; shift 2 ;;
      --plan-section) plan_section="${2:-}"; shift 2 ;;
      --file)         file="${2:-}"; shift 2 ;;
      --line)         line="${2:-}"; shift 2 ;;
      --stage)        stage="${2:-}"; shift 2 ;;
      --force)        force=1; shift ;;
      *) EXIT_CODE=3 die "deviations-add: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$kind" && -n "$note" ]] \
    || { EXIT_CODE=3 die "deviations-add: missing <issue-number>, --kind, or --note"; }
  valid_deviation_kind "$kind" \
    || { EXIT_CODE=1 die "deviations-add: invalid --kind '$kind' (allowed: scope-creep, alternate-approach, deferred, surprise)"; }
  [[ "$stage" =~ ^[1-9]$ ]] \
    || { EXIT_CODE=1 die "deviations-add: --stage must be in {1..9} (got '$stage')"; }
  if [[ -n "$line" ]]; then
    [[ "$line" =~ ^[0-9]+$ ]] \
      || { EXIT_CODE=1 die "deviations-add: --line must be a non-negative integer (got '$line')"; }
  fi
  local current
  current=$(read_state "$key") || exit $?
  # Terminal-state guard (shared with the other stage-mutators, #154): a
  # review-fix deviation belongs to an active run, not a post-terminal backfill.
  require_mutable "$current" "$force" "deviations-add"
  # Stage-7 checkpoint must exist — deviations[] lives under stageCheckpoint["7"].
  local has7
  has7=$(jq -r '(.stageCheckpoint // {}) | has("7")' <<< "$current")
  [[ "$has7" == "true" ]] \
    || { EXIT_CODE=1 die "deviations-add: stageCheckpoint[\"7\"] absent — write the Stage 7 checkpoint before appending deviations"; }
  local now
  now=$(now_iso)
  # Build the deviation object; omit empty optional fields. introducedAtStage
  # distinguishes a Stage-8 review-fix deviation from the Stage-7 originals.
  local dev
  dev=$(jq -n \
    --arg kind "$kind" --arg note "$note" \
    --arg ps "$plan_section" --arg file "$file" --arg line "$line" \
    --argjson stage "$stage" '
      {kind: $kind, note: $note, introducedAtStage: $stage}
      | (if $ps   != "" then .planSection = $ps        else . end)
      | (if $file != "" then .file = $file             else . end)
      | (if $line != "" then .line = ($line | tonumber) else . end)
    ') || { EXIT_CODE=2 die "deviations-add: jq object build failed"; }
  local new_state
  new_state=$(jq --argjson dev "$dev" --arg now "$now" '
    .stageCheckpoint["7"].deviations = ((.stageCheckpoint["7"].deviations // []) + [$dev])
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "deviations-add: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_intake_brief() {
  # Persist the Stage-1 intent snapshot: the Product-Essence Brief pointer
  # (nullable) and the acceptanceCriteria[] snapshot derived from the fetched
  # issue body. The snapshot is immune to later issue edits — run-authoritative
  # for plan-lint and pipeline-retro. See state-schema.md "Intake intent snapshot".
  #
  # Usage:
  #   statectl intake-brief <issue-number> --brief-path <path|null> --acceptance-criteria '<json-array>'
  local key="" brief_path="" ac_json="" brief_set=0 ac_set=0
  key="${1:-}"; shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brief-path) brief_path="${2:-}"; brief_set=1; shift 2 || { EXIT_CODE=3 die "intake-brief: --brief-path needs a value (path or 'null')"; } ;;
      --acceptance-criteria) ac_json="${2:-}"; ac_set=1; shift 2 || { EXIT_CODE=3 die "intake-brief: --acceptance-criteria needs a value"; } ;;
      *) EXIT_CODE=3 die "intake-brief: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && "$brief_set" -eq 1 && "$ac_set" -eq 1 ]] \
    || { EXIT_CODE=3 die "intake-brief: usage: intake-brief <issue-number> --brief-path <path|null> --acceptance-criteria '<json-array>'"; }
  [[ "$brief_path" == "null" || -n "$brief_path" ]] \
    || { EXIT_CODE=3 die "intake-brief: --brief-path must be a non-empty path or the literal 'null'"; }
  jq -e 'type == "array"' <<< "$ac_json" >/dev/null 2>&1 \
    || { EXIT_CODE=3 die "intake-brief: --acceptance-criteria must be a JSON array"; }
  local bad
  bad=$(jq -r '[.[] | select((.id // "") | test("^AC-[0-9]+$") | not)] | length' <<< "$ac_json")
  [[ "$bad" == "0" ]] || { EXIT_CODE=3 die "intake-brief: every acceptanceCriteria[].id must match ^AC-[0-9]+\$"; }
  bad=$(jq -r '[.[] | select((.text | type) != "string" or .text == "")] | length' <<< "$ac_json")
  [[ "$bad" == "0" ]] || { EXIT_CODE=3 die "intake-brief: every acceptanceCriteria[].text must be a non-empty string"; }
  # NB: plain `.negative | type` — `.negative // null` would coerce a legitimate
  # `false` to null (jq's // treats false as empty) and reject it.
  bad=$(jq -r '[.[] | select((.negative | type) != "boolean")] | length' <<< "$ac_json")
  [[ "$bad" == "0" ]] || { EXIT_CODE=3 die "intake-brief: every acceptanceCriteria[].negative must be a boolean"; }
  bad=$(jq -r '[.[] | select(.source != "explicit" and .source != "derived")] | length' <<< "$ac_json")
  [[ "$bad" == "0" ]] || { EXIT_CODE=3 die "intake-brief: every acceptanceCriteria[].source must be \"explicit\" or \"derived\""; }
  bad=$(jq -r '(map(.id) | length) - (map(.id) | unique | length)' <<< "$ac_json")
  [[ "$bad" == "0" ]] || { EXIT_CODE=3 die "intake-brief: acceptanceCriteria[].id values must be unique"; }
  local current
  current=$(read_state "$key") || exit $?
  local top_status
  top_status=$(jq -r '.status // ""' <<< "$current")
  # Terminal-state guard (mirrors verify-attempts): no intent snapshot after the
  # run goes terminal.
  [[ "$top_status" == "in_progress" || "$top_status" == "" ]] \
    || { EXIT_CODE=1 die "intake-brief: status is '$top_status', cannot mutate a terminal state"; }
  local now
  now=$(now_iso)
  local new_state
  if [[ "$brief_path" == "null" ]]; then
    new_state=$(jq --argjson ac "$ac_json" --arg now "$now" '
      .briefPath = null | .acceptanceCriteria = $ac | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "intake-brief: jq mutation failed"; }
  else
    new_state=$(jq --arg bp "$brief_path" --argjson ac "$ac_json" --arg now "$now" '
      .briefPath = $bp | .acceptanceCriteria = $ac | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "intake-brief: jq mutation failed"; }
  fi
  atomic_write "$key" "$new_state"
  jq -r '.acceptanceCriteria | length' <<< "$new_state"
}

cmd_plan_review_set() {
  # Persist the Stage-4 consolidated plan-review verdict as completion evidence
  # (the pipeline bans raw-jq state writes). ORDERING CONTRACT: call BEFORE
  # `set-stage 4 --status completed` — the Stage-4 completion precondition
  # refuses without it. Only non-blocking verdicts are recordable: `block`,
  # `infra`, and `budget-skipped` never reach a completion write (block →
  # mark-failed; infra/budget → stop without closing the stage).
  #
  # Usage:
  #   statectl plan-review-set <issue-number> --overall <pass|fix-and-go>
  local key="${1:-}"; shift || true
  local overall="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --overall) overall="${2:-}"; shift 2 ;;
      --force)   force=1; shift ;;
      *) EXIT_CODE=3 die "plan-review-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$overall" ]] \
    || { EXIT_CODE=3 die "plan-review-set: missing <issue-number> or --overall"; }
  case "$overall" in
    pass|fix-and-go) ;;
    *) EXIT_CODE=1 die "plan-review-set: --overall must be pass|fix-and-go (block/infra/budget-skipped never reach a completion write), got '$overall'" ;;
  esac
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "plan-review-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg o "$overall" --arg now "$now" '
    .stages["4"] = (.stages["4"] // {})
    | .stages["4"].planReview = { overall: $o }
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "plan-review-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_verify_summary_set() {
  # Persist the Stage-6 verify summary (top-level .verifySummary) from the
  # verifyctl verdict JSON — an object on the SUITE lane, the skipped-string on
  # the INERT lane. This top-level field is the persisted source of truth:
  # the Stage-6 completion precondition reads it, and Stage 7 sources its
  # build-checkpoint-7 --verify-summary copy from it (crash-recovery safe).
  # ORDERING CONTRACT: call BEFORE `set-stage 6 --status completed`.
  #
  # Usage:
  #   statectl verify-summary-set <issue-number> --json <verifySummary>
  local key="${1:-}"; shift || true
  local payload="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  payload="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "verify-summary-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$payload" ]] \
    || { EXIT_CODE=3 die "verify-summary-set: missing <issue-number> or --json"; }
  jq '.' <<< "$payload" >/dev/null 2>&1 || die "verify-summary-set: --json payload is not valid JSON"
  # Light shape check: object (SUITE lane) or non-empty string (INERT lane).
  jq -e '(type == "object") or (type == "string" and length > 0)' <<< "$payload" >/dev/null \
    || { EXIT_CODE=1 die "verify-summary-set: --json must be an object or a non-empty string (got: $(head -c 80 <<< "$payload"))"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "verify-summary-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --argjson p "$payload" --arg now "$now" '
    .verifySummary = $p
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "verify-summary-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_quality_pass_set() {
  # Persist the Stage-6 advisory quality-pass bookkeeping (stages.6.qualityPass)
  # — the pipeline bans raw-jq state writes, so the whole object routes through here
  # (deliberate divergence from an earlier fork, which left this field
  # raw-jq). Validates the two load-bearing fields (runId for the once-per-run
  # guard, status for the resume rule); the rest (outcome, commitSha, applied[],
  # suggestions[]) passes through — advisory bookkeeping, not a closed enum.
  #
  # Usage:
  #   statectl quality-pass-set <issue-number> --json <payload>
  local key="${1:-}"; shift || true
  local payload="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  payload="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "quality-pass-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$payload" ]] \
    || { EXIT_CODE=3 die "quality-pass-set: missing <issue-number> or --json"; }
  jq '.' <<< "$payload" >/dev/null 2>&1 || die "quality-pass-set: --json payload is not valid JSON"
  jq -e '(.runId | type == "string" and length > 0)' <<< "$payload" >/dev/null \
    || { EXIT_CODE=1 die "quality-pass-set: payload .runId must be a non-empty string (the once-per-run guard anchor)"; }
  jq -e '.status == "running" or .status == "completed"' <<< "$payload" >/dev/null \
    || { EXIT_CODE=1 die "quality-pass-set: payload .status must be running|completed"; }
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "quality-pass-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --argjson p "$payload" --arg now "$now" '
    .stages["6"] = (.stages["6"] // {})
    | .stages["6"].qualityPass = $p
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "quality-pass-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_mark_failed() {
  local key="${1:-}"; shift || true
  local reason="" stage="" details="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --stage)  stage="${2:-}"; shift 2 ;;
      --json)   details="${2:-}"; shift 2 ;;
      --force)  force=1; shift ;;
      *) EXIT_CODE=3 die "mark-failed: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$reason" ]] || { EXIT_CODE=3 die "mark-failed: missing <issue-number> or --reason"; }
  valid_failure_reason "$reason" \
    || { EXIT_CODE=1 die "mark-failed: invalid --reason '$reason' (see state-schema.md \`### failureContext.reason index\`)"; }
  if [[ -n "$stage" ]]; then
    [[ "$stage" =~ ^[1-9]$ ]] || { EXIT_CODE=1 die "mark-failed: --stage must be in {1..9} if given (omit for pre-Stage-1 failures)"; }
  fi
  if [[ -n "$details" ]]; then
    jq '.' <<< "$details" >/dev/null 2>&1 || die "mark-failed: --json details is not valid JSON"
  fi

  local current
  current=$(read_state "$key") || exit $?
  # Terminal-state guard (shared): refuse to mutate completed/failed without --force.
  require_mutable "$current" "$force" "mark-failed"

  # Determine the stage to record: --stage > currentStage > omit
  local effective_stage="$stage"
  if [[ -z "$effective_stage" ]]; then
    local cur
    cur=$(jq -r '.currentStage // ""' <<< "$current")
    if [[ -n "$cur" && "$cur" != "null" ]]; then
      effective_stage="$cur"
    fi
  fi

  local now
  now=$(now_iso)
  # Plain assignment, not ${details:-{\}}: bash 3.2 (macOS /bin/bash) keeps the
  # backslash in that brace-default expansion, producing the invalid JSON `{\}`
  # and breaking every mark-failed call that omits --json.
  local details_json="$details"
  [[ -n "$details_json" ]] || details_json='{}'
  local new_state
  if [[ -n "$effective_stage" ]]; then
    new_state=$(jq --arg n "$effective_stage" --arg reason "$reason" --arg now "$now" --argjson details "$details_json" '
      .status = "failed"
      | .failureContext = ($details + { stage: ($n | tonumber), reason: $reason })
      | .stages = (.stages // {})
      | .stages[$n] = (.stages[$n] // {})
      | .stages[$n].status = "failed"
      | .stages[$n].completedAt = $now
      | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "mark-failed: jq mutation failed"; }
  else
    # Pre-Stage-1 failure: omit failureContext.stage; no stages.N writes
    new_state=$(jq --arg reason "$reason" --arg now "$now" --argjson details "$details_json" '
      .status = "failed"
      | .failureContext = ($details + { reason: $reason })
      | .lastUpdatedAt = $now
    ' <<< "$current") || { EXIT_CODE=2 die "mark-failed: jq mutation failed"; }
  fi
  atomic_write "$key" "$new_state"
}

cmd_mark_completed() {
  # Terminal success write: status="completed" + lastUpdatedAt in one atomic
  # bundle. Owns the Stage 9 end-of-run write — previously the last prose-jq
  # site in the skill body (#151/#153). Mirrors mark-failed's terminal-state
  # guard: refuses to overwrite a completed/failed state without --force.
  # Additionally gates on all-stages completeness and the Post-Run Eval file
  # (imperative stage machine) — those gates are NOT bypassed by --force
  # (which only overrides the terminal-overwrite guard; a terminal state has
  # all stages done anyway).
  #
  # Usage:
  #   statectl mark-completed <issue-number> [--force]
  local key="${1:-}"; shift || true
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "mark-completed: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" ]] || { EXIT_CODE=3 die "mark-completed: missing <issue-number>"; }
  local current
  current=$(read_state "$key") || exit $?
  # Terminal-state guard (shared): refuse to mutate completed/failed without --force.
  require_mutable "$current" "$force" "mark-completed"

  # Completeness backstop (imperative stage machine): a run cannot reach terminal
  # `completed` unless every stage 1-9 was opened and closed. Order is guaranteed
  # by set-stage's per-transition guards; this closes the "terminated without
  # executing all stages" hole. NOT bypassed by --force. Stacked-PR runs call
  # mark-completed once, after the LAST slice (stages/9-open-pr.md).
  local incomplete
  incomplete=$(jq -r '(.stages // {}) as $s
    | [range(1; 10) | tostring | select((($s[.] // {}).status // "") != "completed")]
    | join(",")' <<< "$current")
  [[ -z "$incomplete" ]] \
    || { EXIT_CODE=1 die "mark-completed: stages [$incomplete] are not completed — every stage 1-9 must complete before the terminal write"; }

  # Post-Run Eval fail-closed gate: self-eval must exist and be plausible. NOT
  # bypassed by --force.
  require_eval_file "$key"

  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg now "$now" '
    .status = "completed"
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "mark-completed: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

# ---------------------------------------------------------------- builders ---
#
# Pure stdout builders. No state-file IO, no side effects beyond emitting
# validated JSON to stdout (or [statectl-error] + non-zero exit on rejection).
# Callers compose: `mark-failed --json "$(build-failure-context ...)"` or
# `checkpoint 7 --json "$(build-checkpoint-7 ...)"`. The consumers re-validate
# (defense in depth); the builders surface schema errors at the construction
# site rather than at write time.

# Parse one `key=value` argument, splitting on the FIRST `=` only. Echoes
# "<key>\t<value>" on stdout. Rejects empty key and missing `=`.
parse_kv_pair() {
  local raw="$1"
  [[ "$raw" == *=* ]] || die "expected key=value, got '$raw'"
  local k="${raw%%=*}"
  local v="${raw#*=}"
  [[ -n "$k" ]] || die "kv key must be non-empty (got '$raw')"
  printf '%s\t%s\n' "$k" "$v"
}

cmd_build_failure_context() {
  local reason="" stage=""
  # Collect kv triples as parallel arrays: keys[], types[] (str|num|lines), values[].
  local -a keys=() types=() values=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason)
        reason="${2:-}"
        shift 2 || { EXIT_CODE=3 die "build-failure-context: --reason missing value"; }
        ;;
      --stage)
        stage="${2:-}"
        shift 2 || { EXIT_CODE=3 die "build-failure-context: --stage missing value"; }
        ;;
      --kv|--kv-num|--kv-lines)
        local flag="$1"
        local raw="${2:-}"
        [[ -n "$raw" ]] || { EXIT_CODE=3 die "build-failure-context: $flag missing value"; }
        local pair
        pair=$(parse_kv_pair "$raw") || exit $?
        local k="${pair%%$'\t'*}"
        local v="${pair#*$'\t'}"
        # Duplicate-key rejection (across all --kv* flags)
        local existing
        for existing in "${keys[@]+"${keys[@]}"}"; do
          [[ "$existing" != "$k" ]] || { EXIT_CODE=1 die "build-failure-context: duplicate key '$k'"; }
        done
        local t
        case "$flag" in
          --kv)       t="str" ;;
          --kv-num)   t="num" ;;
          --kv-lines) t="lines" ;;
        esac
        keys+=("$k")
        types+=("$t")
        values+=("$v")
        shift 2
        ;;
      *)
        EXIT_CODE=3 die "build-failure-context: unrecognized argument: $1"
        ;;
    esac
  done
  [[ -n "$reason" ]] || { EXIT_CODE=3 die "build-failure-context: --reason required"; }
  valid_failure_reason "$reason" \
    || { EXIT_CODE=1 die "build-failure-context: invalid --reason '$reason' (see state-schema.md \`### failureContext.reason index\`)"; }
  if [[ -n "$stage" ]]; then
    [[ "$stage" =~ ^[1-9]$ ]] \
      || { EXIT_CODE=1 die "build-failure-context: --stage must be in {1..9} if given"; }
  fi

  # Assemble payload via jq -n. The base is {reason} or {reason, stage};
  # then fold each kv pair as a typed setter.
  local payload
  if [[ -n "$stage" ]]; then
    payload=$(jq -n --arg r "$reason" --argjson s "$stage" '{reason: $r, stage: $s}') \
      || { EXIT_CODE=2 die "build-failure-context: jq base assembly failed"; }
  else
    payload=$(jq -n --arg r "$reason" '{reason: $r}') \
      || { EXIT_CODE=2 die "build-failure-context: jq base assembly failed"; }
  fi

  local i k t v
  for i in "${!keys[@]}"; do
    k="${keys[$i]}"
    t="${types[$i]}"
    v="${values[$i]}"
    case "$t" in
      str)
        payload=$(jq --arg k "$k" --arg v "$v" '. + {($k): $v}' <<< "$payload") \
          || { EXIT_CODE=2 die "build-failure-context: jq merge failed for key '$k'"; }
        ;;
      num)
        # Validate value parses as JSON number before --argjson (which would
        # otherwise accept any valid JSON literal including strings).
        jq -e 'tonumber' <<< "$v" >/dev/null 2>&1 \
          || { EXIT_CODE=1 die "build-failure-context: --kv-num value for '$k' is not numeric (got '$v')"; }
        payload=$(jq --arg k "$k" --argjson v "$v" '. + {($k): $v}' <<< "$payload") \
          || { EXIT_CODE=2 die "build-failure-context: jq merge failed for key '$k'"; }
        ;;
      lines)
        # Bare split("\n"). Trailing newlines on the input are stripped by the
        # parse_kv_pair → command-substitution path before jq sees them, so
        # callers cannot produce a trailing-empty array element via this flag.
        payload=$(jq --arg k "$k" --arg v "$v" '. + {($k): ($v | split("\n"))}' <<< "$payload") \
          || { EXIT_CODE=2 die "build-failure-context: jq merge failed for key '$k'"; }
        ;;
    esac
  done

  printf '%s\n' "$payload"
}

cmd_build_checkpoint_7() {
  local issue="" branch="" head="" worktree=""
  local plan="" free_note="" docu=""
  local changed="" verify="" devs="" risks="" qps=""
  local plan_set=0 changed_set=0 verify_set=0 devs_set=0 risks_set=0 note_set=0 docu_set=0 qps_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue)                 issue="${2:-}";    shift 2 ;;
      --branch)                branch="${2:-}";   shift 2 ;;
      --head)                  head="${2:-}";     shift 2 ;;
      --worktree)              worktree="${2:-}"; shift 2 ;;
      --plan)                  plan="${2:-}";     plan_set=1;    shift 2 ;;
      --changed-files)         changed="${2:-}";  changed_set=1; shift 2 ;;
      --verify-summary)        verify="${2:-}";   verify_set=1;  shift 2 ;;
      --deviations)            devs="${2:-}";     devs_set=1;    shift 2 ;;
      --free-note)             free_note="${2:-}"; note_set=1;   shift 2 ;;
      --plan-risks)            risks="${2:-}";    risks_set=1;   shift 2 ;;
      --doc-updater-findings)  docu="${2:-}";     docu_set=1;    shift 2 ;;
      --quality-pass-summary)  qps="${2:-}";      qps_set=1;     shift 2 ;;
      *) EXIT_CODE=3 die "build-checkpoint-7: unrecognized argument: $1" ;;
    esac
  done
  [[ -n "$issue" && -n "$branch" && -n "$head" && -n "$worktree" ]] \
    || { EXIT_CODE=3 die "build-checkpoint-7: --issue, --branch, --head, --worktree are required"; }

  # JSON pass-through fields: validate that the input parses as JSON of the
  # expected top-level type. Empty defaults are filled with neutral values.
  local cf_json="[]" vs_json="{}" dv_json="[]" pr_json="[]"
  if [[ "$changed_set" -eq 1 ]]; then
    jq -e 'type == "array"' <<< "$changed" >/dev/null 2>&1 \
      || die "build-checkpoint-7: --changed-files must be a JSON array"
    cf_json="$changed"
  fi
  if [[ "$verify_set" -eq 1 ]]; then
    jq -e 'type == "object"' <<< "$verify" >/dev/null 2>&1 \
      || die "build-checkpoint-7: --verify-summary must be a JSON object"
    vs_json="$verify"
  fi
  if [[ "$devs_set" -eq 1 ]]; then
    jq -e 'type == "array"' <<< "$devs" >/dev/null 2>&1 \
      || die "build-checkpoint-7: --deviations must be a JSON array"
    dv_json="$devs"
  fi
  if [[ "$risks_set" -eq 1 ]]; then
    jq -e 'type == "array"' <<< "$risks" >/dev/null 2>&1 \
      || die "build-checkpoint-7: --plan-risks must be a JSON array"
    pr_json="$risks"
  fi
  # Quality-pass summary (Stage-6 advisory pass disclosure): optional JSON-object
  # passthrough, composed by Stage 7 FROM STATE (.stages."6".qualityPass) so a
  # fresh-session crash-recovery resume loses nothing. Defaults to {}.
  local qps_json="{}"
  if [[ "$qps_set" -eq 1 ]]; then
    jq -e 'type == "object"' <<< "$qps" >/dev/null 2>&1 \
      || die "build-checkpoint-7: --quality-pass-summary must be a JSON object"
    qps_json="$qps"
  fi

  # Lowercase issue to match state-file key convention used by validate_stage7_payload.
  local lower
  lower=$(echo "$issue" | tr '[:upper:]' '[:lower:]')

  # Base payload: required flat fields + always-present collection fields.
  local payload
  payload=$(jq -n \
      --arg issue "$lower" \
      --arg branch "$branch" \
      --arg head "$head" \
      --arg wt "$worktree" \
      --argjson changed "$cf_json" \
      --argjson verify "$vs_json" \
      --argjson devs "$dv_json" \
      --argjson risks "$pr_json" \
      --argjson qps "$qps_json" \
      '{
        ticketKey: $issue,
        branch: $branch,
        headSha: $head,
        worktreePath: $wt,
        changedFiles: $changed,
        verifySummary: $verify,
        deviations: $devs,
        planRisks: $risks,
        qualityPassSummary: $qps
      }') \
    || { EXIT_CODE=2 die "build-checkpoint-7: jq base assembly failed"; }

  # Optional string fields: emit only if the flag was given (or as empty string
  # for the two whose schema documents "" as the no-value sentinel).
  if [[ "$plan_set" -eq 1 ]]; then
    payload=$(jq --arg p "$plan" '. + {planPath: $p}' <<< "$payload") \
      || { EXIT_CODE=2 die "build-checkpoint-7: jq planPath merge failed"; }
  fi
  if [[ "$note_set" -eq 1 ]]; then
    payload=$(jq --arg n "$free_note" '. + {freeNote: $n}' <<< "$payload") \
      || { EXIT_CODE=2 die "build-checkpoint-7: jq freeNote merge failed"; }
  fi
  if [[ "$docu_set" -eq 1 ]]; then
    payload=$(jq --arg d "$docu" '. + {docUpdaterFindings: $d}' <<< "$payload") \
      || { EXIT_CODE=2 die "build-checkpoint-7: jq docUpdaterFindings merge failed"; }
  fi

  # Eager schema validation against the same function cmd_checkpoint uses on write.
  # Surfaces the error at construction time rather than at write time.
  validate_stage7_payload "$lower" "$payload"

  printf '%s\n' "$payload"
}

cmd_unit_test_surface_set() {
  # Persist the full unitTestSurface object at Stage 3 close (the pipeline bans raw-jq
  # state writes — see SKILL.md "Every load-bearing state write goes through statectl").
  # ORDERING CONTRACT: call BEFORE `set-stage 3 --status completed` so a completed
  # Stage 3 always implies the surface classification is present for Stage 4/5.
  #
  # Usage:
  #   statectl unit-test-surface-set <issue-number> --json <payload>
  local key="${1:-}"; shift || true
  local payload="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  payload="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "unit-test-surface-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$payload" ]] || { EXIT_CODE=3 die "unit-test-surface-set: missing <issue-number> --json <payload>"; }
  jq '.' <<< "$payload" >/dev/null 2>&1 || die "unit-test-surface-set: --json payload is not valid JSON"
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "unit-test-surface-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --argjson p "$payload" --arg now "$now" '
    .unitTestSurface = $p
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "unit-test-surface-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_mutation_audit_set() {
  # Persist the mutationReviewAudit object at Stage 5 (after the execute loop).
  # Shape: { executions[], mutationScore, finalDisposition }. Audit/output record,
  # consumed by pipeline-retro + the PR Review Notes; routed through statectl for
  # the same no-raw-jq invariant as every other structured write.
  #
  # Usage:
  #   statectl mutation-audit-set <issue-number> --json <payload>
  local key="${1:-}"; shift || true
  local payload="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  payload="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "mutation-audit-set: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" && -n "$payload" ]] || { EXIT_CODE=3 die "mutation-audit-set: missing <issue-number> --json <payload>"; }
  jq '.' <<< "$payload" >/dev/null 2>&1 || die "mutation-audit-set: --json payload is not valid JSON"
  local current
  current=$(read_state "$key") || exit $?
  require_mutable "$current" "$force" "mutation-audit-set"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --argjson p "$payload" --arg now "$now" '
    .mutationReviewAudit = $p
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "mutation-audit-set: jq mutation failed"; }
  atomic_write "$key" "$new_state"
}

cmd_stage_substatus() {
  # Write a mid-stage sub-status into `.stages.N.<key>`. the pipeline's FIRST stages.N.*
  # sub-status mechanism (no figmaPlanReview/apiTestImplement precedent here).
  # The (stage, key, value) triple is closed-enum hand-validated below — extend the
  # case as new sub-statuses are introduced. Replaces the legacy raw-jq sub-status
  # write, which the no-raw-jq invariant forbids.
  #
  # Usage:
  #   statectl stage-substatus <issue-number> --stage N --key <key> --value <value>
  local key_arg="${1:-}"; shift || true
  local n="" skey="" sval="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stage) n="${2:-}"; shift 2 ;;
      --key)   skey="${2:-}"; shift 2 ;;
      --value) sval="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) EXIT_CODE=3 die "stage-substatus: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key_arg" && -n "$n" && -n "$skey" && -n "$sval" ]] \
    || { EXIT_CODE=3 die "stage-substatus: missing <issue-number> --stage N --key <key> --value <value>"; }
  [[ "$n" =~ ^[1-9]$ ]] || { EXIT_CODE=1 die "stage-substatus: --stage must be in {1..9}, got '$n'"; }
  # Closed-enum validation of the (stage, key, value) triple. Hand-maintained (not
  # part of the gen-statectl-validators generated set).
  case "$n.$skey" in
    5.unitTestMutationReview)
      # `executing` is legacy (pre-mutation-gate.mjs state files) — still accepted
      # for read/resume compatibility; the sequencer flow writes reviewing|completed only.
      case "$sval" in
        reviewing|executing|completed) ;;
        *) EXIT_CODE=1 die "stage-substatus: stages.5.unitTestMutationReview value must be reviewing|executing|completed, got '$sval'" ;;
      esac
      ;;
    5.designPlanReview)
      case "$sval" in
        implementing|verifying|implemented) ;;
        *) EXIT_CODE=1 die "stage-substatus: stages.5.designPlanReview value must be implementing|verifying|implemented, got '$sval'" ;;
      esac
      ;;
    *) EXIT_CODE=1 die "stage-substatus: unsupported (stage,key) pair '$n.$skey'" ;;
  esac
  local current
  current=$(read_state "$key_arg") || exit $?
  require_mutable "$current" "$force" "stage-substatus"
  local now
  now=$(now_iso)
  local new_state
  new_state=$(jq --arg n "$n" --arg k "$skey" --arg v "$sval" --arg now "$now" '
    .stages[$n] = (.stages[$n] // {})
    | .stages[$n][$k] = $v
    | .lastUpdatedAt = $now
  ' <<< "$current") || { EXIT_CODE=2 die "stage-substatus: jq mutation failed"; }
  atomic_write "$key_arg" "$new_state"
}

# ---------------------------------------------------------------- dispatch ---

main() {
  # Eager validation of STATECTL_WRITER — catches typos even for read-only paths
  # like `init` on existing state where no write would otherwise occur.
  resolve_writer >/dev/null
  local subcmd="${1:-}"
  [[ -n "$subcmd" ]] || { EXIT_CODE=3 die "usage: statectl.sh <subcommand> <args>"; }
  shift
  case "$subcmd" in
    init)                   cmd_init "$@" ;;
    get)                    cmd_get "$@" ;;
    state-path)             cmd_state_path "$@" ;;
    set-stage)              cmd_set_stage "$@" ;;
    checkpoint)             cmd_checkpoint "$@" ;;
    worktree-set)           cmd_worktree_set "$@" ;;
    pr-add)                 cmd_pr_add "$@" ;;
    review-rounds)          cmd_review_rounds "$@" ;;
    pause-add)              cmd_pause_add "$@" ;;
    deviations-add)         cmd_deviations_add "$@" ;;
    verify-attempts)        cmd_verify_attempts "$@" ;;
    pipeline-session-add)   cmd_pipeline_session_add "$@" ;;
    slice-set)              cmd_slice_set "$@" ;;
    unit-test-surface-set)  cmd_unit_test_surface_set "$@" ;;
    mutation-audit-set)     cmd_mutation_audit_set "$@" ;;
    stage-substatus)        cmd_stage_substatus "$@" ;;
    intake-brief)           cmd_intake_brief "$@" ;;
    plan-review-set)        cmd_plan_review_set "$@" ;;
    verify-summary-set)     cmd_verify_summary_set "$@" ;;
    quality-pass-set)       cmd_quality_pass_set "$@" ;;
    mark-failed)            cmd_mark_failed "$@" ;;
    mark-completed)         cmd_mark_completed "$@" ;;
    build-failure-context)  cmd_build_failure_context "$@" ;;
    build-checkpoint-7)     cmd_build_checkpoint_7 "$@" ;;
    *) EXIT_CODE=3 die "unknown subcommand: '$subcmd'" ;;
  esac
}

main "$@"
