#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034,SC2016  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect); the fixture scripts' $ are theirs
# run-cases-selftest.sh — run.sh scenario slice (#1053): the cases format. run-selftest-lib.sh prints one
# `case<TAB><passed|failed><TAB><id>` line per fixture block at exit, its rows folded, and SELFTEST_CASES selects blocks;
# the fails-without-the-change check judges each named block by its line, testSupport bringing the head's lib onto the
# record commit's tree, and runs each selected block again at the head.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"
LIB="$SCRIPT_DIR/run-selftest-lib.sh"

echo "[run-cases-selftest] the cases format: fixture blocks as cases, selected by SELFTEST_CASES"

# (cs1) AC-9 AC-11 D-15 D-25 D-27: a suite on the real lib, its run.sh a stub that logs each launch. alpha has a bad row and
# an ok row (folds to failed), beta an ok row, delta no row (prints no case line), the fe-1/fe-2 blocks are named at run
# time; the row before the first fixture is not addressable
fixture cs1; mkdir -p "$T/cs1";printf '#!/usr/bin/env bash\necho "launch $*" >> %q\n' "$T/cs1/launches" > "$T/cs1/stub-run.sh"
cat > "$T/cs1/suite.sh" <<EOF
#!/usr/bin/env bash
source $(printf '%q' "$LIB")
RUN=$(printf '%q' "$T/cs1/stub-run.sh")
ok "a row before any fixture"
fixture alpha; run_case "\$d" alpha; bad "alpha's bad row"; ok "alpha's ok row"
fixture beta; run_case "\$d" beta; ok "beta's row"
fixture delta; run_case "\$d" delta
for v in 1 2; do fixture "fe-\$v"; ok "fe \$v's row"; done
echo "[self-test] \$PASS passed, \$FAIL failed"
EOF
all="$(bash "$T/cs1/suite.sh" 2>&1)"
printf 'case\tfailed\talpha\ncase\tpassed\tbeta\ncase\tpassed\tfe-1\ncase\tpassed\tfe-2\n' > "$T/cs1/want-all"
[ "$(grep '^case' <<<"$all")" = "$(cat "$T/cs1/want-all")" ] && grep -q '\[self-test\] 5 passed, 1 failed' <<<"$all" \
  && [ "$(cat "$T/cs1/launches")" = $'launch 42 alpha\nlaunch 42 beta\nlaunch 42 delta' ] \
  && ok "(cs1) AC-9 D-15: one case line per block with a row — alpha folds to failed, delta prints none, fe-1 and fe-2 by their expanded names" || bad "(cs1) all: $(tr '\n\t' '|^' <<<"$all")"
: > "$T/cs1/launches"
sel="$(SELFTEST_CASES='beta fe-2' bash "$T/cs1/suite.sh" 2>&1)"
[ "$(grep '^case' <<<"$sel")" = $'case\tpassed\tbeta\ncase\tpassed\tfe-2' ] && grep -q '\[self-test\] 2 passed, 0 failed' <<<"$sel" \
  && ! grep -qE "alpha|before any fixture|fe 1" <<<"$sel" && [ "$(cat "$T/cs1/launches")" = 'launch 42 beta' ] \
  && ok "(cs1) AC-11: with SELFTEST_CASES only the selected blocks launch run.sh and print; the rest print and count nothing" || bad "(cs1) selected: $(tr '\n\t' '|^' <<<"$sel") launches: $(tr '\n' '|' < "$T/cs1/launches")"

# (cs2, cs3) the scheduler: the fixture repo carries a run*-selftest.sh suite layout. On the record commit its lib is the lib
# before #1053 (rows, no case lines) and its run.sh a stub that logs each launch with what src/a.ts holds; the build's tree
# carries the real lib and the tagged suite. sel1 reads the change (one bad row, one ok row on that tree), sel2 passes on
# any tree, sel3 fails on every tree, unsel is never named
CS_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"test":"true",%s"testRunners":[{"when":["*-selftest.sh"],"format":"cases","command":"SELFTEST_CASES={cases} bash {file}"}]}}}'
CS_SUPPORT='"testSupport":["plugins/dev-pipeline/skills/run/run-selftest-lib.sh"],'
CS_TI=$'\n## Test intent\n\nACs: AC-9 AC-11\n\nAC-9: each named fixture block is judged by its folded result\nAC-11: only the selected blocks launch run.sh, and each must pass at the head\n'
SKR=plugins/dev-pipeline/skills/run
cs_fixture() { # cs_fixture <case> <config> — the repo's suite layout committed on main, the build's tree and plan
  FIXTURE_CONFIG="$2" fixture "$1" "- true" "$CS_TI"
  sed 's/^Receipt: v3$/Receipt: v4/' "$d/main/.claude/pipeline-state/42-ledger.md" > "$d/r.tmp" && mv "$d/r.tmp" "$d/main/.claude/pipeline-state/42-ledger.md"
  mkdir -p "$d/main/$SKR" "$d/main/plugins/intake-toolkit/skills/plan-interview/tools"
  echo 'exit 0' > "$d/main/plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh"   # the lib looks for its sibling plugin
  printf '#!/usr/bin/env bash\necho "launch $* $(cat "$W/src/a.ts")" >> %q\n' "$d/launches" > "$d/main/$SKR/run.sh"
  printf '%s\n' 'PASS=0; FAIL=0; ok() { PASS=$((PASS+1)); echo "  ok   $*"; }; bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }' \
    'RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.sh"; fixture() { d="$1"; }; run_case() { bash "$RUN" 42 "$@"; }' > "$d/main/$SKR/run-selftest-lib.sh"
  git -C "$d/main" add -A && git -C "$d/main" commit -qm "the suite layout" && git -C "$d/main" push -q origin main 2>/dev/null
  : > "$d/launches"; local t="$FAKE_GH/tree-1"; mkdir -p "$t/src" "$t/$SKR"; echo fixed > "$t/src/a.ts"; cp "$LIB" "$t/$SKR/run-selftest-lib.sh"
  cat > "$t/$SKR/run-x-selftest.sh" <<'EOF'
#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"
export W="$PWD"
fixture sel1; run_case "$d" sel1; grep -qx fixed "$W/src/a.ts" && ok "sel1 reads the change" || bad "sel1 does not see the change"; ok "sel1 setup"
fixture sel2; run_case "$d" sel2; [ -f "$W/src/a.ts" ] && ok "sel2 holds on any tree" || bad "sel2"
fixture sel3; run_case "$d" sel3; bad "sel3 fails on every tree"
fixture unsel; run_case "$d" unsel; ok "unsel row"
echo "[self-test] $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
EOF
  printf '# Plan\n\n## 1. Tests\n\n- [ ] 1.1 the blocks (%s::sel1, %s::sel2) [AC-9]\n- [ ] 1.2 the selected blocks (%s::sel1, %s::sel3) [AC-11]\n\n## 2. Implementation\n\n- [ ] 2.1 the worker (src/a.ts)\n' \
    "$SKR/run-x-selftest.sh" "$SKR/run-x-selftest.sh" "$SKR/run-x-selftest.sh" "$SKR/run-x-selftest.sh" > "$FAKE_GH/plan-1.md"
}
CS_LOG() { cat "$(SD)/fails-without-1.1.log" 2>/dev/null; }
has_line() { grep -qF -- "$1" <<<"$(CS_LOG)"; }
X="$SKR/run-x-selftest.sh"

