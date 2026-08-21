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
# DISCOVERY IS `*-selftest.sh` ONLY, deliberately. The three `*-selftest.mjs` files are executed
# by plugins/dev-pipeline/workflows/workflows-mjs-selftest.sh, which is itself in this
# glob. Widening discovery to `.mjs` would double-run them.
#
# DISPATCH IDIOM is lifted from tools/install-topology-selftest.sh: `xargs -P` over zero-padded
# indices into a worklist file, each worker writing `<idx>.rc` and `<idx>.log`, the parent
# scoring from those in worklist order. bash 3.2 compatible (no `wait -n`) — macos-latest ships
# /bin/bash 3.2 and that is one of this repo's two CI lanes. A worker that dies WITHOUT writing
# an `.rc` scores as a named infra failure, never as a green suite.
#
# THE PASS CACHE (#448) is the second thing this file owns, and the risky one. A suite with a
# row in tools/selftest-cache-inputs.tsv is content-addressed: the key is sha256 over an epoch
# constant, the OS, the bash major version, this runner's own blob id, the suite path and the
# `git hash-object` blob id of every DECLARED input, and a key already recorded as a pass on this
# lane means the suite is not re-run. Four properties contain the failure mode — a
# silently-skipped gate — and they are the load-bearing part, not the hashing:
#
#   1. FAIL-CLOSED BY DEFAULT. The table is opt-in; a suite with no row is always run. And the
#      cache as a whole is off unless --cache-dir is passed, so the mandated local recipe in
#      CLAUDE.md is still a cold sweep.
#   2. SELF-INCLUSION IS MANDATORY. A row set must name the suite itself and, where the naming
#      convention resolves it, the script under test. A suite cannot cache past an edit to its
#      own bytes. Rejected here, loudly, not documented as an expectation.
#   3. RECORDING IS A SEPARATE FLAG. --cache-dir reads; only --cache-write records. CI passes
#      the second on push-to-main alone, so a PR cannot mark its own untested content as passing.
#   4. ONLY PASS IS RECORDED, and only by the parent, after the replay. A red suite, or one whose
#      worker died without a verdict, writes nothing — that is the shape, not a check.
#
# The nightly wholesale sweep (.github/workflows/nightly-guards.yml) runs with no --cache-dir at
# all, so an under-declaration surfaces within a day against a tree nobody is waiting on.
#
# THIS INVERTS tools/mutation-sweep.sh's cache, whose idiom the hashing and marker mechanics here
# are lifted from: that one is local-only and disables itself in the enforcing lane, because CI is
# the authority there and must run cold. Here CI is the thing being sped up, and the authority is
# the nightly leg.
#
# USAGE
#   run-selftests.sh [--exclude <repo-relative-path>]... [--jobs <n>] [--root <dir>]
#                    [--cache-dir <dir>] [--cache-write] [--full]
#
#   --exclude     repeatable. Lifts a suite out of THIS sweep while leaving it discovered, so it
#                 can run in its own CI job. An exclusion matching no discovered suite is a HARD
#                 ERROR — the stale-row posture install-topology-known-red.tsv and
#                 mutation-baseline.tsv already carry, applied to a stale workflow argument.
#   --full        do NOT apply tools/selftest-slow-suites.tsv. The sweep of record passes this;
#                 see #566 below for why the table is on by default and the opt-out is explicit.
#   --jobs        concurrency; defaults to $SELFTEST_JOBS, itself defaulting to 4 (the recipe).
#   --root        tree to discover under; defaults to the repo root above this script.
#   --cache-dir   marker store for the pass cache. Absent, no suite is ever skipped.
#   --cache-write additionally RECORD passes into that store. Requires --cache-dir.
#
#   $LEAN_SELFTEST_CACHE_DIR is the same store handed down by lean-gate.sh milestone 3, which
#   cannot pass a flag to a lane command it does not own — see #563 below. Argv wins; unset is
#   a no-op; recording is on for that path and the reasoning is at the reading site.
#
# EXIT: 0 iff every run suite passed. Non-zero names every failing suite. 2 for a usage error,
# a stale exclusion, a malformed cache-input table, or a discovered/run count disagreement.
# 3 (#527) when there were failures and EVERY one of them is the no-verdict infrastructure class —
# the workers died rather than the suites failing, so the sweep learned nothing about the tree.
# Mixed infra-and-real is 1, because a red branch is still a red branch. lean-gate.sh milestone 3
# reads 3 from any verify lane as infrastructure and charges no fix attempt.
#
# NOT `set -e`: this harness runs other people's suites and SCORES their exit codes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # HERE is already absolute and resolved, so its dirname is too
# Property 2 applied one level up: this file is the harness that PRODUCES every verdict the
# store records, so its own bytes are on the key axis beside the declared inputs. Without it a
# change to how workers are dispatched, or to what environment they inherit, is served past on
# exactly the suites it is most likely to move. Resolved from BASH_SOURCE, never from $ROOT,
# because --root points at a tree that need not contain this script at all.
SELF="${BASH_SOURCE[0]}"
JOBS="${SELFTEST_JOBS:-4}"
EXCLUDES=""   # newline-separated; bash 3.2 has no array-of-args ergonomics worth the noise here
FULL=0        # 1 = do not apply the slow-suite table (#566)
DEFERRED=""   # newline-separated "<suite><TAB><reason>", for the announcement below
TAB=$'\t'

