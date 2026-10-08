#!/usr/bin/env bash
# minimize-verdicts-selftest.sh — behavioral selftest for tools/minimize-verdicts.sh (#946 D-10).
#
# INVARIANTS GUARDED: only a comment whose FIRST line is exactly `verdict: approve|needs-work` is
# minimized; only a lane author's (a Bot, or the account $GH writes as); only one posted before the
# kept comment; every write goes through $GH; a failed minimize is reported and the rest still run.
# The run.sh wiring is a scenario case in skills/run/run-selftest.sh.
#
# Operator-safe: a fake gh, no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/minimize-verdicts.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/minimize-verdicts-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# fake gh: $S/comments.json is the PR's comments; each graphql call appends "<as> <node id>" to $S/minimized;
# a node id listed in $S/fail is refused
mkdir -p "$T/bin"
cat > "$T/bin/fake-gh" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_GH"
case "$1 $2" in
  "repo view") echo o/r ;;
  "api user")  echo tester ;;
  "api graphql") node=""; for a in "$@"; do case "$a" in id=*) node="${a#id=}" ;; esac; done
                 grep -qx "$node" "$S/fail" 2>/dev/null && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }
                 echo "${FAKE_AS:-operator} $node" >> "$S/minimized"; echo '{}' ;;
  api*)        case "$2" in repos/o/r/issues/7/comments) cat "$S/comments.json" ;; *) exit 1 ;; esac ;;
  *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/fake-gh"

# c <id> <login> <type> <body> — one comment object
c() { jq -n --argjson i "$1" --arg l "$2" --arg t "$3" --arg b "$4" '{id:$i, node_id:("N\($i)"), user:{login:$l, type:$t}, body:$b}'; }
setup() { S="$T/$1"; mkdir -p "$S"; shift; printf '%s\n' "$@" | jq -s . > "$S/comments.json"; }
run() { FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" "$@" > "$S/out" 2> "$S/err"; }
minimized() { [ -f "$S/minimized" ] && awk '{print $2}' "$S/minimized" | tr '\n' ' '; }

echo "== minimize-verdicts.sh =="

# (m1) the predicate: the first line, exactly
setup predicate \
  "$(c 1 tester User $'verdict: approve\nreviewed: a')" \
  "$(c 2 tester User $'verdict: needs-work\nreviewed: a')" \
  "$(c 3 tester User $'verdict: approve with notes\nreviewed: a')" \
  "$(c 4 tester User $'Verdict: approve')" \
  "$(c 5 tester User $'the head moved during the review; verdict: approve no longer binds')" \
  "$(c 6 tester User $'review did not run\nverdict: needs-work')" \
  "$(c 7 tester User $'status: NOT posted')" \
  "$(c 8 tester User $'verdict: needs-work\r\nreviewed: a')" \
  "$(c 9 tester User $'verdict: approve\nreviewed: b')"
run 7 9; rc=$?
[ "$rc" -eq 0 ] && [ "$(minimized)" = "N1 N2 N8 " ] && ok "(m1) only first-line verdicts are minimized (CRLF too); notices, look-alikes and a verdict on line 2 are left alone" \
  || bad "(m1) rc=$rc minimized='$(minimized)' (want N1 N2 N8) err=$(cat "$S/err")"

# (m2) the author filter: a Bot or the account $GH writes as; never a stranger
setup authors \
  "$(c 10 stranger User 'verdict: approve')" \
  "$(c 11 'second-shift[bot]' Bot 'verdict: needs-work')" \
  "$(c 12 tester User 'verdict: needs-work')" \
  "$(c 13 'second-shift[bot]' Bot 'verdict: approve')"
run 7 13; rc=$?
[ "$rc" -eq 0 ] && [ "$(minimized)" = "N11 N12 " ] && ok "(m2) a stranger's verdict-shaped comment is left alone" \
  || bad "(m2) rc=$rc minimized='$(minimized)' (want N11 N12)"

# (m3) earlier only: the kept comment and anything after it stay expanded
setup earlier \
  "$(c 20 tester User 'verdict: needs-work')" \
  "$(c 21 tester User 'verdict: needs-work')" \
  "$(c 22 tester User 'verdict: approve')" \
  "$(c 23 tester User 'verdict: needs-work')"
run 7 22; rc=$?
[ "$rc" -eq 0 ] && [ "$(minimized)" = "N20 N21 " ] && grep -qx 'minimized 21' "$S/out" && ok "(m3) only verdicts before the kept one are minimized, including one from the same window" \
  || bad "(m3) rc=$rc minimized='$(minimized)' (want N20 N21) out=$(cat "$S/out")"

# (m4) the first verdict on a PR: nothing earlier, nothing written
setup first "$(c 30 tester User 'verdict: approve')"
run 7 30; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$S/minimized" ] && ok "(m4) a PR's first verdict minimizes nothing" || bad "(m4) rc=$rc minimized='$(minimized)'"

# (m5) a kept id that is not a lane verdict refuses rather than collapsing every verdict on the PR
setup notkept "$(c 40 tester User 'verdict: approve')" "$(c 41 tester User 'head moved')" "$(c 42 stranger User 'verdict: approve')"
run 7 41; rc1=$?; run 7 42; rc2=$?; run 7 99; rc3=$?
[ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ] && [ "$rc3" -eq 1 ] && [ ! -f "$S/minimized" ] && ok "(m5) a kept id that is a notice, a stranger's or absent: exit 1, nothing minimized" \
  || bad "(m5) rc=$rc1/$rc2/$rc3 minimized='$(minimized)'"

# (m6) a failed minimize is reported with its error, the rest still run, exit 1
setup fails "$(c 50 tester User 'verdict: needs-work')" "$(c 51 tester User 'verdict: needs-work')" "$(c 52 tester User 'verdict: approve')"
echo N50 > "$S/fail"
run 7 52; rc=$?
[ "$rc" -eq 1 ] && [ "$(minimized)" = "N51 " ] && grep -q 'comment 50 NOT minimized — HTTP 403' "$S/err" && ok "(m6) a refused minimize: named on stderr with its error, the others still minimized, exit 1" \
  || bad "(m6) rc=$rc minimized='$(minimized)' err=$(cat "$S/err")"

# (m7) every write goes through $GH, and --repo skips the slug read
setup identity "$(c 60 'second-shift[bot]' Bot 'verdict: needs-work')" "$(c 61 'second-shift[bot]' Bot 'verdict: approve')"
FAKE_AS=bot FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" --repo o/r 7 61 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$S/minimized")" = "bot N60" ] && ok "(m7) the minimize is written as \$GH" || bad "(m7) rc=$rc minimized='$(cat "$S/minimized" 2>/dev/null)'"

# (m8) unreadable comments and bad usage
S="$T/unreadable"; mkdir -p "$S"
run 8 1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'could not be read' "$S/err" && ok "(m8) unreadable comments: exit 1, named" || bad "(m8) rc=$rc err=$(cat "$S/err")"
run 7; rc1=$?; run x 1; rc2=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && ok "(m9) a missing or non-numeric argument is usage (exit 2)" || bad "(m9) rc=$rc1/$rc2"

echo "minimize-verdicts-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
