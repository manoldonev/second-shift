#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-audit-selftest.sh — run.sh scenario slice: audit-round rows: placeholders, render and smoke
# commands, fail-closed diffs, unreadable arms.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-audit-selftest] audit-round rows"


# ---- rows, audit round 1 ----
# A9: the magnitude half of the positive-integer test (orch:540 `-ge 1`)
fixture au1; OUT="$( cd "$d/main" && bash "$RUN" 42 --max-rounds 00 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect usage-max-rounds "[A9] --max-rounds 00 is below 1"; [ "$RC" -eq 2 ] && ok "[A9] exit 2" || bad "[A9] exit $RC"

# E15: the earlier block is found under CRLF, as a body round-tripped through the GitHub API carries it (gate:6321-6324)
fixture au2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-crlf" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\r\\n\\r\\n<!-- pipeline-cost-block -->\\r\\nold block line\\r\\n<!-- /pipeline-cost-block -->\\r\\n\\r\\nKEEP THIS LINE\\r\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-crlf"; RUN_GH="$T/bin/gh-crlf" run_case "$d"; expect approved "[E15] run against a CRLF body"
grep -q 'KEEP THIS LINE' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && [ "$(grep -c '<!-- pipeline-cost-block -->' "$FAKE_GH/pr-body.md")" = 1 ] && ok "[E15] the CRLF block was replaced, not appended to" || bad "[E15] body: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-240)"

# G8 C22: "configured" is a config-time predicate — a when-scoped lane that did not run on this diff is still a configured check (gate:5193-5202)
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"docs","when":["docs/**"],"commands":["false"]}]}}}' fixture au3 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[G8] configured-but-skipped is not unverified"

# K12: a crashed and a timed-out review session each get the one re-spawn
fixture au4; printf 'build-pr\nreview-crash\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[K12] a crashed review is re-spawned once"
[ "$(cat "$FAKE_GH/calls")" = 3 ] && ok "[K12] one re-spawn, no build" || bad "[K12] calls=$(cat "$FAKE_GH/calls")"
[ -f "$(SD)/checks-1.1.log" ] && [ ! -f "$(SD)/checks-1.1-retry1.log" ] && ok "[K12] the checks did not re-run for an unmoved head" || bad "[K12] checks re-ran: $(cd "$(SD)" && echo checks-*)"
fixture au5; printf 'build-pr\nbuild-sleep\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; RUN_REVIEW_TIMEOUT=2 run_case "$d"; expect approved "[K12] a timed-out review is re-spawned once"
grep -qF '| review-1.1 | ? | unpriced (no total_cost_usd) |' "$FAKE_GH/pr-body.md" && grep -q '[$][0-9.]* + unpriced' "$FAKE_GH/pr-body.md" && ok "[K12] the killed review is an unpriced row, never \$0.00" || bad "[K12] rows: $(grep -E '^[|] (build|review)' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
# its denials were never read: "?", never a 0 a reader takes for a clean session; the re-spawn that did report counts
# shellcheck disable=SC2016  # the run block's literal dollar costs
grep -qxF '| review-1.1 | ? | unpriced (no total_cost_usd) | ? |' "$FAKE_GH/pr-body.md" && grep -qxF '| review-1.1-retry1 | 3 | $1.00 | 1 |' "$FAKE_GH/pr-body.md" && [ ! -e "$(SD)/denials-review-1.1.txt" ] \
  && ok "[K12] the killed review's denials are unread (?), not 0" || bad "[K12] denials cells: $(grep -E '^[|] review' "$FAKE_GH/pr-body.md" | tr '\n' '|')"
sleep 1; session_sleep_reap

# C13: the docs/plans default is where the record lands when no config says otherwise
fixture au6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; rm "$d/main/.claude/second-shift.config.json"
( cd "$d/main" && git push -q origin main:second-shift/41 ) 2>/dev/null
OUT="$( cd "$d/main" && env -u SECOND_SHIFT_CONFIG bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
git -C "$d/origin.git" cat-file -e second-shift/42:docs/plans/main-42-decisions.md 2>/dev/null && ok "[C13] the record is committed under docs/plans by default" || bad "[C13] record not at docs/plans ($TERM_SLUG)"

