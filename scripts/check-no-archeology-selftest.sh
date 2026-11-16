#!/usr/bin/env bash
# check-no-archeology-selftest.sh — behavioral coverage for scripts/check-no-archeology.sh.
#
# Fixture trees under mktemp, each with its own scripts/no-archeology-baseline.tsv, handed to the
# real lint as its repo root. No production file is written. bash-3.2-safe, no gh, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="${NO_ARCHEOLOGY_LINT:-$HERE/check-no-archeology.sh}"

PASS=0
FAILS=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$LINT" ]] || { echo "check-no-archeology-selftest: FAIL — lint not found at $LINT" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/no-archeology-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# new_fixture <name> — a tree with one clean file per scoped kind and an empty baseline.
new_fixture() {
  local d="$WORK/$1"
  mkdir -p "$d/scripts" "$d/tools" "$d/docs" "$d/.github/workflows"
  printf '#!/usr/bin/env bash\necho clean\n' > "$d/tools/probe.sh"
  printf '// clean\n' > "$d/tools/flow.mjs"
  printf '# clean\n' > "$d/tools/calc.py"
  printf 'name: clean\n' > "$d/.github/workflows/ci.yml"
  printf '# Clean\n' > "$d/docs/guide.md"
  printf '# path\tcount\tclass\twhy\n' > "$d/scripts/no-archeology-baseline.tsv"
  printf '%s' "$d"
}
row() { printf '%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" >> "$1/scripts/no-archeology-baseline.tsv"; }
run_lint() { bash "$LINT" "$1" 2>&1; }

# expect_red <label> <root> <text the output must carry>
expect_red() {
  local out rc
  out="$(run_lint "$2")"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -qF -- "$3"; then ok "$1"
  else bad "$1 (rc=$rc, wanted '$3'):
$out"; fi
}
# expect_green <label> <root>
expect_green() {
  local out rc
  out="$(run_lint "$2")"; rc=$?
  if [[ $rc -eq 0 ]]; then ok "$1"; else bad "$1 (rc=$rc):
$out"; fi
}

echo "== the real tree =="

# The lint has no workflow step of its own: it reaches CI through this case, which the selftest
# sweep runs.
out="$(bash "$LINT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then ok "(r0) the repo itself is clean against its baseline"
else bad "(r0) the repo is not clean (rc=$rc). Remove the id, or see scripts/no-archeology-baseline.tsv:
$out"; fi

echo "== a new id in a clean file reds =="

D="$(new_fixture clean)"
expect_green "(n0) a tree with no ids and an empty baseline is green" "$D"

D="$(new_fixture issue-sh)"; echo '# guard the retry (#412)' >> "$D/tools/probe.sh"
expect_red "(n1) an issue number in a shell comment" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture ac-mjs)"; echo '// AC-3: the retry is bounded' >> "$D/tools/flow.mjs"
expect_red "(n2) an AC id in an mjs comment" "$D" "tools/flow.mjs: 1 line(s)"

D="$(new_fixture d-py)"; echo '# D-12 chose the short timeout' >> "$D/tools/calc.py"
expect_red "(n3) a decision id in a python comment" "$D" "tools/calc.py: 1 line(s)"

D="$(new_fixture wf)"; echo '# moved here in #88' >> "$D/.github/workflows/ci.yml"
expect_red "(n4) an issue number in a workflow file" "$D" ".github/workflows/ci.yml: 1 line(s)"

D="$(new_fixture doc)"; echo 'Retired in #569.' >> "$D/docs/guide.md"
expect_red "(n5) an issue number in a top-level doc" "$D" "docs/guide.md: 1 line(s)"

D="$(new_fixture label)"; echo 'ok "AC-2: a failing suite exits non-zero"' >> "$D/tools/probe.sh"
expect_red "(n6) an AC id in a test title" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture two)"; printf '# (#1)\n# (#2)\n' >> "$D/tools/probe.sh"; echo '// D-1' >> "$D/tools/flow.mjs"
out="$(run_lint "$D")"; rc=$?
[[ $rc -eq 2 ]] && ok "(n7) the exit code is the number of violating files" || bad "(n7) two violating files exited $rc:
$out"

echo "== what is not an id, and what is not read =="

