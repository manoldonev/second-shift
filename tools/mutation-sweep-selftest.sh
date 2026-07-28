#!/usr/bin/env bash
# mutation-sweep-selftest.sh — companion suite for tools/mutation-sweep.sh.
#
# Deliberately IN-GLOB (unlike the harness it tests): CLAUDE.md's coverage rule exempts
# the scenario-lib precedent from the *glob*, not from *coverage*. Being in-glob also runs
# this on the macOS lane's stock bash 3.2, which is what actually enforces the harness's
# bash-3.2-clean claim.
#
# WHY PER-TOOL FIXTURE CASES RATHER THAN A SCENARIO (CLAUDE.md's scenario-first rule):
# the invariants here are repo-level TEST-INFRASTRUCTURE contracts — the sweep's exit
# semantics, its two mutant tiers, and the resolution rules over its TSV family.
# scenario-liveness-selftest.sh composes dev-pipeline VERDICT PATHS (stage gates reaching
# a terminal write); the mutation sweep touches none of them and is never invoked from a
# pipeline stage, so no scenario there covers this and extending it would bolt an
# unrelated harness onto the pipeline composition suite. The rule's real target — a
# component checked only against itself — is answered by cases (j)/(k), which bind the
# harness to the LIVE TREE rather than to its own fixtures.
#
# ENVIRONMENT PINNING IS LOAD-BEARING (D-8). This suite runs on BOTH CI lanes, where
# GITHUB_ACTIONS=1 is always set, RUNNER_OS is Linux on ubuntu and macOS on
# selftests-bash32, and SKIP_STRESS is unset on ubuntu and 1 on macOS. Inheriting that,
# the harness would enter enforcing mode and red the environment check on both lanes,
# failing the exit-0 cases for a reason unrelated to any mutant. Every invocation below
# therefore pins the environment explicitly via adv()/enf() and NEVER inherits the lane's.
#
# Exit code = number of failed cases (the repo-wide selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$HERE/mutation-sweep.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
FAILS=0

[[ -f "$SWEEP" ]] || { echo "[mutation-sweep-selftest] FATAL: $SWEEP missing"; exit 99; }

ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; FAILS=$((FAILS + 1)); }

TMPROOT="$(mktemp -d -t mutation-sweep-selftest.XXXXXX)" || exit 99
trap 'rm -rf "$TMPROOT"' EXIT

# Advisory: harness sees no GITHUB_ACTIONS, so it never enforces the environment header.
adv() { env -u GITHUB_ACTIONS -u RUNNER_OS -u SKIP_STRESS "$@"; }
# Enforcing: the canonical environment, stated explicitly rather than inherited.
enf() { env GITHUB_ACTIONS=1 RUNNER_OS=Linux SKIP_STRESS=1 "$@"; }

# ---------------------------------------------------------------- fixture repo
# A git-initialized temp repo is required, not optional: the harness sandboxes with
# `git worktree add --detach HEAD`, so the fixture needs a real commit.
# $1 = dir, $2 = strong|weak killer.
make_fixture() {
  local dir="$1" killer="$2"
  mkdir -p "$dir/tools"
  cat > "$dir/guard.sh" <<'EOF'
#!/usr/bin/env bash
# fixture guard: rejects the literal string "bad".
if [[ "${1:-}" == "bad" ]]; then
  echo "violation"
  exit 1
fi
echo ok
exit 0
EOF
  if [[ "$killer" == "strong" ]]; then
    # Exercises the violation path, so a fail-open mutant (exit 1 -> exit 0) is caught.
    cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f=0
out="$(bash "$HERE/guard.sh" bad)"; rc=$?
[[ $rc -eq 1 ]] || f=$((f+1))
[[ "$out" == "violation" ]] || f=$((f+1))
out="$(bash "$HERE/guard.sh" good)"; rc=$?
[[ $rc -eq 0 ]] || f=$((f+1))
exit $f
EOF
  else
    # Only ever exercises the happy path — the boilerplate class this sweep exists to find.
    cat > "$dir/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
  fi
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
}

