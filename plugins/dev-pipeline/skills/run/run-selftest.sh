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
# #1022: run.sh lints the receipt with intake-toolkit's ledger-lint.sh. The sibling plugin sits beside this one in a
# checkout (plugins/intake-toolkit) and one version segment further up in an install cache (<cache>/intake-toolkit/<v>)
IT_ROOT=""
for _c in "$SCRIPT_DIR/../../../intake-toolkit" "$SCRIPT_DIR"/../../../../intake-toolkit/*; do
  [ -f "$_c/skills/plan-interview/tools/ledger-lint.sh" ] && IT_ROOT="$(cd "$_c" && pwd)"
done; unset _c
[ -n "$IT_ROOT" ] || { echo "FATAL: no intake-toolkit beside $SCRIPT_DIR — run.sh's receipt lint has nothing to run" >&2; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/run-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
# a BUILD session running this suite carries the spawn env run.sh gives it, and an operator's shell may carry RUN_* caps:
# the F-env cases read what run.sh sets from its defaults, not what this shell inherited
unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS RUN_BUILD_TIMEOUT RUN_REVIEW_TIMEOUT
# ...and an operator's shell may be a herdr pane with a watch configured (#939): the cases set these themselves
for _v in $(compgen -e HERDR_) RUN_WATCH_CMD RUN_WATCH_EDITOR RUN_DETACHED_LOG; do unset "$_v"; done

# ---- fakes ----
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# state dir: $FAKE_GH — files: state, labels, prs, comments.json (array), cost-comments, statuses (commit-status posts), minimized (minimizeComment calls)
S="$FAKE_GH"; sub="$1 $2"; path="${2:-}"; shift 2
case "$sub" in
  "issue view")  case "$*" in *state*) cat "$S/state" ;; *labels*) cat "$S/labels" 2>/dev/null ;; esac ;;
  "issue edit")  add=""; rm=""; while [ $# -gt 0 ]; do case "$1" in --add-label) add="$2"; shift 2;; --remove-label) rm="$2"; shift 2;; *) shift;; esac; done
                 [ -n "$add" ] && echo "$add" >> "$S/labels"; [ -n "$rm" ] && { grep -vx "$rm" "$S/labels" > "$S/l.tmp"; mv "$S/l.tmp" "$S/labels"; } ;;
  "issue comment") echo "$*" >> "$S/issue-comments" ;;
  "pr list")     cat "$S/prs" 2>/dev/null ;;
  "pr checks")   [ -f "$S/ci-red" ] && echo '[{"name":"ci","state":"FAILURE"}]' || echo '[]' ;;
  "pr comment")  echo "$*" >> "$S/cost-comments"   # a --body-file's text goes to pr-comment-bodies, one comment after another
                 prev=""; for a in "$@"; do [ "$prev" = --body-file ] && { cat "$a"; echo '<!-- end of comment -->'; } >> "$S/pr-comment-bodies"; prev="$a"; done ;;
  "pr ready")    [ -f "$S/ready-fail" ] && { cat "$S/ready-fail" >&2; exit 1; }   # one line per flip, in order: who, which way
                 case "$*" in *--undo*) touch "$S/draft"; w=undo ;; *) rm -f "$S/draft"; w=ready ;; esac; echo "${FAKE_GH_AS:-operator} $w" >> "$S/ready-calls" ;;
  "pr view")     case "$*" in *body*) jq -n --rawfile b "$S/pr-created-body.txt" --argjson d "$([ -f "$S/draft" ] && echo true || echo false)" '{body:$b, isDraft:$d}' ;; *) echo "https://x/pr/7" ;; esac ;;
  "repo view")   echo "o/r" ;;
  "api -X")      # PATCH repos/o/r/pulls/7 -F body=@<file> | POST .../labels --input - | DELETE .../labels/<name>
                 verb="$1"; p="$2"
                 case "$verb $p" in
                   "POST "*labels*) jq -r '.labels[]' >> "$S/labels"; jq -Rn '[inputs] | map({name: .})' < "$S/labels" ;;
                   "DELETE "*labels/*) grep -vx "${p##*/}" "$S/labels" > "$S/l.tmp"; mv "$S/l.tmp" "$S/labels" ;;
                   "POST "*/statuses/*) [ -f "$S/status-fail" ] && { cat "$S/status-fail" >&2; exit 1; }   # one line per post: who, the sha, the fields
                                        shift 2; printf '%s %s %s\n' "${FAKE_GH_AS:-operator}" "${p##*/statuses/}" "$*" >> "$S/statuses" ;;
                   *) for a in "$@"; do case "$a" in body=@*) cp "${a#body=@}" "$S/pr-body.md" ;; esac; done ;;
                 esac ;;
  "api user")    echo tester ;;
  "api graphql") [ -f "$S/minimize-fail" ] && { cat "$S/minimize-fail" >&2; exit 1; }   # one line per minimize: who, the node id
                 for a in "$@"; do case "$a" in id=*) echo "${FAKE_GH_AS:-operator} ${a#id=}" >> "$S/minimized" ;; esac; done; echo '{}' ;;
  api*)         case "$path" in *comments*) cat "$S/comments.json" ;; *pulls*) echo '{"body":"built-by: fake"}' ;; *) echo '{}' ;; esac ;;
  *) echo "fake gh: unhandled $sub $*" >&2; exit 1 ;;
esac
EOF
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# behaviors come one per line from $FAKE_CLAUDE_PLAN, consumed in order; cwd is the worktree.
S="$FAKE_GH"; n=$(cat "$S/calls" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$S/calls"
plan=$(sed -n "${n}p" "$FAKE_CLAUDE_PLAN"); prompt="$(cat)"; [ -n "$prompt" ] || prompt="${@: -1}"   # stdin is the contract; the argv fallback lets (q12) fail for the real reason against an argv-passing run.sh
printf '%s' "$prompt" > "$S/prompt-$n.txt"; printf '%s\n' "$@" > "$S/args-$n.txt"
# #964: each --add-dir that exists while the session runs is recorded, and a probe is left in the run's scratch dir
prev=""; for a in "$@"; do if [ "$prev" = --add-dir ] && [ -d "$a" ]; then echo "$a" >> "$S/live-dirs-$n.txt"; case "$a" in *-scratch.*) echo "probe $n" > "$a/probe-$n.txt" ;; esac; fi; prev="$a"; done
# the session's env as claude would apply it: what it inherited, overlaid by any --settings env; the watch's own
# variables are captured too, so a leak of one into a session is visible (#939 D-29)
{ env | grep -E '^(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS|CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS|BASH_(DEFAULT|MAX)_TIMEOUT_MS|HERDR_[A-Za-z0-9_]*|RUN_WATCH[A-Za-z0-9_]*|RUN_DETACHED_LOG)='; prev=""; for a in "$@"; do [ "$prev" = --settings ] && printf '%s' "$a" | jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"'; prev="$a"; done; } | awk -F= '{ v[$1] = $0 } END { for (k in v) print v[k] }' | sort > "$S/env-$n.txt"
branch=$(git rev-parse --abbrev-ref HEAD); cost="${FAKE_COST:-1}"
push() { echo "$n" >> work.txt; git add -A >/dev/null; git commit -qm "build $n"; git push -q origin "$branch"; }
openpr() { # body as the prompt instructs: built-by line, the record link, then Closes (under the Jira heading when bracketed)
  rid=$(grep -oE 'built-by: second-shift run [^ ]+' "$S/prompt-$n.txt" | head -n 1)
  rec=$(grep -oE 'The record is committed at [^;]+' "$S/prompt-$n.txt" | head -n 1 | sed 's/^The record is committed at //')
  key=$(grep -oE "Closes (#[0-9]+|\[[^]]+\])" "$S/prompt-$n.txt" | head -n 1)
  case "${FAKE_CLOSES:-}" in lower) key="closes #42" ;; esac
  { printf '%s\n\nrecord: %s\n\n' "${rid:-built-by: second-shift run ?}" "${rec:-?}"; case "$key" in *"["*) printf '### Jira Items\n%s\n' "$key" ;; *) printf '%s\n' "${key:-Closes #?}" ;; esac; } > "$S/pr-created-body.txt"; echo 7 > "$S/prs"
}
# #991: a verdict body in the grammar verdict-check.sh enforces. A consistent one by default: D-1 (the fixture
# record's one row) honored, and a [blocker] on a needs-work; $ROWS / $FINDINGS replace either part
vbody() { # vbody <verdict> <sha> [<text after the findings>]
  local f="None."; [ "$1" = needs-work ] && f="- [blocker] B1 fake finding"
  printf 'verdict: %s\nreviewed: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n%s\n\n## Findings\n\n%s\n%s' "$1" "$2" "${ROWS-| D-1 | honored | fake |}" "${FINDINGS:-$f}" "${3:-}"
}
post() { # post <body>: one comment by the verdict author, created and updated now
  jq --arg b "$1" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg u "${FAKE_VERDICT_AUTHOR:-tester}" --arg ut "${FAKE_VERDICT_AUTHOR_TYPE:-User}" '. + [{id:(length+1),node_id:"N\(length+1)",body:$b,user:{login:$u,type:$ut},created_at:$t,updated_at:$t,html_url:"https://x/pr/7#verdict"}]' "$S/comments.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments.json"
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
  build-pr-fixbody) openpr ;;   # a PR-only fix: the body is rewritten, nothing is pushed
  build-pr-jira-outside) push; rid=$(grep -oE 'built-by: second-shift run [^ ]+' "$S/prompt-$n.txt" | head -n 1); rec=$(grep -oE 'The record is committed at [^;]+' "$S/prompt-$n.txt" | sed 's/^The record is committed at //')
                   printf '%s\n\nrecord: %s\n\nCloses [GH-42]\n\n### Jira Items\n(nothing)\n' "$rid" "$rec" > "$S/pr-created-body.txt"; echo 7 > "$S/prs" ;;
  build-pr-close)  push; openpr; echo CLOSED > "$S/state" ;;
  build-pr-dirty)  push; openpr; echo uncommitted >> work.txt ;;
  build-pr-untracked) push; openpr; printf 'it("probe", () => {});\n' > src/zz-probe.spec.ts; mkdir -p "src/probe dir"; echo scratch > "src/probe dir/notes.txt" ;;   # never committed: what a probing build leaves
  build-commit-nopush) echo "$n" >> work.txt; git add -A >/dev/null; git commit -qm "local only $n" ;;
  build-skip-test) printf 'it.skip("x", () => {});\n' >> src/a.spec.ts; mkdir -p .github/workflows; echo 'on: push' > .github/workflows/ci.yml; push; openpr ;;
  build-polyglot)  git rm -q tests/test_x.py src/__tests__/b.js; mkdir -p tests; printf '@pytest.mark.skip\ndef test_y(): pass\n' > tests/test_y.py   # #956: a non-JS weakening
                   printf 'func TestZ(t *testing.T) { t.Skip("later") }\n' > src/z_test.go; printf 'addopts = "--cov-fail-under=10"\n' > pyproject.toml
                   echo 'export default []' > eslint.config.mjs; push; openpr ;;
  build-edit-expectation) sed '1s/1999/2000/' src/b.test.ts > b.tmp && mv b.tmp src/b.test.ts   # #957: one assertion moved with the code,
                   sed 's/1999/2000/' src/__snapshots__/price.snap > s.tmp && mv s.tmp src/__snapshots__/price.snap   # a snapshot regenerated whole,
                   printf 'it("more", () => {});\n' >> src/a.spec.ts; printf 'it("new", () => {});\n' > src/c.spec.ts; push; openpr ;;   # an additive edit and a new spec
  build-path-names) for f in $'src/caf\303\251.spec.ts' scripts/x-selftest.sh; do sed '1d' "$f" > e.tmp && mv e.tmp "$f"; done   # #1011: a non-ASCII spec and a selftest each lose an expectation,
                   git rm -q 'src/old dir/y.spec.ts'; mkdir -p .github/workflows; echo 'on: push' > $'.github/workflows/caf\303\251.yml'; push; openpr ;;   # a spec under a spaced dir is deleted, a non-ASCII CI config added
  build-edit-policy) mkdir -p .claude/second-shift .claude/agents docs; git mv .claude/second-shift/security-rules.md docs/security-rules.md   # #1009: a rename out of the policy dir,
                   echo 'accepted: raw SQL' > .claude/second-shift/review-context.md; echo '{}' > .claude/second-shift.config.json   # added policy files,
                   for a in orders-reviewer billing-reviewer unlisted; do echo "$a" > ".claude/agents/$a.md"; done   # and three agents, one a bare reviewers.add[] name
                   git add -f .claude/second-shift .claude/second-shift.config.json .claude/agents; push; openpr ;;   # forced: the fixture gitignores .claude/
  build-pr-add-row) printf '| D-2 | added by the build | x | user-delegated |\n' >> "$(git ls-files 'docs/plans/*-decisions.md')"; push; openpr ;;   # #991: a row only the head carries
  build-pr-rm-record) git rm -q "$(git ls-files 'docs/plans/*-decisions.md')"; push; openpr ;;   # #991: no record at the head to check a verdict against
  review-crash)    printf '{"subtype":"error_during_execution","total_cost_usd":0}\n'; exit 1 ;;
  review-approve|review-needs-work|review-wrong-sha|review-approve-dirty|review-approve-runtime|review-approve-and-push|review-needs-work-drop-base|review-needs-work-diverge|review-needs-work-notes-reason|review-needs-work-move-base)
    sha=$(git rev-parse "origin/$branch"); [ "$plan" = review-wrong-sha ] && sha=deadbeef
    v=approve; case "$plan" in review-needs-work*) v=needs-work ;; esac
    extra=""; [ "$plan" = review-needs-work-notes-reason ] && extra=$'\n## Notes\n\nreason: render-unavailable'   # prose, not line 3
    post "$(vbody "$v" "$sha" "$extra")"
    case "$plan" in
      review-approve-dirty) echo scratch > review-scratch.txt ;;
      review-approve-runtime) mkdir -p .claude/storage; echo raw > .claude/storage/upload-1.bin ;;   # gitignored: `status --porcelain` cannot see it
      review-approve-and-push) push ;;
      review-needs-work-drop-base) git -C "$(git remote get-url origin)" update-ref -d refs/heads/main ;;
      review-needs-work-diverge) git push -q -f origin "$(git commit-tree "HEAD~1^{tree}" -p HEAD~1 -m diverged)":"refs/heads/$branch" ;;
      review-needs-work-move-base) b="$(mktemp -d)"; git clone -q "$(git remote get-url origin)" "$b" 2>/dev/null   # main edits work.txt's FIRST line; the build appends
                                   sed '1s/.*/moved/' "$b/work.txt" > "$b/w" && mv "$b/w" "$b/work.txt" && git -C "$b" commit -qam "base moves into the branch's file" && git -C "$b" push -q origin main; rm -rf "$b" ;;
    esac ;;
  # #991 AC-2: verdicts whose own comment does not back their verdict line
  review-bad-approve-blocker)  post "$(ROWS='| D-1 | honored | fake |' FINDINGS='- [blocker] B1 must change before merge' vbody approve "$(git rev-parse "origin/$branch")")" ;;
  review-bad-approve-violated) post "$(ROWS='| D-1 | violated | fake |' vbody approve "$(git rev-parse "origin/$branch")")" ;;
  review-bad-needs-work-noblocker) post "$(FINDINGS='- [note] N1 nothing required' vbody needs-work "$(git rev-parse "origin/$branch")")" ;;
  review-needs-work-mixed) # #1010: one blocker and one note, in the grammar's review-lead form
    post "$(FINDINGS=$'- [blocker] B1 [Maintainability] src/a.ts:3 (confidence: 85) — mixed blocker\n- [note] N1 [Complexity] src/a.ts:9 (confidence: 60) — mixed note' vbody needs-work "$(git rev-parse "origin/$branch")")" ;;
  review-render-unavailable) sha=$(git rev-parse "origin/$branch")
    post "$(printf 'verdict: needs-work\nreviewed: %s\nreason: render-unavailable\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n\n## Findings\n\nNone.' "$sha")" ;;
  review-two-verdicts) # both bind; the LAST posted wins: $FAKE_ORDER = needs-work,approve or approve,needs-work
    sha=$(git rev-parse "origin/$branch"); for v in ${FAKE_ORDER//,/ }; do post "$(vbody "$v" "$sha")"; done ;;
  review-silent)   : ;;
  review-detach)   git checkout -q --detach "origin/$branch"; post "$(vbody needs-work "$(git rev-parse "origin/$branch")")" ;;
