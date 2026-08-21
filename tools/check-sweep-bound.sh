#!/usr/bin/env bash
# check-sweep-bound.sh — the missing-row counterpart to tools/selftest-slow-suites.tsv's
# stale-row error (#629).
#
# WHY THIS EXISTS. The table keeps lean-gate.sh milestone 3's local sweep inside the harness's
# ~120s reap by deferring every suite at or above its declared threshold. Membership is a
# MEASUREMENT TAKEN ONCE, and the rule that keeps it true — re-measure when you change what a
# listed suite does — was a sentence in that file's own header with nothing behind it. A new or
# grown suite that stays untabled walks the un-deferred sum back toward the reap; past it,
# milestone 3 is not slow but UNPASSABLE, because a reaped call loses its work and five of those
# hard-stop the run. The table already reds when a row names no discovered suite. This reds in
# the other direction.
#
# MEASURING AND JUDGING ARE SPLIT (D-4). tools/run-selftests.sh emits each suite's elapsed
# seconds on its existing frame line and judges nothing; CLAUDE.md pins that runner's exit-code
# contract, and folding "a suite got slow" into it would conflate two failure classes under one
# status. This file is the only thing here that reds.
#
# THE SERIAL SUM, NOT AN OBSERVED WALL TIME (D-5). The lane that runs this check sweeps with the
# table opted OUT, so the un-deferred subset's own wall time is never observed there — only
# per-suite times are. A sum is also immune to lane-concurrency skew, which the same sweep
# exhibits when parallelism is scaled to live lane count.
#
# NIGHTLY ONLY (D-1). PR runners are noisier and a single slow-end sample would red an honest PR.
# The one execution surface is .github/workflows/nightly-guards.yml's ubuntu wholesale lane, and
# its selftest asserts there is no second one.
#
# ONE SUITE OVER THRESHOLD IS A WARNING, NEVER A RED (D-2). A single wall-clock sample of one
# suite is a range rather than a point — this repo has 319/438/584s recorded for one unchanged
# tree — so a per-suite overage names itself and exits 0. The AGGREGATE is the quantity that
# actually breaks milestone 3, and it is the only thing that reds.
#
# A CHECKER THAT CANNOT SEE ITS INPUT MUST NOT REPORT A PASS (D-6). An absent log, a frame line
# whose elapsed field does not parse, a timing naming a suite discovery did not produce, and an
# un-deferred suite with no timing at all are each exit 2. "Could not look" never counts as
# "looked and found nothing"; scripts/check-fail-open-shapes.sh refuses that shape class
# repo-wide and this file is written to its posture.
#
# Usage:
#   check-sweep-bound.sh --log <sweep-output-file> [--root <dir>]
#                        [--baseline <file>] [--table <file>]
#
#   --log        the captured stdout+stderr of a `run-selftests.sh --full` sweep. Required.
#   --root       tree the sweep was taken over; defaults to the repo above this script.
#   --baseline   defaults to <root>/tools/selftest-sweep-baseline.tsv
#   --table      defaults to <root>/tools/selftest-slow-suites.tsv
#
# EXIT: 0 within allowance, with or without per-suite warnings. 1 aggregate breach. 2 usage error
# or unreadable input.
set -uo pipefail

TAB=$'\t'
LOG=""
ROOT=""
BASELINE=""
TABLE=""

