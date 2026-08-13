#!/usr/bin/env bash
# lane-registry-selftest.sh — behavioral guard for lane-registry.sh (#526).
#
# NOTHING HERE RE-DECLARES THE HELPER'S LOGIC. Every case runs the REAL script; the process
# facts it reads are staged through its documented LEAN_LANE_PS_DIR seam so an ancestry, a dead
# pid and a RECYCLED pid are all reproducible without spawning anything. The last two cases drop
# the seam entirely and run against the live process tree, so the real `ps` path is exercised
# too rather than modelled.
#
# NO CONCURRENCY. The registry file IS the seam this ticket introduces, so every case stages
# rows deterministically. A suite that raced real lanes would be testing the scheduler.
#
# The ceiling assertions are keyed on the CORES THE HELPER ITSELF REPORTS (field 3), never on a
# re-implementation of its core count — a suite that recomputed `getconf` would agree with a
# broken helper. What is asserted is the relationship: lanes=1 yields the whole machine, lanes
# equal to cores yields 1, and MORE lanes than cores still yields 1 and never 0.
set -uo pipefail

FAILS=0
ok()   { echo "  pass:  $1"; }
fail() { echo "  FAIL:  $1"; FAILS=$((FAILS + 1)); }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LR="$HERE/lane-registry.sh"
[[ -f "$LR" ]] || { echo "lane-registry-selftest: missing $LR" >&2; exit 2; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/lane-registry-selftest.XXXXXX")" || exit 2
trap 'rm -rf "$BASE"' EXIT

TAB="$(printf '\t')"

# stage_proc <ps-dir> <pid> <ppid> <comm> [start]
# A process exists exactly when its files exist. Omitting <start> models a pid `ps` answers
# about only partially, which is what a race between the read and the exit looks like.
stage_proc() {
  local d="$1" pid="$2" ppid="$3" comm="$4" start="${5:-}"
  mkdir -p "$d"
  printf '%s' "$ppid" > "$d/$pid.ppid"
  printf '%s' "$comm" > "$d/$pid.comm"
  [[ -z "$start" ]] || printf '%s' "$start" > "$d/$pid.lstart"
}

# row <pid> <start> <issue> — one registry line
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "2026-01-01T00:00:00Z"; }

# field <n> <line>
field() { printf '%s' "$2" | cut -d"$TAB" -f"$1"; }

echo "== lane-registry-selftest =="

# ---------------------------------------------------------------------------------------
# (a) LEAN_LANE_PID wins outright — the escape hatch a scheduler registering itself needs.
# ---------------------------------------------------------------------------------------
PS_A="$BASE/ps-a"
stage_proc "$PS_A" 100 200 bash "Mon Jan  1 00:00:00 2026"
stage_proc "$PS_A" 200 300 zsh  "Mon Jan  1 00:00:00 2026"
stage_proc "$PS_A" 300 1   claude "Mon Jan  1 00:00:00 2026"
OUT="$(LEAN_LANE_PS_DIR="$PS_A" LEAN_LANE_PID=4242 bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "4242" ]] \
  && ok "(a) LEAN_LANE_PID overrides the walk" \
  || fail "(a) LEAN_LANE_PID overrides the walk — got '$OUT'"

# ---------------------------------------------------------------------------------------
# (b) The walk steps over shells and stops at the first ancestor that is not one. This is the
# whole reason a pid is usable at all: the helper's own pid and its parent are both gone
# seconds after `entry`, so keying on either would make every lane reap itself.
# ---------------------------------------------------------------------------------------
OUT="$(LEAN_LANE_PS_DIR="$PS_A" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "300" ]] \
  && ok "(b) the walk stops at the first non-shell ancestor" \
  || fail "(b) the walk stops at the first non-shell ancestor — got '$OUT', wanted 300"

# ---------------------------------------------------------------------------------------
# (b2) A login shell reports as `-zsh`, and macOS `ps -o comm=` reports a full path. Both must
# still read as a shell, or the walk stops one hop early on an ordinary interactive session.
# ---------------------------------------------------------------------------------------
PS_B2="$BASE/ps-b2"
stage_proc "$PS_B2" 100 200 /bin/bash "s"
stage_proc "$PS_B2" 200 300 -zsh      "s"
stage_proc "$PS_B2" 300 1   claude    "s"
OUT="$(LEAN_LANE_PS_DIR="$PS_B2" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "300" ]] \
  && ok "(b2) '-zsh' and '/bin/bash' both read as shells" \
  || fail "(b2) '-zsh' and '/bin/bash' both read as shells — got '$OUT', wanted 300"