esac
printf '{"subtype":"success","total_cost_usd":%s,"num_turns":3,"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"ls /"}}]}\n' "$cost"
EOF
cat > "$T/bin/watch-fake" <<'EOF'
#!/usr/bin/env bash
# the fake RUN_WATCH_CMD (#939): records each call, its argv, cwd, herdr env and process group; $FAKE_WATCH picks its behavior
S="$FAKE_GH"; echo call >> "$S/watch-calls"; printf '%s\n' "$@" > "$S/watch-args"; pwd -P > "$S/watch-cwd"
env | grep -E '^HERDR_' | sort > "$S/watch-env"; echo "$$ $(ps -o pgid= -p $$ | tr -d ' ')" > "$S/watch-pgid"
echo "WATCH-STDOUT"; echo "WATCH-STDERR" >&2
case "${FAKE_WATCH:-ok}" in
  fail) exit 3 ;;
  hang) bash -c 'trap "" TERM; exec sleep 9391' & sleep 9392 ;;   # a hung call with a TERM-ignoring grandchild
esac
EOF
chmod +x "$T/bin/gh" "$T/bin/claude" "$T/bin/watch-fake"

# ---- fixture: a bare origin, a main checkout with config + record, an empty worktree root ----
fixture() { # fixture <case> [checks-line] [extra-record] — sets $d and the env
  local c="$1" chk="${2-- true}" extra="${3:-}"; d="$T/$c"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/main" 2>/dev/null
  git -C "$d/main" symbolic-ref HEAD refs/heads/main
  mkdir -p "$d/main/src" "$d/main/.claude/pipeline-state"
  echo "x" > "$d/main/src/a.spec.ts"; echo "y" > "$d/main/src/a.ts"
  local f; for f in ${FIXTURE_FILES:-}; do mkdir -p "$d/main/$(dirname "$f")"; printf '%s\n' "${FIXTURE_BODY:-x}" > "$d/main/$f"; done   # extra base files a build can delete or edit
  local dflt='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}'
  printf '%s\n' "${FIXTURE_CONFIG:-$dflt}" > "$d/main/.claude/second-shift.config.json"
  printf '%s\n' ".claude/" > "$d/main/.gitignore"
  git -C "$d/main" add -A && git -C "$d/main" commit -qm init && git -C "$d/main" push -q -u origin main 2>/dev/null
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  # #1022 D-11: a whole v2 receipt, so the launch lint passes it (an empty checks line is the section's empty form); D-1's
  # first four cells are the text (a) greps for in the build prompt
  printf '# record\n\nReceipt: v2\n\n## Intake steps\n\nRequirements: the ticket body as written\nSplit: not split\nExplore: the fixture repo\nFan-out: skipped — by the selftest fixture\nDup-scan: no candidates\nPost-merge scan: no post-merge AC\nSizing: opus\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n\n## Open Regions\n\nNo open regions — every decision in scope is ratified.\n\n## Surface Inventory\n\nNo user-visible surface — this change renders nothing a user reads.\n\n## Fan-out\n\nFan-out: skipped — by the selftest fixture, which runs no intake\n\n## Checks\n\n%s\n%s\n' \
    "${chk:-No ticket-specific checks — the configured lanes cover this change.}" "$extra" > "$d/main/.claude/pipeline-state/42-ledger.md"
  export FAKE_GH="$d/gh"; mkdir -p "$FAKE_GH"; echo OPEN > "$FAKE_GH/state"; echo '[]' > "$FAKE_GH/comments.json"; : > "$FAKE_GH/prs"
  printf 'ready-for-dev\nopus\n' > "$FAKE_GH/labels"
  export FAKE_CLAUDE_PLAN="$d/plan"; : > "$FAKE_CLAUDE_PLAN"
  export RUN_WORKTREE_ROOT="$d/wt" RUN_CLAUDE="$T/bin/claude" RUN_GH="$T/bin/gh" SECOND_SHIFT_CONFIG="$d/main/.claude/second-shift.config.json"
  export SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="$IT_ROOT"   # the (rl) cases unset it to drive the plugin-list lookup
}
commit_record() { # the receipt already committed as the lane branch's first commit, as an earlier run leaves it: never re-linted (#1022 D-8)
  git -C "$d/main" checkout -q -b second-shift/42 && mkdir -p "$d/main/docs/plans" \
    && cp "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/docs/plans/main-42-decisions.md" \
    && git -C "$d/main" add docs/plans/main-42-decisions.md && git -C "$d/main" commit -qm "docs: decision record for #42" \
    && git -C "$d/main" push -q origin second-shift/42 2>/dev/null && git -C "$d/main" checkout -q main && git -C "$d/main" branch -q -D second-shift/42
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
grep -q 'Claimed by .*/dev-pipeline:run' "$FAKE_GH/issue-comments" && ! grep -q 'dev-pipeline:build' "$FAKE_GH/issue-comments" && ok "(a) a run's claim marker names /dev-pipeline:run" || bad "(a) run marker: $(grep 'Claimed by' "$FAKE_GH/issue-comments")"
! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-1.txt" && ! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-2.txt" && ok "(a) [F1] neither session is resumed or continued" || bad "(a) [F1] a session was resumed"
[ "$(tr '\n' ' ' < "$FAKE_GH/env-1.txt")" = "BASH_DEFAULT_TIMEOUT_MS=6900000 BASH_MAX_TIMEOUT_MS=6900000 CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 " ] && ok "(a) [F-env] BUILD: background tasks off, Bash timeouts 300 s inside the 7200 s bound" || bad "(a) [F-env] BUILD spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
[ "$(tr '\n' ' ' < "$FAKE_GH/env-2.txt")" = "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=3300000 " ] && ok "(a) [F-env] REVIEW: background tasks kept, their wait 300 s inside the 3600 s bound" || bad "(a) [F-env] REVIEW spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-2.txt")"
[ ! -d "$d/wt/42" ] && ok "(a) worktree torn down on approve" || bad "(a) worktree left after approve"
grep -q 'Closes #42' "$FAKE_GH/prompt-1.txt" && grep -q 'gh pr create --draft' "$FAKE_GH/prompt-1.txt" && ok "(a) build prompt asks for a draft PR that closes the ticket" || bad "(a) PR conventions missing from the build prompt"
grep -q 'AskUserQuestion' "$FAKE_GH/args-1.txt" && ! grep -q 'editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(a) keyboard tools disallowed, no jira strip under github" || bad "(a) disallowed-tools list wrong"
grep -q 'DECLARE THE PIPELINE DEFAULT PANEL' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt declares the panel" || bad "(a) panel declaration missing"
grep -q 'the expected call whenever the diff introduces a surface' "$FAKE_GH/prompt-2.txt" && grep -q 'Do not stand in for a specialist' "$FAKE_GH/prompt-2.txt" && grep -q 'pass the decline to review-lead with a one-line reason' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt: opting a reviewer in is the expected call on an introduced surface, the lead pass is no stand-in, and a decline carries a reason" || bad "(a) judgment opt-in / decline-with-reason missing from the review prompt"
grep -q 'models: build opus (label), review opus (default)' <<<"$OUT" && ok "(a) [A4 A6] build model read from the opus label; tiers are passed to the CLI as aliases, never pinned ids" || bad "(a) model line: $(grep 'models:' <<<"$OUT")"
! grep -q 'claude-opus-[0-9]' "$FAKE_GH/args-1.txt" && grep -q '^opus$' "$FAKE_GH/args-1.txt" && ok "(a) [A6] the session is launched with --model opus" || bad "(a) [A6] a pinned model id reached the session: $(grep -A1 -- '--model' "$FAKE_GH/args-1.txt" | tr '\n' ' ')"
first=$(git -C "$d/origin.git" log --format=%s --reverse main..second-shift/42 | head -n 1)
[ "$first" = "docs: decision record for #42" ] && ok "(a) the record is the branch's first commit" || bad "(a) first commit is '$first'"
grep -q '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md" 2>/dev/null && grep -q 'built-by: fake' "$FAKE_GH/pr-body.md" && grep -q '| approved |' "$FAKE_GH/pr-body.md" && ok "(a) run block written into the PR body, original body kept" || bad "(a) no run block in the PR body"
grep -qE '^[|] review-1[.]1 [|] 3 [|] [$]1[.]00 [|]' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(a) per-session cost rows in the block" || bad "(a) per-session rows missing"
grep -q 'ls /' "$(SD)/review-1.1.prompt" && ok "(a) build denials reach the review input" || bad "(a) denials missing from review input"
grep -qF 'A denied command is not a reason to end your turn: skip a command outside the allowlist and name it in the PR body as skipped. Pushing second-shift/42 and opening the draft PR are never skipped.' "$FAKE_GH/prompt-1.txt" \
  && ok "(a) #973 D-3: the build prompt says a denial is not a stop, and pushing and the draft PR are never skipped" || bad "(a) #973 D-3: the denial-is-not-a-stop line is missing from the build prompt"