die() { echo "[check-sweep-bound] $1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)      [[ $# -ge 2 ]] || die "--log requires a file"; LOG="$2"; shift 2 ;;
    --root)     [[ $# -ge 2 ]] || die "--root requires a directory"; ROOT="$2"; shift 2 ;;
    --baseline) [[ $# -ge 2 ]] || die "--baseline requires a file"; BASELINE="$2"; shift 2 ;;
    --table)    [[ $# -ge 2 ]] || die "--table requires a file"; TABLE="$2"; shift 2 ;;
    # Range-free, the check-fail-open-shapes.sh idiom: an edit to the prose above cannot start
    # leaking `set -uo pipefail` into --help.
    -h|--help)  sed -n '2,/^# EXIT: 0 within allowance/p' "$0"; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$HERE")}"
[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
BASELINE="${BASELINE:-$ROOT/tools/selftest-sweep-baseline.tsv}"
TABLE="${TABLE:-$ROOT/tools/selftest-slow-suites.tsv}"

[[ -n "$LOG" ]] || die "--log is required — there is no arm on which this exits 0 without one"
[[ -f "$LOG" && -r "$LOG" ]] || die "the timing input is absent or unreadable: $LOG"

# ---- discovery -------------------------------------------------------------------------
# The SAME glob run-selftests.sh discovers by. It is re-derived rather than read out of the log
# because AC-4's third arm — a timing naming a suite discovery did not produce — cannot be
# decided from the log alone: the log is exactly the thing under suspicion.
ALL="$(cd "$ROOT" && find . -name '*-selftest.sh' -type f | sed 's|^\./||' | LC_ALL=C sort)"
[[ -n "$ALL" ]] || die "discovered 0 suites under $ROOT — nothing to bound"

# ---- the table: deferred set and threshold ----------------------------------------------
# THE THRESHOLD HAS ONE HOME, and it is the table that applies it. A `# threshold-seconds`
# directive rather than a row, so run-selftests.sh's existing comment arm skips it and the
# membership rule stays a single declared number instead of a copy in this file drifting away
# from the prose in that one.
[[ -f "$TABLE" ]] || die "the slow-suite table is absent: $TABLE — the un-deferred set is undefined without it"
THRESHOLD="$(sed -n "s/^# threshold-seconds${TAB}\\([0-9][0-9]*\\)[[:space:]]*$/\\1/p" "$TABLE" | head -1)"
[[ -n "$THRESHOLD" ]] \
  || die "$TABLE declares no '# threshold-seconds<TAB><n>' directive — the membership rule is unreadable"

DEFERRED=""
while IFS="$TAB" read -r t_suite t_secs t_rest; do
  case "${t_suite:-}" in ''|'#'*) continue ;; esac
  [[ -n "$t_secs" && -n "$t_rest" ]] || die "malformed row in $TABLE: '$t_suite'"
  DEFERRED="$DEFERRED${t_suite#./}"$'\n'
done < "$TABLE"

# ---- the committed baseline --------------------------------------------------------------
[[ -f "$BASELINE" ]] || die "the committed baseline is absent: $BASELINE"
base_value() { sed -n "s/^$1${TAB}\\([0-9][0-9]*\\)[[:space:]]*$/\\1/p" "$BASELINE" | head -1; }
BASE_SECS="$(base_value baseline-seconds)"
ALLOWANCE="$(base_value allowance-percent)"
[[ -n "$BASE_SECS" ]] || die "$BASELINE declares no 'baseline-seconds' — it must be a whole number"
[[ -n "$ALLOWANCE" ]] || die "$BASELINE declares no 'allowance-percent' — it must be a whole number"
[[ "$BASE_SECS" -ge 1 ]] || die "$BASELINE declares baseline-seconds=$BASE_SECS — a zero baseline bounds nothing"

# ---- the log: TOP-LEVEL frames only --------------------------------------------------------
# run-selftests-selftest.sh nests runners over throwaway fixture trees, so a real sweep's log
# carries `::group::` lines naming suites — p1-selftest.sh, rowed-selftest.sh — that exist in no
# repo. They arrive INSIDE the framing of the suite that produced them, so a depth counter
# separates them from the parent's own frames exactly. Reading every matching line instead would
# make every honest nightly red on AC-4's third arm.
#
# Depth is walked strictly: a stray `::endgroup::` or an unbalanced replay is unparseable input,
# not something to recover from and score.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-sweep-bound.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

# THE MARKER ROW IS THE ONLY SIGNAL, and awk's exit status is deliberately not a second one.
# Carrying both made the status redundant: dropping it changed no outcome, because the row still
# reached the reader below — an unkillable guard, and the mutation sweep said so. One mechanism,
# read in one place.
awk '
  /^::group::/    { if (depth == 0) printf "%s\t%s\t%s\n", $1, $2, $3; depth++; next }
  /^::endgroup::/ { depth--; if (depth < 0) { print "!\tnegative-depth\t-"; exit } next }
  END             { if (depth != 0) print "!\tunbalanced-framing\t-" }
' "$LOG" > "$TMP/frames"

: > "$TMP/timed"
: > "$TMP/undeferred"
while IFS="$TAB" read -r f_status f_elapsed f_suite; do
  [[ -n "$f_status" ]] || continue
  case "$f_status" in
    '::group::pass'|'::group::FAIL'|'::group::cached') : ;;
    '!') die "the timing input is not a replay this can walk: $f_elapsed" ;;
    *) die "unrecognized frame line status '$f_status' — the emitter's shape moved and this parse is stale" ;;
  esac
  [[ -n "$f_suite" ]] || die "a frame line names no suite: '$f_status $f_elapsed'"
  grep -qxF "$f_suite" <<<"$ALL" \
    || die "the log times '$f_suite', which discovery under $ROOT did not produce — the log and the tree disagree"
  grep -qxF "$f_suite" "$TMP/timed" \
    && die "the log frames '$f_suite' twice — two sweeps in one file cannot be summed"
  printf '%s\n' "$f_suite" >> "$TMP/timed"

  # Deferred suites are measured by this lane too (it sweeps --full) and are deliberately NOT
  # summed: the bound is the set milestone 3 actually runs.
  grep -qxF "$f_suite" <<<"$DEFERRED" && continue

  [[ "$f_elapsed" =~ ^[0-9]+s$ ]] \
    || die "'$f_suite' carries an unparseable elapsed field '$f_elapsed' — a suite that was not measured is not a free one"
  printf '%s\t%s\n' "${f_elapsed%s}" "$f_suite" >> "$TMP/undeferred"
