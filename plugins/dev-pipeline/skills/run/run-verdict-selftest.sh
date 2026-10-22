#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-verdict-selftest.sh — run.sh scenario slice: baseBranch, the commit status, minimized
# verdicts, the verdict grammar, rounds spent.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-verdict-selftest] baseBranch, the commit status, minimized verdicts, the verdict grammar, rounds spent"

# (bb) baseBranch: the lane forks from, targets and reviews against the configured branch, not the remote default
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"baseBranch":"develop"}' fixture bb
git -C "$d/main" switch -q -c develop && echo dev > "$d/main/src/dev-only.ts" && git -C "$d/main" add src/dev-only.ts && git -C "$d/main" commit -qm dev && git -C "$d/main" push -q -u origin develop 2>/dev/null && git -C "$d/main" switch -q main
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(bb) a run on a configured baseBranch"
git -C "$d/origin.git" merge-base --is-ancestor develop second-shift/42 && ok "(bb) the branch is cut from origin/develop" || bad "(bb) the branch does not contain origin/develop"
grep -q "gh pr create --draft --base develop" "$FAKE_GH/prompt-1.txt" && ok "(bb) the build opens its PR against develop" || bad "(bb) build prompt PR base: $(grep -o "against [^ ]*" "$FAKE_GH/prompt-1.txt")"
grep -q "base branch is develop" "$FAKE_GH/prompt-2.txt" && ok "(bb) the review diffs against develop" || bad "(bb) review prompt names no base"
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/"},"paths":{"plansDir":"docs/plans"},"baseBranch":"nope"}' fixture bb2
printf 'build-pr\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-base-unreadable "(bb2) a configured baseBranch missing on origin refuses"
grep -qx ready-for-dev "$FAKE_GH/labels" && ! grep -qx in-progress "$FAKE_GH/labels" && [ ! -f "$FAKE_GH/calls" ] && ok "(bb2) refused before the claim, nothing spawned" || bad "(bb2) claimed or spawned on an unresolvable base"
fixture bb3; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(bb3) no baseBranch"
grep -q "gh pr create --draft --base main" "$FAKE_GH/prompt-1.txt" && ok "(bb3) unset, the PR targets the remote default" || bad "(bb3) default PR base: $(grep -o "against [^ ]*" "$FAKE_GH/prompt-1.txt")"

# (cs) #915: the bound verdict is posted as the second-shift/review commit status on the sha it names
fixture cs1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs1) an approved run"
cs_head="$(git -C "$d/origin.git" rev-parse second-shift/42)"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q "^operator $cs_head .*state=success .*context=second-shift/review .*description=approved at this head — see the verdict .*target_url=https://x/pr/7#verdict" "$FAKE_GH/statuses" \
  && ok "(cs1) [D-1 D-3 D-4] success posted once on the reviewed head, linking the verdict comment" || bad "(cs1) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
grep -qx "status: second-shift/review=success on $cs_head" "$FAKE_GH/pr-body.md" && ok "(cs1) [D-13] the run block names the posted status" || bad "(cs1) run block: $(grep status "$FAKE_GH/pr-body.md")"
fixture cs2; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs2) needs-work, then approve"
cs_l1="$(sed -n 1p "$FAKE_GH/statuses" 2>/dev/null)"; cs_l2="$(sed -n 2p "$FAKE_GH/statuses" 2>/dev/null)"
cs_r1="$(cut -d' ' -f2 <<<"$cs_l1")"; cs_r2="$(cut -d' ' -f2 <<<"$cs_l2")"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 2 ] && grep -q 'state=failure .*description=needs-work at this head' <<<"$cs_l1" && grep -q 'state=success' <<<"$cs_l2" \
  && [ "$cs_r2" = "$(git -C "$d/origin.git" rev-parse second-shift/42)" ] && [ "$cs_r1" != "$cs_r2" ] \
  && ok "(cs2) [D-3] failure on the needs-work head, success on the later approved head" || bad "(cs2) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture cs3; printf 'build-pr\nreview-approve-and-push\nreview-approve-and-push\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(cs3) every verdict voided by a moved head"
