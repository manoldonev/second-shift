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
# strip the planFilePattern reference from its surviving reader
grep -v "stageParams.planFilePattern" "$TMP/tools/preflight.sh" > "$TMP/preflight.tmp"
mv "$TMP/preflight.tmp" "$TMP/tools/preflight.sh"
if bash "$CHECK" "$TMP" >"$TMP/shadow.out" 2>&1; then
  bad "stripped-reader tree should FAIL but passed"
else
  grep -q "SHADOW: 'stageParams.planFilePattern'" "$TMP/shadow.out" && ok "stripped reader -> SHADOW failure + message" \
    || bad "stripped reader failed but without the expected SHADOW message"
fi

# (3) a tree where the branch-prefix reader is stripped must fail (base/prefix
# generalization regression tripwire — issue #8). Since #348 the namespace is owned by
# build-lean/branch-prefix.sh.
TMP2="$(mktemp -d)"; trap 'rm -rf "$TMP" "$TMP2"' EXIT
cp -R "$DP/." "$TMP2/"
grep -v "tracker.branchPrefix" "$TMP2/skills/build-lean/branch-prefix.sh" > "$TMP2/bp.tmp"
mv "$TMP2/bp.tmp" "$TMP2/skills/build-lean/branch-prefix.sh"
if bash "$CHECK" "$TMP2" >"$TMP/shadow2.out" 2>&1; then
  bad "stripped branchPrefix reader should FAIL but passed"
else
  grep -q "SHADOW: 'tracker.branchPrefix'" "$TMP/shadow2.out" && ok "stripped branchPrefix reader -> SHADOW failure + message" \
    || bad "stripped branchPrefix reader failed but without the expected SHADOW message"
fi

# (4) a MISSING anchor file is a distinct failure class from a present-but-silent one: a row
# re-pointed at a path that does not exist would otherwise read as "reader absent" forever.
TMP3="$(mktemp -d)"; trap 'rm -rf "$TMP" "$TMP2" "$TMP3"' EXIT
cp -R "$DP/." "$TMP3/"
rm -f "$TMP3/tools/is-inert-diff.sh"
if bash "$CHECK" "$TMP3" >"$TMP/shadow3.out" 2>&1; then
  bad "missing anchor file should FAIL but passed"
else
  grep -q "SHADOW-CHECK: missing file tools/is-inert-diff.sh" "$TMP/shadow3.out" \
    && ok "missing anchor file -> distinct SHADOW-CHECK message" \
    || bad "missing anchor file failed but without the expected SHADOW-CHECK message"
fi

if [[ "$FAILS" -gt 0 ]]; then echo "check-config-shadowing selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-config-shadowing selftest: all green"
