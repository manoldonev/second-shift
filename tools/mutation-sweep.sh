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
#   mutation-sweep.sh --mode full [--seed] [--report F] [--baseline-out F] [--slow-out F]
#   mutation-sweep.sh --mode pr --base <ref> [--report F]
#
# GUARD UNIVERSE is a rule, not a list: every git-tracked `*.sh` that is not a
# `*-selftest.sh` and is not under `*/evals/*` or `tests/hooks-smoke/`. Every guard in it
# must resolve to its killer(s) via directory-scoped same-stem pairing, a
# mutation-pair-map.tsv row, or a mutation-exclusions.tsv row. An unaccounted guard is RED.
#
# EXIT CONTRACT — survivors are DATA, not automatically a red build.
#   Red only for: a baseline-absent survivor, a missing baseline in an enforcing non-seed
#   run (`baseline-missing`), catalog anchor drift, a bash -n-invalid CATALOG mutant, an
#   unaccounted guard, an unrunnable pair, a baseline environment mismatch
#   (`baseline-environment-mismatch`), or sandbox failure.
#   Warn (never red): a killed mutant still listed in the baseline, and a baseline row
#   whose guard no longer resolves — both say "shrink the baseline".
#
# ENFORCING vs ADVISORY: enforcing iff GITHUB_ACTIONS is set. Local runs are advisory and
# say so — kill verdicts are only comparable inside the canonical environment
# (ubuntu-latest + SKIP_STRESS=1), and this repo documents at least one platform-divergent
# guard (exitplan-ledger-gate's tier-3 `find -newermB` scan is dead code under GNU find).
#
# bash 3.2 clean: the companion selftest is in-glob, so it runs on the macOS lane's stock
# bash. No associative arrays, no mapfile, no ${var^^}.
set -uo pipefail

K_BUDGET="${MUTATION_SWEEP_K:-2}"   # generic mutants per operator per guard
SLOW_THRESHOLD_S=5                  # a paired suite at or above this is "slow"
PR_FAST_GUARD_CAP=6                 # PR lane: sweep at most this many fast guards

MODE=""
BASE_REF=""
SEED=0
REPORT_OUT=""
BASELINE_OUT=""
SLOW_OUT=""

die() { echo "[mutation-sweep] FATAL: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)         MODE="${2:-}"; shift 2 ;;
    --base)         BASE_REF="${2:-}"; shift 2 ;;
    --seed)         SEED=1; shift ;;
    --report)       REPORT_OUT="${2:-}"; shift 2 ;;
    --baseline-out) BASELINE_OUT="${2:-}"; shift 2 ;;
    --slow-out)     SLOW_OUT="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ "$MODE" == "full" || "$MODE" == "pr" ]] || die "--mode must be 'full' or 'pr'"
