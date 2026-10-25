#!/usr/bin/env bash
# render-selftest.sh — a case built for each arm, from a local upstream: the commit order, no remote, the local
# origin ref, the lane's gates in run.sh's order, both prompts rendered from the real sources with no model,
# the local gh serving the ticket and an empty PR and capturing a posted verdict, and no planted marker in
# either arm's prompt, commits, diff, ticket or record. `review` runs with a fake claude, so nothing is billed.
# A runner case builds with a fake npm and a fake jest-json runner, and `verify` accepts only its expected stop.
# shellcheck disable=SC2016  # the fixtures are shell and markdown text, written literally
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
TD="${TMPDIR:-/tmp}"
T="$(mktemp -d "${TD%/}/render-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
py() { python3 "$HERE/planted.py" --root "$R" "$@"; }
field() { python3 -c '
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v[int(k)] if isinstance(v, list) else v.get(k)
print(json.dumps(v) if isinstance(v, (dict, list)) else v)' "$@" 2>/dev/null; }

# -- the upstream: sum subtracts; two fixes are cut from it, one tested and one whose test passes either way --
U="$T/acme/tool"; mkdir -p "$U/src"
printf 'sum() { echo $(( $1 - $2 )); }\n' > "$U/src/sum.sh"
g -C "$U" init -q && g -C "$U" add -A && g -C "$U" commit -qm "initial import"
g -C "$U" config uploadpack.allowAnySHA1InWant true
BASE="$(git -C "$U" rev-parse HEAD)"
mkdir -p "$U/test" "$U/docs/plans"
g -C "$U" checkout -qb tested
printf 'sum() { echo $(( $1 + $2 )); }\n' > "$U/src/sum.sh"
printf '. "$(dirname "$0")/../src/sum.sh"\n[ "$(sum 2 3)" = 5 ]\n' > "$U/test/sum.test.sh"
printf '# Plan\n\n## 1. Sum\n\n- [ ] 1.1 A test that sum adds (test/sum.test.sh) [AC-1]\n- [ ] 1.2 Make sum add (src/sum.sh)\n' > "$U/docs/plans/tool-41-plan.md"
g -C "$U" add -A && g -C "$U" commit -qm tested
g -C "$U" checkout -q "$BASE" && g -C "$U" checkout -qb untested
mkdir -p "$U/test" "$U/docs/plans"
printf 'sum() { echo $(( $1 + $2 )); }\n' > "$U/src/sum.sh"
printf 'exit 0\n' > "$U/test/sum.test.sh"
printf '# Plan\n\n## 1. Sum\n\n- [ ] 1.1 A test that sum adds (test/sum.test.sh) [AC-1]\n- [ ] 1.2 Make sum add (src/sum.sh)\n' > "$U/docs/plans/tool-41-plan.md"
g -C "$U" add -A && g -C "$U" commit -qm untested

R="$T/root"; mkdir -p "$R/overlays/acme__tool" "$R/arms"
cp "$HERE/arms/plain.md" "$R/arms/plain.md"
printf '# Review context\n\nShell functions print their result on stdout.\n' > "$R/overlays/acme__tool/review-context.md"
printf '{"configVersion": 3, "tracker": {"type": "github"}, "commands": {"tool": {"test": "bash test/sum.test.sh", "testRunners": [{"when": ["test/*.test.sh"], "command": "bash {file}"}]}}}\n' > "$R/overlays/acme__tool/config.json"
DESC="The fix keeps a subtraction in the second branch of sum."
mkcase() { # mkcase <id> <fix branch>
  local d="$R/cases/$1"; mkdir -p "$d"
  printf '{"upstream": "file://%s", "instance": "acme__tool-42", "license": "MIT", "base": "%s", "base_branch": "main", "overlay": "acme__tool", "issue": 41, "pr": 42, "commit": "fix: sum adds its arguments", "truth": {"class": "P1", "description": "%s", "locations": [{"file": "src/sum.sh", "start": 1, "end": 1, "side": "head"}]}}\n' "$U" "$BASE" "$DESC" > "$d/case.json"
  printf '# Sum subtracts\n\n`sum 2 3` prints -1.\n\n## Acceptance criteria\n\n- AC-1: `sum 2 3` prints 5.\n' > "$d/ticket.md"
  printf '# Decision record — #41 Sum subtracts\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | How sum combines | It adds its two arguments. | user-answered | intent |\n\n## Test intent\n\nACs: AC-1\n\nAC-1: sum 2 3 prints 5\n' > "$d/record.md"
  git -C "$U" diff "$BASE" "$2" > "$d/patch.diff"
}
mkcase abc123 tested
mkcase def456 untested
leaks() { grep -Eiw 'plant|plants|planted|planting|ground.truth|answer.key|corpus|seeded|injected' "$@"; grep -iF "$DESC" "$@"; grep -F "$R" "$@"; }

echo "== the lane arm =="
py render --case abc123 --arm lane --dest "$T/lane" --clones "$T/clones" > "$T/lane.json" 2> "$T/lane.err"; rc=$?
[ "$rc" -eq 0 ] && ok "render --arm lane exits 0" || bad "render --arm lane rc=$rc: $(tail -n 5 "$T/lane.err")"
CO="$T/lane/checkout"
[ "$(git -C "$CO" log --format=%s | tr '\n' '|')" = "fix: sum adds its arguments|docs: add the decision record|chore: add the review configuration|initial import|" ] \
  && ok "the lane checkout is the base, the overlay, the record as its own commit, then the patch" || bad "lane commits: $(git -C "$CO" log --format=%s | tr '\n' '|')"
[ "$(git -C "$CO" show --name-only --format= HEAD~1)" = "docs/plans/tool-41-decisions.md" ] && ok "the record commit holds the record alone" || bad "record commit: $(git -C "$CO" show --name-only --format= HEAD~1 | tr '\n' ' ')"
[ "$(git -C "$CO" show --name-only --format= HEAD~2 | sort | tr '\n' ' ')" = ".claude/second-shift.config.json .claude/second-shift/review-context.md " ] \
  && ok "the overlay commit holds review-context.md and the config" || bad "overlay commit: $(git -C "$CO" show --name-only --format= HEAD~2 | tr '\n' ' ')"
[ -z "$(git -C "$CO" remote)" ] && [ ! -e "$CO/.git/FETCH_HEAD" ] && ok "the checkout has no remote and no FETCH_HEAD" || bad "remote: [$(git -C "$CO" remote)]"
[ "$(git -C "$CO" rev-parse refs/remotes/origin/main)" = "$(git -C "$CO" rev-parse HEAD~2)" ] && ok "origin/main is set locally, at the overlay commit" || bad "origin/main: $(git -C "$CO" rev-parse refs/remotes/origin/main 2>&1)"
[ "$(field "$T/lane.json" gates)" = '{"plan_coverage": 0, "fails_without_change": 0}' ] && [ "$(field "$T/lane.json" stopped)" = False ] \
  && ok "plan coverage and fails without the change both pass, and the case goes to review" || bad "gates: $(field "$T/lane.json" gates) stopped=$(field "$T/lane.json" stopped)"
grep -q 'fails on the record commit' "$T/lane/state/fails-without-1.log" 2>/dev/null && ok "fails without the change ran the configured runner on the record commit's tree" || bad "fwc log: $(head -n 5 "$T/lane/state/fails-without-1.log" 2>&1)"
P="$T/lane/state/review.prompt"
FIRST="$(git -C "$CO" rev-parse HEAD~1)"
grep -q "^You review PR #42 of this repository" "$P" && grep -qF "git show $FIRST:docs/plans/tool-41-decisions.md" "$P" \
  && ok "the review prompt is run.sh's, for PR 42, naming the record commit" || bad "prompt head: $(head -c 400 "$P")"
grep -qF "'gh issue view 41 --json title,body,comments'" "$P" && grep -qF "The diff is origin/main...HEAD" "$P" \
  && ok "the prompt names the case's ticket and its base branch" || bad "prompt ticket/base lines missing"
input="$(awk '/^## Scheduler input/{on=1} on' "$P")"
grep -q '^### Review policy edited' <<<"$input" && ok "the scheduler input follows the prompt" || bad "no scheduler input in the prompt"
policy="$(awk '/^### Review policy edited/{getline; print; exit}' "$P")"
[ "$policy" = '(none)' ] && ok "the overlay sits below origin/main, so the review sees no policy edit" || bad "policy section: $policy"
grep -qF 'Bash(gh issue view*)' "$T/lane/state/review.allow" && ok "the allowlist is review_allowlist()'s" || bad "allow: $(cat "$T/lane/state/review.allow")"
cmp -s "$T/lane/scratch/record-at-first.md" "$R/cases/abc123/record.md" && ok "the record at its first commit is in the scratch dir" || bad "record-at-first.md differs"
git -C "$CO" log -p > "$T/lane-log.txt"
if leaks "$P" "$T/lane-log.txt" "$T/lane/gh/issue.json" "$T/lane/gh/pr.json" > "$T/lane-leaks.txt"; then bad "a marker in the lane arm: $(head -n 3 "$T/lane-leaks.txt")"; else ok "no marker in the lane's prompt, commits, diff, ticket or PR"; fi

echo "== the local gh =="
lgh() { (cd "$CO" && env PATH="$T/lane/bin:$PATH" GH_LOCAL_DIR="$T/lane/gh" gh "$@"); }
[ "$(lgh issue view 41 --json title,body,comments --jq .title)" = "Sum subtracts" ] && ok "issue view serves the case's ticket" || bad "issue view: $(lgh issue view 41 --json title 2>&1)"
body="$(lgh issue view 41 --json body --jq .body)"
[ "$(lgh issue view 41 --json title,body,comments --jq '.comments | length')" = 0 ] && grep -qx -- '- AC-1: `sum 2 3` prints 5.' <<<"$body" \
  && ok "the ticket carries its AC block and no comments" || bad "ticket body: $(lgh issue view 41 --json body 2>&1 | head -c 200)"
lgh issue view 7 --json title >/dev/null 2>&1 && bad "issue view 7 answered" || ok "another issue number is not found"
[ "$(lgh pr view 42 --json body,comments --jq '[.body, (.comments | length)] | @tsv')" = "$(printf '\t0')" ] && ok "pr view serves an empty PR" || bad "pr view: $(lgh pr view 42 --json body,comments 2>&1)"
diff="$(lgh pr diff 42 2>&1)"
grep -q '^+sum() { echo \$(( \$1 + \$2 )); }' <<<"$diff" && ok "pr diff is the branch's diff from origin/main" || bad "pr diff: $(head -n 3 <<<"$diff")"
printf 'verdict: approve\nhello\n' > "$T/body.md"
lgh pr comment 42 --body-file "$T/body.md" >/dev/null && [ "$(lgh pr view 42 --json comments --jq '.comments[0].body')" = "$(printf 'verdict: approve\nhello')" ] \
  && ok "pr comment saves the body, and pr view returns it" || bad "comment: $(cat "$T/lane/gh/comments.json" 2>&1)"
lgh api repos/x >/dev/null 2>&1 && bad "gh api answered" || ok "any other gh command fails"

echo "== the plain arm =="
py render --case abc123 --arm plain --dest "$T/plain" --clones "$T/clones" > "$T/plain.json" 2> "$T/plain.err"; rc=$?
[ "$rc" -eq 0 ] && ok "render --arm plain exits 0" || bad "render --arm plain rc=$rc: $(tail -n 5 "$T/plain.err")"
PC="$T/plain/checkout"; PP="$T/plain/state/review.prompt"
[ "$(git -C "$PC" log --format=%s | tr '\n' '|')" = "fix: sum adds its arguments|chore: add the review configuration|initial import|" ] \
  && ok "the plain checkout is the same build without the record commit" || bad "plain commits: $(git -C "$PC" log --format=%s | tr '\n' '|')"
[ ! -e "$PC/docs/plans/tool-41-decisions.md" ] && [ -f "$PC/.claude/second-shift/review-context.md" ] && [ -z "$(git -C "$PC" remote)" ] \
  && ok "the plain checkout has review-context.md, no record and no remote" || bad "plain tree"
grep -qF '# Sum subtracts' "$PP" && grep -qF -- '- AC-1: `sum 2 3` prints 5.' "$PP" && grep -qF "$T/plain/scratch/verdict.md" "$PP" \
  && ok "the plain prompt carries the ticket and names its verdict file" || bad "plain prompt: $(head -c 300 "$PP")"
grep -q 'Read the decision record\|Scheduler input' "$PP" && bad "the plain prompt carries a lane rule" || ok "the plain prompt carries none of the lane's rules"
git -C "$PC" log -p > "$T/plain-log.txt"
if leaks "$PP" "$T/plain-log.txt" > "$T/plain-leaks.txt"; then bad "a marker in the plain arm: $(head -n 3 "$T/plain-leaks.txt")"; else ok "no marker in plain's prompt, commits or diff"; fi

echo "== a gate stops a case =="
py render --case def456 --arm lane --dest "$T/stop" --clones "$T/clones" > "$T/stop.json" 2> "$T/stop.err"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/stop.json" stopped)" = True ] && [ "$(field "$T/stop.json" gates fails_without_change)" = 1 ] && [ ! -e "$T/stop/state/review.prompt" ] \
  && ok "a tagged test that passes without the change stops the case before any prompt" || bad "stop: rc=$rc $(head -c 300 "$T/stop.json" 2>&1)"