# (ho) --handoff (/dev-pipeline:build): claim, worktree, record, prompt — then stop; the calling session builds
fixture ho; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect build-handoff "(ho) an unsized ticket is handed to the calling session"
[ "$RC" -eq 0 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(ho) exit 0 and no session spawned" || bad "(ho) rc=$RC, claude calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"
hp="$(sed -n 's/^prompt: //p' <<<"$OUT")"; hw="$(sed -n 's/^worktree: //p' <<<"$OUT")"
[ -n "$hp" ] && grep -q 'Implement ticket 42' "$hp" && grep -q 'D-1' "$hp" && [ -d "$hw" ] && ok "(ho) the build prompt and worktree are printed" || bad "(ho) prompt '$hp' / worktree '$hw'"
# The closing comment is public: the worktree path stays in the local log, never on the tracker.
grep -q 'build-handoff' "$FAKE_GH/issue-comments" && ! grep -qF "$hw" "$FAKE_GH/issue-comments" && grep -q '<worktree>' "$FAKE_GH/issue-comments" \
  && ok "(ho) the handoff comment names <worktree>, never the local path" || bad "(ho) local path in the tracker comment: $(grep build-handoff "$FAKE_GH/issue-comments")"
[ "$(git -C "$d/origin.git" log --format=%s main..second-shift/42 2>/dev/null)" = "docs: decision record for #42" ] && ok "(ho) the record is the pushed branch's only commit" || bad "(ho) branch: $(git -C "$d/origin.git" log --oneline main..second-shift/42 2>&1 | tr '\n' '|')"
grep -qx in-progress "$FAKE_GH/labels" && grep -q 'Claimed by .*/dev-pipeline:build' "$FAKE_GH/issue-comments" && ok "(ho) claimed, and the marker names /dev-pipeline:build" || bad "(ho) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
hb="$(sed -n 's/^baseline: //p' <<<"$OUT")"
[ -n "$hb" ] && [ "$hb" = "$(git -C "$d/origin.git" rev-parse second-shift/42)" ] && grep -q "Record baseline: $hb" "$hp" && grep -q "never amend, rebase or force-push over it" "$hp" && ok "(ho) the record baseline is printed and pinned in the prompt" || bad "(ho) baseline '$hb'"
grep -q '^unpriced: build-in-calling-session' "$FAKE_GH/issue-comments" && ok "(ho) the closing comment says the build is unpriced, not \$0" || bad "(ho) closing comment: $(grep -A1 cost_usd "$FAKE_GH/issue-comments" | tr '\n' '|')"
! grep -q '\[run\] scratch: ' <<<"$OUT" && grep -q 'Delete every probe or scratch file you created' "$hp" && ! grep -q 'Run every check in the foreground' "$hp" \
  && ok "(ho) #964 D-10: no scratch dir for a handoff; its prompt keeps the delete sentence and no foreground rule" || bad "(ho) #964 D-10: handoff scratch/prompt wrong"
lane_says() { jq --arg b "$1" --arg t "$2" '. + [{body:$b,user:{login:"tester",type:"User"},created_at:$t,updated_at:$t}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"; }
# re-entry reads the marker the handoff itself posted (the fake gh logs comments; it does not list them back)
hm="$(awk '/--body <!-- dev-pipeline -->/{on=1; sub(/^.*--body /,"")} on{print} on && /^second-shift-run: /{exit}' "$FAKE_GH/issue-comments")"
grep -qx '<!-- stage: lean-claimed -->' <<<"$hm" && ok "(ho) the handoff posts the lane's claim marker" || bad "(ho) handoff marker: $(tr '\n' '|' <<<"$hm")"
lane_says "$hm" 2020-01-01T00:00:00Z
lane_says 'second-shift run h1: build-handoff — BUILD handed to the calling session' 2020-01-02T00:00:00Z
run_case "$d" --handoff; expect build-handoff "(ho) a second handoff re-enters its own claim"
echo opus >> "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(ho) a plain run refuses a claim handed to /dev-pipeline:build"
[ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(ho) the refusal exits 2 and spawns no second writer" || bad "(ho) rc=$RC, claude calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"
lane_says 'second-shift run h2: build-no-pr — no open PR' 2020-01-03T00:00:00Z; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(ho) a later closing comment ends the handoff's hold"
fixture ho3; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
lane_says $'<!-- run_id: h1 -->\n<!-- stage: lean-claimed -->' 2020-01-01T00:00:00Z; lane_says 'second-shift run h1: build-handoff — BUILD handed to the calling session' 2020-01-02T00:00:00Z
run_case "$d" --resume; expect approved "(ho3) --resume hands a handed-off ticket back to the lane"
fixture ho4 ""; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect env-no-checks "(ho4) a handoff with no check to hand over is refused"
[ "$RC" -eq 2 ] && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] && [ ! -d "$d/wt" ] && ok "(ho4) refused before the claim: nothing written" || bad "(ho4) rc=$RC labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"allowUnverified":true}}}' fixture ho5 ""; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect build-handoff "(ho5) allowUnverified accepts a zero-check handoff"
fixture ho2; OUT="$( cd "$d/main" && bash "$RUN" 42 --handoff --detach 2>&1 )"; RC=$?
grep -q '^terminal: usage-handoff-detach$' <<<"$OUT" && [ "$RC" -eq 2 ] && ok "(ho2) --handoff with --detach is a usage refusal" || bad "(ho2) rc=$RC: $(tail -n 1 <<<"$OUT")"

# (b) needs-work then approve: two rounds, findings reach the round-2 build prompt
fixture b; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(b) needs-work, fix, approve"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-3.txt" && ok "(b) round-2 build prompt carries the findings" || bad "(b) findings not in round-2 prompt"
printf '%s\n' "$OUT" | grep -q '2 round' && ok "(b) two rounds counted" || bad "(b) round count wrong"

# (b3) #1010: a mixed needs-work (a blocker, a note) binds, and its round-2 build is ordered to act on the blocker, not the note.
# A grep on the emitted prompt, by necessity: the fake build never reads its prompt, so no run can show what it was told
fixture b3; printf 'build-pr\nreview-needs-work-mixed\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(b3) a mixed needs-work binds, fix, approve"
grep -qF -- '- [blocker] B1 [Maintainability] src/a.ts:3 (confidence: 85)' "$FAKE_GH/prompt-3.txt" && grep -qF -- '- [note] N1 [Complexity] src/a.ts:9 (confidence: 60)' "$FAKE_GH/prompt-3.txt" \
  && ok "(b3) both finding lines, confidence included, reach the round-2 build" || bad "(b3) a finding line is missing from prompt-3"
grep -qF 'fix each [blocker] finding, or rebut it' "$FAKE_GH/prompt-3.txt" && grep -qF 'violated or undeterminable' "$FAKE_GH/prompt-3.txt" \
  && ok "(b3) the build is ordered to fix or rebut each blocker and fix each bad row" || bad "(b3) the round-2 prompt does not split blockers from notes"
grep -qF 'A [note] finding requires nothing' "$FAKE_GH/prompt-3.txt" && ok "(b3) a note is named optional" || bad "(b3) the round-2 prompt does not free the notes"
! grep -qF 'fix each, or rebut it' "$FAKE_GH/prompt-3.txt" && ok "(b3) the every-finding order is gone" || bad "(b3) the prompt still orders every finding addressed"

# (b2) a check red in round 2 sits beside the review's findings, never in place of them: the retry still has what the review asked for
fixture b2 "- ! grep -qx 3 work.txt"; printf 'build-pr\nreview-needs-work\nbuild-push-only\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"
RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(b2) green, needs-work, then red twice"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-4.txt" && ok "(b2) the red retry still carries the review's findings" || bad "(b2) the red check replaced the review's findings"
grep -q '^## Red check output' "$FAKE_GH/prompt-4.txt" && grep -q 'cannot be rebutted' "$FAKE_GH/prompt-4.txt" && ok "(b2) the red check is handed over as a red check" || bad "(b2) the red check is not named as one"

# (c) no PR after the build
fixture c; printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-no-pr "(c) push without a PR"

# (d) E21: a build that left uncommitted work stops the run and nothing discards that work
fixture d; printf 'build-pr-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-inflight "(d) [E21] a build that left uncommitted work in the worktree is in flight"
[ -n "$(git -C "$d/wt/42" status --porcelain 2>/dev/null)" ] && ok "(d) [E21] the uncommitted work is still there, never reset away" || bad "(d) [E21] the worktree was cleaned — the build's work was discarded"
grep -qE '\[run\] terminal: build-inflight — .*its tree is not clean; it was denied 1 command\(s\), listed in .*/denials-1\.1\.txt\) ' <<<"$OUT" \
  && ok "(d) #973 D-2: the build-inflight detail cites the denials file" || bad "(d) #973 D-2: detail: $(grep 'terminal: build-inflight' <<<"$OUT")"
# (dn) #973 D-4: a session whose result JSON carried no permission_denials is unread, never "none", and the detail says so
cat > "$T/bin/claude-nodenials" <<EOF
#!/usr/bin/env bash
"$T/bin/claude" "\$@" | jq -c 'del(.permission_denials)'
EOF
chmod +x "$T/bin/claude-nodenials"
fixture dn; printf 'build-pr-dirty\n' > "$FAKE_CLAUDE_PLAN"; RUN_CLAUDE="$T/bin/claude-nodenials" run_case "$d"; expect build-inflight "(dn) a dirty tree with unread denials is still in flight"
grep -qE '\[run\] terminal: build-inflight — .*its tree is not clean; its permission denials are unread ' <<<"$OUT" \
  && ok "(dn) #973 D-4: the detail says the denials are unread" || bad "(dn) #973 D-4: detail: $(grep 'terminal: build-inflight' <<<"$OUT")"

# (dq) #926: untracked files alone, on a tree at the pushed head, are archived and the run goes on. The check fails if the
# probe is still in the tree, so it also proves the archive happens before the checks run
fixture dq "- test ! -e src/zz-probe.spec.ts"; printf 'build-pr-untracked\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(dq) a build that left only untracked probes behind is not in flight"
toc="$(tar -tf "$(SD)/quarantine-1.1.tar" 2>/dev/null)"
grep -qx 'src/zz-probe.spec.ts' <<<"$toc" && grep -qx 'src/probe dir/notes.txt' <<<"$toc" && ok "(dq) both files, one entry each, are in quarantine-1.1.tar" || bad "(dq) archive holds: $(tr '\n' ' ' <<<"$toc")"
grep -qE 'archived 2 untracked file\(s\) left in .* to .*/quarantine-1\.1\.tar ' <<<"$OUT" && ok "(dq) the log names the count and the archive" || bad "(dq) no archive line in the log"
sec="$(awk '/^### Untracked files archived/{on=1; next} /^###/{on=0} on' "$(SD)/review-input-1.1.md" 2>/dev/null)"
grep -qx 'src/zz-probe.spec.ts' <<<"$sec" && ok "(dq) the review input lists the archived path" || bad "(dq) review input lacks the archived path"
grep -q 'Put scratch files there; the scheduler removes it' "$FAKE_GH/prompt-1.txt" && ! grep -q 'Delete every probe' "$FAKE_GH/prompt-1.txt" && ok "(dq) #964 D-1: the build prompt puts probes in the scratch dir instead of asking the build to delete them" || bad "(dq) #964 D-1: scratch sentence missing from prompt-1, or the delete sentence kept"
grep -q 'A stored field the change newly reads, or a field it sends across a service boundary, gets a test that moves it through the real schema or model' "$FAKE_GH/prompt-1.txt" && ok "(dq) #950: the build prompt obliges a round-trip test for a newly read stored field" || bad "(dq) #950: round-trip sentence missing from prompt-1"
grep -q 'A test double of a dependency this repo does not own that returns an error or an empty result cites where that shape comes from' "$FAKE_GH/prompt-1.txt" && ok "(dq) #961: the build prompt asks an unowned dependency's error/empty double to cite its source" || bad "(dq) #961: unowned-double sentence missing from prompt-1"
[ ! -d "$d/wt/42" ] && ok "(dq) the worktree is removed at close-out" || bad "(dq) worktree left in place"

# (sc) #964 D-1 D-2 D-3: one scratch dir per run, outside .claude/, live during both spawns, named in both prompts;
# archived into $STATE and removed at exit. Neither session is handed $STATE
fixture sc; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(sc) a run with a scratch dir"
scr="$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | grep -- '-scratch\.' | head -n 1)"
[ -n "$scr" ] && case "$scr" in */.claude/*) false ;; "$(cd "${TMPDIR:-/tmp}" && pwd -P)"/second-shift-42-scratch.*) true ;; *) false ;; esac \
  && ok "(sc) D-1: the build is handed a scratch dir under \$TMPDIR, outside .claude/" || bad "(sc) D-1: build scratch dir '${scr:-none}'"
grep -qxF -- "$scr" "$FAKE_GH/live-dirs-1.txt" 2>/dev/null && grep -qxF -- "$scr" "$FAKE_GH/live-dirs-2.txt" 2>/dev/null && [ "$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-2.txt" | grep -cxF -- "$scr")" = 1 ] \
  && ok "(sc) D-1: the same dir is in both spawns' --add-dir and exists while each runs" || bad "(sc) D-1: live dirs: $(cat "$FAKE_GH"/live-dirs-*.txt 2>/dev/null | tr '\n' ' ')"
grep -qF "$scr" "$FAKE_GH/prompt-1.txt" && grep -qF "$scr" "$FAKE_GH/prompt-2.txt" && grep -q 'Put scratch files there; the scheduler removes it' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) D-1: both prompts name the scratch dir as the place for scratch files" || bad "(sc) D-1: a prompt does not name $scr"
toc="$(tar -tf "$(SD)/scratch.tar" 2>/dev/null)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" && grep -qx './probe-2.txt' <<<"$toc" \
  && ok "(sc) D-2: at exit the dir is gone and both sessions' files are in \$STATE/scratch.tar" || bad "(sc) D-2: dir $([ -e "$scr" ] && echo kept || echo gone), archive: $(tr '\n' ' ' <<<"$toc")"
ads="$(grep -h -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" "$FAKE_GH/args-2.txt")"
[ -n "$ads" ] && ! grep -qF "/run-42/" <<<"$ads" && grep -q 'code-review.mjs' "$FAKE_GH/prompt-2.txt" && grep -qF "writing it with Write into $scr," "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) D-3: the review stages code-review.mjs in the scratch dir and is not handed \$STATE" || bad "(sc) D-3: \$STATE still granted, or the staging sentence does not name $scr"
# the prompt lines (S-3), one case each
grep -q 'Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables' "$FAKE_GH/prompt-1.txt" && grep -q 'Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: both prompts ask for one command per call, absolute paths, no cd or variables" || bad "(sc) S-3: one-command line missing"
grep -q 'Edit files only with the Edit and Write tools, never through a shell' "$FAKE_GH/prompt-1.txt" && grep -q 'Write files only with the Write tool, never through a shell' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: files are edited with Edit/Write only, never a shell rewrite" || bad "(sc) S-3: Edit/Write line missing"
grep -q 'Run every check in the foreground: no nohup, no trailing &' "$FAKE_GH/prompt-1.txt" && grep -q 'no nohup or trailing &' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: no nohup or backgrounded commands" || bad "(sc) S-3: foreground line missing"
grep -q 'Pass every PR or comment body with --body-file' "$FAKE_GH/prompt-1.txt" && grep -qF "passed with --body-file <a file in $scr>" "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: PR and comment bodies go through --body-file" || bad "(sc) S-3: --body-file line missing"
grep -q "Do not run the repo's test suites or checks: the scheduler ran them at this head" "$FAKE_GH/prompt-2.txt" && ! grep -q "Do not run the repo's test suites" "$FAKE_GH/prompt-1.txt" \
  && ok "(sc) S-3: the review does not re-run the suites" || bad "(sc) S-3: review no-suites line missing (or in the build prompt)"
# D-4: the review's denials are recorded beside the build's, and the run block counts them per session
# shellcheck disable=SC2016  # the run block's literal dollar costs
grep -q 'ls /' "$(SD)/denials-review-1.1.txt" 2>/dev/null && grep -qxF '| session | turns | cost | denials |' "$FAKE_GH/pr-body.md" \
  && grep -qxF '| build-1.1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" && grep -qxF '| review-1.1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" \
  && ok "(sc) D-4: denials-review-1.1.txt is written and the run block counts each session's denials" || bad "(sc) D-4: $(grep -E '^\| (session|build|review)' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
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
fixture l3c; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=2.43739 run_case "$d"; expect approved "(l3c) fractional session costs"
grep -qE '[|] [$]4[.]87 [|]' "$FAKE_GH/pr-body.md" && grep -qE '^[|] build-1[.]1 [|] 3 [|] [$]2[.]44 [|]' "$FAKE_GH/pr-body.md" && grep -q '^cost_usd: 4.87$' "$FAKE_GH/issue-comments" && ok "(l3c) every reported cost is rounded to two decimals" || bad "(l3c) costs: $(grep -E '[$][0-9]|cost_usd' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" | tr '\n' '|')"
grep -q 'round(s), [$]4[.]87$' <<<"$OUT" && ! grep -q '4[.]874' "$FAKE_GH/issue-comments" && ! grep -q '4[.]874' <<<"$OUT" && ok "(l3c) the terminal message and closing comment carry the rounded total too" || bad "(l3c) raw total leaked: $(grep -h '4[.]874' "$FAKE_GH/issue-comments" - <<<"$OUT" | head -n 2 | tr '\n' '|')"
fixture l3d; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=2.43739 LC_NUMERIC=de_DE.UTF-8 run_case "$d"; expect approved "(l3d) a comma-decimal locale"
grep -qE '^[|] build-1[.]1 [|] 3 [|] [$]2[.]44 [|]' "$FAKE_GH/pr-body.md" && ! grep -q '2,44' "$FAKE_GH/pr-body.md" && ok "(l3d) costs keep a dot decimal whatever the locale" || bad "(l3d) $(grep -E '[$][0-9]' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
fixture l3e; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=50.002 RUN_COST_CEILING=100 run_case "$d"; expect cost-spent "(l3e) 100.004 against a \$100 ceiling"
grep -q '[$]100[.]01 exceeds the [$]100 ceiling' <<<"$OUT" && ok "(l3e) a cost-spent figure is rounded up, never to the ceiling itself" || bad "(l3e) $(grep 'exceeds' <<<"$OUT" | tail -n 1)"
fixture l4; rm "$d/main/.claude/pipeline-state/42-ledger.md"; run_case "$d"; expect env-no-record "(l4) no intake record"; [ "$RC" -eq 3 ] && ok "(l4) [B6 K8] env-no-record exits 3 (resumable)" || bad "(l4) exit $RC"
fixture l5; run_case "$d" --dry-run; expect usage-dry-run "(l5) the removed --dry-run is refused by name"; [ "$RC" -eq 2 ] && ok "(l5) usage-dry-run exits 2" || bad "(l5) exit $RC"
[ ! -f "$FAKE_GH/calls" ] && ok "(l5) nothing spawned on --dry-run" || bad "(l5) claude called on --dry-run"

# (n) queue discipline and sizing, as the old lane enforced them
fixture n1; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n1) no queue label"
fixture n2; printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n2) blocker label refuses pickup"
fixture n3; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d"; expect usage-model "(n3) unlabeled ticket is not sized here"
grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/issue-comments" ] && ok "(n3) refused BEFORE the claim: still queued, nothing written" || bad "(n3) the claim ran before the sizing refusal"
fixture n4; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --model claude-sonnet-5 --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(n4) --model overrides the missing label"
grep -q 'models: build claude-sonnet-5 (flag), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(n4) override models logged" || bad "(n4) override not applied"
fixture n5; printf '{"tracker":{"type":"github","branchPrefix":"claude/acme-"},"paths":{"plansDir":"docs/plans"}}\n' > "$d/main/.claude/second-shift.config.json"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/claude/acme-42 >/dev/null && ok "(n5) branch honors tracker.branchPrefix" || bad "(n5) no claude/acme-42 on origin: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
# (n6-n9) C6a: the gitignored per-engineer <config>.local.json may override tracker.branchPrefix and nothing else
local_cfg() { printf '%s\n' "$1" > "$d/main/.claude/second-shift.config.local.json"; }
fixture n6; printf '{"tracker":{"type":"github","branchPrefix":"claude/acme-"},"paths":{"plansDir":"docs/plans"}}\n' > "$d/main/.claude/second-shift.config.json"
local_cfg '{"tracker":{"branchPrefix":"jdoe/"}}'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(n6) a run with a local branch-prefix override"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/jdoe/42 >/dev/null && ! git -C "$d/origin.git" rev-parse -q --verify refs/heads/claude/acme-42 >/dev/null \
  && ok "(n6) the local branchPrefix wins over the committed one" || bad "(n6) branches on origin: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
grep -q "branch prefix 'jdoe/' from second-shift.config.local.json (overrides the committed 'claude/acme-')" <<<"$OUT" \
  && ok "(n6) the override is named in the run log, with the prefix it replaced" || bad "(n6) no override line: $(grep 'branch prefix' <<<"$OUT")"
fixture n7; local_cfg '{"tracker":{"branchPrefix":"jdoe/"},"run":{"maxRounds":9}}'; run_case "$d"; expect env-config-local "(n7) a local file that sets a team key is refused"
grep -q 'sets run.maxRounds' <<<"$OUT" && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] \
  && ok "(n7) refused before the claim, naming the key" || bad "(n7) $(grep 'terminal' <<<"$OUT" | head -n 1)"
fixture n8; local_cfg '{"tracker":{"branchPrefix":"jdoe/"}}'; git -C "$d/main" add -f .claude/second-shift.config.local.json && git -C "$d/main" commit -qm local
run_case "$d"; expect env-config-local "(n8) a committed local file is refused"
grep -q 'is committed' <<<"$OUT" && ok "(n8) the refusal says it is committed" || bad "(n8) $(grep 'terminal' <<<"$OUT" | head -n 1)"
fixture n9; local_cfg 'jdoe/'; run_case "$d"; expect env-config-local "(n9) an unparseable local file is refused, never ignored"
fixture n9b; local_cfg '{"tracker":{"branchPrefix":""}}'; run_case "$d"; expect env-config-local "(n9b) an empty local branchPrefix is refused, never a silent fall-back to the committed one"

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
fixture p9; run_case "$d" --review-model claude-sonnet-5; [ "$RC" -eq 2 ] && ok "(p9) --review-model without --review-model-basis is refused" || bad "(p9) exit $RC"
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
# (q12) a red lane that writes megabytes (a web server's request log): the next build still starts, reads the prompt on
# stdin, and gets each red check's tail — passed as an argument it overran the exec limit and the session died as rc 126
fixture q12 "- yes 'chatty check output line' | head -n 60000; false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"
expect checks-red-spent "(q12) a red lane that writes megabytes still reaches a second build"
p2="$FAKE_GH/prompt-2.txt"
[ -s "$p2" ] && [ "$(wc -c < "$p2")" -lt 300000 ] && grep -q '^RED: yes' "$p2" && grep -q 'earlier lines of this check cut' "$p2" && ok "(q12) the second build reads a capped excerpt naming the red check" || bad "(q12) prompt-2: $(wc -c < "$p2" 2>/dev/null) bytes"
grep -q 'Implement ticket 42' "$FAKE_GH/prompt-1.txt" && ! grep -q 'Implement ticket 42' "$FAKE_GH/args-1.txt" && ok "(q12) the prompt arrives on stdin, never as an argument" || bad "(q12) the prompt rode argv or never arrived"
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
u3_head="$(git -C "$d/origin.git" rev-parse second-shift/42)"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect staleness-expired "(u3) on re-entry the base move since the BRANCH POINT is seen"; [ "$RC" -eq 7 ] && ok "(u3) [B12] staleness-expired exits 7" || bad "(u3) exit $RC"
grep -q 'the rebase onto [0-9a-f]* conflicts in: work.txt' <<<"$OUT" && [ "$(git -C "$d/origin.git" rev-parse second-shift/42)" = "$u3_head" ] && [ -z "$(git -C "$d/wt/42" status --porcelain 2>/dev/null)" ] \
  && ok "(u3) a conflicting rebase is aborted: the stop names the file, origin and the worktree are as they were" || bad "(u3) $(grep -E 'terminal|rebase' <<<"$OUT" | tr '\n' '|')"
# (u3r) a base move into the branch's file that git rebases cleanly goes on: the branch is rebased and pushed, and the
#       record baseline — in the PR body and in the next build's prompt — follows the rewritten record commit
FIXTURE_FILES=work.txt FIXTURE_BODY=$'a\nb\nc\nd\ne' fixture u3r; commit_record
first0="$(git -C "$d/origin.git" log --format=%H --diff-filter=A second-shift/42 -- docs/plans/main-42-decisions.md | tail -n 1)"
printf 'built-by: fake\n\nRecord baseline: %s\n' "${first0:0:12}" > "$FAKE_GH/live-body"
cat > "$T/bin/gh-body" <<EOF
#!/usr/bin/env bash
# the PR body as GitHub serves it: --jq .body reads it raw, a PATCH replaces it and is kept in order
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then cat "\$FAKE_GH/live-body"; exit 0; fi
if [ "\$1 \$2 \$3" = "api -X PATCH" ]; then for a in "\$@"; do case "\$a" in body=@*) cp "\${a#body=@}" "\$FAKE_GH/live-body"; { cat "\${a#body=@}"; echo '<!-- end of patch -->'; } >> "\$FAKE_GH/patches" ;; esac; done; fi
exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-body"; printf 'build-pr\nreview-needs-work-move-base\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
RUN_GH="$T/bin/gh-body" run_case "$d"; expect approved "(u3r) a clean rebase onto a base that moved into the branch's file does not stop the run"
first1="$(git -C "$d/origin.git" log --format=%H --diff-filter=A second-shift/42 -- docs/plans/main-42-decisions.md | tail -n 1)"
git -C "$d/origin.git" merge-base --is-ancestor main second-shift/42 && [ "$(git -C "$d/origin.git" show second-shift/42:work.txt | head -n 1)" = moved ] && [ "$first1" != "$first0" ] \
  && ok "(u3r) the branch on origin is rebased onto the moved base and its record commit is new" || bad "(u3r) origin: first $first0 -> $first1, work.txt line 1 '$(git -C "$d/origin.git" show second-shift/42:work.txt | head -n 1)'"
grep -qx "Record baseline: $first1" "$FAKE_GH/patches" && grep -qx "Record baseline: $first1" "$FAKE_GH/live-body" && grep -q "Record baseline: $first1" "$FAKE_GH/prompt-3.txt" \
  && ok "(u3r) the PR body's 'Record baseline:' line and the round-2 build prompt name the rebased record commit" || bad "(u3r) baseline: body $(grep 'Record baseline' "$FAKE_GH/live-body"), want $first1"
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
# #985: the bot-commit call the prompt names, and the 'bash <helper>' form the scheduler itself uses, both match a granted prefix
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); bcall=$(grep -o "'[^']*/bot-commit\.sh -C [^']*'" "$FAKE_GH/prompt-1.txt" | tr -d "'" | sed 's/<[^>]*>/msg.txt/')
granted() { # granted <command> [<allowlist>, default $bal]: a 'Bash(x*)' rule matches by prefix, a 'Bash(x)' rule exactly
  local r p; IFS=, read -r -a r <<<"${2-$bal}"
  for p in "${r[@]}"; do case "$p" in Bash\(*\*\)) p="${p#Bash(}"; [[ "$1" == "${p%\*)}"* ]] && return 0 ;; Bash\(*\)) p="${p#Bash(}"; [ "$1" = "${p%)}" ] && return 0 ;; esac; done; return 1; }
[ -n "$bcall" ] && granted "$bcall" && granted "bash $bcall" && ok "(v1) the prompt's bot-commit call and its bash form are both granted" || bad "(v1) bot-commit call '${bcall:-none}' not granted, bare or through bash"
[ "$(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)" = 'second-shift-bot[bot]' ] && ok "(v1) [E3] the record commit carries the bot's identity" || bad "(v1) [E3] record commit author: $(git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 | head -n 1)"
# every command of a piped or chained check is granted (each is checked on its own), a later one by its own text only,
# never one led by rm; the build may run its worktree's scripts, the review jq and shasum
fixture vg $'- printf x | xargs -0 echo -e a,b\n- true && cat /dev/null\n- true && rm -rf a,b'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(vg) piped and chained checks"
bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1); ral=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-2.txt" | tail -n 1); wt=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | sed -n 2p)
miss=""; for c in 'printf x' 'xargs -0 echo -e a,b' 'true' 'cat /dev/null' "bash $wt/t.sh"; do granted "$c" || miss="$miss [$c]"; done
for c in 'jq -n 1' 'shasum x'; do granted "$c" "$ral" || miss="$miss [review: $c]"; done
for c in 'xargs rm x' 'cat /etc/passwd' 'cat /dev/null /etc/passwd' 'rm -rf x'; do granted "$c" && miss="$miss [granted: $c]"; done
[ -n "$wt" ] && [ -z "$miss" ] && ok "(vg) each command of a piped or chained check is granted by its own text, rm never; worktree scripts, jq and shasum are" || bad "(vg) allowlist wrong:$miss"
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
# the launch lint refuses this receipt from disk (#1022), so the smoke's own guard is reached the way a record the lint
# never saw reaches it: committed on the branch already
run_case "$d"; expect env-receipt-invalid "(v6) the same frames row in a receipt on disk is refused at launch"
grep -q 'receipt: ledger-lint: VIOLATION: malformed design frames row' <<<"$OUT" && ok "(v6) the refusal prints the lint's violation" || bad "(v6) violation not printed: $(grep 'receipt: ' <<<"$OUT" | head -n 3)"
commit_record; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(v6) a frames row with no must-show value is red, never silently green (D-4)"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["e2e-runner --all"]}]}}}' fixture v7 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
grep -q 'e2e-runner --all' "$FAKE_GH/prompt-1.txt" && grep -q 'Bash(e2e-runner\*)' "$FAKE_GH/args-1.txt" && ok "(v7) a when-globbed lane is named in the round-1 prompt and allowlist before any diff exists" || bad "(v7) lane missing from the prompt or allowlist"