CACHE_DIR=""
CACHE_WRITE=0
# OR-1's one-character invalidation. The key covers repo CONTENT — including this runner's own
# bytes, see SELF above — but never the runner IMAGE, so a GitHub image bump could in principle
# move a suite's verdict with every declared input byte-identical. Bumping this makes the next
# run of every lane a full cold sweep — the fail-closed state — and the nightly wholesale leg is
# what surfaces the need to.
CACHE_EPOCH=1
CACHE_MAX="${SELFTEST_CACHE_MAX:-5000}"

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
  # LEAN_SELFTEST_CACHE_DIR (#563) is stripped on the same principle, and it is not a test-only
  # seam: the cache is decided ONCE, in the parent, and a worker never touches the store. Left
  # inheritable, a suite that nests its own runner — run-selftests-selftest.sh does exactly that
  # — would silently start caching under the dogfood sweep while the same suite run standalone
  # did not, which is both a fixture that means something different depending on who ran it and
  # a cache activated by a route nobody declared.
  ( cd "$W_ROOT" && env -u RUN_SELFTESTS_DROP_LAST -u RUN_SELFTESTS_DROP_RC \
       -u LEAN_SELFTEST_CACHE_DIR bash "$W_SUITE" ) \
    > "$W_OUT/$W_IDX.log" 2>&1
  W_RC=$?   # captured BEFORE anything else runs — a later test would overwrite $?
  # Rejection-assertion seam #2 (see RUN_SELFTESTS_DROP_LAST below): exit WITHOUT writing the
  # verdict file, reproducing a worker that died mid-suite. That path is a documented guarantee
  # — a suite with no verdict is named as infra, never scored as a pass — and it is unreachable
  # from a fixture otherwise, since a suite cannot reach its own worker's results directory.
  # Never set in CI or by an operator.
  [[ "${RUN_SELFTESTS_DROP_RC:-}" == "1" ]] && exit 0
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
    --cache-dir)   [[ $# -ge 2 ]] || die "--cache-dir requires a directory"
                   CACHE_DIR="$2"; shift 2 ;;
    --cache-write) CACHE_WRITE=1; shift ;;
    --full)    FULL=1; shift ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ "$JOBS" =~ ^[0-9]+$ ]] && [[ "$JOBS" -ge 1 ]] || die "--jobs/SELFTEST_JOBS must be a positive integer, got: $JOBS"