# ---- rows, audit round 2 ----
# C24 C25 H8: placeholder values are shell-quoted into the command (gate:4005-4030 shquote/subst); a render that fails or writes nothing is red
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {route} {state} > {out}\",\"smokeCommand\":\"test {mustShow} = 'a b' && test {route} = 'x&y z'\"}}}" fixture ar1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | x&y z | filters expanded | 1:2 | a b |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C24 C25] a route with '&' and a space, a state and a must-show with spaces, reach the commands as single arguments"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"false","smokeCommand":"true"}}}' fixture ar2 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] a render command that fails is red"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","smokeCommand":"true"}}}' fixture ar3 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] a render that exits 0 and writes no image is red"

# H9: the duplicate detector compares against EVERY earlier state (gate:4991-4994), not only the previous one
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"printf %s {state} > {out}","smokeCommand":"true"}}}' fixture ar4 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | a | empty | 1:3 | ok |\n| RS-3 | a | default | 1:4 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H9] states a,b,a: the third is identical to the first"
grep -q 'RS-1 and RS-3' "$(SD)/smoke-1.1.log" 2>/dev/null && ok "[H9] the log names both rows" || bad "[H9] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-200)"

# H14: a smokeCommand that takes {textScale} runs every row at 1 and at 2; {textScale} goes in before {mustShow}
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"echo {route} {textScale} >> $T/h14a.calls && test {mustShow} = 'Size {''textScale}x'\"}}}" fixture h14a "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | Size {textScale}x |\n| RS-2 | b | empty | 1:3 | Size {textScale}x |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] a smokeCommand with {textScale} and a must-show carrying the literal token"
[ "$(tr '\n' '|' < "$T/h14a.calls" 2>/dev/null)" = "a 1|a 2|b 1|b 2|" ] && ok "[H14] each row is smoked at text scale 1 and at 2" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14a.calls" 2>/dev/null)"
grep -q 'scaled smoke: not configured' <<<"$OUT" && bad "[H14] the not-configured note printed for a smokeCommand that takes {textScale}" || ok "[H14] no not-configured note when {textScale} is taken"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {textScale} = 1\"}}}" fixture h14b "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H14] a smoke red only at text scale 2 ends the round red"
grep -qx "RED: RS-1 at text scale 2: smoke failed: test 2 = 1" "$(SD)/smoke-1.1.log" 2>/dev/null && grep -q "^ok: RS-1 at text scale 1 " "$(SD)/smoke-1.1.log" && ! grep -q 'at text scale 1: smoke failed' "$(SD)/smoke-1.1.log" \
  && ok "[H14] the red names the row, the scale and the substituted command; scale 1 stays ok" || bad "[H14] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-240)"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"echo {route} >> $T/h14c.calls && { test -f $T/h14c.green || { touch $T/h14c.green; false; }; }\"}}}" fixture h14c "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n'
printf 'build-pr\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] no {textScale}: a red-then-green attempt over two rows"
[ "$(tr '\n' '|' < "$T/h14c.calls" 2>/dev/null)" = "a|b|a|b|" ] && ok "[H14] without {textScale} each row is smoked once per attempt" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14c.calls" 2>/dev/null)"
[ "$(grep -c 'scaled smoke: not configured (smokeCommand takes no {textScale})' <<<"$OUT")" -eq 1 ] && ok "[H14] the not-configured note is printed exactly once per run" || bad "[H14] note printed $(grep -c 'scaled smoke: not configured' <<<"$OUT") times"
[ "$(grep -c '^scaled smoke: not configured (smokeCommand takes no {textScale})$' "$FAKE_GH/pr-body.md" 2>/dev/null)" -eq 1 ] && ok "[H14] the run block carries the note once" || bad "[H14] run block: $(grep -c 'scaled smoke' "$FAKE_GH/pr-body.md" 2>/dev/null)"
! grep -q 'scaled smoke' "$(SD)"/smoke-*.log 2>/dev/null && ok "[H14] the note never enters a smoke log (the build's findings)" || bad "[H14] the note is in a smoke log"

