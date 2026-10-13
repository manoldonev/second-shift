#!/usr/bin/env bash
# post-review-status-selftest.sh — behavioral selftest for tools/post-review-status.sh (#991 AC-3).
#
# INVARIANTS GUARDED: a body that breaks the verdict grammar posts no status (above all, never `success`)
# and prints its failed rules; a body the checker cannot evaluate posts nothing; a passing approve posts
# success and a passing needs-work failure, on the named sha, under second-shift/review, linking the
# verdict; every write goes through $GH; a refused post is exit 3 with gh's error.
#
# Operator-safe: a fake gh, no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/post-review-status.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/post-review-status-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# fake gh: each status post appends "<as> <path> <fields>" to $FAKE_GH/posts; $FAKE_GH/fail refuses it with
# the message GitHub returns when an App lacks a permission ("Resource not accessible by integration", the
# REST API's 403 body — the same shape minimize-verdicts-selftest.sh and run-verdict-selftest.sh's cs8 double)
mkdir -p "$T/bin"
cat > "$T/bin/fake-gh" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_GH"
case "$1 $2" in
  "repo view") echo o/r ;;
  "api -X")    [ -f "$S/fail" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }
               p="$4"; shift 4; echo "${FAKE_AS:-operator} $p $*" >> "$S/posts"; echo '{}' ;;
  *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/fake-gh"

