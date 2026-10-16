#!/usr/bin/env bash
# run.sh — the unattended scheduler: one ticket in, an approved PR out.
#
# usage: run.sh <issue> [--build-model|--model <id>] [--model-basis <text>]
#               [--review-model <id>] [--review-model-basis <text>]
#               [--max-rounds N] [--resume] [--detach] [--handoff]
#   The build model comes from the ticket's `opus` / `sonnet` label; --build-model overrides.
#   Review defaults to `opus`; a departure needs --review-model-basis. The short forms `opus` /
#   `sonnet` are passed through to `claude --model`, which resolves them to the current model of
#   that tier — no model id is written here, so a new release needs no edit.
#   --handoff (/dev-pipeline:build): claim, worktree and record as usual, then write the round-1
#   build prompt and stop with `terminal: build-handoff` instead of spawning BUILD; the calling
#   session builds. No model is resolved: the calling session is the build. While that handoff is
#   the lane's latest closing comment, a run refuses the claim (claimed-elsewhere) unless --resume.
#
# env:  SECOND_SHIFT_CONFIG   config path (default <main>/.claude/second-shift.config.json)
#       RUN_CLAUDE, RUN_GH (alias GH)   the binaries (tests inject fakes)
#       RUN_WORKTREE_ROOT     default <parent of main>/<repo>-worktrees
#       RUN_BUILD_TIMEOUT / RUN_REVIEW_TIMEOUT   seconds (7200 / 3600), positive integers. Each also sets the session's
#                             own waits, 300 s inside the bound: BUILD runs with background tasks off and its Bash
#                             timeouts at that value (floor 120 s); REVIEW's background-task wait (floor 600 s)
#       RUN_COST_CEILING      USD (100); RUN_CHECKS_RED_MAX (3)
#       SECOND_SHIFT_INTAKE_TOOLKIT_ROOT   the intake-toolkit whose ledger-lint.sh lints the receipt (default: the
#                             installPath of the enabled intake-toolkit record in `claude plugin list --json`)
#       Env beats config `run.*` beats these defaults; an explicit --max-rounds beats config.
#       RUN_WATCH_CMD         unset = off. A --detach run calls it ONCE, when its worktree is first ready, from the main
#                             checkout in its own process group under a 10 s bound: `<cmd> <issue> <repo> <detach-log>
#                             <worktree>`. Its output goes to <state>/watch.out; whatever it does is one `watch:` log line
#                             and changes nothing else. herdr-adapter.sh beside this file is the bundled one (a herdr
#                             workspace per ticket); RUN_WATCH_EDITOR=code|cursor makes it open the worktree too.
#                             Every session and lane check runs with HERDR_*, RUN_WATCH* and RUN_DETACHED_LOG unset.
#
# What it does, in order (each phase's invariant in parentheses):
#   0 parse      (reads argv only; a usage error exits 2 with nothing written)
#   1 environment(every config read fails closed under a named slug; nothing written)
#   2 detach     (re-exec under setsid; the log's last line carries the run's exit code, a forwarded signal's too)
#   3 preflight  (read-only, fixed order: record, lanes, design, receipt lint, ticket open, model)
#   4 claim      (the first write: the label swap and the claim marker, or a re-entry)
#   5 baseline   (worktree on the branch; the record is the branch's first commit, pushed)
#   6 rounds     (premise; worktree at the pushed head; BUILD; in-flight check; one PR;
#                 conventions; checks from the first commit; the plan's AC coverage
#                 (tools/plan-coverage.sh: the record at the first commit, the plan at the head, and
#                 the record at the head for an AC added under a recorded departure);
#                 fails without the change (the head's tagged test files on the record commit's
#                 tree, run through commands.<id>.testRunners — per file, or one batch per
#                 reporting runner — each named test must fail there; a pending one, and each
#                 selected case, must then pass at the head);
#                 route smoke; review input;
#                 REVIEW in a fresh session, re-spawned once when dark; verdict bound to the
#                 review window, unedited, naming the current head, its body backing its own
#                 verdict line (tools/verdict-check.sh); the bound verdict posted as the
#                 `second-shift/review` commit status on that head)
#   7 close-out  (run block on the PR at every terminal once one exists; closing comment
#                 when the run claimed; teardown of a clean worktree on approve; the run's
#                 scratch dir archived to <state>/scratch.tar and removed at every exit)
#
# Rules every line below keeps:
#   - a predicate that cannot be evaluated refuses under a named slug; a failed read is never a pass;
#   - no refusal inside `$(...)`, a pipe or a piped loop — producers return non-zero, the CALLER refuses;
#   - nothing here discards work: no `reset --hard`, no forced removal, no checkout over a dirty tree (the
#     fails-without-the-change leg detaches only a tree with no tracked change, and goes back by an unforced
#     checkout); the one history rewrite is rebase_onto_base's clean rebase onto a moved base, pushed under a lease;
#   - the record's sections, the checks and the frames are read from its FIRST commit, never the head —
#     two exceptions: the verdict check reads the record at the head too, so a row the build added is scored (#991),
#     and the plan's AC coverage reads it for an AC added under a recorded departure, and nothing else (#1085);
#   - every session is a fresh process with a wall-clock bound; every attempt keeps its own files;
#   - a regex or record form is stated exactly, never paraphrased.
#
# exit: 0 approved · build-handoff
#       1 stopped for a human: build-no-pr, build-inflight(-unreadable), build-blocked, pr-ambiguous,
#         closeout-inflight(-unreadable), staleness-unreadable, verdict-uncheckable (the bound verdict's
#         body could not be checked against the record), plan-coverage-uncheckable (the record's Test intent
#         at its first commit could not be read as an AC set), baseline-unwritten (a clean rebase was pushed but
#         the PR body's 'Record baseline:' line could not be moved to the new record commit)
#       2 usage-* (the argv), env-* (the environment; most fire before anything is spawned, but
#         env-not-ready, env-worktree*, env-remote-unreadable, env-tracker-unreadable,
#         env-smoke-unconfigured, env-perl and env-state-dir can fire after a paid session; env-receipt-lint-unavailable: no
#         trusted lint for the receipt), claimed-elsewhere
#       3 RESUMABLE — not-queued, env-no-record, env-receipt-invalid: pay off intake and re-launch the same command
#       4 budget spent — rounds-spent, checks-red-spent, cost-spent
#       5 review-unbound — no verdict usable against the current head, after one re-spawn (a verdict
#         whose body breaks the verdict grammar is not usable)
#       7 the premise expired mid-run — ticket-closed, staleness-expired (the base moved into this branch's
#         files and the rebase onto it conflicts, or could not be made on a clean tree; a clean one goes on)
#       129 / 130 / 143 interrupted by HUP / INT / TERM; the session is reaped, the claim is left in place. A
#                 detached run forwards each of them, sent to its printed pid or its process group, to the run
# Every exit prints `terminal: <slug>` as its last stdout line so a wrapper routes on the slug.
set -uo pipefail

# ============================ 0. parse (rows A1-A13, A19) ============================
usage_refusal() { echo "run.sh: $2" >&2; echo "terminal: $1"; exit 2; }
CLAUDE="${RUN_CLAUDE:-claude}"; GH="${RUN_GH:-${GH:-gh}}"
REVIEW_MODEL_DEFAULT="opus"
ISSUE=""; MAX_ROUNDS=3; MAX_ROUNDS_SET=0; BUILD_MODEL=""; MODEL_BASIS=""
REVIEW_MODEL="$REVIEW_MODEL_DEFAULT"; REVIEW_MODEL_BASIS=""; RESUME=0; DETACH=0; HANDOFF=0
KEEP_ARGS=()   # what a detached run re-executes with: everything but --detach
while [ $# -gt 0 ]; do
  case "$1" in
    --build-model|--model)  BUILD_MODEL="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --model-basis)          MODEL_BASIS="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --review-model)         REVIEW_MODEL="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --review-model-basis)   REVIEW_MODEL_BASIS="${2-}"; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --max-rounds)           MAX_ROUNDS="${2-}"; MAX_ROUNDS_SET=1; KEEP_ARGS+=("$1" "${2-}"); shift 2 ;;
    --max-continuations)    usage_refusal usage-max-continuations "--max-continuations was removed in #718 along with the continuation budget it bounded: BUILD is spawned once per round, and a spawn that leaves no PR ends the run for a human to read. There is no value of this flag to pass." ;;
    --dry-run)              usage_refusal usage-dry-run "--dry-run was removed: the real run makes the same preflight checks before it claims anything, and stops on the first one that fails." ;;
    --resume)               RESUME=1; KEEP_ARGS+=("$1"); shift ;;
    --detach)               DETACH=1; shift ;;
    --handoff)              HANDOFF=1; shift ;;
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
[ "$HANDOFF" -eq 0 ] || [ "$DETACH" -eq 0 ] || usage_refusal usage-handoff-detach "--handoff stops before the build for the calling session to run it; there is nothing to detach."

# ============================ 1. environment (rows A20-A27, B1-B4, C1-C14, C28) ============================
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { echo "$(now) [run] $*"; }
exit_code_for() { # the taxonomy a wrapper branches on
  case "$1" in
    approved|build-handoff) echo 0 ;;
    not-queued|env-no-record|env-receipt-invalid) echo 3 ;;
    usage-*|env-*|claimed-elsewhere) echo 2 ;;
    rounds-spent|checks-red-spent|cost-spent) echo 4 ;;
    review-unbound) echo 5 ;;
    ticket-closed|staleness-expired) echo 7 ;;
    *) echo 1 ;;
  esac
}
# Run state the terminal reports on. Set as the run advances; empty until then.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
COST=0; UNPRICED=""; ROUND=0; ATTEMPT=0; CHECKS_RED=0; CLAIMED=0; PR=""; PR_URL=""; PR_DRAFT=""; HEAD_SHA=""; VERDICT=""; CI=""; FIRST=""; CHILD=""; TRACKER=""
# A tracker comment is public: no local path leaves this machine through one. The worktree becomes
# <worktree>, a path in the checkout becomes repo-relative, the home directory becomes ~, and any
# other /Users/<name> or /home/<name> prefix is cut — the detail stays whole in the local log.
public_text() { # public_text <text>
  local t="$1"
  [ -n "${WT:-}" ] && t="${t//"$WT"/<worktree>}"
  [ -n "${MAIN_ROOT:-}" ] && { t="${t//"$MAIN_ROOT"\//}"; t="${t//"$MAIN_ROOT"/<checkout>}"; }
  [ -n "${HOME:-}" ] && t="${t//"$HOME"/\~}"
  printf '%s' "$t" | sed -E 's#/(Users|home)/[^/[:space:]]+#~#g'
}
terminal() { # terminal <slug> <detail> — rows B1, B21, B22, K9: the run block on the PR whenever one exists, one closing comment when the run claimed
  say "terminal: $1 — $2"; echo "terminal: $1"
  if [ -n "$PR" ] && [ "${BLOCK_DONE:-0}" -eq 0 ]; then BLOCK_DONE=1; write_run_block "$1"; fi
  if [ "$CLAIMED" -eq 1 ] && [ "$TRACKER" = github ]; then
    "$GH" issue comment "$ISSUE" --body "$(printf 'second-shift run %s: %s — %s\n%s\ncost_usd: %s\n%s' "$RUN_ID" "$1" "$(public_text "$2")" "${PR_URL:-${PR:+PR #$PR}}" "$(usd "$COST")" "${UNPRICED:+unpriced: $UNPRICED (no total_cost_usd; cost_usd is a lower bound)
}")" >/dev/null 2>&1 || say "could not post the closing comment on #$ISSUE"
  fi
  scratch_close
  exit "$(exit_code_for "$1")"
}
# #964 D-1 D-2: the run's scratch dir (logs, probes, PR/comment/verdict bodies), outside .claude/ and the worktree.
# Created once $STATE exists; at every exit, the traps' included, it is archived to $STATE/scratch.tar and then
# removed, so /tmp is left clean and a blocked run's probes survive as evidence. A failed archive keeps the dir.
SCRATCH=""
scratch_close() {
  [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || return 0
  local d="$SCRATCH" err; SCRATCH=""
  if err="$(tar -C "$d" -cf "$STATE/scratch.tar" . 2>&1)" && tar -tf "$STATE/scratch.tar" >/dev/null 2>&1; then
    rm -rf -- "$d" && say "scratch: archived to $STATE/scratch.tar and removed"
  else say "scratch: NOT archived ($(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)); $d left in place"; fi
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
CONFIG_LOCAL="${CONFIG%.json}.local.json"   # C6a: the per-engineer override beside it, read below
# The config is read once, here, and every later read is of this copy in memory: a build session, or a check lane running
# code the build wrote, can edit the file mid-run, and an edit must not change the checks a run holds that build to.
CONFIG_JSON=""
if [ -f "$CONFIG" ]; then CONFIG_JSON="$(cat "$CONFIG" 2>/dev/null)"; jq -e . <<<"$CONFIG_JSON" >/dev/null 2>&1 || terminal env-config-unparseable "$CONFIG is present but not JSON — refusing to fall back to defaults"
else CONFIG=""; fi
# C2: an unmigrated v2 config is refused, never half-honored (configVersion 3 removed these keys)
if [ -n "$CONFIG" ]; then
  stale="$(jq -r '[ (["topology","gates","stageParams","grillWaivers"][] as $k | select(has($k)) | $k),
      (if (.design.liveRender | type) == "object" then (["tolerancePx","cwd"][] as $k | select(.design.liveRender | has($k)) | "design.liveRender.\($k)") else empty end),
      (if (.configVersion | type) == "number" and .configVersion < 3 then "configVersion \(.configVersion)" else empty end) ] | join(", ")' <<<"$CONFIG_JSON" 2>/dev/null)"
  [ -z "$stale" ] || terminal env-config-stale "$CONFIG is a configVersion 2 config ($stale) — migrate it with docs/migrations/v2-to-v3.md, then re-launch"
fi
# C6a: each engineer may name their own branch namespace in a gitignored <config>.local.json. It sets
# tracker.branchPrefix and the bot's GitHub App keys (#1059 D-3: a repo may keep the app's ids out of its
# committed config) and nothing else: a personal file must not change what the team's runs check or how
# they claim. The app keys are checked by name only, any value type (D-6); every leaf counts, false and null
# included. A committed "local" file is a team decision nobody reviewed as one, so it is refused too.
LOCAL_PREFIX=""
if [ -f "$CONFIG_LOCAL" ]; then
  jq -e 'type == "object"' "$CONFIG_LOCAL" >/dev/null 2>&1 || terminal env-config-local "$CONFIG_LOCAL is present but not a JSON object — fix or delete it"
  local_extra="$(jq -r '[paths(type | IN("object","array") | not) | map(tostring) | select(. != ["tracker","branchPrefix"])
      | select(.[0:3] != ["tracker","bot","app"] or length < 4 or (.[3] | IN("clientId","appName","privateKeyFilename","installationId") | not))
      | join(".")] | join(", ")' "$CONFIG_LOCAL")"
  [ -z "$local_extra" ] || terminal env-config-local "$CONFIG_LOCAL sets $local_extra — the per-engineer file may set tracker.branchPrefix and tracker.bot.app.{clientId,appName,privateKeyFilename,installationId} only; team settings belong in the committed config"
  jq -e '.tracker.branchPrefix | . == null or (type == "string" and length > 0)' "$CONFIG_LOCAL" >/dev/null 2>&1 \
    || terminal env-config-local "$CONFIG_LOCAL: tracker.branchPrefix must be a non-empty string"
  ! git -C "$MAIN_ROOT" ls-files --error-unmatch -- "$CONFIG_LOCAL" >/dev/null 2>&1 \
    || terminal env-config-local "$CONFIG_LOCAL is committed — it is per-engineer: git rm --cached it and add it to .gitignore"
  LOCAL_PREFIX="$(jq -r '.tracker.branchPrefix // empty' "$CONFIG_LOCAL")"
fi
cfg() { [ -n "$CONFIG" ] && jq -r "$1 // empty" <<<"$CONFIG_JSON" 2>/dev/null || true; }             # strings; a literal false would be swallowed, so booleans go through cfg_bool
cfg_bool() { [ -n "$CONFIG" ] && jq -r "if $1 == null then \"\" else ($1|tostring) end" <<<"$CONFIG_JSON" 2>/dev/null || true; }
# this process's own tools read the resolved path (F10); the sessions, whose worktree may carry no config, read a
# copy in their scratch dir (spawn)
[ -n "$CONFIG" ] && export SECOND_SHIFT_CONFIG="$CONFIG"

TRACKER="$(cfg .tracker.type)"; TRACKER="${TRACKER:-github}"                                            # C3
case "$TRACKER" in github|jira) : ;; *) terminal env-tracker-type "tracker.type '$TRACKER' is not github or jira — a typo must not silently pick the arm that attests less" ;; esac
TRACKER_WRITES="$(cfg_bool .tracker.writes)"                                                             # C4
if [ "$TRACKER" = github ]; then TRACKER_WRITES="${TRACKER_WRITES:-true}"; else TRACKER_WRITES="${TRACKER_WRITES:-false}"; fi
KEY_PATTERN="$(cfg .tracker.keyPattern)"                                                                 # C5
PLANS_DIR="$(cfg .paths.plansDir)"; PLANS_DIR="${PLANS_DIR:-docs/plans}"                                 # C13
STATE_DIR="$(cfg .paths.pipelineStateDir)"; STATE_DIR="${STATE_DIR:-.claude/pipeline-state}"             # C14
RUNTIME_DATA="$(cfg '.paths.runtimeData[]?')"   # one pathspec per line; unset = close-out checks no ignored paths
BASE_CFG="$(cfg .baseBranch)"   # the branch the lane forks from and targets; unset = the remote default (resolved in preflight)
RENDER_CMD="$(cfg .design.liveRender.command)"; SMOKE_CMD="$(cfg .design.liveRender.smokeCommand)"       # C24 C25
READY_URL="$(cfg .design.liveRender.readyProbe)"; DESIGN_PROVIDER="$(cfg .design.provider)"              # C26 C23
L_QUEUE="$(cfg .tracker.labels.queue)"; L_QUEUE="${L_QUEUE:-ready-for-dev}"                              # C8
L_CLAIMED="$(cfg .tracker.labels.claimed)"; L_CLAIMED="${L_CLAIMED:-in-progress}"                        # C9
if [ -n "$CONFIG" ] && [ "$(jq -r '.tracker.labels.blockers | type' <<<"$CONFIG_JSON" 2>/dev/null)" = array ]; then L_BLOCKERS="$(jq -r '.tracker.labels.blockers | join("\n")' <<<"$CONFIG_JSON")"   # C10: [] means none
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
    # #1059 D-5 D-7: the commits go through bot-commit.sh, which names the bot from tracker.bot.app.appName — the main
    # checkout's local file first (whatever $CONFIG names), else the config. With neither, every commit lands as the
    # operator: warn, never refuse, because onboard leaves an enabled bot with no appName and those runs work today.
    APP_LOCAL="$MAIN_ROOT/.claude/second-shift.config.local.json"
    app_name="$(jq -r '.tracker.bot.app.appName // empty' "$APP_LOCAL" 2>/dev/null || true)"; [ -n "$app_name" ] || app_name="$(cfg .tracker.bot.app.appName)"
    [ -n "$app_name" ] || say "WARN: tracker.bot.enabled is true but tracker.bot.app.appName is set in neither $CONFIG nor $APP_LOCAL — this run's commits will land as the operator, not the bot; put tracker.bot.app.appName in $APP_LOCAL (or in the committed config)"
  elif [ "$(cfg_bool .tracker.bot.enabled)" = true ]; then terminal env-bot "tracker.bot.enabled is true but the wrapper is $bot_status — refusing to write as the operator in the bot's place"; fi
fi
# C6 C6a C7 E1 E2: the branch namespace — the engineer's local override, else configured, else the dominant
# prefix among remote branches, else REFUSE
BP_RESOLVER="$TOOLS/branch-prefix.sh"
PREFIX="$(cfg .tracker.branchPrefix)"
if [ -n "$LOCAL_PREFIX" ]; then
  overrides=""; [ -z "$PREFIX" ] || overrides=" (overrides the committed '$PREFIX')"
  say "branch prefix '$LOCAL_PREFIX' from $(basename "$CONFIG_LOCAL")$overrides"
  PREFIX="$LOCAL_PREFIX"
fi
if [ -z "$PREFIX" ]; then
  bp_err="$(mktemp "${TMPDIR:-/tmp}/run-bp.XXXXXX")"
  PREFIX="$(bash "$BP_RESOLVER" --configured "" --tracker "$TRACKER" ${KEY_PATTERN:+--key-pattern "$KEY_PATTERN"} --repo "$MAIN_ROOT" 2>"$bp_err")" \
    || { msg="$(tr '\n' ' ' < "$bp_err" | cut -c1-300)"; rm -f "$bp_err"; terminal env-branch-prefix "tracker.branchPrefix is unset and no dominant prefix exists among remote branches: $msg"; }
  rm -f "$bp_err"
