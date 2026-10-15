#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-record-selftest.sh — run.sh scenario slice: the design section, the committed record, the
# receipt lint, stale refs.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-record-selftest] the design section, the committed record, the receipt lint, stale refs"

# (z) round-twelve parity: the design SECTION is what arms and disarms, in the gate's forms; a read
#     remote is never blamed on the build; the cap is a bound; blocker labels with spaces; exit codes
PX="cp $T/px.png {out}"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"$PX\",\"smokeCommand\":\"true\"}}}" fixture z1 "- true" $'\n## Design\n\nHandoff: x\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z1) rows under the spec form '## Design' arm the smoke too"
grep -q 'smoke-RS-1' <<<"$OUT" || [ -f "$(SD)/smoke-RS-1.png" ] && ok "(z1) the render ran" || bad "(z1) no render"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z2 "- true" $'\n## Design\n\nDesign: none\n'
run_case "$d"; expect env-design-undeclared "(z2) a disarm without a reason is refused, as the gate refused it"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z3 "- true" $'\n## Notes\n\nDesign: none — quoted in prose, not the design section\n'
run_case "$d"; expect env-design-undeclared "(z3) a 'Design: none' outside the design section does not disarm"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture z4 "- true" $'\n## Design\n\n   Design:   NONE — an indented disarm with a reason, any case\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z4) the gate's indented, case-insensitive disarm form is accepted"
port=$(( 20000 + RANDOM % 20000 )); ( cd "$T" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & hs=$!
until curl -s -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; do sleep 0.2; done
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"$PX\",\"smokeCommand\":\"true\",\"readyProbe\":\"http://127.0.0.1:$port/\"}}}" fixture z5 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(z5) a readyProbe that answers 200 is ready"
kill "$hs" 2>/dev/null; wait "$hs" 2>/dev/null
fixture z6; printf 'build-stubborn\n' > "$FAKE_CLAUDE_PLAN"; s0=$(date +%s); RUN_BUILD_TIMEOUT=2 run_case "$d"; el=$(( $(date +%s) - s0 )); expect build-blocked "(z6) a TERM-ignoring session is stopped at its cap"
[ "$el" -lt 40 ] && ok "(z6) the cap is a bound (${el}s, KILL after TERM)" || bad "(z6) waited ${el}s"
sleep 1; if pgrep -f "$T/bin/claude" >/dev/null 2>&1; then bad "(z6) the stubborn session survived the KILL"; pkill -KILL -f "$T/bin/claude" 2>/dev/null; else ok "(z6) the stubborn session is dead"; fi
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"blockers":["needs design review"]}},"paths":{"plansDir":"docs/plans"}}' fixture z7
printf 'ready-for-dev\nopus\nneeds design review\n' > "$FAKE_GH/labels"; run_case "$d"; expect not-queued "(z7) a blocker label containing spaces blocks pickup"
fixture z8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-remote-dead" <<EOF
#!/usr/bin/env bash
exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-remote-dead"
( cd "$d/main" && git remote set-url origin /nonexistent-remote ) ; run_case "$d"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != build-inflight ] && ok "(z8) an unreadable remote is a refusal ($TERM_SLUG), never blamed on the build" || bad "(z8) got $TERM_SLUG rc=$RC"
fixture z9; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; [ "$RC" -eq 4 ] && ok "(z9) rounds-spent exits 4" || bad "(z9) exit $RC"
fixture z10 "- false"; printf 'build-pr\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; [ "$RC" -eq 4 ] && ok "(z10) checks-red-spent exits 4" || bad "(z10) exit $RC"
fixture z11; printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; [ "$RC" -eq 1 ] && ok "(z11) build-no-pr exits 1" || bad "(z11) exit $RC"
# (z12) #973 D-1: a commit not on origin, on a clean tree, re-spawns the build to push it; the next prompt says so and lists the denials
fixture z12; printf 'build-pr\nreview-needs-work\nbuild-commit-nopush\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(z12) #973 D-1: a commit left unpushed on a clean tree is pushed by a re-spawned build"
grep -q 'build: exited 0 with 1 commit(s) not on origin/second-shift/42 on a clean tree' <<<"$OUT" && grep -q 'push red — the findings are the log; another BUILD attempt of round 2' <<<"$OUT" \
  && ok "(z12) #973 S-3: the run says why it re-spawned, on the checks-red counter" || bad "(z12) #973 S-3: $(grep -E 'build: exited|push red' <<<"$OUT" | tr '\n' '|')"
grep -q 'these commits are not on origin/second-shift/42' "$FAKE_GH/prompt-4.txt" && grep -q 'local only 3' "$FAKE_GH/prompt-4.txt" \
  && grep -q 'Push second-shift/42 to origin and, unless one is already open for this branch, open the draft PR' "$FAKE_GH/prompt-4.txt" \
  && grep -qE '^Build session permission denials \(.*/denials-2\.2\.txt\):$' "$FAKE_GH/prompt-4.txt" && grep -q '^Bash {"command":"ls /"}$' "$FAKE_GH/prompt-4.txt" \
  && ok "(z12) #973 S-2: the re-spawned build reads the unpushed commit, the push and draft-PR instruction, and the denials" || bad "(z12) #973 S-2: prompt-4 lacks the push log: $(sed -n '/^## Red check output/,$p' "$FAKE_GH/prompt-4.txt" | tr '\n' '|' | cut -c1-400)"
grep -q 'verdict: needs-work' "$FAKE_GH/prompt-4.txt" && ok "(z12) the push retry still carries the review's findings" || bad "(z12) the push retry dropped the review's findings"
grep -q 'local only 3' <<<"$(git -C "$d/origin.git" log --format=%s second-shift/42)" && ok "(z12) [E21] the once-unpushed commit reached origin" || bad "(z12) [E21] the unpushed commit never reached origin"
# (z12b) #973 D-5(4): a build that keeps leaving its commits unpushed spends the checks-red counter, and nothing discards them
fixture z12b; printf 'build-commit-nopush\nbuild-commit-nopush\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"
expect checks-red-spent "(z12b) two clean-tree unpushed exits"
[ "$RC" -eq 4 ] && grep -q 'push red 2 times' <<<"$OUT" && ok "(z12b) checks-red-spent exits 4 and names the push" || bad "(z12b) rc=$RC: $(grep 'terminal: checks-red-spent' <<<"$OUT")"
[ "$(git -C "$d/wt/42" log --oneline origin/second-shift/42..HEAD 2>/dev/null | grep -c .)" -eq 2 ] && ok "(z12b) [E21] both unpushed commits are still there" || bad "(z12b) [E21] the unpushed commits were reset away"