[ "$(git -C "$T/stop/checkout" rev-parse --abbrev-ref HEAD)" = fix-41 ] && ok "the gate puts the checkout back on its branch" || bad "branch after the gate: $(git -C "$T/stop/checkout" rev-parse --abbrev-ref HEAD)"

echo "== review, with a fake claude =="
mkdir -p "$T/fakebin"
cat > "$T/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
if [ -p /dev/stdin ]; then
  echo "fake claude: the prompt is a pipe, which claude -p gives up on after 3 s" >&2
  exit 1
fi
prompt="$(cat)"
echo "fake claude: read a prompt of ${#prompt} bytes" >&2
if [ -n "${FAKE_HANG:-}" ]; then
  echo '{"type": "system", "subtype": "init"}'
  exec sleep 60
fi
if grep -q '^You review PR #' <<<"$prompt"; then
  d="$(mktemp -d)"
  printf 'verdict: approve\nreviewed: %s\n\n## Summary\nMergeable as it is.\nNothing to do.\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n| D-1 | honored | src/sum.sh:1 adds its arguments. |\n\n## Findings\n\nNone.\n' "$(git rev-parse HEAD)" > "$d/v.md"
  gh pr comment 42 --body-file "$d/v.md" >/dev/null; rm -rf "$d"
else
  out="$(sed -n 's/^Output: write your verdict to `\(.*\)` in this form and nothing else:$/\1/p' <<<"$prompt")"
  printf 'verdict: needs-work\n## Findings\n- [blocker] B1 src/sum.sh:1 — sum still subtracts.\n  Scenario: sum 2 3 → -1\n' > "$out"
