#!/usr/bin/env bash
# run-selftest.sh — drives run.sh through every terminal it can reach, with a fake `claude`
# and a fake `gh`. The invariants guarded here are the three adjudication properties the shrink
# keeps: the checks are run by the scheduler from the record's FIRST commit (a build cannot change
# what runs against it), the head must move every round, and a verdict counts only if it is an
# unedited comment naming the current head and posted inside the review session's time window.
# The old liveness scenario composes against the milestone gate; run.sh replaces that path, so
# this is its scenario.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SCRIPT_DIR/run.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/run-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x

# ---- fakes ----
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# state dir: $FAKE_GH — files: state, labels, prs, comments.json (array), cost-comments
S="$FAKE_GH"; sub="$1 $2"; path="${2:-}"; shift 2
case "$sub" in
  "issue view")  case "$*" in *state*) cat "$S/state" ;; *labels*) cat "$S/labels" 2>/dev/null ;; esac ;;
  "issue edit")  add=""; rm=""; while [ $# -gt 0 ]; do case "$1" in --add-label) add="$2"; shift 2;; --remove-label) rm="$2"; shift 2;; *) shift;; esac; done
                 [ -n "$add" ] && echo "$add" >> "$S/labels"; [ -n "$rm" ] && { grep -vx "$rm" "$S/labels" > "$S/l.tmp"; mv "$S/l.tmp" "$S/labels"; } ;;
  "issue comment") echo "$*" >> "$S/issue-comments" ;;
  "pr list")     cat "$S/prs" 2>/dev/null ;;
  "pr checks")   echo '[]' ;;
  "pr comment")  echo "$*" >> "$S/cost-comments" ;;
  "repo view")   echo "o/r" ;;
  "api -X")      # PATCH repos/o/r/pulls/7 -F body=@<file>
                 for a in "$@"; do case "$a" in body=@*) cp "${a#body=@}" "$S/pr-body.md" ;; esac; done ;;
  api*)          case "$path" in *comments*) cat "$S/comments.json" ;; *pulls*) echo '{"body":"built-by: fake"}' ;; esac ;;
  *) echo "fake gh: unhandled $sub $*" >&2; exit 1 ;;
esac
EOF
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# behaviors come one per line from $FAKE_CLAUDE_PLAN, consumed in order; cwd is the worktree.
S="$FAKE_GH"; n=$(cat "$S/calls" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$S/calls"
plan=$(sed -n "${n}p" "$FAKE_CLAUDE_PLAN"); prompt="${@: -1}"; printf '%s' "$prompt" > "$S/prompt-$n.txt"; printf '%s\n' "$@" > "$S/args-$n.txt"
branch=$(git rev-parse --abbrev-ref HEAD); cost="${FAKE_COST:-1}"
push() { echo "$n" >> work.txt; git add -A >/dev/null; git commit -qm "build $n"; git push -q origin "$branch"; }
case "$plan" in
  build-pr)        push; echo 7 > "$S/prs" ;;
  build-push-only) push ;;
  build-delete-test) git rm -q src/a.spec.ts; push; echo 7 > "$S/prs" ;;
  build-nothing)   : ;;
  review-approve|review-needs-work|review-wrong-sha)
    sha=$(git rev-parse "origin/$branch"); [ "$plan" = review-wrong-sha ] && sha=deadbeef
    v=approve; [ "$plan" = review-needs-work ] && v=needs-work
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg b "verdict: $v"$'\n'"reviewed: $sha"$'\n'"| D-1 | honored |" --arg t "$ts" '. + [{body:$b,created_at:$t,updated_at:$t}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json" ;;
  review-silent)   : ;;
esac
printf '{"subtype":"success","total_cost_usd":%s,"num_turns":3,"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"ls /"}}]}\n' "$cost"
EOF
chmod +x "$T/bin/gh" "$T/bin/claude"

