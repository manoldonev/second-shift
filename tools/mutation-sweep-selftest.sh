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
  # 755 like the real tree (107 of 110 tracked guards). The mode is load-bearing fixture
  # state: mutation application that replaces the guard's inode drops the exec bit, and
  # with core.fileMode=true that mode change alone defeats every `git diff --quiet`
  # byte-identity gate. At 644 there is no bit to lose, so (e) and (p) would pass here
  # while dark on every real guard.
  chmod 755 "$dir/guard.sh"
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

# Fleet fixture for the PR-lane cap: $2 trivial guards, each with its own fast same-stem
# killer, all landing in a SECOND commit so `--base HEAD~1` puts every one of them in the
# PR diff. The guards deliberately contain no operator site (no `exit 1`), so a swept
# guard applies zero mutants and a many-guard PR-mode run stays cheap. A separate builder
# rather than a make_fixture parameter: the single-guard cases keep their exact shape.
make_fleet_fixture() {
  local dir="$1" n="$2" i=1
  mkdir -p "$dir/tools"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
  while [[ $i -le $n ]]; do
    printf '#!/usr/bin/env bash\necho ok\nexit 0\n' > "$dir/guard$i.sh"
    chmod 755 "$dir/guard$i.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/guard$i-selftest.sh"
    i=$((i + 1))
  done
  ( cd "$dir" \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm guards ) >/dev/null 2>&1
}

# Weak fleet for the shard/merge cases: $2 guards, each carrying exactly one fail-open
# site behind a happy-path-only killer, so every guard contributes exactly one SURVIVOR —
# which is what makes a merged seed baseline's completeness assertable per guard.
# shellcheck disable=SC2016 # the single-quoted $-expressions are the FIXTURES' code, not ours
make_weak_fleet() {
  local dir="$1" n="$2" i=1
  mkdir -p "$dir/tools"
  printf '# fixture operators\nfail-open\texit 1\ts/exit 1/exit 0/\n' > "$dir/tools/mutation-operators.tsv"
  printf '# fixture exclusions\n' > "$dir/tools/mutation-exclusions.tsv"
  printf '# fixture pair map\n' > "$dir/tools/mutation-pair-map.tsv"
  printf '# fixture catalog\n' > "$dir/tools/mutation-catalog.tsv"
  while [[ $i -le $n ]]; do
    printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "bad" ]]; then\n  exit 1\nfi\necho ok\n' > "$dir/guard$i.sh"
    chmod 755 "$dir/guard$i.sh"
    { printf '#!/usr/bin/env bash\nH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
      printf 'out="$(bash "$H/guard%s.sh" good)"\n[[ "$out" == ok ]] || exit 1\nexit 0\n' "$i"
    } > "$dir/guard$i-selftest.sh"
    i=$((i + 1))
  done
  ( cd "$dir" \
    && git init -q . \
    && git add -A \
    && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm init ) >/dev/null 2>&1
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

echo "(p) mode preservation — an -x-gated weak killer must not score false kills"
# Invariant: applying a mutant preserves the guard's file mode. Several real killers
# precondition-gate on `-x` before exercising anything (is-inert-diff-selftest.sh,
# audit-selftest.sh); if mutation application replaced the guard's inode, the lost exec
# bit would fail that gate for EVERY mutant and the sweep would report this deliberately
# weak (happy-path-only) suite as 100% killing — the exact inversion the harness exists
# to prevent. Correct behavior: the fail-open mutant SURVIVES. No liveness scenario
# covers this for the same reason as the header: the sweep composes no pipeline verdict
# path. Case (e) pins the catalog tier's byte-identity gate at real-tree mode; this one
# pins the generic tier's application site.
FX="$(new_fixture weak)"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -x "$HERE/guard.sh" ]; then
  echo "[self-test] FATAL: guard not executable" >&2
  exit 1
fi
out="$(bash "$HERE/guard.sh" good)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm xgate ) >/dev/null 2>&1
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] \
  && printf '%s' "$OUT" | grep -q 'killed=0 survived=1' \
  && printf '%s' "$OUT" | grep -q 'baseline-absent survivor'; then
  ok "survivor exposed — exec bit held through mutation application"