# ---------------------------------------------------------------------------------------
# (b3) The `-x` in `_is_shell`'s `grep -qxF`, in the direction it actually matters. The
# candidate `comm` is the PATTERN and SHELL_NAMES is the input, so `bashful` — the example the
# helper's comment used to cite — never matches either way and cannot detect the flag. A SHORT
# non-shell name can: `as`, the assembler, is a substring of `dash`. Drop `-x` and the walk
# reads pid 200 as a shell, steps over the real non-shell ancestor, and keys the lane on 300
# instead. Whole-line membership is what makes 200 the answer.
# ---------------------------------------------------------------------------------------
PS_B3="$BASE/ps-b3"
stage_proc "$PS_B3" 100 200 bash   "s"
stage_proc "$PS_B3" 200 300 as     "s"
stage_proc "$PS_B3" 300 1   claude "s"
OUT="$(LEAN_LANE_PS_DIR="$PS_B3" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "200" ]] \
  && ok "(b3) a short non-shell comm inside a shell name ('as' in 'dash') is not a shell" \
  || fail "(b3) a short non-shell comm inside a shell name ('as' in 'dash') is not a shell — got '$OUT', wanted 200"

# ---------------------------------------------------------------------------------------
# (c) An all-shell chain has no non-shell ancestor. Falls back to the immediate parent, which
# under-counts (that entry ages out fast) rather than over-counting.
# ---------------------------------------------------------------------------------------
PS_C="$BASE/ps-c"
stage_proc "$PS_C" 100 200 bash "s"
stage_proc "$PS_C" 200 1   zsh  "s"
OUT="$(LEAN_LANE_PS_DIR="$PS_C" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "200" ]] \
  && ok "(c) an all-shell chain falls back to the immediate parent" \
  || fail "(c) an all-shell chain falls back to the immediate parent — got '$OUT', wanted 200"

# ---------------------------------------------------------------------------------------
# (c2) The walk's pid-1 stop, against a pid 1 that ANSWERS. (c) above also has a ppid of 1, but
# stages no facts for it, so the walk there breaks because `_ps_field` failed — the right answer
# for the wrong reason, and a build with the pid-1 arm deleted still passes it. On a real machine
# `ps -o comm= -p 1` answers `launchd`/`systemd`, which is not a shell, so without the arm EVERY
# lane resolves onto init: one never-dying row that every later run reads as itself, collapsing
# the lane count to 1 forever. Staging init is what makes the arm's absence observable.
# ---------------------------------------------------------------------------------------
PS_C2="$BASE/ps-c2"
stage_proc "$PS_C2" 100 200 bash    "s"
stage_proc "$PS_C2" 200 1   zsh     "s"
stage_proc "$PS_C2" 1   0   launchd "s"
OUT="$(LEAN_LANE_PS_DIR="$PS_C2" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "200" ]] \
  && ok "(c2) a live, non-shell pid 1 is never the lane — the walk stops before init" \
  || fail "(c2) a live, non-shell pid 1 is never the lane — got '$OUT', wanted 200"

# ---------------------------------------------------------------------------------------
# (d) No process facts at all — a `ps` that is absent or refuses. Must still print a pid.
# ---------------------------------------------------------------------------------------
OUT="$(LEAN_LANE_PS_DIR="$BASE/ps-empty" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "100" ]] \
  && ok "(d) unanswerable process facts still yield a pid" \
  || fail "(d) unanswerable process facts still yield a pid — got '$OUT', wanted 100"

