#!/usr/bin/env bash
# check-sweep-bound-selftest.sh — behavioral suite for tools/check-sweep-bound.sh (#629).
#
# EVERY CASE RUNS AGAINST A SYNTHETIC FIXTURE TREE, never a copy of this repo. The checker's
# whole job is arithmetic over a discovered suite set, a table and a baseline; a fixture lets one
# case state exactly one property of that, and it keeps the suite well under the threshold the
# table it guards would otherwise apply to this file.
#
# THE PAIR THAT MATTERS is (d) and (e): a log naming a suite discovery did not produce is a RED,
# and the same shape arriving INSIDE another suite's framing is not. run-selftests-selftest.sh
# nests runners over throwaway trees, so every honest nightly log carries the second — a checker
# that could not tell them apart would red every night and be baselined away within a week.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CHECKER="$HERE/check-sweep-bound.sh"
TAB=$'\t'

[[ -f "$CHECKER" ]] || { echo "[sweep-bound-selftest] FATAL: $CHECKER is missing"; exit 99; }

FAIL=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sweep-bound-selftest.XXXXXX")" || exit 99
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---- fixture construction -----------------------------------------------------------------
# suite <root> <relpath> — an empty discoverable suite. Never executed by anything here; the
# checker reads the tree only to answer "is this a suite that exists?".
suite() { mkdir -p "$(dirname "$1/$2")"; printf '#!/usr/bin/env bash\n' > "$1/$2"; }

# table() and baseline() both write tools/selftest-suite-timings.tsv (#641: --table and
# --baseline default to the same unified file), so each preserves whatever the other already
# wrote there — neither call knows whether it runs first.

# table <root> <threshold> <deferred-suite>... — the slow-suite table the checker resolves.
table() {
  local root="$1" thr="$2"; shift 2
  mkdir -p "$root/tools"
  local f="$root/tools/selftest-suite-timings.tsv"
  local kept=""
  [[ -f "$f" ]] && kept="$(grep -E '^# (baseline-seconds|allowance-percent)' "$f" || true)"
  {
    printf '# fixture slow-suite table\n'
    printf '# threshold-seconds%s%s\n' "$TAB" "$thr"
    [[ -n "$kept" ]] && printf '%s\n' "$kept"
    local s
    for s in "$@"; do printf '%s%s99%sdeferred by this fixture\n' "$s" "$TAB" "$TAB"; done
  } > "$f"
}

baseline() { # <root> <seconds> <allowance>
  local root="$1" secs="$2" allow="$3"
  mkdir -p "$root/tools"
  local f="$root/tools/selftest-suite-timings.tsv"
  local rest=""
  [[ -f "$f" ]] && rest="$(grep -v '^# baseline-seconds\|^# allowance-percent' "$f" || true)"
  {
    [[ -n "$rest" ]] && printf '%s\n' "$rest"
    printf '# baseline-seconds%s%s\n' "$TAB" "$secs"
    printf '# allowance-percent%s%s\n' "$TAB" "$allow"
  } > "$f"
}