else
  bad "(p) expected killed=0 survived=1 + rc=1; a kill here means the mutant write stripped the exec bit; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(q) PR mode — a multi-killer union defers wholesale, never sweeps a partial union"
# Invariant: the PR lane sweeps a guard only when its kill set is a SINGLE fast suite. A
# two-killer union must defer to nightly: sweeping a reduced kill set would grade mutants
# under a weaker criterion than the one that produced the baseline (manufacturing false
# reds on a merge-blocking lane), and sweeping the full union blows the lane's time
# bound, since a surviving mutant runs every killer. Every other case gives kill_set_for
# exactly one killer, so without this one a mutant DELETING the union defer survives the
# whole suite. The LOOSENING direction (`-ne 1` -> `-ne 99`) is NOT killed here — every
# guard then defers, which this case still accepts — it is killed by (r)'s positive
# swept=6 assertion. The two cases cover that line jointly, in opposite directions:
# weakening (r) silently reopens the loosening direction. Deferral must also be VISIBLE:
# the report row carries deferred-to-nightly with the full '+'-joined union. No liveness
# scenario covers this for the header's reason: the sweep composes no pipeline verdict path.
FX="$(new_fixture strong)"
baseline_with "$FX"
# Second killer via the pair map — same-stem pairing plus one map row is the union shape.
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/second-killer-selftest.sh"
printf 'guard.sh\t./second-killer-selftest.sh\tsecond killer forms a two-suite union\n' >> "$FX/tools/mutation-pair-map.tsv"
printf '\n# touched to put this guard in the PR diff\n' >> "$FX/guard.sh"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm union ) >/dev/null 2>&1
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && printf '%s' "$OUT" | grep -q 'multi-suite union (2 killers)' \
  && printf '%s' "$OUT" | grep -q 'guard\.sh	deferred-to-nightly	\./guard-selftest\.sh+\./second-killer-selftest\.sh' \
  && ! printf '%s' "$OUT" | grep -q 'guard\.sh	swept'; then
  ok "two-killer guard defers with the full union visible in its report row"
else
  bad "(q) expected a wholesale defer with the '+'-joined union row and no sweep; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(r) PR mode — the fast-guard cap sweeps six, defers the seventh visibly"
# Invariant: the PR lane sweeps at most six fast guards per push — the bound that keeps
# the merge-blocking CI step inside its timeout — and the overflow guard defers with a
# visible report row rather than being dropped. Seven single-killer guards cross a cap of
# six; no other case sweeps more than one guard in PR mode, so without this one a mutant
# raising or removing the cap survives. The 6/1 split and the reason string deliberately
# pin the cap's value: a deliberate cap change must update this case in the same PR.
FX="$TMPROOT/fleet$RANDOM$RANDOM"
make_fleet_fixture "$FX" 7
baseline_with "$FX"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode pr --base HEAD~1 2>&1 )"; RC=$?
SWEPT_N="$(printf '%s\n' "$OUT" | grep -c '	swept	')"
DEFER_N="$(printf '%s\n' "$OUT" | grep -c '	deferred-to-nightly	')"
if [[ $RC -eq 0 && "$SWEPT_N" -eq 6 && "$DEFER_N" -eq 1 ]] \
  && printf '%s' "$OUT" | grep -q 'PR-lane cap (6 fast guards already swept)'; then
  ok "cap swept 6 guards, deferred 1 with the cap named as the reason"
else
  bad "(r) expected swept=6 deferred=1 + the cap reason; got rc=$RC swept=$SWEPT_N deferred=$DEFER_N"; printf '%s\n' "$OUT" | tail -6
fi