# ---- fixture: a bare origin, a main checkout with config + record, an empty worktree root ----
fixture() { # fixture <case> [checks-line] [extra-record] — sets $d and the env
  local c="$1" chk="${2-- true}" extra="${3:-}"; d="$T/$c"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/main" 2>/dev/null
  git -C "$d/main" symbolic-ref HEAD refs/heads/main
  mkdir -p "$d/main/src" "$d/main/.claude/pipeline-state"
  echo "x" > "$d/main/src/a.spec.ts"; echo "y" > "$d/main/src/a.ts"
  local dflt='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}'
  printf '%s\n' "${FIXTURE_CONFIG:-$dflt}" > "$d/main/.claude/second-shift.config.json"
  printf '%s\n' ".claude/" > "$d/main/.gitignore"
  git -C "$d/main" add -A && git -C "$d/main" commit -qm init && git -C "$d/main" push -q -u origin main 2>/dev/null
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  printf '# record\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n\n## Checks\n\n%s\n%s\n' "$chk" "$extra" > "$d/main/.claude/pipeline-state/42-ledger.md"
  export FAKE_GH="$d/gh"; mkdir -p "$FAKE_GH"; echo OPEN > "$FAKE_GH/state"; echo '[]' > "$FAKE_GH/comments.json"; : > "$FAKE_GH/prs"
  printf 'ready-for-dev\nopus\n' > "$FAKE_GH/labels"
  export FAKE_CLAUDE_PLAN="$d/plan"; : > "$FAKE_CLAUDE_PLAN"
  export RUN_WORKTREE_ROOT="$d/wt" RUN_CLAUDE="$T/bin/claude" RUN_GH="$T/bin/gh" SECOND_SHIFT_CONFIG="$d/main/.claude/second-shift.config.json"
}
run_case() { # run_case <dir> <args...> -> stdout in $OUT, terminal in $TERM_SLUG
  local d="$1"; shift
  OUT="$( cd "$d/main" && bash "$RUN" 42 "$@" 2>&1 )"; RC=$?
  TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
}
expect() { [ "$TERM_SLUG" = "$1" ] && ok "$2 -> $1" || { bad "$2: expected terminal $1, got '$TERM_SLUG'"; printf '%s\n' "$OUT" | tail -n 6 | sed 's/^/       /'; }; }

echo "[run-selftest] run.sh terminals and adjudication invariants"

# (a) happy path: build opens a PR, review approves the head inside the window
fixture a; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(a) build-pr + review-approve"
[ "$RC" -eq 0 ] && ok "(a) exit 0 on approved" || bad "(a) exit $RC on approved"
grep -qx in-progress "$FAKE_GH/labels" && ! grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(a) queue label swapped for the claimed label" || bad "(a) label swap wrong: $(tr '\n' ' ' < "$FAKE_GH/labels")"
grep -q 'approved' "$FAKE_GH/issue-comments" && ok "(a) closing comment on the issue" || bad "(a) no closing comment"
grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(a) claim marker in the old lane's shape" || bad "(a) claim marker missing"
[ ! -d "$d/wt/42" ] && ok "(a) worktree torn down on approve" || bad "(a) worktree left after approve"
grep -q 'Closes #42' "$FAKE_GH/prompt-1.txt" && grep -q 'READY (not draft)' "$FAKE_GH/prompt-1.txt" && ok "(a) build prompt asks for a ready PR that closes the ticket" || bad "(a) PR conventions missing from the build prompt"
grep -q 'AskUserQuestion' "$FAKE_GH/args-1.txt" && ! grep -q 'editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(a) keyboard tools disallowed, no jira strip under github" || bad "(a) disallowed-tools list wrong"
grep -q 'DECLARE THE PIPELINE DEFAULT PANEL' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt declares the panel" || bad "(a) panel declaration missing"
grep -q 'models: build claude-opus-5 (label), review claude-opus-5 (default)' <<<"$OUT" && ok "(a) build model read from the opus label" || bad "(a) model not read from the label"
first=$(git -C "$d/origin.git" log --format=%s --reverse main..second-shift/42 | head -n 1)
[ "$first" = "docs: decision record for #42" ] && ok "(a) the record is the branch's first commit" || bad "(a) first commit is '$first'"
grep -q '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md" 2>/dev/null && grep -q 'built-by: fake' "$FAKE_GH/pr-body.md" && ok "(a) run block written into the PR body, original body kept" || bad "(a) no run block in the PR body"
grep -qE '^[|] review-1 [|] 3 [|] [$]1 [|]' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(a) per-session cost rows in the block" || bad "(a) per-session rows missing"
grep -q 'ls /' "$d/main/.claude/pipeline-state/run-42/review-1.prompt" && ok "(a) build denials reach the review input" || bad "(a) denials missing from review input"

