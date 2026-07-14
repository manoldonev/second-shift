#!/usr/bin/env bash
# Selftest for scaffold-review-context.sh: never-regenerate + never-empty-body guards,
# and a well-formed happy path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/scaffold-review-context.sh"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# (1) happy path -> file written with H1 + both sections, no empty bodies
mkdir -p "$TMP/r1"
printf '## Stack\nNext.js + Postgres.\n\n## Maturity stage\nPre-auth MVP.\n' \
    | bash "$TOOL" "$TMP/r1" --title "acme" >/dev/null 2>&1
DEST="$TMP/r1/.claude/second-shift/review-context.md"
if [ -f "$DEST" ] && grep -q '^# Review context — acme' "$DEST" \
   && grep -q '^## Stack' "$DEST" && grep -q '^## Maturity stage' "$DEST"; then
    ok "happy path -> H1 title + confirmed sections written"
else
    bad "happy path did not produce a well-formed file"
fi

# (2) never regenerate -> refuse when file exists
RC=0; printf '## Stack\nOther.\n' | bash "$TOOL" "$TMP/r1" >/dev/null 2>&1 || RC=$?
[ "$RC" -ne 0 ] && ok "refuses to overwrite an existing review-context.md" \
    || bad "should have refused to regenerate"

# (3) never emit an empty/TODO body -> refuse
mkdir -p "$TMP/r3"
RC=0; OUT="$(printf '## Stack\nTODO\n' | bash "$TOOL" "$TMP/r3" 2>&1)" || RC=$?
if [ "$RC" -ne 0 ] && [ ! -f "$TMP/r3/.claude/second-shift/review-context.md" ] \
   && printf '%s' "$OUT" | grep -q 'Stack'; then
    ok "refuses a TODO-bodied section and writes nothing"
else
    bad "should have refused the TODO body and written nothing (rc=$RC)"
fi

# (4) empty stdin -> nothing written
mkdir -p "$TMP/r4"
RC=0; printf '' | bash "$TOOL" "$TMP/r4" >/dev/null 2>&1 || RC=$?
[ "$RC" -ne 0 ] && [ ! -f "$TMP/r4/.claude/second-shift/review-context.md" ] \
    && ok "empty stdin -> nothing written" || bad "empty stdin should write nothing"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "scaffold-review-context-selftest: ALL PASS"; else
    echo "scaffold-review-context-selftest: $FAILS FAILURE(S)"; exit 1; fi