[[ "$MODE" == "pr" && -z "$BASE_REF" ]] && die "--mode pr requires --base <ref>"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$REPO_ROOT" || die "cannot cd to repo root"

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
red()  { echo "[mutation-sweep] RED: $*" >&2; RC=1; }
warn() { echo "[mutation-sweep] WARN: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
info() { echo "[mutation-sweep] $*"; }

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

is_slow() {
  local secs; secs="$(suite_seconds "$1")"
  [[ "${secs%%.*}" -ge "$SLOW_THRESHOLD_S" ]] 2>/dev/null
}

in_baseline() {
  local id="$1" i=0
  while [[ $i -lt ${#BL_ID[@]} ]]; do
    [[ "${BL_ID[$i]}" == "$id" ]] && return 0
    i=$((i + 1))
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
  for g in "${ALL_GUARDS[@]}"; do
    is_excluded "$g" || SWEEP_GUARDS[${#SWEEP_GUARDS[@]}]="$g"
  done
else
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
REPORT_TMP="$(mktemp -t mutation-sweep-report.XXXXXX)" || die "mktemp failed"
printf 'guard\tstatus\tpaired_selftest\tmutants_applied\tkilled\tsurvived\tsurvivor_ids\n' > "$REPORT_TMP"

emit_row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$REPORT_TMP"
}

finish() {
  if [[ -n "$REPORT_OUT" ]]; then
    cp "$REPORT_TMP" "$REPORT_OUT" && info "report -> $REPORT_OUT"
  else
    cat "$REPORT_TMP"
  fi
  rm -f "$REPORT_TMP"
  [[ $ENFORCING -eq 1 ]] || info "ADVISORY RUN (GITHUB_ACTIONS unset) — kill verdicts are not comparable to the committed baseline; this repo documents platform-divergent guards."
  [[ $WARNINGS -gt 0 ]] && info "$WARNINGS warning(s) — shrink the baseline."
  exit "$RC"
}

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
      emit_row "$g" "deferred-to-nightly" "${ks// /+}" 0 0 0 ""
      info "defer $g -> nightly: $defer"
    else
      fast_count=$((fast_count + 1))
      PR_SWEPT[${#PR_SWEPT[@]}]="$g"
    fi
  done
  SWEEP_GUARDS=()
  for g in ${PR_SWEPT[@]+"${PR_SWEPT[@]}"}; do SWEEP_GUARDS[${#SWEEP_GUARDS[@]}]="$g"; done
fi

if [[ ${#SWEEP_GUARDS[@]} -eq 0 ]]; then
  info "nothing left to sweep after deferral."
  finish
fi

# --------------------------------------------------------------------- sandbox
# `git worktree add --detach`, not `cp -R`: two suites need real git state
# (check-workflows-selftest cd's to the toplevel, derive-release-selftest diffs against
# the latest release tag). The working tree is small and the object store is shared, so
# this is near-free. Selftests resolve their guard relative to their own location, so
# pairing survives the copy.
SANDBOX="$(mktemp -d -t mutation-sweep-sandbox.XXXXXX)" || die "mktemp -d failed"
rmdir "$SANDBOX" 2>/dev/null
# Both codes, deliberately: shellcheck renamed this diagnostic mid-version and the two
# releases disagree on where they hang it. >=0.10 reports SC2329 on the FUNCTION; 0.9,
# which is what `apt-get install shellcheck` still yields on the ubuntu runner, reports
# SC2317 on each command in the BODY. Suppressing only the newer code is clean locally
# and red in CI. A directive on the function line scopes to the whole body for both.
# shellcheck disable=SC2317,SC2329 # invoked indirectly by the EXIT/INT/TERM trap below
cleanup() {
  git worktree remove --force "$SANDBOX" >/dev/null 2>&1
  rm -rf "$SANDBOX" 2>/dev/null
}
trap cleanup EXIT INT TERM
git worktree add --detach "$SANDBOX" HEAD >/dev/null 2>&1 || {
  red "sandbox failure: git worktree add --detach failed"
  finish
}

restore() { git -C "$SANDBOX" checkout -- "$1" 2>/dev/null; }

# Splice ONE mutated line back into the file. awk-with-a-file rather than `awk -v`,
# because -v mangles backslashes and these lines are dense with them.
# Mutants are applied by writing THROUGH the guard's existing inode (`cat >`), never by
# mv-ing a fresh file over it. A fresh inode is 0644, and with core.fileMode=true losing
# the exec bit is itself a git diff: the `git diff --quiet` byte-identity gates (no-op
# flip, catalog anchor drift) go dark, and any killer that precondition-gates on `-x`
# fails on EVERY mutant — false kills that report a weak suite as strong. The catalog
# tier below applies its mutants the same way for the same reason.
splice_line() {
  local file="$1" lineno="$2" replfile="$3" out
  out="$file.mut"
  awk -v n="$lineno" 'NR==FNR{repl=$0; next} FNR==n{print repl; next} {print}' \
    "$replfile" "$file" > "$out" && cat "$out" > "$file" && rm -f "$out"
}

# Run one killer inside the sandbox. Kill = ANY nonzero exit; crash-kills count as kills
# (nonzero is nonzero — the assertion-vs-crash diagnostic is deferred to #248).
run_killer() {
  ( cd "$SANDBOX" && bash "$1" ) >/dev/null 2>&1
}

# Cheapest-first is a pure cost optimization: it short-circuits on a KILL, so the
# any-suite kill criterion is unchanged. A surviving mutant still runs every killer.
order_killers() {
  local ks="$1" s
  for s in $ks; do printf '%s\t%s\n' "$(suite_seconds "$s")" "$s"; done | sort -n | cut -f2
}

TOTAL_SURVIVORS=""
add_survivor() { TOTAL_SURVIVORS="${TOTAL_SURVIVORS:+$TOTAL_SURVIVORS }$1"; }

for guard in "${SWEEP_GUARDS[@]}"; do
  KS="$(kill_set_for "$guard")"
  KS_ORDERED="$(order_killers "$KS" | tr '\n' ' ')"
  GFILE="$SANDBOX/$guard"

  # ---- unrunnable-pair precheck: every killer must be green on the UNMUTATED sandbox
  # before any of this guard's mutants can be scored. A broken or environment-starved
  # suite must never be able to report its guard as fully killed. The timings taken here
  # are also the `seconds` source for the slow list.
  unrunnable=""
  for s in $KS_ORDERED; do
    t0="$(date +%s)"
    if ! run_killer "$s"; then unrunnable="$s"; break; fi
    t1="$(date +%s)"
    MEASURED="${MEASURED:-}"$'\n'"$s	$((t1 - t0))"
  done
  if [[ -n "$unrunnable" ]]; then
    red "unrunnable pair: $unrunnable does not exit 0 against the unmutated sandbox (guard $guard). Its mutants are NOT scored."
    emit_row "$guard" "swept" "${KS// /+}" 0 0 0 ""
    continue
  fi

  applied=0; killed=0; survived=0; survivors=""

  # ---- generic tier
  op_i=0
  while [[ $op_i -lt ${#OP_ID[@]} ]]; do
    opid="${OP_ID[$op_i]}"; opmatch="${OP_MATCH[$op_i]}"; opflip="${OP_FLIP[$op_i]}"
    op_i=$((op_i + 1))
    ordinal=0; used=0
    while IFS= read -r lineno; do
      [[ -n "$lineno" ]] || continue
      ordinal=$((ordinal + 1))
      [[ $used -ge $K_BUDGET ]] && continue   # keep counting ordinals; stop mutating
      REPL="$(mktemp -t mutation-sweep-line.XXXXXX)"
      awk -v n="$lineno" 'NR==n' "$GFILE" | sed -E "$opflip" > "$REPL"
      splice_line "$GFILE" "$lineno" "$REPL"
      rm -f "$REPL"
      if ! bash -n "$GFILE" 2>/dev/null; then
        # A generic mutant that will not parse is a HARNESS ARTIFACT, not a finding:
        # sites are machine-enumerated, so a blind flip can land somewhere it cannot be
        # expressed. Skipped and logged, never red. (Catalog mutants are the opposite.)
        info "skip (bash -n invalid, harness artifact): $guard::$opid::$ordinal"
        restore "$guard"; continue
      fi
      if git -C "$SANDBOX" diff --quiet -- "$guard"; then
        info "skip (no-op flip): $guard::$opid::$ordinal"
        restore "$guard"; continue
      fi
      used=$((used + 1)); applied=$((applied + 1))
      got_kill=0
      for s in $KS_ORDERED; do
        if ! run_killer "$s"; then got_kill=1; break; fi
      done
      if [[ $got_kill -eq 1 ]]; then
        killed=$((killed + 1))
      else
        survived=$((survived + 1))
        sid="$guard::$opid::$ordinal"
        survivors="${survivors:+$survivors,}$sid"
        add_survivor "$sid"
      fi
      restore "$guard"
    done < <(grep -nE "$opmatch" "$GFILE" 2>/dev/null | cut -d: -f1)
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
    SED_ERR="$(sed -E "$csed" "$GFILE" 2>&1 > "$GFILE.mut")"; SED_RC=$?
    if [[ $SED_RC -ne 0 ]]; then
      rm -f "$GFILE.mut"
      red "catalog sed program is invalid: catalog::$cid on $guard — $SED_ERR"
      restore "$guard"; continue
    fi
    cat "$GFILE.mut" > "$GFILE" && rm -f "$GFILE.mut"   # write-through, not mv: see splice_line
    # LOUD anchor-drift, the check-lockstep-pairs-selftest convention: a hand-authored sed
    # that no longer applies is a BUG IN THIS FILE, not a passing mutant.
    if git -C "$SANDBOX" diff --quiet -- "$guard"; then
      red "catalog anchor drift: catalog::$cid left $guard byte-identical — the sed anchor has moved; re-anchor the row in the PR that moved it."
      restore "$guard"; continue
    fi
    if ! bash -n "$GFILE" 2>/dev/null; then
      red "catalog mutant is bash -n invalid: catalog::$cid on $guard"
      restore "$guard"; continue
    fi
    applied=$((applied + 1))
    got_kill=0
    for s in $KS_ORDERED; do
      if ! run_killer "$s"; then got_kill=1; break; fi
    done
    if [[ $got_kill -eq 1 ]]; then
      killed=$((killed + 1))
    else
      survived=$((survived + 1))
      survivors="${survivors:+$survivors,}catalog::$cid"
      add_survivor "catalog::$cid"
    fi
    restore "$guard"
  done

  emit_row "$guard" "swept" "${KS// /+}" "$applied" "$killed" "$survived" "$survivors"
  info "swept $guard — applied=$applied killed=$killed survived=$survived"
done

# The full-sweep report accounts for the ENTIRE universe, excluded rows included (zero
# counts), so it alone is the standing ranking. PR mode stays diff-scoped by design.
if [[ "$MODE" == "full" ]]; then
  for g in "${ALL_GUARDS[@]}"; do
    is_excluded "$g" && emit_row "$g" "excluded" "" 0 0 0 ""
  done
fi

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
    warn "baseline row's guard no longer resolves (renamed or deleted): $sid — drop the row."
  elif [[ "$MODE" == "full" ]]; then
    warn "baseline row is now KILLED: $sid — drop the row."
  fi
done

finish
