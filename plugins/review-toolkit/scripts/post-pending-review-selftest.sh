#!/usr/bin/env bash
# shellcheck disable=SC2016  # expected lines hold literal backticks
# post-pending-review-selftest.sh — behavioral selftest for scripts/post-pending-review.sh.
#
# INVARIANTS GUARDED: one create-review call with no event, commit_id the report's line-2 sha; the body keeps the two
# head lines, every section, the KB block and the machine line, and drops the dev block; @-mentions outside code are
# backticked; a Critical or Warning finding inside a hunk of base...sha is one right-side inline comment; a sha that
# is a PR commit but not the head posts with a moved-on line, one outside the PR posts nothing; an existing pending
# review blocks the post; a failed create is reported once, never through gh-bot.sh; no write besides the create.
# The joined report comes from the real verdict-join.sh, resolved the way review-lead resolves it.
#
# Operator-safe: a fake gh on PATH, a local git fixture, no network. Exit code = number of failed checks.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/post-pending-review.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/post-pending-review-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin"
# The fake answers with the raw shapes the GitHub REST API returns. "List reviews for a pull request" is an array of
# review objects carrying id, state (PENDING for an unsubmitted one, seen only by its author) and user.login; with no
# review it is []. A failed call: gh exits 1 and prints `gh: <message> (HTTP <code>)` on stderr, and "Create a review
# for a pull request" answers 422 Validation Failed. Sources:
# https://docs.github.com/en/rest/pulls/reviews#list-reviews-for-a-pull-request and
# https://docs.github.com/en/rest/pulls/reviews#create-a-review-for-a-pull-request; the same stderr shape is the one
# skills/run/run-verdict-selftest.sh replays for a failed write.
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="$FAKE_GH"
printf '%s\n' "$*" >> "$S/calls"
case "$1 $2" in
  "repo view") echo '{"nameWithOwner":"o/r"}' ;;
  "api user") echo '{"login":"tester","type":"User"}' ;;
  "pr view") jq -n --arg h "$(cat "$S/head")" --arg b "$(cat "$S/base")" '{headRefOid: $h, baseRefOid: $b}' ;;
  "api repos/o/r/pulls/7/commits") jq -R '{sha: .}' "$S/commits" | jq -s . ;;
  "api repos/o/r/pulls/7/reviews") cat "$S/reviews.json" 2>/dev/null || echo '[]' ;;
  "api --method")
    [ "$3 $4" = "POST repos/o/r/pulls/7/reviews" ] || { echo "fake gh: unhandled $*" >&2; exit 1; }
    in=""; while [ $# -gt 0 ]; do [ "$1" = --input ] && in="$2"; shift; done
    if [ -f "$S/create-fail" ]; then echo '{"message":"Validation Failed","status":"422"}'; cat "$S/create-fail" >&2; exit 1; fi
    cp "$in" "$S/payload.json"
    echo '{"id":99,"state":"PENDING","html_url":"https://github.com/o/r/pull/7#pullrequestreview-99"}' ;;
  *) echo "fake gh: unhandled $*" >&2; exit 1 ;;
esac
EOF
printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >> "$FAKE_GH/bot-calls"; exit 0' > "$T/bin/gh-bot.sh"
chmod +x "$T/bin/gh" "$T/bin/gh-bot.sh"

G="$T/repo"
git init -q "$G"; git -C "$G" config user.email selftest@example.invalid; git -C "$G" config user.name selftest
git -C "$G" config commit.gpgsign false
mkdir -p "$G/src"
lines() { seq 1 40 | awk -v p="$1" -v a="$2" -v b="$3" '{ print p $0 ((NR == a || NR == b) ? " changed" : "") }'; }
lines a 0 0 > "$G/src/a.ts"; lines b 0 0 > "$G/src/b.ts"
git -C "$G" add -A; git -C "$G" commit -qm base; BASE="$(git -C "$G" rev-parse HEAD)"
lines a 20 35 > "$G/src/a.ts"; git -C "$G" commit -qam head; H1="$(git -C "$G" rev-parse HEAD)"
lines a 20 36 > "$G/src/a.ts"; git -C "$G" commit -qam later; H2="$(git -C "$G" rev-parse HEAD)"

FENCE='```'
printf '%s\n' 'reviewed-by: second-shift review-lead (v9)' "reviewed: $H1" '## Review Summary' \
  'Ping @jdoe and @acme/platform-team; mail jdoe@example.com; `@not-a-mention` stays.' '' "${FENCE}text" '@fenced stays' "$FENCE" '' \
  '## Strengths' '- tidy' '' '## Critical (must fix before merge)' \
  '- [Security] src/a.ts:20 (confidence: 90) — Token leaks to @jdoe in the log.' '' '## Warnings (should fix)' \
  '- [Performance] src/b.ts:5 (confidence: 85) — slow' '- [Maintainability] naming is unclear (confidence: 85)' \
  '- [Test Coverage] src/a.ts:36 (confidence: 85) — no test for the new branch' '' \
  '## Suggestions (consider)' '- [Complexity] src/a.ts:21 (confidence: 85) — could be simpler' '' \
  '## Verdicts' '| Reviewer | Verdict |' '' '**Ready to merge?** With fixes' '' '**Reasoning:** ok' '' \
  '### Knowledge-base contributions' 'Knowledge-base contributions:' '- kb/auth.md — the token is now scoped (change gap)' > "$T/lead.md"
