#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-pause-selftest.sh — run.sh scenario slice: a pause-and-ask region is the requester's to decide. The build stops on it,
# and the run ends there for a human.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-pause-selftest] the build stops on a pause-and-ask region"

park_d2() { # the fixture receipt with D-2 parked under a pause-and-ask OR-1, beside a reversible OR-2
  local r="$d/main/.claude/pipeline-state/42-ledger.md"
  awk '{ print }
    /^\| D-1 \|/ { print "| D-2 | backfill order | parked under OR-1 | deferred | open |" }' "$r" \
    | awk '/^No open regions/ { print "| ID | Region | Disposition |"; print "| --- | --- | --- |"; print "| OR-1 | Ordering of the backfill | pause-and-ask |"; print "| OR-2 | Retention window | reversible-default-and-flag |"; print ""; print "OR-2 default: 90 days, chosen by the operator; one config line to reverse."; next } { print }' > "$r.tmp" && mv "$r.tmp" "$r"
}
fixture pa; park_d2; printf 'build-pause\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-paused "[pause] the build stopped on the region"
[ "$RC" -eq 1 ] && [ "$(cat "$FAKE_GH/calls")" -eq 1 ] && ok "[pause] exit 1, and no review is spawned" || bad "[pause] rc=$RC calls=$(cat "$FAKE_GH/calls")"
grep -qF "terminal: build-paused — the build stopped on OR-1 — Ordering of the backfill." <<<"$OUT" && grep -qF "The build's question: Oldest first, or newest first? —" <<<"$OUT" && ! grep -qF 'OR-2' <<<"$OUT" \
  && ok "[pause] the detail names the region and carries the build's question" || bad "[pause] detail: $(grep 'terminal: ' <<<"$OUT" | head -n 1)"
grep -qF "with provenance user-answered. When the answer departs from the ticket text, also rewrite that text in the ticket body in place: keep its id and its position, and change nothing else. Then push, and --resume." <<<"$OUT" \
  && ok "[pause] the detail tells the operator to amend the ticket when the answer departs from it" || bad "[pause] detail: $(grep 'terminal: ' <<<"$OUT" | head -n 1)"
grep -qF 'build-paused — the build stopped on OR-1' "$FAKE_GH/issue-comments" 2>/dev/null && ok "[pause] the closing comment on the ticket names the region" || bad "[pause] closing comment: $(tail -n 2 "$FAKE_GH/issue-comments" 2>/dev/null)"
[ -d "$d/wt" ] && grep -qx half "$(find "$d/wt" -name work.txt | head -n 1)" && ok "[pause] the worktree and its uncommitted work are left in place" || bad "[pause] worktree: $(ls "$d/wt" 2>/dev/null)"
fixture pa2; park_d2; printf 'build-pr\nreview-approve-d2\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[pause] a build that never needed the parked decision goes on to an approve"
fixture pa3; park_d2; printf 'build-pause\n' > "$FAKE_CLAUDE_PLAN"; FAKE_PAUSE=OR-2 run_case "$d"; expect build-paused "[pause] a pause that names a region the record does not mark pause-and-ask still stops"
grep -qF "names no pause-and-ask region of the record ('paused: OR-2')" <<<"$OUT" && ok "[pause] ...and the detail says so" || bad "[pause] detail: $(grep 'terminal: ' <<<"$OUT" | head -n 1)"
fixture pa5; park_d2; printf 'build-pause\n' > "$FAKE_CLAUDE_PLAN"; FAKE_PAUSE_RAW=$'I could not decide OR-1\nso I stopped\n' run_case "$d"; expect build-paused "[pause] a pause file with no 'paused:' first line still stops"
grep -qF "names no pause-and-ask region of the record ('I could not decide OR-1'). What it wrote: so I stopped —" <<<"$OUT" && [ "$RC" -eq 1 ] && ok "[pause] ...and the detail quotes its first line instead of naming a region" || bad "[pause] rc=$RC detail: $(grep 'terminal: ' <<<"$OUT" | head -n 1)"
fixture pa6; park_d2; printf 'build-pause\n' > "$FAKE_CLAUDE_PLAN"; FAKE_PAUSE_RAW='' run_case "$d"; expect build-paused "[pause] an empty pause file still stops"
grep -qF "names no pause-and-ask region of the record (''). What it wrote: (nothing) —" <<<"$OUT" && [ "$RC" -eq 1 ] && ok "[pause] ...and the detail says nothing was written" || bad "[pause] rc=$RC detail: $(grep 'terminal: ' <<<"$OUT" | head -n 1)"
fixture pa7; park_d2; printf 'build-pr\nreview-approve-d2\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/awkdead"
cat > "$T/awkdead/awk" <<EOF
#!/usr/bin/env bash
case " \$* " in *'"pause-and-ask"'*) exit 2 ;; esac; exec "$(command -v awk)" "\$@"
EOF
chmod +x "$T/awkdead/awk"; OUT="$( cd "$d/main" && PATH="$T/awkdead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect env-worktree "[pause] regions that cannot be read refuse the build"; [ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "[pause] ...exit 2, and no session is spawned" || bad "[pause] rc=$RC calls=$(cat "$FAKE_GH/calls" 2>/dev/null)"
fixture pa4; park_d2; printf 'build-pr-decide-parked\nreview-approve-d2\nreview-approve-d2\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "[pause] an approve that scores the build's own decision of the parked row honored never binds"
grep -qF "user-delegated row under a pause-and-ask region not scored violated: D-2 honored" <<<"$OUT" && [ ! -s "$FAKE_GH/statuses" ] && ok "[pause] ...the miss names the rule, and no status is posted" || bad "[pause] miss: $(grep 'verdict grammar' <<<"$OUT" | head -n 1)"

# Under github, writes: false withholds only the Atlassian write tools, so a handoff build still amends the ticket with gh.
# Under jira, writes: false withholds every ticket write, and the edit becomes a request in the PR body.
FIXTURE_CONFIG='{"tracker":{"type":"github","writes":false,"branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}' fixture pa8; park_d2
printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff; expect build-handoff "[pause] a github handoff with writes false"
hp="$(sed -n 's/^prompt: //p' <<<"$OUT")"
[ "$CASE_ON" -eq 0 ] || { [ -n "$hp" ] && grep -qF "write it with 'gh issue edit 42 --body-file" "$hp" && ! grep -qF 'make no ticket write' "$hp" \
  && ok "[pause] ...its pause answer still amends the ticket with gh issue edit" || bad "[pause] github handoff: $(grep -F 'departs from the ticket text' "$hp" 2>/dev/null | tail -n 1)"; }
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture pa9; park_d2
mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/GH-42-ledger.md"
[ "$CASE_ON" -eq 0 ] || { OUT="$( cd "$d/main" && bash "$RUN" GH-42 --handoff 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; }
expect build-handoff "[pause] a jira handoff with writes false"
hp="$(sed -n 's/^prompt: //p' <<<"$OUT")"
[ "$CASE_ON" -eq 0 ] || { [ -n "$hp" ] && grep -qF "make no ticket write: tracker.writes is false. Add the ticket edit as a request to the PR body's '## Before you merge' section." "$hp" \
  && ! grep -qF 'gh issue edit' "$hp" && ! grep -qF "rewrite that text in the ticket's description" "$hp" \
  && ok "[pause] ...its pause answer makes no ticket write and asks for the edit in the PR body" || bad "[pause] jira handoff: $(grep -F 'departs from the ticket text' "$hp" 2>/dev/null | tail -n 1)"; }

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
