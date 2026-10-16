#!/usr/bin/env bash
# shellcheck disable=SC2034  # RC, RTCFG and friends are read by the suites that source this file
# run-selftest-lib.sh — the shared harness of the run.sh scenario suites (run*-selftest.sh beside
# this file): a fake `claude`, a fake `gh` and a fake watch on the path, the fixture builder, and
# run_case/expect. Each suite sources it and drives run.sh through its own slice of the terminals.
# One scenario, split across suites only so the sweep runs the slices concurrently.
#
# The invariants the scenario guards are the three adjudication properties the shrink keeps: the
# checks are run by the scheduler from the record's FIRST commit (a build cannot change what runs
# against it), the head must move every round, and a verdict counts only if it is an unedited
# comment naming the current head and posted inside the review session's time window.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SCRIPT_DIR/run.sh"
PASS=0; FAIL=0
# #1053 D-4 D-13 D-15: a case is a fixture block — everything after `fixture <name>` up to the next fixture, its id the
# expanded name. Its ok/bad rows fold (any bad fails it), and at exit the suite prints one `case<TAB><passed|failed><TAB><id>`
# line per block that has a row, for the cases format of the fails-without-the-change check; a block with no row prints
# none, so a crash reads "did not run", never passed. SELFTEST_CASES (space-separated ids) selects blocks: an unselected
# block's run_case returns without launching run.sh and its rows are muted; rows before the first fixture are not
# addressable, so a selection mutes them too. Bash 3.2 has no associative array: the ids are newline lists
CASE_IDS=""; CASE_FAILED=""; CASE_CUR=""; CASE_ON=1
[ -z "${SELFTEST_CASES:-}" ] || CASE_ON=0
case_begin() { CASE_CUR="$1"; CASE_ON=1; [ -z "${SELFTEST_CASES:-}" ] || [[ " $SELFTEST_CASES " == *" $1 "* ]] || CASE_ON=0; }
case_row() { # case_row passed|failed
  [ -n "$CASE_CUR" ] || return 0
  printf '%s' "$CASE_IDS" | grep -qxF -- "$CASE_CUR" || CASE_IDS="$CASE_IDS$CASE_CUR"$'\n'
  [ "$1" = passed ] || CASE_FAILED="$CASE_FAILED$CASE_CUR"$'\n'
}
case_lines() {
  local id st
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    st=passed; ! printf '%s' "$CASE_FAILED" | grep -qxF -- "$id" || st=failed
    printf 'case\t%s\t%s\n' "$st" "$id"
  done <<<"$CASE_IDS"
}
ok()  { [ "$CASE_ON" -eq 1 ] || return 0; PASS=$((PASS+1)); echo "  ok   $*"; case_row passed; }
bad() { [ "$CASE_ON" -eq 1 ] || return 0; FAIL=$((FAIL+1)); echo "  FAIL $*"; case_row failed; }
# #1022: run.sh lints the receipt with intake-toolkit's ledger-lint.sh. The sibling plugin sits beside this one in a
# checkout (plugins/intake-toolkit) and one version segment further up in an install cache (<cache>/intake-toolkit/<v>)
IT_ROOT=""
for _c in "$SCRIPT_DIR/../../../intake-toolkit" "$SCRIPT_DIR"/../../../../intake-toolkit/*; do
  [ -f "$_c/skills/plan-interview/tools/ledger-lint.sh" ] && IT_ROOT="$(cd "$_c" && pwd)"
done; unset _c
[ -n "$IT_ROOT" ] || { echo "FATAL: no intake-toolkit beside $SCRIPT_DIR — run.sh's receipt lint has nothing to run" >&2; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/run-selftest.XXXXXX")"
trap 'case_lines; rm -rf "$T"' EXIT
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
# the config path the session was handed, and that file's content as the session starts
printf '%s\n' "${SECOND_SHIFT_CONFIG:-}" > "$S/config-path-$n.txt"; [ -f "${SECOND_SHIFT_CONFIG:-}" ] && cp "$SECOND_SHIFT_CONFIG" "$S/config-seen-$n.json"
# the session's env as claude would apply it: what it inherited, overlaid by any --settings env; the watch's own
# variables are captured too, so a leak of one into a session is visible (#939 D-29)
{ env | grep -E '^(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS|CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS|BASH_(DEFAULT|MAX)_TIMEOUT_MS|HERDR_[A-Za-z0-9_]*|RUN_WATCH[A-Za-z0-9_]*|RUN_DETACHED_LOG)='; prev=""; for a in "$@"; do [ "$prev" = --settings ] && printf '%s' "$a" | jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"'; prev="$a"; done; } | awk -F= '{ v[$1] = $0 } END { for (k in v) print v[k] }' | sort > "$S/env-$n.txt"
branch=$(git rev-parse --abbrev-ref HEAD); cost="${FAKE_COST:-1}"
# #1039: a session whose call number has a $FAKE_GH/plan-<n>.md writes it as the test-first plan, beside the record
rec=$(git ls-files 'docs/plans/*-decisions.md' 2>/dev/null | head -n 1)
[ -f "$S/plan-$n.md" ] && [ -n "$rec" ] && cp "$S/plan-$n.md" "${rec%-decisions.md}-plan.md"
# #1040: ...and a $FAKE_GH/tree-<n>/ is copied over the worktree as the session's code and tests
[ -d "$S/tree-$n" ] && cp -R "$S/tree-$n/." .
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
  build-edit-config) for c in "$S/../main/.claude/second-shift.config.json" "${SECOND_SHIFT_CONFIG:-}"; do   # the main config and the session's own copy:
                   [ -f "$c" ] || continue; jq --arg m "touch $S/edited-lint-ran" '.commands.main.lint = $m | .reviewers.optIn = ["edited"]' "$c" > "$c.tmp" && mv "$c.tmp" "$c"; done   # a lint the launch never named
                   push; openpr ;;
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
  build-pr-operator-departure) # #1085: the operator restored a guard mid-build — the head's record carries the decision as a
                   # user-answered D-2 row and its AC-9 under Test intent; the record at FIRST is untouched, and the plan tags AC-9
                   awk '$0 == "| D-1 | a | b | user-answered | intent |" { print; print "| D-2 | the guard | restored by the operator | user-answered | intent |"; next }
                        /^ACs: / { print $0 " AC-9"; print "AC-9: the restored guard refuses an over-size layout"; next } { print }' "$rec" > r.tmp && mv r.tmp "$rec"; push; openpr ;;
  build-pr-add-ac-no-row) # #1085: the same AC-9 added at the head with no ledger row to decide it — a build inventing an AC
                   awk '{ print } $0 == "AC-8: the scheduler runs the coverage check" { print "AC-9: the restored guard refuses an over-size layout" }' "$rec" \
                     | sed 's/^ACs: AC-1 AC-2 AC-8$/ACs: AC-1 AC-2 AC-8 AC-9/' > r.tmp && mv r.tmp "$rec"; push; openpr ;;
  build-pr-two-acs) # #1085: a build slip in the head's record — a second 'ACs:' line under Test intent; the record at FIRST is untouched
                   awk '{ print } /^ACs: / { print }' "$rec" > r.tmp && mv r.tmp "$rec"; push; openpr ;;
  build-pr-mark-covered) # #1039 AC-5: a build that tries to mark the coverage check passed — it exempts AC-8 in the head's
                   # record and commits a coverage script that always passes where the plugin's sits in this repo
                   sed 's/^AC-8: .*/AC-8: exempt — the build says so/' "$rec" > r.tmp && mv r.tmp "$rec"
                   mkdir -p plugins/dev-pipeline/tools; printf '#!/usr/bin/env bash\necho "plan-coverage: pass"\n' > plugins/dev-pipeline/tools/plan-coverage.sh
                   push; openpr ;;
  review-crash)    printf '{"subtype":"error_during_execution","total_cost_usd":0}\n'; exit 1 ;;
  review-approve|review-needs-work|review-wrong-sha|review-approve-dirty|review-approve-runtime|review-approve-and-push|review-needs-work-drop-base|review-needs-work-diverge|review-needs-work-notes-reason|review-needs-work-move-base|review-approve-fetched|review-push-approve-new)
    case "$plan" in   # a real review reads the PR's head as it is now, not the worktree's last fetch
      review-approve-fetched) git fetch -q origin ;;
      review-push-approve-new) push ;;
    esac
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
  review-approve-d2) post "$(ROWS=$'| D-1 | honored | fake |\n| D-2 | honored | Added by the build, user-answered. |' vbody approve "$(git rev-parse "origin/$branch")")" ;;   # #1085: the head's added row scored
  review-bad-approve-blocker)  post "$(ROWS='| D-1 | honored | fake |' FINDINGS='- [blocker] B1 must change before merge' vbody approve "$(git rev-parse "origin/$branch")")" ;;
  review-bad-approve-violated) post "$(ROWS='| D-1 | violated | fake |' vbody approve "$(git rev-parse "origin/$branch")")" ;;
  review-bad-needs-work-noblocker) post "$(FINDINGS='- [note] N1 nothing required' vbody needs-work "$(git rev-parse "origin/$branch")")" ;;
  review-approve-kb) # #1033 AC-10: review-lead's knowledge-base contributions block, carried into ## Notes
    post "$(vbody approve "$(git rev-parse "origin/$branch")" $'\n## Notes\n\nKnowledge-base contributions:\n- <kb-page> — the worker retries a 409 forever (lookup gap)\n- <kb-page> — every build round appends to work.txt (change gap)')" ;;
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
  local c="$1" chk="${2-- true}" extra="${3:-}"; d="$T/$c"; mkdir -p "$d"; case_begin "$c"
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
  # #1022 D-11: a whole v3 receipt (#1032), so the launch lint passes it; #1039: v3 carries no Test intent, so every case but
  # run-record-selftest's (pc) block, which moves it to v4, runs the plan coverage as not-applicable (an empty checks line is
  # the section's empty form); D-1's first four cells are the text (a) greps for in the build prompt; #1023: only the
  # operator's skip form lints. #1032 D-8: the knowledge-source answer carries its own heading, '| D-9 |' row and
  # 'Receipt: v99' line, indented — the launch's version read, its lint and the build's record all pass them by.
  printf '# record\n\nReceipt: v3\n\n## Intake steps\n\nRequirements: the ticket body as written\nSplit: not split\nExplore: the fixture repo\nFan-out: skipped — by the operator; the selftest fixture runs no intake\nDup-scan: no candidates\nPost-merge scan: no post-merge AC\nSizing: opus\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n\n## Open Regions\n\nNo open regions — every decision in scope is ratified.\n\n## Surface Inventory\n\nNo user-visible surface — this change renders nothing a user reads.\n\n## Fan-out\n\nFan-out: skipped — by the operator; the selftest fixture runs no intake\n\n## Knowledge source\n\nProvider: <plugin>:<provider-agent>\n\n    ## Answer\n\n    The fixture worker retries a 409 forever.\n\n    | D-9 | a knowledge-base row | x | user-answered | intent |\n\n    Receipt: v99\n\n    Sources:\n    - <kb-page>\n\n## Checks\n\n%s\n%s\n' \
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
  [ "$CASE_ON" -eq 1 ] || { OUT=""; RC=0; TERM_SLUG=""; return 0; }   # an unselected block launches nothing
  OUT="$( cd "$d/main" && bash "$RUN" 42 "$@" 2>&1 )"; RC=$?
  TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
}
expect() { [ "$CASE_ON" -eq 1 ] || return 0; [ "$TERM_SLUG" = "$1" ] && ok "$2 -> $1" || { bad "$2: expected terminal $1, got '$TERM_SLUG'"; printf '%s\n' "$OUT" | tail -n 6 | sed 's/^/       /'; }; }

# fixture inputs more than one suite reads
printf 'x' > "$T/px.png"
RTCFG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans","runtimeData":[".claude/storage","apps/api/uploads"]}}'
