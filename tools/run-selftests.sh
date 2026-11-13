#!/usr/bin/env bash
# run-selftests.sh — the repo's ONE selftest sweep runner. Discovers every `*-selftest.sh`,
# runs them concurrently, and replays each suite's output as one contiguous framed block.
#
# WHY THIS EXISTS. CLAUDE.md's Verification section mandates `xargs -0 -P 4` and records it as
# the difference between a 13:12 and a 5:22 sweep. Both CI selftest jobs were running the exact
# serial form the repo tells contributors not to run — 17:50 on macos, 12:51 on ubuntu, of which
# 709s was the one selftest step. This runner replaces both inline `while read` loops.
#
# WHY A SCRIPT AND NOT A `-P` FLAG. At `-P 4` the suites' raw stdout interleaves and the job log
# stops being readable — you cannot tell which suite printed which FAIL. Per-suite capture and
# ordered replay under `::group::`/`::endgroup::` is the whole reason this is a file. The
# every-checked-in-script-is-covered rule then binds it to tools/run-selftests-selftest.sh,
# which is the second reason (CLAUDE.md, Verification).
#
# PARALLEL SAFETY is asserted by CLAUDE.md: the suites are independent, each allocating its own
# `mktemp` state dir. The one suite that carried a literal `/tmp` path passed `/tmp/x` only as
# an opaque `--worktree` argument and never wrote it; that suite was deleted
# with the staged lane in #348, so no suite in the tree carries one today.
#
# DISCOVERY IS `*-selftest.sh` ONLY, deliberately. The two `*-selftest.mjs` files are executed
# by plugins/review-toolkit/workflows/workflows-mjs-selftest.sh, which is itself in this
# glob. Widening discovery to `.mjs` would double-run them.
#
# DISPATCH IDIOM is lifted from tools/install-topology-selftest.sh: `xargs -P` over zero-padded
# indices into a worklist file, each worker writing `<idx>.rc` and `<idx>.log`, the parent
# scoring from those in worklist order. bash 3.2 compatible (no `wait -n`) — macos-latest ships
# /bin/bash 3.2 and that is one of this repo's two CI lanes. A worker that dies WITHOUT writing
# an `.rc` scores as a named infra failure, never as a green suite.
#
# USAGE
#   run-selftests.sh [--exclude <repo-relative-path>]... [--jobs <n>] [--root <dir>]
#                    [--full] [--shard <i>/<n>]
#
#   --exclude     repeatable. Lifts a suite out of THIS sweep while leaving it discovered, so it
#                 can run in its own CI job. An exclusion matching no discovered suite is a HARD
#                 ERROR — a stale workflow argument fails loudly, not silently.
#   --full        do NOT apply tools/selftest-suite-timings.tsv. The sweep of record passes this;
#                 see #566 below for why the table is on by default and the opt-out is explicit.
#   --jobs        concurrency; defaults to $SELFTEST_JOBS, itself defaulting to 4 (the recipe).
#   --root        tree to discover under; defaults to the repo root above this script.
#   --shard       run only shard <i> of <n>: the i-th, (i+n)-th, ... suite of the sorted,
#                 post-exclusion list. CI runs every shard of a lane as a matrix, so the n shards
#                 of one lane together are exactly the unsharded sweep, each suite in one shard.
#
# EXIT: 0 iff every run suite passed. Non-zero names every failing suite. 2 for a usage error,
# a stale exclusion, or a discovered/run count disagreement.
# 3 (#527) when there were failures and EVERY one of them is the no-verdict infrastructure class —
# the workers died rather than the suites failing, so the sweep learned nothing about the tree.
# Mixed infra-and-real is 1, because a red branch is still a red branch.
#
# NOT `set -e`: this harness runs other people's suites and SCORES their exit codes.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # HERE is already absolute and resolved, so its dirname is too
JOBS="${SELFTEST_JOBS:-4}"
EXCLUDES=""   # newline-separated; bash 3.2 has no array-of-args ergonomics worth the noise here
FULL=0        # 1 = do not apply the slow-suite table (#566)
SHARD_I=1; SHARD_N=1   # --shard <i>/<n>; 1/1 is the whole sweep
DEFERRED=""   # newline-separated "<suite><TAB><reason>", for the announcement below
TAB=$'\t'

