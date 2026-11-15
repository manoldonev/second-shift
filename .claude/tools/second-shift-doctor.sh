#!/usr/bin/env bash
# second-shift thin check — committed into this repo by /second-shift:onboard.
# Presence-verification ONLY (the sanctioned no-vendoring exception): tells a fresh
# clone that the toolkit isn't installed yet. Friendly nudge; never blocks; exit 0 always.
# Wired as a SessionStart hook in .claude/settings.json — project hooks run even when
# plugins aren't installed, which makes this the only channel that reaches someone
# who skipped the trust prompt.
CACHE="${SECOND_SHIFT_CACHE_DIR:-$HOME/.claude/plugins/cache/second-shift}"
LOCK="${1:-.claude/second-shift.lock.json}"
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$LOCK" ] || exit 0
missing=""
while IFS='	' read -r p v; do
  [ -n "$p" ] || continue
  # "latest" (canary lockfile): any installed version counts — check the plugin dir only.
  if [ "$v" = "latest" ]; then
    [ -d "$CACHE/$p" ] || missing="$missing $p"
  else
    [ -d "$CACHE/$p/$v" ] || missing="$missing $p"
  fi
done <<EOF
$(jq -r '.plugins | to_entries[] | "\(.key)\t\(.value)"' "$LOCK" 2>/dev/null)
EOF
if [ -n "$missing" ]; then
  echo "second-shift: you're missing your accelerators —$missing not installed at the pinned version(s)."
  echo "second-shift: fix: claude plugin install <plugin>@second-shift --scope project  (then restart the session)"
  echo "second-shift: full diagnosis: /second-shift:doctor"
fi
# The branch namespace is the one personal setting: the committed tracker.branchPrefix is the team's,
# and each engineer may put their own in a gitignored .claude/second-shift.config.local.json. Only a repo
# that runs the lane (dev-pipeline pinned) branches anything, so only there is this worth saying.
CONFIG=".claude/second-shift.config.json"; LOCAL=".claude/second-shift.config.local.json"
if [ -f "$CONFIG" ] && jq -e '.plugins | has("dev-pipeline")' "$LOCK" >/dev/null 2>&1; then
  if [ ! -f "$LOCAL" ]; then
    team="$(jq -r '.tracker.branchPrefix // empty' "$CONFIG" 2>/dev/null)"
    echo "second-shift: your runs branch as '${team:-<derived from the remote>}<ticket>' — the team's prefix. For your own:"
    echo "second-shift:   echo '{ \"tracker\": { \"branchPrefix\": \"<you>/\" } }' > $LOCAL   (and gitignore it)"
    echo "second-shift:   to keep the team's and silence this note, put {} in that file instead"
  elif command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git check-ignore -q "$LOCAL"; then
    echo "second-shift: $LOCAL is not gitignored — add it to .gitignore (or .git/info/exclude) so it is never committed"
  fi
fi
exit 0
