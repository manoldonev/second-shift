#!/usr/bin/env bash
# Selftest for check-scope-tracker-namespaces.sh — proves it passes on the real
# agent and bites when a namespace grant, the ToolSearch step, or the plugin's own
# code-review.mjs is missing.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-scope-tracker-namespaces.sh"
REAL_PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
REAL_AGENT="$REAL_PLUGIN_ROOT/agents/scope-completeness-reviewer.md"
REAL_CR="$REAL_PLUGIN_ROOT/workflows/code-review.mjs"
fail=0

# 1) Green on the real agent and the real code-review.mjs.
if SECOND_SHIFT_PLUGIN_ROOT="$REAL_PLUGIN_ROOT" bash "$CHECK" >/dev/null 2>&1; then
    echo "PASS: real agent + code-review.mjs pass the namespace check"
else
    echo "FAIL: real agent should pass the namespace check" >&2
    SECOND_SHIFT_PLUGIN_ROOT="$REAL_PLUGIN_ROOT" bash "$CHECK" >&2 || true
    fail=1
fi

# Fixture plugin root: copies of the real agent and code-review.mjs we can mutate
# one at a time, so each case fails for exactly the reason it names.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/agents" "$TMP/workflows"
cp "$REAL_CR" "$TMP/workflows/code-review.mjs"

# expect_red <label> <stderr-pattern>: the check must exit non-zero naming the cause.
expect_red() {
    if SECOND_SHIFT_PLUGIN_ROOT="$TMP" bash "$CHECK" >/dev/null 2>"$TMP/.stderr"; then
        echo "FAIL: check should reject $1" >&2
        fail=1
    elif grep -q "$2" "$TMP/.stderr"; then
        echo "PASS: check rejects $1"
    else
        echo "FAIL: $1: exit non-zero but no '$2' line (stderr: $(cat "$TMP/.stderr"))" >&2
        fail=1
    fi
}

# 2) Red when a namespace grant is dropped from the tools: line.
sed 's/mcp__claude_ai_Atlassian_Rovo__getJiraIssue, //' "$REAL_AGENT" > "$TMP/agents/scope-completeness-reviewer.md"
expect_red "an agent missing the Rovo namespace grant" \
    "MISSING-NAMESPACE: scope-completeness-reviewer 'tools:' does not grant mcp__claude_ai_Atlassian_Rovo__getJiraIssue"

# 3) Red when the ToolSearch discovery step is removed.
sed 's/ToolSearch//g' "$REAL_AGENT" > "$TMP/agents/scope-completeness-reviewer.md"
expect_red "an agent with no ToolSearch discovery" "MISSING-TOOLSEARCH"

# 4) Red when a namespace is dropped from code-review.mjs's ATLASSIAN_MCP_TOOLSEARCH.
# Restore the real agent so only the cross-check fails.
cp "$REAL_AGENT" "$TMP/agents/scope-completeness-reviewer.md"
sed 's/mcp__claude_ai_Atlassian_Rovo__getJiraIssue,//' "$REAL_CR" > "$TMP/workflows/code-review.mjs"
expect_red "code-review.mjs missing a namespace in ATLASSIAN_MCP_TOOLSEARCH" \
    "MISSING-NAMESPACE: code-review.mjs ATLASSIAN_MCP_TOOLSEARCH does not select mcp__claude_ai_Atlassian_Rovo__getJiraIssue"

# 5) Red when the plugin ships no workflows/code-review.mjs: the file lives in this
# plugin, so its absence is a broken install, not a standalone adoption to skip.
rm -f "$TMP/workflows/code-review.mjs"
expect_red "a plugin root with no workflows/code-review.mjs" "MISSING-TABLE: .*workflows/code-review.mjs not found"

if [ "$fail" -ne 0 ]; then
    echo "check-scope-tracker-namespaces-selftest: FAILED" >&2
    exit 1
fi
echo "check-scope-tracker-namespaces-selftest: OK"
exit 0
