#!/usr/bin/env bash
# run.sh — the unattended scheduler: one ticket in, an approved PR out.
#
# usage: run.sh <issue> [--build-model|--model <id>] [--model-basis <text>]
#               [--review-model <id>] [--review-model-basis <text>]
#               [--max-rounds N] [--dry-run] [--resume] [--detach]
#   The build model comes from the ticket's `opus` / `sonnet` label; --build-model overrides.
#   Review defaults to `opus`; a departure needs --review-model-basis. The short forms `opus` /
#   `sonnet` are passed through to `claude --model`, which resolves them to the current model of
#   that tier — no model id is written here, so a new release needs no edit.
#
# env:  SECOND_SHIFT_CONFIG   config path (default <main>/.claude/second-shift.config.json)
#       RUN_CLAUDE, RUN_GH (alias GH)   the binaries (tests inject fakes)
#       RUN_WORKTREE_ROOT     default <parent of main>/<repo>-worktrees
#       RUN_BUILD_TIMEOUT / RUN_REVIEW_TIMEOUT   seconds (7200 / 3600)
#       RUN_COST_CEILING      USD (100); RUN_CHECKS_RED_MAX (3)
#       Env beats config `run.*` beats these defaults; an explicit --max-rounds beats config.
#
# What it does, in order (each phase's invariant in parentheses):
#   0 parse      (reads argv only; a usage error exits 2 with nothing written)
#   1 environment(every config read fails closed under a named slug; nothing written)
#   2 detach     (re-exec under setsid; the log's last line carries the run's exit code)
#   3 preflight  (read-only, fixed order: record, lanes, design, dry-run, ticket open, model)
#   4 claim      (the first write: the label swap and the claim marker, or a re-entry)
#   5 baseline   (worktree on the branch; the record is the branch's first commit, pushed)
#   6 rounds     (premise; worktree at the pushed head; BUILD; in-flight check; one PR;
#                 conventions; checks from the first commit; route smoke; review input;
#                 REVIEW in a fresh session, re-spawned once when dark; verdict bound to the
#                 review window, unedited, naming the current head)
#   7 close-out  (run block on the PR at every terminal once one exists; closing comment
#                 when the run claimed; teardown of a clean worktree on approve)
#
# Rules every line below keeps:
#   - a predicate that cannot be evaluated refuses under a named slug; a failed read is never a pass;
#   - no refusal inside `$(...)`, a pipe or a piped loop — producers return non-zero, the CALLER refuses;
#   - nothing here discards work: no `reset --hard`, no forced removal, no checkout over a dirty tree;
#   - the record's sections, the checks and the frames are read from its FIRST commit, never the head;
#   - every session is a fresh process with a wall-clock bound; every attempt keeps its own files;
#   - the gate's regexes and forms are copied from milestone-gate.sh, never paraphrased.
#
# exit: 0 approved · dry-run
#       1 stopped for a human: build-no-pr, build-inflight(-unreadable), build-blocked, pr-ambiguous,
#         closeout-inflight(-unreadable), staleness-unreadable
#       2 usage-* (the argv), env-* (the environment; most fire before anything is spawned, but
#         env-not-ready, env-worktree*, env-remote-unreadable, env-tracker-unreadable and
#         env-smoke-unconfigured can fire after a paid session), claimed-elsewhere
#       3 RESUMABLE — not-queued, env-no-record: pay off intake and re-launch the same command
#       4 budget spent — rounds-spent, checks-red-spent, cost-spent
#       5 review-unbound — no verdict usable against the current head, after one re-spawn
#       7 the premise expired mid-run — ticket-closed, staleness-expired
#       130 / 143 interrupted by INT / TERM; the session is reaped, the claim is left in place
# Every exit prints `terminal: <slug>` as its last stdout line so a wrapper routes on the slug.
set -uo pipefail

# ============================ 0. parse (rows A1-A13, A19) ============================
usage_refusal() { echo "run.sh: $2" >&2; echo "terminal: $1"; exit 2; }
CLAUDE="${RUN_CLAUDE:-claude}"; GH="${RUN_GH:-${GH:-gh}}"
REVIEW_MODEL_DEFAULT="opus"
ISSUE=""; MAX_ROUNDS=3; MAX_ROUNDS_SET=0; BUILD_MODEL=""; MODEL_BASIS=""
REVIEW_MODEL="$REVIEW_MODEL_DEFAULT"; REVIEW_MODEL_BASIS=""; DRY_RUN=0; RESUME=0; DETACH=0
KEEP_ARGS=()   # what a detached run re-executes with: everything but --detach
while [ $# -gt 0 ]; do
  case "$1" in
    --build-model|--model)  BUILD_MODEL="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --model-basis)          MODEL_BASIS="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --review-model)         REVIEW_MODEL="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --review-model-basis)   REVIEW_MODEL_BASIS="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --max-rounds)           MAX_ROUNDS="${2-}"; MAX_ROUNDS_SET=1; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --max-continuations)    usage_refusal usage-max-continuations "--max-continuations was removed in #718 along with the continuation budget it bounded: BUILD is spawned once per round, and a spawn that leaves no PR ends the run for a human to read. There is no value of this flag to pass." ;;
    --dry-run)              DRY_RUN=1; KEEP_ARGS+=("$1"); shift ;;
    --resume)               RESUME=1; KEEP_ARGS+=("$1"); shift ;;
    --detach)               DETACH=1; shift ;;
    -h|--help)              awk 'NR>1 && /^set -uo pipefail/{exit} NR>1' "$0"; exit 0 ;;
    -*)                     usage_refusal usage-unknown-option "unknown option: $1" ;;
    *) if [ -z "$ISSUE" ]; then ISSUE="$1"; KEEP_ARGS+=("$1"); shift; else usage_refusal usage-unexpected-argument "unexpected argument: $1"; fi ;;
  esac
done
[ -n "$ISSUE" ] || usage_refusal usage-missing-issue "usage: run.sh <issue> [options] (run.sh -h for the table)"
[ -n "$REVIEW_MODEL" ] || usage_refusal usage-empty-review-model "--review-model was given an empty value."
if [ "$REVIEW_MODEL" != "$REVIEW_MODEL_DEFAULT" ] && [ -z "$REVIEW_MODEL_BASIS" ]; then
  usage_refusal usage-review-model-basis "--review-model '$REVIEW_MODEL' departs from the shipped default ('$REVIEW_MODEL_DEFAULT'): say why via --review-model-basis."
fi
case "$MAX_ROUNDS" in ''|*[!0-9]*) usage_refusal usage-max-rounds "--max-rounds must be a positive integer, got '$MAX_ROUNDS'" ;; esac
[ "$MAX_ROUNDS" -ge 1 ] || usage_refusal usage-max-rounds "--max-rounds must be at least 1."