new_fixture() {
  local d="$TMPROOT/fx$RANDOM$RANDOM"
  make_fixture "$d" "$1"
  printf '%s' "$d"
}

baseline_with() { # $1=dir, rest = survivor ids
  local d="$1"; shift
  { echo "# environment: ubuntu-latest SKIP_STRESS=1"
    echo "# k=2"
    for s in "$@"; do printf '%s\tseeded\n' "$s"; done
  } > "$d/tools/mutation-baseline.tsv"
}

# ============================================================= fixture cases

echo "(a) green direction — strong killer catches the mutant"
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'killed=1 survived=0'; then
  ok "mutant killed, exit 0"
else
  bad "(a) expected killed=1 survived=0 and rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(b) red direction — weak killer, empty baseline, survivor is red"
FX="$(new_fixture weak)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'baseline-absent survivor'; then
  ok "baseline-absent survivor is red"
else
  bad "(b) expected rc=1 + baseline-absent survivor; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(c) baseline suppression — the same survivor listed is report-only"
FX="$(new_fixture weak)"
baseline_with "$FX" 'guard.sh::fail-open::1'
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]]; then
  ok "listed survivor does not red the build"
else
  bad "(c) expected rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(d) shrink warns — killed-but-listed, and a listed guard that no longer resolves"
FX="$(new_fixture strong)"
baseline_with "$FX" 'guard.sh::fail-open::1' 'gone/removed.sh::fail-open::1'
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && printf '%s' "$OUT" | grep -q 'now KILLED' \
  && printf '%s' "$OUT" | grep -q 'no longer resolves'; then
  ok "both shrink conditions warn, neither reds"
else
  bad "(d) expected rc=0 + both warns; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(e) catalog anchor drift — a sed that leaves the file byte-identical is red"
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'drifted\tguard.sh\ts/__NEVER_PRESENT__/x/\tanchor that cannot match\n' >> "$FX/tools/mutation-catalog.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'catalog anchor drift'; then
  ok "anchor drift is LOUD"
else
  bad "(e) expected rc=1 + catalog anchor drift; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(f) validity-failure asymmetry — catalog invalid is red, generic invalid is skipped"
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'invalid\tguard.sh\ts/^echo ok$/if/\tyields bash -n invalid output\n' >> "$FX/tools/mutation-catalog.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'catalog mutant is bash -n invalid'; then
  ok "catalog invalid mutant is red"
else
  bad "(f1) expected rc=1 + catalog invalid; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
FX="$(new_fixture strong)"
baseline_with "$FX"
printf 'breaker\t^echo ok$\ts/echo ok/if/\n' >> "$FX/tools/mutation-operators.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'skip (bash -n invalid, harness artifact)'; then
  ok "generic invalid mutant is skipped-and-logged, never red"
else
  bad "(f2) expected rc=0 + skipped harness artifact; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(g) unrunnable pair — a killer red on the UNMUTATED sandbox is infra red"
FX="$(new_fixture strong)"
baseline_with "$FX"
# Replace the killer outright — appending `exit 7` after its own `exit $f` would be
# unreachable and the case would silently pass for the wrong reason.
printf '#!/usr/bin/env bash\nexit 7\n' > "$FX/guard-selftest.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm break ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && printf '%s' "$OUT" | grep -q 'unrunnable pair' \
  && printf '%s' "$OUT" | grep -q 'mutants_applied\|swept'; then
  ok "unrunnable pair is red and its mutants are not scored"
else
  bad "(g) expected rc=1 + unrunnable pair; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(h) baseline-missing — enforcing non-seed is red; seed mode is green with artifacts"
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'baseline-missing'; then
  ok "absent baseline in an enforcing run is the named infra red"
else
  bad "(h1) expected rc=1 + baseline-missing; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi
FX="$(new_fixture weak)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed \
        --baseline-out "$FX/seeded-baseline.tsv" --slow-out "$FX/seeded-slow.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && [[ -s "$FX/seeded-baseline.tsv" ]] \
  && grep -q '^# environment: ubuntu-latest SKIP_STRESS=1$' "$FX/seeded-baseline.tsv" \
  && grep -q '^# k=2$' "$FX/seeded-baseline.tsv" \
  && grep -q '^guard.sh::fail-open::1' "$FX/seeded-baseline.tsv" \
  && [[ -s "$FX/seeded-slow.tsv" ]]; then
  ok "seed mode exits green and writes a headed, populated baseline + slow list"
