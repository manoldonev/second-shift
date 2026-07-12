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

# (3) a tree where the Stage-2 branch-prefix reader is stripped must fail (base/prefix
# generalization regression tripwire — issue #8).
TMP2="$(mktemp -d)"; trap 'rm -rf "$TMP" "$TMP2"' EXIT
cp -R "$DP/." "$TMP2/"
if grep -q "tracker.branchPrefix" "$TMP2/stages/2-worktree.md"; then
  grep -v "tracker.branchPrefix" "$TMP2/stages/2-worktree.md" > "$TMP2/stages/2-worktree.md.tmp"
  mv "$TMP2/stages/2-worktree.md.tmp" "$TMP2/stages/2-worktree.md"
fi
if bash "$CHECK" "$TMP2" >/tmp/shadow-selftest2.out 2>&1; then
  bad "stripped Stage-2 branchPrefix reader should FAIL but passed"
else
  grep -q "SHADOW: 'tracker.branchPrefix'" /tmp/shadow-selftest2.out && ok "stripped branchPrefix reader -> SHADOW failure + message" \
    || bad "stripped branchPrefix reader failed but without the expected SHADOW message"
fi

if [[ "$FAILS" -gt 0 ]]; then echo "check-config-shadowing selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-config-shadowing selftest: all green"
