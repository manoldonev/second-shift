---
name: plan-interview
description: Use BEFORE writing any implementation plan for behavior-changing work — plan mode, or a direct feature/fix ask with no pipeline ticket. Surfaces the load-bearing design decisions to the engineer while the plan is forming and emits the in-plan Decision Ledger the plan gates require. Writes no intake receipt; a ticket headed for the pipeline enters by /intake-toolkit:intake instead. Not for typo/mechanical fixes.
---

# Plan Interview

You are about to write an implementation plan. Before the plan exists as a document, the engineer co-authors its load-bearing decisions — one at a time, with grounded recommendations — so the plan records choices already made instead of asking for a post-factum rubber stamp.

Load `interviewing-baseline` first (Skill tool) — it owns the loop rules and the Decision Ledger contract. This file only adds what is specific to plan-time design elicitation.

## Scope

You elicit **design decisions from the engineer** for a plan. You do NOT:

- Write an intake receipt, or interview a ticket for a pipeline run — that is `/intake-toolkit:intake <issue>`, whose Interview stage follows steps 2–5 below and adds the receipt.
- Stress-test a finished plan — that's `grill-me` (this skill's convergence walk borrows grill-me's semantics; it doesn't replace the user-initiated skill).

## Protocol

1. **Explore first.** Read the issue/spec, the affected code, the repo's ADRs/decision docs (wherever CLAUDE.md routes), and the Product-Essence Brief if one exists (`.claude/pipeline-state/{issue}-brief.md`). Every codebase-answerable question is answered here and recorded as `codebase-derived` — never asked. Answer it by running something where something can be run — a grep count, `ls`, `git cat-file`, a tool's `--help` — and keep the command and its decisive output: a `file:line` you read is a pointer, not verification.

2. **Build the decision register.** Admission = **materiality**. A decision enters the register only if it changes:

   *What the user gets* — the categories that go first because they are the ones an engineering-shaped register silently drops:

   - **states and transitions** — loading, empty, partial, error, not-found, and what moves between them,
   - **copy the user reads** — labels, messages, empty-state and error text; "we'll word it later" is a decision deferred, not a decision avoided,
   - **first paint** — what is on screen before the data arrives, and whether anything shifts when it does,
   - **degraded and missing dependencies** — what the user sees when the thing this depends on is absent, stale, or empty,
   - **composition and placement** — what else is on the surface, what it sits next to, what is suppressed when there is too little to show.

   *How it is built* — material for the same reason, and lower only because they are the ones that get asked anyway:

   - observable behavior (flows, status codes, emitted events),
   - API or data contracts (endpoint shapes, DTO fields, wire formats),
   - data invariants (uniqueness, soft-delete semantics — every natural key needs a conscious uniqueness decision),
   - scope boundaries (what this PR explicitly does not do),
   - tenancy/security posture (multi-tenant scoping filters per the repo's CLAUDE.md rules, guards, credential handling),
   - migration/rollout (existing rows, backfill, ordering across workspace packages),
   - data provenance — for each persisted field (one of an entity whose schema, model, DDL or mapping lives in this repo; third-party API payloads and in-memory JSON are out) the change newly reads but does not write, and that is feature-critical or crosses a service boundary: the persisting schema line, every writer of the entity (including sync or webhook paths that write raw payloads past the schema), and whether existing records carry the field — the backfill half is the migration/rollout item above. It lands as a `codebase-derived` row whose evidence is run, e.g. ``run: `grep -rn "fingerprint" src/entities/document.entity.ts src/sync` → schema line 41; written only by document.service.ts:88`` — or a `deferred` row.

   Everything below that bar is decided silently and does not enter the register. Material design decisions are near-always groundable, so a recommendation is expected on each question.

   **The ticket's candidate fixes are input, not the option set.** Build the options for the decision that picks the mechanism yourself. When the root cause lies in how a tool, library or platform mode behaves rather than in this repo's code, at least one option replaces that primitive instead of working around it. Find it on the tool's own surface (`--help`, its docs), check this repo's history with it (`git log`, earlier tickets), and state what it costs. The row's Resolution names every option weighed, the ticket's and yours, so a reviewer can see what was compared.

3. **Enumerate the surfaces, then check the register against them.** The register is whatever you chose to admit, so "the register is empty" grades the interview against itself. Independently of it, list the surfaces and states this work implies — every screen, route, state and artifact a user or operator ends up looking at. Then walk that list: each entry is either **decided** by a register row, or **explicitly out of scope with a reason**. An entry that is neither is a missing register row — add it and interview it.

   The list is not scratch work. In a plan-mode plan, write it as a `## Surface Inventory` section beside the ledger (schema in `interviewing-baseline`). The lint checks that section only on an intake receipt, so nothing here will fail you for omitting it — which is exactly why it is on you. Genuinely surface-free work states the explicit empty form and moves on.

4. **Pick the traversal.**

   - **Flat walk** — ≤ 4 uncoupled decisions: walk the register in any order.
   - **Convergence walk** — ≥ 5 decisions, or any coupling (one answer changes another decision's options): resolve in dependency order, parents first, grill-me style. Both traversals share the same exit criterion.

5. **Interview** per the baseline loop rules (≤ 2 material questions per turn, recommendation first, "your call" → `user-delegated`).

   **A risk in a specialist's dimension asks for its seat.** When a row or an Open Region records a deferred, unmeasured or inherited risk in a specialist reviewer's dimension — performance (cost, load), security, a11y, unit-test-mutation — ask the operator whether to add a `review panel` row naming that seat (`| D-n | review panel | performance | user-answered |`). The pipeline review's default panel trims those seats, and that row is the carrier that selects one mechanically; a risk written down with no seat behind it is reviewed by one generalist pass. For performance the review still has to decide the seat when no row names it, but only this row makes the selection the operator's.

6. **Emit the Decision Ledger** and exit only when the register is empty *and* every surface is accounted for — each material decision carrying a non-`assumed` provenance, each surface decided or scoped out. Trivial work exits immediately with both explicit empty forms.

## Where the ledger lands

A `## Decision Ledger` section in the plan file itself, before `ExitPlanMode` is called (this plugin's `exitplan-ledger-gate.sh` hook lints for it and blocks the exit if it's missing or malformed). It is the four-column in-plan ledger. This skill never writes `.claude/pipeline-state/{issue}-ledger.md`: the pipeline's receipt is written only by `/intake-toolkit:intake`'s Receipt stage.

## Escalation

Stop and present uncertainty (what you understood / what's blocking / options / a clear question) when:

- the user's answers contradict each other or the codebase, and rechecking doesn't resolve it;
- the register keeps growing past ~10 material decisions — the work is likely decomposition-worthy; if it is headed for the pipeline, say so and point at `/intake-toolkit:intake`, whose Split stage decides it;
- the register is implausibly **thin** for the scope. A ticket with a page of acceptance criteria about rendered output, answered by a handful of transport and build decisions, has not been under-scoped — it has been mis-scoped, and the surfaces in step 3 are where the missing rows are. Say so and widen; a thin register is the failure this skill is most likely to exit satisfied on, because its exit criterion is met.

## What NOT to do

- Don't quiz — every question elicits a decision and carries a grounded recommendation; none tests the engineer.
- Don't ask codebase-answerable questions (baseline rule 1).
- Don't pad the register with immaterial choices to look thorough — 0 material decisions is a legitimate outcome; emit the explicit empty form and move on.
- Don't re-litigate ledger entries later in the session; a recorded resolution is binding for the plan.
- Don't write the plan first and interview after — the interview precedes and shapes the plan.
