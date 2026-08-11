# 503 — plan-interview under-elicits product decisions and permits batch-blessing

## Problem

A `plan-interview` pre-flight on a frontend ticket produced a Decision Ledger that passed
`ledger-lint --receipt` cleanly and still missed the entire product surface: of eight
decisions, all eight were engineering. A follow-up `grill-me` on the same ticket added nine
product decisions, reversed two, and corrected two factual claims. The failure reproduces
from the skill text, not from model variance.

Six findings, from the issue:

1. `plan-interview`'s materiality list is written in engineering categories — five of six
   admission criteria are engineering concerns, so an agent building a register from it
   produces an engineering register **as designed**. Root cause.
2. Nothing validates the register against the surface the ticket implies. The exit criterion
   is "the register is empty", where the register is whatever the agent chose to admit.
3. Escalation is one-sided — a register implausibly *small* for the scope trips nothing.
4. Batch-blessing (collapsing N open decisions into a table of agent-chosen defaults and
   requesting one blanket approval) is not named as prohibited.
5. Repeated operator pushback has no defined meaning, so it was read as fatigue and answered
   by narrowing.
6. The `intake` router treats "a design handoff exists" as a mutually-exclusive scenario row
   rather than an attribute orthogonal to input shape.

## Approach

Findings 1, 4, 5 and 6 are prose contracts in three SKILL.md files — write them.

Finding 2 is the load-bearing one and the only one with a machine-checkable residue. The
issue's Notes suggest an eval as its regression guard; a lint check is strictly better here,
because this repo's CI is model-free by design and an eval is API-billed and off by default.
So the surface-enumeration step gets a **residue**: a mandated `## Surface Inventory` section
on the INTAKE receipt, built as the direct structural sibling of `## Open Regions` — same
row grammar, same closed disposition enum, same explicit-empty form, same behavioral suite.
Each enumerated surface is either `decided` (citing a `D-n` the ledger actually declares) or
`out-of-scope` (with a reason). That is exactly "decided or explicitly scoped out before
exit", made countable instead of sensed.

Finding 3 largely falls out of 2 once the inventory exists, but the thin-register escalation
is still written, because the inventory constrains the receipt and the escalation constrains
the interview that produces it.

Blast radius of the new section has two caller classes, and only one of them is automated.
`--receipt` has no automated caller in the pipeline — the merge boundary reads only the
intent-gap record's `ratified:` key — so CI and the gates are unaffected, leaving the selftest
and one fixture. The **skill layer is the second caller class**: `intake-orchestrator`'s Step
5.5 Receipt Exit Gate runs this lint on a receipt written to a shape that same step spells out,
and `intake-interviewer` prescribes the same shape for its ledger seed. Tightening the lint
without moving those two shape statements makes the exit gate unpassable by construction, at
agent runtime where no build is watching. They move with it (AC-12).

## Acceptance criteria

**AC-1** — `plan-interview/SKILL.md`'s materiality list leads with product/UX admission
categories (states and transitions; copy the user reads; empty / error / edge surfaces; first
paint and loading; what the user sees when a dependency is missing), with the existing
engineering categories retained below them.

**AC-2** — `plan-interview/SKILL.md` gains a step between building the register and
interviewing: enumerate the surfaces and states the ticket implies, and require each to be
decided or explicitly scoped out before exit. The step names the `## Surface Inventory`
section as its residue for a pre-flight receipt.

**AC-3** — `plan-interview/SKILL.md`'s escalation section fires on a register implausibly
*thin* for the scope, alongside the existing fat-register escalation.

**AC-4** — `interviewing-baseline/SKILL.md`'s P8 names batch-blessing explicitly as a
prohibited move: collapsing N open decisions into a table of agent-chosen defaults and
requesting one blanket approval.

**AC-5** — `interviewing-baseline/SKILL.md` defines repeated clarification requests from the
user as a **widen-and-slow** signal, not a narrow signal, as a numbered loop rule.

**AC-6** — `interviewing-baseline/SKILL.md` — the canonical contract source — documents the
`## Surface Inventory` receipt section: row grammar, the closed `decided | out-of-scope`
disposition enum, the `D-n` citation requirement on `decided`, and the explicit empty form.

**AC-7** — `ledger-lint.sh` receipt mode enforces the Surface Inventory. Under `--receipt`
and only under `--receipt`, each of these is a distinct named violation:

- the `## Surface Inventory` section is absent;
- an `| S-n |` row has other than 3 columns;
- an `| S-n |` row has an empty Surface cell;
- a row's disposition token is outside `{decided, out-of-scope}`;
- a `decided` row cites no `D-n`, or cites a `D-n` the Decision Ledger does not declare;
- an `out-of-scope` row carries no reason after the token;
- two rows share an `S-n` id;
- the section has neither rows nor the explicit empty form.

A well-formed inventory lints clean, and the surface-row count is reported on stdout
alongside the existing ledger-row and open-region counts.

**AC-8** — `ledger-lint-selftest.sh` drives every AC-7 refusal and its discriminating pass
against real receipts, and the `(ll-af)` `--help` line-range guard still holds after the
header grows.

**AC-9** — `intake/SKILL.md` checks design-handoff presence as a **pre-dispatch attribute**,
orthogonal to the scenario table, with design-derived facts folded into the interview as
`codebase-derived` rows so no question is spent on what a board already answers.

**AC-10** — `scripts/lockstep-manifest.tsv`'s intake-receipt DROPPED entry covers the new
section and its enum, so the reasoning for guarding it behaviorally rather than by row stays
recorded rather than silently extended.

**AC-11** — the receipt fixture
(`plan-interview/tools/ledger-lint-fixtures/valid-receipt.md`) carries a well-formed Surface
Inventory exercising both disposition values, and `docs/testing.md` needs no change (this
adds cases to an existing suite, not a tier).

**AC-12** — every skill that prescribes the receipt shape states the mandated
`## Surface Inventory` alongside `## Open Regions`: `intake-orchestrator/SKILL.md` Step 5.5
(whose Receipt Exit Gate runs this lint on the shape it just prescribed) and
`intake-interviewer/SKILL.md`'s Decision Ledger seed. Step 5.5's red-lint remediation prose
covers the surface-inventory refusal class as well as the ratification one, so an agent hitting
the new refusal is given a path. A receipt built verbatim to the corrected prose lints clean.

## Out of scope

- An `intake-toolkit/evals/plan-interview-eval` harness. The issue floats one for finding 2;
  AC-7/AC-8 discharge that guard deterministically and model-free, and an API-billed eval
  would be a second, weaker copy.
- Making `--receipt` a pipeline gate. It is operator-run today; wiring it into the merge
  boundary is a separate contract change with its own blast radius.

## Decision Ledger

No material decisions — all choices codebase-derived.
