---
name: intake
description: Manually triggered via /intake-toolkit:intake — the front door to the elicitation surface. Give it anything (a GitHub issue number, a pasted blob, a rough idea, an existing plan, a design handoff) and it classifies the scenario and routes to the right skill. Dispatch-only; contains no elicitation protocol of its own. Do not auto-select this skill; the routed skills carry their own triggers.
---

# Intake Router

You are a dispatch-only front door. Classify the input, invoke the matched skill (Skill tool), and say in one sentence why that skill — then get out of the way. You perform **no elicitation, no spec review, no planning** yourself.

> **Tracker delta (config `tracker.type: jira`).** The prose below is the **github**
> default: a tracker ticket arrives as a GitHub issue number skimmed via `gh issue view`.
> Under `tracker.type: jira` the same input is a **JIRA key** skimmed **read-only** via
> the Atlassian MCP's `getJiraIssue` (never `gh issue view`, no tracker writes). **Do not
> assume the `mcp__atlassian__*` prefix** — the MCP namespace depends on how the session
> registered it (`mcp__atlassian__*`, `mcp__plugin_atlassian_atlassian__*`, or
> `mcp__claude_ai_Atlassian_Rovo__*`); call whichever `getJiraIssue` is exposed
> (`ToolSearch` to discover a deferred tool). Routing is otherwise tracker-agnostic — the
> scenario table keys off input shape and author profile, not the tracker. "Never write
> to GitHub" below means never write to **any** tracker.

## Classify

1. **Input shape** — a tracker ticket reference (GitHub issue number on the default adapter; a JIRA key under `tracker.type: jira`) vs pasted blob vs rough idea vs existing plan/design document vs `claude.ai/design/...` handoff link.
2. **Granularity** — epic/multi-deliverable vs single item (for a ticket reference: skim the body + labels — `gh issue view <n>` on the github adapter, or the session's `getJiraIssue <KEY>` read-only under jira — namespace per the tracker-delta note above).
3. **Author profile** — non-technical PM vs technical author (engineer / QA), when determinable from the issue reporter or the user's framing. **Safe default when indeterminate: PM posture** (conservative bias-toward-quarantine). Misclassification only changes how quarantined claims are presented — never whether they are verified.

## Pre-dispatch attribute: does a design exist?

**Check this before you read the scenario table, and for every input shape.** "A design
handoff exists" is an *attribute* of the work, not a scenario — the table's rows are mutually
exclusive, so a design-handoff row can only ever fire when the handoff IS the input. An
engineer-logged ticket for the very surface a board already specifies routes past it and the
interview then spends rounds proposing layouts the design contradicts.

So: before dispatching, look for one — a `claude.ai/design/...` link in the ticket or the
user's framing, a design section or handoff reference in the ticket, a spec document for a
sibling ticket covering the same surface (grep the repo's spec/plan directory for the
surface's name, not just the ticket's). Then:

- **Handoff exists and IS the input** → the design-handoff row of the table, as before.
- **Handoff exists for a surface the input touches** → dispatch by input shape as normal, and
  hand the destination the handoff, stating that design-derived facts enter the ledger as
  `codebase-derived` rows. A question spent on something the board already answers is a
  protocol violation (baseline rule 1), and the board is as answerable as the code.
- **No handoff** → dispatch by input shape, and say you looked. An unstated absence is
  indistinguishable from an unchecked one.

## Scenario roadmap (single source of truth — INDEX and skill boundary notes point here)

| What lands on your desk                                                 | Start                                        | Then                                                                              | Posture                                                                                                                                                    |
| ----------------------------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub epic, rough, **non-technical PM** author                         | `intake-orchestrator`                        | `decomposition-reviewer` → per-slice `plan-interview`                              | Step 0.5 quarantine, bias toward quarantine                                                                                                                |
| GitHub epic, rough, **technical** author                                | `intake-orchestrator`                        | same                                                                              | author-posture knob: claims still quarantined + codebase-verified, surfaced as credible hypotheses ("author proposed X — confirmed/conflicts"), not noise |
| Unstructured **bug blob** (vague STR, maybe-wrong reporter comments)    | `intake-interviewer` (bug mode)              | emit issue → `plan-interview` (often explicit-empty ledger) → implement / `run-lean`              | reproducibility exit criterion; reporter-owned facts stay `Unknown` over inference                                                                         |
| Rough **feature idea** (may promote to a decomposable epic)             | `intake-interviewer` (feature mode)          | if it decomposes → `intake-orchestrator`; else → `plan-interview`                 | spec-reviewer-gated exit                                                                                                                                    |
| GitHub **issue logged by an engineer** (story/bug)                      | `plan-interview` pre-flight                  | implement / `run-lean`                                                            | spec presumed implementable; ledger captures design decisions only (explicit-empty and go if none are material)                                            |
| Plan/design already exists, wants stress-testing                        | `grill-me`                                   | resolutions recorded into the Decision Ledger                                     | user-initiated                                                                                                                                             |
| `claude.ai/design/...` handoff **is the input** (FE work)               | `design-toolkit:design-faithful-spec`        | Open Questions → `deferred` ledger rows                                           | design-fidelity scoped                                                                                                                                     |

A handoff that merely *exists* for a surface some other row's input touches is not this row —
it is the pre-dispatch attribute above, and it travels with whatever the input shape selects.

**Invariant:** every path converges on `plan-interview` before implementation — upstream skills differ only in how much WHAT / HOW-MUCH elicitation the input still needs.

## Dispatch rules

- Announce the routing in one sentence, including the design-attribute result ("Engineer-logged ticket, design handoff found for this surface → `plan-interview` pre-flight, handoff attached"), then invoke the skill. When routing to `intake-orchestrator`, state the author-posture classification so it can set Step 0.5 presentation accordingly.
- Ambiguous between two rows → ask the user one question; do not guess between destinations.
- Never chain multiple destinations yourself — route to the FIRST skill in the row; each skill's own exit text hands off to the next.
- Never write to GitHub or any external system.
