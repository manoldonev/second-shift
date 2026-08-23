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

# A live owner is kept regardless of age — ownership is the safety mechanism, not age.
D1="$BASE/d1"; mkdir -p "$D1"
LIVE="$D1/leangate.4242.Thu_Aug_14_02_00_00_2026.ab12cd"
mkdir -p "$LIVE"
backdate "$LIVE" 999999
printf 'Thu Aug 14 02:00:00 2026\n' > "$STUB/4242.lstart"

run_reap "$D1"
[ "$RC" -eq 0 ] && [ -d "$LIVE" ] && grep -q 'keep (live owner pid 4242)' "$OUT" \
  && pass "a live owner's fixture is kept however old it is" \
  || { fail "a live owner's fixture was not kept"; sed 's/^/    | /' "$OUT"; }

# A dead owner (no stub entry — simulates a gone pid) IS removed once past the owned floor.
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

# Legacy / unstamped names — no ownership signal at all, so only the LONG floor governs.
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

# Unrelated content in the same tmp root is never touched — the glob is the whole guard.
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

# --dry-run reports without removing.
D8="$BASE/d8"; mkdir -p "$D8"
DRY="$D8/leangate.9191.Whichever.oo44pp"
mkdir -p "$DRY"
backdate "$DRY" 30

run_reap "$D8" --dry-run
[ "$RC" -eq 0 ] && [ -d "$DRY" ] && grep -q 'would remove: leangate.9191' "$OUT" \
  && pass "--dry-run reports a reap-eligible fixture without removing it" \
  || { fail "--dry-run removed a fixture, or did not report it"; sed 's/^/    | /' "$OUT"; }

# A concurrent removal is not fatal: the candidate vanishes between discovery and the delete.
D9="$BASE/d9"; mkdir -p "$D9"
VANISH="$D9/leangate.2020.Ghost.qq55rr"
mkdir -p "$VANISH"
backdate "$VANISH" 30
rmdir "$VANISH"   # gone before the reaper's own stat/rm — simulates the other sweep winning