fi
echo '{"type": "result", "subtype": "success", "result": "done", "total_cost_usd": 0.5, "num_turns": 2}'
EOF
chmod +x "$T/fakebin/claude"
PATH="$T/fakebin:$PATH" py review --case abc123 --arm lane --dest "$T/rv-lane" --clones "$T/clones" --reviewer-model fake --no-bench > "$T/rv-lane.json" 2> "$T/rv-lane.err"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/rv-lane.json" status)" = ok ] && [ "$(field "$T/rv-lane.json" verdict)" = approve ] && [ "$(field "$T/rv-lane.json" rows D-1)" = honored ] \
  && ok "the lane's posted verdict is captured through the local gh and passes verdict-check.sh" || bad "lane review: rc=$rc $(head -c 600 "$T/rv-lane.json") $(tail -n 3 "$T/rv-lane.err")"
PATH="$T/fakebin:$PATH" py review --case abc123 --arm plain --dest "$T/rv-plain" --clones "$T/clones" --reviewer-model fake --no-bench > "$T/rv-plain.json" 2> "$T/rv-plain.err"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$T/rv-plain.json" status)" = ok ] && [ "$(field "$T/rv-plain.json" findings 0 path)" = src/sum.sh ] && [ "$(field "$T/rv-plain.json" findings 0 line)" = 1 ] \
  && ok "plain's verdict file is read: one [blocker] at src/sum.sh:1" || bad "plain review: rc=$rc $(head -c 600 "$T/rv-plain.json") $(tail -n 3 "$T/rv-plain.err")"

