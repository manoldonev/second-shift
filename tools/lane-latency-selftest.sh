#!/usr/bin/env bash
# lane-latency-selftest.sh — behavioral cover for tools/lane-latency.sh.
#
# Zero network, zero model calls. Every case is a fixture ledger written here and handed to the
# real tool; nothing in this file re-implements the tool's arithmetic, which is the point — a
# hand-maintained copy of the epoch conversion would converge on green while production drifted.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/lane-latency.sh"
# The explicit-template form, which IS honored by a private TMPDIR (docs/testing.md), unlike the
# `-t` form the two big stamped fixture families use.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-latency-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSES=0; FAILS=0
pass() { PASSES=$((PASSES + 1)); echo "  PASS: $*"; }
fail() { FAILS=$((FAILS + 1));  echo "  FAIL: $*"; }

row() { # row <file> <ts> <launch-id> <issue> <event> [detail]
  printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "${6:-}" >> "$1"
}

# ---- (a) a measurable launch, scored on the interval OUTSIDE its payload sessions --------------
# Two spawns of 10 minutes each inside a 20:30 run: 30 seconds belongs to the scheduler.
L="$WORK/1-lean-launches.tsv"; : > "$L"
row "$L" 2026-08-25T10:00:00Z run-a 1 launch    "branch_key=1"
row "$L" 2026-08-25T10:00:10Z run-a 1 spawn     "n=1 role=BUILD model=sonnet"
row "$L" 2026-08-25T10:10:10Z run-a 1 spawn-end "n=1 role=BUILD rc=0"
row "$L" 2026-08-25T10:10:20Z run-a 1 spawn     "n=2 role=REVIEW model=opus"
row "$L" 2026-08-25T10:20:20Z run-a 1 spawn-end "n=2 role=REVIEW rc=0"
row "$L" 2026-08-25T10:20:30Z run-a 1 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '30s scheduler' <<<"$out" && grep -q '1 measurable' <<<"$out"; then
  pass "(a1) overhead is the run minus its payload sessions, not the run"
else fail "(a1) expected rc=0 and 30s of scheduler time, got rc=$rc: $out"; fi

# The payload's SIZE must not move the verdict — the same 30s of scheduler time inside sessions
# five times longer still passes. Without this, a threshold on total wall-clock would pass here
# and the metric would be measuring the ticket instead of the lane.
L2="$WORK/2-lean-launches.tsv"; : > "$L2"
row "$L2" 2026-08-25T10:00:00Z run-b 2 launch    "branch_key=2"
row "$L2" 2026-08-25T10:00:10Z run-b 2 spawn     "n=1 role=BUILD model=sonnet"
row "$L2" 2026-08-25T10:50:10Z run-b 2 spawn-end "n=1 role=BUILD rc=0"
row "$L2" 2026-08-25T10:50:20Z run-b 2 spawn     "n=2 role=REVIEW model=opus"
row "$L2" 2026-08-25T11:40:20Z run-b 2 spawn-end "n=2 role=REVIEW rc=0"
row "$L2" 2026-08-25T11:40:30Z run-b 2 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L2" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '30s scheduler' <<<"$out" && grep -q '1:40:30 total' <<<"$out"; then
  pass "(a2) a 1h40m run with the same 30s of scheduler time still passes — the metric is the lane, not the ticket"
else fail "(a2) a longer payload changed the verdict, rc=$rc: $out"; fi

# ---- (b) the ceiling ---------------------------------------------------------------------------
L3="$WORK/3-lean-launches.tsv"; : > "$L3"
row "$L3" 2026-08-25T10:00:00Z run-c 3 launch    "branch_key=3"
row "$L3" 2026-08-25T10:00:10Z run-c 3 spawn     "n=1 role=BUILD model=sonnet"
row "$L3" 2026-08-25T10:10:10Z run-c 3 spawn-end "n=1 role=BUILD rc=0"
row "$L3" 2026-08-25T10:15:10Z run-c 3 spawn     "n=2 role=REVIEW model=opus"
row "$L3" 2026-08-25T10:25:10Z run-c 3 spawn-end "n=2 role=REVIEW rc=0"
row "$L3" 2026-08-25T10:25:20Z run-c 3 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L3" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'OVER' <<<"$out" && grep -qE 'spent 0:05:20 outside its payload' <<<"$out"; then
  pass "(b1) five idle minutes between spawns reds the launch and names the interval"
