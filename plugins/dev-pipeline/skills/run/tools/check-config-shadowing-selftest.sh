#!/usr/bin/env bash
# Selftest for check-config-shadowing.sh: the real tree passes; a tree with a key's reader stripped fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DP="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/check-config-shadowing.sh"
FAILS=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

# (1) the real dev-pipeline tree passes
if bash "$CHECK" "$DP" >/dev/null 2>&1; then ok "real tree: clean"; else bad "real tree should be clean but failed"; fi

# (2) a tree where a stageParams reader is stripped must fail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$DP/." "$TMP/"
# strip the visualCapture reference from Stage 6
if grep -q "stageParams.visualCapture" "$TMP/stages/6-verify.md"; then
  # remove every line mentioning the key
  grep -v "stageParams.visualCapture" "$TMP/stages/6-verify.md" > "$TMP/stages/6-verify.md.tmp"
  mv "$TMP/stages/6-verify.md.tmp" "$TMP/stages/6-verify.md"
fi
if bash "$CHECK" "$TMP" >/tmp/shadow-selftest.out 2>&1; then
  bad "stripped-reader tree should FAIL but passed"
else
  grep -q "SHADOW: 'stageParams.visualCapture'" /tmp/shadow-selftest.out && ok "stripped reader -> SHADOW failure + message" \
    || bad "stripped reader failed but without the expected SHADOW message"
fi

if [[ "$FAILS" -gt 0 ]]; then echo "check-config-shadowing selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-config-shadowing selftest: all green"