# (w) round-eight parity: PR conventions asserted, a stopped run still leaves its block,
#     claimed-elsewhere exits 2, second run's block is its own
# E22 E23: a lane PR is a draft until a review approves its head — GitHub refuses to merge a draft
fixture w1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w1) [E22 E23] a ready PR from the build"
[ "$(cut -d' ' -f2 "$FAKE_GH/ready-calls" 2>/dev/null | tr '\n' ' ')" = "undo ready " ] && ok "(w1) [E22 E23] turned into a draft after the build, marked ready only on the approve" || bad "(w1) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
[ ! -f "$FAKE_GH/draft" ] && grep -q 'marked ready for review — approved at' "$FAKE_GH/pr-body.md" && ok "(w1) [E23] the approved PR is ready and its run block says so" || bad "(w1) still a draft, or no note in the run block"
fixture w1d; printf 'build-pr-draft\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(w1d) [E22] a draft PR is no finding"
[ "$(cut -d' ' -f2 "$FAKE_GH/ready-calls" 2>/dev/null | tr '\n' ' ')" = "ready " ] && ok "(w1d) [E22 E23] a draft is left a draft, then marked ready on the approve" || bad "(w1d) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
fixture w1n; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(w1n) [E23] needs-work, then the rounds are spent"
[ -f "$FAKE_GH/draft" ] && ! grep -q ' ready$' "$FAKE_GH/ready-calls" 2>/dev/null && ok "(w1n) [E23] a run that ends without an approve leaves the PR a draft" || bad "(w1n) flips: $(tr '\n' '|' < "$FAKE_GH/ready-calls" 2>/dev/null)"
fixture w1f; printf 'build-pr-draft\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'HTTP 403: Resource not accessible by integration' > "$FAKE_GH/ready-fail"; run_case "$d"; expect approved "(w1f) [E23] a flip that fails is not fatal"
grep -q 'still a draft — marking it ready failed (HTTP 403' "$FAKE_GH/pr-body.md" && ok "(w1f) [E23] the run block names the failed flip and its reason" || bad "(w1f) run block: $(grep 'draft' "$FAKE_GH/pr-body.md" 2>/dev/null | head -2 | tr '\n' '|')"
fixture w1b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_CLOSES=lower run_case "$d"; expect approved "(w1b) a lowercase 'closes #42' is accepted, as the old gate matched it"
fixture w2; printf 'build-pr-nobody\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(w2) a PR body without built-by/Closes is sent back, then spent"
grep -q "Closes #42" "$FAKE_GH/prompt-2.txt" && ok "(w2) the convention finding reaches the next build prompt" || bad "(w2) finding not in the next prompt"
fixture w3; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(w3) stopped after a PR exists"
grep -q '| review-unbound |' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(w3) a stopped run still writes its run block into the PR body" || bad "(w3) no run block on a stopped run"
fixture w4; echo in-progress > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 2 ] && ok "(w4) claimed-elsewhere spawned nothing and exits 2" || bad "(w4) exit $RC"
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
scr="$(sed -n 's/^.* \[run\] scratch: \(.*\) (both sessions.*$/\1/p' "$d/x1.log")"; toc="$(tar -tf "$(SD)/scratch.tar" 2>&1)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" \
  && ok "(x1) #964 D-2: on TERM the scratch dir is archived into \$STATE and removed" || bad "(x1) #964 D-2: scratch '${scr:-none}' $([ -e "$scr" ] && echo kept), archive: $(tr '\n' ' ' <<<"$toc")"
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
fixture x4; printf 'build-pr-nobody\nbuild-pr-fixbody\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(x4) a PR-only fix (the body) is accepted without the head moving"
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
grep -qx 'BASH_DEFAULT_TIMEOUT_MS=120000' "$FAKE_GH/env-1.txt" && grep -qx 'BASH_MAX_TIMEOUT_MS=120000' "$FAKE_GH/env-1.txt" && ok "(y2) [F-env] a bound under 420 s floors the BUILD's Bash timeouts at the harness's own 120 s" || bad "(y2) [F-env] BUILD spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
# F-env: the bounds feed bash arithmetic, so a fraction is refused before the claim — it must never abandon the round loop into close-out
for v in 600.5 1.5 .; do
  fixture "fe-$v"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT="$v" run_case "$d"; expect env-config-run "(fe1) RUN_BUILD_TIMEOUT=$v is refused"
  [ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(fe1) $v: exit 2, no session spawned" || bad "(fe1) $v: rc=$RC calls=$(cat "$FAKE_GH/calls" 2>/dev/null)"
done
fixture fe2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=7200.0 RUN_REVIEW_TIMEOUT=0900 run_case "$d"; expect approved "(fe2) a whole-number 7200.0 and a zero-padded 0900 are read as integers"
grep -qx 'BASH_MAX_TIMEOUT_MS=6900000' "$FAKE_GH/env-1.txt" && grep -qx 'CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=600000' "$FAKE_GH/env-2.txt" && ok "(fe2) 7200.0 -> 6900 s; 0900 -> 900 s, its wait floored at the harness's own 600 s" || bad "(fe2) env: $(cat "$FAKE_GH/env-1.txt" "$FAKE_GH/env-2.txt" | tr '\n' ' ')"
fixture fe3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 RUN_BUILD_TIMEOUT=9999999 run_case "$d"; expect approved "(fe3) an inherited background-tasks switch and a huge bound"
! grep -q 'CLAUDE_CODE_DISABLE_BACKGROUND_TASKS' "$FAKE_GH/env-2.txt" && ok "(fe3) REVIEW never inherits the BUILD's background-tasks switch" || bad "(fe3) REVIEW env: $(tr '\n' ' ' < "$FAKE_GH/env-2.txt")"
grep -qx 'BASH_MAX_TIMEOUT_MS=2147483647' "$FAKE_GH/env-1.txt" && ok "(fe3) the BUILD's Bash timeout is capped at the JS timer maximum" || bad "(fe3) BUILD env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
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
# (z12) #973 D-1: a commit not on origin, on a clean tree, re-spawns the build to push it; the next prompt says so and lists the denials
fixture z12; printf 'build-pr\nreview-needs-work\nbuild-commit-nopush\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(z12) #973 D-1: a commit left unpushed on a clean tree is pushed by a re-spawned build"
grep -q 'build: exited 0 with 1 commit(s) not on origin/second-shift/42 on a clean tree' <<<"$OUT" && grep -q 'push red — the findings are the log; another BUILD attempt of round 2' <<<"$OUT" \
  && ok "(z12) #973 S-3: the run says why it re-spawned, on the checks-red counter" || bad "(z12) #973 S-3: $(grep -E 'build: exited|push red' <<<"$OUT" | tr '\n' '|')"
grep -q 'these commits are not on origin/second-shift/42' "$FAKE_GH/prompt-4.txt" && grep -q 'local only 3' "$FAKE_GH/prompt-4.txt" \
  && grep -q 'Push second-shift/42 to origin and, unless one is already open for this branch, open the draft PR' "$FAKE_GH/prompt-4.txt" \
  && grep -qE '^Build session permission denials \(.*/denials-2\.2\.txt\):$' "$FAKE_GH/prompt-4.txt" && grep -q '^Bash {"command":"ls /"}$' "$FAKE_GH/prompt-4.txt" \
  && ok "(z12) #973 S-2: the re-spawned build reads the unpushed commit, the push and draft-PR instruction, and the denials" || bad "(z12) #973 S-2: prompt-4 lacks the push log: $(sed -n '/^## Red check output/,$p' "$FAKE_GH/prompt-4.txt" | tr '\n' '|' | cut -c1-400)"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-4.txt" && ok "(z12) the push retry still carries the review's findings" || bad "(z12) the push retry dropped the review's findings"
grep -q 'local only 3' <<<"$(git -C "$d/origin.git" log --format=%s second-shift/42)" && ok "(z12) [E21] the once-unpushed commit reached origin" || bad "(z12) [E21] the unpushed commit never reached origin"
# (z12b) #973 D-5(4): a build that keeps leaving its commits unpushed spends the checks-red counter, and nothing discards them
fixture z12b; printf 'build-commit-nopush\nbuild-commit-nopush\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"
expect checks-red-spent "(z12b) two clean-tree unpushed exits"
[ "$RC" -eq 4 ] && grep -q 'push red 2 times' <<<"$OUT" && ok "(z12b) checks-red-spent exits 4 and names the push" || bad "(z12b) rc=$RC: $(grep 'terminal: checks-red-spent' <<<"$OUT")"
[ "$(git -C "$d/wt/42" log --oneline origin/second-shift/42..HEAD 2>/dev/null | grep -c .)" -eq 2 ] && ok "(z12b) [E21] both unpushed commits are still there" || bad "(z12b) [E21] the unpushed commits were reset away"

# (aa) round-thirteen parity: the committed record is what the design guard reads; a remote dying
#      mid-run and an unreadable tracker at verdict time are environment refusals
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture aa1 "- true" $'\n## Design\n\nDesign: none — first run\n'
printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(aa1) first run, committed with Design: none"
# the receipt on disk is now DELETED and replaced by one with no design section at all: a resume must
# read only the committed record (declared, none-with-reason) and never the receipt
printf '# record\n\n## Checks\n\n- true\n' > "$d/main/.claude/pipeline-state/42-ledger.md"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume reads the committed record, not a receipt that now says nothing"
grep -q 'receipt on disk is not consulted' <<<"$OUT" && ok "(aa1) the receipt was not consulted on resume" || bad "(aa1) the receipt was read on resume"
# #1022 AC-5: that receipt fails the lint, and the resume neither lints nor refuses it
bash "$IT_ROOT/skills/plan-interview/tools/ledger-lint.sh" --receipt "$d/main/.claude/pipeline-state/42-ledger.md" >/dev/null 2>&1; lrc=$?
[ "$lrc" -eq 1 ] && ! grep -q '\[run\] receipt: ' <<<"$OUT" && ok "(aa1) #1022 AC-5: a committed record's failing disk receipt is not linted" || bad "(aa1) #1022 AC-5: lint rc=$lrc, log: $(grep 'receipt: ' <<<"$OUT" | head -n 2)"
rm -f "$d/main/.claude/pipeline-state/42-ledger.md"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume with NO receipt on disk still runs (an absent ledger is not an error once the record is committed)"
fixture aa2; printf 'build-kill-remote\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-remote-unreadable "(aa2) a remote that dies after the build is a refusal, not 'the head did not move'"
[ "$RC" -eq 2 ] && ok "(aa2) exits 2" || bad "(aa2) exit $RC"
fixture aa3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-comments-dead" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ] && [[ "\$2" == *comments* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-comments-dead"; RUN_GH="$T/bin/gh-comments-dead" run_case "$d"; expect env-tracker-unreadable "(aa3) an unreadable comment listing at verdict time is an environment refusal, not review-unbound"

# (ab) round-fourteen parity: the gate's heading rule
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab1 "- true" $'\n### DESIGN\n\nDesign: none — depth three, upper case\n\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ab1) the FIRST design section decides (disarmed), a later one does not merge into it; any depth, any case"
grep -q 'arms no render state' <<<"$OUT" && ok "(ab1) not armed" || bad "(ab1) the second section leaked"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab2 "- true" $'\n## Design notes\n\nDesign: none — a heading with trailing words is not the design section\n'
run_case "$d"; expect env-design-undeclared "(ab2) '## Design notes' is not the design section"

# (rl) #1022: a receipt from disk is linted before the claim, by the ENABLED intake-toolkit's lint
untouched() { [ "$(tr '\n' ' ' < "$FAKE_GH/labels")" = "ready-for-dev opus " ] && [ ! -e "$FAKE_GH/issue-comments" ] && [ ! -e "$FAKE_GH/calls" ] && [ ! -d "$d/wt/42" ]; }
# (rl1) AC-4: a v2 receipt with no '## Intake steps' — refused before the claim, exit 3, the violation and the rerun printed
fixture rl1; REC="$d/main/.claude/pipeline-state/42-ledger.md"
awk '/^## Intake steps/ {skip = 1; next} skip && /^## / {skip = 0} !skip' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC"
run_case "$d"; expect env-receipt-invalid "(rl1) a v2 receipt with no Intake steps"
[ "$RC" -eq 3 ] && ok "(rl1) env-receipt-invalid exits 3 (resumable)" || bad "(rl1) exit $RC"
grep -q '\[run\] receipt: ledger-lint: VIOLATION: missing mandated receipt section: Intake steps' <<<"$OUT" && grep -q 'rerun /intake-toolkit:plan-interview 42' <<<"$OUT" \
  && ok "(rl1) the refusal prints the violation and 'rerun /intake-toolkit:plan-interview 42'" || bad "(rl1) output: $(grep -E 'receipt: |rerun' <<<"$OUT" | tr '\n' '|')"
untouched && ok "(rl1) refused before the claim: no label changed, nothing posted, nothing spawned" || bad "(rl1) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
# (rl1b) D-12: the receipt shape written before #1022 (a 4-column ledger and Checks, the old fixture) is refused the same way
fixture rl1b; printf '# record\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n\n## Checks\n\n- true\n' > "$d/main/.claude/pipeline-state/42-ledger.md"
run_case "$d"; expect env-receipt-invalid "(rl1b) a pre-#1022 receipt shape"
# (rl2) AC-6: an override naming no lint, a lint that is not this lint's version probe, one that knows too few versions,
# and one whose --receipt answers with neither 0 nor 1 — each exits 2 under env-receipt-lint-unavailable, before the claim
stub_lint() { # stub_lint <name> <script body> -> prints the stub plugin root
  mkdir -p "$T/stub-$1/skills/plan-interview/tools"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/stub-$1/skills/plan-interview/tools/ledger-lint.sh"; printf '%s' "$T/stub-$1"
}
rl_unavailable() { # rl_unavailable <label> <toolkit root> <detail fragment>
  fixture "rl2-$1"; SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="$2" run_case "$d"; expect env-receipt-lint-unavailable "(rl2) $1"
  [ "$RC" -eq 2 ] && grep -qF -- "$3" <<<"$OUT" && untouched && ok "(rl2) $1: exits 2 before the claim, naming why" || bad "(rl2) $1: rc=$RC $(grep 'terminal: env-receipt' <<<"$OUT")"
}
# shellcheck disable=SC2016  # the stub bodies expand in the stub, not here
{
rl_unavailable no-lint "$T/no-such-toolkit" "SECOND_SHIFT_INTAKE_TOOLKIT_ROOT names $T/no-such-toolkit, which has no skills/plan-interview/tools/ledger-lint.sh"
rl_unavailable pre-versions "$(stub_lint old 'echo "ledger-lint: unknown option: $1" >&2; exit 2')" '--receipt-version exited 2'
rl_unavailable knows-v1 "$(stub_lint v1 '[ "$1" = --receipt-version ] && { echo 1; exit 0; }; exit 0')" 'the receipt is v2 but'
rl_unavailable rc-127 "$(stub_lint crash '[ "$1" = --receipt-version ] && { echo 2; exit 0; }; nosuchcommand-in-the-lint')" '--receipt exited 127, which is no verdict on the receipt'
}
# (rl3) AC-11: a receipt above every version the lint knows is refused by name, and never read as a pass
fixture rl3; REC="$d/main/.claude/pipeline-state/42-ledger.md"; sed 's/^Receipt: v2$/Receipt: v99/' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC"
run_case "$d"; expect env-receipt-lint-unavailable "(rl3) a v99 receipt"
grep -q 'the receipt is v99 but .* knows receipts up to v' <<<"$OUT" && untouched && ok "(rl3) the refusal names both versions, before the claim" || bad "(rl3) $(grep 'terminal: env-receipt' <<<"$OUT")"
# (rl4) AC-13: with no override the lint comes from the ENABLED intake-toolkit record in `claude plugin list --json`, in an
# install-cache layout — never the newer leftover beside it, a disabled record, or a project record for another checkout.
# The list's shape (id, version, scope, enabled, installPath, projectPath) is the one doctor reads, recorded in
# plugins/second-shift/skills/doctor/tools/doctor-fixtures/plugin-list-*.json
cat > "$T/bin/claude-plugins" <<EOF
#!/usr/bin/env bash
# answers 'plugin list --json' from \$FAKE_PLUGIN_LIST (absent: the command fails); every other call goes to the fake claude
if [ "\$1 \$2" = "plugin list" ]; then echo "\$*" >> "\$FAKE_GH/plugin-calls"; [ -f "\${FAKE_PLUGIN_LIST:-}" ] && cat "\$FAKE_PLUGIN_LIST"; exit \$?; fi
exec "$T/bin/claude" "\$@"
EOF
chmod +x "$T/bin/claude-plugins"
mkdir -p "$T/cache/intake-toolkit"; cp -R "$IT_ROOT" "$T/cache/intake-toolkit/1.0.0"
# shellcheck disable=SC2016  # the stub body expands in the stub, not here
stub_lint leftover '[ "$1" = --receipt-version ] && { echo 99; exit 0; }; echo "ledger-lint: VIOLATION: the leftover lint ran" >&2; exit 1' >/dev/null
mkdir -p "$T/cache/intake-toolkit/9.9.9"; cp -R "$T/stub-leftover/." "$T/cache/intake-toolkit/9.9.9/"
plugin_list() { # plugin_list <enabled record's enabled value> -> $FAKE_PLUGIN_LIST for the current fixture
  local main; main="$(git -C "$d/main" rev-parse --show-toplevel)"
  jq -n --arg c "$T/cache/intake-toolkit" --arg main "$main" --argjson on "$1" '[
    {id: "intake-toolkit@second-shift", version: "9.9.9", scope: "project", enabled: false, installPath: ($c + "/9.9.9"), projectPath: $main, lastUpdated: "2026-10-01T00:00:00Z"},
    {id: "intake-toolkit@second-shift", version: "9.9.9", scope: "project", enabled: true, installPath: ($c + "/9.9.9"), projectPath: "/elsewhere", lastUpdated: "2026-10-02T00:00:00Z"},
    {id: "intake-toolkit@second-shift", version: "1.0.0", scope: "user", enabled: $on, installPath: ($c + "/1.0.0"), lastUpdated: "2026-01-01T00:00:00Z"},
    {id: "dev-pipeline@second-shift", version: "1.0.0", scope: "user", enabled: true, installPath: "/nowhere"}]' > "$d/plugins.json"
  export FAKE_PLUGIN_LIST="$d/plugins.json"
}
fixture rl4; plugin_list true; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect approved "(rl4) the enabled intake-toolkit's lint passes the receipt"
grep -qF "receipt: v2, lints clean ($T/cache/intake-toolkit/1.0.0/skills/plan-interview/tools/ledger-lint.sh)" <<<"$OUT" && grep -qx 'plugin list --json' "$FAKE_GH/plugin-calls" \
  && ok "(rl4) the lint run is the enabled 1.0.0, read from 'claude plugin list --json'" || bad "(rl4) $(grep -E 'receipt: |leftover' <<<"$OUT" | tr '\n' '|')"
