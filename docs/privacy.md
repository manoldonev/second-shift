# Privacy

second-shift is a set of Claude Code plugins that run on your machine, inside your own Claude Code sessions. It has no servers, collects no telemetry, and sends nothing to its author.

## What it reads and writes

- **Your repository.** Onboard writes `.claude/second-shift.config.json`, `.claude/settings.json`, `.claude/second-shift.lock.json` and `.claude/SECOND-SHIFT.md`. A pipeline run writes its intake record under `docs/plans/` and its logs under `.claude/pipeline-state/`. You decide what to commit.
- **Your tracker and code host, through your own tools.** The plugins call GitHub through your `gh` login, to read issues, create labels, branches, pull requests and comments in your repo, and to read second-shift's public releases. Under JIRA they use the Atlassian MCP server you connected. Nothing goes to these services except what those actions need.
- **Figma or Claude Design, if you turn design support on.** The design plugin reads the frames or handoff you point it at.
- **The audit log.** audit-toolkit records the agent's tool calls in `.claude/audit/` on your machine. It stays there.

second-shift reads no credentials of its own. `gh`, git and MCP servers use their own logins. When doctor prints your config for a bug report, it masks the value of every key named like a secret.

## Retention

The author keeps nothing, because nothing reaches the author. Files in your repository and on your machine stay until you delete them. What GitHub, JIRA or Figma keep follows their own policies.

## Claude

What you and the plugins send to Claude is handled under Anthropic's terms and [privacy policy](https://www.anthropic.com/legal/privacy), as for any Claude Code session.

## Contact

Questions: [GitHub Issues](https://github.com/manoldonev/second-shift/issues). Security problems: [SECURITY.md](../SECURITY.md).
