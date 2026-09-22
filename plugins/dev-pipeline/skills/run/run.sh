#!/usr/bin/env bash
# run.sh — the shrunk scheduler: one ticket in, an approved PR out, unattended.
#
# Spawns a BUILD session and a REVIEW session in fresh `claude -p` processes and reads three
# things it did not author: the repo's own checks (run here, from the record's first commit),
# the PR head (must move every round), and a verdict comment bound to that head and to the
# review session's time window. Nothing here tells the model how to work; the record does.
#
# usage: run.sh <issue> [--record <path>] [--max-rounds N] [--model <id>] [--dry-run] [--resume]
#
# env:  SECOND_SHIFT_CONFIG   config path (default <main>/.claude/second-shift.config.json)
#       RUN_CLAUDE / RUN_GH   the binaries (tests inject fakes)
#       RUN_WORKTREE_ROOT     default <parent of main>/<repo>-worktrees
#       RUN_BUILD_TIMEOUT / RUN_REVIEW_TIMEOUT   seconds (7200 / 3600)
#       RUN_COST_CEILING      USD (100); RUN_CHECKS_RED_MAX (3)
#
# exit: 0 approved · 1 any other terminal (printed as `terminal: <slug>`)
set -uo pipefail

CLAUDE="${RUN_CLAUDE:-claude}"; GH="${RUN_GH:-gh}"
ISSUE=""; RECORD=""; MAX_ROUNDS=3; MODEL="${RUN_MODEL:-claude-sonnet-5}"; DRY=0; RESUME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --record) RECORD="$2"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --resume) RESUME=1; shift ;;
    -*) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
    *) ISSUE="$1"; shift ;;
  esac
