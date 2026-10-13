#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-queue-selftest.sh — run.sh scenario slice: queue discipline and sizing, the local config
# override, parity rounds one to four.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-queue-selftest] queue discipline and sizing, the local config override, parity rounds one to four"

# (n) queue discipline and sizing, as the old lane enforced them
fixture n1; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n1) no queue label"
fixture n2; printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(n2) blocker label refuses pickup"
fixture n3; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; run_case "$d"; expect usage-model "(n3) unlabeled ticket is not sized here"
grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/issue-comments" ] && ok "(n3) refused BEFORE the claim: still queued, nothing written" || bad "(n3) the claim ran before the sizing refusal"
fixture n4; printf 'ready-for-dev\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --model claude-sonnet-5 --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(n4) --model overrides the missing label"
grep -q 'models: build claude-sonnet-5 (flag), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(n4) override models logged" || bad "(n4) override not applied"
fixture n5; printf '{"tracker":{"type":"github","branchPrefix":"claude/acme-"},"paths":{"plansDir":"docs/plans"}}\n' > "$d/main/.claude/second-shift.config.json"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/claude/acme-42 >/dev/null && ok "(n5) branch honors tracker.branchPrefix" || bad "(n5) no claude/acme-42 on origin: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
# (n6-n9) C6a: the gitignored per-engineer <config>.local.json may override tracker.branchPrefix and nothing else
local_cfg() { printf '%s\n' "$1" > "$d/main/.claude/second-shift.config.local.json"; }
fixture n6; printf '{"tracker":{"type":"github","branchPrefix":"claude/acme-"},"paths":{"plansDir":"docs/plans"}}\n' > "$d/main/.claude/second-shift.config.json"
local_cfg '{"tracker":{"branchPrefix":"jdoe/"}}'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(n6) a run with a local branch-prefix override"
git -C "$d/origin.git" rev-parse -q --verify refs/heads/jdoe/42 >/dev/null && ! git -C "$d/origin.git" rev-parse -q --verify refs/heads/claude/acme-42 >/dev/null \
  && ok "(n6) the local branchPrefix wins over the committed one" || bad "(n6) branches on origin: $(git -C "$d/origin.git" branch --list | tr '\n' ' ')"
grep -q "branch prefix 'jdoe/' from second-shift.config.local.json (overrides the committed 'claude/acme-')" <<<"$OUT" \
  && ok "(n6) the override is named in the run log, with the prefix it replaced" || bad "(n6) no override line: $(grep 'branch prefix' <<<"$OUT")"
fixture n7; local_cfg '{"tracker":{"branchPrefix":"jdoe/"},"run":{"maxRounds":9}}'; run_case "$d"; expect env-config-local "(n7) a local file that sets a team key is refused"
grep -q 'sets run.maxRounds' <<<"$OUT" && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] \
  && ok "(n7) refused before the claim, naming the key" || bad "(n7) $(grep 'terminal' <<<"$OUT" | head -n 1)"
fixture n8; local_cfg '{"tracker":{"branchPrefix":"jdoe/"}}'; git -C "$d/main" add -f .claude/second-shift.config.local.json && git -C "$d/main" commit -qm local
run_case "$d"; expect env-config-local "(n8) a committed local file is refused"
grep -q 'is committed' <<<"$OUT" && ok "(n8) the refusal says it is committed" || bad "(n8) $(grep 'terminal' <<<"$OUT" | head -n 1)"
fixture n9; local_cfg 'jdoe/'; run_case "$d"; expect env-config-local "(n9) an unparseable local file is refused, never ignored"
fixture n9b; local_cfg '{"tracker":{"branchPrefix":""}}'; run_case "$d"; expect env-config-local "(n9b) an empty local branchPrefix is refused, never a silent fall-back to the committed one"

