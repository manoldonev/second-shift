#!/usr/bin/env bash
# check-intake-tracker-namespaces.sh — regression guard for the intake/Stage-1 tracker
# fetch prose, keeping it namespace-agnostic for the Atlassian MCP.
#
# WHY THIS EXISTS
# ---------------
# The Atlassian MCP tool namespace depends on HOW the server was registered:
#   - top-level mcpServers entry   -> mcp__atlassian__*
#   - plugin-bundled server        -> mcp__plugin_atlassian_atlassian__*
#   - claude.ai Atlassian (Rovo)   -> mcp__claude_ai_Atlassian_Rovo__*
# A prose fetch instruction that hardcodes only `mcp__atlassian__*` misleads a session
# that exposes the MCP under one of the other two namespaces ("No such tool available").
# #187 fixed this for scope-completeness-reviewer (guarded by the sibling
# review-toolkit/scripts/check-scope-tracker-namespaces.sh); this guard covers the
# parallel intake/Stage-1 fetch *prose* sites, which carry no `tools:` frontmatter for
# that check to key off. This repo's CI is model-free, so the live JIRA-under-plugin
# behavior cannot be exercised — this static check is the regression guard for it.
#
# The check is DISCOVERY-BASED, not a hardcoded file list: it scans the intake/Stage-1
# skill surface (all file types — .md prose, .sh tooling, .mjs) and asserts that any
# file naming the top-level `mcp__atlassian__` prefix ALSO names the other two prefixes
# (proving the three-namespace discovery is co-located). A new fetch site is therefore
# covered automatically — closing the exact under-inclusive-list gap that made #191 a
# follow-up to #187.
#
# Structural sibling of scripts/stack-generality-lint.sh: repo-level, cross-plugin prose
# lint, run by CI via its own *-selftest.sh (no ci.yml registration needed).
#
# Usage: check-intake-tracker-namespaces.sh [repo-root]   (default: .)
# Exit code = number of violations (doctor convention); 0 = clean.
set -uo pipefail

ROOT="${1:-.}"

# The three real Atlassian MCP namespace prefixes. Keyed on the top-level prefix
# (the one everyone hardcodes); the other two are the required companions. None is a
# substring of another, so plain fixed-string matching is unambiguous.
TOP="mcp__atlassian__"
NS2="mcp__plugin_atlassian_atlassian__"
NS3="mcp__claude_ai_Atlassian_Rovo__"

# The intake/Stage-1 fetch surface. Roots, not a file list, so new sites are covered.
SCAN_ROOTS="
plugins/intake-toolkit/skills
plugins/dev-pipeline/skills/run
"

violations=0

# Collect the files under the scan roots that name the top-level prefix. grep -rl over
# the roots (all file types); a missing root is a hard error (the guard would otherwise
# pass vacuously if the tree moved).
for rel in $SCAN_ROOTS; do
    dir="$ROOT/$rel"
    if [ ! -d "$dir" ]; then
        printf 'UNLOCATABLE: scan root does not exist: %s\n' "$dir" >&2
        violations=$((violations + 1))
        continue
    fi
    # while-read, not mapfile — macOS ships bash 3.2.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! grep -qF "$NS2" "$f"; then
            printf 'MISSING-NAMESPACE: %s names %s but not %s (three-namespace discovery incomplete)\n' "$f" "$TOP" "$NS2" >&2
            violations=$((violations + 1))
        fi
        if ! grep -qF "$NS3" "$f"; then
            printf 'MISSING-NAMESPACE: %s names %s but not %s (three-namespace discovery incomplete)\n' "$f" "$TOP" "$NS3" >&2
            violations=$((violations + 1))
        fi
    done < <(grep -rlF "$TOP" "$dir" 2>/dev/null)
done

if [ "$violations" -gt 0 ]; then
    printf 'check-intake-tracker-namespaces: %d violation(s) — a fetch site hardcodes a single Atlassian namespace.\n' "$violations" >&2
    exit "$violations"
fi

echo "check-intake-tracker-namespaces: OK (every intake/Stage-1 fetch site names all three Atlassian namespaces)"
exit 0