[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

# ---- the slow-suite table (#566) -------------------------------------------------------
# ON BY DEFAULT, and `--full` is the opt-out. The inverse — an opt-in `--quick` — was rejected
# at intake for a reason that is structural rather than stylistic: the only caller that WANTS
# the bound is lean-gate.sh milestone 3, which runs a `test` command out of a consumer's
# gitignored config. An opt-in flag would therefore have to be added by hand to an untracked
# file that no gate can read, so "did the bound actually apply?" would be unanswerable in
# review and unverifiable in CI. Default-on inverts that: the sweeps of record (both CI
# selftest jobs, the nightly wholesale leg, and the CLAUDE.md contributor recipe) pass `--full`
# in COMMITTED files, where a missing opt-out is visible in the diff.
#
# WHY A TABLE AND NOT MORE `--exclude` FLAGS. The membership is a cost record — each row
# carries the measurement that justifies it — and it has to be reviewable. Flags in the
# gitignored config are neither.
#
# RESOLVED UNDER $ROOT, never under $SELF's repo: --root points at the tree being swept, and a
# sweep of another tree must read that tree's table or it is applying this one's membership to
# suites it has never measured. Absent, every suite is treated as fast.
SLOW_SUITES="$ROOT/tools/selftest-slow-suites.tsv"
if [[ "$FULL" -eq 0 && -f "$SLOW_SUITES" ]]; then
  while IFS="$TAB" read -r sl_suite sl_secs sl_reason; do
    case "${sl_suite:-}" in ''|'#'*) continue ;; esac
    [[ -n "$sl_secs" && -n "$sl_reason" ]] \
      || die "malformed row in $SLOW_SUITES: '$sl_suite' — expected <suite>\\t<seconds>\\t<reason>"
    [[ "$sl_secs" =~ ^[0-9]+$ ]] \
      || die "malformed row in $SLOW_SUITES: '$sl_suite' seconds must be a whole number, got '$sl_secs'"
    DEFERRED="$DEFERRED$sl_suite$TAB${sl_secs}s — $sl_reason"$'\n'
  done < "$SLOW_SUITES"
fi

# ---- orphan reaping (#528) -------------------------------------------------------------
# "The sweep harness on entry": lean-gate-selftest.sh and orchestrate-lean-selftest.sh — both
# discovered and run by THIS sweep — leave a signal-killed run's fixture dir behind (their own
# `trap ... EXIT` never gets to fire). Reaping here, before dispatch, is the entry point that
# catches every prior sweep's casualties, not just this run's.
#
# GUARDED ON THE TOOL'S PRESENCE UNDER THIS ROOT, not on an env flag: a fixture tree built by
# run-selftests-selftest.sh (--root pointing at a throwaway directory of leaf `*-selftest.sh`
# files) never contains tools/reap-lean-fixtures.sh, so this is inert there for free — no
# separate test-only seam needed to keep those fixtures hermetic. A real sweep, in this repo or
# a worktree of it, always has the tool beside it.
#
# Best-effort: a reap failure is housekeeping, never a reason to fail the sweep it is entered
# from — `|| true` keeps a broken reaper from turning a green run red.
if [[ -x "$ROOT/tools/reap-lean-fixtures.sh" ]]; then
  bash "$ROOT/tools/reap-lean-fixtures.sh" --dir "${TMPDIR:-/tmp}" | sed 's/^/[run-selftests] /' || true
fi

