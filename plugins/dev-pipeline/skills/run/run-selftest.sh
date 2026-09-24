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
  build-sleep)     sleep 60; exit 143 ;;   # killed at its bound: a real session leaves no result JSON
  build-stubborn)  trap '' TERM; while :; do sleep 1; done ;;
  build-kill-remote) push; openpr; git remote set-url origin /nonexistent-remote ;;
  build-pr-ready)  touch "$S/undraft"; rm -f "$S/draft" ;;
  build-pr-jira-outside) push; rid=$(grep -oE 'built-by: second-shift run [^ ]+' "$S/prompt-$n.txt" | head -n 1); rec=$(grep -oE 'The record is committed at [^;]+' "$S/prompt-$n.txt" | sed 's/^The record is committed at //')
                   printf '%s\n\nrecord: %s\n\nCloses [GH-42]\n\n### Jira Items\n(nothing)\n' "$rid" "$rec" > "$S/pr-created-body.txt"; echo 7 > "$S/prs" ;;
  build-pr-close)  push; openpr; echo CLOSED > "$S/state" ;;
  build-pr-dirty)  push; openpr; echo uncommitted >> work.txt ;;
  build-commit-nopush) echo "$n" >> work.txt; git add -A >/dev/null; git commit -qm "local only $n" ;;
  build-skip-test) printf 'it.skip("x", () => {});\n' >> src/a.spec.ts; mkdir -p .github/workflows; echo 'on: push' > .github/workflows/ci.yml; push; openpr ;;
  review-crash)    printf '{"subtype":"error_during_execution","total_cost_usd":0}\n'; exit 1 ;;
  review-approve|review-needs-work|review-wrong-sha|review-approve-dirty|review-approve-and-push|review-needs-work-drop-base|review-needs-work-diverge)
    sha=$(git rev-parse "origin/$branch"); [ "$plan" = review-wrong-sha ] && sha=deadbeef
    v=approve; case "$plan" in review-needs-work*) v=needs-work ;; esac
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg b "verdict: $v"$'\n'"reviewed: $sha"$'\n'"| D-1 | honored |" --arg t "$ts" --arg u "${FAKE_VERDICT_AUTHOR:-tester}" --arg ut "${FAKE_VERDICT_AUTHOR_TYPE:-User}" '. + [{body:$b,user:{login:$u,type:$ut},created_at:$t,updated_at:$t}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json"
    case "$plan" in
      review-approve-dirty) echo scratch > review-scratch.txt ;;
      review-approve-and-push) push ;;
      review-needs-work-drop-base) git -C "$(git remote get-url origin)" update-ref -d refs/heads/main ;;
      review-needs-work-diverge) git push -q -f origin "$(git commit-tree "HEAD~1^{tree}" -p HEAD~1 -m diverged)":"refs/heads/$branch" ;;
    esac ;;
  review-render-unavailable) sha=$(git rev-parse "origin/$branch"); ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg b "verdict: needs-work"$'\n'"reviewed: $sha"$'\n'"reason: render-unavailable" --arg t "$ts" --arg u "${FAKE_VERDICT_AUTHOR:-tester}" --arg ut "${FAKE_VERDICT_AUTHOR_TYPE:-User}" '. + [{body:$b,user:{login:$u,type:$ut},created_at:$t,updated_at:$t}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json" ;;
  review-two-verdicts) # both bind; the LAST posted wins: $FAKE_ORDER = needs-work,approve or approve,needs-work
    sha=$(git rev-parse "origin/$branch"); for v in ${FAKE_ORDER//,/ }; do ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg b "verdict: $v"$'\n'"reviewed: $sha" --arg t "$ts" --arg u "${FAKE_VERDICT_AUTHOR:-tester}" --arg ut "${FAKE_VERDICT_AUTHOR_TYPE:-User}" '. + [{body:$b,user:{login:$u,type:$ut},created_at:$t,updated_at:$t}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json"; done ;;
  review-silent)   : ;;
  review-detach)   git checkout -q --detach "origin/$branch"; sha=$(git rev-parse "origin/$branch"); ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg b "verdict: needs-work"$'\n'"reviewed: $sha" --arg t "$ts" --arg u "${FAKE_VERDICT_AUTHOR:-tester}" --arg ut "${FAKE_VERDICT_AUTHOR_TYPE:-User}" '. + [{body:$b,user:{login:$u,type:$ut},created_at:$t,updated_at:$t}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json" ;;
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
grep -q 'approved' "$FAKE_GH/issue-comments" && grep -q 'https://x/pr/7' "$FAKE_GH/issue-comments" && grep -q '^cost_usd: ' "$FAKE_GH/issue-comments" && ok "(a) [B22 D13] closing comment names the PR link and cost_usd" || bad "(a) closing comment: $(tail -n 3 "$FAKE_GH/issue-comments" | tr '\n' '|')"
grep -q '^acceptEdits$' "$FAKE_GH/args-1.txt" && grep -q -- '--permission-prompts' "$FAKE_GH/args-1.txt" && grep -q '^none$' "$FAKE_GH/args-1.txt" && grep -q '^user,project,local$' "$FAKE_GH/args-2.txt" && ok "(a) [F2 F8] acceptEdits, --permission-prompts none, --setting-sources user,project,local on both sessions" || bad "(a) [F2 F8] spawn flags: $(tr '\n' ' ' < "$FAKE_GH/args-1.txt" | cut -c1-200)"
grep -q '| D-1 | a | b | user-answered |' "$FAKE_GH/prompt-1.txt" && grep -q 'They are binding' "$FAKE_GH/prompt-1.txt" && grep -q "Never post a comment starting with 'verdict:'" "$FAKE_GH/prompt-1.txt" && ok "(a) [F16 F17] the record is in the build prompt verbatim, binding, with the verdict ban" || bad "(a) [F16 F17] prompt-1 lacks the record or the rules"
grep -q '<!-- dev-pipeline -->$' "$FAKE_GH/issue-comments" && grep -q '^<!-- run_id: ' "$FAKE_GH/issue-comments" && grep -q '^<!-- session_id: ' "$FAKE_GH/issue-comments" && grep -q '^<!-- stage: lean-claimed -->$' "$FAKE_GH/issue-comments" && ok "(a) [D4] claim marker: the four HTML lines, each whole" || bad "(a) [D4] marker lines: $(grep -c '^<!-- ' "$FAKE_GH/issue-comments")"
! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-1.txt" && ! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-2.txt" && ok "(a) [F1] neither session is resumed or continued" || bad "(a) [F1] a session was resumed"
[ ! -d "$d/wt/42" ] && ok "(a) worktree torn down on approve" || bad "(a) worktree left after approve"
grep -q 'Closes #42' "$FAKE_GH/prompt-1.txt" && grep -q 'READY (not draft)' "$FAKE_GH/prompt-1.txt" && ok "(a) build prompt asks for a ready PR that closes the ticket" || bad "(a) PR conventions missing from the build prompt"
grep -q 'AskUserQuestion' "$FAKE_GH/args-1.txt" && ! grep -q 'editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(a) keyboard tools disallowed, no jira strip under github" || bad "(a) disallowed-tools list wrong"
grep -q 'DECLARE THE PIPELINE DEFAULT PANEL' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt declares the panel" || bad "(a) panel declaration missing"
grep -q 'on your own judgment' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt lets the reviewer opt a reviewer in, with a reason" || bad "(a) judgment opt-in missing from the review prompt"
grep -q 'models: build opus (label), review opus (default)' <<<"$OUT" && ok "(a) [A4 A6] build model read from the opus label; tiers are passed to the CLI as aliases, never pinned ids" || bad "(a) model line: $(grep 'models:' <<<"$OUT")"
! grep -q 'claude-opus-[0-9]' "$FAKE_GH/args-1.txt" && grep -q '^opus$' "$FAKE_GH/args-1.txt" && ok "(a) [A6] the session is launched with --model opus" || bad "(a) [A6] a pinned model id reached the session: $(grep -A1 -- '--model' "$FAKE_GH/args-1.txt" | tr '\n' ' ')"
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

