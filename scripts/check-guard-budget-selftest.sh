#!/usr/bin/env bash
# check-guard-budget-selftest.sh — fixture-driven proof of the guard/test shell ceiling (#641).
#
# Each fixture is its own tiny git repo (mkrepo), so the base-ref merge-base logic under test is
# exercised for real rather than mocked. Runs under the repo's *-selftest.sh CI loop.
# Bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-guard-budget.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t guard-budget-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # mkrepo <dir> — base repo, main branch, no guard files yet
  git -C "$1" init -q -b main
  git -C "$1" -c user.name=t -c user.email=t@t config commit.gpgsign false
}

commit() { # commit <dir> <msg> — stage everything and commit
  git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}

guardfile() { # guardfile <dir> <relpath> <lines> — a check-*.sh matching classify()'s pattern
  mkdir -p "$(dirname "$1/$2")"
  local n=$3 i=0
  : > "$1/$2"
  while [ "$i" -lt "$n" ]; do echo "# line $i" >> "$1/$2"; i=$((i + 1)); done
}

# ---- Case 1: measured mass under the committed ceiling => must PASS.
R="$TMP/r1"; mkdir -p "$R/tools"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
printf '# fixture\n100\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "1 measured (10) under ceiling (100) passes" || bad "1 expected rc=0, got $rc"

# ---- Case 2: measured mass over the committed ceiling => must FAIL, naming the overage.
R="$TMP/r2"; mkdir -p "$R/tools"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 150
printf '# fixture\n100\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
OUT="$(cd "$R" && bash "$GATE" main 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "2 measured (150) over ceiling (100) fails (rc=1)" || bad "2 expected rc=1, got $rc"
echo "$OUT" | grep -qE 'over by 50' && ok "2 names the overage (50 lines)" || bad "2 did not name the overage: $OUT"

# ---- Case 3: ceiling raised in the same diff with NO reason => must FAIL.
R="$TMP/r3"; mkdir -p "$R/tools"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
printf '# fixture\n100\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
printf '# fixture\n500\t2026-01-02\n' > "$R/tools/guard-budget.tsv"
commit "$R" "raise, no reason"
OUT="$(cd "$R" && bash "$GATE" main 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "3 ceiling raised with no reason fails (rc=1)" || bad "3 expected rc=1, got $rc"
echo "$OUT" | grep -qE 'raised from 100 to 500' && ok "3 names the raise" || bad "3 did not name the raise: $OUT"

# ---- Case 4: ceiling raised in the same diff WITH a reason => must PASS.
R="$TMP/r4"; mkdir -p "$R/tools"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
printf '# fixture\n100\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
printf '# fixture\n500\t2026-01-02\ta genuinely new guard, priced\n' > "$R/tools/guard-budget.tsv"
commit "$R" "raise with reason"
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "4 ceiling raised WITH a reason passes" || bad "4 expected rc=0, got $rc"

# ---- Case 5: ceiling LOWERED (ratchet) needs no reason and passes, with an advisory.
R="$TMP/r5"; mkdir -p "$R/tools"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
printf '# fixture\n100\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
printf '# fixture\n50\t2026-01-02\n' > "$R/tools/guard-budget.tsv"
commit "$R" "ratchet down"
OUT="$(cd "$R" && bash "$GATE" main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "5 ceiling lowered with no reason passes" || bad "5 expected rc=0, got $rc"

# ---- Case 6: no prior committed ceiling (this PR introduces the file) => no raise check fires.
R="$TMP/r6"; mkdir -p "$R"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
commit "$R" "base, no guard-budget.tsv yet"
git -C "$R" checkout -qb feature
mkdir -p "$R/tools"
printf '# fixture\n999999\t2026-01-02\n' > "$R/tools/guard-budget.tsv"
commit "$R" "introduce the ceiling"
( cd "$R" && bash "$GATE" main >/dev/null 2>&1 )
rc=$?
[ "$rc" -eq 0 ] && ok "6 first-time introduction of the ceiling is not a 'raise'" || bad "6 expected rc=0, got $rc"

# ---- Case 7: every classify() arm counts, and a non-matching product .sh does not.
# One fixture per remaining pattern (Cases 1-6 only ever exercised check-*.sh) plus a large
# product file the ceiling would overflow into if the negative case were wrong.
R="$TMP/r7"; mkdir -p "$R"; mkrepo "$R"
guardfile "$R" "foo-selftest.sh" 5                                     # *-selftest.sh
guardfile "$R" "check-thing.sh" 10                                     # check-*.sh
guardfile "$R" "foo-lint.sh" 7                                         # *-lint.sh
guardfile "$R" "plugins/dev-pipeline/skills/build-lean/lean-gate.sh" 9 # */skills/*/lean-gate.sh
guardfile "$R" "tools/run-selftests.sh" 11                             # run-selftests.sh
guardfile "$R" "tools/mutation-sweep.sh" 13                            # mutation-sweep.sh
guardfile "$R" "tools/gate-ablation.sh" 6                              # gate-ablation.sh
guardfile "$R" "deploy.sh" 1000                                        # product .sh — must NOT count
mkdir -p "$R/tools"
printf '# fixture\n61\t2026-01-01\n' > "$R/tools/guard-budget.tsv"
commit "$R" "base"
git -C "$R" checkout -qb feature
OUT="$(cd "$R" && bash "$GATE" main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "7 all six remaining classify() arms sum to 61, product.sh (1000) excluded" \
  || bad "7 expected rc=0 (measured 61 == ceiling 61), got $rc: $OUT"

# ---- Case 8: the ceiling file itself missing => must FAIL with a usage error (rc=2).
R="$TMP/r8"; mkdir -p "$R"; mkrepo "$R"
guardfile "$R" "check-thing.sh" 10
commit "$R" "base, no tools/guard-budget.tsv"
git -C "$R" checkout -qb feature
OUT="$(cd "$R" && bash "$GATE" main 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "8 missing tools/guard-budget.tsv fails (rc=2)" || bad "8 expected rc=2, got $rc: $OUT"

echo "check-guard-budget-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
