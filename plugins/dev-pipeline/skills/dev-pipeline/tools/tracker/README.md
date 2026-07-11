# Tracker adapters

The dev-pipeline is tracker-agnostic in its machinery and tracker-specific only at
its edges. Which adapter is active is decided by **config `tracker.type`** (layer 1
per [`docs/context-model.md`](../../../../../docs/context-model.md)); the machinery
(statectl, verifyctl, the stage state-machine) is layer-0 and identical for both.

Two adapters ship:

| Adapter | Home | Consumer set | Posture |
| --- | --- | --- | --- |
| **github** | [`github/`](github/) → shell tools in [`../`](..) | acme lineage | queue + claim + comment (writes back to the tracker) |
| **jira** | [`jira/`](jira/) | read-only JIRA shops | **read-only** — fetch the ticket via MCP, never transition or comment |

## The operation contract

Every stage that touches the tracker calls one of these abstract operations. The
adapter column tells the operator/agent what each resolves to under the active
`tracker.type`. Operations marked *no-op* under a tracker are deliberately absent
there — a `tracker.writes: false` adapter’s audit trail is the state file plus the
draft-PR metadata, not the ticket.

| Operation | github (`tracker.type: github`) | jira (`tracker.type: jira`) |
| --- | --- | --- |
| **pickup** — select the next unit of work | queue query (`gh issue list --label ready-for-dev`) then atomic claim ([`../claim-issue.sh`](../claim-issue.sh), label swap `ready-for-dev`→`in-progress`) | operator supplies the JIRA key; no queue, no claim |
| **fetch-ticket** — load body + comments | `gh api repos/{o}/{r}/issues/$KEY` (+ `/comments`) | `mcp__atlassian__getJiraIssue` (+ remote links → `mcp__atlassian__getConfluencePage`) |
| **post-status-comment** — surface stage progress | REST comment via `$GH_BOT` (see SKILL.md Bot Identity) | *no-op* (`tracker.writes: false` — no JIRA comment mirror) |
| **set-status** — advance the tracker’s own status | label swaps via `$GH_BOT` | *no-op* — operator moves the ticket manually after promoting the PR |
| **create-sub-tickets** — decomposition into `sub-issues` | auto-create ≤5 sub-issues with `ready-for-dev`; parent → `epic` | present ≤5 sub-ticket specs to the operator; no JIRA writes |
| **close-out** — release the work item | remove `in-progress` label via `$GH_BOT` | *no-op* |
| **branch name** — the work branch | `<branchPrefix><key>` (`claude/acme-42`) | `<branchPrefix><key>` (`jdoe/gh-540`) |
| **PR ticket reference** — link the PR back | `Closes #<key>` | `Closes [<KEY>]` in the template’s `### Jira Items` section |

## Config that drives the adapter (all layer 1)

- `tracker.type` — selects the adapter (`github` | `jira`).
- `tracker.writes` — whether tracker-write operations fire (`true` for github’s
  queue/comment model; `false` for the JIRA read-only lineage). A `false` value
  turns *post-status-comment* / *set-status* / *close-out* into no-ops.
- `tracker.keyPattern` — anchored regex the ticket key must match at `statectl init`
  (`[0-9]+` github, `[A-Z]+-[0-9]+` jira). One statectl, tracker-shaped validation.
- `tracker.branchPrefix` — the branch namespace prepended to the key (`claude/acme-`
  github, a per-user `jdoe/` jira). Consumed by `../max-pushed-slice.sh` (`$BRANCH_PREFIX`)
  and the Stage-1/2/9 branch derivation.
- `tracker.bot.*` — github only: the bot identity for tracker/PR writes
  (`enabled`, `envVar`, `wrapperPath`, `app.{clientId,appName,privateKeyFilename,installationId}`).

## Why the github tools live in `../`, not `github/`

`claim-issue.sh`, `install-gh-bot.sh`, and `claim-selftest.sh` are the github
adapter’s implementation and stay at `../` (the tools root) because a web of
drift-parity checks (`claim-selftest.sh`, `pipeline-doctor.sh`, the stage prose)
pins their paths. `github/README.md` points at them; this directory is the
adapter *contract*, not a second copy of the scripts.