D="$(new_fixture shapes)"
cat >> "$D/tools/probe.sh" <<'EOF'
len=${#1}; [ $# -gt 0 ] && echo "$#1"
echo "color: #18181b; entity: &#39; anchor: docs/guide.md#section"
# row F3 of the contract; case [F7]; (ll-q); SC2181; ISO-8601; AC-n and D-n as placeholders
EOF
expect_green "(s1) bash \${#1} and \$#, a hex color, an entity, a case label and a placeholder are not hits" "$D"

D="$(new_fixture outside)"
mkdir -p "$D/docs/plans" "$D/docs/migrations" "$D/fixtures"
echo 'Decided in #412 (D-3, AC-1).' > "$D/docs/plans/2026-01-01-record.md"
echo 'See #569.' > "$D/docs/migrations/v3.md"
echo '{"ticket": "#412"}' > "$D/fixtures/case.json"
echo 'Shipped in #412.' > "$D/CHANGELOG.md"
echo 'Shipped in #412.' > "$D/README.md"
expect_green "(s2) docs/plans, docs/migrations, the changelog, json and root markdown are out of scope" "$D"

D="$(new_fixture binary)"; printf '#!/bin/sh\n\000\001 # (#412)\n' > "$D/tools/blob.sh"
expect_green "(s3) a binary file is skipped whatever its name" "$D"

echo "== sample record data is not a hit; the same id anywhere else is =="

D="$(new_fixture heredoc)"
cat >> "$D/tools/probe.sh" <<'EOF'
cat > "$R/record.md" <<'REC'
| D-1 | which index | partial unique index, see D-2 | codebase-derived | decision |
| OR-1 | open region | the retry budget |
| S-1 | Empty state | decided (D-3) |
| RS-1 | /orders | empty | frame 12 | No orders yet |
| PM-1 | the cache goes stale | D-1 |
| F-2 | lens finding | became D-4 |
ACs: AC-1 AC-2
AC-1: the retry is bounded
AC-2: exempt — covered upstream
- AC-3 the list form
- [ ] 1.1 Write the test (tests/a.test.js) [AC-1] [AC-2]
REC
EOF
expect_green "(f1) record rows, AC lines, the id list and AC tags in a heredoc are data" "$D"

D="$(new_fixture quoted)"
cat >> "$D/tools/probe.sh" <<'EOF'
printf '# Record\n\n| D-1 | a | b | user-answered |\n| D-2 | c | d | deferred |\n' > "$R/record.md"
echo '| D-1 | secret-record-row |' > "$R/plan.md"
printf 'ACs: AC-1\nAC-1: holds — the old behavior\n' >> "$R/record.md"
echo "AC-2: unchecked — manual tier" >> "$R/record.md"
EOF
expect_green "(f2) the same shapes inside a quoted fixture string are data" "$D"

D="$(new_fixture row-comment)"; echo '# D-1 chose the partial index' >> "$D/tools/probe.sh"
expect_red "(f3) a decision id in a comment still reds" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture ac-comment)"; echo '# AC-1: the retry is bounded' >> "$D/tools/probe.sh"
expect_red "(f4) an AC line behind a comment marker still reds" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture title)"
printf '%s\n' 'true && ok "AC-1: the retry is bounded" || bad "(t1) [AC-2] the retry ran twice"' >> "$D/tools/probe.sh"
printf '%s\n' 'pass "the row | D-1 | is honored"' 'fail "decided (D-3) was not read"' >> "$D/tools/probe.sh"
expect_red "(f5) an id in an ok, bad, pass or fail title reds whatever its shape" "$D" "tools/probe.sh: 3 line(s)"

D="$(new_fixture message)"; echo 'echo "the screen names no must-show value (D-4)" >&2' >> "$D/tools/probe.sh"
expect_red "(f6) an id in an echoed runtime message still reds" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture row-tail)"; echo "echo '| D-1 | a |' > \"\$R/record.md\"   # the row D-2 supersedes" >> "$D/tools/probe.sh"
expect_red "(f7) an id after the fixture row's closing quote still reds" "$D" "tools/probe.sh: 1 line(s)"

