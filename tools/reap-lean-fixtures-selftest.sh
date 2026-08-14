#!/usr/bin/env bash
# reap-lean-fixtures-selftest.sh — behavioral suite for tools/reap-lean-fixtures.sh (#528).
#
# Every case drives the REAL script against a private --dir, with REAP_LEAN_PS_STUB standing in
# for `kill -0`/`ps -o lstart=` so ownership is deterministic — no real pid needs to be alive or
# dead on the machine running this suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/reap-lean-fixtures.sh"
[ -x "$TOOL" ] || { echo "FATAL: $TOOL is missing or not executable — nothing to prove." >&2; exit 2; }

FAILS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/reap-lean-fixtures-selftest.XXXXXX")" || exit 2
trap 'rm -rf "$BASE"' EXIT

# ---- portable backdating — the cost-block-selftest.sh set_mtime idiom, epoch-first --------
backdate() { # backdate <path> <seconds-ago>
  local path="$1" ago="$2" ep stamp
  ep=$(( $(date -u +%s) - ago ))
  stamp="$(date -r "$ep" +%Y%m%d%H%M.%S 2>/dev/null)"
  case "$stamp" in ''|*[!0-9.]*) stamp="$(date -d "@$ep" +%Y%m%d%H%M.%S 2>/dev/null)" ;; esac
  [ -n "$stamp" ] || { echo "backdate: could not render a touch stamp on this platform" >&2; return 1; }
  touch -t "$stamp" "$path"
}

STUB="$BASE/ps-stub"; mkdir -p "$STUB"

# run_reap <dir> [args...] -> writes $OUT, sets $RC
OUT=""; RC=0
run_reap() {
  local dir="$1"; shift
  OUT="$BASE/out.$$.$RANDOM"
  REAP_LEAN_PS_STUB="$STUB" bash "$TOOL" --dir "$dir" \
    --min-age-owned-secs 5 --min-age-legacy-secs 10 "$@" > "$OUT" 2>&1
  RC=$?
}

echo "== reap-lean-fixtures-selftest =="

# ---------------------------------------------------------------------------------------
# A live owner is kept regardless of age — ownership is the safety mechanism, not age.
# ---------------------------------------------------------------------------------------
D1="$BASE/d1"; mkdir -p "$D1"
LIVE="$D1/leangate.4242.Thu_Aug_14_02_00_00_2026.ab12cd"
mkdir -p "$LIVE"
backdate "$LIVE" 999999
printf 'Thu Aug 14 02:00:00 2026\n' > "$STUB/4242.lstart"

