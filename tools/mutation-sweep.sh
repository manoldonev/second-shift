#!/usr/bin/env bash
# mutation-sweep.sh — test-the-tests. Mutate the repo's shell guards, run their paired
# selftests, and report which mutants SURVIVE. A surviving mutant is a regression the
# suite would not have caught.
#
# Deliberately named OUTSIDE the `*-selftest.sh` discovery glob so CI never runs it
# against itself (the scenario-lib.sh precedent). Its companion IS in-glob:
# tools/mutation-sweep-selftest.sh.
#
# USAGE
#   mutation-sweep.sh --mode full [--seed] [--shard i/N] [--report F] [--baseline-out F] [--slow-out F]
#   mutation-sweep.sh --mode pr --base <ref> [--report F]
#   mutation-sweep.sh --mode merge --shards-dir <dir> [--report F] [--baseline-out F] [--slow-out F]
#
# SHARDING — `--shard i/N` (full mode only) sweeps the i-th residue class of the sorted
# non-excluded guard list (round-robin: guard at sorted index j belongs to shard j%N+1).
# Deterministic for a given tree, and round-robin rather than contiguous ranges so
# directory-clustered slow suites spread across shards instead of stacking in one. Merge
# mode recombines the per-shard artifacts (each shard's report/baseline/slow files laid
# out as <dir>/<shard>/mutation-*.tsv) into the single operator-facing set. A shard also
# publishes a `mutation-complete` marker, written only on reaching finish(); merge reds on
# a report without one, because --report is streamed and a partial report looks whole.
#
# GUARD UNIVERSE is a rule, not a list: every git-tracked `*.sh` that is not a
# `*-selftest.sh` and is not under `*/evals/*` or `tests/hooks-smoke/`. Every guard in it
# must resolve to its killer(s) via directory-scoped same-stem pairing, a
# mutation-pair-map.tsv row, or a mutation-exclusions.tsv row. An unaccounted guard is RED.
#
# EXIT CONTRACT — survivors are DATA, not automatically a red build.
#   Red only for: a baseline-absent survivor, a `pool disagreement` (a survivor the serial
#   re-verify kills — the harness contradicting itself, never a coverage gap), a missing
#   baseline in an enforcing non-seed
#   run (`baseline-missing`), catalog anchor drift, a bash -n-invalid CATALOG mutant, an
#   operator match grep cannot run as a pattern, an
#   unaccounted guard, an unrunnable pair, a baseline environment mismatch
#   (`baseline-environment-mismatch`), a sandbox failure, or — in merge mode — a guard
#   with no shard row (`merge incomplete`, a shard died before publishing), a guard with
#   several (`merge overlap`, the partition is broken), a shard whose report has no
#   completion marker (`merge truncated`, streamed partial evidence), or shard artifacts
#   whose headers disagree.
#   Warn (never red): a killed mutant still listed in the baseline, and a baseline row
#   whose guard no longer resolves — both say "shrink the baseline".
#
# KILLER TIME BOUND — every killer runs under a wall-clock bound. A mutant that makes its
# guard spin would otherwise block the shard until its time bound tore the job down, which
# once destroyed BOTH the log and the artifact and is how two successive 10-shard nightlies
# lost the same three shards with no diagnosis. Bounding the sweep STEP rather than the job
# now keeps that log, and the streamed report keeps the artifact non-empty — but partial
# evidence is a worse answer than a finished sweep, so the bound below is still what keeps
# a shard diagnosable. A timed-out killer counts as a KILL and is logged by name; a
# killer that blows the bound on the UNMUTATED sandbox is the existing `unrunnable pair`
# red, now saying which it was.
#
# The bound is PER SUITE, not flat: `4 x the suite's measured unmutated time`, floored at
# 60s and capped at MUTATION_SWEEP_KILLER_TIMEOUT_S (300s). A flat bound bounds one killer
# but not a SHARD — a guard whose mutants all spin costs k x the bound, and the first
# bounded seed run still lost a 60-min shard to that accumulation on a ~15-min cost model.
# Scaling to the suite puts the saving where the mutants are (the fast suites) and leaves
# the slow end's margin untouched.
#
# KILLER PROCESS BOUND — the time bound cannot save the host from a mutant that makes its
# guard FORK rather than spin. A wall clock only decides WHEN to stop waiting; it does
# nothing about what the guard does to the machine in the meantime, and a recursively
# forking guard exhausts the runner long before any deadline is reached. That is not
# hypothetical: `doctor.sh --report` re-invokes itself (`bash "$0"`) for its nested
# check run, so flipping the `-eq` that gates report mode makes the nested run re-enter
# report mode and fork again, without bound. The mutant is the FIRST cmp-eq ordinal on
# that guard, which is why shard 1 reached it on every nightly and died there twice —
# once as "the runner has received a shutdown signal", once as "the hosted runner lost
# communication with the server", the two faces of a starved host. Neither run left a
# log blob or an artifact, so the shard's whole verdict was lost both times.
#
# So the group's POPULATION is bounded too, at MUTATION_SWEEP_KILLER_MAX_PROCS (100).
# Like a timeout it scores as a KILL and is logged by name, which turns a runner death
# with no diagnostics into one named mutant on one named guard.
#
# ENFORCING vs ADVISORY: enforcing iff GITHUB_ACTIONS is set. Local runs are advisory and
# say so — kill verdicts are only comparable inside the canonical environment
# (ubuntu-latest + SKIP_STRESS=1), whose GNU userland (coreutils, bash, find) a local
# macOS/BSD run does not exactly reproduce.
#
# ---------------------------------------------------------------------------------------
# COST. The sweep's wall time is Sigma over guards of (mutants x paired-suite seconds), and
# for a long time every one of those seconds was serial on one core. Three levers removed
# it, and the ORDER OF PHASES below is what makes them provably free of coverage cost.
#
# The run is five ordered phases. Only the mutant scoring is parallel; everything that
# EMITS runs serially, in item order. That is not stylistic — it is what makes the survivor
# set, the counts and the report TSV independent of the pool size by construction rather
# than by hope.
#   1. ENUMERATE     — serial, in sandbox 0: apply each generic/catalog mutant, run the
#                      `bash -n` and `git diff --quiet` gates, and write the MUTATED GUARD
#                      BYTES to a work-item blob. Skips, anchor drift and invalid-sed reds
#                      are all decided here, in the historical order.
#   2. CACHE PROBE   — serial: a hit writes its verdict file directly; a miss goes to the
#                      pool manifest. This is also what decides which guards still need a
#                      precheck, which is why it must run BEFORE one.
#   3. PRECHECK      — serial, once per DISTINCT suite, and only for guards carrying at
#                      least one uncached mutant. Produces the `unrunnable pair` verdict and
#                      the MEASURED timings the per-suite killer bound reads.
#   4. VERDICT POOL  — workers take work items by residue class, each in its OWN sandbox:
#                      install the blob through the guard's inode, run the ordered kill set.
#   5. AGGREGATE     — serial: read verdicts in item order, emit the bound-hit lines, the
#                      per-guard counts, the report rows and the exit contract.
#
# WHY THE PRECHECK IS SERIAL AND HOISTED, not folded into the pool. Its timings set every
# killer bound and feed mutation-slow-suites.tsv's deferral semantics, so measuring them
# under the pool's own contention would measure the pool rather than the suite. And why it
# comes after the probe: a precheck IS a paired-suite execution, so a guard whose every
# mutant is already cached must skip it entirely or the run cannot honestly claim to have
# executed none.
#
# MEMOIZATION is the lever that reaches "instant", and the only one that can be wrong in a
# way a green run would hide. The key is the mutated guard's bytes, every paired suite's
# bytes, k, the environment, and THIS FILE's bytes. Keying on the GUARD ALONE is the one way
# to get the middle part wrong: adding a test case can kill a previously-surviving mutant,
# and a guard-only key would serve the stale SURVIVED forever.
#
# The key is narrow, and NOT sound: a THIRD file can flip a verdict with the guard and its
# suites byte-identical — `lean-gate.sh` shells out to four sibling scripts, and
# `statectl-selftest.sh` sources `scenario-lib.sh`. A whole-tree key would be sound and would
# also drop the hit rate to zero, since the sweep sandboxes HEAD and every fix round is a new
# commit. What bounds the unsoundness is the lane: the cache is neither read nor written when
# GITHUB_ACTIONS is set, so a stale verdict can only make a LOCAL advisory run optimistic,
# never the authoritative one.
#
# PARALLELISM was blocked by a single shared sandbox — one worktree, one mutated file, so
# mutants had to serialize. Now one sandbox per WORKER: a worker owns its sandbox for the
# whole run and restores the guard between items, so no two concurrently-running mutants ever
# share one. Disk is therefore bounded at pool x ~7MB rather than mutants x ~7MB.
#
# EARLY EXIT reads the repo-wide selftest convention (`fail() { echo "  FAIL: $1" >&2; }`):
# a killed mutant's verdict is settled at the FIRST such line, so the group is reaped there
# instead of running the remaining cases. Its soundness is an INVARIANT THE PRECHECK ASSERTS
# on every run — a green suite emits no such line — rather than a one-off corpus measurement.
# Breaking it is an unrunnable pair, loudly, because a suite that prints the trigger while
# passing would have every one of its guard's mutants scored KILLED on prose.
#
# A suite reaped mid-run (early exit, or either killer bound) never runs its own
# `trap ... EXIT` cleanup, so killers run with TMPDIR pointed at a per-item scratch directory
# this harness removes unconditionally.
#
# bash 3.2 clean: the companion selftest is in-glob, so it runs on the macOS lane's stock
# bash. No associative arrays, no mapfile, no ${var^^}.
set -uo pipefail

K_BUDGET="${MUTATION_SWEEP_K:-2}"   # generic mutants per operator per guard
# A paired suite at or above this is "slow". Overridable for the same reason
# MUTATION_SWEEP_KILLER_MAX_PROCS is: the companion selftest can then trip the drift warn on a
# fixture suite that sleeps for a second, instead of one that has to sleep past the real bar.
# WIDER THAN THAT ONE USE, THOUGH. is_slow() reads it, and is_slow() is what decides the PR
# lane's deferred-to-nightly set and what a --seed run publishes against — so moving this
# moves which guards a PR grades, not just whether a warn fires. Nothing sets it in CI and the
# companion suite scopes it non-exporting, which is the only reason there is no live leak
# path; this repo has already had a gate seam exported into a nested real invocation.
SLOW_THRESHOLD_S="${MUTATION_SWEEP_SLOW_THRESHOLD_S:-5}"
PR_FAST_GUARD_CAP=6                 # PR lane: sweep at most this many fast guards
# Ceiling on ONE killer invocation, and the bound used for the unmutated precheck (which
# has no measurement yet — it IS the measurement). Clears the slowest paired suite by a
# wide margin under runner load: statectl-selftest measured 107-120s on the CI lane.
KILLER_TIMEOUT_S="${MUTATION_SWEEP_KILLER_TIMEOUT_S:-300}"
KILLER_TIMEOUT_FACTOR=4             # mutant-run bound = this x the suite's measured time
# ...floored here, so a fast suite still gets real slack. Overridable so the companion
# selftest can prove the bound SCALES without burning the real floor in wall clock.
KILLER_TIMEOUT_MIN_S="${MUTATION_SWEEP_KILLER_MIN_S:-60}"
# Live processes allowed in ONE killer's process group. Sized off measurement, not taste:
# the seven heaviest paired suites were sampled in this exact shape (own process group,
# `ps -A -o pgid=`) and peak between 6 and 9 — statectl 8, scenario-liveness 9, cost-block
# 8, verifyctl 9, e2e-replay 7, doctor 6, check-lean-chain 7. 100 therefore clears the
# measured ceiling by more than 10x, with room for suites that fan out harder than
# anything here does today, while still catching a forking guard within seconds of it
# starting. Overridable so the companion selftest can trip it on a handful of processes
# rather than on a real bomb.
KILLER_MAX_PROCS="${MUTATION_SWEEP_KILLER_MAX_PROCS:-100}"

TAB="$(printf '\t')"

# ------------------------------------------------------------------ worker pool
# `cores - 2` leaves the machine usable and matches the repo's existing `-P 4` habit at the
# low end; the cap keeps a 64-core runner from opening 62 worktrees for a 33-mutant diff.
# Sandboxes are created LAZILY up to min(pool, items), so a two-mutant run still makes one.
JOBS_CAP=8
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || CORES=""
case "${CORES:-}" in ''|*[!0-9]*) CORES=2 ;; esac
JOBS="${MUTATION_SWEEP_JOBS:-}"
if [[ -z "$JOBS" ]]; then
  JOBS=$((CORES - 2))
  [[ $JOBS -lt 1 ]] && JOBS=1
  [[ $JOBS -gt $JOBS_CAP ]] && JOBS=$JOBS_CAP
fi

