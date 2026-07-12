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
  [ -d "$CACHE/$p/$v" ] || missing="$missing $p"
done <<EOF
$(jq -r '.plugins | to_entries[] | "\(.key)\t\(.value)"' "$LOCK" 2>/dev/null)
EOF
if [ -n "$missing" ]; then
  echo "second-shift: you're missing your accelerators —$missing not installed at the pinned version(s)."
  echo "second-shift: fix: claude plugin install <plugin>@second-shift --scope project  (then restart the session)"
  echo "second-shift: full diagnosis: /second-shift:doctor"
fi
exit 0
