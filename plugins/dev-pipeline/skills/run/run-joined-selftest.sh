#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-joined-selftest.sh — run.sh scenario slice: the joined review, on by default. A record-blind plain review runs
# beside the lane review; the scheduler joins the two drafts and posts one verdict; run.joinedReview false turns it off.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"
unset RUN_JOINED_REVIEW

echo "[run-joined-selftest] the joined review: plain beside the lane, one verdict posted by the scheduler"

posted() { awk -v k="$1" '$0 == "<!-- end of comment -->" { c++; next } c == k - 1' "$FAKE_GH/pr-comment-bodies" 2>/dev/null; }   # the k-th body the scheduler posted
devjson() { posted "$1" | sed -n 's/^<!-- plain-vs-lane: \(.*\) -->$/\1/p'; }   # the dev block's machine-readable line
devblock_last() { posted "$1" | awk '/^<details><summary>dev: lane vs plain<\/summary>$/ { on = 1 } on { last = $0 } END { exit !(on && last == "</details>") }'; }
OFFCFG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"joinedReview":false}}'

# (j1) the default: no config key, no env. Both sessions run in parallel; the plain one cannot reach the record
fixture j1; printf 'build-pr\nreview-approve-seeplain\n' > "$FAKE_CLAUDE_PLAN"; export FAKE_PLAIN_PLAN="$d/plain-plan"; printf 'plain-slow\n' > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(j1) the default review is joined"
[ "$(cat "$FAKE_GH/plain-calls" 2>/dev/null)" = 1 ] && [ -f "$FAKE_GH/saw-plain-running" ] \
  && ok "(j1) one plain session, running while the lane review ran" || bad "(j1) plain calls=$(cat "$FAKE_GH/plain-calls" 2>/dev/null) saw-running=$([ -f "$FAKE_GH/saw-plain-running" ] && echo yes || echo no)"
pa="$FAKE_GH/plain-args-1.txt"; tree="$(cat "$FAKE_GH/plain-cwd-1.txt")"
grep -qx 'Read,Grep,Glob' "$pa" && grep -qx -- --strict-mcp-config "$pa" \
  && [ "$(grep -cx -- --add-dir "$pa")" -eq 2 ] && grep -qxF "$tree" "$pa" && grep -qx "${tree%/tree}/scratch" "$pa" \
  && ok "(j1) the plain session is allowed Read, Grep and Glob only, with no MCP server, and is given its tree and scratch alone" || bad "(j1) plain args: $(tr '\n' ' ' < "$pa")"
dis="$(awk 'p { print; exit } $0 == "--disallowedTools" { p = 1 }' "$pa")"
main_p="$(cd "$d/main" && pwd -P)"; wt_p="$(cd "$d" && pwd -P)/wt/42"
[[ ",$dis," == *",Agent,"* && ",$dis," == *",Bash,"* && ",$dis," == *",Write,"* && "$dis" == *"Read(/$main_p/**)"* && "$dis" == *"Read(/$wt_p/**)"* && "$dis" == *"-scratch."*"/**)"* ]] \
  && ok "(j1) it is denied Agent, Bash, Write, and reads of the main checkout, the lane worktree and the lane scratch" || bad "(j1) deny list: $dis"
[ "$(grep -c . "$FAKE_GH/plain-dirs-1.txt")" -eq 3 ] && [ ! -s "$FAKE_GH/plain-reach-1.txt" ] \
  && ok "(j1) no record row, decisions file or .git is reachable from the plain session's cwd and dirs" || bad "(j1) reachable: $(tr '\n' ' ' < "$FAKE_GH/plain-reach-1.txt")"
pp="$FAKE_GH/plain-prompt-1.txt"
grep -q '^# a change$' "$pp" && grep -q 'Do the thing in src/a.ts' "$pp" && ! grep -q 'docs/plans' "$pp" && grep -q '^+1$' "$pp" \
  && ! grep -q '{out}\|{ticket}\|{diff}\|Adapted from\|^---$' "$pp" && grep -qF "saved to \`${tree%/tree}/scratch/verdict.md\`" "$pp" \
  && ok "(j1) its prompt is plain-review.md below its header: the ticket less the line linking the record, the diff without the plans dir, and its draft path" || bad "(j1) plain prompt: $(head -c 600 "$pp" | tr '\n' '|')"
! grep -qF 'Bash(gh pr comment' "$FAKE_GH/args-2.txt" && grep -q '^Write your verdict to .*/verdict-draft-1.1.md with the Write tool. Do not post it' "$FAKE_GH/prompt-2.txt" \
  && ok "(j1) the lane review may not comment and is told to write its draft" || bad "(j1) lane allowlist/prompt: $(grep -o 'Bash(gh pr comment[^,]*' "$FAKE_GH/args-2.txt")"