# (aa) round-thirteen parity: the committed record is what the design guard reads; a remote dying
#      mid-run and an unreadable tracker at verdict time are environment refusals
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture aa1 "- true" $'\n## Design\n\nDesign: none — first run\n'
printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(aa1) first run, committed with Design: none"
# the receipt on disk is now DELETED and replaced by one with no design section at all: a resume must
# read only the committed record (declared, none-with-reason) and never the receipt
printf '# record\n\n## Checks\n\n- true\n' > "$d/main/.claude/pipeline-state/42-ledger.md"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume reads the committed record, not a receipt that now says nothing"
grep -q 'receipt on disk is not consulted' <<<"$OUT" && ok "(aa1) the receipt was not consulted on resume" || bad "(aa1) the receipt was read on resume"
# #1022 AC-5: that receipt fails the lint, and the resume neither lints nor refuses it
bash "$IT_ROOT/skills/plan-interview/tools/ledger-lint.sh" --receipt "$d/main/.claude/pipeline-state/42-ledger.md" >/dev/null 2>&1; lrc=$?
[ "$lrc" -eq 1 ] && ! grep -q '\[run\] receipt: ' <<<"$OUT" && ok "(aa1) #1022 AC-5: a committed record's failing disk receipt is not linted" || bad "(aa1) #1022 AC-5: lint rc=$lrc, log: $(grep 'receipt: ' <<<"$OUT" | head -n 2)"
rm -f "$d/main/.claude/pipeline-state/42-ledger.md"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(aa1) a resume with NO receipt on disk still runs (an absent ledger is not an error once the record is committed)"
fixture aa2; printf 'build-kill-remote\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-remote-unreadable "(aa2) a remote that dies after the build is a refusal, not 'the head did not move'"
[ "$RC" -eq 2 ] && ok "(aa2) exits 2" || bad "(aa2) exit $RC"
fixture aa3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-comments-dead" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ] && [[ "\$2" == *comments* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-comments-dead"; RUN_GH="$T/bin/gh-comments-dead" run_case "$d"; expect env-tracker-unreadable "(aa3) an unreadable comment listing at verdict time is an environment refusal, not review-unbound"

# (ab) round-fourteen parity: the gate's heading rule
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab1 "- true" $'\n### DESIGN\n\nDesign: none — depth three, upper case\n\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ab1) the FIRST design section decides (disarmed), a later one does not merge into it; any depth, any case"
grep -q 'arms no render state' <<<"$OUT" && ok "(ab1) not armed" || bad "(ab1) the second section leaked"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true"}}}' fixture ab2 "- true" $'\n## Design notes\n\nDesign: none — a heading with trailing words is not the design section\n'
run_case "$d"; expect env-design-undeclared "(ab2) '## Design notes' is not the design section"

# (rl) #1022: a receipt from disk is linted before the claim, by the ENABLED intake-toolkit's lint
untouched() { [ "$(tr '\n' ' ' < "$FAKE_GH/labels")" = "ready-for-dev opus " ] && [ ! -e "$FAKE_GH/issue-comments" ] && [ ! -e "$FAKE_GH/calls" ] && [ ! -d "$d/wt/42" ]; }
# (rl1) AC-4: a v3 receipt with no '## Intake steps' — refused before the claim, exit 3, the violation and the rerun printed
fixture rl1; REC="$d/main/.claude/pipeline-state/42-ledger.md"
awk '/^## Intake steps/ {skip = 1; next} skip && /^## / {skip = 0} !skip' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC"
run_case "$d"; expect env-receipt-invalid "(rl1) a v3 receipt with no Intake steps"
[ "$RC" -eq 3 ] && ok "(rl1) env-receipt-invalid exits 3 (resumable)" || bad "(rl1) exit $RC"
grep -q '\[run\] receipt: ledger-lint: VIOLATION: missing mandated receipt section: Intake steps' <<<"$OUT" && grep -q 'rerun /intake-toolkit:intake 42' <<<"$OUT" && ! grep -q 'intake-toolkit:plan-interview' <<<"$OUT" \
  && ok "(rl1) the refusal prints the violation and 'rerun /intake-toolkit:intake 42' (#1023 AC-13)" || bad "(rl1) output: $(grep -E 'receipt: |rerun' <<<"$OUT" | tr '\n' '|')"