else
  bad "(h2) seed mode did not produce the expected artifacts; rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(i) baseline-environment-mismatch — named red, never a survivor diff"
for probe in "RUNNER_OS=macOS SKIP_STRESS=1" "RUNNER_OS=Linux SKIP_STRESS=" "RUNNER_OS=Linux SKIP_STRESS=1 MUTATION_SWEEP_K=3"; do
  FX="$(new_fixture weak)"
  baseline_with "$FX"
  # shellcheck disable=SC2086 # probe is a deliberate space-separated VAR=VAL list
  OUT="$( cd "$FX" && env GITHUB_ACTIONS=1 $probe bash "$SWEEP" --mode full 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] \
    && printf '%s' "$OUT" | grep -q 'baseline-environment-mismatch' \
    && ! printf '%s' "$OUT" | grep -q 'baseline-absent survivor'; then
    ok "mismatch [$probe] reds as itself, survivors not compared"
  else
    bad "(i) [$probe] expected the named mismatch and NO survivor diff; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
  fi
done

echo "(l) PR mode — empty diff exits 0; slow / multi-suite guards defer visibly"
FX="$(new_fixture strong)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'nothing to sweep'; then
  ok "zero touched guards exits 0 before any baseline resolution"
else
  bad "(l1) expected rc=0 + nothing to sweep; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
# The empty-diff exit must precede baseline resolution — prove it by removing the
# baseline entirely and keeping the enforcing environment. This is what keeps a
# doc-only PR (and the PR that first lands this harness) off the baseline-missing red.
FX="$(new_fixture strong)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! printf '%s' "$OUT" | grep -q 'baseline-missing'; then
  ok "empty PR diff never reaches the baseline-missing check"
else
  bad "(l2) empty PR diff reded on a missing baseline; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
# Slow killer -> the guard defers wholesale rather than being swept against a reduced
# criterion (which would grade mutants more weakly than the baseline that produced them).
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '# fixture slow list\n./guard-selftest.sh\t42\t2026-07-29\n' > "$FX/tools/mutation-slow-suites.tsv"
# The commit must TOUCH THE GUARD, or the PR-mode diff selects nothing and the case
# passes vacuously on the empty-diff exit instead of exercising deferral.
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm slow ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'deferred-to-nightly'; then
  ok "slow-suite guard defers with a visible report row"
else
  bad "(l3) expected a deferred-to-nightly row; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(m) exclusions preempt pairing — a guard in BOTH files is a lint error, via the harness"
# Driven THROUGH mutation-sweep.sh, not re-checked in this file. Case (k) lints the
# committed TSVs directly, which is a data lint; asserting the harness's own red branch
# by re-implementing its condition here would be the mirror shape CLAUDE.md warns about —
# it could not fail on a harness edit. The real tree has no such guard, so without this
# fixture the branch has zero end-to-end coverage.
FX="$(new_fixture strong)"
baseline_with "$FX"
printf '# fixture exclusions\nguard.sh\tdeliberately excluded\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\nguard.sh\t./guard-selftest.sh\tconflicting row\n' > "$FX/tools/mutation-pair-map.tsv"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'excluded AND carries pair-map rows'; then
  ok "conflicting exclusion + pair-map rows is red"
else
  bad "(m) expected rc=1 + the conflict red; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(n) argument contract — bad invocations die loudly rather than sweeping something wrong"
FX="$(new_fixture strong)"
for args in "--mode bogus" "--mode pr" "--frobnicate" ""; do
  # shellcheck disable=SC2086 # args is a deliberate space-separated argv fragment
  OUT="$( cd "$FX" && adv bash "$SWEEP" $args 2>&1 )"; RC=$?
  if [[ $RC -eq 2 ]] && printf '%s' "$OUT" | grep -q 'FATAL'; then
    ok "rejects [${args:-<no args>}]"
  else
    bad "(n) [${args:-<no args>}] expected rc=2 + FATAL; got rc=$RC"
  fi