echo "== the session's output is kept =="
S="$T/rv-lane/work/state"
[ "$(field "$T/rv-lane.json" session_stdout)" = "$S/session.stdout" ] && [ "$(field "$T/rv-lane.json" session_stderr)" = "$S/session.stderr" ] \
  && ok "the record names the session's stdout and stderr files under state/" || bad "record paths: $(field "$T/rv-lane.json" session_stdout) $(field "$T/rv-lane.json" session_stderr)"
grep -qF '"total_cost_usd": 0.5' "$S/session.stdout" 2>/dev/null && grep -q '^fake claude: read a prompt of [0-9]* bytes$' "$S/session.stderr" 2>/dev/null \
  && ok "the session's stdout and stderr land in state/session.stdout and state/session.stderr" || bad "session files: $(head -c 200 "$S/session.stdout" 2>&1) | $(head -c 200 "$S/session.stderr" 2>&1)"
FAKE_HANG=1 PATH="$T/fakebin:$PATH" py review --case abc123 --arm plain --dest "$T/rv-hang" --clones "$T/clones" --reviewer-model fake --reviewer-timeout-s 3 --no-bench > "$T/rv-hang.json" 2> "$T/rv-hang.err"; rc=$?
H="$T/rv-hang/work/state"
[ "$rc" -eq 0 ] && [ "$(field "$T/rv-hang.json" status)" = timeout ] && [ "$(field "$T/rv-hang.json" session_stdout)" = "$H/session.stdout" ] && [ "$(field "$T/rv-hang.json" session_stderr)" = "$H/session.stderr" ] \
  && ok "a session that outlives its timeout is a timeout, and its record names both files" || bad "hang: rc=$rc $(head -c 600 "$T/rv-hang.json") $(tail -n 3 "$T/rv-hang.err")"
