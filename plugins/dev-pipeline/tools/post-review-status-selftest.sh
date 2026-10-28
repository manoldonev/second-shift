#!/usr/bin/env bash
# post-review-status-selftest.sh — behavioral selftest for tools/post-review-status.sh (#991 AC-3).
#
# INVARIANTS GUARDED: a body that breaks the verdict grammar posts no status (above all, never `success`)
# and prints its failed rules; a body the checker cannot evaluate posts nothing; a passing approve posts
# success and a passing needs-work failure, on the named sha, under second-shift/review, linking the
# verdict; every write goes through $GH; a refused post is exit 3 with gh's error; a folded rows table posts;
# --recheck reads the posted comment by id, re-posts what a passing one implies and posts error on a failing one.
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
  # `gh api ... --jq .body` prints the comment's body string raw; a missing comment is the REST API's 404
  # ("Get an issue comment", docs.github.com/rest/issues/comments), which gh reports as "gh: Not Found (HTTP 404)"
  "api repos/o/r/issues/comments/"*) f="$S/comment-${2##*/}"; [ -f "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$f" ;;
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

# (p10) #1085: an AC the operator added after the baseline — the head's record lists AC-9 and carries a D-2 row with
# user-answered provenance the first commit lacks, and the plan tags it — is covered: the approve posts success
LEDGER=$'| ID | Decision | Resolution | Provenance | Kind |\n| --- | --- | --- | --- | --- |\n| D-1 | a | b | user-answered | intent |\n'
printf '%s\n## Test intent\n\nACs: AC-1 AC-8\n\nAC-1: x\nAC-8: y\n' "$LEDGER" > "$T/first-dep.md"
printf '%s| D-2 | the guard | restored | user-answered | intent |\n\n## Test intent\n\nACs: AC-1 AC-8 AC-9\n\nAC-1: x\nAC-8: y\nAC-9: the guard\n' "$LEDGER" > "$T/head/docs/plans/r-42-decisions.md"
printf '%s\n' '- [ ] 1.1 a (a.spec.ts) [AC-1] [AC-8]' '- [ ] 1.2 the guard (g.spec.ts) [AC-9]' > "$T/head/docs/plans/r-42-plan.md"
printf 'verdict: approve\nreviewed: %s\n\n## Decision record rows\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n| D-1 | honored | x |\n| D-2 | honored | Added by the build, user-answered. |\n\n## Findings\n\nNone.\n' "$SHA" > "$T/approve-dep.md"
run p10 7 "$SHA" "$T/approve-dep.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first-dep.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'state=success' "$S/posts" && ok "(p10) #1085: an operator-added AC the head defines and the plan tags: the approve posts success" || bad "(p10) rc=$rc posts='$(posts)' out=$(cat "$S/out" "$S/err" | tr '\n' '|')"
# the same AC with no operator row at the head stays red
printf '%s\n## Test intent\n\nACs: AC-1 AC-8 AC-9\n\nAC-1: x\nAC-8: y\nAC-9: the guard\n' "$LEDGER" > "$T/head/docs/plans/r-42-decisions.md"
run p10b 7 "$SHA" "$T/approve-ok.md" "$T/head/docs/plans/r-42-decisions.md" "$T/first-dep.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(posts)" ] && grep -q 'which only the record at the head defines' "$S/out" && ok "(p10) a head-only AC with no operator row: no status, exit 1" || bad "(p10b) rc=$rc posts='$(posts)' out=$(tr '\n' '|' < "$S/out")"

# (p11) a verdict whose rows table is folded under its count summary posts its status
folded() { # folded <verdict> <score> <findings> <summary line 1>
  printf 'verdict: %s\nreviewed: %s\n\n## Summary\n\n%s\nNothing to do.\n\n## Decision record rows\n\n<details><summary>1 rows: 1 %s</summary>\n\n| Row | Score | Evidence |\n| --- | --- | --- |\n| D-1 | %s | x |\n</details>\n\n## Findings\n\n%s\n' "$1" "$SHA" "$4" "$2" "$2" "$3"
}
folded approve honored 'None.' 'Mergeable as it is.' > "$T/folded-ok.md"
run p11 7 "$SHA" "$T/folded-ok.md" "$T/rec.md" "$T/rec.md" https://x/pr/7#c1; rc=$?
[ "$rc" -eq 0 ] && grep -q "^operator repos/o/r/statuses/$SHA -f state=success -f context=second-shift/review " "$S/posts" \
  && ok "(p11) an approve with a folded rows table posts success" || bad "(p11) rc=$rc posts='$(posts)' out=$(cat "$S/out" "$S/err" | tr '\n' '|')"