# ============================ 1. environment (rows A20-A27, B1-B4, C1-C14, C28) ============================
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { echo "$(now) [run] $*"; }
exit_code_for() { # the taxonomy a wrapper branches on (orchestrate.sh's, kept)
  case "$1" in
    approved|dry-run) echo 0 ;;
    not-queued|env-no-record) echo 3 ;;
    usage-*|env-*|claimed-elsewhere) echo 2 ;;
    rounds-spent|checks-red-spent|cost-spent) echo 4 ;;
    review-unbound) echo 5 ;;
    ticket-closed|staleness-expired) echo 7 ;;
    *) echo 1 ;;
  esac
}
# Run state the terminal reports on. Set as the run advances; empty until then.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
COST=0; ROUND=0; ATTEMPT=0; CHECKS_RED=0; CLAIMED=0; PR=""; PR_URL=""; HEAD_SHA=""; VERDICT=""; CI=""; FIRST=""; CHILD=""; TRACKER=""
terminal() { # terminal <slug> <detail> — rows B1, B21, B22, K9: the run block on the PR whenever one exists, one closing comment when the run claimed
  say "terminal: $1 — $2"; echo "terminal: $1"
  if [ -n "$PR" ] && [ "${BLOCK_DONE:-0}" -eq 0 ]; then BLOCK_DONE=1; write_run_block "$1"; fi
  if [ "$CLAIMED" -eq 1 ] && [ "$TRACKER" = github ]; then
    "$GH" issue comment "$ISSUE" --body "$(printf 'second-shift run %s: %s — %s\n%s\ncost_usd: %s\n' "$RUN_ID" "$1" "$2" "${PR_URL:-${PR:+PR #$PR}}" "$COST")" >/dev/null 2>&1 || say "could not post the closing comment on #$ISSUE"
  fi
  exit "$(exit_code_for "$1")"
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || terminal env-no-git-repo "not in a git repo"
_common="$(git rev-parse --git-common-dir 2>/dev/null)" || terminal env-git-common-dir "cannot resolve --git-common-dir"
case "$_common" in /*) : ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" || terminal env-main-root "cannot resolve the main checkout"
REPO_SLUG="$(basename "$MAIN_ROOT")"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$(cd "$SKILL_DIR/../../tools" && pwd)"

# C1/C2: an absent file means the consumer configured nothing; a present-but-unparseable one is a refusal
CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"
if [ -f "$CONFIG" ]; then jq -e . "$CONFIG" >/dev/null 2>&1 || terminal env-config-unparseable "$CONFIG is present but not JSON — refusing to fall back to defaults"
else CONFIG=""; fi
cfg() { [ -n "$CONFIG" ] && jq -r "$1 // empty" "$CONFIG" 2>/dev/null || true; }             # strings; a literal false would be swallowed, so booleans go through cfg_bool
cfg_bool() { [ -n "$CONFIG" ] && jq -r "if $1 == null then \"\" else ($1|tostring) end" "$CONFIG" 2>/dev/null || true; }
# the sessions run in the worktree, whose gitignored .claude/ has no config: hand them the resolved path (F10)
[ -n "$CONFIG" ] && export SECOND_SHIFT_CONFIG="$CONFIG"

TRACKER="$(cfg .tracker.type)"; TRACKER="${TRACKER:-github}"                                            # C3
case "$TRACKER" in github|jira) : ;; *) terminal env-tracker-type "tracker.type '$TRACKER' is not github or jira — a typo must not silently pick the arm that attests less" ;; esac
TRACKER_WRITES="$(cfg_bool .tracker.writes)"                                                             # C4
if [ "$TRACKER" = github ]; then TRACKER_WRITES="${TRACKER_WRITES:-true}"; else TRACKER_WRITES="${TRACKER_WRITES:-false}"; fi
KEY_PATTERN="$(cfg .tracker.keyPattern)"                                                                 # C5
PLANS_DIR="$(cfg .paths.plansDir)"; PLANS_DIR="${PLANS_DIR:-docs/plans}"                                 # C13
STATE_DIR="$(cfg .paths.pipelineStateDir)"; STATE_DIR="${STATE_DIR:-.claude/pipeline-state}"             # C14
RENDER_CMD="$(cfg .design.liveRender.command)"; SMOKE_CMD="$(cfg .design.liveRender.smokeCommand)"       # C24 C25
READY_URL="$(cfg .design.liveRender.readyProbe)"; DESIGN_PROVIDER="$(cfg .design.provider)"              # C26 C23
L_QUEUE="$(cfg .tracker.labels.queue)"; L_QUEUE="${L_QUEUE:-ready-for-dev}"                              # C8
L_CLAIMED="$(cfg .tracker.labels.claimed)"; L_CLAIMED="${L_CLAIMED:-in-progress}"                        # C9
if [ -n "$CONFIG" ] && [ "$(jq -r '.tracker.labels.blockers | type' "$CONFIG" 2>/dev/null)" = array ]; then L_BLOCKERS="$(jq -r '.tracker.labels.blockers | join("\n")' "$CONFIG")"   # C10: [] means none
else L_BLOCKERS="$(printf 'epic\nneeds-intake-review\nneeds-spec-work\nneeds-plan-review')"; fi
# C5, plus the github key shape: a zero-padded or non-numeric key would derive a lane nobody can reconstruct
if [ -n "$KEY_PATTERN" ] && ! printf '%s' "$ISSUE" | grep -qiE "^($KEY_PATTERN)$"; then terminal usage-key "'$ISSUE' does not match tracker.keyPattern '$KEY_PATTERN'"; fi
if [ "$TRACKER" = github ] && ! printf '%s' "$ISSUE" | grep -qE '^[1-9][0-9]*$'; then terminal usage-key "'$ISSUE' is not a github issue number"; fi
# C11 C12 D6: the lane's own tracker writes go through the bot when one is configured (gh-bot.sh is the one
# resolution ladder); reads stay on the operator's gh. Enabled-but-broken refuses, never a silent write as the operator.
BOT_OK=0; GH_READ="$GH"
if [ -z "${RUN_GH:-}" ]; then
  bot_status="$(bash "$TOOLS/gh-bot.sh" --status 2>/dev/null)"
  if [ "$bot_status" = ok ]; then GH="$(bash "$TOOLS/gh-bot.sh" --path)"; BOT_OK=1
  elif [ "$(cfg_bool .tracker.bot.enabled)" = true ]; then terminal env-bot "tracker.bot.enabled is true but the wrapper is $bot_status — refusing to write as the operator in the bot's place"; fi
fi
# C6 C7 E1 E2: the branch namespace — configured, else the dominant prefix among remote branches, else REFUSE
BP_RESOLVER="$SKILL_DIR/../build/branch-prefix.sh"; [ -f "$BP_RESOLVER" ] || BP_RESOLVER="$TOOLS/branch-prefix.sh"
PREFIX="$(cfg .tracker.branchPrefix)"
if [ -z "$PREFIX" ]; then
  bp_err="$(mktemp "${TMPDIR:-/tmp}/run-bp.XXXXXX")"
  PREFIX="$(bash "$BP_RESOLVER" --configured "" --tracker "$TRACKER" ${KEY_PATTERN:+--key-pattern "$KEY_PATTERN"} --repo "$MAIN_ROOT" 2>"$bp_err")" \
    || { msg="$(tr '\n' ' ' < "$bp_err" | cut -c1-300)"; rm -f "$bp_err"; terminal env-branch-prefix "tracker.branchPrefix is unset and no dominant prefix exists among remote branches: $msg"; }
  rm -f "$bp_err"
fi
BRANCH="${PREFIX}$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')"
WT_ROOT="${RUN_WORKTREE_ROOT:-$(dirname "$MAIN_ROOT")/${REPO_SLUG}-worktrees}"; WT="$WT_ROOT/$ISSUE"
RECORD_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-decisions.md"
RECORD="$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md"   # the receipt's one conventional path (plan-interview writes it there)
# C28 A23 D-6: caps — env, else config run.*, else the defaults; each must be a positive number
cap() { # cap <var> <env value> <config key> <default> — sets <var> in this shell (a refusal must not sit inside a substitution)
  local v="$2"; [ -n "$v" ] || v="$(cfg "$3")"; [ -n "$v" ] || v="$4"
  case "$v" in ''|*[!0-9.]*|0|0.0) terminal env-config-run "${3#.} must be a positive number, got '$v'" ;; esac
  printf -v "$1" '%s' "$v"
}
[ "$MAX_ROUNDS_SET" -eq 1 ] || cap MAX_ROUNDS "" .run.maxRounds 3
cap BUILD_TO "${RUN_BUILD_TIMEOUT:-}" .run.buildTimeoutSeconds 7200
cap REVIEW_TO "${RUN_REVIEW_TIMEOUT:-}" .run.reviewTimeoutSeconds 3600
cap COST_CEIL "${RUN_COST_CEILING:-}" .run.costCeilingUsd 100
cap CHECKS_RED_MAX "${RUN_CHECKS_RED_MAX:-}" .run.checksRedMax 3
MAX_REVIEW_RETRIES=1                                                                                    # K12
LOG_DIR="$MAIN_ROOT/$STATE_DIR"; STATE="$LOG_DIR/run-$ISSUE/$RUN_ID"

# ============================ 2. detach (rows A16-A18) ============================
if [ "$DETACH" -eq 1 ]; then
  command -v perl >/dev/null 2>&1 || terminal env-detach-perl "--detach needs perl for setsid; run in the foreground instead"
  mkdir -p "$LOG_DIR" 2>/dev/null || terminal env-detach-log-dir "--detach cannot create $LOG_DIR for the run's log"
  DETACH_LOG="$LOG_DIR/$ISSUE-lean-run-$(now | tr -d ':-')-$$.log"
  _wrap=(); command -v caffeinate >/dev/null 2>&1 && _wrap=(caffeinate -dims)
  # shellcheck disable=SC2016  # the inner script expands in the child, not here
  nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' -- \
    ${_wrap[@]+"${_wrap[@]}"} bash -c 'bash "$@"; rc=$?; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [run] detached run exited rc=$rc"' \
    _ "$0" "${KEEP_ARGS[@]}" > "$DETACH_LOG" 2>&1 < /dev/null &
  say "detached: pid $! · log $DETACH_LOG · its last line will be 'detached run exited rc=<n>'"
  exit 0
fi

# ============================ library ============================
# -- processes (rows B18, F11-F13) --
# shellcheck disable=SC2329  # invoked from the traps
reap() { [ -n "$CHILD" ] || return 0; pkill -TERM -P "$CHILD" 2>/dev/null; kill -TERM "$CHILD" 2>/dev/null; }
trap 'reap; say "interrupted; claim left in place"; exit 130' INT
trap 'reap; say "terminated; claim left in place"; exit 143' TERM
bounded() { # bounded <secs> <logfile> <cmd...> — a bash watchdog (macOS ships no `timeout`); TERM, then KILL after 10s: the cap is a bound
  local secs="$1" log="$2"; shift 2
  ( cd "$WT" && exec "$@" ) > "$log" 2>"$log.err" < /dev/null & CHILD=$!
  local t=0
  while kill -0 "$CHILD" 2>/dev/null; do
    if [ "$t" -ge "$secs" ]; then
      reap; local k=0; while kill -0 "$CHILD" 2>/dev/null && [ "$k" -lt 10 ]; do sleep 1; k=$((k+1)); done
      kill -0 "$CHILD" 2>/dev/null && { pkill -KILL -P "$CHILD" 2>/dev/null; kill -KILL "$CHILD" 2>/dev/null; }
      wait "$CHILD" 2>/dev/null; CHILD=""; return 124
    fi
    sleep 1; t=$((t+1))
  done
  wait "$CHILD"; local rc=$?; CHILD=""; return $rc
}
# -- lane commands (row G5): what must not reach a lane child --
SEAM_SCRUB='SECOND_SHIFT_CONFIG|SECOND_SHIFT_REPO_ROOT|SECOND_SHIFT_EXTENSION_MANIFEST|SECOND_SHIFT_PLUGIN_ROOT|SECOND_SHIFT_REVIEW_TOOLKIT_ROOT|SECOND_SHIFT_DEV_PIPELINE_ROOT|SECOND_SHIFT_DESIGN_TOOLKIT_ROOT|SECOND_SHIFT_SECTION_CATALOG|STATECTL_STATE_DIR|STATECTL_WRITER|DEV_PIPELINE_MODE|BRANCH_PREFIX|KEY_PATTERN|LANE_ATTEND_MODE|MUTATION_SWEEP_NO_DEFER'
SCRUB_ENV=(); IFS='|' read -r -a _toks <<< "$SEAM_SCRUB"; for _t in "${_toks[@]}"; do SCRUB_ENV+=(-u "$_t"); done; unset _toks _t
lane() { ( cd "$WT" && env "${SCRUB_ENV[@]}" bash -c "$1" ); }
first_word() { local w; for w in $1; do case "$w" in *=*) continue ;; *) printf '%s' "$w"; return ;; esac; done; printf '%s' "${1%% *}"; }
# -- session flags (rows F2, F4-F10) --
DISALLOWED="AskUserQuestion,EnterWorktree,ExitWorktree"
if [ "$TRACKER_WRITES" = false ]; then # the 14 Atlassian write tools under every namespace they are served under
  for _tool in addCommentToJiraIssue addWorklogToJiraIssue createIssueLink createJiraIssue editJiraIssue transitionJiraIssue createConfluencePage updateConfluencePage createConfluenceFooterComment createConfluenceInlineComment createCompassComponent createCompassComponentRelationship createCompassCustomFieldDefinition addTeamworkGraphContext; do
    for _ns in mcp__atlassian__ mcp__plugin_atlassian_atlassian__ mcp__claude_ai_Atlassian_Rovo__; do DISALLOWED="$DISALLOWED,$_ns$_tool"; done
  done
fi
MCP_ALLOW=""; [ "$TRACKER" = jira ] && MCP_ALLOW=",mcp__atlassian,mcp__plugin_atlassian_atlassian,mcp__claude_ai_Atlassian_Rovo"
SPAWN_COMMON=(--permission-mode acceptEdits --permission-prompts none --disallowedTools "$DISALLOWED" --setting-sources "user,project,local" --add-dir "$WT" --output-format json)
[ -n "$CONFIG" ] && SPAWN_COMMON+=(--add-dir "$(cd "$(dirname "$CONFIG")" && pwd)")
add_cost() { local c; c="$(jq -r '.total_cost_usd // 0' "$1" 2>/dev/null)"; COST="$(awk -v a="$COST" -v b="${c:-0}" 'BEGIN{print a+b}')"; }
over_ceiling() { awk -v c="$COST" -v m="$COST_CEIL" 'BEGIN{exit !(c>m)}'; }

# -- tracker reads (rows D7-D9, J1, J3, K2-K5): every producer returns non-zero on a failed read; callers refuse --
issue_state() { [ "$TRACKER" = github ] || { echo OPEN; return 0; }; "$GH_READ" issue view "$ISSUE" --json state --jq .state 2>/dev/null; }
has_label() { local names; [ "$TRACKER" = github ] || return 1; names="$("$GH_READ" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || return 1; grep -qxF "$1" <<<"$names"; }
repo_slug() { "$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null; }
lane_marker_present() { # the lane's own claim marker: whole-line stage marker plus a run_id line, by a Bot or the account this scheduler writes with (D-24)
  local repo me comments
  repo="$(repo_slug)" || return 1
  me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
  comments="$("$GH_READ" api "repos/$repo/issues/$ISSUE/comments" --paginate 2>/dev/null)" || return 1
  printf '%s' "$comments" | jq -e --arg me "$me" 'any(.[];
      ((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))
      and (.body | test("(^|\n)<!-- stage: lean-claimed -->(\n|$)"))
      and (.body | test("<!-- run_id: ")))' >/dev/null 2>&1
}
open_prs() { "$GH_READ" pr list --head "$BRANCH" --state open --json number --jq '.[].number' 2>/dev/null; }
remote_head() { local out; out="$(git -C "$WT" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null)" || return 1; printf '%s' "$out" | cut -f1; }

# -- the record (rows G6, G7, H1-H4, H6, K6): read at its FIRST commit once one exists, else the receipt --
record_at_first() { git -C "$WT" show "$FIRST:$RECORD_REL" 2>/dev/null; }
record_text() { if [ -n "$FIRST" ]; then record_at_first; else cat "$RECORD" 2>/dev/null; fi; }
# the gate's heading rule: exact title at any depth, case-folded; ANY heading closes the section; the FIRST such section decides
section_of() { awk -v h="$1" 'on && /^#+[[:space:]]/ {on=0; done=1} !done && tolower($0) ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {on=1; next} on'; }
design_section_of() { section_of "design( frames)?"; }
# shellcheck disable=SC2016  # markdown backticks
record_checks() { record_text | section_of "checks" | sed -n 's/^- *`\{0,1\}\([^`]*\)`\{0,1\} *$/\1/p'; }
frames_rows() { record_text | design_section_of | grep -E '^\| *RS-[0-9]+ *\|' | sed 's/^| *//; s/ *| */|/g; s/ *|$//'; }
design_declared() { # 0 armed or disarmed with a reason; 1 neither (the gate's #705 rule, its forms byte for byte); reads record_text
  [ -n "$DESIGN_PROVIDER" ] || return 0
  local sec; sec="$(record_text | design_section_of)"
  [ -n "$sec" ] || return 1
  grep -qE '^\| *RS-[0-9]+ *\|' <<<"$sec" && return 0
  if grep -qiE '^[[:space:]]*Design:[[:space:]]*none([[:space:]]|$)' <<<"$sec"; then
    grep -qiE '^[[:space:]]*Design:[[:space:]]*none[[:space:]]+[^[:space:]]' <<<"$sec" && return 0
    say "design: the record disarms this ticket but states no reason; the form is 'Design: none — <reason>'"
  fi
  return 1
}

# -- configured checks (rows C15-C22, G2-G4, G8, G10) --
commands_key() { # topology's "." entry while topology exists, else the sole key, else this checkout's name
  [ -n "$CONFIG" ] || return 0
  jq -r --arg s "$REPO_SLUG" '
    (.topology.repos // {} | to_entries | map(select(.value.path == ".")) | .[0].key) as $t
    | (.commands // {} | keys) as $k
    | if ($t != null and ($k | index($t))) then $t elif ($k | length) == 1 then $k[0] elif ($k | index($s)) then $s else empty end' "$CONFIG" 2>/dev/null
}
lanes_malformed() { # prints the first malformed lanes[]/extraLanes[] entry, nothing when all are well-formed
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '
    def check(kind): to_entries[] | select((.value|type) != "object" or (.value.name // "") == "" or ((.value.commands // []) | type) != "array" or ((.value.commands // []) | length) == 0 or any(.value.commands[]; type != "string"))
      | kind + " lane [" + (.key|tostring) + "]: must be an object {name, cwd?, commands[] of strings}";
    ((.commands[$k].lanes // []) | if type == "array" then check("setup") else "commands.lanes must be an array" end),
    ((.commands[$k].extraLanes // []) | if type == "array" then check("extra") else "commands.extraLanes must be an array" end)' "$CONFIG" 2>&1 | head -n 1
}
setup_lanes() { local key; key="$(commands_key)"; [ -n "$key" ] || return 0; jq -r --arg k "$key" '.commands[$k].lanes[]? | (.cwd // ".") as $d | .commands[] | if $d == "." then . else "cd " + ($d|@sh) + " && " + . end' "$CONFIG" 2>/dev/null; }
config_checks() { # config_checks [all]: lint/typecheck/test/format, then extraLanes whose `when` globs match a changed file since FIRST (or have none); `all` lists every lane
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '.commands[$k] | [.lint, .typecheck, .test, .format] | map(select(type=="string"))[]' "$CONFIG" 2>/dev/null
  if [ "${1:-}" = all ]; then jq -r --arg k "$key" '.commands[$k].extraLanes[]?.commands[]? | select(type=="string")' "$CONFIG" 2>/dev/null; return 0; fi
  local lane hit g f
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue; hit=1
    if [ "$(printf '%s' "$lane" | jq '.when | length')" -gt 0 ]; then
      hit=0
      while IFS= read -r g; do while IFS= read -r f; do # shellcheck disable=SC2254  # $g IS a glob, by contract
        case "$f" in $g) hit=1 ;; esac; done <<EOF
$CHANGED
EOF
      done <<EOF
$(printf '%s' "$lane" | jq -r '.when[]')
EOF
    fi
    [ "$hit" -eq 1 ] && printf '%s' "$lane" | jq -r '.commands[] | select(type=="string")'
  done <<EOF
$(jq -c --arg k "$key" '.commands[$k].extraLanes[]? | {when: (.when // []), commands: (.commands // [])}' "$CONFIG" 2>/dev/null)
EOF
}
allow_unverified() { local key; key="$(commands_key)"; [ -n "$key" ] && [ "$(jq -r --arg k "$key" '.commands[$k].allowUnverified // false' "$CONFIG" 2>/dev/null)" = true ]; }
checks_list() { { config_checks "${1:-}"; record_checks; } | awk 'NF && !seen[$0]++'; }
CHANGED=""   # the files this branch touches since the record commit; read fail-closed by the caller before the checks (C20)
run_checks() { # run_checks <attempt> -> 0 green, 1 red; the log is the next build's findings
  local log="$STATE/checks-$1.log" cmd rc=0 n=0; : > "$log"
  while IFS= read -r cmd; do # setup lanes first, fail-fast: a failed install makes every later red bogus
    [ -n "$cmd" ] || continue; say "setup: $cmd"
    if lane "$cmd" >> "$log" 2>&1; then echo "ok (setup): $cmd" >> "$log"; else echo "RED (setup, aborting the rest): $cmd" >> "$log"; return 1; fi
  done <<EOF
$(setup_lanes)
EOF
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue; n=$((n+1)); say "check: $cmd"
    if lane "$cmd" >> "$log" 2>&1; then echo "ok: $cmd" >> "$log"; else echo "RED: $cmd" >> "$log"; rc=1; fi
  done <<EOF
$(checks_list)
EOF
  # "configured" is a config-TIME predicate, as the gate read it: a when-scoped lane that did not run on this diff
  # is still a configured check; only a repo with nothing under lint/typecheck/test/format, extraLanes and '## Checks' is unverified
  if [ "$n" -eq 0 ] && [ "$(checks_list all | grep -c .)" -eq 0 ]; then
    allow_unverified && { say "checks: none configured; commands.<repo>.allowUnverified is true, so this is declared, not silent"; return 0; }
    echo "RED: no check is configured under commands.* and none under '## Checks' — a zero-check run is not green (declare allowUnverified to accept it)" >> "$log"; return 1
  fi
  [ "$n" -gt 0 ] || say "checks: every configured lane is when-scoped and none matched this diff — configured, not unverified"
  return $rc
}

# -- route smoke (rows C24-C26, H7-H12) --
# Substitution is into a SHELL COMMAND STRING, so every value is single-quoted on the way in (a state is
# human prose, a route may carry `&`), and the template is walked rather than `${t//p/r}`: under bash 5.2's
# patsub_replacement a `&` in the replacement expands to the matched placeholder, silently. Both copied
# from the gate (shquote/subst); the placeholders appear UNQUOTED in the template, as documented there.
shquote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
subst() { # subst <template> <placeholder> <replacement>
  local t="$1" p="$2" r="$3" out=""
  while :; do
    case "$t" in
      *"$p"*) out="$out${t%%"$p"*}$r"; t="${t#*"$p"}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$t"
}
hash_file() { local h; h="$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)"; [ -n "$h" ] || h="$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"; [ -n "$h" ] && printf '%s' "$h"; }
route_smoke() { # route_smoke <attempt> -> 0 ok, 1 red (log at $STATE/smoke-<attempt>.log), 2 unconfigured; 3 not ready, 4 no hash tool (the caller refuses)
  local rows log="$STATE/smoke-$1.log"; rows="$(frames_rows)"; : > "$log"
  [ -n "$rows" ] || { [ -n "$RENDER_CMD" ] && say "smoke: the record's design section arms no render state"; return 0; }
  [ -n "$RENDER_CMD" ] && [ -n "$SMOKE_CMD" ] || return 2
  if [ -n "$READY_URL" ]; then # only when a render is about to happen; no `-f`, so an HTTP answer stays distinguishable from a transport failure
    local try=1 code crc reading=""
    while [ "$try" -le 3 ]; do
      code="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$READY_URL" 2>/dev/null)"; crc=$?
      case "$crc:$code" in 0:2??|0:3??) reading=ready; break ;; 0:*) reading="HTTP $code" ;; *) reading="curl exit $crc" ;; esac
      sleep $((try*2)); try=$((try+1))
    done
    [ "$reading" = ready ] || { READY_READING="$reading"; return 3; }
  fi
  SMOKE_LOG="$log"; SMOKE_RC=0
  local seen="" dup rs route state must png sha c
  while IFS='|' read -r rs route state _frame must; do
    [ -n "$rs" ] || continue
    png="$STATE/smoke-$rs.$1.png"; rm -f "$png"
    c="$(subst "$RENDER_CMD" '{route}' "$(shquote "$route")")"; c="$(subst "$c" '{state}' "$(shquote "$state")")"; c="$(subst "$c" '{out}' "$(shquote "$png")")"
    if ! lane "$c" >> "$log" 2>&1; then smoke_red "$rs render failed: $c"; continue; fi
    [ -s "$png" ] || { smoke_red "$rs exited 0 but wrote no image at $png"; continue; }
    sha="$(hash_file "$png")" || return 4
    # the {state}-blind-harness detector, as the gate ran it: a hash seen for ANY earlier state is red
    dup="$(printf '%s\n' "$seen" | awk -v s="$sha" '$1 == s { print $2; exit }')"
    [ -z "$dup" ] || smoke_red "render states $dup and $rs hash identically — the harness rendered the same view for two declared states"
    seen="$seen$sha $rs
"
    [ -n "$must" ] || { smoke_red "$rs declares no must-show value — the record must name one per screen (D-4)"; continue; }
    c="$(subst "$SMOKE_CMD" '{route}' "$(shquote "$route")")"; c="$(subst "$c" '{mustShow}' "$(shquote "$must")")"
    if lane "$c" >> "$log" 2>&1; then echo "ok: $rs shows '$must'" >> "$log"; say "smoke: $rs rendered to $png and shows '$must'"; else smoke_red "$rs must-show '$must' not satisfied"; fi
  done <<EOF
$rows
EOF
  return $SMOKE_RC
}
smoke_red() { echo "RED: $*" >> "$SMOKE_LOG"; say "smoke: $*"; SMOKE_RC=1; }

# -- the review input (rows I9-I11) --
review_input() { # review_input <attempt> -> writes $STATE/review-input-<attempt>.md; 1 when a diff cannot be read (the caller refuses)
  local out="$STATE/review-input-$1.md" ns full names
  ns="$(git -C "$WT" diff --name-status "$FIRST"..HEAD 2>/dev/null)" || return 1
  full="$(git -C "$WT" diff "$FIRST"..HEAD 2>/dev/null)" || return 1
  names="$(git -C "$WT" diff --name-only "$FIRST"..HEAD 2>/dev/null)" || return 1
  {
    echo "### Deleted or renamed test files"; awk '$1 ~ /^[DR]/ && $2 ~ /(\.spec\.|\.test\.|_test\.|\/tests?\/)/' <<<"$ns"; echo
    echo "### Added skips / forced-green lines"; grep -nE '^\+.*(\.skip\(|\.only\(|\|\| *true|xit\(|xdescribe\()' <<<"$full" || echo "(none)"; echo
    echo "### CI or check configuration edited"; grep -E '^\.github/|^\.gitlab|\.ya?ml$|^package\.json$|vitest\.config|jest\.config|\.eslintrc|tsconfig' <<<"$names" || echo "(none)"; echo
    echo "### Build session permission denials"; [ -s "$STATE/denials-$A.txt" ] && cat "$STATE/denials-$A.txt" || echo "(none)"
  } > "$out"
}

# -- the two prompts (rows F15-F20) --
build_prompt() { # build_prompt <round> <findings-file-or-empty>
  echo "Implement ticket $ISSUE of this repository. Fetch the ticket text yourself from the tracker (${TRACKER})."
  echo "Do not merge. Do not delete, skip or weaken a test to make a check pass; if a test is wrong, say so in the PR."
  [ "$BOT_OK" -eq 1 ] && echo "Commit through $TOOLS/bot-commit.sh (the repo's bot identity), never plain git commit — and re-pass the identity on any --amend, which otherwise silently re-stamps you as the committer."
  if [ "$1" -eq 1 ]; then
    echo "When the checks are green, commit, push branch $BRANCH to origin and, unless one is already open for this branch, open a READY (not draft) PR against the default branch with 'gh pr create'. The PR body, in order: line 1 exactly 'built-by: second-shift run $RUN_ID'; then a link to the decision record at $RECORD_REL; then a summary of the change;"
    if [ "$TRACKER" = github ]; then echo "and the line 'Closes #$ISSUE' so the ticket closes on merge."; else echo "and a '### Jira Items' heading with the line 'Closes [$ISSUE]'."; fi
  else echo "Address the review findings below: fix each, or rebut it in a PR comment. Then commit and push $BRANCH."; fi
  echo; echo "The following decisions were settled with the requester before implementation started. They are binding. The record is committed at $RECORD_REL; if you must depart from a row, edit that row in place (new resolution, provenance user-delegated, a one-line reason) and commit the edit with the code. Never post a comment starting with 'verdict:'."
  echo; record_at_first
  if [ -n "$(frames_rows)" ]; then
    echo; echo "This ticket has design frames. Follow the figma-faithful sequence: read every frame id in the '## Design frames' section first; write the token and component plan; before writing UI code, have a subagent read that plan against the frames and list what it would get wrong, then fix the plan. Render every screen with the repo's render command, open the PNG, compare it with its frame and fix what differs, up to three rounds per screen. A screen that shows an error page, a login page or a spinner is not done."
  fi
  echo; echo "Before opening the PR (or pushing a fix), run every command below and make it green (a lane gated on changed-file globs runs only when its files change):"; checks_list all | sed 's/^/- /'
  [ -n "$2" ] && { echo; echo "## Review findings"; cat "$2"; }
}
review_prompt() { # review_prompt <pr> <review-input-file>
  echo "You are reviewing PR #$1 of this repository at its current head, in a session separate from the one that built it. Check out the PR head. Read the decision record at $RECORD_REL as it stood at commit $FIRST (git show $FIRST:$RECORD_REL) and as it stands at the head."
  echo "Score EVERY row of the record against the code: honored, violated, departed (the row was edited; name who decided, per its provenance), or undeterminable (say what you could not read). A violated or undeterminable row is a blocker; neither may stand beside an approve."
  echo "Then run review-toolkit:review-lead over the PR diff and DECLARE THE PIPELINE DEFAULT PANEL when you invoke it: the fan-out defaults to scope-completeness-reviewer; security-reviewer, a11y-reviewer and unit-test-mutation-reviewer are selected only by an opt-in — a 'review panel' row in the record with user-answered or user-delegated provenance naming security, a11y or unit-test-mutation, or the config's reviewers.default[]. review-lead never infers this; an undeclared panel leaves the surface triggers in force."
  echo "review-lead dispatches its reviewers through the code-review.mjs Workflow: stage that script by copying it into $STATE (this run's evidence directory, already added to this session), never into the worktree, and run the Workflow from there."
  echo "If the ticket has design frames, render every screen at the head with the repo's render command and compare it with its frame; if you cannot render, you cannot approve: post 'verdict: needs-work' with a line 'reason: render-unavailable'."
  local via=""; [ "$BOT_OK" -eq 1 ] && via=" through $GH (the bot identity)"
  echo; echo "Post ONE PR comment$via. Its first line is exactly 'verdict: approve' or 'verdict: needs-work'; its second line is exactly 'reviewed: <the full sha of the head you reviewed>'. Then the row table, then findings. Never edit that comment afterwards."
  echo; echo "## Scheduler input (deleted or skipped tests, config edits, and the build's permission denials)"; cat "$2"
}
build_allowlist() { # row F3: derived from what the record and config name
  local allow="Read,Edit,Write,Agent,Bash(git *),Bash(gh pr create*),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh issue view*)$MCP_ALLOW" c
  [ "$BOT_OK" -eq 1 ] && allow="$allow,Bash($TOOLS/bot-commit.sh*),Bash($GH *)"
  [ -n "$(frames_rows)" ] && allow="$allow,mcp__figma,mcp__plugin_figma_figma"
  while IFS= read -r c; do [ -n "$c" ] && allow="$allow,Bash($(first_word "$c")*)"; done <<EOF
$(checks_list all)
EOF
  [ -n "$RENDER_CMD" ] && allow="$allow,Bash($(first_word "$RENDER_CMD")*)"
  printf '%s' "$allow"
}
review_allowlist() { # row F20: review-lead's panel is a Workflow whose agents inherit these tools
  local allow="Read,Grep,Glob,Agent,Skill,Workflow,Bash(find *),Bash(cp *),Bash(bash *check-review-context.sh*),Bash(git *),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh pr diff*),Bash(gh api*)$MCP_ALLOW"
  [ -n "$RENDER_CMD" ] && allow="$allow,Bash($(first_word "$RENDER_CMD")*)"
  [ -n "$(frames_rows)" ] && allow="$allow,mcp__figma,mcp__plugin_figma_figma"
  [ "$BOT_OK" -eq 1 ] && allow="$allow,Bash($GH *)"
  printf '%s' "$allow"
}

# -- the worktree (rows E17-E21, J6) --
worktree_inflight() { # the gate's predicate (milestone-gate.sh worktree_inflight), copied: 0 collected · 8 in flight · 1 unreadable
  local dirty unpushed; INFLIGHT_REASON=""
  dirty="$(git -C "$WT" status --porcelain 2>&1)" || { INFLIGHT_REASON="its status could not be read ($dirty)"; return 1; }
  if [ -n "$dirty" ]; then INFLIGHT_REASON="its tree is not clean"; return 8; fi
  # best effort, wrong only in the SAFE direction: a failed fetch can make pushed work look unpushed, never the reverse
  git -C "$WT" fetch --quiet origin "$BRANCH" >/dev/null 2>&1
  unpushed="$(git -C "$WT" log --oneline "refs/remotes/origin/$BRANCH..HEAD" 2>&1)" || { INFLIGHT_REASON="origin/$BRANCH is unresolvable, so nothing proves its work is pushed"; return 1; }
  if [ -n "$unpushed" ]; then INFLIGHT_REASON="it carries commits that are not on origin/$BRANCH"; return 8; fi
  return 0
}
worktree_ready() { # before a spawn: a detached tree is put back on the branch, a clean tree is fast-forwarded to origin; dirt is the build's own resume state and is left alone
  local ref dirty
  ref="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || terminal env-worktree "$WT is not a git worktree"
  dirty="$(git -C "$WT" status --porcelain 2>/dev/null)" || terminal env-worktree "cannot read the status of $WT"
  if [ -n "$dirty" ]; then
    [ "$ref" = "$BRANCH" ] || terminal env-worktree "$WT is detached and carries uncommitted work — put it on $BRANCH by hand"
    say "worktree: uncommitted work in $WT is left for the build"; return 0
  fi
  [ "$ref" = "$BRANCH" ] || git -C "$WT" checkout -q "$BRANCH" 2>/dev/null || terminal env-worktree "cannot put $WT on $BRANCH"
  git -C "$WT" fetch -q origin "$BRANCH" 2>/dev/null || terminal env-remote-unreadable "cannot fetch origin/$BRANCH into $WT"
  git -C "$WT" merge -q --ff-only "origin/$BRANCH" >/dev/null 2>&1 || terminal env-worktree-diverged "$WT and origin/$BRANCH have diverged — reconcile by hand and --resume"
}
sync_to_remote() { # after a collected build: the worktree at the pushed head, which is what the checks and the review read; sets HEAD_SHA
  git -C "$WT" fetch -q origin "$BRANCH" 2>/dev/null || terminal env-remote-unreadable "cannot fetch origin/$BRANCH after the build — a network blip is not the build's fault"
  git -C "$WT" merge -q --ff-only "origin/$BRANCH" >/dev/null 2>&1 || terminal env-worktree-diverged "$WT and origin/$BRANCH have diverged after the build"
  HEAD_SHA="$(git -C "$WT" rev-parse --verify "refs/remotes/origin/$BRANCH" 2>/dev/null)" || terminal env-remote-unreadable "origin/$BRANCH does not resolve after the fetch"
  [ "$(git -C "$WT" rev-parse HEAD 2>/dev/null)" = "$HEAD_SHA" ] || terminal env-worktree-diverged "$WT is not at origin/$BRANCH ($HEAD_SHA) after the fast-forward"
}
premise_holds() { # rows J2, J4-J8: re-asked before every build spawn; a predicate that cannot be evaluated is not one that passed
  local st base_now overlap
  st="$(issue_state)"; [ -n "$st" ] || terminal staleness-unreadable "could not read #$ISSUE from the tracker mid-run"
  [ "$st" = OPEN ] || terminal ticket-closed "#$ISSUE closed mid-run; worktree and claim left in place"
  git -C "$WT" fetch -q origin "$BASE_NAME" 2>/dev/null || terminal staleness-unreadable "could not fetch origin/$BASE_NAME"
  base_now="$(git -C "$WT" rev-parse -q --verify "refs/remotes/origin/$BASE_NAME" 2>/dev/null)" || terminal staleness-unreadable "origin/$BASE_NAME does not resolve"
  [ "$base_now" = "$BASE_START" ] && return 0
  local base_files ours
  base_files="$(git -C "$WT" diff --name-only "$BASE_START" "$base_now" 2>/dev/null)" || terminal staleness-unreadable "cannot diff origin/$BASE_NAME's move ($BASE_START..$base_now)"
  ours="$(git -C "$WT" diff --name-only "$FIRST" HEAD 2>/dev/null)" || terminal staleness-unreadable "cannot diff this branch against its record commit"
  overlap="$(comm -12 <(printf '%s\n' "$base_files" | sort) <(printf '%s\n' "$ours" | sort) | grep . | head -n 3 | tr '\n' ' ')"
  [ -z "$overlap" ] || terminal staleness-expired "origin/$BASE_NAME moved into file(s) this branch touches: $overlap"
}

# -- the PR (rows E7-E13, E16) --
pr_conventions() { # pr_conventions <pr> <attempt> -> 0, 1 unmet (reasons in $STATE/pr-conventions-<attempt>.txt), 2 unreadable (the caller refuses)
  local out="$STATE/pr-conventions-$2.txt" info body draft first
  info="$("$GH_READ" pr view "$1" --json body,isDraft 2>/dev/null)" || return 2
  body="$(printf '%s' "$info" | jq -r '.body // ""')"; draft="$(printf '%s' "$info" | jq -r '.isDraft // false')"
  : > "$out"
  [ "$draft" = false ] || echo "the PR is a draft; mark it ready for review" >> "$out"
  first="$(printf '%s\n' "$body" | head -n 1)"
  grep -q "^built-by: second-shift run " <<<"$first" || echo "PR body line 1 must be 'built-by: second-shift run <id>'" >> "$out"
  grep -qF "$RECORD_REL" <<<"$body" || echo "PR body must link the decision record at $RECORD_REL" >> "$out"
  if [ "$TRACKER" = github ]; then
    grep -qiE "(^|[^a-z])closes[[:space:]]+#$ISSUE([^0-9]|$)" <<<"$body" || echo "PR body must carry 'Closes #$ISSUE'" >> "$out"
  else # the gate's rule: the Closes line lives under the Jira Items heading, matched case-insensitively, any depth; the next heading closes it
    awk -v k="$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')" '
        { l = tolower($0) }
        l ~ /^#+[[:space:]]+jira items[[:space:]]*$/ { on = 1; next }
        on && l ~ /^#+[[:space:]]/ { on = 0 }
        on && l ~ ("closes[[:space:]]+\\[" k "\\]") { f = 1 }
        END { exit !f }' <<<"$body" \
      || echo "PR body must carry 'Closes [$ISSUE]' under a '### Jira Items' heading" >> "$out"
  fi
  [ ! -s "$out" ]
}
ci_status() { # one word for the report, never waited on (row G11)
  local out; out="$("$GH_READ" pr checks "$PR" --json name,state 2>/dev/null)" || { echo unavailable; return; }
  [ "$(printf '%s' "$out" | jq 'length')" -gt 0 ] || { echo none; return; }
  printf '%s' "$out" | jq -e 'any(.[]; .state=="FAILURE" or .state=="ERROR")' >/dev/null && { echo red; return; }
  printf '%s' "$out" | jq -e 'all(.[]; .state=="SUCCESS" or .state=="NEUTRAL" or .state=="SKIPPED")' >/dev/null && { echo green; return; }
  echo pending
}
# -- the verdict (rows I1-I5, I7): bound to the review window, unedited, naming the current head; the LAST binding comment wins --
verdict() { # verdict <start-iso> <end-iso> -> prints approve|needs-work and saves the body; 1 none binds; 2 the tracker could not be read
  local repo comments
  repo="$(repo_slug)" || return 2
  comments="$("$GH_READ" api "repos/$repo/issues/$PR/comments" --paginate 2>/dev/null)" || return 2
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$comments" \
    | jq -r --arg s "$1" --arg e "$2" --arg h "$HEAD_SHA" '
        .[] | select(.created_at >= $s and .created_at <= $e and .created_at == .updated_at)
        | select((.body | split("\n")[0]) | test("^verdict: (approve|needs-work)$"))
        | select((.body | split("\n")[1]) == ("reviewed: " + $h))
        | (.body | split("\n")[0] | sub("^verdict: ";"")) + "\t" + (.body | @base64)' \
    | tail -n 1 > "$STATE/verdict.tsv"
  [ -s "$STATE/verdict.tsv" ] || return 1
  cut -f2 "$STATE/verdict.tsv" | base64 --decode > "$STATE/verdict-body.md"
  cut -f1 "$STATE/verdict.tsv"
}
# -- the run block (rows E14-E16, I13, I14): in the PR BODY under the old lane's marker, at every terminal once a PR exists --
cost_block() { # <terminal slug>
  echo '<!-- pipeline-cost-block -->'
  echo "## second-shift run"; echo
  echo "| run | outcome | rounds | verdict | reviewed head | cost | CI |"; echo "| --- | --- | --- | --- | --- | --- | --- |"
  echo "| $RUN_ID | $1 | $ROUND | ${VERDICT:-none} | ${HEAD_SHA:-—} | \$$COST | $CI |"; echo
  echo "| session | turns | cost |"; echo "| --- | --- | --- |"
  local f; for f in "$STATE"/build-*.json "$STATE"/review-*.json; do
    [ -f "$f" ] && jq -r --arg n "$(basename "$f" .json)" '"| \($n) | \(.num_turns // "?") | $\((.total_cost_usd // 0) * 100 | round / 100) |"' "$f"
  done
  echo '<!-- /pipeline-cost-block -->'
}
write_run_block() { # <terminal slug>; a body that cannot be read is never replaced blind
  local repo body
  CI="$(ci_status)"; say "ci: $CI (read once for the report; the checks that gate a round ran here)"
  repo="$(repo_slug)" || { say "could not read the repo slug; the run block is NOT written"; return 0; }
  if ! body="$("$GH_READ" api "repos/$repo/pulls/$PR" --jq .body 2>/dev/null)"; then
    say "could not read PR #$PR's body; the run block is NOT written (a blind replace would erase the body)"; return 0
  fi
  # strip an earlier block: ours ends at the closing marker, the old lane's at its `Cache-hit rate:` line. CR-stripped
  # first (the gate's rule): a body round-tripped through the GitHub API carries CRLF, and `$0 == m` never matches then
  body="$(printf '%s\n' "$body" | tr -d '\r' | awk '$0 == "<!-- pipeline-cost-block -->"{skip=1} !skip{print} skip && ($0 == "<!-- /pipeline-cost-block -->" || /^Cache-hit rate: /){skip=0} END{if (skip) print "<!-- an earlier cost block had no terminator; text below it was not preserved -->"}')"
  printf '%s\n\n%s\n' "$body" "$(cost_block "$1")" > "$STATE/pr-body.md"
  "$GH" api -X PATCH "repos/$repo/pulls/$PR" -F "body=@$STATE/pr-body.md" >/dev/null 2>&1 || say "could not write the run block into PR #$PR's body (it is in $STATE/pr-body.md)"
}

# ============================ 3. preflight, read-only (rows A4, A13, A27, D10, D11, H1, J1, J3, K6-K8) ============================
say "run $RUN_ID: issue $ISSUE, tracker $TRACKER (writes $TRACKER_WRITES), branch $BRANCH, worktree $WT, record $RECORD_REL"
committed_record_exists() { # the branch already carries the record: the receipt on disk is no longer read at all
  git -C "$MAIN_ROOT" fetch -q origin "$BRANCH" 2>/dev/null || true
  local ref; for ref in "refs/remotes/origin/$BRANCH" "refs/heads/$BRANCH"; do git -C "$MAIN_ROOT" cat-file -e "$ref:$RECORD_REL" 2>/dev/null && return 0; done; return 1
}
if committed_record_exists; then RECORD_SOURCE=committed; say "record: already committed on $BRANCH — the receipt on disk is not consulted"
else RECORD_SOURCE=receipt; [ -f "$RECORD" ] || terminal env-no-record "no intake record at $RECORD — run /intake-toolkit:plan-interview $ISSUE first"; fi
bad_lane="$(lanes_malformed)"; [ -z "$bad_lane" ] || terminal env-config-lanes "commands.$(commands_key): $bad_lane"
# on the receipt, so a fresh run refuses before it claims; the committed record is re-checked in phase 5 and is what counts
if [ "$RECORD_SOURCE" = receipt ] && ! design_declared; then
  terminal env-design-undeclared "design.provider is configured but the record's design section ('## Design frames' or '## Design') neither carries RS rows nor a 'Design: none — <reason>' line — a UI ticket cannot skip the render silently"
fi
if [ "$DRY_RUN" -eq 1 ]; then
  say "dry-run: would claim, create the worktree, commit the record, and run up to $MAX_ROUNDS rounds; checks: $(checks_list all 2>/dev/null | tr '\n' ';')"
  echo "terminal: dry-run"; exit 0
fi
st="$(issue_state)"; [ -n "$st" ] || terminal env-tracker-unreadable "could not read #$ISSUE from the tracker"
[ "$st" = OPEN ] || terminal env-ticket-closed "#$ISSUE is not open — nothing spawned, a preflight refusal like any other"
if [ -z "$BUILD_MODEL" ]; then # an unsized ticket is refused with nothing written to the tracker
  if has_label opus; then BUILD_MODEL=opus; MODEL_BASIS=label
  elif has_label sonnet; then BUILD_MODEL=sonnet; MODEL_BASIS=label
  elif [ "$TRACKER" != github ]; then terminal usage-model "under $TRACKER pass --build-model: there is no sizing label to read"
  else terminal usage-model "#$ISSUE carries neither opus nor sonnet — intake sizes tickets, this scheduler does not (pass --build-model to override)"; fi
fi
say "models: build $BUILD_MODEL (${MODEL_BASIS:-flag}), review $REVIEW_MODEL (${REVIEW_MODEL_BASIS:-default})"

# ============================ 4. claim (rows D1-D12, D14-D16, K1-K4, K10) ============================
if [ "$TRACKER" != github ]; then say "claim: $TRACKER tracker — operator-attested, nothing written"
elif has_label "$L_CLAIMED"; then
  # re-entry, as the old lane read it: the claimed label AND a lane-posted marker; a claim with no marker was made by someone else
  if [ "$RESUME" -eq 1 ] || lane_marker_present; then say "claim: re-entering a ticket the lane claimed"; CLAIMED=1
  else terminal claimed-elsewhere "#$ISSUE carries $L_CLAIMED with no lane claim marker; pass --resume to take it over"; fi
else
  while IFS= read -r b; do [ -n "$b" ] && has_label "$b" && terminal not-queued "#$ISSUE carries blocker label $b"; done <<EOF
$L_BLOCKERS
EOF
  has_label "$L_QUEUE" || terminal not-queued "#$ISSUE does not carry $L_QUEUE — only the operator queues a ticket"
  # the atomic queue->claimed swap: add, confirm, remove, through claim-issue.sh when a bot is configured
  if [ "$BOT_OK" -eq 1 ]; then SECOND_SHIFT_CONFIG="${CONFIG:-}" bash "$TOOLS/claim-issue.sh" "$ISSUE" --queue "$L_QUEUE" --claimed "$L_CLAIMED" >/dev/null 2>&1 || terminal env-claim-failed "claim-issue.sh could not swap $L_QUEUE -> $L_CLAIMED on #$ISSUE; the queue label is left in place"
  else "$GH" issue edit "$ISSUE" --add-label "$L_CLAIMED" --remove-label "$L_QUEUE" >/dev/null 2>&1 || terminal env-claim-failed "could not swap $L_QUEUE -> $L_CLAIMED on #$ISSUE; the queue label is left in place"; fi
  # the claim marker, in the old lane's shape (re-entry and evidence readers grep it)
  # shellcheck disable=SC2016  # markdown backticks
  "$GH" issue comment "$ISSUE" --body "$(printf '<!-- dev-pipeline -->\n<!-- run_id: %s -->\n<!-- session_id: %s -->\n<!-- stage: lean-claimed -->\n\n🤖 Claimed by \`/dev-pipeline:run\`.\nsecond-shift-run: %s (branch %s)' "$RUN_ID" "${CLAUDE_CODE_SESSION_ID:-unset}" "$RUN_ID" "$BRANCH")" >/dev/null 2>&1 \
    || terminal env-claim-failed "labels swapped but the claim marker could not be posted on #$ISSUE — re-entry would refuse; fix the tracker write and --resume"
  CLAIMED=1
fi
mkdir -p "$STATE" || terminal env-state-dir "cannot create $STATE"

# ============================ 5. baseline (rows E3-E6, E17, E18, G7, H6, J6, J11) ============================
git -C "$MAIN_ROOT" fetch -q origin 2>/dev/null || true
base="$(git -C "$MAIN_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
for b in "$base" origin/main origin/master; do [ -n "$b" ] && git -C "$MAIN_ROOT" rev-parse -q --verify "$b" >/dev/null 2>&1 && { base="$b"; break; }; done
BASE_NAME="${base#origin/}"
if [ -d "$WT" ]; then
  wt_ref="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || terminal env-worktree "$WT exists but is not a git worktree"
  case "$wt_ref" in "$BRANCH"|HEAD) : ;; *) terminal env-worktree-mismatch "$WT is on branch '$wt_ref', not $BRANCH — remove it (git worktree remove) and re-launch" ;; esac
else
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null || true
  if git -C "$MAIN_ROOT" rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1 || git -C "$MAIN_ROOT" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
    git -C "$MAIN_ROOT" worktree add -q "$WT" "$BRANCH" 2>/dev/null || git -C "$MAIN_ROOT" worktree add -q --track -b "$BRANCH" "$WT" "origin/$BRANCH" || terminal env-worktree "could not attach $WT to $BRANCH"
  else
    git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$WT" "$base" || terminal env-worktree "could not create $WT from $base"
  fi
fi
# the staleness anchor is the branch point (merge-base), re-derived on re-entry so a move between runs is still seen
BASE_START="$(git -C "$WT" merge-base "origin/$BASE_NAME" HEAD 2>/dev/null)" || BASE_START=""
[ -n "$BASE_START" ] || terminal env-base-unreadable "cannot resolve the merge-base of origin/$BASE_NAME and $BRANCH"
if ! git -C "$WT" cat-file -e "HEAD:$RECORD_REL" 2>/dev/null; then # the record is the branch's first commit, pushed before any build
  mkdir -p "$WT/$(dirname "$RECORD_REL")" && cp "$RECORD" "$WT/$RECORD_REL" || terminal env-record-commit "could not place the record at $RECORD_REL"
  git -C "$WT" add "$RECORD_REL" || terminal env-record-commit "could not stage the record"
  if [ "$BOT_OK" -eq 1 ]; then SECOND_SHIFT_CONFIG="${CONFIG:-}" bash "$TOOLS/bot-commit.sh" -C "$WT" -q -m "docs: decision record for #$ISSUE" -- "$RECORD_REL" || terminal env-record-commit "bot-commit.sh could not commit the record"
  else git -C "$WT" commit -q -m "docs: decision record for #$ISSUE" -- "$RECORD_REL" || terminal env-record-commit "could not commit the record"; fi
  git -C "$WT" push -q -u origin "$BRANCH" || terminal env-push "could not push $BRANCH"
fi
FIRST="$(git -C "$WT" log --format=%H --diff-filter=A -- "$RECORD_REL" 2>/dev/null | tail -n 1)"
[ -n "$FIRST" ] || terminal env-no-first-commit "the record has no adding commit on $BRANCH"
say "record baseline: $FIRST"
design_declared || terminal env-design-undeclared "the committed record at $FIRST carries neither RS rows nor a 'Design: none — <reason>' line in its design section — the receipt on disk is not what the run reads"

# ============================ 6. rounds (rows B7-B9, B14-B16, E13, F1, F14, G1, G9, H12, I6, I12, I15, J8, J10, J12, J13, K12) ============================
red_attempt() { # a red check, smoke or convention spends the checks-red counter, never a round; its log is the next build's findings
  CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "$1 red $CHECKS_RED times (cost \$$COST)"
  FINDINGS="$2"; NEED_BUILD=1; say "$1 red — the findings are the log; another BUILD attempt of round $ROUND"
}
spawn() { # spawn <role> <model> <id> <allowlist> <max-turns> <prompt-file> -> rc (124 past the bound); the result JSON is $STATE/<role>-<id>.json
  local secs="$REVIEW_TO" extra=(); [ "$1" = build ] && secs="$BUILD_TO"
  # the review stages review-lead's Workflow script in this run's state dir: added, and outside the worktree
  [ "$1" = review ] && extra=(--add-dir "$STATE")
  bounded "$secs" "$STATE/$1-$3.json" "$CLAUDE" -p --model "$2" "${SPAWN_COMMON[@]}" ${extra[@]+"${extra[@]}"} --allowedTools "$4" --max-turns "$5" "$(cat "$6")"; local rc=$?
  add_cost "$STATE/$1-$3.json"; return $rc
}
FINDINGS=""; NEED_BUILD=1; NEED_CHECKS=1; INPUT=""
while :; do
  ROUND=$((ROUND+1)); [ "$ROUND" -le "$MAX_ROUNDS" ] || terminal rounds-spent "$MAX_ROUNDS rounds without an approve (cost \$$COST)"
  say "round $ROUND of $MAX_ROUNDS (cost so far \$$COST)"
  review_tries=0; VERDICT=""
  while :; do
    if [ "$NEED_BUILD" -eq 1 ]; then # ---- BUILD, until its work is collected on one ready PR ----
      premise_holds
      worktree_ready
      ATTEMPT=$((ATTEMPT+1)); A="$ROUND.$ATTEMPT"
      record_at_first >/dev/null || terminal env-worktree "cannot read the record at $FIRST:$RECORD_REL — a build must not be handed an empty record as binding"
      build_prompt "$ROUND" "$FINDINGS" > "$STATE/build-$A.prompt"
      spawn build "$BUILD_MODEL" "$A" "$(build_allowlist)" 400 "$STATE/build-$A.prompt"; brc=$?
      jq -r '.permission_denials[]? | (.tool_name + " " + (.tool_input|tostring))' "$STATE/build-$A.json" > "$STATE/denials-$A.txt" 2>/dev/null || true
      [ "$brc" -eq 124 ] && terminal build-blocked "build session exceeded ${BUILD_TO}s; worktree and claim left in place"
      sub="$(jq -r '.subtype // "unreadable"' "$STATE/build-$A.json" 2>/dev/null)"
      [ "$sub" = success ] || terminal build-blocked "build session ended $sub (rc=$brc); worktree and claim left in place"
      over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
      worktree_inflight; ifrc=$?
      case "$ifrc" in
        0) : ;;
        8) terminal build-inflight "the BUILD session exited 0 but $WT still holds work nothing else has a copy of ($INFLIGHT_REASON) — push from the worktree and --resume; nothing here discards it" ;;
        *) terminal build-inflight-unreadable "whether $WT still holds work could not be evaluated ($INFLIGHT_REASON) — reviewing on that guess is the defect this check exists to remove" ;;
      esac
      prs="$(open_prs)" || terminal env-tracker-unreadable "could not list the open PRs on $BRANCH"
      n="$(printf '%s\n' "$prs" | grep -c .)"
      [ "$n" -ne 0 ] || terminal build-no-pr "no open PR on $BRANCH after the BUILD session — nothing to review; a human decides what happens next. Worktree and claim left in place"
      [ "$n" -eq 1 ] || terminal pr-ambiguous "$n open PRs on $BRANCH: $(printf '%s' "$prs" | tr '\n' ' ')"
      PR="$prs"; PR_URL="$("$GH_READ" pr view "$PR" --json url --jq .url 2>/dev/null)" || PR_URL=""
      NEED_BUILD=0; NEED_CHECKS=1
      pr_conventions "$PR" "$A"; crc=$?
      [ "$crc" -ne 2 ] || terminal env-tracker-unreadable "PR #$PR could not be read — a conventions check that cannot run is not one that passed"
      [ "$crc" -eq 0 ] || { red_attempt "PR conventions" "$STATE/pr-conventions-$A.txt"; continue; }
    fi
    # ---- the checks the build did not run, at the pushed head; re-run only when the head moved (ids: the build attempt, suffixed on a re-spawn) ----
    RA="$A"; [ "$review_tries" -eq 0 ] || RA="$A-retry$review_tries"
    if [ "$NEED_CHECKS" -eq 1 ]; then
      sync_to_remote
      CHANGED="$(git -C "$WT" diff --name-only "$FIRST" HEAD 2>/dev/null)" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT — a diff that cannot be read must not skip every when-scoped lane"
      run_checks "$RA" || { red_attempt checks "$STATE/checks-$RA.log"; continue; }
      route_smoke "$RA"; src=$?
      [ "$src" -ne 2 ] || terminal env-smoke-unconfigured "the record declares design frames but design.liveRender.command/smokeCommand is not configured"
      [ "$src" -ne 3 ] || terminal env-not-ready "readyProbe $READY_URL is not ready after 3 tries (last reading: $READY_READING) — start the service and --resume"
      [ "$src" -ne 4 ] || terminal env-hash-tool "cannot hash a render: neither shasum nor sha256sum is on PATH"
      [ "$src" -eq 0 ] || { red_attempt smoke "$STATE/smoke-$RA.log"; continue; }
      review_input "$RA" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT"
      INPUT="$STATE/review-input-$RA.md"; NEED_CHECKS=0
    fi
    # ---- REVIEW: a fresh session bound to this head and its window; re-spawned once when it leaves no binding verdict ----
    review_prompt "$PR" "$INPUT" > "$STATE/review-$RA.prompt"
    start="$(now)"
    spawn review "$REVIEW_MODEL" "$RA" "$(review_allowlist)" 300 "$STATE/review-$RA.prompt"; rrc=$?
    end="$(now)"
    rsub="$(jq -r '.subtype // "unreadable"' "$STATE/review-$RA.json" 2>/dev/null)"
    miss=""
    if [ "$rrc" -eq 124 ]; then miss="the review session exceeded ${REVIEW_TO}s"
    elif [ "$rsub" != success ]; then miss="the review session ended $rsub (rc=$rrc)"
    else
      VERDICT="$(verdict "$start" "$end")"; vrc=$?
      [ "$vrc" -ne 2 ] || terminal env-tracker-unreadable "the PR's comments could not be read after the review — an environment refusal, not a verdict; --resume"
      if [ "$vrc" -ne 0 ]; then miss="no unedited 'verdict:' comment naming head $HEAD_SHA was posted between $start and $end"
      else after="$(remote_head)" || terminal env-remote-unreadable "cannot read origin/$BRANCH after the review — the approve is not discarded for a network blip; --resume"
        [ "$after" = "$HEAD_SHA" ] || { miss="the head moved during the review ($HEAD_SHA -> $after); the checks re-run on the new head"; NEED_CHECKS=1; }; fi
    fi
    [ -n "$miss" ] || break
    review_tries=$((review_tries+1))
    [ "$review_tries" -le "$MAX_REVIEW_RETRIES" ] || terminal review-unbound "$miss — twice. No round spent and no BUILD spawned; run /dev-pipeline:review $PR by hand"
    say "$miss — re-spawning REVIEW ($review_tries of $MAX_REVIEW_RETRIES). No round spent, no BUILD spawn."
    over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
  done
  say "verdict: $VERDICT (reviewed $HEAD_SHA)"
  [ "$VERDICT" = approve ] && break
  FINDINGS="$STATE/verdict-body.md"; NEED_BUILD=1
  over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
done

# ============================ 7. close-out (rows E19, E20) ============================
worktree_inflight; ifrc=$?
case "$ifrc" in
  0) git -C "$MAIN_ROOT" worktree remove "$WT" >/dev/null 2>&1 && say "worktree $WT removed; the branch and PR #$PR stay" || say "worktree $WT left in place (a lock, or a removal that failed); remove it by hand" ;;
  8) terminal closeout-inflight "approved, but $WT still holds work nothing else has a copy of ($INFLIGHT_REASON) — the ticket is still claimed and PR #$PR is still open" ;;
  *) terminal closeout-inflight-unreadable "approved, but whether $WT still holds work could not be evaluated ($INFLIGHT_REASON)" ;;
esac
terminal approved "PR #$PR approved at $HEAD_SHA after $ROUND round(s), \$$COST"