# ---------------------------------------------------------------------------------------
# (e) A ppid that does not move is a cycle. The walk must not ride it.
# ---------------------------------------------------------------------------------------
PS_E="$BASE/ps-e"
stage_proc "$PS_E" 100 200 bash "s"
stage_proc "$PS_E" 200 200 bash "s"
# No `timeout` wrapper: macOS does not ship one, and the hop cap is what bounds this anyway —
# a case that needed an external stopwatch would be asserting the wrong guarantee.
OUT="$(LEAN_LANE_PS_DIR="$PS_E" bash "$LR" lane-pid --from 100 2>/dev/null)"
[[ "$OUT" == "200" ]] \
  && ok "(e) a self-parenting ancestor terminates the walk" \
  || fail "(e) a self-parenting ancestor terminates the walk — got '$OUT', wanted 200"

# ---------------------------------------------------------------------------------------
# (f) No registry at all. The single-lane answer, NAMED, and never a confident zero.
# ---------------------------------------------------------------------------------------
REG_F="$BASE/absent/lanes.tsv"
LINE="$(bash "$LR" ceiling --registry "$REG_F" 2>/dev/null)"
CORES="$(field 3 "$LINE")"
[[ "$(field 4 "$LINE")" == "absent" && "$(field 2 "$LINE")" == "1" && "$(field 1 "$LINE")" == "$CORES" ]] \
  && ok "(f) an absent registry degrades to one lane and says so" \
  || fail "(f) an absent registry degrades to one lane and says so — got '$LINE'"
case "$CORES" in ''|*[!0-9]*) fail "(f2) the reported core count is not a number: '$CORES'" ;;
  *) [[ "$CORES" -ge 1 ]] && ok "(f2) the reported core count is a positive integer ($CORES)" \
       || fail "(f2) the reported core count is not positive: '$CORES'" ;;
esac

# ---------------------------------------------------------------------------------------
# (g) An unreadable registry. Distinguished from absent, because the remediation differs.
# Skipped as root, where the mode bits do not bind.
# ---------------------------------------------------------------------------------------
REG_G="$BASE/g-lanes.tsv"
: > "$REG_G"; chmod 000 "$REG_G"
if [[ "$(id -u)" == "0" ]] || cat "$REG_G" >/dev/null 2>&1; then
  ok "(g) SKIPPED — this user can read a mode-000 file"
else
  LINE="$(bash "$LR" ceiling --registry "$REG_G" 2>/dev/null)"
  [[ "$(field 4 "$LINE")" == "unreadable" && "$(field 2 "$LINE")" == "1" ]] \
    && ok "(g) an unreadable registry degrades to one lane and says so" \
    || fail "(g) an unreadable registry degrades to one lane and says so — got '$LINE'"
fi
chmod 644 "$REG_G" 2>/dev/null || true

# ---------------------------------------------------------------------------------------
# (h) An empty registry — a machine where every lane has torn down.
# ---------------------------------------------------------------------------------------
REG_H="$BASE/h-lanes.tsv"; : > "$REG_H"
LINE="$(bash "$LR" ceiling --registry "$REG_H" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "empty" && "$(field 2 "$LINE")" == "1" && "$(field 1 "$LINE")" == "$CORES" ]] \
  && ok "(h) an empty registry degrades to one lane and says so" \
  || fail "(h) an empty registry degrades to one lane and says so — got '$LINE'"

# ---------------------------------------------------------------------------------------
# (i) Rows whose pids are gone. Fully stale is its OWN basis — not `empty`, not a zero — and
# the rows are reaped rather than left to accumulate across every later reader.
# ---------------------------------------------------------------------------------------
PS_I="$BASE/ps-i"; mkdir -p "$PS_I"      # stages NO processes: every pid below is dead
REG_I="$BASE/i-lanes.tsv"
{ row 901 "s" 11; row 902 "s" 12; } > "$REG_I"
LINE="$(LEAN_LANE_PS_DIR="$PS_I" bash "$LR" ceiling --registry "$REG_I" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "stale" && "$(field 2 "$LINE")" == "1" && "$(field 1 "$LINE")" == "$CORES" ]] \
  && ok "(i) a fully stale registry degrades to one lane and says so" \
  || fail "(i) a fully stale registry degrades to one lane and says so — got '$LINE'"
[[ ! -s "$REG_I" ]] \
  && ok "(i2) stale rows are reaped by the reader" \
  || fail "(i2) stale rows are reaped by the reader — registry still holds: $(cat "$REG_I")"

