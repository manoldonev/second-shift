#!/usr/bin/env bash
# verifyctl.sh — deterministic Stage-6 verify runner for the dev-pipeline skill.
#
# Owns everything mechanical in stages/6-verify.md so `verifyAttempts` honesty
# stops depending on the LLM: lane derivation (INERT/SUITE via the canonical
# tools/is-inert-diff.sh classifier), prettier resolution, SUITE execution
# (config setup lanes / scoped format / configured lint & type-check & test
# concurrent), by-command failure classification, and — the drift-killer —
# the fix-attempt accounting: verifyctl detects a re-run after a failed run via
# its own sidecar and charges `statectl verify-attempts` itself, refusing to run
# when a class budget (2) is exhausted. The calling session's role shrinks to:
# invoke `run`, read the verdict JSON, fix the classified failures, re-invoke.
#
# Usage:
#   verifyctl.sh run <issue-number> [--no-attempt]
#
# Everything else is DERIVED from state / git, never passed — no override flags
# by design (every override is a re-opened honesty hole):
#   worktreePath   <- statectl get .worktreePath (repo-relative; resolved against
#                     the main checkout root via the git-common-dir idiom; an
#                     absolute value — e.g. a selftest fixture — passes through)
#   base ref       <- statectl get .worktreeBase (persisted by slice-set; covers
#                     stacked slices) // the config's host-repo baseBranch.
#                     Diffed via `git merge-base` so an advancing origin base
#                     cannot skew the lane.
#   INERT/SUITE    <- tools/is-inert-diff.sh over the merge-base diff (the
#                     single source of truth; default-to-SUITE on any non-match)
#
# Static context comes from the consumer repo's .claude/second-shift.config.json
# (override: SECOND_SHIFT_CONFIG): the host repo is the topology.repos entry
# with path ".", supplying baseBranch and the commands table (lint/typecheck/
# test — null means "lane not available", skipped; lintAutofixes gates the
# in-run `<lint> --fix` loop and requires the lint command to accept a --fix
# suffix; commands.lanes[] are setup steps run sequentially before the trio,
# INFRA-grade on failure — e.g. install / workspace-package builds). Scoped
# formatting assumes a prettier-based repo (the one toolchain assumption
# verifyctl keeps; all current consumers are prettier repos). Single-repo
# operation: no --repo flag, no per-repo sidecars, no integration lane.
#
# Attempt accounting (skipped entirely under --no-attempt):
#   Sidecar {state-dir}/{issue}-verify.json, owned EXCLUSIVELY by verifyctl:
#   { runId, headSha, chargedHead, at, failedClasses[], status }.
#   - Sidecar with runId != state .runId is discarded (self-cleans across
#     stacked slices and operator state clears).
#   - Prior status "fail" => this invocation is a fix-attempt re-run: each class
#     in failedClasses is charged via `statectl verify-attempts` — idempotently
#     per HEAD (charge only when HEAD != chargedHead; chargedHead is written
#     BEFORE the increment so a crash mid-charge under-charges, never
#     double-charges into premature budget exhaustion).
#   - A class already at budget (2) => verdict {"status":"budget-exhausted"},
#     exit 4, nothing runs, nothing increments.
#   - INFRA is never charged and never budget-refused (surface immediately).
#   --no-attempt: no budget check, no increment, no sidecar write — read-only
#   accounting posture, contracted for the quality pass's one-shot safety-net
#   re-verify ONLY.
#
# Class ownership: FORMAT / LINT_AUTOFIX / TYPE_ERROR / TEST_FAILURE are charged
# EXCLUSIVELY by verifyctl. PLAN_CMD_FAILURE (plan-specific verification
# commands) stays in-session — see stages/6-verify.md. INFRA is never charged.
#
# Output: one verdict JSON document on stdout. Full command output spools to
# {state-dir}/{issue}-verify.log (overwritten per run); the JSON carries only an
# 80-line tail per failure (token discipline). `verifySummary` is emitted
# ready-made for `statectl verify-summary-set` (both lanes) — the Stage-6
# completion precondition reads the top-level state field it writes.
#
# Exit codes: 0 pass | 1 fail | 2 internal | 3 usage | 4 budget-exhausted
#
# Helper-failure contract: errors print to stderr with `[verifyctl-error] `
# prefix and exit non-zero. verifyctl never writes state directly; its only
# state mutation is delegated to `statectl verify-attempts`.