# (p) parity with orchestrate.sh: tool strip, config commands, exit codes, flags, prefix refusal
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[A-Z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture p1
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model claude-sonnet-5
expect usage-key "(p1) jira key pattern refuses a numeric key"
FIXTURE_CONFIG='{"tracker":{"type":"github","writes":false,"branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}' fixture p2
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(p2) writes:false run"
grep -qx in-progress "$FAKE_GH/labels" && grep -q 'stage: lean-claimed' "$FAKE_GH/issue-comments" && ok "(p2) [D16] under github, writes:false gates only the tool strip: the labels and the marker are still written" || bad "(p2) [D16] no claim under writes:false"
grep -q 'mcp__atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && grep -q 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && grep -q 'mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue' "$FAKE_GH/args-2.txt" && ok "(p2) tracker.writes:false strips the Atlassian write tools in both sessions" || bad "(p2) write tools not stripped"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"false","typecheck":null,"test":"true"}}}' fixture p3 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(p3) configured commands.* run as checks even with no '## Checks'"
grep -q 'RED: false' "$(SD)/checks-1.1.log" && grep -q 'ok: true' "$(SD)/checks-1.1.log" && ok "(p3) lint red, test green, typecheck null skipped" || bad "(p3) check log wrong"
FIXTURE_CONFIG='{"tracker":{"type":"github"},"paths":{"plansDir":"docs/plans"}}' fixture p4; run_case "$d"; expect env-branch-prefix "(p4) no prefix configured and no dominant remote prefix: refuse, never guess"
[ "$RC" -eq 2 ] && ok "(p4) exit 2" || bad "(p4) exit $RC"
fixture p5; printf 'opus\n' > "$FAKE_GH/labels"; run_case "$d"; [ "$RC" -eq 3 ] && ok "(p5) not-queued exits 3 (resumable)" || bad "(p5) not-queued exit $RC"
fixture p6; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; [ "$RC" -eq 4 ] && ok "(p6) rounds-spent exits 4" || bad "(p6) rounds-spent exit $RC"
fixture p7; printf 'build-pr\nreview-wrong-sha\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; [ "$RC" -eq 5 ] && ok "(p7) review-unbound exits 5" || bad "(p7) review-unbound exit $RC"
fixture p8; printf 'build-pr-close\nreview-needs-work\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect ticket-closed "(p8) a ticket closed MID-RUN expires the premise"
[ "$RC" -eq 7 ] && ok "(p8) mid-run closed exits 7" || bad "(p8) exit $RC"
fixture p9; run_case "$d" --review-model claude-sonnet-5; [ "$RC" -eq 2 ] && ok "(p9) --review-model without --review-model-basis is refused" || bad "(p9) exit $RC"
fixture p10; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model claude-sonnet-5 --model-basis "test" --review-model claude-sonnet-5 --review-model-basis "test"; expect approved "(p10) orchestrate.sh's --build-model and basis flags are accepted"
grep -q 'models: build claude-sonnet-5 (test), review claude-sonnet-5 (test)' <<<"$OUT" && ok "(p10) bases logged" || bad "(p10) bases not logged"
fixture p11; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && git checkout -q -b bump && echo z >> src/a.ts && git commit -qam "base moves" && git push -q origin bump:main && git checkout -q main && git reset -q --hard origin/main ) 2>/dev/null
# the branch will touch work.txt only, so a base move on src/a.ts must NOT expire it
run_case "$d"; expect approved "(p11) a base move outside the branch's files does not expire the premise"