fixture rl5; plugin_list false
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect env-receipt-lint-unavailable "(rl5) no enabled intake-toolkit applies to this checkout"
grep -q 'lists no enabled intake-toolkit for ' <<<"$OUT" && untouched && ok "(rl5) a disabled record and another checkout's are not used" || bad "(rl5) $(grep 'terminal: env-receipt' <<<"$OUT")"
fixture rl6; unset FAKE_PLUGIN_LIST
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect env-receipt-lint-unavailable "(rl6) 'claude plugin list --json' fails"
grep -q "plugin list --json' failed" <<<"$OUT" && untouched && ok "(rl6) a failed plugin list is a refusal, not a pass" || bad "(rl6) $(grep 'terminal: env-receipt' <<<"$OUT")"

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

# (ae) #1024: whether the record is committed is asked of origin, never read off a stale local ref
stale_record() { # a branch carrying an OLD record, pushed and then deleted upstream: $d/main keeps only origin/second-shift/42
  git -C "$d/main" checkout -q -b second-shift/42; mkdir -p "$d/main/docs/plans"
  printf '# stale record\n\n| D-9 | stale | stale | user-answered |\n' > "$d/main/docs/plans/main-42-decisions.md"
  git -C "$d/main" add docs/plans && git -C "$d/main" commit -qm "docs: stale record" && git -C "$d/main" push -q origin second-shift/42 2>/dev/null
  git -C "$d/main" checkout -q main && git -C "$d/main" branch -q -D second-shift/42 && git -C "$d/origin.git" update-ref -d refs/heads/second-shift/42
  git -C "$d/main" cat-file -e refs/remotes/origin/second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null || bad "($1) fixture: no stale tracking ref carrying a record"
}
nothing_written() { [ "$RC" -eq 2 ] && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] && [ ! -f "$FAKE_GH/calls" ] && ok "($1) exits 2 before the claim: nothing written, nothing spawned" || bad "($1) rc=$RC labels: $(tr '\n' ' ' < "$FAKE_GH/labels") calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"; }
# (ae1) AC-2: origin reachable, the branch deleted upstream: the stale ref is dropped and the receipt is what the branch carries
fixture ae1; stale_record ae1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ae1) [AC-2] a branch deleted upstream reads the receipt, not the stale tracking ref"
! grep -q 'already committed' <<<"$OUT" && grep -q 'record: origin has no second-shift/42 — deleted the stale tracking ref origin/second-shift/42' <<<"$OUT" \
  && ok "(ae1) [D-2] the stale tracking ref is deleted and the run log says so" || bad "(ae1) record lines: $(grep 'record:' <<<"$OUT" | tr '\n' '|')"
ae1_rec="$(git -C "$d/origin.git" show second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null)"
[ "$(git -C "$d/origin.git" log --format=%s --reverse main..second-shift/42 | head -n 1)" = "docs: decision record for #42" ] && grep -qF '| D-1 | a | b | user-answered |' <<<"$ae1_rec" \
  && ok "(ae1) the branch is cut fresh from the base and carries the receipt" || bad "(ae1) branch: $(git -C "$d/origin.git" log --oneline main..second-shift/42 2>&1 | tr '\n' '|')"