else fail "(b1) expected rc=1 naming 0:05:20, got rc=$rc: $out"; fi

out="$(bash "$TOOL" --max-overhead-seconds 400 "$L3" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(b2) the ceiling is the knob it claims to be — the same ledger passes under a wider one"
else fail "(b2) --max-overhead-seconds did not move the verdict, rc=$rc: $out"; fi

# EXACTLY at the ceiling is inside it. A boundary that reds on equality would make the documented
# number mean one less than it says.
L4="$WORK/4-lean-launches.tsv"; : > "$L4"
row "$L4" 2026-08-25T10:00:00Z run-d 4 launch    "branch_key=4"
row "$L4" 2026-08-25T10:00:00Z run-d 4 spawn     "n=1 role=BUILD model=sonnet"
row "$L4" 2026-08-25T10:10:00Z run-d 4 spawn-end "n=1 role=BUILD rc=0"
row "$L4" 2026-08-25T10:11:00Z run-d 4 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L4" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '60s scheduler' <<<"$out"; then
  pass "(b3) an overhead exactly at the ceiling is within it"
else fail "(b3) the boundary excluded its own value, rc=$rc: $out"; fi

# ---- (c) what CANNOT be measured is not scored either way --------------------------------------
# The pre-existing corpus has no spawn-end rows. Scoring those as zero-overhead would manufacture a
# clean bill of health for every run that predates the instrument; reding them would make the guard
# useless on the day it landed.
L5="$WORK/5-lean-launches.tsv"; : > "$L5"
row "$L5" 2026-08-24T21:44:24Z legacy 5 launch   "branch_key=5"
row "$L5" 2026-08-24T21:44:26Z legacy 5 spawn    "n=1 role=BUILD model=sonnet"
row "$L5" 2026-08-24T21:54:38Z legacy 5 spawn    "n=2 role=REVIEW model=opus"
row "$L5" 2026-08-24T22:37:09Z legacy 5 terminal "approved rc=0"
out="$(bash "$TOOL" "$L5" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'not-measurable' <<<"$out" && grep -q '0 measurable' <<<"$out" \
   && grep -q '1 not measurable' <<<"$out"; then
  pass "(c1) a ledger without spawn-end rows is reported not-measurable — neither passed nor failed"
else fail "(c1) a legacy ledger was scored, rc=$rc: $out"; fi

# A spawn still open at the terminal is the KILLED scheduler, and its missing interval would land
# on the loop as overhead. Same treatment, for the same reason.
L6="$WORK/6-lean-launches.tsv"; : > "$L6"
row "$L6" 2026-08-25T10:00:00Z run-e 6 launch    "branch_key=6"
row "$L6" 2026-08-25T10:00:10Z run-e 6 spawn     "n=1 role=BUILD model=sonnet"
row "$L6" 2026-08-25T10:10:10Z run-e 6 spawn-end "n=1 role=BUILD rc=0"
row "$L6" 2026-08-25T10:10:20Z run-e 6 spawn     "n=2 role=REVIEW model=opus"
row "$L6" 2026-08-25T11:30:00Z run-e 6 terminal  "build-session-failed rc=1"
out="$(bash "$TOOL" "$L6" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'not-measurable (2 spawn start(s), 1 end(s))' <<<"$out"; then
  pass "(c2) a spawn still open at the terminal is not-measurable, not 80 minutes of scheduler overhead"
else fail "(c2) an unclosed spawn was scored as overhead, rc=$rc: $out"; fi

# A launch with no terminal is IN FLIGHT, not a datapoint — and must not be reported as a gap.
L7="$WORK/7-lean-launches.tsv"; : > "$L7"
row "$L7" 2026-08-25T10:00:00Z run-f 7 launch    "branch_key=7"
row "$L7" 2026-08-25T10:00:10Z run-f 7 spawn     "n=1 role=BUILD model=sonnet"
out="$(bash "$TOOL" "$L7" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'run-f' <<<"$out"; then
  pass "(c3) a launch still in flight is silently skipped, not reported as a finished one"