echo "(s) leading-hyphen operator matches — the committed cmp rows enumerate real sites"
# The committed comparison operators' match strings BEGIN WITH A HYPHEN, so site
# enumeration must terminate option parsing before the pattern. Without that, grep reads
# the match as OPTIONS: one row becomes the pattern 'q|-ne' (matching every line
# containing 'q', all discarded as no-op flips), the other errors and enumerates zero
# sites — silently, in both directions. This case drives the REAL committed rows through
# the real harness against a guard holding exactly one genuine site per operator, plus a
# decoy comment that matches only under the mis-parse. Correct behavior: two mutants,
# both killed, zero no-op skips. The mis-parse instead yields one mutant and a no-op
# skip on the decoy line (or an enumeration red), failing both assertions.
FX="$(new_fixture strong)"
grep '^cmp-' "$REPO_ROOT/tools/mutation-operators.tsv" > "$FX/tools/mutation-operators.tsv"
if [[ "$(grep -c . "$FX/tools/mutation-operators.tsv")" -eq 2 ]]; then
  ok "committed operators file still carries both cmp-* rows"
else
  bad "(s) expected exactly two cmp-* rows in the committed operators file"
fi
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
# quick decoy: this comment line matches only a mis-parsed comparison pattern.
if [ "$#" -eq 0 ]; then
  echo "missing argument"
  exit 3
fi
if [ -z "$1" ]; then
  echo "empty argument"
  exit 3
fi
echo ok
EOF
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f=0
bash "$HERE/guard.sh" >/dev/null 2>&1; [[ $? -eq 3 ]] || f=$((f+1))
bash "$HERE/guard.sh" "" >/dev/null 2>&1; [[ $? -eq 3 ]] || f=$((f+1))
out="$(bash "$HERE/guard.sh" good)"; [[ "$out" == "ok" ]] || f=$((f+1))
exit $f
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm cmp ) >/dev/null 2>&1
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] \
  && printf '%s' "$OUT" | grep -q 'applied=2 killed=2 survived=0' \
  && ! printf '%s' "$OUT" | grep -q 'skip (no-op flip)'; then
  ok "cmp-eq and cmp-z each enumerated their one real site and mutated it"
else
  bad "(s) expected applied=2 killed=2 survived=0 and no no-op skips; got rc=$RC"; printf '%s\n' "$OUT" | tail -6
fi

echo "(t) a match grep cannot compile is a named red, never a silent zero-site pass"
# The other half of the enumeration contract: when grep exits >= 2 the match never ran
# as a pattern, and treating that as 'no sites' reports every guard clean against a
# mutation class that was never applied. The red must name the operator.
FX="$(new_fixture strong)"
printf '# fixture operators\nbadre\t(\ts/x/y/\n' > "$FX/tools/mutation-operators.tsv"
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'operator match does not enumerate.*badre'; then
  ok "non-compilable match reds loudly and names the operator"
else
  bad "(t) expected rc=1 + the named enumeration red; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
fi

echo "(u) shard argument contract — malformed specs die loudly; 1/1 is exactly unsharded"
FX="$(new_fixture strong)"
for args in \
  "--mode full --shard 0/3" "--mode full --shard 4/3" "--mode full --shard x/3" \
  "--mode full --shard 3" "--mode full --shard 2/" "--mode full --shard 08/10" \
  "--mode pr --base HEAD --shard 1/2" "--mode merge" "--mode full --shards-dir ." \
  "--mode pr --base HEAD --seed" "--mode merge --shards-dir /nonexistent-dir-xyz"; do
  # shellcheck disable=SC2086 # args is a deliberate space-separated argv fragment
  OUT="$( cd "$FX" && adv bash "$SWEEP" $args 2>&1 )"; RC=$?
  if [[ $RC -eq 2 ]] && printf '%s' "$OUT" | grep -q 'FATAL'; then
    ok "rejects [$args]"
  else
    bad "(u) [$args] expected rc=2 + FATAL; got rc=$RC"
  fi
done
OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full --shard 1/1 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'killed=1 survived=0'; then
  ok "--shard 1/1 sweeps the whole (one-guard) universe like an unsharded run"
else
  bad "(u) --shard 1/1 expected killed=1 survived=0 rc=0; got rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(v) shard partition — disjoint, complete, deterministic; excluded rows on shard 1 only"
