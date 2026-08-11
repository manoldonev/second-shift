# Tracker adapters

The dev-pipeline is tracker-agnostic in its machinery and tracker-specific only at
its edges. Which adapter is active is decided by **config `tracker.type`** (layer 1
per [`docs/context-model.md`](../../../../../docs/context-model.md)); the machinery
(statectl, verifyctl, the stage state-machine) is layer-0 and identical for both.

Two adapters ship:

| Adapter | Home | Consumer set | Posture |
| --- | --- | --- | --- |
| **github** | [`github/`](github/) → shell tools in [`../`](..) | queue + claim model | queue + claim + comment (writes back to the tracker) |
| **jira** | [`jira/`](jira/) | read-only JIRA shops | **read-only** — fetch the ticket via MCP, never transition or comment |

## The operation contract

Every stage that touches the tracker calls one of these abstract operations. The
adapter column tells the operator/agent what each resolves to under the active
`tracker.type`. Operations marked *no-op* under a tracker are deliberately absent
there — a `tracker.writes: false` adapter’s audit trail is the run’s own record (the
`run` lane’s state file, the lean lane’s progress file) plus the PR metadata, not the
ticket.

The table below is the **`run` lane’s** operation contract; the lean lane’s
adapter-sensitive operations follow it.

| Operation | github (`tracker.type: github`) | jira (`tracker.type: jira`) |
| --- | --- | --- |
| **pickup** — select the next unit of work | queue query (`gh issue list --label ready-for-dev`) then atomic claim ([`../claim-issue.sh`](../claim-issue.sh), label swap `ready-for-dev`→`in-progress`) | operator supplies the JIRA key; no queue, no claim |
| **fetch-ticket** — load body + comments | `gh api repos/{o}/{r}/issues/$KEY` (+ `/comments`) | `getJiraIssue` (+ remote links → `getConfluencePage`), under whichever Atlassian namespace the session exposes — see the note below |
| **preflight-read** — the read-only onboarding finish line's single tracker READ ([`../preflight.sh`](../preflight.sh), no claim) | `gh api repos/{o}/{r}/issues/$KEY` with a key; queue head via `gh issue list --label <queue>` without one | *SKIP-with-note* — the jira fetch is session-side MCP, unreachable from a shell tool |
| **predecessor-read** — the pre-claim ordering check for a `sub-issues-sequential` chain ([`../predecessor-gate.sh`](../predecessor-gate.sh), before any claim) | **two reads.** (1) the candidate's own body, folded into the pickup query (`--json` gains `body`) and piped to `predecessor-gate.sh extract` — paid **per candidate examined**, and reused downstream by the intake fan-out and the AC snapshot rather than re-fetched. (2) `gh api repos/{o}/{r}/issues/<predecessorKey> --jq .state`, fed to `predecessor-gate.sh verdict` — paid **only** when read (1) printed a `predecessor=` line | *SKIP-with-note* — the jira fetch is session-side MCP, unreachable from a shell tool (the *preflight-read* precedent). Sequential ordering is **operator-enforced** here, with no machine gate; the trailers exist only in the ordered specs presented to the operator |
| **set-status** — advance the tracker’s own status | label swaps via `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/gh-bot.sh"` | *no-op* — operator moves the ticket manually after promoting the PR |
| **create-sub-tickets** — decomposition into `sub-issues` | auto-create ≤5 sub-issues with `ready-for-dev`; parent → `epic` | present ≤5 sub-ticket specs to the operator; no JIRA writes |
| **close-out** — release the work item | remove `in-progress` label via `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/gh-bot.sh"` | *no-op* |
| **branch name** — the work branch | `<branchPrefix><key>` (`claude/acme-42`) | `<branchPrefix><key>` (`jdoe/gh-540`) |
| **PR ticket reference** — link the PR back | `Closes #<key>` | `Closes [<KEY>]` in the template’s `### Jira Items` section |

### The lean lane (`/dev-pipeline:run-lean`)

