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
  "pr checks")   [ -f "$S/ci-red" ] && echo '[{"name":"ci","state":"FAILURE"}]' || echo '[]' ;;
  "pr comment")  echo "$*" >> "$S/cost-comments" ;;
  "pr view")     case "$*" in *body*) jq -n --rawfile b "$S/pr-created-body.txt" --argjson d "$([ -f "$S/draft" ] && echo true || echo false)" '{body:$b, isDraft:$d}' ;; *) echo "https://x/pr/7" ;; esac ;;
  "repo view")   echo "o/r" ;;
  "api -X")      # PATCH repos/o/r/pulls/7 -F body=@<file> | POST .../labels --input - | DELETE .../labels/<name>
                 verb="$1"; p="$2"
                 case "$verb $p" in
                   "POST "*labels*) jq -r '.labels[]' >> "$S/labels"; jq -Rn '[inputs] | map({name: .})' < "$S/labels" ;;
                   "DELETE "*labels/*) grep -vx "${p##*/}" "$S/labels" > "$S/l.tmp"; mv "$S/l.tmp" "$S/labels" ;;
                   *) for a in "$@"; do case "$a" in body=@*) cp "${a#body=@}" "$S/pr-body.md" ;; esac; done ;;
                 esac ;;
  "api user")    echo tester ;;
  api*)          case "$path" in *comments*) cat "$S/comments.json" ;; *pulls*) echo '{"body":"built-by: fake"}' ;; *) echo '{}' ;; esac ;;
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
openpr() { # body as the prompt instructs: built-by line, the record link, then Closes (under the Jira heading when bracketed)
  rid=$(grep -oE 'built-by: second-shift run [^ ]+' "$S/prompt-$n.txt" | head -n 1)
  rec=$(grep -oE 'The record is committed at [^;]+' "$S/prompt-$n.txt" | head -n 1 | sed 's/^The record is committed at //')
  key=$(grep -oE "Closes (#[0-9]+|\[[^]]+\])" "$S/prompt-$n.txt" | head -n 1)
  case "${FAKE_CLOSES:-}" in lower) key="closes #42" ;; esac
  { printf '%s\n\nrecord: %s\n\n' "${rid:-built-by: second-shift run ?}" "${rec:-?}"; case "$key" in *"["*) printf '### Jira Items\n%s\n' "$key" ;; *) printf '%s\n' "${key:-Closes #?}" ;; esac; } > "$S/pr-created-body.txt"; echo 7 > "$S/prs"
}
case "$plan" in
  build-pr)        push; openpr ;;
  build-pr-draft)  push; openpr; touch "$S/draft" ;;
  build-pr-nobody) push; echo 7 > "$S/prs"; echo "just a summary" > "$S/pr-created-body.txt" ;;
  build-push-only) push ;;
  build-delete-test) git rm -q src/a.spec.ts; push; openpr ;;
  build-nothing)   : ;;
  build-sleep)     sleep 60 ;;
  build-pr-ready)  touch "$S/undraft"; rm -f "$S/draft" ;;
  build-pr-jira-outside) push; rid=$(grep -oE 'built-by: second-shift run [^ ]+' "$S/prompt-$n.txt" | head -n 1); rec=$(grep -oE 'The record is committed at [^;]+' "$S/prompt-$n.txt" | sed 's/^The record is committed at //')
                   printf '%s\n\nrecord: %s\n\nCloses [GH-42]\n\n### Jira Items\n(nothing)\n' "$rid" "$rec" > "$S/pr-created-body.txt"; echo 7 > "$S/prs" ;;
  build-pr-close)  push; openpr; echo CLOSED > "$S/state" ;;
  review-crash)    printf '{"subtype":"error_during_execution","total_cost_usd":0}\n'; exit 1 ;;
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
# shellcheck disable=SC2012  # run ids are plain ASCII; sorted ls is the simplest "latest"
SD() { ls -d "$d/main/.claude/pipeline-state/run-42"/*/ 2>/dev/null | sort | tail -n 1 | sed 's#/$##'; }
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
grep -q '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md" 2>/dev/null && grep -q 'built-by: fake' "$FAKE_GH/pr-body.md" && grep -q '| approved |' "$FAKE_GH/pr-body.md" && ok "(a) run block written into the PR body, original body kept" || bad "(a) no run block in the PR body"
grep -qE '^[|] review-1[.]1 [|] 3 [|] [$]1 [|]' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(a) per-session cost rows in the block" || bad "(a) per-session rows missing"
grep -q 'ls /' "$(SD)/review-1.1.prompt" && ok "(a) build denials reach the review input" || bad "(a) denials missing from review input"

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
grep -q 'a.spec.ts' "$(SD)/review-1.1.prompt" && ok "(k) deleted spec named in the review input" || bad "(k) deleted spec not surfaced"

# (l) claimed elsewhere, ticket closed, cost ceiling, no record
fixture l; echo in-progress > "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(l1) in-progress label without --resume"
[ ! -d "$d/wt/42" ] && ok "(l1) no worktree created" || bad "(l1) worktree created despite refusal"
fixture l2; echo CLOSED > "$FAKE_GH/state"; run_case "$d"; expect env-ticket-closed "(l2) a ticket closed at launch is a preflight refusal"
[ "$RC" -eq 2 ] && ok "(l2) exits 2, like every preflight refusal" || bad "(l2) exit $RC"
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
grep -q 'mcp__atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && grep -q 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && grep -q 'mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue' "$FAKE_GH/args-2.txt" && ok "(p2) tracker.writes:false strips the Atlassian write tools in both sessions" || bad "(p2) write tools not stripped"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"false","typecheck":null,"test":"true"}}}' fixture p3 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(p3) configured commands.* run as checks even with no '## Checks'"
grep -q 'RED: false' "$(SD)/checks-1.1.log" && grep -q 'ok: true' "$(SD)/checks-1.1.log" && ok "(p3) lint red, test green, typecheck null skipped" || bad "(p3) check log wrong"
FIXTURE_CONFIG='{"tracker":{"type":"github"},"paths":{"plansDir":"docs/plans"}}' fixture p4; run_case "$d"; expect env-branch-prefix "(p4) no prefix configured and no dominant remote prefix: refuse, never guess"
[ "$RC" -eq 2 ] && ok "(p4) exit 2" || bad "(p4) exit $RC"
fixture p5; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 3 ] && ok "(p5) not-queued exits 3 (resumable)" || bad "(p5) not-queued exit $RC"
fixture p6; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; [ "$RC" -eq 4 ] && ok "(p6) rounds-spent exits 4" || bad "(p6) rounds-spent exit $RC"
fixture p7; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; [ "$RC" -eq 5 ] && ok "(p7) review-unbound exits 5" || bad "(p7) review-unbound exit $RC"
fixture p8; printf 'build-pr-close\nreview-needs-work\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect ticket-closed "(p8) a ticket closed MID-RUN expires the premise"
[ "$RC" -eq 7 ] && ok "(p8) mid-run closed exits 7" || bad "(p8) exit $RC"
fixture p9; run_case "$d" --review-model claude-sonnet-5 --dry-run; [ "$RC" -eq 2 ] && ok "(p9) --review-model without --review-model-basis is refused" || bad "(p9) exit $RC"
fixture p10; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model claude-sonnet-5 --model-basis "test" --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(p10) orchestrate.sh's --build-model and basis flags are accepted"
grep -q 'models: build claude-sonnet-5 (test), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(p10) bases logged" || bad "(p10) bases not logged"
fixture p11; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && git checkout -q -b bump && echo z >> src/a.ts && git commit -qam "base moves" && git push -q origin bump:main && git checkout -q main && git reset -q --hard origin/main ) 2>/dev/null
# the branch will touch work.txt only, so a base move on src/a.ts must NOT expire it
run_case "$d"; expect approved "(p11) a base move outside the branch's files does not expire the premise"

# (q) round-two parity: exit codes for env refusals, re-entry by marker, evidence per attempt,
#     the old cost block's terminator, fail-closed staleness, the jira read allowlist, config caps
fixture q1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm -rf "$d/origin.git"; run_case "$d"
[ "$RC" -eq 2 ] && ok "(q1) an environment refusal exits 2 (was demoted to 1)" || bad "(q1) env refusal exit $RC ($TERM_SLUG)"
fixture q2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
echo 'x <!-- stage: lean-claimed --> y' >> "$FAKE_GH/issue-comments"; jq '. + [{body:"<!-- run_id: old -->\n<!-- stage: lean-claimed -->",user:{login:"tester",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect approved "(q2) claimed label + lane marker re-enters without --resume"
grep -q 'approved' "$FAKE_GH/issue-comments" && ok "(q2) closing comment posted on a re-entered run" || bad "(q2) no closing comment on re-entry"
fixture q3 "- false"; printf 'build-pr\nbuild-push-only\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=3 run_case "$d"; expect checks-red-spent "(q3) three red attempts"
[ -f "$(SD)/build-1.1.json" ] && [ -f "$(SD)/build-1.3.json" ] && ok "(q3) every attempt keeps its own evidence file" || bad "(q3) attempt evidence overwritten"
fixture q4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-oldblock" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\n\\n<!-- pipeline-cost-block -->\\nold block line\\nCache-hit rate: 50%%\\n\\nKEEP THIS LINE\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-oldblock"; RUN_GH="$T/bin/gh-oldblock" run_case "$d"; expect approved "(q4) run against a PR carrying the OLD lane's cost block"
grep -q 'KEEP THIS LINE' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && ok "(q4) old block replaced up to its Cache-hit terminator; the body below it survives" || bad "(q4) body strip wrong: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-200)"
fixture q5; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; ( cd "$d/main" && git remote set-url origin /nonexistent ) ; run_case "$d"
# the record push fails first on a dead remote, which is an env refusal; the staleness arm is exercised below via a fetch that fails mid-run
[ "$RC" -eq 2 ] && ok "(q5) dead remote is an environment refusal, not a pass" || bad "(q5) dead remote exit $RC ($TERM_SLUG)"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[a-z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture q6
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/gh-42-ledger.md"
OUT="$( cd "$d/main" && bash "$RUN" gh-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(q6) jira run with a key that matches keyPattern"
grep -q 'mcp__atlassian' "$FAKE_GH/args-1.txt" && grep -q 'mcp__plugin_atlassian_atlassian' "$FAKE_GH/args-1.txt" && grep -q 'mcp__claude_ai_Atlassian_Rovo' "$FAKE_GH/args-1.txt" && grep -q 'mcp__atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(q6) jira build may READ the tracker (server allowed) while writes stay disallowed" || bad "(q6) jira allowlist wrong"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"maxRounds":1,"costCeilingUsd":0.5}}' fixture q7
printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect cost-spent "(q7) config run.costCeilingUsd honored"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":null,"typecheck":null,"test":null,"allowUnverified":true}}}' fixture q8 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(q8) zero checks pass only when allowUnverified is declared"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["false"]},{"name":"docs","when":["docs/**"],"commands":["false"]}]}}}' fixture q9 ""
printf 'build-delete-test\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
grep -q 'RED: false' "$(SD)/checks-1.1.log" && [ "$(grep -c 'false' "$(SD)/checks-1.1.log")" = 1 ] && ok "(q9) extraLanes run only when a changed file matches their when-globs (src/ matched, docs/ did not)" || bad "(q9) when-globs wrong: $(grep -c false "$(SD)/checks-1.1.log") false lanes ran"
fixture q10; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model opus --review-model opus; expect approved "(q10) opus/sonnet short forms accepted; opus review needs no basis"
FIXTURE_CONFIG='{"tracker":{"type":"gitlab","branchPrefix":"x/"},"paths":{"plansDir":"docs/plans"}}' fixture q11; run_case "$d"; expect env-tracker-type "(q11) an unknown tracker.type is refused, never the quieter arm"

# (r) round-three parity: marker read is a checked match and body-anchored, lanes[] setup steps,
#     -h, explicit --max-rounds beats config, SEAM_SCRUB on lane commands, config dir reachable
fixture r1; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
jq '. + [{body:"someone wrote: the marker is <!-- stage: lean-claimed --> in the old lane",created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect claimed-elsewhere "(r1) a comment merely quoting the marker inline does not re-enter"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","commands":["false"]}],"lint":"true"}}}' fixture r2 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(r2) lanes[] setup steps run and gate"
[ "$(sed -n '1p' "$(SD)/checks-1.1.log")" = "RED (setup, aborting the rest): false" ] && ok "(r2) setup lane ran FIRST" || bad "(r2) order wrong: $(head -2 "$(SD)/checks-1.1.log" | tr '\n' '|')"
fixture r3; OUT="$( cd "$d/main" && bash "$RUN" -h 2>&1 )"; RC=$?; [ "$RC" -eq 0 ] && grep -q '^# usage: run.sh' <<<"$OUT" && ok "(r3) -h prints usage and exits 0" || bad "(r3) -h exit $RC"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"maxRounds":1}}' fixture r4
printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 3; expect approved "(r4) an explicit --max-rounds 3 beats config run.maxRounds 1"
# shellcheck disable=SC2016  # the check line is meant to expand in the lane, not here
fixture r5 '- test -z "${SECOND_SHIFT_CONFIG:-}"'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(r5) lane commands run with the config seam scrubbed"
grep -q -- "--add-dir" "$FAKE_GH/args-1.txt" && grep -qF "$(cd "$(dirname "$SECOND_SHIFT_CONFIG")" && pwd)" "$FAKE_GH/args-1.txt" && ok "(r5) the config's directory is handed to the session via --add-dir" || bad "(r5) config dir not in --add-dir"

# (s) round-four parity: setup lanes fail fast, malformed lanes fail loudly, usage slugs, the full seam scrub
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","commands":["false"]}],"lint":"echo LINT-RAN"}}}' fixture s1 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(s1) a red setup lane"
! grep -q 'LINT-RAN' "$(SD)/checks-1.1.log" && grep -q 'aborting the rest' "$(SD)/checks-1.1.log" && ok "(s1) setup lane failure aborts before lint runs (fail-fast)" || bad "(s1) lint ran after a red setup lane"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup"}],"lint":"true"}}}' fixture s2 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-config-lanes "(s2) a lane with no commands fails loudly, never silently contributes nothing"
[ "$RC" -eq 2 ] && ok "(s2) exits 2" || bad "(s2) exit $RC"
[ ! -f "$FAKE_GH/calls" ] && ok "(s2) refused before any build was spawned" || bad "(s2) a build was spawned on a malformed config"
fixture s3; OUT="$( cd "$d/main" && bash "$RUN" 42 --bogus 2>&1 )"; RC=$?; grep -q '^terminal: usage-unknown-option$' <<<"$OUT" && [ "$RC" -eq 2 ] && ok "(s3) usage refusals carry their slug line" || bad "(s3) no usage slug (rc=$RC)"
# shellcheck disable=SC2016  # the check line expands in the lane, not here
fixture s4 '- test -z "${BRANCH_PREFIX:-}${KEY_PATTERN:-}${SECOND_SHIFT_REPO_ROOT:-}"'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; BRANCH_PREFIX=leak KEY_PATTERN=leak SECOND_SHIFT_REPO_ROOT=leak run_case "$d"; expect approved "(s4) the gate's full seam list is scrubbed from lane commands"

# (t) round-five parity: configured label names are WRITTEN, not just read; the no-bot claim path;
#     an unreadable tracker fails closed; every usage slug
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"queue":"todo","claimed":"doing"}},"paths":{"plansDir":"docs/plans"}}' fixture t1
printf 'todo\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(t1) run with configured label names"
grep -qx doing "$FAKE_GH/labels" && ! grep -qx todo "$FAKE_GH/labels" && ok "(t1) the configured queue label was removed and the configured claimed label applied" || bad "(t1) labels after claim: $(tr '\n' ' ' < "$FAKE_GH/labels")"
fixture t2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
# no bot configured, RUN_GH unset: the plain-gh swap must be taken (the fake sits on PATH as `gh`)
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(t2) a consumer with no bot configured can run (plain gh claim swap)"
fixture t3; : > "$FAKE_GH/state"; cat > "$T/bin/gh-dead" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue view" ] && [[ "\$*" == *state* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-dead"; RUN_GH="$T/bin/gh-dead" run_case "$d"; expect env-tracker-unreadable "(t3) an unreadable tracker is a refusal, never read as OPEN"
fixture t4; OUT="$( cd "$d/main" && bash "$RUN" 2>&1 )"; grep -q '^terminal: usage-missing-issue$' <<<"$OUT" && ok "(t4) usage-missing-issue slug" || bad "(t4) missing-issue slug absent"
OUT="$( cd "$d/main" && bash "$RUN" 42 --max-rounds 0 2>&1 )"; grep -q '^terminal: usage-max-rounds$' <<<"$OUT" && ok "(t4) usage-max-rounds slug" || bad "(t4) max-rounds slug absent"
OUT="$( cd "$d/main" && bash "$RUN" 42 --review-model sonnet 2>&1 )"; grep -q '^terminal: usage-review-model-basis$' <<<"$OUT" && ok "(t4) usage-review-model-basis slug" || bad "(t4) review-model-basis slug absent"

# (u) round-six parity: no blind body replace, a broken enabled bot refuses, staleness anchored at
#     the branch point on re-entry, a dead review session, a failed marker post
fixture u1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-nobody" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-nobody"; RUN_GH="$T/bin/gh-nobody" run_case "$d"; expect approved "(u1) run whose PR-body read fails"
[ ! -f "$FAKE_GH/pr-body.md" ] && grep -q 'NOT written' <<<"$OUT" && ok "(u1) an unreadable PR body is never replaced blind" || bad "(u1) body was PATCHed over an unread body"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"wrapperPath":"/nonexistent/gh-as-bot.sh"}},"paths":{"plansDir":"docs/plans"}}' fixture u2
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" env -u RUN_GH -u GH_BOT bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect env-bot "(u2) bot enabled but its wrapper missing is a refusal, never a silent write as the operator"
fixture u3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(u3) first run"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main && echo moved >> work.txt && git add work.txt && git commit -qm "base moves onto the branch's file" && git push -q origin main ) 2>/dev/null
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect staleness-expired "(u3) on re-entry the base move since the BRANCH POINT is seen"
fixture u4; printf 'build-pr\nreview-crash\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(u4) a review session that died is not a verdict"
fixture u5; cat > "$T/bin/gh-nocomment" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue comment" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-nocomment"; RUN_GH="$T/bin/gh-nocomment" run_case "$d"; expect env-claim-failed "(u5) a claim marker that could not be posted is a refusal"

# (v) round-seven parity: the working-bot path end to end, jira keys lowercased in the branch, the
#     marker's author filter, must-show absent is red, every lane named before the first diff
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT"}},"paths":{"plansDir":"docs/plans"}}' fixture v1
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(v1) a consumer WITH a bot: claim through claim-issue.sh, marker and body through the wrapper"
grep -qx in-progress "$FAKE_GH/labels" && ! grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(v1) claim-issue.sh swapped the labels through the bot" || bad "(v1) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(v1) marker posted through the bot" || bad "(v1) no marker"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture v2
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
OUT="$( cd "$d/main" && bash "$RUN" GH-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(v2) jira key"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/jdoe/gh-42 >/dev/null && ok "(v2) the jira key is lowercased in the branch name, as the adapter documents" || bad "(v2) branches: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
fixture v3; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
jq '. + [{body:"<!-- run_id: x -->\n<!-- stage: lean-claimed -->",user:{login:"stranger",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect claimed-elsewhere "(v3) a marker posted by another account is not the lane's claim"
fixture v4; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
jq '. + [{body:"<!-- run_id: x -->\n<!-- stage: lean-claimed -->",user:{login:"some-app[bot]",type:"Bot"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect approved "(v4) a Bot-authored marker re-enters"
printf 'x' > "$T/px.png"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {mustShow} = ok\"}}}" fixture v5 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(v5) route smoke: render, non-empty image, must-show satisfied"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture v6 "- true" $'\n## Design frames\n\n| RS | route | state | frame |\n| --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(v6) a frames row with no must-show value is red, never silently green (D-4)"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["e2e-runner --all"]}]}}}' fixture v7 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
grep -q 'e2e-runner --all' "$FAKE_GH/prompt-1.txt" && grep -q 'Bash(e2e-runner\*)' "$FAKE_GH/args-1.txt" && ok "(v7) a when-globbed lane is named in the round-1 prompt and allowlist before any diff exists" || bad "(v7) lane missing from the prompt or allowlist"

# (w) round-eight parity: PR conventions asserted, a draft is no PR, a stopped run still leaves its
#     block, claimed-elsewhere exits 2, dry-run lists every lane, second run's block is its own
fixture w1; printf 'build-pr-draft\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(w1) a draft PR is a finding the build gets to fix, then spent"
grep -qi 'draft' "$FAKE_GH/prompt-2.txt" && ok "(w1) the draft finding reaches the next build prompt" || bad "(w1) no draft finding in prompt 2"
grep -q '| checks-red-spent |' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(w1) the run block is written onto the draft PR" || bad "(w1) no run block on the draft"
fixture w1b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_CLOSES=lower run_case "$d"; expect approved "(w1b) a lowercase 'closes #42' is accepted, as the old gate matched it"
fixture w2; printf 'build-pr-nobody\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(w2) a PR body without built-by/Closes is sent back, then spent"
grep -q "Closes #42" "$FAKE_GH/prompt-2.txt" && ok "(w2) the convention finding reaches the next build prompt" || bad "(w2) finding not in the next prompt"
fixture w3; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(w3) stopped after a PR exists"
grep -q '| review-unbound |' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(w3) a stopped run still writes its run block into the PR body" || bad "(w3) no run block on a stopped run"
fixture w4; echo in-progress > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 2 ] && ok "(w4) claimed-elsewhere spawned nothing and exits 2" || bad "(w4) exit $RC"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["e2e-runner --all"]}]}}}' fixture w5 ""
run_case "$d" --dry-run; grep -q 'e2e-runner --all' <<<"$OUT" && ok "(w5) dry-run names the when-globbed lane" || bad "(w5) dry-run omits the lane"
fixture w6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w6) first run"
first_block="$(SD)/pr-body.md"; printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main ) ; run_case "$d" --resume; expect approved "(w6) second run on the same ticket"
[ "$(grep -c '^| build-' "$(SD)/pr-body.md")" = 1 ] && [ "$(SD)/pr-body.md" != "$first_block" ] && ok "(w6) the second run's block lists only its own sessions" || bad "(w6) block rows: $(grep -c '^| build-' "$(SD)/pr-body.md")"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"queue":"ready.for.dev","claimed":"in-progress"}},"paths":{"plansDir":"docs/plans"}}' fixture w7
printf 'ready-for-dev\nopus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(w7) a queue label with regex metacharacters is matched exactly (ready-for-dev is not ready.for.dev)"

# (x) round-ten parity: TERM exits 143 and kills the session, the ready probe gates only a render,
#     a PR-only fix does not dead-end, jira Closes outside its heading, ci red reported
fixture x1; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && exec bash "$RUN" 42 > "$d/x1.log" 2>&1 ) & rp=$!
until grep -q 'round 1 of' "$d/x1.log" 2>/dev/null; do sleep 0.5; done; sleep 1.5
kill -TERM "$rp"; wait "$rp"; xrc=$?
[ "$xrc" -eq 143 ] && ok "(x1) TERM exits 143" || bad "(x1) TERM exit $xrc"
sleep 1; if pgrep -f "$T/bin/claude" >/dev/null 2>&1 || pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(x1) the session outlived the scheduler"; pkill -f "$T/bin/claude" 2>/dev/null; pkill -f 'sleep 60' 2>/dev/null; else ok "(x1) the session and its children were killed with the scheduler"; fi
grep -q 'claim left in place' "$d/x1.log" && grep -qx in-progress "$FAKE_GH/labels" && ok "(x1) the claim is left in place on TERM" || bad "(x1) claim state wrong after TERM"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","readyProbe":"http://127.0.0.1:9/"}}}' fixture x2 "- true" $'\nDesign: none — a wording change, nothing renders\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(x2) a readyProbe gates nothing on a ticket declared Design: none"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:9/\"}}}" fixture x3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(x3) a dead readyProbe stops an armed ticket before rendering"
[ "$RC" -eq 2 ] && ok "(x3) infra stop, exit 2, no attempt spent" || bad "(x3) exit $RC"
fixture x4; printf 'build-pr-draft\nbuild-pr-ready\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(x4) a PR-only fix (un-draft) is accepted without the head moving"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture x5
printf 'build-pr-jira-outside\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
OUT="$( cd "$d/main" && RUN_CHECKS_RED_MAX=2 bash "$RUN" GH-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect checks-red-spent "(x5) jira Closes outside its heading is a finding, as the old gate ruled"
fixture x6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; touch "$FAKE_GH/ci-red"; run_case "$d"; expect approved "(x6) CI is never waited on"
grep -q '| red |' "$FAKE_GH/pr-body.md" && ok "(x6) a red CI is reported in the run block" || bad "(x6) CI red not reported"

# (y) round-eleven parity: a provider repo's ticket declares its design state, the probe wants a 2xx/3xx,
#     a timed-out session is reaped, -h prints the whole table
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture y1
run_case "$d"; expect env-design-undeclared "(y1) on a design-provider repo a record with neither frames nor 'Design: none' is refused (#705's rule)"
[ ! -f "$FAKE_GH/calls" ] && ok "(y1) refused before any build" || bad "(y1) a build ran"
fixture y2; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=2 run_case "$d"; expect build-blocked "(y2) a build past its ceiling is stopped"
sleep 1; if pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(y2) the timed-out session's children outlived it"; pkill -f 'sleep 60' 2>/dev/null; else ok "(y2) the timed-out session and its children were reaped"; fi
port=$(( 20000 + RANDOM % 20000 )); ( cd "$T" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & hs=$!
until curl -s -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; do sleep 0.2; done
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:$port/missing\"}}}" fixture y3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(y3) an HTTP 404 from the readyProbe is not ready"
grep -q 'last reading: HTTP 404' <<<"$OUT" && ok "(y3) the refusal names the reading" || bad "(y3) reading not named"
kill "$hs" 2>/dev/null; wait "$hs" 2>/dev/null
fixture y4; OUT="$( cd "$d/main" && bash "$RUN" -h 2>&1 )"; grep -q '130 / 143' <<<"$OUT" && ok "(y4) -h prints the whole exit table" || bad "(y4) -h truncated"

# (m) rounds spent
fixture m; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; expect rounds-spent "(m) two needs-work rounds"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