# (q) round-two parity: exit codes for env refusals, re-entry by marker, evidence per attempt,
#     the old cost block's terminator, fail-closed staleness, the jira read allowlist, config caps
fixture q1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm -rf "$d/origin.git"; run_case "$d"
[ "$RC" -eq 2 ] && ok "(q1) an environment refusal exits 2 (was demoted to 1)" || bad "(q1) env refusal exit $RC ($TERM_SLUG)"
fixture q2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
echo 'x <!-- stage: lean-claimed --> y' >> "$FAKE_GH/issue-comments"; jq '. + [{body:"<!-- run_id: old -->\n<!-- stage: lean-claimed -->",user:{login:"tester",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect approved "(q2) claimed label + lane marker re-enters without --resume"
grep -q 'approved' "$FAKE_GH/issue-comments" && ok "(q2) closing comment posted on a re-entered run" || bad "(q2) no closing comment on re-entry"
[ "$(grep -c 'stage: lean-claimed' "$FAKE_GH/issue-comments")" = 1 ] && [ "$(grep -c '^in-progress$' "$FAKE_GH/labels")" = 1 ] && ok "(q2) [K2 K10] re-entry posts no marker and swaps no label" || bad "(q2) [K2 K10] re-entry wrote to the tracker: markers=$(grep -c 'stage: lean-claimed' "$FAKE_GH/issue-comments") labels=$(tr '\n' ' ' < "$FAKE_GH/labels")"
fixture q3 "- false"; printf 'build-pr\nbuild-push-only\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=3 run_case "$d"; expect checks-red-spent "(q3) three red attempts"
[ -f "$(SD)/build-1.1.json" ] && [ -f "$(SD)/build-1.3.json" ] && ok "(q3) every attempt keeps its own evidence file" || bad "(q3) attempt evidence overwritten"
# (q12) a red lane that writes megabytes (a web server's request log): the next build still starts, reads the prompt on
# stdin, and gets each red check's tail — passed as an argument it overran the exec limit and the session died as rc 126
fixture q12 "- yes 'chatty check output line' | head -n 60000; false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"
expect checks-red-spent "(q12) a red lane that writes megabytes still reaches a second build"
p2="$FAKE_GH/prompt-2.txt"
[ -s "$p2" ] && [ "$(wc -c < "$p2")" -lt 300000 ] && grep -q '^RED: yes' "$p2" && grep -q 'earlier lines of this check cut' "$p2" && ok "(q12) the second build reads a capped excerpt naming the red check" || bad "(q12) prompt-2: $(wc -c < "$p2" 2>/dev/null) bytes"
grep -q 'Implement ticket 42' "$FAKE_GH/prompt-1.txt" && ! grep -q 'Implement ticket 42' "$FAKE_GH/args-1.txt" && ok "(q12) the prompt arrives on stdin, never as an argument" || bad "(q12) the prompt rode argv or never arrived"
fixture q4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-oldblock" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\n\\n<!-- pipeline-cost-block -->\\nold block line\\nCache-hit rate: 50%%\\n\\nKEEP THIS LINE\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-oldblock"; RUN_GH="$T/bin/gh-oldblock" run_case "$d"; expect approved "(q4) run against a PR carrying the OLD lane's cost block"
grep -q 'KEEP THIS LINE' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && ok "(q4) old block replaced up to its Cache-hit terminator; the body below it survives" || bad "(q4) body strip wrong: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-200)"
fixture q5; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; ( cd "$d/main" && git remote set-url origin /nonexistent ) ; run_case "$d"
# the record push fails first on a dead remote, which is an env refusal; the staleness arm is exercised below via a fetch that fails mid-run
[ "$RC" -eq 2 ] && ok "(q5) dead remote is an environment refusal, not a pass" || bad "(q5) dead remote exit $RC ($TERM_SLUG)"
FIXTURE_CONFIG='{"tracker":{"type":"jira","writes":false,"branchPrefix":"jdoe/","keyPattern":"[a-z]+-[0-9]+"},"paths":{"plansDir":"docs/plans"}}' fixture q6
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/pipeline-state/42-ledger.md" "$d/main/.claude/pipeline-state/gh-42-ledger.md"
OUT="$( cd "$d/main" && bash "$RUN" gh-42 --build-model opus 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "(q6) jira run with a key that matches keyPattern"
grep -q 'mcp__atlassian' "$FAKE_GH/args-1.txt" && grep -q 'mcp__plugin_atlassian_atlassian' "$FAKE_GH/args-1.txt" && grep -q 'mcp__claude_ai_Atlassian_Rovo' "$FAKE_GH/args-1.txt" && grep -q 'mcp__atlassian__editJiraIssue' "$FAKE_GH/args-1.txt" && ok "(q6) jira build may READ the tracker (server allowed) while writes stay disallowed" || bad "(q6) jira allowlist wrong"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"maxRounds":1,"costCeilingUsd":0.5}}' fixture q7
printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect cost-spent "(q7) config run.costCeilingUsd honored"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":null,"typecheck":null,"test":null,"allowUnverified":true}}}' fixture q8 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(q8) zero checks pass only when allowUnverified is declared"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","extraLanes":[{"name":"e2e","when":["src/**"],"commands":["false"]},{"name":"docs","when":["docs/**"],"commands":["false"]}]}}}' fixture q9 ""
printf 'build-delete-test\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
grep -q 'RED: false' "$(SD)/checks-1.1.log" && [ "$(grep -c 'false' "$(SD)/checks-1.1.log")" = 1 ] && ok "(q9) extraLanes run only when a changed file matches their when-globs (src/ matched, docs/ did not)" || bad "(q9) when-globs wrong: $(grep -c false "$(SD)/checks-1.1.log") false lanes ran"
fixture q10; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --build-model opus --review-model opus; expect approved "(q10) opus/sonnet short forms accepted; opus review needs no basis"
FIXTURE_CONFIG='{"tracker":{"type":"gitlab","branchPrefix":"x/"},"paths":{"plansDir":"docs/plans"}}' fixture q11; run_case "$d"; expect env-tracker-type "(q11) an unknown tracker.type is refused, never the quieter arm"

# (r) round-three parity: marker read is a checked match and body-anchored, lanes[] setup steps,
#     -h, explicit --max-rounds beats config, SEAM_SCRUB on lane commands, the config reaches a session as a copy
fixture r1; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
jq '. + [{body:"someone wrote: the marker is <!-- stage: lean-claimed --> in the old lane",created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"
run_case "$d"; expect claimed-elsewhere "(r1) a comment merely quoting the marker inline does not re-enter"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","commands":["false"]}],"lint":"true"}}}' fixture r2 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(r2) lanes[] setup steps run and gate"
[ "$(sed -n '1p' "$(SD)/checks-1.1.log")" = "RED (setup, aborting the rest): false" ] && ok "(r2) setup lane ran FIRST" || bad "(r2) order wrong: $(head -2 "$(SD)/checks-1.1.log" | tr '\n' '|')"
fixture r3; OUT="$( cd "$d/main" && bash "$RUN" -h 2>&1 )"; RC=$?; [ "$RC" -eq 0 ] && grep -q '^# usage: run.sh' <<<"$OUT" && ! grep -q '^terminal: ' <<<"$OUT" && ok "(r3) [A12] -h prints usage, exits 0, no terminal line" || bad "(r3) -h exit $RC"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"run":{"maxRounds":1}}' fixture r4
printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 3; expect approved "(r4) an explicit --max-rounds 3 beats config run.maxRounds 1"
# shellcheck disable=SC2016  # the check line is meant to expand in the lane, not here
fixture r5 '- test -z "${SECOND_SHIFT_CONFIG:-}"'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(r5) lane commands run with the config seam scrubbed"
cfgdir="$(cd "$(dirname "$SECOND_SHIFT_CONFIG")" && pwd)"
! grep -A1 -x -- '--add-dir' "$FAKE_GH/args-1.txt" | grep -qxF -- "$cfgdir" && ok "(r5) no session is granted the config's directory (the main checkout's .claude/, where \$STATE and every receipt live)" || bad "(r5) $cfgdir is in the BUILD's --add-dir"
case "$(cat "$FAKE_GH/config-path-1.txt")" in *-scratch.*/second-shift.config.json) cmp -s "$FAKE_GH/config-seen-1.json" "$SECOND_SHIFT_CONFIG" && ok "(r5) the session reads the config from a copy in its scratch dir" || bad "(r5) the session's copy differs from the config" ;;
  *) bad "(r5) the session's SECOND_SHIFT_CONFIG is not a copy in its scratch dir: $(cat "$FAKE_GH/config-path-1.txt")" ;; esac
