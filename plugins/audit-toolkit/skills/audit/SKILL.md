---
name: audit
description: Read-only query of the current Claude Code session's tool-call ledger. Surfaces what tools Claude actually invoked (vs. what Claude claims it invoked). Observability only — a visibility signal for manual review.
---

You are the audit query skill. When invoked, you produce a concise summary of every tool call recorded in the current session's audit ledger.

The ledger is written by the audit-toolkit hook (`audit-tool-calls.sh`) on `PostToolUse` / `PostToolUseFailure` / `SubagentStop` / `UserPromptExpansion`. The hook fires automatically once the `audit-toolkit` plugin is enabled (plugin `hooks/hooks.json`); a legacy manual mode wires it via `.claude/settings.local.json`. It is the harness's record of what tools fired AND which slash commands the user invoked, independent of Claude's chat output. **When the two streams disagree, the harness wins.**

**This skill is observability only** — it surfaces signals for manual review and team-convention checks, and nothing here blocks pushes, commits, or any other action. The underlying ledger is separately admissible as evidence for tooling that gates on it (the `target` field exists for that), but `/audit` itself only reports.

## Capabilities

- ✅ Surfaces every tool call recorded since session start.
- ✅ Distinguishes successful (`outcome=ok`) from failed (`outcome=fail`) calls.
- ✅ Surfaces user-typed slash-command loads (`UserPromptExpansion` events).
- ✅ Records what each call ran **on** in `target` — file path, skill name, workflow script, or a `Bash` command's first line. See `QUERIES.md`.
- ✅ Sees `Skill()` tool invocations, including programmatic ones: they arrive as `PostToolUse` rows with `tool: "Skill"`, and `target` carries the skill name.
- ❌ No hash chain or tamper detection (lean version has none).
- ❌ Does NOT block pushes / PR creation. This is a visibility signal, not a gate.

## Inputs

- **Optional**: `--session-id <ID>` — query a specific session's ledger instead of the current one.
- **Default**: query the most-recently-modified ledger.

## Process

### Step 1: Locate ledger — and onboard if missing

The ledger directory is anchored on the **main checkout**, not on whatever directory the session is running in — the hook resolves `--git-common-dir/..` so one repo family has one ledger directory, and a session working in a linked worktree is still found. Resolve it before looking for anything:

```bash
AUDIT_DIR="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/.claude/audit"
LEDGER=$(ls -t "$AUDIT_DIR"/*.jsonl 2>/dev/null | head -1)
```

If `$LEDGER` is empty, **do not produce an audit report**. Instead, output the onboarding instructions verbatim to the user (substituting the resolved `$AUDIT_DIR` for the paths below). Two cases:

**Case A — no `$AUDIT_DIR` at all (the audit hook has never fired here):**

> The audit ledger is empty for this session — the audit hook hasn't written anything in this repo yet. The audit infrastructure is observability only (a small per-tool-call cost).
>
> To enable visibility into what tools Claude actually invokes: **enable the `audit-toolkit` plugin** for this repo. Its `hooks/hooks.json` wires the ledger writer automatically — nothing to copy. (Legacy/manual mode, for a repo not adopting the plugin, copies `templates/settings.audit-template.json` to `.claude/settings.local.json` and restarts Claude Code.)
>
> After the plugin is enabled, every tool call in this repo — including sessions running in a linked worktree — is appended to a per-session JSONL ledger under the main checkout's `.claude/audit/`. Run `/audit` again to see it.
>
> Full setup notes: the audit `SETUP.md`. The system is observability only — it never blocks pushes or commits.

**Case B — `$AUDIT_DIR` exists but has no `*.jsonl` for this session (the hook is wired but no tool calls have fired yet):**

> The audit ledger directory exists, but no ledger has been written for the current session yet.
>
> Two likely causes:
>
> 1. **The plugin/hook was enabled mid-session.** Hook wiring is loaded at session start. Restart Claude Code, run a couple of tool calls, then re-run `/audit`.
> 2. **No tool calls have fired in this session yet.** Use any tool (Read, Edit, Bash, etc.), then re-run `/audit`.
>
> If neither applies, confirm the `audit-toolkit` plugin is enabled (or, in legacy manual mode, that `.claude/settings.local.json` has a `hooks.PostToolUse` entry pointing at the audit hook).

Distinguish A from B by `[ -d "$AUDIT_DIR" ]`. If even the directory is missing, that's Case A. Otherwise Case B.

### Step 2: Aggregate counts

Walk the ledger:

- Total rows; rows per `tool` (PostToolUse breakdown); failure count.
- `Agent` dispatches: list with counts per `subagent`.
- `UserPromptExpansion` events: list with `command_name`s.
- `Skill` loads: list with counts per `target` (the skill name).
- Files touched: unique `target` values for `Edit` / `Write` rows.

### Step 3: Render report

```
## Audit — session <SID>

### Activity
- Total tool calls:        <N>
- Agent dispatches:        <M>
- Failed calls:            <F>
- Slash-command loads:     <K>  (commands: <list>)

### Top tools
  Bash×<n>  Edit×<n>  Read×<n>  ...

### Subagent dispatches
  security-reviewer×<n>  performance-reviewer×<n>  ...
  (or: "(none)")

### Skills loaded
  review-toolkit:review-lead×<n>  intake-toolkit:intake-orchestrator×<n>  ...
  (or: "(none)")

### Files touched (Edit/Write)
  <path>  <path>  ...
  (or: "(none)")

### Time range
First entry: <ts>; last entry: <ts>; ledger size: <KB>.
```

### Step 5: Hand-off pointers

> Inspect the raw ledger:
> `jq '.' "$AUDIT_DIR"/<SID>.jsonl | less`
>
> Filter for subagent dispatches:
> `jq -c 'select(.tool == "Agent")' "$AUDIT_DIR"/<SID>.jsonl`
>
> Aggregate across the last N days:
> `/audit-history 14`
>
> See more queries: the audit `QUERIES.md`

## What NOT to do

- **Do not edit the ledger.** It's the truth source.
- **Do not invent rows.** If a row isn't there, the tool wasn't invoked (or the hook isn't installed).
- **Do not claim "dispatch happened" if no `tool: "Agent"` row exists.** That's the trust failure this skill exists to surface.
- **Do not claim the audit gates pushes.** It does not.

## Background

This audit skill surfaces claimed-vs-actual sub-agent tool calls: a read-only window onto what tools actually fired, so any gap between what Claude's chat output reports and what the harness recorded is _visible_ even when not auto-blocked.