# (d) E21: a build that left uncommitted work stops the run and nothing discards that work
fixture d; printf 'build-pr-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-inflight "(d) [E21] a build that left uncommitted work in the worktree is in flight"
[ -n "$(git -C "$d/wt/42" status --porcelain 2>/dev/null)" ] && ok "(d) [E21] the uncommitted work is still there, never reset away" || bad "(d) [E21] the worktree was cleaned — the build's work was discarded"
fixture d2; printf 'build-nothing\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-no-pr "(d2) [B14 B15] a build that changed nothing and opened no PR is build-no-pr, not in flight (orch:1515-1545 never tested head movement)"

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
fixture l; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(l1) in-progress label without --resume"
[ ! -d "$d/wt/42" ] && ok "(l1) no worktree created" || bad "(l1) worktree created despite refusal"
fixture l2; echo CLOSED > "$FAKE_GH/state"; run_case "$d"; expect env-ticket-closed "(l2) a ticket closed at launch is a preflight refusal"
[ "$RC" -eq 2 ] && ok "(l2) exits 2, like every preflight refusal" || bad "(l2) exit $RC"
fixture l3; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=60 RUN_COST_CEILING=100 run_case "$d"; expect cost-spent "(l3) cost ceiling"; [ "$RC" -eq 4 ] && ok "(l3) [B8] cost-spent exits 4" || bad "(l3) exit $RC"
# I15: the ceiling is exceeded, not reached — a run whose spend lands exactly on it keeps going
fixture l3b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=25 RUN_COST_CEILING=25 run_case "$d"; expect approved "[I15] a build whose spend equals the ceiling is not over it"
fixture l4; rm "$d/main/.claude/pipeline-state/42-ledger.md"; run_case "$d"; expect env-no-record "(l4) no intake record"; [ "$RC" -eq 3 ] && ok "(l4) [B6 K8] env-no-record exits 3 (resumable)" || bad "(l4) exit $RC"
fixture l5; run_case "$d" --dry-run; expect dry-run "(l5) dry-run spawns nothing"; [ "$RC" -eq 0 ] && ok "(l5) [B2 A13] dry-run exits 0" || bad "(l5) exit $RC"
[ ! -f "$FAKE_GH/calls" ] && ok "(l5) no claude call on dry-run" || bad "(l5) claude called on dry-run"

# (n) queue discipline and sizing, as the old lane enforced them
fixture n1; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n1) no queue label"
fixture n2; printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n2) blocker label refuses pickup"
fixture n3; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d"; expect usage-model "(n3) unlabeled ticket is not sized here"
grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/issue-comments" ] && ok "(n3) refused BEFORE the claim: still queued, nothing written" || bad "(n3) the claim ran before the sizing refusal"
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
grep -qx in-progress "$FAKE_GH/labels" && grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(p2) [D16] under github, writes:false gates only the tool strip: the labels and the marker are still written" || bad "(p2) [D16] no claim under writes:false"
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
[ "$(grep -c 'stage: lean-claimed' "$FAKE_GH/issue-comments")" = 1 ] && [ "$(grep -c '^in-progress$' "$FAKE_GH/labels")" = 1 ] && ok "(q2) [K2 K10] re-entry posts no marker and swaps no label" || bad "(q2) [K2 K10] re-entry wrote to the tracker: markers=$(grep -c 'stage: lean-claimed' "$FAKE_GH/issue-comments") labels=$(tr '\n' ' ' < "$FAKE_GH/labels")"
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
fixture r3; OUT="$( cd "$d/main" && bash "$RUN" -h 2>&1 )"; RC=$?; [ "$RC" -eq 0 ] && grep -q '^# usage: run.sh' <<<"$OUT" && ! grep -q '^terminal: ' <<<"$OUT" && ok "(r3) [A12] -h prints usage, exits 0, no terminal line" || bad "(r3) -h exit $RC"
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
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect staleness-expired "(u3) on re-entry the base move since the BRANCH POINT is seen"; [ "$RC" -eq 7 ] && ok "(u3) [B12] staleness-expired exits 7" || bad "(u3) exit $RC"
fixture u4; printf 'build-pr\nreview-crash\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(u4) a review session that died is not a verdict"
fixture u5; cat > "$T/bin/gh-nocomment" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue comment" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-nocomment"; RUN_GH="$T/bin/gh-nocomment" run_case "$d"; expect env-claim-failed "(u5) a claim marker that could not be posted is a refusal"