# (ae2) AC-1: origin unreachable: refused before the claim, and the stale ref holding a record is not read
fixture ae2; stale_record ae2; git -C "$d/main" remote set-url origin "$d/nonexistent.git"; run_case "$d"; expect env-remote-unreadable "(ae2) [AC-1] an unreachable origin refuses"
grep -q 'cannot reach origin to read second-shift/42 — whether the record is already committed is unknown, so neither it nor the receipt is read' <<<"$OUT" && ! grep -q 'already committed on' <<<"$OUT" \
  && ok "(ae2) [D-4] the refusal says the record's state is unknown; the stale ref is not read" || bad "(ae2) $(grep -E 'record:|terminal:' <<<"$OUT" | tr '\n' '|')"
nothing_written ae2
# (ae3) D-3: a local branch origin does not have is unpushed work: refused, kept
fixture ae3; git -C "$d/main" branch -q second-shift/42 main; run_case "$d"; expect env-branch-unpushed "(ae3) [D-3] a local branch origin lacks is refused"
grep -q 'origin has no second-shift/42, but there is a local branch second-shift/42 — push it (git push -u origin second-shift/42) to resume it, or remove the worktree and the branch' <<<"$OUT" \
  && git -C "$d/main" rev-parse -q --verify refs/heads/second-shift/42 >/dev/null && ok "(ae3) the refusal names the branch and both ways out; the branch is kept" || bad "(ae3) $(grep 'terminal: env' <<<"$OUT")"
nothing_written ae3
# (ae4) D-3: so is a detached worktree at $WT
fixture ae4; mkdir -p "$d/wt"; git -C "$d/main" worktree add -q --detach "$d/wt/42" origin/main; run_case "$d"; expect env-branch-unpushed "(ae4) [D-3] a detached worktree for a branch origin lacks is refused"
grep -q "but there is a detached worktree at $d/wt/42" <<<"$OUT" && [ -d "$d/wt/42" ] && ok "(ae4) the refusal names the worktree; it is kept" || bad "(ae4) $(grep 'terminal: env' <<<"$OUT")"
nothing_written ae4
# (ae5) AC-3: a branch on origin carrying the record is read from origin, with no local ref and no receipt to fall back on
fixture ae5; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(ae5) first run commits the record"
git -C "$d/main" worktree remove --force "$d/wt/42"; git -C "$d/main" branch -q -D second-shift/42; git -C "$d/main" update-ref -d refs/remotes/origin/second-shift/42; rm -f "$d/main/.claude/pipeline-state/42-ledger.md"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(ae5) [AC-3] the committed record is read off origin"
grep -q 'record: already committed on second-shift/42' <<<"$OUT" && ok "(ae5) the receipt is not consulted" || bad "(ae5) $(grep 'record:' <<<"$OUT")"

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
[ "$(grep -c 'watch:' "$dlog" 2>/dev/null)" -eq 1 ] && grep -q ' \[run\] watch: off (RUN_WATCH_CMD is unset)$' "$dlog" && ok "(#939 AC-3) an unwatched detached run says 'watch: off', once" || bad "(#939 AC-3) watch lines: $(grep 'watch:' "$dlog" | tr '\n' '|')"

# ---- #939: every session is named and findable; one bounded watch call per detached launch; the scrub; a detached run's signals ----
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
arg_after() { awk -v f="$2" 'p == f { print; exit } { p = $0 }' "$1"; }   # arg_after <args file> <flag>
watch_lines() { grep -c ' \[run\] watch: ' <<<"$OUT"; }
# (wa1) a run that looks detached (RUN_DETACHED_LOG is how the detach parent says so) and is watched, launched from a herdr
# pane: two rounds and a review re-spawn make the worktree ready again, and every variable the watch reads is set — the
# lane check below goes red if one of them reaches it
# shellcheck disable=SC2016  # the check line expands in the lane, not here
fixture wa1 '- test -z "${HERDR_PANE_ID:-}${HERDR_SOCKET_PATH:-}${HERDR_ZZ_UNNAMED:-}${RUN_WATCH_CMD:-}${RUN_WATCH_EDITOR:-}${RUN_DETACHED_LOG:-}"'
printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-wrong-sha\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo started > "$d/detached.log"
HERDR_PANE_ID=op-pane HERDR_TAB_ID=op-tab HERDR_WORKSPACE_ID=op-ws HERDR_SOCKET_PATH="$d/herdr.sock" HERDR_ZZ_UNNAMED=leak RUN_WATCH_EDITOR=code \
  RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"
expect approved "(wa1) a watched run: needs-work, a review re-spawn, then approve"
[ "$(grep -c . "$FAKE_GH/watch-calls" 2>/dev/null)" = 1 ] && ok "(wa1) [AC-4] the watch command is called once per launch, though the worktree was made ready twice" || bad "(wa1) [AC-4] watch calls: $(grep -c . "$FAKE_GH/watch-calls" 2>/dev/null)"
[ "$(tr '\n' ' ' < "$FAKE_GH/watch-args" 2>/dev/null)" = "42 main $d/detached.log $d/wt/42 " ] && [ "$(cat "$FAKE_GH/watch-cwd" 2>/dev/null)" = "$(cd "$d/main" && pwd -P)" ] \
  && ok "(wa1) [AC-4] args <issue> <repo> <detach-log> <worktree>, run from the main checkout" || bad "(wa1) [AC-4] args: $(tr '\n' ' ' < "$FAKE_GH/watch-args" 2>/dev/null) cwd: $(cat "$FAKE_GH/watch-cwd" 2>/dev/null)"
read -r wpid wpgid < "$FAKE_GH/watch-pgid" 2>/dev/null
[ -n "${wpid:-}" ] && [ "$wpid" = "${wpgid:-}" ] && ok "(wa1) [AC-4 D-26] the call leads its own process group" || bad "(wa1) [AC-4] pid/pgid: ${wpid:-?}/${wpgid:-?}"
[ "$(tr '\n' ' ' < "$FAKE_GH/watch-env")" = "HERDR_SOCKET_PATH=$d/herdr.sock HERDR_ZZ_UNNAMED=leak " ] \
  && ok "(wa1) [AC-21] the call keeps herdr's server location and drops the launching pane, tab and workspace ids" || bad "(wa1) [AC-21] watch env: $(tr '\n' ' ' < "$FAKE_GH/watch-env")"
grep -qx WATCH-STDOUT "$(SD)/watch.out" && grep -qx WATCH-STDERR "$(SD)/watch.out" && ! grep -q 'WATCH-STD' <<<"$OUT" \
  && ok "(wa1) [AC-4] the call's stdout and stderr go to its file in the state dir, never the run's log" || bad "(wa1) [AC-4] watch.out: $(tr '\n' '|' < "$(SD)/watch.out" 2>/dev/null)"
[ "$(watch_lines)" -eq 1 ] && grep -q " \[run\] watch: $T/bin/watch-fake started the watch (output: " <<<"$OUT" && ok "(wa1) one 'watch:' line" || bad "(wa1) watch lines: $(grep 'watch:' <<<"$OUT" | tr '\n' '|')"
leak="$(grep -hE '^(HERDR_|RUN_WATCH|RUN_DETACHED_LOG)' "$FAKE_GH"/env-*.txt)"
[ "$(cat "$FAKE_GH/calls")" = 5 ] && [ -z "$leak" ] && ok "(wa1) [AC-12] no session got a HERDR_*, RUN_WATCH* or RUN_DETACHED_LOG variable, an unnamed HERDR_ZZ_UNNAMED included" || bad "(wa1) [AC-12] leaked: $(tr '\n' ' ' <<<"$leak")"
names="$(for n in 1 2 3 4 5; do arg_after "$FAKE_GH/args-$n.txt" -n; done | tr '\n' ' ')"
[ "$names" = "42-build-1-1 42-review-1-1 42-build-2-2 42-review-2-2 42-review-2-2-retry1 " ] && ok "(wa1) [AC-1] each session is named <issue>-<role>-<attempt id>, the id sanitized" || bad "(wa1) [AC-1] names: $names"
sids="$(for n in 1 2 3 4 5; do arg_after "$FAKE_GH/args-$n.txt" --session-id; done)"; asid="$(arg_after "$T/a/gh/args-1.txt" --session-id)"
[ "$(grep -cxE "$UUID_RE" <<<"$sids")" -eq 5 ] && [ "$(sort -u <<<"$sids" | grep -c .)" -eq 5 ] && grep -qxE "$UUID_RE" <<<"$asid" && ! grep -qxF "$asid" <<<"$sids" \
  && ok "(wa1) [AC-1] each session gets a fresh lowercase v4 --session-id, never reused within or across launches" || bad "(wa1) [AC-1] session ids: $(tr '\n' ' ' <<<"$sids") / (a): $asid"
s1="$(sed -n 1p <<<"$sids")"; s5="$(sed -n 5p <<<"$sids")"
grep -qF " [run] session: build 1.1 $s1 ~/.claude*/projects/*/$s1.jsonl" <<<"$OUT" && grep -qF " [run] session: review 2.2-retry1 $s5 ~/.claude*/projects/*/$s5.jsonl" <<<"$OUT" \
  && [ "$(grep -c ' \[run\] session: ' <<<"$OUT")" -eq 5 ] && ok "(wa1) [AC-2] one session line per spawn: role, attempt id, uuid, transcript glob" || bad "(wa1) [AC-2] $(grep 'session:' <<<"$OUT" | tr '\n' '|')"
# (wa2, wa4) AC-5: a foreground run is never watched; a run that ends before its worktree is ready calls nothing
fixture wa2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_WATCH_CMD="$T/bin/watch-fake" run_case "$d"; expect approved "(wa2) a foreground run with RUN_WATCH_CMD set"
[ ! -f "$FAKE_GH/watch-calls" ] && [ "$(watch_lines)" -eq 1 ] && grep -q ' \[run\] watch: skipped for a foreground run' <<<"$OUT" && ok "(wa2) [AC-5] nothing invoked; the log says the watch was skipped" || bad "(wa2) [AC-5] calls: $(cat "$FAKE_GH/watch-calls" 2>/dev/null) lines: $(grep 'watch:' <<<"$OUT")"
fixture wa4; echo CLOSED > "$FAKE_GH/state"; RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"; expect env-ticket-closed "(wa4) a watched run refused in preflight"
[ ! -f "$FAKE_GH/watch-calls" ] && [ "$(watch_lines)" -eq 0 ] && ok "(wa4) [AC-5] a refusal before the worktree: no call" || bad "(wa4) [AC-5] watch was called"
# (wb1-wb3) AC-6: a watch that fails, is missing or hangs changes nothing but its one line
wb() { # wb <case> <cmd> <FAKE_WATCH> <line regex> — the same run as (a); its terminal, exit, run block and comments carry no watch
  fixture "$1"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; local s0; s0=$(date +%s)
  FAKE_WATCH="$3" RUN_WATCH_CMD="$2" RUN_DETACHED_LOG="$d/detached.log" run_case "$d"; WB_EL=$(( $(date +%s) - s0 ))
  expect approved "($1) [AC-6] a watch that is '$3' leaves the outcome alone"
  [ "$RC" -eq 0 ] && [ "$(watch_lines)" -eq 1 ] && grep -qE " \[run\] watch: FAILED — $4" <<<"$OUT" && ok "($1) [AC-6] exit 0 and exactly one 'watch:' failure line" || bad "($1) [AC-6] rc=$RC watch lines: $(grep 'watch:' <<<"$OUT" | tr '\n' '|')"
  ! grep -qiE 'watch|herdr' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" && grep -q '| approved |' "$FAKE_GH/pr-body.md" && ok "($1) [AC-6 AC-14] the run block and the closing comment carry nothing of the watch" || bad "($1) [AC-6] $(grep -iE 'watch|herdr' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" | head -n 2)"
}
wb wb1 "$T/bin/watch-fake" fail "$T/bin/watch-fake exited rc=3 "
wb wb2 /nonexistent/watch ok "'/nonexistent/watch' is not an executable"
wb wb3 "$T/bin/watch-fake" hang "$T/bin/watch-fake ran past its 10s bound and its process group was killed"
[ "$WB_EL" -lt 40 ] && ok "(wb3) [AC-4] the 10 s bound is a bound (${WB_EL}s for the whole run)" || bad "(wb3) [AC-4] the run took ${WB_EL}s"
sleep 0.5; if pgrep -f 'sleep 939[12]' >/dev/null 2>&1; then bad "(wb3) [AC-4] a descendant of the hung call survived its group kill"; pkill -KILL -f 'sleep 939[12]'; else ok "(wb3) [AC-4] the hung call's whole group, a TERM-ignoring grandchild included, is gone"; fi
# (wb4) AC-4: while the call runs, the run's TERM trap reaps its whole group
fixture wb4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && FAKE_WATCH=hang RUN_WATCH_CMD="$T/bin/watch-fake" RUN_DETACHED_LOG="$d/detached.log" exec bash "$RUN" 42 > "$d/wb4.log" 2>&1 ) & rp=$!
for _ in $(seq 1 60); do [ -f "$FAKE_GH/watch-calls" ] && break; sleep 0.5; done; sleep 1
kill -TERM "$rp"; wait "$rp"; xrc=$?
sleep 0.5; if pgrep -f 'sleep 939[12]' >/dev/null 2>&1; then bad "(wb4) [AC-4] the watch call outlived a TERM to the run (rc=$xrc)"; pkill -KILL -f 'sleep 939[12]'
else [ "$xrc" -eq 143 ] && grep -q 'terminated; claim left in place' "$d/wb4.log" && ok "(wb4) [AC-4] TERM during the watch call exits 143 and reaps the call's whole group" || bad "(wb4) rc=$xrc $(tail -n 2 "$d/wb4.log" | tr '\n' '|')"; fi
# (dk1-dk4) AC-20 D-28: a detached run killed by its printed pid or by its process group stops through its own trap,
# leaves its claim, leaves no process of its group behind, and its log still ends with the exit line
detached_kill() { # detached_kill <case> <signal> pid|group <rc>
  fixture "$1"; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --detach
  local pid log; pid="$(sed -n 's/.*detached: pid \([0-9]*\) .*/\1/p' <<<"$OUT")"; log="$(sed -n 's/.*detached: pid [0-9]* · log \([^ ]*\) .*/\1/p' <<<"$OUT")"
  [ -n "$pid" ] && [ -n "$log" ] || { bad "($1) no pid or log: $OUT"; return; }
  for _ in $(seq 1 120); do grep -q ' \[run\] session: build 1.1 ' "$log" 2>/dev/null && [ -f "$FAKE_GH/calls" ] && break; sleep 0.5; done; sleep 1
  if [ "$3" = group ]; then kill "-$2" -- "-$pid"; else kill "-$2" "$pid"; fi
  for _ in $(seq 1 60); do grep -q 'detached run exited rc=' "$log" && break; sleep 0.5; done
  local last; last="$(tail -n 1 "$log")"
  grep -qE " \[run\] detached run exited rc=$4$" <<<"$last" && grep -q 'claim left in place' "$log" && grep -qx in-progress "$FAKE_GH/labels" \
    && ok "($1) [AC-20] $2 to the $3 stops the run through its trap, the claim kept, the last line 'detached run exited rc=$4'" || bad "($1) [AC-20] $2 to the $3: $(tail -n 3 "$log" | tr '\n' '|')"
  for _ in $(seq 1 20); do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 -- "-$pid" 2>/dev/null; then bad "($1) [AC-20] a process of the run's group survived: $(pgrep -l -g "$pid" | tr '\n' '|')"; kill -KILL -- "-$pid" 2>/dev/null
  else ok "($1) [AC-20] no process of the run, its session or the wrapper survives"; fi
}
detached_kill dk1 TERM pid 143
detached_kill dk2 TERM group 143
detached_kill dk3 INT pid 130
detached_kill dk4 HUP group 129

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