# (r6) a build that rewrites the config, the main checkout's and its own copy, changes neither the checks the run then
#      runs nor the config the review after it reads: run.sh holds the launch-time read
R6CFG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"commands\":{\"main\":{\"lint\":\"touch $T/r6/gh/launch-lint-ran\"}}}"
FIXTURE_CONFIG="$R6CFG" fixture r6 ""; printf '%s\n' "$R6CFG" > "$d/launch-config.json"
printf 'build-edit-config\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(r6) a build that edits the config mid-run"
[ -f "$FAKE_GH/launch-lint-ran" ] && [ ! -e "$FAKE_GH/edited-lint-ran" ] && ok "(r6) the checks are the launch config's, not the edited file's" || bad "(r6) checks after the edit: launch lint $([ -f "$FAKE_GH/launch-lint-ran" ] && echo ran || echo 'did not run'), edited lint $([ -e "$FAKE_GH/edited-lint-ran" ] && echo ran || echo 'did not run')"
cmp -s "$FAKE_GH/config-seen-2.json" "$d/launch-config.json" && ok "(r6) the review reads the launch config, not the build's edit of its copy" || bad "(r6) the review read: $(tr -d '\n' < "$FAKE_GH/config-seen-2.json" 2>/dev/null)"

# (s) round-four parity: setup lanes fail fast, malformed lanes fail loudly, usage slugs, the full seam scrub
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","commands":["false"]}],"lint":"echo LINT-RAN"}}}' fixture s1 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(s1) a red setup lane"
! grep -q 'LINT-RAN' "$(SD)/checks-1.1.log" && grep -q 'aborting the rest' "$(SD)/checks-1.1.log" && ok "(s1) setup lane failure aborts before lint runs (fail-fast)" || bad "(s1) lint ran after a red setup lane"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup"}],"lint":"true"}}}' fixture s2 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-config-lanes "(s2) a lane with no commands fails loudly, never silently contributes nothing"
[ "$RC" -eq 2 ] && ok "(s2) exits 2" || bad "(s2) exit $RC"
[ ! -f "$FAKE_GH/calls" ] && ok "(s2) refused before any build was spawned" || bad "(s2) a build was spawned on a malformed config"
fixture s3; OUT="$( cd "$d/main" && bash "$RUN" 42 --bogus 2>&1 )"; RC=$?; grep -q '^terminal: usage-unknown-option$' <<<"$OUT" && [ "$RC" -eq 2 ] && ok "(s3) usage refusals carry their slug line" || bad "(s3) no usage slug (rc=$RC)"
# shellcheck disable=SC2016  # the check line expands in the lane, not here
fixture s4 '- test -z "${BRANCH_PREFIX:-}${KEY_PATTERN:-}${SECOND_SHIFT_REPO_ROOT:-}"'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; BRANCH_PREFIX=leak KEY_PATTERN=leak SECOND_SHIFT_REPO_ROOT=leak run_case "$d"; expect approved "(s4) the gate's full seam list is scrubbed from lane commands"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