grep -qxF '{"type": "system", "subtype": "init"}' "$H/session.stdout" 2>/dev/null && grep -q '^fake claude: read a prompt' "$H/session.stderr" 2>/dev/null \
  && ok "a timed-out session keeps what it wrote before the kill" || bad "hang files: $(head -c 200 "$H/session.stdout" 2>&1) | $(head -c 200 "$H/session.stderr" 2>&1)"

echo "== a runner case, with a fake npm and a fake jest-json runner =="
J="$T/acme/calc"; mkdir -p "$J/src"
printf 'sum() { echo $(( $1 - $2 )); }\n' > "$J/src/sum.sh"
printf '{"name": "calc", "devDependencies": {"fakejest": "1.0.0"}}\n' > "$J/package.json"
g -C "$J" init -q && g -C "$J" add -A && g -C "$J" commit -qm "initial import"
g -C "$J" config uploadpack.allowAnySHA1InWant true
JBASE="$(git -C "$J" rev-parse HEAD)"
fix() { # fix <branch> <test body> <plan tag>
  g -C "$J" checkout -q "$JBASE" && g -C "$J" checkout -qb "$1"
  mkdir -p "$J/test" "$J/docs/plans"
  printf 'sum() { echo $(( $1 + $2 )); }\n' > "$J/src/sum.sh"
  printf '%s\n' "$2" > "$J/test/sum.test.sh"
  printf '# Plan\n\n## 1. Sum\n\n- [ ] 1.1 A test that sum adds (test/sum.test.sh::adds) [%s]\n- [ ] 1.2 Make sum add (src/sum.sh)\n' "$3" > "$J/docs/plans/calc-41-plan.md"
  g -C "$J" add -A && g -C "$J" commit -qm "$1"
}
fix vacuous "printf 'case\\tpassed\\tadds\\n'" AC-1
fix real '. "$(dirname "$0")/../src/sum.sh"; if [ "$(sum 2 3)" = 5 ]; then printf '"'"'case\tpassed\tadds\n'"'"'; else printf '"'"'case\tfailed\tadds\n'"'"'; fi' AC-1
fix untagged "printf 'case\\tpassed\\tadds\\n'" AC-2
mkdir -p "$T/fake"
cat > "$T/fake/jest.py" <<'EOF'
import json, subprocess, sys
report, files = sys.argv[1], sys.argv[2:]
results = []
for f in files:
    out = subprocess.run(["bash", f], capture_output=True, text=True).stdout
    rows = [l.split("\t") for l in out.splitlines() if l.startswith("case\t")]
    tests = [{"ancestorTitles": [], "title": r[2], "status": r[1]} for r in rows if len(r) == 3]
    status = "failed" if any(t["status"] == "failed" for t in tests) else "passed"
    results.append({"name": f, "status": status, "message": "", "assertionResults": tests})