run_reap "$D1"
[ "$RC" -eq 0 ] && [ -d "$LIVE" ] && grep -q 'keep (live owner pid 4242)' "$OUT" \
  && pass "a live owner's fixture is kept however old it is" \
  || { fail "a live owner's fixture was not kept"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# A dead owner (no stub entry — simulates a gone pid) IS removed once past the owned floor.
# ---------------------------------------------------------------------------------------
D2="$BASE/d2"; mkdir -p "$D2"
DEAD="$D2/leangate.5151.Wed_Jan_01_00_00_00_2020.ff99gg"
mkdir -p "$DEAD"
backdate "$DEAD" 30   # older than --min-age-owned-secs 5

run_reap "$D2"
[ "$RC" -eq 0 ] && [ ! -d "$DEAD" ] && grep -q 'removed: leangate.5151' "$OUT" \
  && pass "a dead owner's fixture past the owned floor is removed" \
  || { fail "a dead owner's fixture was not removed"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# The SAME dead-owner shape, too young for the owned floor — kept. Proves age is a floor
# beneath ownership, not skipped once ownership says "not live".
# ---------------------------------------------------------------------------------------
D3="$BASE/d3"; mkdir -p "$D3"
YOUNG_DEAD="$D3/leangate.6161.Wed_Jan_01_00_00_00_2020.hh11ii"
mkdir -p "$YOUNG_DEAD"   # fresh mtime — not backdated

run_reap "$D3"
[ "$RC" -eq 0 ] && [ -d "$YOUNG_DEAD" ] && grep -q 'keep (not past the 5s owned floor' "$OUT" \
  && pass "a dead owner's fixture younger than the owned floor is kept" \
  || { fail "a young dead-owner fixture was reaped early"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# A RECYCLED pid: the stub answers for that pid, but with a DIFFERENT stamp than the
# fixture's own — an unrelated live process now holds the number, not this orphan's owner.
# ---------------------------------------------------------------------------------------
D4="$BASE/d4"; mkdir -p "$D4"
RECYCLED="$D4/leangate.7171.Old_Stamp_Value.jj22kk"
mkdir -p "$RECYCLED"
backdate "$RECYCLED" 30
printf 'Totally_Different_Process\n' > "$STUB/7171.lstart"

run_reap "$D4"
[ "$RC" -eq 0 ] && [ ! -d "$RECYCLED" ] && grep -q 'removed: leangate.7171' "$OUT" \
  && pass "a recycled pid (stamp mismatch) is treated as not-owned and removed" \
  || { fail "a recycled-pid fixture was kept"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# Legacy / unstamped names — no ownership signal at all, so only the LONG floor governs.
# ---------------------------------------------------------------------------------------
D5="$BASE/d5"; mkdir -p "$D5"
LEGACY_YOUNG="$D5/leangate.ab12cd"     # 2 dot-fields: no pid, no stamp
mkdir -p "$LEGACY_YOUNG"
LEGACY_OLD="$D5/orchestrate-lean-selftest.zz99yy"
mkdir -p "$LEGACY_OLD"
backdate "$LEGACY_OLD" 30              # older than --min-age-legacy-secs 10

run_reap "$D5"
[ "$RC" -eq 0 ] && [ -d "$LEGACY_YOUNG" ] && [ ! -d "$LEGACY_OLD" ] \
  && grep -q 'keep (unstamped name' "$OUT" && grep -q 'removed: orchestrate-lean-selftest.zz99yy' "$OUT" \
  && pass "an unstamped legacy name is governed by the long floor alone" \
  || { fail "legacy age-floor handling is wrong"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# Unrelated content in the same tmp root is never touched — the glob is the whole guard.
# ---------------------------------------------------------------------------------------
D6="$BASE/d6"; mkdir -p "$D6"
UNRELATED="$D6/some-other-tool.abcdef"
mkdir -p "$UNRELATED"
backdate "$UNRELATED" 999999

run_reap "$D6"
[ "$RC" -eq 0 ] && [ -d "$UNRELATED" ] \
  && pass "content matching neither known prefix is never touched" \
  || { fail "unrelated content was removed"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# An unreadable ownership source is skipped, never fatal — the whole run still completes and
# reports rather than crashing. Simulated by pointing REAP_LEAN_PS_STUB at a directory that
# does not exist, so every owned-format candidate resolves "not owned" via the same safe path,
# and the script still exits 0 with a summary line.
# ---------------------------------------------------------------------------------------
D7="$BASE/d7"; mkdir -p "$D7"
UNREADABLE="$D7/leangate.8181.Whatever_Stamp.mm33nn"
mkdir -p "$UNREADABLE"
backdate "$UNREADABLE" 30

OUT="$BASE/out.unreadable"
REAP_LEAN_PS_STUB="$BASE/does-not-exist" bash "$TOOL" --dir "$D7" \
  --min-age-owned-secs 5 --min-age-legacy-secs 10 > "$OUT" 2>&1
RC=$?
[ "$RC" -eq 0 ] && [ ! -d "$UNREADABLE" ] \
  && pass "an unreadable ownership source degrades to not-owned rather than crashing" \
  || { fail "an unreadable ps-stub source was fatal or mishandled (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# --dry-run reports without removing.
# ---------------------------------------------------------------------------------------
D8="$BASE/d8"; mkdir -p "$D8"
DRY="$D8/leangate.9191.Whichever.oo44pp"
mkdir -p "$DRY"
backdate "$DRY" 30

run_reap "$D8" --dry-run
[ "$RC" -eq 0 ] && [ -d "$DRY" ] && grep -q 'would remove: leangate.9191' "$OUT" \
  && pass "--dry-run reports a reap-eligible fixture without removing it" \
  || { fail "--dry-run removed a fixture, or did not report it"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# A concurrent removal is not fatal: the candidate vanishes between discovery and the delete.
# ---------------------------------------------------------------------------------------
D9="$BASE/d9"; mkdir -p "$D9"
VANISH="$D9/leangate.2020.Ghost.qq55rr"
mkdir -p "$VANISH"
backdate "$VANISH" 30
rmdir "$VANISH"   # gone before the reaper's own stat/rm — simulates the other sweep winning

run_reap "$D9"
[ "$RC" -eq 0 ] \
  && pass "a candidate removed by a concurrent reaper does not fail the run (rc=0)" \
  || { fail "a vanished candidate reded the run (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# Usage floor.
# ---------------------------------------------------------------------------------------
OUT="$BASE/out.usage1"
bash "$TOOL" --dir "$BASE/does-not-exist" > "$OUT" 2>&1
[ "$?" -eq 2 ] && pass "usage: a nonexistent --dir is rejected" \
              || fail "usage: a nonexistent --dir was accepted"

OUT="$BASE/out.usage2"
bash "$TOOL" --dir "$BASE" --min-age-owned-secs notanumber > "$OUT" 2>&1
[ "$?" -eq 2 ] && pass "usage: a non-numeric --min-age-owned-secs is rejected" \
              || fail "usage: a non-numeric --min-age-owned-secs was accepted"

OUT="$BASE/out.usage3"
bash "$TOOL" --bogus > "$OUT" 2>&1
[ "$?" -eq 2 ] && pass "usage: an unknown argument is rejected" \
              || fail "usage: an unknown argument was accepted"

# ---------------------------------------------------------------------------------------
# --help prints the header, and only the header — the lean-gate-selftest.sh (w) / orchestrate-
# lean-selftest.sh (n) pattern, applied here: a hand-maintained `sed -n '2,Np'` line count
# silently truncates or leaks code the moment the header grows or shrinks, so it needs its own
# case rather than trusting the two siblings' coverage to somehow reach a third file.
OUT="$BASE/out.help"
bash "$TOOL" --help > "$OUT" 2>&1
help_rc=$?
help_out="$(cat "$OUT")"
if [ "$help_rc" -eq 0 ] \
   && grep -qF 'reap-lean-fixtures.sh [--dir <tmp-root>]' <<<"$help_out" \
   && ! grep -q '^set -uo pipefail' <<<"$help_out"; then
  pass "--help prints through the last header line and stops before the code"
else fail "--help did not print exactly the header (rc=$help_rc): $help_out"; fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "reap-lean-fixtures-selftest: PASS"
  exit 0
fi
echo "reap-lean-fixtures-selftest: FAIL ($FAILS)"
exit 1