# "a whole number", and NOT the longer phrasing tools/mutation-sweep.sh uses for the same check:
# that wording embeds one of the two tokens the equality operator in tools/mutation-operators.tsv
# enumerates, so the sweep reads a die MESSAGE as a mutation site. The flip then lands in prose
# nothing can kill, burning one of that operator's two budgeted ordinals and displacing a real
# comparison out of the swept window. (This comment is under the same constraint, and says so
# rather than naming the tokens: an explanation that spells them out recreates the site twice.)
[[ "$CACHE_MAX" =~ ^[0-9]+$ ]] || die "SELFTEST_CACHE_MAX must be a whole number, got: $CACHE_MAX"
# --cache-write without a store is a workflow that THINKS it is recording passes and is not.
# Refusing beats accepting it: a lane silently recording nothing looks identical to a lane whose
# cache never hits, and the difference is a whole CI cycle of debugging.
if [[ "$CACHE_WRITE" -eq 1 && -z "$CACHE_DIR" ]]; then
  die "--cache-write requires --cache-dir"
fi

# ---- the lean lane's store (#563) ------------------------------------------------------
# The SECOND activation path, and the only one that is not argv. lean-gate.sh milestone 3 cannot
# rewrite the `test` command it runs — that string lives in a consumer's config, gitignored here
# — so it hands the store down the one channel it does own: an env assignment prepended to the
# lane's invocation. This is the reading end of that coupling.
#
# ARGV WINS, and this sits AFTER the parse and after the --cache-write check so that stays true
# in both directions: an explicit --cache-dir is never overridden, and a lone --cache-write is
# still the usage error it is today rather than being quietly satisfied out of the environment.
# UNSET IS A NO-OP: the CLAUDE.md local recipe, both CI lanes and the nightly wholesale leg see
# no such variable and resolve exactly what they resolve today.
#
# RECORDING IS ON for this path, which is the one place it departs from CI's split. CI withholds
# --cache-write from the PR lane because there an untrusted branch would record into a store
# other runs read; this store is machine-local and records the operator's own tree, the posture
# tools/mutation-sweep.sh's cache already takes. And a store that is never written can never be
# served from: the lean lane's whole case is the SECOND sweep of an unmoved head.
CACHE_FROM_ENV=0
if [[ -z "$CACHE_DIR" && -n "${LEAN_SELFTEST_CACHE_DIR:-}" ]]; then
  CACHE_DIR="$LEAN_SELFTEST_CACHE_DIR"
  CACHE_WRITE=1
  CACHE_FROM_ENV=1
  echo "[run-selftests] cache: activated from LEAN_SELFTEST_CACHE_DIR (recording on) — $CACHE_DIR"
fi

# ---- hashing -------------------------------------------------------------------------
# The picker tools/mutation-sweep.sh already carries: shasum ships with macOS and with the
# ubuntu runner's perl, sha256sum is coreutils. `git hash-object` needs no repository — it is a
# pure blob hash — which is what lets a fixture tree outside any repo exercise this. If either
# tool is missing the cache disables itself rather than keying on something weaker: a cache that
# cannot compute its own key must serve no entries at all.
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

if [[ -n "$CACHE_DIR" && -z "$SHA_KIND" ]]; then
  echo "[run-selftests] cache disabled: neither shasum nor sha256sum is available, so no key can be computed."
  CACHE_DIR=""; CACHE_WRITE=0
fi
if [[ -n "$CACHE_DIR" ]] && ! command -v git >/dev/null 2>&1; then
  echo "[run-selftests] cache disabled: git is unavailable, so no declared input can be hashed."
  CACHE_DIR=""; CACHE_WRITE=0
fi
if [[ -n "$CACHE_DIR" ]] && ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
  # The one behavioral difference between the two activation paths (#563). A --cache-dir that
  # cannot be created is a flag an operator typed that cannot work, and saying so beats running
  # a sweep they think is caching. An INJECTED store that cannot be created is not the tree's
  # fault, and dying on it would let an unwritable $HOME red a milestone about something else
  # entirely — so that path joins the two disable arms above and runs cold, named.
  [[ "$CACHE_FROM_ENV" -eq 1 ]] || die "--cache-dir is not creatable: $CACHE_DIR"
  echo "[run-selftests] cache disabled: LEAN_SELFTEST_CACHE_DIR is not creatable: $CACHE_DIR"
  CACHE_DIR=""; CACHE_WRITE=0
