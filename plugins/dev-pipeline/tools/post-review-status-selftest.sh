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
# REST API's 403 body — the same shape minimize-verdicts-selftest.sh and run-selftest.sh's cs8 double)
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

echo "post-review-status-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