[ ! -s "$FAKE_GH/statuses" ] && ok "(cs3) [D-1] a verdict voided by a moved head posts no status" || bad "(cs3) statuses: $(cat "$FAKE_GH/statuses")"
fixture cs4; printf 'build-pr\nreview-approve-and-push\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(cs4) the second review binds"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q "^operator $(git -C "$d/origin.git" rev-parse second-shift/42) " "$FAKE_GH/statuses" && ok "(cs4) only the bound head gets the status, never the voided one" || bad "(cs4) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture cs5; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Validation Failed (HTTP 422)' > "$FAKE_GH/status-fail"; run_case "$d"
expect approved "(cs5) [D-5] a failed status post leaves the terminal unchanged"
grep -q "^status: NOT posted (second-shift/review=success on $(git -C "$d/origin.git" rev-parse second-shift/42)) — gh: Validation Failed (HTTP 422)$" "$FAKE_GH/pr-body.md" && ok "(cs5) [D-5] the failed post is reported in the run block" || bad "(cs5) run block: $(grep status "$FAKE_GH/pr-body.md")"
fixture cs6; printf 'build-pr\nreview-render-unavailable\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(cs6) render-unavailable"
grep -q 'state=failure' "$FAKE_GH/statuses" 2>/dev/null && ok "(cs6) [D-3] a render-unavailable needs-work posts failure" || bad "(cs6) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
# (er) a review that cannot read the ticket or dispatch its design-fidelity reviewer stops the run like one that cannot
# render: env-not-ready, no round spent, no BUILD spawned
for r in ticket-unreadable seat-unavailable; do
  fixture "er-$r"; printf 'build-pr\nreview-%s\nbuild-push-only\nreview-approve\n' "$r" > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect env-not-ready "(er) verdict: needs-work with reason: $r"
  [ ! -f "$FAKE_GH/prompt-3.txt" ] && grep -q "(reason: $r)" <<<"$OUT" && grep -q 'state=failure' "$FAKE_GH/statuses" 2>/dev/null \
    && ok "(er) $r: no second BUILD, the terminal names the reason, the needs-work posts failure" || bad "(er) $r: prompt-3 $([ -f "$FAKE_GH/prompt-3.txt" ] && echo spawned || echo absent), terminal: $(grep '^terminal' <<<"$OUT")"
