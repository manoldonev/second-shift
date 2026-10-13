#!/usr/bin/env bash
# run-selftest-cases-selftest.sh — guards run-selftest.sh's case filter (#1035): `run-selftest.sh <case-id>...` runs only
# the cases a top-level `fixture <id>` line opens, keeps the functions a skipped case defines, prints the cases it ran, and
# exits 2 on an id no case opens. Its own suite, not a run-selftest.sh case: a filter that ignored its arguments would then
# re-run the whole suite, this case included, without end
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$HERE/run-selftest.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
echo "[run-selftest-cases-selftest] run-selftest.sh <case-id>..."

# (ho3) calls lane_says, which only the skipped (ho) defines; (rp4) opens on a VAR=value line continued onto the next
OUT="$(bash "$SUITE" ho3 rp4 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && grep -qx '\[self-test\] [1-9][0-9]* passed, 0 failed' <<<"$OUT" \
  && ok "(ho3 rp4) both cases pass, one of them on a helper a skipped case defines" || bad "(ho3 rp4) rc=$RC: $(tail -n 4 <<<"$OUT" | tr '\n' '|')"
grep -qx '\[run-selftest\] case filter: ran ho3 rp4 ([0-9]* of [0-9]* cases)' <<<"$OUT" && grep -q ' (2 of ' <<<"$OUT" \
  && ok "(ho3 rp4) the run prints the cases it ran" || bad "(ho3 rp4) no case-filter line: $(grep 'case filter' <<<"$OUT")"
others="$(grep -E '^  (ok|FAIL) ' <<<"$OUT" | grep -vE '^  (ok|FAIL) +(\(ho3\)|\[I10\] #1011)')"
ran="$(grep -cE '^  (ok|FAIL) ' <<<"$OUT")"
[ -z "$others" ] && [ "$ran" -gt 1 ] && grep -qx "\[self-test\] $ran passed, 0 failed" <<<"$OUT" \
  && ok "(ho3 rp4) no other case's line ran, and the summary counts only theirs" || bad "(ho3 rp4) $ran result lines; others: $(head -n 3 <<<"$others" | tr '\n' '|')"

# an id no case opens: exit 2 before any case runs, naming the id. (wb1) is opened by a helper's `fixture "$1"`, not a
# top-level line, so it is no case of its own
for id in no-such-case wb1; do
  OUT="$(bash "$SUITE" ho3 "$id" 2>&1)"; RC=$?
  [ "$RC" -eq 2 ] && grep -qF "no case '$id'" <<<"$OUT" && ! grep -qE '^  (ok|FAIL) ' <<<"$OUT" \
    && ok "($id) exits 2 and names the id; no case ran" || bad "($id) rc=$RC: $(tail -n 3 <<<"$OUT" | tr '\n' '|')"
done

echo "[run-selftest-cases-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
