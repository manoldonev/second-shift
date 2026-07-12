#!/usr/bin/env bash
# Append one row per tool call to a per-session JSONL ledger.
# Wired to PostToolUse / PostToolUseFailure / SubagentStop /
# UserPromptExpansion via the plugin's hooks/hooks.json — fires automatically
# once the audit-toolkit plugin is enabled. (Legacy/manual fallback for repos
# not using the plugin: templates/settings.audit-template.json.)
#
# Observability only. The ledger is a visibility signal for manual review;
# nothing here blocks pushes, commits, or any other action.
# `/audit` reads the ledger; `/audit-history` aggregates across sessions.

set -uo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(jq -r '.session_id // empty' <<<"$PAYLOAD")
[ -z "$SESSION_ID" ] && exit 0

CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD")
EVENT=$(jq -r '.hook_event_name // empty' <<<"$PAYLOAD")
TOOL=$(jq -r '.tool_name // empty' <<<"$PAYLOAD")
SUBAGENT=$(jq -r '.tool_input.subagent_type // .agent_type // empty' <<<"$PAYLOAD")
COMMAND_NAME=$(jq -r '.command_name // empty' <<<"$PAYLOAD")

OUTCOME="ok"
[ "$EVENT" = "PostToolUseFailure" ] && OUTCOME="fail"

AUDIT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}/.claude/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null && chmod 700 "$AUDIT_DIR" 2>/dev/null
LEDGER="$AUDIT_DIR/${SESSION_ID}.jsonl"

# Atomic create-if-absent: `>>` (append) never truncates and creates the file
# when missing; `umask 077` gives a freshly created ledger mode 0600. This
# avoids the check-then-create TOCTOU of `[ ! -e ] && install -m 600 /dev/null`
# — under concurrent hook invocations sharing one session_id, two processes
# could both pass the `-e` test and `install` would truncate the ledger,
# clobbering rows written in between. Append-create has no truncation window.
( umask 077
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$SESSION_ID" \
    --arg event "$EVENT" \
    --arg tool "$TOOL" \
    --arg subagent "$SUBAGENT" \
    --arg command_name "$COMMAND_NAME" \
    --arg outcome "$OUTCOME" \
    '{ts:$ts, session_id:$sid, event:$event, tool:$tool, subagent:$subagent, command_name:$command_name, outcome:$outcome}' \
    >> "$LEDGER" 2>/dev/null
)

exit 0