# ----------------------------------------------------------------------- cache
# ADVISORY LANE ONLY. The cache is neither read nor written when GITHUB_ACTIONS is set (see
# below, once ENFORCING is known). The key is deliberately NARROW — the mutated guard and its
# suites — and that key is not quite sound in this tree: `lean-gate.sh` shells out to four
# sibling scripts and `statectl-selftest.sh` sources `scenario-lib.sh`, so a THIRD file can
# flip a verdict with both keyed files byte-identical. A whole-tree key would be sound and
# would also drop the hit rate to zero, since the sweep sandboxes HEAD and every fix round is
# a new commit. Confining the cache to the advisory lane is what makes the narrow key an
# acceptable trade instead of an unsound one: a stale verdict can then only make a LOCAL run
# optimistic, and the authoritative run always starts cold.
CACHE_ENABLED="${MUTATION_SWEEP_CACHE:-1}"
# Per repo, not per machine: two checkouts can hold byte-identical guards and suites while
# differing in one of those third files, and the sourced-file residual is the whole reason
# not to let them share entries.
CACHE_DIR="${MUTATION_SWEEP_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/second-shift/mutation-sweep}"
# AC-8's bound. Eviction is WHOLESALE rather than LRU on purpose: entries are one line each,
# so the cap is only ever reached after tens of thousands of distinct mutants, and the two
# portable ways to sort by mtime (`stat -f` vs `stat -c`) are exactly the kind of
# dialect-split this repo's macOS lane exists to catch. Wiping costs one cold run and cannot
# be subtly wrong.
CACHE_MAX="${MUTATION_SWEEP_CACHE_MAX:-20000}"

# ------------------------------------------------------------------ early exit
EARLY_EXIT="${MUTATION_SWEEP_EARLY_EXIT:-1}"
FAIL_PATTERN="${MUTATION_SWEEP_FAIL_PATTERN:-FAIL:}"

MODE=""
BASE_REF=""
SEED=0
REPORT_OUT=""
BASELINE_OUT=""
SLOW_OUT=""
SHARD_SPEC=""
SHARDS_DIR=""
# Unsharded is literally shard 1/1: every guard is in residue class 0, and the
# shard-1-only report rows (excluded guards) emit exactly once.
SHARD_I=1
SHARD_N=1

die() { echo "[mutation-sweep] FATAL: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)         MODE="${2:-}"; shift 2 ;;
    --base)         BASE_REF="${2:-}"; shift 2 ;;
    --seed)         SEED=1; shift ;;
    --report)       REPORT_OUT="${2:-}"; shift 2 ;;
    --baseline-out) BASELINE_OUT="${2:-}"; shift 2 ;;
    --slow-out)     SLOW_OUT="${2:-}"; shift 2 ;;
    --shard)        SHARD_SPEC="${2:-}"; shift 2 ;;
    --shards-dir)   SHARDS_DIR="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,52p' "$0"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

case "$JOBS" in ''|*[!0-9]*) die "MUTATION_SWEEP_JOBS must be a positive integer: '$JOBS'" ;; esac
[[ "$JOBS" -ge 1 ]] || die "MUTATION_SWEEP_JOBS must be at least 1: '$JOBS'"
case "$CACHE_MAX" in ''|*[!0-9]*) die "MUTATION_SWEEP_CACHE_MAX must be a non-negative integer: '$CACHE_MAX'" ;; esac

[[ "$MODE" == "full" || "$MODE" == "pr" || "$MODE" == "merge" ]] || die "--mode must be 'full', 'pr', or 'merge'"
[[ "$MODE" == "pr" && -z "$BASE_REF" ]] && die "--mode pr requires --base <ref>"
[[ "$MODE" == "pr" && $SEED -eq 1 ]] && die "--seed does not apply to PR mode (a diff-scoped baseline would be partial)"
if [[ -n "$SHARD_SPEC" ]]; then
  [[ "$MODE" == "full" ]] || die "--shard applies only to --mode full"
  # Shape gate rejects zero, leading zeros (octal traps), and anything non-numeric; the
  # range gate rejects i > N. Both die like every other argv error.
  case "$SHARD_SPEC" in
    [1-9]*/[1-9]*) : ;;
    *) die "--shard must be i/N with 1 <= i <= N: '$SHARD_SPEC'" ;;
  esac
  SHARD_I="${SHARD_SPEC%%/*}"; SHARD_N="${SHARD_SPEC#*/}"
  case "$SHARD_I$SHARD_N" in
    *[!0-9]*) die "--shard must be i/N with 1 <= i <= N: '$SHARD_SPEC'" ;;
  esac
  [[ "$SHARD_I" -le "$SHARD_N" ]] || die "--shard index exceeds shard count: '$SHARD_SPEC'"
fi
if [[ "$MODE" == "merge" ]]; then
  [[ -n "$SHARDS_DIR" ]] || die "--mode merge requires --shards-dir <dir>"
  [[ -d "$SHARDS_DIR" ]] || die "--shards-dir is not a directory: $SHARDS_DIR"
  SHARDS_DIR="$(cd "$SHARDS_DIR" && pwd)" || die "cannot resolve --shards-dir"
  [[ $SEED -eq 0 ]] || die "--seed does not apply to merge mode (seed-ness is read from the shard artifacts)"
  [[ -z "$BASE_REF" ]] || die "--base does not apply to merge mode"
else
  [[ -z "$SHARDS_DIR" ]] || die "--shards-dir requires --mode merge"
fi

RUN_T0="$(date +%s)"
SUITE_RUNS=0
CACHE_HITS=0

# Resolved BEFORE the cd below, so a relative invocation from a subdirectory still finds it.
# The cache keys on this file's own bytes (see cache_key), which is what makes a change to
# the kill criterion, the early-exit trigger or the killer bounds invalidate every entry with
# no human discipline in the loop.
SELF_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$REPO_ROOT" || die "cannot cd to repo root"
CACHE_DIR="$CACHE_DIR/$(basename "$REPO_ROOT")"

TOOLS_DIR="$REPO_ROOT/tools"
PAIR_MAP="$TOOLS_DIR/mutation-pair-map.tsv"
EXCLUSIONS="$TOOLS_DIR/mutation-exclusions.tsv"
OPERATORS="$TOOLS_DIR/mutation-operators.tsv"
CATALOG="$TOOLS_DIR/mutation-catalog.tsv"
BASELINE="$TOOLS_DIR/mutation-baseline.tsv"
SLOW_SUITES="$TOOLS_DIR/mutation-slow-suites.tsv"

ENFORCING=0
[[ -n "${GITHUB_ACTIONS:-}" ]] && ENFORCING=1

RC=0                 # 1 = red
WARNINGS=0
BL_WARNINGS=0        # the subset of WARNINGS whose remedy is the baseline file
red()  { echo "[mutation-sweep] RED: $*" >&2; RC=1; }
warn() { echo "[mutation-sweep] WARN: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
# A warn whose remedy IS "drop the row". Counted apart from the generic one because finish()
# PRESCRIBES a remedy, and while every warn was a baseline row it could name that remedy
# unconditionally. It no longer is: slow-list drift is a warn about a different file, and an
# aggregate that answers it with "shrink the baseline" sends the reader to a file needing
# nothing. Classify at the call site; the summary reads the class rather than assuming it.
warn_baseline() { warn "$@"; BL_WARNINGS=$((BL_WARNINGS + 1)); }
info() { echo "[mutation-sweep] $*"; }
# Evidence attached to the red/warn immediately above it. On stderr for that reason: `info`
# goes to stdout, and a diagnostic that lands in a different stream than the verdict it
# explains is one the operator has to reassemble by timestamp.
detail() { echo "[mutation-sweep]   $*" >&2; }

# ---------------------------------------------------------------- TSV loading
# Parallel indexed arrays — bash 3.2 has no associative arrays. Sizes here are in the
# tens, so linear lookup is not worth optimizing away.
EXCL_PATH=(); EXCL_REASON=()
MAP_GUARD=(); MAP_SUITE=()
OP_ID=(); OP_MATCH=(); OP_FLIP=()
CAT_ID=(); CAT_GUARD=(); CAT_SED=()
SLOW_NAME=(); SLOW_SECS=()
BL_ID=()

# Emits the non-comment, non-blank rows of a TSV. The `|| [[ -n "$line" ]]` tail is what
# makes a final line with no trailing newline still count. Callers parse columns
# themselves rather than passing a callback: a name-indirect dispatch reads as a dead
# function to shellcheck, and the explicit loops are shorter than the suppressions.
tsv_rows() {
  local file="$1" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in ''|'#'*) continue ;; esac
    printf '%s\n' "$line"
  done < "$file"
}

