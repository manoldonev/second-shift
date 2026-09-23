# jira tracker adapter

Active when config `tracker.type: jira`. The read-only model: the
operator supplies a JIRA key, and the pipeline treats the tracker as **read-only**
(`tracker.writes: false`). It fetches the ticket via the Atlassian MCP and never
transitions or comments — the run’s audit trail is the PR: the run block the scheduler
posts on it and the review's verdict comment.

> **The "No JIRA writes" principle.** Nothing in the lane calls an Atlassian write tool
> (`transitionJiraIssue`, `addCommentToJiraIssue`, `editJiraIssue`, …). This keeps a run
> to a single outward-facing write — the PR — and avoids a redundant approval gate.
> **What enforces it:** under `tracker.writes: false`, `/dev-pipeline:run` starts every BUILD
> and REVIEW session without the Atlassian write tools (the scheduler's `--disallowedTools`
> list, under all three namespaces below); the read tools stay. **Where it stops:** a
> `/dev-pipeline:review` the operator invokes directly is operator-attended and keeps
> whatever tools that session has.

The table below is this adapter's operation contract. The scheduler's tracker-sensitive
operations are tabulated in [`../README.md`](../README.md#the-pipeline-dev-pipelinerun).

> **Ready, never draft.** The **ready** (non-draft) PR contract holds under both trackers —
> the scheduler's PR conventions check rejects a draft on either adapter.

## Prerequisite

The Atlassian MCP must be connected on the calling session — the ticket is fetched
through it. **Do not assume the `mcp__atlassian__*` prefix:** the MCP's tool
namespace depends on how the session registered the server — `mcp__atlassian__*`
(top-level `mcpServers`), `mcp__plugin_atlassian_atlassian__*` (plugin-bundled), or
`mcp__claude_ai_Atlassian_Rovo__*` (claude.ai Rovo). Call whichever `getJiraIssue` the
session exposes (`ToolSearch` to discover it when it is a deferred tool). A missing MCP
is a fetch-time prerequisite failure, surfaced by the intake surface.

## Operations (all read-only on the tracker)

| Operation | jira implementation |
| --- | --- |
| **pickup** | Operator supplies the JIRA key on invocation (`/dev-pipeline:run PROJ-540 --build-model sonnet` — there is no sizing label to read). No queue, no claim, no label mutation. |
| **fetch-ticket** | `getJiraIssue` for the body; `getJiraIssueRemoteIssueLinks` → `getConfluencePage` for linked design/spec pages — under whichever namespace the session exposes (see **Prerequisite**). |
| **sequential ordering** (`sub-issues-sequential`) | **Operator-enforced:** the ordered sub-ticket specs presented at decomposition carry the `Predecessor:` / `Successor:` trailers and the "start this only once `<predecessor>` is done" note, and the operator honors that sequence when supplying the next key. |
| **post-status-comment** | *no-op.* Progress is on the PR only. |
| **set-status** | *no-op.* The ticket stays in its current JIRA status for the whole run. |
| **create-sub-tickets** (`sub-issues` verdict) | Present ≤5 recommended sub-ticket specs to the operator; make **no** JIRA writes. The operator creates and re-queues them. |
| **close-out** | *no-op.* |
| **branch name** | `<branchPrefix><key-lowercased>`; `branchPrefix` is a per-user identifier + `/` (e.g. `jdoe/` → `jdoe/proj-540`). |
| **PR ticket reference** | Fill the repo’s `pull_request_template.md` `### Jira Items` with `Closes [<KEY>]`; the branch/PR are still on GitHub (`gh pr create`, ready — see **Ready, never draft** above). |

## Deriving `branchPrefix` (the user identifier)

With JIRA the branch prefix is typically a per-user short name, not the git username.
Set it explicitly in config (`tracker.branchPrefix: "jdoe/"`). When it is unset, the scheduler
derives it from the dominant prefix among existing remote branches for your key pattern, and
refuses (exit 2) when there is nothing to derive from — it never prompts, because spawned lane
sessions cannot ask. Config is the durable home; derivation is the fallback.

## One repo per run

The scheduler works exactly one repo's worktree. A consumer whose work spans two repos runs the
lane once per repo, and the split happens at intake: one ticket per target repo.

## Config

```jsonc
"tracker": {
  "type": "jira",
  "writes": false,
  "keyPattern": "[A-Z]+-[0-9]+",
  "branchPrefix": "jdoe/"
}
```

`tracker.bot` is **optional here, not forbidden**. JIRA repos don’t claim through a bot —
there is no queue race, and the scheduler's claim writes nothing to the tracker either way. But
the bot's other job is write identity on the **code host**, and source control is GitHub under
this adapter too: the build's commits, the review's verdict comment and the run block on the PR
are all GitHub writes that happen on every run. Configure a bot and they carry its identity;
omit it and they land as the operator.