fi
if [[ -n "$CACHE_DIR" ]]; then
  CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
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
# case, not an edge one: this repo's milestone-3 `test` command already passes
# `--exclude tools/install-topology-selftest.sh` explicitly, and that suite is also a table row.
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
# NAMED, one line per suite, never a count. An operator reading a green milestone 3 has to be
# able to tell which suites that green does NOT cover, and a number cannot answer it. The gate
# replays this verbatim; it makes no deferral claim of its own.
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

BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$BASE"' EXIT
RESULTS="$BASE/results"
mkdir -p "$RESULTS" || die "cannot create $RESULTS"
mkdir -p "$BASE/cache-inputs" "$BASE/cache-manifest" "$BASE/hits" || die "cannot create $BASE/cache-*"

# ---- the cache-input table -------------------------------------------------------------
# READ AND VALIDATED ON EVERY SWEEP, including one running with no cache at all. A row is only
# ever USED under --cache-dir, but a malformed declaration is a broken gate declaration, and
# leaving it unread until the day CI happens to enable the cache is the same silent-widening
# posture the stale --exclude check above already refuses.
#
# Slugging `/` to `%` is what lets a suite path be a filename. No repo path contains `%`.
CACHE_TSV="$ROOT/tools/selftest-cache-inputs.tsv"
slug_of() { printf '%s' "${1//\//%}"; }

if [[ -f "$CACHE_TSV" ]]; then
  c_lineno=0
  while IFS="$TAB" read -r c_suite c_input c_rest || [[ -n "$c_suite" ]]; do
    c_lineno=$((c_lineno + 1))
    case "$c_suite" in ''|'#'*) continue ;; esac
    [[ -z "$c_rest" ]] \
      || die "selftest-cache-inputs.tsv:$c_lineno: expected exactly two tab-separated columns (suite, input)"
    c_suite="${c_suite#./}"; c_input="${c_input#./}"
    [[ -n "$c_input" ]] \
      || die "selftest-cache-inputs.tsv:$c_lineno: '$c_suite' declares an empty input"
    grep -qxF "$c_suite" <<<"$ALL" \
      || die "selftest-cache-inputs.tsv:$c_lineno: '$c_suite' matches no discovered suite under $ROOT — stale cache-input row"
    [[ -e "$ROOT/$c_input" ]] \
      || die "selftest-cache-inputs.tsv:$c_lineno: '$c_suite' declares an input that does not exist: '$c_input'"
    printf '%s\n' "$c_input" >> "$BASE/cache-inputs/$(slug_of "$c_suite")"
    printf '%s\n' "$c_suite" >> "$BASE/cache-suites"
  done < "$CACHE_TSV"
fi

# Per-suite completeness. Property 2 of the four: a suite that does not pin its own bytes, or
# the bytes of the script it tests, can cache past the very edit its row exists to notice.
#
# THE SUBJECT IS MECHANIZED ONLY WHERE THE NAMING CONVENTION RESOLVES IT — `<stem>-selftest.sh`
# next to `<stem>.sh`. CLAUDE.md's register is explicit that coverage here is not naming
# (cost-block-selftest.sh tests pipeline-cost-block.sh, one directory up), so for the rest the
# floor is weaker and stated as such: at least one input besides the suite itself, which rejects
# the degenerate row that pins nothing but its own bytes and reads like a complete declaration.
if [[ -f "$BASE/cache-suites" ]]; then
  LC_ALL=C sort -u "$BASE/cache-suites" > "$BASE/cache-suites.u"
  while IFS= read -r c_suite; do
    [[ -n "$c_suite" ]] || continue
    c_slug="$(slug_of "$c_suite")"
    LC_ALL=C sort -u "$BASE/cache-inputs/$c_slug" -o "$BASE/cache-inputs/$c_slug"
    grep -qxF "$c_suite" "$BASE/cache-inputs/$c_slug" \
      || die "selftest-cache-inputs.tsv: '$c_suite' does not declare ITSELF as an input — a cached suite must not survive an edit to its own bytes"
    c_subject="$(dirname "$c_suite")/$(basename "$c_suite" -selftest.sh).sh"
    c_subject="${c_subject#./}"
    if [[ -f "$ROOT/$c_subject" ]] && ! grep -qxF "$c_subject" "$BASE/cache-inputs/$c_slug"; then
      die "selftest-cache-inputs.tsv: '$c_suite' does not declare its script under test '$c_subject'"
    fi
    [[ "$(grep -c . "$BASE/cache-inputs/$c_slug")" -ge 2 ]] \
      || die "selftest-cache-inputs.tsv: '$c_suite' declares no input besides itself — a row that pins only its own bytes is not a declaration"
  done < "$BASE/cache-suites.u"
