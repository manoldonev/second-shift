---
name: plan-interview
description: Use BEFORE writing any implementation plan for behavior-changing work — plan mode, a direct feature/fix ask, or pre-flight for a dev-pipeline ticket. Surfaces the load-bearing design decisions to the engineer while the plan is forming and emits the Decision Ledger the plan gates require. Not for typo/mechanical fixes.
---

# Plan Interview

You are about to write an implementation plan. Before the plan exists as a document, the engineer co-authors its load-bearing decisions — one at a time, with grounded recommendations — so the plan records choices already made instead of asking for a post-factum rubber stamp.

Load `interviewing-baseline` first (Skill tool) — it owns the loop rules and the Decision Ledger contract. This file only adds what is specific to plan-time design elicitation.

## Scope

You elicit **design decisions from the engineer** (plan-authoring). You do NOT:

- Elicit requirements from a reporter — that's `intake-interviewer`.
- Decompose into sub-issues — that's `intake-orchestrator`.
- Stress-test a finished plan — that's `grill-me` (this skill's convergence walk borrows grill-me's semantics; it doesn't replace the user-initiated skill).

## Protocol

1. **Explore first.** Read the issue/spec, the affected code, the repo's ADRs/decision docs (wherever CLAUDE.md routes), and the Product-Essence Brief if one exists (`.claude/pipeline-state/{issue}-brief.md`). Every codebase-answerable question is answered here and recorded as `codebase-derived` — never asked.

2. **Build the decision register.** Admission = **materiality**. A decision enters the register only if it changes:

   - observable behavior (user-visible flows, status codes, emitted events),
   - API or data contracts (endpoint shapes, DTO fields, wire formats),
   - data invariants (uniqueness, soft-delete semantics — every natural key needs a conscious uniqueness decision),
   - scope boundaries (what this PR explicitly does not do),
   - tenancy/security posture (multi-tenant scoping filters per the repo's CLAUDE.md rules, guards, credential handling),
   - migration/rollout (existing rows, backfill, ordering across workspace packages).

   Everything below that bar is decided silently and does not enter the register. Material design decisions are near-always groundable, so a recommendation is expected on each question.

3. **Pick the traversal.**

   - **Flat walk** — ≤ 4 uncoupled decisions: walk the register in any order.
   - **Convergence walk** — ≥ 5 decisions, or any coupling (one answer changes another decision's options): resolve in dependency order, parents first, grill-me style. Both traversals share the same exit criterion.

4. **Interview** per the baseline loop rules (≤ 2 material questions per turn, recommendation first, "your call" → `user-delegated`).

5. **Emit the Decision Ledger** and exit only when the register is empty — every material decision carries a non-`assumed` provenance. Trivial work exits immediately with the explicit empty form.

## Where the ledger lands

- **Plan-mode / ad-hoc session:** a `## Decision Ledger` section in the plan file itself, before `ExitPlanMode` is called (this plugin's `exitplan-ledger-gate.sh` hook lints for it and blocks the exit if it's missing or malformed).
- **Pipeline pre-flight** (`/plan-interview <issue>` before an autonomous `/dev-pipeline <issue>` run): write `.claude/pipeline-state/{issue}-ledger.md` — same location convention as the Product-Essence Brief; it survives worktree cleanup and Stage 1/3 hydrate it into the pipeline plan. The interview always happens in the interactive session, never inside the autonomous run.

## Escalation

Stop and present uncertainty (what you understood / what's blocking / options / a clear question) when:

- the user's answers contradict each other or the codebase, and rechecking doesn't resolve it;
- the register keeps growing past ~10 material decisions — the ticket is likely decomposition-worthy; suggest `intake-orchestrator`.

## What NOT to do

- Don't quiz — every question elicits a decision and carries a grounded recommendation; none tests the engineer.
- Don't ask codebase-answerable questions (baseline rule 1).
- Don't pad the register with immaterial choices to look thorough — 0 material decisions is a legitimate outcome; emit the explicit empty form and move on.
- Don't re-litigate ledger entries later in the session; a recorded resolution is binding for the plan.
- Don't write the plan first and interview after — the interview precedes and shapes the plan.
