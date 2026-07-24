# Audit ledger — setup

The audit system gives you on-demand and after-the-fact visibility into what tools Claude actually invoked during a session, vs. what Claude's chat output claims it invoked. **It is observability only — a visibility signal for manual review.** Nothing here blocks pushes, commits, or PRs. Drift is surfaced in `/audit` and `/audit-history` reports; follow-up is by team convention, not by an automatic block.

## How the hooks get wired

**Plugin mode (default).** The audit hooks ship in this plugin's `hooks/hooks.json`. Once the `audit-toolkit` plugin is enabled for the repo, the hooks fire **automatically** on `PostToolUse` / `PostToolUseFailure` / `SubagentStop` / `UserPromptExpansion` — no per-engineer settings edit, no restart dance beyond enabling the plugin. Nothing to copy.

**Legacy / manual mode.** For a repo that wants the ledger writer but is *not* adopting the plugin (or an engineer who wants a local, per-checkout opt-in), wire the hook by hand from the template:

```bash
cp <plugin>/templates/settings.audit-template.json .claude/settings.local.json
# OR, if you already have a settings.local.json, merge its `hooks` block by hand.
# Then restart Claude Code.
```

`settings.local.json` is gitignored, so manual mode is per-engineer.

## Cost

The hook adds a small per-tool-call cost (~1–2 ms). In plugin mode it's on for everyone using the plugin; if that overhead is unwelcome for a given repo, disable the plugin (or use `reviewers`/`gates`-style config to keep it off) rather than editing the hook.

## What you get

- **Ledger** at `.claude/audit/{session_id}.jsonl` (gitignored, in the consumer repo). One JSON row per tool call: `ts, event, tool, subagent, command_name, outcome`.
- **`/audit`** slash command — read-only summary of the current session's tool calls, with subagent dispatch counts.
- **`/audit-history N`** slash command — aggregator across the last N days. Surfaces top dispatched subagents and top loaded orchestrators.

## What you do NOT get

- No automatic block on push or PR-create. The audit cannot stop `git push`.
- No tamper detection. Hash chain was removed for simplicity; the ledger is plain JSONL.

## Verify

After the plugin is enabled (or manual mode is wired + Claude Code restarted), run a few tool calls (anything will do). Then:

```bash
# Confirm the ledger is being written (in the consumer repo).
ls .claude/audit/

# Query the current session.
/audit-toolkit:audit

# Aggregate across the last 14 days.
/audit-toolkit:audit-history 14
```

Plugin maintainers can run the smoke test directly against the plugin checkout:

```bash
<plugin>/scripts/audit-selftest.sh
```

## Disable / opt out

- **Plugin mode**: disable the `audit-toolkit` plugin for the repo. The hooks stop firing.
- **Manual mode**: remove the `"hooks"` block from `.claude/settings.local.json` and restart Claude Code.

There was no team-wide enforcement to begin with — the audit is observability — so opting out simply turns off the visibility signals for your sessions.

## Background

This audit infrastructure surfaces claimed-vs-actual sub-agent tool calls: harness-level evidence of what tools actually fired, independent of Claude's chat output, so any gap between the two is visible.
