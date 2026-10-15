#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034,SC2016,SC2012  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect); the plans' backticks are their text; run ids are plain ASCII
# run-judge-selftest.sh — run.sh scenario slice (#1053): the fails-without-the-change check judges each named test of a
# vitest-json or jest-json runner by its row in the runner's JSON report, running the runner's files in one call per leg.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
#
# The runner is a fake (tools/fake-runner.sh in the fixture repo): no vitest or jest runs here, since CI is model-free and
# node-free for these suites. The report it writes takes its shape from the runners' own JSON reporters — vitest's
# packages/vitest/src/node/reporters/json.ts (JsonTestResults: testResults[] of {name: the file's absolute path, status
# 'passed'|'failed', message, assertionResults[] of {ancestorTitles, title, fullName, status 'passed'|'failed'|'skipped'|
# 'pending'|'todo'|'disabled', failureMessages}}) and jest's @jest/test-result FormattedTestResults, written by
# `--json --outputFile`. Its error and empty shapes are the ones the #1053 record measured in scratch (D-17 on jest 28.1.3;
# F-1, F-2, F-3 on vitest 4.1.10): a file that does not load is status failed, a message, no rows; a vitest beforeAll
# failure leaves the file failed with an empty message and its rows skipped; jest reports those rows failed; a skip is
# vitest's 'skipped' and jest's 'pending'.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-judge-selftest] the per-test judge of the json runners, one call per runner per leg"

# A test file is lines the fake reads, tab-separated: `T <ancestors joined ' > ', or -> <title> <shell condition>` (a test
# that passes when the condition holds, run in the worktree), `SKIP <ancestors> <title>`, `LOADFAIL <condition>` (the file
# does not load when it holds), `HOOKFAIL <condition>` (a beforeAll throws when it holds) and `NOTCOLLECTED` (the runner
# leaves the file out of its report). The worker src/a.ts is 'y' on the record commit's tree and 'fixed' at the head.
fake_runner() { # fake_runner <calls log> -> the runner's script on stdout
  printf '#!/usr/bin/env bash\nCALLS=%q\n' "$1"
  cat <<'EOF'
mode="$1"; shift; base="${mode%%-*}"; variant=""; [ "$mode" = "$base" ] || variant="${mode#*-}"
out=""; files=()
for a in "$@"; do case "$a" in --outputFile=*) out="${a#--outputFile=}" ;; -*) ;; *) files+=("$a") ;; esac; done
echo "call $mode ${#files[@]} $(cat src/a.ts)" >> "$CALLS"
[ "$variant" != hang ] || { sleep 30; exit 1; }
results='[]'; failed=0
for f in "${files[@]}"; do
  ! grep -q '^NOTCOLLECTED' "$f" || continue
  load="$(awk -F'\t' '$1 == "LOADFAIL" { print $2 }' "$f")"; hook="$(awk -F'\t' '$1 == "HOOKFAIL" { print $2 }' "$f")"
  if [ -n "$load" ] && eval "$load"; then
    results="$(jq -c --arg n "$f" '. + [{name: $n, status: "failed", message: "SyntaxError: Unexpected token — the file does not load", assertionResults: []}]' <<<"$results")"; failed=1; continue
  fi
  hooked=0; if [ -n "$hook" ] && eval "$hook"; then hooked=1; fi
  rows='[]'
  while IFS=$'\t' read -r kind anc title cond; do
    case "$kind" in
      T) if [ "$hooked" -eq 1 ]; then if [ "$base" = vitest ]; then st=skipped; else st=failed; fi
         elif eval "$cond"; then st=passed; else st=failed; fi ;;
      SKIP) if [ "$base" = vitest ]; then st=skipped; else st=pending; fi ;;
      *) continue ;;
    esac
    rows="$(jq -c --arg a "$anc" --arg t "$title" --arg s "$st" '(if $a == "-" then [] else ($a | split(" > ")) end) as $anc
      | . + [{ancestorTitles: $anc, title: $t, fullName: ($anc + [$t] | join(" ")), status: $s, failureMessages: (if $s == "failed" then ["AssertionError"] else [] end)}]' <<<"$rows")"
  done < "$f"
  fst=passed
  if [ "$(jq '[.[] | select(.status == "failed")] | length' <<<"$rows")" -gt 0 ]; then fst=failed; fi
  if [ "$hooked" -eq 1 ]; then fst=failed; fi
  [ "$fst" = passed ] || failed=1
  results="$(jq -c --arg n "$f" --arg s "$fst" --argjson r "$rows" '. + [{name: $n, status: $s, message: "", assertionResults: $r}]' <<<"$results")"