# Invariant: --shard i/N partitions the non-excluded universe — every guard lands in
# EXACTLY one shard, no shard is empty at 7 guards / 3 shards, and the same spec always
# yields the same set. A partition that returns everything to every shard (duplicated
# work AND duplicated merge rows) or nothing to some shard (silently unswept guards)
# must fail here. The excluded guard's zero-count row is universe bookkeeping and must
# come from shard 1 exactly once, or the merged report carries duplicates.
FX="$TMPROOT/shardfleet$RANDOM$RANDOM"
make_fleet_fixture "$FX" 7
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/excluded-guard.sh"
chmod 755 "$FX/excluded-guard.sh"
printf 'excluded-guard.sh\tfixture exclusion\n' >> "$FX/tools/mutation-exclusions.tsv"
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm excl ) >/dev/null 2>&1
SHARD_OK=1
for i in 1 2 3; do
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode full --shard "$i/3" --report "$FX/rep$i.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 && -s "$FX/rep$i.tsv" ]] || { SHARD_OK=0; bad "(v) shard $i/3 run failed rc=$RC"; }
done
if [[ $SHARD_OK -eq 1 ]]; then
  TOTAL="$(awk -F'\t' '$2=="swept"{print $1}' "$FX"/rep[123].tsv | grep -c .)"
  UNIQ="$(awk -F'\t' '$2=="swept"{print $1}' "$FX"/rep[123].tsv | sort -u | grep -c .)"
  MIN=7; MAX=0
  for i in 1 2 3; do
    n="$(awk -F'\t' '$2=="swept"' "$FX/rep$i.tsv" | grep -c .)"
    [[ "$n" -lt "$MIN" ]] && MIN=$n
    [[ "$n" -gt "$MAX" ]] && MAX=$n
  done
  if [[ "$TOTAL" -eq 7 && "$UNIQ" -eq 7 && "$MIN" -ge 1 && "$MAX" -le 6 ]]; then
    ok "3 shards cover all 7 guards exactly once (min=$MIN max=$MAX per shard)"
  else
    bad "(v) partition broken: total=$TOTAL uniq=$UNIQ min=$MIN max=$MAX (want 7/7, every shard nonempty and partial)"
  fi
  ( cd "$FX" && adv bash "$SWEEP" --mode full --shard 2/3 --report "$FX/rep2again.tsv" ) >/dev/null 2>&1
  if cmp -s <(awk -F'\t' '$2=="swept"{print $1}' "$FX/rep2.tsv") \
            <(awk -F'\t' '$2=="swept"{print $1}' "$FX/rep2again.tsv"); then
    ok "the same shard spec re-selects the same guard set"
  else
    bad "(v) shard 2/3 selected a different set on a second run — partition is unstable"
  fi
  E1="$(grep -c "^excluded-guard\.sh	excluded" "$FX/rep1.tsv")"
  E23="$(grep -c "^excluded-guard\.sh	excluded" "$FX/rep2.tsv" "$FX/rep3.tsv" | awk -F: '{s+=$2} END{print s}')"
  if [[ "$E1" -eq 1 && "$E23" -eq 0 ]]; then
    ok "excluded zero-count row emits from shard 1 only"
  else
    bad "(v) excluded row emission: shard1=$E1 shards2+3=$E23 (want 1 and 0)"
  fi
fi

echo "(w) sharded seed + merge — one header block, all survivors, whole-universe coverage"
# Invariant chain: (1) each seed shard publishes report+baseline+slow for ITS guards;
# (2) merge concatenates into ONE report with ONE header line and one row per guard,
# ONE baseline carrying exactly one '# environment:' / '# k=' block with every shard's
# survivors, and ONE slow list deduplicated per suite at the max measurement; (3) a
# missing shard report is the named 'merge incomplete' red carrying the dead shard's
# guard names — the datapoint the monolithic job's destroyed logs never produced; a
# duplicated one is the named 'merge overlap' red.
FX="$TMPROOT/mergefx$RANDOM$RANDOM"
make_weak_fleet "$FX" 4
mkdir -p "$FX/shards/s1" "$FX/shards/s2"
MERGE_OK=1
for i in 1 2; do
  OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard "$i/2" \
          --report "$FX/shards/s$i/mutation-report.tsv" \
          --baseline-out "$FX/shards/s$i/mutation-baseline.tsv" \
          --slow-out "$FX/shards/s$i/mutation-slow-suites.tsv" 2>&1 )"; RC=$?
  [[ $RC -eq 0 && -s "$FX/shards/s$i/mutation-baseline.tsv" ]] \
    || { MERGE_OK=0; bad "(w) seed shard $i/2 failed rc=$RC"; printf '%s\n' "$OUT" | tail -4; }
