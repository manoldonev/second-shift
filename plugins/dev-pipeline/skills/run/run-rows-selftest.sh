#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-rows-selftest.sh — run.sh scenario slice: contract-inventory rows: tracker and git read
# failures, close-out, the review input.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-rows-selftest] contract-inventory rows"

# B13 J4: an unreadable tracker MID-RUN is staleness-unreadable, exit 1 (fail closed), never read as OPEN
fixture rd; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-state-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue view" ] && [[ "\$*" == *state* ]]; then n=\$(cat "\$FAKE_GH/state-reads" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "\$FAKE_GH/state-reads"; [ "\$n" -ge 3 ] && exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-state-dies"; RUN_GH="$T/bin/gh-state-dies" run_case "$d"; expect staleness-unreadable "[B13 J4] tracker unreadable before round 2"; [ "$RC" -eq 1 ] && ok "[B13] exit 1" || bad "[B13] exit $RC"

# B16: two open PRs on the head
fixture re; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-two-prs" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "pr list" ]; then printf '7\n8\n'; exit 0; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-two-prs"; RUN_GH="$T/bin/gh-two-prs" run_case "$d"; expect pr-ambiguous "[B16] more than one open PR on the head"; [ "$RC" -eq 1 ] && ok "[B16] exit 1" || bad "[B16] exit $RC"

# C1 C2: an absent config means every default; a present-but-unparseable one is a refusal
fixture rf; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm "$d/main/.claude/second-shift.config.json"
( cd "$d/main" && git push -q origin main:second-shift/41 ) 2>/dev/null   # C7's plurality scan needs one candidate: <prefix><numeric key>
OUT="$( cd "$d/main" && env -u SECOND_SHIFT_CONFIG bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[C1] no config file: github, ready-for-dev, docs/plans, the scanned prefix"
fixture rg; echo '{not json' > "$d/main/.claude/second-shift.config.json"; run_case "$d"; expect env-config-unparseable "[C2] an unparseable config never falls back to defaults"; [ "$RC" -eq 2 ] && ok "[C2] exit 2" || bad "[C2] exit $RC"

# D3: a failed label swap leaves the queue label and stops
fixture rh; cat > "$T/bin/gh-edit-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue edit" ]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-edit-dies"; RUN_GH="$T/bin/gh-edit-dies" run_case "$d"; expect env-claim-failed "[D3] the swap failed"
grep -qx ready-for-dev "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/calls" ] && ok "[D3] queue label intact, nothing spawned" || bad "[D3] labels: $(tr '\n' ' ' < "$FAKE_GH/labels"), calls: $(cat "$FAKE_GH/calls" 2>/dev/null)"

