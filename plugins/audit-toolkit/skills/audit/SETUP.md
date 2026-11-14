# Audit ledger — setup

The audit system gives you on-demand and after-the-fact visibility into what tools Claude actually invoked during a session, vs. what Claude's chat output claims it invoked.

**The ledger is advisory.** `/audit` and `/audit-history` surface drift in their reports, and follow-up is by team convention, not by an automatic block. Nothing in this plugin blocks pushes, commits, or PRs.

## How the hooks get wired

The audit hooks ship in this plugin's `hooks/hooks.json`. Once the `audit-toolkit` plugin is enabled for the repo, the hooks fire **automatically** on `PostToolUse` / `PostToolUseFailure` / `SubagentStop` / `UserPromptExpansion` — no per-engineer settings edit, no restart dance beyond enabling the plugin. Nothing to copy.

## Cost

The hook adds a small per-tool-call cost (~1–2 ms). It's on for everyone using the plugin; if that overhead is unwelcome for a given repo, disable the plugin rather than editing the hook.

## What you get

- **Ledger** at `<main checkout>/.claude/audit/{session_id}.jsonl` (gitignored, in the consumer repo). The directory is resolved as `--git-common-dir/..`, so one repo family has **one** ledger directory and a session working in a linked worktree writes there too — the same anchor every reader uses. (When that resolution yields nothing — a non-git project directory — the hook falls back to `$CLAUDE_PROJECT_DIR/.claude/audit` rather than blocking the session.) One JSON row per tool call, with these fields (kept in lockstep with `QUERIES.md`; pair `audit-row-fields`):

  <!-- LOCKSTEP: held verbatim to the audit QUERIES.md field list, which carries the reasoning. -->
  <!-- LOCKSTEP-BEGIN audit-row-fields -->
  `ts`, `session_id`, `event`, `tool`, `subagent`, `command_name`, `target`, `outcome`
  <!-- LOCKSTEP-END audit-row-fields -->

  `target` is what the call ran **on** — the file path for `Read`/`Edit`/`Write`, the first line of a `Bash` command (capped at 200 chars), the skill name for `Skill`, the script path for `Workflow`, and `""` for everything else. Per-tool table and query recipes: `QUERIES.md`.
- **`/audit`** slash command — read-only summary of the current session's tool calls, with subagent dispatch counts.
- **`/audit-history N`** slash command — aggregator across the last N days. Surfaces top dispatched subagents and top loaded orchestrators.

## What you do NOT get

- No automatic block on push or PR-create. The audit cannot stop `git push`.
- No tamper detection. Hash chain was removed for simplicity; the ledger is plain JSONL.

## Verify

After the plugin is enabled, run a few tool calls (anything will do). Then:

```bash
# Confirm the ledger is being written (in the consumer repo). The directory is
# anchored on the main checkout even when you run this from a linked worktree.
ls "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/.claude/audit/"

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

Disable the `audit-toolkit` plugin for the repo. The hooks stop firing.

There was no team-wide enforcement to begin with — the audit is observability — so opting out simply turns off the visibility signals for your sessions.

## Background

This audit infrastructure surfaces claimed-vs-actual sub-agent tool calls: harness-level evidence of what tools actually fired, independent of Claude's chat output, so any gap between the two is visible.
