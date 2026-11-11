#!/usr/bin/env bash
# other-comments-selftest.sh — behavioral selftest for tools/other-comments.sh.
#
# INVARIANTS GUARDED: issue comments, inline review comments and non-empty review bodies at or before the start count,
# per author; the gh login and <appName>[bot] never count, the name resolved as bot-commit.sh resolves it, bot enabled
# or not; a failed or malformed read exits 1 and leaves no file, so no 0 stands for a failure.
#
# The fake gh's shapes come from GitHub's REST docs: list issue comments
# (docs.github.com/en/rest/issues/comments#list-issue-comments) and list review comments
# (docs.github.com/en/rest/pulls/comments#list-review-comments-on-a-pull-request) carry user.login and created_at, and
# user is nullable (a deleted account); list reviews (docs.github.com/en/rest/pulls/reviews#list-reviews-for-a-pull-request)
# carries body, which is "" on a review left without one, and submitted_at, which a PENDING review lacks. Each list is
# an array, [] when empty, and `gh api --paginate` prints one array per page (minimize-verdicts.sh reads it the same
# way). A refused read is gh exiting non-zero; `gh api user` under a GitHub App token is refused with HTTP 403.
#
# Operator-safe: a fake gh, no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/other-comments.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/other-comments-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT

mkdir -p "$T/bin" "$T/nogit"
cat > "$T/bin/fake-gh" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_GH"
case "$1 $2" in
  "repo view") echo o/r ;;
  "api user")  [ -f "$S/user-fail" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }; echo tester ;;
  api*)        case "$2" in
                 repos/o/r/issues/7/comments) f=issue ;;
                 repos/o/r/pulls/7/comments) f=inline ;;
                 repos/o/r/pulls/7/reviews) f=reviews ;;
                 *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
               esac
               [ -f "$S/$f-fail" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
               cat "$S/$f.json" ;;
  *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/fake-gh"

AT=2026-11-11T12:00:00Z
c() { jq -nc --arg l "$1" --arg t "$2" '{user: (if $l == "" then null else {login: $l} end), created_at: $t, body: "x"}'; }
r() { jq -nc --arg l "$1" --arg t "$2" --arg b "$3" '{user: {login: $l}, body: $b, state: "COMMENTED"} + (if $t == "" then {state: "PENDING"} else {submitted_at: $t} end)'; }
setup() {
  S="$T/$1"; mkdir -p "$S"
  printf '%s\n' "$(c tester 2026-11-11T11:00:00Z)" "$(c alice 2026-11-11T11:59:59Z)" "$(c bob 2026-11-11T12:00:01Z)" "$(c '' 2026-11-11T10:00:00Z)" | jq -sc . > "$S/issue.json"
  printf '%s\n' "$(c 'greptile-apps[bot]' 2026-11-11T11:00:00Z)" "$(c 'second-shift-app[bot]' 2026-11-11T11:00:00Z)" "$(c tester 2026-11-11T11:00:00Z)" | jq -sc . > "$S/inline.json"
  printf '%s\n' "$(c 'greptile-apps[bot]' 2026-11-11T12:00:00Z)" | jq -sc . >> "$S/inline.json"
  printf '%s\n' "$(r 'greptile-apps[bot]' 2026-11-11T11:00:00Z 'summary')" "$(r 'greptile-apps[bot]' 2026-11-11T11:00:00Z '')" \
    "$(r carol '' 'pending text')" "$(r carol 2026-11-11T12:30:00Z 'late')" | jq -sc . > "$S/reviews.json"
}
run() { FAKE_GH="$S" GH="$T/bin/fake-gh" bash "$TOOL" "$@" > "$S/out" 2> "$S/err"; }
got() { jq -Sc . "$S/count.json" 2>/dev/null; }

echo "== other-comments.sh =="

echo '{"tracker":{"bot":{"enabled":false,"app":{"appName":"second-shift-app"}}}}' > "$T/config.json"
setup counts
SECOND_SHIFT_CONFIG="$T/config.json" run -C "$T/nogit" 7 "$AT" "$S/count.json"; rc=$?
[ "$rc" -eq 0 ] && [ "$(got)" = '{"at":"2026-11-11T12:00:00Z","by_author":{"alice":1,"ghost":1,"greptile-apps[bot]":3},"total":5}' ] && [ ! -s "$S/out" ] \
  && ok "(o1) another author's inline comments, review body and issue comment at or before the start count; the gh login, <appName>[bot] (bot disabled), later comments, empty and pending reviews do not" \
  || bad "(o1) rc=$rc got=$(got) err=$(cat "$S/err")"

setup noconfig
run -C "$T/nogit" 7 "$AT" "$S/count.json"; rc=$?
[ "$rc" -eq 0 ] && [ "$(jq -c '[.total, .by_author["second-shift-app[bot]"], .by_author.tester]' "$S/count.json")" = '[6,1,null]' ] \
  && ok "(o2) with no config only the gh login is excluded" || bad "(o2) rc=$rc got=$(got)"

setup local; git init -q "$S/repo"; mkdir -p "$S/repo/.claude"
echo '{"tracker":{"bot":{"enabled":true,"app":{"appName":"committed-app"}}}}' > "$S/repo/.claude/second-shift.config.json"
echo '{"tracker":{"bot":{"app":{"appName":"second-shift-app"}}}}' > "$S/repo/.claude/second-shift.config.local.json"
run -C "$S/repo" 7 "$AT" "$S/count.json"; rc=$?
[ "$rc" -eq 0 ] && [ "$(jq -c '[.total, .by_author["second-shift-app[bot]"]]' "$S/count.json")" = '[5,null]' ] \
  && ok "(o3) the main checkout's local appName overrides the committed one, as bot-commit.sh resolves it" || bad "(o3) rc=$rc got=$(got)"

fails=""
for f in user issue inline reviews malformed; do
  setup "fail-$f"; echo '{"at":"stale","total":0,"by_author":{}}' > "$S/count.json"
  if [ "$f" = malformed ]; then echo '{"message":"Not Found"}' > "$S/inline.json"; else touch "$S/$f-fail"; fi
  SECOND_SHIFT_CONFIG="$T/config.json" run -C "$T/nogit" 7 "$AT" "$S/count.json"; rc=$?
  { [ "$rc" -eq 1 ] && [ ! -e "$S/count.json" ] && [ -s "$S/err" ] && ! compgen -G "$S/count.json.tmp*" >/dev/null; } || fails="$fails $f(rc=$rc)"
done
[ -z "$fails" ] && ok "(o4) a failed login, issue, inline or review read, or a non-list answer: exit 1, named, and no file, an earlier one removed" || bad "(o4)$fails"

setup usage
run 7 "$AT"; rc1=$?; run x "$AT" "$S/c.json"; rc2=$?; run 7 2026-11-11 "$S/c.json"; rc3=$?; run --repo; rc4=$?
[ "$rc1$rc2$rc3$rc4" = 2222 ] && ok "(o5) a missing argument, a non-numeric PR or a start not in ISO-8601 UTC is usage (exit 2)" || bad "(o5) rc=$rc1/$rc2/$rc3/$rc4"

echo "other-comments-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
