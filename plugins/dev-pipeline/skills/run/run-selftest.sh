#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-selftest.sh — run.sh scenario slice: terminals and adjudication invariants: the happy path,
# the handoff, needs-work rounds, what a build leaves, the scratch dir, which verdicts bind, the
# checks, the early refusals.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-selftest] terminals and adjudication invariants"

# (a) happy path: build opens a PR, review approves the head inside the window
fixture a; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(a) build-pr + review-approve"
[ "$RC" -eq 0 ] && ok "(a) exit 0 on approved" || bad "(a) exit $RC on approved"
grep -qx in-progress "$FAKE_GH/labels" && ! grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(a) queue label swapped for the claimed label" || bad "(a) label swap wrong: $(tr '\n' ' ' < "$FAKE_GH/labels")"
grep -q 'approved' "$FAKE_GH/issue-comments" && grep -q 'https://x/pr/7' "$FAKE_GH/issue-comments" && grep -q '^cost_usd: ' "$FAKE_GH/issue-comments" && ok "(a) [B22 D13] closing comment names the PR link and cost_usd" || bad "(a) closing comment: $(tail -n 3 "$FAKE_GH/issue-comments" | tr '\n' '|')"
grep -q '^acceptEdits$' "$FAKE_GH/args-1.txt" && grep -q -- '--permission-prompts' "$FAKE_GH/args-1.txt" && grep -q '^none$' "$FAKE_GH/args-1.txt" && grep -q '^user,project,local$' "$FAKE_GH/args-2.txt" && ok "(a) [F2 F8] acceptEdits, --permission-prompts none, --setting-sources user,project,local on both sessions" || bad "(a) [F2 F8] spawn flags: $(tr '\n' ' ' < "$FAKE_GH/args-1.txt" | cut -c1-200)"
grep -q '| D-1 | a | b | user-answered |' "$FAKE_GH/prompt-1.txt" && grep -q 'They are binding' "$FAKE_GH/prompt-1.txt" && grep -q "Never post a comment starting with 'verdict:'" "$FAKE_GH/prompt-1.txt" && ok "(a) [F16 F17] the record is in the build prompt verbatim, binding, with the verdict ban" || bad "(a) [F16 F17] prompt-1 lacks the record or the rules"
grep -qx '    The fixture worker retries a 409 forever.' "$FAKE_GH/prompt-1.txt" && grep -qF "The record's '## Knowledge source' and '## Fan-out' sections are context, not binding" "$FAKE_GH/prompt-1.txt" \
  && ok "(a) #1032 D-4: the knowledge-source answer reaches the build verbatim, and the prompt says it and the fan-out are context, not binding" || bad "(a) #1032 D-4: prompt-1 lacks the indented answer or the context-not-binding sentence"
