#!/usr/bin/env bash
# Selftest for check-config-shadowing.sh: the real tree passes; a tree with a key's reader stripped fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DP="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/check-config-shadowing.sh"
FAILS=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; FAILS=$((FAILS+1)); }
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT

# (1) the real dev-pipeline tree passes
if bash "$CHECK" "$DP" >/dev/null 2>&1; then ok "real tree: clean"; else bad "real tree should be clean but failed"; fi

# strip_case <name> <relative-file> <key> — a copy of the tree with every line naming <key>
# removed from <relative-file> must fail, naming that key.
strip_case() {
  local d="$TMPROOT/$1"; mkdir -p "$d"; cp -R "$DP/." "$d/"
  grep -vF "$3" "$d/$2" > "$d/stripped.tmp" || true
  mv "$d/stripped.tmp" "$d/$2"
  if bash "$CHECK" "$d" > "$d/shadow.out" 2>&1; then
    bad "stripped $3 reader should FAIL but passed"
  elif grep -qF "SHADOW: '$3'" "$d/shadow.out"; then
    ok "stripped $3 reader -> SHADOW failure + message"
  else
    bad "stripped $3 reader failed but without the expected SHADOW message"
  fi
}

# (2) the scheduler's plans-dir read, and (3) the branch-prefix resolver's namespace read
strip_case plans skills/run/run.sh paths.plansDir
strip_case prefix tools/branch-prefix.sh tracker.branchPrefix

# (4) a MISSING anchor file is a distinct failure class from a present-but-silent one: a row
# re-pointed at a path that does not exist would otherwise read as "reader absent" forever.
D="$TMPROOT/missing"; mkdir -p "$D"; cp -R "$DP/." "$D/"
rm -f "$D/tools/branch-prefix.sh"
if bash "$CHECK" "$D" > "$D/shadow.out" 2>&1; then
  bad "missing anchor file should FAIL but passed"
else
  grep -q "SHADOW-CHECK: missing file tools/branch-prefix.sh" "$D/shadow.out" \
    && ok "missing anchor file -> distinct SHADOW-CHECK message" \
    || bad "missing anchor file failed but without the expected SHADOW-CHECK message"
fi

if [[ "$FAILS" -gt 0 ]]; then echo "check-config-shadowing selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-config-shadowing selftest: all green"
