# jira tracker adapter

Active when config `tracker.type: jira`. The read-only model: the
operator supplies a JIRA key, and the pipeline treats the tracker as **read-only**
(`tracker.writes: false`). It fetches the ticket via the Atlassian MCP and never
transitions or comments — the run’s audit trail is the state file
(`.claude/pipeline-state/<key>.json`) plus the draft-PR metadata.

> **The "No JIRA writes" principle.** No stage calls an Atlassian write tool
> (`transitionJiraIssue`, `addCommentToJiraIssue`, `editJiraIssue`, …). A draft PR
> is not "In Review" and must not advance the ticket; the operator moves it manually
> after promoting the PR out of draft. This keeps the pipeline to a single
> outward-facing write (the draft PR) and avoids a redundant approval gate.

## Prerequisite

The Atlassian MCP (`mcp__atlassian__*`) must be connected on the calling session —
Stage 1 fetches the ticket through it. A missing MCP is a fetch-time prerequisite
failure, surfaced by the intake stage.

## Operations (all read-only on the tracker)

| Operation | jira implementation |
| --- | --- |
| **pickup** | Operator supplies the JIRA key on invocation (`/dev-pipeline:run GH-540`). No queue, no claim, no label mutation. |
| **fetch-ticket** | `mcp__atlassian__getJiraIssue` for the body; `mcp__atlassian__getJiraIssueRemoteIssueLinks` → `mcp__atlassian__getConfluencePage` for linked design/spec pages. |
| **post-status-comment** | *no-op.* Progress is written to the state file only. |
| **set-status** | *no-op.* The ticket stays in its current JIRA status for the whole run. |
| **create-sub-tickets** (`sub-issues` verdict) | Present ≤5 recommended sub-ticket specs to the operator; make **no** JIRA writes. The operator creates and re-queues them. |
| **close-out** | *no-op.* |
| **branch name** | `<branchPrefix><key-lowercased>`; `branchPrefix` is a per-user identifier + `/` (e.g. `jdoe/` → `jdoe/gh-540`). Stacked slice N: `…-pr<N>`. |
| **PR ticket reference** | Fill the repo’s `pull_request_template.md` `### Jira Items` with `Closes [<KEY>]`; the branch/PR are still on GitHub (`gh pr create --draft`). |

## Deriving `branchPrefix` (the user identifier)

With JIRA the branch prefix is typically a per-user short name, not the git username.
Set it explicitly in config (`tracker.branchPrefix: "jdoe/"`) or let Stage 2 detect
it once from existing `*/gh-*` branches and confirm with the operator (interactive
priming round), caching it. Config is the durable home; detection is the first-run
convenience. See [`../../../stages/2-worktree.md`](../../../stages/2-worktree.md).

## Topology note

JIRA-model repos are often a **be-fe-pair** (`topology.type: be-fe-pair`): the
ticket summary prefix (`[BE]`, `[FE]`, `[Core]`) routes work to one or both repos
(`topology.repos.<id>.ticketTag`), and Stage 9 opens one draft PR per target repo
with cross-repo companion links. Base branches may differ per repo (BE `alpha`, FE
`main`) — that asymmetry is pure config (`topology.repos.<id>.baseBranch`).

## Config

```jsonc
"tracker": {
  "type": "jira",
  "writes": false,
  "keyPattern": "[A-Z]+-[0-9]+",
  "branchPrefix": "jdoe/"
}
```

No `tracker.bot` block: JIRA repos don’t claim through a bot (there is no queue race),
and the draft PR is created with regular `gh`.