done
if [[ $MERGE_OK -eq 1 ]]; then
  # Crafted slow files exercise the per-suite dedup: real sub-second fixture suites never
  # cross the slow threshold, so the seeded lists are empty. These are merge INPUTS —
  # the merge itself still runs in production code.
  printf '# fixture slow header\nshared-selftest.sh\t7\t2026-07-30\nonly1-selftest.sh\t6\t2026-07-30\n' \
    > "$FX/shards/s1/mutation-slow-suites.tsv"
  printf '# fixture slow header\nshared-selftest.sh\t9\t2026-07-30\nonly2-selftest.sh\t8\t2026-07-30\n' \
    > "$FX/shards/s2/mutation-slow-suites.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards" \
          --report "$FX/merged-report.tsv" --baseline-out "$FX/merged-baseline.tsv" \
          --slow-out "$FX/merged-slow.tsv" 2>&1 )"; RC=$?
  ROWS_OK=1
  for g in 1 2 3 4; do
    [[ "$(grep -c "^guard$g\.sh	swept" "$FX/merged-report.tsv")" -eq 1 ]] || ROWS_OK=0
    grep -q "^guard$g\.sh::fail-open::1	" "$FX/merged-baseline.tsv" || ROWS_OK=0
  done
  if [[ $RC -eq 0 && $ROWS_OK -eq 1 ]] \
    && [[ "$(grep -c '^guard	status	paired_selftest' "$FX/merged-report.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^# environment:' "$FX/merged-baseline.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^# k=' "$FX/merged-baseline.tsv")" -eq 1 ]]; then
    ok "merged report has one header + one row per guard; baseline has one header block + all survivors"
  else
    bad "(w) merge output malformed; rc=$RC rows_ok=$ROWS_OK"; printf '%s\n' "$OUT" | tail -6
  fi
  if [[ "$(grep -c '^# fixture slow header' "$FX/merged-slow.tsv")" -eq 1 ]] \
    && [[ "$(grep -c '^shared-selftest\.sh	' "$FX/merged-slow.tsv")" -eq 1 ]] \
    && grep -q '^shared-selftest\.sh	9	' "$FX/merged-slow.tsv" \
    && grep -q '^only1-selftest\.sh	6	' "$FX/merged-slow.tsv" \
    && grep -q '^only2-selftest\.sh	8	' "$FX/merged-slow.tsv"; then
    ok "merged slow list dedups the shared suite at its max measurement"
  else
    bad "(w) merged slow list wrong"; cat "$FX/merged-slow.tsv"
  fi
  cp -R "$FX/shards" "$FX/shards-missing"
  rm -f "$FX/shards-missing/s2/mutation-report.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-missing" \
          --report "$FX/m2.tsv" --baseline-out "$FX/b2.tsv" --slow-out "$FX/sl2.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'merge incomplete: no shard reported guard guard2\.sh'; then
    ok "a dead shard's guards are NAMED by the merge red"
  else
    bad "(w) expected rc=1 + 'merge incomplete' naming guard2.sh; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
  cp -R "$FX/shards" "$FX/shards-dup"
  cp "$FX/shards-dup/s1/mutation-report.tsv" "$FX/shards-dup/s2/mutation-report.tsv"
  OUT="$( cd "$FX" && adv bash "$SWEEP" --mode merge --shards-dir "$FX/shards-dup" \
          --report "$FX/m3.tsv" --baseline-out "$FX/b3.tsv" --slow-out "$FX/sl3.tsv" 2>&1 )"; RC=$?
  if [[ $RC -eq 1 ]] && printf '%s' "$OUT" | grep -q 'merge overlap'; then
    ok "duplicated shard rows are the named partition-broken red"
  else
    bad "(w) expected rc=1 + 'merge overlap'; got rc=$RC"; printf '%s\n' "$OUT" | tail -5
  fi
fi
# An EMPTY seed shard (N exceeds the guard count) must still publish its headed artifacts,
# or the merge reds every such run on a missing shard baseline.
FX="$(new_fixture weak)"
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --seed --shard 2/2 \
        --report "$FX/r.tsv" --baseline-out "$FX/b.tsv" --slow-out "$FX/s.tsv" 2>&1 )"; RC=$?
if [[ $RC -eq 0 && -s "$FX/b.tsv" && -s "$FX/r.tsv" ]] \
  && grep -q '^# environment: ' "$FX/b.tsv" \
  && [[ "$(grep -vc '^#' "$FX/b.tsv")" -eq 0 ]]; then
  ok "an empty seed shard still writes a headed, survivor-free baseline"
else
  bad "(w) empty seed shard did not publish artifacts; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(x) sharded enforcing run — another shard's baseline rows are out of scope, not 'now KILLED'"
# The shrink warn is only decidable for guards THIS shard swept: under sharding, every
# shard seeing every other shard's rows as 'now KILLED' would tell the operator to drop
# ~ (N-1)/N of a healthy baseline. Unsharded behavior (warn on every row) is asserted by
# case (d) and re-pinned here on the same fixture.
FX="$TMPROOT/scopefx$RANDOM$RANDOM"
make_fleet_fixture "$FX" 2
baseline_with "$FX" 'guard2.sh::fail-open::1'
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | grep -q 'now KILLED: guard2\.sh::fail-open::1'; then
  ok "unsharded full run still warns on the stale row"
else
  bad "(x) unsharded run should warn 'now KILLED'; rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi
OUT="$( cd "$FX" && enf bash "$SWEEP" --mode full --shard 1/2 2>&1 )"; RC=$?
if [[ $RC -eq 0 ]] && ! printf '%s' "$OUT" | grep -q 'now KILLED'; then
  ok "shard 1/2 (which does not sweep guard2.sh) stays silent about its row"
else
  bad "(x) shard 1/2 warned about another shard's row (or reded); rc=$RC"; printf '%s\n' "$OUT" | tail -4
fi

echo "(y) killer stdin isolation — a killer cannot consume the harness's stdin"
# Invariant: run_killer gives each killer its own /dev/null stdin. 30 of the 48 swept
# guards contain a read loop; a mutant that breaks one's input redirection leaves it
# reading whatever stdin the harness inherited rather than its own.
# Asserted by consumption rather than by hanging: this case would otherwise have to BLOCK
# to fail. A killer that eats the sentinel here is one that would misread on a real guard.
# NOT the cause of the dead nightly shards, though it was first blamed for them — those
# survived this fix unchanged and belong to (z) below.
FX="$(new_fixture strong)"
baseline_with "$FX"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Isolated stdin makes this EOF at once; leaked stdin makes it eat the caller's sentinel.
IFS= read -r _ 2>/dev/null || true
out="$(bash "$HERE/guard.sh" bad)"; rc=$?
[[ $rc -eq 1 && "$out" == "violation" ]] || exit 1
exit 0
EOF
( cd "$FX" && git add -A && git -c user.email=f@e.invalid -c user.name=f commit -qm stdin ) >/dev/null 2>&1
LEFTOVER="$( printf 'SENTINEL\n' | { ( cd "$FX" && enf bash "$SWEEP" --mode full ) >/dev/null 2>&1; IFS= read -r l || true; printf '%s' "$l"; } )"
if [[ "$LEFTOVER" == "SENTINEL" ]]; then
  ok "harness stdin survived the killer runs"
else
  bad "(y) a killer consumed the harness's stdin (leftover='$LEFTOVER'); a guard's read loop would block here instead"
fi

echo "(z) killer time bound — a mutant that makes its guard SPIN cannot hang the sweep"
# The failure this pins killed three shards of every 10-shard nightly, deterministically,
# and destroyed their logs each time. `cmp-z` inverts the EOF-tolerance clause of the
# repo's standard read idiom — `while IFS= read -r line || [[ -n "$line" ]]` becomes
# `|| [[ -z "$line" ]]` — and at EOF that clause is permanently TRUE, so the guard spins
# forever at 100% CPU. Its killer never returns, and `run_killer` had no time bound, so
# the shard emitted no further line until the job timed out with the log unfinalized.
# Three live guards carry that idiom; the k budget decides which are armed, which is why
# shard 8 (scaffold-review-context.sh, ordinal 5 > k=2) survived while shards 4 and 9
# (ordinal 1) did not. This fixture reproduces the armed shape at ordinal 1.
#
# Unlike (y), this case CAN assert by hanging, because it brings its own outer watchdog:
# the harness runs under a wall-clock bound here, and blowing it is the failure. That is
# the only honest way to pin "does not hang" — asserting by proxy is what let this pass
# unnoticed while three shards died.
FX="$TMPROOT/fxspin$RANDOM$RANDOM"
mkdir -p "$FX/tools"
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
# Carries the repo's EOF-tolerant read idiom verbatim — the real mutation site.
while IFS= read -r line || [[ -n "$line" ]]; do
  :
done
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" </dev/null)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
printf '# fixture operators\ncmp-z\t-z |-n \ts/-z /__MUT__/g; s/-n /-z /g; s/__MUT__/-n /g\n' \
  > "$FX/tools/mutation-operators.tsv"
printf '# fixture exclusions\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\n'   > "$FX/tools/mutation-pair-map.tsv"
printf '# fixture catalog\n'    > "$FX/tools/mutation-catalog.tsv"
( cd "$FX" && git init -q . && git add -A \
  && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm spin ) >/dev/null 2>&1

SPIN_LOG="$FX/sweep.log"
( cd "$FX" && adv env MUTATION_SWEEP_KILLER_TIMEOUT_S=5 bash "$SWEEP" --mode full ) \
  >"$SPIN_LOG" 2>&1 </dev/null &
SPIN_PID=$!
# Outer bound: 5s killer timeout + sandbox/precheck slack. Generous enough that a healthy
# harness never trips it, tight enough that a hung one fails fast instead of stalling CI.
SPIN_DEADLINE=$(( $(date +%s) + 90 ))
SPIN_HUNG=0
while kill -0 "$SPIN_PID" 2>/dev/null; do
  if [[ "$(date +%s)" -ge "$SPIN_DEADLINE" ]]; then SPIN_HUNG=1; break; fi
  sleep 0.2
done
if [[ $SPIN_HUNG -eq 1 ]]; then
  kill -9 "$SPIN_PID" 2>/dev/null
  pkill -9 -f "$FX/guard.sh" 2>/dev/null
  wait "$SPIN_PID" 2>/dev/null
  bad "(z) the sweep HUNG on a spinning mutant — run_killer has no time bound"
else
  wait "$SPIN_PID" 2>/dev/null; SPIN_RC=$?
  SPIN_OUT="$(cat "$SPIN_LOG")"
  if [[ $SPIN_RC -ne 0 ]]; then
    bad "(z) sweep completed but exited $SPIN_RC"; printf '%s\n' "$SPIN_OUT" | tail -5
  elif ! printf '%s' "$SPIN_OUT" | grep -q 'killer timeout'; then
    bad "(z) the timed-out killer was not named in the log — a silent kill hides a spin"
    printf '%s\n' "$SPIN_OUT" | tail -5
  elif ! printf '%s' "$SPIN_OUT" | grep -qE 'swept guard\.sh — applied=1 killed=1 survived=0'; then
    bad "(z) spun mutant not scored as killed-by-timeout"; printf '%s\n' "$SPIN_OUT" | tail -5
  else
    ok "spinning mutant is bounded, scored as killed, and NAMED in the log"
  fi
fi

echo "(aa) killer bound SCALES per suite — a fast suite is not held to the slow ceiling"
# The bound in (z) is flat only because that fixture pins the ceiling low. A flat bound
# bounds one killer but NOT a shard: a guard whose mutants all spin costs k x the bound,
# and the first bounded seed run still lost a 60-min shard to that accumulation on a
# ~15-min cost model. So the contract is `4 x the suite's measured unmutated time`,
# floored and capped — and this case pins that the FLOOR is what a ~0s fixture suite gets,
# not the ceiling. Asserted through the logged bound, which is the operator-visible number.
# Floor is overridden to 3s so the case proves scaling in seconds rather than in a minute.
FX="$TMPROOT/fxscale$RANDOM$RANDOM"
mkdir -p "$FX/tools"
cat > "$FX/guard.sh" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r line || [[ -n "$line" ]]; do
  :
done
echo ok
exit 0
EOF
chmod 755 "$FX/guard.sh"
cat > "$FX/guard-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$HERE/guard.sh" </dev/null)"
[[ "$out" == "ok" ]] || exit 1
exit 0
EOF
printf '# fixture operators\ncmp-z\t-z |-n \ts/-z /__MUT__/g; s/-n /-z /g; s/__MUT__/-n /g\n' \
  > "$FX/tools/mutation-operators.tsv"