[ "$(grep -c '^verdict: ' "$FAKE_GH/pr-comment-bodies" 2>/dev/null)" -eq 1 ] && [ "$(jq length "$FAKE_GH/comments.json")" -eq 1 ] && grep -q 'state=success' "$FAKE_GH/statuses" \
  && ok "(j1) the scheduler posts one joined verdict, binds it and posts success" || bad "(j1) posted: $(tr '\n' '|' < "$FAKE_GH/pr-comment-bodies" 2>/dev/null)"
devblock_last 1 && jq -e '.lane_blockers == 0 and .plain_blockers == 0 and .agreed == 0 and .flipped == false and .plain_returned == true
    and .lane_cost_usd == 1 and .plain_cost_usd == 0.5 and (.lane_wall_s | type) == "number" and .plain_wall_s >= 2' <<<"$(devjson 1)" >/dev/null \
  && posted 1 | grep -qx 'Verdict: the lane alone said approve; the joined verdict is approve.' && posted 1 | grep -q 'Plain session: [$]0.50, [0-9]* s, returned\.$' \
  && ok "(j1) [AC-10] the verdict ends with the folded dev block: no-flip counts, both sessions' cost and wall time, and its JSON line" || bad "(j1) dev block: $(devjson 1) $(posted 1 | tail -n 9 | tr '\n' '|')"
grep -q '^cost_usd: 2.50$' "$FAKE_GH/issue-comments" && ok "(j1) the run's cost counts the plain session" || bad "(j1) cost: $(grep -o 'cost_usd: [0-9.]*' "$FAKE_GH/issue-comments")"

# (j2) a blocker only plain raised turns the lane's approve into a needs-work, which the next build reads
fixture j2; printf 'build-pr\nreview-approve-summary\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'plain-blocker-new\nplain-approve\n' > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(j2) needs-work from a plain-only blocker, then approve"
posted 1 > "$d/v1.md"
head -n 1 "$d/v1.md" | grep -qx 'verdict: needs-work' && grep -qx 'Not mergeable yet.' "$d/v1.md" && ! grep -q 'Mergeable as it is.\|^Nothing to do.$\|^None.$' "$d/v1.md" \
  && grep -qx -- '- \[blocker\] B1 \[plain\] src/other.ts:20 — a defect only plain saw' "$d/v1.md" && grep -qx '  Scenario: an empty list → a crash' "$d/v1.md" \
  && ok "(j2) line 1 and the Summary's first line are rewritten; the blocker is added as [plain] with its scenario" || bad "(j2) first verdict: $(tr '\n' '|' < "$d/v1.md")"
grep -q 'state=failure' "$FAKE_GH/statuses" && grep -q '\[plain\] src/other.ts:20' "$FAKE_GH/prompt-3.txt" \
  && ok "(j2) the needs-work posts failure and the next build gets the [plain] finding" || bad "(j2) statuses=$(tr '\n' '|' < "$FAKE_GH/statuses") prompt-3 has it: $(grep -c 'other.ts' "$FAKE_GH/prompt-3.txt")"
devblock_last 1 && jq -e '.plain_only == 1 and .lane_only == 0 and .flipped == true and .plain_returned == true' <<<"$(devjson 1)" >/dev/null \
  && grep -qx -- '- Plain-only: B1 (plain B1) src/other.ts:20' "$d/v1.md" \
  && grep -qx 'Verdict: the lane alone said approve; the joined verdict is needs-work (plain flipped approve → needs-work).' "$d/v1.md" \
  && ok "(j2) [AC-10] the dev block names the plain-only blocker and the flip" || bad "(j2) dev block: $(devjson 1)"

# (j3) a blocker both raised at the same site is one finding, tagged [lane+plain]; plain's notes are dropped
fixture j3; printf 'build-pr\nreview-needs-work-mixed\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'plain-blocker-agree\nplain-approve\n' > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(j3) an agreed blocker, then approve"
posted 1 > "$d/v1.md"
grep -qx -- '- \[blocker\] B1 \[lane+plain\] src/a.ts:3 — mixed blocker' "$d/v1.md" && [ "$(grep -c '^- \[blocker\]' "$d/v1.md")" -eq 1 ] \
  && grep -qx -- '- \[note\] N1 src/a.ts:9 — mixed note' "$d/v1.md" && ! grep -q 'a plain note\|^- .*\[plain\]' "$d/v1.md" \
  && ok "(j3) one blocker tagged [lane+plain], the lane's note kept, plain's note dropped" || bad "(j3) first verdict: $(tr '\n' '|' < "$d/v1.md")"
jq -e '.lane_blockers == 1 and .plain_blockers == 1 and .agreed == 1 and .lane_only == 0 and .plain_only == 0 and .plain_notes_dropped == 1 and .flipped == false' <<<"$(devjson 1)" >/dev/null \
  && grep -qx -- '- Agreed: B1 ↔ plain B1' "$d/v1.md" && grep -qx -- '- Plain-only: none' "$d/v1.md" \
  && ok "(j3) [AC-10] the dev block pairs the agreed ids and counts the dropped note" || bad "(j3) dev block: $(devjson 1)"

