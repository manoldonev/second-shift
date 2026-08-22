#!/usr/bin/env bash
# check-guard-budget-selftest.sh — fixture-driven proof of the derived guard/test shell-mass
# comparison (#641).
#
# Every case asserts the PRINTED measured value, never rc alone (AC-1's own text) — rc alone
# would not distinguish "measured correctly" from "measured wrong and got lucky on the sign".
#
# AC-2's classify() coverage is one case PER ARM: each adds one file matching exactly one
# arm and asserts the delta is exactly that file's line count, so neutering a single arm
# fails that case alone and names which arm broke. Bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-guard-budget.sh"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d -t guard-budget-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # mkrepo <dir> — base repo with a main branch and one never-counted product file
  git -C "$1" init -q -b main
  git -C "$1" -c user.name=t -c user.email=t@t config commit.gpgsign false
  mkdir -p "$1/plugins/p"
  printf 'line1\nline2\nline3\nline4\nline5\n' > "$1/plugins/p/build.sh"
  git -C "$1" add . && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "base"
}

nlines() { # nlines <n> — print <n> numbered lines, for a file of a known, assertable size
  local i=1
  while [ "$i" -le "$1" ]; do echo "line $i"; i=$((i + 1)); done
}

commit_all() { # commit_all <dir> <message>
  git -C "$1" add . && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2" >/dev/null
}

# ============================================================= AC-1: the four fixture cases

# ---- Case 1: mass DECREASED => pass, printed values show the decrease.
R="$TMP/r1"; mkdir -p "$R"; mkrepo "$R"
mkdir -p "$R/tools"
nlines 10 > "$R/tools/check-thing.sh"
commit_all "$R" "feat: add a 10-line guard"
git -C "$R" checkout -qb feature
nlines 4 > "$R/tools/check-thing.sh"
commit_all "$R" "fix: shrink the guard to 4 lines"
OUT="$( (cd "$R" && bash "$GATE" main) 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT" | grep -q "base 10, HEAD 4 (delta -6)"; then
  ok "1 mass decreased passes and prints base 10 / HEAD 4 / delta -6"
else
  bad "1 expected rc=0 and 'base 10, HEAD 4 (delta -6)', got rc=$rc: $OUT"
fi

# ---- Case 2: mass UNCHANGED (only a product file moves) => pass, values equal.
R="$TMP/r2"; mkdir -p "$R"; mkrepo "$R"
mkdir -p "$R/tools"
nlines 7 > "$R/tools/check-thing.sh"
commit_all "$R" "feat: add a 7-line guard"
git -C "$R" checkout -qb feature
echo "line6" >> "$R/plugins/p/build.sh"
commit_all "$R" "feat: product file grows, guard untouched"
OUT="$( (cd "$R" && bash "$GATE" main) 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT" | grep -q "base 7, HEAD 7 (delta 0)"; then
  ok "2 mass unchanged passes and prints base 7 / HEAD 7 / delta 0 (product growth not counted)"
else
  bad "2 expected rc=0 and 'base 7, HEAD 7 (delta 0)', got rc=$rc: $OUT"
fi

# ---- Case 3: mass INCREASED, no trailer => fail, naming the delta.
R="$TMP/r3"; mkdir -p "$R"; mkrepo "$R"
mkdir -p "$R/tools"
nlines 5 > "$R/tools/check-thing.sh"
commit_all "$R" "feat: add a 5-line guard"
git -C "$R" checkout -qb feature
nlines 12 > "$R/tools/check-thing.sh"
commit_all "$R" "feat: grow the guard with no trailer"
OUT="$( (cd "$R" && bash "$GATE" main) 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ] && echo "$OUT" | grep -q "grew by 7 lines" && echo "$OUT" | grep -q "base 5 (" ; then
  ok "3 mass increased with no trailer fails (rc=1), names delta 7 and base 5"
else
  bad "3 expected rc=1 naming 'grew by 7 lines' and 'base 5 (...)', got rc=$rc: $OUT"
fi

# ---- Case 4: mass INCREASED, WITH a Guard-mass trailer => pass.
R="$TMP/r4"; mkdir -p "$R"; mkrepo "$R"
mkdir -p "$R/tools"
nlines 5 > "$R/tools/check-thing.sh"
commit_all "$R" "feat: add a 5-line guard"
git -C "$R" checkout -qb feature
nlines 12 > "$R/tools/check-thing.sh"
git -C "$R" add . && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "feat: grow the guard" \
  -m "Guard-mass: +7 new fixture arm needs its own guard rows"
OUT="$( (cd "$R" && bash "$GATE" main) 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT" | grep -q "delta +7" && echo "$OUT" | grep -q "covered by a 'Guard-mass:' trailer"; then
  ok "4 mass increased with a Guard-mass trailer passes, printing delta +7"
else
  bad "4 expected rc=0 with delta +7 and trailer acknowledgement, got rc=$rc: $OUT"
fi

# ============================================================= AC-2: classification coverage

# ---- Negative case: a product .sh file (matches no arm) never counts, at any size.
R="$TMP/r5"; mkdir -p "$R"; mkrepo "$R"
git -C "$R" checkout -qb feature
nlines 40 > "$R/plugins/p/big-product-feature.sh"
commit_all "$R" "feat: a large product script, no guard/test naming"
OUT="$( (cd "$R" && bash "$GATE" main) 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT" | grep -q "delta 0"; then
  ok "5 a 40-line product .sh (no classify arm matches) contributes 0 to guard mass"
else
  bad "5 expected rc=0 delta 0 for an unclassified product file, got rc=$rc: $OUT"
fi

# ---- One case per classify() arm: adds ONE file matching exactly that arm, asserts the exact
# delta. arm_case <label> <relative-path> — the file always gets exactly 6 lines.
arm_case() {
  local label="$1" relpath="$2"
  local r="$TMP/arm-$label"
  mkdir -p "$r"; mkrepo "$r"
  git -C "$r" checkout -qb feature
  mkdir -p "$r/$(dirname "$relpath")"
  nlines 6 > "$r/$relpath"
  commit_all "$r" "feat: add $relpath"
  local out rc
  out="$( (cd "$r" && bash "$GATE" main) 2>&1 )"; rc=$?
  if [ "$rc" -eq 1 ] && echo "$out" | grep -q "grew by 6 lines"; then
    ok "arm:$label — $relpath counted, delta 6"
  else
    bad "arm:$label — expected rc=1 'grew by 6 lines' for $relpath, got rc=$rc: $out"
  fi
}

arm_case "selftest"    "tools/widget-selftest.sh"
arm_case "check"       "tools/check-widget.sh"
arm_case "lint"        "scripts/widget-lint.sh"
arm_case "lean-gate"   "plugins/dev-pipeline/skills/build-lean/lean-gate.sh"
arm_case "run-sf"      "tools/run-selftests.sh"
arm_case "mut-sweep"   "tools/mutation-sweep.sh"
arm_case "gate-abl"    "tools/gate-ablation.sh"

echo "check-guard-budget-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