# (v) round-seven parity: the working-bot path end to end, jira keys lowercased in the branch, the
#     marker's author filter, must-show absent is red, every lane named before the first diff
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT","app":{"appName":"second-shift-bot"}}},"paths":{"plansDir":"docs/plans"}}' fixture v1
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
git -C "$d/main" config user.name t; git -C "$d/main" config user.email t@x   # the build's own commits; the record commit must carry the bot's identity instead
OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh" env -u RUN_GH -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(v1) a consumer WITH a bot: claim through claim-issue.sh, marker and body through the wrapper"
grep -qx in-progress "$FAKE_GH/labels" && ! grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(v1) claim-issue.sh swapped the labels through the bot" || bad "(v1) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(v1) marker posted through the bot" || bad "(v1) no marker"
[ "$(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)" = 'second-shift-bot[bot]' ] && ok "(v1) [E3] the record commit carries the bot's identity" || bad "(v1) [E3] record commit author: $(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)"
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
fixture x1b; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV or die' -- bash "$RUN" 42 > "$d/x1b.log" 2>&1 ) & rp=$!
until grep -q 'round 1 of' "$d/x1b.log" 2>/dev/null; do sleep 0.5; done; sleep 1.5
kill -INT "$rp"; wait "$rp"; xrc=$?
[ "$xrc" -eq 130 ] && grep -q 'interrupted; claim left in place' "$d/x1b.log" && ok "(x1b) [B18] INT exits 130" || bad "(x1b) INT exit $xrc"
sleep 1; if pgrep -f 'sleep 60' >/dev/null 2>&1; then bad "(x1b) [B18] the session outlived the scheduler on INT"; pkill -f 'sleep 60' 2>/dev/null; else ok "(x1b) [B18] the session was reaped on INT"; fi
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","readyProbe":"http://127.0.0.1:9/"}}}' fixture x2 "- true" $'\n## Design\n\nDesign: none — a wording change, nothing renders\n'
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

# (z) round-twelve parity: the design SECTION is what arms and disarms, in the gate's forms; a read
#     remote is never blamed on the build; the cap is a bound; blocker labels with spaces; exit codes
PX="cp $T/px.png {out}"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"$PX\",\"smokeCommand\":\"true\"}}}" fixture z1 "- true" $'\n## Design\n\nHandoff: x\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z1) rows under the spec form '## Design' arm the smoke too"
grep -q 'smoke-RS-1' <<<"$OUT" || [ -f "$(SD)/smoke-RS-1.png" ] && ok "(z1) the render ran" || bad "(z1) no render"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z2 "- true" $'\n## Design\n\nDesign: none\n'
run_case "$d"; expect env-design-undeclared "(z2) a disarm without a reason is refused, as the gate refused it"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z3 "- true" $'\n## Notes\n\nDesign: none — quoted in prose, not the design section\n'
run_case "$d"; expect env-design-undeclared "(z3) a 'Design: none' outside the design section does not disarm"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z4 "- true" $'\n## Design\n\n   Design:   NONE — an indented disarm with a reason, any case\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z4) the gate's indented, case-insensitive disarm form is accepted"
port=$(( 20000 + RANDOM % 20000 )); ( cd "$T" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & hs=$!
until curl -s -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; do sleep 0.2; done
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"$PX\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:$port/\"}}}" fixture z5 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z5) a readyProbe that answers 200 is ready"
kill "$hs" 2>/dev/null; wait "$hs" 2>/dev/null
fixture z6; printf 'build-stubborn\n' > "$FAKE_CLAUDE_PLAN"; s0=$(date +%s); RUN_BUILD_TIMEOUT=2 run_case "$d"; el=$(( $(date +%s) - s0 )); expect build-blocked "(z6) a TERM-ignoring session is stopped at its cap"
[ "$el" -lt 40 ] && ok "(z6) the cap is a bound (${el}s, KILL after TERM)" || bad "(z6) waited ${el}s"
sleep 1; if pgrep -f "$T/bin/claude" >/dev/null 2>&1; then bad "(z6) the stubborn session survived the KILL"; pkill -KILL -f "$T/bin/claude" 2>/dev/null; else ok "(z6) the stubborn session is dead"; fi
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"blockers":["needs design review"]}},"paths":{"plansDir":"docs/plans"}}' fixture z7
printf 'ready-for-dev\nopus\nneeds design review\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(z7) a blocker label containing spaces blocks pickup"
fixture z8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-remote-dead" <<EOF
#!/usr/bin/env bash
exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-remote-dead"
( cd "$d/main" && git remote set-url origin /nonexistent-remote ) ; run_case "$d"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != build-inflight ] && ok "(z8) an unreadable remote is a refusal ($TERM_SLUG), never blamed on the build" || bad "(z8) got $TERM_SLUG rc=$RC"
fixture z9; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; [ "$RC" -eq 4 ] && ok "(z9) rounds-spent exits 4" || bad "(z9) exit $RC"
fixture z10 "- false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; [ "$RC" -eq 4 ] && ok "(z10) checks-red-spent exits 4" || bad "(z10) exit $RC"
fixture z11; printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; [ "$RC" -eq 1 ] && ok "(z11) build-no-pr exits 1" || bad "(z11) exit $RC"
fixture z12; printf 'build-pr\nreview-needs-work\nbuild-commit-nopush\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-inflight "(z12) [E21] a commit not on origin is in flight"
[ "$RC" -eq 1 ] && ok "(z12) build-inflight exits 1" || bad "(z12) exit $RC"
[ -n "$(git -C "$d/wt/42" log --oneline origin/second-shift/42..HEAD 2>/dev/null)" ] && ok "(z12) [E21] the unpushed commit is still there" || bad "(z12) [E21] the unpushed commit was reset away"