# H14 (D-5): a stdin-reading render or smoke command must not swallow the rows still to run
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cat > /dev/null; printf %s {state} > {out}\",\"smokeCommand\":\"cat > /dev/null; echo {route} >> $T/h14d.calls\"}}}" fixture h14d "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n| RS-3 | c | error | 1:4 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] stdin-reading render and smoke commands over three rows"
[ "$(tr '\n' '|' < "$T/h14d.calls" 2>/dev/null)" = "a|b|c|" ] && ok "[H14] all three rows are smoked when the commands read stdin" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14d.calls" 2>/dev/null)"
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"printf %s {state} > {out}\",\"smokeCommand\":\"cat > /dev/null; echo {route} {textScale} >> $T/h14f.calls\"}}}" fixture h14f "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n| RS-2 | b | empty | 1:3 | ok |\n| RS-3 | c | error | 1:4 | ok |\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] a stdin-reading smokeCommand with {textScale} over three rows"
[ "$(tr '\n' '|' < "$T/h14f.calls" 2>/dev/null)" = "a 1|a 2|b 1|b 2|c 1|c 2|" ] && ok "[H14] all three rows are smoked at both scales when the scaled smoke reads stdin" || bad "[H14] calls: $(tr '\n' '|' < "$T/h14f.calls" 2>/dev/null)"

# H14 (D-10): a red at text scale 1 does not skip text scale 2
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}\",\"smokeCommand\":\"test {textScale} = 2\"}}}" fixture h14e "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H14] a smoke red only at text scale 1 ends the round red"
grep -qx "RED: RS-1 at text scale 1: smoke failed: test 1 = 2" "$(SD)/smoke-1.1.log" 2>/dev/null && grep -q "^ok: RS-1 at text scale 2 " "$(SD)/smoke-1.1.log" \
  && ok "[H14] after a scale-1 red, scale 2 still runs and is logged ok" || bad "[H14] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" 2>/dev/null | cut -c1-240)"

# H14 (D-6): the not-configured note needs armed rows; a 'Design: none' record carries none
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"design":{"provider":"figma","liveRender":{"command":"true","smokeCommand":"true"}}}' fixture h14g "- true" $'\n## Design\n\nDesign: none — a wording change, nothing renders\n'
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[H14] Design: none with a smokeCommand that takes no {textScale}"
! grep -q 'scaled smoke: not configured' <<<"$OUT" && ! grep -q 'scaled smoke' "$FAKE_GH/pr-body.md" 2>/dev/null \
  && ok "[H14] no not-configured note when the record arms no rows" || bad "[H14] the note printed for a record that arms no rows"

# C20: the when-glob diff is fail-closed (gate:3970-3981) — a diff that cannot be read never skips every when-scoped lane
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"e2e","when":["src/**"],"commands":["false"]}]}}}' fixture ar5 ""
printf 'build-delete-test\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitnameonlydead"
cat > "$T/gitnameonlydead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" diff --name-only "*) case "\$*" in *..*) ;; *) exit 128 ;; esac ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitnameonlydead/git"; OUT="$( cd "$d/main" && PATH="$T/gitnameonlydead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ "$TERM_SLUG" != approved ] && ok "[C20] an unreadable diff stops the run ($TERM_SLUG) instead of skipping the when-scoped lane" || bad "[C20] rc=$RC $TERM_SLUG"

# J5: the staleness overlap diffs are fail-closed too
fixture ar6; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[J5] first run"
( cd "$d/main" && git fetch -q origin && git reset -q --hard origin/main && echo moved >> work.txt && git add work.txt && git commit -qm "base moves" && git push -q origin main ) 2>/dev/null
printf 'build-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; : > "$FAKE_GH/calls"; printf 'in-progress\nopus\n' > "$FAKE_GH/labels"
OUT="$( cd "$d/main" && PATH="$T/gitnameonlydead:$PATH" bash "$RUN" 42 --resume 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect staleness-unreadable "[J5] a base move whose overlap cannot be computed is unreadable, never 'moved into nothing of ours'"

# I7: a comment listing that is not an array is an unreadable tracker, not review-unbound (orch:700)
fixture ar7; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-comments-object" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ] && [[ "\$2" == *issues/7/comments* ]]; then echo '{"message":"rate limited"}'; exit 0; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-comments-object"; RUN_GH="$T/bin/gh-comments-object" run_case "$d"; expect env-tracker-unreadable "[I7] a non-array comment listing"

