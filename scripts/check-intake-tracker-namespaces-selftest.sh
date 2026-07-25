#!/usr/bin/env bash
# Selftest for check-intake-tracker-namespaces.sh — proves it passes on the real tree
# and bites when a guarded file drops a namespace or a fresh single-prefix fetch site
# is introduced. CI runs this via the *-selftest.sh glob (both lanes, incl. macOS bash
# 3.2), so a real prose regression fails here.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-intake-tracker-namespaces.sh"
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fail=0

# 1) Green on the real tree.
if bash "$CHECK" "$REPO_ROOT" >/dev/null 2>&1; then
    echo "PASS: real tree names all three Atlassian namespaces at every fetch site"
else
    echo "FAIL: real tree should pass the namespace check" >&2
    bash "$CHECK" "$REPO_ROOT" >&2 || true
    fail=1
fi

# Fixture: minimal mirror of the two scan roots. A pristine three-namespace file kept
# OUTSIDE the scan roots so it is never itself scanned; copied in as the clean case.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugins/intake-toolkit/skills/demo"
mkdir -p "$TMP/plugins/dev-pipeline/skills/run"
PRISTINE="$TMP/pristine.md"
cat > "$PRISTINE" <<'EOF'
Fetch the ticket via the Atlassian MCP getJiraIssue — namespace varies:
`mcp__atlassian__getJiraIssue`, `mcp__plugin_atlassian_atlassian__getJiraIssue`,
or `mcp__claude_ai_Atlassian_Rovo__getJiraIssue` (ToolSearch to discover a deferred tool).
EOF
CLEAN="$TMP/plugins/intake-toolkit/skills/demo/SKILL.md"
cp "$PRISTINE" "$CLEAN"

# 2) Green on a clean fixture (all three namespaces present).
if bash "$CHECK" "$TMP" >/dev/null 2>&1; then
    echo "PASS: clean fixture passes"
else
    echo "FAIL: clean fixture should pass" >&2
    bash "$CHECK" "$TMP" >&2 || true
    fail=1
fi

# 3) Red when a namespace is dropped from a guarded file.
sed 's/mcp__claude_ai_Atlassian_Rovo__getJiraIssue//' "$PRISTINE" > "$CLEAN"
if bash "$CHECK" "$TMP" >/dev/null 2>&1; then
    echo "FAIL: check should reject a guarded file missing the Rovo namespace" >&2
    fail=1
else
    echo "PASS: check rejects a guarded file missing a namespace"
fi

# 4) Red when a NEW single-prefix fetch site is introduced (discovery, not a hardcoded
# file list). Restore the clean file, then add a fresh single-prefix site in the other
# scan root.
cp "$PRISTINE" "$CLEAN"
NEWSITE="$TMP/plugins/dev-pipeline/skills/run/new-fetch.md"
echo 'Fetch the ticket read-only via mcp__atlassian__getJiraIssue (single prefix).' > "$NEWSITE"
if bash "$CHECK" "$TMP" >/dev/null 2>&1; then
    echo "FAIL: check should reject a newly-added single-prefix fetch site" >&2
    fail=1
else
    echo "PASS: check rejects a newly-added single-prefix site (discovery-based)"
fi

if [ "$fail" -ne 0 ]; then
    echo "check-intake-tracker-namespaces-selftest: FAILED" >&2
    exit 1
fi
echo "check-intake-tracker-namespaces-selftest: OK"
exit 0