# (aa) round-thirteen parity: the committed record is what the design guard reads; a remote dying
#      mid-run and an unreadable tracker at verdict time are environment refusals
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture aa1 "- true" $'\n## Design\n\nDesign: none — first run\n'
printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(aa1) first run, committed with Design: none"
# the receipt on disk is now DELETED and replaced by one with no design section at all: a resume must
# read only the committed record (declared, none-with-reason) and never the receipt
printf '# record\n\n## Checks\n\n- true\n' > "$d/main/.claude/pipeline-state/42-ledger.md"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume reads the committed record, not a receipt that now says nothing"
grep -q 'receipt on disk is not consulted' <<<"$OUT" && ok "(aa1) the receipt was not consulted on resume" || bad "(aa1) the receipt was read on resume"
rm -f "$d/main/.claude/pipeline-state/42-ledger.md"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume with NO receipt on disk still runs (an absent ledger is not an error once the record is committed)"
fixture aa2; printf 'build-kill-remote\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-remote-unreadable "(aa2) a remote that dies after the build is a refusal, not 'the head did not move'"
[ "$RC" -eq 2 ] && ok "(aa2) exits 2" || bad "(aa2) exit $RC"
fixture aa3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-comments-dead" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ] && [[ "\$2" == *comments* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-comments-dead"; RUN_GH="$T/bin/gh-comments-dead" run_case "$d"; expect env-tracker-unreadable "(aa3) an unreadable comment listing at verdict time is an environment refusal, not review-unbound"

# (ab) round-fourteen parity: the gate's heading rule, and dry-run reads the receipt's checks
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab1 "- true" $'\n### DESIGN\n\nDesign: none — depth three, upper case\n\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ab1) the FIRST design section decides (disarmed), a later one does not merge into it; any depth, any case"
grep -q 'arms no render state' <<<"$OUT" && ok "(ab1) not armed" || bad "(ab1) the second section leaked"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab2 "- true" $'\n## Design notes\n\nDesign: none — a heading with trailing words is not the design section\n'
run_case "$d"; expect env-design-undeclared "(ab2) '## Design notes' is not the design section"
fixture ab3 "- echo CHECK-FROM-RECORD"; run_case "$d" --dry-run; grep -q 'CHECK-FROM-RECORD' <<<"$OUT" && ok "(ab3) dry-run lists the record's own checks before any commit exists" || bad "(ab3) dry-run omitted the record's checks"

# (ac) round-fifteen parity: [] blockers, github key shape, a detached worktree after review, no ambient model seam
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"blockers":[]}},"paths":{"plansDir":"docs/plans"}}' fixture ac1
printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ac1) blockers: [] means no blocker labels, so epic does not block"
fixture ac2; OUT="$( cd "$d/main" && bash "$RUN" 0042 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-key "(ac2) a zero-padded github key is refused, as the gate refused it"
fixture ac3; printf 'build-pr\nreview-detach\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ac3) a review that left the worktree detached does not make the next build read as inflight"
fixture ac4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_MODEL=claude-sonnet-5 RUN_ID=ambient-run-id run_case "$d"; grep -q 'models: build opus (label)' <<<"$OUT" && ok "(ac4) an ambient RUN_MODEL does not override the ticket's label" || bad "(ac4) RUN_MODEL leaked"
[ ! -d "$d/main/.claude/pipeline-state/run-42/ambient-run-id" ] && ! grep -q 'run_id: ambient-run-id' "$FAKE_GH/issue-comments" && ok "(ac4) [A26] an ambient RUN_ID never keys the run's records" || bad "(ac4) [A26] ambient RUN_ID leaked"

# (ad) round-sixteen parity: a run that ends with the worktree detached (a review checked out the head) can be resumed
fixture ad1; printf 'build-pr\nreview-detach\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(ad1) first run ends after a detaching review"
[ "$(git -C "$d/wt/42" rev-parse --abbrev-ref HEAD)" = HEAD ] && ok "(ad1) the worktree is left detached, as a review may leave it" || bad "(ad1) fixture did not detach"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(ad1) the resume repairs a detached worktree instead of refusing it as 'another branch'"

fixture ad2; mkdir -p "$d/wt"; git -C "$d/main" worktree add -q -b other "$d/wt/42" origin/main; run_case "$d"; expect env-worktree-mismatch "(ad2) a worktree on a DIFFERENT named branch is still refused"

# ---- rows: cases keyed to the contract inventory (strategy repo, run-sh-contract-inventory-2026-09-22.md).
#      Each case names the row it discriminates; a row whose behavior is reverted turns its case red.

# A2 A8 A10: usage refusals with their own slugs
fixture ra; OUT="$( cd "$d/main" && bash "$RUN" 42 43 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect usage-unexpected-argument "[A2] a second positional argument is refused, never silently taken as the ticket"; [ "$RC" -eq 2 ] && ok "[A2] exit 2" || bad "[A2] exit $RC"
OUT="$( cd "$d/main" && bash "$RUN" 42 --review-model "" 2>&1 )"; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-empty-review-model "[A8] an empty --review-model has its own slug"
OUT="$( cd "$d/main" && bash "$RUN" 42 --record /tmp/x.md 2>&1 )"; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-unknown-option "[A15] --record is not a flag: the receipt lives at its one conventional path"
OUT="$( cd "$d/main" && bash "$RUN" 42 --max-continuations 3 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-max-continuations "[A10] the retired --max-continuations is named, not 'unknown option'"; [ "$RC" -eq 2 ] && ok "[A10] exit 2" || bad "[A10] exit $RC"

# A18: --detach with an uncreatable log dir refuses before detaching
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans","pipelineStateDir":"blocker/state"}}' fixture rb; : > "$d/main/blocker"
run_case "$d" --detach; expect env-detach-log-dir "[A18] --detach cannot create its log dir"; [ "$RC" -eq 2 ] && ok "[A18] exit 2" || bad "[A18] exit $RC"