done

echo "(o) --report writes the TSV to the named path instead of stdout"
FX="$(new_fixture strong)"
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --report "$FX/report.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && [[ -s "$FX/report.tsv" ]] \
  && head -1 "$FX/report.tsv" | grep -q '^guard	status	paired_selftest' \
  && grep -q '^guard\.sh	swept' "$FX/report.tsv" \
  && ! printf '%s' "$OUT" | grep -q '^guard	status'; then
  ok "report lands at the path and is kept off stdout"
else
  bad "(o) --report did not write the expected TSV; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

# ======================================================== live-tree lint cases
# (j) and (k) run against the REAL tree, not a fixture. They are pure resolution/parse
# lints — no mutation, no sandbox, no suite execution — so they are cheap enough for both
# per-push lanes, and they are what stops this harness from converging on green while the
# tree drifts underneath it.

echo "(j) universe rule — every in-universe guard in the REAL tree is accounted"
UNIV="$( cd "$REPO_ROOT" && git ls-files '*.sh' \
        | grep -v -- '-selftest\.sh$' | grep -v '/evals/' | grep -v '^tests/hooks-smoke/' | sort )"
UNACCOUNTED=""
EXCL_LIST="$(grep -v '^#' "$REPO_ROOT/tools/mutation-exclusions.tsv" | grep -v '^$' | cut -f1)"
MAP_LIST="$(grep -v '^#' "$REPO_ROOT/tools/mutation-pair-map.tsv" | grep -v '^$' | cut -f1)"
while IFS= read -r g; do
  [[ -n "$g" ]] || continue
  case $'\n'"$EXCL_LIST"$'\n' in *$'\n'"$g"$'\n'*) continue ;; esac
  same="$(dirname "$g")/$(basename "$g" .sh)-selftest.sh"
  [[ -f "$REPO_ROOT/$same" ]] && continue
  case $'\n'"$MAP_LIST"$'\n' in *$'\n'"$g"$'\n'*) continue ;; esac
  UNACCOUNTED="${UNACCOUNTED:+$UNACCOUNTED }$g"
done <<< "$UNIV"
if [[ -z "$UNACCOUNTED" ]]; then
  ok "all $(printf '%s\n' "$UNIV" | grep -c .) in-universe guards resolve"
else
  bad "(j) unaccounted guard(s) — add a same-stem suite, a pair-map row, or an exclusions row: $UNACCOUNTED"
fi
# The harness must reach the same verdict through its own accounting path.
OUT="$( cd "$REPO_ROOT" && adv bash "$SWEEP" --mode pr --base HEAD 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! printf '%s' "$OUT" | grep -q 'unaccounted guard'; then
  ok "the harness's own accounting agrees"
else
  bad "(j) harness accounting disagrees with the direct lint; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(k) TSV family lint — shape and resolution of every committed mutation-*.tsv"
lint_fail() { bad "(k) $*"; }
# Exclusions: path must be in-universe, must NOT also carry pair-map rows, reason non-empty.
while IFS=$'\t' read -r p reason; do
  case "$p" in ''|'#'*) continue ;; esac
  [[ -n "$reason" ]] || lint_fail "exclusions row has no reason: $p"
  case $'\n'"$MAP_LIST"$'\n' in
    *$'\n'"$p"$'\n'*) lint_fail "excluded guard also carries pair-map rows (exclusion preempts pairing): $p" ;;
  esac
  [[ -f "$REPO_ROOT/$p" ]] || lint_fail "exclusions row path does not exist: $p"
done < "$REPO_ROOT/tools/mutation-exclusions.tsv"
# Pair map: both sides must resolve on disk, note non-empty.
while IFS=$'\t' read -r g s note; do
  case "$g" in ''|'#'*) continue ;; esac
  [[ -f "$REPO_ROOT/$g" ]] || lint_fail "pair-map guard does not exist: $g"
  [[ -f "$REPO_ROOT/$s" ]] || lint_fail "pair-map selftest does not exist: $s"
  [[ -n "$note" ]] || lint_fail "pair-map row has no note: $g -> $s"
