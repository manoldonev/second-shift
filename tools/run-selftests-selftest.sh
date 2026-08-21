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
#
# LEAN_JOB_CEILING is SCRUBBED unless a case opts in through $CEILING, and that scrub is not
# hygiene — it is what makes the jobs assertions below mean anything. The lean gate exports that
# variable into every milestone-3 child, and one of those children is the sweep that runs this
# file, so an inherited ceiling would silently clip the value every ceiling case asserts.
#
# LEAN_SELFTEST_CACHE_DIR (#563) is scrubbed for the identical reason and a sharper consequence:
# the lean gate exports a STORE too, and an inherited one would turn the cache ON in every case
# below that asserts nothing is served without --cache-dir. The #563 cases at the end of this
# file set it deliberately, one invocation at a time, and never through this driver.
OUT=""; RC=0
CEILING=""
run_runner() {
  local root="$1"; shift
  OUT="$BASE/out.$$.$RANDOM"
  if [[ -n "$CEILING" ]]; then
    env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u LEAN_SELFTEST_CACHE_DIR \
      LEAN_JOB_CEILING="$CEILING" \
      bash "$RUNNER" --root "$root" "$@" > "$OUT" 2>&1
  else
    env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u LEAN_SELFTEST_CACHE_DIR \
      -u LEAN_JOB_CEILING \
      bash "$RUNNER" --root "$root" "$@" > "$OUT" 2>&1
  fi
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
#
# THIS CASE HAND-ROLLS ITS `env`, so it carries both of the driver's scrubs itself — the header
# above says why each one matters — and the hostile ceiling in front of it is the assertion, not
# scenery. Without the scrub an ambient ceiling below 3 clips the very number being asserted, and
# the case then reds for a reason that has nothing to do with SELFTEST_JOBS. That is not
# hypothetical: the lean gate exports a ceiling into every milestone-3 child, one of which is the
# sweep that runs this file, so the leak surfaces only on a machine running enough lanes to push
# the ceiling under 3 — somebody else's concurrency deciding whether this suite passes. Setting
# one here makes a dropped scrub fail EVERYWHERE instead of only there.
OUT="$BASE/out.ac4env"
LEAN_JOB_CEILING=2 env -u TMPDIR -u RUN_SELFTESTS_DROP_LAST -u LEAN_JOB_CEILING -u LEAN_SELFTEST_CACHE_DIR \
  SELFTEST_JOBS=3 bash "$RUNNER" --root "$R4G" > "$OUT" 2>&1
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
# A worker that writes no verdict is INFRA, never a pass. Documented guarantee, and the one
# path a fixture cannot reach on its own — a suite has no handle on its worker's results dir —
# so it goes through the RUN_SELFTESTS_DROP_RC seam. Both suites here EXIT 0; if a missing
# verdict were read as their exit code, the sweep would be green.
# ---------------------------------------------------------------------------------------
RCM="$BASE/norc"; mkdir -p "$RCM"
make_suite "$RCM" "alpha-selftest.sh" 0 'echo alpha-ok'
make_suite "$RCM" "beta-selftest.sh" 0 'echo beta-ok'

OUT="$BASE/out.norc"
env -u TMPDIR -u RUN_SELFTESTS_DROP_LAST RUN_SELFTESTS_DROP_RC=1 \
  bash "$RUNNER" --root "$RCM" --jobs 2 > "$OUT" 2>&1
RC=$?
# rc=3, not merely non-zero: this fixture is the REAL shape #527 reserves the code for — every
# worker died without scoring its suite — so binding it to the exact parent code here is what ties
# the reserved value to the path a consumer's lane actually takes.
[[ "$RC" -eq 3 ]] \
  && grep -q 'alpha-selftest\.sh (rc=125)' "$OUT" \
  && grep -q 'beta-selftest\.sh (rc=125)' "$OUT" \
  && ok "no-verdict: a verdict-less worker reds as rc=125 per suite, and the sweep exits the reserved 3" \
  || { fail "no-verdict: a verdict-less worker did not red as 125 into a parent 3 (rc=$RC)"; sed 's/^/    | /' "$OUT"; }
# The infra cause must be SAID, not just coded — 125 is otherwise indistinguishable from a
# suite that genuinely exited 125.
[[ "$(grep -c 'no verdict written' "$OUT")" -eq 2 ]] \
  && ok "no-verdict: each verdict-less suite is named as infra, not as a suite result" \
  || { fail "no-verdict: the infra cause was not stated per suite"; sed 's/^/    | /' "$OUT"; }
# Control: the same fixture without the seam is green, so the case above measures the seam.
run_runner "$RCM" --jobs 2
[[ "$RC" -eq 0 ]] && ok "no-verdict: control — the same fixture is green when verdicts are written" \
                 || { fail "no-verdict: control fixture is not green (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# #527 AC-1 — the RESERVED PARENT CODE, and the condition on it is ALL, never ANY.
#
# The classification is the recorded rc, so a suite that genuinely exits 125 lands in the infra
# class exactly like a worker that wrote no verdict — deliberate, and stated in the no-verdict
# block above. That is what lets these cases be driven from plain fixtures rather than through
# the DROP_RC seam, which is all-or-nothing and so cannot express a MIXED sweep at all.
#
# THE MIXED CASE IS THE FAIL-OPEN GUARD and the reason the all-infra case is not enough on its
# own: a runner that collapsed to 3 on ANY infra failure would report a genuinely red branch as
# infrastructure, which downstream costs no fix attempt and re-spawns until the continuation
# budget is gone — a red branch that never reds.
# ---------------------------------------------------------------------------------------
INF="$BASE/infra-all"; mkdir -p "$INF"
make_suite "$INF" "alpha-selftest.sh" 125 'echo alpha-infra'
make_suite "$INF" "beta-selftest.sh"  125 'echo beta-infra'
make_suite "$INF" "gamma-selftest.sh" 0   'echo gamma-ok'
run_runner "$INF" --jobs 2
[[ "$RC" -eq 3 ]] \
  && ok "AC-1: every failure in the infra class ⇒ the reserved exit 3" \
  || { fail "AC-1: an all-infra sweep exited $RC, not the reserved 3"; sed 's/^/    | /' "$OUT"; }
# The split must be READABLE, not only encoded: an operator reading a log sees why the sweep
# claimed infrastructure, and a consumer debugging a reclassification has the count to point at.
grep -q '2 failed (2 infrastructure)' "$OUT" \
  && grep -q 'Exiting 3 (reserved)' "$OUT" \
  && ok "AC-1: the summary names the infra split and the reserved code is announced" \
  || { fail "AC-1: the infra split was not reported in the summary"; sed 's/^/    | /' "$OUT"; }

MIX="$BASE/infra-mixed"; mkdir -p "$MIX"
make_suite "$MIX" "alpha-selftest.sh" 125 'echo alpha-infra'
make_suite "$MIX" "beta-selftest.sh"  1   'echo beta-genuinely-red'
run_runner "$MIX" --jobs 2
[[ "$RC" -eq 1 ]] \
  && ok "AC-1: one genuinely red suite alongside an infra failure still exits 1" \
  || { fail "AC-1: a mixed sweep exited $RC, not 1 — a red branch would read as infrastructure"; sed 's/^/    | /' "$OUT"; }
grep -q '2 failed (1 infrastructure)' "$OUT" \
  && ok "AC-1: the mixed summary still reports the infra count it did not act on" \
  || { fail "AC-1: the mixed summary lost the infra count"; sed 's/^/    | /' "$OUT"; }

# A green sweep is untouched by any of it — the code only exists on the failing path, and a
# reserved value that leaked into a clean run would red every consumer lane at once.
GRN="$BASE/infra-green"; mkdir -p "$GRN"
make_suite "$GRN" "alpha-selftest.sh" 0 'echo alpha-ok'
run_runner "$GRN" --jobs 2
[[ "$RC" -eq 0 ]] \
  && ok "AC-1: a clean sweep still exits 0" \
  || { fail "AC-1: a clean sweep exited $RC"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# Nesting — the runner must survive running a suite that itself invokes the runner.
#
# THIS IS A REGRESSION GUARD, not a hypothetical. The dispatch sets RUN_SELFTESTS_WORKER on
# `xargs`, so it is inherited by every process below it, INCLUDING the suite. A suite that then
# invoked the runner took the worker branch, read `--root` as its index, and produced garbage —
# and the suite it broke was THIS FILE, which passed standalone and failed the moment the repo
# sweep ran it. 67 of 68 suites green is exactly how that reads if you only run one at a time.
#
# The fixture reproduces the real shape: an outer sweep whose one suite is an inner sweep.
# ---------------------------------------------------------------------------------------
# The inner tree lives OUTSIDE the outer root on purpose. Nested inside it, the outer sweep
# would discover the leaves itself and print their markers whether or not the nested runner ever
# worked — the assertions below would pass vacuously.
NEST="$BASE/nest"; mkdir -p "$NEST"
INNER="$BASE/nest-inner"; mkdir -p "$INNER"
make_suite "$INNER" "aleaf-selftest.sh" 0 'echo ALEAF-ran'
make_suite "$INNER" "zleaf-selftest.sh" 0 'echo ZLEAF-ran'
{
  echo '#!/usr/bin/env bash'
  echo "exec bash '$RUNNER' --root '$INNER'"
} > "$NEST/outer-selftest.sh"
# A second outer suite, sorting AFTER the nesting one, so the seam case below truncates this
# plain suite rather than the nested one it is trying to observe.
make_suite "$NEST" "zz-plain-selftest.sh" 0 'echo plain-ran'

run_runner "$NEST" --jobs 2
[[ "$RC" -eq 0 ]] && grep -q 'ALEAF-ran' "$OUT" && grep -q 'ZLEAF-ran' "$OUT" \
  && ok "nesting: a suite that itself invokes the runner runs clean under the sweep" \
  || { fail "nesting: the runner's own mode leaked into the suite it ran (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# The parent's test-only seam must not reach a nested runner either: inherited, it would drop the
# inner sweep's LAST suite and red it as truncation. ZLEAF is that last suite, so its marker is
# the discriminator — the outer sweep reds either way (the seam is doing its job up there).
OUT="$BASE/out.nest2"
env -u TMPDIR RUN_SELFTESTS_DROP_LAST=1 bash "$RUNNER" --root "$NEST" --jobs 2 > "$OUT" 2>&1
RC=$?
grep -q 'ZLEAF-ran' "$OUT" \
  && ok "nesting: the parent's truncation seam does not reach the nested runner" \
  || { fail "nesting: RUN_SELFTESTS_DROP_LAST leaked into the nested runner (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# =========================================================================================
# THE PASS CACHE (#448).
#
# Every case here drives the REAL runner against a fixture tree carrying its own
# `tools/selftest-cache-inputs.tsv`, because the runner resolves the table at
# `<root>/tools/selftest-cache-inputs.tsv` — so a fixture root gets a fixture table with no
# extra flag, and the repo's own table is never in play.
#
# The cardinal risk this mechanism carries is a SILENTLY SKIPPED GATE, so the assertions are
# built the way that risk demands: every skip case is paired with a proof that the same fixture
# goes RED when its declared input moves, and every "no marker was written" case is paired with
# a control proving a marker WOULD have been written under the same conditions. A cache case
# that only ever asserts a hit is indistinguishable from a runner that skips everything.
# =========================================================================================

# write_tsv <root> <row>...   — each row is "suite<TAB>input" with the tab written literally
write_tsv() {
  local root="$1"; shift
  mkdir -p "$root/tools"
  : > "$root/tools/selftest-cache-inputs.tsv"
  local row
  for row in "$@"; do printf '%s\n' "$row" >> "$root/tools/selftest-cache-inputs.tsv"; done
}

T=$'\t'
CDIR=""
# run_cached <root> [args...] — as run_runner, but always with --cache-dir $CDIR.
run_cached() {
  local root="$1"; shift
  run_runner "$root" --cache-dir "$CDIR" "$@"
}

# ---------------------------------------------------------------------------------------
# AC-1 / AC-7 — fail-closed by default, twice over.
#
#   (a) a suite with NO row is never skipped, even when the cache is on and hot;
#   (b) with NO --cache-dir a suite holding a valid marker still runs — which is the runner
#       side of AC-7's "the nightly bypasses the cache", and of D-11's "a bare local sweep is
#       still cold".
#
# The discriminator is a MARKER line the suite prints. A skipped suite cannot print it.
# ---------------------------------------------------------------------------------------
RC1="$BASE/cache-optin"; mkdir -p "$RC1"
CDIR="$BASE/cache-store-1"
make_suite "$RC1" "rowed-selftest.sh"  0 'echo ROWED-ran'
make_suite "$RC1" "rowed.sh"           0 'echo subject'
make_suite "$RC1" "norow-selftest.sh"  0 'echo NOROW-ran'
write_tsv "$RC1" \
  "rowed-selftest.sh${T}rowed-selftest.sh" \
  "rowed-selftest.sh${T}rowed.sh"

run_cached "$RC1" --cache-write
[[ "$RC" -eq 0 ]] && grep -q 'ROWED-ran' "$OUT" && grep -q 'cache: 0 served, 1 recorded' "$OUT" \
  && ok "cache: the cold run runs everything and records exactly the one rowed suite" \
  || { fail "cache: the cold run did not record exactly one pass (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_cached "$RC1"
[[ "$RC" -eq 0 ]] \
  && ! grep -q 'ROWED-ran' "$OUT" \
  && grep -q 'NOROW-ran' "$OUT" \
  && grep -q 'cache: 1 served' "$OUT" \
  && ok "AC-1: the rowed suite is served from cache; the un-rowed suite still runs" \
  || { fail "AC-1: opt-in participation is not fail-closed"; sed 's/^/    | /' "$OUT"; }

# AC-7 / D-11: the SAME hot store, but no --cache-dir. Nothing may be skipped.
run_runner "$RC1"
[[ "$RC" -eq 0 ]] && grep -q 'ROWED-ran' "$OUT" && ! grep -q 'cache:' "$OUT" \
  && ok "AC-7: with no --cache-dir a suite holding a valid marker still runs — the bypass is the default" \
  || { fail "AC-7: a marker was honored without --cache-dir"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-10 — a skip names the suite, the key, and the inputs behind the key.
#
# Asserted against the store: the key PRINTED must be the key the marker is FILED UNDER. A run
# that printed a plausible-looking hex string that keyed nothing would satisfy a shape check.
# ---------------------------------------------------------------------------------------
run_cached "$RC1"
CKEY="$(sed -n 's/^\[run-selftests\]  *key: \([0-9a-f]\{64\}\)$/\1/p' "$OUT" | head -1)"
if [[ -n "$CKEY" && -f "$CDIR/${CKEY:0:2}/$CKEY" ]]; then
  ok "AC-10: the printed key is the key the marker is filed under"
else
  fail "AC-10: no 64-hex key was printed, or it names no marker (got '${CKEY:-}')"
  sed 's/^/    | /' "$OUT"
fi
sed -n '/::group::cached  rowed-selftest.sh/,/::endgroup::/p' "$OUT" > "$BASE/ac10.block"
grep -q 'rowed-selftest\.sh$' "$BASE/ac10.block" \
  && grep -q 'rowed\.sh$' "$BASE/ac10.block" \
  && [[ "$(grep -cE '^\[run-selftests\]     [0-9a-f]{40}  ' "$BASE/ac10.block")" -eq 2 ]] \
  && ok "AC-10: the skip block names both declared inputs with their blob ids" \
  || { fail "AC-10: the skip did not print the inputs that produced the key"; sed 's/^/    | /' "$BASE/ac10.block"; }

# ---------------------------------------------------------------------------------------
# AC-3 — breaking a DECLARED input misses the cache, and the suite goes red.
#
# ISOLATED ON THE SUBJECT, in its own fixture, because that is the half self-inclusion cannot
# prove. The suite's own bytes are byte-identical across all three runs below; the only thing
# that ever moves is `rc3.sh`. If the key did not cover it, run 3 would be served and green.
#
# Both halves are asserted and neither implies the other: a runner could miss the cache and
# still report green (it re-ran a suite that happens to pass), or red for an unrelated reason.
# ---------------------------------------------------------------------------------------
RC3="$BASE/cache-invalidate"; mkdir -p "$RC3"
CDIR3="$BASE/cache-store-3"
# shellcheck disable=SC2016  # the suite body is written verbatim to a file; $0 expands THERE
make_suite "$RC3" "rc3-selftest.sh" 0 'echo RC3-ran' \
  'if grep -q SUBJECT-EDITED "$(dirname "$0")/rc3.sh"; then exit 1; fi'
make_suite "$RC3" "rc3.sh" 0 'echo subject'
write_tsv "$RC3" "rc3-selftest.sh${T}rc3-selftest.sh" "rc3-selftest.sh${T}rc3.sh"

run_runner "$RC3" --cache-dir "$CDIR3" --cache-write
[[ "$RC" -eq 0 ]] && grep -q 'RC3-ran' "$OUT" \
  && ok "AC-3: the seeding run is green and records the pass" \
  || { fail "AC-3: the seeding run was not green (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_runner "$RC3" --cache-dir "$CDIR3"
[[ "$RC" -eq 0 ]] && ! grep -q 'RC3-ran' "$OUT" && grep -q 'cache: 1 served' "$OUT" \
  && ok "AC-3: control — the unchanged tree IS served, so run 3 measures the edit" \
  || { fail "AC-3: the unchanged tree was not served (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

make_suite "$RC3" "rc3.sh" 0 'echo SUBJECT-EDITED'
run_runner "$RC3" --cache-dir "$CDIR3"
[[ "$RC" -ne 0 ]] \
  && grep -q 'RC3-ran' "$OUT" \
  && grep -q 'rc3-selftest\.sh (rc=1)' "$OUT" \
  && grep -q 'cache: 0 served' "$OUT" \
  && ok "AC-3: editing ONLY the declared subject misses the cache and reds the suite" \
  || { fail "AC-3: the key did not move when a declared input other than the suite did (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# The self-inclusion half, on the same fixture: restore the subject so the ORIGINAL key is live
# again, then move only the suite's own bytes. A runner keying on anything less would serve the
# stale pass here.
make_suite "$RC3" "rc3.sh" 0 'echo subject'
# shellcheck disable=SC2016  # as above
make_suite "$RC3" "rc3-selftest.sh" 1 'echo RC3-ran' \
  'if grep -q SUBJECT-EDITED "$(dirname "$0")/rc3.sh"; then exit 1; fi' \
  'echo suite-itself-edited'
run_runner "$RC3" --cache-dir "$CDIR3"
[[ "$RC" -ne 0 ]] && grep -q 'cache: 0 served' "$OUT" \
  && ok "AC-3: editing the suite's OWN bytes misses the cache — self-inclusion is live, not just declared" \
  || { fail "AC-3: a suite was served past an edit to itself (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-5 — only PASS is recorded. The store must not have grown while that suite was red.
# The count is exact, not a "no new marker for this key" check: a runner that recorded the
# FAILING run under a different key would pass the weaker form.
# ---------------------------------------------------------------------------------------
before="$(find "$CDIR" -type f | grep -c '')"
make_suite "$RC1" "rowed-selftest.sh" 1 'echo ROWED-ran' 'echo still-broken'
run_cached "$RC1" --cache-write
after="$(find "$CDIR" -type f | grep -c '')"
[[ "$RC" -ne 0 && "$before" -eq "$after" ]] \
  && ok "AC-5: a failing suite recorded nothing ($before markers before and after)" \
  || { fail "AC-5: the store moved on a red run ($before -> $after, rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# Control: the identical fixture, passing, DOES record — so the case above measured the verdict
# gate and not a store that had simply stopped being writable.
make_suite "$RC1" "rowed-selftest.sh" 0 'echo ROWED-ran' 'echo fixed'
run_cached "$RC1" --cache-write
after2="$(find "$CDIR" -type f | grep -c '')"
[[ "$RC" -eq 0 && "$after2" -gt "$after" ]] \
  && ok "AC-5: control — the same fixture green DOES record ($after -> $after2)" \
  || { fail "AC-5: control did not record ($after -> $after2, rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# A worker that wrote no verdict must also record nothing — 125 is not a pass, and this is the
# path AC-5's "or timed-out" half names.
RCN="$BASE/cache-norc"; mkdir -p "$RCN"
CDIRN="$BASE/cache-store-norc"
make_suite "$RCN" "nv-selftest.sh" 0 'echo NV-ran'
make_suite "$RCN" "nv.sh"          0 'echo nv-subject'
write_tsv "$RCN" "nv-selftest.sh${T}nv-selftest.sh" "nv-selftest.sh${T}nv.sh"
OUT="$BASE/out.cache-norc"
env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST RUN_SELFTESTS_DROP_RC=1 \
  bash "$RUNNER" --root "$RCN" --cache-dir "$CDIRN" --cache-write > "$OUT" 2>&1
RC=$?
[[ "$RC" -ne 0 ]] && [[ "$(find "$CDIRN" -type f 2>/dev/null | grep -c '')" -eq 0 ]] \
  && ok "AC-5: a verdict-less worker records nothing" \
  || { fail "AC-5: a verdict-less worker left a marker behind (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-6 — recording needs its own flag. This is the property that stops a PR marking its own
# untested content as passing, so it is asserted on the RUNNER, not left to the workflow's
# `if:`. The control immediately below is what makes it non-vacuous.
# ---------------------------------------------------------------------------------------
RC6="$BASE/cache-write-flag"; mkdir -p "$RC6"
CDIR6="$BASE/cache-store-6"
make_suite "$RC6" "w-selftest.sh" 0 'echo W-ran'
make_suite "$RC6" "w.sh"          0 'echo w-subject'
write_tsv "$RC6" "w-selftest.sh${T}w-selftest.sh" "w-selftest.sh${T}w.sh"

run_runner "$RC6" --cache-dir "$CDIR6"
[[ "$RC" -eq 0 ]] && [[ "$(find "$CDIR6" -type f | grep -c '')" -eq 0 ]] \
  && grep -q 'cache: 0 served, 0 recorded' "$OUT" \
  && ok "AC-6: --cache-dir alone records nothing" \
  || { fail "AC-6: a read-only run wrote to the store (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_runner "$RC6" --cache-dir "$CDIR6" --cache-write
[[ "$RC" -eq 0 ]] && [[ "$(find "$CDIR6" -type f | grep -c '')" -eq 1 ]] \
  && ok "AC-6: control — adding --cache-write records the pass" \
  || { fail "AC-6: --cache-write did not record (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_runner "$RC6" --cache-write
[[ "$RC" -eq 2 ]] && ok "AC-6: --cache-write without --cache-dir is rejected" \
                  || { fail "AC-6: --cache-write with no store was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# AC-4 — a suite with no row is unaffected in BOTH directions: it runs, and when it breaks it
# reds, while its rowed neighbour is still being served. The pairing is the point: a runner
# that had stopped scoring skipped-adjacent suites would show a green sweep here.
# ---------------------------------------------------------------------------------------
make_suite "$RC1" "norow-selftest.sh" 1 'echo NOROW-ran' 'echo norow-broke'
run_cached "$RC1"
[[ "$RC" -ne 0 ]] \
  && grep -q 'norow-selftest\.sh (rc=1)' "$OUT" \
  && grep -q 'cache: 1 served' "$OUT" \
  && ok "AC-4: breaking a suite in no row still reds, while the rowed suite is served" \
  || { fail "AC-4: an always-run suite was affected by the cache (rc=$RC)"; sed 's/^/    | /' "$OUT"; }
make_suite "$RC1" "norow-selftest.sh" 0 'echo NOROW-ran'

# ---------------------------------------------------------------------------------------
# AC-2 — the table's rejection rules. Every arm asserts rc=2 AND the named cause, because a
# runner that reded for an unrelated reason would satisfy the exit code alone.
#
# ALL OF THEM RUN WITHOUT --cache-dir. That is the contract, not an economy: the table is
# validated on every sweep, so a malformed declaration reds the local recipe too rather than
# waiting for the day CI enables the cache to be read at all.
# ---------------------------------------------------------------------------------------
RC2="$BASE/cache-reject"; mkdir -p "$RC2"
make_suite "$RC2" "r-selftest.sh" 0 'echo R-ran'
make_suite "$RC2" "r.sh"          0 'echo r-subject'
make_suite "$RC2" "other-selftest.sh" 0 'echo other'

reject_case() { # <label> <expected-substring> <row>...
  local label="$1" want="$2"; shift 2
  write_tsv "$RC2" "$@"
  run_runner "$RC2"
  [[ "$RC" -eq 2 ]] && grep -qF "$want" "$OUT" \
    && ok "AC-2: $label" \
    || { fail "AC-2: $label — rc=$RC, or the cause was not named"; sed 's/^/    | /' "$OUT"; }
}

reject_case "a row set omitting the suite itself is rejected" \
  "does not declare ITSELF as an input" \
  "r-selftest.sh${T}r.sh"

reject_case "a row set omitting the script under test is rejected" \
  "does not declare its script under test 'r.sh'" \
  "r-selftest.sh${T}r-selftest.sh" \
  "r-selftest.sh${T}other-selftest.sh"

reject_case "a row set that pins only its own bytes is rejected" \
  "declares no input besides itself" \
  "other-selftest.sh${T}other-selftest.sh"

reject_case "a row naming an undiscovered suite is a stale row" \
  "stale cache-input row" \
  "ghost-selftest.sh${T}ghost-selftest.sh"

reject_case "a row naming a nonexistent input is rejected" \
  "declares an input that does not exist" \
  "r-selftest.sh${T}r-selftest.sh" \
  "r-selftest.sh${T}r.sh" \
  "r-selftest.sh${T}vanished.sh"

reject_case "a three-column row is rejected" \
  "expected exactly two tab-separated columns" \
  "r-selftest.sh${T}r-selftest.sh${T}r.sh"

# Control: the well-formed table over the same fixture is green, so every rejection above
# measured its own rule rather than a tree the runner could not process at all.
write_tsv "$RC2" \
  "r-selftest.sh${T}r-selftest.sh" \
  "r-selftest.sh${T}r.sh"
run_runner "$RC2"
[[ "$RC" -eq 0 ]] && ok "AC-2: control — the well-formed table over the same fixture is green" \
                  || { fail "AC-2: control table was rejected (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# A DIRECTORY input covers the files beneath it, including ones that appear or vanish — the
# property `cost-tracking-fixtures` and `stages/` depend on in the real table. A row that
# hashed only the directory's name would serve a stale pass over an edited fixture.
# ---------------------------------------------------------------------------------------
RCD="$BASE/cache-dirinput"; mkdir -p "$RCD/fix"
CDIRD="$BASE/cache-store-dir"
make_suite "$RCD" "d-selftest.sh" 0 'echo D-ran'
echo "one" > "$RCD/fix/a.txt"
write_tsv "$RCD" "d-selftest.sh${T}d-selftest.sh" "d-selftest.sh${T}fix"

run_runner "$RCD" --cache-dir "$CDIRD" --cache-write
run_runner "$RCD" --cache-dir "$CDIRD"
[[ "$RC" -eq 0 ]] && ! grep -q 'D-ran' "$OUT" \
  && ok "cache: a directory input produces a stable key across an unchanged tree" \
  || { fail "cache: the directory-input key was not stable"; sed 's/^/    | /' "$OUT"; }

echo "two" > "$RCD/fix/a.txt"
run_runner "$RCD" --cache-dir "$CDIRD"
[[ "$RC" -eq 0 ]] && grep -q 'D-ran' "$OUT" \
  && ok "cache: editing a file INSIDE a declared directory misses the cache" \
  || { fail "cache: a directory input did not cover its contents"; sed 's/^/    | /' "$OUT"; }

echo "one" > "$RCD/fix/a.txt"   # restore the hashed content, then ADD a sibling
echo "new" > "$RCD/fix/b.txt"
run_runner "$RCD" --cache-dir "$CDIRD"
[[ "$RC" -eq 0 ]] && grep -q 'D-ran' "$OUT" \
  && ok "cache: ADDING a file to a declared directory misses the cache" \
  || { fail "cache: a directory input did not cover an added file"; sed 's/^/    | /' "$OUT"; }

# ---------------------------------------------------------------------------------------
# THE ENVIRONMENT AXIS of the key. A marker recorded under one lane's identity must never be
# served to another's — the two CI lanes differ by RUNNER_OS, and by SKIP_STRESS, and a suite
# that skipped its stress legs answered a strictly weaker question than one that ran them.
#
# Each arm is a SEED under one identity and a read under another, so the assertion is on the
# store's behavior rather than on the key string. The control at the end re-reads under the
# seeding identity, which is what stops "nothing is ever served" from passing all of this.
# ---------------------------------------------------------------------------------------
RCE="$BASE/cache-env"; mkdir -p "$RCE"
CDIRE="$BASE/cache-store-env"
make_suite "$RCE" "e-selftest.sh" 0 'echo E-ran'
make_suite "$RCE" "e.sh"          0 'echo e-subject'
write_tsv "$RCE" "e-selftest.sh${T}e-selftest.sh" "e-selftest.sh${T}e.sh"

run_env_case() { # <label> <expect-served: yes|no> <env assignment>...
  local label="$1" expect="$2"; shift 2
  OUT="$BASE/out.env.$RANDOM"
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u SKIP_STRESS -u RUNNER_OS "$@" \
    bash "$RUNNER" --root "$RCE" --cache-dir "$CDIRE" > "$OUT" 2>&1
  RC=$?
  if [[ "$RC" -ne 0 ]]; then
    fail "key-axis: $label — the sweep itself reded (rc=$RC)"; sed 's/^/    | /' "$OUT"; return
  fi
  if [[ "$expect" == "yes" ]]; then
    grep -q 'cache: 1 served' "$OUT" && ok "key-axis: $label — served" \
      || { fail "key-axis: $label — expected a hit, got a miss"; sed 's/^/    | /' "$OUT"; }
  else
    grep -q 'cache: 0 served' "$OUT" && ok "key-axis: $label — not served" \
      || { fail "key-axis: $label — a marker crossed a key axis"; sed 's/^/    | /' "$OUT"; }
  fi
}

OUT="$BASE/out.env.seed"
env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u SKIP_STRESS RUNNER_OS=Linux \
  bash "$RUNNER" --root "$RCE" --cache-dir "$CDIRE" --cache-write > "$OUT" 2>&1
RC=$?
[[ "$RC" -eq 0 ]] && grep -q 'cache: 0 served, 1 recorded' "$OUT" \
  && ok "key-axis: seeded one marker under RUNNER_OS=Linux with stress legs on" \
  || { fail "key-axis: the seeding run did not record (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_env_case "a different RUNNER_OS" no  RUNNER_OS=Darwin
run_env_case "the same OS but SKIP_STRESS set" no RUNNER_OS=Linux SKIP_STRESS=1
run_env_case "control — the seeding identity" yes RUNNER_OS=Linux

# ---------------------------------------------------------------------------------------
# THE RUNNER'S OWN BYTES are the last axis, and the one the declaration table cannot express:
# this harness is what produces every verdict the store records, so a change to how workers
# are dispatched must not be served past on the suites it is most likely to move. Asserted on
# a COPY of the runner, because the assertion needs a runner whose bytes differ — mutating the
# one under test is not available. The copy reads its tree from --root, so it behaves
# identically from anywhere.
# ---------------------------------------------------------------------------------------
RCR="$BASE/cache-runner"; mkdir -p "$RCR"
CDIRR="$BASE/cache-store-runner"
RCOPY="$BASE/runner-copy.sh"
make_suite "$RCR" "r-selftest.sh" 0 'echo R-ran'
make_suite "$RCR" "r.sh"          0 'echo r-subject'
write_tsv "$RCR" "r-selftest.sh${T}r-selftest.sh" "r-selftest.sh${T}r.sh"
cp "$RUNNER" "$RCOPY"

run_copy_case() { # <label> <expect-served: yes|no> [--cache-write]
  local label="$1" expect="$2"; shift 2
  OUT="$BASE/out.runner.$RANDOM"
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST \
    bash "$RCOPY" --root "$RCR" --cache-dir "$CDIRR" "$@" > "$OUT" 2>&1
  RC=$?
  if [[ "$RC" -ne 0 ]]; then
    fail "runner-axis: $label — the sweep itself reded (rc=$RC)"; sed 's/^/    | /' "$OUT"; return
  fi
  if [[ "$expect" == "yes" ]]; then
    grep -q 'cache: 1 served' "$OUT" && ok "runner-axis: $label — served" \
      || { fail "runner-axis: $label — expected a hit, got a miss"; sed 's/^/    | /' "$OUT"; }
  else
    grep -q 'cache: 0 served' "$OUT" && ok "runner-axis: $label — not served" \
      || { fail "runner-axis: $label — a marker crossed the runner axis"; sed 's/^/    | /' "$OUT"; }
  fi
}

run_copy_case "seed under the copy's own bytes" no --cache-write
run_copy_case "control — the same runner bytes" yes
# One comment line. Behavior is identical by construction, so a hit here could only mean the
# runner is off the key axis entirely.
echo '# runner-axis mutation' >> "$RCOPY"
run_copy_case "one byte changed in the runner" no

# ---------------------------------------------------------------------------------------
# A malformed marker is a MISS, never a pass. The fail-safe half of the store contract: the
# only thing that may be read as a pass is exactly the one well-formed record line.
# ---------------------------------------------------------------------------------------
RCT="$BASE/cache-tamper"; mkdir -p "$RCT"
CDIRT="$BASE/cache-store-tamper"
make_suite "$RCT" "t-selftest.sh" 0 'echo T-ran'
make_suite "$RCT" "t.sh"          0 'echo t-subject'
write_tsv "$RCT" "t-selftest.sh${T}t-selftest.sh" "t-selftest.sh${T}t.sh"
run_runner "$RCT" --cache-dir "$CDIRT" --cache-write
TMARK="$(find "$CDIRT" -type f | head -1)"
if [[ -n "$TMARK" ]]; then
  echo "garbage" > "$TMARK"
  run_runner "$RCT" --cache-dir "$CDIRT"
  [[ "$RC" -eq 0 ]] && grep -q 'T-ran' "$OUT" \
    && ok "cache: a malformed marker is a miss, not a pass" \
    || { fail "cache: a malformed marker was honored"; sed 's/^/    | /' "$OUT"; }
else
  fail "cache: no marker was written, so the malformed-marker case could not run"
fi

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

# ---------------------------------------------------------------------------------------
# The lane job ceiling (#526). A fixture tree of two trivial passing suites — nothing here is
# about what the suites do, only about the jobs value the runner resolves and prints.
#
# The ceiling is asserted through `jobs=` on the runner's own summary line rather than by
# timing anything: a concurrency assertion keyed on wall clock is a flake generator, and the
# resolved value is the entire contract.
# ---------------------------------------------------------------------------------------
RJ="$BASE/jobs"; mkdir -p "$RJ"
make_suite "$RJ" "j1-selftest.sh" 0 'echo j1'
make_suite "$RJ" "j2-selftest.sh" 0 'echo j2'

# AC-5. No ceiling and no flag is what BOTH CI workflows produce — neither invokes the gate that
# exports one, and neither passes --jobs. Asserted, not assumed: this is the case that says CI's
# concurrency is untouched by everything else in this change.
CEILING=""; run_runner "$RJ"
if [[ "$RC" -eq 0 ]] && grep -q 'jobs=4' "$OUT" && ! grep -q 'job ceiling' "$OUT"; then
  ok "ceiling: absent leaves the default at 4 — CI's resolved concurrency is unchanged"
else
  fail "ceiling: absent must resolve jobs=4 with no announcement (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# AC-2. The case the whole ticket exists for: SELFTEST_JOBS could not carry a ceiling because
# --jobs overwrites it, so absent-with-an-explicit-flag must be byte-identical to today.
CEILING=""; run_runner "$RJ" --jobs 10
if [[ "$RC" -eq 0 ]] && grep -q 'jobs=10' "$OUT" && ! grep -q 'job ceiling' "$OUT"; then
  ok "ceiling: absent leaves an explicit --jobs 10 alone"
else
  fail "ceiling: absent must leave --jobs 10 alone (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

CEILING=2; run_runner "$RJ" --jobs 10
if [[ "$RC" -eq 0 ]] && grep -q 'jobs=2' "$OUT" && grep -q 'job ceiling: 10 -> 2' "$OUT"; then
  ok "ceiling: below the flag clips it, and says so"
else
  fail "ceiling: 2 must clip --jobs 10 to 2 and announce it (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# A CEILING, not an override. An operator who asked for fewer workers than their share keeps
# them — raising anyone's concurrency is not something this variable may ever do.
CEILING=9; run_runner "$RJ" --jobs 3
if [[ "$RC" -eq 0 ]] && grep -q 'jobs=3' "$OUT" && ! grep -q 'job ceiling' "$OUT"; then
  ok "ceiling: above the flag is a no-op"
else
  fail "ceiling: 9 must leave --jobs 3 alone (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# Rejected the way --jobs is. Unvalidated, the minimum is undefined and the naive shell form
# yields an empty or zero jobs value — a silent drop to serial, which is the fail-open shape
# this change exists to remove.
CEILING=abc; run_runner "$RJ"
[[ "$RC" -eq 2 ]] && ok "ceiling: a non-numeric ceiling is rejected" \
                  || { fail "ceiling: LEAN_JOB_CEILING=abc was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

CEILING=0; run_runner "$RJ"
[[ "$RC" -eq 2 ]] && ok "ceiling: a zero ceiling is rejected" \
                  || { fail "ceiling: LEAN_JOB_CEILING=0 was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }
CEILING=""

# ---------------------------------------------------------------------------------------
# THE FIXTURE REAPER CALL SITE (#528). Every other case builds a --root whose tools/ holds only
# selftest-cache-inputs.tsv, so the `[[ -x <root>/tools/reap-lean-fixtures.sh ]]` guard takes
# its FALSE branch in all of them and nothing proved the true branch does anything at all.
#
# Two properties: the reaper is invoked, and a reaper that FAILS is housekeeping — never a reason
# to red a sweep whose suites all passed.
#
# What holds the second is NOT the call site's `|| true`. Measured: dropping it leaves this case
# green, because this harness is deliberately not `set -e` (see its own note at the top of
# run-selftests.sh — it scores other suites' exit codes and must not abort on one). The `|| true`
# is belt-and-braces against a future `set -e`, and this case does not pin it. What it does pin is
# the behavior that matters to a sweep: a failing reaper leaves the verdict alone.
RRP="$BASE/reaper"
make_suite "$RRP" "ok-selftest.sh" 0 'echo "ok-suite ran"'
mkdir -p "$RRP/tools"
{
  echo '#!/usr/bin/env bash'
  echo 'echo "REAPER-RAN"'
  echo 'exit 3'
} > "$RRP/tools/reap-lean-fixtures.sh"
chmod +x "$RRP/tools/reap-lean-fixtures.sh"

run_runner "$RRP"
if [[ "$RC" -eq 0 ]] && grep -q 'REAPER-RAN' "$OUT" && grep -q 'ok-suite ran' "$OUT"; then
  ok "reaper: a present tool is invoked, and a failing one leaves the sweep's verdict green"
else
  fail "reaper: expected an invoked reaper and a green sweep (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# The control: with the tool ABSENT the sweep is identical and silent, so the case above is
# reading the guard's true branch rather than something the runner prints regardless.
rm -f "$RRP/tools/reap-lean-fixtures.sh"
run_runner "$RRP"
if [[ "$RC" -eq 0 ]] && ! grep -q 'REAPER-RAN' "$OUT"; then
  ok "reaper: with no tool under the root the sweep runs unchanged"
else
  fail "reaper: the absent-tool control did not hold (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# =========================================================================================
# #563 — THE LEAN LANE'S ACTIVATION PATH.
#
# lean-gate.sh milestone 3 cannot pass a flag to a `test` command it does not own, so it hands
# the store down as $LEAN_SELFTEST_CACHE_DIR. That is a SECOND way to turn a cache on, and the
# cardinal risk of this mechanism is a silently skipped gate — so every case here is driven
# through the env, never the flag, and every skip is paired with the edit that must un-skip it.
# =========================================================================================

# run_env_cached <store> <root> [args...] — the runner with the store injected and NO cache flag.
run_env_cached() {
  local store="$1" root="$2"; shift 2
  OUT="$BASE/out.$$.$RANDOM"
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u LEAN_JOB_CEILING \
    LEAN_SELFTEST_CACHE_DIR="$store" \
    bash "$RUNNER" --root "$root" "$@" > "$OUT" 2>&1
  RC=$?
}

RE1="$BASE/env-cache"; mkdir -p "$RE1"
CDIRE="$BASE/env-store"
make_suite "$RE1" "e-selftest.sh" 0 'echo E-ran'
make_suite "$RE1" "e.sh"          0 'echo e-subject'
make_suite "$RE1" "plain-selftest.sh" 0 'echo PLAIN-ran'
write_tsv "$RE1" "e-selftest.sh${T}e-selftest.sh" "e-selftest.sh${T}e.sh"

# Cold. The env path RECORDS without --cache-write, which is the one place it departs from the
# argv contract — so it is asserted here rather than inferred from the hit below.
run_env_cached "$CDIRE" "$RE1"
[[ "$RC" -eq 0 ]] && grep -q 'E-ran' "$OUT" \
  && grep -q 'activated from LEAN_SELFTEST_CACHE_DIR' "$OUT" \
  && grep -q 'cache: 0 served, 1 recorded' "$OUT" \
  && ok "#563: the env store activates the cache and records the pass with no --cache-write" \
  || { fail "#563: the env store did not activate/record (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# Hot, unchanged inputs: the rowed suite is SERVED, the un-rowed neighbour still runs. This is
# AC-1 — the close-out sweep of an unmoved head — reached through the gate's channel.
run_env_cached "$CDIRE" "$RE1"
[[ "$RC" -eq 0 ]] && ! grep -q 'E-ran' "$OUT" && grep -q 'PLAIN-ran' "$OUT" \
  && grep -q 'cache: 1 served' "$OUT" \
  && ok "#563/AC-1: an unchanged re-run is served from the env store; the un-rowed suite still runs" \
  || { fail "#563/AC-1: the unchanged re-run was not served (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# AC-2, the un-skip. Editing a DECLARED input re-runs the suite — and the fixture is made red in
# the same edit, so a runner that served the stale marker would report green on broken content.
make_suite "$RE1" "e.sh" 1 'echo e-subject-broken'
run_env_cached "$CDIRE" "$RE1"
[[ "$RC" -eq 0 ]] && grep -q 'E-ran' "$OUT" && grep -q 'cache: 0 served' "$OUT" \
  && ok "#563/AC-2: editing a declared input misses the env-store cache and re-runs the suite" \
  || { fail "#563/AC-2: a moved input was still served (rc=$RC)"; sed 's/^/    | /' "$OUT"; }
make_suite "$RE1" "e.sh" 0 'echo e-subject'

# AC-2, argv precedence. With BOTH present the flag decides, and the assertion is on the STORES,
# not on a log line: the marker must land in the flag's store and the env's must stay empty.
CDIRA="$BASE/argv-store"
OUT="$BASE/out.argv-wins"
env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u LEAN_JOB_CEILING \
  LEAN_SELFTEST_CACHE_DIR="$BASE/never-used-store" \
  bash "$RUNNER" --root "$RE1" --cache-dir "$CDIRA" --cache-write > "$OUT" 2>&1
RC=$?
[[ "$RC" -eq 0 ]] \
  && [[ "$(find "$CDIRA" -type f 2>/dev/null | grep -c '')" -eq 1 ]] \
  && [[ "$(find "$BASE/never-used-store" -type f 2>/dev/null | grep -c '')" -eq 0 ]] \
  && ! grep -q 'activated from LEAN_SELFTEST_CACHE_DIR' "$OUT" \
  && ok "#563/AC-2: argv --cache-dir wins over the env store, which is never touched" \
  || { fail "#563/AC-2: the env store overrode or shadowed argv (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# AC-2, unset is a no-op: the SAME hot store, with neither flag nor variable. Nothing is skipped.
run_runner "$RE1"
[[ "$RC" -eq 0 ]] && grep -q 'E-ran' "$OUT" && ! grep -q 'cache:' "$OUT" \
  && ok "#563/AC-2: with the variable unset a hot store is invisible — the default is still cold" \
  || { fail "#563/AC-2: a marker was honored with no store declared (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# AC-3, the worker scrub. A suite must not SEE the store: the cache is decided in the parent, and
# an inherited value turns a nested runner's fixtures into a different question than the one they
# assert. The control below proves the probe can observe the variable at all.
RE2="$BASE/env-scrub"; mkdir -p "$RE2"
# The single quotes are the assertion: the probe must read the variable in ITS OWN environment
# when the runner dispatches it, not this suite's at fixture-writing time.
# shellcheck disable=SC2016
make_suite "$RE2" "probe-selftest.sh" 0 'echo "PROBE-store=${LEAN_SELFTEST_CACHE_DIR:-unset}"'
run_env_cached "$BASE/scrub-store" "$RE2"
[[ "$RC" -eq 0 ]] && grep -q 'PROBE-store=unset' "$OUT" \
  && ok "#563/AC-3: the store is scrubbed from the dispatched suite's environment" \
  || { fail "#563/AC-3: LEAN_SELFTEST_CACHE_DIR leaked into a suite (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

OUT="$BASE/out.scrub-control"
env LEAN_SELFTEST_CACHE_DIR="$BASE/scrub-store" bash "$RE2/probe-selftest.sh" > "$OUT" 2>&1
grep -q "PROBE-store=$BASE/scrub-store" "$OUT" \
  && ok "#563/AC-3: control — run directly, the same probe DOES see the variable" \
  || { fail "#563/AC-3: the scrub control is vacuous — the probe never sees the value"; sed 's/^/    | /' "$OUT"; }

# AC-3, the one asymmetry between the two activation paths. An injected store that cannot be
# created is not the tree's fault and must not red a milestone about something else; a --cache-dir
# an operator typed and that cannot work still exits 2.
printf 'not a directory\n' > "$BASE/blocker"
run_env_cached "$BASE/blocker/store" "$RE2"
[[ "$RC" -eq 0 ]] && grep -q 'cache disabled: LEAN_SELFTEST_CACHE_DIR is not creatable' "$OUT" \
  && grep -q 'PROBE-store=' "$OUT" \
  && ok "#563/AC-3: an uncreatable env store runs cold with a named notice" \
  || { fail "#563/AC-3: an uncreatable env store did not degrade to a cold sweep (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

run_runner "$RE2" --cache-dir "$BASE/blocker/store"
[[ "$RC" -eq 2 ]] \
  && ok "#563/AC-3: control — an uncreatable argv --cache-dir is still a usage error" \
  || { fail "#563/AC-3: an uncreatable --cache-dir was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "run-selftests-selftest: PASS"
  exit 0
fi
echo "run-selftests-selftest: FAIL ($FAILS)"
exit 1