# A17: --detach with no perl on PATH
mkdir -p "$T/noperl"; for b in /bin/* /usr/bin/*; do case "$(basename "$b")" in perl*) ;; *) ln -sf "$b" "$T/noperl/$(basename "$b")" ;; esac; done
for tool in git jq curl; do p="$(command -v "$tool")"; [ -n "$p" ] && ln -sf "$p" "$T/noperl/$tool"; done
fixture rc1; OUT="$( cd "$d/main" && PATH="$T/noperl:$T/bin" bash "$RUN" 42 --detach 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
if PATH="$T/noperl:$T/bin" command -v perl >/dev/null 2>&1; then ok "[A17] (skipped: perl still resolvable on the stripped PATH)"; else expect env-detach-perl "[A17] --detach without perl is refused"; fi

# A16: --detach runs to its terminal under setsid; the log's last line carries the exit code
fixture rc2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --detach
[ "$RC" -eq 0 ] && grep -q 'detached: pid ' <<<"$OUT" && ok "[A16] --detach prints pid and log, exits 0" || bad "[A16] detach rc=$RC: $(tail -n 2 <<<"$OUT" | tr '\n' '|')"
dlog="$(sed -n 's/.*detached: pid [0-9]* · log \([^ ]*\) .*/\1/p' <<<"$OUT")"
for _ in $(seq 1 120); do grep -q 'detached run exited rc=' "$dlog" 2>/dev/null && break; sleep 0.5; done
grep -q 'detached run exited rc=0$' "$dlog" 2>/dev/null && grep -q '^terminal: approved$' "$dlog" && ok "[A16] the detached run reached approved and the log's last line carries rc=0" || bad "[A16] detached log: $(tail -n 3 "$dlog" 2>/dev/null | tr '\n' '|')"

# B13 J4: an unreadable tracker MID-RUN is staleness-unreadable, exit 1 (fail closed), never read as OPEN
fixture rd; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-state-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue view" ] && [[ "\$*" == *state* ]]; then n=\$(cat "\$FAKE_GH/state-reads" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "\$FAKE_GH/state-reads"; [ "\$n" -ge 3 ] && exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-state-dies"; RUN_GH="$T/bin/gh-state-dies" run_case "$d"; expect staleness-unreadable "[B13 J4] tracker unreadable before round 2"; [ "$RC" -eq 1 ] && ok "[B13] exit 1" || bad "[B13] exit $RC"

# B16: two open PRs on the head
fixture re; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-two-prs" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "pr list" ]; then printf '7\n8\n'; exit 0; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-two-prs"; RUN_GH="$T/bin/gh-two-prs" run_case "$d"; expect pr-ambiguous "[B16] more than one open PR on the head"; [ "$RC" -eq 1 ] && ok "[B16] exit 1" || bad "[B16] exit $RC"

# C1 C2: an absent config means every default; a present-but-unparseable one is a refusal
fixture rf; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm "$d/main/.claude/second-shift.config.json"
( cd "$d/main" && git push -q origin main:second-shift/41 ) 2>/dev/null   # C7's plurality scan needs one candidate: <prefix><numeric key>
OUT="$( cd "$d/main" && env -u SECOND_SHIFT_CONFIG bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[C1] no config file: github, ready-for-dev, docs/plans, the scanned prefix"
fixture rg; echo '{not json' > "$d/main/.claude/second-shift.config.json"; run_case "$d"; expect env-config-unparseable "[C2] an unparseable config never falls back to defaults"; [ "$RC" -eq 2 ] && ok "[C2] exit 2" || bad "[C2] exit $RC"

# D3: a failed label swap leaves the queue label and stops
fixture rh; cat > "$T/bin/gh-edit-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue edit" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-edit-dies"; RUN_GH="$T/bin/gh-edit-dies" run_case "$d"; expect env-claim-failed "[D3] the swap failed"
grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/calls" ] && ok "[D3] queue label intact, nothing spawned" || bad "[D3] labels: $(tr '\n' ' ' < "$FAKE_GH/labels"), calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"

# E12: a PR whose body cannot be read is a tracker read failure — exit 2, never waved through and never blamed on the build
fixture ri; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-prview-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "pr view" ] && [[ "\$*" == *body* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-prview-dies"; RUN_GH="$T/bin/gh-prview-dies" run_case "$d"; expect env-tracker-unreadable "[E12] unreadable PR body"; [ "$RC" -eq 2 ] && ok "[E12] exit 2" || bad "[E12] exit $RC"

# E20: an approve with work left in the worktree is not a finished run
fixture rj; printf 'build-pr\nreview-approve-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect closeout-inflight "[E20] the review left an untracked file behind"
[ "$RC" -eq 1 ] && [ -d "$d/wt/42" ] && [ -f "$d/wt/42/review-scratch.txt" ] && ok "[E20] exit 1, worktree kept with the work in it" || bad "[E20] rc=$RC, worktree $([ -d "$d/wt/42" ] && echo kept || echo gone)"

# F7 F18 H13: Figma servers, the figma-faithful sequence and the render-unavailable rule appear only on a frames ticket
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture rk "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[F7] frames ticket"
grep -q 'mcp__figma' "$FAKE_GH/args-1.txt" && grep -q 'mcp__figma' "$FAKE_GH/args-2.txt" && ok "[F7] Figma servers allowed in both sessions on a frames ticket" || bad "[F7] Figma servers missing"
grep -q 'figma-faithful' "$FAKE_GH/prompt-1.txt" && grep -q 'three rounds per screen' "$FAKE_GH/prompt-1.txt" && ok "[F18] the build prompt carries the figma-faithful sequence" || bad "[F18] sequence missing"
grep -q 'render-unavailable' "$FAKE_GH/prompt-2.txt" && ok "[H13] the review prompt carries the render-unavailable rule" || bad "[H13] rule missing"
# F20: the review session can run review-lead's panel — the fan-out is a Workflow whose agents inherit
# the session's tools, staged into the run's state dir (outside the worktree), after review-toolkit's lint
fixture rpanel; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[F20] panel tools"
ral=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-2.txt" | tail -n 1); bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1)
miss=""; for t in Skill Workflow Grep Glob 'Bash(find *)' 'Bash(cp *)' 'Bash(bash *check-review-context.sh*)' 'Bash(gh issue view*)'; do case ",$ral," in *",$t,"*) ;; *) miss="$miss $t" ;; esac; done
[ -z "$miss" ] && ok "[F20] the review allowlist carries every tool the panel dispatch uses" || bad "[F20] review allowlist lacks:$miss"
case ",$bal," in *,Workflow,*) bad "[F20] the build session was given Workflow" ;; *) ok "[F20] the build allowlist is unchanged" ;; esac
sdir=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-2.txt" | grep '/run-42/' | head -n 1)
[ -n "$sdir" ] && ! grep -qF -- "$sdir" "$FAKE_GH/args-1.txt" && grep -qF "$sdir" "$FAKE_GH/prompt-2.txt" && grep -q 'code-review.mjs' "$FAKE_GH/prompt-2.txt" \
  && ok "[F20] only the review session gets the run's state dir, and its prompt stages code-review.mjs there" || bad "[F20] state dir '${sdir:-none}' not added to the review, or not named as the staging dir"