untouched && ok "(rl1) refused before the claim: no label changed, nothing posted, nothing spawned" || bad "(rl1) labels: $(tr '\n' ' ' < "$FAKE_GH/labels")"
# (rl1b) D-12: the receipt shape written before #1022 (a 4-column ledger and Checks, the old fixture) is refused the same way
fixture rl1b; printf '# record\n\n## Decision Ledger\n\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | a | b | user-answered |\n\n## Checks\n\n- true\n' > "$d/main/.claude/pipeline-state/42-ledger.md"
run_case "$d"; expect env-receipt-invalid "(rl1b) a pre-#1022 receipt shape"
# (rl2) AC-6: an override naming no lint, a lint that is not this lint's version probe, one that knows too few versions,
# and one whose --receipt answers with neither 0 nor 1 — each exits 2 under env-receipt-lint-unavailable, before the claim
stub_lint() { # stub_lint <name> <script body> -> prints the stub plugin root
  mkdir -p "$T/stub-$1/skills/plan-interview/tools"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/stub-$1/skills/plan-interview/tools/ledger-lint.sh"; printf '%s' "$T/stub-$1"
}
rl_unavailable() { # rl_unavailable <label> <toolkit root> <detail fragment>
  fixture "rl2-$1"; SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="$2" run_case "$d"; expect env-receipt-lint-unavailable "(rl2) $1"
  [ "$RC" -eq 2 ] && grep -qF -- "$3" <<<"$OUT" && untouched && ok "(rl2) $1: exits 2 before the claim, naming why" || bad "(rl2) $1: rc=$RC $(grep 'terminal: env-receipt' <<<"$OUT")"
}
# shellcheck disable=SC2016  # the stub bodies expand in the stub, not here
{
rl_unavailable no-lint "$T/no-such-toolkit" "SECOND_SHIFT_INTAKE_TOOLKIT_ROOT names $T/no-such-toolkit, which has no skills/plan-interview/tools/ledger-lint.sh"
rl_unavailable pre-versions "$(stub_lint old 'echo "ledger-lint: unknown option: $1" >&2; exit 2')" '--receipt-version exited 2'
rl_unavailable knows-v1 "$(stub_lint v1 '[ "$1" = --receipt-version ] && { echo 1; exit 0; }; exit 0')" 'the receipt is v3 but'
rl_unavailable knows-v2 "$(stub_lint v2 '[ "$1" = --receipt-version ] && { echo 2; exit 0; }; exit 0')" 'the receipt is v3 but'
rl_unavailable rc-127 "$(stub_lint crash '[ "$1" = --receipt-version ] && { echo 3; exit 0; }; nosuchcommand-in-the-lint')" '--receipt exited 127, which is no verdict on the receipt'
}
# (rl3) AC-11: a receipt above every version the lint knows is refused by name, and never read as a pass
fixture rl3; REC="$d/main/.claude/pipeline-state/42-ledger.md"; sed 's/^Receipt: v3$/Receipt: v99/' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC"
run_case "$d"; expect env-receipt-lint-unavailable "(rl3) a v99 receipt"
grep -q 'the receipt is v99 but .* knows receipts up to v' <<<"$OUT" && untouched && ok "(rl3) the refusal names both versions, before the claim" || bad "(rl3) $(grep 'terminal: env-receipt' <<<"$OUT")"
# (rl4) AC-13: with no override the lint comes from the ENABLED intake-toolkit record in `claude plugin list --json`, in an
# install-cache layout — never the newer leftover beside it, a disabled record, or a project record for another checkout.
# The list's shape (id, version, scope, enabled, installPath, projectPath) is the one doctor reads, recorded in
# plugins/second-shift/skills/doctor/tools/doctor-fixtures/plugin-list-*.json
cat > "$T/bin/claude-plugins" <<EOF
#!/usr/bin/env bash
# answers 'plugin list --json' from \$FAKE_PLUGIN_LIST (absent: the command fails); every other call goes to the fake claude
if [ "\$1 \$2" = "plugin list" ]; then echo "\$*" >> "\$FAKE_GH/plugin-calls"; [ -f "\${FAKE_PLUGIN_LIST:-}" ] && cat "\$FAKE_PLUGIN_LIST"; exit \$?; fi
exec "$T/bin/claude" "\$@"
EOF
chmod +x "$T/bin/claude-plugins"
mkdir -p "$T/cache/intake-toolkit"; cp -R "$IT_ROOT" "$T/cache/intake-toolkit/1.0.0"
# shellcheck disable=SC2016  # the stub body expands in the stub, not here
stub_lint leftover '[ "$1" = --receipt-version ] && { echo 99; exit 0; }; echo "ledger-lint: VIOLATION: the leftover lint ran" >&2; exit 1' >/dev/null
mkdir -p "$T/cache/intake-toolkit/9.9.9"; cp -R "$T/stub-leftover/." "$T/cache/intake-toolkit/9.9.9/"
plugin_list() { # plugin_list <enabled record's enabled value> -> $FAKE_PLUGIN_LIST for the current fixture
  local main; main="$(git -C "$d/main" rev-parse --show-toplevel)"
  jq -n --arg c "$T/cache/intake-toolkit" --arg main "$main" --argjson on "$1" '[
    {id: "intake-toolkit@second-shift", version: "9.9.9", scope: "project", enabled: false, installPath: ($c + "/9.9.9"), projectPath: $main, lastUpdated: "2026-10-01T00:00:00Z"},
    {id: "intake-toolkit@second-shift", version: "9.9.9", scope: "project", enabled: true, installPath: ($c + "/9.9.9"), projectPath: "/elsewhere", lastUpdated: "2026-10-02T00:00:00Z"},
    {id: "intake-toolkit@second-shift", version: "1.0.0", scope: "user", enabled: $on, installPath: ($c + "/1.0.0"), lastUpdated: "2026-01-01T00:00:00Z"},
    {id: "dev-pipeline@second-shift", version: "1.0.0", scope: "user", enabled: true, installPath: "/nowhere"}]' > "$d/plugins.json"
  export FAKE_PLUGIN_LIST="$d/plugins.json"
}
fixture rl4; plugin_list true; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect approved "(rl4) the enabled intake-toolkit's lint passes the receipt"
grep -qF "receipt: v3, lints clean ($T/cache/intake-toolkit/1.0.0/skills/plan-interview/tools/ledger-lint.sh)" <<<"$OUT" && grep -qx 'plugin list --json' "$FAKE_GH/plugin-calls" \
  && ok "(rl4) the lint run is the enabled 1.0.0, read from 'claude plugin list --json'" || bad "(rl4) $(grep -E 'receipt: |leftover' <<<"$OUT" | tr '\n' '|')"
fixture rl5; plugin_list false
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect env-receipt-lint-unavailable "(rl5) no enabled intake-toolkit applies to this checkout"
grep -q 'lists no enabled intake-toolkit for ' <<<"$OUT" && untouched && ok "(rl5) a disabled record and another checkout's are not used" || bad "(rl5) $(grep 'terminal: env-receipt' <<<"$OUT")"
fixture rl6; unset FAKE_PLUGIN_LIST
SECOND_SHIFT_INTAKE_TOOLKIT_ROOT="" RUN_CLAUDE="$T/bin/claude-plugins" run_case "$d"; expect env-receipt-lint-unavailable "(rl6) 'claude plugin list --json' fails"
grep -q "plugin list --json' failed" <<<"$OUT" && untouched && ok "(rl6) a failed plugin list is a refusal, not a pass" || bad "(rl6) $(grep 'terminal: env-receipt' <<<"$OUT")"

