#!/usr/bin/env bash
# changed-lines-selftest.sh — behavioral selftest for tools/changed-lines.sh.
#
# INVARIANTS GUARDED: the last reviewed head is line 2 of the latest unedited lane verdict (a Bot's, or the account $GH
# writes as) that has no reason line; a stranger's, an edited one and one with a reason line are passed over. The set
# marks each head line within 3 lines of a hunk of `git diff <reviewed> <head>`, new side, for a changed, an added and
# a pure-deletion hunk, and none for a deleted file; the two-dot diff works when the reviewed sha is no ancestor of the
# head. With no earlier lane verdict, unreadable comments or an unreadable reviewed sha, the tool writes no set (exit 3).
# The run.sh wiring is a scenario case in skills/run/run-later-round-selftest.sh.
#
# Operator-safe: a fake gh, no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/changed-lines.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/changed-lines-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# The fake gh answers as `gh api repos/{owner}/{repo}/issues/{n}/comments --paginate` does: a JSON array of issue
# comment objects (id, user.login, user.type, body, created_at, updated_at), an empty array when the PR has none.
# Shape: https://docs.github.com/en/rest/issues/comments#list-issue-comments. A refused read is gh's non-zero exit with
# its `HTTP <code>: <message>` line on stderr, as gh prints an API error.
mkdir -p "$T/bin"
cat > "$T/bin/fake-gh" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_GH"
case "$1 $2" in
  "repo view") echo o/r ;;
  "api user")  [ -f "$S/no-user" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }; echo tester ;;
  "api repos/o/r/issues/7/comments") [ -f "$S/unreadable" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }; cat "$S/comments.json" ;;
  *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/fake-gh"

# a repo: A has f (20 lines) and d; B edits f line 10; H deletes f line 5, edits old line 15, adds g and deletes d.
# R is a sibling of H off A, H's tree with one more edit at old line 18: a rebased reviewed head
R="$T/repo"; git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
seq 1 20 > "$R/f"; echo gone > "$R/d"; git -C "$R" add -A; git -C "$R" commit -qm A; A="$(git -C "$R" rev-parse HEAD)"
sed '10s/.*/ten/' "$R/f" > "$R/f.t" && mv "$R/f.t" "$R/f"; git -C "$R" commit -qam B; B="$(git -C "$R" rev-parse HEAD)"
sed '5d; 15s/.*/fifteen/' "$R/f" > "$R/f.t" && mv "$R/f.t" "$R/f"; printf 'g1\ng2\n' > "$R/g"; git -C "$R" rm -q d; git -C "$R" add -A; git -C "$R" commit -qm H
H="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b side "$A"; git -C "$R" checkout -q "$H" -- .; git -C "$R" rm -q --cached d 2>/dev/null; rm -f "$R/d"
sed '17s/.*/eighteen/' "$R/f" > "$R/f.t" && mv "$R/f.t" "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm R; RB="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q "$H"

