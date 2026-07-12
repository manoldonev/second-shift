#!/usr/bin/env bash
# Selftest for check-review-context.sh: registry-named files pass; a typo'd or
# unregistered basename fails closed; config add/remove deltas are honored.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-review-context.sh"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Hermetic plugin root with a minimal review-lead SKILL.md carrying the panel line.
mkdir -p "$TMP/plugin/skills/review-lead"
cat > "$TMP/plugin/skills/review-lead/SKILL.md" <<'MD'
choose from the effective reviewer registry — the plugin-shipped panel (security-reviewer, performance-reviewer, db-reviewer, a11y-reviewer) plus/minus the consumer config deltas.
MD
export SECOND_SHIFT_PLUGIN_ROOT="$TMP/plugin"

# (1) no review-context dir -> clean
mkdir -p "$TMP/r1"
bash "$CHECK" "$TMP/r1" >/dev/null 2>&1 && ok "no dir -> clean" || bad "no dir should pass"

# (2) panel-named files -> clean
mkdir -p "$TMP/r2/.claude/second-shift/review-context"
: > "$TMP/r2/.claude/second-shift/review-context/db-reviewer.md"
: > "$TMP/r2/.claude/second-shift/review-context/performance-reviewer.md"
bash "$CHECK" "$TMP/r2" >/dev/null 2>&1 && ok "panel-named files -> clean" || bad "panel-named files should pass"

# (3) typo'd basename -> fail closed with UNKNOWN-REVIEWER-FILE
mkdir -p "$TMP/r3/.claude/second-shift/review-context"
: > "$TMP/r3/.claude/second-shift/review-context/preformance-reviewer.md"   # typo
if bash "$CHECK" "$TMP/r3" >"$TMP/r3.out" 2>&1; then
  bad "typo'd basename should FAIL but passed"
else
  grep -q "UNKNOWN-REVIEWER-FILE:.*preformance-reviewer.md" "$TMP/r3.out" && ok "typo'd basename -> fail closed" \
    || bad "typo failed but without the expected message"
fi

# (4) consumer-added reviewer -> allowed via config
mkdir -p "$TMP/r4/.claude/second-shift/review-context" "$TMP/r4/.claude"
: > "$TMP/r4/.claude/second-shift/review-context/coaching-reviewer.md"
cat > "$TMP/r4/.claude/second-shift.config.json" <<'JSON'
{ "reviewers": { "add": [ { "name": "coaching-reviewer", "dimensions": ["coaching"] } ] } }
JSON
bash "$CHECK" "$TMP/r4" >/dev/null 2>&1 && ok "config-added reviewer file -> clean" \
  || bad "config-added reviewer file should pass"

# (5) removed reviewer's file -> fail closed
mkdir -p "$TMP/r5/.claude/second-shift/review-context" "$TMP/r5/.claude"
: > "$TMP/r5/.claude/second-shift/review-context/a11y-reviewer.md"
cat > "$TMP/r5/.claude/second-shift.config.json" <<'JSON'
{ "reviewers": { "remove": [ "a11y-reviewer" ] } }
JSON
bash "$CHECK" "$TMP/r5" >/dev/null 2>&1 && bad "removed reviewer's file should FAIL" \
  || ok "removed reviewer's file -> fail closed"

# (6) non-markdown junk -> fail closed
mkdir -p "$TMP/r6/.claude/second-shift/review-context"
: > "$TMP/r6/.claude/second-shift/review-context/db-reviewer.txt"
bash "$CHECK" "$TMP/r6" >/dev/null 2>&1 && bad "non-.md file should FAIL" || ok "non-.md file -> fail closed"

echo
if [ "$FAILS" -eq 0 ]; then echo "check-review-context-selftest: ALL PASS"; else echo "check-review-context-selftest: $FAILS FAILURE(S)"; exit 1; fi