# (ac) round-fifteen parity: [] blockers, github key shape, a detached worktree after review, no ambient model seam
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","labels":{"blockers":[]}},"paths":{"plansDir":"docs/plans"}}' fixture ac1
printf 'ready-for-dev\nopus\nepic\n' > "$FAKE_GH/labels"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ac1) blockers: [] means no blocker labels, so epic does not block"
fixture ac2; OUT="$( cd "$d/main" && bash "$RUN" 0042 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; expect usage-key "(ac2) a zero-padded github key is refused, as the gate refused it"
fixture ac3; printf 'build-pr\nreview-detach\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ac3) a review that left the worktree detached does not make the next build read as inflight"
fixture ac4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_MODEL=claude-sonnet-5 RUN_ID=ambient-run-id run_case "$d"; grep -q 'models: build opus (label)' <<<"$OUT" && ok "(ac4) an ambient RUN_MODEL does not override the ticket's label" || bad "(ac4) RUN_MODEL leaked"
[ ! -d "$d/main/.claude/pipeline-state/run-42/ambient-run-id" ] && ! grep -q 'run_id: ambient-run-id' "$FAKE_GH/issue-comments" && ok "(ac4) [A26] an ambient RUN_ID never keys the run's records" || bad "(ac4) [A26] ambient RUN_ID leaked"

# (ad) round-sixteen parity: a run that ends with the worktree detached (a review checked out the head) can be resumed
fixture ad1; printf 'build-pr\nreview-detach\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(ad1) first run ends after a detaching review"
[ "$(git -C "$d/wt/42" rev-parse --abbrev-ref HEAD)" = HEAD ] && ok "(ad1) the worktree is left detached, as a review may leave it" || bad "(ad1) fixture did not detach"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(ad1) the resume repairs a detached worktree instead of refusing it as 'another branch'"

fixture ad2; mkdir -p "$d/wt"; git -C "$d/main" worktree add -q -b other "$d/wt/42" origin/main; run_case "$d"; expect env-worktree-mismatch "(ad2) a worktree on a DIFFERENT named branch is still refused"

# (ae) #1024: whether the record is committed is asked of origin, never read off a stale local ref
stale_record() { # a branch carrying an OLD record, pushed and then deleted upstream: $d/main keeps only origin/second-shift/42
  git -C "$d/main" checkout -q -b second-shift/42; mkdir -p "$d/main/docs/plans"
  printf '# stale record\n\n| D-9 | stale | stale | user-answered |\n' > "$d/main/docs/plans/main-42-decisions.md"
  git -C "$d/main" add docs/plans && git -C "$d/main" commit -qm "docs: stale record" && git -C "$d/main" push -q origin second-shift/42 2>/dev/null
  git -C "$d/main" checkout -q main && git -C "$d/main" branch -q -D second-shift/42 && git -C "$d/origin.git" update-ref -d refs/heads/second-shift/42
  git -C "$d/main" cat-file -e refs/remotes/origin/second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null || bad "($1) fixture: no stale tracking ref carrying a record"
}
nothing_written() { [ "$RC" -eq 2 ] && grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -s "$FAKE_GH/issue-comments" ] && [ ! -f "$FAKE_GH/calls" ] && ok "($1) exits 2 before the claim: nothing written, nothing spawned" || bad "($1) rc=$RC labels: $(tr '\n' ' ' < "$FAKE_GH/labels") calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"; }
# (ae1) AC-2: origin reachable, the branch deleted upstream: the stale ref is dropped and the receipt is what the branch carries
fixture ae1; stale_record ae1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(ae1) [AC-2] a branch deleted upstream reads the receipt, not the stale tracking ref"
! grep -q 'already committed' <<<"$OUT" && grep -q 'record: origin has no second-shift/42 — deleted the stale tracking ref origin/second-shift/42' <<<"$OUT" \
  && ok "(ae1) [D-2] the stale tracking ref is deleted and the run log says so" || bad "(ae1) record lines: $(grep 'record:' <<<"$OUT" | tr '\n' '|')"
ae1_rec="$(git -C "$d/origin.git" show second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null)"
[ "$(git -C "$d/origin.git" log --format=%s --reverse main..second-shift/42 | head -n 1)" = "docs: decision record for #42" ] && grep -qF '| D-1 | a | b | user-answered |' <<<"$ae1_rec" \
  && ok "(ae1) the branch is cut fresh from the base and carries the receipt" || bad "(ae1) branch: $(git -C "$d/origin.git" log --oneline main..second-shift/42 2>&1 | tr '\n' '|')"
# (ae2) AC-1: origin unreachable: refused before the claim, and the stale ref holding a record is not read
fixture ae2; stale_record ae2; git -C "$d/main" remote set-url origin "$d/nonexistent.git"; run_case "$d"; expect env-remote-unreadable "(ae2) [AC-1] an unreachable origin refuses"
grep -q 'cannot reach origin to read second-shift/42 — whether the record is already committed is unknown, so neither it nor the receipt is read' <<<"$OUT" && ! grep -q 'already committed on' <<<"$OUT" \
  && ok "(ae2) [D-4] the refusal says the record's state is unknown; the stale ref is not read" || bad "(ae2) $(grep -E 'record:|terminal:' <<<"$OUT" | tr '\n' '|')"
nothing_written ae2
# (ae3) D-3: a local branch origin does not have is unpushed work: refused, kept
fixture ae3; git -C "$d/main" branch -q second-shift/42 main; run_case "$d"; expect env-branch-unpushed "(ae3) [D-3] a local branch origin lacks is refused"
grep -q 'origin has no second-shift/42, but there is a local branch second-shift/42 — push it (git push -u origin second-shift/42) to resume it, or remove the worktree and the branch' <<<"$OUT" \
  && git -C "$d/main" rev-parse -q --verify refs/heads/second-shift/42 >/dev/null && ok "(ae3) the refusal names the branch and both ways out; the branch is kept" || bad "(ae3) $(grep 'terminal: env' <<<"$OUT")"
nothing_written ae3
# (ae4) D-3: so is a detached worktree at $WT
fixture ae4; mkdir -p "$d/wt"; git -C "$d/main" worktree add -q --detach "$d/wt/42" origin/main; run_case "$d"; expect env-branch-unpushed "(ae4) [D-3] a detached worktree for a branch origin lacks is refused"
grep -q "but there is a detached worktree at $d/wt/42" <<<"$OUT" && [ -d "$d/wt/42" ] && ok "(ae4) the refusal names the worktree; it is kept" || bad "(ae4) $(grep 'terminal: env' <<<"$OUT")"
nothing_written ae4
# (ae5) AC-3: a branch on origin carrying the record is read from origin, with no local ref and no receipt to fall back on
fixture ae5; printf 'build-pr\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 1; expect rounds-spent "(ae5) first run commits the record"
git -C "$d/main" worktree remove --force "$d/wt/42"; git -C "$d/main" branch -q -D second-shift/42; git -C "$d/main" update-ref -d refs/remotes/origin/second-shift/42; rm -f "$d/main/.claude/pipeline-state/42-ledger.md"
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect approved "(ae5) [AC-3] the committed record is read off origin"
grep -q 'record: already committed on second-shift/42' <<<"$OUT" && ok "(ae5) the receipt is not consulted" || bad "(ae5) $(grep 'record:' <<<"$OUT")"