The lean lane is the default and has no stages and no state file: its records are the
progress file plus three committed artifacts. [`lean-gate.sh`](../../../build-lean/lean-gate.sh)
resolves the same `tracker.type` (absent ⇒ `github`) and branches at tracker-sensitive
sites. Milestones 1–4 are adapter-insensitive — a committed spec, two repo policy scripts,
the config command table, a committed verdict record — and stay that way.
[`lean-reconcile.sh`](../../../build-lean/lean-reconcile.sh) resolves the same key on the same
terms, and branches at its own tracker-sensitive sites. Both reject an unrecognized value
rather than falling through to an arm.

| Operation | github | jira |
| --- | --- | --- |
| **entry** — SKILL.md step 1’s queue-label confirm | confirm the queue label; a missing one is a reject, no prompting | *not applicable* — no queue, no label; the gate prints the adapter note and the operator supplies the key |
| **claim** (`lean-gate.sh claim`) | two bot-wrapper writes: the label swap plus a `lean-claimed` marker comment | *no tracker write.* The run-id/claim record still lands in the progress file — the anchor the reconcile row below reads — and `GH_BOT` is not required |
| **exit** (`lean-gate.sh 5`) | ready PR carrying `Closes #<key>` + the spec link, plus a closing comment referencing the verdict record | ready PR carrying `Closes [<KEY>]` under a `Jira Items` heading, the spec link, and the verdict-record path **in the body**; the comment trail is never read |
| **reconcile** — the operator’s pre-merge check ([`lean-reconcile.sh`](../../../build-lean/lean-reconcile.sh)) | every arm; check (1) compares the bot claim comment’s `run_id` against the progress file’s | **all but one.** Check (1)’s claim arm is skipped and the fetch is never attempted, so the run makes no `gh` call; every other arm runs unchanged. The dropped arm is named in the output and on the closing line. `--comments-file` is refused here |

The **ready-PR** requirement is adapter-independent. lean has no promotion step for a draft
to advance out of, so the `run` lane’s draft-PR rationale (below) does not carry over.

> **Partial integrity backstop under jira.** lean has two integrity checks, and they diverge
> here. `lean-reconcile.sh` (operator-run) keeps every arm but one: only the claim-comment
> comparison needs a tracker, and the rest read git, the progress file, the verdict record and
> the audit ledger — including the P10 authorship check, which is what the
> generation-must-not-author-evaluation separation rests on. It states which arm did not run, so
> a green jira reconcile cannot be read as the full github-strength attestation.
>
> The merge boundary `scripts/check-lean-chain.sh` (CI) remains **github-only**: it keys off the
> bot-authored `lean-claimed` comment, which this adapter posts none of. A jira run therefore has
> an operator-run backstop and no automated one; adapting the CI gate is out of this lane’s scope
> and tracked separately.

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
- `tracker.keyPattern` — anchored regex the ticket key must match at `statectl init`
  (`[0-9]+` github, `[A-Z]+-[0-9]+` jira). One statectl, tracker-shaped validation.
  Also consumed by `../predecessor-gate.sh` (`$KEY_PATTERN`) to extract and render
  `Predecessor:` / `Successor:` trailer keys in the adapter's own key shape, and by
  `statectl successor-key-set` to validate the key it persists.
- `tracker.branchPrefix` — the branch namespace prepended to the key (`claude/acme-`
  github, a per-user `jdoe/` jira). Consumed by the Stage-1/2/9 branch derivation.
- `tracker.bot.*` — the bot identity for the pipeline's **GitHub** writes
  (`enabled`, `envVar`, `wrapperPath`, `app.{clientId,appName,privateKeyFilename,installationId}`).
  Legal under **either** tracker: the key is scoped to the code host, not to the tracker, and
  source control is GitHub for every adapter. Only the *claim* write is github-tracker-only,
  because only a writing tracker has an issue to claim on.

## Why the github tools live in `../`, not `github/`

`claim-issue.sh`, `install-gh-bot.sh`, and `claim-selftest.sh` are the github
adapter’s implementation and stay at `../` (the tools root) because a web of
drift-parity checks (`claim-selftest.sh`, `pipeline-doctor.sh`, the stage prose)
pins their paths. `github/README.md` points at them; this directory is the
adapter *contract*, not a second copy of the scripts.