fi
BRANCH="${PREFIX}$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')"
WT_ROOT="${RUN_WORKTREE_ROOT:-$(dirname "$MAIN_ROOT")/${REPO_SLUG}-worktrees}"; WT="$WT_ROOT/$ISSUE"
RECORD_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-decisions.md"
PLAN_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-plan.md"   # #1039 D-4: the build's test-first task plan, beside the record
RECORD="$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md"   # the receipt's one conventional path (/intake-toolkit:intake's Receipt stage writes it there)
# C28 A23 D-6: caps — env, else config run.*, else the defaults; each must be a positive number, and a count or a
# bound a positive integer: bash arithmetic and `[ -lt ]` fail on a fraction, and a failed expansion abandons the round loop
cap() { # cap <var> <env value> <config key> <default> [int] — sets <var> in this shell (a refusal must not sit inside a substitution)
  local v="$2"; [ -n "$v" ] || v="$(cfg "$3")"; [ -n "$v" ] || v="$4"
  if [ "${5:-}" = int ]; then
    [[ "$v" =~ ^([0-9]+)\.0*$ ]] && v="${BASH_REMATCH[1]}"   # jq -r prints a config 7200.0 as written; config-lint accepts it
    case "$v" in ''|*[!0-9]*) terminal env-config-run "${3#.} must be a positive integer, got '$v'" ;; esac
    v=$((10#$v)); [ "$v" -gt 0 ] || terminal env-config-run "${3#.} must be a positive integer, got '$v'"
  fi
  case "$v" in ''|*[!0-9.]*|0|0.0) terminal env-config-run "${3#.} must be a positive number, got '$v'" ;; esac
  printf -v "$1" '%s' "$v"
}
[ "$MAX_ROUNDS_SET" -eq 1 ] || cap MAX_ROUNDS "" .run.maxRounds 3 int
cap BUILD_TO "${RUN_BUILD_TIMEOUT:-}" .run.buildTimeoutSeconds 7200 int
cap REVIEW_TO "${RUN_REVIEW_TIMEOUT:-}" .run.reviewTimeoutSeconds 3600 int
cap COST_CEIL "${RUN_COST_CEILING:-}" .run.costCeilingUsd 100
cap CHECKS_RED_MAX "${RUN_CHECKS_RED_MAX:-}" .run.checksRedMax 3 int
# F-env: a session's own waits end 5 minutes inside its bound, never below the harness's own 120 s / 600 s, so a hung
# command or dispatch fails inside the session while it can still commit and report; capped at the JS timer maximum
inner_ms() { local s=$(($1-300)); [ "$s" -ge "$2" ] || s="$2"; s=$((s*1000)); [ "$s" -le 2147483647 ] || s=2147483647; printf '%s' "$s"; }
BUILD_BASH_MS="$(inner_ms "$BUILD_TO" 120)"; REVIEW_BG_WAIT_MS="$(inner_ms "$REVIEW_TO" 600)"
MAX_REVIEW_RETRIES=1                                                                                    # K12
LOG_DIR="$MAIN_ROOT/$STATE_DIR"; STATE="$LOG_DIR/run-$ISSUE/$RUN_ID"

# ============================ 2. detach (rows A16-A18) ============================
if [ "$DETACH" -eq 1 ]; then
  command -v perl >/dev/null 2>&1 || terminal env-detach-perl "--detach needs perl for setsid; run in the foreground instead"
  mkdir -p "$LOG_DIR" 2>/dev/null || terminal env-detach-log-dir "--detach cannot create $LOG_DIR for the run's log"
  DETACH_LOG="$LOG_DIR/$ISSUE-lean-run-$(now | tr -d ':-')-$$.log"
  # D-28: the printed pid is the wrapper, which forwards TERM/INT/HUP to the run and always writes the exit line, so a kill
  # of that pid or of the whole process group stops the run through its own trap instead of orphaning it. nohup leaves HUP
  # ignored and `&` leaves INT ignored, and a signal ignored on entry cannot be trapped: both are restored before the exec.
  # caffeinate (macOS) holds the machine awake on the run's pid rather than wrapping it, so it never stands in for the pid.
  # shellcheck disable=SC2016,SC2094  # the inner script expands in the child, not here; the log path is handed over, not read
  RUN_DETACHED_LOG="$DETACH_LOG" nohup perl -MPOSIX -e 'POSIX::setsid(); $SIG{HUP} = $SIG{INT} = "DEFAULT"; exec @ARGV or die "exec: $!\n"' -- \
    bash -c 'perl -e "\$SIG{INT} = q(DEFAULT); exec @ARGV or die" -- bash "$@" & p=$!
      command -v caffeinate >/dev/null 2>&1 && { caffeinate -dims -w "$p" & }
      fwd() { kill -"$1" "$p" 2>/dev/null; }; trap "fwd TERM" TERM; trap "fwd INT" INT; trap "fwd HUP" HUP
      while :; do wait "$p"; rc=$?; kill -0 "$p" 2>/dev/null || break; done
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [run] detached run exited rc=$rc"' \
    _ "$0" "${KEEP_ARGS[@]}" > "$DETACH_LOG" 2>&1 < /dev/null &
  say "detached: pid $! · log $DETACH_LOG · its last line will be 'detached run exited rc=<n>'"
  exit 0
fi

# ============================ library ============================
# -- processes (rows B18, F11-F13) --
# shellcheck disable=SC2329  # invoked from the traps
CHILD_GROUP=0   # 1 while $CHILD leads its own process group (the watch call): reaped as a group, so no descendant survives
reap() {
  [ -n "$CHILD" ] || return 0
  if [ "$CHILD_GROUP" -eq 1 ]; then kill -TERM -- "-$CHILD" 2>/dev/null; sleep 0.2; kill -KILL -- "-$CHILD" 2>/dev/null; fi
  pkill -TERM -P "$CHILD" 2>/dev/null; kill -TERM "$CHILD" 2>/dev/null
}
trap 'reap; scratch_close; say "hung up; claim left in place"; exit 129' HUP
trap 'reap; scratch_close; say "interrupted; claim left in place"; exit 130' INT
trap 'reap; scratch_close; say "terminated; claim left in place"; exit 143' TERM
bounded() { # bounded <secs> <logfile> <cmd...> — a bash watchdog (macOS ships no `timeout`); TERM, then KILL after 10s: the cap is a bound
  local secs="$1" log="$2"; shift 2
  ( cd "$WT" && exec "$@" ) > "$log" 2>"$log.err" < "${BOUNDED_STDIN:-/dev/null}" & CHILD=$!; CHILD_GROUP=0
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
# #939 D-14 D-27: the watch's own variables reach no session and no lane check. Listed from this run's environment rather
# than hard-coded, so a herdr variable nobody named here is unset too; the detach re-exec above is not scrubbed
WATCH_UNSET=()
for _t in $(compgen -e HERDR_) $(compgen -e RUN_WATCH) $(compgen -e RUN_DETACHED_LOG); do
  case "$_t" in HERDR_*|RUN_WATCH*|RUN_DETACHED_LOG) WATCH_UNSET+=(-u "$_t") ;; esac
done; unset _t
SCRUB_ENV+=(${WATCH_UNSET[@]+"${WATCH_UNSET[@]}"})
lane() { ( cd "$WT" && env "${SCRUB_ENV[@]}" bash -c "$1" ); }
first_word() { local w; for w in $1; do case "$w" in *=*) continue ;; *) printf '%s' "$w"; return ;; esac; done; printf '%s' "${1%% *}"; }
xargs_runs() { # xargs_runs <segment>: the command an xargs segment runs — its options skipped, and the value -n -P -L -I -d -s -E -a
  # take when it is the next word (#1048 OR-1) — or nothing when the segment is no xargs
  local a i=1 IFS=' '; read -r -a a <<<"$1"; [ "${a[0]:-}" = xargs ] || return 0
  while [ "$i" -lt "${#a[@]}" ]; do
    case "${a[i]}" in --) i=$((i+1)); break ;; -n|-P|-L|-I|-d|-s|-E|-a) i=$((i+2)) ;; -*) i=$((i+1)) ;; *) break ;; esac
  done
  printf '%s' "${a[*]:i}"
}
cmd_grants() { # cmd_grants <command> [xargs]: one ',Bash(...)' rule per command of a pipeline or chain, each checked on its own by the session
  # the first by its first word; every later one by its exact text, or, cut before a word holding , ( ) * or {, by that
  # prefix plus * — never one bare word, and never one led (or, through xargs, run) by rm, a shell, env, eval, exec, sudo, nohup, cd or python3.
  # With xargs (the build's, #1048 D-2), a later xargs segment also grants the command it runs on its own, by its text so cut, plus *
  local seg first=1 kept lead words run
  while IFS= read -r seg; do
    seg="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$seg")"; [ -n "$seg" ] || continue
    if [ "$first" -eq 1 ]; then first=0; printf ',Bash(%s*)' "$(first_word "$seg")"; continue; fi
    kept="$(awk '{ if (match($0, /(^|[[:space:]])[^[:space:]]*[,()*{]/)) { s = substr($0, 1, RSTART - 1); sub(/[[:space:]]+$/, "", s); print "cut " s } else print "whole " $0 }' <<<"$seg")"
    if [ "${kept%% *}" = whole ]; then printf ',Bash(%s)' "$seg"; kept="$seg"
    else
      kept="${kept#cut }"; read -r -a words <<<"$kept"; [ "${#words[@]}" -ge 2 ] || continue
      lead="${words[0]}"; [ "$lead" = xargs ] && lead="$(first_word "$(xargs_runs "$kept")")"
      case "$lead" in rm|sh|bash|zsh|env|eval|exec|sudo|nohup|cd|python3|'') continue ;; esac
      printf ',Bash(%s*)' "$kept"
    fi
    [ "${2:-}" = xargs ] || continue
    run="$(xargs_runs "$kept")"; read -r -a words <<<"$run"; [ "${#words[@]}" -ge 2 ] || continue
    case "$(first_word "$run")" in rm|sh|bash|zsh|env|eval|exec|sudo|nohup|cd|python3) continue ;; esac
    printf ',Bash(%s*)' "$run"
  done < <(awk '{ gsub(/&&|\|\||[|;]/, "\n"); print }' <<<"$1")
}
# -- session flags (rows F2, F4-F10) --
DISALLOWED="AskUserQuestion,EnterWorktree,ExitWorktree"
if [ "$TRACKER_WRITES" = false ]; then # the 14 Atlassian write tools under every namespace they are served under
  for _tool in addCommentToJiraIssue addWorklogToJiraIssue createIssueLink createJiraIssue editJiraIssue transitionJiraIssue createConfluencePage updateConfluencePage createConfluenceFooterComment createConfluenceInlineComment createCompassComponent createCompassComponentRelationship createCompassCustomFieldDefinition addTeamworkGraphContext; do
    for _ns in mcp__atlassian__ mcp__plugin_atlassian_atlassian__ mcp__claude_ai_Atlassian_Rovo__; do DISALLOWED="$DISALLOWED,$_ns$_tool"; done
  done
fi
MCP_ALLOW=""; [ "$TRACKER" = jira ] && MCP_ALLOW=",mcp__atlassian,mcp__plugin_atlassian_atlassian,mcp__claude_ai_Atlassian_Rovo"
# No session is granted the config's directory: by default it is the main checkout's .claude/, which holds the config,
# this run's $STATE and every other ticket's receipt. A session reads the config from a copy in its scratch dir (spawn).
SPAWN_COMMON=(--permission-mode acceptEdits --permission-prompts none --disallowedTools "$DISALLOWED" --setting-sources "user,project,local" --add-dir "$WT" --output-format json)
read_denials() { # read_denials <result-json> <out> — the file is written only when the JSON was read: a missing file is
  # "unread" (the run block's "?"), never "none"; a session killed at its bound leaves no JSON to read
  # slurped: jq on an empty file runs no filter and exits 0, so "one object carrying the key" is asserted, not assumed
  if jq -rs 'if length == 1 and (.[0] | type) == "object" and (.[0] | has("permission_denials")) then .[0].permission_denials[] | (.tool_name + " " + (.tool_input|tostring)) else error("unread") end' "$1" > "$2.tmp" 2>/dev/null
  then mv "$2.tmp" "$2"
  else rm -f "$2.tmp" "$2"; fi
}
add_cost() { # rows I14 I16: a session with no total_cost_usd (killed at its bound, crashed) is UNPRICED, never $0
  local c n; n="$(basename "$1" .json)"; c="$(jq -r '.total_cost_usd | numbers' "$1" 2>/dev/null)"
  if [ -z "$c" ]; then UNPRICED="${UNPRICED:+$UNPRICED }$n"; say "unpriced: $n left no total_cost_usd — the run's cost is a lower bound"; return 0; fi
  COST="$(LC_ALL=C awk -v a="$COST" -v b="$c" 'BEGIN{print a+b}')"
}
over_ceiling() { LC_ALL=C awk -v c="$COST" -v m="$COST_CEIL" 'BEGIN{exit !(c>m)}'; } # every cost awk runs in C: a comma-decimal locale misreads the sum
usd() { LC_ALL=C awk -v c="$1" 'BEGIN{printf "%.2f", c}'; } # display only; COST keeps full precision for the ceiling
usd_up() { LC_ALL=C awk -v c="$1" 'BEGIN{x = c * 100 - 1e-9; n = int(x); if (x > n) n++; printf "%.2f", n / 100}'; } # a cost-spent figure never rounds down to the ceiling