done < "$REPO_ROOT/tools/mutation-pair-map.tsv"
# Operators: unique non-empty ids, non-empty match/flip.
SEEN_OPS=""
while IFS=$'\t' read -r id m f; do
  case "$id" in ''|'#'*) continue ;; esac
  [[ -n "$m" && -n "$f" ]] || lint_fail "operator '$id' has an empty match or flip"
  case " $SEEN_OPS " in *" $id "*) lint_fail "duplicate operator id: $id" ;; esac
  SEEN_OPS="$SEEN_OPS $id"
done < "$REPO_ROOT/tools/mutation-operators.tsv"
[[ -n "$SEEN_OPS" ]] || lint_fail "no operators defined"
# Catalog: unique ids, guard in-universe and not excluded, sed non-empty, PATTERN-addressed
# (D-3 — a bare line address is not permitted; the emit-deadline site moved between two
# runs of this very ticket, and only the pattern-addressed entries survived it).
if [[ -f "$REPO_ROOT/tools/mutation-catalog.tsv" ]]; then
  SEEN_CAT=""
  while IFS=$'\t' read -r id g sd note; do
    case "$id" in ''|'#'*) continue ;; esac
    case " $SEEN_CAT " in *" $id "*) lint_fail "duplicate catalog id: $id" ;; esac
    SEEN_CAT="$SEEN_CAT $id"
    [[ -n "$sd" ]] || lint_fail "catalog row '$id' has an empty sed"
    [[ -n "$note" ]] || lint_fail "catalog row '$id' has no note"
    [[ -f "$REPO_ROOT/$g" ]] || lint_fail "catalog guard does not exist: $g (row $id)"
    case $'\n'"$EXCL_LIST"$'\n' in
      *$'\n'"$g"$'\n'*) lint_fail "catalog row '$id' targets an EXCLUDED guard: $g" ;;
    esac
    case "$sd" in
      [0-9]*) lint_fail "catalog row '$id' uses a bare line address — D-3 requires a pattern address" ;;
    esac
  done < "$REPO_ROOT/tools/mutation-catalog.tsv"
fi
# Slow suites: selftest resolves, seconds numeric, measured_at ISO-8601.
if [[ -f "$REPO_ROOT/tools/mutation-slow-suites.tsv" ]]; then
  while IFS=$'\t' read -r s secs when; do
    case "$s" in ''|'#'*) continue ;; esac
    [[ -f "$REPO_ROOT/$s" ]] || lint_fail "slow-suites selftest does not exist: $s"
    case "$secs" in ''|*[!0-9]*) lint_fail "slow-suites seconds is not an integer: $s -> '$secs'" ;; esac
    case "$when" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
      *) lint_fail "slow-suites measured_at is not ISO-8601: $s -> '$when'" ;;
    esac
  done < "$REPO_ROOT/tools/mutation-slow-suites.tsv"
fi
# Baseline: header present, survivor ids well-formed.
if [[ -f "$REPO_ROOT/tools/mutation-baseline.tsv" ]]; then
  grep -q '^# environment: ' "$REPO_ROOT/tools/mutation-baseline.tsv" || lint_fail "baseline has no '# environment:' header"
  grep -q '^# k=' "$REPO_ROOT/tools/mutation-baseline.tsv" || lint_fail "baseline has no '# k=' header"
  while IFS=$'\t' read -r sid _; do
    case "$sid" in ''|'#'*) continue ;; esac
    case "$sid" in
      catalog::*) : ;;
      *::*::*)    : ;;
      *) lint_fail "malformed baseline survivor id: $sid" ;;
    esac
  done < "$REPO_ROOT/tools/mutation-baseline.tsv"
fi
[[ $FAILS -eq 0 ]] && ok "TSV family is well-formed and resolves"

echo
if [[ $FAILS -eq 0 ]]; then
  echo "[mutation-sweep-selftest] all cases passed"
else
  echo "[mutation-sweep-selftest] $FAILS case(s) failed"
fi
exit "$FAILS"
