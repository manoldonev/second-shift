#!/usr/bin/env bash
# _effective-registry.sh — shared effective-reviewer-registry computation, SOURCED by
# check-review-context.sh (basename lint) and check-review-context-sections.sh (section
# lint + coverage). Single source of truth for:
#
#   effective = plugin_panel (review-lead SKILL.md) − config reviewers.remove + reviewers.add
#
# Not meant to be executed on its own — `source` it, then call compute_effective_registry.
# Kept a leading-underscore filename so callers can tell it apart from runnable scripts;
# check-review-context-selftest.sh / check-review-context-sections-selftest.sh both cover it
# transitively.
#
#   compute_effective_registry <review-lead-SKILL.md-path> <config.json-path>
#     Echoes the effective reviewer names, one per line, sorted-unique.
#     Returns non-zero (echoing an ERROR to stderr) when the plugin panel cannot be parsed.
#     An absent/parse-failed config yields empty add/remove deltas (panel unchanged); jq
#     absence is treated the same (deltas skipped) — the caller decides whether to warn.

compute_effective_registry() {
    local skill="$1" config="$2"
    local plugin_registry adds="" removes=""

    [ -f "$skill" ] || { echo "effective-registry: ERROR — review-lead SKILL.md not found at $skill" >&2; return 1; }

    # Plugin panel: the same enumeration check-reviewer-references.sh parses.
    plugin_registry=$(grep -oE 'the plugin-shipped panel \([^)]+\)' "$skill" \
        | grep -oE '[a-z][a-z0-9-]+-reviewer' | sort -u || true)
    [ -n "$plugin_registry" ] || { echo "effective-registry: ERROR — could not parse the plugin panel from $skill" >&2; return 1; }

    if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
        adds=$(jq -r '.reviewers.add[]?.name // empty' "$config" 2>/dev/null | grep -v '^$' | sort -u || true)
        removes=$(jq -r '.reviewers.remove[]? // empty' "$config" 2>/dev/null | grep -v '^$' | sort -u || true)
    fi

    { comm -23 <(printf '%s\n' "$plugin_registry") <(printf '%s\n' "$removes"); printf '%s\n' "$adds"; } \
        | grep -v '^$' | sort -u
}