# (pc) #1039: the scheduler checks the build's test-first plan covers every AC of the record at FIRST. The receipt is
# the fixture moved to v4 with a Test intent section over non-contiguous ids (AC-1 AC-2 AC-8, AC-2 exempt), so the
# launch's real lint passes it before the run reads it back from the record commit
TI=$'\n## Test intent\n\nACs: AC-1 AC-2 AC-8\n\nAC-1: a duplicate import answers 409\nAC-2: exempt — the README section is prose\nAC-8: the scheduler runs the coverage check\n'
fixture_v4() { # fixture_v4 <case> [test intent section]
  fixture "$1" "- true" "${2-$TI}"; sed 's/^Receipt: v3$/Receipt: v4/' "$d/main/.claude/pipeline-state/42-ledger.md" > "$d/r.tmp" && mv "$d/r.tmp" "$d/main/.claude/pipeline-state/42-ledger.md"
}
PLAN_OK=$'# Plan\n\n## 1. Tests\n\n- [ ] 1.1 duplicate import answers 409 (src/a.spec.ts) [AC-1]\n- [ ] 1.2 the scheduler case (run-selftest.sh) [AC-8]\n\n## 2. Implementation\n\n- [ ] 2.1 the worker (src/a.ts)'
# (pc1) AC-2 / D-6: the plan in the first commit after the record covers every non-exempt AC — the check passes, the run
# goes on to its review, and the log and run block say so with the plan's position
fixture_v4 pc1; printf '%s\n' "$PLAN_OK" > "$FAKE_GH/plan-1.md"; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(pc1) a plan covering AC-1 and AC-8, AC-2 exempt"
grep -q 'receipt: v4, lints clean' <<<"$OUT" && grep -q 'plan coverage: exit 0 — pass — 2 covered, 1 exempt' <<<"$OUT" \
  && grep -q 'plan position: the first commit after the record ([0-9a-f]*) added docs/plans/main-42-plan.md' <<<"$OUT" \
  && ok "(pc1) AC-2: the v4 receipt lints; the coverage passes, logged with the plan's position" || bad "(pc1) $(grep -E 'receipt: |plan ' <<<"$OUT" | tr '\n' '|')"
grep -qE '^plan coverage at [0-9a-f]{40}: pass — 2 covered, 1 exempt$' "$FAKE_GH/pr-body.md" && grep -q '^plan position: the first commit after the record' "$FAKE_GH/pr-body.md" \
  && ok "(pc1) D-6: the run block carries the result and the position" || bad "(pc1) run block: $(grep -i plan "$FAKE_GH/pr-body.md" | tr '\n' '|')"
grep -q "Your first commit after the record commit [0-9a-f]* is a task plan at docs/plans/main-42-plan.md" "$FAKE_GH/prompt-1.txt" \
  && grep -q "each AC's tagged test proves the behavior its line states" "$FAKE_GH/prompt-1.txt" \
  && ok "(pc1) D-12: the build prompt asks for the plan at its path and for tests that prove each stated behavior" || bad "(pc1) the build prompt has no plan instruction"
grep -q 'fails without the change: not-applicable — no test runner is configured (commands.<id>.testRunners)' <<<"$OUT" \
  && grep -qx 'fails without the change: not-applicable — no test runner is configured (commands.<id>.testRunners)' "$FAKE_GH/pr-body.md" \
  && ok "(pc1) #1040 D-3: with no testRunners the fails-without-the-change check is not-applicable, logged and noted" || bad "(pc1) #1040: $(grep 'without the change' <<<"$OUT" | tr '\n' '|')"
# (pc2) D-7: no plan is a red attempt — the re-spawned build reads why, adds it, and the run goes on; its position is noted
fixture_v4 pc2; printf '%s\n' "$PLAN_OK" > "$FAKE_GH/plan-2.md"; printf 'build-pr\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(pc2) a build with no plan, then one that adds it"
grep -q 'plan coverage red — the findings are the log; another BUILD attempt of round 1' <<<"$OUT" \
  && grep -q 'plan-coverage: RED: no plan — [0-9a-f]*:docs/plans/main-42-plan.md does not exist' <<<"$(sed -n '/^## Red check output/,$p' "$FAKE_GH/prompt-2.txt")" \
  && ok "(pc2) D-7: a missing plan spends a checks-red attempt and the re-spawned build reads why" || bad "(pc2) $(sed -n '/^## Red check output/,$p' "$FAKE_GH/prompt-2.txt" | tr '\n' '|' | cut -c1-400)"
grep -q 'plan position: the first commit after the record ([0-9a-f]*) did not add docs/plans/main-42-plan.md' <<<"$OUT" \
  && ok "(pc2) D-6: a plan added later is noted as not in the first commit after the record, never gated" || bad "(pc2) $(grep 'plan position' <<<"$OUT" | tr '\n' '|')"
# (pc3) AC-3 / AC-5: an uncovered AC and an undefined tag are red, each named — and a build cannot mark the check passed:
# it exempts AC-8 in the head's record and commits an always-pass coverage script; the record at FIRST and the
# installed script decide. A third red would end checks-red-spent; one is the cap here
fixture_v4 pc3; printf '%s\n' '- [ ] 1.1 duplicate import (src/a.spec.ts) [AC-1] [AC-9]' > "$FAKE_GH/plan-1.md"; printf 'build-pr-mark-covered\n' > "$FAKE_CLAUDE_PLAN"
RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "(pc3) a red coverage check on the last checks-red attempt"
grep -q 'terminal: checks-red-spent — plan coverage red 1 times' <<<"$OUT" && grep -q 'plan coverage: exit 1 — RED — 2 problem(s)' <<<"$OUT" \
  && grep -q 'plan-coverage: RED: AC-8 has no test task' "$(SD)/plan-coverage-1.1.log" && grep -q 'plan-coverage: RED: task 1.1 tags AC-9, which the record' "$(SD)/plan-coverage-1.1.log" \
  && ok "(pc3) AC-3 / AC-5: AC-8 uncovered and AC-9 undefined, named, though the head's record exempts AC-8 and carries a passing script" || bad "(pc3) $(grep -E 'plan |terminal' <<<"$OUT" | tr '\n' '|')"
