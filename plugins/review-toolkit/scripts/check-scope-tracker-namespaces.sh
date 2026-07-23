#!/usr/bin/env bash
# check-scope-tracker-namespaces.sh — guard scope-completeness-reviewer against a
# regression to a hardcoded Atlassian MCP namespace.
#
# Why this exists
# ---------------
# scope-completeness-reviewer fetches the JIRA ticket through the Atlassian MCP,
# whose tool namespace depends on HOW the server was registered:
#   - top-level mcpServers entry   -> mcp__atlassian__*
#   - plugin-bundled server        -> mcp__plugin_atlassian_atlassian__*
#   - claude.ai Atlassian (Rovo)   -> mcp__claude_ai_Atlassian_Rovo__*
# A hardcoded `mcp__atlassian__*` prefix makes the Scope Completeness Gate
# permanently unsatisfiable for a consumer whose MCP arrives under either of the
# other two — BLOCKED is treated as FAIL, so the run can never reach "Ready to
# merge". This repo's CI is model-free, so the live JIRA-under-plugin behavior
# cannot be exercised; this static check is the regression guard for it.
#
# Asserts:
#   (1) the agent's `tools:` frontmatter grants getJiraIssue under ALL THREE
#       Atlassian namespaces;
#   (2) the agent body references ToolSearch (the deferred-tool discovery step);
#   (3) when the dev-pipeline plugin is installed as a sibling, its
#       code-review.mjs ATLASSIAN_MCP_TOOLSEARCH selects getJiraIssue under all
#       three namespaces too. Skipped with a note when dev-pipeline is absent
#       (standalone review-toolkit adoption — fail open, do not deny).
#
# Roots (env overrides win, for hermetic selftests):
#   review-toolkit plugin root = $SECOND_SHIFT_PLUGIN_ROOT      or  $SCRIPT_DIR/..
#   dev-pipeline sibling root  = $SECOND_SHIFT_DEV_PIPELINE_ROOT or  resolved sibling
#
# Standalone CLI: errors -> stderr, exit 1 on drift, exit 0 clean.

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

PLUGIN_ROOT="${SECOND_SHIFT_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
PLUGIN_ROOT=$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd) || PLUGIN_ROOT=""
AGENT="$PLUGIN_ROOT/agents/scope-completeness-reviewer.md"

# The three real Atlassian MCP namespace prefixes. getJiraIssue is the load-bearing
# fetch; if it is granted under a namespace, the sibling tools are too (they are
# added/removed together). Matching getJiraIssue is bounded so it does not
# false-match the getJiraIssueRemoteIssueLinks token that shares its prefix.
NAMESPACES=(mcp__atlassian__ mcp__plugin_atlassian_atlassian__ mcp__claude_ai_Atlassian_Rovo__)

errors=()

if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$AGENT" ]; then
    printf 'UNLOCATABLE: scope-completeness-reviewer.md not found (PLUGIN_ROOT=%s). Set SECOND_SHIFT_PLUGIN_ROOT to the review-toolkit plugin root.\n' "${PLUGIN_ROOT:-<empty>}" >&2
    exit 1
fi

# (1) tools: frontmatter grants getJiraIssue under all three namespaces.
tools_line=$(grep -m1 '^tools:' "$AGENT" || true)
for ns in "${NAMESPACES[@]}"; do
    if ! printf '%s' "$tools_line" | grep -qE "${ns}getJiraIssue([, ]|$)"; then
        errors+=("MISSING-NAMESPACE: scope-completeness-reviewer 'tools:' does not grant ${ns}getJiraIssue")
    fi
done

# (2) agent body references ToolSearch (deferred-tool discovery mechanism).
if ! grep -q 'ToolSearch' "$AGENT"; then
    errors+=("MISSING-TOOLSEARCH: scope-completeness-reviewer has no ToolSearch discovery step for the deferred Atlassian tools")
fi

# (3) dev-pipeline sibling code-review.mjs ATLASSIAN_MCP_TOOLSEARCH covers all three.
DP_ROOT="${SECOND_SHIFT_DEV_PIPELINE_ROOT:-}"
if [ -z "$DP_ROOT" ]; then
    cand=$(cd "$SCRIPT_DIR/../../dev-pipeline" 2>/dev/null && pwd) || cand=""
    if [ -n "$cand" ] && [ -d "$cand/skills/run/workflows" ]; then
        DP_ROOT="$cand"
    else
        for c in "$SCRIPT_DIR"/../../../dev-pipeline/*/; do
            [ -d "$c/skills/run/workflows" ] || continue
            DP_ROOT=$(cd "$c" && pwd)
        done
    fi
fi
CR="$DP_ROOT/skills/run/workflows/code-review.mjs"
if [ -n "$DP_ROOT" ] && [ -f "$CR" ]; then
    for ns in "${NAMESPACES[@]}"; do
        if ! grep -qE "${ns}getJiraIssue," "$CR"; then
            errors+=("MISSING-NAMESPACE: code-review.mjs ATLASSIAN_MCP_TOOLSEARCH does not select ${ns}getJiraIssue")
        fi
    done
else
    printf 'note: dev-pipeline plugin not resolved as a sibling — skipping the code-review.mjs cross-check (standalone review-toolkit adoption).\n' >&2
fi

if [ ${#errors[@]} -gt 0 ]; then
    printf '%s\n' "${errors[@]}" >&2
    exit 1
fi

echo "check-scope-tracker-namespaces: OK (all three Atlassian namespaces covered)"
exit 0