done
[ "$variant" = noreport ] || jq -n --argjson r "$results" '{success: ([$r[] | select(.status == "failed")] | length == 0), testResults: $r}' > "$out"
[ "$variant" != exit0 ] || exit 0
exit "$failed"
EOF
}
J_RUNNERS='[
  {"when":["*.vtest.ts"],"format":"vitest-json","command":"bash tools/fake-runner.sh vitest --reporter=json --outputFile={report} --bail=0 {files}"},
  {"when":["*.jtest.ts"],"format":"jest-json","command":"bash tools/fake-runner.sh jest --json --outputFile={report} --runTestsByPath --bail=0 {files}"},
  {"when":["*.hang.ts"],"format":"vitest-json","command":"bash tools/fake-runner.sh vitest-hang --reporter=json --outputFile={report} --bail=0 {files}","timeoutSeconds":2},
  {"when":["*.norep.ts"],"format":"vitest-json","command":"bash tools/fake-runner.sh vitest-noreport --reporter=json --outputFile={report} --bail=0 {files}"},
  {"when":["*.exit0.ts"],"format":"jest-json","command":"bash tools/fake-runner.sh jest-exit0 --json --outputFile={report} --runTestsByPath --bail=0 {files}"},
  {"when":["*.check.sh"],"command":"bash {file}"},
  {"when":["*.slow.sh"],"command":"bash {file}","timeoutSeconds":2}]'
J_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"commands\":{\"main\":{\"test\":\"true\",\"testRunners\":$J_RUNNERS}}}"
j_fixture() { # j_fixture <case> <the Test intent's ACs, as 'AC-1 AC-2'> — a v4 receipt, the fake runner committed on main
  local ti="" id
  for id in $2; do ti="$ti$id: the named tests of $id fail without the change"$'\n'; done
  FIXTURE_CONFIG="$J_CONFIG" fixture "$1" "- true" $'\n## Test intent\n\nACs: '"$2"$'\n\n'"$ti"
  sed 's/^Receipt: v3$/Receipt: v4/' "$d/main/.claude/pipeline-state/42-ledger.md" > "$d/r.tmp" && mv "$d/r.tmp" "$d/main/.claude/pipeline-state/42-ledger.md"
  mkdir -p "$d/main/tools"; fake_runner "$d/runner-calls" > "$d/main/tools/fake-runner.sh"
  git -C "$d/main" add tools/fake-runner.sh && git -C "$d/main" commit -qm "the fake runner" && git -C "$d/main" push -q origin main 2>/dev/null
  : > "$d/runner-calls"; mkdir -p "$FAKE_GH/tree-1/src"; echo fixed > "$FAKE_GH/tree-1/src/a.ts"
}
j_test() { # j_test <path under the build's tree> <line> ... — a test file of the build, one line per argument
  local p="$FAKE_GH/tree-1/$1"; shift; mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" > "$p"
}
j_plan() { printf '# Plan\n\n## 1. Tests\n\n%s\n\n## 2. Implementation\n\n- [ ] 2.1 the worker (src/a.ts)\n' "$1" > "$FAKE_GH/plan-1.md"; }
J_LOG() { cat "$(SD)/fails-without-1.1.log" 2>/dev/null; }
has_line() { grep -qF -- "$1" <<<"$(J_LOG)"; }
TAB=$'\t'; FIXED="grep -qx fixed src/a.ts"

