#!/usr/bin/env bash
# plain-review-tools.sh — prints the tools dir of the dev-pipeline plugin that review-lead's plain review runs from:
# plain-review.sh (the session) and verdict-join.sh (the join). The plain review and its join live in dev-pipeline,
# beside run.sh's; this resolves them from the repo layout or the plugin cache.
#
# Usage: plain-review-tools.sh
# Env: SECOND_SHIFT_DEV_PIPELINE_ROOT overrides the search.
# Exit: 0 the dir on stdout · 1 no dev-pipeline carries both scripts (the reason on stderr).
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# LOCKSTEP-BEGIN sibling-plugin-root
resolve_sibling_plugin_root() {
    local name="$1" marker="$2" override="${3:-}"
    if [ -n "$override" ]; then
        (cd "$override" 2>/dev/null && pwd)
        return
    fi
    local cand
    cand=$(cd "$SCRIPT_DIR/../../$name" 2>/dev/null && pwd) || cand=""
    if [ -n "$cand" ] && [ -d "$cand/$marker" ]; then
        echo "$cand"
        return
    fi
    # Cache layout: pick the HIGHEST version dir with the marker path. Glob order is
    # lexical, so the bare `tail -1` this used to be ranked 9.0.0 above 10.0.0. ASCENDING +
    # `tail -1` rather than a reversed sort: BSD sort ignores a global `-r` once per-key
    # modifiers are present, which would silently select the OLDEST version there.
    for cand in "$SCRIPT_DIR"/../../../"$name"/*/; do
        [ -d "$cand/$marker" ] || continue
        printf '%s\t%s\n' "$(basename "$cand")" "$(cd "$cand" && pwd)"
    done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-
}
# LOCKSTEP-END sibling-plugin-root
root="$(resolve_sibling_plugin_root dev-pipeline tools "${SECOND_SHIFT_DEV_PIPELINE_ROOT:-}")"
[ -n "$root" ] || { echo "plain-review-tools: the dev-pipeline plugin is not installed" >&2; exit 1; }
[ -f "$root/tools/plain-review.sh" ] && [ -f "$root/tools/verdict-join.sh" ] \
  || { echo "plain-review-tools: the dev-pipeline at $root has no plain review; update it" >&2; exit 1; }
echo "$root/tools"