# (cs2) AC-9 AC-11 D-13: testSupport brings the head's lib onto the record commit's tree; sel1 folds to failed there (ok),
# sel2 passes there (red), sel3 fails there (ok); unsel is not selected, so it neither launches run.sh nor prints a row. At
# the head the selected blocks that failed run again alone: sel1 passes, sel3 does not (red)
# shellcheck disable=SC2059  # CS_CONFIG is the format
cs_fixture cs2 "$(printf "$CS_CONFIG" "$CS_SUPPORT")"
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(cs2) a red cases judge on the last checks-red attempt"
has_line "testSupport (commands.main.testSupport), from the head, never run: $SKR/run-selftest-lib.sh" \
  && has_line "ok: AC-9 — $X::sel1 fails on the record commit's tree" && has_line "ok: AC-11 — $X::sel1 fails on the record commit's tree" \
  && has_line "RED: AC-9 — $X::sel2 passes on the record commit's tree" \
  && ok "(cs2) AC-9: each named block is judged by its folded line, the head's lib on the record commit's tree by testSupport" || bad "(cs2) AC-9 log: $(CS_LOG | grep -E 'AC-9|testSupport' | tr '\n' '|')"
grep -q "SELFTEST_CASES='sel1 sel2 sel3' bash '$X'" <<<"$OUT" \
  && [ "$(grep -c ' y$' "$d/launches")" -eq 3 ] && grep -qx 'launch 42 sel1 y' "$d/launches" && grep -qx 'launch 42 sel2 y' "$d/launches" && grep -qx 'launch 42 sel3 y' "$d/launches" \
  && ! grep -q unsel "$d/launches" && ! has_line 'unsel row' \
  && ok "(cs2) AC-11: on the record commit's tree only the selected blocks launch run.sh; unsel prints and counts nothing" || bad "(cs2) AC-11 launches: $(tr '\n' '|' < "$d/launches") out: $(grep 'SELFTEST_CASES' <<<"$OUT" | tr '\n' '|')"
grep -q "SELFTEST_CASES='sel1 sel3' bash '$X'" <<<"$OUT" && [ "$(grep -c ' fixed$' "$d/launches")" -eq 2 ] \
  && has_line "ok: AC-11 — $X::sel1 passes at the head" && has_line "RED: AC-11 — $X::sel3 does not pass at the head" \
  && ok "(cs2) AC-11 D-13: each selected block that failed there runs again at the head; one that fails there is red" || bad "(cs2) head leg: $(CS_LOG | grep -E 'head' | tr '\n' '|') launches: $(tr '\n' '|' < "$d/launches")"

# (cs3) AC-9 D-16: without testSupport the record commit's tree keeps the lib before #1053, which prints no case lines —
# each named block is red, naming testSupport, never a file-level pass of its plain exit code
# shellcheck disable=SC2059
cs_fixture cs3 "$(printf "$CS_CONFIG" '')"
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(cs3) a cases file that prints no case lines"
has_line "RED: AC-9 — $X::sel1 did not run on the record commit's tree: $X printed no case lines — is the helper lib that prints them in testSupport (commands.main.testSupport)?" \
  && has_line "RED: AC-9 — $X::sel2 did not run" && ! has_line 'ok: AC-' && ! has_line 'the head leg' \
  && ok "(cs3) AC-9: no case lines is red naming testSupport, and nothing goes to the head leg" || bad "(cs3) log: $(CS_LOG | grep -E 'RED|ok:' | tr '\n' '|')"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