# (j1) AC-1 AC-2 AC-6 AC-3: every per-test red in one record-tree call. AC-1: a named test that passes there is red though an
# unrelated test of its file fails there; its sibling that reads the change fails there (ok). AC-2: a named test the file
# does not report, one it skips, one in a file the runner never collected, a bare file under the vitest runner and a
# file::case under the exit runner. AC-6: two rows match one name. AC-3: a test whose file does not load there and that
# fails at the head too is red on the head leg
j_fixture j1 "AC-1 AC-2 AC-3 AC-6"
j_test src/one.vtest.ts "T${TAB}Importer > dup${TAB}rejects (409)${TAB}$FIXED" "T${TAB}Importer > dup${TAB}adds${TAB}true" "T${TAB}-${TAB}unrelated${TAB}false"
j_test src/two.vtest.ts "T${TAB}-${TAB}twice${TAB}$FIXED" "T${TAB}-${TAB}twice${TAB}$FIXED" "SKIP${TAB}-${TAB}later" "T${TAB}-${TAB}other${TAB}$FIXED"
j_test src/gone.vtest.ts "NOTCOLLECTED"
j_test src/three.vtest.ts "LOADFAIL${TAB}! $FIXED" "T${TAB}-${TAB}never${TAB}false"
j_test src/b.check.sh "$FIXED"
j_plan '- [ ] 1.1 the importer (src/one.vtest.ts::`Importer > dup > rejects (409)`, src/one.vtest.ts::`Importer > dup > adds`) [AC-1]
- [ ] 1.2 the forms a runner cannot judge (src/two.vtest.ts::missing, src/two.vtest.ts::later, src/gone.vtest.ts::x, src/one.vtest.ts, src/b.check.sh::x) [AC-2]
- [ ] 1.3 the file that does not load (src/three.vtest.ts::never) [AC-3]
- [ ] 1.4 two rows (src/two.vtest.ts::twice) [AC-6]'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(j1) a red per-test judge on the last checks-red attempt"
has_line "ok: AC-1 — src/one.vtest.ts::Importer > dup > rejects (409) fails on the record commit's tree" \
  && has_line "RED: AC-1 — src/one.vtest.ts::Importer > dup > adds passes on the record commit's tree" \
  && ok "(j1) AC-1: the named test that passes there is red, naming AC-1 and the test, though 'unrelated' fails in its file" || bad "(j1) AC-1 log: $(J_LOG | grep -E 'AC-1' | tr '\n' '|')"
has_line "RED: AC-2 — src/two.vtest.ts::missing did not run on the record commit's tree" \
  && has_line "RED: AC-2 — src/two.vtest.ts::later is skipped on the record commit's tree, not failed" \
  && has_line "RED: AC-2 — src/gone.vtest.ts::x was not collected: testRunners[0] (*.vtest.ts) left src/gone.vtest.ts out of its report" \
  && has_line "RED: AC-2 — src/one.vtest.ts is a bare file, but testRunners[0] (*.vtest.ts) has format vitest-json, which judges named tests" \
  && has_line "RED: AC-2 — src/b.check.sh::x names one test, but testRunners[5] (*.check.sh) has format exit, which judges whole files" \
  && ok "(j1) AC-2: a missing, a skipped, an uncollected and two wrong-form named tests are each red" || bad "(j1) AC-2 log: $(J_LOG | grep -E 'AC-2' | tr '\n' '|')"
has_line "RED: AC-6 — src/two.vtest.ts::twice is ambiguous: 2 rows of the runner's report match it" \
  && ok "(j1) AC-6: two matching rows are red 'ambiguous'" || bad "(j1) AC-6 log: $(J_LOG | grep -E 'AC-6' | tr '\n' '|')"
has_line "pending: AC-3 — src/three.vtest.ts::never: its file does not load there" \
  && has_line "RED: AC-3 — src/three.vtest.ts::never does not pass at the head" \
  && ok "(j1) AC-3: a test whose file does not load there and that fails at the head is red" || bad "(j1) AC-3 log: $(J_LOG | grep -E 'AC-3' | tr '\n' '|')"
[ "$(grep -c '^call vitest ' "$d/runner-calls")" -eq 2 ] && grep -qx 'call vitest 4 y' "$d/runner-calls" && grep -qx 'call vitest 1 fixed' "$d/runner-calls" \
  && ok "(j1) the vitest runner ran once over its four files on the record commit's tree, once over the pending one at the head" || bad "(j1) calls: $(tr '\n' '|' < "$d/runner-calls")"