# (b) needs-work then approve: two rounds, findings reach the round-2 build prompt
fixture b; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(b) needs-work, fix, approve"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-3.txt" && ok "(b) round-2 build prompt carries the findings" || bad "(b) findings not in round-2 prompt"
printf '%s\n' "$OUT" | grep -q '2 round' && ok "(b) two rounds counted" || bad "(b) round count wrong"

# (c) no PR after the build
fixture c; printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-no-pr "(c) push without a PR"

# (d) head did not move
fixture d; printf 'build-nothing\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-inflight "(d) build changed nothing"

# (e) verdict names the wrong head
fixture e; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(e) verdict for another sha"

# (f) a stale approve for THIS head, posted before the review window, must not count
fixture f; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
# the review posts a correct approve for the right head; the gh wrapper backdates it on read, so the
# only thing wrong with it is WHEN it was posted
cat > "$T/bin/gh-backdate" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/issues/7/comments" ]; then jq 'map(.created_at = "2020-01-01T00:00:00Z" | .updated_at = "2020-01-01T00:00:00Z")' "\$FAKE_GH/comments.json"; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-backdate"; RUN_GH="$T/bin/gh-backdate" run_case "$d"; expect review-unbound "(f) a correct approve posted outside the review window is rejected"

# (g) an edited verdict comment must not count
fixture g; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-edit" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/issues/7/comments" ]; then jq 'map(.updated_at = "2099-01-01T00:00:00Z")' "\$FAKE_GH/comments.json"; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-edit"; RUN_GH="$T/bin/gh-edit" run_case "$d"; expect review-unbound "(g) edited verdict comment is rejected"

# (h) checks red, then spent
fixture h "- false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"
RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(h) red checks spend their own counter"
[ "$(cat "$FAKE_GH/calls")" = 2 ] && ok "(h) no review was spawned on red checks" || bad "(h) review spawned on red checks ($(cat "$FAKE_GH/calls") calls)"

# (i) the checks list is read from the FIRST commit: a build that rewrites '## Checks' to '- true' still runs '- false'
fixture i "- false"; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/claude-rewrite" <<EOF
#!/usr/bin/env bash
sed -i.bak 's/^- false$/- true/' docs/plans/main-42-decisions.md 2>/dev/null; rm -f docs/plans/main-42-decisions.md.bak
exec "$T/bin/claude" "\$@"
EOF
chmod +x "$T/bin/claude-rewrite"; RUN_CLAUDE="$T/bin/claude-rewrite" RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(i) a build cannot change what runs against it"

# (j) zero checks declared is not green
fixture j ""; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(j) no '## Checks' lines refuses to read as green"

# (k) a deleted test file reaches the reviewer
fixture k; printf 'build-delete-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
grep -q 'a.spec.ts' "$d/main/.claude/pipeline-state/run-42/review-1.prompt" && ok "(k) deleted spec named in the review input" || bad "(k) deleted spec not surfaced"

# (l) claimed elsewhere, ticket closed, cost ceiling, no record
fixture l; echo in-progress > "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(l1) in-progress label without --resume"
[ ! -d "$d/wt/42" ] && ok "(l1) no worktree created" || bad "(l1) worktree created despite refusal"
fixture l2; echo CLOSED > "$FAKE_GH/state"; run_case "$d"; expect ticket-closed "(l2) closed ticket"
fixture l3; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=60 RUN_COST_CEILING=100 run_case "$d"; expect cost-spent "(l3) cost ceiling"
fixture l4; rm "$d/main/.claude/pipeline-state/42-ledger.md"; run_case "$d"; expect env-no-record "(l4) no intake record"
fixture l5; run_case "$d" --dry-run; expect dry-run "(l5) dry-run spawns nothing"
[ ! -f "$FAKE_GH/calls" ] && ok "(l5) no claude call on dry-run" || bad "(l5) claude called on dry-run"