# F16: the record read for the build prompt is checked
fixture ar8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitshowdead"
cat > "$T/gitshowdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" show "*) exit 128 ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitshowdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitshowdead:$PATH" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
[ "$RC" -eq 2 ] && [ ! -f "$FAKE_GH/calls" ] && ok "[F16] a record that cannot be read at its first commit stops before any build ($TERM_SLUG)" || bad "[F16] rc=$RC $TERM_SLUG calls=$(cat "$FAKE_GH/calls" 2>/dev/null)"

# B22: a closing comment that could not be posted is said aloud
fixture ar9; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-close-dies" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "issue comment" ] && [[ "\$*" == *"second-shift run"* ]]; then exit 1; fi; exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/bin/gh-close-dies"; RUN_GH="$T/bin/gh-close-dies" run_case "$d"; expect approved "[B22] approve with a dead closing comment"
grep -q 'could not post the closing comment' <<<"$OUT" && ok "[B22] the failed closing comment is reported" || bad "[B22] silent"

# E21 E20: the unreadable arms, and a diverged worktree
fixture ar10; printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; mkdir -p "$T/gitstatusdead"
cat > "$T/gitstatusdead/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" status --porcelain "*) n=\$(cat "\$FAKE_GH/status-reads" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "\$FAKE_GH/status-reads"; [ "\$n" -ge "\${FAKE_STATUS_DIES_AT:-1}" ] && { echo "fatal: index locked" >&2; exit 128; } ;; esac; exec "$(command -v git)" "\$@"
EOF
chmod +x "$T/gitstatusdead/git"; OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=2 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect build-inflight-unreadable "[E21] an unreadable status after the build"; [ "$RC" -eq 1 ] && ok "[E21] exit 1" || bad "[E21] exit $RC"
fixture ar11; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=3 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect closeout-inflight-unreadable "[E20] an unreadable status at close-out"; [ "$RC" -eq 1 ] && [ -d "$d/wt/42" ] && ok "[E20] exit 1, worktree kept" || bad "[E20] rc=$RC"
FIXTURE_CONFIG="$RTCFG" fixture ar11b; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"   # the 4th status read is the runtime-data one
OUT="$( cd "$d/main" && PATH="$T/gitstatusdead:$PATH" FAKE_STATUS_DIES_AT=4 bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[E20-rd] an unreadable runtime-data status at close-out"
[ "$RC" -eq 0 ] && [ -d "$d/wt/42" ] && printf '%s\n' "$OUT" | grep -q 'left in place: the status of paths.runtimeData could not be read' && ok "[E20-rd] fail safe: worktree kept and the reason printed" || bad "[E20-rd] rc=$RC, worktree $([ -d "$d/wt/42" ] && echo kept || echo gone)"
fixture ar12; printf 'build-pr\nreview-needs-work-diverge\nbuild-push-only\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-worktree-diverged "[E18] a worktree that cannot fast-forward to origin is refused, never reset"
[ "$RC" -eq 2 ] && [ "$(cat "$FAKE_GH/calls")" = 2 ] && ok "[E18] exit 2, no second build" || bad "[E18] rc=$RC calls=$(cat "$FAKE_GH/calls")"

# A20 A21 C16: the config-path override, the GH alias, and .format as a check
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"}}' fixture ar13
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; mv "$d/main/.claude/second-shift.config.json" "$d/elsewhere.json"
OUT="$( cd "$d/main" && SECOND_SHIFT_CONFIG="$d/elsewhere.json" bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[A20] SECOND_SHIFT_CONFIG points at a config outside the default path (no config at the default: the prefix would be unresolvable)"
fixture ar14; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
OUT="$( cd "$d/main" && GH="$T/bin/gh" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
expect approved "[A21] GH names the tracker CLI when RUN_GH is unset"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"true","format":"false"}}}' fixture ar15 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[C16] .format runs as a check"