grep -qF "For a file such a runner matches, name each test as file::case." "$FAKE_GH/prompt-1.txt" \
  && grep -qF "within its runner's time bound (*.vtest.ts: 600s, vitest-json; *.jtest.ts: 600s, jest-json; *.hang.ts: 2s, vitest-json;" "$FAKE_GH/prompt-1.txt" \
  && ok "(j1) S-3: the build prompt states the file::case grammar and each runner's bound and format" || bad "(j1) S-3 prompt: $(grep -E 'file::case|time bound' "$FAKE_GH/prompt-1.txt" | cut -c1-300 | tr '\n' '|')"
ls "$(SD)"/fails-without-1.1-record-1.json "$(SD)"/fails-without-1.1-head-1.json >/dev/null 2>&1 \
  && ok "(j1) OR-2: each leg's report is copied into the run's state, per attempt" || bad "(j1) no report copies: $(ls "$(SD)" | tr '\n' ' ')"

# (j2) AC-3 AC-4: three vitest files and three jest files — each runner runs once on the record commit's tree and once at
# the head. On that tree two vitest files and two jest files do not load and one vitest file fails in a beforeAll (its rows
# skipped, its file failed with an empty message): pending, each passes at the head, labeled file-level. jest reports a
# beforeAll failure as failed rows, so that test fails there and is not run again
j_fixture j2 "AC-3 AC-4"
j_test src/v1.vtest.ts "LOADFAIL${TAB}! $FIXED" "T${TAB}-${TAB}a${TAB}$FIXED"
j_test src/v2.vtest.ts "HOOKFAIL${TAB}! $FIXED" "T${TAB}hooked${TAB}b${TAB}true"
j_test src/v3.vtest.ts "LOADFAIL${TAB}! $FIXED" "T${TAB}-${TAB}c${TAB}$FIXED"
j_test src/j1.jtest.ts "LOADFAIL${TAB}! $FIXED" "T${TAB}-${TAB}a${TAB}$FIXED"
j_test src/j2.jtest.ts "HOOKFAIL${TAB}! $FIXED" "T${TAB}hooked${TAB}b${TAB}true"
j_test src/j3.jtest.ts "LOADFAIL${TAB}! $FIXED" "T${TAB}-${TAB}c${TAB}$FIXED"
j_plan '- [ ] 1.1 the vitest files (src/v1.vtest.ts::a, src/v2.vtest.ts::`hooked > b`, src/v3.vtest.ts::c) [AC-3] [AC-4]
- [ ] 1.2 the jest files (src/j1.jtest.ts::a, src/j2.jtest.ts::`hooked > b`, src/j3.jtest.ts::c) [AC-4]'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(j2) pending tests that pass at the head"
[ "$(grep -c '^call vitest ' "$d/runner-calls")" -eq 2 ] && grep -qx 'call vitest 3 y' "$d/runner-calls" && grep -qx 'call vitest 3 fixed' "$d/runner-calls" \
  && [ "$(grep -c '^call jest ' "$d/runner-calls")" -eq 2 ] && grep -qx 'call jest 3 y' "$d/runner-calls" && grep -qx 'call jest 2 fixed' "$d/runner-calls" \
  && ok "(j2) AC-4: three vitest files and three jest files run in one call per runner on each leg" || bad "(j2) AC-4 calls: $(tr '\n' '|' < "$d/runner-calls")"
has_line "pending: AC-3 — src/v1.vtest.ts::a: its file does not load there" \
  && has_line "pending: AC-3 — src/v2.vtest.ts::hooked > b: it is skipped there behind a failing beforeAll" \
  && has_line "ok: AC-3 — src/v1.vtest.ts::a passes at the head" && has_line "ok: AC-3 — src/v2.vtest.ts::hooked > b passes at the head" \
  && has_line "ok: AC-4 — src/j2.jtest.ts::hooked > b fails on the record commit's tree" \
  && ok "(j2) AC-3: a file that does not load and a vitest beforeAll failure go to the head leg and pass there; jest's beforeAll rows fail" || bad "(j2) AC-3 log: $(J_LOG | tr '\n' '|' | cut -c1-900)"