grep -q '<!-- dev-pipeline -->$' "$FAKE_GH/issue-comments" && grep -q '^<!-- run_id: ' "$FAKE_GH/issue-comments" && grep -q '^<!-- session_id: ' "$FAKE_GH/issue-comments" && grep -q '^<!-- stage: lean-claimed -->$' "$FAKE_GH/issue-comments" && ok "(a) [D4] claim marker: the four HTML lines, each whole" || bad "(a) [D4] marker lines: $(grep -c '^<!-- ' "$FAKE_GH/issue-comments")"
grep -q 'Claimed by .*/dev-pipeline:run' "$FAKE_GH/issue-comments" && ! grep -q 'dev-pipeline:build' "$FAKE_GH/issue-comments" && ok "(a) a run's claim marker names /dev-pipeline:run" || bad "(a) run marker: $(grep 'Claimed by' "$FAKE_GH/issue-comments")"
! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-1.txt" && ! grep -qE '^--(resume|continue)$' "$FAKE_GH/args-2.txt" && ok "(a) [F1] neither session is resumed or continued" || bad "(a) [F1] a session was resumed"
[ "$(tr '\n' ' ' < "$FAKE_GH/env-1.txt")" = "BASH_DEFAULT_TIMEOUT_MS=6900000 BASH_MAX_TIMEOUT_MS=6900000 CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 " ] && ok "(a) [F-env] BUILD: background tasks off, Bash timeouts 300 s inside the 7200 s bound" || bad "(a) [F-env] BUILD spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-1.txt")"
[ "$(tr '\n' ' ' < "$FAKE_GH/env-2.txt")" = "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=3300000 " ] && ok "(a) [F-env] REVIEW: background tasks kept, their wait 300 s inside the 3600 s bound" || bad "(a) [F-env] REVIEW spawn env: $(tr '\n' ' ' < "$FAKE_GH/env-2.txt")"
[ ! -d "$d/wt/42" ] && ok "(a) worktree torn down on approve" || bad "(a) worktree left after approve"
grep -q 'Closes #42' "$FAKE_GH/prompt-1.txt" && grep -q 'gh pr create --draft' "$FAKE_GH/prompt-1.txt" && ok "(a) build prompt asks for a draft PR that closes the ticket" || bad "(a) PR conventions missing from the build prompt"
grep -q 'AskUserQuestion' "$FAKE_GH/args-1.txt" && ! grep -q 'editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(a) keyboard tools disallowed, no jira strip under github" || bad "(a) disallowed-tools list wrong"
grep -q "DECLARE THE LANE'S OPT-INS" "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt declares the lane's opt-ins" || bad "(a) opt-in declaration missing"
grep -q 'the expected call whenever the diff introduces a surface' "$FAKE_GH/prompt-2.txt" && grep -q 'Do not stand in for an opt-in seat' "$FAKE_GH/prompt-2.txt" && grep -q 'pass the decline to review-lead with a one-line reason' "$FAKE_GH/prompt-2.txt" && ok "(a) review prompt: opting a reviewer in is the expected call on an introduced surface, the lead pass is no stand-in, and a decline carries a reason" || bad "(a) judgment opt-in / decline-with-reason missing from the review prompt"
grep -q "naming security, a11y, unit-test-mutation, performance, maintainability, complexity or test-coverage" "$FAKE_GH/prompt-2.txt" && grep -q 'performance for a new entry point' "$FAKE_GH/prompt-2.txt" \
  && grep -q 'A record-named risk with neither a dispatch nor a decline is a process \[blocker\]' "$FAKE_GH/prompt-2.txt" && grep -q 'Its risk is also required performance work: the review states the worst-case bound as a finding' "$FAKE_GH/prompt-2.txt" \
  && ok "(a) #1034: performance is a fourth opt-in with an entry-point surface, a record-named cost risk is a required decision, and its row's risk is required work beside its score" || bad "(a) #1034: the performance opt-in, record arm or named-risk scoring is missing from the review prompt"
grep -q 'models: build opus (label), review opus (default)' <<<"$OUT" && ok "(a) [A4 A6] build model read from the opus label; tiers are passed to the CLI as aliases, never pinned ids" || bad "(a) model line: $(grep 'models:' <<<"$OUT")"
! grep -q 'claude-opus-[0-9]' "$FAKE_GH/args-1.txt" && grep -q '^opus$' "$FAKE_GH/args-1.txt" && ok "(a) [A6] the session is launched with --model opus" || bad "(a) [A6] a pinned model id reached the session: $(grep -A1 -- '--model' "$FAKE_GH/args-1.txt" | tr '\n' ' ')"
first=$(git -C "$d/origin.git" log --format=%s --reverse main..second-shift/42 | head -n 1)
[ "$first" = "docs: add the decision record" ] && ok "(a) the record is the branch's first commit" || bad "(a) first commit is '$first'"
grep -q '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md" 2>/dev/null && grep -q 'built-by: fake' "$FAKE_GH/pr-body.md" && grep -q '| approved |' "$FAKE_GH/pr-body.md" && ok "(a) run block written into the PR body, original body kept" || bad "(a) no run block in the PR body"
grep -qE '^[|] review-1[.]1 [|] 3 [|] [$]1[.]00 [|]' "$FAKE_GH/pr-body.md" 2>/dev/null && ok "(a) per-session cost rows in the block" || bad "(a) per-session rows missing"
lnum() { grep -nE "$1" "$FAKE_GH/pr-body.md" 2>/dev/null | head -n 1 | cut -d: -f1; }
lo=$(lnum '^Outcome: approved after 1 round[(]s[)][.] Verdict: approve[.]'); ls_=$(lnum '^status: '); ld=$(lnum '^<details><summary>Run details</summary>$'); lt=$(lnum '^[|] run [|] outcome [|]'); le=$(lnum '^</details>$'); lm=$(lnum '^<!-- /pipeline-cost-block -->$')
[ -n "$lo" ] && [ -n "$ls_" ] && [ -n "$ld" ] && [ "$lo" -lt "$ld" ] && [ "$ls_" -lt "$ld" ] && [ "$ld" -lt "$lt" ] && [ "$lt" -lt "$le" ] && [ "$le" -lt "$lm" ] \
  && ok "(a) the run block opens with the outcome line and the status note, and folds the run and session tables" || bad "(a) run block order: outcome=$lo status=$ls_ details=$ld table=$lt /details=$le end=$lm"
