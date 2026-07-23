#!/usr/bin/env bash
# Selftest for check-scope-tracker-namespaces.sh — proves it passes on the real
# agent and bites when a namespace grant or the ToolSearch step is removed.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-scope-tracker-namespaces.sh"
REAL_PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
REAL_AGENT="$REAL_PLUGIN_ROOT/agents/scope-completeness-reviewer.md"
fail=0

# 1) Green on the real agent (the dev-pipeline sibling cross-check runs if present).
if SECOND_SHIFT_PLUGIN_ROOT="$REAL_PLUGIN_ROOT" bash "$CHECK" >/dev/null 2>&1; then
    echo "PASS: real agent + code-review.mjs pass the namespace check"
else
    echo "FAIL: real agent should pass the namespace check" >&2
    SECOND_SHIFT_PLUGIN_ROOT="$REAL_PLUGIN_ROOT" bash "$CHECK" >&2 || true
    fail=1
fi

# Fixture plugin root: a copy of the real agent we can mutate. Point the
# dev-pipeline sibling env at a nonexistent path so the cross-check is skipped —
# this isolates the agent-level assertions.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/agents"

# 2) Red when a namespace grant is dropped from the tools: line.
sed 's/mcp__claude_ai_Atlassian_Rovo__getJiraIssue, //' "$REAL_AGENT" > "$TMP/agents/scope-completeness-reviewer.md"
if SECOND_SHIFT_PLUGIN_ROOT="$TMP" SECOND_SHIFT_DEV_PIPELINE_ROOT="$TMP/nonexistent" bash "$CHECK" >/dev/null 2>&1; then
    echo "FAIL: check should reject an agent missing the Rovo namespace grant" >&2
    fail=1
else
    echo "PASS: check rejects an agent missing the Rovo namespace grant"
fi

# 3) Red when the ToolSearch discovery step is removed.
sed 's/ToolSearch//g' "$REAL_AGENT" > "$TMP/agents/scope-completeness-reviewer.md"
if SECOND_SHIFT_PLUGIN_ROOT="$TMP" SECOND_SHIFT_DEV_PIPELINE_ROOT="$TMP/nonexistent" bash "$CHECK" >/dev/null 2>&1; then
    echo "FAIL: check should reject an agent with no ToolSearch discovery" >&2
    fail=1
else
    echo "PASS: check rejects an agent with no ToolSearch discovery"
fi

# 4) Red when a namespace is dropped from code-review.mjs's ATLASSIAN_MCP_TOOLSEARCH
# (assertion 3). Restore the real agent so only the cross-check fails, and point the
# dev-pipeline sibling env at a fixture root carrying a mutated code-review.mjs.
REAL_CR="$SCRIPT_DIR/../../dev-pipeline/skills/run/workflows/code-review.mjs"
if [ -f "$REAL_CR" ]; then
    cp "$REAL_AGENT" "$TMP/agents/scope-completeness-reviewer.md"
    DP_FIX="$TMP/dp/skills/run/workflows"
    mkdir -p "$DP_FIX"
    sed 's/mcp__claude_ai_Atlassian_Rovo__getJiraIssue,//' "$REAL_CR" > "$DP_FIX/code-review.mjs"
    if SECOND_SHIFT_PLUGIN_ROOT="$REAL_PLUGIN_ROOT" SECOND_SHIFT_DEV_PIPELINE_ROOT="$TMP/dp" bash "$CHECK" >/dev/null 2>&1; then
        echo "FAIL: check should reject code-review.mjs missing a namespace in ATLASSIAN_MCP_TOOLSEARCH" >&2
        fail=1
    else
        echo "PASS: check rejects code-review.mjs missing a namespace in ATLASSIAN_MCP_TOOLSEARCH"
    fi
else
    echo "SKIP: dev-pipeline sibling code-review.mjs not found — cross-check red path not exercised"
fi

if [ "$fail" -ne 0 ]; then
    echo "check-scope-tracker-namespaces-selftest: FAILED" >&2
    exit 1
fi
echo "check-scope-tracker-namespaces-selftest: OK"
exit 0