grep -qE "^fails without the change at [0-9a-f]{40}: pass — 6 named test\(s\) fail on the record commit's tree [0-9a-f]{40}, 5 of them file-level$" "$FAKE_GH/pr-body.md" \
  && grep -qF "fails without the change: AC-3 file-level — src/v1.vtest.ts::a: its file does not load on the record commit's tree; the test passes at the head" "$FAKE_GH/pr-body.md" \
  && grep -qF "fails without the change: AC-3 file-level — src/v2.vtest.ts::hooked > b: its file fails in a beforeAll on the record commit's tree" "$FAKE_GH/pr-body.md" \
  && ok "(j2) S-2: the run block carries the pass and labels each pending test file-level" || bad "(j2) run block: $(grep 'without the change' "$FAKE_GH/pr-body.md" | tr '\n' '|')"

# (j3) AC-7: a call that times out, one that leaves no report, and one that reports failed rows but exits 0 — each ONE red
# naming its runner, however many tests the call covered
j_fixture j3 "AC-7"
j_test src/x.hang.ts "T${TAB}-${TAB}a${TAB}$FIXED"; j_test src/y.hang.ts "T${TAB}-${TAB}b${TAB}$FIXED"
j_test src/x.norep.ts "T${TAB}-${TAB}a${TAB}$FIXED"; j_test src/x.exit0.ts "T${TAB}-${TAB}a${TAB}$FIXED"
j_plan '- [ ] 1.1 the run-level reds (src/x.hang.ts::a, src/y.hang.ts::b, src/x.norep.ts::a, src/x.exit0.ts::a) [AC-7]'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(j3) three runner calls that cannot be judged"
[ "$(J_LOG | grep -c '^RED: ')" -eq 3 ] \
  && has_line "RED: AC-7 — testRunners[2] (*.hang.ts) did not finish within 2s on the record commit's tree, and its process group was killed — the call covered src/x.hang.ts::a, src/y.hang.ts::b" \
  && has_line "RED: AC-7 — testRunners[3] (*.norep.ts) left no readable report at {report} on the record commit's tree" \
  && has_line "RED: AC-7 — testRunners[4] (*.exit0.ts) reported failed tests but exited 0 on the record commit's tree" \
  && grep -q 'fails without the change: RED — 3 problem(s)' <<<"$OUT" \
  && ok "(j3) AC-7: a timeout, a missing report and failed rows with exit 0 are one red each, naming the runner" || bad "(j3) AC-7 log: $(J_LOG | grep -E '^RED' | tr '\n' '|')"

# (j4) AC-1 AC-2 AC-7: a case holding a backslash is matched as written — awk reads it from ENVIRON, so `\t` stays two
# characters and the test that passes there is red, never dropped; a file the runner lists with no row and no load
# message is red "did not run" (D-24); an exit runner's timeout is one red naming the runner (D-11)
j_fixture j4 "AC-1 AC-2 AC-7"
j_test src/bs.vtest.ts "T${TAB}-${TAB}path\\to${TAB}true" "T${TAB}-${TAB}other${TAB}false"
j_test src/empty.vtest.ts "# no test"
j_test src/z.slow.sh "sleep 30"
j_plan '- [ ] 1.1 the escaped title (src/bs.vtest.ts::path\to) [AC-1]
- [ ] 1.2 the empty file (src/empty.vtest.ts::x) [AC-2]
- [ ] 1.3 the slow file (src/z.slow.sh) [AC-7]'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(j4) a passing backslash case, an empty file and a slow exit file"
has_line 'RED: AC-1 — src/bs.vtest.ts::path\to passes on the record commit'"'"'s tree' \
  && ok "(j4) AC-1: a named test whose case holds a backslash and passes there is red, naming its AC" || bad "(j4) AC-1 log: $(J_LOG | grep -E 'bs.vtest' | tr '\n' '|')"
has_line "RED: AC-2 — src/empty.vtest.ts::x did not run on the record commit's tree" \
  && ok "(j4) AC-2 D-24: a file listed with no row and no load message is red 'did not run'" || bad "(j4) AC-2 log: $(J_LOG | grep -E 'empty' | tr '\n' '|')"
has_line "RED: AC-7 — testRunners[6] (*.slow.sh) did not finish within 2s on the record commit's tree, and its process group was killed — tag a smaller file, or bound the wait inside it — the call covered src/z.slow.sh" \
  && [ "$(J_LOG | grep -c '^RED: ')" -eq 3 ] \
  && ok "(j4) AC-7 D-11: an exit runner's timeout is one red naming the runner" || bad "(j4) AC-7 log: $(J_LOG | grep -E '^RED' | tr '\n' '|')"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