# E12: a PR whose body cannot be read is a tracker read failure — exit 2, never waved through and never blamed on the build
fixture ri; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-prview-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "pr view" ] && [[ "\$*" == *body* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-prview-dies"; RUN_GH="$T/bin/gh-prview-dies" run_case "$d"; expect env-tracker-unreadable "[E12] unreadable PR body"; [ "$RC" -eq 2 ] && ok "[E12] exit 2" || bad "[E12] exit $RC"

# E20 #926: an untracked file the review left at close-out is archived, and the approved worktree is removed
fixture rj; printf 'build-pr\nreview-approve-dirty\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20] the review left an untracked file behind"
toc="$(tar -tf "$(SD)/quarantine-closeout.tar" 2>&1)"
[ "$RC" -eq 0 ] && [ ! -d "$d/wt/42" ] && grep -qx review-scratch.txt <<<"$toc" && ok "[E20] exit 0, the file is in quarantine-closeout.tar and the worktree is removed" || bad "[E20] rc=$RC, worktree $([ -d "$d/wt/42" ] && echo kept || echo gone), archive: $(tr '\n' ' ' <<<"$toc")"

# E20-rd: gitignored runtime data under a declared paths.runtimeData keeps the worktree — `worktree remove` would delete it — and the run still ends approved
FIXTURE_CONFIG="$RTCFG" fixture rt1; printf 'build-pr\nreview-approve-runtime\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] runtime data under a declared path at close-out"
[ "$RC" -eq 0 ] && [ -f "$d/wt/42/.claude/storage/upload-1.bin" ] && printf '%s\n' "$OUT" | grep -q "worktree $d/wt/42 left in place: runtime data under .claude/storage;" && ok "[E20-rd] exit 0, worktree and its data kept, the blocking path printed" || bad "[E20-rd] rc=$RC, data $([ -f "$d/wt/42/.claude/storage/upload-1.bin" ] && echo kept || echo gone): $(printf '%s\n' "$OUT" | grep 'worktree ' | tail -n 1)"
FIXTURE_CONFIG="$RTCFG" fixture rt2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] declared runtime paths that hold nothing"
[ ! -d "$d/wt/42" ] && ok "[E20-rd] an empty declared path does not block removal" || bad "[E20-rd] worktree kept with nothing under the declared paths"
fixture rt3; printf 'build-pr\nreview-approve-runtime\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[E20-rd] no paths.runtimeData declared"
[ ! -d "$d/wt/42" ] && ok "[E20-rd] key absent: close-out removes as before" || bad "[E20-rd] key absent but the worktree was kept"

# F7 F18 H13: Figma servers, the figma-faithful sequence and the render-unavailable rule appear only on a frames ticket
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture rk "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[F7] frames ticket"
grep -q 'mcp__figma' "$FAKE_GH/args-1.txt" && grep -q 'mcp__figma' "$FAKE_GH/args-2.txt" && ok "[F7] Figma servers allowed in both sessions on a frames ticket" || bad "[F7] Figma servers missing"
grep -q 'figma-faithful' "$FAKE_GH/prompt-1.txt" && grep -q 'three rounds per screen' "$FAKE_GH/prompt-1.txt" && ok "[F18] the build prompt carries the figma-faithful sequence" || bad "[F18] sequence missing"
grep -q 'render-unavailable' "$FAKE_GH/prompt-2.txt" && ok "[H13] the review prompt carries the render-unavailable rule" || bad "[H13] rule missing"
# F20: the review session can run review-lead's panel — the fan-out is a Workflow whose agents inherit
# the session's tools, staged into the run's state dir (outside the worktree), after review-toolkit's lint
fixture rpanel; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[F20] panel tools"
ral=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-2.txt" | tail -n 1); bal=$(grep -A1 -x -- '--allowedTools' "$FAKE_GH/args-1.txt" | tail -n 1)
miss=""; for t in Skill Workflow Grep Glob 'Bash(find *)' 'Bash(cp *)' 'Bash(bash *check-review-context.sh*)' 'Bash(gh issue view*)'; do case ",$ral," in *",$t,"*) ;; *) miss="$miss $t" ;; esac; done
[ -z "$miss" ] && ok "[F20] the review allowlist carries every tool the panel dispatch uses" || bad "[F20] review allowlist lacks:$miss"
case ",$bal," in *,Workflow,*) bad "[F20] the build session was given Workflow" ;; *) ok "[F20] the build allowlist is unchanged" ;; esac
sdir=$(grep -A1 -x -- '--add-dir' "$FAKE_GH/args-2.txt" | grep -- '-scratch\.' | head -n 1)
[ -n "$sdir" ] && grep -qF "writing it with Write into $sdir," "$FAKE_GH/prompt-2.txt" && grep -q 'code-review.mjs' "$FAKE_GH/prompt-2.txt" \
  && ok "[F20] #964 D-3: the review's prompt stages code-review.mjs in the run's scratch dir, which it is handed" || bad "[F20] scratch dir '${sdir:-none}' not added to the review, or not named as the staging dir"
case ",$ral," in *",Bash(gh api"*) bad "[F20] the review session may call gh api (it can DELETE)" ;; *) ok "[F20] the review session gets no gh api" ;; esac

