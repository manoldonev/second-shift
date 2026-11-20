#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-pass1-selftest.sh — run.sh scenario slice: the review round's pass 1. A blind session, beside the plain one, in a
# copy of the head the record cannot be reached from; the review session starts only on its findings, which its prompt
# carries. The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-pass1-selftest] pass 1: a blind session before the review session"

arg_after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' "$1"; }   # arg_after <args file> <flag>

# (p1) a round with no run.joinedReview and no RUN_JOINED_REVIEW: pass 1 and the plain session run, both blind; the PR
# commits the Claude config the copy must leave out
fixture p1; printf 'build-pr-claude-files\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
export FAKE_PASS1_PLAN="$d/pass1-plan" FAKE_PLAIN_PLAN="$d/plain-plan"; printf 'pass1-blocker\n' > "$FAKE_PASS1_PLAN"; : > "$FAKE_PLAIN_PLAN"
mkdir -p "$d/cfg/projects"; unset RUN_JOINED_REVIEW
CLAUDE_CONFIG_DIR="$d/cfg" run_case "$d"; expect approved "(p1) a round whose pass 1 raised a blocker the fake review then approved"
[ "$(cat "$FAKE_GH/pass1-calls" 2>/dev/null)" = 1 ] && [ "$(cat "$FAKE_GH/plain-calls" 2>/dev/null)" = 1 ] \
  && ok "(p1) one pass-1 session and one plain session in the round, with no switch set" || bad "(p1) pass1-calls=$(cat "$FAKE_GH/pass1-calls" 2>/dev/null) plain-calls=$(cat "$FAKE_GH/plain-calls" 2>/dev/null)"
pt="$FAKE_GH/pass1-tree-1.txt"
git -C "$d/origin.git" cat-file -e second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null && git -C "$d/origin.git" cat-file -e second-shift/42:.claude/settings.json 2>/dev/null \
  && grep -qx './work.txt' "$pt" && ! grep -qE '^\./(\.git|docs/plans|\.claude|\.mcp\.json|CLAUDE\.local\.md)(/|$)' "$pt" && [ ! -s "$FAKE_GH/pass1-reach-1.txt" ] \
  && ok "(p1) the head carries the record and .claude/; the pass-1 copy has no .git, no plans dir, no .claude/, and no dir it is given reaches the record" \
  || bad "(p1) tree: $(tr '\n' ' ' < "$pt" 2>/dev/null) reach: $(tr '\n' ' ' < "$FAKE_GH/pass1-reach-1.txt" 2>/dev/null)"
pa="$FAKE_GH/pass1-args-1.txt"; dis="$(arg_after "$pa" --disallowedTools)"
main_p="$(cd "$d/main" && pwd -P)"; wt_p="$(cd "$d" && pwd -P)/wt/42"; cfg_p="$(cd "$d/cfg/projects" && pwd -P)"
[[ ",$dis," == *",Bash,"* && ",$dis," == *",Agent,"* && ",$dis," == *",Write,"* && ",$dis," == *",WebFetch,"* \
   && "$dis" == *"Read(/$main_p/**)"* && "$dis" == *"Read(/$wt_p/**)"* && "$dis" == *"-scratch."*"/**)"* && "$dis" == *"Read(/$cfg_p/**)"* ]] \
  && [ "$(arg_after "$pa" --allowedTools)" = 'Read,Grep,Glob' ] && [ "$(cat "$FAKE_GH/pass1-cwd-1.txt")" != "$wt_p" ] \
  && ok "(p1) its flags deny Bash, Agent, Write, WebFetch and reads of the lane worktree, the main checkout, the lane scratch and the transcripts" \
  || bad "(p1) allow=$(arg_after "$pa" --allowedTools) deny=$dis"
pp="$FAKE_GH/pass1-prompt-1.txt"
grep -q '^Review the diff for completeness\.' "$pp" && grep -q '^Review the diff for correctness\.' "$pp" && grep -q '^End with the notes pass\.' "$pp" \
  && grep -q '^# a change$' "$pp" && grep -q 'Do the thing in src/a.ts' "$pp" && grep -q '^+1$' "$pp" \
  && ! grep -q 'docs/plans\|decisions\.md\|plan\.md\|PR description\|LOCKSTEP-\|{diff}\|{ticket}\|^---$' "$pp" \
  && ok "(p1) the pass-1 prompt carries its rules, the stripped ticket and the diff without the plans dir, and names no record path and no PR description" \
  || bad "(p1) pass-1 prompt: $(head -c 600 "$pp" | tr '\n' '|')"
rp="$FAKE_GH/prompt-2.txt"
[ "$(cat "$FAKE_GH/pass1-seen-2.txt" 2>/dev/null)" = 1 ] && grep -qx '<pass-1>' "$rp" && grep -qF -- '- [blocker] B1 src/a.ts:2 — the pass-1 defect' "$rp" \
  && ! grep -q '^## Pass 1: the ticket and the code\|^Review the diff for completeness\.\|^Review the diff for correctness\.' "$rp" \
  && first="$(git -C "$d/origin.git" log --format=%H --diff-filter=A second-shift/42 -- docs/plans/main-42-decisions.md | tail -n 1)" \
  && grep -qF "First read it as it stood at commit $first (git show $first:docs/plans/main-42-decisions.md)" "$rp" && grep -qF 'Then read it as it stands at the head.' "$rp" \
  && ok "(p1) the review session starts after pass 1 returned; its prompt carries the pass-1 findings, no pass-1 review section, and the record at its first commit and at the head" \
  || bad "(p1) pass-1 seen=$(cat "$FAKE_GH/pass1-seen-2.txt" 2>/dev/null) review prompt: $(sed -n '/Pass 1/,/Pass 2/p' "$rp" | head -n 12 | tr '\n' '|')"