printf '%s\n' 'verdict: needs-work' '## Findings' '- [blocker] B1 src/a.ts:21 — the same leak' \
  '- [blocker] B2 src/a.ts:35 — off by one' '  Scenario: n = 0 → crash' '- [note] N1 src/d.ts:1 — style' > "$T/plain.md"
PT="$(bash "$HERE/plain-review-tools.sh")" || { echo "post-pending-review-selftest: no dev-pipeline verdict-join.sh to join with"; exit 1; }
bash "$PT/verdict-join.sh" "$T/lead.md" "$T/plain.md" --format report --lane-cost 1.2 --plain-cost 0.3 --lane-wall 100 --plain-wall 40 > "$T/joined.md"
grep -q '^<details><summary>dev: lane vs blind' "$T/joined.md" && grep -q '^- \[blind\] src/a.ts:35' "$T/joined.md" \
  || { echo "post-pending-review-selftest: the join did not produce a dev block and a [blind] blocker"; exit 1; }

# setup <name> <head> <base> <commit>... — one PR state
setup() { S="$T/$1"; mkdir -p "$S"; echo "$2" > "$S/head"; echo "$3" > "$S/base"; shift 3; printf '%s\n' "$@" > "$S/commits"; }
run() {
  local rc
  PATH="$T/bin:$PATH" FAKE_GH="$S" bash "$TOOL" --repo o/r --worktree "$G" 7 "$@" > "$S/out" 2> "$S/err"; rc=$?
  [ ! -f "$S/payload.json" ] || jq -r .body "$S/payload.json" > "$S/body.txt"
  return "$rc"
}
creates() { grep -c '^api --method POST repos/o/r/pulls/7/reviews ' "$S/calls" 2>/dev/null; }
body() { cat "$S/body.txt"; }

echo "== post-pending-review.sh =="

setup head "$H1" "$BASE" "$H1"; run "$T/joined.md"; rc=$?
[ "$rc" -eq 0 ] && [ "$(creates)" = 1 ] && jq -e --arg s "$H1" '(has("event") | not) and .commit_id == $s' "$S/payload.json" >/dev/null \
  && ok "(p1) a report on the PR head makes one create-review call, with no event and the reviewed sha as commit_id" \
  || bad "(p1) rc=$rc creates=$(creates) err=$(cat "$S/err") payload=$(cat "$S/payload.json" 2>/dev/null)"
[ "$(body | sed -n 1p)" = 'reviewed-by: second-shift review-lead (v9)' ] && [ "$(body | sed -n 2p)" = "reviewed: $H1" ] \
  && [ "$(jq -r .commit_id "$S/payload.json")" = "$(body | sed -n '2s/^reviewed: //p')" ] \
  && ok "(p2) the body's lines 1 and 2 are the report's head lines, and commit_id is line 2's sha" || bad "(p2) $(body | sed -n 1,2p)"
[ "$(body | grep -E '^##+ ')" = "$(grep -E '^##+ ' "$T/joined.md")" ] \
  && grep -qxF -- '- kb/auth.md — the token is now scoped (change gap)' "$S/body.txt" \
  && [ "$(body | grep '^<!-- plain-vs-lane: ')" = "$(grep '^<!-- plain-vs-lane: ' "$T/joined.md")" ] \
  && [ "$(body | tail -1)" = "$(grep '^<!-- plain-vs-lane: ' "$T/joined.md")" ] \
  && ! grep -qE 'dev: lane vs blind|Lane session:|Blind session:|blind review, as written|<details|\[note\] N1' "$S/body.txt" \
  && ok "(p3) the body keeps every section, the KB block and the machine line, and drops the dev block, cost line and blind draft" \
  || bad "(p3) $(body)"
grep -qxF 'Ping `@jdoe` and `@acme/platform-team`; mail jdoe@example.com; `@not-a-mention` stays.' "$S/body.txt" \
  && grep -qxF '@fenced stays' "$S/body.txt" \
  && jq -e '.comments[] | select(.line == 20) | .body == "[Security] Token leaks to `@jdoe` in the log."' "$S/payload.json" >/dev/null \
  && ok "(p4) a bare @handle and @org/team are backticked in the body and an inline comment; an email and an @ in code are not" \
  || bad "(p4) $(body | sed -n 3,8p) comments=$(jq -c .comments "$S/payload.json")"
