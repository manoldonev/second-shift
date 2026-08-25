#!/usr/bin/env bash
# lane-latency.sh — how much of a lean run's wall-clock the SCHEDULER is responsible for.
#
# WHY THIS EXISTS. "run-lean takes hours" is true and was, until this tool, unfalsifiable as a
# statement about the scheduler. A run's total is dominated by payload sessions — 10 to 50 minutes
# each, four of them on a two-round run — and nothing separated that from the loop's own cost, so
# the lane could only be defended with an anecdote. `docs/lane-latency.md` derives the answer by
# hand for two runs (2 seconds each); this derives it for every run that has a ledger, and REFUSES
# when it regresses. A claim nobody can check is a claim that rots.
#
# WHAT IT MEASURES, and why this metric rather than the obvious one. Total wall-clock is a property
# of the WORK — a big ticket takes longer per round under any drive-mode — so gating on it would
# red on tickets for being large and the guard would be ignored inside a month. Overhead is a
# property of the LANE:
#
#     overhead = (terminal − launch) − Σ(spawn-end − spawn)
#
# Everything outside a payload session: preflight, the staleness/PR/in-flight/verdict gate calls
# between phases, and the close-out. It is independent of how long the sessions took and of how big
# the ticket was, which is what makes a fixed threshold honest.
#
# IT NEEDS `spawn-end` ROWS, which the orchestrator only began writing alongside this tool. A
# launch without them is reported `not-measurable` and is NOT a failure: the pre-existing corpus
# cannot answer this question and pretending otherwise would either red every historical run or
# silently score them as zero-overhead. Only launches carrying both edges are gated.
#
# Usage:
#   lane-latency.sh [--dir <state-dir>] [--max-overhead-seconds <n>] [--quiet] [<ledger.tsv>...]
#
#     --dir                     directory to scan for '*-lean-launches.tsv' (default: the config's
#                               pipelineStateDir under the repo root, else .claude/pipeline-state)
#     --max-overhead-seconds    per-launch ceiling (default 60)
#     --quiet                   print only the verdict and any offending launches
#
# Exit: 0 = every measurable launch is within the ceiling · 1 = at least one exceeded it ·
#       2 = usage, or a ledger that could not be read · 3 = a ledger row that does not parse, or
#       whose timestamps run backwards (fail closed: an unparseable ledger is not a passing one).
set -uo pipefail

MAX_OVERHEAD=60
QUIET=0
DIR=""
FILES=()

die() { echo "[lane-latency] $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)                    DIR="${2:-}"; [ -n "$DIR" ] || die "--dir needs a directory"; shift 2 ;;
    --max-overhead-seconds)   MAX_OVERHEAD="${2:-}"; shift 2 ;;
    --quiet)                  QUIET=1; shift ;;
    -h|--help)                sed -n '2,37p' "$0"; exit 0 ;;
    -*)                       die "unknown option: $1" ;;
    *)                        FILES+=("$1"); shift ;;
  esac
done

case "$MAX_OVERHEAD" in
  ''|*[!0-9]*) die "--max-overhead-seconds needs a non-negative integer, got '$MAX_OVERHEAD'" ;;
esac

if [ "${#FILES[@]}" -eq 0 ]; then
  if [ -z "$DIR" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' ".")"
    DIR="$root/.claude/pipeline-state"
  fi
  [ -d "$DIR" ] || die "no such directory: $DIR"
  # No `ls | while` and no glob-in-array under bash 3.2 with nullglob unset: a directory with no
  # ledgers must be an empty list rather than a literal '*-lean-launches.tsv' path.
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<EOF
$(find "$DIR" -maxdepth 1 -name '*-lean-launches.tsv' -type f 2>/dev/null | sort)
EOF
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[lane-latency] no launch ledgers found${DIR:+ under $DIR} — nothing to measure."
  exit 0
fi

for f in "${FILES[@]}"; do
  [ -r "$f" ] || die "cannot read ledger: $f"
done

# The whole computation, in one awk so the ledger is read once and the epoch conversion is shared.
#
# NO `date(1)`, DELIBERATELY. Converting an ISO-8601 stamp with `date` needs `-j -f` on BSD and
# `-d` on GNU, and a script carrying both forms fails DIRTY on whichever host it guesses wrong —
# the failure is a wrong number, not an error. `mktime()` is not available either: this repo's
# macOS lanes run BWK awk, not gawk. So the civil-days conversion is written out; it is exact,
# integer-only, and identical on every host.
awk -v max="$MAX_OVERHEAD" -v quiet="$QUIET" '
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y -= 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function epoch(ts,   y, mo, d, h, mi, s) {
  if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return -1
  y  = substr(ts, 1, 4) + 0; mo = substr(ts, 6, 2) + 0; d = substr(ts, 9, 2) + 0
  h  = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; s = substr(ts, 18, 2) + 0
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) return -1
  return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
}
function hms(n,   sign) { sign = ""; if (n < 0) { sign = "-"; n = -n }
  return sprintf("%s%d:%02d:%02d", sign, int(n/3600), int((n%3600)/60), n%60) }