[ "$(cat "$FAKE_GH/calls")" = 1 ] && ok "(pc3) no review was spawned on a red coverage" || bad "(pc3) calls: $(cat "$FAKE_GH/calls")"
# (pc4) AC-4 / D-3: a v3 record carries no Test intent — not-applicable, logged and noted, never red; no plan is asked for
fixture pc4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(pc4) a v3 record"
grep -q 'plan coverage: not-applicable — record v3 carries no Test intent' <<<"$OUT" && grep -qx 'plan coverage: not-applicable — record v3 carries no Test intent' "$FAKE_GH/pr-body.md" \
  && ! grep -q 'task plan at' "$FAKE_GH/prompt-1.txt" \
  && ok "(pc4) D-3: not-applicable is a log line and a run-block note, and the build is not asked for a plan" || bad "(pc4) $(grep 'plan ' <<<"$OUT" | tr '\n' '|')"
# (pc5) AC-4: a ticket with no AC block ('ACs: none — <reason>') is not-applicable, not a pass
fixture_v4 pc5 $'\n## Test intent\n\nACs: none — the ticket has no AC block\n'; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(pc5) 'ACs: none'"
grep -q 'plan coverage: not-applicable — the ticket has no AC block' <<<"$OUT" && ! grep -q 'plan coverage: exit 0' <<<"$OUT" \
  && ok "(pc5) AC-4: no AC block is reported not-applicable, distinct from a pass" || bad "(pc5) $(grep 'plan ' <<<"$OUT" | tr '\n' '|')"
# (pc6) a committed record (never re-linted) whose Test intent has no 'ACs:' line cannot be checked: a human's stop, exit 1
fixture_v4 pc6 $'\n## Test intent\n\nAC-1: a duplicate import answers 409\n'; commit_record; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect plan-coverage-uncheckable "(pc6) a record whose Test intent carries no AC set"
[ "$RC" -eq 1 ] && grep -q "carries 0 'ACs:' lines" <<<"$OUT" && ok "(pc6) exits 1, naming why" || bad "(pc6) rc=$RC $(grep 'terminal:' <<<"$OUT")"

# (fw) #1040: after the checks and the coverage pass, the scheduler applies the head's tagged test files onto the record
# commit's tree and runs each through its configured runner — every one must fail there. The record's four forms: AC-1 a
# behavior (its file is run), AC-2 holds (kept off), AC-3 unchecked (noted, not run), AC-4 exempt. The fixture's worker
# src/a.ts is 'y' at the record commit; each build writes 'fixed' into it with the tests of its tree-<n>
FW_TI=$'\n## Test intent\n\nACs: AC-1 AC-2 AC-3 AC-4\n\nAC-1: the worker writes fixed\nAC-2: holds — the worker file still exists\nAC-3: unchecked — api tier; needs the running app\nAC-4: exempt — the README is prose\n'
FW_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"test":"bash src/b.check.sh","testRunners":[{"when":["*.check.sh"],"command":"bash {file}"}]}}}'
fw_plan() { # fw_plan <call> [AC-1's files] [AC-2's] [AC-3's] -> $FAKE_GH/plan-<call>.md
  printf '# Plan\n\n## 1. Tests\n\n- [ ] 1.1 the worker writes fixed (%s) [AC-1]\n- [ ] 1.2 the worker still exists (%s) [AC-2]\n- [ ] 1.3 the api tier (%s) [AC-3]\n\n## 2. Implementation\n\n- [ ] 2.1 the worker (src/a.ts)\n' \
    "${2:-src/b.check.sh}" "${3:-src/c.check.sh}" "${4:-api/x.api.ts}" > "$FAKE_GH/plan-$1.md"
}
fw_tree() { # fw_tree <call> <src/b.check.sh, AC-1's test> -> $FAKE_GH/tree-<call>: the worker, AC-1's test, AC-2's (passes with or without the change), AC-3's
  local t="$FAKE_GH/tree-$1"; mkdir -p "$t/src" "$t/api"
  echo fixed > "$t/src/a.ts"; printf '%s\n' "$2" > "$t/src/b.check.sh"; echo 'test -f src/a.ts' > "$t/src/c.check.sh"; echo 'it("x", () => {});' > "$t/api/x.api.ts"
}
fw_restored() { # the worktree is back on its branch at the pushed head, nothing tracked left changed, no red-tree mark
  [ "$(git -C "$d/wt/42" rev-parse --abbrev-ref HEAD)" = second-shift/42 ] && [ "$(git -C "$d/wt/42" rev-parse HEAD)" = "$(git -C "$d/origin.git" rev-parse second-shift/42)" ] \
    && [ -z "$(git -C "$d/wt/42" status --porcelain --untracked-files=no)" ] && [ ! -e "$d/main/.claude/pipeline-state/run-42/red-tree" ]
}
# (fw1) AC-6 / D-5: AC-1's test passes on the record commit's tree (it never reads what the change does) — red, the log names
# the AC and the file, and the re-spawned build reads it on the checks-red counter; its stronger test fails there, and the run goes on
FIXTURE_CONFIG="$FW_CONFIG" fixture_v4 fw1 "$FW_TI"; fw_plan 1; fw_tree 1 'test -f src/a.ts'; fw_tree 2 'grep -qx fixed src/a.ts'
printf 'build-pr\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(fw1) a tagged test that passes without the change, then one that fails there"
grep -q "RED: AC-1 — src/b.check.sh passes on the record commit's tree ([0-9a-f]*) with the head's tagged test files applied: it does not fail without the change" "$(SD)/fails-without-1.1.log" \
  && grep -q 'fails without the change red — the findings are the log; another BUILD attempt of round 1' <<<"$OUT" \
  && grep -q "RED: AC-1 — src/b.check.sh passes on the record commit's tree" <<<"$(sed -n '/^## Red check output/,$p' "$FAKE_GH/prompt-2.txt")" \
  && ok "(fw1) AC-6: the passing tagged file is red, naming AC-1 and src/b.check.sh, and the next build reads it" || bad "(fw1) $(grep -E 'fails without|terminal' <<<"$OUT" | tr '\n' '|')"