# ---------------------------------------------------------------------------------------
# (j) A RECYCLED pid. The row's pid is alive, but it is a different process — the start times
# disagree. Crediting it is exactly the confusion the two-part key exists to prevent.
# ---------------------------------------------------------------------------------------
PS_J="$BASE/ps-j"
stage_proc "$PS_J" 903 1 claude "Tue Feb  2 02:02:02 2026"
REG_J="$BASE/j-lanes.tsv"
row 903 "Mon Jan  1 01:01:01 2026" 13 > "$REG_J"
LINE="$(LEAN_LANE_PS_DIR="$PS_J" bash "$LR" ceiling --registry "$REG_J" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "stale" && "$(field 2 "$LINE")" == "1" ]] \
  && ok "(j) a live pid whose start time moved is stale, not a lane" \
  || fail "(j) a live pid whose start time moved is stale, not a lane — got '$LINE'"

# ---------------------------------------------------------------------------------------
# (k) One live lane gets the whole machine — the uncontended case, which must not regress.
# ---------------------------------------------------------------------------------------
PS_K="$BASE/ps-k"
stage_proc "$PS_K" 801 1 claude "S1"
REG_K="$BASE/k-lanes.tsv"
row 801 "S1" 21 > "$REG_K"
LINE="$(LEAN_LANE_PS_DIR="$PS_K" bash "$LR" ceiling --registry "$REG_K" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "live" && "$(field 2 "$LINE")" == "1" && "$(field 1 "$LINE")" == "$CORES" ]] \
  && ok "(k) one live lane is handed the whole machine" \
  || fail "(k) one live lane is handed the whole machine — got '$LINE'"

# ---------------------------------------------------------------------------------------
# (l) Three live lanes. The count is the number of LIVE rows, and a dead row mixed in must not
# be counted — the case a reaper that only ran on a separate schedule would get wrong.
# ---------------------------------------------------------------------------------------
PS_L="$BASE/ps-l"
stage_proc "$PS_L" 811 1 claude "S1"
stage_proc "$PS_L" 812 1 claude "S2"
stage_proc "$PS_L" 813 1 claude "S3"
REG_L="$BASE/l-lanes.tsv"
{ row 811 "S1" 31; row 812 "S2" 32; row 899 "SX" 39; row 813 "S3" 33; } > "$REG_L"
LINE="$(LEAN_LANE_PS_DIR="$PS_L" bash "$LR" ceiling --registry "$REG_L" 2>/dev/null)"
EXPECT_L=$((CORES / 3)); [[ "$EXPECT_L" -ge 1 ]] || EXPECT_L=1
[[ "$(field 4 "$LINE")" == "live" && "$(field 2 "$LINE")" == "3" && "$(field 1 "$LINE")" == "$EXPECT_L" ]] \
  && ok "(l) three live lanes and one dead row derive a three-way ceiling ($EXPECT_L)" \
  || fail "(l) three live lanes and one dead row derive a three-way ceiling — got '$LINE', wanted lanes=3 ceiling=$EXPECT_L"
[[ "$(grep -c '[^[:space:]]' "$REG_L")" == "3" ]] \
  && ok "(l2) the dead row is reaped and the live ones survive" \
  || fail "(l2) the dead row is reaped and the live ones survive — registry: $(cat "$REG_L")"

# ---------------------------------------------------------------------------------------
# (m) MORE lanes than cores. The one arithmetic outcome that must never appear is 0 — a ceiling
# of 0 is a silent drop to serial with nothing announced, the fail-open shape this whole change
# exists to remove.
# ---------------------------------------------------------------------------------------
PS_M="$BASE/ps-m"
REG_M="$BASE/m-lanes.tsv"; : > "$REG_M"
i=1
while [[ "$i" -le $((CORES * 2 + 1)) ]]; do
  stage_proc "$PS_M" "$((7000 + i))" 1 claude "S$i"
  row "$((7000 + i))" "S$i" "4$i" >> "$REG_M"
  i=$((i + 1))
done
LINE="$(LEAN_LANE_PS_DIR="$PS_M" bash "$LR" ceiling --registry "$REG_M" 2>/dev/null)"
[[ "$(field 1 "$LINE")" == "1" && "$(field 2 "$LINE")" == "$((CORES * 2 + 1))" ]] \
  && ok "(m) more lanes than cores floors at 1, never 0" \
  || fail "(m) more lanes than cores floors at 1, never 0 — got '$LINE'"