grep -q 'ls /' "$(SD)/review-1.1.prompt" && ok "(a) build denials reach the review input" || bad "(a) denials missing from review input"
grep -qF 'A denied command is not a reason to end your turn: skip a command outside the allowlist and name it in the PR body as skipped. Pushing second-shift/42 and opening the draft PR are never skipped.' "$FAKE_GH/prompt-1.txt" \
  && ok "(a) #973 D-3: the build prompt says a denial is not a stop, and pushing and the draft PR are never skipped" || bad "(a) #973 D-3: the denial-is-not-a-stop line is missing from the build prompt"
grep -qF 'run the checks below that cover what you changed and make them green; running the whole list is not required.' "$FAKE_GH/prompt-1.txt" \
  && grep -qF 'The scheduler runs every command below at the pushed head before a review starts' "$FAKE_GH/prompt-1.txt" && grep -qF 'a red one comes back to you as findings and spends a checks-red attempt.' "$FAKE_GH/prompt-1.txt" \
  && grep -qx -- '- true' "$FAKE_GH/prompt-1.txt" && ! grep -q 'run every command below and make it green' "$FAKE_GH/prompt-1.txt" \
  && ok "(a) #1035 D-2: the build prompt keeps the list as the scheduler's pass at the pushed head, and asks the build only for the checks its change touches" || bad "(a) #1035 D-2: the build prompt's checks paragraph still asks for the whole list, or lost the list or the checks-red framing"
grep -qx 'While iterating, rerun only the test file or suite your change touches.' "$FAKE_GH/prompt-1.txt" \
  && ok "(a) #1035 D-4: the build prompt tells a build to iterate on the test file or suite it touches" || bad "(a) #1035 D-4: the iteration line is missing from the build prompt"

