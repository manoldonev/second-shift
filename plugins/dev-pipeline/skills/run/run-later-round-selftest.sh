#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-later-round-selftest.sh — run.sh scenario slice: a later review. Once the PR has a lane verdict, each review gets
# that verdict's reviewed sha and the lines changed since, in its prompt and in the join; the first review gets neither.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-later-round-selftest] a later review gates only what changed since the last reviewed head"

posted() { awk -v k="$1" '$0 == "<!-- end of comment -->" { c++; next } c == k - 1' "$FAKE_GH/pr-comment-bodies" 2>/dev/null; }   # the k-th body the scheduler posted
devjson() { posted "$1" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p'; }   # the join's machine-readable line
above() { posted "$1" | sed '/^lane vs blind: /,$d'; }   # the k-th body without the join's lines
reviewed() { posted "$1" | sed -n '2s/^reviewed: //p'; }

# (lr1) round 1 is a full review. Round 2's build rewrites src/a.ts, so plain's findings there are on changed lines and
# gate. Round 3's build touches work.txt alone, so plain's blocker in src/other.ts is on an unchanged line and does not
fixture lr1; printf 'build-pr\nreview-needs-work-mixed\nbuild-push-only\nreview-approve\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
export FAKE_PLAIN_PLAN="$d/plain-plan"; printf 'plain-approve\nplain-blocker-agree\nplain-blocker-new\n' > "$FAKE_PLAIN_PLAN"
mkdir -p "$FAKE_GH/tree-3/src"; printf 'a1\na2\na3\na4\na5\na6\n' > "$FAKE_GH/tree-3/src/a.ts"
run_case "$d"; expect approved "(lr1) needs-work, needs-work on changed lines, then approve"
[ "$CASE_ON" -eq 1 ] || { echo "[self-test] $PASS passed, $FAIL failed"; exit 0; }

! grep -q '^## A later review$' "$FAKE_GH/prompt-2.txt" && [ ! -e "$(SD)/changed-lines-1.1.txt" ] \
  && jq -e '.plain_unchanged_dropped == null' <<<"$(devjson 1)" >/dev/null && grep -q 'review: a full review — PR #7 has no earlier lane verdict' <<<"$OUT" \
  && ok "(lr1) the first review is a full review: no later-review section, no changed-line set, no count in the machine line" \
  || bad "(lr1) round 1: later section=$(grep -c '^## A later review$' "$FAKE_GH/prompt-2.txt") dev=$(devjson 1)"

s1="$(reviewed 1)"; s2="$(reviewed 2)"
setof() { grep -o 'changed-lines-[0-9.]*\.txt, one path' "$FAKE_GH/prompt-$1.txt" | sed 's/, one path$//'; }   # the set the k-th prompt names, in the run's state dir
lead="$(grep '^This PR already has a lane verdict\.' "$FAKE_GH/prompt-4.txt")"; set2="$(SD)/$(setof 4)"; set3="$(SD)/$(setof 6)"
[[ "$lead" == "This PR already has a lane verdict. The latest one reviewed $s1. The lines changed since then are listed in "*"-scratch."*"/changed-lines-"*".txt, one path:first-last range per line: each line of the head within 3 lines of a hunk of 'git -C "*" diff $s1 HEAD'. An empty list means that nothing changed." ]] \
  && grep -q '^In a later review, read the PR.s earlier lane verdicts last' "$FAKE_GH/prompt-4.txt" \
  && [ -n "$s1" ] && grep -qx 'src/a.ts:1-9' "$set2" && grep -qx 'work.txt:1-5' "$set2" && [ "$(grep -c . "$set2")" -eq 2 ] \
  && ok "(lr1) round 2's review is told the sha round 1 reviewed and where the lines changed since are; the set covers the rewritten src/a.ts" \
  || bad "(lr1) round 2: s1=$s1 prompt=$(sed -n '/^## A later review$/,+1p' "$FAKE_GH/prompt-4.txt" | tr '\n' '|') set=$(tr '\n' ' ' < "$set2" 2>/dev/null)"

[ "$(posted 2 | head -n 1)" = 'verdict: needs-work' ] && above 2 | grep -qx -- '- \[blocker\] B1 \[blind\] src/a.ts:4 — the defect the lane saw' \
  && above 2 | grep -qx -- '- \[note\] N1 \[blind\] src/a.ts:9 — a plain note' \
  && jq -e '.plain_unchanged_dropped == 0 and .plain_only == 2 and .flipped == true' <<<"$(devjson 2)" >/dev/null \
  && ok "(lr1) round 2's join gets the set: plain's blocker and note on changed lines are added and flip the approve" || bad "(lr1) round 2 verdict: $(above 2 | grep '^- ' | tr '\n' '|') dev=$(devjson 2)"

grep -q "The latest one reviewed $s2\. " "$FAKE_GH/prompt-6.txt" && [ -n "$s2" ] && [ "$s2" != "$s1" ] \
  && [ "$(cat "$set3")" = 'work.txt:1-6' ] \
  && ok "(lr1) round 3 narrows against round 2's reviewed sha, the latest verdict, and only work.txt changed since" \
  || bad "(lr1) round 3: s2=$s2 named=$(grep -o 'The latest one reviewed [0-9a-f]*' "$FAKE_GH/prompt-6.txt") set=$(tr '\n' ' ' < "$set3" 2>/dev/null)"

[ "$(posted 3 | head -n 1)" = 'verdict: approve' ] && ! above 3 | grep -q 'src/other.ts\|\[blind\]' \
  && jq -e '.plain_unchanged_dropped == 1 and .plain_only == 0 and .flipped == false and .plain_blockers == 1' <<<"$(devjson 3)" >/dev/null \
  && [ "$(tail -n 1 "$FAKE_GH/statuses" | grep -c 'state=success')" -eq 1 ] \
  && ok "(lr1) round 3's join leaves out plain's blocker on an unchanged line and counts it; the approve binds with a success status" \
  || bad "(lr1) round 3 verdict: $(above 3 | tr '\n' '|' | cut -c1-400) dev=$(devjson 3)"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