json.dump({"testResults": results}, open(report, "w"))
sys.exit(1 if any(r["status"] == "failed" for r in results) else 0)
EOF
mkdir -p "$T/npmbin"
cat > "$T/npmbin/npm" <<'EOF'
#!/usr/bin/env bash
echo "$PWD $*" >> "$FAKE_NPM_LOG"
[ -f package.json ] || exit 1
[ -z "${FAKE_NPM_EMPTY:-}" ] || exit 0
mkdir -p node_modules/fakejest && cp "$FAKE_JEST" node_modules/fakejest/jest.py
EOF
chmod +x "$T/npmbin/npm"
for ov in acme__calc acme__calc-noreport; do mkdir -p "$R/overlays/$ov"; printf '# Review context\n\nShell functions print their result on stdout.\n' > "$R/overlays/$ov/review-context.md"; done
printf '{"configVersion": 3, "tracker": {"type": "github"}, "commands": {"calc": {"test": "bash test/sum.test.sh", "testRunners": [{"when": ["test/*.test.sh"], "command": "python3 node_modules/fakejest/jest.py {report} {files}", "format": "jest-json"}]}}}\n' > "$R/overlays/acme__calc/config.json"
printf '{"configVersion": 3, "tracker": {"type": "github"}, "commands": {"calc": {"test": "bash test/sum.test.sh", "testRunners": [{"when": ["test/*.test.sh"], "command": "python3 node_modules/fakejest/jest.py %s/elsewhere.json {files}", "format": "jest-json"}]}}}\n' "$T" > "$R/overlays/acme__calc-noreport/config.json"
mkrunner() { # mkrunner <id> <fix branch> <overlay>
  local d="$R/cases/$1"; mkdir -p "$d"
  printf '{"upstream": "file://%s", "instance": "acme__calc-42", "license": "MIT", "base": "%s", "base_branch": "main", "overlay": "%s", "issue": 41, "pr": 42, "commit": "fix: sum adds its arguments", "expect_stop": "fails_without_change", "truth": {"class": "P1", "description": "%s", "locations": [{"file": "test/sum.test.sh", "start": 1, "end": 1, "side": "head"}]}}\n' "$J" "$JBASE" "$3" "$DESC" > "$d/case.json"
  printf '# Sum subtracts\n\n`sum 2 3` prints -1.\n\n## Acceptance criteria\n\n- AC-1: `sum 2 3` prints 5.\n' > "$d/ticket.md"
  printf '# Decision record — #41 Sum subtracts\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | How sum combines | It adds its two arguments. | user-answered | intent |\n\n## Test intent\n\nACs: AC-1\n\nAC-1: sum 2 3 prints 5\n' > "$d/record.md"
  git -C "$J" diff "$JBASE" "$2" > "$d/patch.diff"
}
mkrunner vac111 vacuous acme__calc
mkrunner rea222 real acme__calc
mkrunner unt333 untagged acme__calc
mkrunner nor444 vacuous acme__calc-noreport
export FAKE_NPM_LOG="$T/npm.log" FAKE_JEST="$T/fake/jest.py"
vfy() { PATH="$T/npmbin:$PATH" py verify --case "$1" --dest "$T/verify-$1" --clones "$T/rclones" > "$T/verify-$1.out" 2>&1; }
vfy vac111; rc=$?
[ "$rc" -eq 0 ] && grep -qx 'expected stop fails_without_change: met' "$T/verify-vac111.out" \
  && ok "verify passes a runner case whose tagged test passes without the change, so the lane stops on fails without the change" || bad "vac111: rc=$rc $(tail -n 5 "$T/verify-vac111.out" | tr '\n' '|')"