# B10: a verdict binds only from a Bot or the account the scheduler writes with — on a public repo anyone can
# comment, and a needs-work body is pasted into the next BUILD prompt
fixture rauth; printf 'build-pr\nreview-approve\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_VERDICT_AUTHOR=stranger run_case "$d"
expect review-unbound "[B10] a verdict posted by a stranger's account"
[ ! -f "$FAKE_GH/prompt-4.txt" ] && ok "[B10] no BUILD spawned on a stranger's verdict" || bad "[B10] a stranger's verdict drove another round"
fixture rauthb; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; FAKE_VERDICT_AUTHOR='second-shift-bot[bot]' FAKE_VERDICT_AUTHOR_TYPE=Bot run_case "$d"
expect approved "[B10] a verdict posted by a Bot account"

# H13: a review that could not render stops the run as env-not-ready; it does not spend a round
fixture rru; printf 'build-pr\nreview-render-unavailable\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect env-not-ready "[H13] verdict: needs-work with reason: render-unavailable"
[ ! -f "$FAKE_GH/prompt-3.txt" ] && ok "[H13] no second BUILD after render-unavailable" || bad "[H13] render-unavailable spent a round"

# C2: an unmigrated v2 config is refused before anything is written, never half-honored (the commands
# key is then the sole key or the main checkout's name, the rule the pre-commit hook applies)
si=0; for stale in '"topology":{"type":"standalone","repos":{"x":{"path":".","baseBranch":"main"}}}' '"stageParams":{"formatGlob":"*"}' '"grillWaivers":{}' '"configVersion":2'; do
  FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"commands\":{\"main\":{\"lint\":null,\"typecheck\":null,\"test\":\"true\"}},$stale}" fixture "rstale$si"; si=$((si + 1))
  printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-config-stale "[C2] v2 config (${stale%%:*})"
  [ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && printf '%s\n' "$OUT" | grep -q 'v2-to-v3.md' && ok "[C2] exit 2, nothing written, the migration doc named (${stale%%:*})" || bad "[C2] rc=$RC, calls=$([ -f "$FAKE_GH/calls" ] && echo yes || echo no) (${stale%%:*})"
done
FIXTURE_CONFIG='{"configVersion":3,"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":null,"typecheck":null,"test":"true"}}}' fixture rv3
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C2] a v3 config runs"

# I14 I16: a session with no result JSON (killed at its bound) is reported unpriced, never as $0
fixture rcost; printf 'build-sleep\n' > "$FAKE_CLAUDE_PLAN"; RUN_BUILD_TIMEOUT=2 run_case "$d"; expect build-blocked "[I16] a build killed at its bound"
grep -q 'unpriced' "$FAKE_GH/issue-comments" && ok "[I16] the closing comment says the run is unpriced" || bad "[I16] a killed session was priced as \$0: $(grep cost_usd "$FAKE_GH/issue-comments" | tail -n 1)"
printf '%s\n' "$OUT" | grep -q 'unpriced' && ok "[I16] the operator is told a session is unpriced" || bad "[I16] nothing said about the unpriced session"
scr="$(sed -n 's/^.* \[run\] scratch: \(.*\) (both sessions.*$/\1/p' <<<"$OUT")"; toc="$(tar -tf "$(SD)/scratch.tar" 2>&1)"
[ -n "$scr" ] && [ ! -e "$scr" ] && grep -qx './probe-1.txt' <<<"$toc" \
  && ok "#964 D-2: a blocked run's scratch dir is archived into \$STATE as evidence and removed" || bad "#964 D-2: blocked run scratch '${scr:-none}'"
fixture rk2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
! grep -q 'mcp__figma' "$FAKE_GH/args-1.txt" && ! grep -q 'figma-faithful' "$FAKE_GH/prompt-1.txt" && ok "[F7 F18] neither on a ticket without frames" || bad "[F7 F18] leaked onto a frames-less ticket"

# H9: two states rendering pixel-identical is red
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"true\"}}}" fixture rl "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | a | empty | 1:3 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H9] two states with identical pixels are red"
grep -qi 'identical' "$(SD)"/smoke-1.1.log 2>/dev/null && ok "[H9] the log names the identical render" || bad "[H9] log: $(head -3 "$(SD)"/smoke-1.1.log 2>/dev/null | tr '\n' '|')"

