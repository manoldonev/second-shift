---
name: intake
description: Manually triggered via /intake-toolkit:intake — the only way into intake. Give it a GitHub issue number or JIRA key, a pasted blob, a rough idea or a design handoff, and it runs one sequence (Requirements, Split, Explore, Interview, Receipt) that ends in the intake receipt a pipeline run launches from. Do not auto-select this skill.
---

# Intake

`/intake-toolkit:intake <input>` is the only way into intake. Every input runs **one sequence**,
in this order, and this skill owns the order:

**Requirements → Split → Explore → Interview → Receipt**

Each stage lives in a supporting file beside this one, and only this skill reads them. None is a
skill of its own, so none can be called on its own and skip the stages before it. `$SKILL_DIR` is
this skill's base directory; read each stage file from it when the sequence reaches that stage,
and follow it there:

| Stage | File | Runs | Hands on |
| --- | --- | --- | --- |
| Requirements | `$SKILL_DIR/requirements.md` | every input | the ticket body, its key, the spec-reviewer outcome and the knowledge source's outcome |
| Split | `$SKILL_DIR/split.md` | only when triggered (below) | the slices, or "not split" and why |
| Explore | `$SKILL_DIR/explore.md` | every ticket, once per split | your exploration, the snapshot and the fan-out pool |
| Interview | `$SKILL_DIR/interview.md` | per ticket, or per slice | the Decision Ledger, Open Regions and Surface Inventory |
| Receipt | `$SKILL_DIR/receipt.md` | per ticket, or per slice | `.claude/pipeline-state/{issue}-ledger.md`, linted clean |

Load `interviewing-baseline` (Skill tool) before the first question: it owns the loop rules, the
Decision Ledger and the receipt contract every stage writes into.

A stage's output passes to the next one **in memory**, in this session. Nothing between two stages
is a file another session reads, and no stage hands control to another skill and stops.

> **Tracker delta (config `tracker.type: jira`).** The prose in the stage files is the **github**
> default: a ticket is a GitHub issue number read with `gh issue view`. Under
> `tracker.type: jira` it is a **JIRA key** read with the Atlassian MCP's `getJiraIssue`, never
> `gh issue view`. Do not assume one MCP namespace: the tool is `mcp__atlassian__getJiraIssue`,
> `mcp__plugin_atlassian_atlassian__getJiraIssue` or `mcp__claude_ai_Atlassian_Rovo__getJiraIssue`
> depending on how the session registered it (`ToolSearch` to discover a deferred tool). The
> jira adapter has no labels and makes no tracker writes besides the filing the operator says yes
> to (`requirements.md`, "Filing"); every other write the stage files name is **presented** to the
> operator instead.

## When Split runs

Split runs when **any** of these holds, and is skipped otherwise:

- the ticket carries the `epic` label (the config's name for it, where renamed);
- Requirements finds more than one deliverable — distinct capabilities, each of which could ship
  on its own;
- the Interview's register passes about **10 material decisions**. The ticket then **returns to
  Split** from the Interview: a register that size is a decomposition the classification missed.
  If Split then creates slices, Explore runs again for the split, and its fan-out supersedes the
  one that ran on the unsplit ticket (`explore.md`, "After a return from the Interview").

A skipped Split is still an outcome: the receipt's `Split:` line says why it did not run.

## Gates, each once

| Gate | Stage | How often |
| --- | --- | --- |
| `review-toolkit:spec-reviewer` | Requirements | once per intake; no later stage dispatches it |
| the consumer's knowledge provider (`.claude/second-shift/intake-context.md`, `## Knowledge source`) | Requirements, its last act | once per intake, before Split, `codebase-explorer`, the fan-out and any Interview question; on a split, once on the parent, and every slice receipt carries the whole answer |
| `review-toolkit:codebase-explorer` | Split | at most once per intake, and only there; Split's review of the slices as a set reads its map |
| the intake fan-out (`intake-fanout.mjs`) | Explore | once per ticket, or once per split (a split the Interview sends back adds the split's one run, which supersedes the first) |
| `intake-toolkit:implementability-probe` | Receipt | per ticket, or per slice |
| `dup-scan.sh` | Receipt | per ticket, or per slice |
| sizing | Receipt | per ticket, or per slice |

A stage that finds a gate's result already in hand uses it; it never dispatches the gate again.

## On a split

The sequence forks once, after Split:

1. **Split** decides the slices and, on the operator's yes, creates them **without the queue
   label**.
2. **Explore** runs once, on the parent body **plus the slice list**, so the fan-out's lenses see
   the seams between slices. One notice covers it.
3. **Interview, then Receipt, per slice.** Each slice's interview takes the pool items that touch
   it; its receipt lists them and names the shared run, and carries the knowledge source's whole
   answer, from the one dispatch Requirements made on the parent. A slice gets the queue label
   (where intake applies it) only after its own receipt lints clean.

The parent gets no receipt: it becomes the epic its slices point at.

## Stops and restarts

- **A stop before the receipt writes no receipt and no seed file.** No `*-ledger.md`, no draft
  ledger, no saved body. The only file a stopped session may leave is the internal
  `.claude/pipeline-state/{issue}-snapshot.md` (Explore) and the Product-Essence Brief
  (`{issue}-brief.md`, Split); the scheduler reads neither.
- **The next session restarts from the ticket**, with `/intake-toolkit:intake <issue>`. The
  ticket, its comments and its sub-issues are the state; nothing local is. No file carries the
  knowledge source's answer across a stop, so a restart dispatches the provider again.
- **A restart that finds slices** (`Part of #<issue>` sub-issues) finishes the receipts of the
  slices that have none and leaves the others alone — `split.md`, "Restart over existing slices".

## Provenance of an escalation answer

A stage that escalates asks its question in the session first. The answer's provenance follows
the channel it came through:

- answered **in the session** → `user-answered`;
- answered **in a ticket comment** (the operator chose to answer later, so the question was posted
  and the session stopped) → `ticket-sourced`, the Resolution citing the comment's URL.

## Design handoffs, in or beside the input

Before Requirements, look for a design handoff: a `claude.ai/design/...` link in the ticket or the
operator's framing, a design section in the ticket, or a spec document for a sibling ticket on the
same surface (grep the repo's spec and plan directories for the surface's name). Say what you found,
including "none": an unstated absence reads like an unchecked one.

- **The handoff is the input** → Requirements runs design-toolkit's `design-faithful-spec`
  (`requirements.md`).
- **A handoff exists for a surface the input touches** → it travels with the input through every
  stage. Facts read from it enter the ledger as `codebase-derived` rows whose evidence is
  ``run: `<command>` → <output>``, the command being the read of the handoff. A question the board
  already answers is a protocol violation (`interviewing-baseline` rule 1).

## Outside the sequence

- **`plan-interview`** is for plan mode and a direct feature or fix ask with no pipeline ticket:
  an in-plan ledger, no receipt. A ticket headed for the pipeline comes here instead.
- **`grill-me`** stress-tests a plan or design that already exists, on the user's request.

Every path to a pipeline run converges on this one sequence: the receipt the scheduler launches
from is written only by its Receipt stage.