# ---- rows, audit round 3 (guards only) ----
# H8: a render that writes an image and still exits non-zero is red on its exit code
FIXTURE_CONFIG="{\"tracker\":{\"type\":\"github\",\"branchPrefix\":\"second-shift/\"},\"paths\":{\"plansDir\":\"docs/plans\"},\"design\":{\"provider\":\"figma\",\"liveRender\":{\"command\":\"cp $T/px.png {out}; false\",\"smokeCommand\":\"true\"}}}" fixture as1 "- true" $'\n## Design frames\n\n| RS | route | state | frame | must-show |\n| --- | --- | --- | --- | --- |\n| RS-1 | a | default | 1:2 | ok |\n'
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[H8] an image written by a render that exited non-zero is still red"
grep -q 'render failed' "$(SD)/smoke-1.1.log" && ok "[H8] the log names the exit, not the image" || bad "[H8] log: $(tr '\n' '|' < "$(SD)/smoke-1.1.log" | cut -c1-160)"

# C18: a setup lane runs in its own cwd
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"setup","cwd":"src","commands":["test -f a.ts"]}],"lint":"true"}}}' fixture as2 ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "[C18] the setup lane's command ran in src/ (a.ts exists only there)"

# the setup lanes run before the first build, so the build starts on an installed tree; a red one is told to the build
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"install","commands":["touch deps-installed"]}],"lint":"true"}}}' fixture as2b ""
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "a green setup lane before the build"
grep -qx deps-installed "$FAKE_GH/tree-seen-1.txt" && ok "the first build starts with the setup lane's output in its worktree" || bad "the first build started before the setup lanes ran: $(tr '\n' ' ' < "$FAKE_GH/tree-seen-1.txt")"
! grep -q '## Setup lanes red' "$FAKE_GH/prompt-1.txt" && ok "a green setup adds nothing to the build prompt" || bad "a green setup was reported red to the build"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lanes":[{"name":"install","commands":["echo NO-REGISTRY; false"]}],"lint":"true"}}}' fixture as2c ""
printf 'build-pr\nbuild-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=2 run_case "$d"; expect checks-red-spent "a red setup lane before the build still spawns the build, and the checks still gate"
grep -q '## Setup lanes red before this build' "$FAKE_GH/prompt-1.txt" && grep -q 'NO-REGISTRY' "$FAKE_GH/prompt-1.txt" && ok "the first build is told the setup lanes failed, with the log" || bad "the first build prompt does not report the red setup"
! grep -q '## Setup lanes red' "$FAKE_GH/prompt-2.txt" && ok "only the first build gets the pre-build setup report" || bad "a later build was handed the stale pre-build setup report"

# a lane past its bound is red, and the bound reaches what the lane started
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"lint":"sleep 20 & echo $! > '"$T"'/lane-child.pid; sleep 20"}}}' fixture as2t ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_LANE_TIMEOUT=2 RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "a check that outlives the lane bound is red"
grep -q 'TIMED OUT after 2s' "$(SD)/checks-1.1.log" && ok "the checks log names the timeout" || bad "the checks log does not name the timeout: $(tail -n 3 "$(SD)/checks-1.1.log" | tr '\n' ' ')"
! kill -0 "$(cat "$T/lane-child.pid" 2>/dev/null || echo 0)" 2>/dev/null && ok "a process the timed-out lane started is stopped with it" || bad "a timed-out lane's background child survived"

# C20: an extraLanes entry with no `when` always runs
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"commands":{"main":{"extraLanes":[{"name":"always","commands":["false"]}]}}}' fixture as3 ""
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; RUN_CHECKS_RED_MAX=1 run_case "$d"; expect checks-red-spent "[C20] a lane with no when globs runs on every diff"

# E15: an earlier block with no terminator is replaced and the loss is said in the body
fixture as4; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
cat > "$T/bin/gh-noterm" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "api repos/o/r/pulls/7" ]; then printf '{"body":"built-by: fake\\n\\n<!-- pipeline-cost-block -->\\nold block line\\nno terminator here\\n"}'; else exec "$T/bin/gh" "\$@"; fi
EOF
chmod +x "$T/bin/gh-noterm"; RUN_GH="$T/bin/gh-noterm" run_case "$d"; expect approved "[E15] run against a block with no terminator"
grep -q 'had no terminator; text below it was not preserved' "$FAKE_GH/pr-body.md" && ! grep -q 'old block line' "$FAKE_GH/pr-body.md" && ok "[E15] the body says what was not preserved" || bad "[E15] body: $(tr '\n' '|' < "$FAKE_GH/pr-body.md" | cut -c1-200)"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