# (j4) a plain review that returns no verdict, or crashes: the lane's verdict is posted alone, with a Notes line
for p in silent crash; do
  fixture "j4-$p"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'plain-%s\n' "$p" > "$FAKE_PLAIN_PLAN"
  run_case "$d"; expect approved "(j4) plain-$p"
  posted 1 | grep -qx 'Joined review: the plain review returned no verdict, so this verdict is the lane review alone.' && grep -q '^cost_usd: 2.50$' "$FAKE_GH/issue-comments" \
    && ok "(j4) plain-$p: the lane's verdict is posted with a Notes line saying plain did not return; its cost still counts" || bad "(j4) plain-$p: $(posted 1 | tr '\n' '|')"
  devblock_last 1 && jq -e '.plain_returned == false and .plain_blockers == 0 and .flipped == false and .plain_cost_usd == 0.5' <<<"$(devjson 1)" >/dev/null \
    && posted 1 | grep -q 'Plain session: [$]0.50, [0-9]* s, did not return (the plain review returned no verdict)\.$' \
    && ok "(j4) [AC-10] plain-$p: the dev block says plain did not return" || bad "(j4) plain-$p dev block: $(devjson 1)"
done
fixture j4-ticket; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_PLAIN_PLAN"; touch "$FAKE_GH/issue-unreadable"
run_case "$d"; expect approved "(j4) the ticket cannot be read for the plain review"
[ ! -f "$FAKE_GH/plain-calls" ] && posted 1 | grep -qx 'Joined review: the ticket could not be read for the plain review, so this verdict is the lane review alone.' \
  && ok "(j4) no plain session is spawned, and the verdict says why" || bad "(j4) ticket: plain-calls=$(cat "$FAKE_GH/plain-calls" 2>/dev/null) $(posted 1 | tail -n 2 | tr '\n' '|')"

# (j5) a lane review that leaves no draft is a miss: both sessions re-spawn once, then the run ends review-unbound
fixture j5; printf 'build-pr\nreview-silent\nreview-silent\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect review-unbound "(j5) the lane review wrote no draft, twice"
[ "$(cat "$FAKE_GH/plain-calls" 2>/dev/null)" = 2 ] && ! grep -q '^verdict: ' "$FAKE_GH/pr-comment-bodies" 2>/dev/null && grep -q 'wrote no verdict draft' <<<"$OUT" \
  && ok "(j5) the plain review re-spawned with it; nothing was posted" || bad "(j5) plain-calls=$(cat "$FAKE_GH/plain-calls" 2>/dev/null)"

# (j6) a joined verdict that breaks the grammar is never posted; the re-spawn is told which rule broke
fixture j6; printf 'build-pr\nreview-bad-approve-blocker\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(j6) a rejected joined verdict, then a consistent one"
[ "$(grep -c '^verdict: ' "$FAKE_GH/pr-comment-bodies")" -eq 1 ] && grep -qF -- '- approve with a blocker' "$FAKE_GH/prompt-3.txt" && [ "$(wc -l < "$FAKE_GH/statuses")" -eq 1 ] \
  && ok "(j6) only the verdict that passes the check is posted, and the re-spawn names the rule" || bad "(j6) posted $(grep -c '^verdict: ' "$FAKE_GH/pr-comment-bodies") verdicts"

# (j7) switched off: the review is the lane review alone, as before the joined review
FIXTURE_CONFIG="$OFFCFG" fixture j7; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(j7) run.joinedReview false"
[ ! -f "$FAKE_GH/plain-calls" ] && grep -qF 'Bash(gh pr comment*)' "$FAKE_GH/args-2.txt" && grep -q '^Post ONE PR comment' "$FAKE_GH/prompt-2.txt" \
  && ! grep -q '^verdict: ' "$FAKE_GH/pr-comment-bodies" 2>/dev/null && [ "$(jq length "$FAKE_GH/comments.json")" -eq 1 ] \
  && ! jq -e '.[0].body | contains("dev: lane vs plain")' "$FAKE_GH/comments.json" >/dev/null \
  && ok "(j7) no plain session and no dev block; the lane review posts its own verdict" || bad "(j7) plain-calls=$(cat "$FAKE_GH/plain-calls" 2>/dev/null)"

# (j8) jira: the scheduler reads no Jira ticket, so an explicit true refuses before anything is spawned
FIXTURE_CONFIG='{"tracker":{"type":"jira","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"joinedReview":true}}' fixture j8
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-config-run "(j8) run.joinedReview true under jira"
[ ! -f "$FAKE_GH/calls" ] && ok "(j8) nothing spawned" || bad "(j8) calls=$(cat "$FAKE_GH/calls")"
fixture j9; RUN_JOINED_REVIEW=maybe run_case "$d"; expect env-config-run "(j9) a switch that is not true or false"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