# E20 #926: an untracked file the review left at close-out is archived, and the approved worktree is removed
fixture rj; printf 'build-pr\nreview-approve-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20] the review left an untracked file behind"
toc="$(tar -tf "$(SD)/quarantine-closeout.tar" 2>&1)"
[ "$RC" -eq 0 ] && [ ! -d "$d/wt/42" ] && grep -qx review-scratch.txt <<<"$toc" && ok "[E20] exit 0, the file is in quarantine-closeout.tar and the worktree is removed" || bad "[E20] rc=$RC, worktree $([ -d "$d/wt/42" ] && echo kept || echo gone), archive: $(tr '\n' ' ' <<<"$toc")"

# E20-rd: gitignored runtime data under a declared paths.runtimeData keeps the worktree — `worktree remove` would delete it — and the run still ends approved
RTCFG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans","runtimeData":[".claude/storage","apps/api/uploads"]}}'
FIXTURE_CONFIG="$RTCFG" fixture rt1; printf 'build-pr\nreview-approve-runtime\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] runtime data under a declared path at close-out"
[ "$RC" -eq 0 ] && [ -f "$d/wt/42/.claude/storage/upload-1.bin" ] && printf '%s\n' "$OUT" | grep -q "worktree $d/wt/42 left in place: runtime data under .claude/storage;" && ok "[E20-rd] exit 0, worktree and its data kept, the blocking path printed" || bad "[E20-rd] rc=$RC, data $([ -f "$d/wt/42/.claude/storage/upload-1.bin" ] && echo kept || echo gone): $(printf '%s\n' "$OUT" | grep 'worktree ' | tail -n 1)"
FIXTURE_CONFIG="$RTCFG" fixture rt2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] declared runtime paths that hold nothing"
[ ! -d "$d/wt/42" ] && ok "[E20-rd] an empty declared path does not block removal" || bad "[E20-rd] worktree kept with nothing under the declared paths"
fixture rt3; printf 'build-pr\nreview-approve-runtime\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] no paths.runtimeData declared"
[ ! -d "$d/wt/42" ] && ok "[E20-rd] key absent: close-out removes as before" || bad "[E20-rd] key absent but the worktree was kept"

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
sdir=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-2.txt" | grep -- '-scratch\.' | head -n 1)
[ -n "$sdir" ] && grep -qF "writing it with Write into $sdir," "$FAKE_GH/prompt-2.txt" && grep -q 'code-review.mjs' "$FAKE_GH/prompt-2.txt" \
  && ok "[F20] #964 D-3: the review's prompt stages code-review.mjs in the run's scratch dir, which it is handed" || bad "[F20] scratch dir '${sdir:-none}' not added to the review, or not named as the staging dir"
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
scr="$(sed -n 's/^.* \[run\] scratch: \(.*\) (both sessions.*$/\1/p' <<<"$OUT")"; toc="$(tar -tf "$(SD)/scratch.tar" 2>&1)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" \
  && ok "#964 D-2: a blocked run's scratch dir is archived into \$STATE as evidence and removed" || bad "#964 D-2: blocked run scratch '${scr:-none}'"
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
rsec() { awk -v h="### $1" 'index($0, h) == 1 {on=1; next} /^###/{on=0} on && NF' "$(SD)/review-input-1.1.md" 2>/dev/null; }
[ "$(rsec 'Deleted or renamed test files')" = "(none)" ] && [ "$(rsec 'Configured lanes not run')" = "(none)" ] && ok "[I10] #956: the deleted-tests and skipped-lanes sections say (none) when empty" || bad "[I10] #956: deleted=[$(rsec 'Deleted or renamed test files')] lanes=[$(rsec 'Configured lanes not run')]"
[ "$(rsec 'Existing test or snapshot expectations changed')" = "(none)" ] && ok "[I10] #957: lines only added to an existing spec change no expectation: (none)" || bad "[I10] #957: additive section: [$(rsec 'Existing test or snapshot expectations changed')]"
[ "$(rsec 'Review policy edited')" = "(none)" ] && ok "[I10] #1009: a diff that edits no review policy says (none)" || bad "[I10] #1009: policy section: [$(rsec 'Review policy edited')]"

# I10 #1009: head-side edits to the review policy reach the review input: both sides of a rename out of the policy dir,
# the config and context files, and the repo-local agent of a bare reviewers.add[] name only
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"reviewers":{"add":[{"name":"orders-reviewer"},{"name":"pack:billing-reviewer"}]}}' fixture rpol
mkdir -p "$d/main/.claude/second-shift"; echo 'never raw SQL' > "$d/main/.claude/second-shift/security-rules.md"
git -C "$d/main" add -f .claude/second-shift/security-rules.md && git -C "$d/main" commit -qm policy && git -C "$d/main" push -q origin main
printf 'build-edit-policy\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #1009 run"
s="$(rsec 'Review policy edited')"
grep -qxE $'R[0-9]+\t\\.claude/second-shift/security-rules\\.md\tdocs/security-rules\\.md' <<<"$s" && grep -qxF $'A\t.claude/second-shift/review-context.md' <<<"$s" \
  && grep -qxF $'A\t.claude/second-shift.config.json' <<<"$s" && grep -qxF $'A\t.claude/agents/orders-reviewer.md' <<<"$s" && [ "$(grep -c '' <<<"$s")" -eq 4 ] \
  && ok "[I10] #1009: the rename out of the policy dir, the context and config files and the bare reviewers.add[] agent are listed; the pack and unlisted agents are not" || bad "[I10] #1009: policy section: $(tr '\n\t' '| ' <<<"$s")"
grep -q '^### Review policy edited' "$(SD)/review-1.1.prompt" && grep -q "For every file under 'Review policy edited' in the scheduler input below, trace the edit" "$(SD)/review-1.1.prompt" \
  && ok "[I10] #1009: the section and its trace instruction reach the review prompt" || bad "[I10] #1009: not in the review prompt"

# I10 #957: a modified existing spec and a snapshot outside the spec pattern are listed with their removed lines, capped at 20
FIXTURE_FILES="src/b.test.ts src/__snapshots__/price.snap" FIXTURE_BODY="$(for i in $(seq 1 22); do echo "expect(v$i).toBe(1999)"; done)" fixture rp3
printf 'build-edit-expectation\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #957 run"
want="$(echo src/__snapshots__/price.snap; for i in $(seq 1 20); do echo "  -expect(v$i).toBe(1999)"; done; echo '  (… 2 more)'; echo src/b.test.ts; echo '  -expect(v1).toBe(1999)')"
s="$(rsec 'Existing test or snapshot expectations changed')"; [ "$s" = "$want" ] && ok "[I10] #957: the edited assertion and the regenerated snapshot are named with their old expectations; the additive and new specs are not" || bad "[I10] #957: section: $(tr '\n' '|' <<<"$s")"
grep -q '^### Existing test or snapshot expectations changed' "$(SD)/review-1.1.prompt" && ok "[I10] #957: the section reaches the review prompt" || bad "[I10] #957: not in the review prompt"

# I10 #956: the detectors are stack-neutral, and a when-skipped lane is named even when another lane ran
FIXTURE_FILES="tests/test_x.py src/__tests__/b.js pyproject.toml" FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"unit","when":["src/**"],"commands":["true"]},{"name":"docs-lint","when":["docs/**"],"commands":["true"]}]}}}' fixture rp2 ""
printf 'build-polyglot\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #956 polyglot run"
s="$(rsec 'Deleted or renamed test files')"; grep -qE '^D[[:space:]]+tests/test_x\.py$' <<<"$s" && grep -qE '^D[[:space:]]+src/__tests__/b\.js$' <<<"$s" && ok "[I10] #956: a top-level tests/ and a __tests__/ deletion are listed" || bad "[I10] #956: deleted section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Added skips')"; grep -q '@pytest.mark.skip' <<<"$s" && grep -q 't.Skip("later")' <<<"$s" && ok "[I10] #956: a pytest skip and a Go t.Skip( are listed" || bad "[I10] #956: skips section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'CI or check configuration edited')"; grep -qx 'pyproject.toml' <<<"$s" && grep -qx 'eslint.config.mjs' <<<"$s" && ! grep -q 'test_y.py' <<<"$s" && ok "[I10] #956: the pyproject.toml coverage edit and eslint.config.mjs are listed" || bad "[I10] #956: config section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Configured lanes not run')"; [ "$s" = "docs-lint" ] && grep -q 'ok: true' "$(SD)/checks-1.1.log" && ok "[I10] #956: the when-skipped lane is named while the matched one ran" || bad "[I10] #956: lanes section: $(tr '\n' '|' <<<"$s")"

# I10 #1011: a non-ASCII path, a path with a space and this repo's own *-selftest.* reach every section and the when-glob.
# Names are NFC bytes (macOS git recomposes to NFC, Linux does not); quotePath=true is pinned through GIT_CONFIG_*, so a
# machine with a global quotePath=false cannot pass these without run.sh's own -c
cafe=$'caf\303\251'
FIXTURE_FILES="src/$cafe.spec.ts scripts/x-selftest.sh" FIXTURE_BODY=$'expect(a).toBe(1)\nexpect(b).toBe(2)' \
  FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"cafe","when":["src/'"$cafe"'.spec.ts"],"commands":["true cafe"]}]}}}' fixture rp4 ""
mkdir -p "$d/main/src/old dir"; echo x > "$d/main/src/old dir/y.spec.ts"; git -C "$d/main" add -A; git -C "$d/main" commit -qm "spaced spec"; git -C "$d/main" push -q origin main 2>/dev/null
printf 'build-path-names\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=true run_case "$d"; expect approved "[I10] #1011 run"
want="$(printf 'scripts/x-selftest.sh\n  -expect(a).toBe(1)\nsrc/%s.spec.ts\n  -expect(a).toBe(1)' "$cafe")"
s="$(rsec 'Existing test or snapshot expectations changed')"; [ "$s" = "$want" ] && ok "[I10] #1011: a non-ASCII spec and a *-selftest.sh are named with their removed expectations" || bad "[I10] #1011: expectations section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Deleted or renamed test files')"; [ "$s" = $'D\tsrc/old dir/y.spec.ts' ] && ok "[I10] #1011: a deleted spec whose path holds a space is listed whole" || bad "[I10] #1011: deleted section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'CI or check configuration edited')"; [ "$s" = ".github/workflows/$cafe.yml" ] && ok "[I10] #1011: a non-ASCII CI config is listed unquoted" || bad "[I10] #1011: config section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Configured lanes not run')"; [ "$s" = "(none)" ] && grep -qx 'ok: true cafe' "$(SD)/checks-1.1.log" && ok "[I10] #1011: a when-glob naming the non-ASCII path runs its lane" || bad "[I10] #1011: lanes section: $(tr '\n' '|' <<<"$s"); log: $(tr '\n' '|' < "$(SD)/checks-1.1.log")"

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
grep -qF '| review-1.1 | ? | unpriced (no total_cost_usd) |' "$FAKE_GH/pr-body.md" && grep -q '[$][0-9.]* + unpriced' "$FAKE_GH/pr-body.md" && ok "[K12] the killed review is an unpriced row, never \$0.00" || bad "[K12] rows: $(grep -E '^[|] (build|review)' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
# its denials were never read: "?", never a 0 a reader takes for a clean session; the re-spawn that did report counts
# shellcheck disable=SC2016  # the run block's literal dollar costs
grep -qxF '| review-1.1 | ? | unpriced (no total_cost_usd) | ? |' "$FAKE_GH/pr-body.md" && grep -qxF '| review-1.1-retry1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" && [ ! -e "$(SD)/denials-review-1.1.txt" ] \
  && ok "[K12] the killed review's denials are unread (?), not 0" || bad "[K12] denials cells: $(grep -E '^[|] review' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
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

# H14: a smokeCommand that takes {textScale} runs every row at 1 and at 2; {textScale} goes in before {mustShow}
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"echo {route} {textScale} >> $T/h14a.calls && test {mustShow} = 'Size {''textScale}x'\"}}}" fixture h14a "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | Size {textScale}x |\n| RS-2 | b | empty | 1:3 | Size {textScale}x |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] a smokeCommand with {textScale} and a must-show carrying the literal token"
[ "$(tr '\n' '|' < "$T/h14a.calls" 2>/dev/null)" = "a 1|a 2|b 1|b 2|" ] && ok "[H14] each row is smoked at text scale 1 and at 2" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14a.calls" 2>/dev/null)"
grep -q 'scaled smoke: not configured' <<<"$OUT" && bad "[H14] the not-configured note printed for a smokeCommand that takes {textScale}" || ok "[H14] no not-configured note when {textScale} is taken"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {textScale} = 1\"}}}" fixture h14b "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H14] a smoke red only at text scale 2 ends the round red"
grep -qx "RED: RS-1 at text scale 2: smoke failed: test 2 = 1" "$(SD)/smoke-1.1.log" 2>/dev/null && grep -q "^ok: RS-1 at text scale 1 " "$(SD)/smoke-1.1.log" && ! grep -q 'at text scale 1: smoke failed' "$(SD)/smoke-1.1.log" \
  && ok "[H14] the red names the row, the scale and the substituted command; scale 1 stays ok" || bad "[H14] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-240)"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"echo {route} >> $T/h14c.calls && { test -f $T/h14c.green || { touch $T/h14c.green; false; }; }\"}}}" fixture h14c "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n'
printf 'build-pr\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] no {textScale}: a red-then-green attempt over two rows"
[ "$(tr '\n' '|' < "$T/h14c.calls" 2>/dev/null)" = "a|b|a|b|" ] && ok "[H14] without {textScale} each row is smoked once per attempt" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14c.calls" 2>/dev/null)"
[ "$(grep -c 'scaled smoke: not configured (smokeCommand takes no {textScale})' <<<"$OUT")" -eq 1 ] && ok "[H14] the not-configured note is printed exactly once per run" || bad "[H14] note printed $(grep -c 'scaled smoke: not configured' <<<"$OUT") times"
[ "$(grep -c '^scaled smoke: not configured (smokeCommand takes no {textScale})$' "$FAKE_GH/pr-body.md" 2>/dev/null)" -eq 1 ] && ok "[H14] the run block carries the note once" || bad "[H14] run block: $(grep -c 'scaled smoke' "$FAKE_GH/pr-body.md" 2>/dev/null)"
! grep -q 'scaled smoke' "$(SD)"/smoke-*.log 2>/dev/null && ok "[H14] the note never enters a smoke log (the build's findings)" || bad "[H14] the note is in a smoke log"

# H14 (D-5): a stdin-reading render or smoke command must not swallow the rows still to run
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cat > /dev/null; printf %s {state} > {out}\",\"smokeCommand\":\"cat > /dev/null; echo {route} >> $T/h14d.calls\"}}}" fixture h14d "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n| RS-3 | c | error | 1:4 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] stdin-reading render and smoke commands over three rows"
[ "$(tr '\n' '|' < "$T/h14d.calls" 2>/dev/null)" = "a|b|c|" ] && ok "[H14] all three rows are smoked when the commands read stdin" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14d.calls" 2>/dev/null)"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"cat > /dev/null; echo {route} {textScale} >> $T/h14f.calls\"}}}" fixture h14f "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n| RS-3 | c | error | 1:4 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] a stdin-reading smokeCommand with {textScale} over three rows"
[ "$(tr '\n' '|' < "$T/h14f.calls" 2>/dev/null)" = "a 1|a 2|b 1|b 2|c 1|c 2|" ] && ok "[H14] all three rows are smoked at both scales when the scaled smoke reads stdin" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14f.calls" 2>/dev/null)"

# H14 (D-10): a red at text scale 1 does not skip text scale 2
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {textScale} = 2\"}}}" fixture h14e "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H14] a smoke red only at text scale 1 ends the round red"
grep -qx "RED: RS-1 at text scale 1: smoke failed: test 1 = 2" "$(SD)/smoke-1.1.log" 2>/dev/null && grep -q "^ok: RS-1 at text scale 2 " "$(SD)/smoke-1.1.log" \
  && ok "[H14] after a scale-1 red, scale 2 still runs and is logged ok" || bad "[H14] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-240)"

# H14 (D-6): the not-configured note needs armed rows; a 'Design: none' record carries none
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","smokeCommand":"true"}}}' fixture h14g "- true" $'\n## Design\n\nDesign: none — a wording change, nothing renders\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] Design: none with a smokeCommand that takes no {textScale}"
! grep -q 'scaled smoke: not configured' <<<"$OUT" && ! grep -q 'scaled smoke' "$FAKE_GH/pr-body.md" 2>/dev/null \
  && ok "[H14] no not-configured note when the record arms no rows" || bad "[H14] the note printed for a record that arms no rows"

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
FIXTURE_CONFIG="$RTCFG" fixture ar11b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"   # the 4th status read is the runtime-data one
OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=4 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[E20-rd] an unreadable runtime-data status at close-out"
[ "$RC" -eq 0 ] && [ -d "$d/wt/42" ] && printf '%s\n' "$OUT" | grep -q 'left in place: the status of paths.runtimeData could not be read' && ok "[E20-rd] fail safe: worktree kept and the reason printed" || bad "[E20-rd] rc=$RC, worktree $([ -d "$d/wt/42" ] && echo kept || echo gone)"
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

# (bb) baseBranch: the lane forks from, targets and reviews against the configured branch, not the remote default
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"baseBranch":"develop"}' fixture bb
git -C "$d/main" switch -q -c develop && echo dev > "$d/main/src/dev-only.ts" && git -C "$d/main" add src/dev-only.ts && git -C "$d/main" commit -qm dev && git -C "$d/main" push -q -u origin develop 2>/dev/null && git -C "$d/main" switch -q main
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(bb) a run on a configured baseBranch"
git -C "$d/origin.git" merge-base --is-ancestor develop second-shift/42 && ok "(bb) the branch is cut from origin/develop" || bad "(bb) the branch does not contain origin/develop"
grep -q "gh pr create --draft --base develop" "$FAKE_GH/prompt-1.txt" && ok "(bb) the build opens its PR against develop" || bad "(bb) build prompt PR base: $(grep -o "against [^ ]*" "$FAKE_GH/prompt-1.txt")"
grep -q "base branch is develop" "$FAKE_GH/prompt-2.txt" && ok "(bb) the review diffs against develop" || bad "(bb) review prompt names no base"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"baseBranch":"nope"}' fixture bb2
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-base-unreadable "(bb2) a configured baseBranch missing on origin refuses"
grep -qx ready-for-dev "$FAKE_GH/labels" && ! grep -qx in-progress "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/calls" ] && ok "(bb2) refused before the claim, nothing spawned" || bad "(bb2) claimed or spawned on an unresolvable base"
fixture bb3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(bb3) no baseBranch"
grep -q "gh pr create --draft --base main" "$FAKE_GH/prompt-1.txt" && ok "(bb3) unset, the PR targets the remote default" || bad "(bb3) default PR base: $(grep -o "against [^ ]*" "$FAKE_GH/prompt-1.txt")"