SHA=0123456789abcdef0123456789abcdef01234567
printf '| ID | Decision |\n| --- | --- |\n| D-1 | a |\n' > "$T/rec.md"
verdict() { printf 'verdict: %s\nreviewed: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n| D-1 | %s | x |\n\n## Findings\n\n%s\n' "$1" "$SHA" "$2" "$3" > "$T/$4.md"; }
run() { S="$T/$1"; mkdir -p "$S"; shift; FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" "$@" > "$S/out" 2> "$S/err"; }
posts() { cat "$S/posts" 2>/dev/null; }

echo "== post-review-status.sh =="

verdict approve honored '- [blocker] B1 must change before merge' approve-blocker
run p1 7 "$SHA" "$T/approve-blocker.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q '^- approve with a blocker' "$S/out" && grep -q 'NOT posted' "$S/out" \
  && ok "(p1) an approve with a [blocker]: no status at all, the failed rule printed, exit 1" || bad "(p1) rc=$rc posts='$(posts)' out=$(tr '\n' '|' < "$S/out")"

verdict approve honored 'No blockers.' approve-prose
run p2 7 "$SHA" "$T/approve-prose.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q 'Findings not in the grammar' "$S/out" && ok "(p2) an approve whose findings are not in the grammar posts nothing" || bad "(p2) rc=$rc posts='$(posts)'"

verdict approve honored 'None.' approve-ok
run p3 7 "$SHA" "$T/approve-ok.md" "$T/rec.md" "$T/no-such-record.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 2 ] && [ -z "$(posts)" ] && ok "(p3) a record that cannot be read: nothing posted, exit 2" || bad "(p3) rc=$rc posts='$(posts)'"

run p4 7 "$SHA" "$T/approve-ok.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 0 ] && [ "$(posts)" = "operator repos/o/r/statuses/$SHA -f state=success -f context=second-shift/review -f target_url=https://x/pr/7#c1 -f description=approved at this head — see the verdict" ] \
  && ok "(p4) a passing approve posts success on the sha, under second-shift/review, linking the verdict" || bad "(p4) rc=$rc posts='$(posts)' err=$(cat "$S/err")"

verdict needs-work honored '- [blocker] B1 fix it' nw-ok
FAKE_AS=bot run p5 --repo o/r 7 "$SHA" "$T/nw-ok.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c2; rc=$?
[ "$rc" -eq 0 ] && grep -q '^bot repos/o/r/statuses/.* state=failure .*description=needs-work at this head' "$S/posts" \
  && ok "(p5) a passing needs-work posts failure, written as \$GH" || bad "(p5) rc=$rc posts='$(posts)'"

verdict needs-work honored '- [note] N1 optional' nw-noblocker
run p6 7 "$SHA" "$T/nw-noblocker.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c3; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q 'needs-work with no blocker' "$S/out" && ok "(p6) a needs-work with nothing to fix posts nothing" || bad "(p6) rc=$rc posts='$(posts)'"

S="$T/p7"; mkdir -p "$S"; touch "$S/fail"
FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" 7 "$SHA" "$T/approve-ok.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c1 > "$S/out" 2> "$S/err"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'NOT posted .*HTTP 403' "$S/err" && ok "(p7) a refused post: exit 3, gh's error named" || bad "(p7) rc=$rc err=$(cat "$S/err")"

run p8 7 "$SHA" "$T/approve-ok.md" "$T/rec.md" "$T/rec.md"; rc1=$?
run p8 x "$SHA" "$T/approve-ok.md" "$T/rec.md" "$T/rec.md" https://x; rc2=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ -z "$(posts)" ] && ok "(p8) a missing or malformed argument is usage (exit 2)" || bad "(p8) rc=$rc1/$rc2"

# (p9) #1039 AC-5 / D-10: on the handoff path an approve is held to the plan's AC coverage — the record at FIRST names
# AC-1 and AC-8, the plan beside the record at the head tags only AC-1 (and the head's record exempts AC-8, which is not
# what the check reads): nothing posted, exit 1, the coverage report printed
mkdir -p "$T/head/docs/plans"
printf '| ID | Decision |\n| --- | --- |\n| D-1 | a |\n\n## Test intent\n\nACs: AC-1 AC-8\n\nAC-1: x\nAC-8: y\n' > "$T/first.md"
printf '| ID | Decision |\n| --- | --- |\n| D-1 | a |\n\n## Test intent\n\nACs: AC-1 AC-8\n\nAC-1: x\nAC-8: exempt — the build says so\n' > "$T/head/docs/plans/r-42-decisions.md"
printf '%s\n' '- [ ] 1.1 a (a.spec.ts) [AC-1]' > "$T/head/docs/plans/r-42-plan.md"
run p9 7 "$SHA" "$T/approve-ok.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q "NOT posted on $SHA: the approve's plan coverage is red" "$S/out" && grep -q '^- plan-coverage: RED: AC-8 has no test task' "$S/out" \
  && ok "(p9) an approve whose plan leaves AC-8 uncovered: no status, the coverage report printed, exit 1" || bad "(p9) rc=$rc posts='$(posts)' out=$(tr '\n' '|' < "$S/out")"
# a needs-work posts failure whatever the coverage
verdict needs-work honored '- [blocker] B1 AC-8 has no test' nw-cov
run p9b 7 "$SHA" "$T/nw-cov.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first.md" https://x/pr/7#c2; rc=$?
[ "$rc" -eq 0 ] && grep -q 'state=failure' "$S/posts" && ok "(p9) a needs-work on the same red plan still posts failure" || bad "(p9b) rc=$rc posts='$(posts)'"
# once the plan covers AC-8 the approve posts success; a missing plan is red too
printf '%s\n' '- [ ] 1.1 a (a.spec.ts) [AC-1] [AC-8]' > "$T/head/docs/plans/r-42-plan.md"
run p9c 7 "$SHA" "$T/approve-ok.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'state=success' "$S/posts" && ok "(p9) the covering plan: the approve posts success" || bad "(p9c) rc=$rc posts='$(posts)' out=$(cat "$S/out" "$S/err")"
rm "$T/head/docs/plans/r-42-plan.md"
run p9d 7 "$SHA" "$T/approve-ok.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q 'RED: no plan' "$S/out" && ok "(p9) no plan beside the record: no status, exit 1" || bad "(p9d) rc=$rc posts='$(posts)'"
# a record whose Test intent cannot be read as an AC set: nothing posted, exit 2
printf '## Test intent\n\nAC-1: x\n' > "$T/first-noacs.md"
run p9e 7 "$SHA" "$T/approve-ok.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first-noacs.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 2 ] && [ -z "$(posts)" ] && ok "(p9) an uncheckable coverage: nothing posted, exit 2" || bad "(p9e) rc=$rc posts='$(posts)'"

echo "post-review-status-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