case ",$ral," in *",Bash(gh api"*) bad "[F20] the review session may call gh api (it can DELETE)" ;; *) ok "[F20] the review session gets no gh api" ;; esac

# B10: a verdict binds only from a Bot or the account the scheduler writes with — on a public repo anyone can
# comment, and a needs-work body is pasted into the next BUILD prompt
fixture rauth; printf 'build-pr\nreview-approve\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_VERDICT_AUTHOR=stranger run_case "$d"
expect review-unbound "[B10] a verdict posted by a stranger's account"
[ ! -f "$FAKE_GH/prompt-4.txt" ] && ok "[B10] no BUILD spawned on a stranger's verdict" || bad "[B10] a stranger's verdict drove another round"
fixture rauthb; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_VERDICT_AUTHOR='second-shift-bot[bot]' FAKE_VERDICT_AUTHOR_TYPE=Bot run_case "$d"
expect approved "[B10] a verdict posted by a Bot account"

# H13: a review that could not render stops the run as env-not-ready; it does not spend a round
fixture rru; printf 'build-pr\nreview-render-unavailable\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect env-not-ready "[H13] verdict: needs-work with reason: render-unavailable"
[ ! -f "$FAKE_GH/prompt-3.txt" ] && ok "[H13] no second BUILD after render-unavailable" || bad "[H13] render-unavailable spent a round"

# C2: an unmigrated v2 config is refused before anything is written, never half-honored (the commands
# key is then the sole key or the main checkout's name, the rule the pre-commit hook applies)
si=0; for stale in '"topology":{"type":"standalone","repos":{"x":{"path":".","baseBranch":"main"}}}' '"stageParams":{"formatGlob":"*"}' '"grillWaivers":{}' '"configVersion":2'; do
  FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"commands\":{\"main\":{\"lint\":null,\"typecheck\":null,\"test\":\"true\"}},$stale}" fixture "rstale$si"; si=$((si + 1))
  printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-config-stale "[C2] v2 config (${stale%%:*})"
  [ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && printf '%s\n' "$OUT" | grep -q 'v2-to-v3.md' && ok "[C2] exit 2, nothing written, the migration doc named (${stale%%:*})" || bad "[C2] rc=$RC, calls=$([ -f "$FAKE_GH/calls" ] && echo yes || echo no) (${stale%%:*})"
done
FIXTURE_CONFIG='{"configVersion":3,"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":null,"typecheck":null,"test":"true"}}}' fixture rv3
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C2] a v3 config runs"

# I14 I16: a session with no result JSON (killed at its bound) is reported unpriced, never as $0
fixture rcost; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=2 run_case "$d"; expect build-blocked "[I16] a build killed at its bound"
grep -q 'unpriced' "$FAKE_GH/issue-comments" && ok "[I16] the closing comment says the run is unpriced" || bad "[I16] a killed session was priced as \$0: $(grep cost_usd "$FAKE_GH/issue-comments" | tail -n 1)"
printf '%s\n' "$OUT" | grep -q 'unpriced' && ok "[I16] the operator is told a session is unpriced" || bad "[I16] nothing said about the unpriced session"
fixture rk2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
! grep -q 'mcp__figma' "$FAKE_GH/args-1.txt" && ! grep -q 'figma-faithful' "$FAKE_GH/prompt-1.txt" && ok "[F7 F18] neither on a ticket without frames" || bad "[F7 F18] leaked onto a frames-less ticket"

# H9: two states rendering pixel-identical is red
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture rl "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | a | empty | 1:3 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H9] two states with identical pixels are red"
grep -qi 'identical' "$(SD)"/smoke-1.1.log 2>/dev/null && ok "[H9] the log names the identical render" || bad "[H9] log: $(head -3 "$(SD)"/smoke-1.1.log 2>/dev/null | tr '\n' '|')"

# H11: frames declared but no render/smoke command configured
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma"}}' fixture rm1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-smoke-unconfigured "[H11] no liveRender.command"; [ "$RC" -eq 2 ] && ok "[H11] exit 2" || bad "[H11] exit $RC"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\"}}}" fixture rm2 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-smoke-unconfigured "[H11] a render command with no smokeCommand"

# I5: with several binding comments the LAST wins
fixture rn; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=needs-work,approve run_case "$d"; expect approved "[I5] needs-work then approve: approve wins"
fixture rn2; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=approve,needs-work run_case "$d" --max-rounds 1; expect rounds-spent "[I5] approve then needs-work: needs-work wins"