run_reap "$D9"
[ "$RC" -eq 0 ] \
  && pass "a candidate removed by a concurrent reaper does not fail the run (rc=0)" \
  || { fail "a vanished candidate reded the run (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# Usage floor.
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
# WRITER -> READER ROUND TRIP over the REAL ownership path, which no other case reaches. Every
# case above sets REAP_LEAN_PS_STUB, so `kill -0` / `ps -o lstart=` never runs and a mutation
# making the stub branch unconditional survives the whole suite — production would silently
# consult a stub directory that does not exist and read every live fixture as unowned.
#
# The fixture name is built by fixture_stamp_own — the SAME function the two fixture-producing
# suites call, not a re-derivation of the reader's expression. That distinction is the whole
# point of this case: it used to spell the sanitization out here, which compared the reader
# against a copy of itself and could not see the writer disagreeing with either. It did not:
# the writer piped `ps` output INCLUDING its newline into `tr`, the reader let `$()` strip the
# newline first, and the two matched only on a `ps` that pads lstart with a trailing blank.
# Under one that does not, this fixture is DELETED while its owner is alive.
#
# The suite's own pid is necessarily alive, and the fixture is backdated far past the owned
# floor, so KEEPING it can only be ownership talking, never age.
STAMP_LIB="$HERE/fixture-stamp.sh"
[ -r "$STAMP_LIB" ] || { echo "FATAL: $STAMP_LIB is missing — the tool sources it, so every ownership case would fail for the same uninformative reason." >&2; exit 2; }
# shellcheck source=tools/fixture-stamp.sh
. "$STAMP_LIB"

D10="$BASE/d10"; mkdir -p "$D10"
live_pid=$$
own_seg="$(fixture_stamp_own)"
REALLIVE="$D10/leangate.$own_seg.real01"
mkdir -p "$REALLIVE"
backdate "$REALLIVE" 999999

OUT="$BASE/out.realps"
env -u REAP_LEAN_PS_STUB bash "$TOOL" --dir "$D10" \
  --min-age-owned-secs 5 --min-age-legacy-secs 10 > "$OUT" 2>&1
realps_rc=$?
if [ "$realps_rc" -eq 0 ] && [ -d "$REALLIVE" ] \
   && grep -qF "keep (live owner pid $live_pid)" "$OUT"; then
  pass "a name stamped by the real producer round-trips: the reader keeps it as live-owned"
else fail "the writer->reader round trip did not keep a live-owned fixture (rc=$realps_rc): $(tail -1 "$OUT")"; fi

# ---------------------------------------------------------------------------------------
# The property that makes the round trip hold on EVERY `ps`, asserted directly rather than
# inferred from the machine this happens to run on: the token must not depend on whether the
# raw lstart string ends in a blank, a newline, both, or neither. `ps` implementations differ
# exactly there — BSD pads the column, a fixed-width ctime slice does not.
sane_bare="$(fixture_stamp_sanitize 'Fri Aug 14 14:16:19 2026')"
sane_blank="$(fixture_stamp_sanitize 'Fri Aug 14 14:16:19 2026 ')"
sane_nl="$(fixture_stamp_sanitize 'Fri Aug 14 14:16:19 2026
')"
if [ -n "$sane_bare" ] && [ "$sane_bare" = "$sane_blank" ] && [ "$sane_bare" = "$sane_nl" ]; then
  pass "the ownership token is identical whether the raw lstart string is padded, newline-terminated, or bare"
else fail "trailing-whitespace shapes produced different tokens: bare='$sane_bare' blank='$sane_blank' newline='$sane_nl'"; fi

# ---------------------------------------------------------------------------------------
# OWNERSHIP HAS THREE ANSWERS. A pid that is alive while its start time cannot be read is
# "cannot tell", not "not mine" — every failure to establish ownership must resolve toward
# keeping, because the cost of keeping is disk and the cost of deleting is a live suite's tree.
# An EMPTY stub entry models it: the pid answers, the start time does not.
D11="$BASE/d11"; mkdir -p "$D11"
UNKNOWN="$D11/leangate.3131.Some_Stamp.ss66tt"
mkdir -p "$UNKNOWN"
backdate "$UNKNOWN" 999999
: > "$STUB/3131.lstart"

run_reap "$D11"
[ "$RC" -eq 0 ] && [ -d "$UNKNOWN" ] && grep -q 'keep (ownership unknown for live pid 3131)' "$OUT" \
  && pass "a live pid whose start time cannot be read is kept, not reaped as unowned" \
  || { fail "an unresolvable-ownership fixture was reaped"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# THE DEFAULT FLOORS, which no other case reaches. Every case above passes explicit
# --min-age-*-secs, so MIN_AGE_OWNED/MIN_AGE_LEGACY are never what decides anything and
# `86400 -> 0` passed the whole suite — while the sole production call site
# (run-selftests.sh) passes no overrides, making those two constants exactly what gates real
# deletions. One fixture on each side of each floor, run with no flags at all.
D12="$BASE/d12"; mkdir -p "$D12"
OWNED_OLD="$D12/leangate.4141.Gone_Owner.aa01bb"      # dead owner, past 600s
OWNED_YOUNG="$D12/leangate.4141.Gone_Owner.cc02dd"    # dead owner, inside 600s
LEG_OLD="$D12/leangate.uu77vv"                        # unstamped, past 86400s
LEG_MID="$D12/leangate.ww88xx"                        # unstamped, past 600s but inside 86400s
mkdir -p "$OWNED_OLD" "$OWNED_YOUNG" "$LEG_OLD" "$LEG_MID"
backdate "$OWNED_OLD" 1800
backdate "$OWNED_YOUNG" 120
backdate "$LEG_OLD" 172800
backdate "$LEG_MID" 1800

OUT="$BASE/out.defaultfloors"
REAP_LEAN_PS_STUB="$STUB" bash "$TOOL" --dir "$D12" > "$OUT" 2>&1
floors_rc=$?
if [ "$floors_rc" -eq 0 ] \
   && [ ! -d "$OWNED_OLD" ] && [ -d "$OWNED_YOUNG" ] \
   && [ ! -d "$LEG_OLD" ] && [ -d "$LEG_MID" ]; then
  pass "with no flags, the built-in 600s owned floor and 86400s legacy floor are what decide"
else
  fail "the default floors did not govern (rc=$floors_rc): owned_old=$([ -d "$OWNED_OLD" ] && echo kept || echo gone) owned_young=$([ -d "$OWNED_YOUNG" ] && echo kept || echo gone) legacy_old=$([ -d "$LEG_OLD" ] && echo kept || echo gone) legacy_mid=$([ -d "$LEG_MID" ] && echo kept || echo gone)"
  sed 's/^/    | /' "$OUT"
fi

# ---------------------------------------------------------------------------------------
# The DEFAULT scan root, which no other case reaches. Every case above passes `--dir`, so the
# `--dir`-less fallback is never exercised by them and a mutation of its default value survived
# the entire suite — measured, not hypothesised. `--dry-run` is what makes asserting it safe:
# the real root is scanned, but nothing anywhere is removed.
OUT="$BASE/out.defaultroot"
env -u TMPDIR bash "$TOOL" --dry-run > "$OUT" 2>&1
defroot_rc=$?
if [ "$defroot_rc" -eq 0 ] && grep -qF 'under /tmp' "$OUT"; then
  pass "with TMPDIR unset the scan root falls back to /tmp"
else fail "the TMPDIR-unset fallback root was not /tmp (rc=$defroot_rc): $(tail -1 "$OUT")"; fi

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