printf '# fixture exclusions\n' > "$FX/tools/mutation-exclusions.tsv"
printf '# fixture pair map\n'   > "$FX/tools/mutation-pair-map.tsv"
printf '# fixture catalog\n'    > "$FX/tools/mutation-catalog.tsv"
( cd "$FX" && git init -q . && git add -A \
  && git -c user.email=fixture@example.invalid -c user.name=fixture commit -qm scale ) >/dev/null 2>&1

SCALE_LOG="$FX/sweep.log"
( cd "$FX" && adv env MUTATION_SWEEP_KILLER_TIMEOUT_S=300 MUTATION_SWEEP_KILLER_MIN_S=3 \
    bash "$SWEEP" --mode full ) >"$SCALE_LOG" 2>&1 </dev/null &
SCALE_PID=$!
SCALE_DEADLINE=$(( $(date +%s) + 90 ))
SCALE_HUNG=0
while kill -0 "$SCALE_PID" 2>/dev/null; do
  if [[ "$(date +%s)" -ge "$SCALE_DEADLINE" ]]; then SCALE_HUNG=1; break; fi
  sleep 0.2
done
if [[ $SCALE_HUNG -eq 1 ]]; then
  kill -9 "$SCALE_PID" 2>/dev/null; pkill -9 -f "$FX/guard.sh" 2>/dev/null
  wait "$SCALE_PID" 2>/dev/null
  bad "(aa) sweep did not finish — a ~0s suite was held to the 300s ceiling, not the floor"