# H11: frames declared but no render/smoke command configured
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma"}}' fixture rm1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-smoke-unconfigured "[H11] no liveRender.command"; [ "$RC" -eq 2 ] && ok "[H11] exit 2" || bad "[H11] exit $RC"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\"}}}" fixture rm2 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-smoke-unconfigured "[H11] a render command with no smokeCommand"

# I5: with several binding comments the LAST wins
fixture rn; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=needs-work,approve run_case "$d"; expect approved "[I5] needs-work then approve: approve wins"
fixture rn2; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=approve,needs-work run_case "$d" --max-rounds 1; expect rounds-spent "[I5] approve then needs-work: needs-work wins"

# I6 K12: a head that moved under the review unbinds its verdict; a dark review is re-spawned ONCE, no round spent
fixture ro; printf 'build-pr\nreview-approve-and-push\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I6 K12] the second review binds"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && grep -q 'reviewed: ' "$FAKE_GH/prompt-3.txt" && ok "[I6] the approve for the pre-push head was rejected; one review re-spawned, no build" || bad "[I6] calls=$(cat "$FAKE_GH/calls")"
printf '%s\n' "$OUT" | grep -q '1 round' && ok "[K12] the retry spent no round" || bad "[K12] round count wrong"
[ -f "$(SD)/checks-1.1-retry1.log" ] && ok "[I6] the checks re-ran on the moved head before the re-spawn" || bad "[I6] no checks on the moved head: $(cd "$(SD)" && echo checks-*)"
fixture ro2; printf 'build-pr\nreview-silent\nreview-silent\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "[K12] two dark reviews"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && [ "$RC" -eq 5 ] && ok "[K12] exactly one retry, then exit 5" || bad "[K12] calls=$(cat "$FAKE_GH/calls") rc=$RC"

# I10: added skips and an edited CI config reach the review input
fixture rp; printf 'build-skip-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] run"
grep -q 'it.skip' "$(SD)/review-1.1.prompt" && grep -q 'ci.yml' "$(SD)/review-1.1.prompt" && ok "[I10] the added skip and the CI edit are named in the review input" || bad "[I10] not surfaced"
rsec() { awk -v h="### $1" 'index($0, h) == 1 {on=1; next} /^###/{on=0} on && NF' "$(SD)/review-input-1.1.md" 2>/dev/null; }
[ "$(rsec 'Deleted or renamed test files')" = "(none)" ] && [ "$(rsec 'Configured lanes not run')" = "(none)" ] && ok "[I10] #956: the deleted-tests and skipped-lanes sections say (none) when empty" || bad "[I10] #956: deleted=[$(rsec 'Deleted or renamed test files')] lanes=[$(rsec 'Configured lanes not run')]"
[ "$(rsec 'Existing test or snapshot expectations changed')" = "(none)" ] && ok "[I10] #957: lines only added to an existing spec change no expectation: (none)" || bad "[I10] #957: additive section: [$(rsec 'Existing test or snapshot expectations changed')]"
[ "$(rsec 'Review policy edited')" = "(none)" ] && ok "[I10] #1009: a diff that edits no review policy says (none)" || bad "[I10] #1009: policy section: [$(rsec 'Review policy edited')]"