# I6 K12: a head that moved under the review unbinds its verdict; a dark review is re-spawned ONCE, no round spent
fixture ro; printf 'build-pr\nreview-approve-and-push\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I6 K12] the second review binds"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && grep -q 'reviewed: ' "$FAKE_GH/prompt-3.txt" && ok "[I6] the approve for the pre-push head was rejected; one review re-spawned, no build" || bad "[I6] calls=$(cat "$FAKE_GH/calls")"
printf '%s\n' "$OUT" | grep -q '1 round' && ok "[K12] the retry spent no round" || bad "[K12] round count wrong"
[ -f "$(SD)/checks-1.1-retry1.log" ] && ok "[I6] the checks re-ran on the moved head before the re-spawn" || bad "[I6] no checks on the moved head: $(cd "$(SD)" && echo checks-*)"
fixture ro2; printf 'build-pr\nreview-silent\nreview-silent\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "[K12] two dark reviews"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && [ "$RC" -eq 5 ] && ok "[K12] exactly one retry, then exit 5" || bad "[K12] calls=$(cat "$FAKE_GH/calls") rc=$RC"

# I10: added skips and an edited CI config reach the review input
fixture rp; printf 'build-skip-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] run"
grep -q 'it.skip' "$(SD)/review-1.1.prompt" && grep -q 'ci.yml' "$(SD)/review-1.1.prompt" && ok "[I10] the added skip and the CI edit are named in the review input" || bad "[I10] not surfaced"

# J7: origin/<base> that no longer resolves mid-run is staleness-unreadable, never 'nothing moved'
fixture rq; printf 'build-pr\nreview-needs-work-drop-base\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect staleness-unreadable "[J7] the base ref vanished before round 2"; [ "$RC" -eq 1 ] && ok "[J7] exit 1" || bad "[J7] exit $RC"

# J11: an unresolvable merge-base (an orphan branch) is env-base-unreadable
fixture rr; mkdir -p "$d/wt"; ( cd "$d/main" && git worktree add -q --detach "$d/wt/42" && cd "$d/wt/42" && git checkout -q --orphan second-shift/42 && git commit -qm orphan --allow-empty && git push -q origin second-shift/42 ) 2>/dev/null
printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect env-base-unreadable "[J11] no merge-base with the base branch"; [ "$RC" -eq 2 ] && ok "[J11] exit 2" || bad "[J11] exit $RC"

# J13: a diff against the first commit that cannot be read stops the run
fixture rs; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitdiffdead"
cat > "$T/gitdiffdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" diff --name-status "*) exit 128 ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitdiffdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitdiffdead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != approved ] && ok "[J13] an unreadable diff is an environment stop ($TERM_SLUG)" || bad "[J13] rc=$RC $TERM_SLUG"

# K5: re-entry is decided by the tracker alone — a local run-id cache admits nothing
fixture rt; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; echo "run-x" > "$d/main/.claude/pipeline-state/42-run-id"; run_case "$d"; expect claimed-elsewhere "[K5] a claimed label with no marker is not re-entered on the strength of a local cache"

# ---- rows, audit round 1 ----
# A9: the magnitude half of the positive-integer test (orch:540 `-ge 1`)
fixture au1; OUT="$( cd "$d/main" && bash "$RUN" 42 --max-rounds 00 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect usage-max-rounds "[A9] --max-rounds 00 is below 1"; [ "$RC" -eq 2 ] && ok "[A9] exit 2" || bad "[A9] exit $RC"

# E15: the earlier block is found under CRLF, as a body round-tripped through the GitHub API carries it (gate:6321-6324)
fixture au2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-crlf" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\r\\n\\r\\n<!-- pipeline-cost-block -->\\r\\nold block line\\r\\n<!-- /pipeline-cost-block -->\\r\\n\\r\\nKEEP THIS LINE\\r\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-crlf"; RUN_GH="$T/bin/gh-crlf" run_case "$d"; expect approved "[E15] run against a CRLF body"
grep -q 'KEEP THIS LINE' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && [ "$(grep -c '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md")" = 1 ] && ok "[E15] the CRLF block was replaced, not appended to" || bad "[E15] body: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-240)"

# G8 C22: "configured" is a config-time predicate — a when-scoped lane that did not run on this diff is still a configured check (gate:5193-5202)
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"docs","when":["docs/**"],"commands":["false"]}]}}}' fixture au3 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[G8] configured-but-skipped is not unverified"

# K12: a crashed and a timed-out review session each get the one re-spawn
fixture au4; printf 'build-pr\nreview-crash\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[K12] a crashed review is re-spawned once"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && ok "[K12] one re-spawn, no build" || bad "[K12] calls=$(cat "$FAKE_GH/calls")"
[ -f "$(SD)/checks-1.1.log" ] && [ ! -f "$(SD)/checks-1.1-retry1.log" ] && ok "[K12] the checks did not re-run for an unmoved head" || bad "[K12] checks re-ran: $(cd "$(SD)" && echo checks-*)"
fixture au5; printf 'build-pr\nbuild-sleep\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_REVIEW_TIMEOUT=2 run_case "$d"; expect approved "[K12] a timed-out review is re-spawned once"
sleep 1; pkill -f 'sleep 60' 2>/dev/null

# C13: the docs/plans default is where the record lands when no config says otherwise
fixture au6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm "$d/main/.claude/second-shift.config.json"
( cd "$d/main" && git push -q origin main:second-shift/41 ) 2>/dev/null
OUT="$( cd "$d/main" && env -u SECOND_SHIFT_CONFIG bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
git -C "$d/origin.git" cat-file -e second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null && ok "[C13] the record is committed under docs/plans by default" || bad "[C13] record not at docs/plans ($TERM_SLUG)"

# ---- rows, audit round 2 ----
# C24 C25 H8: placeholder values are shell-quoted into the command (gate:4005-4030 shquote/subst); a render that fails or writes nothing is red
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {route} {state} > {out}\",\"smokeCommand\":\"test {mustShow} = 'a b' && test {route} = 'x&y z'\"}}}" fixture ar1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | x&y z | filters expanded | 1:2 | a b |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C24 C25] a route with '&' and a space, a state and a must-show with spaces, reach the commands as single arguments"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"false","smokeCommand":"true"}}}' fixture ar2 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] a render command that fails is red"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","smokeCommand":"true"}}}' fixture ar3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] a render that exits 0 and writes no image is red"