# (n) queue discipline and sizing, as the old lane enforced them
fixture n1; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n1) no queue label"
fixture n2; printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n2) blocker label refuses pickup"
fixture n3; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d"; expect usage-model "(n3) unlabeled ticket is not sized here"
fixture n4; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --model claude-sonnet-5 --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(n4) --model overrides the missing label"
grep -q 'models: build claude-sonnet-5 (flag), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(n4) override models logged" || bad "(n4) override not applied"
fixture n5; printf '{"tracker":{"type":"github","branchPrefix":"claude/acme-"},"paths":{"plansDir":"docs/plans"}}\n' > "$d/main/.claude/second-shift.config.json"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/claude/acme-42 >/dev/null && ok "(n5) branch honors tracker.branchPrefix" || bad "(n5) no claude/acme-42 on origin: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"

# (p) parity with orchestrate.sh: tool strip, config commands, exit codes, flags, prefix refusal
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture p1
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model claude-sonnet-5
expect usage-key "(p1) jira key pattern refuses a numeric key"
FIXTURE_CONFIG='{"tracker":{"type":"github","writes":false,"branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}' fixture p2
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(p2) writes:false run"
grep -q 'mcp__atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && grep -q 'mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue' "$FAKE_GH/args-2.txt" && ok "(p2) tracker.writes:false strips the Atlassian write tools in both sessions" || bad "(p2) write tools not stripped"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"false","typecheck":null,"test":"true"}}}' fixture p3 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(p3) configured commands.* run as checks even with no '## Checks'"
grep -q 'RED: false' "$d/main/.claude/pipeline-state/run-42/checks-1.log" && grep -q 'ok: true' "$d/main/.claude/pipeline-state/run-42/checks-1.log" && ok "(p3) lint red, test green, typecheck null skipped" || bad "(p3) check log wrong"
FIXTURE_CONFIG='{"tracker":{"type":"github"},"paths":{"plansDir":"docs/plans"}}' fixture p4; run_case "$d"; expect env-branch-prefix "(p4) no prefix configured and no dominant remote prefix: refuse, never guess"
[ "$RC" -eq 2 ] && ok "(p4) exit 2" || bad "(p4) exit $RC"
fixture p5; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 3 ] && ok "(p5) not-queued exits 3 (resumable)" || bad "(p5) not-queued exit $RC"
fixture p6; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; [ "$RC" -eq 4 ] && ok "(p6) rounds-spent exits 4" || bad "(p6) rounds-spent exit $RC"
fixture p7; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; [ "$RC" -eq 5 ] && ok "(p7) review-unbound exits 5" || bad "(p7) review-unbound exit $RC"
fixture p8; echo CLOSED > "$FAKE_GH/state"; run_case "$d"; [ "$RC" -eq 7 ] && ok "(p8) ticket-closed exits 7" || bad "(p8) ticket-closed exit $RC"
fixture p9; run_case "$d" --review-model claude-sonnet-5 --dry-run; [ "$RC" -eq 2 ] && ok "(p9) --review-model without --review-model-basis is refused" || bad "(p9) exit $RC"
fixture p10; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model claude-sonnet-5 --model-basis "test" --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(p10) orchestrate.sh's --build-model and basis flags are accepted"
grep -q 'models: build claude-sonnet-5 (test), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(p10) bases logged" || bad "(p10) bases not logged"
fixture p11; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && git checkout -q -b bump && echo z >> src/a.ts && git commit -qam "base moves" && git push -q origin bump:main && git checkout -q main && git reset -q --hard origin/main ) 2>/dev/null
# the branch will touch work.txt only, so a base move on src/a.ts must NOT expire it
run_case "$d"; expect approved "(p11) a base move outside the branch's files does not expire the premise"

# (m) rounds spent
fixture m; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; expect rounds-spent "(m) two needs-work rounds"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