else
  wait "$SCALE_PID" 2>/dev/null
  SCALE_OUT="$(cat "$SCALE_LOG")"
  if printf '%s' "$SCALE_OUT" | grep -q 'killer timeout (3s exceeded'; then
    ok "fast suite bounded at the 3s floor, not the 300s ceiling"
  else
    bad "(aa) expected the floor in the logged bound; got:"
    printf '%s\n' "$SCALE_OUT" | grep 'killer timeout' | head -2
  fi
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
# Operators: unique non-empty ids, non-empty match/flip, and every match must COMPILE as
# an ERE when passed after grep's option terminator — a match grep cannot compile
# enumerates zero sites, and the PR lane's diff scoping means the PR that commits such a
# row may never itself sweep a guard, so this per-push lint is the row's first executable
# check.
SEEN_OPS=""
while IFS=$'\t' read -r id m f; do
  case "$id" in ''|'#'*) continue ;; esac
  [[ -n "$m" && -n "$f" ]] || lint_fail "operator '$id' has an empty match or flip"
  case " $SEEN_OPS " in *" $id "*) lint_fail "duplicate operator id: $id" ;; esac
  SEEN_OPS="$SEEN_OPS $id"
  printf '' | grep -qE -- "$m" 2>/dev/null
  [[ $? -le 1 ]] || lint_fail "operator '$id' match is not a grep -E-compilable pattern: $m"
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
