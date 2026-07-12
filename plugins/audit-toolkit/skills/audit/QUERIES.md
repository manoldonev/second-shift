# Audit ledger jq query reference card

The audit ledger is JSONL — one row per harness event. Each row has a flat shape:

```json
{
  "ts": "2026-04-29T01:23:45Z",
  "session_id": "abc123",
  "event": "PostToolUse | PostToolUseFailure | SubagentStop | UserPromptExpansion",
  "tool": "Agent | Read | Edit | Bash | Write | TodoWrite | ...",
  "subagent": "<subagent_type> when tool=Agent or event=SubagentStop",
  "command_name": "<slash-command> when event=UserPromptExpansion",
  "outcome": "ok | fail"
}
```

## Setup

Most queries assume you've resolved the current ledger:

```bash
LEDGER=$(ls -t .claude/audit/*.jsonl | head -1)
```

## Common queries

### Show every Agent dispatch

```bash
jq -c 'select(.tool == "Agent")' "$LEDGER"
```

### Show only failed tool calls

```bash
jq -c 'select(.outcome == "fail")' "$LEDGER"
```

### Show every slash-command invocation (skill load)

```bash
jq -c 'select(.event == "UserPromptExpansion") | {ts, command_name}' "$LEDGER"
```

### List unique subagents dispatched

```bash
jq -r 'select(.tool == "Agent" and .outcome == "ok") | .subagent' "$LEDGER" | sort -u
```

### Count dispatches per subagent

```bash
jq -r 'select(.tool == "Agent" and .outcome == "ok") | .subagent' "$LEDGER" | sort | uniq -c
```

### Filter to a specific time window

```bash
# Last 5 minutes
jq -c --arg cutoff "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
  'select(.ts > $cutoff)' "$LEDGER"
```

### List Bash commands invoked

```bash
jq -r 'select(.tool == "Bash") | .args_excerpt.command // empty' "$LEDGER"
```

### Files this session touched (Edit/Write)

```bash
jq -r 'select(.tool == "Edit" or .tool == "Write") | .args_excerpt.file_path // empty' "$LEDGER" | sort -u
```

### Aggregate across sessions

```bash
# All sessions in the last 7 days, count Agent dispatches per subagent
find .claude/audit -name '*.jsonl' -mtime -7 -print0 | xargs -0 cat \
  | jq -r 'select(.tool == "Agent" and .outcome == "ok") | .subagent' \
  | sort | uniq -c | sort -rn
```

## Tips

- All ledger files are JSONL; one row per line. Use `jq -c` for compact output, `jq '.'` for pretty.
- The lean ledger has only the fields above. There's no `args_excerpt`, no `result_sha`, no hash chain — those were stripped to match the experimental scope.
- For `Bash` and `Edit` queries above to work, you need to write a hook that captures `tool_input`. The current lean hook does not — it captures only the row schema above. Re-add `tool_input` capture in `audit-tool-calls.sh` if needed.
