# Tracker adapters

The dev-pipeline is tracker-agnostic in its machinery and tracker-specific only at
its edges. Which adapter is active is decided by **config `tracker.type`** (layer 1
per [`docs/context-model.md`](../../../../docs/context-model.md)); the machinery
(the scheduler [`run.sh`](../../skills/run/run.sh) and the shared tools in [`../`](..)) is
layer-0 and identical for both.

Two adapters ship:

| Adapter | Home | Consumer set | Posture |
| --- | --- | --- | --- |
| **github** | [`github/`](github/) → shell tools in [`../`](..) | queue + claim model | queue + claim + comment (writes back to the tracker) |
| **jira** | [`jira/`](jira/) | read-only JIRA shops | **read-only** — fetch the ticket via MCP, never transition or comment |

## The operation contract

Every tracker touch resolves through one of these abstract operations. The adapter
column tells the operator/agent what each resolves to under the active `tracker.type`.
Operations marked *no-op* under a tracker are deliberately absent there — a
`tracker.writes: false` adapter’s audit trail is the PR — the run block the scheduler posts
on it and the review's verdict comment — not the ticket.

The table below is the adapter-wide contract, shared by the intake surface and the
pipeline; the scheduler's own tracker-sensitive operations follow it.

| Operation | github (`tracker.type: github`) | jira (`tracker.type: jira`) |
| --- | --- | --- |
| **pickup** — select the next unit of work | queue query (`gh issue list --label ready-for-dev`) then atomic claim ([`../claim-issue.sh`](../claim-issue.sh), label swap `ready-for-dev`→`in-progress`) | operator supplies the JIRA key; no queue, no claim |
| **fetch-ticket** — load body + comments | `gh api repos/{o}/{r}/issues/$KEY` (+ `/comments`) | `getJiraIssue` (+ remote links → `getConfluencePage`), under whichever Atlassian namespace the session exposes — see the note below |
| **set-status** — advance the tracker’s own status | label swaps via `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"` | *no-op* — operator moves the ticket manually |
| **create-sub-tickets** — decomposition into `sub-issues` | auto-create ≤5 sub-issues with `ready-for-dev`; parent → `epic` | present ≤5 sub-ticket specs to the operator; no JIRA writes |
| **close-out** — release the work item | `pr-revision` removes `in-progress` via `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"`; the pipeline removes nothing — the optional `second-shift-unclaim` workflow releases the claimed and queue labels when the issue closes | *no-op* |
| **branch name** — the work branch | `<branchPrefix><key>` (`claude/acme-42`) | `<branchPrefix><key>` (`jdoe/gh-540`) |
| **PR ticket reference** — link the PR back | `Closes #<key>` | `Closes [<KEY>]` in the template’s `### Jira Items` section |

### The pipeline (`/dev-pipeline:run`)

The scheduler, [`run.sh`](../../skills/run/run.sh), resolves the same `tracker.type` (absent ⇒
`github`), rejects an unrecognized value rather than falling through to an arm, and branches at
these sites only. Everything else — the record, the checks, the route smoke, the review's
verdict comment — is adapter-insensitive.

| Operation | github | jira |
| --- | --- | --- |
| **entry** — the queue-label confirm | the queue label, or a claim this run can re-enter; neither stops the run (`not-queued`, exit 3), no prompting. A claimed label with no lane claim marker stops as `claimed-elsewhere` (exit 2) unless `--resume` is passed | *not applicable* — no queue, no label; the operator supplies the key |
| **claim** | two writes: the label swap plus a `lean-claimed` marker comment | *no tracker write* — operator-attested |
| **build model** | the ticket's `opus` / `sonnet` label | `--build-model` is required: there is no label to read |
| **exit** | ready PR carrying `Closes #<key>` + the record link; a closing comment on the issue with the terminal and the cost | ready PR carrying `Closes [<KEY>]` under a `### Jira Items` heading + the record link; nothing is written to the ticket |

The **ready-PR** requirement is adapter-independent: there is no draft stage on either adapter.

> **Atlassian MCP namespace (jira fetch).** Do not hardcode a single prefix: the MCP's
> tool namespace depends on how the session registered the server — `mcp__atlassian__*`
> (top-level `mcpServers`), `mcp__plugin_atlassian_atlassian__*` (plugin-bundled), or
> `mcp__claude_ai_Atlassian_Rovo__*` (claude.ai Rovo). Call whichever `getJiraIssue` the
> session exposes (`ToolSearch` to discover a deferred tool). Full contract:
> [`jira/README.md`](jira/README.md).

## Config that drives the adapter (all layer 1)

- `tracker.type` — selects the adapter (`github` | `jira`).
- `tracker.writes` — whether tracker-write operations fire (`true` for github’s
  queue/comment model; `false` for the read-only JIRA model). A `false` value
  turns *post-status-comment* / *set-status* / *close-out* into no-ops.
- `tracker.keyPattern` — anchored regex the ticket key must match (`[0-9]+` github,
  `[A-Z]+-[0-9]+` jira). The scheduler refuses a key that does not match it, and the branch
  derivation reads it.
- `tracker.branchPrefix` — the branch namespace prepended to the key (`claude/acme-`
  github, a per-user `jdoe/` jira). Consumed by the scheduler's branch derivation
  ([`../branch-prefix.sh`](../branch-prefix.sh)).
- `tracker.bot.*` — the bot identity for the pipeline's **GitHub** writes
  (`enabled`, `envVar`, `wrapperPath`, `app.{clientId,appName,privateKeyFilename,installationId}`).
  Legal under **either** tracker: the key is scoped to the code host, not to the tracker, and
  source control is GitHub for every adapter. Only the *claim* write is github-tracker-only,
  because only a writing tracker has an issue to claim on.

## Why the github tools live in `../`, not `github/`

`claim-issue.sh`, `install-gh-bot.sh`, and `claim-selftest.sh` are the github
adapter’s implementation and stay at `../` (the tools root) because the scheduler and
`claim-selftest.sh` pin their paths. `github/README.md` points at them; this directory is
the adapter *contract*, not a second copy of the scripts.