grep -q "ok: AC-1 — src/b.check.sh fails on the record commit's tree" "$(SD)/fails-without-1.2.log" && [ "$(cat "$FAKE_GH/calls")" = 3 ] \
  && ok "(fw1) D-5: the strengthened test fails there and the run goes on to one review" || bad "(fw1) 1.2: $(tr '\n' '|' < "$(SD)/fails-without-1.2.log" 2>/dev/null)"
# (fw2) AC-7: AC-1's test fails on that tree and passes at the head; AC-2's (holds) would pass there but is kept off; AC-3's
# (unchecked) matches no runner and is noted, not run — the check passes and the run goes on to review
FIXTURE_CONFIG="$FW_CONFIG" fixture_v4 fw2 "$FW_TI"; fw_plan 1; fw_tree 1 'grep -qx fixed src/a.ts'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(fw2) every tagged file not marked holds fails on the record commit's tree, the checks green at the head"
grep -qE "fails without the change: pass — 1 tagged file\(s\) fail on the record commit's tree [0-9a-f]{40}" <<<"$OUT" \
  && grep -q "ok: AC-1 — src/b.check.sh fails on the record commit's tree" "$(SD)/fails-without-1.1.log" && [ "$(cat "$FAKE_GH/calls")" = 2 ] \
  && ok "(fw2) AC-7: the check passes and the run goes on to review" || bad "(fw2) $(grep -E 'fails without|terminal' <<<"$OUT" | tr '\n' '|')"
grep -qE "^fails without the change at [0-9a-f]{40}: pass — 1 tagged file\(s\) fail on the record commit's tree" "$FAKE_GH/pr-body.md" \
  && grep -q '^fails without the change: AC-2 holds — src/c.check.sh is not run for it' "$FAKE_GH/pr-body.md" \
  && grep -q '^fails without the change: AC-3 unchecked — api/x.api.ts is noted, not run' "$FAKE_GH/pr-body.md" \
  && ok "(fw2) S-1: the run block carries the pass and the holds and unchecked notes" || bad "(fw2) run block: $(grep 'without the change' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
grep -q 'every one must fail there' "$FAKE_GH/prompt-1.txt" && ok "(fw2) S-3: the build prompt says each tagged test file must fail without the change" || bad "(fw2) the build prompt has no fails-without-the-change instruction"
grep -q "within its runner's time bound (\*.check.sh: 600s)" "$FAKE_GH/prompt-1.txt" && ok "(fw2) D-22: a runner with no timeoutSeconds is bounded at the 600s default" || bad "(fw2) the build prompt does not state the 600s default bound"
# (fw3) D-11: a tagged file no runner matches, its AC not marked unchecked, and one the head does not carry — each red, named,
# beside the file that did run; D-19: a holds and an unchecked AC tagged on a file the head does not carry are red too, never
# noted as proven; the worktree is back on its branch at the head afterwards
FIXTURE_CONFIG="$FW_CONFIG" fixture_v4 fw3 "$FW_TI"; fw_plan 1 'src/b.check.sh, src/b.spec.ts, src/gone.check.sh' 'src/c.check.sh, src/gone-holds.check.sh' 'api/gone.api.ts'
fw_tree 1 'grep -qx fixed src/a.ts'; echo 'it("y", () => {});' > "$FAKE_GH/tree-1/src/b.spec.ts"
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
expect checks-red-spent "(fw3) a red fails-without-the-change check on the last checks-red attempt"
grep -q 'terminal: checks-red-spent — fails without the change red 1 times' <<<"$OUT" \
  && grep -q 'RED: AC-1 — src/b.spec.ts matches no configured test runner (commands.main.testRunners), and the record does not mark AC-1 unchecked' "$(SD)/fails-without-1.1.log" \
  && grep -q 'RED: AC-1 — src/gone.check.sh does not exist at [0-9a-f]*' "$(SD)/fails-without-1.1.log" && grep -q 'ok: AC-1 — src/b.check.sh fails' "$(SD)/fails-without-1.1.log" \
  && ok "(fw3) D-11: an unmatched and a missing tagged file are red, each named; S-9: the spent detail names the check" || bad "(fw3) $(grep -E 'fails without|terminal' <<<"$OUT" | tr '\n' '|') log: $(tr '\n' '|' < "$(SD)/fails-without-1.1.log")"
grep -q 'RED: AC-2 — src/gone-holds.check.sh does not exist at [0-9a-f]*' "$(SD)/fails-without-1.1.log" && grep -q 'RED: AC-3 — api/gone.api.ts does not exist at [0-9a-f]*' "$(SD)/fails-without-1.1.log" \
  && grep -q 'AC-2 holds — src/c.check.sh is not run for it' "$(SD)/fails-without-1.1.log" && ! grep -qE 'gone-holds.check.sh is not run|gone.api.ts is noted' "$(SD)/fails-without-1.1.log" \
  && ok "(fw3) D-19: a holds and an unchecked AC's missing files are red, not noted" || bad "(fw3) D-19 log: $(tr '\n' '|' < "$(SD)/fails-without-1.1.log")"
fw_restored && ok "(fw3) D-7: the worktree is back on its branch at the head, clean, the red-tree mark gone" || bad "(fw3) worktree: $(git -C "$d/wt/42" status --short --branch | tr '\n' '|')"
# (fw4) D-7: a launch that finds the worktree left on the red tree (the mark, detached at the record commit, a tagged file
# applied — a run killed mid-check) puts it back on the branch before anything else, and the run goes on
first="$(git -C "$d/wt/42" log --format=%H --diff-filter=A -- docs/plans/main-42-decisions.md | tail -n 1)"
git -C "$d/wt/42" checkout -q --detach "$first" && git -C "$d/wt/42" checkout -q second-shift/42 -- src/b.check.sh && printf 'first=%s\n' "$first" > "$d/main/.claude/pipeline-state/run-42/red-tree"
fw_plan 1; printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume
expect approved "(fw4) a resume after a run killed on the red tree"
grep -q "red tree: $d/wt/42 put back on second-shift/42" <<<"$OUT" && ! grep -q 'detached and carries uncommitted work' <<<"$OUT" \
  && ok "(fw4) D-7: the launch restored the branch before anything else" || bad "(fw4) $(grep -E 'red tree|worktree|terminal' <<<"$OUT" | tr '\n' '|')"