done
[ -n "$ISSUE" ] || { echo "usage: run.sh <issue> [--record <path>] [--max-rounds N] [--model <id>] [--dry-run] [--resume]" >&2; exit 2; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { echo "$(now) [run] $*"; }
terminal() { # terminal <slug> <detail>
  say "terminal: $1 — $2"; echo "terminal: $1"
  [ "${1:-}" = approved ] && exit 0 || exit 1
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
PLANS_DIR="$(cfg .paths.plansDir)"; PLANS_DIR="${PLANS_DIR:-docs/plans}"
RENDER_CMD="$(cfg .design.liveRender.command)"
SMOKE_CMD="$(cfg .design.liveRender.smokeCommand)"
READY_URL="$(cfg .design.liveRender.readyProbe)"
REPO_SLUG="$(basename "$MAIN_ROOT")"
BRANCH="second-shift/$ISSUE"
WT_ROOT="${RUN_WORKTREE_ROOT:-$(dirname "$MAIN_ROOT")/${REPO_SLUG}-worktrees}"
WT="$WT_ROOT/$ISSUE"
RECORD_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-decisions.md"
[ -n "$RECORD" ] || RECORD="$MAIN_ROOT/.claude/pipeline-state/$ISSUE-ledger.md"
BUILD_TO="${RUN_BUILD_TIMEOUT:-7200}"; REVIEW_TO="${RUN_REVIEW_TIMEOUT:-3600}"
COST_CEIL="${RUN_COST_CEILING:-100}"; CHECKS_RED_MAX="${RUN_CHECKS_RED_MAX:-3}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STATE="$MAIN_ROOT/.claude/pipeline-state/run-$ISSUE"; mkdir -p "$STATE"
COST=0; CHECKS_RED=0; CHILD=""

cleanup() { [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null; }
trap 'cleanup; say "interrupted; claim left in place"; exit 130' INT TERM

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

# ---- tracker (github writes the claim; jira is operator-attested and read-only) ----
issue_state() { [ "$TRACKER" = github ] && "$GH" issue view "$ISSUE" --json state --jq .state 2>/dev/null || echo OPEN; }
has_label() { [ "$TRACKER" = github ] && "$GH" issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null | grep -qx "$1"; }
claim() {
  [ "$TRACKER" = github ] || { say "claim: $TRACKER tracker — operator-attested, nothing written"; return 0; }
  if has_label in-progress && [ "$RESUME" -eq 0 ]; then terminal claimed-elsewhere "#$ISSUE carries in-progress; pass --resume to re-enter your own run"; fi
  "$GH" issue edit "$ISSUE" --add-label in-progress >/dev/null 2>&1 || terminal env-claim-failed "could not label #$ISSUE"
  "$GH" issue comment "$ISSUE" --body "second-shift-run: $RUN_ID (branch $BRANCH)" >/dev/null 2>&1 || true
}

# ---- record sections (read from the FIRST commit, never the head) ----
FIRST=""
record_at_first() { git -C "$WT" show "$FIRST:$RECORD_REL" 2>/dev/null; }
section() { record_at_first | awk -v h="$1" 'tolower($0) ~ "^## "h {on=1; next} on && /^## /{exit} on'; }
# shellcheck disable=SC2016  # the backticks are markdown, not shell
checks_list() { section "checks" | sed -n 's/^- *`\{0,1\}\([^`]*\)`\{0,1\} *$/\1/p'; }
frames_rows() { section "design frames" | grep -E '^\| *RS-[0-9]+ *\|' | sed 's/^| *//; s/ *| */|/g; s/ *|$//'; }

# ---- the two prompts ----
build_prompt() { # build_prompt <round> <findings-file-or-empty>
  {
    echo "Implement ticket $ISSUE of this repository. Fetch the ticket text yourself from the tracker (${TRACKER})."
    echo "Do not merge. Do not delete, skip or weaken a test to make a check pass; if a test is wrong, say so in the PR."
    if [ "$1" -eq 1 ]; then echo "When the checks are green, commit, push branch $BRANCH to origin and open a PR against the default branch with 'gh pr create'. The PR body's first line must be: built-by: second-shift run $RUN_ID"
    else echo "Address the review findings below: fix each, or rebut it in a PR comment. Then commit and push $BRANCH."; fi
    echo; echo "The following decisions were settled with the requester before implementation started. They are binding. The record is committed at $RECORD_REL; if you must depart from a row, edit that row in place (new resolution, provenance user-delegated, a one-line reason) and commit the edit with the code. Never post a comment starting with 'verdict:'."
    echo; record_at_first
    if [ -n "$(frames_rows)" ]; then
      echo; echo "This ticket has design frames. Follow the figma-faithful sequence: read every frame id in the '## Design frames' section first; write the token and component plan; before writing UI code, have a subagent read that plan against the frames and list what it would get wrong, then fix the plan. Render every screen with the repo's render command, open the PNG, compare it with its frame and fix what differs, up to three rounds per screen. A screen that shows an error page, a login page or a spinner is not done."
    fi
    echo; echo "Before opening the PR (or pushing a fix), run every command under '## Checks' and make it green."
    [ -n "$2" ] && { echo; echo "## Review findings"; cat "$2"; }
  }
}
review_prompt() { # review_prompt <pr> <review-input-file>
  {
    echo "You are reviewing PR #$1 of this repository at its current head, in a session separate from the one that built it. Check out the PR head. Read the decision record at $RECORD_REL as it stood at commit $FIRST (git show $FIRST:$RECORD_REL) and as it stands at the head."
    echo "Score EVERY row of the record against the code: honored, violated, or departed (the row was edited; name who decided, per its provenance). A violated row is a blocker. Then run review-lead with the repo's default panel over the PR diff."
    echo "If the ticket has design frames, render every screen at the head with the repo's render command and compare it with its frame; if you cannot render, you cannot approve: post 'verdict: needs-work' with a line 'reason: render-unavailable'."
    echo; echo "Post ONE PR comment. Its first line is exactly 'verdict: approve' or 'verdict: needs-work'; its second line is exactly 'reviewed: <the full sha of the head you reviewed>'. Then the row table, then findings. Never edit that comment afterwards."
    echo; echo "## Scheduler input (deleted or skipped tests, config edits, and the build's permission denials)"; cat "$2"
  }
}

# ---- deterministic checks at the pushed head ----
run_checks() { # -> 0 green, 1 red; writes $STATE/checks-N.log
  local log="$STATE/checks-$1.log" cmd rc=0 n=0; : > "$log"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue; n=$((n+1))
    say "check: $cmd"
    if ( cd "$WT" && bash -c "$cmd" ) >> "$log" 2>&1; then echo "ok: $cmd" >> "$log"; else echo "RED: $cmd" >> "$log"; rc=1; fi
  done <<EOF
$(checks_list)
EOF
  [ "$n" -gt 0 ] || { say "checks: none declared under '## Checks' — refusing to read that as green"; return 1; }
  return $rc
}
route_smoke() { # -> 0 ok, 1 red, 2 unconfigured
  local rows; rows="$(frames_rows)"; [ -n "$rows" ] || return 0
  [ -n "$RENDER_CMD" ] || return 2
  local rc=0 prev="" rs route state must png sha
  while IFS='|' read -r rs route state _frame must; do
    png="$STATE/smoke-$rs.png"; rm -f "$png"
    local c="${RENDER_CMD//\{route\}/$route}"; c="${c//\{out\}/$png}"; c="${c//\{state\}/$state}"
    if ! ( cd "$WT" && bash -c "$c" ) > "$STATE/smoke-$rs.log" 2>&1; then say "smoke: $rs render failed"; rc=1; continue; fi
    [ -s "$png" ] || { say "smoke: $rs produced no image"; rc=1; continue; }
    sha="$(shasum "$png" | cut -c1-40)"; [ "$sha" != "$prev" ] || { say "smoke: $rs is pixel-identical to the previous state"; rc=1; }; prev="$sha"
    if [ -n "$must" ]; then
      [ -n "$SMOKE_CMD" ] || return 2
      c="${SMOKE_CMD//\{route\}/$route}"; c="${c//\{mustShow\}/$must}"
      ( cd "$WT" && bash -c "$c" ) >> "$STATE/smoke-$rs.log" 2>&1 || { say "smoke: $rs must-show '$must' not satisfied"; rc=1; }
    fi
  done <<EOF
$rows
EOF
  return $rc
}
test_surface_diff() { # -> file
  local out="$STATE/review-input-$1.md"
  {
    echo "### Deleted or renamed test files"; git -C "$WT" diff --name-status "$FIRST"..HEAD | awk '$1 ~ /^[DR]/ && $2 ~ /(\.spec\.|\.test\.|_test\.|\/tests?\/)/' ; echo
    echo "### Added skips / forced-green lines"; git -C "$WT" diff "$FIRST"..HEAD | grep -nE '^\+.*(\.skip\(|\.only\(|\|\| *true|xit\(|xdescribe\()' || echo "(none)"; echo
    echo "### CI or check configuration edited"; git -C "$WT" diff --name-only "$FIRST"..HEAD | grep -E '^\.github/|^\.gitlab|\.ya?ml$|^package\.json$|vitest\.config|jest\.config|\.eslintrc|tsconfig' || echo "(none)"; echo
    echo "### Build session permission denials"; [ -s "$STATE/denials-$1.txt" ] && cat "$STATE/denials-$1.txt" || echo "(none)"
  } > "$out"; echo "$out"
}

# ---- PR and verdict ----
open_pr() { "$GH" pr list --head "$BRANCH" --state open --json number --jq '.[].number' 2>/dev/null; }
remote_head() { git -C "$WT" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | cut -f1; }
ci_status() { # <pr> -> one word for the report; never waited on (checks already ran here)
  local out; out="$("$GH" pr checks "$1" --json name,state 2>/dev/null)" || { echo unavailable; return; }
  [ "$(printf '%s' "$out" | jq 'length')" -gt 0 ] || { echo none; return; }
  printf '%s' "$out" | jq -e 'any(.[]; .state=="FAILURE" or .state=="ERROR")' >/dev/null && { echo red; return; }
  printf '%s' "$out" | jq -e 'all(.[]; .state=="SUCCESS" or .state=="NEUTRAL" or .state=="SKIPPED")' >/dev/null && { echo green; return; }
  echo pending
}
verdict() { # <pr> <start-iso> <end-iso> <head> -> prints approve|needs-work and saves the body; 1 if unbound
  local repo; repo="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  "$GH" api "repos/$repo/issues/$1/comments" --paginate 2>/dev/null \
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
add_cost() { local c; c="$(jq -r '.total_cost_usd // 0' "$1" 2>/dev/null)"; COST="$(awk -v a="$COST" -v b="${c:-0}" 'BEGIN{print a+b}')"; }
over_ceiling() { awk -v c="$COST" -v m="$COST_CEIL" 'BEGIN{exit !(c>m)}'; }

# ================================ the run ================================
say "run $RUN_ID: issue $ISSUE, tracker $TRACKER, branch $BRANCH, worktree $WT, record $RECORD_REL"
[ -f "$RECORD" ] || terminal env-no-record "no intake record at $RECORD — run /intake-toolkit:plan-interview $ISSUE first"
if [ "$DRY" -eq 1 ]; then say "dry-run: would claim, create the worktree, commit the record, and run up to $MAX_ROUNDS rounds"; echo "terminal: dry-run"; exit 0; fi
[ "$(issue_state)" = OPEN ] || terminal ticket-closed "#$ISSUE is not open"
claim

# worktree on the branch; the record is the first commit, pushed before any build starts
if [ -d "$WT" ]; then
  [ "$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$BRANCH" ] || terminal env-worktree-mismatch "$WT exists on another branch"
else
  git -C "$MAIN_ROOT" fetch -q origin || true
  base="$(git -C "$MAIN_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  for b in "$base" origin/main origin/master; do [ -n "$b" ] && git -C "$MAIN_ROOT" rev-parse -q --verify "$b" >/dev/null 2>&1 && { base="$b"; break; }; done
  if git -C "$MAIN_ROOT" rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1 || git -C "$MAIN_ROOT" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
    git -C "$MAIN_ROOT" worktree add -q "$WT" "$BRANCH" 2>/dev/null || git -C "$MAIN_ROOT" worktree add -q --track -b "$BRANCH" "$WT" "origin/$BRANCH" || terminal env-worktree "could not attach $WT to $BRANCH"
  else
    git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$WT" "$base" || terminal env-worktree "could not create $WT from $base"
  fi
fi
if ! git -C "$WT" cat-file -e "HEAD:$RECORD_REL" 2>/dev/null; then
  mkdir -p "$WT/$(dirname "$RECORD_REL")" && cp "$RECORD" "$WT/$RECORD_REL"
  git -C "$WT" add "$RECORD_REL" && git -C "$WT" commit -q -m "docs: decision record for #$ISSUE" -- "$RECORD_REL" || terminal env-record-commit "could not commit the record"
  git -C "$WT" push -q -u origin "$BRANCH" || terminal env-push "could not push $BRANCH"
fi
FIRST="$(git -C "$WT" log --format=%H --diff-filter=A -- "$RECORD_REL" | tail -n 1)"
[ -n "$FIRST" ] || terminal env-no-first-commit "the record has no adding commit on $BRANCH"
say "record baseline: $FIRST"

FINDINGS=""; ROUND=0; PR=""
while [ "$ROUND" -lt "$MAX_ROUNDS" ]; do
  ROUND=$((ROUND+1)); say "round $ROUND of $MAX_ROUNDS (cost so far \$$COST)"
  [ "$(issue_state)" = OPEN ] || terminal ticket-closed "#$ISSUE closed mid-run"
  if [ -n "$READY_URL" ] && ! curl -fsS -m 10 "$READY_URL" >/dev/null 2>&1; then terminal env-not-ready "ready probe $READY_URL failed"; fi

  # ---- build ----
  before="$(remote_head)"
  build_prompt "$ROUND" "$FINDINGS" > "$STATE/build-$ROUND.prompt"
  allow="Read,Edit,Write,Bash(git *),Bash(gh pr create*),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh issue view*)"
  while IFS= read -r c; do [ -n "$c" ] && allow="$allow,Bash(${c%% *}*)"; done <<EOF
$(checks_list)
EOF
  [ -n "$RENDER_CMD" ] && allow="$allow,Bash(${RENDER_CMD%% *}*)"
  ( cd "$WT" && bounded "$BUILD_TO" "$STATE/build-$ROUND.json" \
      "$CLAUDE" -p --model "$MODEL" --permission-mode acceptEdits --permission-prompts none \
        --allowedTools "$allow" --add-dir "$WT" --output-format json --max-turns 400 "$(cat "$STATE/build-$ROUND.prompt")" ); brc=$?
  add_cost "$STATE/build-$ROUND.json"
  jq -r '.permission_denials[]? | (.tool_name + " " + (.tool_input|tostring))' "$STATE/build-$ROUND.json" > "$STATE/denials-$ROUND.txt" 2>/dev/null || true
  [ "$brc" -eq 124 ] && terminal build-blocked "build session exceeded ${BUILD_TO}s"
  sub="$(jq -r '.subtype // "unreadable"' "$STATE/build-$ROUND.json" 2>/dev/null)"
  [ "$sub" = success ] || terminal build-blocked "build session ended $sub (rc=$brc)"
  over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
  after="$(remote_head)"; [ -n "$after" ] && [ "$after" != "$before" ] || terminal build-inflight "remote head of $BRANCH did not move in round $ROUND"
  git -C "$WT" fetch -q origin "$BRANCH" && git -C "$WT" reset -q --hard "origin/$BRANCH"
  n="$(open_pr | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || { [ "$n" -eq 0 ] && terminal build-no-pr "no open PR for $BRANCH after round $ROUND" || terminal pr-ambiguous "$n open PRs for $BRANCH"; }
  PR="$(open_pr)"

  # ---- checks the build did not run ----
  if ! run_checks "$ROUND"; then
    CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "checks red $CHECKS_RED times"
    FINDINGS="$STATE/checks-$ROUND.log"; say "checks red — findings are the check log; next round"; ROUND=$((ROUND-1)); continue
  fi
  route_smoke; src=$?
  [ "$src" -eq 2 ] && terminal env-smoke-unconfigured "the record declares design frames but design.liveRender.command/smokeCommand is not configured"
  if [ "$src" -ne 0 ]; then
    CHECKS_RED=$((CHECKS_RED+1)); [ "$CHECKS_RED" -lt "$CHECKS_RED_MAX" ] || terminal checks-red-spent "smoke red $CHECKS_RED times"
    cat "$STATE"/smoke-*.log > "$STATE/smoke-$ROUND.log" 2>/dev/null; FINDINGS="$STATE/smoke-$ROUND.log"; ROUND=$((ROUND-1)); continue
  fi
  input="$(test_surface_diff "$ROUND")"

  # ---- review, in a fresh session, bound to this head and this time window ----
  head="$(remote_head)"; start="$(now)"
  review_prompt "$PR" "$input" > "$STATE/review-$ROUND.prompt"
  ( cd "$WT" && bounded "$REVIEW_TO" "$STATE/review-$ROUND.json" \
      "$CLAUDE" -p --model "$MODEL" --permission-mode acceptEdits --permission-prompts none \
        --allowedTools "Read,Bash(git *),Bash(gh pr view*),Bash(gh pr comment*),Bash(gh pr diff*),Bash(gh api*)${RENDER_CMD:+,Bash(${RENDER_CMD%% *}*)}" \
        --add-dir "$WT" --output-format json --max-turns 300 "$(cat "$STATE/review-$ROUND.prompt")" ); rrc=$?
  end="$(now)"; add_cost "$STATE/review-$ROUND.json"
  [ "$rrc" -eq 124 ] && terminal review-unbound "review session exceeded ${REVIEW_TO}s"
  v="$(verdict "$PR" "$start" "$end" "$head")" || terminal review-unbound "no unedited 'verdict:' comment naming head $head was posted between $start and $end"
  [ "$(remote_head)" = "$head" ] || terminal review-unbound "head moved during review"
  say "verdict: $v (reviewed $head)"
  [ "$v" = approve ] && break
  FINDINGS="$STATE/verdict-body.md"
  over_ceiling && terminal cost-spent "\$$COST exceeds the \$$COST_CEIL ceiling"
done

CI="$( [ -n "$PR" ] && ci_status "$PR" || echo none )"; say "ci: $CI (read once for the report; the checks that gate a round ran here)"
[ -n "$PR" ] && "$GH" pr comment "$PR" --body "second-shift run $RUN_ID: $ROUND round(s), \$$COST, CI $CI" >/dev/null 2>&1 || true
[ "${v:-}" = approve ] && terminal approved "PR #$PR approved at $head after $ROUND round(s), \$$COST"
terminal rounds-spent "$MAX_ROUNDS rounds without an approve (cost \$$COST)"