# -- tracker reads (rows D7-D9, J1, J3, K2-K5): every producer returns non-zero on a failed read; callers refuse --
issue_state() { [ "$TRACKER" = github ] || { echo OPEN; return 0; }; "$GH_READ" issue view "$ISSUE" --json state --jq .state 2>/dev/null; }
has_label() { local names; [ "$TRACKER" = github ] || return 1; names="$("$GH_READ" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || return 1; grep -qxF "$1" <<<"$names"; }
repo_slug() { "$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null; }
lane_comments() { # the issue's comments this lane wrote — a Bot, or the account this scheduler writes with (D-24) — oldest first, as one array
  local repo me comments
  repo="$(repo_slug)" || return 1
  me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
  comments="$("$GH_READ" api "repos/$repo/issues/$ISSUE/comments" --paginate 2>/dev/null)" || return 1
  printf '%s' "$comments" | jq -s --arg me "$me" 'add // [] | map(select((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))) | sort_by(.created_at)' 2>/dev/null
}
lane_marker_present() { # the lane's own claim marker: whole-line stage marker plus a run_id line
  lane_comments | jq -e 'any(.[]; (.body | test("(^|\n)<!-- stage: lean-claimed -->(\n|$)")) and (.body | test("<!-- run_id: ")))' >/dev/null 2>&1
}
handoff_holds() { # the lane's latest closing comment is build-handoff: a /dev-pipeline:build session is building in the worktree; unreadable counts as held
  local c; c="$(lane_comments)" || return 0
  jq -e '[.[].body | select(test("^second-shift run [^ ]+: "))] | (last // "") | test("^second-shift run [^ ]+: build-handoff ")' <<<"$c" >/dev/null 2>&1
}
open_prs() { "$GH_READ" pr list --head "$BRANCH" --state open --json number --jq '.[].number' 2>/dev/null; }
remote_head() { local out; out="$(git -C "$WT" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null)" || return 1; printf '%s' "$out" | cut -f1; }

# -- the record (rows G6, G7, H1-H4, H6, K6): read at its FIRST commit once one exists, else the receipt --
record_at_first() { git -C "$WT" show "$FIRST:$RECORD_REL" 2>/dev/null; }
record_at_head() { git -C "$WT" show "$HEAD_SHA:$RECORD_REL" 2>/dev/null; }   # #1085: read by plan-coverage.sh --head for operator-added ACs only
record_text() { if [ -n "$FIRST" ]; then record_at_first; else cat "$RECORD" 2>/dev/null; fi; }
# #1039 D-3: the build is asked for a plan only when the record at FIRST carries the section (a v4 receipt's)
# (the caller has read the record at FIRST already; were this read to fail, plan_coverage's own read refuses the run)
record_has_test_intent() { local r; r="$(record_at_first)" || return 1; grep -qiE '^#+[[:space:]]+test intent[[:space:]]*$' <<<"$r"; }
# the heading rule: exact title at any depth, case-folded; ANY heading closes the section; the FIRST such section decides
section_of() { awk -v h="$1" 'on && /^#+[[:space:]]/ {on=0; done=1} !done && tolower($0) ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {on=1; next} on'; }
design_section_of() { section_of "design( frames)?"; }
# shellcheck disable=SC2016  # markdown backticks
record_checks() { record_text | section_of "checks" | sed -n 's/^- *`\{0,1\}\([^`]*\)`\{0,1\} *$/\1/p'; }
frames_rows() { record_text | design_section_of | grep -E '^\| *RS-[0-9]+ *\|' | sed 's/^| *//; s/ *| */|/g; s/ *|$//'; }
design_declared() { # 0 armed or disarmed with a reason; 1 neither (its forms byte for byte); reads record_text
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
# #1022: the receipt's lint is the ENABLED intake-toolkit's, never a leftover cached version: the env override, else the
# installPath of the intake-toolkit record that applies here (a project record for this checkout first, as doctor.sh
# resolves it), enabled. Sets INTAKE_LINT, or LINT_WHY and returns 1; the caller refuses
# shellcheck disable=SC2016  # a jq program: $root is jq's --arg binding
INTAKE_RECORD='[.[] | select(((.id // "") | startswith("intake-toolkit@")) and .enabled == true and ((.projectPath // "") == $root or .scope == "user" or .scope == "local"))]
  | ((map(select(.scope == "project")) | sort_by(.lastUpdated // "") | last) // (sort_by(.lastUpdated // "") | last)) | .installPath // empty'
INTAKE_LINT=""; LINT_WHY=""
resolve_intake_lint() {
  local root="${SECOND_SHIFT_INTAKE_TOOLKIT_ROOT:-}" from="SECOND_SHIFT_INTAKE_TOOLKIT_ROOT" list
  if [ -z "$root" ]; then
    from="the enabled intake-toolkit in '$CLAUDE plugin list --json'"
    list="$(cd "$MAIN_ROOT" && "$CLAUDE" plugin list --json 2>/dev/null)" || { LINT_WHY="'$CLAUDE plugin list --json' failed"; return 1; }
    root="$(jq -r --arg root "$MAIN_ROOT" "$INTAKE_RECORD" <<<"$list" 2>/dev/null)" || { LINT_WHY="'$CLAUDE plugin list --json' did not print a plugin list"; return 1; }
    [ -n "$root" ] || { LINT_WHY="'$CLAUDE plugin list --json' lists no enabled intake-toolkit for $MAIN_ROOT"; return 1; }
  fi
  INTAKE_LINT="$root/skills/plan-interview/tools/ledger-lint.sh"
  [ -f "$INTAKE_LINT" ] || { LINT_WHY="$from names $root, which has no skills/plan-interview/tools/ledger-lint.sh"; return 1; }
}
receipt_version() { # the highest `Receipt: v<N>` line in the receipt; none is v1 (the lint itself refuses two, or a misplaced one)
  local v; v="$(sed -n 's/^[Rr][Ee][Cc][Ee][Ii][Pp][Tt]:[[:space:]]*v\([0-9][0-9]*\).*$/\1/p' "$RECORD" | sort -n | tail -n 1)"
  printf '%s' "$((10#${v:-1}))"
}

# -- configured checks (rows C15-C22, G2-G4, G8, G10) --
commands_key() { # the sole key, else the main checkout's directory name (the pre-commit hook's rule)
  [ -n "$CONFIG" ] || return 0
  jq -r --arg s "$REPO_SLUG" '
    (.commands // {} | keys) as $k
    | if ($k | length) == 1 then $k[0] elif ($k | index($s)) then $s else empty end' <<<"$CONFIG_JSON" 2>/dev/null
}
lanes_malformed() { # prints the first malformed lanes[]/extraLanes[] entry, nothing when all are well-formed
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '
    def check(kind): to_entries[] | select((.value|type) != "object" or (.value.name // "") == "" or ((.value.commands // []) | type) != "array" or ((.value.commands // []) | length) == 0 or any(.value.commands[]; type != "string"))
      | kind + " lane [" + (.key|tostring) + "]: must be an object {name, cwd?, commands[] of strings}";
    ((.commands[$k].lanes // []) | if type == "array" then check("setup") else "commands.lanes must be an array" end),
    ((.commands[$k].extraLanes // []) | if type == "array" then check("extra") else "commands.extraLanes must be an array" end)' <<<"$CONFIG_JSON" 2>&1 | head -n 1
}
setup_lanes() { local key; key="$(commands_key)"; [ -n "$key" ] || return 0; jq -r --arg k "$key" '.commands[$k].lanes[]? | (.cwd // ".") as $d | .commands[] | if $d == "." then . else "cd " + ($d|@sh) + " && " + . end' <<<"$CONFIG_JSON" 2>/dev/null; }
config_checks() { # config_checks [all]: lint/typecheck/test/format, then extraLanes whose `when` globs match a changed file since FIRST (or have none); `all` lists every lane
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '.commands[$k] | [.lint, .typecheck, .test, .format] | map(select(type=="string"))[]' <<<"$CONFIG_JSON" 2>/dev/null
  if [ "${1:-}" = all ]; then jq -r --arg k "$key" '.commands[$k].extraLanes[]?.commands[]? | select(type=="string")' <<<"$CONFIG_JSON" 2>/dev/null; return 0; fi
  local lane
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue
    lane_hit "$lane" && printf '%s' "$lane" | jq -r '.commands[] | select(type=="string")'
  done <<EOF
$(extra_lanes)
EOF
}
extra_lanes() { local key; key="$(commands_key)"; [ -n "$key" ] || return 0; jq -c --arg k "$key" '.commands[$k].extraLanes[]? | {name: (.name // ""), when: (.when // []), commands: (.commands // [])}' <<<"$CONFIG_JSON" 2>/dev/null; }
lane_hit() { # lane_hit <lane-json>: 0 when the lane has no `when` globs or one matches a file in $CHANGED
  local g f
  [ "$(printf '%s' "$1" | jq '.when | length')" -gt 0 ] || return 0
  while IFS= read -r g; do while IFS= read -r f; do # shellcheck disable=SC2254  # $g IS a glob, by contract
    case "$f" in $g) return 0 ;; esac; done <<EOF
$CHANGED
EOF
  done <<EOF
$(printf '%s' "$1" | jq -r '.when[]')
EOF
  return 1
}
skipped_lanes() { # the name of each when-scoped extraLanes entry no file in $CHANGED matched, whether or not others ran (#956)
  local lane
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue
    lane_hit "$lane" || printf '%s' "$lane" | jq -r '.name'
  done <<EOF
$(extra_lanes)
EOF
}
allow_unverified() { local key; key="$(commands_key)"; [ -n "$key" ] && [ "$(jq -r --arg k "$key" '.commands[$k].allowUnverified // false' <<<"$CONFIG_JSON" 2>/dev/null)" = true ]; }
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
  # "configured" is a config-TIME predicate: a when-scoped lane that did not run on this diff
  # is still a configured check; only a repo with nothing under lint/typecheck/test/format, extraLanes and '## Checks' is unverified
  if [ "$n" -eq 0 ] && [ "$(checks_list all | grep -c .)" -eq 0 ]; then
    allow_unverified && { say "checks: none configured; commands.<repo>.allowUnverified is true, so this is declared, not silent"; return 0; }
    echo "RED: no check is configured under commands.* and none under '## Checks' — a zero-check run is not green (declare allowUnverified to accept it)" >> "$log"; return 1
  fi
  [ "$n" -gt 0 ] || say "checks: every configured lane is when-scoped and none matched this diff — configured, not unverified"
  return $rc
}
# -- the plan's AC coverage (#1039 D-6 D-7 D-9): tools/plan-coverage.sh from $TOOLS (the installed plugin, outside every dir
# the build is granted), handed the record at FIRST, the record at the pushed head (#1085: read for an AC added under a
# recorded departure, nothing else) and the plan at the pushed head as git objects through pipes — never the
# worktree, $STATE or the config, all of which the build can write. Not a configured lane: its exit code is the result.
# PLAN_NOTES is the latest check's run-block lines; the plan's position is noted, never gating: no commit order proves a
# test came first, so #1040 D-1 proves "fails without the change" instead (fails_without_change below) --
PLAN_NOTES=""
plan_coverage() { # plan_coverage <attempt> -> the script's exit: 0 pass · 1 red (the log: $STATE/plan-coverage-<attempt>.log) · 2 uncheckable · 3 not-applicable
  local log="$STATE/plan-coverage-$1.log" out rc after pos
  if git -C "$WT" cat-file -e "$HEAD_SHA:$PLAN_REL" 2>/dev/null; then
    out="$(bash "$TOOLS/plan-coverage.sh" --head <(record_at_head) <(record_at_first) <(git -C "$WT" show "$HEAD_SHA:$PLAN_REL" 2>/dev/null) 2>&1)"; rc=$?
  else # no such file: the script names the plan missing at the head
    out="$(bash "$TOOLS/plan-coverage.sh" --head <(record_at_head) <(record_at_first) "$HEAD_SHA:$PLAN_REL" 2>&1)"; rc=$?
  fi
  if [ "$rc" -eq 3 ]; then
    PLAN_NOTES="$(printf '%s' "$out" | tail -n 1 | sed 's/^plan-coverage:/plan coverage:/')"$'\n'; say "${PLAN_NOTES%$'\n'}"; return 3
  fi
  after="$(git -C "$WT" rev-list --reverse --first-parent "$FIRST..$HEAD_SHA" 2>/dev/null | head -n 1)"
  if [ -z "$after" ]; then pos="no commit follows the record commit $FIRST"
  elif [ -n "$(git -C "$WT" diff-tree --no-commit-id --name-only --diff-filter=A -r "$after" -- "$PLAN_REL" 2>/dev/null)" ]; then pos="the first commit after the record ($after) added $PLAN_REL"
  else pos="the first commit after the record ($after) did not add $PLAN_REL"; fi
  { echo "plan coverage: tools/plan-coverage.sh read the record at $FIRST and $PLAN_REL at $HEAD_SHA (exit $rc)"
    printf '%s\n' "$out"; echo "plan position (noted, not checked): $pos"; } > "$log"
  PLAN_NOTES="plan coverage at $HEAD_SHA: $(printf '%s' "$out" | tail -n 1 | sed 's/^plan-coverage: //')"$'\n'"plan position: $pos"$'\n'
  say "plan coverage: exit $rc — $(printf '%s' "$out" | tail -n 1 | sed 's/^plan-coverage: //') (log: $log)"; say "plan position: $pos"
  return "$rc"
}
# -- fails without the change (#1040, layer 3 of #1018; #1053): after the checks and the coverage pass, the head's tagged test
# files are applied onto the record commit's tree (the base code, none of the build's), beside the head's testSupport files
# (never run), and run through the first configured testRunners entry whose `when` glob matches each. The runner's `format`
# decides the unit (#1053 D-2 D-5 D-8): exit runs one file and its exit code judges the file (#1040 D-2: any failure counts);
# cases runs one file and judges each named file::case by the `case<TAB><passed|failed><TAB><id>` line it prints; vitest-json
# and jest-json run every file of the runner in one call and judge each named test by its row in the JSON report. Every named
# test must fail there. One whose file does not load there, or that sits behind a failing vitest beforeAll, is pending (D-3):
# the head leg runs it after the restore, at the head, with each selected test of a {cases} runner that failed on the record
# commit's tree, and each must pass (D-9; D-28: a selected test already red there is not run again).
# Passing at the head is otherwise the checks'. A holds AC's files are kept off it and an unchecked AC's are noted, not run
# (#1040 D-4, D-11); the AC-to-test map comes from plan-coverage.sh --files, never a second plan parser (#1040 D-7). The tree
# is built in $WT, which keeps its ignored dependencies: detached to the record commit only when no tracked change is in it,
# put back on the branch by a plain checkout — which carries any change rather than discard it — under an EXIT trap, and by
# the next launch when a mark outlives the process (red_tree_restore). The runners were read at launch (D-13): a build cannot
# change them mid-run -- Each call runs bounded (bounded_group): one that has not finished within its runner's timeoutSeconds
# is red, never a failure, since a runner that hangs on every tree would otherwise pass every proof (#1053 D-11: a batch is
# one call). A report is no weaker than the exit code it replaces (#1053 D-10): it is deleted before each call and copied to
# the run's state right after, and deliberate forgery is the review's to catch
FWC_NOTES=""
FWC_TIMEOUT_DEFAULT=600
FWC_GRACE=10
FWC_TIMED_OUT=0
bounded_group() { # bounded_group <secs> <out> <command> — the command in $WT, scrubbed, as the leader of its own session, so
  # the bound reaches every descendant (bounded() reaps one level down): TERM the group, KILL it after FWC_GRACE. What is left
  # of the group after a clean exit is killed too, so nothing it backgrounded writes on the red tree during the restore.
  # Deadlines are wall-clock ($SECONDS), not counted polls: on a loaded machine a poll takes longer than its sleep
  local secs="$1" out="$2" end rc
  FWC_TIMED_OUT=0
  ( cd "$WT" && exec env "${SCRUB_ENV[@]}" perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' -- bash -c "$3" ) > "$out" 2>&1 < /dev/null & CHILD=$!; CHILD_GROUP=1
  end=$((SECONDS + secs)); while kill -0 "$CHILD" 2>/dev/null && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
  if kill -0 "$CHILD" 2>/dev/null; then
    FWC_TIMED_OUT=1; kill -TERM -- "-$CHILD" 2>/dev/null; kill -TERM "$CHILD" 2>/dev/null   # the leader too, as the watch call: a setsid that failed leaves no group
    end=$((SECONDS + FWC_GRACE)); while { kill -0 -- "-$CHILD" || kill -0 "$CHILD"; } 2>/dev/null && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
    kill -KILL -- "-$CHILD" 2>/dev/null; kill -KILL "$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null; CHILD=""; CHILD_GROUP=0; return 1
  fi
  wait "$CHILD"; rc=$?; kill -KILL -- "-$CHILD" 2>/dev/null; CHILD=""; CHILD_GROUP=0; return "$rc"
}
RED_TREE_MARK="$LOG_DIR/run-$ISSUE/red-tree"
test_runners() { local key; key="$(commands_key)"; [ -n "$key" ] || return 0; jq -c --arg k "$key" '.commands[$k].testRunners[]? | objects' <<<"$CONFIG_JSON" 2>/dev/null; }
runner_for() { # runner_for <file> -> '<index>\t<timeoutSeconds>\t<format>\t<command>' of the first testRunners entry a `when` glob of which matches the file; 1 when none does
  local r g i=0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    i=$((i + 1))
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2254  # $g IS a glob, by contract (extraLanes' `when`)
      case "$1" in $g) printf '%s' "$r" | jq -r --argjson d "$FWC_TIMEOUT_DEFAULT" --arg i "$i" '"\($i)\t\(.timeoutSeconds // $d)\t\(.format // "exit")\t\(.command // "")"'; return 0 ;; esac
    done <<EOF
$(printf '%s' "$r" | jq -r '.when[]? | strings')
EOF
  done <<EOF
$(test_runners)
EOF
  return 1
}
runner_name() { # runner_name <index, from 1> -> 'testRunners[<n>] (<when globs>)', the name a red gives the runner
  printf 'testRunners[%s] (%s)' "$(($1 - 1))" "$(test_runners | sed -n "${1}p" | jq -r '[.when[]? | strings] | join(", ")')"
}
test_support() { local key; key="$(commands_key)"; [ -n "$key" ] || return 0; jq -r --arg k "$key" '.commands[$k].testSupport[]? | strings' <<<"$CONFIG_JSON" 2>/dev/null; }
support_files() { # the files changed since the record commit that a testSupport glob matches and the head carries (#1053
  # OR-3: one the head deleted is left as the record commit has it, so the tree still builds)
  local globs f g; globs="$(test_support)"; [ -n "$globs" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2254  # $g IS a glob, matched as `when` is (#1053 D-21)
      case "$f" in $g) git -C "$WT" cat-file -e "$HEAD_SHA:$f" 2>/dev/null && printf '%s\n' "$f"; break ;; esac
    done <<<"$globs"
  done <<EOF
$(git -C "$WT" -c core.quotePath=false diff --name-only --no-renames "$FIRST" "$HEAD_SHA" 2>/dev/null)
EOF
}
subst_many() { # subst_many <template> <placeholder> <replacement> [<placeholder> <replacement> ...] — one walk, so the text one
  # placeholder inserts is never read for another (a build names the files and the cases)
  local t="$1" out="" i p pre best bpre bp br; shift
  while :; do
    best=-1
    for ((i = 1; i < $#; i += 2)); do
      p="${!i}"; pre="${t%%"$p"*}"
      [ "$pre" != "$t" ] || continue
      if [ "$best" -lt 0 ] || [ "${#pre}" -lt "$best" ]; then best=${#pre}; bpre="$pre"; bp="$p"; br="$((i + 1))"; br="${!br}"; fi
    done
    [ "$best" -ge 0 ] || break
    out="$out$bpre$br"; t="${t:${#bpre}+${#bp}}"
  done
  printf '%s' "$out$t"
}
fwc_realpath() { # fwc_realpath <repo-relative file> -> its path under the worktree, symlinks resolved, as a runner reports it (F-1)
  local dir; dir="$(cd "$WT/$(dirname "$1")" 2>/dev/null && pwd -P)" || dir="$WT/$(dirname "$1")"
  printf '%s/%s' "$dir" "$(basename "$1")"
}
# One named test against a vitest/jest JSON report (#1053 D-2 D-3 D-7; the shape: testResults[] of {name: the file's absolute
# path, status, message, assertionResults[] of {ancestorTitles, title, status}}, in both runners — F-1, F-6, D-17). The case,
# split on ' > ', must equal ancestorTitles + title exactly. Prints one word: failed · passed · status <s> · pending hook (a
# vitest beforeAll failure: the file failed with an empty message and no failed row) · pending load (no row, the file failed
# with a message: it does not load) · ambiguous <n> · not-collected (the file is not in the report) · did-not-run
# shellcheck disable=SC2016  # a jq program: its $names are jq's
FWC_JUDGE='
  [(.testResults // [])[] | select(.name == $n1 or .name == $n2)] as $fr
  | if ($fr | length) == 0 then "not-collected"
    else [$fr[] | (.assertionResults // [])[]] as $rows
    | ($c | split(" > ")) as $want
    | [$rows[] | select(((.ancestorTitles // []) + [.title]) == $want)] as $m
    | if ($m | length) > 1 then "ambiguous \($m | length)"
      elif ($m | length) == 1 then
        if $m[0].status == "failed" then "failed"
        elif $m[0].status == "passed" then "passed"
        elif $fmt == "vitest-json" and any($fr[]; .status == "failed" and ((.message // "") == ""))
             and ([$rows[] | select(.status == "failed")] | length) == 0 then "pending hook"
        else "status \($m[0].status)" end
      elif ($rows | length) > 0 then "did-not-run"
      elif any($fr[]; .status == "failed" and ((.message // "") != "")) then "pending load"
      else "did-not-run" end
    end'
fwc_json_verdict() { # fwc_json_verdict <report> <file> <case> <format>
  jq -r --arg n1 "$(fwc_realpath "$2")" --arg n2 "$WT/$2" --arg c "$3" --arg fmt "$4" "$FWC_JUDGE" "$1" 2>/dev/null || echo not-collected
}
# A file or a case is the build's text: awk reads it from ENVIRON, never `-v`, which turns a backslash escape into another string
fwc_cases_verdict() { # fwc_cases_verdict <output> <case> — a cases runner's case lines are its report (#1053 D-4 D-16)
  local rows n; rows="$(FWC_C="$2" awk -F'\t' '$1 == "case" && ($2 == "passed" || $2 == "failed") && $3 == ENVIRON["FWC_C"] { print $2 }' "$1" 2>/dev/null)"
  n="$(printf '%s' "$rows" | grep -c .)"
  if [ "$n" -eq 0 ]; then echo did-not-run; elif [ "$n" -eq 1 ]; then echo "$rows"; else echo "ambiguous $n"; fi
}
red_tree_restore() { # put $WT back on $BRANCH after the leg, never forced; 1 when git refuses (a change the checkout would overwrite)
  [ -f "$RED_TREE_MARK" ] || return 0
  git -C "$WT" checkout -q "$BRANCH" 2>/dev/null || return 1
  rm -f "$RED_TREE_MARK"
}
# The leg's helpers below read and write fails_without_change's locals — map, log, red, ran, nt, fl, notes, headq, key — by
# bash's dynamic scope; they are called from it only
fwc_ids() { FWC_F="$1" FWC_C="$2" awk -F'\t' '$1 == "run" && $3 == ENVIRON["FWC_F"] && $4 == ENVIRON["FWC_C"] { printf "%s ", $2 }' <<<"$map"; }   # every behavior AC tagged on this test
fwc_rows_of() { FWC_F="$1" awk -F'\t' '$2 == ENVIRON["FWC_F"]' <<<"$2"; }   # fwc_rows_of <file> <tests: index\tfile\tcase lines> -> that file's lines
fwc_label() { if [ -n "$2" ]; then printf '%s::%s' "$1" "$2"; else printf '%s' "$1"; fi; }
fwc_red() { # fwc_red <file> <case> <why> — one red per AC tagged on the test, and one red still when no id is found: a red never vanishes
  local id ids; ids="$(fwc_ids "$1" "$2")"
  if [ -z "$ids" ]; then echo "RED: ? — $(fwc_label "$1" "$2") $3 (no AC of the plan's map names this test)" >> "$log"; red=$((red + 1)); return; fi
  for id in $ids; do echo "RED: $id — $(fwc_label "$1" "$2") $3" >> "$log"; red=$((red + 1)); done
}
fwc_ok() { local id; for id in $(fwc_ids "$1" "$2"); do echo "ok: $id — $(fwc_label "$1" "$2") $3" >> "$log"; done; }
fwc_run_red() { # fwc_run_red <index> <tests: index\tfile\tcase lines> <why> — ONE red naming the runner, covering its tests (#1053 D-2 AC-7)
  local ids="" tl="" f c rest
  while IFS=$'\t' read -r _ f c rest; do
    [ -n "$f" ] || continue; ids="$ids$(fwc_ids "$f" "$c")"; tl="$tl${tl:+, }$(fwc_label "$f" "$c")"
  done <<<"$2"
  ids="$(printf '%s' "$ids" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd ' ' -)"
  echo "RED: ${ids:-?} — $(runner_name "$1") $3 — the call covered $tl" >> "$log"; red=$((red + 1))
}
fwc_call() { # fwc_call <attempt> <secs> <command> -> its exit, bounded; its output at $STATE/fails-without-<attempt>.out and in the log
  local rc
  say "fails without the change: $3 (bound ${2}s)"; echo "\$ $3" >> "$log"
  bounded_group "$2" "$STATE/fails-without-$1.out" "$3"; rc=$?
  cat "$STATE/fails-without-$1.out" >> "$log" 2>/dev/null
  return "$rc"
}
fwc_record_verdict() { # fwc_record_verdict <index> <file> <case> <verdict> <1 when the runner takes {cases}>
  local id why
  case "$4" in
    failed) fwc_ok "$2" "$3" "fails on the record commit's tree"; nt=$((nt + 1))
            [ "$5" -eq 0 ] || headq="$headq$1"$'\t'"$2"$'\t'"$3"$'\t'selected$'\n' ;;   # D-13: a case run alone may fail for lack of a sibling's setup
    passed) fwc_red "$2" "$3" "passes on the record commit's tree ($FIRST) with the head's tagged test files applied: it does not fail without the change — make it test what the change does" ;;
    "pending "*)
      why="its file does not load there (it failed with a message and reported no test)"; [ "$4" != "pending hook" ] || why="it is skipped there behind a failing beforeAll (its file failed with an empty message and no failed test)"
      for id in $(fwc_ids "$2" "$3"); do echo "pending: $id — $(fwc_label "$2" "$3"): $why — it must pass at the head" >> "$log"; done
      headq="$headq$1"$'\t'"$2"$'\t'"$3"$'\t'"${4#pending }"$'\n' ;;
    "status "*) fwc_red "$2" "$3" "is ${4#status } on the record commit's tree, not failed: a test that does not run proves nothing — remove its skip, only or todo" ;;
    "ambiguous "*) fwc_red "$2" "$3" "is ambiguous: ${4#ambiguous } rows of the runner's report match it on the record commit's tree — give the tests distinct names" ;;
    not-collected) fwc_red "$2" "$3" "was not collected: $(runner_name "$1") left $2 out of its report on the record commit's tree — check the runner's include globs and rootDir" ;;
    *) fwc_red "$2" "$3" "did not run on the record commit's tree: no row of the runner's report names it" ;;
  esac
}
fwc_head_verdict() { # fwc_head_verdict <index> <file> <case> <why it is on the head leg: load · hook · selected> <verdict>
  local id what
  if [ "$5" != passed ]; then
    fwc_red "$2" "$3" "does not pass at the head ($HEAD_SHA) — the report says: $5 — a pending test, and each selected case, must pass there"; return
  fi
  if [ "$4" = selected ]; then fwc_ok "$2" "$3" "passes at the head ($HEAD_SHA), run with only the selected cases"; return; fi
  what="does not load on the record commit's tree"; [ "$4" != hook ] || what="fails in a beforeAll on the record commit's tree"
  fwc_ok "$2" "$3" "passes at the head ($HEAD_SHA): file-level — its file $what"; nt=$((nt + 1)); fl=$((fl + 1))
  for id in $(fwc_ids "$2" "$3"); do notes="$notes$id file-level — $(fwc_label "$2" "$3"): its file $what; the test passes at the head"$'\n'; done
}
fwc_leg() { # fwc_leg <record|head> <attempt> <index> <tests of that runner: index\tfile\tcase[\twhy] lines> — one runner's calls on one leg
  local leg="$1" att="$2" i="$3" list="$4" r secs fmt cmd f c sel hc=0 why frc fq rep copy where v
  r="$(test_runners | sed -n "${i}p")"
  secs="$(jq -r --argjson d "$FWC_TIMEOUT_DEFAULT" '.timeoutSeconds // $d' <<<"$r")"; fmt="$(jq -r '.format // "exit"' <<<"$r")"; cmd="$(jq -r '.command // ""' <<<"$r")"
  case "$cmd" in *"{cases}"*) hc=1 ;; esac
  where="on the record commit's tree"; [ "$leg" = record ] || where="at the head ($HEAD_SHA)"
  case "$fmt" in
    exit) # one call per file; its exit code judges the file (#1040 D-2) — the record leg only
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        c="$(subst "$cmd" '{file}' "$(shquote "$f")")"; ran=$((ran + 1))
        fwc_call "$att" "$secs" "$c"; frc=$?
        if [ "$FWC_TIMED_OUT" -eq 1 ]; then fwc_run_red "$i" "$(fwc_rows_of "$f" "$list")" "did not finish within ${secs}s on the record commit's tree, and its process group was killed — tag a smaller file, or bound the wait inside it"
        elif [ "$frc" -eq 0 ]; then fwc_red "$f" "" "passes on the record commit's tree ($FIRST) with the head's tagged test files applied: it does not fail without the change — make it test what the change does"
        else fwc_ok "$f" "" "fails on the record commit's tree (exit $frc)"; fi
      done <<<"$(cut -f2 <<<"$list" | awk 'NF && !seen[$0]++')" ;;
    cases) # one call per file; its case lines are its report (#1053 D-4 D-16)
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        sel="$(fwc_rows_of "$f" "$list" | cut -f3 | paste -sd ' ' -)"
        c="$(subst_many "$cmd" '{file}' "$(shquote "$f")" '{cases}' "$(shquote "$sel")")"
        fwc_call "$att" "$secs" "$c"
        if [ "$FWC_TIMED_OUT" -eq 1 ]; then
          fwc_run_red "$i" "$(fwc_rows_of "$f" "$list")" "did not finish within ${secs}s $where, and its process group was killed"; continue
        fi
        while IFS=$'\t' read -r _ f c why; do
          [ -n "$f" ] || continue
          if ! grep -qE $'^case\t(passed|failed)\t.' "$STATE/fails-without-$att.out" 2>/dev/null; then
            fwc_red "$f" "$c" "did not run $where: $f printed no case lines — is the helper lib that prints them in testSupport (commands.$key.testSupport)?"; continue
          fi
          v="$(fwc_cases_verdict "$STATE/fails-without-$att.out" "$c")"
          if [ "$leg" = record ]; then fwc_record_verdict "$i" "$f" "$c" "$v" "$hc"; else fwc_head_verdict "$i" "$f" "$c" "$why" "$v"; fi
        done <<<"$(fwc_rows_of "$f" "$list")"
      done <<<"$(cut -f2 <<<"$list" | awk 'NF && !seen[$0]++')" ;;
    *) # vitest-json, jest-json: one call over every file of the runner, judged by its JSON report (#1053 D-2 D-5)
      fq=""; while IFS= read -r f; do [ -z "$f" ] || fq="$fq${fq:+ }$(shquote "$(fwc_realpath "$f")")"; done <<<"$(cut -f2 <<<"$list" | awk 'NF && !seen[$0]++')"
      rep="$FWC_TMP/report-$i.json"; rm -f "$rep"
      c="$(subst_many "$cmd" '{report}' "$(shquote "$rep")" '{files}' "$fq")"
      fwc_call "$att" "$secs" "$c"; frc=$?
      copy="$STATE/fails-without-$att-$leg-$i.json"; rm -f "$copy"; [ ! -f "$rep" ] || cp "$rep" "$copy"   # OR-2: per run and attempt, in the run's state
      why=""
      if [ "$FWC_TIMED_OUT" -eq 1 ]; then why="did not finish within ${secs}s $where, and its process group was killed"
      elif ! jq -e '(.testResults | type) == "array"' "$copy" >/dev/null 2>&1; then why="left no readable report at {report} $where (exit $frc)"
      elif [ "$frc" -eq 0 ] && [ "$(jq '[.testResults[] | (.assertionResults // [])[] | select(.status == "failed")] | length' "$copy" 2>/dev/null)" != 0 ]; then
        why="reported failed tests but exited 0 $where — the report and the exit code disagree"
      fi
      if [ -n "$why" ]; then fwc_run_red "$i" "$list" "$why"; return; fi
      while IFS=$'\t' read -r _ f c why; do
        [ -n "$f" ] || continue
        v="$(fwc_json_verdict "$copy" "$f" "$c" "$fmt")"
        if [ "$leg" = record ]; then fwc_record_verdict "$i" "$f" "$c" "$v" 0; else fwc_head_verdict "$i" "$f" "$c" "$why" "$v"; fi
      done <<<"$list" ;;
  esac
}
FWC_TMP=""
fails_without_change() { # fails_without_change <attempt> -> 0 pass · 1 red (the log: $STATE/fails-without-<attempt>.log) · 3 not-applicable
  local log="$STATE/fails-without-$1.log" map rc kind id f c r i fmt c2 red=0 ran=0 nt=0 fl=0 notes="" tests="" headq="" apply support dirty why key summary parts
  key="$(commands_key)"; FWC_NOTES=""
  if [ -z "$(test_runners)" ]; then
    why="no test runner is configured (commands.${key:-<id>}.testRunners)"
    echo "not-applicable: $why" > "$log"; FWC_NOTES="fails without the change: not-applicable — $why"$'\n'; say "fails without the change: not-applicable — $why"; return 3
  fi
  map="$(bash "$TOOLS/plan-coverage.sh" --files --head <(record_at_head) <(record_at_first) <(git -C "$WT" show "$HEAD_SHA:$PLAN_REL" 2>/dev/null) 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || terminal plan-coverage-uncheckable "tools/plan-coverage.sh --files exited $rc on the record at $FIRST and $PLAN_REL at $HEAD_SHA, whose coverage had just passed ($(printf '%s' "$map" | tr '\n' ' ' | cut -c1-300))"
  { echo "fails without the change: the head's tagged test files at $HEAD_SHA applied onto the record commit's tree $FIRST; each must fail there"; echo; } > "$log"
  while IFS=$'\t' read -r kind id f c; do   # #1053 D-6: the map is tab-separated, the case empty for a bare file
    [ -n "$f" ] || continue
    # D-19: a tagged file the head does not carry is red whatever its AC's kind — a holds or unchecked AC is no more covered by a fictitious path
    if ! git -C "$WT" cat-file -e "$HEAD_SHA:$f" 2>/dev/null; then echo "RED: $id — $f does not exist at $HEAD_SHA" >> "$log"; red=$((red+1)); continue; fi
    case "$kind" in
      holds) notes="$notes$id holds — $(fwc_label "$f" "$c") is not run for it: the checks at the head prove it"$'\n' ;;
      unchecked) notes="$notes$id unchecked — $(fwc_label "$f" "$c") is noted, not run"$'\n' ;;
      *) if ! r="$(runner_for "$f")" || [ -z "${r##*$'\t'}" ]; then
           echo "RED: $id — $f matches no configured test runner (commands.$key.testRunners), and the record does not mark $id unchecked" >> "$log"; red=$((red+1)); continue
         fi
         i="${r%%$'\t'*}"; fmt="$(cut -f3 <<<"$r")"
         # #1053 D-8: a test its runner cannot judge is red — the runner's format decides the unit
         if [ "$fmt" = exit ] && [ -n "$c" ]; then
           echo "RED: $id — $f::$c names one test, but $(runner_name "$i") has format exit, which judges whole files — name the bare file, or give the runner a reporting format" >> "$log"; red=$((red+1))
         elif [ "$fmt" != exit ] && [ -z "$c" ]; then
           echo "RED: $id — $f is a bare file, but $(runner_name "$i") has format $fmt, which judges named tests — name each test as $f::<case>" >> "$log"; red=$((red+1))
         else tests="$tests$i"$'\t'"$f"$'\t'"$c"$'\n'; fi ;;
    esac
  done <<<"$map"
  tests="$(printf '%s' "$tests" | awk 'NF && !seen[$0]++')"
  if [ -n "$tests" ]; then
    dirty="$(git -C "$WT" status --porcelain --untracked-files=no 2>/dev/null)" || terminal env-worktree "cannot read the status of $WT before the fails-without-the-change check"
    [ -z "$dirty" ] || terminal env-worktree "the checks left tracked changes in $WT ($(printf '%s' "$dirty" | head -n 3 | tr '\n' ' ')) — the record commit's tree cannot be built over them, and nothing here discards them"
    command -v perl >/dev/null 2>&1 || terminal env-perl "the fails-without-the-change check needs perl for setsid, so its time bound reaches every process a test starts"
    FWC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/fails-without.XXXXXX")" || terminal env-state-dir "cannot make a directory for the runners' reports"
    support="$(support_files)"; apply="$(printf '%s\n%s\n' "$(cut -f2 <<<"$tests")" "$support" | awk 'NF && !seen[$0]++')"
    [ -z "$support" ] || echo "testSupport (commands.$key.testSupport), from the head, never run: $(printf '%s' "$support" | paste -sd ',' - | sed 's/,/, /g')" >> "$log"
    printf 'first=%s head=%s branch=%s\n' "$FIRST" "$HEAD_SHA" "$BRANCH" > "$RED_TREE_MARK" || terminal env-state-dir "cannot write $RED_TREE_MARK"
    trap 'red_tree_restore || say "red tree: $WT could NOT be put back on $BRANCH — run git checkout $BRANCH in it"; rm -rf "$FWC_TMP"' EXIT
    git -C "$WT" checkout -q --detach "$FIRST" 2>>"$log" \
      && printf '%s\n' "$apply" | tr '\n' '\0' | xargs -0 git -C "$WT" checkout -q "$HEAD_SHA" -- 2>>"$log"; rc=$?
    if [ "$rc" -eq 0 ]; then
      while IFS= read -r i; do
        [ -z "$i" ] || fwc_leg record "$1" "$i" "$(awk -F'\t' -v i="$i" '$1 == i' <<<"$tests")"
      done <<<"$(cut -f1 <<<"$tests" | awk '!seen[$0]++')"
    fi
    red_tree_restore; c2=$?; trap 'rm -rf "$FWC_TMP"' EXIT
    [ "$c2" -eq 0 ] || terminal env-worktree "could not put $WT back on $BRANCH after the fails-without-the-change check — it is detached at $FIRST with the head's tagged test files applied; run git checkout $BRANCH in it, then --resume"
    [ "$rc" -eq 0 ] || terminal env-worktree "could not build the record commit's tree $FIRST with the head's tagged test files in $WT ($(tail -n 3 "$log" | tr '\n' ' ' | cut -c1-300)) — $WT is back on $BRANCH"
    [ "$(git -C "$WT" rev-parse HEAD 2>/dev/null)" = "$HEAD_SHA" ] || terminal env-worktree-diverged "$WT is not at $HEAD_SHA after the fails-without-the-change check"
    # #1053 D-9: the head leg — after the restore, at the head, one call per json runner and one per file for cases, over every
    # pending test and each selected test of a {cases} runner that failed on the record commit's tree (D-28); each must pass there
    if [ -n "$headq" ]; then
      { echo; echo "the head leg at $HEAD_SHA: every pending test, and each selected case that failed on the record commit's tree, must pass there"; } >> "$log"
      while IFS= read -r i; do
        [ -z "$i" ] || fwc_leg head "$1" "$i" "$(awk -F'\t' -v i="$i" '$1 == i' <<<"$headq")"
      done <<<"$(cut -f1 <<<"$headq" | awk 'NF && !seen[$0]++')"
    fi
    rm -rf "$FWC_TMP"; trap - EXIT
  fi
  [ -z "$notes" ] || printf '%s' "$notes" >> "$log"
  if [ "$red" -gt 0 ]; then summary="RED — $red problem(s)"
  else
    parts=""; [ "$nt" -eq 0 ] || parts="$nt named test(s)"
    if [ "$ran" -gt 0 ] || [ -z "$parts" ]; then parts="$ran tagged file(s)${parts:+ and $parts}"; fi
    summary="pass — $parts fail on the record commit's tree $FIRST"; [ "$fl" -eq 0 ] || summary="$summary, $fl of them file-level"
  fi
  say "fails without the change: $summary (log: $log)"
  FWC_NOTES="fails without the change at $HEAD_SHA: $summary"$'\n'"$(printf '%s' "$notes" | sed 's/^/fails without the change: /')"
  [ -z "$notes" ] || FWC_NOTES="$FWC_NOTES"$'\n'
  [ "$red" -eq 0 ]
}

# -- route smoke (rows C24-C26, H7-H12, H14) --
# Substitution is into a SHELL COMMAND STRING, so every value is single-quoted on the way in (a state is
# human prose, a route may carry `&`), and the template is walked rather than `${t//p/r}`: under bash 5.2's
# patsub_replacement a `&` in the replacement expands to the matched placeholder, silently. The
# placeholders appear UNQUOTED in the template (shquote and subst below). Row H14: a smokeCommand that takes
# {textScale} runs at 1 and at 2 per row; {textScale} goes in FIRST, since subst rescans inserted text and a
# must-show value may carry the literal token. Every lane call reads /dev/null, never the rows heredoc.
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
  local seen="" dup rs route state must png sha c s scales=1
  case "$SMOKE_CMD" in *'{textScale}'*) scales="1 2" ;; esac
  while IFS='|' read -r rs route state _frame must; do
    [ -n "$rs" ] || continue
    png="$STATE/smoke-$rs.$1.png"; rm -f "$png"
    c="$(subst "$RENDER_CMD" '{route}' "$(shquote "$route")")"; c="$(subst "$c" '{state}' "$(shquote "$state")")"; c="$(subst "$c" '{out}' "$(shquote "$png")")"
    if ! lane "$c" >> "$log" 2>&1 </dev/null; then smoke_red "$rs render failed: $c"; continue; fi
    [ -s "$png" ] || { smoke_red "$rs exited 0 but wrote no image at $png"; continue; }
    sha="$(hash_file "$png")" || return 4
    # the {state}-blind-harness detector: a hash seen for ANY earlier state is red
    dup="$(printf '%s\n' "$seen" | awk -v s="$sha" '$1 == s { print $2; exit }')"
    [ -z "$dup" ] || smoke_red "render states $dup and $rs hash identically — the harness rendered the same view for two declared states"
    seen="$seen$sha $rs
"
    [ -n "$must" ] || { smoke_red "$rs declares no must-show value — the record must name one per screen (D-4)"; continue; }
    if [ "$scales" = 1 ]; then
      c="$(subst "$SMOKE_CMD" '{route}' "$(shquote "$route")")"; c="$(subst "$c" '{mustShow}' "$(shquote "$must")")"
      if lane "$c" >> "$log" 2>&1 </dev/null; then echo "ok: $rs shows '$must'" >> "$log"; say "smoke: $rs rendered to $png and shows '$must'"; else smoke_red "$rs must-show '$must' not satisfied"; fi
      continue
    fi
    for s in $scales; do # both scales run even after a red, so the findings carry both
      c="$(subst "$SMOKE_CMD" '{textScale}' "$s")"; c="$(subst "$c" '{route}' "$(shquote "$route")")"; c="$(subst "$c" '{mustShow}' "$(shquote "$must")")"
      if lane "$c" >> "$log" 2>&1 </dev/null; then echo "ok: $rs at text scale $s shows '$must'" >> "$log"; say "smoke: $rs rendered to $png and, at text scale $s, shows '$must'"
      else smoke_red "$rs at text scale $s: smoke failed: $c"; fi
    done
  done <<EOF
$rows
EOF
  return $SMOKE_RC
}
smoke_red() { echo "RED: $*" >> "$SMOKE_LOG"; say "smoke: $*"; SMOKE_RC=1; }

# -- the review input (rows I9-I11) --
TEST_PATH_ERE='(\.spec\.|\.test\.|_test\.|_spec\.|(^|/)(tests?|__tests__)/|(^|/)test_[^/]*\.py$|(^|/)conftest\.py$|-selftest\.)'   # a test path, on any stack (#956); -selftest. is this repo's own (#1011)
# every name-list read takes core.quotePath=false: a default-quoted "caf\303\251.spec.ts" matches no pattern, glob or pathspec (#1011)
expectations_changed() { # expectations_changed <name-status> -> each modified existing test or snapshot file, then its removed lines (#957)
  # an oracle edited with the code it pins stays green in CI: the old expectation is what the review traces to an AC or a record row
  local f removed n listed=0
  while IFS= read -r f; do
    removed="$(git -C "$WT" diff "$FIRST"..HEAD -- "$f" 2>/dev/null | awk '/^@@/ { h=1; next } h && /^-/')"
    [ -n "$removed" ] || continue   # an additive change moved no expectation
    listed=1; n="$(grep -c '' <<<"$removed")"
    echo "$f"; head -n 20 <<<"$removed" | sed 's/^/  /'
    [ "$n" -le 20 ] || echo "  (… $((n - 20)) more)"
  done < <(TEST_PATH_ERE="$TEST_PATH_ERE" awk -F'\t' '$1 == "M" && ($2 ~ ENVIRON["TEST_PATH_ERE"] || $2 ~ /(^|\/)__snapshots__\/|\.snap$/) { print $2 }' <<<"$1")
  [ "$listed" -eq 1 ] || echo "(none)"
}
policy_edited() { # policy_edited <name-status> -> each row that adds, edits, deletes or renames a review-policy file, either side of a rename (#1009)
  # the reviewers load these from the head, so a PR is reviewed against policy it can edit; a qualified reviewers.add[] name is a plugin pack, not a repo file
  local agents; agents="$(cfg '[.reviewers.add[]?.name | strings | select(test("[:/]") | not) | ".claude/agents/" + . + ".md"] | join("\n")')"
  AGENTS="$agents" awk -F'\t' 'BEGIN { n = split(ENVIRON["AGENTS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") ag[a[i]] = 1 }
    function policy(f) { return f == ".claude/second-shift.config.json" || index(f, ".claude/second-shift/") == 1 || (f in ag) }
    policy($2) || ($3 != "" && policy($3)) { print; k++ } END { if (!k) print "(none)" }' <<<"$1"
}
review_input() { # review_input <attempt> -> writes $STATE/review-input-<attempt>.md; 1 when a diff cannot be read (the caller refuses)
  local out="$STATE/review-input-$1.md" ns full names lanes
  ns="$(git -C "$WT" -c core.quotePath=false diff --name-status "$FIRST"..HEAD 2>/dev/null)" || return 1
  full="$(git -C "$WT" diff "$FIRST"..HEAD 2>/dev/null)" || return 1
  names="$(git -C "$WT" -c core.quotePath=false diff --name-only "$FIRST"..HEAD 2>/dev/null)" || return 1
  {
    # stack-neutral and advisory (#956): on a non-JS repo an empty section must not read as clean evidence
    echo "### Deleted or renamed test files"
    TEST_PATH_ERE="$TEST_PATH_ERE" awk -F'\t' '$1 ~ /^[DR]/ && $2 ~ ENVIRON["TEST_PATH_ERE"] { print; n++ } END { if (!n) print "(none)" }' <<<"$ns"; echo
    echo "### Existing test or snapshot expectations changed (removed lines)"
    expectations_changed "$ns"; echo
    echo "### Added skips / forced-green lines"
    grep -nE '^\+.*(\.skip\(|\.only\(|\|\| *true|xit\(|xdescribe\(|(^|[^[:alnum:]_.])fit\(|test\.todo\(|@pytest\.mark\.(skip|skipif|xfail)|t\.Skipf?\(|@Disabled|#\[ignore)' <<<"$full" || echo "(none)"; echo
    echo "### CI or check configuration edited"
    grep -E '^\.github/|^\.gitlab|\.ya?ml$|(^|/)package\.json$|vitest\.config|jest\.config|\.eslintrc|eslint\.config\.|tsconfig|(^|/)(pyproject\.toml|pytest\.ini|setup\.cfg|\.coveragerc|Makefile)$' <<<"$names" || echo "(none)"; echo
    echo "### Review policy edited (the config, review context and repo-local reviewers the reviewers load from this head)"
    policy_edited "$ns"; echo
    echo "### Configured lanes not run on this diff (when-scoped; no changed file matched their globs)"
    lanes="$(skipped_lanes)"; [ -n "$lanes" ] && printf '%s\n' "$lanes" || echo "(none)"; echo
    echo "### Build session permission denials"; [ -s "$STATE/denials-$A.txt" ] && cat "$STATE/denials-$A.txt" || echo "(none)"; echo
    echo "### Untracked files archived after the build (in no commit: a stray probe, or a file the build forgot to add)"
    [ -s "$STATE/quarantine-$A.list" ] && tr '\0' '\n' < "$STATE/quarantine-$A.list" || echo "(none)"
  } > "$out"
}

# -- the two prompts (rows F15-F20) --
build_prompt() { # build_prompt <round> <review-findings-file-or-empty> <red-check-file-or-empty>
  echo "Implement ticket $ISSUE of this repository. Fetch the ticket text yourself from the tracker (${TRACKER})."
  # #1048 D-5 D-19: the fetch is named, so the build's first command is never composed
  if [ "$TRACKER" = github ]; then echo "Fetch it with exactly 'gh issue view $ISSUE --json title,body,comments', as written."
  else echo "Fetch it with the getJiraIssue MCP tool, under whichever Atlassian namespace this session exposes."; fi
  echo "Do not merge. Do not delete, skip or weaken a test to make a check pass. If a test is wrong, say so in the PR."
  if [ -n "$SCRATCH" ]; then
    echo "Your scratch directory is $SCRATCH. It is already added to this session. Put all logs, probes, and PR or comment bodies in it. Never put them in the worktree or in /tmp. Put scratch files there; the scheduler removes it at the end of the run. A probe that you never committed is not a test that the PR deletes."
    echo "Run every check in the foreground: no nohup, no trailing &."
  else echo "Delete every probe or scratch file you created before you end your turn. A probe that you never committed is not a test that the PR deletes."; fi
  echo "Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables. Do not chain commands with ; or &&. Do not use \$( ) substitution. Run each check below exactly as written."
  echo "Read an issue or PR comment with gh issue view or gh pr view --json comments, never gh api."
  echo "A denied command is not a reason to end your turn: skip a command outside the allowlist and name it in the PR body as skipped. Pushing $BRANCH and opening the draft PR are never skipped."
  echo "Edit files only with the Edit and Write tools, never through a shell. Do not edit a file with python, sed -i, a heredoc or a > redirect."
  echo "Pass every PR or comment body with --body-file <a file you wrote with Write>. Never pass a body inline with --body."
  echo "A stored field the change newly reads, or a field it sends across a service boundary, gets a test that moves it through the real schema or model. Do not use a hand-built fixture for this test. A fixture that already holds the value does not prove that the store keeps the value."
  echo "A test double of a dependency this repo does not own that returns an error or an empty result cites where that shape comes from. Cite the dependency's types, its docs or a recorded real response. A double that shows only what you expect proves nothing about the dependency."
  # #1076 D-10 D-11: unconditional, so a UI ticket with no design frames carries it too
  echo "Before you write a comment that claims a UI library does or does not do something, open the installed source of that library and check the claim. Cite the installed file in the comment when the claim is not obvious."
  [ "$BOT_OK" -eq 1 ] && echo "Commit through the repo's bot identity. Never use plain git commit. Run it exactly as '$TOOLS/bot-commit.sh -C $WT -F <a message file you wrote with Write>'. Start the command with the bare path. Do not put bash before it. Run each --amend through bot-commit.sh too. A plain --amend makes you the committer and gives no warning."
  if [ "$1" -eq 1 ]; then
    echo "When the checks you ran are green, commit and push branch $BRANCH to origin. If no PR is open for this branch, open a DRAFT PR against $BASE_NAME with 'gh pr create --draft --base $BASE_NAME'. Leave it a draft: the scheduler marks it ready for review only when a review approves its head."
    echo "Write the PR body for the human who reviews it. Use short sentences and the active voice. Put one fact in each sentence. Use the same word for the same thing. Do not use idioms, metaphors or abstract words. Put what the reviewer must know first. State each fact once: a later section cites the row id and does not repeat the fact. Keep the body under 500 words, not counting the Checks table. A limit never removes a record row, a deferred decision, a skipped command or a test you think is wrong. If they do not fit, shorten the wording and cut '## Changes' first. If the repo has a pull request template, keep its headings and put the sections below under them. Write the body in this order:"
    echo "1. Line 1, exactly: 'built-by: second-shift run $RUN_ID'."
    echo "2. '## What this changes': at most 80 words. Say what changes for the users of this code, and why. Do not describe the implementation here."
    echo "3. '## Before you merge': each thing the reviewer must decide or do before the merge. For each record row with provenance deferred, name its open region. If the region's disposition is pause-and-ask, say what the build stopped on and what it asks. If it is reversible-default-and-flag, name the default you used. Include each deploy, migration or other PR that must land first. If there is nothing, write 'Nothing outside this PR.'"
    echo "4. '## Review focus': start with 'The build suggests:', then one to three bullets. Each bullet names a file or an area where a human check adds the most, and says why in one sentence. Examples: a security boundary, an assumption that no test covers, a choice that is easy to get wrong."
    echo "5. '## Decisions made for you': first one line that counts the record rows by provenance, in plain words. Example: 'The record has 9 rows. The requester answered 5 at intake. The codebase settles 3. The build added 1.' Then a table '| Row | Decision | Provenance |'. Give one line to each row with provenance user-delegated, and to each row you added or edited after commit $FIRST. For an edited row, give the old resolution, the new resolution and the reason. Use at most 40 words in a Decision cell. If no row qualifies, write 'No row was decided for you.'"
    echo "6. '## Changes': the changes, grouped by area. Use at most 8 bullets, with at most 20 words in each bullet. Do not repeat a decision or a default that an earlier section states. When you cite a record row or an acceptance criterion, put its id in parentheses after the sentence that states it. Do not write a list of ids without the facts they stand for."
    echo "7. '## Checks': a table '| Check | Result |' with each check you ran. Then a line 'Skipped:' that names each skipped command and its reason. If you skipped nothing, write 'Skipped: none.' If you think a test is wrong, name it here and give the reason."
    echo "8. A line 'Decision record:' with a link to $RECORD_REL that opens on GitHub, then the line 'Record baseline: $FIRST'."
    if [ "$TRACKER" = github ]; then echo "9. The line 'Closes #$ISSUE', so the ticket closes on merge."; else echo "9. The template's '### Jira Items' heading, or your own, and under it the line 'Closes [$ISSUE]'."; fi
  else echo "Address the review below: fix each [blocker] finding, or rebut it in a PR comment. Fix each record row the review scored violated or undeterminable, or edit that row as the record rules below allow. A [note] finding requires nothing: fix one only if you choose to, and never rebut or reply to one. Then commit and push $BRANCH. If you added or edited a record row, add it to the PR body's '## Decisions made for you' table. Edit the body with 'gh pr edit <pr> --body-file <a file you wrote with Write>'."; fi
  echo; echo "The following decisions were settled with the requester before implementation started. They are binding. The record's '## Knowledge source' and '## Fan-out' sections are context, not binding. They hold evidence that intake read, not decisions. Only the D-n rows bind. The record is committed at $RECORD_REL; edit rows there. If you must change the decision of a row, edit that row in place. Write the new resolution and set the provenance to user-delegated. End the cell with one sentence that starts 'Changed in build:' and gives the reason. A material decision that no row covers gets a new row with provenance user-delegated. End its cell with one sentence that starts 'Added in build:' and gives the reason. Commit each edit with the code. Commit $FIRST is the record baseline the review reads: never amend, rebase or force-push over it. Never post a comment starting with 'verdict:'."
  echo; record_at_first
  if record_has_test_intent; then # #1039 D-4 D-5 D-6 D-12: the plan is a coverage map the scheduler checks, never a tick list
    echo; echo "For each acceptance criterion (AC), the record's '## Test intent' section names the observable behavior that its test must prove. For an exempt AC, it names the exemption and its reason."
    echo "Your first commit after the record commit $FIRST is a task plan at $PLAN_REL. Write each group as '## N. Group'. Write each task as '- [ ] N.M Description (files)'. Put each test task before the implementation task that it covers. End each test task with the ids of the ACs that its test proves. Put each id in its own brackets. Put nothing after the last id. Example: '- [ ] 1.1 Description (files) [AC-1] [AC-3]'."
    echo "Tag each AC that the section does not exempt on at least one test task. Do not tag an id that the section's 'ACs:' line does not list. Make sure that each AC's tagged test proves the behavior its line states. A ticked box has no meaning. A line that starts with '- [' and is not a task in that form is an unparseable line."
    echo "Before a review starts, the scheduler checks the plan at the pushed head against the record at $FIRST. These problems come back to you as findings: an uncovered AC, an id that the record does not define, a missing plan, an unparseable line. A red plan check spends one checks-red attempt."
    echo "In each task that carries an AC id, name its test files in the parentheses that end the description. Separate the file names with commas. A tagged task that names no test file comes back to you as findings in the same way."
    # #1040 S-3, #1053 S-3: the check the scheduler runs next, stated only when a runner is configured to run it; the
    # file::case grammar only when a runner judges named tests
    if test_runners | jq -e 'select((.format // "exit") != "exit")' >/dev/null 2>&1; then
      echo "A runner with format cases, vitest-json or jest-json judges named tests, not files. For a file such a runner matches, name each test as file::case. For vitest and jest, the case is the test's describe titles and its own title, joined with ' > ', as the runner renders them at the head. For a cases runner, the case is the id the test prints: in run-selftest-lib.sh, the name of the fixture block. Put the case in backticks when it holds a space, '>', '(', ')', ',' or '['. A case without backticks runs to the next comma. Example: (src/a.test.ts::\`Importer > dup > rejects (409)\`, src/b.test.ts::adds). A case cannot hold a backtick. An unterminated backtick, or a case that needs backticks and has none, is an unparseable line."
    fi
    [ -z "$(test_runners)" ] || echo "Then the scheduler puts the worktree on the record commit $FIRST. It applies the head's tagged test files on top, with the changed files that commands.$(commands_key).testSupport names, and runs the tagged tests through their configured test runner (commands.$(commands_key).testRunners). Without your change, every one must fail there. A runner with format exit judges the whole file by its exit code. A runner with format cases, vitest-json or jest-json judges each named test by the result that it reports for that test, and a vitest-json or jest-json runner runs all of its files in one call. A named test whose file does not load there, or that a failing vitest beforeAll skips there, must pass at the head instead. A cases runner that takes {cases} runs only the named cases, and each of them that fails there must also pass at the head. There are two exceptions. The scheduler does not run the files of an AC that the section marks 'holds'. That AC is existing behavior, and the checks at the head prove it. It notes the files of an AC that the section marks 'unchecked', but does not run them. A tagged test is red if it passes there, if it is skipped there, if its runner does not run it, if two tests match its name, if its runner cannot judge the form that you named it in, if no runner matches its file, or if the head does not carry its file. Each red test comes back to you as findings, and a red check spends one checks-red attempt. A test that passes without the change does not test the change. Each file must also finish there within its runner's time bound ($(test_runners | jq -r --argjson d "$FWC_TIMEOUT_DEFAULT" '"\(.when | join(", ")): \(.timeoutSeconds // $d)s\(if (.format // "exit") != "exit" then ", " + .format else "" end)"' | paste -sd ';' - | sed 's/;/; /g')), or it is red too. For a vitest-json or jest-json runner, the bound covers the one call over all of its files. Tag a test file that contains the cases of this change, not a whole slow suite."
  fi
  if [ -n "$(frames_rows)" ]; then
    echo; echo "This ticket has design frames. Follow the figma-faithful sequence:"
    echo "1. Read every frame id in the '## Design frames' section first."
    echo "2. Write the token and component plan."
    echo "3. Before you write UI code, tell a subagent to compare that plan with the frames. The subagent lists what the plan gets wrong. Then fix the plan."
    echo "4. Render every screen with the repo's render command. Open the PNG and compare it with its frame. Fix each difference. Do up to three rounds per screen."
    echo "A screen that shows an error page, a login page or a spinner is not done."
  fi
  # the scheduler's pass at the pushed head is the authority (#1035): the build runs what covers its change, not the whole list again
  echo; echo "While iterating, rerun only the test file or suite your change touches."
  # #1048 D-4 D-20: a repo's CLAUDE.md or docs may list more; those commands are not granted
  echo "Run the checks listed below and the tests your change touches, never a verification list from the repo's CLAUDE.md or docs."
  echo "Before you push, run the checks below that cover what you changed and make them green; running the whole list is not required. The scheduler runs every command below at the pushed head before a review starts. A lane with changed-file globs runs only when a changed file matches its globs. Of these commands, a red one comes back to you as findings and spends a checks-red attempt."; checks_list all | sed 's/^/- /'
  [ -n "$2" ] && { echo; echo "## Review findings"; cat "$2"; }
  [ -n "${3:-}" ] && { echo; echo "## Red check output"; echo "A red check cannot be rebutted. Reproduce it with its command, then fix the cause. If the check itself is wrong, say so in the PR."; cat "$3"; }
}
review_prompt() { # review_prompt <pr> <review-input-file> [<the previous verdict's failed rules, on a re-spawn>]
  echo "You review PR #$1 of this repository at its current head. Your session is separate from the session that built it. Check out the PR head. Read the decision record at $RECORD_REL twice. First read it as it stood at commit $FIRST (git show $FIRST:$RECORD_REL). Then read it as it stands at the head."
  echo "Score EVERY row of the record against the code. The scores are: honored, violated, departed, or undeterminable. A departed row was edited: name who decided, per its provenance. For an undeterminable row, say what you could not read. A violated or undeterminable row is a blocker. Do not approve when a row has either score."
  echo "A row can name a deferred, unmeasured or inherited cost, load or performance risk. Still score that row on whether the code matches it. The row is the operator's decision. A score never overrides it. Its risk is also required performance work: the review states the worst-case bound as a finding, at the severity the performance rules give it. The row permits the out-of-diff reads that check the bound. The row can name a file that the diff does not touch. That fact scores the row. It does not bound the risk."
  echo "The PR's base branch is $BASE_NAME. Pass it to review-lead as the base. Then the diff is origin/$BASE_NAME...HEAD and not the remote default branch."
  echo "Then run review-toolkit:review-lead over the PR diff. Pass it the ticket $ISSUE yourself, so it never reads the PR body to find one. DECLARE THE PIPELINE DEFAULT PANEL when you invoke it. Under that panel the fan-out defaults to scope-completeness-reviewer. The other four reviewers (security-reviewer, a11y-reviewer, unit-test-mutation-reviewer and performance-reviewer) run only on an opt-in. An opt-in comes from one of two sources. The first is a 'review panel' row in the record with user-answered or user-delegated provenance, naming security, a11y, unit-test-mutation or performance. The second is the config's reviewers.default[]. review-lead never infers this. An undeclared panel leaves the surface triggers in force."
  echo "You can opt one of the four back in. That is the expected call whenever the diff introduces a surface. It is not expected when the diff only edits an existing surface. Opt in security for a new authentication, session, tenancy or ownership-scoping path. Also opt it in for a new query built from external input. Opt in a11y for new form controls or a new interactive component. Opt in unit-test-mutation for new logic with a co-located spec. Opt in performance for a new entry point that reaches a data read or existing heavy work. An entry point is a route, handler, consumer or SDK method. For a change to a file that already sits on one of those surfaces, you decide either way. Pass each short name to review-lead with a one-line reason."
  echo "Do not stand in for a specialist on a surface the diff introduces. Your lead pass is one reader over the whole diff. It is not that reviewer's checklist. The trimmed panel stays the default because it was measured. You judge a diff that it was never measured on."
  echo "Declining a reviewer whose surface the diff introduces is itself a decision. When you decline one, pass the decline to review-lead with a one-line reason. review-lead writes the decline into the panel line of the review. The human who reads the verdict reads that line. An introduced surface with neither a reviewer nor a reason is a silent decision."
  echo "A record-named cost risk makes performance a required decision. A D-n row or an OR-n Open Region of the record can name a cost, load or performance risk. When one does, opt performance in, or pass its decline with a reason that answers that row. When you opt in, pass review-lead that row and the new entry point's path:line. Then performance-reviewer traces the risk and not the whole diff. A record-named risk with neither a dispatch nor a decline is a process [blocker] on your verdict. The blocker is for the missing decision, not for the code. Whether a decline answers the row is your judgment. The panel line shows it."
  echo "Your scratch directory is $SCRATCH (already added to this session). It is the only place for logs, probes, and your verdict and comment drafts. Never use the worktree or /tmp for them. Put scratch files there; the scheduler removes it at the end of the run."
  echo "review-lead dispatches its reviewers through the code-review.mjs Workflow. Stage that script by reading it and writing it with Write into $SCRATCH, never into the worktree. A cp out of the plugin cache is denied here. Run the Workflow from $SCRATCH."
  echo "Do not run the repo's test suites or checks: the scheduler ran them at this head before spawning you, and CI runs them on the PR. Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables, no ; or && chains, no | pipes, no \$( ) substitution, no nohup or trailing &. Write files only with the Write tool, never through a shell (no python, heredoc or > redirect)."
  echo "Read an issue or PR comment with gh issue view or gh pr view --json comments, never gh api."
  echo "Read the build's own account last. First write the row scores and your findings, review-lead's included, from the record, the diff and the code. Only then read the PR description and the build's PR comments. Use them to reconcile the departures and rebuttals they state. Measurements show that an author's framing lowers what a reviewer finds. If that reading changes a score or a finding, say so in the verdict's '## Notes' with a line 'revised after reading the build's account: <what changed>'."
  echo "If the ticket has design frames, render every screen at the head with the repo's render command. Compare each screen with its frame. If you cannot render, you cannot approve: post 'verdict: needs-work' with line 3 'reason: render-unavailable'."
  local via=""; [ "$BOT_OK" -eq 1 ] && via=" through $GH (the bot identity)"
  echo; echo "Post ONE PR comment$via, its body passed with --body-file <a file in $SCRATCH>, never inline with --body. Its body follows the verdict grammar below exactly. Never edit that comment afterwards."
  echo "Before you post, check your draft: run 'bash $TOOLS/verdict-check.sh <your draft in $SCRATCH> $WT/$RECORD_REL $SCRATCH/record-at-first.md' (the record at the head, then at $FIRST). It prints every rule the draft breaks. Fix the draft until it exits 0. The scheduler runs the same check on the comment you post. A comment that fails the check does not count: the scheduler posts no status and starts a new review."
  echo "For every file under 'Existing test or snapshot expectations changed' in the scheduler input below, trace its removed expectation to an acceptance criterion of the ticket or a row of the decision record. An entry you cannot trace is a [blocker]. Name the file and the expectation. Require the build to cite the criterion or row that authorized the change."
  echo "For every file under 'Review policy edited' in the scheduler input below, trace the edit to an acceptance criterion of the ticket or a row of the decision record. The reviewers load these files from the head, so this PR is reviewed against the policy it edits. An entry you cannot trace is a [blocker]. Name the file. Require the build to cite the criterion or row that authorized the edit. The edit itself is never the blocker. The blocker is a merge that does not name who decided the edit."
  echo
  # #991: the verdict grammar, stated once here and once in review/SKILL.md step 8; tools/verdict-check.sh enforces it
  grep -v 'LOCKSTEP-' <<'GRAMMAR'
# LOCKSTEP-BEGIN verdict-grammar
The verdict comment has these parts, in this order and nothing else:
- Line 1 is exactly `verdict: approve` or `verdict: needs-work`. Line 2 is exactly `reviewed: <the full sha of the head you reviewed>`. An optional line 3 is exactly `reason: render-unavailable`.
- `## Summary`, right after line 2, or line 3 when it is present. Its first line is exactly `Mergeable as it is.` on an approve, or `Not mergeable yet.` on a needs-work. Then name each row scored `departed`, `violated` or `undeterminable`, with its score. Then write each action the human must take, one per line, or `Nothing to do.` Write no table. Use at most eight lines.
- `## Decision record rows`, then a table headed `| Row | Score | Evidence |` and its `| --- | --- | --- |` line, with one row for every `D-n` row of the record at its first commit and at the head: a row the build deleted and a row it added are both scored. The Row cell's first token is the row's `D-n` id, and the Score cell's first word is one of `honored`, `violated`, `departed`, `undeterminable`. The section holds the table and blank lines only: per-row detail goes in the Evidence cell, anything else in `## Notes`. Other row kinds, such as `RS-n`, are not scored in this table.
- `## Findings`, which runs to the next `## ` heading. Each finding starts with `- [blocker] B<n> ` or `- [note] N<n> `, and its continuation lines are indented two or more spaces. Suppressed findings are `[note]`s. A section with no findings holds the single line `None.`.
- After its id and one space, a finding from review-lead's report carries that report's reviewer, file:line and confidence in its form: `- [blocker] B1 [Reviewer] file:line (confidence: N) — <text>`, file:line only where the finding has one. A finding you raise from a rule (a violated or undeterminable row, an untraced test-expectation change) or as a process note names its rule and carries no number: never invent a score.
- `## Panel` (optional): the panel lines review-lead writes.
- `## Notes` (optional): free prose for the human, such as process notes or `revised after reading the build's account: <what changed>`. Nothing in it counts toward the verdict.

`Ready to merge?` is never written anywhere in the body.

A `[blocker]` is something in the diff that must change before merge. The PR title and description are not the diff: a stale or wrong one is at most a `[note]`, never a `[blocker]`, and never makes a verdict `needs-work`. A `[note]` requires nothing. review-lead's findings translate one way: a Critical is a `[blocker]`; a Warning you would hold the merge for is a `[blocker]`, and any other Warning is a `[note]`; its "Ready to merge?" and "With fixes" are never written on this comment.

`verdict: approve` means mergeable as-is: every record row is scored, none is `violated` or `undeterminable`, and there is no `[blocker]` and no `reason: render-unavailable` line. `verdict: needs-work` carries at least one `[blocker]`, a `violated` or `undeterminable` row, or the `reason: render-unavailable` line; under that line the rows need not be scored, and the findings may be `None.`.
# LOCKSTEP-END verdict-grammar
GRAMMAR
  # #1033 D-1 D-3: review-lead applies the repo's inclusion test; the verdict carries its block whole. Stated once here and
  # once in review/SKILL.md step 8
  echo; grep -v 'LOCKSTEP-' <<'KB'
# LOCKSTEP-BEGIN kb-contributions
Knowledge-base contributions: when review-lead's report has a `### Knowledge-base contributions` block, carry it into the verdict's `## Notes` as review-lead wrote it — the lead line `Knowledge-base contributions:` with one proposal per line under it, or the single line `Knowledge-base contributions: none`. review-lead applied the inclusion test the repo's review-context.md declares: do not apply it again, and add, drop or reword no proposal. Carry the whole list on every verdict, never only what changed since an earlier one: the earlier verdicts are collapsed once one binds. When the report has no such block, the verdict carries no contributions line. A proposal is a draft the operator files in the knowledge base: never a finding, and it never makes a verdict `needs-work`.
# LOCKSTEP-END kb-contributions
KB
  # the verdict's style, stated once here and once in review/SKILL.md step 8
  echo; grep -v 'LOCKSTEP-' <<'STYLE'
# LOCKSTEP-BEGIN verdict-style
Write the verdict for the human who decides the merge.
Use short sentences. An instruction has at most 20 words. A statement has at most 25 words.
Write one instruction per sentence. Use the active voice.
Do not use idioms, hedges or semicolon chains.
Use the same word for the same thing every time.
State each fact once. Do not repeat a fact from one section in another.
In the rows table:
- Keep each Evidence cell to one or two sentences.
- Start the Evidence cell with the file:line or the test id. Then say what it shows.
- Start the Evidence cell of a departed row with `Decided by <who> (<provenance>).` Then give the commit of the edit and the new resolution.
- If the edit of a departed row names no decider, start its Evidence cell with `No decider named.`
- Start the Evidence cell of a row that the build added with `Added by the build, <provenance>.`
- Start the Evidence cell of a row that the build deleted with `Deleted by the build.` Then name who decided.
- Put longer detail in `## Notes`.
In `## Findings`:
- Put blockers first and notes after them. Put dismissed and suppressed notes last.
- Start the text after the dash of such a note with `Dismissed.` or `Suppressed.` Then give the reason in one sentence.
- Give the defect in the first sentence of each finding.
- Put the evidence on continuation lines. Indent them two spaces.
- End each blocker with the continuation line `Fix: <one instruction>`.
- Do not give a note a Fix line. A note requires nothing.
- Write a note in at most three lines. Write a dismissed or suppressed note in one line.
In `## Panel`:
- Copy the panel lines that review-lead writes. Do not merge, drop or reword a line.
- Do not repeat the panel reasons in `## Notes`.
In `## Notes`:
- Use one `###` sub-heading for each topic. Write at most six sentences under it.
- Write an inventory, such as the mutation run, as a list.
- Put the knowledge-base block last.
- Do not write a sub-heading that has nothing under it.
- Write a topic that changed no score or finding in one sentence, or leave it out.
- Keep `## Notes` under 150 words, not counting the knowledge-base block.
A limit never removes a row, a finding, a panel line or a knowledge-base proposal. If they do not fit, shorten the wording.
# LOCKSTEP-END verdict-style
STYLE
  if [ -n "${3:-}" ]; then
    echo; echo "## Your previous verdict did not bind"
    echo "The previous review posted a verdict. Its comment does not support its own verdict line. The scheduler posted no status for it and spawned you in its place. Review the head yourself. Post a new verdict comment in the grammar above. Never edit the old one. The old verdict broke these rules:"
    sed 's/^/- /' "$3"
  fi
  echo; echo "## Scheduler input (deleted or skipped tests, changed test or snapshot expectations, config edits, review-policy edits, the build's permission denials, and the untracked files archived after it)"; cat "$2"
}
build_allowlist() { # row F3: derived from what the record and config name
  # bash $WT/*: a build runs the scripts it writes in its worktree, which the checks already execute.
  # #1048: Grep and Glob are its lookups (D-1), never a Bash grep, ls, wc or head; a later round may edit the PR body (D-3)
  local allow="Read,Grep,Glob,Edit,Write,Agent,Bash(git *),Bash(gh pr create*),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh pr edit * --body-file *),Bash(gh issue view*),Bash(bash $WT/*)$MCP_ALLOW" c
  [ "$BOT_OK" -eq 1 ] && allow="$allow,Bash($TOOLS/bot-commit.sh*),Bash(bash $TOOLS/bot-commit.sh*),Bash($GH *)"   # the bash form too: the scheduler calls it that way, and a build copies it
  [ -n "$(frames_rows)" ] && allow="$allow,mcp__figma,mcp__plugin_figma_figma"
  while IFS= read -r c; do [ -n "$c" ] && allow="$allow$(cmd_grants "$c" xargs)"; done <<EOF
$(checks_list all)
EOF
  [ -n "$RENDER_CMD" ] && allow="$allow$(cmd_grants "$RENDER_CMD" xargs)"
  printf '%s' "$allow"
}
review_allowlist() { # row F20: review-lead's panel is a Workflow whose agents inherit these tools
  local allow="Read,Grep,Glob,Agent,Skill,Workflow,Bash(find *),Bash(cp *),Bash(jq *),Bash(shasum *),Bash(bash *check-review-context.sh*),Bash(bash *verdict-check.sh*),Bash(git *),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh pr diff*),Bash(gh issue view*)$MCP_ALLOW"
  [ -n "$RENDER_CMD" ] && allow="$allow$(cmd_grants "$RENDER_CMD")"
  [ -n "$(frames_rows)" ] && allow="$allow,mcp__figma,mcp__plugin_figma_figma"
  [ "$BOT_OK" -eq 1 ] && allow="$allow,Bash($GH pr comment*),Bash($GH pr view*)"   # never the wrapper whole: it takes api -X DELETE
  printf '%s' "$allow"
}

# -- the worktree (rows E17-E21, J6) --
worktree_inflight() { # worktree_inflight <archive-tag> -> 0 collected · 8 in flight · 1 unreadable
  # tracked dirt (modified, staged, intent-to-add, submodule) and unpushed commits are in flight; untracked files alone,
  # on a tree at the pushed head, are what a session left behind: archived to $STATE/quarantine-<tag>.tar, never discarded
  # INFLIGHT_UNPUSHED holds the unpushed commits when they, on a clean tree, are all that is in flight (#973)
  local dirty unpushed; INFLIGHT_REASON=""; INFLIGHT_UNPUSHED=""
  dirty="$(git -C "$WT" status --porcelain --untracked-files=no 2>&1)" || { INFLIGHT_REASON="its status could not be read ($dirty)"; return 1; }
  if [ -n "$dirty" ]; then INFLIGHT_REASON="its tree is not clean"; return 8; fi
  # best effort, wrong only in the SAFE direction: a failed fetch can make pushed work look unpushed, never the reverse
  git -C "$WT" fetch --quiet origin "$BRANCH" >/dev/null 2>&1
  unpushed="$(git -C "$WT" log --oneline "refs/remotes/origin/$BRANCH..HEAD" 2>&1)" || { INFLIGHT_REASON="origin/$BRANCH is unresolvable, so nothing proves its work is pushed"; return 1; }
  if [ -n "$unpushed" ]; then INFLIGHT_REASON="it carries commits that are not on origin/$BRANCH"; INFLIGHT_UNPUSHED="$unpushed"; return 8; fi
  quarantine_untracked "$1" || return 8
  return 0
}
quarantine_untracked() { # quarantine_untracked <tag> -> 0 nothing left or archived · 1 not archived (INFLIGHT_REASON set; the originals stay)
  # one entry per file, raw NUL-separated paths, whatever status.showUntrackedFiles says; ignored files are never listed,
  # and an untracked path under a declared paths.runtimeData is left for runtime_data_held
  local ar="$STATE/quarantine-$1.tar" list="$STATE/quarantine-$1.list" f p keep n err toc missing
  git -C "$WT" ls-files -z --others --exclude-standard > "$list.all" 2> "$list.err" \
    || { INFLIGHT_REASON="its untracked files could not be listed ($(tr '\n' ' ' < "$list.err"))"; return 1; }
  : > "$list"
  while IFS= read -r -d '' f; do
    keep=1
    while IFS= read -r p; do p="${p#./}"; p="${p%/}"; [ -n "$p" ] || continue; case "$f" in "$p"|"$p"/*) keep=0 ;; esac; done <<EOF
$RUNTIME_DATA
EOF
    [ "$keep" -eq 0 ] || printf '%s\0' "$f" >> "$list"
  done < "$list.all"
  rm -f "$list.all" "$list.err"
  [ -s "$list" ] || { rm -f "$list"; return 0; }
  n="$(tr -cd '\0' < "$list" | wc -c | tr -d ' ')"
  err="$(tar -C "$WT" -cf "$ar" --null -T - < "$list" 2>&1)" || { INFLIGHT_REASON="its $n untracked file(s) could not be archived to $ar ($err)"; return 1; }
  # the archive is read back before any original is deleted: every listed path must be in it
  toc="$(tar -tf "$ar" 2>&1)" || { INFLIGHT_REASON="the archive $ar of its $n untracked file(s) could not be read back ($toc)"; return 1; }
  missing="$(tr '\0' '\n' < "$list" | grep -vxF -f <(printf '%s\n' "$toc") | head -n 1)"
  [ -z "$missing" ] || { INFLIGHT_REASON="the archive $ar does not hold its untracked file $missing"; return 1; }
  while IFS= read -r -d '' f; do
    rm -rf -- "${WT:?}/$f" || { INFLIGHT_REASON="$f could not be deleted after it was archived to $ar"; return 1; }
  done < "$list"
  say "worktree: archived $n untracked file(s) left in $WT to $ar (in no commit; open the archive to recover one)"
}
runtime_data_held() { # 0 none · 8 held · 1 unreadable. `status --porcelain` never sees ignored files, and `worktree remove` deletes them
  # one read per declared path: git folds an ignored directory into its ignored ancestor, so the operator is told the path they declared
  local p out held=""; RUNTIME_REASON=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    out="$(git -C "$WT" status --porcelain --ignored -- "$p" 2>&1)" || { RUNTIME_REASON="the status of paths.runtimeData could not be read ($out)"; return 1; }
    [ -z "$out" ] || held="$held${held:+ }$p"
  done <<EOF
$RUNTIME_DATA
EOF
  [ -n "$held" ] || return 0
  RUNTIME_REASON="runtime data under $held"; return 8
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
  base_files="$(git -C "$WT" -c core.quotePath=false diff --name-only "$BASE_START" "$base_now" 2>/dev/null)" || terminal staleness-unreadable "cannot diff origin/$BASE_NAME's move ($BASE_START..$base_now)"
  ours="$(git -C "$WT" -c core.quotePath=false diff --name-only "$FIRST" HEAD 2>/dev/null)" || terminal staleness-unreadable "cannot diff this branch against its record commit"
  overlap="$(comm -12 <(printf '%s\n' "$base_files" | sort) <(printf '%s\n' "$ours" | sort) | grep . | head -n 3 | tr '\n' ' ')"
  [ -z "$overlap" ] || rebase_onto_base "$base_now" "origin/$BASE_NAME moved into file(s) this branch touches: $overlap"
}
rebase_onto_base() { # rebase_onto_base <base sha> <why>: a rebase git completes alone re-anchors the run; a conflict, or anything it cannot vouch for, is the stop
  # The one history rewrite this file makes. It discards nothing: the tree is clean, origin held the old head until a
  # leased push replaced it, and every way back is `reset --keep` onto that head. The record commit is rewritten with
  # the rest, so its blob is verified unchanged and the PR body's 'Record baseline:' line follows it — the review reads
  # a line naming a commit that is not the record's as a rewritten record (review/SKILL.md step 3).
  local onto="$1" why="$2" old old_blob new_first conflicts dirty
  worktree_ready
  dirty="$(git -C "$WT" status --porcelain 2>/dev/null)" || terminal env-worktree "cannot read the status of $WT"
  [ -z "$dirty" ] || terminal staleness-expired "$why — not rebased: $WT carries uncommitted work"
  old="$(git -C "$WT" rev-parse HEAD 2>/dev/null)" || terminal env-worktree "cannot read HEAD in $WT"
  old_blob="$(git -C "$WT" rev-parse -q --verify "$FIRST:$RECORD_REL" 2>/dev/null)" || terminal env-worktree "cannot read the record at $FIRST:$RECORD_REL"
  if ! git -C "$WT" rebase -q "$onto" >/dev/null 2>&1; then
    conflicts="$(git -C "$WT" -c core.quotePath=false diff --name-only --diff-filter=U 2>/dev/null | head -n 3 | tr '\n' ' ')"
    git -C "$WT" rebase --abort >/dev/null 2>&1 || terminal env-worktree "the rebase onto $onto stopped and could not be aborted — run 'git rebase --abort' in $WT"
    terminal staleness-expired "$why — the rebase onto $onto conflicts${conflicts:+ in: $conflicts}; rebase by hand, then re-launch"
  fi
  new_first="$(git -C "$WT" log --format=%H --diff-filter=A -- "$RECORD_REL" 2>/dev/null | tail -n 1)"
  if [ -z "$new_first" ] || [ "$(git -C "$WT" rev-parse -q --verify "$new_first:$RECORD_REL" 2>/dev/null)" != "$old_blob" ]; then
    git -C "$WT" reset -q --keep "$old" 2>/dev/null
    terminal staleness-expired "$why — not rebased: the rebased branch does not carry the record as committed at $FIRST"
  fi
  if ! git -C "$WT" push -q --force-with-lease="$BRANCH:$old" origin "$BRANCH" 2>/dev/null; then
    git -C "$WT" reset -q --keep "$old" 2>/dev/null
    terminal env-push "rebased $BRANCH onto $onto but could not push it (origin/$BRANCH may have moved since $old); $WT is back at $old"
  fi
  say "staleness: $why — rebased cleanly onto $onto and pushed; record baseline $FIRST -> $new_first"
  baseline_follows "$FIRST" "$new_first"
  FIRST="$new_first"; BASE_START="$onto"
}
baseline_follows() { # baseline_follows <old> <new>: the open PR's 'Record baseline:' line naming <old> is rewritten to <new>; no PR yet, nothing to follow
  local pr="$PR" repo body f="$STATE/pr-body-rebased.md" rc
  if [ -z "$pr" ]; then pr="$(open_prs)" || terminal baseline-unwritten "the branch is rebased (record baseline now $2), but the open PRs of $BRANCH could not be read — set the PR body's 'Record baseline:' line to $2, then re-launch"; pr="$(printf '%s\n' "$pr" | head -n 1)"; fi
  [ -n "$pr" ] || return 0
  repo="$(repo_slug)" && body="$("$GH_READ" api "repos/$repo/pulls/$pr" --jq .body 2>/dev/null)" \
    || terminal baseline-unwritten "the branch is rebased (record baseline now $2), but PR #$pr's body could not be read — set its 'Record baseline:' line to $2, then re-launch"
  printf '%s\n' "$body" | tr -d '\r' | awk -v old="$1" -v new="$2" '
    /^Record baseline: [0-9a-f]+[[:space:]]*$/ && length($3) >= 7 && index(old, $3) == 1 { print "Record baseline: " new; n++; next }
    { print }
    END { exit n ? 0 : 3 }' > "$f"; rc=$?
  [ "$rc" -ne 3 ] || { say "staleness: PR #$pr's body names no 'Record baseline: ${1:0:7}…' line; nothing to follow"; return 0; }
  "$GH" api -X PATCH "repos/$repo/pulls/$pr" -F "body=@$f" >/dev/null 2>&1 \
    || terminal baseline-unwritten "the branch is rebased (record baseline now $2), but PR #$pr's body could not be written (it is in $f) — set its 'Record baseline:' line to $2, then re-launch"
  say "staleness: PR #$pr's 'Record baseline:' line now names $2"
}

# -- the PR (rows E7-E13, E16) --
pr_conventions() { # pr_conventions <pr> <attempt> -> 0, 1 unmet (reasons in $STATE/pr-conventions-<attempt>.txt), 2 unreadable (the caller refuses)
  local out="$STATE/pr-conventions-$2.txt" info body first
  info="$("$GH_READ" pr view "$1" --json body,isDraft 2>/dev/null)" || return 2
  body="$(printf '%s' "$info" | jq -r '.body // ""')"; PR_DRAFT="$(printf '%s' "$info" | jq -r '.isDraft // false')"
  : > "$out"
  first="$(printf '%s\n' "$body" | head -n 1)"
  grep -q "^built-by: second-shift run " <<<"$first" || echo "PR body line 1 must be 'built-by: second-shift run <id>'" >> "$out"
  grep -qF "$RECORD_REL" <<<"$body" || echo "PR body must link the decision record at $RECORD_REL" >> "$out"
  if [ "$TRACKER" = github ]; then
    grep -qiE "(^|[^a-z])closes[[:space:]]+#$ISSUE([^0-9]|$)" <<<"$body" || echo "PR body must carry 'Closes #$ISSUE'" >> "$out"
  else # the Closes line lives under the Jira Items heading, matched case-insensitively, any depth; the next heading closes it
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
  # row B10: only a Bot or the account this scheduler writes with binds (lane_comments' filter) —
  # anyone can comment on a public repo, and a needs-work body becomes the next BUILD's findings
  local repo comments me
  repo="$(repo_slug)" || return 2
  me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
  comments="$("$GH_READ" api "repos/$repo/issues/$PR/comments" --paginate 2>/dev/null)" || return 2
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$comments" \
    | jq -r --arg s "$1" --arg e "$2" --arg h "$HEAD_SHA" --arg me "$me" '
        .[] | select(.created_at >= $s and .created_at <= $e and .created_at == .updated_at)
        | select((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))
        | select((.body | split("\n")[0]) | test("^verdict: (approve|needs-work)$"))
        | select((.body | split("\n")[1]) == ("reviewed: " + $h))
        | (.body | split("\n")[0] | sub("^verdict: ";"")) + "\t" + (.body | @base64) + "\t" + (.html_url // "") + "\t" + ((.id // "") | tostring)' \
    | tail -n 1 > "$STATE/verdict.tsv"
  [ -s "$STATE/verdict.tsv" ] || return 1
  cut -f2 "$STATE/verdict.tsv" | base64 --decode > "$STATE/verdict-body.md"
  cut -f1 "$STATE/verdict.tsv"
}
# -- the verdict check (#991 D-9): a bound verdict counts only when its own body backs it, under the grammar the review
# prompt states. The record is read at the head as well as at FIRST, so a row the build added or deleted is owed a score --
verdict_check() { # verdict_check <attempt> -> verdict-check.sh's exit: 0 backed · 1 breaks a rule (the rules in $STATE/verdict-check-<attempt>.txt) · 2 uncheckable
  local hr="$STATE/record-head-$1.md" fr="$STATE/record-first.md"
  record_at_first > "$fr" || rm -f "$fr"   # a record that cannot be read is a missing file: the checker refuses, never passes
  git -C "$WT" show "$HEAD_SHA:$RECORD_REL" > "$hr" 2>/dev/null || rm -f "$hr"
  cp "$STATE/verdict-body.md" "$STATE/verdict-body-$1.md" || return 2
  bash "$TOOLS/verdict-check.sh" "$STATE/verdict-body-$1.md" "$hr" "$fr" > "$STATE/verdict-check-$1.txt" 2>&1
}
verdict_notice() { # verdict_notice <attempt> <verdict url>: one plain PR comment linking the rejected verdict and naming its failed rules; never fatal, never an edit of the verdict
  local f="$STATE/verdict-notice-$1.md" err
  { echo "second-shift run $RUN_ID: the verdict at ${2:-(its URL was not read)} does not bind. Its comment breaks the verdict grammar, so the scheduler posted no \`$STATUS_CONTEXT\` status and started no build."
    echo; echo "Rules it breaks:"; sed 's/^/- /' "$STATE/verdict-check-$1.txt"; echo
    echo "The scheduler never edits a verdict. After the first failed verdict, it starts one new review. After the second, the run ends as review-unbound. Then run /dev-pipeline:review $PR by hand."; } > "$f"
  err="$("$GH" pr comment "$PR" --body-file "$f" 2>&1 >/dev/null)" && { say "verdict: the notice naming the failed rules is posted on PR #$PR"; return 0; }
  STATUS_NOTES="${STATUS_NOTES}verdict notice: NOT posted — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)"$'\n'; say "verdict: could not post the notice on PR #$PR"
}
# -- the review status (#915 D-1 D-3 D-4 D-5 D-7): the BOUND verdict as a commit status on the sha it names. Called only
# after the head-moved check, so a voided verdict posts nothing; a failed post is reported in the run block, never fatal --
STATUS_CONTEXT="second-shift/review"; STATUS_NOTES=""
RUN_NOTES=""   # run-scoped notes for the run block (row H14's scaled-smoke note); STATUS_NOTES stays verdict-scoped
review_status() {
  local state desc repo url err why args
  case "$VERDICT" in
    approve) state=success; desc="approved at this head — see the verdict" ;;
    needs-work) state=failure; desc="needs-work at this head — see the verdict" ;;
    *) return 0 ;;
  esac
  url="$(cut -f3 "$STATE/verdict.tsv" 2>/dev/null)"
  args=(-f "state=$state" -f "context=$STATUS_CONTEXT" -f "description=$desc"); [ -z "$url" ] || args+=(-f "target_url=$url")
  if ! repo="$(repo_slug)"; then why="the repo slug could not be read"
  elif err="$("$GH" api -X POST "repos/$repo/statuses/$HEAD_SHA" "${args[@]}" 2>&1 >/dev/null)"; then
    STATUS_NOTES="${STATUS_NOTES}status: $STATUS_CONTEXT=$state on $HEAD_SHA"$'\n'; say "status: $STATUS_CONTEXT=$state posted on $HEAD_SHA"; return 0
  else
    why="$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)"
    # never retried as the operator: a configured bot that cannot write statuses is the App's missing permission
    [ "$BOT_OK" -eq 1 ] && grep -qE 'HTTP 40[34]' <<<"$err" && why="$why — the bot's GitHub App needs the 'Commit statuses: write' permission"
  fi
  STATUS_NOTES="${STATUS_NOTES}status: NOT posted ($STATUS_CONTEXT=$state on $HEAD_SHA) — $why"$'\n'; say "status: NOT posted on $HEAD_SHA — $why"
}
# -- the earlier verdicts (#946 D-3 D-5 D-6 D-7): once a verdict binds, every earlier lane verdict on the PR is minimized
# as outdated through $GH, so the bound one is the one a human sees expanded. A failure is one run-block line, never fatal --
minimize_earlier_verdicts() {
  local id repo err
  id="$(cut -f4 "$STATE/verdict.tsv" 2>/dev/null)"
  if [ -z "$id" ]; then err="the bound verdict's comment id was not read"
  elif ! repo="$(repo_slug)"; then err="the repo slug could not be read"
  elif err="$(GH="$GH" bash "$TOOLS/minimize-verdicts.sh" --repo "$repo" "$PR" "$id" 2>&1 >/dev/null)"; then
    say "verdicts: earlier verdicts on PR #$PR minimized as outdated"; return 0
  fi
  STATUS_NOTES="${STATUS_NOTES}verdicts: earlier ones NOT all minimized — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"$'\n'; say "verdicts: could not minimize every earlier verdict on PR #$PR"
}
# -- the draft hold (rows E22, E23): GitHub refuses to merge a draft, so a lane PR stays one until a review approves its
# head; the scheduler owns both flips. A flip that fails is reported in the run block, never fatal --
DRAFT_NOTES=""
pr_hold_draft() { # after every build: a ready PR is turned back into a draft
  local err
  [ "$PR_DRAFT" = false ] || return 0
  if err="$("$GH" pr ready "$PR" --undo 2>&1 >/dev/null)"; then
    PR_DRAFT=true; say "pr: #$PR turned back into a draft — it is marked ready only when a review approves its head"
  else
    DRAFT_NOTES="${DRAFT_NOTES}pr: NOT turned into a draft — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200); it stayed mergeable before its review"$'\n'; say "pr: could not turn #$PR into a draft"
  fi
}
pr_mark_ready() { # approved at this head: the one flip out of draft
  local err
  if err="$("$GH" pr ready "$PR" 2>&1 >/dev/null)"; then
    DRAFT_NOTES="${DRAFT_NOTES}pr: marked ready for review — approved at $HEAD_SHA"$'\n'; say "pr: #$PR marked ready for review"
  else
    DRAFT_NOTES="${DRAFT_NOTES}pr: still a draft — marking it ready failed ($(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)); mark it ready by hand"$'\n'; say "pr: could not mark #$PR ready for review"
  fi
}
# -- the run block (rows E14-E16, I13, I14): in the PR BODY under the old lane's marker, at every terminal once a PR exists --
cost_block() { # <terminal slug>
  echo '<!-- pipeline-cost-block -->'
  echo "## second-shift run"; echo
  # the reader's line first; the status and draft notes stay outside the fold, since a status NOT posted changes what a merge proves
  local head="${HEAD_SHA:0:7}"
  echo "Outcome: $1 after $ROUND round(s). Verdict: ${VERDICT:-none}. Reviewed head: ${head:-none}. CI: $CI. Cost: \$$(usd "$COST")${UNPRICED:+ + unpriced}."; echo
  [ -z "$STATUS_NOTES" ] || printf '%s' "$STATUS_NOTES" | awk '{print; print ""}'   # one paragraph per bound verdict's status post
  [ -z "$DRAFT_NOTES" ] || printf '%s' "$DRAFT_NOTES" | awk '{print; print ""}'     # one paragraph per draft flip worth reporting
  echo "<details><summary>Run details</summary>"; echo   # GitHub renders markdown inside the fold only after a blank line
  echo "| run | outcome | rounds | verdict | reviewed head | cost | CI |"; echo "| --- | --- | --- | --- | --- | --- | --- |"
  echo "| $RUN_ID | $1 | $ROUND | ${VERDICT:-none} | ${HEAD_SHA:-—} | \$$(usd "$COST")${UNPRICED:+ + unpriced} | $CI |"; echo
  [ -z "$RUN_NOTES" ] || printf '%s' "$RUN_NOTES" | awk '{print; print ""}'
  [ -z "$PLAN_NOTES" ] || printf '%s' "$PLAN_NOTES" | awk '{print; print ""}'       # #1039: the latest coverage check, and the plan's position
  [ -z "$FWC_NOTES" ] || printf '%s' "$FWC_NOTES" | awk '{print; print ""}'         # #1040: the latest fails-without-the-change check, its holds and unchecked notes
  # #964 D-4: one denial count per session, from the denials file the scheduler wrote after it ("?" when its JSON was unread);
  # a review's count misses the denials made inside its Workflow subagents, which its result JSON does not list
  echo "| session | turns | cost | denials |"; echo "| --- | --- | --- | --- |"
  local f n c dn df; for f in "$STATE"/build-*.json "$STATE"/review-*.json; do
    [ -f "$f" ] || continue; n="$(basename "$f" .json)"; c="$(jq -r '.total_cost_usd | numbers' "$f" 2>/dev/null)"
    case "$n" in build-*) df="$STATE/denials-${n#build-}.txt" ;; *) df="$STATE/denials-$n.txt" ;; esac
    dn="?"; [ -f "$df" ] && dn="$(grep -c . "$df")"
    if [ -n "$c" ]; then echo "| $n | $(jq -r '.num_turns // "?"' "$f") | \$$(usd "$c") | $dn |"; else echo "| $n | ? | unpriced (no total_cost_usd) | $dn |"; fi
  done
  echo; echo '</details>'
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
  # first: a body round-tripped through the GitHub API carries CRLF, and `$0 == m` never matches then
  body="$(printf '%s\n' "$body" | tr -d '\r' | awk '$0 == "<!-- pipeline-cost-block -->"{skip=1} !skip{print} skip && ($0 == "<!-- /pipeline-cost-block -->" || /^Cache-hit rate: /){skip=0} END{if (skip) print "<!-- an earlier cost block had no terminator; text below it was not preserved -->"}')"
  printf '%s\n\n%s\n' "$body" "$(cost_block "$1")" > "$STATE/pr-body.md"
  "$GH" api -X PATCH "repos/$repo/pulls/$PR" -F "body=@$STATE/pr-body.md" >/dev/null 2>&1 || say "could not write the run block into PR #$PR's body (it is in $STATE/pr-body.md)"
}

# ============================ 3. preflight, read-only (rows A4, A13, A27, D10, D11, H1, J1, J3, K6-K8) ============================
say "run $RUN_ID: issue $ISSUE, tracker $TRACKER (writes $TRACKER_WRITES), branch $BRANCH, worktree $WT, record $RECORD_REL"
committed_record_exists() { # the branch on origin already carries the record: the receipt on disk is no longer read at all
  # #1024: asked of the remote, never of a local ref — a failed fetch keeps a stale refs/remotes/origin/$BRANCH, and
  # fetch exits 128 for both "unreachable" and "no such branch"; ls-remote --exit-code gives the second its own 2
  local out rc sha found="" wt_ref stale
  out="$(git -C "$MAIN_ROOT" ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) sha="$(printf '%s\n' "$out" | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1; exit }')"
       [ -n "$sha" ] || terminal env-remote-unreadable "origin listed no refs/heads/$BRANCH line — whether the record is already committed is unknown, so neither it nor the receipt is read"
       git -C "$MAIN_ROOT" fetch -q origin "$BRANCH" 2>/dev/null || terminal env-remote-unreadable "cannot fetch origin/$BRANCH — whether the record is already committed is unknown, so neither it nor the receipt is read"
       git -C "$MAIN_ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || terminal env-remote-unreadable "origin/$BRANCH moved past $sha during the fetch — whether the record is already committed is unknown, so neither it nor the receipt is read"
       git -C "$MAIN_ROOT" cat-file -e "$sha:$RECORD_REL" 2>/dev/null ;;
    2) # origin has no such branch: a local branch or worktree for it is unpushed work, refused before the claim, nothing deleted
       git -C "$MAIN_ROOT" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 && found="a local branch $BRANCH"
       if [ -d "$WT" ] && wt_ref="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
         case "$wt_ref" in
           "$BRANCH") found="${found:+$found and }the worktree $WT on it" ;;
           HEAD) found="${found:+$found and }a detached worktree at $WT" ;;
         esac   # on another named branch: phase 5's env-worktree-mismatch
       fi
       [ -z "$found" ] || terminal env-branch-unpushed "origin has no $BRANCH, but there is $found — push it (git push -u origin $BRANCH) to resume it, or remove the worktree and the branch to start fresh from the receipt"
       if stale="$(git -C "$MAIN_ROOT" rev-parse -q --verify "refs/remotes/origin/$BRANCH" 2>/dev/null)"; then
         git -C "$MAIN_ROOT" update-ref -d "refs/remotes/origin/$BRANCH" 2>/dev/null \
           || terminal env-branch-unpushed "origin has no $BRANCH, but its stale tracking ref origin/$BRANCH ($stale) could not be deleted — delete it (git update-ref -d refs/remotes/origin/$BRANCH) and re-launch"
         say "record: origin has no $BRANCH — deleted the stale tracking ref origin/$BRANCH ($stale), so the branch is cut fresh from the base"
       fi
       return 1 ;;
    *) terminal env-remote-unreadable "cannot reach origin to read $BRANCH — whether the record is already committed is unknown, so neither it nor the receipt is read" ;;
  esac
}
if committed_record_exists; then RECORD_SOURCE=committed; say "record: already committed on $BRANCH — the receipt on disk is not consulted"
else RECORD_SOURCE=receipt; [ -f "$RECORD" ] || terminal env-no-record "no intake record at $RECORD — run /intake-toolkit:intake $ISSUE first"; fi
bad_lane="$(lanes_malformed)"; [ -z "$bad_lane" ] || terminal env-config-lanes "commands.$(commands_key): $bad_lane"
# on the receipt, so a fresh run refuses before it claims; the committed record is re-checked in phase 5 and is what counts
if [ "$RECORD_SOURCE" = receipt ] && ! design_declared; then
  terminal env-design-undeclared "design.provider is configured but the record's design section ('## Design frames' or '## Design') neither carries RS rows nor a 'Design: none — <reason>' line — a UI ticket cannot skip the render silently"
fi
# #1022: a receipt from disk is linted before the claim; a committed record was linted when it was a receipt and is not
# re-linted. The lint's rc 1 is the receipt's fault (resumable); anything else, or a lint that knows fewer receipt
# versions than the receipt carries, is a lint this run cannot trust
if [ "$RECORD_SOURCE" = receipt ]; then
  resolve_intake_lint || terminal env-receipt-lint-unavailable "cannot lint the receipt: $LINT_WHY — install or enable intake-toolkit (or set SECOND_SHIFT_INTAKE_TOOLKIT_ROOT), then re-launch"
  receipt_v="$(receipt_version)"
  lint_knows="$(bash "$INTAKE_LINT" --receipt-version 2>/dev/null)"; lint_rc=$?
  if [ "$lint_rc" -ne 0 ] || ! [[ "$lint_knows" =~ ^[0-9]+$ ]]; then
    terminal env-receipt-lint-unavailable "$INTAKE_LINT --receipt-version exited $lint_rc printing '$(printf '%s' "$lint_knows" | tr '\n' ' ' | cut -c1-100)' — an intake-toolkit that predates receipt versions; update it, then re-launch"
  fi
  [ "$lint_knows" -ge "$receipt_v" ] || terminal env-receipt-lint-unavailable "the receipt is v$receipt_v but $INTAKE_LINT knows receipts up to v$lint_knows — it cannot check the sections a v$receipt_v receipt carries; update intake-toolkit, then re-launch"
  lint_err="$(bash "$INTAKE_LINT" --receipt "$RECORD" 2>&1 >/dev/null)"; lint_rc=$?
  case "$lint_rc" in
    0) say "receipt: v$receipt_v, lints clean ($INTAKE_LINT)" ;;
    1) while IFS= read -r l; do say "receipt: $l"; done <<<"$lint_err"
       terminal env-receipt-invalid "the receipt at $RECORD fails ledger-lint.sh --receipt (the violations above) — rerun /intake-toolkit:intake $ISSUE" ;;
    *) terminal env-receipt-lint-unavailable "$INTAKE_LINT --receipt exited $lint_rc, which is no verdict on the receipt: $(printf '%s' "$lint_err" | tr '\n' ' ' | cut -c1-300)" ;;
  esac
fi
# the base, before the claim: a configured baseBranch that does not resolve refuses — never a silent fall back to the default
git -C "$MAIN_ROOT" fetch -q origin 2>/dev/null || true
if [ -n "$BASE_CFG" ]; then
  base="origin/$BASE_CFG"
  git -C "$MAIN_ROOT" rev-parse -q --verify "$base" >/dev/null 2>&1 || terminal env-base-unreadable "baseBranch is '$BASE_CFG' but $base does not resolve — push the branch or fix the key"
else
  base="$(git -C "$MAIN_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  for b in "$base" origin/main origin/master; do [ -n "$b" ] && git -C "$MAIN_ROOT" rev-parse -q --verify "$b" >/dev/null 2>&1 && { base="$b"; break; }; done
fi
BASE_NAME="${base#origin/}"
st="$(issue_state)"; [ -n "$st" ] || terminal env-tracker-unreadable "could not read #$ISSUE from the tracker"
[ "$st" = OPEN ] || terminal env-ticket-closed "#$ISSUE is not open — nothing spawned, a preflight refusal like any other"
if [ -z "$BUILD_MODEL" ] && [ "$HANDOFF" -eq 0 ]; then # an unsized ticket is refused with nothing written to the tracker
  if has_label opus; then BUILD_MODEL=opus; MODEL_BASIS=label
  elif has_label sonnet; then BUILD_MODEL=sonnet; MODEL_BASIS=label
  elif [ "$TRACKER" != github ]; then terminal usage-model "under $TRACKER pass --build-model: there is no sizing label to read"
  else terminal usage-model "#$ISSUE carries neither opus nor sonnet — intake sizes tickets, this scheduler does not (pass --build-model to override)"; fi
fi
bb="${MODEL_BASIS:-flag}"; [ -n "$BUILD_MODEL" ] || bb=handoff
say "models: build ${BUILD_MODEL:-the calling session} ($bb), review $REVIEW_MODEL (${REVIEW_MODEL_BASIS:-default})"

# a handoff build is checked by nobody but the calling session: with no check to hand it, refuse before the claim, as a run would refuse its first round
if [ "$HANDOFF" -eq 1 ] && [ -z "$(checks_list all)" ] && ! allow_unverified; then
  terminal env-no-checks "no check is configured under commands.* and none under '## Checks' — a run would refuse this as not green, so a handoff will not hand it over (declare allowUnverified to accept it)"
fi

# ============================ 4. claim (rows D1-D12, D14-D16, K1-K4, K10) ============================
if [ "$TRACKER" != github ]; then say "claim: $TRACKER tracker — operator-attested, nothing written"
elif has_label "$L_CLAIMED"; then
  # re-entry, as the old lane read it: the claimed label AND a lane-posted marker; a claim with no marker was made by someone else
  if [ "$RESUME" -eq 0 ] && ! lane_marker_present; then terminal claimed-elsewhere "#$ISSUE carries $L_CLAIMED with no lane claim marker; pass --resume to take it over"; fi
  # a ticket handed to /dev-pipeline:build is being built by hand in the worktree: a run re-entering it would spawn a second writer there
  if [ "$RESUME" -eq 0 ] && [ "$HANDOFF" -eq 0 ] && handoff_holds; then terminal claimed-elsewhere "#$ISSUE was handed to an in-session build (/dev-pipeline:build) that may still be writing to $WT; pass --resume to hand it back to the lane"; fi
  say "claim: re-entering a ticket the lane claimed"; CLAIMED=1
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
  "$GH" issue comment "$ISSUE" --body "$(printf '<!-- dev-pipeline -->\n<!-- run_id: %s -->\n<!-- session_id: %s -->\n<!-- stage: lean-claimed -->\n\n🤖 Claimed by \`/dev-pipeline:%s\`.\nsecond-shift-run: %s (branch %s)' "$RUN_ID" "${CLAUDE_CODE_SESSION_ID:-unset}" "$([ "$HANDOFF" -eq 1 ] && echo build || echo run)" "$RUN_ID" "$BRANCH")" >/dev/null 2>&1 \
    || terminal env-claim-failed "labels swapped but the claim marker could not be posted on #$ISSUE — re-entry would refuse; fix the tracker write and --resume"
  CLAIMED=1
fi
mkdir -p "$STATE" || terminal env-state-dir "cannot create $STATE"
# #964 D-10: a --handoff build runs after this process has exited, so no scratch dir is made for it to outlive
if [ "$HANDOFF" -eq 0 ]; then
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/second-shift-$ISSUE-scratch.XXXXXX")" || terminal env-scratch-dir "cannot create a scratch dir under ${TMPDIR:-/tmp}"
  SCRATCH="$(cd "$SCRATCH" && pwd -P)"   # the physical path: a session's --add-dir and the prompt must name the same dir
  say "scratch: $SCRATCH (both sessions; archived to $STATE/scratch.tar at exit)"
fi

# ============================ 5. baseline (rows E3-E6, E17, E18, G7, H6, J6, J11) ============================
if [ -d "$WT" ]; then
  wt_ref="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || terminal env-worktree "$WT exists but is not a git worktree"
  case "$wt_ref" in "$BRANCH"|HEAD) : ;; *) terminal env-worktree-mismatch "$WT is on branch '$wt_ref', not $BRANCH — remove it (git worktree remove) and re-launch" ;; esac
  # #1040 D-7: a run killed during its fails-without-the-change check left $WT on the record commit's tree; it goes back on
  # the branch before anything else, by the same unforced checkout, which refuses rather than discard a change
  if [ -f "$RED_TREE_MARK" ]; then
    red_tree_restore || terminal env-worktree "$WT was left on the record commit's tree by an interrupted fails-without-the-change check ($(cat "$RED_TREE_MARK" 2>/dev/null)), and git checkout $BRANCH refuses there — reconcile it by hand, delete $RED_TREE_MARK, then --resume"
    say "red tree: $WT put back on $BRANCH (an earlier run was interrupted during its fails-without-the-change check)"
  fi
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
# row H14: the rows (read at $FIRST) and smokeCommand are fixed from here, so the note is set once per process, before any
# terminal that reaches a PR; never in the smoke log, which becomes the build's findings on a red
if [ -n "$SMOKE_CMD" ] && [ -n "$(frames_rows)" ]; then
  case "$SMOKE_CMD" in
    *'{textScale}'*) : ;;
    *) RUN_NOTES="${RUN_NOTES}scaled smoke: not configured (smokeCommand takes no {textScale})"$'\n'; say "scaled smoke: not configured (smokeCommand takes no {textScale})" ;;
  esac
fi

# ============================ 6. rounds (rows B7-B9, B14-B16, E13, F1, F14, G1, G9, H12, I6, I12, I15, J8, J10, J12, J13, K12) ============================
red_attempt() { # a red check, smoke or convention spends the checks-red counter, never a round; its log goes to the next build beside the review's findings
  CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "$1 red $CHECKS_RED times (cost \$$(usd "$COST"))"
  RED_LOG="$(findings_excerpt "$2")"; NEED_BUILD=1; say "$1 red — the findings are the log; another BUILD attempt of round $ROUND"
}
denials_cite() { # denials_cite <attempt> -> the build's denials as a detail line cites them; nothing when it was denied none
  # under read_denials a missing file is "unread", never "none" (#967), so the line says which
  local f="$STATE/denials-$1.txt"
  if [ ! -e "$f" ]; then echo "; its permission denials are unread (its result JSON carried none to read)"
  elif [ -s "$f" ]; then echo "; it was denied $(grep -c '' "$f") command(s), listed in $f"; fi
}
unpushed_log() { # unpushed_log <attempt> -> writes $STATE/unpushed-<attempt>.log, what the re-spawned build reads (#973 D-1)
  local f="$STATE/denials-$1.txt" log="$STATE/unpushed-$1.log"
  {
    echo "The BUILD session exited 0 on a clean tree, but these commits are not on origin/$BRANCH:"
    printf '%s\n' "$INFLIGHT_UNPUSHED"
    echo "Push $BRANCH to origin and, unless one is already open for this branch, open the draft PR as the instructions above say. A denied command is not a reason to end your turn."
    echo "Build session permission denials ($f):"
    if [ ! -e "$f" ]; then echo "(unread: the session's result JSON carried none to read, so whether it was denied anything is unknown)"
    elif [ -s "$f" ]; then cat "$f"; else echo "(none)"; fi
  } > "$log"
  printf '%s' "$log"
}
findings_excerpt() { # findings_excerpt <log> -> the path of what the next build reads: each red check's last lines, capped
  # A lane can write megabytes (a web server's request log); the build needs why it went red, not the whole stream.
  # Green checks keep their 'ok:' line only; a red one keeps its last 150 lines, each cut at 400 chars; a log with no
  # ok/RED markers (a smoke or convention log) is kept as its own tail. The whole excerpt is capped at 200 KB.
  local log="$1" out="$1.findings" cap=200000
  awk -v max=150 -v w=400 -v full="$log" '
    function flush(red,   i, s) {
      if (red) { s = (n > max) ? n - max : 0; if (s) print "[... " s " earlier lines of this check cut; the full log is " full " ...]"
                 for (i = s + 1; i <= n; i++) print substr(buf[i % max], 1, w) }
      n = 0 }
    /^(RED|ok)( \([^)]*\))?: / { flush($0 ~ /^RED/); print; next }
    { buf[++n % max] = $0 }
    END { flush(1) }' "$log" > "$out.tmp"
  if [ "$(wc -c < "$out.tmp")" -gt "$cap" ]; then
    { head -c "$cap" "$out.tmp"; printf '\n[... findings cut at %s bytes; the full log is %s ...]\n' "$cap" "$log"; } > "$out"; rm -f "$out.tmp"
  else mv "$out.tmp" "$out"; fi
  printf '%s' "$out"
}
new_uuid() { # an RFC 4122 v4 uuid, lowercase as transcript file names are (macOS uuidgen prints upper case, D-31)
  local h; h="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ "${#h}" -eq 32 ] || return 1
  printf '%s-%s-4%s-%x%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" $(( (16#${h:16:1} & 3) | 8 )) "${h:17:3}" "${h:20:12}"
}
# -- the watch call (#939 D-9 D-10 D-26 D-27): once per launch, once the worktree is first ready; whatever it does, one
# `watch:` line and nothing else. It runs from the main checkout in its own process group under its own watchdog —
# bounded() would cd into the worktree and reap only one level down — with its output in its own file: never the detach
# log, never a command substitution, which a forked descendant holding the pipe would stall. Nothing it says is read back.
WATCH_TO=10   # OR-1: one constant; a watch that misbehaves changes no outcome at any value
WATCHED=0
watch_once() {
  [ "$WATCHED" -eq 0 ] || return 0; WATCHED=1
  [ -n "${RUN_WATCH_CMD:-}" ] || { say "watch: off (RUN_WATCH_CMD is unset)"; return 0; }
  [ -n "${RUN_DETACHED_LOG:-}" ] || { say "watch: skipped for a foreground run (only a --detach run is watched)"; return 0; }
  command -v -- "$RUN_WATCH_CMD" >/dev/null 2>&1 || { say "watch: FAILED — '$RUN_WATCH_CMD' is not an executable; the run goes on unwatched"; return 0; }
  local out="$STATE/watch.out" t=0 rc
  # the pane, tab and workspace the operator launched from are not the watch's: the adapter names its own by id (AC-21)
  ( cd "$MAIN_ROOT" && exec env -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' -- \
      "$RUN_WATCH_CMD" "$ISSUE" "$REPO_SLUG" "$RUN_DETACHED_LOG" "$WT" ) > "$out" 2>&1 < /dev/null & CHILD=$!; CHILD_GROUP=1
  while kill -0 "$CHILD" 2>/dev/null && [ "$t" -lt $((WATCH_TO*5)) ]; do sleep 0.2; t=$((t+1)); done
  if kill -0 "$CHILD" 2>/dev/null; then # past the bound: the whole group, TERM then KILL; wait would say 143, so the timeout is recorded here
    kill -TERM -- "-$CHILD" 2>/dev/null; kill -TERM "$CHILD" 2>/dev/null
    t=0; while kill -0 -- "-$CHILD" 2>/dev/null && [ "$t" -lt 10 ]; do sleep 0.2; t=$((t+1)); done
    kill -KILL -- "-$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null; CHILD=""; CHILD_GROUP=0
    say "watch: FAILED — $RUN_WATCH_CMD ran past its ${WATCH_TO}s bound and its process group was killed (output: $out); the run goes on unwatched"
    return 0
  fi
  wait "$CHILD"; rc=$?; CHILD=""; CHILD_GROUP=0
  if [ "$rc" -eq 0 ]; then say "watch: $RUN_WATCH_CMD started the watch (output: $out)"
  else say "watch: FAILED — $RUN_WATCH_CMD exited rc=$rc (output: $out); the run goes on unwatched"; fi
}
spawn() { # spawn <role> <model> <id> <allowlist> <max-turns> <prompt-file> -> rc (124 past the bound); the result JSON is $STATE/<role>-<id>.json
  local secs="$REVIEW_TO" extra=(); [ "$1" = build ] && secs="$BUILD_TO"
  # #964 D-1 D-3: both sessions get the run's scratch dir (the review stages review-lead's Workflow script there);
  # neither gets $STATE, which the scheduler alone writes
  [ -n "$SCRATCH" ] && extra=(--add-dir "$SCRATCH")
  # F-env: under -p a turn that ends waiting on a background task ends the process, and a background shell dies with it.
  # BUILD runs every command in the foreground, inside its bound. REVIEW keeps background tasks (review-lead's panel is a
  # Workflow), and -p waits on a running one only 600 s idle by default: its wait is raised to inside its own bound.
  # Passed as --settings env, which sits above the user, project and local files, so a repo's own settings.json env
  # cannot quietly put a BUILD back on the 120 s default; REVIEW drops a switch it would only inherit from this shell
  local sets envv=(env ${WATCH_UNSET[@]+"${WATCH_UNSET[@]}"})
  # #1048 D-6 D-8 D-18: the BUILD alone gets the PermissionRequest hook, which fires only on a call its allowlist denies
  # and answers it with a reason; here, never in the plugin's hooks.json, which every session with the plugin loads.
  # #1080: it is given the record and the plan, the two files the build must write even when plansDir is under .claude/
  if [ "$1" = build ]; then
    sets="$(jq -cn --arg ms "$BUILD_BASH_MS" --arg hook "bash $(shquote "$TOOLS/lane-permission-hook.sh") $(shquote "$WT") $(shquote "$SCRATCH") $(shquote "$WT/$RECORD_REL") $(shquote "$WT/$PLAN_REL")" \
      '{env:{CLAUDE_CODE_DISABLE_BACKGROUND_TASKS:"1",BASH_DEFAULT_TIMEOUT_MS:$ms,BASH_MAX_TIMEOUT_MS:$ms},hooks:{PermissionRequest:[{hooks:[{type:"command",command:$hook}]}]}}')" \
      || terminal env-session-settings "cannot write the build session's --settings JSON"
  else sets="$(printf '{"env":{"CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS":"%s"}}' "$REVIEW_BG_WAIT_MS")"; envv+=(-u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS); fi
  # the session reads a copy of the config, written afresh from the launch-time read before every spawn: the sessions
  # share the scratch dir, so a build's edit to its copy must not reach the review that follows it. After every -u:
  # env reads its first assignment as the end of its options
  if [ -n "$CONFIG" ] && [ -n "$SCRATCH" ]; then
    printf '%s\n' "$CONFIG_JSON" > "$SCRATCH/second-shift.config.json" || terminal env-scratch-dir "cannot write the session's copy of the config into $SCRATCH"
    envv+=(SECOND_SHIFT_CONFIG="$SCRATCH/second-shift.config.json")
  fi
  # #939 D-13: every session is named and findable while it runs (`claude agents`), and its transcript is on disk under its id
  local sid name; sid="$(new_uuid)" || terminal env-session-id "cannot read /dev/urandom for a session id"
  name="$ISSUE-$1-$(printf '%s' "$3" | tr -c 'A-Za-z0-9-' '-')"
  say "session: $1 $3 $sid ~/.claude*/projects/*/$sid.jsonl"
  # the prompt goes in on stdin, never as an argument: a red check's log can carry it past the exec limit
  # (1 MiB on macOS, 128 KiB for one argument on Linux), and the session then dies as rc 126 before it starts
  local BOUNDED_STDIN="$6"
  bounded "$secs" "$STATE/$1-$3.json" "${envv[@]}" "$CLAUDE" -p --session-id "$sid" -n "$name" --model "$2" "${SPAWN_COMMON[@]}" ${extra[@]+"${extra[@]}"} --settings "$sets" --allowedTools "$4" --max-turns "$5"; local rc=$?
  add_cost "$STATE/$1-$3.json"; return $rc
}
FINDINGS=""; RED_LOG=""; NEED_BUILD=1; NEED_CHECKS=1; INPUT=""
while :; do
  ROUND=$((ROUND+1)); [ "$ROUND" -le "$MAX_ROUNDS" ] || terminal rounds-spent "$MAX_ROUNDS rounds without an approve (cost \$$(usd "$COST"))"
  say "round $ROUND of $MAX_ROUNDS (cost so far \$$(usd "$COST"))"
  review_tries=0; VERDICT=""; REJECTED=""
  while :; do
    if [ "$NEED_BUILD" -eq 1 ]; then # ---- BUILD, until its work is collected on one draft PR ----
      premise_holds
      worktree_ready
      watch_once   # guarded: a later attempt or round makes the worktree ready again, and the launch is watched once
      ATTEMPT=$((ATTEMPT+1)); A="$ROUND.$ATTEMPT"
      record_at_first >/dev/null || terminal env-worktree "cannot read the record at $FIRST:$RECORD_REL — a build must not be handed an empty record as binding"
      build_prompt "$ROUND" "$FINDINGS" "$RED_LOG" > "$STATE/build-$A.prompt"
      if [ "$HANDOFF" -eq 1 ]; then # the calling session builds; nothing after this is the scheduler's
        echo "worktree: $WT"; echo "baseline: $FIRST"; echo "prompt: $STATE/build-$A.prompt"
        UNPRICED="build-in-calling-session"
        terminal build-handoff "BUILD handed to the calling session in $WT; review with /dev-pipeline:review <pr> in a fresh session"
      fi
      spawn build "$BUILD_MODEL" "$A" "$(build_allowlist)" 400 "$STATE/build-$A.prompt"; brc=$?
      read_denials "$STATE/build-$A.json" "$STATE/denials-$A.txt"
      [ "$brc" -eq 124 ] && terminal build-blocked "build session exceeded ${BUILD_TO}s; worktree and claim left in place"
      sub="$(jq -r '.subtype // "unreadable"' "$STATE/build-$A.json" 2>/dev/null)"
      [ "$sub" = success ] || terminal build-blocked "build session ended $sub (rc=$brc); worktree and claim left in place"
      over_ceiling && terminal cost-spent "\$$(usd_up "$COST") exceeds the \$$COST_CEIL ceiling"
      worktree_inflight "$A"; ifrc=$?
      case "$ifrc" in
        0) : ;;
        8) if [ -n "$INFLIGHT_UNPUSHED" ]; then # committed but not pushed (#973 D-1): a new build pushes it, on the checks-red counter
             say "build: exited 0 with $(grep -c '' <<<"$INFLIGHT_UNPUSHED") commit(s) not on origin/$BRANCH on a clean tree — another BUILD pushes them and opens the draft PR"
             red_attempt push "$(unpushed_log "$A")"; continue
           fi
           terminal build-inflight "the BUILD session exited 0 but $WT still holds work nothing else has a copy of ($INFLIGHT_REASON$(denials_cite "$A")) — push from the worktree and --resume; nothing here discards it" ;;
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
      pr_hold_draft
      [ "$crc" -eq 0 ] || { red_attempt "PR conventions" "$STATE/pr-conventions-$A.txt"; continue; }
    fi
    # ---- every configured check, at the pushed head: the authority, whatever the build ran itself; re-run only when the head moved (ids: the build attempt, suffixed on a re-spawn) ----
    RA="$A"; [ "$review_tries" -eq 0 ] || RA="$A-retry$review_tries"
    if [ "$NEED_CHECKS" -eq 1 ]; then
      sync_to_remote
      CHANGED="$(git -C "$WT" -c core.quotePath=false diff --name-only "$FIRST" HEAD 2>/dev/null)" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT — a diff that cannot be read must not skip every when-scoped lane"
      run_checks "$RA" || { red_attempt checks "$STATE/checks-$RA.log"; continue; }
      plan_coverage "$RA"; pcrc=$?   # #1039: after the checks, before the smoke; not-applicable goes on
      case "$pcrc" in
        0|3) : ;;
        1) red_attempt "plan coverage" "$STATE/plan-coverage-$RA.log"; continue ;;
        *) terminal plan-coverage-uncheckable "tools/plan-coverage.sh exited $pcrc on the record at $FIRST and $PLAN_REL at $HEAD_SHA ($(tr '\n' ' ' < "$STATE/plan-coverage-$RA.log" 2>/dev/null | cut -c1-300)) — a check that cannot run is not one that passed, and no build can change the record at its first commit" ;;
      esac
      if [ "$pcrc" -eq 0 ]; then # #1040: after the coverage, before the smoke; a red spends the checks-red counter (D-5)
        fails_without_change "$RA"; fwrc=$?
        [ "$fwrc" -ne 1 ] || { red_attempt "fails without the change" "$STATE/fails-without-$RA.log"; continue; }
      else # the record carries no Test intent, or the ticket no AC block: the coverage's own not-applicable reason
        why="${PLAN_NOTES%$'\n'}"; FWC_NOTES="fails without the change: not-applicable — ${why#plan coverage: not-applicable — }"$'\n'; say "${FWC_NOTES%$'\n'}"
      fi
      route_smoke "$RA"; src=$?
      [ "$src" -ne 2 ] || terminal env-smoke-unconfigured "the record declares design frames but design.liveRender.command/smokeCommand is not configured"
      [ "$src" -ne 3 ] || terminal env-not-ready "readyProbe $READY_URL is not ready after 3 tries (last reading: $READY_READING) — start the service and --resume"
      [ "$src" -ne 4 ] || terminal env-hash-tool "cannot hash a render: neither shasum nor sha256sum is on PATH"
      [ "$src" -eq 0 ] || { red_attempt smoke "$STATE/smoke-$RA.log"; continue; }
      review_input "$RA" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT"
      INPUT="$STATE/review-input-$RA.md"; NEED_CHECKS=0
    fi
    # ---- REVIEW: a fresh session bound to this head and its window; re-spawned once when it leaves no binding verdict ----
    # the head can move while the checks run (a push, or GitHub's 'Update branch' merge). A review spawned now would read and
    # name the new head, which no verdict for this one can match: the checks run again on the new head first
    miss=""; after="$(remote_head)" || terminal env-remote-unreadable "cannot read origin/$BRANCH before the review; --resume"
    [ "$after" = "$HEAD_SHA" ] || { miss="the head moved during the checks ($HEAD_SHA -> $after). The checks run again on the new head before a review"; NEED_CHECKS=1; }
    if [ -z "$miss" ]; then
      # the record at FIRST, where the review's own draft check reads it (the head's is in the worktree it reviews)
      [ -z "$SCRATCH" ] || record_at_first > "$SCRATCH/record-at-first.md" || terminal env-worktree "cannot read the record at $FIRST:$RECORD_REL for the review"
      review_prompt "$PR" "$INPUT" "$REJECTED" > "$STATE/review-$RA.prompt"
      start="$(now)"
      spawn review "$REVIEW_MODEL" "$RA" "$(review_allowlist)" 300 "$STATE/review-$RA.prompt"; rrc=$?
      end="$(now)"
      # #964 D-4: the review's denials, read as the build's are. Known gap: a denial inside the review's Workflow
      # subagents is not in this result JSON, so it is not counted here
      read_denials "$STATE/review-$RA.json" "$STATE/denials-review-$RA.txt"
      rsub="$(jq -r '.subtype // "unreadable"' "$STATE/review-$RA.json" 2>/dev/null)"
      if [ "$rrc" -eq 124 ]; then miss="the review session exceeded ${REVIEW_TO}s"
      elif [ "$rsub" != success ]; then miss="the review session ended $rsub (rc=$rrc)"
      else
        VERDICT="$(verdict "$start" "$end")"; vrc=$?
        [ "$vrc" -ne 2 ] || terminal env-tracker-unreadable "the PR's comments could not be read after the review — an environment refusal, not a verdict; --resume"
        # a review reads the head as it is when it starts, so one that names a head the checks never ran on is a moved head, not a
        # dark review: re-spawned as it is, it would name that head again
        after="$(remote_head)" || terminal env-remote-unreadable "cannot read origin/$BRANCH after the review — a verdict is not discarded for a network blip; --resume"
        if [ "$after" != "$HEAD_SHA" ]; then miss="the head moved during the review ($HEAD_SHA -> $after). The checks run again on the new head"; NEED_CHECKS=1
        elif [ "$vrc" -ne 0 ]; then miss="no unedited 'verdict:' comment naming head $HEAD_SHA was posted between $start and $end"; fi
        if [ -z "$miss" ]; then # #991: the bound verdict binds only when its own comment backs it; checked before any status
          vurl="$(cut -f3 "$STATE/verdict.tsv" 2>/dev/null)"
          verdict_check "$RA"; vcrc=$?
          if [ "$vcrc" -eq 1 ]; then
            miss="the verdict at ${vurl:-(no URL)} breaks the verdict grammar: $(paste -sd ';' "$STATE/verdict-check-$RA.txt" | sed 's/;/; /g' | cut -c1-600)"
            VERDICT=""; REJECTED="$STATE/verdict-check-$RA.txt"; verdict_notice "$RA" "$vurl"
          elif [ "$vcrc" -ne 0 ]; then
            VERDICT=""
            terminal verdict-uncheckable "the verdict at ${vurl:-(no URL)} could not be checked against the record ($(tr '\n' ' ' < "$STATE/verdict-check-$RA.txt" | cut -c1-300)) — a check that cannot run is not one that passed; no status posted"
          fi
        fi
      fi
    fi
    [ -n "$miss" ] || break
    review_tries=$((review_tries+1))
    [ "$review_tries" -le "$MAX_REVIEW_RETRIES" ] || terminal review-unbound "$miss. This happened twice. No round was spent and no build was spawned. Run /dev-pipeline:review $PR by hand"
    say "$miss — re-spawning REVIEW ($review_tries of $MAX_REVIEW_RETRIES). No round spent, no BUILD spawn."
    over_ceiling && terminal cost-spent "\$$(usd_up "$COST") exceeds the \$$COST_CEIL ceiling"
  done
  say "verdict: $VERDICT (reviewed $HEAD_SHA)"
  review_status
  minimize_earlier_verdicts
  [ "$VERDICT" = approve ] && break
  # row H13: a review that could not render is the environment's failure, not the build's — no round is spent. The
  # grammar puts the reason on line 3 (#991); the same words in the body's ## Notes are prose, not the reason
  awk '{ sub(/\r$/, "") } NR == 3 && $0 == "reason: render-unavailable" { f = 1 } END { exit !f }' "$STATE/verdict-body.md" \
    && terminal env-not-ready "the review could not render the design frames at $HEAD_SHA (reason: render-unavailable) — fix the render environment and re-launch"
  FINDINGS="$STATE/verdict-body.md"; RED_LOG=""; NEED_BUILD=1
  over_ceiling && terminal cost-spent "\$$(usd_up "$COST") exceeds the \$$COST_CEIL ceiling"
done

# ============================ 7. close-out (rows E19, E20) ============================
worktree_inflight closeout; ifrc=$?
case "$ifrc" in
  0) runtime_data_held; rdrc=$?
     if [ "$rdrc" -ne 0 ]; then say "worktree $WT left in place: $RUNTIME_REASON; move what must survive, then remove it by hand"
     else git -C "$MAIN_ROOT" worktree remove "$WT" >/dev/null 2>&1 && say "worktree $WT removed; the branch and PR #$PR stay" || say "worktree $WT left in place (a lock, or a removal that failed); remove it by hand"; fi ;;
  8) terminal closeout-inflight "approved, but $WT still holds work nothing else has a copy of ($INFLIGHT_REASON) — the ticket is still claimed and PR #$PR is still open" ;;
  *) terminal closeout-inflight-unreadable "approved, but whether $WT still holds work could not be evaluated ($INFLIGHT_REASON)" ;;
esac
pr_mark_ready
terminal approved "PR #$PR approved at $HEAD_SHA after $ROUND round(s), \$$(usd "$COST")"