# I10 #1009: head-side edits to the review policy reach the review input: both sides of a rename out of the policy dir,
# the config and context files, and the repo-local agent of a bare reviewers.add[] name only
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"reviewers":{"add":[{"name":"orders-reviewer"},{"name":"pack:billing-reviewer"}]}}' fixture rpol
mkdir -p "$d/main/.claude/second-shift"; echo 'never raw SQL' > "$d/main/.claude/second-shift/security-rules.md"
git -C "$d/main" add -f .claude/second-shift/security-rules.md && git -C "$d/main" commit -qm policy && git -C "$d/main" push -q origin main
printf 'build-edit-policy\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #1009 run"
s="$(rsec 'Review policy edited')"
grep -qxE $'R[0-9]+\t\\.claude/second-shift/security-rules\\.md\tdocs/security-rules\\.md' <<<"$s" && grep -qxF $'A\t.claude/second-shift/review-context.md' <<<"$s" \
  && grep -qxF $'A\t.claude/second-shift.config.json' <<<"$s" && grep -qxF $'A\t.claude/agents/orders-reviewer.md' <<<"$s" && [ "$(grep -c '' <<<"$s")" -eq 4 ] \
  && ok "[I10] #1009: the rename out of the policy dir, the context and config files and the bare reviewers.add[] agent are listed; the pack and unlisted agents are not" || bad "[I10] #1009: policy section: $(tr '\n\t' '| ' <<<"$s")"
grep -q '^### Review policy edited' "$(SD)/review-1.1.prompt" && grep -q "For every file under 'Review policy edited' in the scheduler input below, trace the edit" "$(SD)/review-1.1.prompt" \
  && ok "[I10] #1009: the section and its trace instruction reach the review prompt" || bad "[I10] #1009: not in the review prompt"

# I10 #957: a modified existing spec and a snapshot outside the spec pattern are listed with their removed lines, capped at 20
FIXTURE_FILES="src/b.test.ts src/__snapshots__/price.snap" FIXTURE_BODY="$(for i in $(seq 1 22); do echo "expect(v$i).toBe(1999)"; done)" fixture rp3
printf 'build-edit-expectation\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #957 run"
want="$(echo src/__snapshots__/price.snap; for i in $(seq 1 20); do echo "  -expect(v$i).toBe(1999)"; done; echo '  (… 2 more)'; echo src/b.test.ts; echo '  -expect(v1).toBe(1999)')"
s="$(rsec 'Existing test or snapshot expectations changed')"; [ "$s" = "$want" ] && ok "[I10] #957: the edited assertion and the regenerated snapshot are named with their old expectations; the additive and new specs are not" || bad "[I10] #957: section: $(tr '\n' '|' <<<"$s")"
grep -q '^### Existing test or snapshot expectations changed' "$(SD)/review-1.1.prompt" && ok "[I10] #957: the section reaches the review prompt" || bad "[I10] #957: not in the review prompt"

# I10 #956: the detectors are stack-neutral, and a when-skipped lane is named even when another lane ran
FIXTURE_FILES="tests/test_x.py src/__tests__/b.js pyproject.toml" FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"unit","when":["src/**"],"commands":["true"]},{"name":"docs-lint","when":["docs/**"],"commands":["true"]}]}}}' fixture rp2 ""
printf 'build-polyglot\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[I10] #956 polyglot run"
s="$(rsec 'Deleted or renamed test files')"; grep -qE '^D[[:space:]]+tests/test_x\.py$' <<<"$s" && grep -qE '^D[[:space:]]+src/__tests__/b\.js$' <<<"$s" && ok "[I10] #956: a top-level tests/ and a __tests__/ deletion are listed" || bad "[I10] #956: deleted section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Added skips')"; grep -q '@pytest.mark.skip' <<<"$s" && grep -q 't.Skip("later")' <<<"$s" && ok "[I10] #956: a pytest skip and a Go t.Skip( are listed" || bad "[I10] #956: skips section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'CI or check configuration edited')"; grep -qx 'pyproject.toml' <<<"$s" && grep -qx 'eslint.config.mjs' <<<"$s" && ! grep -q 'test_y.py' <<<"$s" && ok "[I10] #956: the pyproject.toml coverage edit and eslint.config.mjs are listed" || bad "[I10] #956: config section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Configured lanes not run')"; [ "$s" = "docs-lint" ] && grep -q 'ok: true' "$(SD)/checks-1.1.log" && ok "[I10] #956: the when-skipped lane is named while the matched one ran" || bad "[I10] #956: lanes section: $(tr '\n' '|' <<<"$s")"

