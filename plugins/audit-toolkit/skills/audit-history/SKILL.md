---
name: audit-history
description: Cross-session aggregator for the audit ledger. Walks every .claude/audit/*.jsonl in the recent N-day window and surfaces visibility signals for manual review. Observability only.
---

You are the audit-history skill. You aggregate across all session ledgers in the project and report:

- **Activity totals** — total `Agent` dispatches; top-N dispatched subagents; top-N loaded orchestrators (UPE captures).

This skill is **read-only**. It does not modify ledgers, registries, or sessions. The implementation is the plugin-bundled `scripts/audit-history.sh` (`${CLAUDE_PLUGIN_ROOT}/scripts/audit-history.sh`).

## Inputs

- **Optional**: `[days]` — positional argument, default `30`. Only sessions modified within the last N days are included.
- **Optional**: `--json` — emit machine-readable JSON instead of text.

## Process

When invoked, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/audit-history.sh" [days] [--json]
```

The script handles: filesystem walk, aggregate counts, and top-N histograms. The output is human-readable markdown by default; surface it directly to the user.

## What this answers

1. **Which orchestrators are most-used?** Top-loaded list (uses `UserPromptExpansion` captures).
2. **Which subagents fire most?** Top-dispatched list — useful as a sanity check on team review patterns.
3. **What's the overall dispatch posture?** A trending dispatch count is a signal to spot-check `/audit --session-id <SID>` for specific sessions.

## Limitations

- **Visibility signal only.** This skill surfaces counts for **manual review**; nothing is blocked.
- **Per-session detail requires `UserPromptExpansion` capture** (i.e. the audit-toolkit plugin/hook was enabled for that session). Sessions without UPE rows have no signal that an orchestrator was loaded.
- **`Skill()` tool calls are invisible.** Claude Code does not fire `PostToolUse` for programmatic skill loads, so `/dev-pipeline → review-lead` nested loads are not visible in the ledger. Only direct user-typed `/orchestrator-skill` slash commands produce visibility signals.
- **No tamper detection.** The lean audit has no hash chain. The ledger is plain JSONL; a teammate with shell access could rewrite it.

## When to use this

- **Periodically**, e.g. once a week, as a team-convention check on dispatch patterns.
- **After enabling the audit hooks** for the first time, to baseline the existing ledger files.
- **When debugging**, point at a specific date range to see what the team's Claude sessions actually invoked.

## Output format

Default text output is markdown — directly readable. JSON via `--json` is for piping into other tools (e.g. dashboards).

## What this is NOT

- Not real-time. Reads existing files; doesn't subscribe to live updates.
- Not a replacement for the on-demand `/audit` slash command (which queries the current session's ledger).
- Not a push gate or any kind of automatic block. The lean audit is a visibility signal only.
- Not a tamper-resistant attestation. If the ledger files were rewritten, this aggregator can't detect it.
