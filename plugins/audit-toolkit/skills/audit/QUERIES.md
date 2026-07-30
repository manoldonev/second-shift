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
  "target": "what the call ran ON — see the per-tool table below",
  "outcome": "ok | fail"
}
```

Field list (kept in lockstep with the audit `SETUP.md`; pair `audit-row-fields`):

<!-- LOCKSTEP-BEGIN audit-row-fields -->
`ts`, `session_id`, `event`, `tool`, `subagent`, `command_name`, `target`, `outcome`
<!-- LOCKSTEP-END audit-row-fields -->

### `target` — the identifying input, per tool

| `tool` | `target` holds |
| --- | --- |
| `Read` / `Edit` / `Write` | the file path |
| `Bash` | the command's **first line**, truncated to 200 characters |
| `Skill` | the skill name, e.g. `review-toolkit:review-lead` |
| `Workflow` | the script path, falling back to the workflow name |
| anything else | `""` — the key is always present, never omitted |

`target` is what makes the ledger usable as **evidence** rather than only as a count: a gate can assert that a `Read` of a particular file happened inside a given window, and there is no receipt to fabricate — either the harness logged it or it did not. For `Agent` rows the equivalent identity already lives in `subagent`.

Two cautions. `Bash` targets are truncated, not sanitized — a command carrying an inline credential records its first 200 characters like any other, so treat the ledger with the care you'd give shell history (it is mode `0600` in a `0700` dir and never leaves the machine). And paths are recorded exactly as the harness supplied them, usually absolute and worktree-prefixed; normalize on the read side if you need them repo-relative.

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
jq -r 'select(.tool == "Bash") | .target | select(. != "")' "$LEDGER"
```

### Files this session touched (Edit/Write)

```bash
jq -r 'select(.tool == "Edit" or .tool == "Write") | .target | select(. != "")' "$LEDGER" | sort -u
```

### Which skills actually loaded

```bash
jq -r 'select(.tool == "Skill") | .target | select(. != "")' "$LEDGER" | sort | uniq -c
```

### Did a specific file get read in a time window

```bash
# The evidence shape a pipeline gate asserts on.
jq -e --arg f "stages/9-open-pr.md" --arg since "2026-04-29T01:00:00Z" \
  'select(.tool == "Read" and .outcome == "ok" and .ts > $since and (.target | endswith($f)))' \
  "$LEDGER" >/dev/null && echo "read confirmed" || echo "no such read"
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
- The ledger has only the fields above. There's no `result_sha` and no hash chain — those were stripped to match the experimental scope, and nothing here detects tampering.
- `target` carries one identifying scalar per row, not a nested argument dump: never the full argv, never stdin, never a `Bash` command's later lines. Queries that need more than identity have to go to the transcript.