# (ho) --handoff (/dev-pipeline:build): claim, worktree, record, prompt — then stop; the calling session builds
fixture ho; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect build-handoff "(ho) an unsized ticket is handed to the calling session"
[ "$RC" -eq 0 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(ho) exit 0 and no session spawned" || bad "(ho) rc=$RC, claude calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"
hp="$(sed -n 's/^prompt: //p' <<<"$OUT")"; hw="$(sed -n 's/^worktree: //p' <<<"$OUT")"
[ -n "$hp" ] && grep -q 'Implement ticket 42' "$hp" && grep -q 'D-1' "$hp" && [ -d "$hw" ] && ok "(ho) the build prompt and worktree are printed" || bad "(ho) prompt '$hp' / worktree '$hw'"
# The closing comment is public: the worktree path stays in the local log, never on the tracker.
grep -q 'build-handoff' "$FAKE_GH/issue-comments" && ! grep -qF "$hw" "$FAKE_GH/issue-comments" && grep -q '<worktree>' "$FAKE_GH/issue-comments" \
  && ok "(ho) the handoff comment names <worktree>, never the local path" || bad "(ho) local path in the tracker comment: $(grep build-handoff "$FAKE_GH/issue-comments")"
[ "$(git -C "$d/origin.git" log --format=%s main..second-shift/42 2>/dev/null)" = "docs: add the decision record" ] && ok "(ho) the record is the pushed branch's only commit" || bad "(ho) branch: $(git -C "$d/origin.git" log --oneline main..second-shift/42 2>&1 | tr '\n' '|')"
grep -qx in-progress "$FAKE_GH/labels" && grep -q 'Claimed by .*/dev-pipeline:build' "$FAKE_GH/issue-comments" && ok "(ho) claimed, and the marker names /dev-pipeline:build" || bad "(ho) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
hb="$(sed -n 's/^baseline: //p' <<<"$OUT")"
[ -n "$hb" ] && [ "$hb" = "$(git -C "$d/origin.git" rev-parse second-shift/42)" ] && grep -q "Record baseline: $hb" "$hp" && grep -q "never amend, rebase or force-push over it" "$hp" && ok "(ho) the record baseline is printed and pinned in the prompt" || bad "(ho) baseline '$hb'"
grep -q '^unpriced: build-in-calling-session' "$FAKE_GH/issue-comments" && ok "(ho) the closing comment says the build is unpriced, not \$0" || bad "(ho) closing comment: $(grep -A1 cost_usd "$FAKE_GH/issue-comments" | tr '\n' '|')"
! grep -q '\[run\] scratch: ' <<<"$OUT" && grep -q 'Delete every probe or scratch file you created' "$hp" && ! grep -q 'Run every check in the foreground' "$hp" \
  && ok "(ho) #964 D-10: no scratch dir for a handoff; its prompt keeps the delete sentence and no foreground rule" || bad "(ho) #964 D-10: handoff scratch/prompt wrong"
lane_says() { jq --arg b "$1" --arg t "$2" '. + [{body:$b,user:{login:"tester",type:"User"},created_at:$t,updated_at:$t}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"; }
# re-entry reads the marker the handoff itself posted (the fake gh logs comments; it does not list them back)
hm="$(awk '/--body <!-- dev-pipeline -->/{on=1; sub(/^.*--body /,"")} on{print} on && /^second-shift-run: /{exit}' "$FAKE_GH/issue-comments")"
grep -qx '<!-- stage: lean-claimed -->' <<<"$hm" && ok "(ho) the handoff posts the lane's claim marker" || bad "(ho) handoff marker: $(tr '\n' '|' <<<"$hm")"
lane_says "$hm" 2020-01-01T00:00:00Z
lane_says 'second-shift run h1: build-handoff — BUILD handed to the calling session' 2020-01-02T00:00:00Z
run_case "$d" --handoff; expect build-handoff "(ho) a second handoff re-enters its own claim"
echo opus >> "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(ho) a plain run refuses a claim handed to /dev-pipeline:build"
[ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "(ho) the refusal exits 2 and spawns no second writer" || bad "(ho) rc=$RC, claude calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"
lane_says 'second-shift run h2: build-no-pr — no open PR' 2020-01-03T00:00:00Z; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(ho) a later closing comment ends the handoff's hold"
fixture ho3; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
lane_says $'<!-- run_id: h1 -->\n<!-- stage: lean-claimed -->' 2020-01-01T00:00:00Z; lane_says 'second-shift run h1: build-handoff — BUILD handed to the calling session' 2020-01-02T00:00:00Z
run_case "$d" --resume; expect approved "(ho3) --resume hands a handed-off ticket back to the lane"
fixture ho4 ""; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect env-no-checks "(ho4) a handoff with no check to hand over is refused"
[ "$RC" -eq 2 ] && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] && [ ! -d "$d/wt" ] && ok "(ho4) refused before the claim: nothing written" || bad "(ho4) rc=$RC labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"allowUnverified":true}}}' fixture ho5 ""; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d" --handoff
expect build-handoff "(ho5) allowUnverified accepts a zero-check handoff"
fixture ho2; OUT="$( cd "$d/main" && bash "$RUN" 42 --handoff --detach 2>&1 )"; RC=$?
grep -q '^terminal: usage-handoff-detach$' <<<"$OUT" && [ "$RC" -eq 2 ] && ok "(ho2) --handoff with --detach is a usage refusal" || bad "(ho2) rc=$RC: $(tail -n 1 <<<"$OUT")"

# (b) needs-work then approve: two rounds, findings reach the round-2 build prompt
fixture b; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(b) needs-work, fix, approve"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-3.txt" && ok "(b) round-2 build prompt carries the findings" || bad "(b) findings not in round-2 prompt"
printf '%s\n' "$OUT" | grep -q '2 round' && ok "(b) two rounds counted" || bad "(b) round count wrong"

# (b3) #1010: a mixed needs-work (a blocker, a note) binds, and its round-2 build is ordered to act on the blocker, not the note.
# A grep on the emitted prompt, by necessity: the fake build never reads its prompt, so no run can show what it was told
fixture b3; printf 'build-pr\nreview-needs-work-mixed\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
run_case "$d"; expect approved "(b3) a mixed needs-work binds, fix, approve"
grep -qF -- '- [blocker] B1 [Maintainability] src/a.ts:3 (confidence: 85)' "$FAKE_GH/prompt-3.txt" && grep -qF -- '- [note] N1 [Complexity] src/a.ts:9 (confidence: 60)' "$FAKE_GH/prompt-3.txt" \
  && ok "(b3) both finding lines, confidence included, reach the round-2 build" || bad "(b3) a finding line is missing from prompt-3"
grep -qF 'fix each [blocker] finding, or rebut it' "$FAKE_GH/prompt-3.txt" && grep -qF 'violated or undeterminable' "$FAKE_GH/prompt-3.txt" \
  && ok "(b3) the build is ordered to fix or rebut each blocker and fix each bad row" || bad "(b3) the round-2 prompt does not split blockers from notes"
grep -qF 'A [note] finding requires nothing' "$FAKE_GH/prompt-3.txt" && ok "(b3) a note is named optional" || bad "(b3) the round-2 prompt does not free the notes"
! grep -qF 'fix each, or rebut it' "$FAKE_GH/prompt-3.txt" && ok "(b3) the every-finding order is gone" || bad "(b3) the prompt still orders every finding addressed"

# (b2) a check red in round 2 sits beside the review's findings, never in place of them: the retry still has what the review asked for
fixture b2 "- ! grep -qx 3 work.txt"; printf 'build-pr\nreview-needs-work\nbuild-push-only\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"
RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(b2) green, needs-work, then red twice"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-4.txt" && ok "(b2) the red retry still carries the review's findings" || bad "(b2) the red check replaced the review's findings"
grep -q '^## Red check output' "$FAKE_GH/prompt-4.txt" && grep -q 'cannot be rebutted' "$FAKE_GH/prompt-4.txt" && ok "(b2) the red check is handed over as a red check" || bad "(b2) the red check is not named as one"

# (c) no PR after the build
fixture c; printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-no-pr "(c) push without a PR"

# (d) E21: a build that left uncommitted work stops the run and nothing discards that work
fixture d; printf 'build-pr-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-inflight "(d) [E21] a build that left uncommitted work in the worktree is in flight"
[ -n "$(git -C "$d/wt/42" status --porcelain 2>/dev/null)" ] && ok "(d) [E21] the uncommitted work is still there, never reset away" || bad "(d) [E21] the worktree was cleaned — the build's work was discarded"
grep -qE '\[run\] terminal: build-inflight — .*its tree is not clean; it was denied 1 command\(s\), listed in .*/denials-1\.1\.txt\) ' <<<"$OUT" \
  && ok "(d) #973 D-2: the build-inflight detail cites the denials file" || bad "(d) #973 D-2: detail: $(grep 'terminal: build-inflight' <<<"$OUT")"
# (dn) #973 D-4: a session whose result JSON carried no permission_denials is unread, never "none", and the detail says so
cat > "$T/bin/claude-nodenials" <<EOF
#!/usr/bin/env bash
"$T/bin/claude" "\$@" | jq -c 'del(.permission_denials)'
EOF
chmod +x "$T/bin/claude-nodenials"
fixture dn; printf 'build-pr-dirty\n' > "$FAKE_CLAUDE_PLAN"; RUN_CLAUDE="$T/bin/claude-nodenials" run_case "$d"; expect build-inflight "(dn) a dirty tree with unread denials is still in flight"
grep -qE '\[run\] terminal: build-inflight — .*its tree is not clean; its permission denials are unread ' <<<"$OUT" \
  && ok "(dn) #973 D-4: the detail says the denials are unread" || bad "(dn) #973 D-4: detail: $(grep 'terminal: build-inflight' <<<"$OUT")"

# (dq) #926: untracked files alone, on a tree at the pushed head, are archived and the run goes on. The check fails if the
# probe is still in the tree, so it also proves the archive happens before the checks run
fixture dq "- test ! -e src/zz-probe.spec.ts"; printf 'build-pr-untracked\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(dq) a build that left only untracked probes behind is not in flight"
toc="$(tar -tf "$(SD)/quarantine-1.1.tar" 2>/dev/null)"
grep -qx 'src/zz-probe.spec.ts' <<<"$toc" && grep -qx 'src/probe dir/notes.txt' <<<"$toc" && ok "(dq) both files, one entry each, are in quarantine-1.1.tar" || bad "(dq) archive holds: $(tr '\n' ' ' <<<"$toc")"
grep -qE 'archived 2 untracked file\(s\) left in .* to .*/quarantine-1\.1\.tar ' <<<"$OUT" && ok "(dq) the log names the count and the archive" || bad "(dq) no archive line in the log"
sec="$(awk '/^### Untracked files archived/{on=1; next} /^###/{on=0} on' "$(SD)/review-input-1.1.md" 2>/dev/null)"
grep -qx 'src/zz-probe.spec.ts' <<<"$sec" && ok "(dq) the review input lists the archived path" || bad "(dq) review input lacks the archived path"
grep -q 'Put scratch files there; the scheduler removes it' "$FAKE_GH/prompt-1.txt" && ! grep -q 'Delete every probe' "$FAKE_GH/prompt-1.txt" && ok "(dq) #964 D-1: the build prompt puts probes in the scratch dir instead of asking the build to delete them" || bad "(dq) #964 D-1: scratch sentence missing from prompt-1, or the delete sentence kept"
grep -q 'A stored field the change newly reads, or a field it sends across a service boundary, gets a test that moves it through the real schema or model' "$FAKE_GH/prompt-1.txt" && ok "(dq) #950: the build prompt obliges a round-trip test for a newly read stored field" || bad "(dq) #950: round-trip sentence missing from prompt-1"
grep -q 'A test double of a dependency this repo does not own that returns an error or an empty result cites where that shape comes from' "$FAKE_GH/prompt-1.txt" && ok "(dq) #961: the build prompt asks an unowned dependency's error/empty double to cite its source" || bad "(dq) #961: unowned-double sentence missing from prompt-1"
grep -q 'Before you write a comment that claims a UI library does or does not do something, open the installed source of that library and check the claim' "$FAKE_GH/prompt-1.txt" && ok "(dq) #1076 AC-5: a ticket with no design frames still gets the UI-library authoring sentence" || bad "(dq) #1076 AC-5: UI-library authoring sentence missing from prompt-1"
[ ! -d "$d/wt/42" ] && ok "(dq) the worktree is removed at close-out" || bad "(dq) worktree left in place"

# (sc) #964 D-1 D-2 D-3: one scratch dir per run, outside .claude/, live during both spawns, named in both prompts;
# archived into $STATE and removed at exit. Neither session is handed $STATE
fixture sc; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(sc) a run with a scratch dir"
scr="$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | grep -- '-scratch\.' | head -n 1)"
[ -n "$scr" ] && case "$scr" in */.claude/*) false ;; "$(cd "${TMPDIR:-/tmp}" && pwd -P)"/second-shift-42-scratch.*) true ;; *) false ;; esac \
  && ok "(sc) D-1: the build is handed a scratch dir under \$TMPDIR, outside .claude/" || bad "(sc) D-1: build scratch dir '${scr:-none}'"
grep -qxF -- "$scr" "$FAKE_GH/live-dirs-1.txt" 2>/dev/null && grep -qxF -- "$scr" "$FAKE_GH/live-dirs-2.txt" 2>/dev/null && [ "$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-2.txt" | grep -cxF -- "$scr")" = 1 ] \
  && ok "(sc) D-1: the same dir is in both spawns' --add-dir and exists while each runs" || bad "(sc) D-1: live dirs: $(cat "$FAKE_GH"/live-dirs-*.txt 2>/dev/null | tr '\n' ' ')"
grep -qF "$scr" "$FAKE_GH/prompt-1.txt" && grep -qF "$scr" "$FAKE_GH/prompt-2.txt" && grep -q 'Put scratch files there; the scheduler removes it' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) D-1: both prompts name the scratch dir as the place for scratch files" || bad "(sc) D-1: a prompt does not name $scr"
toc="$(tar -tf "$(SD)/scratch.tar" 2>/dev/null)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" && grep -qx './probe-2.txt' <<<"$toc" \
  && ok "(sc) D-2: at exit the dir is gone and both sessions' files are in \$STATE/scratch.tar" || bad "(sc) D-2: dir $([ -e "$scr" ] && echo kept || echo gone), archive: $(tr '\n' ' ' <<<"$toc")"
ads="$(grep -h -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" "$FAKE_GH/args-2.txt")"
[ -n "$ads" ] && ! grep -qF "/run-42/" <<<"$ads" && grep -q 'code-review.mjs' "$FAKE_GH/prompt-2.txt" && grep -qF "writing it with Write into $scr," "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) D-3: the review stages code-review.mjs in the scratch dir and is not handed \$STATE" || bad "(sc) D-3: \$STATE still granted, or the staging sentence does not name $scr"
# the prompt lines (S-3), one case each
grep -q 'Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables' "$FAKE_GH/prompt-1.txt" && grep -q 'Run each shell command on its own, with absolute paths: no cd (use git -C <dir>), no shell variables' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: both prompts ask for one command per call, absolute paths, no cd or variables" || bad "(sc) S-3: one-command line missing"
grep -q 'Edit files only with the Edit and Write tools, never through a shell' "$FAKE_GH/prompt-1.txt" && grep -q 'Write files only with the Write tool, never through a shell' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: files are edited with Edit/Write only, never a shell rewrite" || bad "(sc) S-3: Edit/Write line missing"
grep -q 'Run every check in the foreground: no nohup, no trailing &' "$FAKE_GH/prompt-1.txt" && grep -q 'no nohup or trailing &' "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: no nohup or backgrounded commands" || bad "(sc) S-3: foreground line missing"
grep -q 'Pass every PR or comment body with --body-file' "$FAKE_GH/prompt-1.txt" && grep -qF "passed with --body-file <a file in $scr>" "$FAKE_GH/prompt-2.txt" \
  && ok "(sc) S-3: PR and comment bodies go through --body-file" || bad "(sc) S-3: --body-file line missing"
grep -q "Do not run the repo's test suites or checks: the scheduler ran them at this head" "$FAKE_GH/prompt-2.txt" && ! grep -q "Do not run the repo's test suites" "$FAKE_GH/prompt-1.txt" \
  && ok "(sc) S-3: the review does not re-run the suites" || bad "(sc) S-3: review no-suites line missing (or in the build prompt)"
# D-4: the review's denials are recorded beside the build's, and the run block counts them per session
# shellcheck disable=SC2016  # the run block's literal dollar costs
grep -q 'ls /' "$(SD)/denials-review-1.1.txt" 2>/dev/null && grep -qxF '| session | turns | cost | denials |' "$FAKE_GH/pr-body.md" \
  && grep -qxF '| build-1.1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" && grep -qxF '| review-1.1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" \
  && ok "(sc) D-4: denials-review-1.1.txt is written and the run block counts each session's denials" || bad "(sc) D-4: $(grep -E '^\| (session|build|review)' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
fixture d2; printf 'build-nothing\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect build-no-pr "(d2) [B14 B15] a build that changed nothing and opened no PR is build-no-pr, not in flight (orch:1515-1545 never tested head movement)"

# (e) verdict names the wrong head
fixture e; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(e) verdict for another sha"

# (f) a stale approve for THIS head, posted before the review window, must not count
fixture f; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
# the review posts a correct approve for the right head; the gh wrapper backdates it on read, so the
# only thing wrong with it is WHEN it was posted
cat > "$T/bin/gh-backdate" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/issues/7/comments" ]; then jq 'map(.created_at = "2020-01-01T00:00:00Z" | .updated_at = "2020-01-01T00:00:00Z")' "\$FAKE_GH/comments.json"; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-backdate"; RUN_GH="$T/bin/gh-backdate" run_case "$d"; expect review-unbound "(f) a correct approve posted outside the review window is rejected"

# (g) an edited verdict comment must not count
fixture g; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-edit" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/issues/7/comments" ]; then jq 'map(.updated_at = "2099-01-01T00:00:00Z")' "\$FAKE_GH/comments.json"; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-edit"; RUN_GH="$T/bin/gh-edit" run_case "$d"; expect review-unbound "(g) edited verdict comment is rejected"

# (h) checks red, then spent
fixture h "- false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"
RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "(h) red checks spend their own counter"
[ "$(cat "$FAKE_GH/calls")" = 2 ] && ok "(h) no review was spawned on red checks" || bad "(h) review spawned on red checks ($(cat "$FAKE_GH/calls") calls)"

# (i) the checks list is read from the FIRST commit: a build that rewrites '## Checks' to '- true' still runs '- false'
fixture i "- false"; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/claude-rewrite" <<EOF
#!/usr/bin/env bash
sed -i.bak 's/^- false$/- true/' docs/plans/main-42-decisions.md 2>/dev/null; rm -f docs/plans/main-42-decisions.md.bak
exec "$T/bin/claude" "\$@"
EOF
chmod +x "$T/bin/claude-rewrite"; RUN_CLAUDE="$T/bin/claude-rewrite" RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(i) a build cannot change what runs against it"

# (j) zero checks declared is not green
fixture j ""; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(j) no '## Checks' lines refuses to read as green"

# (k) a deleted test file reaches the reviewer
fixture k; printf 'build-delete-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
grep -q 'a.spec.ts' "$(SD)/review-1.1.prompt" && ok "(k) deleted spec named in the review input" || bad "(k) deleted spec not surfaced"

# (l) claimed elsewhere, ticket closed, cost ceiling, no record
fixture l; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d"; expect claimed-elsewhere "(l1) in-progress label without --resume"
[ ! -d "$d/wt/42" ] && ok "(l1) no worktree created" || bad "(l1) worktree created despite refusal"
fixture l2; echo CLOSED > "$FAKE_GH/state"; run_case "$d"; expect env-ticket-closed "(l2) a ticket closed at launch is a preflight refusal"
[ "$RC" -eq 2 ] && ok "(l2) exits 2, like every preflight refusal" || bad "(l2) exit $RC"
fixture l3; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=60 RUN_COST_CEILING=100 run_case "$d"; expect cost-spent "(l3) cost ceiling"; [ "$RC" -eq 4 ] && ok "(l3) [B8] cost-spent exits 4" || bad "(l3) exit $RC"
# I15: the ceiling is exceeded, not reached — a run whose spend lands exactly on it keeps going
fixture l3b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=25 RUN_COST_CEILING=25 run_case "$d"; expect approved "[I15] a build whose spend equals the ceiling is not over it"
fixture l3c; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=2.43739 run_case "$d"; expect approved "(l3c) fractional session costs"
grep -qE '[|] [$]4[.]87 [|]' "$FAKE_GH/pr-body.md" && grep -qE '^[|] build-1[.]1 [|] 3 [|] [$]2[.]44 [|]' "$FAKE_GH/pr-body.md" && grep -q '^cost_usd: 4.87$' "$FAKE_GH/issue-comments" && ok "(l3c) every reported cost is rounded to two decimals" || bad "(l3c) costs: $(grep -E '[$][0-9]|cost_usd' "$FAKE_GH/pr-body.md" "$FAKE_GH/issue-comments" | tr '\n' '|')"
grep -q 'round(s), [$]4[.]87$' <<<"$OUT" && ! grep -q '4[.]874' "$FAKE_GH/issue-comments" && ! grep -q '4[.]874' <<<"$OUT" && ok "(l3c) the terminal message and closing comment carry the rounded total too" || bad "(l3c) raw total leaked: $(grep -h '4[.]874' "$FAKE_GH/issue-comments" - <<<"$OUT" | head -n 2 | tr '\n' '|')"
fixture l3d; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=2.43739 LC_NUMERIC=de_DE.UTF-8 run_case "$d"; expect approved "(l3d) a comma-decimal locale"
grep -qE '^[|] build-1[.]1 [|] 3 [|] [$]2[.]44 [|]' "$FAKE_GH/pr-body.md" && ! grep -q '2,44' "$FAKE_GH/pr-body.md" && ok "(l3d) costs keep a dot decimal whatever the locale" || bad "(l3d) $(grep -E '[$][0-9]' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
fixture l3e; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; FAKE_COST=50.002 RUN_COST_CEILING=100 run_case "$d"; expect cost-spent "(l3e) 100.004 against a \$100 ceiling"
grep -q '[$]100[.]01 exceeds the [$]100 ceiling' <<<"$OUT" && ok "(l3e) a cost-spent figure is rounded up, never to the ceiling itself" || bad "(l3e) $(grep 'exceeds' <<<"$OUT" | tail -n 1)"
fixture l4; rm "$d/main/.claude/pipeline-state/42-ledger.md"; run_case "$d"; expect env-no-record "(l4) no intake record"; [ "$RC" -eq 3 ] && ok "(l4) [B6 K8] env-no-record exits 3 (resumable)" || bad "(l4) exit $RC"
# #1023 AC-13: /intake is the only way in, so the refusal names it, not a retired stage skill
grep -q 'run /intake-toolkit:intake 42 first' <<<"$OUT" && ! grep -q 'intake-toolkit:plan-interview' <<<"$OUT" \
  && ok "(l4) #1023: the refusal names '/intake-toolkit:intake 42'" || bad "(l4) #1023: $(grep 'terminal: env-no-record' <<<"$OUT")"
fixture l5; run_case "$d" --dry-run; expect usage-dry-run "(l5) the removed --dry-run is refused by name"; [ "$RC" -eq 2 ] && ok "(l5) usage-dry-run exits 2" || bad "(l5) exit $RC"
[ ! -f "$FAKE_GH/calls" ] && ok "(l5) nothing spawned on --dry-run" || bad "(l5) claude called on --dry-run"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