fi

# ---- keys and markers --------------------------------------------------------------------
# The manifest is written to a file rather than piped, for two reasons: a `git hash-object` that
# fails mid-stream must abort the key (a partial manifest would hash cleanly to a WRONG key), and
# AC-10 wants the same bytes printed back on a hit, so the reader can see what the key covered.
cache_manifest() { # $1 = suite relpath -> writes $BASE/cache-manifest/<slug>; 1 if unhashable
  local suite="$1" slug list out p abs f h
  slug="$(slug_of "$suite")"
  list="$BASE/cache-inputs/$slug"
  out="$BASE/cache-manifest/$slug"
  [[ -f "$list" ]] || return 1
  # Unhashable runner -> no key -> every suite runs. Fail-closed, same as any unhashable input.
  local runner_h
  runner_h="$(git hash-object -- "$SELF" 2>/dev/null)"
  [[ -n "$runner_h" ]] || return 1
  printf 'selftest-cache|epoch=%s|os=%s|bash=%s|stress=%s|runner=%s|suite=%s\n' \
    "$CACHE_EPOCH" "$CACHE_OS" "$CACHE_BASH_MAJOR" "$CACHE_STRESS" "$runner_h" "$suite" > "$out" || return 1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    abs="$ROOT/$p"
    if [[ -d "$abs" ]]; then
      # A directory contributes every regular file beneath it, sorted, so an ADDED or DELETED
      # fixture moves the key exactly as an edited one does.
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        h="$(git hash-object -- "$abs/$f" 2>/dev/null)"
        [[ -n "$h" ]] || return 1
        printf '%s  %s\n' "$h" "$p/$f" >> "$out"
      done < <(cd "$abs" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
    else
      h="$(git hash-object -- "$abs" 2>/dev/null)"
      [[ -n "$h" ]] || return 1
      printf '%s  %s\n' "$h" "$p" >> "$out"
    fi
  done < "$list"
  return 0
}

cache_marker() { printf '%s/%s/%s' "$CACHE_DIR" "${1:0:2}" "$1"; }

# FAIL SAFE, the same posture mutation-sweep.sh's cache_get takes: anything that is not exactly
# the one well-formed record line is a MISS, and a miss costs a real run. There is deliberately
# no path here that turns an unreadable or truncated marker into a pass.
cache_hit() { # $1 = key
  local f line
  [[ -n "$CACHE_DIR" && -n "$1" ]] || return 1
  f="$(cache_marker "$1")"
  [[ -f "$f" && -r "$f" ]] || return 1
  line="$(head -1 "$f" 2>/dev/null)" || return 1
  case "$line" in "v1${TAB}pass${TAB}"*) return 0 ;; *) return 1 ;; esac
}

