#!/usr/bin/env bash
#
# checked-call-selftest.sh — behavioral coverage for tools/checked-call.sh.
#
# INVARIANT GUARDED: `checked_match` yields THREE distinguishable outcomes where the
# `producer | grep -q P` pipeline it replaces yields two. Case (c5) is the whole ticket —
# it asserts the three return codes are pairwise distinct, and (c10) executes the old
# pipeline beside the new call to show the collapse the old shape actually has. A suite
# that only checked "match returns 0" would pass on a function that returned 1 for both
# a genuine negative and a dead producer, which is the bug.
#
# WHY NO SCENARIO COVERS IT (CLAUDE.md scenario-first rule): this is a pure predicate with
# no state and no terminal write. scenario-liveness-selftest.sh composes verdict paths that
# reach a write; there is no write here to compose onto. Its two production consumers
# (detect.sh's tracker probe, pipeline-doctor.sh's capability probes) both shell out to
# tools a test may not run, so their branches are unreachable from a scenario too.
#
# TECHNIQUE: source the REAL production text and call it. Not a re-declared copy — that is
# the mirror harness CLAUDE.md bans, and it could not fail on a production edit.
#
# Operator-safe: no gh, no network, no Claude CLI. bash-3.2-safe. Runs in CI via the
# '*-selftest.sh' discovery loop.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${CHECKED_CALL_LIB:-$SCRIPT_DIR/checked-call.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$LIB" ]] || {
  echo "checked-call-selftest: FAIL — checked-call.sh not found at $LIB" >&2
  exit 1
}
# shellcheck source=checked-call.sh
. "$LIB"

command -v checked_match >/dev/null 2>&1 || {
  echo "checked-call-selftest: FAIL — sourcing $LIB defined no checked_match" >&2
  exit 1
}

echo "== checked-call: the three outcomes =="

# Producers. Each is a real command whose behavior the case names, so no case depends on
# a stub agreeing with a comment.
# shellcheck disable=SC2317,SC2329  # invoked indirectly — checked_match runs them via "$@".
# Both codes: 0.10+ calls this SC2329, 0.9.0 (what CI installs) calls the same condition
# SC2317. A disable for a code the running version never emits is inert, so naming both is
# the only form that is clean on either.
say_match()   { printf '%s\n' 'server: Playwright (connected)'; }
say_nomatch() { printf '%s\n' 'server: atlassian (connected)'; }
# shellcheck disable=SC2317,SC2329  # ditto.
say_empty()   { :; }
# shellcheck disable=SC2317,SC2329  # ditto.
say_stderr()  { printf '%s\n' 'Playwright' >&2; }
die_7()       { return 7; }

checked_match -i -e playwright -- say_match
rc_match=$?
[[ $rc_match -eq 0 ]] \
  && ok "(c1) producer succeeded and matched -> 0" \
  || bad "(c1) producer succeeded and matched -> expected 0, got $rc_match"

checked_match -i -e playwright -- say_nomatch
rc_nomatch=$?
[[ $rc_nomatch -eq 1 ]] \
  && ok "(c2) producer succeeded, no match -> 1 (a genuine negative)" \
  || bad "(c2) producer succeeded, no match -> expected 1, got $rc_nomatch"

checked_match -i -e playwright -- die_7
rc_dead=$?
[[ $rc_dead -eq 2 ]] \
  && ok "(c3) producer FAILED -> 2 (unknown, not negative)" \
  || bad "(c3) producer FAILED -> expected 2, got $rc_dead"
[[ "${CHECKED_MATCH_RC:-}" == "7" ]] \
  && ok "(c3b) CHECKED_MATCH_RC carries the producer's own status (7)" \
  || bad "(c3b) CHECKED_MATCH_RC expected 7, got '${CHECKED_MATCH_RC:-<unset>}'"

checked_match -i -e playwright -- no-such-command-checked-call-selftest
rc_missing=$?
[[ $rc_missing -eq 2 && "${CHECKED_MATCH_RC:-}" == "127" ]] \
  && ok "(c4) producer not on PATH -> 2, rc 127" \
  || bad "(c4) producer not on PATH -> expected 2/127, got $rc_missing/${CHECKED_MATCH_RC:-<unset>}"

# THE case. Three outcomes are only useful if they are three.
if [[ $rc_match -ne $rc_nomatch && $rc_nomatch -ne $rc_dead && $rc_match -ne $rc_dead ]]; then
  ok "(c5) match / no-match / producer-failed are pairwise DISTINCT ($rc_match, $rc_nomatch, $rc_dead)"
else
  bad "(c5) outcomes collapsed: match=$rc_match no-match=$rc_nomatch dead=$rc_dead"
fi

echo "== checked-call: the edges that decide which outcome you get =="

checked_match -i -e playwright -- say_empty
rc=$?
[[ $rc -eq 1 ]] \
  && ok "(c6) producer succeeded with EMPTY output -> 1, not 2 — silence is a negative, not a failure" \
  || bad "(c6) empty-but-successful producer -> expected 1, got $rc"

checked_match -i -e playwright -- say_stderr
rc=$?
[[ $rc -eq 1 ]] \
  && ok "(c7) the pattern on STDERR does not match — an error message cannot fake a positive" \
  || bad "(c7) stderr reached the matcher -> expected 1, got $rc"

checked_match -e '--head' -- printf '%s\n' '      --head string'
rc=$?
[[ $rc -eq 0 ]] \
  && ok "(c8) a leading-hyphen pattern under -e matches (no '--' needed inside the grep args)" \
  || bad "(c8) leading-hyphen pattern -> expected 0, got $rc"

echo "== checked-call: usage errors land in the caller's default (safe) arm =="

for spec in "no-separator:-e foo" "no-grep-args:-- true" "no-producer:-e foo --"; do
  label="${spec%%:*}"
  # shellcheck disable=SC2086  # deliberate word-splitting: each spec IS an argv fragment.
  checked_match ${spec#*:} 2>/dev/null
  rc=$?
  [[ $rc -eq 3 ]] \
    && ok "(c9/$label) -> 3" \
    || bad "(c9/$label) -> expected 3, got $rc"
done

echo "== checked-call: the collapse it replaces, executed =="

# The old shape, run for real against the SAME two producers that (c2) and (c3) separate.
# Both arms are non-zero and indistinguishable — that is the defect, and pinning it here is
# what makes (c5) a claim about the world rather than about our own return statements.
say_nomatch 2>/dev/null | grep -qi -e playwright
old_nomatch=$?
die_7 2>/dev/null | grep -qi -e playwright
old_dead=$?
if [[ $old_nomatch -eq $old_dead ]]; then
  ok "(c10) the replaced pipeline reports the same rc ($old_nomatch) for 'no match' and 'producer died'"
else
  bad "(c10) the replaced pipeline separated them ($old_nomatch vs $old_dead) — re-read this suite's premise before trusting it"
fi

echo
echo "checked-call-selftest: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