frame() { # <status> <elapsed-field> <suite> [inner-line...]
  local st="$1" el="$2" su="$3"; shift 3
  printf '::group::%s  %s  %s\n' "$st" "$el" "$su"
  [[ $# -gt 0 ]] && printf '%s\n' "$@"
  printf '::endgroup::\n'
}

run() { bash "$CHECKER" "$@" > "$TMP/out" 2>&1; echo $?; }
dump() { sed 's/^/    | /' "$TMP/out" >&2; }

# The standing tree: two un-deferred suites summing to 30s, one tabled suite the sum must ignore.
R="$TMP/root"
suite "$R" a-selftest.sh
suite "$R" nested/b-selftest.sh
suite "$R" heavy-selftest.sh
table "$R" 25 heavy-selftest.sh
{
  frame pass 10s a-selftest.sh
  frame pass 20s nested/b-selftest.sh
  frame pass 400s heavy-selftest.sh
} > "$TMP/green.log"

# ---------------------------------------------------------------------------------------
# (a) AC-2 — inside the allowance: exit 0, and the summary names the sum, the baseline and the
# drift. The tabled suite's 400s is in the log and must NOT be in the sum; if it were, no
# baseline this case could write would pass.
# ---------------------------------------------------------------------------------------
baseline "$R" 30 10
RC="$(run --log "$TMP/green.log" --root "$R")"
if [[ "$RC" -eq 0 ]] \
  && grep -qF '30s over 2 suite(s)' "$TMP/out" \
  && grep -qF 'baseline 30s' "$TMP/out" \
  && grep -qF 'drift 0%' "$TMP/out"; then
  ok "(a) AC-2: an un-deferred sum inside the allowance exits 0 and names sum, baseline and drift"
else
  bad "(a) AC-2: expected a clean summary naming sum/baseline/drift, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (b) AC-2 — over the allowance: exit 1, and the red carries all five things a reader acts on.
# ---------------------------------------------------------------------------------------
baseline "$R" 25 10
RC="$(run --log "$TMP/green.log" --root "$R")"
MISS=""
grep -qF 'sum is 30s' "$TMP/out"           || MISS="$MISS sum"
grep -qF 'baseline is 25s' "$TMP/out"      || MISS="$MISS baseline"
grep -qF 'Drift: 20%' "$TMP/out"           || MISS="$MISS drift"
grep -qF 'largest un-deferred contributors' "$TMP/out" || MISS="$MISS contributors"
grep -qF 'nested/b-selftest.sh' "$TMP/out" || MISS="$MISS top-contributor-name"
grep -qF 'TABLE THE SUITE' "$TMP/out"      || MISS="$MISS remedy-1"
grep -qF 'RE-BASELINE' "$TMP/out"          || MISS="$MISS remedy-2"
if [[ "$RC" -eq 1 && -z "$MISS" ]]; then
  ok "(b) AC-2: a breach exits 1 naming sum, baseline, drift, the largest contributors and both remedies"
else
  bad "(b) AC-2: rc=$RC, missing from the red:${MISS:- nothing}"; dump
fi

# ---------------------------------------------------------------------------------------
# (c) AC-2 — the boundary. A sum landing EXACTLY on the allowance is inside it. Asserted
# because the comparison is cross-multiplied rather than taken against a rounded limit, and an
# off-by-one there would red an honest lane at the one drift it is most likely to sit at.
# ---------------------------------------------------------------------------------------
baseline "$R" 30 10
{ frame pass 13s a-selftest.sh; frame pass 20s nested/b-selftest.sh; } > "$TMP/edge.log"
RC="$(run --log "$TMP/edge.log" --root "$R")"
[[ "$RC" -eq 0 ]] \
  && ok "(c) AC-2: a sum exactly on the allowance is inside it" \
  || { bad "(c) AC-2: 33s against 30s+10% should pass, got rc=$RC"; dump; }

{ frame pass 14s a-selftest.sh; frame pass 20s nested/b-selftest.sh; } > "$TMP/edge2.log"
RC="$(run --log "$TMP/edge2.log" --root "$R")"
[[ "$RC" -eq 1 ]] \
  && ok "(c) AC-2: one second past the allowance reds" \
  || { bad "(c) AC-2: 34s against 30s+10% should red, got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (d) AC-3 — an un-tabled suite at the threshold warns BY NAME and still exits 0. The aggregate
# is deliberately left inside the allowance: a per-suite overage must never be what reds.
# ---------------------------------------------------------------------------------------
suite "$R" grower-selftest.sh
baseline "$R" 55 10
{
  frame pass 10s a-selftest.sh
  frame pass 20s nested/b-selftest.sh
  frame pass 25s grower-selftest.sh
} > "$TMP/warn.log"
RC="$(run --log "$TMP/warn.log" --root "$R")"
if [[ "$RC" -eq 0 ]] \
  && grep -qF 'warning: grower-selftest.sh measured 25s' "$TMP/out" \
  && grep -qF '1 per-suite warning(s)' "$TMP/out"; then
  ok "(d) AC-3: a suite at the table threshold is named as a warning and exits 0"
else
  bad "(d) AC-3: expected a named warning with rc=0, got rc=$RC"; dump
fi

# The same suite one second under the threshold is silent — otherwise the warning would be
# proving only that the checker prints something.
{
  frame pass 10s a-selftest.sh
  frame pass 20s nested/b-selftest.sh
  frame pass 24s grower-selftest.sh
} > "$TMP/quiet.log"
RC="$(run --log "$TMP/quiet.log" --root "$R")"
if [[ "$RC" -eq 0 ]] && grep -qF '0 per-suite warning(s)' "$TMP/out"; then
  ok "(d) AC-3: a suite under the threshold warns about nothing"
else
  bad "(d) AC-3: 24s against a 25s threshold should be silent, got rc=$RC"; dump
fi
rm -f "$R/grower-selftest.sh"

# ---------------------------------------------------------------------------------------
# (e) AC-4 — every way the input can fail to be readable is exit 2. Table-driven, because the
# property under test is that NO arm of it exits 0.
# ---------------------------------------------------------------------------------------
baseline "$R" 30 10

RC="$(run --root "$R")"
[[ "$RC" -eq 2 ]] && ok "(e) AC-4: no --log at all is exit 2" \
  || { bad "(e) AC-4: a missing --log must not be scored, got rc=$RC"; dump; }

RC="$(run --log "$TMP/does-not-exist.log" --root "$R")"
[[ "$RC" -eq 2 ]] && ok "(e) AC-4: an absent log file is exit 2" \
  || { bad "(e) AC-4: an absent log must not be scored, got rc=$RC"; dump; }

# A cached frame carries a literal dash: the suite was not run, so it has no elapsed. Summing it
# as zero would make a fully-cached sweep the cheapest one on record.
{ frame pass 10s a-selftest.sh; frame cached - nested/b-selftest.sh; } > "$TMP/cached.log"
RC="$(run --log "$TMP/cached.log" --root "$R")"
if [[ "$RC" -eq 2 ]] && grep -qF 'unparseable elapsed field' "$TMP/out"; then
  ok "(e) AC-4: an unmeasured (cached) suite is exit 2, not a free suite"
else
  bad "(e) AC-4: a dash elapsed field must red, got rc=$RC"; dump
fi

# The pre-#629 frame shape, which carries no elapsed field at all. A revert of the emitter must
# red here rather than summing suite paths.
{ printf '::group::pass  a-selftest.sh\n::endgroup::\n'; } > "$TMP/oldshape.log"
RC="$(run --log "$TMP/oldshape.log" --root "$R")"
[[ "$RC" -eq 2 ]] && ok "(e) AC-4: a frame line with no elapsed field is exit 2" \
  || { bad "(e) AC-4: the pre-emitter frame shape must red, got rc=$RC"; dump; }

{
  frame pass 10s a-selftest.sh
  frame pass 20s nested/b-selftest.sh
  frame pass 5s ghost-selftest.sh
} > "$TMP/ghost.log"
RC="$(run --log "$TMP/ghost.log" --root "$R")"
if [[ "$RC" -eq 2 ]] && grep -qF 'ghost-selftest.sh' "$TMP/out"; then
  ok "(e) AC-4: a timing naming a suite discovery did not produce is exit 2"
else
  bad "(e) AC-4: an undiscovered suite must red by name, got rc=$RC"; dump
fi

{ frame pass 10s a-selftest.sh; } > "$TMP/partial.log"
RC="$(run --log "$TMP/partial.log" --root "$R")"
if [[ "$RC" -eq 2 ]] && grep -qF 'nested/b-selftest.sh' "$TMP/out"; then
  ok "(e) AC-4: an un-deferred suite with no timing at all is exit 2, named"
else
  bad "(e) AC-4: an incomplete sum must red naming what is missing, got rc=$RC"; dump
fi

{ frame pass 10s a-selftest.sh; frame pass 20s nested/b-selftest.sh; printf '::endgroup::\n'; } > "$TMP/unbalanced.log"
RC="$(run --log "$TMP/unbalanced.log" --root "$R")"
[[ "$RC" -eq 2 ]] && ok "(e) AC-4: a replay whose framing does not balance is exit 2" \
  || { bad "(e) AC-4: unbalanced framing must red, got rc=$RC"; dump; }

# THE DUPLICATE IS THE ONLY DEFECT HERE, and that costs a line of fixture care. A log that
# merely repeats one suite is ALSO missing the other, so the completeness arm reds it and the
# case proves nothing about duplicates — measured: with the duplicate check neutered this case
# still passed. Both un-deferred suites are present, and the repeat is small enough that summing
# it twice stays inside the allowance, so exit 2 can only come from the arm under test.
{
  frame pass 10s a-selftest.sh
  frame pass 20s nested/b-selftest.sh
  frame pass 1s a-selftest.sh
} > "$TMP/dup.log"
RC="$(run --log "$TMP/dup.log" --root "$R")"
if [[ "$RC" -eq 2 ]] && grep -qF 'twice' "$TMP/out"; then
  ok "(e) AC-4: one suite framed twice is exit 2"
else
  bad "(e) AC-4: two sweeps in one log cannot be summed, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (f) AC-4's negative control, and the case the guard is most likely to be wrong about. A
# NESTED runner's frames sit inside a real suite's block and name suites that exist nowhere.
# They must be invisible, and the outer suite's own time must still be summed.
# ---------------------------------------------------------------------------------------
{
  frame pass 10s a-selftest.sh \
    '::group::pass  1s  p1-selftest.sh' \
    '[run-selftests] fixture output' \
    '::endgroup::' \
    '::group::FAIL  2s  p2-selftest.sh (rc=1)' \
    '::endgroup::'
  frame pass 20s nested/b-selftest.sh
} > "$TMP/nested.log"
baseline "$R" 30 10
RC="$(run --log "$TMP/nested.log" --root "$R")"
if [[ "$RC" -eq 0 ]] && grep -qF '30s over 2 suite(s)' "$TMP/out"; then
  ok "(f) AC-4: frames nested inside a suite's own output are not read as timings"
else
  bad "(f) AC-4: a nested runner's frames leaked into the sum or reded the run (rc=$RC)"; dump
fi

# ---------------------------------------------------------------------------------------
# (g) The two declarations the checker cannot proceed without. Neither may degrade to a default:
# a missing threshold would silence AC-3 wholesale, and a missing baseline would leave the
# aggregate compared against nothing.
# ---------------------------------------------------------------------------------------
table "$R" 25 heavy-selftest.sh
sed '/^# threshold-seconds/d' "$R/tools/selftest-suite-timings.tsv" > "$TMP/nothr.tsv"
RC="$(run --log "$TMP/green.log" --root "$R" --table "$TMP/nothr.tsv")"
if [[ "$RC" -eq 2 ]] && grep -qF 'threshold-seconds' "$TMP/out"; then
  ok "(g) AC-4: a table declaring no threshold is exit 2"
else
  bad "(g) AC-4: a missing threshold directive must red, got rc=$RC"; dump
fi

printf '# allowance-percent%s10\n' "$TAB" > "$TMP/nobase.tsv"
RC="$(run --log "$TMP/green.log" --root "$R" --baseline "$TMP/nobase.tsv")"
[[ "$RC" -eq 2 ]] && ok "(g) AC-4: a baseline record with no baseline-seconds is exit 2" \
  || { bad "(g) AC-4: a baseline missing its sum must red, got rc=$RC"; dump; }

printf '# baseline-seconds%s0\n# allowance-percent%s10\n' "$TAB" "$TAB" > "$TMP/zerobase.tsv"
RC="$(run --log "$TMP/green.log" --root "$R" --baseline "$TMP/zerobase.tsv")"
[[ "$RC" -eq 2 ]] && ok "(g) AC-4: a zero baseline is exit 2, not a bound everything breaches" \
  || { bad "(g) AC-4: baseline-seconds=0 must red, got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (h) AC-5 — ONE execution surface. Asserted over .github/workflows/ rather than in prose,
# because the whole reason this check is nightly-only is that a PR runner's slow-end sample
# would red an honest PR (D-1). A second wiring is the regression.
# ---------------------------------------------------------------------------------------
WIRED="$(cd "$REPO/.github/workflows" && grep -lF 'check-sweep-bound.sh' -- *.yml 2>/dev/null | LC_ALL=C sort)"
if [[ "$WIRED" == "nightly-guards.yml" ]]; then
  ok "(h) AC-5: check-sweep-bound.sh is invoked from nightly-guards.yml and nowhere else"
else
  bad "(h) AC-5: expected exactly nightly-guards.yml to invoke the checker, got: ${WIRED:-<nothing>}"
fi

# ---------------------------------------------------------------------------------------
# (i) The LIVE table, driven behaviorally rather than grepped. The fixture log and baseline are
# held fixed and only the table is swapped for the repo's own, so the case reds two ways: the
# directive going missing (exit 2) and the threshold moving (the warning count changes). Both
# would otherwise be learned from a nightly.
# ---------------------------------------------------------------------------------------
L="$TMP/live-root"
suite "$L" c-selftest.sh
baseline "$L" 12 10
{ frame pass 12s c-selftest.sh; } > "$TMP/live.log"
RC="$(run --log "$TMP/live.log" --root "$L" --table "$REPO/tools/selftest-suite-timings.tsv")"
if [[ "$RC" -eq 0 ]] && grep -qF '1 per-suite warning(s)' "$TMP/out"; then
  ok "(i) the live slow-suite table declares a threshold the checker reads, and it is at most 12s"
else
  bad "(i) the live table's threshold directive is missing or has moved (rc=$RC)"; dump
fi

# ---------------------------------------------------------------------------------------
# (j) The default --root, which the one execution surface relies on: nightly-guards.yml invokes
# the checker with a --log and nothing else. If that default stopped resolving to the repo the
# checker ships in, the nightly would red for a reason no reader would connect to a sweep.
#
# Asserted through a log naming one REAL suite and no others: discovery over the repo must then
# find the rest of the un-deferred set missing, which is a message a wrong root cannot produce.
# ---------------------------------------------------------------------------------------
{ frame pass 1s tools/check-sweep-bound-selftest.sh; } > "$TMP/noroot.log"
bash "$CHECKER" --log "$TMP/noroot.log" > "$TMP/out" 2>&1
RC=$?
NAMED="$(grep -cE '^  [A-Za-z].*-selftest\.sh$' "$TMP/out")"
if [[ "$RC" -eq 2 ]] \
  && grep -qF 'no timing for these un-deferred suites' "$TMP/out" \
  && [[ "$NAMED" -ge 40 ]]; then
  ok "(j) with no --root the checker discovers the repo it ships in ($NAMED un-deferred suites unaccounted for)"
else
  bad "(j) the default --root did not resolve to this repo (rc=$RC, $NAMED suites named)"; dump
fi

# ---------------------------------------------------------------------------------------
# (k) TMPDIR unset. The ubuntu lane that runs this check does not set it, so the fallback in the
# scratch allocation is the path CI actually takes — and a local run with TMPDIR set can never
# observe it. Same scrub run-selftests-selftest.sh applies for the same reason.
# ---------------------------------------------------------------------------------------
baseline "$R" 30 10
env -u TMPDIR bash "$CHECKER" --log "$TMP/green.log" --root "$R" > "$TMP/out" 2>&1
RC=$?
[[ "$RC" -eq 0 ]] && ok "(k) the scratch allocation works with TMPDIR unset, as it is on the nightly lane" \
  || { bad "(k) TMPDIR unset broke the run (rc=$RC)"; dump; }

# ---------------------------------------------------------------------------------------
# (l) --help is range-free: it prints the header comment up to its last line and stops. The
# alternative — a line range — starts leaking `set -uo pipefail` into the help text the first
# time anyone edits the prose above it, which is silent and permanent. Same case
# reap-lean-fixtures-selftest.sh carries for the same idiom.
# ---------------------------------------------------------------------------------------
bash "$CHECKER" --help > "$TMP/out" 2>&1
RC=$?
if [[ "$RC" -eq 0 ]] \
  && grep -qF 'check-sweep-bound.sh --log' "$TMP/out" \
  && grep -qF 'EXIT: 0 within allowance' "$TMP/out" \
  && ! grep -qF 'set -uo pipefail' "$TMP/out"; then
  ok "(l) --help prints through the last header line and stops before the code"
else
  bad "(l) --help is truncated, empty, or leaking code (rc=$RC)"; dump
fi

echo "[sweep-bound-selftest] $FAIL failure(s)"
exit "$FAIL"