# I10 #1011: a non-ASCII path, a path with a space and this repo's own *-selftest.* reach every section and the when-glob.
# Names are NFC bytes (macOS git recomposes to NFC, Linux does not); quotePath=true is pinned through GIT_CONFIG_*, so a
# machine with a global quotePath=false cannot pass these without run.sh's own -c
cafe=$'caf\303\251'
FIXTURE_FILES="src/$cafe.spec.ts scripts/x-selftest.sh" FIXTURE_BODY=$'expect(a).toBe(1)\nexpect(b).toBe(2)' \
  FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"cafe","when":["src/'"$cafe"'.spec.ts"],"commands":["true cafe"]}]}}}' fixture rp4 ""
mkdir -p "$d/main/src/old dir"; echo x > "$d/main/src/old dir/y.spec.ts"; git -C "$d/main" add -A; git -C "$d/main" commit -qm "spaced spec"; git -C "$d/main" push -q origin main 2>/dev/null
printf 'build-path-names\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=true run_case "$d"; expect approved "[I10] #1011 run"
want="$(printf 'scripts/x-selftest.sh\n  -expect(a).toBe(1)\nsrc/%s.spec.ts\n  -expect(a).toBe(1)' "$cafe")"
s="$(rsec 'Existing test or snapshot expectations changed')"; [ "$s" = "$want" ] && ok "[I10] #1011: a non-ASCII spec and a *-selftest.sh are named with their removed expectations" || bad "[I10] #1011: expectations section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Deleted or renamed test files')"; [ "$s" = $'D\tsrc/old dir/y.spec.ts' ] && ok "[I10] #1011: a deleted spec whose path holds a space is listed whole" || bad "[I10] #1011: deleted section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'CI or check configuration edited')"; [ "$s" = ".github/workflows/$cafe.yml" ] && ok "[I10] #1011: a non-ASCII CI config is listed unquoted" || bad "[I10] #1011: config section: $(tr '\n' '|' <<<"$s")"
s="$(rsec 'Configured lanes not run')"; [ "$s" = "(none)" ] && grep -qx 'ok: true cafe' "$(SD)/checks-1.1.log" && ok "[I10] #1011: a when-glob naming the non-ASCII path runs its lane" || bad "[I10] #1011: lanes section: $(tr '\n' '|' <<<"$s"); log: $(tr '\n' '|' < "$(SD)/checks-1.1.log")"

# J7: origin/<base> that no longer resolves mid-run is staleness-unreadable, never 'nothing moved'
fixture rq; printf 'build-pr\nreview-needs-work-drop-base\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect staleness-unreadable "[J7] the base ref vanished before round 2"; [ "$RC" -eq 1 ] && ok "[J7] exit 1" || bad "[J7] exit $RC"

# J11: an unresolvable merge-base (an orphan branch) is env-base-unreadable
fixture rr; mkdir -p "$d/wt"; ( cd "$d/main" && git worktree add -q --detach "$d/wt/42" && cd "$d/wt/42" && git checkout -q --orphan second-shift/42 && git commit -qm orphan --allow-empty && git push -q origin second-shift/42 ) 2>/dev/null
printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; run_case "$d" --resume; expect env-base-unreadable "[J11] no merge-base with the base branch"; [ "$RC" -eq 2 ] && ok "[J11] exit 2" || bad "[J11] exit $RC"

# J13: a diff against the first commit that cannot be read stops the run
fixture rs; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitdiffdead"
cat > "$T/gitdiffdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" diff --name-status "*) exit 128 ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitdiffdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitdiffdead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != approved ] && ok "[J13] an unreadable diff is an environment stop ($TERM_SLUG)" || bad "[J13] rc=$RC $TERM_SLUG"

# K5: re-entry is decided by the tracker alone — a local run-id cache admits nothing
fixture rt; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"; echo "run-x" > "$d/main/.claude/pipeline-state/42-run-id"; run_case "$d"; expect claimed-elsewhere "[K5] a claimed label with no marker is not re-entered on the strength of a local cache"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
