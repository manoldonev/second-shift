#!/usr/bin/env bash
# Appends a marker per hook firing. Presence of both markers after a session with
# one Bash call proves: (1) plugin hooks.json is honored, (2) ${CLAUDE_PLUGIN_ROOT}
# resolves inside hook command strings, (3) the hook script executes from the plugin dir.
set -euo pipefail
echo "$(date -u +%FT%TZ) hooks-smoke: ${1:-unknown} (root=${CLAUDE_PLUGIN_ROOT:-unset})" >> /tmp/second-shift-hooks-smoke.log
exit 0