else fail "(c3) an in-flight launch appeared in the report, rc=$rc: $out"; fi

# ---- (d) fail closed on a ledger that does not parse -------------------------------------------
# The failure direction matters: a corrupt ledger read as "no launches exceeded" is a green build
# over a corpus nobody measured.
L8="$WORK/8-lean-launches.tsv"; : > "$L8"
row "$L8" 2026-08-25T10:00:00Z run-g 8 launch    "branch_key=8"
row "$L8" "yesterday-ish"      run-g 8 spawn     "n=1 role=BUILD model=sonnet"
row "$L8" 2026-08-25T10:20:00Z run-g 8 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L8" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && grep -q 'unreadable timestamp' <<<"$out" && ! grep -q '✓' <<<"$out"; then
  pass "(d1) an unreadable timestamp exits 3 and prints no verdict — a corrupt ledger is not a passing one"
else fail "(d1) expected rc=3 with no verdict, got rc=$rc: $out"; fi

L9="$WORK/9-lean-launches.tsv"; : > "$L9"
row "$L9" 2026-08-25T10:00:00Z run-h 9 launch    "branch_key=9"
row "$L9" 2026-08-25T10:10:00Z run-h 9 spawn     "n=1 role=BUILD model=sonnet"
row "$L9" 2026-08-25T10:05:00Z run-h 9 spawn-end "n=1 role=BUILD rc=0"
row "$L9" 2026-08-25T10:20:00Z run-h 9 terminal  "approved rc=0"
out="$(bash "$TOOL" "$L9" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && grep -q 'closes a spawn before it opened' <<<"$out"; then
  pass "(d2) a spawn that closes before it opens exits 3 rather than subtracting a negative payload"
else fail "(d2) expected rc=3 on backwards spawn edges, got rc=$rc: $out"; fi

out="$(bash "$TOOL" --max-overhead-seconds sixty "$L" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'non-negative integer' <<<"$out"; then
  pass "(d3) a non-numeric ceiling is a usage refusal, not a silently-zero threshold"
else fail "(d3) expected rc=2 on a non-numeric ceiling, got rc=$rc: $out"; fi

# ---- (e) the date arithmetic, which is written out because no portable library provides it ------
# `date -d` is GNU-only and `date -j -f` is BSD-only, and mktime() is gawk-only; the conversion is
# therefore hand-rolled, so it gets cases rather than trust. A run that crosses midnight, a month
# boundary, a LEAP DAY and a year boundary must all subtract correctly — an off-by-one in
# days_from_civil is invisible inside a single day and enormous across one.
i=0
for span in "2026-08-25T23:55:00Z 2026-08-26T00:05:00Z" \
            "2026-01-31T23:55:00Z 2026-02-01T00:05:00Z" \
            "2024-02-28T23:55:00Z 2024-02-29T00:05:00Z" \
            "2024-02-29T23:55:00Z 2024-03-01T00:05:00Z" \
            "2026-12-31T23:55:00Z 2027-01-01T00:05:00Z"; do
  i=$((i + 1))
  read -r span_from span_to <<<"$span"
  set -- "$span_from" "$span_to"
  LB="$WORK/1$i-lean-launches.tsv"; : > "$LB"
  row "$LB" "$1" "run-x$i" "1$i" launch    "branch_key=1$i"
  row "$LB" "$1" "run-x$i" "1$i" spawn     "n=1 role=BUILD model=sonnet"
  row "$LB" "$2" "run-x$i" "1$i" spawn-end "n=1 role=BUILD rc=0"
  row "$LB" "$2" "run-x$i" "1$i" terminal  "approved rc=0"
  out="$(bash "$TOOL" "$LB" 2>&1)"; rc=$?
  # The whole ten minutes is payload, so the scheduler's share is zero — and it can only be zero if
  # both stamps converted onto the same timeline across the boundary.
  if [ "$rc" -eq 0 ] && grep -q '0:10:00 total' <<<"$out" && grep -q '0s scheduler' <<<"$out"; then
    pass "(e$i) a run spanning $1 → $2 subtracts to ten minutes"
  else fail "(e$i) the boundary $1 → $2 did not subtract correctly, rc=$rc: $out"; fi
done