# H9: the duplicate detector compares against EVERY earlier state (gate:4991-4994), not only the previous one
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"printf %s {state} > {out}","smokeCommand":"true"}}}' fixture ar4 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | a | empty | 1:3 | ok |\n| RS-3 | a | default | 1:4 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H9] states a,b,a: the third is identical to the first"
grep -q 'RS-1 and RS-3' "$(SD)/smoke-1.1.log" 2>/dev/null && ok "[H9] the log names both rows" || bad "[H9] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-200)"

# C20: the when-glob diff is fail-closed (gate:3970-3981) — a diff that cannot be read never skips every when-scoped lane
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"e2e","when":["src/**"],"commands":["false"]}]}}}' fixture ar5 ""
printf 'build-delete-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitnameonlydead"
cat > "$T/gitnameonlydead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" diff --name-only "*) case "\$*" in *..*) ;; *) exit 128 ;; esac ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitnameonlydead/git"; OUT="$( cd "$d/main" && PATH="$T/gitnameonlydead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != approved ] && ok "[C20] an unreadable diff stops the run ($TERM_SLUG) instead of skipping the when-scoped lane" || bad "[C20] rc=$RC $TERM_SLUG"

# J5: the staleness overlap diffs are fail-closed too
fixture ar6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[J5] first run"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main && echo moved >> work.txt && git add work.txt && git commit -qm "base moves" && git push -q origin main ) 2>/dev/null
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
OUT="$( cd "$d/main" && PATH="$T/gitnameonlydead:$PATH" bash "$RUN" 42 --resume 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect staleness-unreadable "[J5] a base move whose overlap cannot be computed is unreadable, never 'moved into nothing of ours'"

# I7: a comment listing that is not an array is an unreadable tracker, not review-unbound (orch:700)
fixture ar7; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-comments-object" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ] && [[ "\$2" == *issues/7/comments* ]]; then echo '{"message":"rate limited"}'; exit 0; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-comments-object"; RUN_GH="$T/bin/gh-comments-object" run_case "$d"; expect env-tracker-unreadable "[I7] a non-array comment listing"

# F16: the record read for the build prompt is checked
fixture ar8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitshowdead"
cat > "$T/gitshowdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" show "*) exit 128 ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitshowdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitshowdead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "[F16] a record that cannot be read at its first commit stops before any build ($TERM_SLUG)" || bad "[F16] rc=$RC $TERM_SLUG calls=$(cat "$FAKE_GH/calls" 2>/dev/null)"

# B22: a closing comment that could not be posted is said aloud
fixture ar9; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-close-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue comment" ] && [[ "\$*" == *"second-shift run"* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-close-dies"; RUN_GH="$T/bin/gh-close-dies" run_case "$d"; expect approved "[B22] approve with a dead closing comment"
grep -q 'could not post the closing comment' <<<"$OUT" && ok "[B22] the failed closing comment is reported" || bad "[B22] silent"

# E21 E20: the unreadable arms, and a diverged worktree
fixture ar10; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitstatusdead"
cat > "$T/gitstatusdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" status --porcelain "*) n=\$(cat "\$FAKE_GH/status-reads" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "\$FAKE_GH/status-reads"; [ "\$n" -ge "\${FAKE_STATUS_DIES_AT:-1}" ] && { echo "fatal: index locked" >&2; exit 128; } ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitstatusdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=2 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect build-inflight-unreadable "[E21] an unreadable status after the build"; [ "$RC" -eq 1 ] && ok "[E21] exit 1" || bad "[E21] exit $RC"
fixture ar11; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=3 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect closeout-inflight-unreadable "[E20] an unreadable status at close-out"; [ "$RC" -eq 1 ] && [ -d "$d/wt/42" ] && ok "[E20] exit 1, worktree kept" || bad "[E20] rc=$RC"
fixture ar12; printf 'build-pr\nreview-needs-work-diverge\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-worktree-diverged "[E18] a worktree that cannot fast-forward to origin is refused, never reset"
[ "$RC" -eq 2 ] && [ "$(cat "$FAKE_GH/calls")" = 2 ] && ok "[E18] exit 2, no second build" || bad "[E18] rc=$RC calls=$(cat "$FAKE_GH/calls")"

# A20 A21 C16: the config-path override, the GH alias, and .format as a check
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}' fixture ar13
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/second-shift.config.json" "$d/elsewhere.json"
OUT="$( cd "$d/main" && SECOND_SHIFT_CONFIG="$d/elsewhere.json" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[A20] SECOND_SHIFT_CONFIG points at a config outside the default path (no config at the default: the prefix would be unresolvable)"
fixture ar14; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
OUT="$( cd "$d/main" && GH="$T/bin/gh" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[A21] GH names the tracker CLI when RUN_GH is unset"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","format":"false"}}}' fixture ar15 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[C16] .format runs as a check"

# ---- rows, audit round 3 (guards only) ----
# H8: a render that writes an image and still exits non-zero is red on its exit code
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}; false\",\"smokeCommand\":\"true\"}}}" fixture as1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] an image written by a render that exited non-zero is still red"
grep -q 'render failed' "$(SD)/smoke-1.1.log" && ok "[H8] the log names the exit, not the image" || bad "[H8] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" | cut -c1-160)"

# C18: a setup lane runs in its own cwd
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","cwd":"src","commands":["test -f a.ts"]}],"lint":"true"}}}' fixture as2 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C18] the setup lane's command ran in src/ (a.ts exists only there)"

# C20: an extraLanes entry with no `when` always runs
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"always","commands":["false"]}]}}}' fixture as3 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[C20] a lane with no when globs runs on every diff"

# E15: an earlier block with no terminator is replaced and the loss is said in the body
fixture as4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-noterm" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\n\\n<!-- pipeline-cost-block -->\\nold block line\\nno terminator here\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-noterm"; RUN_GH="$T/bin/gh-noterm" run_case "$d"; expect approved "[E15] run against a block with no terminator"
grep -q 'had no terminator; text below it was not preserved' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && ok "[E15] the body says what was not preserved" || bad "[E15] body: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-200)"

# (m) rounds spent
fixture m; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; expect rounds-spent "(m) two needs-work rounds"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