# ---------------------------------------------------------------------------------------
# (n) register / deregister round trip against the LIVE process tree — no seam. This is the
# case that proves the real `ps` path answers at all; every case above stages its facts.
# ---------------------------------------------------------------------------------------
REG_N="$BASE/n/lanes.tsv"
bash "$LR" register --registry "$REG_N" --issue 526 --pid $$ >/dev/null 2>&1
LINE="$(bash "$LR" ceiling --registry "$REG_N" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "live" && "$(field 2 "$LINE")" == "1" ]] \
  && ok "(n) a real pid registers, and reads back live through the real ps" \
  || fail "(n) a real pid registers, and reads back live through the real ps — got '$LINE'"
bash "$LR" deregister --registry "$REG_N" --issue 526 --pid $$ >/dev/null 2>&1
LINE="$(bash "$LR" ceiling --registry "$REG_N" 2>/dev/null)"
[[ "$(field 4 "$LINE")" == "empty" ]] \
  && ok "(n2) deregister removes this lane's row" \
  || fail "(n2) deregister removes this lane's row — got '$LINE'"

# ---------------------------------------------------------------------------------------
# (o) register is idempotent. `entry` is idempotent and a resumed run calls it again; an
# appending register would let one lane hold N votes and shrink everyone else's ceiling.
# ---------------------------------------------------------------------------------------
REG_O="$BASE/o/lanes.tsv"
bash "$LR" register --registry "$REG_O" --issue 526 --pid $$ >/dev/null 2>&1
bash "$LR" register --registry "$REG_O" --issue 526 --pid $$ >/dev/null 2>&1
bash "$LR" register --registry "$REG_O" --issue 526 --pid $$ >/dev/null 2>&1
[[ "$(grep -c '[^[:space:]]' "$REG_O")" == "1" ]] \
  && ok "(o) re-registering one lane keeps one row" \
  || fail "(o) re-registering one lane keeps one row — registry: $(cat "$REG_O")"

# ---------------------------------------------------------------------------------------
# (p) `--issue` NARROWS the deregister match, it does not widen it. Another lane's row must
# survive a deregister that names the same issue key with a different pid.
# ---------------------------------------------------------------------------------------
PS_P="$BASE/ps-p"
stage_proc "$PS_P" 821 1 claude "S1"
stage_proc "$PS_P" 822 1 claude "S2"
REG_P="$BASE/p-lanes.tsv"
{ row 821 "S1" 526; row 822 "S2" 526; } > "$REG_P"
LEAN_LANE_PS_DIR="$PS_P" bash "$LR" deregister --registry "$REG_P" --issue 526 --pid 821 >/dev/null 2>&1
if [[ "$(grep -c '[^[:space:]]' "$REG_P")" == "1" ]] && grep -q '^822' "$REG_P"; then
  ok "(p) deregister drops only the named pid's row"
else
  fail "(p) deregister drops only the named pid's row — registry: $(cat "$REG_P")"
fi

# ---------------------------------------------------------------------------------------
# (q) Usage errors exit 2, the same class the runner and the sweep already use.
# ---------------------------------------------------------------------------------------
bash "$LR" wat --registry "$BASE/q.tsv" >/dev/null 2>&1; RC=$?
[[ "$RC" == "2" ]] && ok "(q) an unknown subcommand exits 2" || fail "(q) an unknown subcommand exits 2 — got rc=$RC"
env -u LEAN_LANE_REGISTRY bash "$LR" ceiling >/dev/null 2>&1; RC=$?
[[ "$RC" == "2" ]] && ok "(q2) ceiling without a registry exits 2" || fail "(q2) ceiling without a registry exits 2 — got rc=$RC"
bash "$LR" register --registry "$BASE/q.tsv" >/dev/null 2>&1; RC=$?
[[ "$RC" == "2" ]] && ok "(q3) register without --issue exits 2" || fail "(q3) register without --issue exits 2 — got rc=$RC"

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "lane-registry-selftest: all cases passed"
  exit 0
fi
echo "lane-registry-selftest: $FAILS case(s) failed"
exit 1
