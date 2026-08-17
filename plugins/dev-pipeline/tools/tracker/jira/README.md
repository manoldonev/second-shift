# jira tracker adapter

Active when config `tracker.type: jira`. The read-only model: the
operator supplies a JIRA key, and the pipeline treats the tracker as **read-only**
(`tracker.writes: false`). It fetches the ticket via the Atlassian MCP and never
transitions or comments — the run’s audit trail is the run’s own record (the lean
lane’s progress file, `.claude/pipeline-state/<key>-lean-progress.md`) plus the PR
metadata.

> **The "No JIRA writes" principle.** Nothing in the lane calls an Atlassian write tool
> (`transitionJiraIssue`, `addCommentToJiraIssue`, `editJiraIssue`, …). This keeps a run
> to a single outward-facing write — the PR — and avoids a redundant approval gate.

The table below is this adapter's operation contract. The lean lane’s gate-sensitive
operations are tabulated in [`../README.md`](../README.md#the-lean-lane-dev-pipelinerun-lean).

> **Ready, never draft.** The **ready** (non-draft) PR contract holds under both trackers —
> `lean-gate.sh` milestone 5 rejects a draft on either adapter. The draft-PR carve-out that
> used to apply here belonged to the staged lane's manual promotion step, deleted in #348;
> there is no promotion step left for a draft to advance out of.

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
| **pickup** | Operator supplies the JIRA key on invocation (`/dev-pipeline:run-lean GH-540`). No queue, no claim, no label mutation. |
| **fetch-ticket** | `getJiraIssue` for the body; `getJiraIssueRemoteIssueLinks` → `getConfluencePage` for linked design/spec pages — under whichever namespace the session exposes (see **Prerequisite**). |
| **predecessor-read** (`sub-issues-sequential` ordering) | ***SKIP-with-note.*** Both reads the github adapter pays — the candidate's body and the predecessor's state — are session-side MCP here, unreachable from a shell tool, so `../../predecessor-gate.sh` is never invoked (the **preflight-read** precedent). **Ordering is operator-enforced with no machine gate:** the ordered sub-ticket specs presented at decomposition carry the `Predecessor:` / `Successor:` trailers and the "start this only once `<predecessor>` is done" note, and the operator honors that sequence when supplying the next key. The trailer-rendering rule exists here solely for that presented spec text. |
| **post-status-comment** | *no-op.* Progress is written to the lane's progress file only. |
| **set-status** | *no-op.* The ticket stays in its current JIRA status for the whole run. |
| **create-sub-tickets** (`sub-issues` verdict) | Present ≤5 recommended sub-ticket specs to the operator; make **no** JIRA writes. The operator creates and re-queues them. |
| **close-out** | *no-op.* |
| **branch name** | `<branchPrefix><key-lowercased>`; `branchPrefix` is a per-user identifier + `/` (e.g. `jdoe/` → `jdoe/gh-540`). |
| **PR ticket reference** | Fill the repo’s `pull_request_template.md` `### Jira Items` with `Closes [<KEY>]`; the branch/PR are still on GitHub (`gh pr create`, ready — see **Ready, never draft** above). |

## Deriving `branchPrefix` (the user identifier)

With JIRA the branch prefix is typically a per-user short name, not the git username.
Set it explicitly in config (`tracker.branchPrefix: "jdoe/"`) or derive it once from
existing `*/gh-*` branches and confirm with the operator before cutting the worktree
(build-lean step 3). Config is the durable home; detection is the first-run convenience.
The staged lane's Stage-2 detection step that used to own this is deleted (#348), so
**config is now the only durable home** — an unset `branchPrefix` is an operator prompt,
not a cached derivation.

## Topology note

JIRA-model repos are often a **be-fe-pair** (`topology.type: be-fe-pair`): the
ticket summary prefix (`[BE]`, `[FE]`, `[Core]`) routes work to one or both repos
(`topology.repos.<id>.ticketTag`). Base branches may differ per repo (BE `alpha`, FE
`main`) — that asymmetry is pure config (`topology.repos.<id>.baseBranch`).

**The per-repo PR fan-out did not survive #348.** The staged lane's Stage 9 opened one
draft PR per target repo with cross-repo companion links; that capability is recorded
`dropped` in [`tools/capability-parity.tsv`](../../../../../tools/capability-parity.tsv).
Under the lean lane a pair consumer **runs the lane once per repo** — the cross-repo
split happens at intake, which files one ticket per target repo. `ticketTag` is therefore
advisory routing for whoever launches the session, not a gate input.

## Config

```jsonc
"tracker": {
  "type": "jira",
  "writes": false,
  "keyPattern": "[A-Z]+-[0-9]+",
  "branchPrefix": "jdoe/"
}
```

`tracker.bot` is **optional here, not forbidden** (#440). JIRA repos don’t claim through a
bot — there is no queue race, and `lean-gate.sh claim` writes nothing to the tracker either
way. But the bot's other job is write identity on the **code host**, and source control is
GitHub under this adapter too: PR comments, the step-7 PR marker, the cost-block PATCH and
the git committer are all GitHub writes that happen on every run. Configure a bot and they
carry its identity, and the merge boundary's identity arm gates at full strength. Omit it and
they land as the operator, with that arm announcing itself unavailable at reduced strength.