die() { echo "[run-selftests] $1" >&2; exit 2; }

# ---- worker mode ---------------------------------------------------------------------
# One suite per fresh invocation. Writes <idx>.rc and <idx>.log; the parent scores from those,
# so a worker that dies without writing an .rc is visible as infra rather than as a green suite.
#
# Keyed on an ARGV SENTINEL, never on an environment variable, and that is load-bearing rather
# than style. An env flag is inherited by everything below the dispatch — including the suites
# themselves — so a suite that invokes this runner would take this branch, read `--root` as its
# index, and collapse. That is not hypothetical: an earlier revision keyed on
# `RUN_SELFTESTS_WORKER`, and tools/run-selftests-selftest.sh (which nests a runner inside a
# suite) passed standalone and failed the moment the repo sweep ran it. argv cannot leak
# downward the way the environment does. Same `--run-one` idiom as install-topology-selftest.sh.
#
# It must also come BEFORE the option parser, which would otherwise reject the worker's
# positional arguments as unknown options — into the dispatch call's discarded stdout, leaving
# every suite scored 125 with no visible cause.
if [[ "${1:-}" == "--run-one" ]]; then
  W_IDX="${2:?--run-one: index}"; W_LIST="${3:?--run-one: worklist}"
  W_ROOT="${4:?--run-one: root}"; W_OUT="${5:?--run-one: results dir}"
  W_SUITE="$(awk -F'\t' -v i="$W_IDX" '$1 == i { print $2 }' "$W_LIST")"
  [[ -n "$W_SUITE" ]] || exit 0
  # The parent's test-only seams are stripped for the same reason: a nested runner must not
  # inherit an instruction to truncate its own worklist or to suppress its own verdicts.
  #
  # THE CLOCK BRACKETS THE SUITE AND NOTHING ELSE (#629). Whole seconds from `date +%s`, which is
  # the one form both lanes agree on — a sub-second flag is GNU-only, and a dual form fails dirty
  # on macos. A suite that finishes inside one second is charged ONE, never zero: the consumer is
  # a SUM over ~50 suites, and rounding the small ones away would let the set grow by half a
  # minute without the total moving. Over-stating is the safe direction, and the baseline is taken
  # through this same emitter, so the two are commensurable.
  W_T0="$(date +%s)"
  ( cd "$W_ROOT" && env -u RUN_SELFTESTS_DROP_LAST -u RUN_SELFTESTS_DROP_RC bash "$W_SUITE" ) \
    > "$W_OUT/$W_IDX.log" 2>&1
  W_RC=$?   # captured BEFORE anything else runs — a later test would overwrite $?
  W_SECS=$(( $(date +%s) - W_T0 ))
  [[ "$W_SECS" -ge 1 ]] || W_SECS=1
  # Rejection-assertion seam #2 (see RUN_SELFTESTS_DROP_LAST below): exit WITHOUT writing the
  # verdict file, reproducing a worker that died mid-suite. That path is a documented guarantee
  # — a suite with no verdict is named as infra, never scored as a pass — and it is unreachable
  # from a fixture otherwise, since a suite cannot reach its own worker's results directory.
  # Never set in CI or by an operator.
  [[ "${RUN_SELFTESTS_DROP_RC:-}" == "1" ]] && exit 0
  # Written BEFORE the verdict, so the parent never sees an rc with no time beside it. The
  # reverse order would give the replay a scored suite whose frame line has nothing to print.
  echo "$W_SECS" > "$W_OUT/$W_IDX.secs"
  echo "$W_RC" > "$W_OUT/$W_IDX.rc"
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude) [[ $# -ge 2 ]] || die "--exclude requires a path"
               EXCLUDES="$EXCLUDES$2"$'\n'; shift 2 ;;
    --jobs)    [[ $# -ge 2 ]] || die "--jobs requires a count"
               JOBS="$2"; shift 2 ;;
    --root)    [[ $# -ge 2 ]] || die "--root requires a directory"
               ROOT="$2"; shift 2 ;;
    --full)    FULL=1; shift ;;
    --shard)   [[ $# -ge 2 ]] || die "--shard requires <i>/<n>"
               [[ "$2" =~ ^([0-9]+)/([0-9]+)$ ]] || die "--shard must be <i>/<n>, got: $2"
               SHARD_I="${BASH_REMATCH[1]}"; SHARD_N="${BASH_REMATCH[2]}"; shift 2 ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ "$JOBS" =~ ^[0-9]+$ ]] && [[ "$JOBS" -ge 1 ]] || die "--jobs/SELFTEST_JOBS must be a positive integer, got: $JOBS"
[[ "$SHARD_N" -ge 1 && "$SHARD_I" -ge 1 && "$SHARD_I" -le "$SHARD_N" ]] || die "--shard needs 1 <= i <= n, got: $SHARD_I/$SHARD_N"
[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

# ---- the slow-suite table (#566) -------------------------------------------------------
# ON BY DEFAULT, and `--full` is the opt-out. The inverse — an opt-in `--quick` — was rejected
# at intake for a reason that is structural rather than stylistic: a caller that wants the
# bound runs a `test` command out of a consumer's gitignored config, so an opt-in flag would
# have to be added by hand to an untracked file nothing can read, and "did the bound actually
# apply?" would be unanswerable in review and unverifiable in CI. Default-on inverts that: the
# sweeps of record (both CI selftest jobs, the nightly wholesale leg, and the CLAUDE.md
# contributor recipe) pass `--full` in COMMITTED files, where a missing opt-out is visible in
# the diff.
#
# WHY A TABLE AND NOT MORE `--exclude` FLAGS. The membership is a cost record — each row
# carries the measurement that justifies it — and it has to be reviewable. Flags in the
# gitignored config are neither.
#
# RESOLVED UNDER $ROOT, never under this script's repo: --root points at the tree being swept, and a
# sweep of another tree must read that tree's table or it is applying this one's membership to
# suites it has never measured. Absent, every suite is treated as fast.
#
# THE THRESHOLD HAS ONE HOME (#641, carried over from #629): the table's own
# `# threshold-seconds` directive. A row below it is filtered out here at read time.
SLOW_SUITES="$ROOT/tools/selftest-suite-timings.tsv"
if [[ "$FULL" -eq 0 && -f "$SLOW_SUITES" ]]; then
  SLOW_THRESHOLD_S="$(sed -n "s/^# threshold-seconds${TAB}\\([0-9][0-9]*\\)[[:space:]]*\$/\\1/p" "$SLOW_SUITES" | head -1)"
  [[ -n "$SLOW_THRESHOLD_S" ]] \
    || die "$SLOW_SUITES declares no '# threshold-seconds<TAB><n>' directive — the membership rule is unreadable"
  while IFS="$TAB" read -r sl_suite sl_secs sl_date; do
    case "${sl_suite:-}" in ''|'#'*) continue ;; esac
    [[ -n "$sl_secs" && -n "$sl_date" ]] \
      || die "malformed row in $SLOW_SUITES: '$sl_suite' — expected <suite>\\t<seconds>\\t<measured_at>"
    [[ "$sl_secs" =~ ^[0-9]+$ ]] \
      || die "malformed row in $SLOW_SUITES: '$sl_suite' seconds must be a whole number, got '$sl_secs'"
    [[ "$sl_secs" -ge "$SLOW_THRESHOLD_S" ]] || continue
    DEFERRED="$DEFERRED$sl_suite$TAB${sl_secs}s (measured $sl_date)"$'\n'
  done < "$SLOW_SUITES"
fi

# ---- discovery -----------------------------------------------------------------------
# Sorted so the worklist — and therefore the replayed log — is deterministic across lanes.
ALL="$(cd "$ROOT" && find . -name '*-selftest.sh' -type f | sed 's|^\./||' | LC_ALL=C sort)"
DISCOVERED=0
[[ -n "$ALL" ]] && DISCOVERED="$(printf '%s\n' "$ALL" | wc -l | tr -d ' ')"
[[ "$DISCOVERED" -gt 0 ]] || die "discovered 0 suites under $ROOT — a sweep that runs nothing is never green"

# ---- exclusions ----------------------------------------------------------------------
# Each --exclude must name a discovered suite EXACTLY. A path that matches nothing is a stale
# workflow argument: it would silently widen the sweep the day the suite is renamed, and the
# renamed suite would then run twice (here and in its own job) with nobody noticing.
#
# THE TABLE'S ROWS ARE EXCLUSIONS TOO, and they carry the SAME stale-row posture: a row naming
# no discovered suite is a hard error, so a renamed suite cannot silently start running twice.
# The message names which source the bad path came from — a stale table row and a stale
# workflow argument have different remedies.
#
# DEDUPED, and that is a correctness requirement rather than tidiness. EXCLUDED feeds
# EXPECTED = DISCOVERED - EXCLUDED, which the run/discovered invariant is checked against, so
# counting one suite twice would under-state EXPECTED and red an honest sweep. It is the normal
# case, not an edge one: a sweep without --full that passes the usual
# `--exclude tools/install-topology-selftest.sh` names a suite that is also a table row.
EXCLUDED=0
SEEN=""
while IFS= read -r ex_line; do
  ex="${ex_line%%"$TAB"*}"
  [[ -n "$ex" ]] || continue
  ex="${ex#./}"
  ex_src="--exclude '$ex' matches no discovered suite under $ROOT — stale exclusion"
  case "$ex_line" in
    *"$TAB"*) ex_src="$SLOW_SUITES row '$ex' matches no discovered suite under $ROOT — stale table row; drop it or fix the path" ;;
  esac
  grep -qxF "$ex" <<<"$ALL" || die "$ex_src"
  grep -qxF "$ex" <<<"$SEEN" && continue
  SEEN="$SEEN$ex"$'\n'
  EXCLUDED=$((EXCLUDED + 1))
done <<EOF
$EXCLUDES
$DEFERRED
EOF
# THE DEDUPED UNION BECOMES THE CANONICAL LIST, and the dispatch filter below reads only this.
# Keeping the table in a second variable and filtering on $EXCLUDES alone was the first shape of
# this and it was wrong in the one direction a green run hides: EXCLUDED counted the table rows,
# so EXPECTED dropped, but the worklist still carried them — the suites ran, the run/discovered
# invariant caught the disagreement, and the sweep died on an arithmetic error rather than on
# anything about the tree. One list, counted and filtered from the same bytes.
EXCLUDES="$SEEN"

# ---- the deferred-to-CI listing (#566 AC-4) --------------------------------------------
# NAMED, one line per suite, never a count. An operator reading a green sweep has to be able to
# tell which suites that green does NOT cover, and a number cannot answer it.
#
# A DEFERRAL IS NOT A FAILURE. It is announced on stdout beside the ordinary sweep output and
# changes no exit code — the excluded set is computed BEFORE dispatch, so the discovered/ran
# invariant holds by construction rather than being fought.
if [[ -n "$DEFERRED" ]]; then
  echo "[run-selftests] slow-suite table applied ($SLOW_SUITES) — deferred to CI, which sweeps them with --full:"
  while IFS="$TAB" read -r df_suite df_note; do
    [[ -n "$df_suite" ]] || continue
    echo "[run-selftests]   deferred: $df_suite ($df_note)"
  done <<EOF
$DEFERRED
EOF
fi

EXPECTED=$((DISCOVERED - EXCLUDED))
[[ "$EXPECTED" -gt 0 ]] || die "every discovered suite is excluded — a sweep that runs nothing is never green"
# THE SHARD'S SHARE IS DERIVED BY ARITHMETIC, not by counting the filter below, so the count
# reconciliation after the run still compares two independent derivations: positions i, i+n, ...
# of EXPECTED.
SWEEP_TOTAL="$EXPECTED"
if [[ "$SHARD_N" -gt 1 ]]; then
  [[ "$SHARD_I" -le "$EXPECTED" ]] || die "shard $SHARD_I/$SHARD_N has no suite (only $EXPECTED to run) — a sweep that runs nothing is never green"
  EXPECTED=$(( (EXPECTED - SHARD_I) / SHARD_N + 1 ))
fi

BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$BASE"' EXIT
RESULTS="$BASE/results"
mkdir -p "$RESULTS" || die "cannot create $RESULTS"

# The filter below and the DISCOVERED/EXCLUDED arithmetic above are two independent derivations
# of the same set. They are reconciled after the run (see "count reconciliation"), because a
# sweep that quietly runs fewer suites than it discovered reads as a FASTER GREEN — the single
# failure mode this work is most exposed to.
: > "$BASE/worklist"
n=0
pos=0
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  if [[ -n "$EXCLUDES" ]] && grep -qxF "${suite#./}" <<<"$EXCLUDES"; then
    continue
  fi
  pos=$((pos + 1))
  [[ $(( (pos - 1) % SHARD_N )) -eq $((SHARD_I - 1)) ]] || continue
  n=$((n + 1))
  printf '%s\t%s\n' "$(printf '%04d' "$n")" "$suite" >> "$BASE/worklist"
done <<EOF
$ALL
EOF

# Rejection-assertion seam. Drops the last worklist entry AFTER the counts are taken, so
# run-selftests-selftest.sh can prove the reconciliation below actually reds rather than
# asserting it in prose. Same posture as ci.yml's issue-forms step, which fails if the
# validator ACCEPTS a checked-in bad fixture. Never set in CI or by an operator.
if [[ "${RUN_SELFTESTS_DROP_LAST:-}" == "1" ]]; then
  sed '$d' "$BASE/worklist" > "$BASE/worklist.dropped" && mv "$BASE/worklist.dropped" "$BASE/worklist"
fi

if [[ "$SHARD_N" -gt 1 ]]; then
  echo "[run-selftests] $DISCOVERED discovered, $EXCLUDED excluded, $SWEEP_TOTAL to run, shard $SHARD_I/$SHARD_N runs $EXPECTED of them, jobs=$JOBS"
else
  echo "[run-selftests] $DISCOVERED discovered, $EXCLUDED excluded, $EXPECTED to run, jobs=$JOBS"
fi

# ---- dispatch ------------------------------------------------------------------------
cut -f1 "$BASE/worklist" > "$BASE/dispatch"
# shellcheck disable=SC2016  # the placeholders are for the inner sh -c, deliberately unexpanded
xargs -P "$JOBS" -n1 -I{} \
  sh -c 'bash "$0" --run-one "$1" "$2" "$3" "$4"' \
  "$HERE/$(basename "${BASH_SOURCE[0]}")" "{}" "$BASE/worklist" "$ROOT" "$RESULTS" \
  < "$BASE/dispatch" >/dev/null

# ---- ordered replay ------------------------------------------------------------------
# Worklist order, not completion order: the log reads the same at -P 4 as it does at -P 1, which
# is what makes AC-4's same-verdict claim inspectable rather than merely asserted. The
# ::group:: framing is emitted unconditionally — GitHub folds it, a local run just sees a
# labelled block, and a selftest can assert contiguity without faking $GITHUB_ACTIONS.
RAN=0
FAILED=""
# #527 AC-1. The infra tally beside the failure list. The per-suite class already exists below
# (`rc=125`, the no-verdict-written case) and is already PRINTED as infra — only the parent
# collapsed it, so a caller could not tell a sweep whose workers were killed from a sweep whose
# suites are red. Counted here rather than re-derived from $FAILED at the exit: parsing "(rc=125)"
# back out of a formatted list would be a second reader of a string this file only writes.
INFRA=0
while IFS="$TAB" read -r idx suite; do
  [[ -n "$idx" ]] || continue
  RAN=$((RAN + 1))

  if [[ -f "$RESULTS/$idx.rc" ]]; then
    rc="$(cat "$RESULTS/$idx.rc")"
  else
    # A worker that produced no verdict is infra, not a suite result. Never silently green.
    rc=125
  fi

  # ELAPSED SITS BETWEEN THE STATUS AND THE SUITE (#629), not after it. The suite path stays the
  # LAST whitespace-separated token of a pass frame, which is what run-selftests-selftest's
  # contiguity walk reads it as; appending the time instead would have made `(3s)` the suite name.
  # A worker that wrote no verdict wrote no time either, so `?s` and rc=125 arrive together.
  if [[ -f "$RESULTS/$idx.secs" ]]; then
    secs="$(cat "$RESULTS/$idx.secs")s"
  else
    secs="?s"
  fi

  if [[ "$rc" -eq 0 ]]; then
    echo "::group::pass  $secs  $suite"
  else
    echo "::group::FAIL  $secs  $suite (rc=$rc)"
  fi
  [[ -f "$RESULTS/$idx.log" ]] && cat "$RESULTS/$idx.log"
  [[ "$rc" -eq 125 ]] && echo "[run-selftests] no verdict written — the worker died before scoring this suite (infra, not a result)"
  echo "::endgroup::"

  if [[ "$rc" -ne 0 ]]; then
    FAILED="$FAILED$suite (rc=$rc)"$'\n'
    [[ "$rc" -eq 125 ]] && INFRA=$((INFRA + 1))
  fi
done < "$BASE/worklist"

# ---- count reconciliation ------------------------------------------------------------
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  echo "[run-selftests] ERROR: discovered-minus-excluded is $EXPECTED but $RAN suite(s) ran — silent truncation, not a pass." >&2
  exit 2
fi

if [[ -n "$FAILED" ]]; then
  echo "[run-selftests] FAILED suites:" >&2
  printf '%s' "$FAILED" | while IFS= read -r f; do [[ -n "$f" ]] && echo "  $f" >&2; done
  count="$(printf '%s' "$FAILED" | grep -c .)"
  echo "[run-selftests] summary: $RAN run, $count failed ($INFRA infrastructure)" >&2
  # THE RESERVED CODE, and it is reserved rather than merely returned: a 3 says "this
  # told us nothing about the branch". So the condition has to be ALL, never ANY — one genuinely
  # red suite alongside a killed worker is still a red branch, and reporting that as
  # infrastructure would be the fail-open direction.
  #
  # 0/1/2 are taken here (`die`, the count reconciliation, the failure list), so a fourth code was
  # needed; 125-127 was rejected because it is the shell's and `timeout`'s own "could not execute"
  # band, which a consumer lane can hit by accident once the code means something cross-repo.
  if [[ "$INFRA" -eq "$count" ]]; then
    echo "[run-selftests] every failure above is the no-verdict INFRASTRUCTURE class — the workers died, so nothing was learned about this tree. Exiting 3 (reserved), not 1." >&2
    exit 3
  fi
  exit 1
fi

echo "[run-selftests] summary: $RAN run, 0 failed"
