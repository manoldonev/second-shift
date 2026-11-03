#!/usr/bin/env bash
# plain-review-tools-selftest.sh — behavioral selftest for scripts/plain-review-tools.sh.
#
# INVARIANTS GUARDED: in this repo it finds plugins/dev-pipeline/tools; in a plugin cache it picks the highest
# dev-pipeline version (10.x above 9.x) and refuses one whose tools dir has no plain review; with no dev-pipeline at
# all it is exit 1.
#
# Operator-safe: no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/plain-review-tools.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/plain-review-tools-selftest.XXXXXX")"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

P="$T/repo/plugins"; mkdir -p "$P/review-toolkit/scripts" "$P/dev-pipeline/tools"
cp "$TOOL" "$P/review-toolkit/scripts/"; touch "$P/dev-pipeline/tools/plain-review.sh" "$P/dev-pipeline/tools/verdict-join.sh"
OUT="$(bash "$P/review-toolkit/scripts/plain-review-tools.sh")"; RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "$P/dev-pipeline/tools" ] && ok "(t1) the repo layout resolves to plugins/dev-pipeline/tools" || bad "(t1) rc=$RC out=$OUT"

C="$T/cache/second-shift"
mkdir -p "$C/review-toolkit/3.0.0/scripts" "$C/dev-pipeline/9.0.0/tools" "$C/dev-pipeline/10.0.0/tools"
cp "$TOOL" "$C/review-toolkit/3.0.0/scripts/"
touch "$C/dev-pipeline/9.0.0/tools/plain-review.sh" "$C/dev-pipeline/9.0.0/tools/verdict-join.sh" \
  "$C/dev-pipeline/10.0.0/tools/plain-review.sh" "$C/dev-pipeline/10.0.0/tools/verdict-join.sh"
OUT="$(bash "$C/review-toolkit/3.0.0/scripts/plain-review-tools.sh")"; RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "$C/dev-pipeline/10.0.0/tools" ] && ok "(t2) the cache layout picks the highest version" || bad "(t2) rc=$RC out=$OUT"

rm "$C/dev-pipeline/10.0.0/tools/plain-review.sh"
bash "$C/review-toolkit/3.0.0/scripts/plain-review-tools.sh" >/dev/null 2>"$T/err"; RC=$?
[ "$RC" -eq 1 ] && grep -q 'has no plain review' "$T/err" && ok "(t3) a dev-pipeline with no plain review is exit 1" || bad "(t3) rc=$RC $(cat "$T/err")"

rm -rf "$C/dev-pipeline"
bash "$C/review-toolkit/3.0.0/scripts/plain-review-tools.sh" >/dev/null 2>"$T/err"; RC=$?
[ "$RC" -eq 1 ] && grep -q 'not installed' "$T/err" && ok "(t4) no dev-pipeline at all is exit 1" || bad "(t4) rc=$RC $(cat "$T/err")"

echo "plain-review-tools-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