jq -e '[.comments[] | [.path, .line, .side]] == [["src/a.ts", 20, "RIGHT"], ["src/a.ts", 35, "RIGHT"], ["src/a.ts", 36, "RIGHT"]]' "$S/payload.json" >/dev/null \
  && jq -e '.comments[1].body == "[Blind review] off by one\nScenario: n = 0 → crash" and .comments[2].body == "[Test Coverage] no test for the new branch"' "$S/payload.json" >/dev/null \
  && grep -qxF 'inline comments: 3; findings in the body only: 2' "$S/out" \
  && ok "(p5) each in-hunk Critical or Warning is one right-side inline comment at its first site; an out-of-hunk or siteless one and a Suggestion stay in the body" \
  || bad "(p5) comments=$(jq -c .comments "$S/payload.json") out=$(cat "$S/out")"

setup moved "$H2" "$BASE" "$H1" "$H2"; run "$T/joined.md"; rc=$?
[ "$rc" -eq 0 ] && [ "$(creates)" = 1 ] && [ "$(jq -r .commit_id "$S/payload.json")" = "$H1" ] \
  && grep -qxF "the PR has moved on: its head is now $H2, and this review sits on $H1" "$S/out" \
  && ok "(p6) a sha that is a PR commit but not the head posts, and says the PR has moved on" || bad "(p6) rc=$rc out=$(cat "$S/out") err=$(cat "$S/err")"
setup offpr "$H2" "$BASE" "$H2"; run "$T/joined.md"; rc=$?
[ "$rc" -ne 0 ] && [ "$(creates)" = 0 ] && grep -qF "the reviewed commit $H1 is not one of PR #7's commits" "$S/err" \
  && ok "(p7) a sha outside the PR's commits creates nothing, exits non-zero and says why" || bad "(p7) rc=$rc err=$(cat "$S/err")"

setup pending "$H1" "$BASE" "$H1"
printf '%s' '[{"id":54,"state":"COMMENTED","user":{"login":"tester"}},{"id":55,"state":"PENDING","user":{"login":"tester"},"html_url":"https://github.com/o/r/pull/7#pullrequestreview-55"}]' > "$S/reviews.json"
run "$T/joined.md"; rc=$?
[ "$rc" -ne 0 ] && ! grep -qE -- '--method|-X ' "$S/calls" && grep -qF 'pending review on PR #7: 55 ' "$S/err" \
  && ok "(p8) an existing pending review of the caller's: nothing created or deleted, a non-zero exit, and its id named" \
  || bad "(p8) rc=$rc calls=$(cat "$S/calls") err=$(cat "$S/err")"

setup fail "$H1" "$BASE" "$H1"; echo 'gh: Validation Failed (HTTP 422)' > "$S/create-fail"
GH="$T/bin/gh-bot.sh" run "$T/joined.md"; rc=$?
[ "$rc" -ne 0 ] && [ "$(creates)" = 1 ] && grep -qF 'gh: Validation Failed (HTTP 422)' "$S/err" && [ ! -e "$S/bot-calls" ] \
  && ok "(p9) a failed create prints gh's error, exits non-zero, is not retried and never goes through gh-bot.sh" \
  || bad "(p9) rc=$rc creates=$(creates) err=$(cat "$S/err") bot=$(cat "$S/bot-calls" 2>/dev/null)"

setup nojoin "$H1" "$BASE" "$H1"; run "$T/lead.md"; rc=$?
[ "$rc" -eq 0 ] && [ "$(creates)" = 1 ] && [ "$(body | sed -n 1p)" = 'reviewed-by: second-shift review-lead (v9)' ] \
  && [ "$(body | sed -n 2p)" = "reviewed: $H1" ] && ! grep -q 'plain-vs-lane' "$S/body.txt" && [ "$(jq -r .commit_id "$S/payload.json")" = "$H1" ] \
  && ok "(p10) a report with no machine line is posted the same way, with both head lines" || bad "(p10) rc=$rc err=$(cat "$S/err")"

setup nobase "$H1" 1111111111111111111111111111111111111111 "$H1"; run "$T/joined.md"; rc=$?
[ "$rc" -eq 0 ] && [ "$(creates)" = 1 ] && jq -e 'has("comments") | not' "$S/payload.json" >/dev/null \
  && grep -qxF "no inline comments: the PR's base commit 1111111111111111111111111111111111111111 could not be fetched" "$S/out" \
  && ok "(p11) a base commit that cannot be fetched posts the review with no inline comments and says why" || bad "(p11) rc=$rc out=$(cat "$S/out") err=$(cat "$S/err")"

setup badreport "$H1" "$BASE" "$H1"; sed 2d "$T/lead.md" > "$S/report.md"; run "$S/report.md"; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$S/calls" ] && ok "(p12) a report with no reviewed line on line 2 is refused before any gh call" || bad "(p12) rc=$rc"

allowed='^(repo view --json nameWithOwner|api user|pr view 7 --repo o/r --json headRefOid,baseRefOid|api repos/o/r/pulls/7/(commits|reviews) --paginate|api --method POST repos/o/r/pulls/7/reviews --input [^ ]+)$'
other="$(cat "$T"/*/calls | grep -vE "$allowed")"
[ -z "$other" ] && [ -s "$T/head/calls" ] && ! grep -q statuses "$T"/*/calls \
  && ok "(p13) across every case gh saw no statuses call and no write besides the one review create" || bad "(p13) other calls: $other"

echo "post-pending-review-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