while IFS=$'\t' read -r c1 c2; do
  EXCL_PATH[${#EXCL_PATH[@]}]="$c1"; EXCL_REASON[${#EXCL_REASON[@]}]="${c2:-}"
done < <(tsv_rows "$EXCLUSIONS")

# Every reader below names EXACTLY as many variables as its file has columns. `read`
# assigns all leftover fields to the LAST variable, so reading a 4-column row into 3
# variables silently glues the trailing column — tab and all — onto the one before it.
# That is not hypothetical: it made every catalog `sed` field carry its own `note`,
# turning a valid program into an invalid one whose failure then read as anchor drift.
while IFS=$'\t' read -r c1 c2 _; do
  MAP_GUARD[${#MAP_GUARD[@]}]="$c1"; MAP_SUITE[${#MAP_SUITE[@]}]="${c2:-}"
done < <(tsv_rows "$PAIR_MAP")

while IFS=$'\t' read -r c1 c2 c3; do
  OP_ID[${#OP_ID[@]}]="$c1"; OP_MATCH[${#OP_MATCH[@]}]="${c2:-}"; OP_FLIP[${#OP_FLIP[@]}]="${c3:-}"
done < <(tsv_rows "$OPERATORS")

while IFS=$'\t' read -r c1 c2 c3 _; do
  CAT_ID[${#CAT_ID[@]}]="$c1"; CAT_GUARD[${#CAT_GUARD[@]}]="${c2:-}"; CAT_SED[${#CAT_SED[@]}]="${c3:-}"
done < <(tsv_rows "$CATALOG")

while IFS=$'\t' read -r c1 c2 _; do
  SLOW_NAME[${#SLOW_NAME[@]}]="$c1"; SLOW_SECS[${#SLOW_SECS[@]}]="${c2:-0}"
done < <(tsv_rows "$SLOW_SUITES")

[[ ${#OP_ID[@]} -gt 0 ]] || die "no operators loaded from $OPERATORS"

is_excluded() {
  local p="$1" i=0
  while [[ $i -lt ${#EXCL_PATH[@]} ]]; do
    [[ "${EXCL_PATH[$i]}" == "$p" ]] && return 0
    i=$((i + 1))
  done
  return 1
}

# Kill set = directory-scoped same-stem suite (if it exists) UNION every pair-map row.
kill_set_for() {
  local guard="$1" dir stem same i out=""
  dir="$(dirname "$guard")"
  stem="$(basename "$guard" .sh)"
  same="$dir/$stem-selftest.sh"
  [[ -f "$REPO_ROOT/$same" ]] && out="$same"
  i=0
  while [[ $i -lt ${#MAP_GUARD[@]} ]]; do
    if [[ "${MAP_GUARD[$i]}" == "$guard" ]]; then
      case " $out " in
        *" ${MAP_SUITE[$i]} "*) : ;;
        *) out="${out:+$out }${MAP_SUITE[$i]}" ;;
      esac
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

has_map_rows() {
  local guard="$1" i=0
  while [[ $i -lt ${#MAP_GUARD[@]} ]]; do
    [[ "${MAP_GUARD[$i]}" == "$guard" ]] && return 0
    i=$((i + 1))
  done
  return 1
}

suite_seconds() {
  local s="$1" i=0
  while [[ $i -lt ${#SLOW_NAME[@]} ]]; do
    if [[ "${SLOW_NAME[$i]}" == "$s" ]]; then printf '%s' "${SLOW_SECS[$i]}"; return 0; fi
    i=$((i + 1))
  done
  printf '0'
}

# Seconds this RUN measured for a suite on the unmutated sandbox (the precheck timings).
# Largest wins: the same suite is timed once per guard whose kill set contains it, and the
# conservative reading is the slowest observation.
measured_seconds() {
  local s="$1" best=0 name secs
  while IFS=$'\t' read -r name secs; do
    [[ "$name" == "$s" ]] || continue
    [[ "${secs:-0}" -gt "$best" ]] 2>/dev/null && best="$secs"
  done <<< "${MEASURED:-}"
  printf '%s' "$best"
}

# Per-suite killer bound. A flat 300s bounds one killer but NOT a shard: a guard whose
# mutants all spin costs k * 300s, and shard 2 of the first bounded seed run blew a 60-min
# job on a ~15-min cost model doing exactly that. Scaling to what the suite actually takes
# fixes the accumulation where the mutants are — 38 of shard 2's mutants pair with ~2s
# suites and only 6 with statectl — without touching the slow end's safety margin:
#   ~2s suite   -> the 60s floor      (5x cheaper than the flat bound)
#   statectl     -> 300s ceiling       (measured 107-120s on CI; margin unchanged)
# Floor first, ceiling last, so KILLER_TIMEOUT_S stays a hard cap the floor cannot raise.
killer_bound_for() {
  local s="$1" secs b
  secs="$(measured_seconds "$s")"
  [[ "$secs" -gt 0 ]] 2>/dev/null || secs="$(suite_seconds "$s")"
  b=$(( ${secs%%.*} * KILLER_TIMEOUT_FACTOR ))
  [[ $b -lt $KILLER_TIMEOUT_MIN_S ]] && b=$KILLER_TIMEOUT_MIN_S
  [[ $b -gt $KILLER_TIMEOUT_S ]] && b=$KILLER_TIMEOUT_S
  printf '%s' "$b"
}

is_slow() {
  local secs; secs="$(suite_seconds "$1")"
  [[ "${secs%%.*}" -ge "$SLOW_THRESHOLD_S" ]] 2>/dev/null
}

# ------------------------------------------------------------------- hashing
# shasum ships with macOS and with the ubuntu runner's perl; sha256sum is coreutils. If
# NEITHER resolves the cache disables itself rather than keying on something weaker — a
# cache that cannot compute its own key must serve no entries at all.
SHA_KIND=""
if command -v shasum >/dev/null 2>&1; then
  SHA_KIND="shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_KIND="sha256sum"
fi

sha_stdin() {
  case "$SHA_KIND" in
    shasum)    shasum -a 256 2>/dev/null | cut -d' ' -f1 ;;
    sha256sum) sha256sum     2>/dev/null | cut -d' ' -f1 ;;
    *)         return 1 ;;
  esac
}
sha_file() {
  [[ -f "$1" ]] || return 1
  sha_stdin < "$1"
}

if [[ "$CACHE_ENABLED" == "1" && -z "$SHA_KIND" ]]; then
  CACHE_ENABLED=0
  info "cache disabled: neither shasum nor sha256sum is available, so no key can be computed."
fi
# A SEED run publishes mutation-slow-suites.tsv from the timings its own unmutated precheck
# takes, and its header says so. Serving those timings from an earlier run's cache would make
# the file a record of when the cache was populated rather than of this run — so seed mode
# measures everything itself, at the cost of one uncached pass it takes once.
if [[ "$CACHE_ENABLED" == "1" && $SEED -eq 1 ]]; then
  CACHE_ENABLED=0
  info "cache disabled for the seed run: the slow list must record THIS run's measurements."
fi
# The trade the narrow key rests on. Neither read nor written in the enforcing lane, so a
# stale verdict can only ever make a LOCAL advisory run optimistic — and the cost of that is
# learning about a baseline-absent survivor one CI cycle later, which is the same cost the
# issue's own follow-up already accepts for skipping the local run outright.
if [[ "$CACHE_ENABLED" == "1" && $ENFORCING -eq 1 ]]; then
  CACHE_ENABLED=0
  info "cache disabled in the enforcing lane: CI is the authority and always runs cold."
fi
SELF_SHA=""
[[ "$CACHE_ENABLED" == "1" ]] && SELF_SHA="$(sha_file "$SELF_PATH")"
if [[ "$CACHE_ENABLED" == "1" && -z "$SELF_SHA" ]]; then
  CACHE_ENABLED=0
  info "cache disabled: this script's own bytes could not be hashed, so no key can be pinned to them."
fi

# The environment axis of the key: every knob that changes WHAT A VERDICT MEANS, so that a run
# under a different one is never served an answer to a different question. Same axis the
# baseline header already records, plus two families of knob.
#
# The killer bounds decide whether a spinning mutant scores as a timeout KILL. The early-exit
# trigger decides it by the identical argument — a run with a custom FAIL_PATTERN scores under a
# different kill criterion, and D-3's standing assertion does not close the gap: the precheck
# only establishes that the UNMUTATED suite is silent, so a mutated guard whose suite prints
# that pattern while exiting 0 would cache a KILLED a default-pattern run then serves.
#
# MUTATION_SWEEP_JOBS is deliberately NOT here, and the omission is not free: pool contention
# can turn a would-be survivor into a timeout KILL, and that verdict then persists across pool
# sizes. Keying on it would cost most of the hit rate — the loop this cache exists for re-runs
# at one pool size — and the residual leans the safe way, hiding a weak test rather than
# inventing a finding. `MUTATION_SWEEP_CACHE=0` is the escape hatch when a survivor is in doubt.
CACHE_ENV_TAG="${RUNNER_OS:-$(uname -s 2>/dev/null || echo unknown)}|${SKIP_STRESS:-}|$KILLER_TIMEOUT_S|$KILLER_TIMEOUT_FACTOR|$KILLER_TIMEOUT_MIN_S|$KILLER_MAX_PROCS|$EARLY_EXIT|$FAIL_PATTERN"

# $1 = sha of the MUTATED guard bytes, $2 = sha of the kill set's suite bytes (in order).
#
# SELF_SHA is in the key, and it is the component that needs the argument. A hand-maintained
# schema constant would have to be bumped by whoever next edits the kill criterion, the
# early-exit trigger or the killer bounds — and the one thing certain about that discipline is
# that it eventually fails silently, leaving entries that outlive the meaning they were
# recorded under. Keying on this file's own bytes makes the invalidation automatic. The stated
# cost: a change that edits this harness runs fully cold, which is exactly what this ticket's
# own fix rounds do.
cache_key() {
  printf 'mutation-sweep|%s|%s|%s|k%s|%s' "$SELF_SHA" "$1" "$2" "$K_BUDGET" "$CACHE_ENV_TAG" | sha_stdin
}

# FAIL SAFE (AC-8): anything that is not exactly one well-formed record line is a MISS, and
# a miss costs a real run. There is deliberately no path here that turns an unreadable or
# malformed entry into a pass.
cache_get() {
  local f n line
  [[ "$CACHE_ENABLED" == "1" ]] || return 1
  [[ -n "$1" ]] || return 1
  f="$CACHE_DIR/${1:0:2}/$1"
  [[ -f "$f" && -r "$f" ]] || return 1
  n="$(wc -l < "$f" 2>/dev/null | tr -d ' ')" || return 1
  [[ "$n" == "1" ]] || return 1
  line="$(head -1 "$f" 2>/dev/null)" || return 1
  case "$line" in
    "v1${TAB}killed${TAB}"*|"v1${TAB}survived${TAB}"*) : ;;
    *) return 1 ;;
  esac
  printf '%s' "$line"
}

# mv-atomic, so a sibling worker reading the same key never sees a torn file. Every failure
# path here is silent and non-fatal: an unwritable cache must slow the sweep down, never
# break it.
cache_put() {
  local d t
  [[ "$CACHE_ENABLED" == "1" ]] || return 0
  [[ -n "$1" ]] || return 0
  d="$CACHE_DIR/${1:0:2}"
  mkdir -p "$d" 2>/dev/null || return 0
  # $WORKER_TOKEN, not $$ alone, and not $RANDOM alone. In a bash-3.2 subshell `$$` is still
  # the PARENT's pid and $RANDOM continues the parent's inherited sequence, so two workers
  # reaching this line together can generate the SAME name — and then one `mv`s the other's
  # half-written file into place. The token is the only component that is distinct per worker
  # by construction.
  t="$d/.tmp.$$.$WORKER_TOKEN.$RANDOM"
  printf '%s\n' "$2" > "$t" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 0; }
  mv -f "$t" "$d/$1" 2>/dev/null || rm -f "$t" 2>/dev/null
  return 0
}

cache_prune() {
  local n
  [[ "$CACHE_ENABLED" == "1" ]] || return 0
  [[ -d "$CACHE_DIR" ]] || return 0
  n="$(find "$CACHE_DIR" -type f 2>/dev/null | grep -c '' )"
  [[ "${n:-0}" -gt "$CACHE_MAX" ]] || return 0
  rm -rf "${CACHE_DIR:?}"/* 2>/dev/null
  info "cache: $n entries exceeded the $CACHE_MAX bound — cleared (the next run is cold)."
}

in_baseline() {
  local id="$1" i=0
  while [[ $i -lt ${#BL_ID[@]} ]]; do
    [[ "${BL_ID[$i]}" == "$id" ]] && return 0
    i=$((i + 1))
  done
  return 1
}

sid_guard() { # survivor id -> owning guard relpath (empty if unresolvable)
  local sid="$1" cid i=0
  case "$sid" in
    catalog::*)
      cid="${sid#catalog::}"
      while [[ $i -lt ${#CAT_ID[@]} ]]; do
        if [[ "${CAT_ID[$i]}" == "$cid" ]]; then printf '%s' "${CAT_GUARD[$i]}"; return 0; fi
        i=$((i + 1))
      done
      ;;
    *) printf '%s' "${sid%%::*}" ;;
  esac
}

swept_this_run() {
  local g="$1" x
  [[ -n "$g" ]] || return 1
  for x in ${SWEEP_GUARDS[@]+"${SWEEP_GUARDS[@]}"}; do
    [[ "$x" == "$g" ]] && return 0
  done
  return 1
}

# True when this run assigned the guard but scored none of its mutants because its paired
# suite could not run. Distinct from `swept_this_run` on purpose — see the shrink warn.
unrun_this_run() {
  local g="$1" x
  [[ -n "$g" ]] || return 1
  for x in ${UNRUN_GUARDS:-}; do
    [[ "$x" == "$g" ]] && return 0
  done
  return 1
}

# ------------------------------------------------------------- guard universe
universe() {
  git ls-files '*.sh' \
    | grep -v -- '-selftest\.sh$' \
    | grep -v '/evals/' \
    | grep -v '^tests/hooks-smoke/' \
    | sort
}

ALL_GUARDS=()
while IFS= read -r g; do
  [[ -n "$g" ]] && ALL_GUARDS[${#ALL_GUARDS[@]}]="$g"
done < <(universe)

# Accounting runs over the WHOLE universe in both modes: an unaccounted guard is red
# regardless of whether this run would have swept it. That is the check keeping the TSV
# family honest as the tree grows, and scoping it to the diff would blind it.
for g in "${ALL_GUARDS[@]}"; do
  if is_excluded "$g"; then
    if has_map_rows "$g"; then
      red "guard is excluded AND carries pair-map rows (an exclusions row preempts pairing): $g"
    fi
    continue
  fi
  [[ -z "$(kill_set_for "$g")" ]] && red "unaccounted guard (no same-stem suite, no pair-map row, no exclusions row): $g"
done

# ------------------------------------------------------------------ mode scope
SWEEP_GUARDS=()
if [[ "$MODE" == "full" ]]; then
  # Round-robin shard partition over the sorted non-excluded list (see the header). With
  # the default 1/1 every guard is in residue class 0, so the unsharded path is unchanged.
  shard_idx=0
  for g in "${ALL_GUARDS[@]}"; do
    is_excluded "$g" && continue
    if [[ $((shard_idx % SHARD_N)) -eq $((SHARD_I - 1)) ]]; then
      SWEEP_GUARDS[${#SWEEP_GUARDS[@]}]="$g"
    fi
    shard_idx=$((shard_idx + 1))
  done
elif [[ "$MODE" == "pr" ]]; then
  TOUCHED=""
  TOUCHED="$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null)" || die "cannot diff $BASE_REF...HEAD"
  for g in "${ALL_GUARDS[@]}"; do
    is_excluded "$g" && continue
    case $'\n'"$TOUCHED"$'\n' in
      *$'\n'"$g"$'\n'*) SWEEP_GUARDS[${#SWEEP_GUARDS[@]}]="$g" ;;
    esac
  done
fi

# ------------------------------------------------------------------- reporting
# --report IS THE SINK, not a destination copied to at the end. Buffering in mktemp and
# copying once in finish() means a run that dies first publishes NOTHING — and the CI
# upload step, which reds on an empty directory (`if-no-files-found: error`), then has
# nothing to upload either. So the shard most worth diagnosing is the one that yields
# least. Writing the header and every row straight onto the artifact path makes the
# report exist from the sweep's first moment, so a killed shard still publishes an
# artifact, and whatever rows had been emitted are in it.
#
# BE PRECISE ABOUT WHAT THAT RESCUES. Rows for swept guards are emitted in PHASE 5, which
# runs after the whole worker pool has finished, so a shard killed DURING the pool — the
# actual timeout failure mode — publishes the header plus shard 1's excluded-guard
# bookkeeping rows and no verdicts. The per-mutant evidence for that death is in the job
# LOG, which survives because the sweep step carries its own timeout-minutes (blowing a
# step bound is a step failure and the job finalizes; blowing the job bound cancels it).
# The two mechanisms are complementary, and neither alone is the fix.
#
# The mktemp buffer survives only where there is no artifact path to stream to (--report
# unset), and there finish() still prints it to stdout.
if [[ -n "$REPORT_OUT" ]]; then
  REPORT_SINK="$REPORT_OUT"
else
  REPORT_SINK="$(mktemp -t mutation-sweep-report.XXXXXX)" || die "mktemp failed"
fi
printf 'guard\tstatus\tpaired_selftest\tmutants_applied\tkilled\tsurvived\tsurvivor_ids\tsites_beyond_budget\n' > "$REPORT_SINK" \
  || die "cannot write the report sink: $REPORT_SINK"

# The completion marker (see finish()) sits beside the report, so the whole output dir is
# what a shard publishes. NON-DOTTED, deliberately: upload-artifact@v4 excludes hidden
# paths unless include-hidden-files is set, and a dotted output dir once matched nothing
# while reporting success.
COMPLETE_MARKER=""
[[ -n "$REPORT_OUT" ]] && COMPLETE_MARKER="$(dirname "$REPORT_OUT")/mutation-complete"

# sites_beyond_budget is the report's answer to a question it used to be unable to
# distinguish: a guard with NO applicable site for an operator and a guard whose sites all
# sit past K_BUDGET both emitted the same silence, which is how a live spinning-idiom site
# stayed dark unnoticed. It carries per-operator detail in the paired_selftest plus-joined
# style (`cmp-z:3`, `cmp-z:3+cmp-eq:1`) — a bare count would say a guard is dark without
# saying of which mutation class. It is REPORT-ONLY and never reds a lane, the same posture
# mutation-operators.tsv states for non-application.
#
# It counts only sites the enumerator declined SOLELY because the operator's budget was
# already spent. The other two skips — an unparseable flip, a no-op flip — are harness
# artifacts rather than budget darkness and are not counted. On a `deferred-to-nightly` or
# `excluded` row it is empty because enumeration never ran; the status column is what tells
# those apart from a swept guard with nothing beyond budget.
#
# APPENDED LAST, and that is load-bearing: mutation-sweep-selftest.sh's report_row() parses
# $5/$6/$7 positionally, and --mode merge compares shard headers byte-wise.
emit_row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$REPORT_SINK"
}

finish() {
  if [[ -n "$REPORT_OUT" ]]; then
    info "report -> $REPORT_OUT"
  else
    cat "$REPORT_SINK"
    rm -f "$REPORT_SINK"
  fi
  # Written HERE and nowhere else: reaching finish() is exactly the property the marker
  # asserts. Its absence beside a report is what lets merge tell a shard that streamed
  # some rows and then died from one that ran to completion.
  if [[ -n "$COMPLETE_MARKER" ]]; then
    printf 'mode=%s shard=%s rc=%s wall_s=%s\n' \
      "$MODE" "${SHARD_SPEC:-1/1}" "$RC" "$(( $(date +%s) - RUN_T0 ))" > "$COMPLETE_MARKER" \
      || info "could not write the completion marker: $COMPLETE_MARKER"
  fi
  # AC-6: the improvement is MEASURED, never asserted from the design. Every run states what
  # it actually cost and how much of that the cache paid for, so a claim about the speedup
  # can be checked against a line the run printed rather than against a remembered figure.
  info "timing: $(( $(date +%s) - RUN_T0 ))s wall — ${SUITE_RUNS:-0} verdict(s) computed by running a paired suite, ${CACHE_HITS:-0} served from cache (pool $JOBS, cache=$CACHE_ENABLED)."
  [[ $ENFORCING -eq 1 ]] || info "ADVISORY RUN (GITHUB_ACTIONS unset) — kill verdicts are not comparable to the committed baseline; a local run's userland does not exactly reproduce CI's."
  if [[ $WARNINGS -gt 0 ]]; then
    if [[ $BL_WARNINGS -gt 0 ]]; then
      info "$WARNINGS warning(s), $BL_WARNINGS of them stale baseline row(s) — shrink the baseline."
    else
      info "$WARNINGS warning(s) — see the WARN line(s) above; the baseline is not one of them."
    fi
  fi
  exit "$RC"
}

# ------------------------------------------------------------------ shard merge
# Merge mode combines per-shard artifacts into the single operator-facing set. It never
# sweeps, never sandboxes, and never reads the committed baseline: shard files in, one
# report (plus, when the shards ran as seed, one baseline and one slow list) out.
#
# The whole-universe accounting survives sharding HERE, not per shard: every in-universe
# guard must appear in EXACTLY ONE shard report. A shard that died before publishing
# therefore NAMES its guards (`merge incomplete`) — the datapoint a monolithic run's
# destroyed logs never yielded — and a broken partition is equally loud (`merge overlap`).
#
# Since the report is STREAMED, a present report no longer implies a finished shard: a
# shard killed mid-sweep publishes the rows it had reached. The completion marker is what
# separates the two, and merge says which shards are which rather than leaving the
# operator to infer it from a row count.
if [[ "$MODE" == "merge" ]]; then
  SHARD_REPORTS=()
  for f in "$SHARDS_DIR"/*/mutation-report.tsv; do
    [[ -f "$f" ]] && SHARD_REPORTS[${#SHARD_REPORTS[@]}]="$f"
  done
  [[ ${#SHARD_REPORTS[@]} -gt 0 ]] \
    || die "no shard reports under $SHARDS_DIR (expected <shard>/mutation-report.tsv) — every shard died before publishing"

  SHARD_COMPLETE=()
  SHARD_TRUNCATED=""
  for f in "${SHARD_REPORTS[@]}"; do
    d="$(dirname "$f")"
    if [[ -f "$d/mutation-complete" ]]; then
      SHARD_COMPLETE[${#SHARD_COMPLETE[@]}]="$f"
    else
      SHARD_TRUNCATED="$SHARD_TRUNCATED $(basename "$d")"
    fi
  done
  [[ -z "$SHARD_TRUNCATED" ]] \
    || red "merge truncated: shard(s)${SHARD_TRUNCATED} published a report but no mutation-complete marker — those rows are the partial evidence of a shard killed mid-sweep, not a finished sweep"

  MERGE_HDR="$(head -1 "$REPORT_SINK")"
  for f in "${SHARD_REPORTS[@]}"; do
    [[ "$(head -1 "$f")" == "$MERGE_HDR" ]] \
      || red "shard report header mismatch (shards ran a different harness?): $f"
  done
  for f in "${SHARD_REPORTS[@]}"; do tail -n +2 "$f"; done | grep -v '^$' | sort >> "$REPORT_SINK"

  for g in "${ALL_GUARDS[@]}"; do
    n="$(awk -F'\t' -v g="$g" 'NR>1 && $1==g {c++} END {print c+0}' "$REPORT_SINK")"
    if [[ "$n" -eq 0 ]]; then
      red "merge incomplete: no shard reported guard $g — its shard died before publishing"
    elif [[ "$n" -gt 1 ]]; then
      red "merge overlap: guard $g appears in $n shard reports — the shard partition is broken"
    fi
  done

  SHARD_BASELINES=()
  for f in "$SHARDS_DIR"/*/mutation-baseline.tsv; do
    [[ -f "$f" ]] && SHARD_BASELINES[${#SHARD_BASELINES[@]}]="$f"
  done
  if [[ ${#SHARD_BASELINES[@]} -gt 0 ]]; then
    [[ -n "$BASELINE_OUT" ]] || die "seed shard baselines present but no --baseline-out (refusing to default to the committed path)"
    # COMPLETED shards, not every shard with a report: a seed shard writes its baseline
    # inside finish(), so one killed mid-sweep has a (partial) report and no baseline by
    # construction. Counting it here would report a truncation as a mode mismatch — the
    # wrong diagnosis, and one that hides the truncation red above behind a louder lie.
    [[ ${#SHARD_BASELINES[@]} -eq ${#SHARD_COMPLETE[@]} ]] \
      || red "seed merge: ${#SHARD_COMPLETE[@]} completed shard report(s) but ${#SHARD_BASELINES[@]} baseline(s) — mixed seed and enforcing shards"
    # One header block in, one header block out: the merged baseline carries the FIRST
    # shard's comment header verbatim (survivor rows never start with '#'), which the
    # equality reds below pin to every other shard's. The enforcing lane parses these
    # lines, so a duplicated or dropped header is a broken baseline, not a cosmetic one.
    BL_ENV0="$(grep -m1 '^# environment:' "${SHARD_BASELINES[0]}" || true)"
    BL_K0="$(grep -m1 '^# k=' "${SHARD_BASELINES[0]}" || true)"
    [[ -n "$BL_ENV0" && -n "$BL_K0" ]] || red "seed merge: shard baseline lacks the environment/k header: ${SHARD_BASELINES[0]}"
    for f in "${SHARD_BASELINES[@]}"; do
      [[ "$(grep -m1 '^# environment:' "$f" || true)" == "$BL_ENV0" && "$(grep -m1 '^# k=' "$f" || true)" == "$BL_K0" ]] \
        || red "seed merge: baseline header mismatch across shards ($f) — shards ran in different environments"
    done
    {
      grep '^#' "${SHARD_BASELINES[0]}"
      for f in "${SHARD_BASELINES[@]}"; do grep -v '^#' "$f"; done | grep -v '^$' | sort
    } > "$BASELINE_OUT"
    info "merge: baseline -> $BASELINE_OUT (one header block, survivor rows from all shards)"

    SHARD_SLOWS=()
    for f in "$SHARDS_DIR"/*/mutation-slow-suites.tsv; do
      [[ -f "$f" ]] && SHARD_SLOWS[${#SHARD_SLOWS[@]}]="$f"
    done
    if [[ ${#SHARD_SLOWS[@]} -gt 0 ]]; then
      [[ -n "$SLOW_OUT" ]] || die "seed shard slow lists present but no --slow-out (refusing to default to the committed path)"
      # A suite shared across shards via pair-map unions is timed once per shard; keep
      # ONE row per suite, at the largest measurement (the conservative classification).
      TAB="$(printf '\t')"
      {
        grep '^#' "${SHARD_SLOWS[0]}"
        for f in "${SHARD_SLOWS[@]}"; do grep -v '^#' "$f"; done | grep -v '^$' \
          | sort -t "$TAB" -k1,1 -k2,2rn | awk -F'\t' '!seen[$1]++'
      } > "$SLOW_OUT"
      info "merge: slow-suites -> $SLOW_OUT (per-suite max across shards)"
    fi
  fi
  finish
fi

# PR mode with nothing to do exits BEFORE any baseline resolution. The ordering is
# load-bearing: it is what keeps a doc-only or workflow-only PR from reding on
# `baseline-missing`, and it is what let the PR that introduced this harness stay green
# while its own seed run was still in flight.
if [[ "$MODE" == "pr" && ${#SWEEP_GUARDS[@]} -eq 0 ]]; then
  info "PR mode: no in-universe guards touched by $BASE_REF...HEAD — nothing to sweep."
  finish
fi

# ------------------------------------------------------- baseline + environment
# Seed mode never enforces; it PRODUCES the baseline. Everything below is skipped for it.
if [[ $SEED -eq 0 ]]; then
  if [[ ! -f "$BASELINE" ]]; then
    if [[ $ENFORCING -eq 1 ]]; then
      red "baseline-missing: $BASELINE absent in an enforcing non-seed run. Re-seed via mutation-sweep.yml (workflow_dispatch, seed=true)."
      finish
    fi
    info "no baseline at $BASELINE — advisory run, every survivor will be reported as new."
  else
    BL_ENV_LINE="$(grep -m1 '^# environment:' "$BASELINE" 2>/dev/null || true)"
    BL_K_LINE="$(grep -m1 '^# k=' "$BASELINE" 2>/dev/null || true)"
    BL_K="${BL_K_LINE#\# k=}"
    if [[ $ENFORCING -eq 1 ]]; then
      # The header's `ubuntu-latest` text is DOCUMENTARY: no Actions variable exposes the
      # runs-on label, and ImageOS is deliberately unstable across image rollouts (keying
      # on it would red the lane on GitHub's schedule rather than this repo's changes).
      # The executable assertion is RUNNER_OS + SKIP_STRESS + the generic budget.
      MISMATCH=""
      [[ "${RUNNER_OS:-}" == "Linux" ]] || MISMATCH="RUNNER_OS='${RUNNER_OS:-}' (want Linux)"
      [[ "${SKIP_STRESS:-}" == "1" ]] || MISMATCH="${MISMATCH:+$MISMATCH; }SKIP_STRESS='${SKIP_STRESS:-}' (want 1)"
      [[ "$BL_K" == "$K_BUDGET" ]] || MISMATCH="${MISMATCH:+$MISMATCH; }baseline k='$BL_K' vs current K='$K_BUDGET'"
      if [[ -n "$MISMATCH" ]]; then
        red "baseline-environment-mismatch: $MISMATCH. Baseline header: ${BL_ENV_LINE:-<none>} / ${BL_K_LINE:-<none>}. Survivors NOT compared."
        finish
      fi
    fi
    while IFS=$'\t' read -r c1 _; do
      BL_ID[${#BL_ID[@]}]="$c1"
    done < <(tsv_rows "$BASELINE")
  fi
fi

# ----------------------------------------------------------------- PR deferral
# A guard is swept in the PR lane only when its kill set is a SINGLE FAST SUITE. A
# slow-list killer or a multi-suite union both defer wholesale: running a reduced kill set
# would grade mutants under a weaker criterion than the one that produced the baseline
# (manufacturing false reds on a merge-blocking lane), and running the full union blows
# the lane's time bound, since a SURVIVING mutant runs every killer.
PR_SWEPT=()
if [[ "$MODE" == "pr" ]]; then
  fast_count=0
  for g in "${SWEEP_GUARDS[@]}"; do
    ks="$(kill_set_for "$g")"
    n=0; for s in $ks; do n=$((n + 1)); done
    defer=""
    [[ $n -ne 1 ]] && defer="multi-suite union ($n killers)"
    if [[ -z "$defer" ]]; then
      for s in $ks; do is_slow "$s" && defer="slow suite ($s, $(suite_seconds "$s")s)"; done
    fi
    if [[ -z "$defer" && $fast_count -ge $PR_FAST_GUARD_CAP ]]; then
      defer="PR-lane cap ($PR_FAST_GUARD_CAP fast guards already swept)"
    fi
    if [[ -n "$defer" ]]; then
      emit_row "$g" "deferred-to-nightly" "${ks// /+}" 0 0 0 "" ""
      info "defer $g -> nightly: $defer"
    else
      fast_count=$((fast_count + 1))
      PR_SWEPT[${#PR_SWEPT[@]}]="$g"
    fi
  done
  SWEEP_GUARDS=()
  for g in ${PR_SWEPT[@]+"${PR_SWEPT[@]}"}; do SWEEP_GUARDS[${#SWEEP_GUARDS[@]}]="$g"; done
fi

# The full-sweep report accounts for the ENTIRE universe, excluded rows included (zero
# counts), so the merged report alone is the standing ranking. The rows are universe
# bookkeeping, not per-shard measurements, so ONE shard (the first) emits them — that is
# what keeps the merge a pure concatenation with no dedup of data rows. PR mode stays
# diff-scoped by design.
if [[ "$MODE" == "full" && "$SHARD_I" -eq 1 ]]; then
  for g in "${ALL_GUARDS[@]}"; do
    is_excluded "$g" && emit_row "$g" "excluded" "" 0 0 0 "" ""
  done
fi

# A SEED run with nothing to sweep still falls through: an empty shard must publish its
# headed (empty) baseline and slow list, or the merge reds on a missing shard artifact.
if [[ ${#SWEEP_GUARDS[@]} -eq 0 && $SEED -eq 0 ]]; then
  info "nothing left to sweep after deferral."
  finish
fi

# ------------------------------------------------------------- killer machinery
# Kill = ANY nonzero exit; crash-kills count as kills (nonzero is nonzero — the
# assertion-vs-crash diagnostic is deferred to #248).
#
# `</dev/null` isolates each killer's stdin. stdout and stderr were always redirected;
# stdin was not, so a killer inherited the harness's. 30 of the 48 swept guards contain a
# `read` loop, and a mutant that breaks one's input redirection leaves it reading the
# INHERITED stdin rather than its own. With stdin isolated the stray read hits EOF at
# once, the suite exits nonzero, and the mutant simply scores as killed.
#
# This was a real bug and is NOT the cause of the shard deaths it was first blamed for:
# the same three shards hung identically after it landed. The cause was an unbounded
# killer against a SPINNING guard — see the time bound below. Isolated stdin is in fact
# what makes that spin reachable at EOF, so the two are neighbors, not the same defect.
#
# TIME BOUND. A mutant can make its guard SPIN, and an unbounded killer then blocks the
# whole shard forever: no further `swept` line, death by job timeout with the log blob
# unfinalized and no artifact — undiagnosable by construction, which is how the same three
# shards died on two successive nightlies without yielding a single datapoint. The class is
# not exotic: `cmp-z` inverts the EOF-tolerance clause of this repo's standard read idiom
# (`while IFS= read -r line || [[ -n "$line" ]]` -> `|| [[ -z "$line" ]]`), which at EOF is
# permanently true, so the guard spins at 100% CPU.
#
# THREE live guards carry that idiom. K_BUDGET predicted exactly which shards died in the
# seed run (middle column), and it is also what each site is armed BY today (last column):
#   gen-statectl-validators.sh L213  cmp-z ord 1  shard 4 died               generic tier
#   predecessor-gate.sh        L85   cmp-z ord 1  shard 9 died (reproduced)  generic tier
#   scaffold-review-context.sh L69   cmp-z ord 5  shard 8 never mutated      catalog row
# The third was never safe, only out of budget — ordinal 5 against k=2 — and it is armed by
# the `scaffold-spin-at-eof` catalog row rather than by raising MUTATION_SWEEP_K, which
# would have armed every other guard's ordinals 3-5 at the same time for one named site. The
# budget is unchanged, so no baseline re-seed and no cache-key change follow. The general
# question of the budget itself is separate and still open.
# Shard 5 carries none of them and completes locally; its CI death is NOT explained by
# this defect, and the bound is what lets that run NAME whatever it hit instead.
#
# What made that third site invisible for two nightlies was not the budget but the REPORT:
# a guard with no applicable site and a guard whose sites all sit past k emitted the same
# silence. The sites_beyond_budget column (see emit_row) is what ended that, and it is the
# standing evidence any later decision about k should rest on.
#
# A timed-out killer scores as a KILL, the mutation-testing convention (Stryker and PIT
# both count a timeout as detected): the suite did surface the defect, and the alternative
# — scoring it a survivor — would red the build on a mutant nothing can ever kill. It is
# logged by name at every call site, so a timeout is visible DATA rather than a silent kill.
#
# EARLY EXIT is the third exit path and the only one that is a pure cost optimization: the
# verdict of a KILLED mutant is settled at the paired suite's first `FAIL:` line, so the
# group is reaped there rather than after every remaining case. Its soundness rests on an
# invariant the precheck ASSERTS on every run — a green suite emits no `FAIL:` line — rather
# than on the one-off corpus measurement that established it (63/63 suites, zero such lines).
# A suite that breaks the invariant is an unrunnable pair, loudly, because a suite that
# prints the trigger while passing would have every one of its guard's mutants scored KILLED
# on prose.
#
# `set -m` is what makes the watchdog able to reap the tree. It puts the backgrounded
# killer in its OWN process group, so `kill -9 -PID` takes the spinning GUARD — a
# grandchild — with it; killing the suite's pid alone leaves the guard burning a core and
# holding the sandbox. Verified on bash 5 and on stock bash 3.2, neither of which prints
# job-control noise for a background job in a non-interactive shell. `timeout(1)` is NOT
# used: it is absent from macOS, which is one of this repo's two CI lanes.
KILLER_TIMED_OUT=0
KILLER_EARLY=0            # 1 = this killer was reaped at its first FAIL: line
KILLER_BOUND_USED=0
KILLER_BOUND_KIND=""      # "time" | "procs" — which bound fired; "" when none did
KILLER_BOUND_PROCS=0      # group population observed when the process bound fired
CURRENT_KILLER_PGID=""

# Live process count in process group $1. `ps -A -o pgid=` is the portable intersection of
# BSD (macOS) and procps (ubuntu): both print one bare pgid per process, one per line.
# `grep -c` exits 1 on no match, so the count is read from stdout and the status ignored —
# an empty group is 0, not an error.
group_size() {
  ps -A -o pgid= 2>/dev/null | tr -d ' ' | grep -c "^$1\$"
}

# Reap a killer's whole process group. SIGSTOP FIRST is load-bearing against a FORKING
# mutant, not defensive habit: a single SIGKILL sweep races a tree that is still forking,
# and whatever is created between the signal and its delivery survives as an orphan that
# keeps forking for the rest of the shard — which is how a bounded killer can still leave
# a runner to die minutes later, on a guard the harness has already moved past. A stopped
# process cannot fork, so freeze the group, kill it, then CONFIRM it is gone, re-freezing
# each round for whatever was mid-fork when the last round landed.
#
# The pgid is our own child's pid, so `wait` first: until it is reaped the leader lingers
# as a zombie and `ps` still counts it, which would keep the confirm loop from ever
# converging. The attempt cap bounds this at ~5s so a race on a reused pid cannot turn
# into an unbounded signal loop against a group we no longer own.
reap_group() {
  local pgid="$1" i=0 n
  while [[ $i -lt 50 ]]; do
    kill -STOP -"$pgid" 2>/dev/null
    kill -9 -"$pgid" 2>/dev/null || kill -9 "$pgid" 2>/dev/null
    wait "$pgid" 2>/dev/null
    n="$(group_size "$pgid")"
    [[ "${n:-0}" -eq 0 ]] && return 0
    i=$((i + 1))
    sleep 0.1
  done
  return 1
}

# ------------------------------------------------------------------- sandbox pool
# `git worktree add --detach`, not `cp -R`: two suites need real git state
# (check-workflows-selftest cd's to the toplevel, derive-release-selftest diffs against
# the latest release tag), and a copied worktree's `.git` FILE would point two sandboxes at
# one metadata directory. The working tree is small and the object store is shared, so this
# is near-free. Selftests resolve their guard relative to their own location, so pairing
# survives the copy.
#
# ONE SANDBOX PER WORKER, created lazily. A worker restores its guard between items, so no
# two concurrently-running mutants share a tree — which is the whole of "no mutant observes
# another's mutation" — and disk stays bounded at pool x ~7MB rather than growing with the
# mutant count.
WORKDIR="$(mktemp -d -t mutation-sweep-work.XXXXXX)" || die "mktemp -d failed"
SANDBOXES=""
SANDBOX_N=0
POOL_PIDS=""
WORKER_TOKEN="main"
WORKER_PGID_FILE="$WORKDIR/pgid.0"
KILLER_LOG="$WORKDIR/killer.0.log"
KILLER_TMPDIR="$WORKDIR/tmp.0"
SB_CUR=""

# Guards whose pair could not run. Space-separated rather than an array because the shrink
# warn below needs membership, not order, and bash 3.2 has no associative arrays.
UNRUN_GUARDS=""

# WHY THE PRECHECK SNAPSHOTS ITS OWN OUTPUT. $KILLER_LOG is truncated by the NEXT killer and
# deleted with $WORKDIR on exit, so by the time the `unrunnable pair` red is emitted — a
# separate loop, after every suite has run — the evidence is already gone. Before this, that
# red carried a reason string and nothing else: a suite reaped by the OOM killer (rc=137 on a
# 2-core runner) and one with a genuinely failing case (rc=1) produced the identical line, so
# the class was undiagnosable in CI by construction and every occurrence died as "no idea".
PRE_LOG_LINES="${MUTATION_SWEEP_PRE_LOG_LINES:-40}"
pre_log_path() { printf '%s/pre.log.%s' "$WORKDIR" "$(printf '%s' "$1" | tr '/' '_')"; }
save_pre_log() { tail -n "$PRE_LOG_LINES" "$KILLER_LOG" > "$(pre_log_path "$1")" 2>/dev/null; }

# Both codes, deliberately: shellcheck renamed this diagnostic mid-version and the two
# releases disagree on where they hang it. >=0.10 reports SC2329 on the FUNCTION; 0.9,
# which is what `apt-get install shellcheck` still yields on the ubuntu runner, reports
# SC2317 on each command in the BODY. Suppressing only the newer code is clean locally
# and red in CI. A directive on the function line scopes to the whole body for both.
# shellcheck disable=SC2317,SC2329 # invoked indirectly by the EXIT/INT/TERM trap below
cleanup() {
  local p f
  # The in-flight killer runs in its OWN process group (see run_killer), so a Ctrl-C or a
  # SIGTERM aimed at this harness never reaches it. Without this the operator's interrupt
  # leaves a spinning guard burning a core and pinning the worktrees the loop below removes.
  # reap_group, not a bare kill: an interrupt can land while a FORKING mutant is in
  # flight, and that is exactly the case a single SIGKILL sweep loses to.
  [[ -n "${CURRENT_KILLER_PGID:-}" ]] && reap_group "$CURRENT_KILLER_PGID" >/dev/null 2>&1
  # Workers first, then whatever killer each one had in flight. The pgid FILES are what make
  # this survive a worker that was SIGKILLed before its own trap could run — without them an
  # interrupt during the pool would orphan one spinning guard per worker.
  for p in ${POOL_PIDS:-}; do kill -TERM "$p" 2>/dev/null; done
  if [[ -n "${POOL_PIDS:-}" ]]; then
    sleep 0.3
    for p in ${POOL_PIDS:-}; do kill -9 "$p" 2>/dev/null; done
    wait 2>/dev/null
  fi
  for f in "$WORKDIR"/pgid.*; do
    [[ -f "$f" ]] || continue
    p="$(cat "$f" 2>/dev/null)"
    [[ -n "${p:-}" ]] && reap_group "$p" >/dev/null 2>&1
  done
  for p in ${SANDBOXES:-}; do
    git worktree remove --force "$p" >/dev/null 2>&1
    rm -rf "$p" 2>/dev/null
  done
  rm -rf "$WORKDIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Grow the pool to $1 sandboxes. Serial by construction — `git worktree add` writes
# .git/worktrees, so concurrent adds would race the very metadata they register in.
sandbox_ensure() {
  local want="$1" p
  while [[ $SANDBOX_N -lt $want ]]; do
    p="$(mktemp -d -t mutation-sweep-sandbox.XXXXXX)" || { red "sandbox failure: mktemp -d failed"; return 1; }
    rmdir "$p" 2>/dev/null
    if ! git worktree add --detach "$p" HEAD >/dev/null 2>&1; then
      red "sandbox failure: git worktree add --detach failed"
      return 1
    fi
    SANDBOXES="${SANDBOXES:+$SANDBOXES }$p"
    SANDBOX_N=$((SANDBOX_N + 1))
  done
  return 0
}

sandbox_at() {
  local i=0 p
  for p in ${SANDBOXES:-}; do
    [[ $i -eq $1 ]] && { printf '%s' "$p"; return 0; }
    i=$((i + 1))
  done
  return 1
}

sandbox_ensure 1 || finish
SB0="$(sandbox_at 0)"

restore() { git -C "${2:-$SB0}" checkout -- "$1" 2>/dev/null; }

# Splice ONE mutated line back into the file. awk-with-a-file rather than `awk -v`,
# because -v mangles backslashes and these lines are dense with them.
# Mutants are applied by writing THROUGH the guard's existing inode (`cat >`), never by
# mv-ing a fresh file over it. A fresh inode is 0644, and with core.fileMode=true losing
# the exec bit is itself a git diff: the `git diff --quiet` byte-identity gates (no-op
# flip, catalog anchor drift) go dark, and any killer that precondition-gates on `-x`
# fails on EVERY mutant — false kills that report a weak suite as strong. The catalog
# tier below applies its mutants the same way for the same reason, and so does the pool
# worker when it installs an enumerated blob.
splice_line() {
  local file="$1" lineno="$2" replfile="$3" out
  out="$file.mut"
  awk -v n="$lineno" 'NR==FNR{repl=$0; next} FNR==n{print repl; next} {print}' \
    "$replfile" "$file" > "$out" && cat "$out" > "$file" && rm -f "$out"
}

# Run one killer inside this shell's sandbox.
#   $1 = suite relpath, $2 = wall-clock bound, $3 = 1 to allow early exit (default 1)
# Returns the suite's exit status, 124 on either bound, 125 on early exit.
run_killer() {
  local pid rc deadline poll=0 n bound="${2:-$KILLER_TIMEOUT_S}" early="${3:-1}"
  KILLER_TIMED_OUT=0
  KILLER_EARLY=0
  KILLER_BOUND_KIND=""
  KILLER_BOUND_PROCS=0
  KILLER_BOUND_USED="$bound"
  [[ "$EARLY_EXIT" == "1" ]] || early=0
  : > "$KILLER_LOG"
  # A reaped suite never runs its own `trap ... EXIT` cleanup, so its mktemp dirs would leak
  # once per kill. Pointing TMPDIR at a directory this harness owns turns that into one
  # unconditional rm — which is also what keeps sandbox disk reclaimed on the reap paths.
  rm -rf "$KILLER_TMPDIR" 2>/dev/null
  mkdir -p "$KILLER_TMPDIR" 2>/dev/null
  set -m
  ( cd "$SB_CUR" && TMPDIR="$KILLER_TMPDIR" bash "$1" ) > "$KILLER_LOG" 2>&1 </dev/null &
  pid=$!
  set +m
  # The job is its own process-group leader, so pgid == pid. Published both in-process (for
  # this shell's own trap) and to a file (for the PARENT's cleanup, which is the only thing
  # left if a worker is SIGKILLed).
  CURRENT_KILLER_PGID="$pid"
  printf '%s' "$pid" > "$WORKER_PGID_FILE" 2>/dev/null
  deadline=$(( $(date +%s) + bound ))
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$(date +%s)" -ge "$deadline" ]]; then
      # Re-check rather than kill blind: the suite may have exited inside the poll
      # interval, and reporting a finished run as timed out would fabricate a kill.
      kill -0 "$pid" 2>/dev/null || break
      reap_group "$pid"
      CURRENT_KILLER_PGID=""; : > "$WORKER_PGID_FILE" 2>/dev/null
      KILLER_TIMED_OUT=1
      KILLER_BOUND_KIND="time"
      return 124
    fi
    # Sampled every ~1s rather than every poll: `ps -A` and a `grep` over a growing log both
    # cost far more than `date`, and neither a forking tree nor a failing case needs
    # millisecond granularity to be caught.
    poll=$((poll + 1))
    if [[ $((poll % 5)) -eq 0 ]]; then
      if [[ $early -eq 1 ]] && grep -q -- "$FAIL_PATTERN" "$KILLER_LOG" 2>/dev/null; then
        kill -0 "$pid" 2>/dev/null || break
        reap_group "$pid"
        CURRENT_KILLER_PGID=""; : > "$WORKER_PGID_FILE" 2>/dev/null
        KILLER_EARLY=1
        return 125
      fi
      n="$(group_size "$pid")"
      if [[ "${n:-0}" -gt "$KILLER_MAX_PROCS" ]] 2>/dev/null; then
        reap_group "$pid"
        CURRENT_KILLER_PGID=""; : > "$WORKER_PGID_FILE" 2>/dev/null
        KILLER_TIMED_OUT=1
        KILLER_BOUND_KIND="procs"
        KILLER_BOUND_PROCS="$n"
        return 124
      fi
    fi
    sleep 0.2
  done
  wait "$pid"; rc=$?
  CURRENT_KILLER_PGID=""; : > "$WORKER_PGID_FILE" 2>/dev/null
  # A suite that finished on its own can still have printed the pattern before exiting; the
  # exit status is what decides, exactly as before. Early exit only ever removes waiting.
  return "$rc"
}

# Every non-plain kill reports itself identically across both mutant tiers, so the wording
# lives here once. $1 = mutant id, $2 = suite, $3 = kind, $4 = the wall-clock bound in
# force, $5 = the population observed. The time-bound line keeps its exact historical shape
# — the companion selftest parses `killer timeout (Ns exceeded` out of it to prove the bound
# scales per suite.
report_bound_hit() {
  if [[ "$3" == "procs" ]]; then
    info "killer process bound ($5 processes exceeded $KILLER_MAX_PROCS, scored as KILLED): $1 via $2 — the mutant most likely made the guard FORK without bound."
  elif [[ "$3" == "early" ]]; then
    info "early exit (first '$FAIL_PATTERN' line, scored as KILLED): $1 via $2 — the remaining cases were not run."
  else
    info "killer timeout (${4}s exceeded, scored as KILLED): $1 via $2 — the mutant most likely made the guard spin."
  fi
}

# Cheapest-first is a pure cost optimization: it short-circuits on a KILL, so the
# any-suite kill criterion is unchanged. A surviving mutant still runs every killer.
order_killers() {
  local ks="$1" s
  for s in $ks; do printf '%s\t%s\n' "$(suite_seconds "$s")" "$s"; done | sort -n | cut -f2
}

TOTAL_SURVIVORS=""
add_survivor() { TOTAL_SURVIVORS="${TOTAL_SURVIVORS:+$TOTAL_SURVIVORS }$1"; }

# ---------------------------------------------------------------- pool mechanics
# Static round-robin over a manifest rather than a claimed queue: bash 3.2 has no `wait -n`
# and no lock primitive worth the machinery here, and the items interleave across guards so
# the imbalance a contiguous split would cause does not arise. Determinism of the RESULT does
# not depend on any of this — every worker writes one result file per item and the
# aggregation reads them back in item order.

# shellcheck disable=SC2317,SC2329 # invoked indirectly by the worker's own trap
worker_trap() {
  local p
  [[ -s "$WORKER_PGID_FILE" ]] || return 0
  p="$(cat "$WORKER_PGID_FILE" 2>/dev/null)"
  [[ -n "${p:-}" ]] && reap_group "$p" >/dev/null 2>&1
  return 0
}

# $1 = worker index (0-based), $2 = pool size, $3 = manifest
pool_worker() {
  local w="$1" n="$2" manifest="$3" pos=0 line
  SB_CUR="$(sandbox_at "$w")"
  WORKER_TOKEN="$w"
  WORKER_PGID_FILE="$WORKDIR/pgid.$w"
  KILLER_LOG="$WORKDIR/killer.$w.log"
  KILLER_TMPDIR="$WORKDIR/tmp.$w"
  : > "$WORKER_PGID_FILE"
  trap worker_trap EXIT INT TERM
  while IFS= read -r line; do
    [[ $((pos % n)) -eq $w ]] && do_mutant_item "$line"
    pos=$((pos + 1))
  done < "$manifest"
  rm -rf "$KILLER_TMPDIR" 2>/dev/null
  return 0
}

# $1 = pool size, $2 = manifest. Returns 1 only when the pool could not be built.
run_pool() {
  local n="$1" manifest="$2" total w
  total="$(grep -c '' "$manifest" 2>/dev/null)" || total=0
  [[ "${total:-0}" -gt 0 ]] || return 0
  [[ $n -gt $total ]] && n=$total
  sandbox_ensure "$n" || return 1
  POOL_PIDS=""
  w=0
  while [[ $w -lt $n ]]; do
    pool_worker "$w" "$n" "$manifest" &
    POOL_PIDS="${POOL_PIDS:+$POOL_PIDS }$!"
    w=$((w + 1))
  done
  wait
  POOL_PIDS=""
  return 0
}

# --------------------------------------------------------------- pool work item
# Line: idx <TAB> sid <TAB> guard <TAB> ordered kill set <TAB> blob <TAB> key.
# Writes $WORKDIR/verdict.<idx> as one record line. Cache hits never reach here — they are
# resolved in the serial probe below, because knowing them is what decides whether a guard
# needs its precheck run at all.
do_mutant_item() {
  local line="$1" idx sid guard ks blob key rec s got_kill rc
  local hit_suite hit_kind hit_bound hit_procs
  IFS="$TAB" read -r idx sid guard ks blob key <<EOF
$line
EOF
  cat "$blob" > "$SB_CUR/$guard"
  got_kill=0; hit_suite="-"; hit_kind="plain"; hit_bound=0; hit_procs=0
  for s in $ks; do
    run_killer "$s" "$(killer_bound_for "$s")"; rc=$?
    if [[ $rc -ne 0 ]]; then
      got_kill=1
      hit_suite="$s"
      hit_bound="$KILLER_BOUND_USED"
      hit_procs="$KILLER_BOUND_PROCS"
      if [[ $KILLER_EARLY -eq 1 ]]; then
        hit_kind="early"
      elif [[ $KILLER_TIMED_OUT -eq 1 ]]; then
        hit_kind="$KILLER_BOUND_KIND"
      fi
      break
    fi
  done
  restore "$guard" "$SB_CUR"
  if [[ $got_kill -eq 1 ]]; then
    rec="v1${TAB}killed${TAB}$hit_kind${TAB}$hit_suite${TAB}$hit_bound${TAB}$hit_procs"
  else
    rec="v1${TAB}survived${TAB}plain${TAB}-${TAB}0${TAB}0"
  fi
  cache_put "$key" "$rec"
  printf '%s\n' "$rec" > "$WORKDIR/verdict.$idx"
  return 0
}

# ------------------------------------------------------------- serial re-verify
# THE ORACLE. A baseline-absent survivor is the only thing that reds this lane, and the pool
# has been observed fabricating one: a mutant its own paired selftest demonstrably kills was
# scored SURVIVED, on two guards in one nightly, while a THIRD guard carrying the identical
# idiom behind the identical assertion killed it in the same run. No single behavior of the
# mutated construct explains both outcomes, so the verdict was not a fact about the code.
#
# The false-SURVIVED path inside the pool is not isolated. This does not try to isolate it —
# it makes the class self-healing instead: before a survivor is allowed to red anything, it is
# re-derived SERIALLY, on a sandbox no worker has touched, because the pool is the suspect and
# an oracle must not use it. Cheap by construction: it runs only for a survivor that would red
# (zero of them on a green run), never on the ordinary path.
#
# The FULL ordered kill set is re-run, not one suite. "Survived" means no suite in the set
# killed, so re-running one is not the same question.
#
# Scope, and the reason is not only cost: a mutant served from the verdict CACHE is out, because
# its verdict was not produced by this run's pool (naming it a pool disagreement would accuse a
# path the pool never touched), the cache is inert in every enforcing lane and in seed mode, and
# — the load-bearing half — a pool-scored mutant is exactly the set whose kill suites this run
# prechecked GREEN. A guard with no uncached mutant is never prechecked, so feeding one to the
# oracle would let a broken suite fabricate the correction it is supposed to detect.
REVERIFY_SB=""
REVERIFY_REC=""
REVERIFY_KEY=""

# A sandbox of its own, appended past the pool's, created on first use so a green run pays
# nothing. `git worktree add` is serial by construction (see sandbox_ensure) and this runs in
# the main shell after `wait`, so there is nothing to race.
reverify_sandbox() {
  [[ -n "$REVERIFY_SB" ]] && return 0
  sandbox_ensure $((SANDBOX_N + 1)) || return 1
  REVERIFY_SB="$(sandbox_at $((SANDBOX_N - 1)))" || return 1
  [[ -n "$REVERIFY_SB" ]] || return 1
  return 0
}

# A survivor is re-verified when it would red the lane. Seed mode re-verifies every pool-scored
# survivor: it is the one lane that writes a spurious survivor into the committed baseline
# permanently and silently, so the ~20 serial suite runs per shard buy the baseline's integrity.
reverify_needed() {
  [[ $SEED -eq 1 ]] && return 0
  in_baseline "$1" && return 1
  return 0
}

# $1 = mutant index. True when this run's POOL produced the verdict. A cache hit is resolved in
# the serial probe and never reaches the pool, so it is out of scope — see the note above.
pool_scored() {
  awk -F"$TAB" -v i="$1" '$1==i {found=1; exit} END {exit !found}' "$WORKDIR/mut.final" 2>/dev/null
}

# $1 = mutant index. Returns 0 when the serial re-run KILLS what the pool called survived,
# publishing the corrected record in REVERIFY_REC and its cache key in REVERIFY_KEY. Returns 1
# when the pool's verdict stands — which includes every case where the re-run could not be
# performed at all, because an oracle that cannot answer must not overturn anything.
reverify_survivor() {
  local idx="$1" row guard ks blob key s rc got
  local hit_suite hit_kind hit_bound hit_procs
  local sv_sb sv_log sv_pgid sv_tmp sv_token
  REVERIFY_REC=""; REVERIFY_KEY=""
  # mut.final rather than mut.todo: same six fields, already filtered to the mutants this run's
  # pool actually scored, which is precisely the re-verify set.
  row="$(awk -F"$TAB" -v i="$idx" '$1==i {print; exit}' "$WORKDIR/mut.final" 2>/dev/null)"
  [[ -n "$row" ]] || return 1
  IFS="$TAB" read -r _ _ guard ks blob key <<EOF
$row
EOF
  [[ -n "$guard" && -f "$blob" ]] || return 1
  reverify_sandbox || return 1

  # run_killer reads its sandbox, log, pgid file and TMPDIR from globals the pool worker sets
  # per worker. Borrow them under a token of their own and hand them back, so nothing later in
  # this shell inherits the oracle's.
  sv_sb="$SB_CUR"; sv_log="$KILLER_LOG"; sv_pgid="$WORKER_PGID_FILE"
  sv_tmp="$KILLER_TMPDIR"; sv_token="$WORKER_TOKEN"
  SB_CUR="$REVERIFY_SB"
  KILLER_LOG="$WORKDIR/killer.rv.log"
  WORKER_PGID_FILE="$WORKDIR/pgid.rv"
  KILLER_TMPDIR="$WORKDIR/tmp.rv"
  WORKER_TOKEN="rv"
  : > "$WORKER_PGID_FILE"

  cat "$blob" > "$SB_CUR/$guard"
  # Counted here rather than at the call site, so the run's own timing line stays an honest
  # record of paired-suite executions even on the paths where the oracle declines to run. One
  # per re-derived VERDICT, matching how the pool counts its own.
  SUITE_RUNS=$((SUITE_RUNS + 1))
  got=0; hit_suite="-"; hit_kind="plain"; hit_bound=0; hit_procs=0
  for s in $ks; do
    run_killer "$s" "$(killer_bound_for "$s")"; rc=$?
    if [[ $rc -ne 0 ]]; then
      got=1
      hit_suite="$s"
      hit_bound="$KILLER_BOUND_USED"
      hit_procs="$KILLER_BOUND_PROCS"
      if [[ $KILLER_EARLY -eq 1 ]]; then
        hit_kind="early"
      elif [[ $KILLER_TIMED_OUT -eq 1 ]]; then
        hit_kind="$KILLER_BOUND_KIND"
      fi
      break
    fi
  done
  restore "$guard" "$SB_CUR"
  rm -rf "$KILLER_TMPDIR" 2>/dev/null

  SB_CUR="$sv_sb"; KILLER_LOG="$sv_log"; WORKER_PGID_FILE="$sv_pgid"
  KILLER_TMPDIR="$sv_tmp"; WORKER_TOKEN="$sv_token"

  [[ $got -eq 1 ]] || return 1
  REVERIFY_REC="v1${TAB}killed${TAB}$hit_kind${TAB}$hit_suite${TAB}$hit_bound${TAB}$hit_procs"
  REVERIFY_KEY="$key"
  return 0
}

# ===================================================================== PHASE 1
# ENUMERATE, serially, in sandbox 0. Cheap — sed, awk, `bash -n`, `git diff --quiet` — and
# it is where every skip and every catalog red is decided, in the historical order. What it
# produces is a work item carrying the MUTATED GUARD BYTES, so the pool never re-derives a
# mutant and two workers can hold different mutants of the same guard at once.
#
# Enumeration runs BEFORE the precheck, which is a reordering with a reason: a guard whose
# every mutant is already cached must skip its precheck entirely, and "every mutant" is not
# knowable until the mutants exist. A precheck IS a paired-suite execution, so a run that
# still paid for one could not honestly claim to have executed none.
GL_GUARD=(); GL_KS=(); GL_KSORD=(); GL_UNRUN=(); GL_APPLIED=(); GL_FIRST=(); GL_COUNT=()
GL_BEYOND=()
MUT_SID=()
: > "$WORKDIR/mut.todo"
IDX=0
gi=0
for guard in ${SWEEP_GUARDS[@]+"${SWEEP_GUARDS[@]}"}; do
  KS="$(kill_set_for "$guard")"
  KSORD="$(order_killers "$KS" | tr '\n' ' ')"
  GL_GUARD[${#GL_GUARD[@]}]="$guard"
  GL_KS[${#GL_KS[@]}]="$KS"
  GL_KSORD[${#GL_KSORD[@]}]="$KSORD"
  GL_UNRUN[${#GL_UNRUN[@]}]=""
  GL_APPLIED[${#GL_APPLIED[@]}]=0
  GL_FIRST[${#GL_FIRST[@]}]="$IDX"
  GL_COUNT[${#GL_COUNT[@]}]=0
  GL_BEYOND[${#GL_BEYOND[@]}]=""
  GFILE="$SB0/$guard"
  BEYOND=""

  # One suites-sha per guard: the kill set's suite bytes, hashed in kill order. This is the
  # half of the key that makes the memo sound across test changes — a new case in ANY paired
  # suite changes it, so every cached verdict for the guard is a miss rather than a stale
  # SURVIVED.
  SSHA=""
  if [[ "$CACHE_ENABLED" == "1" ]]; then
    for s in $KSORD; do SSHA="$SSHA$(sha_file "$SB0/$s")"; done
    SSHA="$(printf '%s' "$SSHA" | sha_stdin)"
  fi

  # ---- generic tier
  op_i=0
  while [[ $op_i -lt ${#OP_ID[@]} ]]; do
    opid="${OP_ID[$op_i]}"; opmatch="${OP_MATCH[$op_i]}"; opflip="${OP_FLIP[$op_i]}"
    op_i=$((op_i + 1))
    # Sites are enumerated ONCE, up front, with `--` terminating option parsing: a match
    # may begin with a hyphen (two committed operators do), and without the terminator
    # grep reads it as OPTIONS — one such match enumerated every line containing 'q', the
    # other errored outright, and a stderr redirect made both failure modes silent. grep
    # exit >= 2 (as opposed to 1, the normal no-match exit) means the match did not run
    # as a pattern at all, which must be LOUD: a silently dead operator reports every
    # guard as clean against a mutation class that was never applied.
    SITES="$(grep -nE -- "$opmatch" "$GFILE" 2>&1)"; GREP_RC=$?
    if [[ $GREP_RC -ge 2 ]]; then
      red "operator match does not enumerate (grep exit $GREP_RC): $opid on $guard — $SITES"
      continue
    fi
    ordinal=0; used=0; beyond=0
    while IFS= read -r lineno; do
      [[ -n "$lineno" ]] || continue
      ordinal=$((ordinal + 1))
      # keep counting ordinals; stop mutating. The declined sites are TALLIED rather than
      # dropped: they are the difference between a guard with no applicable site and a
      # guard that is dark, and the report could not previously say which.
      [[ $used -ge $K_BUDGET ]] && { beyond=$((beyond + 1)); continue; }
      REPL="$(mktemp -t mutation-sweep-line.XXXXXX)"
      awk -v n="$lineno" 'NR==n' "$GFILE" | sed -E -e "$opflip" > "$REPL"
      splice_line "$GFILE" "$lineno" "$REPL"
      rm -f "$REPL"
      if ! bash -n "$GFILE" 2>/dev/null; then
        # A generic mutant that will not parse is a HARNESS ARTIFACT, not a finding:
        # sites are machine-enumerated, so a blind flip can land somewhere it cannot be
        # expressed. Skipped and logged, never red. (Catalog mutants are the opposite.)
        info "skip (bash -n invalid, harness artifact): $guard::$opid::$ordinal"
        restore "$guard"; continue
      fi
      if git -C "$SB0" diff --quiet -- "$guard"; then
        info "skip (no-op flip): $guard::$opid::$ordinal"
        restore "$guard"; continue
      fi
      used=$((used + 1))
      GL_APPLIED[gi]=$(( GL_APPLIED[gi] + 1 ))
      sid="$guard::$opid::$ordinal"
      cp "$GFILE" "$WORKDIR/blob.$IDX"
      MKEY=""
      [[ "$CACHE_ENABLED" == "1" ]] && MKEY="$(cache_key "$(sha_file "$GFILE")" "$SSHA")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$IDX" "$sid" "$guard" "$KSORD" "$WORKDIR/blob.$IDX" "$MKEY" >> "$WORKDIR/mut.todo"
      MUT_SID[IDX]="$sid"
      IDX=$((IDX + 1))
      restore "$guard"
    done <<< "$(printf '%s\n' "$SITES" | cut -d: -f1)"
    [[ $beyond -gt 0 ]] && BEYOND="${BEYOND:+$BEYOND+}$opid:$beyond"
  done

  # ---- catalog tier
  cat_i=0
  while [[ $cat_i -lt ${#CAT_ID[@]} ]]; do
    cid="${CAT_ID[$cat_i]}"; cguard="${CAT_GUARD[$cat_i]}"; csed="${CAT_SED[$cat_i]}"
    cat_i=$((cat_i + 1))
    [[ "$cguard" == "$guard" ]] || continue
    # A sed that ERRORS and a sed that simply does not match are different bugs and must
    # not be conflated: swallowing the exit code made an invalid program look like anchor
    # drift, which sent the reader hunting for a moved anchor that had never moved.
    SED_ERR="$(sed -E -e "$csed" "$GFILE" 2>&1 > "$GFILE.mut")"; SED_RC=$?
    if [[ $SED_RC -ne 0 ]]; then
      rm -f "$GFILE.mut"
      red "catalog sed program is invalid: catalog::$cid on $guard — $SED_ERR"
      restore "$guard"; continue
    fi
    cat "$GFILE.mut" > "$GFILE" && rm -f "$GFILE.mut"   # write-through, not mv: see splice_line
    # LOUD anchor-drift, the check-lockstep-pairs-selftest convention: a hand-authored sed
    # that no longer applies is a BUG IN THIS FILE, not a passing mutant.
    if git -C "$SB0" diff --quiet -- "$guard"; then
      red "catalog anchor drift: catalog::$cid left $guard byte-identical — the sed anchor has moved; re-anchor the row in the PR that moved it."
      restore "$guard"; continue
    fi
    if ! bash -n "$GFILE" 2>/dev/null; then
      red "catalog mutant is bash -n invalid: catalog::$cid on $guard"
      restore "$guard"; continue
    fi
    GL_APPLIED[gi]=$(( GL_APPLIED[gi] + 1 ))
    cp "$GFILE" "$WORKDIR/blob.$IDX"
    MKEY=""
    [[ "$CACHE_ENABLED" == "1" ]] && MKEY="$(cache_key "$(sha_file "$GFILE")" "$SSHA")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$IDX" "catalog::$cid" "$guard" "$KSORD" "$WORKDIR/blob.$IDX" "$MKEY" >> "$WORKDIR/mut.todo"
    MUT_SID[IDX]="catalog::$cid"
    IDX=$((IDX + 1))
    restore "$guard"
  done

  GL_COUNT[gi]=$(( IDX - GL_FIRST[gi] ))
  GL_BEYOND[gi]="$BEYOND"
  gi=$((gi + 1))
done

# ===================================================================== PHASE 2
# CACHE PROBE, serially. A hit is written straight to its verdict file; a miss goes to the
# pool manifest. This is also what decides which guards still need a precheck.
: > "$WORKDIR/mut.run"
GL_MISSES=()
i=0
while [[ $i -lt ${#GL_GUARD[@]} ]]; do GL_MISSES[${#GL_MISSES[@]}]=0; i=$((i + 1)); done
while IFS="$TAB" read -r idx sid guard ks blob key; do
  if [[ -n "$key" ]] && rec="$(cache_get "$key")"; then
    printf '%s\n' "$rec" > "$WORKDIR/verdict.$idx"
    CACHE_HITS=$((CACHE_HITS + 1))
    continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$idx" "$sid" "$guard" "$ks" "$blob" "$key" >> "$WORKDIR/mut.run"
  i=0
  while [[ $i -lt ${#GL_GUARD[@]} ]]; do
    [[ "${GL_GUARD[$i]}" == "$guard" ]] && { GL_MISSES[i]=$(( GL_MISSES[i] + 1 )); break; }
    i=$((i + 1))
  done
done < "$WORKDIR/mut.todo"

# ===================================================================== PHASE 3
# PRECHECK, serially, once per DISTINCT suite, and only for suites a guard with at least one
# uncached mutant needs. Serial and hoisted on purpose: these timings set every killer bound
# and feed mutation-slow-suites.tsv, so taking them under the mutant pool's contention would
# measure the pool rather than the suite.
#
# Every killer must be green on the UNMUTATED sandbox before any of its guard's mutants can
# be scored: a broken or environment-starved suite must never be able to report its guard as
# fully killed. A green suite that PRINTS the early-exit trigger is the same class of fault,
# because every mutant of its guard would then be scored KILLED on prose.
SB_CUR="$SB0"
PRE_OK=""      # suites that passed
PRE_BAD=""     # suites that failed; their reasons live one-per-line in $WORKDIR/pre.why,
               # in a FILE rather than a packed string, because a reason is a sentence and a
               # space-separated list would split it on its first word.
: > "$WORKDIR/pre.why"
# A guard with NO uncached mutant is not prechecked, and a guard with no mutants at all is
# the vacuous case of that. Two consequences, both deliberate: a mutant-less guard no longer
# yields an `unrunnable pair` red (nothing was going to be scored from it either), and its
# suite contributes no timing — which is why SEED mode, the canonical measurement that
# publishes mutation-slow-suites.tsv, prechecks everything regardless.
i=0
while [[ $i -lt ${#GL_GUARD[@]} ]]; do
  gi="$i"; i=$((i + 1))
  [[ $SEED -eq 1 || "${GL_MISSES[$gi]}" -gt 0 ]] || continue
  for s in ${GL_KSORD[$gi]}; do
    case " $PRE_OK $PRE_BAD " in *" $s "*) continue ;; esac
    t0="$(date +%s)"
    SUITE_RUNS=$((SUITE_RUNS + 1))
    # Early exit is DISARMED here: this run is what decides whether the trigger can be
    # trusted for this suite at all, so reading it would beg the question.
    run_killer "$s" "$KILLER_TIMEOUT_S" 0; krc=$?
    if [[ $krc -eq 0 ]]; then
      if grep -q -- "$FAIL_PATTERN" "$KILLER_LOG" 2>/dev/null; then
        PRE_BAD="${PRE_BAD:+$PRE_BAD }$s"
        save_pre_log "$s"
        printf '%s\t%s\n' "$s" "prints '$FAIL_PATTERN' while PASSING, which would score every mutant of its guard as an early-exit KILL on prose" >> "$WORKDIR/pre.why"
        continue
      fi
      t1="$(date +%s)"
      MEASURED="${MEASURED:-}"$'\n'"$s	$((t1 - t0))"
      # SLOW-LIST DRIFT, WARNED HERE RATHER THAN IN THE REPORT. A suite that has grown past
      # the threshold while absent from the committed list keeps its guard in the PR lane,
      # where every mutant that makes the guard spin costs the full killer bound — enough of
      # them and the job dies on its own ceiling BEFORE finish() ever runs, so a warn deferred
      # to the report is precisely the one nobody sees. lean-gate-selftest.sh reached 143s
      # this way and took three PR runs with it, each reading only as "timed out after 15
      # minutes". Emitting at measurement time is what makes the diagnosis outlive the
      # timeout it diagnoses. Warn, never red: the list is a cost record, and a stale row
      # costs wall clock, not correctness.
      if [[ $((t1 - t0)) -ge $SLOW_THRESHOLD_S ]] && ! is_slow "$s"; then
        warn "slow-list drift: $s measured $((t1 - t0))s (>= ${SLOW_THRESHOLD_S}s) but tools/mutation-slow-suites.tsv does not record it at or above that bar, so its guard is still swept in the PR lane. Add or update the row by ordinary PR."
      fi
      PRE_OK="${PRE_OK:+$PRE_OK }$s"
      continue
    fi
    # A killer that blows a bound on the UNMUTATED tree is a different bug from one that
    # merely exits nonzero, and the operator needs to be told which they have — including
    # WHICH bound, since a suite that forks past the population bound with no mutant applied
    # is a defect in the suite, not a slow machine.
    if [[ $KILLER_TIMED_OUT -eq 1 && "$KILLER_BOUND_KIND" == "procs" ]]; then
      why="exceeded the ${KILLER_MAX_PROCS}-process killer bound at $KILLER_BOUND_PROCS processes against the unmutated sandbox"
    elif [[ $KILLER_TIMED_OUT -eq 1 ]]; then
      why="exceeded the ${KILLER_TIMEOUT_S}s killer bound against the unmutated sandbox"
    else
      # The STATUS, not just "nonzero". 137/143 name a reaped process (the runner ran out of
      # memory) and separate it from a suite whose own case failed — the single distinction
      # that decides whether the next move is a code fix or a capacity one.
      why="does not exit 0 against the unmutated sandbox (exit $krc)"
    fi
    PRE_BAD="${PRE_BAD:+$PRE_BAD }$s"
    save_pre_log "$s"
    printf '%s\t%s\n' "$s" "$why" >> "$WORKDIR/pre.why"
  done
done

# Map suite verdicts back onto guards, in guard order.
i=0
while [[ $i -lt ${#GL_GUARD[@]} ]]; do
  gi="$i"; i=$((i + 1))
  [[ $SEED -eq 1 || "${GL_MISSES[$gi]}" -gt 0 ]] || continue
  for s in ${GL_KSORD[$gi]}; do
    case " $PRE_BAD " in
      *" $s "*)
        GL_UNRUN[gi]="$s"
        UNRUN_GUARDS="${UNRUN_GUARDS:+$UNRUN_GUARDS }${GL_GUARD[$gi]}"
        why="$(awk -F'\t' -v s="$s" '$1==s {print $2; exit}' "$WORKDIR/pre.why")"
        red "unrunnable pair: $s $why (guard ${GL_GUARD[$gi]}). Its mutants are NOT scored."
        # Nothing was scored for this guard, so its baseline rows are UNDECIDABLE this run.
        # Said out loud because the shrink warn below now stays silent about them, and a
        # silence the operator cannot account for reads as "the rows are fine".
        detail "its baseline rows are undecidable this run — not reported as killed."
        pl="$(pre_log_path "$s")"
        if [[ -s "$pl" ]]; then
          detail "---- last $PRE_LOG_LINES line(s) of $s ----"
          while IFS= read -r pline || [[ -n "$pline" ]]; do detail "| $pline"; done < "$pl"
          detail "---- end $s ----"
        else
          detail "(it produced no output)"
        fi
        break
        ;;
    esac
  done
done

# Drop every mutant belonging to an unrunnable guard before the pool sees it.
: > "$WORKDIR/mut.final"
while IFS="$TAB" read -r idx sid guard ks blob key; do
  skip=0
  i=0
  while [[ $i -lt ${#GL_GUARD[@]} ]]; do
    if [[ "${GL_GUARD[$i]}" == "$guard" ]]; then
      [[ -n "${GL_UNRUN[$i]}" ]] && skip=1
      break
    fi
    i=$((i + 1))
  done
  [[ $skip -eq 1 ]] && continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$idx" "$sid" "$guard" "$ks" "$blob" "$key" >> "$WORKDIR/mut.final"
done < "$WORKDIR/mut.run"

# ===================================================================== PHASE 4
POOL_TOTAL="$(grep -c '' "$WORKDIR/mut.final" 2>/dev/null)" || POOL_TOTAL=0
SUITE_RUNS=$(( SUITE_RUNS + POOL_TOTAL ))
info "pool: $JOBS worker(s), $POOL_TOTAL mutant(s) to score, $CACHE_HITS served from cache."
run_pool "$JOBS" "$WORKDIR/mut.final" || finish

# ===================================================================== PHASE 5
# AGGREGATE, serially, in item order, so the report is a function of the work list and
# nothing else — which is exactly what makes a parallel run's survivor set provably the
# serial one.
i=0
while [[ $i -lt ${#GL_GUARD[@]} ]]; do
  guard="${GL_GUARD[$i]}"
  KS="${GL_KS[$i]}"
  gi="$i"
  i=$((i + 1))
  if [[ -n "${GL_UNRUN[$gi]}" ]]; then
    emit_row "$guard" "swept" "${KS// /+}" 0 0 0 "" "${GL_BEYOND[$gi]}"
    continue
  fi
  applied="${GL_APPLIED[$gi]}"; killed=0; survived=0; survivors=""
  j="${GL_FIRST[$gi]}"; jend=$(( GL_FIRST[gi] + GL_COUNT[gi] ))
  while [[ $j -lt $jend ]]; do
    sid="${MUT_SID[$j]}"
    vf="$WORKDIR/verdict.$j"
    if [[ ! -f "$vf" ]]; then
      red "verdict lost: no result for $sid — a pool worker died before publishing."
      j=$((j + 1)); continue
    fi
    IFS="$TAB" read -r _ verdict vkind vsuite vbound vprocs < "$vf"
    # The oracle runs HERE — inside the aggregation, before the verdict is counted — and not
    # beside the exit contract below, which is the only placement that makes a correction
    # coherent everywhere at once. The counts, the survivor_ids in the report row,
    # TOTAL_SURVIVORS, the seed baseline (written from it, and BEFORE the exit contract is
    # ever reached) and the exit contract itself are then all derived from the corrected
    # verdict by construction rather than patched afterwards.
    if [[ "$verdict" == "survived" ]] && reverify_needed "$sid" && pool_scored "$j"; then
      info "re-verifying survivor serially, outside the pool: $sid"
      if reverify_survivor "$j"; then
        red "pool disagreement: $sid was scored SURVIVED by the worker pool but is KILLED by a serial re-run of the same kill set outside it — the harness is at fault, not the guard. Reporting the corrected KILLED verdict; do NOT add a baseline row for this mutant."
        printf '%s\n' "$REVERIFY_REC" > "$vf"
        cache_put "$REVERIFY_KEY" "$REVERIFY_REC"
        IFS="$TAB" read -r _ verdict vkind vsuite vbound vprocs < "$vf"
      else
        info "serial re-run agrees: $sid really does survive its kill set."
      fi
    fi
    [[ "$vkind" != "plain" ]] && report_bound_hit "$sid" "$vsuite" "$vkind" "$vbound" "$vprocs"
    if [[ "$verdict" == "killed" ]]; then
      killed=$((killed + 1))
    else
      survived=$((survived + 1))
      survivors="${survivors:+$survivors,}$sid"
      add_survivor "$sid"
    fi
    j=$((j + 1))
  done
  emit_row "$guard" "swept" "${KS// /+}" "$applied" "$killed" "$survived" "$survivors" "${GL_BEYOND[$gi]}"
  info "swept $guard — applied=$applied killed=$killed survived=$survived"
done

cache_prune

# --------------------------------------------------------------- seed artifacts
if [[ $SEED -eq 1 ]]; then
  OUT="${BASELINE_OUT:-$BASELINE}"
  {
    echo "# mutation-baseline.tsv — survivors accepted as known, produced by the canonical seed run."
    echo "# A survivor listed here is REPORT-ONLY. A survivor NOT listed here is a red build."
    echo "# An EMPTY baseline (headers only) is valid; a MISSING baseline in an enforcing run is infra red."
    echo "# environment: ubuntu-latest SKIP_STRESS=1"
    echo "# k=$K_BUDGET"
    echo "#"
    echo "# survivor_id<TAB>note"
    for sid in $TOTAL_SURVIVORS; do printf '%s\tseeded by the canonical seed run\n' "$sid"; done
  } > "$OUT"
  info "seed: baseline -> $OUT"

  SOUT="${SLOW_OUT:-$SLOW_SUITES}"
  {
    echo "# mutation-slow-suites.tsv — paired suites measured at or above ${SLOW_THRESHOLD_S}s in the canonical"
    echo "# environment. The PR lane defers any guard whose killer appears here."
    echo "# Membership drift is a report warn, never red; this committed copy updates by ordinary PR."
    echo "# A paired suite ABSENT from this file is treated as fast."
    echo "#"
    echo "# selftest<TAB>seconds<TAB>measured_at   (seconds from the seed run's unmutated precheck; ISO-8601 date)"
    printf '%s\n' "${MEASURED:-}" | grep -v '^$' | sort -u | while IFS=$'\t' read -r s secs; do
      [[ -n "$s" ]] || continue
      [[ "$secs" -ge "$SLOW_THRESHOLD_S" ]] 2>/dev/null && printf '%s\t%s\t%s\n' "$s" "$secs" "$(date -u +%Y-%m-%d)"
    done
  } > "$SOUT"
  info "seed: slow-suites -> $SOUT"
  info "seed mode: artifacts published, exiting green."
  RC=0
  finish
fi

# ---------------------------------------------------------------- exit contract
for sid in $TOTAL_SURVIVORS; do
  in_baseline "$sid" || red "baseline-absent survivor: $sid"
done

# Shrink warns — never red. A baseline that has outgrown the tree is noise, not a failure.
i=0
while [[ $i -lt ${#BL_ID[@]} ]]; do
  sid="${BL_ID[$i]}"; i=$((i + 1))
  case " $TOTAL_SURVIVORS " in
    *" $sid "*) continue ;;
  esac
  bg="${sid%%::*}"
  if [[ "$bg" != "catalog" && ! -f "$REPO_ROOT/$bg" ]]; then
    warn_baseline "baseline row's guard no longer resolves (renamed or deleted): $sid — drop the row."
  elif [[ "$MODE" == "full" ]]; then
    # Under sharding, "now KILLED" is only decidable for guards THIS shard swept — a row
    # belonging to another shard's guard is out of scope, not stale. Unsharded (no
    # --shard) keeps the historical behavior for every row.
    #
    # SWEPT IS NOT SCORED. SWEEP_GUARDS is the shard's ASSIGNED partition, fixed before the
    # precheck runs, so a guard whose pair turned out to be unrunnable is still "swept" while
    # every one of its mutants was dropped unscored. Its rows are then absent from
    # TOTAL_SURVIVORS for the one reason that proves nothing — nothing ran — and reading that
    # absence as a kill told the operator to drop live survivors. Obeying it reds the NEXT
    # healthy run with exactly those rows as baseline-absent survivors: a whipsaw the sweep
    # inflicts on itself. Undecidable is its own answer, and it is silence plus the red above.
    if unrun_this_run "$(sid_guard "$sid")"; then
      continue
    elif [[ -z "$SHARD_SPEC" ]] || swept_this_run "$(sid_guard "$sid")"; then
      warn_baseline "baseline row is now KILLED: $sid — drop the row."
    fi
  fi
done

finish
