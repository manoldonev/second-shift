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
# LEAN_SELFTEST_CACHE_DIR (#563) is SCRUBBED, and the scrub is not hygiene:
# the lean gate exports a STORE too, and an inherited one would turn the cache ON in every case
# below that asserts nothing is served without --cache-dir.
#
# EVERY DIRECT INVOCATION BELOW CARRIES THE SAME SCRUB, and until #613 the policy was stated here
# and honored only by this driver — so the cases that hand-roll their own `env` inherited whatever
# the machine was running under. #613 made that policy real for #526's job ceiling; #566 deletes
# the ceiling, so the discipline now rides on the one seam the gate still hands a lane child.
# The SELFTEST_JOBS case argues it at its own site.
#
# The #563 cases at the end of this file set the store deliberately, one invocation at a time,
# and never through this driver.
OUT=""; RC=0
run_runner() {
  local root="$1"; shift
  OUT="$BASE/out.$$.$RANDOM"
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u LEAN_SELFTEST_CACHE_DIR \
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

# frame_set <file> — the replayed ::group:: headers with the elapsed field blanked. See the
# AC-4 case below for why the time is not part of what is being compared.
frame_set() { awk '/^::group::/ { $2 = "ELAPSED"; print }' "$1"; }

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
env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR -u SELFTEST_JOBS RUN_SELFTESTS_DROP_LAST=1 \
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
  #
  # The elapsed field (#629) is normalized out, and that is the assertion staying honest rather
  # than being weakened. The two runs differ by CONCURRENCY, which is the one thing a wall clock
  # is guaranteed to disagree about — a suite that straddles a second boundary at jobs=4 and not
  # at jobs=1 would red this case for behaving exactly as measured time behaves. What must not
  # move is the set and its order, and that is what is compared.
  if diff <(frame_set "$out1") <(frame_set "$out4") >/dev/null; then
    ok "AC-4: $label — jobs=1 and jobs=4 report the identical suite set, in order"
  else
    fail "AC-4: $label — the reported suite set differs between jobs=1 and jobs=4"
    diff <(frame_set "$out1") <(frame_set "$out4") | sed 's/^/    | /'
  fi
done

# SELFTEST_JOBS (the env form the workflows use) must reach the same place as --jobs.
#
# THIS CASE HAND-ROLLS ITS `env`, so it must carry run_runner's LEAN_SELFTEST_CACHE_DIR scrub
# itself — and the hostile store in front of it is the assertion, not scenery. Without the scrub
# an ambient store activates the pass cache (`cache: activated from LEAN_SELFTEST_CACHE_DIR`),
# and this case then runs a cached sweep while claiming to measure a cold one. That is not
# hypothetical: the lean gate exports a store into every milestone-3 child, one of which is the
# sweep that runs this file, so the leak surfaces only on a machine whose operator carries the
# variable. Setting one here makes a dropped scrub fail EVERYWHERE instead of only there — which
# is why the assertion is two-sided: the jobs number AND the absence of the activation line.
#
# It carried #526's LEAN_JOB_CEILING scrub on the same reasoning until #566 deleted the ceiling;
# the argument survived the variable, so it was re-pointed at the seam that is still handed down.
OUT="$BASE/out.ac4env"
LEAN_SELFTEST_CACHE_DIR="$BASE/hostile-cache" \
  env -u TMPDIR -u RUN_SELFTESTS_DROP_LAST -u LEAN_SELFTEST_CACHE_DIR SELFTEST_JOBS=3 \
  bash "$RUNNER" --root "$R4G" > "$OUT" 2>&1
RC=$?
[[ "$RC" -eq 0 ]] && grep -q 'jobs=3' "$OUT" && ! grep -q 'activated from LEAN_SELFTEST_CACHE_DIR' "$OUT" \
  && ok "AC-4: SELFTEST_JOBS is honored as the concurrency source, on an uncached sweep" \
  || { fail "AC-4: SELFTEST_JOBS was not honored, or an ambient cache store leaked in"; sed 's/^/    | /' "$OUT"; }

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
env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR -u RUN_SELFTESTS_DROP_LAST RUN_SELFTESTS_DROP_RC=1 \
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
env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR RUN_SELFTESTS_DROP_LAST=1 bash "$RUNNER" --root "$NEST" --jobs 2 > "$OUT" 2>&1
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
sed -n '/::group::cached  -  rowed-selftest.sh/,/::endgroup::/p' "$OUT" > "$BASE/ac10.block"
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
env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST RUN_SELFTESTS_DROP_RC=1 \
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
  env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u SKIP_STRESS -u RUNNER_OS "$@" \
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
env -u TMPDIR -u LEAN_SELFTEST_CACHE_DIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST -u SKIP_STRESS RUNNER_OS=Linux \
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
# THE SLOW-SUITE TABLE (#566 AC-10). The bound that replaced ~640 lines of detached-runner
# supervision in lean-gate.sh: milestone 3 fits inside the harness turn because the sweep it
# runs is narrowed here, not because a runner outlives the turn.
#
# EVERY OTHER CASE IN THIS FILE BUILDS A --root WITH NO SUCH TABLE, which is what keeps them
# meaningful — an absent table is the "every suite is fast" default, so nothing above this
# point changed behavior when the table shipped.
# ---------------------------------------------------------------------------------------
RSL="$BASE/slow"; mkdir -p "$RSL/tools"
make_suite "$RSL" "tools/quick-selftest.sh" 0 'echo quick'
make_suite "$RSL" "tools/heavy-selftest.sh" 0 'echo heavy'
make_suite "$RSL" "sub/other-selftest.sh"   0 'echo other'
# Two rows sit ON the 9s boundary, folded into this same table, and between them they pin the
# comparison itself rather than only its far side. sub/other-selftest.sh (8s) is one second
# UNDER and must stay un-deferred and actually run — deleting the `>= threshold` filter outright
# (deferring every tabled suite regardless of value) is what the 'pass ... sub/other-selftest.sh'
# clause catches. tools/quick-selftest.sh (9s) is EXACTLY AT the bar and must be deferred — that
# is the row that distinguishes `>=` from `>`, and without it the excluded count is identical
# under either operator.
printf '# threshold-seconds\t9\ntools/heavy-selftest.sh\t147\t2026-08-20\ntools/quick-selftest.sh\t9\t2026-08-20\nsub/other-selftest.sh\t8\t2026-08-20\n' > "$RSL/tools/selftest-suite-timings.tsv"

# AC-10 / AC-4. Applied BY DEFAULT — no flag opts in. The deferred suite is NAMED with its
# measured seconds and date (a count could not tell an operator which green they are not
# getting), the sweep still exits 0, and the discovered/ran invariant holds because the
# exclusion is computed before dispatch rather than by killing a live suite.
run_runner "$RSL"
if [[ "$RC" -eq 0 ]] && grep -q 'deferred: tools/heavy-selftest.sh (147s (measured 2026-08-20))' "$OUT" \
   && grep -q 'deferred: tools/quick-selftest.sh (9s (measured 2026-08-20))' "$OUT" \
   && grep -q '3 discovered, 2 excluded, 1 to run' "$OUT" \
   && grep -q '::group::pass.*sub/other-selftest.sh' "$OUT" && ! grep -q 'ERROR' "$OUT"; then
  ok "slow-table: applied by default, names each deferred suite, defers the at-threshold row, runs the under-threshold one, still exits 0"
else
  fail "slow-table: default application failed (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# AC-10. `--full` is the opt-out, and it is what every sweep of record passes. This is the case
# that says CI's coverage is unchanged by the table's existence.
run_runner "$RSL" --full
if [[ "$RC" -eq 0 ]] && ! grep -q 'deferred:' "$OUT" && grep -q '3 discovered, 0 excluded, 3 to run' "$OUT"; then
  ok "slow-table: --full ignores the table entirely — the sweep of record still runs everything"
else
  fail "slow-table: --full must run all 3 suites with no deferral (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# THE DEDUPE, and it is a correctness case rather than a tidiness one. EXCLUDED feeds
# EXPECTED = DISCOVERED - EXCLUDED, which the run/discovered invariant is checked against, so
# counting one suite twice under-states EXPECTED and reds an honest sweep. It is the NORMAL
# case, not an edge one: this repo's own milestone-3 `test` command passes
# `--exclude tools/install-topology-selftest.sh` explicitly, and that suite is also a table row.
run_runner "$RSL" --exclude tools/heavy-selftest.sh
if [[ "$RC" -eq 0 ]] && grep -q '3 discovered, 2 excluded, 1 to run' "$OUT" && ! grep -q 'ERROR' "$OUT"; then
  ok "slow-table: a suite excluded BOTH explicitly and by the table counts once"
else
  fail "slow-table: explicit+table double-count broke the run/discovered invariant (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# THE STALE-ROW POSTURE, inherited from --exclude verbatim: a row naming no discovered suite is
# a hard error, so a renamed suite cannot silently start running twice (here and in its own CI
# job) with nobody noticing. The message must name the TABLE — a stale table row and a stale
# workflow argument have different remedies, and a shared message sends the reader to the wrong
# file.
printf '# threshold-seconds\t9\ntools/vanished-selftest.sh\t99\t2026-08-20\n' > "$RSL/tools/selftest-suite-timings.tsv"
run_runner "$RSL"
if [[ "$RC" -eq 2 ]] && grep -q 'selftest-suite-timings.tsv row' "$OUT" && grep -q 'stale table row' "$OUT"; then
  ok "slow-table: a row matching no discovered suite reds, and the message names the table"
else
  fail "slow-table: stale row must red with a table-specific message (rc=$RC)"; sed 's/^/    | /' "$OUT"
fi

# ...and --full does not read the table at all, so a stale row cannot red the sweep of record.
# The opt-out has to be total: a CI lane that reds on the local check's cost record would make
# the table a merge blocker, which is the opposite of what it is for.
run_runner "$RSL" --full
[[ "$RC" -eq 0 ]] && ok "slow-table: --full does not read the table, so a stale row cannot red CI" \
                  || { fail "slow-table: --full redded on a stale table row (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# A MALFORMED ROW IS A USAGE ERROR, not a silently-skipped one. A row whose seconds column is
# not a number is a hand-edit that did not finish, and treating it as absent would defer nothing
# while reporting a bound that is not in force.
printf '# threshold-seconds\t9\ntools/heavy-selftest.sh\tsoon\t2026-08-20\n' > "$RSL/tools/selftest-suite-timings.tsv"
run_runner "$RSL"
[[ "$RC" -eq 2 ]] && ok "slow-table: a non-numeric seconds column is rejected" \
                  || { fail "slow-table: malformed row was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# #641: a table with rows but no `# threshold-seconds` directive is unreadable, not "defer
# nothing" — the membership rule the rows exist to state has gone missing.
printf 'tools/heavy-selftest.sh\t147\t2026-08-20\n' > "$RSL/tools/selftest-suite-timings.tsv"
run_runner "$RSL"
[[ "$RC" -eq 2 ]] && grep -q 'threshold-seconds' "$OUT" \
  && ok "slow-table: a table with no '# threshold-seconds' directive is a hard error" \
  || { fail "slow-table: a directive-less table was accepted (rc=$RC)"; sed 's/^/    | /' "$OUT"; }

# AC-4 (#641): the committed table is a real union — no suite appears twice.
DUPES="$(grep -v '^#' "$HERE/selftest-suite-timings.tsv" | grep -v '^$' | cut -f1 | sort | uniq -d)"
[[ -z "$DUPES" ]] && ok "slow-table: the committed table has no duplicate suite row" \
                  || fail "slow-table: duplicate row(s) in the committed table: $DUPES"

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
  env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST \
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
env -u TMPDIR -u SELFTEST_JOBS -u RUN_SELFTESTS_DROP_LAST \
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

# ---------------------------------------------------------------------------------------
# #629/AC-1 — every frame line carries the suite's elapsed seconds, and the exit-code contract
# is untouched by it.
#
# THE SUB-SECOND ARM IS THE ONE THAT MATTERS. tools/check-sweep-bound.sh sums these across ~60
# suites, most of which finish inside a second; an emitter that rounded those to 0 would let the
# un-deferred set grow by half a minute without its total moving, which is the exact drift the
# sum exists to see. So a suite that takes no measurable time is charged ONE second, and that is
# asserted as a literal rather than as "some number".
#
# The failing suite is here for two reasons: its frame must carry the time AND still carry
# (rc=N), and the sweep must still red. An emitter that reformatted the FAIL frame past the
# reconciliation would be invisible to a green-only fixture.
# ---------------------------------------------------------------------------------------
R629="$BASE/ac629"; mkdir -p "$R629"
make_suite "$R629" "fast-selftest.sh" 0 'echo instant'
make_suite "$R629" "slow-selftest.sh" 0 'sleep 2' 'echo slept'
make_suite "$R629" "red-selftest.sh"  1 'echo broke'

run_runner "$R629" --jobs 3
[[ "$RC" -ne 0 ]] && ok "#629/AC-1: the exit-code contract is unchanged — a red suite still reds (rc=$RC)" \
                 || { fail "#629/AC-1: a failing suite exited 0 once elapsed was emitted"; sed 's/^/    | /' "$OUT"; }

FRAMES="$(grep -c '^::group::' "$OUT")"
TIMED="$(grep -cE '^::group::(pass|FAIL)  [0-9]+s  ' "$OUT")"
[[ "$FRAMES" -eq 3 && "$TIMED" -eq 3 ]] \
  && ok "#629/AC-1: all 3 frame lines carry an elapsed field" \
  || { fail "#629/AC-1: $TIMED of $FRAMES frame lines carried elapsed"; sed 's/^/    | /' "$OUT"; }

grep -qE '^::group::pass  1s  fast-selftest\.sh$' "$OUT" \
  && ok "#629/AC-1: a sub-second suite is charged one second, never zero" \
  || { fail "#629/AC-1: the instant suite was not charged exactly 1s"; sed 's/^/    | /' "$OUT"; }

SLOW_SECS="$(sed -n 's/^::group::pass  \([0-9][0-9]*\)s  slow-selftest\.sh$/\1/p' "$OUT" | head -1)"
[[ -n "$SLOW_SECS" && "$SLOW_SECS" -ge 2 ]] \
  && ok "#629/AC-1: a 2s suite reports at least its own sleep (${SLOW_SECS}s)" \
  || { fail "#629/AC-1: the 2s suite reported '${SLOW_SECS:-<nothing>}'"; sed 's/^/    | /' "$OUT"; }

grep -qE '^::group::FAIL  [0-9]+s  red-selftest\.sh \(rc=1\)$' "$OUT" \
  && ok "#629/AC-1: a FAIL frame carries the elapsed AND still names the exit code" \
  || { fail "#629/AC-1: the FAIL frame lost its rc or its elapsed"; sed 's/^/    | /' "$OUT"; }

# The property the AC-5 contiguity walk above depends on: a pass frame's LAST whitespace-separated
# token is still the suite path. Appending the time instead of inserting it would have made that
# token `(1s)` and silently broken the leak detection while every case here stayed green.
sed -n 's/^::group::pass .*[[:space:]]//p' "$OUT" > "$BASE/ac629.tokens"
grep -qxF 'fast-selftest.sh' "$BASE/ac629.tokens" \
  && grep -qxF 'slow-selftest.sh' "$BASE/ac629.tokens" \
  && ok "#629/AC-1: the suite path is still the last token of a pass frame" \
  || { fail "#629/AC-1: elapsed displaced the suite path as the frame's last token"; sed 's/^/    | /' "$BASE/ac629.tokens"; }

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "run-selftests-selftest: PASS"
  exit 0
fi
echo "run-selftests-selftest: FAIL ($FAILS)"
exit 1