# mv-atomic against a concurrent sibling sweep sharing the store. Every failure path is silent
# and non-fatal: an unwritable cache must slow the next sweep down, never break this one.
cache_put() { # $1 = key, $2 = suite
  local d t
  [[ -n "$CACHE_DIR" && -n "$1" ]] || return 1
  d="$CACHE_DIR/${1:0:2}"
  mkdir -p "$d" 2>/dev/null || return 1
  t="$d/.tmp.$$.$RANDOM"
  printf 'v1%spass%s%s\n' "$TAB" "$TAB" "$2" > "$t" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 1; }
  mv -f "$t" "$d/$1" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 1; }
  return 0
}

# Unbounded growth would eventually make the restore step the cost this file exists to remove.
# Clearing wholesale (rather than evicting by age) keeps the failure mode fail-closed: the next
# run is simply cold.
cache_prune() {
  local n
  [[ -n "$CACHE_DIR" ]] || return 0
  n="$(find "$CACHE_DIR" -type f 2>/dev/null | grep -c '')"
  [[ "${n:-0}" -gt "$CACHE_MAX" ]] || return 0
  rm -rf "${CACHE_DIR:?}"/* 2>/dev/null
  echo "[run-selftests] cache: $n markers exceeded the $CACHE_MAX bound — cleared (the next run is cold)."
}

# The environment axis of the key (D-13): every knob that changes WHAT A VERDICT MEANS, so a run
# under a different one is never served an answer to a different question. RUNNER_OS is what the
# two CI lanes differ by; the bash major is what the macos shim exists to pin, and a verdict under
# 3.2 is not a verdict under 5. SKIP_STRESS is here because a suite that skipped its stress legs
# passed a strictly weaker question than one that ran them — today the two CI lanes also differ by
# OS so nothing could collide, but that is a coincidence of the current matrix, not a property.
CACHE_OS="${RUNNER_OS:-$(uname -s 2>/dev/null || echo unknown)}"
CACHE_BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
CACHE_STRESS="${SKIP_STRESS:-}"

# The filter below and the DISCOVERED/EXCLUDED arithmetic above are two independent derivations
# of the same set. They are reconciled after the run (see "count reconciliation"), because a
# sweep that quietly runs fewer suites than it discovered reads as a FASTER GREEN — the single
# failure mode this work is most exposed to.
: > "$BASE/worklist"
n=0
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  if [[ -n "$EXCLUDES" ]] && grep -qxF "${suite#./}" <<<"$EXCLUDES"; then
    continue
  fi
  n=$((n + 1))
  # Third column: the cache key, or empty. Empty is the fail-closed value and covers every
  # reason a suite might not participate — no --cache-dir, no row in the table, or an input
  # that could not be hashed. Nothing downstream distinguishes them, and nothing needs to.
  key=""
  if [[ -n "$CACHE_DIR" ]] && cache_manifest "$suite"; then
    key="$(sha_stdin < "$BASE/cache-manifest/$(slug_of "$suite")")"
  fi
  printf '%s\t%s\t%s\n' "$(printf '%04d' "$n")" "$suite" "$key" >> "$BASE/worklist"
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

# ---- cache resolution ------------------------------------------------------------------
# Decided in the PARENT, before dispatch, and recorded as a marker file per index. Doing it here
# rather than inside the worker is what keeps the store race-free: nothing under --cache-dir is
# ever read or written by a concurrent process of this run.
: > "$BASE/dispatch"
while IFS="$TAB" read -r idx suite key; do
  [[ -n "$idx" ]] || continue
  if cache_hit "$key"; then
    : > "$BASE/hits/$idx"
    continue
  fi
  printf '%s\n' "$idx" >> "$BASE/dispatch"
done < "$BASE/worklist"

# ---- dispatch ------------------------------------------------------------------------
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
CACHED=0
FAILED=""
# #527 AC-1. The infra tally beside the failure list. The per-suite class already exists below
# (`rc=125`, the no-verdict-written case) and is already PRINTED as infra — only the parent
# collapsed it, so a caller could not tell a sweep whose workers were killed from a sweep whose
# suites are red. Counted here rather than re-derived from $FAILED at the exit: parsing "(rc=125)"
# back out of a formatted list would be a second reader of a string this file only writes.
INFRA=0
while IFS="$TAB" read -r idx suite key; do
  [[ -n "$idx" ]] || continue
  RAN=$((RAN + 1))

  # AC-10. A skip that does not say what it skipped, under which key, over which bytes, is
  # indistinguishable in a log from a suite that quietly stopped being discovered.
  if [[ -f "$BASE/hits/$idx" ]]; then
    CACHED=$((CACHED + 1))
    echo "::group::cached  $suite"
    echo "[run-selftests] cache hit — this exact content already passed on this lane, so the suite was not re-run."
    echo "[run-selftests]   key: $key"
    echo "[run-selftests]   over: $(head -1 "$BASE/cache-manifest/$(slug_of "$suite")")"
    echo "[run-selftests]   inputs:"
    tail -n +2 "$BASE/cache-manifest/$(slug_of "$suite")" | sed 's/^/[run-selftests]     /'
    echo "::endgroup::"
    continue
  fi

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
    [[ "$rc" -eq 125 ]] && INFRA=$((INFRA + 1))
  fi
done < "$BASE/worklist"

# ---- record passes ---------------------------------------------------------------------
# Property 4: only PASS, only from the parent, only after the replay has scored the run. A red
# suite, a suite whose worker died without writing a verdict, and a suite served from the cache
# all fall out of this loop without a marker — the first two because the rc gate refuses them,
# the third because re-recording what was never re-run would let one stale pass renew itself
# indefinitely. Property 3 is the flag: without --cache-write this block does not exist.
RECORDED=0
if [[ "$CACHE_WRITE" -eq 1 ]]; then
  cache_prune
  while IFS="$TAB" read -r idx suite key; do
    [[ -n "$key" ]] || continue
    [[ -f "$BASE/hits/$idx" ]] && continue
    [[ -f "$RESULTS/$idx.rc" ]] || continue
    [[ "$(cat "$RESULTS/$idx.rc")" == "0" ]] || continue
    cache_put "$key" "$suite" && RECORDED=$((RECORDED + 1))
  done < "$BASE/worklist"
fi

if [[ -n "$CACHE_DIR" ]]; then
  echo "[run-selftests] cache: $CACHED served, $RECORDED recorded ($CACHE_DIR)"
fi

# ---- count reconciliation ------------------------------------------------------------
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  echo "[run-selftests] ERROR: discovered-minus-excluded is $EXPECTED but $RAN suite(s) ran — silent truncation, not a pass." >&2
  exit 2
fi

if [[ -n "$FAILED" ]]; then
  echo "[run-selftests] FAILED suites:" >&2
  printf '%s' "$FAILED" | while IFS= read -r f; do [[ -n "$f" ]] && echo "  $f" >&2; done
  count="$(printf '%s' "$FAILED" | grep -c .)"
  echo "[run-selftests] summary: $RAN scored, $((RAN - CACHED)) run, $CACHED served from cache, $count failed ($INFRA infrastructure)" >&2
  # #527 AC-1. THE RESERVED CODE, and it is reserved rather than merely returned: a consumer wires
  # this runner (or any other suite runner) into `commands.<host>.test`, and lean-gate.sh milestone
  # 3 reads a 3 from ANY verify lane as "this told us nothing about the branch". So the condition
  # has to be ALL, never ANY — one genuinely red suite alongside a killed worker is still a red
  # branch, and reporting that as infrastructure would be the fail-open direction: a broken branch
  # that costs no fix attempt and re-spawns until the continuation budget runs out.
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

# "scored", not "ran" — with a cache in play they are different numbers, and a sweep that reports
# the larger one as work it performed is the faster-green misreading this whole file guards.
echo "[run-selftests] summary: $RAN scored, $((RAN - CACHED)) run, $CACHED served from cache, 0 failed"
