#!/usr/bin/env bash
# committed-config-selftest.sh — this repo's own .claude/second-shift.config.json is committed, and
# never with the bot's GitHub App identity in it (#1059).
#
# The config is tracked so the policy the lane runs under (checks, test runners, tracker settings)
# shows in a diff. tracker.bot.app stays in each engineer's gitignored
# .claude/second-shift.config.local.json: the app's ids must not ship in the public marketplace.
#
# It reads the config as COMMITTED (`git show HEAD:`), never the working copy: an operator's copy on
# disk may differ, and only what is committed is published.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL=".claude/second-shift.config.json"
LOCAL_REL=".claude/second-shift.config.local.json"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

if ! CFG="$(git -C "$ROOT" show "HEAD:$REL" 2>/dev/null)"; then
  bad "$REL is not committed at HEAD — commit it; only tracker.bot.app stays in $LOCAL_REL"
elif ! jq -e 'type == "object"' <<<"$CFG" >/dev/null 2>&1; then
  bad "$REL at HEAD is not a JSON object"
else
  ok "$REL is committed at HEAD"
  if jq -e '(.tracker.bot | type) == "object" and (.tracker.bot | has("app"))' <<<"$CFG" >/dev/null; then
    bad "$REL carries tracker.bot.app — move the block to $LOCAL_REL"
  else
    ok "$REL carries no tracker.bot.app block"
  fi
  # The four app keys anywhere at all, so a block moved elsewhere in the file is caught too.
  hits="$(jq -r '[paths | map(tostring) | select(.[-1] | IN("clientId","appName","privateKeyFilename","installationId")) | join(".")] | join(", ")' <<<"$CFG")"
  if [ -n "$hits" ]; then bad "$REL carries the app key(s) $hits — they belong in $LOCAL_REL"; else ok "$REL names no app key anywhere"; fi
fi

# The config is not ignored (so an edit to it shows in git status); the per-engineer file still is.
if git -C "$ROOT" check-ignore -q --no-index "$REL"; then bad ".gitignore still ignores $REL"; else ok "$REL is not ignored"; fi
if git -C "$ROOT" check-ignore -q --no-index "$LOCAL_REL"; then ok "$LOCAL_REL stays ignored"; else bad ".gitignore no longer ignores $LOCAL_REL"; fi

if [ "$FAILS" -gt 0 ]; then echo "committed-config selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "committed-config selftest: all green"
