---
name: interviewing-baseline
description: Shared interviewing protocol for all intake-role skills (intake-interviewer, plan-interview, grill-me, intake-orchestrator escalations). Provides the interview loop rules and the Decision Ledger contract — schema, provenance enum, explicit-empty form.
---

# Interviewing Baseline Protocol

This skill defines the shared protocol that ALL interviewing/elicitation skills follow, the same way `review-toolkit:reviewer-baseline` unifies the reviewer agents. It exists so loop rules and the Decision Ledger contract live in exactly one place.

**Canonical source notice:** this file is the single source of truth for the Decision Ledger schema, the provenance enum, and the intake-receipt contract below it (Kind axis, open regions, surface inventory, intent-gap record). Every other site that restates them (`plan-interview/tools/ledger-lint.sh`, this plugin's `hooks/exitplan-ledger-gate.sh` via that lint, `review-toolkit:plan-reviewer`) carries a mirror marker and must be updated in lockstep when this section changes.

## Interview Loop Rules

Rules for every interviewing turn, regardless of which skill is running:

1. **Explore first.** If a question can be answered by reading the codebase, the repo's docs, or ADRs (Grep/Glob/Read, or dispatching `review-toolkit:codebase-explorer` where the calling skill supports it), answer it yourself instead of asking. Asking the user a codebase-answerable question is a protocol violation.
2. **At most 2 questions per turn.** The user disengages otherwise. Related sub-choices may share one `AskUserQuestion` call, but the material decisions per turn stay ≤ 2.
3. **Attach a recommendation only when it's grounded** in the user's input, the codebase, or the repo's docs — cite the grounding. If nothing grounds an answer, ask plain — do not guess. (Reporter-owned facts — environment, frequency, business intent — are rarely groundable; design decisions almost always are.)
4. **Recommended answer goes first.** When using `AskUserQuestion`, the grounded recommendation is the first option, labeled `(Recommended)`.
5. **Never re-ask.** A question answered earlier in the session — or already resolved in the artifact under discussion — is settled. If the user declines to answer, record it (`TBD` in a ticket draft; `deferred` in a Decision Ledger) and move on.
6. **"Your call" is a valid answer.** When the user delegates a decision, record the recommendation as the resolution with provenance `user-delegated` — do not re-open it later.
7. **Disambiguate domain nouns before drafting.** A noun with >1 plausible schema referent (`git grep` over the repo's data-schema definitions, plus adjacent service interfaces) is forced to a choice by question — never picked by word-similarity.
8. **No draft-first (P8).** Never present a finished artifact ahead of the decisions it encodes. Nobody holds a complete picture of what they want until something concrete pushes back, and a full draft pushes back on everything at once: the human is reduced to correcting a fait accompli, and the decisions they would have made differently arrive as edits instead of choices. So: **the agent proposes per decision, the human disposes per decision**, and the artifact is *assembled from ledger rows* once they exist. A draft is legitimate as the residue of ratified rows — never as the opening move, and never as a way to "give them something to react to."

   **Batch-blessing is the same violation wearing an interview's clothes**, and it is named here because it does not look like a draft: collapsing N open decisions into a table of agent-chosen defaults and asking for one blanket approval. It reads as a turn — there are options on the screen, the human answers — while being the exact inverse of one, because a single "looks fine" cannot distinguish the rows they actually considered from the rows they skimmed. It *manufactures* agreement instead of reaching it. Presenting many resolved rows for the record is fine; presenting many *unresolved* ones for one approval is not. If a batch is genuinely uncontroversial, that is a claim the rows are immaterial — drop them from the register (rule: don't pad it) rather than blessing them wholesale.

9. **Repeated clarification requests mean WIDEN, not narrow.** When the user pushes back on a question round — "you're one-shotting this", "that's not what I asked", a second request to clarify — the reading is that the register is wrong or too shallow, not that the user is tired of questions. The move is to slow down and widen the surface under discussion; shrinking the question set, or answering the pushback with a defaults table, is the failure this rule exists to name. Fatigue looks different: the user answers, briefly, and asks you to get on with it.

## The Decision Ledger

<!-- canonical: interviewing-baseline provenance enum — all mirrors keep verbatim -->

The machine-checkable residue every elicitation leaves behind. It is a mandated `## Decision Ledger` section in the implementation plan (or, pre-flight for a pipeline ticket, a standalone `.claude/pipeline-state/{issue}-ledger.md`):

```
| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Uniqueness of document fingerprint per user | Partial unique index on (userId, fingerprint) | user-answered |
| D-2 | 404 vs 409 on duplicate import | 409 | user-delegated |
| D-3 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived |
| D-4 | Backfill order for historical records | deferred to next milestone (owner: reporter) | deferred |
| D-5 | Max import size | 50 MB, per the operator's comment https://github.com/acme/repo/issues/42#issuecomment-1234567 | ticket-sourced |
```

**Provenance closed enum** — exactly these five values:

- `user-answered` — the engineer made the call in the interview.
- `user-delegated` — the engineer said "your call"; the grounded recommendation is recorded as the resolution.
- `codebase-derived` — grounded in code, an ADR, the repo's CLAUDE.md, or the Product-Essence Brief; the Resolution cites the source.
- `deferred` — explicitly parked, with owner and when it must be resolved in the Resolution cell.
- `ticket-sourced` — the operator resolved it **in a ticket comment** and the run adopted that resolution. The Resolution cell MUST cite the comment by URL (`https://…`) — an uncited row is an assumption wearing a label, and the lint rejects it. This is the one user-provenance value an autonomous run may originate, precisely because the citation is independently verifiable without a local pre-flight artifact.

`assumed` is **not** a legal value. An assumption either gets asked, grounded, or deferred explicitly — the ledger makes a silent assumption a lint error instead of a style problem.

**Rules:**

- IDs are stable `D-1..n` and never reused after retirement (same discipline as `AC-n` IDs).
- Resolution is never empty.
- **Precedence when sources disagree:** a row hydrated from a pre-flight `.claude/pipeline-state/{issue}-ledger.md` wins over a ticket comment covering the same decision. Two comments that conflict, or one that is ambiguous, resolve to `deferred` naming the conflict in the Resolution cell — never to a `ticket-sourced` row that picks a side.
- **Explicit empty form** for trivial work — the section must still exist, containing exactly this line instead of a table:

  ```
  No material decisions — all choices codebase-derived.
  ```

## The intake receipt

The ledger above is what an interview leaves behind. The **receipt** is what INTAKE hands to
BUILD, and it carries one thing the in-plan ledger does not: a claim about *which* rows a human
actually settled. Run `ledger-lint.sh --receipt <path>` over it.

### The Kind axis

Provenance alone cannot express the ratification bar. The failure mode is a row that resolves
intent while wearing a `codebase-derived` label, so any rule keyed on provenance is circular.
Receipt rows therefore carry a fifth `Kind` cell:

```
| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | 404 vs 409 on duplicate import | 409 | user-answered | intent |
| D-2 | DTO validation library | class-validator (repo convention, CLAUDE.md) | codebase-derived | fact |
| D-3 | Backfill ordering | parked under OR-1 (owner: reporter) | deferred | open |
```

| Kind | Legal provenance | Meaning |
| --- | --- | --- |
| `intent` | `user-answered`, `user-delegated` | the human resolved it |
| `fact` | `codebase-derived`, `ticket-sourced` | derived from code or a cited comment |
| `open` | `deferred` | parked, and mapped to a declared open region |

The provenance enum is unchanged — this adds an axis, it does not fork the vocabulary. The Kind
cell is receipt-only: an in-plan Decision Ledger stays four columns, and the lint enforces the
arity of whichever artifact it was pointed at.

**The bar:** an `intent` row backed by `codebase-derived`, `ticket-sourced`, or `deferred` is
unratified, and the lint rejects it. That is how comprehension debt becomes countable rather
than sensed.

### Open Regions

A receipt that declares nothing open is claiming it knows everything that matters. Make the
claim explicit: a mandated `## Open Regions` section, rows or the empty form.

```
| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Ordering guarantees for the historical backfill | pause-and-ask |
| OR-2 | Retention window for import audit rows | reversible-default-and-flag |
```

Disposition is a closed two-value enum. `pause-and-ask` stops BUILD and routes the decision
back; `reversible-default-and-flag` takes a stated default and surfaces it — legitimate only
where reversing it later is cheap, and the receipt says why in prose below the table. Every
`open`-kind ledger row cites the `OR-n` it falls under; a citation the section does not declare
is worse than none, because it reads as an owned gap everywhere downstream.

Zero open regions is legal to the lint and a **finding** to `spec-reviewer` on non-trivial
scope — over-claimed completeness is a judgment about scope size, not something a script can
decide.

Explicit empty form, for genuinely trivial scope:

```
No open regions — every decision in scope is ratified.
```

### The Surface Inventory

Open Regions makes the *known* gaps explicit. The inventory is for the other kind: the
surface nobody thought to ask about. A ledger's exit criterion — "the register is empty" —
grades the interview against a register the interview itself chose, so an interview that
never raised the empty state exits satisfied, with a clean lint. The inventory is the
independent axis, a mandated `## Surface Inventory` section on the receipt:

```
| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | First paint while the list is still loading | decided (D-1) |
| S-2 | Empty state when the user has imported nothing | decided (D-2) |
| S-3 | Print stylesheet for the report | out-of-scope — nothing here is printed |
```

Enumerate every screen, route, state and artifact a user or operator ends up looking at —
loading, empty, partial, error, not-found, first paint, the copy on each. Disposition is a
closed two-value enum: `decided` **must cite the `D-n` that decides it** (an uncited claim
that a decision exists is the inventory's version of a silent assumption), and
`out-of-scope` **must carry the reason**. A listed surface that is neither is the gap this
section exists to count.

What it buys is bounded and worth stating: it cannot tell you the enumeration was complete.
It turns a surface nobody thought about into a surface nobody *listed* — which a reader and
a script can both see, where the absence of a question is visible to neither.

Explicit empty form, for work with no user-visible surface at all (a lint, a CI change):

```
No user-visible surface — this change renders nothing a user reads.
```

### The intent-gap record

A decision the receipt never covered will sometimes surface during BUILD. That is normal
operation (P9), not a failure — what must not happen is the run quietly making the call. BUILD
writes a committed record at `<plansDir>/<slug>-<issue>-lean-intent-gap.md`:

```
issue: <n>
run_id: <build run id>
session_id: <build session id>
region: <OR-n, or `undeclared` when the gap falls outside every declared region>
disposition: <the region's disposition, or the one the operator sets on an undeclared gap>
ratified: no
ratified_by:

## Gap
<the decision, and why the receipt does not cover it>

## Disposition followed
<paused and asked, or: took reversible default X and flagged it>
```

The header keys are read **first-match**, so `ratified:` sits above the prose that discusses it.
Ratification is an operator act out of band — a comment on the issue — and the record then
carries `ratified: yes` plus that comment's URL in `ratified_by:`. The merge boundary
(`scripts/check-lean-chain.sh`) refuses while the record reads `no`, and refuses a `yes` that
cites nothing: a run ratifying its own gap is not ratification.

One record per issue, one `ratified:` key covering it; a second gap resets it to `no`. Because
committing the flip moves the branch, it costs a fresh review round — land ratification before
the review handoff where you can.

## Who emits what

Each intake-role skill keeps its own purpose and trigger; what unifies them is the ledger:

| Skill                                            | Elicits                                      | Ledger role                                                       |
| ------------------------------------------------ | -------------------------------------------- | ----------------------------------------------------------------- |
| `intake-interviewer`                             | requirements from a reporter                 | emits a ledger seeded with requirement-level decisions            |
| `intake-orchestrator` / `decomposition-reviewer` | escalation-point choices                     | escalation answers → `user-answered`; open questions → `deferred` |
| `plan-interview`                                 | the engineer's load-bearing design decisions | primary author of the ledger                                      |
| `grill-me`                                       | challenges to an existing plan/design        | resolutions recorded back into the ledger as `user-answered`      |
| `design-toolkit:design-faithful-spec`            | ambiguous states/transitions in a handoff    | Open Questions double as `deferred` rows                          |

Routing between these skills lives in the `intake` front-door skill — see its scenario roadmap; do not restate routing here.

## What all interviewers must avoid

- Leading with a finished draft, or with a decision set the human has not disposed of one at a time — including a table of agent-chosen defaults put up for one blanket approval.
- Reading repeated pushback as fatigue and narrowing in response.
- Quizzing the engineer — questions elicit decisions; they never test comprehension.
- Asking codebase-answerable questions.
- Ungrounded recommendations dressed as grounded ones.
- Re-litigating a decision the user already made (in this session or in the ledger).
