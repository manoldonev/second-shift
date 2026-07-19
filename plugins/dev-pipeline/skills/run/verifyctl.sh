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
# INFRA-grade on failure — e.g. install / workspace-package builds). Formatting
# is config-driven (commands.<host>.format, #12): a string runs verbatim as the
# repo's own formatter (`black .`, `yarn format`), null skips the format lane
# entirely, and an ABSENT key falls back to scoped prettier (the documented
# default — the ONLY path that needs node/npx). Single-repo operation: no --repo
# flag, no per-repo sidecars, no integration lane.
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
  # --repo <id> (be-fe-pair): key the command table on that repo id; else the
  # path="." host (single-repo default).
  if [[ -n "${REPO_ID:-}" ]]; then
    host="$REPO_ID"
    [[ "$(jq -r --arg h "$host" '.topology.repos | has($h)' "$cfg" 2>/dev/null)" == "true" ]] \
      || { EXIT_CODE=2 die "run: --repo '$host' is not a topology.repos entry ($cfg)"; }
  else
    host=$(jq -r '.topology.repos | to_entries[] | select(.value.path == ".") | .key' "$cfg" 2>/dev/null | head -n1)
    [[ -n "$host" ]] \
      || { EXIT_CODE=2 die "run: config has no topology.repos entry with path \".\" ($cfg)"; }
  fi
  BASE_BRANCH=$(jq -r --arg h "$host" '.topology.repos[$h].baseBranch // empty' "$cfg")
  [[ -n "$BASE_BRANCH" ]] \
    || { EXIT_CODE=2 die "run: config topology.repos.$host.baseBranch missing ($cfg)"; }
  CMD_LINT=$(jq -r --arg h "$host" '.commands[$h].lint // empty' "$cfg")
  CMD_TYPECHECK=$(jq -r --arg h "$host" '.commands[$h].typecheck // empty' "$cfg")
  CMD_TEST=$(jq -r --arg h "$host" '.commands[$h].test // empty' "$cfg")
  # commands.<host>.format (#12): decouple formatting from the hardcoded prettier.
  #   string -> FORMAT_MODE=config: run the command verbatim from the worktree
  #             (the repo's own formatter, e.g. "black ." / "yarn format"). The
  #             command owns its scope; the caller scopes the commit (Stage 6).
  #   null   -> FORMAT_MODE=skip: NO format lane (a no-node / non-prettier consumer
  #             opts out; prettier + the npx fallback never run).
  #   absent -> FORMAT_MODE=prettier: the documented default (scoped prettier
  #             --check/--write over stageParams.formatGlob) — byte-for-byte the
  #             prior behavior, so a config that never set `format` is unchanged.
  #             (This is the ONLY path that needs node/npx — see docs/onboarding.md.)
  CMD_FORMAT=$(jq -r --arg h "$host" '.commands[$h].format // empty' "$cfg")
  if [[ -n "$CMD_FORMAT" ]]; then
    FORMAT_MODE=config
  elif [[ "$(jq -r --arg h "$host" '.commands[$h] | has("format")' "$cfg")" == "true" ]]; then
    FORMAT_MODE=skip
  else
    FORMAT_MODE=prettier
  fi
  LINT_AUTOFIXES=$(jq -r --arg h "$host" '.commands[$h].lintAutofixes // false' "$cfg")
  # #98 D2b: zero-lane safety valve — read by the SUITE verdict emission only when
  # nothing verifying is configured; never a gate kill-switch for configured lanes.
  ALLOW_UNVERIFIED=$(jq -r --arg h "$host" '.commands[$h].allowUnverified // false' "$cfg")
  SETUP_LANES=$(jq -c --arg h "$host" '.commands[$h].lanes // []' "$cfg")
  # EP-2 additive verify lanes (run AFTER the SUITE trio, blocking, ext:<name> keys).
  EXTRA_LANES=$(jq -c --arg h "$host" '.commands[$h].extraLanes // []' "$cfg")

  # resolve stageParams.formatGlob (default = *.{ts,tsx,js,json,md}) — the
  # prettier scoped-format file glob. Absent key => the shipped literal, so an
  # empty config is byte-for-byte today's behavior. Expanded once here into
  # brace alternatives (FORMAT_GLOB_ALTS) that collect_format_files matches each
  # changed file against; the default expands to exactly the shipped
  # *.ts/*.tsx/*.js/*.json/*.md set. Brace expansion only — pathname expansion
  # is disabled across the eval so no glob value ever touches the filesystem.
  FORMAT_GLOB=$(jq -r '.stageParams.formatGlob // "*.{ts,tsx,js,json,md}"' "$cfg")
  local _had_noglob=off
  case $- in *f*) _had_noglob=on ;; esac
  set -f
  eval "FORMAT_GLOB_ALTS=( $FORMAT_GLOB )"
  [[ "$_had_noglob" == off ]] && set +f
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
  # REPO_ID (be-fe-pair, #5): `--repo <id>` verifies ONE target repo — load_config
  # keys the command table + baseBranch on <id> (not the path="." host), and the
  # worktree/base/verify-budget are read from `worktrees.<id>.*`. Empty (no --repo)
  # = the single-repo path: host = path ".", flat worktreePath/worktreeBase/
  # verifyAttempts — byte-for-byte the prior behavior. REPO_ID is a cmd_run local,
  # visible to load_config via bash dynamic scoping.
  local key="" no_attempt=0 REPO_ID=""
  key="${1:-}"; shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-attempt) no_attempt=1; shift ;;
      --repo) REPO_ID="${2:-}"; shift 2 ;;
      *) EXIT_CODE=3 die "run: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$key" ]] \
    || { EXIT_CODE=3 die "usage: verifyctl.sh run <issue-number> [--repo <id>] [--no-attempt]"; }

  local key_lc
  key_lc=$(echo "$key" | tr '[:upper:]' '[:lower:]')

  # ---- static context (consumer config) ----
  load_config

  # ---- derive everything from state / git ----
  local wt run_id base_ref
  # --repo <id> reads the per-repo worktree map (worktrees.<id>.*); else the flat
  # single-repo field. REPO_ID is a safe config repo id (no jq injection).
  if [[ -n "$REPO_ID" ]]; then
    wt=$(sget "$key" ".worktrees[\"$REPO_ID\"].worktreePath // \"\"")
    [[ -n "$wt" ]] || { EXIT_CODE=2 die "run: state has no .worktrees.$REPO_ID.worktreePath (Stage-2 pair worktree not created?)"; }
  else
    wt=$(sget "$key" '.worktreePath // ""')
    [[ -n "$wt" ]] || { EXIT_CODE=2 die "run: state has no .worktreePath (worktree-set not run?)"; }
  fi
  # Canonical form is repo-relative — resolve against the main checkout root.
  # An absolute value (selftest fixtures write one directly) passes through.
  [[ "$wt" == /* ]] || wt="$(main_root)/$wt"
  [[ -d "$wt" ]] || { EXIT_CODE=2 die "run: worktreePath does not resolve to a directory ('$wt')"; }
  run_id=$(sget "$key" '.runId // ""')
  [[ -n "$run_id" ]] || { EXIT_CODE=2 die "run: state has no .runId (statectl init not run?)"; }
  # Persisted by slice-set on stacked runs (priorSliceBranch for slice N>1);
  # absent on single-PR runs => the config's host-repo baseBranch. No
  # branch-name arithmetic — the persisted field is the source of truth.
  if [[ -n "$REPO_ID" ]]; then
    base_ref=$(sget "$key" ".worktrees[\"$REPO_ID\"].base // \"\"")
  else
    base_ref=$(sget "$key" '.worktreeBase // ""')
  fi
  [[ -n "$base_ref" ]] || base_ref="$BASE_BRANCH"

  # verify-attempts --repo passthrough: charges the per-repo budget
  # (worktrees.<id>.verifyAttempts) for a --repo run, the flat verifyAttempts
  # otherwise. Expanded bash-3.2-safe at each call site: ${VA_REPO[@]+"${VA_REPO[@]}"}.
  local -a VA_REPO=()
  [[ -n "$REPO_ID" ]] && VA_REPO=(--repo "$REPO_ID")

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
  # Per-repo sidecar/log suffix (be-fe-pair): isolates each target repo's
  # attempt-detection + log so a `--repo be` and a `--repo fe` run in the same
  # issue never corrupt each other's accounting. Empty for single-repo (unchanged).
  sidecar="$sdir/${key_lc}${REPO_ID:+-$REPO_ID}-verify.json"
  logfile="$sdir/${key_lc}${REPO_ID:+-$REPO_ID}-verify.log"

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
          "$STATECTL" verify-attempts "$key" ${VA_REPO[@]+"${VA_REPO[@]}"} --incr "$c" >/dev/null \
            || { EXIT_CODE=2 die "run: statectl verify-attempts --incr $c failed"; }
          attempts_charged=$(jq --arg c "$c" '.[$c] = ((.[$c] // 0) + 1)' <<< "$attempts_charged")
        done <<< "$classes"
      fi
    fi
  fi

  # ---- execute the lane ----
  : > "$logfile"
  local failures="[]" format_changed="[]" lint_autofixed="[]"
  # #98: lanes initialize to "skipped" and are PROMOTED on execution — a lane
  # that did not run can never report clean/passed (the demotion invariant is
  # structural, covering setup- and format-short-circuits alike).
  local vs_format="skipped" vs_lint="skipped" vs_tsc="skipped" vs_test="skipped" vs_setup="skipped"
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

  # Changed files matching the resolved prettier format glob (FORMAT_GLOB, from
  # stageParams.formatGlob; default *.{ts,tsx,js,json,md}), existing in the
  # worktree. Populates the CHECK_FILES array. Each changed file is tested
  # against the brace alternatives expanded in load_config — the default set
  # reproduces the former *.ts|*.tsx|*.js|*.json|*.md case exactly.
  collect_format_files() {
    CHECK_FILES=()
    local f a
    while IFS= read -r f; do
      for a in "${FORMAT_GLOB_ALTS[@]}"; do
        # shellcheck disable=SC2053 # glob-style pattern match — RHS intentionally unquoted
        if [[ "$f" == $a ]]; then
          [[ -f "$wt/$f" ]] && CHECK_FILES+=("$f")
          break
        fi
      done
    done <<< "$changed"
  }

  if [[ "$lane" == "INERT" ]]; then
    # Scoped prettier --check on changed format-glob files only (a
    # .claude/**/*.mjs-only diff has nothing to check — correct). ONLY in the
    # prettier default mode: a config `format` command (FORMAT_MODE=config) is a
    # whole-repo formatter gated in the SUITE lane, and FORMAT_MODE=skip disables
    # formatting entirely — neither runs on an inert docs/shell diff, so a no-node
    # consumer's inert run never reaches npx prettier (#12).
    if [[ "$FORMAT_MODE" == "prettier" ]]; then
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
    local lane_count li lane_name lane_cwd lane_cmds lc_i lane_cmd lane_dir lane_type
    lane_count=$(jq 'length' <<< "$SETUP_LANES")
    for (( li=0; li<lane_count; li++ )); do
      [[ "$overall" == "pass" ]] || break
      # Shape backstop (#100): config-lint is the primary gate, but verifyctl can
      # run against a config that was never linted. A non-object entry used to
      # make the `.name`/`.commands` reads below error to stderr, leaving
      # lane_cmds empty so the inner loop ran zero times — the lane was SILENTLY
      # skipped and the run still reached a green verdict. Fail INFRA instead.
      lane_type=$(jq -r --argjson i "$li" '.[$i] | type' <<< "$SETUP_LANES")
      if [[ "$lane_type" != "object" ]]; then
        record_failure "INFRA" "setup lane [$li]: must be an object {name, cwd?, commands[]}, got $lane_type" 1 ""
        vs_setup="failed"   # #98 rename: the setup field carries the lanes[] outcome
        break
      fi
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
          vs_setup="failed"
          break
        fi
      done
    done
    # Promote: all configured setup lanes ran without failure. No lanes[] configured
    # leaves the init "skipped" (#98 D1 — setup never claims a lane that didn't run).
    [[ "$lane_count" -gt 0 && "$overall" == "pass" ]] && vs_setup="clean"

    # 2. Format (#12, FORMAT_MODE resolved in load_config):
    #    prettier -> scoped `prettier --write` on the changed format-glob files
    #                (default; never repo-wide; never .mjs — outside the glob).
    #    config   -> run commands.<host>.format VERBATIM from the worktree root
    #                (the repo's own whole-set formatter, e.g. `black .`). No node
    #                assumption. The command owns its scope.
    #    skip     -> no formatter runs at all (commands.<host>.format is null).
    #    In every mode the files that changed are collected into formatChanged[]
    #    for the caller's scoped commit; a non-INFRA non-zero exit is a FORMAT fail.
    if [[ "$overall" == "pass" && "$FORMAT_MODE" != "skip" ]]; then
      local pre_format post_format fmt_out fmt_label=""
      # #98: the format lane is executing — promote from the "skipped" init at
      # block entry so the `applied` guard below (which keys off "clean") still
      # fires. The prettier zero-files path keeps "clean": the lane ran and had
      # nothing to check. A short-circuited block never reaches this line.
      vs_format="clean"
      fmt_out=$(mktemp)
      if [[ "$FORMAT_MODE" == "config" ]]; then
        fmt_label="format: $CMD_FORMAT"
        pre_format=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
        ( cd "$wt" && bash -c "$CMD_FORMAT" ) > "$fmt_out" 2>&1
        rc=$?
      else
        # prettier default (scoped over the changed format-glob files)
        collect_format_files
        pre_format=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
        if (( ${#CHECK_FILES[@]} > 0 )); then
          local prettier
          fmt_label="prettier --write (scoped)"
          prettier=$(resolve_prettier "$wt")
          # shellcheck disable=SC2086
          ( cd "$wt" && $prettier --write "${CHECK_FILES[@]}" ) > "$fmt_out" 2>&1
          rc=$?
        else
          rc=0   # nothing to format on this diff
        fi
      fi
      if [[ -n "$fmt_label" ]]; then
        { echo "===== [format] $fmt_label (exit=$rc) ====="; cat "$fmt_out"; } >> "$logfile"
        if [[ "$rc" -ne 0 ]]; then
          if is_infra_rc "$rc"; then
            record_failure "INFRA" "$fmt_label" "$rc" "$fmt_out"
          else
            record_failure "FORMAT" "$fmt_label" "$rc" "$fmt_out"
            vs_format="failed"
          fi
        fi
        post_format=$(git -C "$wt" status --porcelain | awk '{print $2}' | sort)
        format_changed=$(comm -13 <(echo "$pre_format") <(echo "$post_format") | jq -R . | jq -s 'map(select(length > 0))')
        [[ "$format_changed" != "[]" && "$vs_format" == "clean" ]] && vs_format="applied"
      fi
    fi
    [[ "$FORMAT_MODE" == "skip" ]] && vs_format="skipped"

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
              "$STATECTL" verify-attempts "$key" ${VA_REPO[@]+"${VA_REPO[@]}"} --incr LINT_AUTOFIX >/dev/null \
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
      # #98: promote lanes that ran and passed (rc==0) from the "skipped" init.
      # Failure/autofix paths above already wrote their tokens; an INFRA-failed
      # lane stays "skipped" — it did not complete, and overall is fail anyway.
      [[ -n "$lint_pid" && "$lint_rc" -eq 0 ]] && vs_lint="clean"
      [[ -n "$tsc_pid" && "$tsc_rc" -eq 0 ]] && vs_tsc="clean"
      [[ -n "$test_pid" && "$test_rc" -eq 0 ]] && vs_test="passed"
    fi

    # ---- EP-2: extra lanes (additive, append-after-SUITE, blocking, ext:<name> keys) ----
    # Built-in SUITE lanes ran first; extra lanes append sequentially, never interleave or
    # replace. `when` globs gate execution (empty = always); results land under NAMESPACED
    # ext:<name> keys (canonical keys unreachable). A lane failure records under its declared
    # (closed-enum) failureClass and charges the standard attempt budget — no advisory mode.
    # Skipped entirely when the SUITE already failed (the verdict is failed regardless) or on an
    # inert diff (this whole branch only runs on a non-inert SUITE diff).
    local ext_json="{}"
    local el_count
    el_count=$(jq 'length' <<< "$EXTRA_LANES")
    if [[ "$el_count" -gt 0 && "$failures" == "[]" ]]; then
      local el_i
      for (( el_i=0; el_i<el_count; el_i++ )); do
        local el_name el_fc el_when_count el_run el_status el_cmds el_ci el_cmd el_rc el_type
        # Shape backstop (#100) — same fail-open as the setup-lane loop above:
        # a non-object entry left el_cmds empty, so the lane was recorded without
        # ever running. INFRA is correct here (a malformed config is an
        # environment defect, not the lane's own failureClass).
        el_type=$(jq -r --argjson i "$el_i" '.[$i] | type' <<< "$EXTRA_LANES")
        if [[ "$el_type" != "object" ]]; then
          record_failure "INFRA" "extra lane [$el_i]: must be an object {name, when?, commands[], failureClass?}, got $el_type" 1 ""
          break
        fi
        el_name=$(jq -r --argjson i "$el_i" '.[$i].name' <<< "$EXTRA_LANES")
        el_fc=$(jq -r --argjson i "$el_i" '.[$i].failureClass' <<< "$EXTRA_LANES")
        el_when_count=$(jq --argjson i "$el_i" '(.[$i].when // []) | length' <<< "$EXTRA_LANES")
        el_run=1
        if [[ "$el_when_count" -gt 0 ]]; then
          el_run=0
          local wi wg cf
          for (( wi=0; wi<el_when_count; wi++ )); do
            wg=$(jq -r --argjson i "$el_i" --argjson j "$wi" '.[$i].when[$j]' <<< "$EXTRA_LANES")
            while IFS= read -r cf; do
              [[ -z "$cf" ]] && continue
              # shellcheck disable=SC2053
              if [[ "$cf" == $wg ]]; then el_run=1; break 2; fi
            done <<< "$changed"
          done
        fi
        if [[ "$el_run" -ne 1 ]]; then
          ext_json=$(jq --arg n "$el_name" '. + {("ext:"+$n): "skipped"}' <<< "$ext_json")
          continue
        fi
        el_status="clean"
        el_cmds=$(jq --argjson i "$el_i" '(.[$i].commands // []) | length' <<< "$EXTRA_LANES")
        for (( el_ci=0; el_ci<el_cmds; el_ci++ )); do
          el_cmd=$(jq -r --argjson i "$el_i" --argjson j "$el_ci" '.[$i].commands[$j]' <<< "$EXTRA_LANES")
          run_cmd "ext:$el_name" bash -c "cd \"$wt\" && $el_cmd"
          el_rc=$?
          if [[ "$el_rc" -ne 0 ]]; then
            record_failure "$el_fc" "extra lane '$el_name': $el_cmd" "$el_rc" "$RUN_CMD_OUT"
            el_status="failed"
            if [[ "$no_attempt" -ne 1 ]]; then
              "$STATECTL" verify-attempts "$key" ${VA_REPO[@]+"${VA_REPO[@]}"} --incr "$el_fc" >/dev/null \
                || { EXIT_CODE=2 die "run: statectl verify-attempts --incr $el_fc (extra lane $el_name) failed"; }
            fi
            break
          fi
        done
        ext_json=$(jq --arg n "$el_name" --arg s "$el_status" '. + {("ext:"+$n): $s}' <<< "$ext_json")
      done
    fi

    # #98 D2b/D2c: a clean run with nothing verifying executed must not emit an
    # optimistic object. Two LEGITIMATE skips ride the string path (statectl's
    # existing string acceptance — same mechanism as INERT); anything else falls
    # through to the object emit, where the Stage-6 content gate refuses an
    # all-skipped summary. A recorded failure ALWAYS falls through — the opt-out
    # can never mask a failure (overall gate below).
    local vs_json unverified_string=""
    if [[ "$overall" == "pass" && -z "$CMD_LINT" && -z "$CMD_TYPECHECK" && -z "$CMD_TEST" ]]; then
      if [[ "$el_count" -eq 0 ]]; then
        # D2b: zero verifying lanes configured — string path only via explicit opt-in.
        [[ "$ALLOW_UNVERIFIED" == "true" ]] \
          && unverified_string="skipped (no verify lanes configured — allowUnverified opt-out)"
      elif jq -e '[.[]] | length > 0 and all(. == "skipped")' <<< "$ext_json" >/dev/null 2>&1; then
        # D2c: verification IS configured (when-gated extraLanes) but the config
        # scoped it away from this diff — the INERT posture, not a gate failure.
        unverified_string="skipped (when-gated verify lanes did not match the diff)"
      fi
    fi
    if [[ -n "$unverified_string" ]]; then
      vs_json=$(jq -n --arg s "$unverified_string" '$s')
    else
      vs_json=$(jq -n --arg f "$vs_format" --arg l "$vs_lint" --arg t "$vs_tsc" \
                      --arg te "$vs_test" --arg s "$vs_setup" --argjson ext "$ext_json" \
                      '{format: $f, lint: $l, typeCheck: $t, test: $te, setup: $s} + $ext')
    fi
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
  # Same per-repo suffix as cmd_run (REPO_ID inherited from the calling run's scope).
  sidecar="$sdir/${key_lc}${REPO_ID:+-$REPO_ID}-verify.json"

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