# ---- (f) directory mode, and an empty one ------------------------------------------------------
EMPTY="$WORK/empty"; mkdir -p "$EMPTY"
out="$(bash "$TOOL" --dir "$EMPTY" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'no launch ledgers found' <<<"$out"; then
  pass "(f1) a directory with no ledgers says so and exits 0 — nothing to measure is not a failure"
else fail "(f1) expected a clean 'nothing to measure', got rc=$rc: $out"; fi

DMIX="$WORK/mixed"; mkdir -p "$DMIX"
cp "$L" "$DMIX/1-lean-launches.tsv"; cp "$L3" "$DMIX/3-lean-launches.tsv"; cp "$L5" "$DMIX/5-lean-launches.tsv"
out="$(bash "$TOOL" --dir "$DMIX" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'exceeded the 60s' <<<"$out" && grep -q 'not-measurable' <<<"$out"; then
  pass "(f2) directory mode reads every ledger, and one bad launch beside a good and a legacy one still reds"
else fail "(f2) directory mode did not aggregate correctly, rc=$rc: $out"; fi

out="$(bash "$TOOL" --dir "$DMIX" --quiet 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && ! grep -q 'not-measurable' <<<"$out" && grep -q 'OVER' <<<"$out"; then
  pass "(f3) --quiet drops the passing and not-measurable rows and keeps the offender"
else fail "(f3) --quiet printed the wrong subset, rc=$rc: $out"; fi

out="$(bash "$TOOL" "$WORK/nope-lean-launches.tsv" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'cannot read ledger' <<<"$out"; then
  pass "(f4) a named ledger that does not exist is a usage refusal, not an empty pass"
else fail "(f4) expected rc=2 on a missing ledger, got rc=$rc: $out"; fi

# ---- (g) the two paths a caller reaches with NO arguments ---------------------------------------
# Both were mutation survivors on this file's first run — the operators flip `-n`/`-z` and `&&`/`||`
# and neither site had a case. Neither is exotica: `--help` is how the ceiling and the exit codes
# are discoverable, and the bare invocation is the one an operator actually types.
out="$(bash "$TOOL" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'overhead = ' <<<"$out" && grep -q -- '--max-overhead-seconds' <<<"$out" \
   && ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "(g1) --help prints the header — the metric and the knob — and stops before the code"
else fail "(g1) --help did not print the header, rc=$rc: $out"; fi

# THE DEFAULT ROOT. With no --dir and no files the state dir is derived from the repo the tool is
# standing in, and the fallback for "not a repo" must not contaminate the answer for "is a repo".
# Driven from a real checkout carrying a real ledger: a root that resolved wrong reports the
# directory missing instead of measuring the launch inside it.
GITREPO="$WORK/repo"; mkdir -p "$GITREPO/.claude/pipeline-state"
git -C "$GITREPO" init -q
GL="$GITREPO/.claude/pipeline-state/99-lean-launches.tsv"; : > "$GL"
row "$GL" 2026-08-25T10:00:00Z run-z 99 launch    "branch_key=99"
row "$GL" 2026-08-25T10:00:10Z run-z 99 spawn     "n=1 role=BUILD model=sonnet"
row "$GL" 2026-08-25T10:10:10Z run-z 99 spawn-end "n=1 role=BUILD rc=0"
row "$GL" 2026-08-25T10:10:20Z run-z 99 terminal  "approved rc=0"
out="$(cd "$GITREPO" && bash "$TOOL" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '1 measurable' <<<"$out" && grep -q '20s scheduler' <<<"$out"; then
  pass "(g2) with no arguments the state dir is derived from the enclosing repo, and its ledgers are measured"
else fail "(g2) the default root did not resolve to the repo's state dir, rc=$rc: $out"; fi

# ...and the fallback it is paired with: OUTSIDE a repo the same call degrades to a relative path
# and refuses on its absence, rather than measuring whatever corpus it happens to land on.
NOREPO="$WORK/norepo"; mkdir -p "$NOREPO"
out="$(cd "$NOREPO" && bash "$TOOL" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no such directory' <<<"$out"; then
  pass "(g3) outside a repo the default root falls back to a relative path and refuses on its absence"
else fail "(g3) expected rc=2 outside a repo, got rc=$rc: $out"; fi

echo "[lane-latency-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit "$FAILS"
