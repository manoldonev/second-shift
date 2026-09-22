#!/usr/bin/env bash
# run.sh — the shrunk scheduler: one ticket in, an approved PR out, unattended.
#
# Spawns a BUILD session and a REVIEW session in fresh `claude -p` processes and reads three
# things it did not author: the repo's own checks (run here — the consumer's configured
# `commands` plus the record's `## Checks`, both read from sources the build cannot edit), the
# PR head (must move every round), and a verdict comment bound to that head and to the review
# session's time window. Nothing here tells the model how to work; the record does.
#
# Every consumer-visible behavior of orchestrate.sh is kept unless #881's ledger records the
# change: the branch namespace resolver, the queue/claimed/blocker labels and the atomic swap,
# the claim marker, the PR conventions (ready PR, `Closes`, the cost block under its marker),
# the bot identity for the lane's own writes, the `tracker.writes: false` tool strip, the
# model-from-label rule, the flags a launch script passes, and the exit-code taxonomy.
#
# usage: run.sh <issue> [--build-model|--model <id>] [--model-basis <text>]
#               [--review-model <id>] [--review-model-basis <text>]
#               [--record <path>] [--max-rounds N] [--dry-run] [--resume] [--detach]
#   The build model comes from the ticket's `opus` / `sonnet` label; --build-model overrides.
#   Review defaults to opus; a departure needs --review-model-basis, as before.
#
# env:  SECOND_SHIFT_CONFIG   config path (default <main>/.claude/second-shift.config.json)
#       RUN_CLAUDE, RUN_GH (alias GH)   the binaries (tests inject fakes)
#       RUN_WORKTREE_ROOT     default <parent of main>/<repo>-worktrees
#       RUN_BUILD_TIMEOUT / RUN_REVIEW_TIMEOUT   seconds (7200 / 3600)
#       RUN_COST_CEILING      USD (100); RUN_CHECKS_RED_MAX (3)
#
# exit: 0 approved · 1 stopped (build-no-pr, build-inflight, build-blocked, pr-ambiguous,
#       claimed-elsewhere, staleness-unreadable) · 2 usage or environment refusal (usage-*, every
#       env-* slug) · 3 RESUMABLE: not queued / no intake record — pay off intake and re-launch the
#       same command · 4 budget spent (rounds, checks-red, cost) · 5 no verdict usable against the
#       current head · 7 the premise expired mid-run (ticket closed, base moved into this branch's
#       files). Model ids accept the short forms `opus` / `sonnet`.
set -uo pipefail

CLAUDE="${RUN_CLAUDE:-claude}"; GH="${RUN_GH:-${GH:-gh}}"
ISSUE=""; RECORD=""; MAX_ROUNDS=3; MODEL="${RUN_MODEL:-}"; MODEL_BASIS=""
REVIEW_MODEL="${RUN_REVIEW_MODEL:-claude-opus-5}"; REVIEW_MODEL_BASIS=""; DRY=0; RESUME=0; DETACH=0
KEEP_ARGS=(); MAX_ROUNDS_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --record) RECORD="$2"; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --max-rounds) MAX_ROUNDS="$2"; MAX_ROUNDS_SET=1; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --model|--build-model) MODEL="$2"; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --model-basis) MODEL_BASIS="$2"; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --review-model) REVIEW_MODEL="$2"; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --review-model-basis) REVIEW_MODEL_BASIS="$2"; KEEP_ARGS+=("$1" "$2"); shift 2 ;;
    --dry-run) DRY=1; KEEP_ARGS+=("$1"); shift ;;
    --resume) RESUME=1; KEEP_ARGS+=("$1"); shift ;;
    --detach) DETACH=1; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    -*) echo "run.sh: unknown flag $1" >&2; echo "terminal: usage-unknown-option"; exit 2 ;;
    *) ISSUE="$1"; KEEP_ARGS+=("$1"); shift ;;
  esac
done
[ -n "$ISSUE" ] || { sed -n '16,20p' "$0" >&2; echo "terminal: usage-missing-issue"; exit 2; }
alias_model() { case "$1" in opus) echo claude-opus-5 ;; sonnet) echo claude-sonnet-5 ;; *) echo "$1" ;; esac; }
MODEL="$(alias_model "$MODEL")"; REVIEW_MODEL="$(alias_model "$REVIEW_MODEL")"
case "$MAX_ROUNDS" in ''|*[!0-9]*|0) echo "run.sh: --max-rounds must be a positive integer" >&2; echo "terminal: usage-max-rounds"; exit 2 ;; esac
if [ "$REVIEW_MODEL" != claude-opus-5 ] && [ -z "$REVIEW_MODEL_BASIS" ]; then
  echo "run.sh: --review-model departs from the default (claude-opus-5); state why with --review-model-basis" >&2; echo "terminal: usage-review-model-basis"; exit 2