# c <id> <login> <type> <created> <updated> <body> — one comment object
c() { jq -n --argjson i "$1" --arg l "$2" --arg t "$3" --arg c "$4" --arg u "$5" --arg b "$6" '{id:$i, user:{login:$l, type:$t}, created_at:$c, updated_at:$u, body:$b}'; }
setup() { S="$T/$1"; mkdir -p "$S"; shift; if [ $# -eq 0 ]; then echo '[]' > "$S/comments.json"; else printf '%s\n' "$@" | jq -s . > "$S/comments.json"; fi; }
run() { FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" "$@" > "$S/out" 2> "$S/err"; }
t1=2026-01-01T00:00:00Z t2=2026-01-02T00:00:00Z t3=2026-01-03T00:00:00Z t4=2026-01-04T00:00:00Z t5=2026-01-05T00:00:00Z

echo "== changed-lines.sh =="

# (cl1) the latest lane verdict: a stranger's, an edited one and one with a reason line come later and are passed over
setup pick \
  "$(c 1 'second-shift[bot]' Bot $t1 $t1 $'verdict: needs-work\nreviewed: '"$A")" \
  "$(c 2 tester User $t2 $t2 $'verdict: needs-work\r\nreviewed: '"$B"$'\r\n\r\n## Findings')" \
  "$(c 3 tester User $t3 $t4 $'verdict: approve\nreviewed: '"$A")" \
  "$(c 4 tester User $t4 $t4 $'verdict: needs-work\nreviewed: '"$A"$'\nreason: render-unavailable')" \
  "$(c 5 stranger User $t5 $t5 $'verdict: approve\nreviewed: '"$A")" \
  "$(c 6 tester User $t5 $t5 'the head moved during the review')"
run -C "$R" 7 "$H" "$S/set"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$S/out")" = "reviewed: $B" ] \
  && ok "(cl1) the latest unedited lane verdict with no reason line names the reviewed head (CRLF too)" || bad "(cl1) rc=$rc out=$(cat "$S/out") err=$(cat "$S/err")"
# B..H: f loses old line 5 (+4,0) and changes old line 15 (+14); g is new (+1,2); d is deleted
printf 'f:1-7\nf:11-17\ng:1-5\n' > "$S/want"
[ -f "$S/set" ] && diff -u "$S/want" "$S/set" > "$S/diff" \
  && ok "(cl2) the set covers each head line within 3 lines of a changed, an added and a pure-deletion hunk; a deleted file has none" || bad "(cl2) $(cat "$S/diff" 2>/dev/null || echo 'no set written')"

# (cl3) a Bot's verdict binds even when the writer account cannot be read; a reviewed head off another branch still diffs
setup bot "$(c 1 'second-shift[bot]' Bot $t1 $t1 $'verdict: approve\nreviewed: '"$RB")"
touch "$S/no-user"
run -C "$R" 7 "$H" "$S/set"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$S/out")" = "reviewed: $RB" ] && [ "$(cat "$S/set")" = "f:14-20" ] \
  && ok "(cl3) a Bot's verdict on a rebased head: the content diff marks only the line that differs" || bad "(cl3) rc=$rc out=$(cat "$S/out") set=$(tr '\n' ' ' < "$S/set" 2>/dev/null)"

# (cl4) a review of the head the last verdict named: the set is empty, so nothing counts as changed
setup same "$(c 1 tester User $t1 $t1 $'verdict: needs-work\nreviewed: '"$H")"
run --repo o/r -C "$R" 7 "$H" "$S/set"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$S/set" ] && [ ! -s "$S/set" ] && ok "(cl4) the same head: an empty set" || bad "(cl4) rc=$rc set=$(cat "$S/set" 2>/dev/null)"

# (cl5) a full review: no earlier lane verdict, unreadable comments, an unreadable reviewed sha; a stale set is removed
full_ok() { # full_ok <label> <reason pattern>
  [ "$rc" -eq 3 ] && [ ! -e "$S/set" ] && grep -q "^full review: $2" "$S/out" && ok "$1" || bad "$1: rc=$rc out=$(cat "$S/out") set=$([ -e "$S/set" ] && echo present || echo absent)"
}
setup none "$(c 1 stranger User $t1 $t1 $'verdict: approve\nreviewed: '"$A")" "$(c 2 tester User $t2 $t2 'a plain comment')"
echo stale > "$S/set"; run -C "$R" 7 "$H" "$S/set"; rc=$?
full_ok "(cl5) no lane verdict on the PR: a full review, and the stale set is gone" "PR [#]7 has no earlier lane verdict"
setup empty
run -C "$R" 7 "$H" "$S/set"; rc=$?
full_ok "(cl5) a PR with no comments: a full review" "PR [#]7 has no earlier lane verdict"
setup unreadable; touch "$S/unreadable"
run -C "$R" 7 "$H" "$S/set"; rc=$?
full_ok "(cl5) the comments cannot be read: a full review" "the comments of PR [#]7 could not be read"
setup unknown "$(c 1 tester User $t1 $t1 $'verdict: needs-work\nreviewed: 0123456789abcdef0123456789abcdef01234567')"
run -C "$R" 7 "$H" "$S/set"; rc=$?
full_ok "(cl5) a reviewed sha the repo does not hold: a full review" "the reviewed sha 0123456789abcdef0123456789abcdef01234567 cannot be read"

# (cl6) usage
setup usage
run 7 "$H" "$S/set"; rc1=$?; run -C "$R" x "$H" "$S/set"; rc2=$?; run -C "$R" 7 "$H"; rc3=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 2 ] && ok "(cl6) no -C, a non-numeric PR or a missing out file is usage (exit 2)" || bad "(cl6) rc=$rc1/$rc2/$rc3"

echo "changed-lines-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
