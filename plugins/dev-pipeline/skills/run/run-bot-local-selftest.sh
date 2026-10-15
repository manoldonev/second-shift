#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # the sourced lib sets $d, $OUT, $RC (fixture, run_case) and reads TERM_SLUG (expect)
# run-bot-local-selftest.sh — run.sh scenario slice: the bot's GitHub App keys in the per-engineer
# local file (#1059), and the launch warning when an enabled bot has no appName anywhere.
# The fakes, the fixture and run_case/expect live in run-selftest-lib.sh.
set -uo pipefail
# shellcheck source=run-selftest-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-selftest-lib.sh"

echo "[run-bot-local-selftest] the bot's app keys in the local file, the launch warning for an unresolved appName"

local_cfg() { printf '%s\n' "$1" > "$d/main/.claude/second-shift.config.local.json"; }
# bot_run — run.sh with the bot wrapper live (FAKE_BOT) and RUN_GH unset, as (v1) in run-claim-selftest runs it: only
# then does the scheduler reach the block that resolves the bot
bot_run() {
  [ "$CASE_ON" -eq 1 ] || { OUT=""; RC=0; TERM_SLUG=""; return 0; }
  git -C "$d/main" config user.name t; git -C "$d/main" config user.email t@x   # a commit that misses the bot lands as 't'
  OUT="$( cd "$d/main" && PATH="$T/bin:$PATH" FAKE_BOT="$T/bin/gh" env -u RUN_GH -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL bash "$RUN" 42 2>&1 )"; RC=$?
  TERM_SLUG="$(printf '%s\n' "$OUT" | sed -n 's/^terminal: //p' | tail -n 1)"
}
record_author() { git -C "$d/origin.git" log --format=%an --reverse main..second-shift/42 2>/dev/null | head -n 1; }
NOAPP='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT"}},"paths":{"plansDir":"docs/plans"}}'
WARN_RE='WARN: tracker.bot.enabled is true but tracker.bot.app.appName is set in neither'

# (w1) AC-3: bot enabled, wrapper working, appName in neither the config nor the main checkout's local file. The
#      scheduler warns that commits will land as the operator, names the fix, and the run still starts.
FIXTURE_CONFIG="$NOAPP" fixture w1; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
bot_run; expect approved "(w1) an enabled bot with no appName anywhere still runs"
grep -q "$WARN_RE" <<<"$OUT" && grep -q 'commits will land as the operator' <<<"$OUT" \
  && grep -q "put tracker.bot.app.appName in [^ ]*/w1/main/.claude/second-shift.config.local.json" <<<"$OUT" \
  && ok "(w1) the launch warning says commits land as the operator and names the key and the file that fix it" \
  || bad "(w1) no launch warning: $(grep -i 'warn' <<<"$OUT" | head -n 2 | tr '\n' '|')"

# (w2) AC-4 + AC-3: the four app keys in the local file, beside branchPrefix, any value type. run.sh accepts the file,
#      prints no warning, and the record commit — bot-commit.sh against a config with no app block — is the bot's.
FIXTURE_CONFIG="$NOAPP" fixture w2; printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"
local_cfg '{"tracker":{"branchPrefix":"second-shift/","bot":{"app":{"clientId":"Iv1-test","appName":"local-bot","privateKeyFilename":"local-bot.pem","installationId":7}}}}'
bot_run; expect approved "(w2) a local file carrying the app keys launches"
! grep -q "$WARN_RE" <<<"$OUT" && ok "(w2) an appName from the local file prints no launch warning" || bad "(w2) warned although the local file names the app"
[ "$(record_author)" = 'local-bot[bot]' ] && ok "(w2) the record commit carries the bot identity from the local file" || bad "(w2) record commit author: $(record_author)"

# (w3) an appName in the committed config alone prints no warning either: the check reads both files
FIXTURE_CONFIG='{"tracker":{"type":"github","branchPrefix":"second-shift/","bot":{"enabled":true,"envVar":"FAKE_BOT","app":{"appName":"committed-bot"}}},"paths":{"plansDir":"docs/plans"}}' fixture w3
printf 'build-pr\nreview-approve\n' > "$FAKE_CLAUDE_PLAN"; bot_run; expect approved "(w3) an appName in the committed config"
! grep -q "$WARN_RE" <<<"$OUT" && ok "(w3) an appName from the committed config prints no launch warning" || bad "(w3) warned although the committed config names the app"

# (w4, w5) AC-4: every other key is still refused, inside tracker.bot too, naming the key
fixture w4; local_cfg '{"tracker":{"bot":{"enabled":false,"app":{"appName":"local-bot"}}}}'; run_case "$d"; expect env-config-local "(w4) a local tracker.bot.enabled is refused"
grep -q 'sets tracker.bot.enabled ' <<<"$OUT" && grep -qx ready-for-dev "$FAKE_GH/labels" && ok "(w4) refused before the claim, naming the key" || bad "(w4) $(grep 'terminal' <<<"$OUT" | head -n 1)"
fixture w5; local_cfg '{"tracker":{"bot":{"app":{"appName":"local-bot","secret":"x"}}}}'; run_case "$d"; expect env-config-local "(w5) an unknown app key in the local file is refused"
grep -q 'sets tracker.bot.app.secret ' <<<"$OUT" && ok "(w5) the refusal names the unknown app key" || bad "(w5) $(grep 'terminal' <<<"$OUT" | head -n 1)"

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