grep -q "^RED: AC-1 — test/sum.test.sh::adds passes on the record commit's tree" "$T/verify-vac111/vac111/lane/state/fails-without-1.log" 2>/dev/null \
  && ok "the gate ran the jest-json runner from the installed node_modules and named the tagged test" || bad "vac111 log: $(head -n 8 "$T/verify-vac111/vac111/lane/state/fails-without-1.log" 2>&1 | tr '\n' '|')"
vfy rea222; rc=$?
[ "$rc" -eq 1 ] && grep -qx 'expected stop fails_without_change: NOT met — the lane did not stop' "$T/verify-rea222.out" \
  && ok "verify fails a runner case whose tagged test fails without the change, since the lane goes on to review" || bad "rea222: rc=$rc $(tail -n 5 "$T/verify-rea222.out" | tr '\n' '|')"
vfy unt333; rc=$?
[ "$rc" -eq 1 ] && grep -qx 'expected stop fails_without_change: NOT met — the lane stopped on plan coverage (exit 1)' "$T/verify-unt333.out" \
  && ok "verify fails a runner case that stops on plan coverage" || bad "unt333: rc=$rc $(tail -n 5 "$T/verify-unt333.out" | tr '\n' '|')"
vfy nor444; rc=$?
[ "$rc" -eq 1 ] && grep -q "^expected stop fails_without_change: NOT met — a red other than a tagged test of a truth file passing on the record commit's tree: RED: .* left no readable report" "$T/verify-nor444.out" \
  && ok "verify fails a runner case that stops because its runner wrote no report" || bad "nor444: rc=$rc $(tail -n 5 "$T/verify-nor444.out" | tr '\n' '|')"
[ "$(grep -c . "$FAKE_NPM_LOG" 2>/dev/null)" = 1 ] && grep -q ' install --ignore-scripts' "$FAKE_NPM_LOG" && [ -d "$T/rclones/acme__calc.deps/$JBASE/node_modules" ] \
  && ok "npm install ran once for the four cases on one base, both arms each, with its result kept beside the bare clones" || bad "npm calls: $(cat "$FAKE_NPM_LOG" 2>&1 | tr '\n' '|')"
[ -z "$(git -C "$T/verify-vac111/vac111/plain/checkout" status --porcelain)" ] && [ -f "$T/verify-vac111/vac111/plain/checkout/node_modules/fakejest/jest.py" ] \
  && ok "each checkout holds the installed node_modules, and git does not list them" || bad "plain checkout: $(git -C "$T/verify-vac111/vac111/plain/checkout" status --porcelain | head -n 3 | tr '\n' '|')"
FAKE_NPM_EMPTY=1 PATH="$T/npmbin:$PATH" py render --case vac111 --arm lane --dest "$T/empty" --clones "$T/eclones" > "$T/empty.out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q "vac111: the runner needs node_modules/fakejest/jest.py, which the install at .* did not provide" "$T/empty.out" \
  && ok "an install that leaves no runner binary fails the build, naming the binary" || bad "empty install: rc=$rc $(tail -n 3 "$T/empty.out" | tr '\n' '|')"

echo "render-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