# (cs) #915: the bound verdict is posted as the second-shift/review commit status on the sha it names
fixture cs1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs1) an approved run"
cs_head="$(git -C "$d/origin.git" rev-parse second-shift/42)"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q "^operator $cs_head .*state=success .*context=second-shift/review .*description=approved at this head — see the verdict .*target_url=https://x/pr/7#verdict" "$FAKE_GH/statuses" \
  && ok "(cs1) [D-1 D-3 D-4] success posted once on the reviewed head, linking the verdict comment" || bad "(cs1) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
grep -qx "status: second-shift/review=success on $cs_head" "$FAKE_GH/pr-body.md" && ok "(cs1) [D-13] the run block names the posted status" || bad "(cs1) run block: $(grep status "$FAKE_GH/pr-body.md")"
fixture cs2; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs2) needs-work, then approve"
cs_l1="$(sed -n 1p "$FAKE_GH/statuses" 2>/dev/null)"; cs_l2="$(sed -n 2p "$FAKE_GH/statuses" 2>/dev/null)"
cs_r1="$(cut -d' ' -f2 <<<"$cs_l1")"; cs_r2="$(cut -d' ' -f2 <<<"$cs_l2")"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 2 ] && grep -q 'state=failure .*description=needs-work at this head' <<<"$cs_l1" && grep -q 'state=success' <<<"$cs_l2" \
  && [ "$cs_r2" = "$(git -C "$d/origin.git" rev-parse second-shift/42)" ] && [ "$cs_r1" != "$cs_r2" ] \
  && ok "(cs2) [D-3] failure on the needs-work head, success on the later approved head" || bad "(cs2) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture cs3; printf 'build-pr\nreview-approve-and-push\nreview-approve-and-push\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(cs3) every verdict voided by a moved head"
[ ! -s "$FAKE_GH/statuses" ] && ok "(cs3) [D-1] a verdict voided by a moved head posts no status" || bad "(cs3) statuses: $(cat "$FAKE_GH/statuses")"
fixture cs4; printf 'build-pr\nreview-approve-and-push\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs4) the second review binds"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q "^operator $(git -C "$d/origin.git" rev-parse second-shift/42) " "$FAKE_GH/statuses" && ok "(cs4) only the bound head gets the status, never the voided one" || bad "(cs4) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture cs5; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Validation Failed (HTTP 422)' > "$FAKE_GH/status-fail"; run_case "$d"
expect approved "(cs5) [D-5] a failed status post leaves the terminal unchanged"
grep -q "^status: NOT posted (second-shift/review=success on $(git -C "$d/origin.git" rev-parse second-shift/42)) — gh: Validation Failed (HTTP 422)$" "$FAKE_GH/pr-body.md" && ok "(cs5) [D-5] the failed post is reported in the run block" || bad "(cs5) run block: $(grep status "$FAKE_GH/pr-body.md")"
fixture cs6; printf 'build-pr\nreview-render-unavailable\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(cs6) render-unavailable"
grep -q 'state=failure' "$FAKE_GH/statuses" 2>/dev/null && ok "(cs6) [D-3] a render-unavailable needs-work posts failure" || bad "(cs6) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
# through the bot when one is configured; a bot the App denies statuses is named, never retried as the operator
printf '#!/usr/bin/env bash\nFAKE_GH_AS=bot exec %s "$@"\n' "$T/bin/gh" > "$T/bin/gh-asbot"; chmod +x "$T/bin/gh-asbot"
cs_bot() { OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh-asbot" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; }
CS_BOT_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT","app":{"appName":"second-shift-bot"}}},"paths":{"plansDir":"docs/plans"}}'
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture cs7; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; cs_bot; expect approved "(cs7) a run with a bot"
grep -q "^bot $(git -C "$d/origin.git" rev-parse second-shift/42) .*state=success" "$FAKE_GH/statuses" 2>/dev/null && ! grep -q '^operator ' "$FAKE_GH/statuses" && ok "(cs7) [D-5] the status is posted through the bot" || bad "(cs7) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture cs8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Resource not accessible by integration (HTTP 403)' > "$FAKE_GH/status-fail"; cs_bot
expect approved "(cs8) a bot the App denies statuses"
grep -q "^status: NOT posted .*(HTTP 403) — the bot's GitHub App needs the 'Commit statuses: write' permission$" "$FAKE_GH/pr-body.md" && ok "(cs8) [D-7] the run block names the missing App permission" || bad "(cs8) run block: $(grep status "$FAKE_GH/pr-body.md")"
grep -q '(HTTP 422)$' "$T/cs5/gh/pr-body.md" 2>/dev/null && ! grep -q 'Commit statuses' "$T/cs5/gh/pr-body.md" && ok "(cs5) [D-7] no App hint without a bot or a 403/404" || bad "(cs5) [D-7] hint leaked: $(grep status "$T/cs5/gh/pr-body.md")"

# (mv) #946: once a verdict binds, the PR's earlier lane verdicts are minimized as outdated — never a notice, never a stranger's
mv_seed() { # a stranger's verdict-shaped comment and a lane notice, posted before the run
  jq '. + [{id:1,node_id:"N1",body:"verdict: needs-work\nreviewed: x",user:{login:"stranger",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"},
           {id:2,node_id:"N2",body:"the head moved during the review; verdict: approve no longer binds",user:{login:"tester",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' \
    "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"; }
fixture mv1; mv_seed; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(mv1) needs-work, then approve"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "operator N3" ] && ok "(mv1) [D-3 D-4 D-1] the earlier needs-work is minimized; the bound approve, the notice and the stranger's are not" \
  || bad "(mv1) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"
fixture mv2; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=needs-work,approve run_case "$d"; expect approved "(mv2) two verdicts in one window"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "operator N1" ] && ok "(mv2) [D-9] the earlier verdict of the same window is minimized, the bound one is not" \
  || bad "(mv2) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"
fixture mv3; mv_seed; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve-and-push\nreview-approve-and-push\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(mv3) the later verdicts voided by a moved head"
[ ! -s "$FAKE_GH/minimized" ] && ok "(mv3) [D-3] a voided verdict minimizes nothing: the bound needs-work stays expanded" || bad "(mv3) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized")"
fixture mv4; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Resource not accessible by integration (HTTP 403)' > "$FAKE_GH/minimize-fail"; run_case "$d"
expect approved "(mv4) [D-7] a failed minimize leaves the terminal unchanged"
grep -q "state=success" "$FAKE_GH/statuses" 2>/dev/null && ok "(mv4) [D-7] the commit status still posts" || bad "(mv4) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
grep -q "^verdicts: earlier ones NOT all minimized — comment 1 NOT minimized — gh: Resource not accessible by integration (HTTP 403)" "$FAKE_GH/pr-body.md" \
  && ok "(mv4) [D-7] the failed minimize is one run-block line" || bad "(mv4) run block: $(grep verdicts "$FAKE_GH/pr-body.md")"
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture mv5; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; cs_bot; expect approved "(mv5) a run with a bot"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "bot N1" ] && ok "(mv5) [D-6] the minimize is written through the bot" || bad "(mv5) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"

# (vc) #991: a verdict binds only when its own comment backs it. Each inconsistent body, posted by both the review and its
# re-spawn: no status, no BUILD, the re-spawn told which rule broke, a notice linking each rejected verdict, review-unbound
vc_case() { # vc_case <id> <build plan> <review plan> <rule>
  fixture "$1"; printf '%s\n%s\n%s\n' "$2" "$3" "$3" > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "($1) $3, twice"
  [ "$RC" -eq 5 ] && [ ! -s "$FAKE_GH/statuses" ] && [ "$(cat "$FAKE_GH/calls")" -eq 3 ] && [ ! -f "$FAKE_GH/prompt-4.txt" ] \
    && ok "($1) no status posted and no BUILD spawned" || bad "($1) rc=$RC calls=$(cat "$FAKE_GH/calls") statuses=$(cat "$FAKE_GH/statuses" 2>/dev/null)"
  grep -q '^## Your previous verdict did not bind' "$FAKE_GH/prompt-3.txt" && grep -qF -- "- $4" "$FAKE_GH/prompt-3.txt" && ! grep -q 'previous verdict did not bind' "$FAKE_GH/prompt-2.txt" \
    && ok "($1) the re-spawn prompt names the rule: $4" || bad "($1) prompt-3: $(grep -A3 'previous verdict' "$FAKE_GH/prompt-3.txt" | tr '\n' '|')"
  [ "$(grep -c 'does not bind' "$FAKE_GH/pr-comment-bodies" 2>/dev/null)" -eq 2 ] && grep -q '^second-shift run .*: the verdict at https://x/pr/7#verdict does not bind' "$FAKE_GH/pr-comment-bodies" \
    && grep -qF -- "- $4" "$FAKE_GH/pr-comment-bodies" && ! grep -q '^verdict:' "$FAKE_GH/pr-comment-bodies" \
    && ok "($1) one notice per rejected verdict links it and names the rule, and is no verdict itself" || bad "($1) notices: $(tr '\n' '|' < "$FAKE_GH/pr-comment-bodies" 2>/dev/null)"
  grep -qF "breaks the verdict grammar: $4" <<<"$OUT" && ok "($1) the miss names the failed rule" || bad "($1) miss: $(grep 'verdict grammar' <<<"$OUT" | head -n 1)"
}
vc_case vc1 build-pr review-bad-approve-blocker "approve with a blocker"
vc_case vc2 build-pr review-bad-approve-violated "approve with a violated or undeterminable row: D-1 violated"
vc_case vc3 build-pr-add-row review-approve "record row not scored: D-2"   # the row only the head carries: run.sh reads the record there too
vc_case vc4 build-pr review-bad-needs-work-noblocker "needs-work with no blocker"
grep -qF 'Bash(bash *verdict-check.sh*)' "$FAKE_GH/args-2.txt" && grep -q "^Before you post, check your draft: run 'bash .*/tools/verdict-check.sh " "$FAKE_GH/prompt-2.txt" \
  && grep -qx 'The verdict comment has these parts, in this order and nothing else:' "$FAKE_GH/prompt-2.txt" && ! grep -q 'LOCKSTEP-' "$FAKE_GH/prompt-2.txt" && ok "(vc4) [D-2] the review may run the checker on its draft and is told to; the grammar reaches it without its markers" \
  || bad "(vc4) [D-2] allowlist/prompt: $(grep -c 'verdict-check' "$FAKE_GH/prompt-2.txt")"
fixture vc5; printf 'build-pr\nreview-bad-approve-blocker\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(vc5) a rejected verdict, then a consistent approve from the re-spawn"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q 'state=success' "$FAKE_GH/statuses" && ok "(vc5) one status, from the verdict that binds" || bad "(vc5) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture vc6; printf 'build-pr-rm-record\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect verdict-uncheckable "(vc6) no record at the head to check the verdict against"
[ "$RC" -eq 1 ] && [ ! -s "$FAKE_GH/statuses" ] && [ "$(cat "$FAKE_GH/calls")" -eq 2 ] && grep -q '| verdict-uncheckable | 1 | none |' "$FAKE_GH/pr-body.md" \
  && ok "(vc6) [D-5] exit 1, no status, no re-spawn, the run block names no verdict" || bad "(vc6) rc=$RC calls=$(cat "$FAKE_GH/calls") block=$(grep '| verdict-uncheckable' "$FAKE_GH/pr-body.md")"
fixture vc7; printf 'build-pr\nreview-needs-work-notes-reason\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(vc7) 'reason: render-unavailable' as prose under ## Notes is not the render reason: the needs-work goes to a BUILD"

# (m) rounds spent
fixture m; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; expect rounds-spent "(m) two needs-work rounds"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
