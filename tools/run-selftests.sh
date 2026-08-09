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
# `mktemp` state dir. The one suite carrying a literal `/tmp` path (statectl-selftest.sh) passes
# `/tmp/x` only as an opaque `--worktree` argument and never writes it.
#
# DISCOVERY IS `*-selftest.sh` ONLY, deliberately. The three `*-selftest.mjs` files are executed
# by plugins/dev-pipeline/skills/run/workflows/workflows-mjs-selftest.sh, which is itself in this
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
#
#   --exclude   repeatable. Lifts a suite out of THIS sweep while leaving it discovered, so it
#               can run in its own CI job. An exclusion matching no discovered suite is a HARD
#               ERROR — the stale-row posture install-topology-known-red.tsv and
#               mutation-baseline.tsv already carry, applied to a stale workflow argument.
#   --jobs      concurrency; defaults to $SELFTEST_JOBS, itself defaulting to 4 (the recipe).
#   --root      tree to discover under; defaults to the repo root above this script.
#
# EXIT: 0 iff every run suite passed. Non-zero names every failing suite. 2 for a usage error,
# a stale exclusion, or a discovered/run count disagreement.
#
# NOT `set -e`: this harness runs other people's suites and SCORES their exit codes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
JOBS="${SELFTEST_JOBS:-4}"
EXCLUDES=""   # newline-separated; bash 3.2 has no array-of-args ergonomics worth the noise here

die() { echo "[run-selftests] $1" >&2; exit 2; }

# ---- worker mode ---------------------------------------------------------------------
# One suite per fresh invocation. Writes <idx>.rc and <idx>.log; the parent scores from those,
# so a worker that dies without writing an .rc is visible as infra rather than as a green suite.
#
# This branch must come BEFORE the option parser: a worker is invoked with four POSITIONAL
# arguments, which the parser below would reject as unknown options — and it would do so into
# the dispatch call's discarded stdout, leaving every suite scored 125 with no visible cause.
if [[ "${RUN_SELFTESTS_WORKER:-}" == "1" ]]; then
  W_IDX="${1:?worker: index}"; W_LIST="${2:?worker: worklist}"; W_ROOT="${3:?worker: root}"; W_OUT="${4:?worker: results}"
  W_SUITE="$(awk -F'\t' -v i="$W_IDX" '$1 == i { print $2 }' "$W_LIST")"
  [[ -n "$W_SUITE" ]] || exit 0
  ( cd "$W_ROOT" && bash "$W_SUITE" ) > "$W_OUT/$W_IDX.log" 2>&1
  echo "$?" > "$W_OUT/$W_IDX.rc"
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
    *)         die "unknown argument: $1" ;;
  esac
done

[[ "$JOBS" =~ ^[0-9]+$ ]] && [[ "$JOBS" -ge 1 ]] || die "--jobs/SELFTEST_JOBS must be a positive integer, got: $JOBS"
[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

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
EXCLUDED=0
while IFS= read -r ex; do
  [[ -n "$ex" ]] || continue
  ex="${ex#./}"
  if ! printf '%s\n' "$ALL" | grep -qxF "$ex"; then
    die "--exclude '$ex' matches no discovered suite under $ROOT — stale exclusion"
  fi
  EXCLUDED=$((EXCLUDED + 1))
done <<EOF
$EXCLUDES
EOF

EXPECTED=$((DISCOVERED - EXCLUDED))
[[ "$EXPECTED" -gt 0 ]] || die "every discovered suite is excluded — a sweep that runs nothing is never green"

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
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  if [[ -n "$EXCLUDES" ]] && printf '%s' "$EXCLUDES" | grep -qxF "${suite#./}"; then
    continue
  fi
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

echo "[run-selftests] $DISCOVERED discovered, $EXCLUDED excluded, $EXPECTED to run, jobs=$JOBS"

# ---- dispatch ------------------------------------------------------------------------
# shellcheck disable=SC2016  # the placeholders are for the inner sh -c, deliberately unexpanded
cut -f1 "$BASE/worklist" | RUN_SELFTESTS_WORKER=1 xargs -P "$JOBS" -n1 -I{} \
  sh -c 'bash "$0" "$1" "$2" "$3" "$4"' \
  "$HERE/$(basename "${BASH_SOURCE[0]}")" "{}" "$BASE/worklist" "$ROOT" "$RESULTS" >/dev/null

# ---- ordered replay ------------------------------------------------------------------
# Worklist order, not completion order: the log reads the same at -P 4 as it does at -P 1, which
# is what makes AC-4's same-verdict claim inspectable rather than merely asserted. The
# ::group:: framing is emitted unconditionally — GitHub folds it, a local run just sees a
# labelled block, and a selftest can assert contiguity without faking $GITHUB_ACTIONS.
RAN=0
FAILED=""
while IFS= read -r line; do
  idx="${line%%	*}"; suite="${line#*	}"
  RAN=$((RAN + 1))
  if [[ -f "$RESULTS/$idx.rc" ]]; then
    rc="$(cat "$RESULTS/$idx.rc")"
  else
    # A worker that produced no verdict is infra, not a suite result. Never silently green.
    rc=125
  fi

  if [[ "$rc" -eq 0 ]]; then
    echo "::group::pass  $suite"
  else
    echo "::group::FAIL  $suite (rc=$rc)"
  fi
  [[ -f "$RESULTS/$idx.log" ]] && cat "$RESULTS/$idx.log"
  [[ "$rc" -eq 125 ]] && echo "[run-selftests] no verdict written — the worker died before scoring this suite (infra, not a result)"
  echo "::endgroup::"

  if [[ "$rc" -ne 0 ]]; then
    FAILED="$FAILED$suite (rc=$rc)"$'\n'
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
  echo "[run-selftests] summary: $RAN ran, $((RAN - count)) passed, $count failed" >&2
  exit 1
fi

echo "[run-selftests] summary: $RAN ran, $RAN passed, 0 failed"