grep -q '^cost_usd: 2.75$' "$FAKE_GH/issue-comments" \
  && ok "(p1) the run's cost counts pass 1 with the build, the plain session and the review session" || bad "(p1) cost: $(grep -o 'cost_usd: [0-9.]*' "$FAKE_GH/issue-comments")"

# (p2) a second round: pass 1 reads no earlier verdict, and a None. pass 1 is a valid one that starts the review session
fixture p2; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_PASS1_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(p2) needs-work, then approve, each on a None. pass 1"
pp="$FAKE_GH/pass1-prompt-2.txt"
[ "$(cat "$FAKE_GH/pass1-calls" 2>/dev/null)" = 2 ] && grep -qF 'fake finding' "$FAKE_GH/pr-comment-bodies" && [ -s "$pp" ] \
  && ! grep -q 'fake finding\|^reviewed: \|^## Decision record rows' "$pp" \
  && ok "(p2) the round-2 pass-1 prompt carries no text of the round-1 verdict" || bad "(p2) pass1-calls=$(cat "$FAKE_GH/pass1-calls" 2>/dev/null) prompt: $(grep -n 'fake finding\|^reviewed:\|^## Decision' "$pp" | head -n 3)"
grep -qx 'None.' <(sed -n '/^<pass-1>$/,/^<\/pass-1>$/p' "$FAKE_GH/prompt-2.txt") && [ "$(cat "$FAKE_GH/calls")" = 4 ] \
  && ok "(p2) a pass 1 whose findings are None. starts the review session" || bad "(p2) calls=$(cat "$FAKE_GH/calls")"

# (p3) a pass 1 with no findings block is a review miss: no review session, one retry of the whole attempt, no round spent
fixture p3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'pass1-no-findings\npass1-none\n' > "$FAKE_PASS1_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect approved "(p3) a pass 1 with no findings block, then one with None."
[ "$(cat "$FAKE_GH/calls")" = 2 ] && [ "$(cat "$FAKE_GH/pass1-calls")" = 2 ] && [ "$(cat "$FAKE_GH/plain-calls")" = 2 ] \
  && grep -q 'pass 1 returned no findings block — re-spawning REVIEW (1 of 1)' <<<"$OUT" && ! grep -q 'round 2 of' <<<"$OUT" \
  && grep -q '^cost_usd: 3.50$' "$FAKE_GH/issue-comments" \
  && ok "(p3) no review session on the first attempt; pass 1 and plain run again, the discarded plain is priced, and no round is spent" \
  || bad "(p3) calls=$(cat "$FAKE_GH/calls") pass1=$(cat "$FAKE_GH/pass1-calls") plain=$(cat "$FAKE_GH/plain-calls") cost=$(grep -o 'cost_usd: [0-9.]*' "$FAKE_GH/issue-comments")"

# (p4) twice no verdict from pass 1: the run ends review-unbound and no review session ever started
fixture p4; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; printf 'pass1-silent\npass1-silent\n' > "$FAKE_PASS1_PLAN"; : > "$FAKE_PLAIN_PLAN"
run_case "$d"; expect review-unbound "(p4) pass 1 returned no verdict, twice"
[ "$(cat "$FAKE_GH/calls")" = 1 ] && grep -q 'pass 1 returned no verdict. This happened twice' <<<"$OUT" && ! grep -q '^verdict: ' "$FAKE_GH/pr-comment-bodies" 2>/dev/null \
  && ok "(p4) the build was the only lane session, and nothing was posted" || bad "(p4) calls=$(cat "$FAKE_GH/calls") $(grep 'pass 1' <<<"$OUT" | tail -n 2)"

# (p5) pass 1 runs under the review time limit: past it, it is stopped, and the attempt is a review miss
fixture p5; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'pass1-slow\npass1-none\n' > "$FAKE_PASS1_PLAN"; : > "$FAKE_PLAIN_PLAN"
RUN_REVIEW_TIMEOUT=3 run_case "$d"; expect approved "(p5) a pass 1 past the review time limit, then one in time"
[ "$(cat "$FAKE_GH/calls")" = 2 ] && grep -q 'pass 1 ran past 3s — re-spawning REVIEW (1 of 1)' <<<"$OUT" && [ "$(cat "$FAKE_GH/pass1-calls")" = 2 ] \
  && ok "(p5) the slow pass 1 is stopped at run.reviewTimeoutSeconds and no review session starts on it" \
  || bad "(p5) calls=$(cat "$FAKE_GH/calls") $(grep 'pass 1' <<<"$OUT" | tail -n 2)"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