# --recheck <comment-id>: the posted comment is read through $GH by id, then checked as a body file is
recheck() { S="$T/$1"; mkdir -p "$S"; cp "$2" "$S/comment-$3"; shift 3; FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" "$@" > "$S/out" 2> "$S/err"; }
recheck r1 "$T/folded-ok.md" 55 --recheck 55 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x/pr/7#c55; rc=$?
[ "$rc" -eq 0 ] && [ "$(posts)" = "operator repos/o/r/statuses/$SHA -f state=success -f context=second-shift/review -f target_url=https://x/pr/7#c55 -f description=approved at this head — see the verdict" ] \
  && ok "(r1) --recheck of a passing approve comment re-posts success on the sha" || bad "(r1) rc=$rc posts='$(posts)' err=$(cat "$S/err")"
folded needs-work honored '- [blocker] B1 fix it' 'Not mergeable yet.' > "$T/folded-nw.md"
FAKE_AS=bot recheck r1b "$T/folded-nw.md" 56 --repo o/r --recheck 56 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x/pr/7#c56; rc=$?
[ "$rc" -eq 0 ] && grep -q "^bot repos/o/r/statuses/$SHA .*state=failure .*description=needs-work at this head" "$S/posts" \
  && ok "(r1) --recheck of a passing needs-work comment re-posts failure, written as \$GH" || bad "(r1b) rc=$rc posts='$(posts)' err=$(cat "$S/err")"
# an edit after posting folded the table under a wrong count and dropped its Summary
folded approve honored 'None.' 'Mergeable as it is.' | sed 's/1 rows: 1 honored/2 rows: 2 honored/' | awk '/^## Summary$/ { skip = 1 } /^## Decision record rows$/ { skip = 0 } !skip' > "$T/edited-bad.md"
recheck r2 "$T/edited-bad.md" 57 --recheck 57 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x/pr/7#c57; rc=$?
[ "$rc" -eq 1 ] && [ "$(grep -c . "$S/posts")" = 1 ] && grep -q "^operator repos/o/r/statuses/$SHA -f state=error -f context=second-shift/review -f target_url=https://x/pr/7#c57 -f description=re-check failed: rows summary counts differ from the table" "$S/posts" \
  && grep -q '^- rows summary counts differ from the table' "$S/out" && grep -q '^- folded rows table with no ## Summary' "$S/out" \
  && ok "(r2) --recheck of a failing comment posts error on the sha naming the first rule, prints every rule, exit 1" || bad "(r2) rc=$rc posts='$(posts)' out=$(tr '\n' '|' < "$S/out")"
printf '| ID | Decision |\n| --- | --- |\n| D-1 | a |\n\n## Test intent\n\nACs: AC-1 AC-8\n\nAC-1: x\nAC-8: y\n' > "$T/head/docs/plans/r-43-decisions.md"
printf '%s\n' '- [ ] 1.1 a (a.spec.ts) [AC-1]' > "$T/head/docs/plans/r-43-plan.md"
recheck r3 "$T/folded-ok.md" 58 --recheck 58 7 "$SHA" "$T/head/docs/plans/r-43-decisions.md" "$T/head/docs/plans/r-43-decisions.md" https://x/pr/7#c58; rc=$?
[ "$rc" -eq 1 ] && grep -q "state=error .*description=re-check failed: plan-coverage: RED: AC-8 has no test task" "$S/posts" \
  && ok "(r3) --recheck of an approve whose plan coverage is red posts error, exit 1" || bad "(r3) rc=$rc posts='$(posts)' out=$(tr '\n' '|' < "$S/out")"
S="$T/r4"; mkdir -p "$S"; FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" --recheck 404 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x/pr/7#c404 > "$S/out" 2> "$S/err"; rc=$?
[ "$rc" -eq 2 ] && [ -z "$(posts)" ] && grep -q 'comment 404 could not be read .*HTTP 404' "$S/err" \
  && ok "(r4) --recheck of a comment that cannot be read posts nothing, exit 2" || bad "(r4) rc=$rc posts='$(posts)' err=$(cat "$S/err")"
recheck r5 "$T/edited-bad.md" 59 --recheck 59 7 "$SHA" "$T/rec.md" "$T/no-such-record.md" https://x/pr/7#c59; rc=$?
[ "$rc" -eq 2 ] && [ -z "$(posts)" ] && ok "(r5) --recheck that cannot evaluate the body posts nothing, exit 2" || bad "(r5) rc=$rc posts='$(posts)'"
S="$T/r6"; mkdir -p "$S"; touch "$S/fail"; cp "$T/edited-bad.md" "$S/comment-60"
FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" --recheck 60 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x/pr/7#c60 > "$S/out" 2> "$S/err"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'NOT posted .*HTTP 403' "$S/err" && ok "(r6) --recheck whose error post is refused: exit 3, gh's error named" || bad "(r6) rc=$rc err=$(cat "$S/err")"
recheck r7 "$T/folded-ok.md" 61 --recheck x 7 "$SHA" "$T/rec.md" "$T/rec.md" https://x; rc1=$?
recheck r7 "$T/folded-ok.md" 61 --recheck 61 7 "$SHA" "$T/rec.md" "$T/rec.md"; rc2=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ -z "$(posts)" ] && ok "(r7) --recheck with a malformed id or a missing argument is usage (exit 2)" || bad "(r7) rc=$rc1/$rc2"

echo "post-review-status-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