done < "$TMP/frames"

# ---- completeness ------------------------------------------------------------------------
# Every un-deferred discovered suite must appear. A sum taken over an arbitrary subset of the
# set it claims to bound is the faster-green misreading this whole check exists to refuse.
MISSING=""
while IFS= read -r d_suite; do
  [[ -n "$d_suite" ]] || continue
  grep -qxF "$d_suite" <<<"$DEFERRED" && continue
  grep -qxF "$d_suite" "$TMP/timed" && continue
  MISSING="$MISSING  $d_suite"$'\n'
done <<EOF
$ALL
EOF
if [[ -n "$MISSING" ]]; then
  echo "[check-sweep-bound] the log carries no timing for these un-deferred suites:" >&2
  printf '%s' "$MISSING" >&2
  die "an incomplete sum is not a pass — sweep with --full and capture the whole replay"
fi

SUM=0
while IFS="$TAB" read -r u_secs _; do
  [[ -n "$u_secs" ]] || continue
  SUM=$((SUM + u_secs))
done < "$TMP/undeferred"
COUNT="$(grep -c . "$TMP/undeferred")"
# A table that deferred everything would sum to zero and pass. run-selftests.sh already refuses
# to call a sweep that runs nothing green; the bound on that sweep refuses the same shape.
[[ "$COUNT" -ge 1 ]] || die "the log times no un-deferred suite — a sum over nothing bounds nothing"

# ---- the verdict ---------------------------------------------------------------------------
# Integer only — stock bash 3.2 is one of this repo's CI lanes and there is no bc on it. The
# comparison is cross-multiplied rather than taken against a rounded limit, so a drift sitting
# exactly on the allowance is inside it in both directions.
DRIFT=$(( (SUM - BASE_SECS) * 100 / BASE_SECS ))
LIMIT=$(( BASE_SECS * (100 + ALLOWANCE) / 100 ))

WARNED=0
while IFS="$TAB" read -r w_secs w_suite; do
  [[ -n "$w_secs" ]] || continue
  [[ "$w_secs" -ge "$THRESHOLD" ]] || continue
  WARNED=$((WARNED + 1))
  echo "[check-sweep-bound] warning: $w_suite measured ${w_secs}s, at or above the ${THRESHOLD}s table threshold."
  echo "[check-sweep-bound]   Re-measure it alone; if it holds, give it a $TABLE row. One sample is a range, so this does not red on its own."
done < "$TMP/undeferred"

# THE LARGEST CONTRIBUTORS, and the message says contributors rather than growers on purpose:
# the baseline record is the AGGREGATE (D-3), so no per-suite history exists to rank a delta
# against. What the reader has to act on is which un-deferred suites carry the sum, which this
# does name.
top_contributors() { LC_ALL=C sort -rn "$TMP/undeferred" | head -5 | sed "s/^/[check-sweep-bound]   /"; }

if [[ $((SUM * 100)) -gt $((BASE_SECS * (100 + ALLOWANCE))) ]]; then
  echo "[check-sweep-bound] ✗ the un-deferred serial sum is ${SUM}s over $COUNT suite(s); the committed baseline is ${BASE_SECS}s and the allowance is ${ALLOWANCE}% (limit ${LIMIT}s). Drift: ${DRIFT}%." >&2
  echo "[check-sweep-bound] largest un-deferred contributors in this run (seconds, suite):" >&2
  top_contributors >&2
  echo "[check-sweep-bound] Two remedies, and the diff should say which was chosen:" >&2
  echo "[check-sweep-bound]   1. TABLE THE SUITE — re-measure the grower alone and add a $TABLE row. It still runs in CI; a row costs signal latency, never soundness." >&2
  echo "[check-sweep-bound]   2. RE-BASELINE — update $BASELINE in a reviewed commit, stating what was measured, when, and on which lane. Never an automatic rewrite." >&2
  exit 1
fi

echo "[check-sweep-bound] ✓ un-deferred serial sum ${SUM}s over $COUNT suite(s) — baseline ${BASE_SECS}s, allowance ${ALLOWANCE}% (limit ${LIMIT}s), drift ${DRIFT}%, $WARNED per-suite warning(s)."