# (fw5) N1: a tagged file that hangs on the record commit's tree is red once its runner's timeoutSeconds passes — never counted
# as failing — and the bound reaches the whole process group: a grandchild that ignores TERM is killed before it writes
FW_T='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"test":"bash src/b.check.sh","testRunners":[{"when":["*.check.sh"],"command":"bash {file}","timeoutSeconds":%s}]}}}'
# shellcheck disable=SC2059  # FW_T is the format
FIXTURE_CONFIG="$(printf "$FW_T" 2)" fixture_v4 fw5 "$FW_TI"; fw_plan 1
fw_tree 1 "grep -qx fixed src/a.ts && exit 0
( trap '' TERM; sleep 25; echo leaked > '$d/leak' ) & sleep 40"
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"
t=0; while [ ! -e "$d/leak" ] && [ "$t" -lt 15 ]; do sleep 1; t=$((t+1)); done   # past the grandchild's 25s, had it survived the bound
expect checks-red-spent "(fw5) a tagged file that hangs on the record commit's tree"
grep -qF "RED: AC-1 — testRunners[0] (*.check.sh) did not finish within 2s on the record commit's tree, and its process group was killed — tag a smaller file, or bound the wait inside it — the call covered src/b.check.sh" "$(SD)/fails-without-1.1.log" \
  && ! grep -q 'ok: AC-1' "$(SD)/fails-without-1.1.log" \
  && ok "(fw5) N1 #1053 D-11: past timeoutSeconds the file is red, naming the runner, the bound and the file, never a failure" || bad "(fw5) $(grep -E 'fails without|terminal' <<<"$OUT" | tr '\n' '|') log: $(tr '\n' '|' < "$(SD)/fails-without-1.1.log" 2>/dev/null)"
grep -q "Each file must also finish there within its runner's time bound (\*.check.sh: 2s), or it is red too" "$FAKE_GH/prompt-1.txt" \
  && ok "(fw5) the build prompt states each runner's bound before it writes the tests" || bad "(fw5) the build prompt does not state the bound"
[ ! -e "$d/leak" ] && ok "(fw5) N1: the TERM-ignoring grandchild was killed with the group before it wrote" || bad "(fw5) a grandchild outlived the bound and wrote $d/leak"
fw_restored && ok "(fw5) the worktree is back on its branch after the bound" || bad "(fw5) worktree: $(git -C "$d/wt/42" status --short --branch | tr '\n' '|')"
# (fw6) D-7: a TERM to the run during the check stops it at once — the group is reaped, the EXIT trap puts the worktree
# back on its branch and removes the mark, and the claim stays for a re-launch
# shellcheck disable=SC2059
FIXTURE_CONFIG="$(printf "$FW_T" 60)" fixture_v4 fw6 "$FW_TI"; fw_plan 1; fw_tree 1 'grep -qx fixed src/a.ts && exit 0
sleep 30'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
( cd "$d/main" && exec bash "$RUN" 42 ) > "$d/fw6.out" 2>&1 & rp=$!
t=0; while [ ! -e "$d/main/.claude/pipeline-state/run-42/red-tree" ] && [ "$t" -lt 600 ]; do sleep 0.2; t=$((t+1)); done
sleep 1; kill -TERM "$rp" 2>/dev/null; t=0; while kill -0 "$rp" 2>/dev/null && [ "$t" -lt 100 ]; do sleep 0.2; t=$((t+1)); done
if kill -0 "$rp" 2>/dev/null; then bad "(fw6) the run was still waiting on the hanging file 20s after its TERM"; else ok "(fw6) a TERM during the check ends the run at once"; fi
wait "$rp" 2>/dev/null; grep -q 'terminated; claim left in place' "$d/fw6.out" && fw_restored \
  && ok "(fw6) D-7: the EXIT trap put the worktree back on its branch and removed the mark" || bad "(fw6) $(tail -n 3 "$d/fw6.out" | tr '\n' '|') worktree: $(git -C "$d/wt/42" status --short --branch | tr '\n' '|')"
# (fw7) D-18: the checks leave a tracked change in the worktree — the record commit's tree is not built over it, the run ends
# env-worktree naming the file, and the change is still there
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"test":"bash src/b.check.sh && echo dirt >> src/a.ts","testRunners":[{"when":["*.check.sh"],"command":"bash {file}"}]}}}' \
  fixture_v4 fw7 "$FW_TI"; fw_plan 1; fw_tree 1 'grep -qx fixed src/a.ts'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect env-worktree "(fw7) the checks left a tracked change"
grep -q 'the checks left tracked changes in .* src/a.ts' <<<"$OUT" && grep -qx dirt "$d/wt/42/src/a.ts" && [ ! -e "$d/main/.claude/pipeline-state/run-42/red-tree" ] \
  && [ "$(git -C "$d/wt/42" rev-parse --abbrev-ref HEAD)" = second-shift/42 ] \
  && ok "(fw7) D-18: the change is named and kept, and the worktree never left its branch" || bad "(fw7) $(grep -E 'terminal' <<<"$OUT" | tr '\n' '|')"
# (fw8) D-20: a launch that finds the red tree carrying a change the checkout back would overwrite refuses, keeping the change
# and the mark for a human
first="$(git -C "$d/wt/42" log --format=%H --diff-filter=A -- docs/plans/main-42-decisions.md | tail -n 1)"
git -C "$d/wt/42" checkout -q -- src/a.ts && git -C "$d/wt/42" checkout -q --detach "$first" && echo 'a local edit' > "$d/wt/42/src/a.ts" \
  && printf 'first=%s\n' "$first" > "$d/main/.claude/pipeline-state/run-42/red-tree"
printf 'build-push-only\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume
expect env-worktree "(fw8) a red tree whose checkout back would overwrite a change"
grep -q 'left on the record commit.s tree by an interrupted fails-without-the-change check' <<<"$OUT" && grep -qx 'a local edit' "$d/wt/42/src/a.ts" \
  && [ -e "$d/main/.claude/pipeline-state/run-42/red-tree" ] && [ ! -s "$FAKE_GH/calls" ] \
  && ok "(fw8) D-20: the launch refuses before any build, keeping the change and the mark" || bad "(fw8) $(grep -E 'red tree|terminal' <<<"$OUT" | tr '\n' '|') calls=$(cat "$FAKE_GH/calls")"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