D="$(new_fixture mid)"; echo 'note="see AC-1: and the row | D-1 | in the record"' >> "$D/tools/probe.sh"
expect_red "(f8) the shapes are data only at the start of a line or string" "$D" "tools/probe.sh: 1 line(s)"

echo "== the baseline only goes down =="

D="$(new_fixture at)"; printf '# (#1)\n# (#2)\n' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 2 debt "fixture"
expect_green "(b1) a file at its count is green" "$D"

D="$(new_fixture over)"; printf '# (#1)\n# (#2)\n# AC-3\n' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 2 debt "fixture"
expect_red "(b2) a file over its count reds" "$D" "tools/probe.sh: 3 hit(s), the baseline allows 2"

D="$(new_fixture under)"; printf '# (#1)\n' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 2 open-pr "fixture"
out="$(run_lint "$D")"; rc=$?
[[ $rc -eq 0 ]] && printf '%s' "$out" | grep -qF "tools/probe.sh: 1 hit(s), the row allows 2 — lower it" \
  && ok "(b3) a file under its count is green and the row is named as lowerable" || bad "(b3) rc=$rc:
$out"

D="$(new_fixture stale)"; row "$D" tools/probe.sh 2 debt "fixture"
expect_red "(b4) a row whose file has no hits left reds as stale" "$D" "tools/probe.sh: STALE"

D="$(new_fixture gone)"; row "$D" tools/deleted.sh 2 debt "fixture"
expect_red "(b5) a row whose file is gone reds as stale" "$D" "tools/deleted.sh: STALE"

D="$(new_fixture data)"; echo "echo \"ACs: AC-1 AC-2\"" >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 1 data "the format the tool prints"
echo '# (#412)' >> "$D/tools/calc.py"
expect_red "(b6) a row excuses its own file only" "$D" "tools/calc.py: 1 line(s)"

echo "== a baseline that cannot be read reds =="

D="$(new_fixture norow)"; echo '# (#1)' >> "$D/tools/probe.sh"; printf 'tools/probe.sh\t1\tdebt\n' >> "$D/scripts/no-archeology-baseline.tsv"
expect_red "(m1) a row with no reason" "$D" "tools/probe.sh: malformed row"

D="$(new_fixture class)"; echo '# (#1)' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 1 fine "fixture"
expect_red "(m2) an unknown class" "$D" 'unknown class "fine"'

D="$(new_fixture count)"; echo '# (#1)' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh many debt "fixture"
expect_red "(m3) a count that is not a positive number" "$D" "the count must be a positive number"

D="$(new_fixture twice)"; echo '# (#1)' >> "$D/tools/probe.sh"; row "$D" tools/probe.sh 1 debt "fixture"; row "$D" tools/probe.sh 1 debt "fixture"
expect_red "(m4) a path listed twice" "$D" "tools/probe.sh: listed twice"

D="$(new_fixture nobase)"; rm "$D/scripts/no-archeology-baseline.tsv"
expect_red "(m5) a missing baseline" "$D" "the baseline is missing"

D="$WORK/empty"; mkdir -p "$D/scripts"; printf '# none\n' > "$D/scripts/no-archeology-baseline.tsv"
expect_red "(m6) a tree with nothing in scope" "$D" "nothing was checked"

echo "== --list and the tracked-files rule =="

D="$(new_fixture list)"; echo '# guard the retry (#412)' >> "$D/tools/probe.sh"
out="$(bash "$LINT" --list "$D" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && [[ "$out" == "tools/probe.sh:3:# guard the retry (#412)" ]] \
  && ok "(l1) --list prints each hit as file:line:text and exits 0" || bad "(l1) rc=$rc: $out"

D="$(new_fixture tracked)"
if git -C "$D" init -q 2>/dev/null && git -C "$D" add -A 2>/dev/null; then
  echo '# scratch note (#412)' > "$D/tools/untracked.sh"
  expect_green "(l2) in a work tree an untracked file is not graded" "$D"
  git -C "$D" add tools/untracked.sh
  expect_red "(l3) the same file reds once it is tracked" "$D" "tools/untracked.sh: 1 line(s)"
else
  bad "(l2) could not build a git fixture"
fi

echo
echo "check-no-archeology-selftest: $PASS passed, $FAILS failed"
[[ $FAILS -eq 0 ]]