done
# through the bot when one is configured; a bot the App denies statuses is named, never retried as the operator
printf '#!/usr/bin/env bash\nFAKE_GH_AS=bot exec %s "$@"\n' "$T/bin/gh" > "$T/bin/gh-asbot"; chmod +x "$T/bin/gh-asbot"
cs_bot() { OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh-asbot" env -u RUN_GH bash "$RUN" 42 2>&1 )"; RC=$?; TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"; }
CS_BOT_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT","app":{"appName":"second-shift-bot"}}},"paths":{"plansDir":"docs/plans"}}'
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture cs7; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; cs_bot; expect approved "(cs7) a run with a bot"
grep -q "^bot $(git -C "$d/origin.git" rev-parse second-shift/42) .*state=success" "$FAKE_GH/statuses" 2>/dev/null && ! grep -q '^operator ' "$FAKE_GH/statuses" && ok "(cs7) [D-5] the status is posted through the bot" || bad "(cs7) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture cs8; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Resource not accessible by integration (HTTP 403)' > "$FAKE_GH/status-fail"; cs_bot
expect approved "(cs8) a bot the App denies statuses"
grep -q "^status: NOT posted .*(HTTP 403) — the bot's GitHub App needs the 'Commit statuses: write' permission$" "$FAKE_GH/pr-body.md" && ok "(cs8) [D-7] the run block names the missing App permission" || bad "(cs8) run block: $(grep status "$FAKE_GH/pr-body.md")"
grep -q '(HTTP 422)$' "$T/cs5/gh/pr-body.md" 2>/dev/null && ! grep -q 'Commit statuses' "$T/cs5/gh/pr-body.md" && ok "(cs5) [D-7] no App hint without a bot or a 403/404" || bad "(cs5) [D-7] hint leaked: $(grep status "$T/cs5/gh/pr-body.md")"

# (mv) #946: once a verdict binds, the PR's earlier lane verdicts are minimized as outdated — never a notice, never a stranger's
mv_seed() { # a stranger's verdict-shaped comment and a lane notice, posted before the run
  jq '. + [{id:1,node_id:"N1",body:"verdict: needs-work\nreviewed: x",user:{login:"stranger",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"},
           {id:2,node_id:"N2",body:"the head moved during the review; verdict: approve no longer binds",user:{login:"tester",type:"User"},created_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z"}]' \
    "$FAKE_GH/comments.json" > "$FAKE_GH/c.tmp" && mv "$FAKE_GH/c.tmp" "$FAKE_GH/comments.json"; }
fixture mv1; mv_seed; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(mv1) needs-work, then approve"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "operator N3" ] && ok "(mv1) [D-3 D-4 D-1] the earlier needs-work is minimized; the bound approve, the notice and the stranger's are not" \
  || bad "(mv1) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"
fixture mv2; printf 'build-pr\nreview-two-verdicts\n' > "$FAKE_CLAUDE_PLAN"; FAKE_ORDER=needs-work,approve run_case "$d"; expect approved "(mv2) two verdicts in one window"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "operator N1" ] && ok "(mv2) [D-9] the earlier verdict of the same window is minimized, the bound one is not" \
  || bad "(mv2) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"
fixture mv3; mv_seed; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve-and-push\nreview-approve-and-push\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "(mv3) the later verdicts voided by a moved head"
[ ! -s "$FAKE_GH/minimized" ] && ok "(mv3) [D-3] a voided verdict minimizes nothing: the bound needs-work stays expanded" || bad "(mv3) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized")"
fixture mv4; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; echo 'gh: Resource not accessible by integration (HTTP 403)' > "$FAKE_GH/minimize-fail"; run_case "$d"
expect approved "(mv4) [D-7] a failed minimize leaves the terminal unchanged"
grep -q "state=success" "$FAKE_GH/statuses" 2>/dev/null && ok "(mv4) [D-7] the commit status still posts" || bad "(mv4) statuses: $(cat "$FAKE_GH/statuses" 2>/dev/null)"
grep -q "^verdicts: earlier ones NOT all minimized — comment 1 NOT minimized — gh: Resource not accessible by integration (HTTP 403)" "$FAKE_GH/pr-body.md" \
  && ok "(mv4) [D-7] the failed minimize is one run-block line" || bad "(mv4) run block: $(grep verdicts "$FAKE_GH/pr-body.md")"
FIXTURE_CONFIG="$CS_BOT_CONFIG" fixture mv5; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; cs_bot; expect approved "(mv5) a run with a bot"
[ "$(cat "$FAKE_GH/minimized" 2>/dev/null)" = "bot N1" ] && ok "(mv5) [D-6] the minimize is written through the bot" || bad "(mv5) minimized: $(tr '\n' '|' < "$FAKE_GH/minimized" 2>/dev/null)"

# (vc) #991: a verdict binds only when its own comment backs it. Each inconsistent body, posted by both the review and its
# re-spawn: no status, no BUILD, the re-spawn told which rule broke, a notice linking each rejected verdict, review-unbound
vc_case() { # vc_case <id> <build plan> <review plan> <rule>
  fixture "$1"; printf '%s\n%s\n%s\n' "$2" "$3" "$3" > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect review-unbound "($1) $3, twice"
  [ "$RC" -eq 5 ] && [ ! -s "$FAKE_GH/statuses" ] && [ "$(cat "$FAKE_GH/calls")" -eq 3 ] && [ ! -f "$FAKE_GH/prompt-4.txt" ] \
    && ok "($1) no status posted and no BUILD spawned" || bad "($1) rc=$RC calls=$(cat "$FAKE_GH/calls") statuses=$(cat "$FAKE_GH/statuses" 2>/dev/null)"
  grep -q '^## Your previous verdict did not bind' "$FAKE_GH/prompt-3.txt" && grep -qF -- "- $4" "$FAKE_GH/prompt-3.txt" && ! grep -q 'previous verdict did not bind' "$FAKE_GH/prompt-2.txt" \
    && ok "($1) the re-spawn prompt names the rule: $4" || bad "($1) prompt-3: $(grep -A3 'previous verdict' "$FAKE_GH/prompt-3.txt" | tr '\n' '|')"
  [ "$(grep -c 'does not bind' "$FAKE_GH/pr-comment-bodies" 2>/dev/null)" -eq 2 ] && grep -q '^second-shift run .*: the verdict at https://x/pr/7#verdict does not bind' "$FAKE_GH/pr-comment-bodies" \
    && grep -qF -- "- $4" "$FAKE_GH/pr-comment-bodies" && ! grep -q '^verdict:' "$FAKE_GH/pr-comment-bodies" \
    && ok "($1) one notice per rejected verdict links it and names the rule, and is no verdict itself" || bad "($1) notices: $(tr '\n' '|' < "$FAKE_GH/pr-comment-bodies" 2>/dev/null)"
  grep -qF "breaks the verdict grammar: $4" <<<"$OUT" && ok "($1) the miss names the failed rule" || bad "($1) miss: $(grep 'verdict grammar' <<<"$OUT" | head -n 1)"
}
vc_case vc1 build-pr review-bad-approve-blocker "approve with a blocker"
vc_case vc2 build-pr review-bad-approve-violated "approve with a violated or undeterminable row: D-1 violated"
vc_case vc3 build-pr-add-row review-approve "record row not scored: D-2"   # the row only the head carries: run.sh reads the record there too
vc_case vc4 build-pr review-bad-needs-work-noblocker "needs-work with no blocker"
grep -qF 'Bash(bash *verdict-check.sh*)' "$FAKE_GH/args-2.txt" && grep -q "^Before you post, check your draft: run 'bash .*/tools/verdict-check.sh " "$FAKE_GH/prompt-2.txt" \
  && grep -qx 'The verdict comment has these parts, in this order and nothing else:' "$FAKE_GH/prompt-2.txt" && ! grep -q 'LOCKSTEP-' "$FAKE_GH/prompt-2.txt" && ok "(vc4) [D-2] the review may run the checker on its draft and is told to; the grammar reaches it without its markers" \
  || bad "(vc4) [D-2] allowlist/prompt: $(grep -c 'verdict-check' "$FAKE_GH/prompt-2.txt")"
fixture vc5; printf 'build-pr\nreview-bad-approve-blocker\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(vc5) a rejected verdict, then a consistent approve from the re-spawn"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q 'state=success' "$FAKE_GH/statuses" && ok "(vc5) one status, from the verdict that binds" || bad "(vc5) statuses: $(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"
fixture vc6; printf 'build-pr-rm-record\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect verdict-uncheckable "(vc6) no record at the head to check the verdict against"
[ "$RC" -eq 1 ] && [ ! -s "$FAKE_GH/statuses" ] && [ "$(cat "$FAKE_GH/calls")" -eq 2 ] && grep -q '| verdict-uncheckable | 1 | none |' "$FAKE_GH/pr-body.md" \
  && ok "(vc6) [D-5] exit 1, no status, no re-spawn, the run block names no verdict" || bad "(vc6) rc=$RC calls=$(cat "$FAKE_GH/calls") block=$(grep '| verdict-uncheckable' "$FAKE_GH/pr-body.md")"
fixture vc7; printf 'build-pr\nreview-needs-work-notes-reason\nbuild-push-only\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"
expect approved "(vc7) 'reason: render-unavailable' as prose under ## Notes is not the render reason: the needs-work goes to a BUILD"

# (kb) the review session writes the knowledge-base contributions itself, by the inclusion test review-context.md declares,
# and a verdict carrying them binds against the v3 record (its '## Knowledge source' answer included) the launch linted
fixture kb; printf 'build-pr\nreview-approve-kb\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d"; expect approved "(kb) an approve carrying the contributions block"
grep -qF "Knowledge-base contributions: when the repo's review-context.md has a \`## Knowledge-base contributions\` section, write a contributions block last in the verdict's \`## Notes\`." "$FAKE_GH/prompt-2.txt" \
  && grep -qF 'Apply the inclusion test that the section declares, as written, to every candidate, and list only the candidates that pass.' "$FAKE_GH/prompt-2.txt" && grep -qF 'Carry the whole list on every verdict' "$FAKE_GH/prompt-2.txt" \
  && ! grep -q "review-lead's report" "$FAKE_GH/prompt-2.txt" && ! grep -q 'LOCKSTEP-' "$FAKE_GH/prompt-2.txt" \
  && ok "(kb) the review prompt has the session apply the inclusion test itself and carry the whole list on every verdict" || bad "(kb) the contributions instruction is missing from the review prompt, or still reads review-lead's report"
[ "$(wc -l < "$FAKE_GH/statuses" 2>/dev/null)" -eq 1 ] && grep -q 'state=success' "$FAKE_GH/statuses" && jq -e '.[0].body | split("\n") | any(. == "Knowledge-base contributions:")' "$FAKE_GH/comments.json" >/dev/null \
  && ok "(kb) AC-10: verdict-check binds the verdict with its contributions lines: one success status" || bad "(kb) AC-10: statuses=$(tr '\n' '|' < "$FAKE_GH/statuses" 2>/dev/null)"

# (m) rounds spent
fixture m; printf 'build-pr\nreview-needs-work\nbuild-push-only\nreview-needs-work\n' > "$FAKE_CLAUDE_PLAN"; run_case "$d" --max-rounds 2; expect rounds-spent "(m) two needs-work rounds"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