BEGIN { FS = "\t"; bad = 0; failed = 0; measured = 0; skipped = 0 }
{
  if (NF < 4) { printf "[lane-latency] %s:%d does not parse as a ledger row\n", FILENAME, FNR > "/dev/stderr"; bad = 1; next }
  ts = epoch($1); id = $2; ev = $4; detail = (NF >= 5 ? $5 : "")
  if (ts < 0) { printf "[lane-latency] %s:%d has an unreadable timestamp: %s\n", FILENAME, FNR, $1 > "/dev/stderr"; bad = 1; next }
  if (!(id in seen)) { seen[id] = 1; order[++n] = id; file[id] = FILENAME; issue[id] = $3 }
  if (ev == "launch")         { start[id] = ts }
  else if (ev == "terminal")  { end[id] = ts; verdict[id] = detail }
  else if (ev == "spawn")     { open_at[id] = ts; opened[id]++ }
  else if (ev == "spawn-end") {
    if (!(id in open_at)) { printf "[lane-latency] %s:%d closes a spawn that never opened\n", FILENAME, FNR > "/dev/stderr"; bad = 1; next }
    if (ts < open_at[id]) { printf "[lane-latency] %s:%d closes a spawn before it opened\n", FILENAME, FNR > "/dev/stderr"; bad = 1; next }
    payload[id] += ts - open_at[id]; closed[id]++; delete open_at[id]
  }
}
END {
  for (i = 1; i <= n; i++) {
    id = order[i]
    if (!(id in start) || !(id in end)) { continue }   # a launch still in flight is not a datapoint
    total = end[id] - start[id]
    if (total < 0) { printf "[lane-latency] %s: launch %s ends before it starts\n", file[id], id > "/dev/stderr"; bad = 1; continue }
    # NOT MEASURABLE, and reported rather than scored. Either the run predates spawn-end rows, or a
    # spawn was still open when the run ended — a killed scheduler, whose missing interval would
    # otherwise be attributed to the loop as overhead and red an innocent lane.
    if (closed[id] == 0 || opened[id] != closed[id]) {
      skipped++
      if (!quiet) printf "  %-24s #%-5s %8s  not-measurable (%d spawn start(s), %d end(s))\n", id, issue[id], hms(total), opened[id] + 0, closed[id] + 0
      continue
    }
    measured++
    over = total - payload[id]
    verdict_txt = (over > max ? "OVER" : "ok")
    if (over > max) {
      failed++
      printf "[lane-latency] %s: launch %s (#%s) spent %s outside its payload sessions — ceiling is %ds\n", file[id], id, issue[id], hms(over), max > "/dev/stderr"
    }
    if (!quiet || over > max)
      printf "  %-24s #%-5s %8s total  %8s payload  %6ds scheduler  %s\n", id, issue[id], hms(total), hms(payload[id]), over, verdict_txt
  }
  if (bad) { printf "[lane-latency] ✗ a ledger row could not be read — refusing to report a verdict over a partial corpus.\n" > "/dev/stderr"; exit 3 }
  if (failed) { printf "[lane-latency] ✗ %d of %d measurable launch(es) exceeded the %ds scheduler ceiling.\n", failed, measured, max > "/dev/stderr"; exit 1 }
  printf "[lane-latency] ✓ %d measurable launch(es) within the %ds scheduler ceiling; %d not measurable.\n", measured, max, skipped
  exit 0
}
' "${FILES[@]}"
