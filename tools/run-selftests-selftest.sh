#!/usr/bin/env bash
# run-selftests-selftest.sh — behavioral guard for tools/run-selftests.sh.
#
# Every case runs the REAL runner against a fixture tree of throwaway `*-selftest.sh` files
# under a private --root. Nothing here re-declares the runner's logic, and nothing greps its
# source for prose: the assertions are on exit status, on the named suites in the output, and
# on the contiguity of the replayed blocks.
#
# TMPDIR IS UNSET for every invocation. The runner allocates its scratch under
# `${TMPDIR:-/tmp}`, and mutation-sweep's killers export TMPDIR — leaving it inherited would
# make the default arm of that expansion unreachable and its mutants unkillable.
set -uo pipefail

FAILS=0
ok()   { echo "  pass:  $1"; }
fail() { echo "  FAIL:  $1"; FAILS=$((FAILS + 1)); }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/run-selftests.sh"
[[ -f "$RUNNER" ]] || { echo "run-selftests-selftest: missing $RUNNER" >&2; exit 2; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests-selftest.XXXXXX")" || exit 2
trap 'rm -rf "$BASE"' EXIT

# run_runner <fixture-root> [args...] -> writes $OUT, sets $RC
OUT=""; RC=0
run_runner() {
  local root="$1"; shift
  OUT="$BASE/out.$$.$RANDOM"
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST \
    bash "$RUNNER" --root "$root" "$@" > "$OUT" 2>&1
  RC=$?
}

# make_suite <root> <relpath> <exit-code> [body-line...]
make_suite() {
  local root="$1" rel="$2" code="$3"; shift 3
  mkdir -p "$root/$(dirname "$rel")"
  {
    echo '#!/usr/bin/env bash'
    local line
    for line in "$@"; do echo "$line"; done
    echo "exit $code"
  } > "$root/$rel"
}

echo "== run-selftests-selftest =="

# ---------------------------------------------------------------------------------------
# AC-2 — a failing suite reds the run, and EVERY failing suite is named.
# Two failures, not one: a runner that stops at the first red would pass a one-failure case.
# ---------------------------------------------------------------------------------------
R2="$BASE/ac2"; mkdir -p "$R2"
make_suite "$R2" "a-selftest.sh" 0 'echo alpha-ok'
make_suite "$R2" "b-selftest.sh" 1 'echo bravo-broke'
make_suite "$R2" "c-selftest.sh" 3 'echo charlie-broke'
make_suite "$R2" "d-selftest.sh" 0 'echo delta-ok'

run_runner "$R2"
[[ "$RC" -ne 0 ]] && ok "AC-2: a failing suite exits non-zero (rc=$RC)" \
                 || fail "AC-2: failing suites exited 0"
# Scoped to the FAILED-suites block, NOT the whole output. Every suite is named ANYWAY by its
# own ::group:: header, so an unscoped grep here passes on a runner that records only the first
# failure — measured: that mutant survived the unscoped form.
sed -n '/FAILED suites:/,$p' "$OUT" > "$BASE/ac2.failblock"
[[ -s "$BASE/ac2.failblock" ]] \
  && grep -q 'b-selftest\.sh (rc=1)' "$BASE/ac2.failblock" \
  && grep -q 'c-selftest\.sh (rc=3)' "$BASE/ac2.failblock" \
  && ok "AC-2: both failing suites are named with their exit codes" \
  || { fail "AC-2: not every failing suite was named"; sed 's/^/    | /' "$OUT"; }
# The passing suites must NOT be in the failure list — a runner that names everything names
# nothing.
grep -q 'a-selftest\.sh' "$BASE/ac2.failblock" \
  && fail "AC-2: a passing suite appears in the FAILED list" \
  || ok "AC-2: passing suites stay out of the failure list"
# A failing sweep must still run every suite, not abort at the first red.
grep -q 'delta-ok' "$OUT" \
  && ok "AC-2: suites after the first failure still ran" \
  || fail "AC-2: the sweep stopped at the first failing suite"

# ---------------------------------------------------------------------------------------
# AC-3a — an --exclude matching no discovered suite is a hard error.
# ---------------------------------------------------------------------------------------
R3="$BASE/ac3"; mkdir -p "$R3"
make_suite "$R3" "keep-selftest.sh" 0 'echo keep'
make_suite "$R3" "drop-selftest.sh" 0 'echo drop'

run_runner "$R3" --exclude "nowhere/ghost-selftest.sh"
[[ "$RC" -eq 2 ]] && grep -q 'stale exclusion' "$OUT" \
  && ok "AC-3: a stale --exclude is a hard error naming it stale (rc=$RC)" \
  || { fail "AC-3: stale --exclude did not hard-error (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# A LIVE --exclude must be honored: excluded suite absent, the other present, counts stated.
run_runner "$R3" --exclude "drop-selftest.sh"
[[ "$RC" -eq 0 ]] \
  && grep -q '2 discovered, 1 excluded, 1 to run' "$OUT" \
  && grep -q 'keep-selftest\.sh' "$OUT" \
  && ! grep -q 'drop-selftest\.sh' "$OUT" \
  && ok "AC-3: a live --exclude removes exactly that suite and the counts say so" \
  || { fail "AC-3: --exclude did not remove exactly one suite"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-3b — discovered/run disagreement reds, even when every suite that DID run passed.
# Driven through the runner's rejection-assertion seam (RUN_SELFTESTS_DROP_LAST), which
# drops one worklist entry after the counts are taken. Without a seam this arm could only be
# asserted in prose; the whole point is that a silently-truncated sweep must not read green.
# ---------------------------------------------------------------------------------------
R3B="$BASE/ac3b"; mkdir -p "$R3B"
make_suite "$R3B" "one-selftest.sh" 0 'echo one'
make_suite "$R3B" "two-selftest.sh" 0 'echo two'

OUT="$BASE/out.ac3b"
env -u TMPDIR -u SELFTEST_JOBS RUN_SELFTESTS_DROP_LAST=1 \
  bash "$RUNNER" --root "$R3B" > "$OUT" 2>&1
RC=$?
[[ "$RC" -eq 2 ]] && grep -q 'silent truncation' "$OUT" \
  && ok "AC-3: an all-green sweep that ran fewer suites than it discovered still reds" \
  || { fail "AC-3: truncated sweep did not red (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# Control: the SAME fixture without the seam is green. Proves the case above measured the
# reconciliation and not a broken fixture.
run_runner "$R3B"
[[ "$RC" -eq 0 ]] && ok "AC-3: control — the untruncated fixture is green" \
                 || { fail "AC-3: control fixture is not green (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-4 — SELFTEST_JOBS=1 and SELFTEST_JOBS=4 produce the same verdict over the same set.
# Asserted on BOTH a green set and a red one: a runner that always reds, or always greens,
# would satisfy either half alone.
# ---------------------------------------------------------------------------------------
R4G="$BASE/ac4-green"; mkdir -p "$R4G"
R4R="$BASE/ac4-red"; mkdir -p "$R4R"
i=1
while [[ $i -le 6 ]]; do
  make_suite "$R4G" "s$i-selftest.sh" 0 "echo green-$i"
  make_suite "$R4R" "s$i-selftest.sh" 0 "echo red-$i"
  i=$((i + 1))
done
make_suite "$R4R" "s4-selftest.sh" 1 'echo red-4-broke'

for root in "$R4G" "$R4R"; do
  label="$(basename "$root")"
  run_runner "$root" --jobs 1; rc1="$RC"; out1="$OUT"
  run_runner "$root" --jobs 4; rc4="$RC"; out4="$OUT"
  [[ "$rc1" -eq "$rc4" ]] \
    && ok "AC-4: $label — jobs=1 and jobs=4 agree on the verdict (rc=$rc1)" \
    || fail "AC-4: $label — jobs=1 rc=$rc1 but jobs=4 rc=$rc4"
  # Same verdict is not enough: the same SET must have run, in the same order.
  if diff <(grep '^::group::' "$out1") <(grep '^::group::' "$out4") >/dev/null; then
    ok "AC-4: $label — jobs=1 and jobs=4 report the identical suite set, in order"
  else
    fail "AC-4: $label — the reported suite set differs between jobs=1 and jobs=4"
    diff <(grep '^::group::' "$out1") <(grep '^::group::' "$out4") | sed 's/^/    | /'
  fi
done

# SELFTEST_JOBS (the env form the workflows use) must reach the same place as --jobs.
OUT="$BASE/out.ac4env"
env -u TMPDIR -u RUN_SELFTESTS_DROP_LAST SELFTEST_JOBS=3 \
  bash "$RUNNER" --root "$R4G" > "$OUT" 2>&1
RC=$?
[[ "$RC" -eq 0 ]] && grep -q 'jobs=3' "$OUT" \
  && ok "AC-4: SELFTEST_JOBS is honored as the concurrency source" \
  || { fail "AC-4: SELFTEST_JOBS was not honored"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-5 — each suite's output is one CONTIGUOUS group, never interleaved with another's.
#
# The fixtures are built to interleave under a naive `-P 4`: each prints its marker, sleeps,
# prints again. Run at jobs=4, the wall clocks overlap, so raw streams would braid. The
# assertion walks the replay and requires every line between a ::group:: and its ::endgroup::
# to carry that suite's own marker.
# ---------------------------------------------------------------------------------------
R5="$BASE/ac5"; mkdir -p "$R5"
i=1
while [[ $i -le 4 ]]; do
  make_suite "$R5" "p$i-selftest.sh" 0 \
    "echo MARK$i-first" 'sleep 0.4' "echo MARK$i-second" 'sleep 0.4' "echo MARK$i-third"
  i=$((i + 1))
done

run_runner "$R5" --jobs 4
[[ "$RC" -eq 0 ]] || { fail "AC-5: fixture sweep did not pass (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# Walk the replay: inside p<N>'s group, every MARK line must be MARK<N>.
#
# The two total counts are what stop this from passing vacuously. Without them, a runner that
# replayed NOTHING would satisfy the per-group check (no lines to leak) — and so would one
# that streamed live, since lines emitted outside any group are not inside a group either.
# 12 MARK lines must exist in the output, and all 12 must be inside their own suite's group.
awk '
  /^::group::/ { inblk=1; suite=$0; sub(/.*[[:space:]]/, "", suite); sub(/-selftest\.sh.*/, "", suite); next }
  /^::endgroup::/ { inblk=0; next }
  /MARK/ { total++ }
  inblk && /^MARK/ {
    want = "MARK" substr(suite, 2)
    if (index($0, want) != 1) { print "leak in " suite ": " $0; bad=1 }
    seen[suite]++; framed++
  }
  END { for (s in seen) if (seen[s] != 3) { print "group " s " carried " seen[s] " of its 3 lines"; bad=1 }
        if (total != 12)  { print "expected 12 MARK lines in the output, found " total; bad=1 }
        if (framed != 12) { print "expected 12 MARK lines inside groups, found " framed+0; bad=1 }
        exit bad ? 1 : 0 }
' "$OUT" > "$BASE/ac5.report"
if [[ -s "$BASE/ac5.report" ]]; then
  fail "AC-5: suite output interleaved across groups"
  sed 's/^/    | /' "$BASE/ac5.report"
else
  ok "AC-5: at jobs=4 every suite's output is contiguous inside its own group"
fi

# Every group opened is closed — an unbalanced frame breaks GitHub's log folding, which is the
# entire reason the output is captured rather than streamed.
opens="$(grep -c '^::group::' "$OUT")"
closes="$(grep -c '^::endgroup::' "$OUT")"
[[ "$opens" -eq 4 && "$closes" -eq 4 ]] \
  && ok "AC-5: 4 groups opened, 4 closed" \
  || fail "AC-5: unbalanced framing — $opens ::group:: vs $closes ::endgroup::"

# ---------------------------------------------------------------------------------------
# Usage floor — a bad argument or an empty run set must never read as a green sweep.
# ---------------------------------------------------------------------------------------
run_runner "$R2" --jobs 0
[[ "$RC" -eq 2 ]] && ok "usage: --jobs 0 is rejected" || fail "usage: --jobs 0 was accepted (rc=$RC)"

run_runner "$R2" --bogus
[[ "$RC" -eq 2 ]] && ok "usage: an unknown argument is rejected" || fail "usage: --bogus was accepted (rc=$RC)"

EMPTY="$BASE/empty"; mkdir -p "$EMPTY"
run_runner "$EMPTY"
[[ "$RC" -eq 2 ]] && grep -q 'discovered 0 suites' "$OUT" \
  && ok "usage: a tree with no suites reds instead of reporting an empty pass" \
  || { fail "usage: an empty tree did not red (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_runner "$R3" --exclude "keep-selftest.sh" --exclude "drop-selftest.sh"
[[ "$RC" -eq 2 ]] && ok "usage: excluding every suite reds instead of passing vacuously" \
                  || { fail "usage: an all-excluded sweep did not red (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "run-selftests-selftest: PASS"
  exit 0
fi
echo "run-selftests-selftest: FAIL ($FAILS)"
exit 1
