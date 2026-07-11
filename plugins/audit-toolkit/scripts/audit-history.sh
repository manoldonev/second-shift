#!/usr/bin/env bash
# /audit-history [days=N] — aggregate ledger query across sessions.
#
# Walks every .claude/audit/*.jsonl in the recent N-day window and surfaces:
#   - session counts
#   - total Agent dispatches
#   - top subagents (which reviewers fire most)
#   - top loaded orchestrators (which skills the team uses most)
#
# A tool-truth ledger (observability only): a neutral record of what tools
# actually fired (vs. the narrative), for manual spot-checking. No automatic action.

set -uo pipefail

DAYS=30
FORMAT="text"

while [ $# -gt 0 ]; do
    case "$1" in
        --json) FORMAT="json"; shift ;;
        --help|-h) head -16 "$0" | grep -E '^# ' | sed 's/^# //'; exit 0 ;;
        [0-9]*) DAYS="$1"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not in a git repo"; exit 1; }
AUDIT_DIR=".claude/audit"

if [ ! -d "$AUDIT_DIR" ]; then
    cat <<'EOF'
No audit ledgers found — the audit hook hasn't written anything on this
checkout yet.

To enable it: enable the audit-toolkit plugin for this repo. Its
hooks/hooks.json wires the ledger writer automatically — nothing to copy.
(Legacy/manual mode, for a repo not adopting the plugin: copy the plugin's
templates/settings.audit-template.json to .claude/settings.local.json.)

Once enabled, every Claude Code session in this project appends tool-call
rows to .claude/audit/{session_id}.jsonl, and `/audit-history N` reports
across the last N days.

Full setup: the audit-toolkit SETUP.md. Observability only —
nothing here blocks pushes, commits, or PRs.
EOF
    exit 0
fi

LEDGERS=$(find "$AUDIT_DIR" -maxdepth 1 -name '*.jsonl' -mtime -"$DAYS" 2>/dev/null | sort)
LEDGER_COUNT=$(echo "$LEDGERS" | grep -c . || true)
if [ "$LEDGER_COUNT" -eq 0 ]; then
    cat <<EOF
.claude/audit/ exists but no ledger files modified in the last $DAYS days.

Possible causes:
  1. The plugin/hook was enabled mid-session — hook wiring is loaded at
     session start. Restart Claude Code, run any tool, then retry.
  2. The hook is enabled but no Claude Code sessions have fired tool calls
     in this project in the last $DAYS days. Try a wider window
     (e.g. \`/audit-history 90\`) or check older ledgers manually.

Full setup: the audit-toolkit SETUP.md.
EOF
    exit 0
fi

TOTAL=0
TOTAL_DISPATCHES=0
SUB_COUNTS=$(mktemp); ORCH_COUNTS=$(mktemp)
trap 'rm -f "$SUB_COUNTS" "$ORCH_COUNTS"' EXIT

while IFS= read -r ledger; do
    [ -z "$ledger" ] && continue
    TOTAL=$((TOTAL + 1))

    dispatches=$(jq -r 'select(.tool == "Agent" and .outcome == "ok") | .subagent' "$ledger" 2>/dev/null | grep -v '^$')
    n_dispatches=$(echo "$dispatches" | grep -c . || true)
    TOTAL_DISPATCHES=$((TOTAL_DISPATCHES + n_dispatches))
    echo "$dispatches" >> "$SUB_COUNTS"

    loads=$(jq -r 'select(.event == "UserPromptExpansion") | .command_name' "$ledger" 2>/dev/null | grep -v '^$')
    echo "$loads" >> "$ORCH_COUNTS"
done <<<"$LEDGERS"

SUB_TOP=$(sort "$SUB_COUNTS" | grep -v '^$' | uniq -c | sort -rn | head -10)
ORCH_TOP=$(sort "$ORCH_COUNTS" | grep -v '^$' | uniq -c | sort -rn | head -10)

if [ "$FORMAT" = "json" ]; then
    jq -n \
        --argjson days "$DAYS" \
        --argjson total "$TOTAL" \
        --argjson dispatches "$TOTAL_DISPATCHES" \
        --arg sub_top "$SUB_TOP" \
        --arg orch_top "$ORCH_TOP" \
        '{window_days:$days, sessions:{total:$total}, agent_dispatches:$dispatches, subagent_top10:$sub_top, orchestrator_loads_top10:$orch_top}'
    exit 0
fi

cat <<EOF

## Audit history — last $DAYS days ($TOTAL sessions)

### Activity
- Total sessions:           $TOTAL
- Total Agent dispatches:   $TOTAL_DISPATCHES

### Top dispatched subagents
$(printf '%s\n' "$SUB_TOP" | while IFS= read -r l; do printf '  %s\n' "$l"; done)

### Top loaded orchestrators
$(printf '%s\n' "$ORCH_TOP" | while IFS= read -r l; do printf '  %s\n' "$l"; done)

EOF