fi

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { echo "$(now) [run] $*"; }
exit_code_for() { # the taxonomy a wrapper may branch on (orchestrate.sh's, kept)
  case "$1" in
    approved|dry-run) echo 0 ;;
    not-queued|env-no-record) echo 3 ;;
    usage-*|env-*) echo 2 ;;
    rounds-spent|checks-red-spent|cost-spent) echo 4 ;;
    review-unbound) echo 5 ;;
    ticket-closed|staleness-expired) echo 7 ;;
    staleness-unreadable) echo 1 ;;
    *) echo 1 ;;
  esac
}
terminal() { # terminal <slug> <detail> — one closing comment on the issue, as the old lane posted
  say "terminal: $1 — $2"; echo "terminal: $1"
  if [ "${CLAIMED:-0}" -eq 1 ] && [ "$TRACKER" = github ]; then
    "$GH" issue comment "$ISSUE" --body "$(printf 'second-shift run %s: %s — %s\n%s\ncost_usd: %s\n' "$RUN_ID" "$1" "$2" "${PR_URL:-${PR:+PR #$PR}}" "${COST:-0}")" >/dev/null 2>&1 || true
  fi
  exit "$(exit_code_for "$1")"
}

# ---- repo, config (fail closed on a present-but-unparseable file, like orchestrate.sh) ----
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || terminal env-no-git-repo "not in a git repo"
_common="$(git rev-parse --git-common-dir)"; case "$_common" in /*) : ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT="$(cd "$_common/.." && pwd)"
CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"
if [ -f "$CONFIG" ]; then
  jq -e . "$CONFIG" >/dev/null 2>&1 || terminal env-config-unparseable "$CONFIG is not JSON"
else
  CONFIG=""
fi
cfg() { [ -n "$CONFIG" ] && jq -r "$1 // empty" "$CONFIG" 2>/dev/null || true; }
# The sessions run in the worktree, whose gitignored .claude/ has no config; hand them the main
# checkout's resolved path so review-lead and the tracker adapter read the same file this does.
[ -n "$CONFIG" ] && export SECOND_SHIFT_CONFIG="$CONFIG"
TRACKER="$(cfg .tracker.type)"; TRACKER="${TRACKER:-github}"
case "$TRACKER" in github|jira) : ;; *) terminal env-tracker-type "tracker.type '$TRACKER' is not github or jira — a typo must not silently pick the arm that attests less" ;; esac
# read as a tostring: `cfg`'s `// empty` would swallow a literal false (the value that matters here)
TRACKER_WRITES="$( [ -n "$CONFIG" ] && jq -r 'if .tracker.writes == null then "" else (.tracker.writes|tostring) end' "$CONFIG" 2>/dev/null || true )"
if [ "$TRACKER" != github ]; then TRACKER_WRITES="${TRACKER_WRITES:-false}"; else TRACKER_WRITES="${TRACKER_WRITES:-true}"; fi
KEY_PATTERN="$(cfg .tracker.keyPattern)"
PLANS_DIR="$(cfg .paths.plansDir)"; PLANS_DIR="${PLANS_DIR:-docs/plans}"
STATE_DIR="$(cfg .paths.pipelineStateDir)"; STATE_DIR="${STATE_DIR:-.claude/pipeline-state}"
RENDER_CMD="$(cfg .design.liveRender.command)"
SMOKE_CMD="$(cfg .design.liveRender.smokeCommand)"
READY_URL="$(cfg .design.liveRender.readyProbe)"
L_QUEUE="$(cfg .tracker.labels.queue)"; L_QUEUE="${L_QUEUE:-ready-for-dev}"
L_CLAIMED="$(cfg .tracker.labels.claimed)"; L_CLAIMED="${L_CLAIMED:-in-progress}"
L_BLOCKERS="$(cfg '.tracker.labels.blockers | join(" ")')"; L_BLOCKERS="${L_BLOCKERS:-epic needs-intake-review needs-spec-work needs-plan-review}"
REPO_SLUG="$(basename "$MAIN_ROOT")"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$(cd "$SKILL_DIR/../../tools" && pwd)"
if [ -n "$KEY_PATTERN" ] && ! printf '%s' "$ISSUE" | grep -qiE "^($KEY_PATTERN)$"; then terminal usage-key "'$ISSUE' does not match tracker.keyPattern '$KEY_PATTERN'"; fi
# The lane's own tracker writes go through the bot when the consumer configured one, as before
# (tools/gh-bot.sh is the one resolution ladder); a disabled or unresolvable bot means plain gh.
# Reads stay on the operator's gh (GH_READ); only the lane's writes go through the bot, as before.
BOT_OK=0; GH_READ="$GH"
if [ -z "${RUN_GH:-}" ]; then
  bot_status="$(bash "$TOOLS/gh-bot.sh" --status 2>/dev/null)"
  bot_enabled="$( [ -n "$CONFIG" ] && jq -r '.tracker.bot.enabled // false | tostring' "$CONFIG" 2>/dev/null || echo false )"
  if [ "$bot_status" = ok ]; then GH="$(bash "$TOOLS/gh-bot.sh" --path)"; BOT_OK=1
  elif [ "$bot_enabled" = true ]; then terminal env-bot "tracker.bot.enabled is true but the wrapper is $bot_status — refusing to write as the operator in the bot's place"; fi
fi
# The work-branch namespace: configured, else the dominant prefix among remote branches, else
# REFUSE — a guessed namespace is the silent defect branch-prefix.sh exists to remove.
BP_RESOLVER="$SKILL_DIR/../build/branch-prefix.sh"; [ -f "$BP_RESOLVER" ] || BP_RESOLVER="$TOOLS/branch-prefix.sh"
PREFIX="$(cfg .tracker.branchPrefix)"
if [ -z "$PREFIX" ]; then
  PREFIX="$(bash "$BP_RESOLVER" --configured "" --tracker "$TRACKER" ${KEY_PATTERN:+--key-pattern "$KEY_PATTERN"} --repo "$MAIN_ROOT" 2>"$MAIN_ROOT/.git/run-bp.err")" \
    || terminal env-branch-prefix "tracker.branchPrefix is unset and no dominant prefix exists among remote branches: $(tr '\n' ' ' < "$MAIN_ROOT/.git/run-bp.err" | cut -c1-300)"
fi
BRANCH="${PREFIX}$(printf '%s' "$ISSUE" | tr '[:upper:]' '[:lower:]')"
WT_ROOT="${RUN_WORKTREE_ROOT:-$(dirname "$MAIN_ROOT")/${REPO_SLUG}-worktrees}"
WT="$WT_ROOT/$ISSUE"
RECORD_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-decisions.md"
[ -n "$RECORD" ] || RECORD="$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md"
# per-ticket caps: env, else config `run.*`, else the defaults the ledger states (D-6)
c_rounds="$(cfg .run.maxRounds)"; c_red="$(cfg .run.checksRedMax)"; c_bto="$(cfg .run.buildTimeoutSeconds)"; c_rto="$(cfg .run.reviewTimeoutSeconds)"; c_ceil="$(cfg .run.costCeilingUsd)"
[ "$MAX_ROUNDS_SET" -eq 0 ] && [ -n "$c_rounds" ] && MAX_ROUNDS="$c_rounds"
BUILD_TO="${RUN_BUILD_TIMEOUT:-${c_bto:-7200}}"; REVIEW_TO="${RUN_REVIEW_TIMEOUT:-${c_rto:-3600}}"
COST_CEIL="${RUN_COST_CEILING:-${c_ceil:-100}}"; CHECKS_RED_MAX="${RUN_CHECKS_RED_MAX:-${c_red:-3}}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STATE="$MAIN_ROOT/$STATE_DIR/run-$ISSUE/$RUN_ID"; mkdir -p "$STATE"
COST=0; CHECKS_RED=0; CHILD=""; CLAIMED=0; PR=""; PR_URL=""; ATTEMPT=0

# --detach: the documented launch shape for a caller whose commands are time-capped (kept).
if [ "$DETACH" -eq 1 ]; then
  command -v perl >/dev/null 2>&1 || terminal env-detach-perl "--detach needs perl for setsid; run in the foreground instead"
  DETACH_LOG="$MAIN_ROOT/$STATE_DIR/$ISSUE-run-$(now | tr -d ':-')-$$.log"
  _wrap=(); command -v caffeinate >/dev/null 2>&1 && _wrap=(caffeinate -dims)
  # shellcheck disable=SC2016  # the inner script expands in the child, not here
  nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' -- \
    ${_wrap[@]+"${_wrap[@]}"} bash -c 'bash "$@"; rc=$?; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [run] detached run exited rc=$rc"' \
    _ "$0" "${KEEP_ARGS[@]}" > "$DETACH_LOG" 2>&1 < /dev/null &
  say "detached: pid $! · log $DETACH_LOG · its last line will be 'detached run exited rc=<n>'"
  exit 0
fi

trap '[ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null; say "interrupted; claim left in place"; exit 130' INT TERM

# bounded <secs> <logfile> <cmd...> — no `timeout` binary on macOS; a bash watchdog instead
bounded() {
  local secs="$1" log="$2"; shift 2
  "$@" > "$log" 2>"$log.err" < /dev/null & CHILD=$!
  local t=0
  while kill -0 "$CHILD" 2>/dev/null; do
    [ "$t" -ge "$secs" ] && { kill "$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null; CHILD=""; return 124; }
    sleep 1; t=$((t+1))
  done
  wait "$CHILD"; local rc=$?; CHILD=""; return $rc
}

# What must not reach a lane child (milestone 3's SEAM_SCRUB, kept in lockstep with the gate's list)
# LOCKSTEP-BEGIN seam-scrub subset
SEAM_SCRUB='SECOND_SHIFT_CONFIG|SECOND_SHIFT_REPO_ROOT|SECOND_SHIFT_EXTENSION_MANIFEST|SECOND_SHIFT_PLUGIN_ROOT|SECOND_SHIFT_REVIEW_TOOLKIT_ROOT|SECOND_SHIFT_DEV_PIPELINE_ROOT|SECOND_SHIFT_DESIGN_TOOLKIT_ROOT|SECOND_SHIFT_SECTION_CATALOG|STATECTL_STATE_DIR|STATECTL_WRITER|DEV_PIPELINE_MODE|BRANCH_PREFIX|KEY_PATTERN|LANE_ATTEND_MODE|MUTATION_SWEEP_NO_DEFER'
# LOCKSTEP-END seam-scrub
SCRUB_ENV=(); IFS='|' read -r -a _toks <<< "$SEAM_SCRUB"; for _t in "${_toks[@]}"; do SCRUB_ENV+=(-u "$_t"); done; unset _toks _t
lane() { ( cd "$WT" && env "${SCRUB_ENV[@]}" bash -c "$1" ); } # a lane command, scrubbed, in the worktree

# The tools no spawned session may use: the three that would wait on a keyboard, and under
# `tracker.writes: false` every Atlassian write tool in every namespace it is served under (#874).
DISALLOWED="AskUserQuestion,EnterWorktree,ExitWorktree"
if [ "$TRACKER_WRITES" = false ]; then
  for _tool in addCommentToJiraIssue addWorklogToJiraIssue createIssueLink createJiraIssue editJiraIssue transitionJiraIssue createConfluencePage updateConfluencePage createConfluenceFooterComment createConfluenceInlineComment createCompassComponent createCompassComponentRelationship createCompassCustomFieldDefinition addTeamworkGraphContext; do
    for _ns in mcp__atlassian__ mcp__plugin_atlassian_atlassian__ mcp__claude_ai_Atlassian_Rovo__; do DISALLOWED="$DISALLOWED,$_ns$_tool"; done
  done
fi
# shellcheck disable=SC2054  # the comma-separated values are single arguments the CLI parses
MCP_ALLOW=""
[ "$TRACKER" = jira ] && MCP_ALLOW=",mcp__atlassian,mcp__plugin_atlassian_atlassian,mcp__claude_ai_Atlassian_Rovo"
SPAWN_COMMON=(--permission-mode acceptEdits --permission-prompts none --disallowedTools "$DISALLOWED" --setting-sources "user,project,local" --add-dir "$WT" --output-format json)
[ -n "$CONFIG" ] && SPAWN_COMMON+=(--add-dir "$(cd "$(dirname "$CONFIG")" && pwd)")

# ---- tracker (github writes the claim; jira is operator-attested and read-only) ----
issue_state() { # prints the state, or nothing when the tracker could not be read — callers refuse on nothing
  [ "$TRACKER" = github ] || { echo OPEN; return 0; }
  "$GH_READ" issue view "$ISSUE" --json state --jq .state 2>/dev/null
}
has_label() { # a checked match: the producer's output is captured first, so a dead gh never reads as "no"
  [ "$TRACKER" = github ] || return 1
  local names; names="$("$GH_READ" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null)" || return 1
  grep -qxF "$1" <<<"$names"
}
lane_marker_present() { # the lane's own claim marker: a whole-line stage marker plus a run_id line, posted by a Bot or by the
  # account this scheduler writes with — issue comments are writable by anyone on a public repo (orchestrate.sh's filter, kept)
  local repo; repo="$("$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || return 1
  local me; me="$("$GH" api user --jq .login 2>/dev/null)" || me=""
  local comments; comments="$("$GH_READ" api "repos/$repo/issues/$ISSUE/comments" --paginate 2>/dev/null)" || return 1
  printf '%s' "$comments" | jq -e --arg me "$me" 'any(.[];
      ((.user.type // "") == "Bot" or (($me != "") and ((.user.login // "") == $me)))
      and (.body | test("(^|\n)<!-- stage: lean-claimed -->(\n|$)"))
      and (.body | test("<!-- run_id: ")))' >/dev/null 2>&1
}
claim() {
  [ "$TRACKER" = github ] || { say "claim: $TRACKER tracker — operator-attested, nothing written"; return 0; }
  if has_label "$L_CLAIMED"; then
    # re-entry, as the old lane read it: the claimed label AND a lane-posted marker; a claim with no
    # marker was made by someone else and is refused unless the operator says --resume
    if [ "$RESUME" -eq 1 ] || lane_marker_present; then
      say "claim: re-entering a ticket the lane claimed"; CLAIMED=1; return 0
    fi
    terminal claimed-elsewhere "#$ISSUE carries $L_CLAIMED with no lane claim marker; pass --resume to take it over"
  fi
  local b; for b in $L_BLOCKERS; do has_label "$b" && terminal not-queued "#$ISSUE carries blocker label $b"; done
  has_label "$L_QUEUE" || terminal not-queued "#$ISSUE does not carry $L_QUEUE — only the operator queues a ticket"
  # the atomic queue->claimed swap, add-then-confirm-then-remove, bot-aware (tools/claim-issue.sh)
  if [ "$BOT_OK" -eq 1 ]; then SECOND_SHIFT_CONFIG="${CONFIG:-}" bash "$TOOLS/claim-issue.sh" "$ISSUE" --queue "$L_QUEUE" --claimed "$L_CLAIMED" >/dev/null 2>&1 || terminal env-claim-failed "claim-issue.sh could not swap $L_QUEUE -> $L_CLAIMED on #$ISSUE"
  else "$GH" issue edit "$ISSUE" --add-label "$L_CLAIMED" --remove-label "$L_QUEUE" >/dev/null 2>&1 || terminal env-claim-failed "could not swap $L_QUEUE -> $L_CLAIMED on #$ISSUE"; fi
  # the claim marker, in the shape the old lane posted (re-entry and evidence readers grep it)
  # shellcheck disable=SC2016  # markdown backticks, not shell
  "$GH" issue comment "$ISSUE" --body "$(printf '<!-- dev-pipeline -->\n<!-- run_id: %s -->\n<!-- session_id: %s -->\n<!-- stage: lean-claimed -->\n\n🤖 Claimed by \`/dev-pipeline:run\`.\nsecond-shift-run: %s (branch %s)' "$RUN_ID" "${CLAUDE_CODE_SESSION_ID:-unset}" "$RUN_ID" "$BRANCH")" >/dev/null 2>&1 || terminal env-claim-failed "labels swapped but the claim marker could not be posted on #$ISSUE — re-entry would refuse; fix the tracker write and --resume"
  CLAIMED=1
}

# ---- record sections (read from the FIRST commit, never the head) ----
FIRST=""
record_at_first() { git -C "$WT" show "$FIRST:$RECORD_REL" 2>/dev/null; }
section() { record_at_first | awk -v h="$1" 'tolower($0) ~ "^## "h {on=1; next} on && /^## /{exit} on'; }
# shellcheck disable=SC2016  # the backticks are markdown, not shell
record_checks() { section "checks" | sed -n 's/^- *`\{0,1\}\([^`]*\)`\{0,1\} *$/\1/p'; }
# The consumer's configured `commands.<repo>` (lint, typecheck, test, extraLanes) run as checks,
# as milestone 3 ran them; the record's `## Checks` adds to them. Config lives in the main
# checkout's gitignored .claude/, which the build session cannot edit either.
commands_key() { # the repo id whose commands apply: topology's "." entry while topology exists, else the sole key, else this checkout's name
  [ -n "$CONFIG" ] || return 0
  jq -r --arg s "$REPO_SLUG" '
    (.topology.repos // {} | to_entries | map(select(.value.path == ".")) | .[0].key) as $t
    | (.commands // {} | keys) as $k
    | if ($t != null and ($k | index($t))) then $t elif ($k | length) == 1 then $k[0] elif ($k | index($s)) then $s else empty end' "$CONFIG" 2>/dev/null
}
validate_lanes() { # the #100 backstop the gate carried: a malformed lane fails loudly, never silently contributes nothing
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  local bad; bad="$(jq -r --arg k "$key" '
    def check(kind): to_entries[] | select((.value|type) != "object" or (.value.name // "") == "" or ((.value.commands // []) | type) != "array" or ((.value.commands // []) | length) == 0 or any(.value.commands[]; type != "string"))
      | kind + " lane [" + (.key|tostring) + "]: must be an object {name, cwd?, commands[] of strings}";
    ((.commands[$k].lanes // []) | if type == "array" then check("setup") else "commands.lanes must be an array" end),
    ((.commands[$k].extraLanes // []) | if type == "array" then check("extra") else "commands.extraLanes must be an array" end)' "$CONFIG" 2>&1 | head -n 1)"
  [ -z "$bad" ] || terminal env-config-lanes "commands.$key: $bad"
}
setup_lanes() { # lanes[] setup steps, in their cwd (a path under the worktree now that topology ids are retired)
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '.commands[$k].lanes[]? | (.cwd // ".") as $d | .commands[] | if $d == "." then . else "cd " + ($d|@sh) + " && " + . end' "$CONFIG" 2>/dev/null
}
config_checks() { # config_checks [all] — lint/typecheck/test/format, then extraLanes whose `when` globs match a changed file (or have none);
  # `all` lists every extraLane regardless (for the prompt and the allowlist before any diff exists); setup lanes run before these, fail-fast
  local key; key="$(commands_key)"; [ -n "$key" ] || return 0
  jq -r --arg k "$key" '.commands[$k] | [.lint, .typecheck, .test, .format] | map(select(type=="string"))[]' "$CONFIG" 2>/dev/null
  if [ "${1:-}" = all ]; then jq -r --arg k "$key" '.commands[$k].extraLanes[]?.commands[]? | select(type=="string")' "$CONFIG" 2>/dev/null; return 0; fi
  local changed; changed="$(git -C "$WT" diff --name-only "$FIRST" HEAD 2>/dev/null)"
  jq -c --arg k "$key" '.commands[$k].extraLanes[]? | {when: (.when // []), commands: (.commands // [])}' "$CONFIG" 2>/dev/null | while IFS= read -r lane; do
    local hit=1 g f
    if [ "$(printf '%s' "$lane" | jq '.when | length')" -gt 0 ]; then
      hit=0
      while IFS= read -r g; do while IFS= read -r f; do # shellcheck disable=SC2254  # $g IS a glob, by contract
        case "$f" in $g) hit=1 ;; esac; done <<EOF
$changed
EOF
      done <<EOF
$(printf '%s' "$lane" | jq -r '.when[]')
EOF
    fi
    [ "$hit" -eq 1 ] && printf '%s' "$lane" | jq -r '.commands[] | select(type=="string")'
  done
}
allow_unverified() { local key; key="$(commands_key)"; [ -n "$key" ] && [ "$(jq -r --arg k "$key" '.commands[$k].allowUnverified // false' "$CONFIG" 2>/dev/null)" = true ]; }
checks_list() { { config_checks "${1:-}"; record_checks; } | awk 'NF && !seen[$0]++'; }
frames_rows() { section "design frames" | grep -E '^\| *RS-[0-9]+ *\|' | sed 's/^| *//; s/ *| */|/g; s/ *|$//'; }

# ---- the two prompts ----
build_prompt() { # build_prompt <round> <findings-file-or-empty>
  {
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
}
review_prompt() { # review_prompt <pr> <review-input-file>
  {
    echo "You are reviewing PR #$1 of this repository at its current head, in a session separate from the one that built it. Check out the PR head. Read the decision record at $RECORD_REL as it stood at commit $FIRST (git show $FIRST:$RECORD_REL) and as it stands at the head."
    echo "Score EVERY row of the record against the code: honored, violated, departed (the row was edited; name who decided, per its provenance), or undeterminable (say what you could not read). A violated or undeterminable row is a blocker; neither may stand beside an approve."
    echo "Then run review-toolkit:review-lead over the PR diff and DECLARE THE PIPELINE DEFAULT PANEL when you invoke it: the fan-out defaults to scope-completeness-reviewer; security-reviewer, a11y-reviewer and unit-test-mutation-reviewer are selected only by an opt-in — a 'review panel' row in the record with user-answered or user-delegated provenance naming security, a11y or unit-test-mutation, or the config's reviewers.default[]. review-lead never infers this; an undeclared panel leaves the surface triggers in force."
    echo "If the ticket has design frames, render every screen at the head with the repo's render command and compare it with its frame; if you cannot render, you cannot approve: post 'verdict: needs-work' with a line 'reason: render-unavailable'."
    local via=""; [ "$BOT_OK" -eq 1 ] && via=" through $GH (the bot identity)"
    echo; echo "Post ONE PR comment$via. Its first line is exactly 'verdict: approve' or 'verdict: needs-work'; its second line is exactly 'reviewed: <the full sha of the head you reviewed>'. Then the row table, then findings. Never edit that comment afterwards."
    echo; echo "## Scheduler input (deleted or skipped tests, config edits, and the build's permission denials)"; cat "$2"
  }
}

# ---- deterministic checks at the pushed head ----
run_checks() { # -> 0 green, 1 red; writes $STATE/checks-N.log
  local log="$STATE/checks-$1.log" cmd rc=0 n=0; : > "$log"
  # setup lanes first, fail-fast: a failed install makes every later red a bogus one
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    say "setup: $cmd"
    if lane "$cmd" >> "$log" 2>&1; then echo "ok (setup): $cmd" >> "$log"; else echo "RED (setup, aborting the rest): $cmd" >> "$log"; return 1; fi
  done <<EOF
$(setup_lanes)
EOF
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue; n=$((n+1))
    say "check: $cmd"
    # SEAM_SCRUB, as milestone 3 did: a lane command never sees the scheduler's config seam
    if lane "$cmd" >> "$log" 2>&1; then echo "ok: $cmd" >> "$log"; else echo "RED: $cmd" >> "$log"; rc=1; fi
  done <<EOF
$(checks_list)
EOF
  if [ "$n" -eq 0 ]; then
    allow_unverified && { say "checks: none configured; commands.<repo>.allowUnverified is true, so this is declared, not silent"; return 0; }
    say "checks: nothing configured under commands.* and nothing under '## Checks' — refusing to read that as green (declare allowUnverified to accept it)"; return 1
  fi
  return $rc
}
route_smoke() { # -> 0 ok, 1 red, 2 unconfigured
  local rows; rows="$(frames_rows)"; [ -n "$rows" ] || return 0
  [ -n "$RENDER_CMD" ] || return 2
  local rc=0 prev="" rs route state must png sha
  while IFS='|' read -r rs route state _frame must; do
    png="$STATE/smoke-$rs.png"; rm -f "$png"
    local c="${RENDER_CMD//\{route\}/$route}"; c="${c//\{out\}/$png}"; c="${c//\{state\}/$state}"
    if ! lane "$c" > "$STATE/smoke-$rs.log" 2>&1; then say "smoke: $rs render failed"; rc=1; continue; fi
    [ -s "$png" ] || { say "smoke: $rs produced no image"; rc=1; continue; }
    sha="$(shasum "$png" | cut -c1-40)"; [ "$sha" != "$prev" ] || { say "smoke: $rs is pixel-identical to the previous state"; rc=1; }; prev="$sha"
    [ -n "$must" ] || { say "smoke: $rs declares no must-show value — the record must name one per screen (D-4)"; rc=1; continue; }
    if [ -n "$must" ]; then
      [ -n "$SMOKE_CMD" ] || return 2
      c="${SMOKE_CMD//\{route\}/$route}"; c="${c//\{mustShow\}/$must}"
      lane "$c" >> "$STATE/smoke-$rs.log" 2>&1 || { say "smoke: $rs must-show '$must' not satisfied"; rc=1; }
    fi
  done <<EOF
$rows
EOF
  return $rc
}
test_surface_diff() { # -> file; a diff that cannot be read is a refusal, never "(none)"
  local out="$STATE/review-input-$1.md" ns full names
  ns="$(git -C "$WT" diff --name-status "$FIRST"..HEAD 2>/dev/null)" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT"
  full="$(git -C "$WT" diff "$FIRST"..HEAD 2>/dev/null)" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT"
  names="$(git -C "$WT" diff --name-only "$FIRST"..HEAD 2>/dev/null)" || terminal env-worktree "cannot diff $FIRST..HEAD in $WT"
  {
    echo "### Deleted or renamed test files"; awk '$1 ~ /^[DR]/ && $2 ~ /(\.spec\.|\.test\.|_test\.|\/tests?\/)/' <<<"$ns"; echo
    echo "### Added skips / forced-green lines"; grep -nE '^\+.*(\.skip\(|\.only\(|\|\| *true|xit\(|xdescribe\()' <<<"$full" || echo "(none)"; echo
    echo "### CI or check configuration edited"; grep -E '^\.github/|^\.gitlab|\.ya?ml$|^package\.json$|vitest\.config|jest\.config|\.eslintrc|tsconfig' <<<"$names" || echo "(none)"; echo
    echo "### Build session permission denials"; [ -s "$STATE/denials-$1.txt" ] && cat "$STATE/denials-$1.txt" || echo "(none)"
  } > "$out"; echo "$out"
}
# The premise can expire mid-run (kept from orchestrate.sh): the ticket closed, or the base moved
# into a file this branch touches — a green build against a base nobody merges onto is wasted.
premise_holds() {
  local st; st="$(issue_state)"; [ -n "$st" ] || terminal staleness-unreadable "could not read #$ISSUE from the tracker mid-run"
  [ "$st" = OPEN ] || terminal ticket-closed "#$ISSUE closed mid-run"
  git -C "$WT" fetch -q origin "$BASE_NAME" 2>/dev/null || terminal staleness-unreadable "could not fetch origin/$BASE_NAME — a predicate that cannot be evaluated is not a predicate that passed"
  local base_now; base_now="$(git -C "$WT" rev-parse -q --verify "origin/$BASE_NAME" 2>/dev/null)"; [ -n "$base_now" ] || terminal staleness-unreadable "origin/$BASE_NAME does not resolve"
  [ "$base_now" = "$BASE_START" ] && return 0
  local overlap; overlap="$(comm -12 <(git -C "$WT" diff --name-only "$BASE_START" "$base_now" | sort) <(git -C "$WT" diff --name-only "$FIRST" HEAD | sort) | head -n 3 | tr '\n' ' ')"
  [ -z "$overlap" ] || terminal staleness-expired "origin/$BASE_NAME moved into file(s) this branch touches: $overlap"
}

# ---- PR and verdict ----
open_pr() { "$GH_READ" pr list --head "$BRANCH" --state open --json number --jq '.[].number' 2>/dev/null; }
remote_head() { git -C "$WT" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | cut -f1; }
ci_status() { # <pr> -> one word for the report; never waited on (checks already ran here)
  local out; out="$("$GH_READ" pr checks "$1" --json name,state 2>/dev/null)" || { echo unavailable; return; }
  [ "$(printf '%s' "$out" | jq 'length')" -gt 0 ] || { echo none; return; }
  printf '%s' "$out" | jq -e 'any(.[]; .state=="FAILURE" or .state=="ERROR")' >/dev/null && { echo red; return; }
  printf '%s' "$out" | jq -e 'all(.[]; .state=="SUCCESS" or .state=="NEUTRAL" or .state=="SKIPPED")' >/dev/null && { echo green; return; }
  echo pending
}
verdict() { # <pr> <start-iso> <end-iso> <head> -> prints approve|needs-work and saves the body; 1 if unbound
  local repo; repo="$("$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  "$GH_READ" api "repos/$repo/issues/$1/comments" --paginate 2>/dev/null \
    | jq -r --arg s "$2" --arg e "$3" --arg h "$4" '
        .[] | select(.created_at >= $s and .created_at <= $e and .created_at == .updated_at)
        | select((.body | split("\n")[0]) | test("^verdict: (approve|needs-work)$"))
        | select((.body | split("\n")[1]) == ("reviewed: " + $h))
        | (.body | split("\n")[0] | sub("^verdict: ";"")) + "\t" + (.body | @base64)' \
    | tail -n 1 > "$STATE/verdict.tsv"
  [ -s "$STATE/verdict.tsv" ] || return 1
  cut -f2 "$STATE/verdict.tsv" | base64 --decode > "$STATE/verdict-body.md"
  cut -f1 "$STATE/verdict.tsv"
}
first_word() { # the command word an allowlist entry keys on, past any leading VAR=value assignments
  local w; for w in $1; do case "$w" in *=*) continue ;; *) printf '%s' "$w"; return ;; esac; done; printf '%s' "${1%% *}"
}
add_cost() { local c; c="$(jq -r '.total_cost_usd // 0' "$1" 2>/dev/null)"; COST="$(awk -v a="$COST" -v b="${c:-0}" 'BEGIN{print a+b}')"; }
over_ceiling() { awk -v c="$COST" -v m="$COST_CEIL" 'BEGIN{exit !(c>m)}'; }

# ================================ the run ================================
say "run $RUN_ID: issue $ISSUE, tracker $TRACKER (writes $TRACKER_WRITES), branch $BRANCH, worktree $WT, record $RECORD_REL"
[ -f "$RECORD" ] || terminal env-no-record "no intake record at $RECORD — run /intake-toolkit:plan-interview $ISSUE first"
validate_lanes
if [ "$DRY" -eq 1 ]; then say "dry-run: would claim, create the worktree, commit the record, and run up to $MAX_ROUNDS rounds; checks: $(checks_list 2>/dev/null | tr '\n' ';')"; echo "terminal: dry-run"; exit 0; fi
st="$(issue_state)"; [ -n "$st" ] || terminal env-tracker-unreadable "could not read #$ISSUE from the tracker"
[ "$st" = OPEN ] || terminal env-ticket-closed "#$ISSUE is not open — nothing spawned, a preflight refusal like any other"
claim
if [ -z "$MODEL" ]; then
  if has_label opus; then MODEL=claude-opus-5; MODEL_BASIS="label"; elif has_label sonnet; then MODEL=claude-sonnet-5; MODEL_BASIS="label"
  elif [ "$TRACKER" != github ]; then terminal usage-model "under $TRACKER pass --build-model: there is no sizing label to read"
  else terminal usage-model "#$ISSUE carries neither opus nor sonnet — intake sizes tickets, this scheduler does not (pass --build-model to override)"; fi
fi
say "models: build $MODEL (${MODEL_BASIS:-flag}), review $REVIEW_MODEL (${REVIEW_MODEL_BASIS:-default})"

# worktree on the branch; the record is the first commit, pushed before any build starts
git -C "$MAIN_ROOT" fetch -q origin || true
base="$(git -C "$MAIN_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
for b in "$base" origin/main origin/master; do [ -n "$b" ] && git -C "$MAIN_ROOT" rev-parse -q --verify "$b" >/dev/null 2>&1 && { base="$b"; break; }; done
BASE_NAME="${base#origin/}"
if [ -d "$WT" ]; then
  [ "$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$BRANCH" ] || terminal env-worktree-mismatch "$WT exists on another branch"
else
  if git -C "$MAIN_ROOT" rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1 || git -C "$MAIN_ROOT" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
    git -C "$MAIN_ROOT" worktree add -q "$WT" "$BRANCH" 2>/dev/null || git -C "$MAIN_ROOT" worktree add -q --track -b "$BRANCH" "$WT" "origin/$BRANCH" || terminal env-worktree "could not attach $WT to $BRANCH"
  else
    git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$WT" "$base" || terminal env-worktree "could not create $WT from $base"
  fi
fi
# the staleness anchor is the branch point (merge-base), as the gate measured it — not the base at
# re-entry, which would hide every move that happened between runs
BASE_START="$(git -C "$WT" merge-base "origin/$BASE_NAME" HEAD 2>/dev/null)"
[ -n "$BASE_START" ] || terminal env-base-unreadable "cannot resolve the merge-base of origin/$BASE_NAME and $BRANCH"
if ! git -C "$WT" cat-file -e "HEAD:$RECORD_REL" 2>/dev/null; then
  mkdir -p "$WT/$(dirname "$RECORD_REL")" && cp "$RECORD" "$WT/$RECORD_REL"
  git -C "$WT" add "$RECORD_REL" || terminal env-record-commit "could not stage the record"
  if [ "$BOT_OK" -eq 1 ]; then SECOND_SHIFT_CONFIG="${CONFIG:-}" bash "$TOOLS/bot-commit.sh" -C "$WT" -q -m "docs: decision record for #$ISSUE" -- "$RECORD_REL" || terminal env-record-commit "bot-commit.sh could not commit the record"
  else git -C "$WT" commit -q -m "docs: decision record for #$ISSUE" -- "$RECORD_REL" || terminal env-record-commit "could not commit the record"; fi
  git -C "$WT" push -q -u origin "$BRANCH" || terminal env-push "could not push $BRANCH"
fi
FIRST="$(git -C "$WT" log --format=%H --diff-filter=A -- "$RECORD_REL" | tail -n 1)"
[ -n "$FIRST" ] || terminal env-no-first-commit "the record has no adding commit on $BRANCH"
say "record baseline: $FIRST"

FINDINGS=""; ROUND=0
while [ "$ROUND" -lt "$MAX_ROUNDS" ]; do
  ROUND=$((ROUND+1)); say "round $ROUND of $MAX_ROUNDS (cost so far \$$COST)"
  premise_holds
  if [ -n "$READY_URL" ] && ! curl -fsS -m 10 "$READY_URL" >/dev/null 2>&1; then terminal env-not-ready "ready probe $READY_URL failed"; fi

  # ---- build ----
  before="$(remote_head)"; ATTEMPT=$((ATTEMPT+1)); A="$ROUND.$ATTEMPT"
  build_prompt "$ROUND" "$FINDINGS" > "$STATE/build-$A.prompt"
  allow="Read,Edit,Write,Agent,Bash(git *),Bash(gh pr create*),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh issue view*)$MCP_ALLOW"
  [ "$BOT_OK" -eq 1 ] && allow="$allow,Bash($TOOLS/bot-commit.sh*),Bash($GH *)"
  [ -n "$(frames_rows)" ] && allow="$allow,mcp__figma,mcp__plugin_figma_figma"
  while IFS= read -r c; do [ -n "$c" ] && allow="$allow,Bash($(first_word "$c")*)"; done <<EOF
$(checks_list all)
EOF
  [ -n "$RENDER_CMD" ] && allow="$allow,Bash($(first_word "$RENDER_CMD")*)"
  ( cd "$WT" && bounded "$BUILD_TO" "$STATE/build-$A.json" \
      "$CLAUDE" -p --model "$MODEL" "${SPAWN_COMMON[@]}" --allowedTools "$allow" --max-turns 400 "$(cat "$STATE/build-$A.prompt")" ); brc=$?
  add_cost "$STATE/build-$A.json"
  jq -r '.permission_denials[]? | (.tool_name + " " + (.tool_input|tostring))' "$STATE/build-$A.json" > "$STATE/denials-$A.txt" 2>/dev/null || true
  [ "$brc" -eq 124 ] && terminal build-blocked "build session exceeded ${BUILD_TO}s"
  sub="$(jq -r '.subtype // "unreadable"' "$STATE/build-$A.json" 2>/dev/null)"
  [ "$sub" = success ] || terminal build-blocked "build session ended $sub (rc=$brc)"
  over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
  after="$(remote_head)"; [ -n "$after" ] && [ "$after" != "$before" ] || terminal build-inflight "remote head of $BRANCH did not move in round $ROUND"
  git -C "$WT" fetch -q origin "$BRANCH" && git -C "$WT" reset -q --hard "origin/$BRANCH"
  n="$(open_pr | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || { [ "$n" -eq 0 ] && terminal build-no-pr "no open PR for $BRANCH after round $ROUND" || terminal pr-ambiguous "$n open PRs for $BRANCH"; }
  PR="$(open_pr)"; PR_URL="$("$GH_READ" pr view "$PR" --json url --jq .url 2>/dev/null)"

  # ---- checks the build did not run ----
  if ! run_checks "$A"; then
    CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "checks red $CHECKS_RED times"
    FINDINGS="$STATE/checks-$A.log"; say "checks red — findings are the check log; next attempt of this round"; ROUND=$((ROUND-1)); continue
  fi
  route_smoke; src=$?
  [ "$src" -eq 2 ] && terminal env-smoke-unconfigured "the record declares design frames but design.liveRender.command/smokeCommand is not configured"
  if [ "$src" -ne 0 ]; then
    CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "smoke red $CHECKS_RED times"
    cat "$STATE"/smoke-*.log > "$STATE/smoke-$A.log" 2>/dev/null; FINDINGS="$STATE/smoke-$A.log"; ROUND=$((ROUND-1)); continue
  fi
  input="$(test_surface_diff "$A")"

  # ---- review, in a fresh session, bound to this head and this time window ----
  head="$(remote_head)"; start="$(now)"
  review_prompt "$PR" "$input" > "$STATE/review-$A.prompt"
  rallow="Read,Agent,Bash(git *),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh pr diff*),Bash(gh api*)$MCP_ALLOW${RENDER_CMD:+,Bash($(first_word "$RENDER_CMD")*)}"
  [ -n "$(frames_rows)" ] && rallow="$rallow,mcp__figma,mcp__plugin_figma_figma"
  [ "$BOT_OK" -eq 1 ] && rallow="$rallow,Bash($GH *)"
  ( cd "$WT" && bounded "$REVIEW_TO" "$STATE/review-$A.json" \
      "$CLAUDE" -p --model "$REVIEW_MODEL" "${SPAWN_COMMON[@]}" --allowedTools "$rallow" --max-turns 300 "$(cat "$STATE/review-$A.prompt")" ); rrc=$?
  end="$(now)"; add_cost "$STATE/review-$A.json"
  [ "$rrc" -eq 124 ] && terminal review-unbound "review session exceeded ${REVIEW_TO}s"
  rsub="$(jq -r '.subtype // "unreadable"' "$STATE/review-$A.json" 2>/dev/null)"
  [ "$rsub" = success ] || terminal review-unbound "review session ended $rsub (rc=$rrc)"
  v="$(verdict "$PR" "$start" "$end" "$head")" || terminal review-unbound "no unedited 'verdict:' comment naming head $head was posted between $start and $end"
  [ "$(remote_head)" = "$head" ] || terminal review-unbound "head moved during review"
  say "verdict: $v (reviewed $head)"
  [ "$v" = approve ] && break
  FINDINGS="$STATE/verdict-body.md"
  over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
done

CI="$( [ -n "$PR" ] && ci_status "$PR" || echo none )"; say "ci: $CI (read once for the report; the checks that gate a round ran here)"
# The run's summary goes in the PR BODY under the marker the old lane used, replacing an earlier
# block from a resumed run: the body is what a human reads at merge, and comments scroll away.
cost_block() {
  echo '<!-- pipeline-cost-block -->'
  echo "## second-shift run"; echo
  echo "| run | rounds | verdict | reviewed head | cost | CI |"; echo "| --- | --- | --- | --- | --- | --- |"
  echo "| $RUN_ID | $ROUND | ${v:-none} | ${head:-—} | \$$COST | $CI |"; echo
  echo "| session | turns | cost |"; echo "| --- | --- | --- |"
  local f; for f in "$STATE"/build-*.json "$STATE"/review-*.json; do
    [ -f "$f" ] && jq -r --arg n "$(basename "$f" .json)" '"| \($n) | \(.num_turns // "?") | $\((.total_cost_usd // 0) * 100 | round / 100) |"' "$f"
  done
  echo '<!-- /pipeline-cost-block -->'
}
if [ -n "$PR" ]; then
  repo="$("$GH_READ" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  if ! body="$("$GH_READ" api "repos/$repo/pulls/$PR" --jq .body 2>/dev/null)"; then
    say "could not read PR #$PR's body; the run block is NOT written (a blind replace would erase the body)"; body=""; SKIP_BODY=1
  fi
  # strip an earlier block: ours ends at the closing marker, the old lane's at its `Cache-hit rate:` line
  body="$(printf '%s\n' "$body" | awk '$0 == "<!-- pipeline-cost-block -->"{skip=1} !skip{print} skip && ($0 == "<!-- /pipeline-cost-block -->" || /^Cache-hit rate: /){skip=0} END{if (skip) print "<!-- an earlier cost block had no terminator; text below it was not preserved -->"}')"
  printf '%s\n\n%s\n' "$body" "$(cost_block)" > "$STATE/pr-body.md"
  if [ "${SKIP_BODY:-0}" -eq 0 ]; then
    "$GH" api -X PATCH "repos/$repo/pulls/$PR" -F "body=@$STATE/pr-body.md" >/dev/null 2>&1 || say "could not write the run block into PR #$PR's body (it is in $STATE/pr-body.md)"
  fi
fi
if [ "${v:-}" = approve ]; then
  # close-out teardown, as before: the branch and PR stay, the worktree goes
  git -C "$MAIN_ROOT" worktree remove "$WT" >/dev/null 2>&1 && say "worktree $WT removed" || say "worktree $WT left in place (uncommitted work or a lock; remove it by hand)"
  terminal approved "PR #$PR approved at $head after $ROUND round(s), \$$COST"
fi
terminal rounds-spent "$MAX_ROUNDS rounds without an approve (cost \$$COST)"