set -uo pipefail

die() {
  echo "[verifyctl-error] $*" >&2
  exit "${EXIT_CODE:-2}"
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Sibling statectl + the canonical lane classifier, resolved next to this
# script (not CWD-relative).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATECTL="$SCRIPT_DIR/statectl.sh"
IS_INERT="$SCRIPT_DIR/tools/is-inert-diff.sh"
[[ -x "$STATECTL" ]] || { EXIT_CODE=2 die "statectl.sh not found/executable at $STATECTL"; }
[[ -f "$IS_INERT" ]] || { EXIT_CODE=2 die "tools/is-inert-diff.sh not found at $IS_INERT"; }

# Consumer-repo main-checkout root. CWD-anchored (worktree-safe via
# git-common-dir) — post-pluginization this script lives in the plugin
# checkout, NOT the consumer repo, so script-location anchoring would resolve
# to the wrong repo. The pipeline always invokes verifyctl from the consumer
# repo or one of its worktrees. Override: SECOND_SHIFT_REPO_ROOT (selftests).
main_root() {
  if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$SECOND_SHIFT_REPO_ROOT"
    return 0
  fi
  local common_dir
  if common_dir=$(git rev-parse --git-common-dir 2>/dev/null) \
     && common_dir=$(cd "$common_dir" 2>/dev/null && pwd); then
    printf '%s\n' "$(dirname "$common_dir")"
    return 0
  fi
  pwd
}

# Consumer config path (static context). Missing config is fatal for `run` —
# verifyctl cannot derive a command truth table.
config_path() {
  printf '%s\n' "${SECOND_SHIFT_CONFIG:-$(main_root)/.claude/second-shift.config.json}"
}

# State-dir resolution mirrors statectl's precedence: explicit override (the
# selftest fixtures), then the consumer root (config paths.pipelineStateDir
# when present), then cwd-relative fallback.
state_dir() {
  if [[ -n "${STATECTL_STATE_DIR:-}" ]]; then
    printf '%s\n' "$STATECTL_STATE_DIR"
    return 0
  fi
  local root cfg rel=".claude/pipeline-state"
  root=$(main_root)
  cfg=$(config_path)
  if [[ -f "$cfg" ]]; then
    rel=$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$cfg" 2>/dev/null) \
      || rel=".claude/pipeline-state"
  fi
  printf '%s\n' "$root/$rel"
}

# Load the host repo's static context into globals. Host repo = the
# topology.repos entry with path "." (the repo this config lives in).
# Command semantics: null/absent command => that lane is skipped (schema:
# "lane not available"); lanes[] are sequential setup steps (INFRA on failure).
load_config() {
  local cfg host
  cfg=$(config_path)
  [[ -f "$cfg" ]] \
    || { EXIT_CODE=2 die "run: no consumer config at $cfg (write .claude/second-shift.config.json — see second-shift docs/onboarding.md; selftest override: SECOND_SHIFT_CONFIG)"; }
  host=$(jq -r '.topology.repos | to_entries[] | select(.value.path == ".") | .key' "$cfg" 2>/dev/null | head -n1)
  [[ -n "$host" ]] \
    || { EXIT_CODE=2 die "run: config has no topology.repos entry with path \".\" ($cfg)"; }
  BASE_BRANCH=$(jq -r --arg h "$host" '.topology.repos[$h].baseBranch // empty' "$cfg")
  [[ -n "$BASE_BRANCH" ]] \
    || { EXIT_CODE=2 die "run: config topology.repos.$host.baseBranch missing ($cfg)"; }
  CMD_LINT=$(jq -r --arg h "$host" '.commands[$h].lint // empty' "$cfg")
  CMD_TYPECHECK=$(jq -r --arg h "$host" '.commands[$h].typecheck // empty' "$cfg")
  CMD_TEST=$(jq -r --arg h "$host" '.commands[$h].test // empty' "$cfg")
  LINT_AUTOFIXES=$(jq -r --arg h "$host" '.commands[$h].lintAutofixes // false' "$cfg")
  SETUP_LANES=$(jq -c --arg h "$host" '.commands[$h].lanes // []' "$cfg")
}

sget() { # $1 = issue, $2 = jq path — statectl get with error passthrough
  "$STATECTL" get "$1" "$2" || exit 2
}

# Resolve the prettier binary: the worktree's own install (SUITE lane installed
# it), then the main checkout's (INERT lane skipped install — the main checkout
# always has one; pipeline-doctor probes it), then a pinned npx fallback.
# Echoes an invocation prefix; caller appends file args.
resolve_prettier() { # $1 = worktree abs path
  local wt="$1" mr
  if [[ -x "$wt/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$wt/node_modules/.bin/prettier"
    return 0
  fi
  mr=$(main_root)
  if [[ -x "$mr/node_modules/.bin/prettier" ]]; then
    printf '%s\n' "$mr/node_modules/.bin/prettier"
    return 0
  fi
  # Pin from root package.json (strip range marker), default known-good.
  local pv
  pv=$(sed -n 's/.*"prettier": *"[~^]*\([0-9][0-9.]*\)".*/\1/p' "$mr/package.json" 2>/dev/null)
  printf 'npx --yes prettier@%s\n' "${pv:-3.7.4}"
}

# ---------------------------------------------------------------- run ---------

cmd_run() {
  local key="" no_attempt=0
  key="${1:-}"; shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-attempt) no_attempt=1; shift ;;
      *) EXIT_CODE=3 die "run: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" ]] \
    || { EXIT_CODE=3 die "usage: verifyctl.sh run <issue-number> [--no-attempt]"; }

  local key_lc
  key_lc=$(echo "$key" | tr '[:upper:]' '[:lower:]')

  # ---- static context (consumer config) ----
  load_config

  # ---- derive everything from state / git ----
  local wt run_id base_ref
  wt=$(sget "$key" '.worktreePath // ""')
  [[ -n "$wt" ]] || { EXIT_CODE=2 die "run: state has no .worktreePath (worktree-set not run?)"; }
  # Canonical form is repo-relative — resolve against the main checkout root.
  # An absolute value (selftest fixtures write one directly) passes through.
  [[ "$wt" == /* ]] || wt="$(main_root)/$wt"
  [[ -d "$wt" ]] || { EXIT_CODE=2 die "run: worktreePath does not resolve to a directory ('$wt')"; }
  run_id=$(sget "$key" '.runId // ""')
  [[ -n "$run_id" ]] || { EXIT_CODE=2 die "run: state has no .runId (statectl init not run?)"; }
  # Persisted by slice-set on stacked runs (priorSliceBranch for slice N>1);
  # absent on single-PR runs => the config's host-repo baseBranch. No
  # branch-name arithmetic — the persisted field is the source of truth.
  base_ref=$(sget "$key" '.worktreeBase // ""')
  [[ -n "$base_ref" ]] || base_ref="$BASE_BRANCH"

  # merge-base (immune to the base ref advancing under the worktree). Prefer the
  # origin/ ref; fall back to the local ref; neither resolvable => INFRA-grade.
  local merge_base
  merge_base=$(git -C "$wt" merge-base "origin/$base_ref" HEAD 2>/dev/null) \
    || merge_base=$(git -C "$wt" merge-base "$base_ref" HEAD 2>/dev/null) \
    || { EXIT_CODE=2 die "run: cannot resolve merge-base of '$base_ref' in $wt"; }
  local head_sha
  head_sha=$(git -C "$wt" rev-parse HEAD)

  # ---- changed files + lane (via the canonical classifier) ----
  local changed
  changed=$(git -C "$wt" diff --name-only "${merge_base}..HEAD")
  local lane="SUITE"
  if [[ -z "$changed" ]]; then
    lane="INERT"
  elif bash "$IS_INERT" <<< "$changed" >/dev/null; then
    lane="INERT"
  fi

  local sdir sidecar logfile
  sdir=$(state_dir)
  mkdir -p "$sdir"
  sidecar="$sdir/${key_lc}-verify.json"
  logfile="$sdir/${key_lc}-verify.log"

  # ---- attempt accounting (pre-run) ----
  local attempts_charged="{}"
  if [[ "$no_attempt" -ne 1 && -f "$sidecar" ]]; then
    local sc_run_id
    sc_run_id=$(jq -r '.runId // ""' "$sidecar" 2>/dev/null) || sc_run_id=""
    if [[ "$sc_run_id" != "$run_id" ]]; then
      rm -f "$sidecar"   # stale sidecar from a previous run/slice — discard
    else
      local sc_status sc_charged
      sc_status=$(jq -r '.status // ""' "$sidecar")
      sc_charged=$(jq -r '.chargedHead // ""' "$sidecar")
      if [[ "$sc_status" == "fail" && "$sc_charged" != "$head_sha" ]]; then
        # This invocation is a fix-attempt re-run. Budget-check every failed
        # class FIRST (refuse before charging), then charge idempotently.
        local classes
        classes=$(jq -r '.failedClasses[]? // empty' "$sidecar" | grep -v '^INFRA$' || true)
        local c count
        while IFS= read -r c; do
          [[ -z "$c" ]] && continue
          count=$(sget "$key" ".verifyAttempts.${c} // 0")
          if (( count >= 2 )); then
            jq -n --arg class "$c" --arg lane "$lane" \
                  --argjson attempts "$(sget "$key" ".verifyAttempts // {}")" '
              { lane: $lane, status: "budget-exhausted",
                class: $class, attempts: $attempts,
                note: "fix-attempt budget (2) exhausted for this class; surface to the user — do not retry" }'
            exit 4
          fi
        done <<< "$classes"
        # chargedHead is written BEFORE the increments: a crash mid-charge
        # under-charges (re-run sees chargedHead==HEAD and skips), never
        # double-charges.
        local tmp="${sidecar}.tmp"
        jq --arg h "$head_sha" '.chargedHead = $h' "$sidecar" > "$tmp" && mv "$tmp" "$sidecar" \
          || { EXIT_CODE=2 die "run: could not update sidecar $sidecar"; }
        while IFS= read -r c; do
          [[ -z "$c" ]] && continue
          "$STATECTL" verify-attempts "$key" --incr "$c" >/dev/null \
            || { EXIT_CODE=2 die "run: statectl verify-attempts --incr $c failed"; }
          attempts_charged=$(jq --arg c "$c" '.[$c] = ((.[$c] // 0) + 1)' <<< "$attempts_charged")
        done <<< "$classes"
      fi
    fi
  fi

  # ---- execute the lane ----
  : > "$logfile"
  local failures="[]" format_changed="[]" lint_autofixed="[]"
  local vs_format="clean" vs_lint="clean" vs_tsc="clean" vs_test="passed" vs_build="clean"
  local overall="pass"

  # Append one command's spooled output + record a failure entry.
  # $1=class $2=command-string $3=exit-code $4=output-file
  record_failure() {
    local class="$1" cmdstr="$2" ec="$3" outf="$4"
    local tail_txt
    tail_txt=$(tail -n 80 "$outf" 2>/dev/null || true)
    failures=$(jq --arg class "$class" --arg cmd "$cmdstr" --argjson ec "$ec" \
                  --arg tail "$tail_txt" --arg log "$logfile" \
                  '. + [{class: $class, command: $cmd, exitCode: $ec, outputTail: $tail, logFile: $log}]' <<< "$failures")
    overall="fail"
  }

  # Run one command, spooling output. Echoes rc. $1=label $2...=command
  run_cmd() {
    local label="$1"; shift
    local outf
    outf=$(mktemp)
    {
      echo "===== [$label] $* ($(now_iso)) ====="
    } >> "$logfile"
    "$@" > "$outf" 2>&1
    local rc=$?
    cat "$outf" >> "$logfile"
    echo "===== [$label] exit=$rc =====" >> "$logfile"
    RUN_CMD_OUT="$outf"
    return $rc
  }

  # INFRA detection: command not found / not executable.
  is_infra_rc() { [[ "$1" == "126" || "$1" == "127" ]]; }

  # Changed files matching the prettier format-glob *.{ts,tsx,js,json,md},
  # existing in the worktree. Populates the CHECK_FILES array.
  collect_format_files() {
    CHECK_FILES=()
    local f
    while IFS= read -r f; do
      case "$f" in
        *.ts|*.tsx|*.js|*.json|*.md) [[ -f "$wt/$f" ]] && CHECK_FILES+=("$f") ;;
      esac
    done <<< "$changed"
  }

  if [[ "$lane" == "INERT" ]]; then
    # Scoped prettier --check on changed format-glob files only (a
    # .claude/**/*.mjs-only diff has nothing to check — correct).
    collect_format_files
    if (( ${#CHECK_FILES[@]} > 0 )); then
      local prettier rc=0
      prettier=$(resolve_prettier "$wt")
      # shellcheck disable=SC2086 # resolve_prettier may echo an npx prefix
      ( cd "$wt" && $prettier --check "${CHECK_FILES[@]}" ) > "$logfile" 2>&1
      rc=$?
      if [[ "$rc" -ne 0 ]]; then
        if is_infra_rc "$rc"; then
          record_failure "INFRA" "prettier --check (inert lane)" "$rc" "$logfile"
        else
          record_failure "FORMAT" "prettier --check (inert lane)" "$rc" "$logfile"
          vs_format="failed"
        fi
      fi
    fi
    local vs_string="skipped (inert diff — no JS/TS surface)"
    [[ "$overall" == "fail" ]] && vs_string="inert prettier check failed"
    emit_verdict "$key" "$(build_verdict_ctx "$(jq -n --arg s "$vs_string" '$s')")"
  else
    # ---- SUITE lane ----
    local rc
    # 1. Setup lanes from the config (commands.<host>.lanes[]): sequential
    #    environment/build prerequisites — dependency install, workspace
    #    package builds — run BEFORE format/lint/type-check/test. A failure
    #    here is INFRA-grade (environment prerequisite — never a charged
    #    class); an error that survives setup is a real classified failure
    #    from step 3. Each lane: {name, cwd?, commands[]}, cwd relative to
    #    the worktree.
    local lane_count li lane_name lane_cwd lane_cmds lc_i lane_cmd lane_dir
    lane_count=$(jq 'length' <<< "$SETUP_LANES")
    for (( li=0; li<lane_count; li++ )); do
      [[ "$overall" == "pass" ]] || break
      lane_name=$(jq -r --argjson i "$li" '.[$i].name' <<< "$SETUP_LANES")
      lane_cwd=$(jq -r --argjson i "$li" '.[$i].cwd // ""' <<< "$SETUP_LANES")
      lane_dir="$wt${lane_cwd:+/$lane_cwd}"
      lane_cmds=$(jq -r --argjson i "$li" '(.[$i].commands // []) | length' <<< "$SETUP_LANES")
      for (( lc_i=0; lc_i<lane_cmds; lc_i++ )); do
        lane_cmd=$(jq -r --argjson i "$li" --argjson j "$lc_i" '.[$i].commands[$j]' <<< "$SETUP_LANES")
        run_cmd "setup:$lane_name" bash -c "cd \"$lane_dir\" && $lane_cmd"
        rc=$?
        if [[ "$rc" -ne 0 ]]; then
          record_failure "INFRA" "setup lane '$lane_name': $lane_cmd" "$rc" "$RUN_CMD_OUT"
          vs_build="failed"
          break
        fi
      done
    done

    # 2. Scoped format: prettier --write on the changed format-glob files only
    #    (never repo-wide; never .mjs — outside the format glob). Files it
    #    changed are reported in formatChanged[] for the caller's scoped commit.
    if [[ "$overall" == "pass" ]]; then
      collect_format_files
      if (( ${#CHECK_FILES[@]} > 0 )); then
        local prettier pre_format post_format
        prettier=$(resolve_prettier "$wt")
        pre_format=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
        local fmt_out
        fmt_out=$(mktemp)
        # shellcheck disable=SC2086
        ( cd "$wt" && $prettier --write "${CHECK_FILES[@]}" ) > "$fmt_out" 2>&1
        rc=$?
        { echo "===== [format] prettier --write (exit=$rc) ====="; cat "$fmt_out"; } >> "$logfile"
        if [[ "$rc" -ne 0 ]]; then
          if is_infra_rc "$rc"; then
            record_failure "INFRA" "prettier --write (scoped)" "$rc" "$fmt_out"
          else
            record_failure "FORMAT" "prettier --write (scoped)" "$rc" "$fmt_out"
            vs_format="failed"
          fi
        fi
        post_format=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
        format_changed=$(comm -13 <(echo "$pre_format") <(echo "$post_format") | jq -R . | jq -s 'map(select(length > 0))')
        [[ "$format_changed" != "[]" && "$vs_format" == "clean" ]] && vs_format="applied"
      fi
    fi

    # 3. lint & type-check & test — the configured commands, independent, run
    #    CONCURRENTLY (background jobs; collect all before classifying —
    #    mirrors the stage prose matrix). A null/absent command means the lane
    #    is not available in this repo (schema contract) — skipped, never
    #    classified.
    if [[ "$overall" == "pass" ]]; then
      local lint_out tsc_out test_out lint_rc=0 tsc_rc=0 test_rc=0 lint_pid="" tsc_pid="" test_pid=""
      lint_out=$(mktemp); tsc_out=$(mktemp); test_out=$(mktemp)
      if [[ -n "$CMD_LINT" ]]; then
        ( cd "$wt" && bash -c "$CMD_LINT" ) > "$lint_out" 2>&1 & lint_pid=$!
      else
        vs_lint="skipped"
      fi
      if [[ -n "$CMD_TYPECHECK" ]]; then
        ( cd "$wt" && bash -c "$CMD_TYPECHECK" ) > "$tsc_out" 2>&1 & tsc_pid=$!
      else
        vs_tsc="skipped"
      fi
      if [[ -n "$CMD_TEST" ]]; then
        ( cd "$wt" && bash -c "$CMD_TEST" ) > "$test_out" 2>&1 & test_pid=$!
      else
        vs_test="skipped"
      fi
      [[ -n "$lint_pid" ]] && { wait "$lint_pid"; lint_rc=$?; }
      [[ -n "$tsc_pid" ]] && { wait "$tsc_pid"; tsc_rc=$?; }
      [[ -n "$test_pid" ]] && { wait "$test_pid"; test_rc=$?; }
      { [[ -n "$lint_pid" ]] && echo "===== [lint] $CMD_LINT (exit=$lint_rc) =====" && cat "$lint_out";
        [[ -n "$tsc_pid" ]] && echo "===== [type-check] $CMD_TYPECHECK (exit=$tsc_rc) =====" && cat "$tsc_out";
        [[ -n "$test_pid" ]] && echo "===== [test] $CMD_TEST (exit=$test_rc) =====" && cat "$test_out";
        true; } >> "$logfile"

      if [[ -n "$tsc_pid" && "$tsc_rc" -ne 0 ]]; then
        if is_infra_rc "$tsc_rc"; then
          record_failure "INFRA" "$CMD_TYPECHECK" "$tsc_rc" "$tsc_out"
        else
          record_failure "TYPE_ERROR" "$CMD_TYPECHECK" "$tsc_rc" "$tsc_out"
          vs_tsc="failed"
        fi
      fi
      if [[ -n "$lint_pid" && "$lint_rc" -ne 0 ]]; then
        if is_infra_rc "$lint_rc"; then
          record_failure "INFRA" "$CMD_LINT" "$lint_rc" "$lint_out"
        elif [[ "$LINT_AUTOFIXES" != "true" ]]; then
          # Repo declares no autofixing lint — a lint failure is a residual
          # by definition (same charged class; no in-run fix loop to attempt).
          record_failure "LINT_AUTOFIX" "$CMD_LINT" "$lint_rc" "$lint_out"
          vs_lint="failed"
        else
          # Autofix once (convention: the configured lint command accepts a
          # --fix suffix when lintAutofixes is true); if it fully cleans the
          # lint, the fix loop happened in-run — verifyctl itself charges
          # LINT_AUTOFIX.
          local pre_fix post_fix recheck_rc
          pre_fix=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
          run_cmd "lint--fix" bash -c "cd \"$wt\" && $CMD_LINT --fix"
          post_fix=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
          lint_autofixed=$(comm -13 <(echo "$pre_fix") <(echo "$post_fix") | jq -R . | jq -s 'map(select(length > 0))')
          run_cmd "lint(recheck)" bash -c "cd \"$wt\" && $CMD_LINT"
          recheck_rc=$?
          if [[ "$recheck_rc" -eq 0 ]]; then
            vs_lint="autofixed"
            if [[ "$no_attempt" -ne 1 ]]; then
              "$STATECTL" verify-attempts "$key" --incr LINT_AUTOFIX >/dev/null \
                || { EXIT_CODE=2 die "run: statectl verify-attempts --incr LINT_AUTOFIX failed"; }
              attempts_charged=$(jq '.LINT_AUTOFIX = ((.LINT_AUTOFIX // 0) + 1)' <<< "$attempts_charged")
            fi
          else
            record_failure "LINT_AUTOFIX" "$CMD_LINT (residual after --fix)" "$recheck_rc" "$RUN_CMD_OUT"
            vs_lint="failed"
          fi
        fi
      fi
      if [[ -n "$test_pid" && "$test_rc" -ne 0 ]]; then
        if is_infra_rc "$test_rc"; then
          record_failure "INFRA" "$CMD_TEST" "$test_rc" "$test_out"
        else
          record_failure "TEST_FAILURE" "$CMD_TEST" "$test_rc" "$test_out"
          vs_test="failed"
        fi
      fi
    fi

    local vs_json
    vs_json=$(jq -n --arg f "$vs_format" --arg l "$vs_lint" --arg t "$vs_tsc" \
                    --arg te "$vs_test" --arg b "$vs_build" \
                    '{format: $f, lint: $l, typeCheck: $t, test: $te, build: $b}')
    emit_verdict "$key" "$(build_verdict_ctx "$vs_json")"
  fi
}

# build_verdict_ctx — assemble the verdict-context JSON from cmd_run's ambient
# locals (bash dynamic scoping). $1 = verifySummary JSON. The ctx IS the verdict
# shape minus `attempts` (read fresh from state inside emit_verdict, after any
# charging). A single blob instead of ordinal positional args — positional args
# were a silent off-by-one trap for any future field insertion.
build_verdict_ctx() {
  jq -n --arg lane "$lane" --arg base "$base_ref" \
        --arg mb "$merge_base" --arg head "$head_sha" --arg status "$overall" \
        --argjson failures "$failures" --argjson charged "$attempts_charged" \
        --argjson fmt "$format_changed" --argjson lint "$lint_autofixed" \
        --argjson noatt "$([[ "$no_attempt" == "1" ]] && echo true || echo false)" \
        --argjson vs "$1" '
    { lane: $lane, base: $base, mergeBase: $mb, head: $head,
      status: $status, failures: $failures, attemptsCharged: $charged,
      formatChanged: $fmt, lintAutofixed: $lint,
      noAttempt: $noatt, verifySummary: $vs }'
}

# emit_verdict — write the sidecar (unless --no-attempt) and print the verdict.
# $1 = issue number; $2 = verdict-context JSON from build_verdict_ctx.
emit_verdict() {
  local key="$1" ctx="$2"
  local status head_sha no_attempt
  status=$(jq -r '.status' <<< "$ctx")
  head_sha=$(jq -r '.head' <<< "$ctx")
  no_attempt=$(jq -r '.noAttempt' <<< "$ctx")

  local key_lc sdir sidecar
  key_lc=$(echo "$key" | tr '[:upper:]' '[:lower:]')
  sdir=$(state_dir)
  sidecar="$sdir/${key_lc}-verify.json"

  if [[ "$no_attempt" != "true" ]]; then
    local run_id charged failed_classes
    run_id=$(sget "$key" '.runId // ""')
    charged=$(jq -r '.chargedHead // ""' "$sidecar" 2>/dev/null || echo "")
    failed_classes=$(jq '[.failures[] | .class] | unique' <<< "$ctx")
    local tmp="${sidecar}.tmp"
    jq -n --arg run_id "$run_id" --arg h "$head_sha" --arg ch "$charged" \
          --arg at "$(now_iso)" --argjson fc "$failed_classes" \
          --arg st "$([[ "$status" == "pass" ]] && echo pass || echo fail)" \
          '{runId: $run_id, headSha: $h, chargedHead: $ch, at: $at, failedClasses: $fc, status: $st}' > "$tmp" \
      && mv "$tmp" "$sidecar" \
      || { EXIT_CODE=2 die "emit: could not write sidecar $sidecar"; }
  fi

  local attempts
  attempts=$(sget "$key" ".verifyAttempts // {}")
  jq --argjson attempts "$attempts" '. + {attempts: $attempts}' <<< "$ctx"

  [[ "$status" == "pass" ]] && exit 0 || exit 1
}

# ---------------------------------------------------------------- dispatch ----

main() {
  local subcmd="${1:-}"
  [[ -n "$subcmd" ]] || { EXIT_CODE=3 die "usage: verifyctl.sh run <issue-number> [--no-attempt]"; }
  shift
  case "$subcmd" in
    run) cmd_run "$@" ;;
    *) EXIT_CODE=3 die "unknown subcommand: '$subcmd' (only: run)" ;;
  esac
}

main "$@"
