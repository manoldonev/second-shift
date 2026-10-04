# #916 — intake receipt (pre-flight, 2026-10-04)

Intake fan-out at plan-interview pre-flight, with a per-receipt value section. Admission and evidence are in the ticket body (consumer replay; strategy repo `fanout-914-2026-10-03/consumer-intake/`). Duplicate scan: rc 0, no candidates.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the fan-out runs | On by default when plan-interview is pre-flight for a lane ticket (`/plan-interview <issue>`); off for ad-hoc and plan-mode use. The operator may skip it per ticket, and the skip is recorded with who skipped it. No arming classifier now; which tickets should get it is OR-1 | user-answered | intent |
| D-2 | How the fan-out's output enters the interview | The plan-interview session consumes the refuted evidence pool itself, like explore-first findings. An item becomes a register row only if it passes the existing materiality bar, and pool evidence may overturn a snapshot claim. No separate assembler and no new question cap; ≤ 2 per turn stands | user-answered | intent |
| D-3 | Mechanism | A new Workflow script `plugins/review-toolkit/workflows/intake-fanout.mjs`, built as the consumer replay ran it. Stages: a sealed lens writer, four angles plus a pre-mortem (blind), a refuter per claim (refuted by default), then the pool returned. Every agent gets the ticket, the protocol text (plan-interview and interviewing-baseline skill files, passed as `protocol`), the target checkout and every other checkout the change meets (`checkouts`, e.g. the frontend that calls this backend); the writer gets #914's build rules verbatim and no menu of angles. Schema is evidence-only (claim, pointer, observed, angle, status, measured-under, plus kind), with no rationale, confidence or refuter text. Staged the way intake-orchestrator stages `intake-review.mjs` (`intake-orchestrator/SKILL.md:184-188`, `docs/namespaces.md` rule 3). Revised 2026-10-04 after the strategy audit of #916: the build had dropped the protocol text and the consumer checkout the measured agents had, and added an angle menu matching the answer keys | user-delegated | intent |
| D-4 | Timing and speed | The fan-out launches at the start of pre-flight and runs alongside explore-first; it never reads the snapshot. All five lenses finish before the first question, and nothing arrives between two questions. Each lens prompt carries a soft budget of about 25 tool calls ("return what you have"); a script can stop waiting on an agent but cannot abort it. Measured: 20–27 min per ticket for the whole replay, with uncapped lenses, so the budget's effect on what the lenses catch is unmeasured (OR-3). Amends the ticket's decision 4. Revised 2026-10-04 after the strategy audit of #916: the earlier 'catching lenses done by 11 min' is in no committed record | user-delegated | intent |
| D-5 | Failure handling | A lens or the lens writer that fails (including a safeguard block) is retried once on the other model family, or once at the same tier when no other family is reachable. A refuter is retried once on its own family, because its other family is the one that made the claim. If the fan-out still cannot complete, the interview proceeds without it and `## Fan-out` records what ran, what failed and why. Never a silent no-fan-out. Revised 2026-10-04 after the strategy audit of #916: once refuters follow the claim's family (D-7), a cross-family retry would be a same-family check | user-delegated | intent |
| D-6 | The value section | Every pre-flight receipt carries a mandated `## Fan-out` section. It holds a tally line (rows added, snapshot claims overturned, questions added), a `Lenses:` line (each lens's key, model, and claims kept of claims made), then every pool item with the angle that produced it, tagged `new` / `already-had` / `overturned` (naming the claim) / `not material`, each with its disposition. Two explicit forms replace it: skipped (by whom) or failed (what). The schema goes in interviewing-baseline; `ledger-lint.sh --receipt` enforces it. Reader: the operator's consumer read. Revised 2026-10-04 after the strategy audit of #916: without per-lens attribution, a lens that never contributes cannot be found from consumer records | user-delegated | intent |
| D-7 | Agents and model mix | Three new agent files in review-toolkit: `intake-lens-writer` (opus), `intake-lens` and `intake-refuter`. The script runs the arm the consumer replay measured: the four angles alternate opus and fable (`reasoning`/`cross`), the pre-mortem runs on fable, and every claim is refuted by the family that did not make it, including a lens retried onto the other family. Without Fable access the run stays on opus after two failed `cross` dispatches and the pool reports `same-family (fable unavailable)`. `reviewers.modelOverrides` and `reviewers.tierMap` can still set either role. Revised 2026-10-04 after the strategy audit of #916, by the operator: the build had shipped all-opus lenses with fable refuters and called it 'as measured'; the operator directed implementing the measured alternation | user-answered | intent |
| D-8 | Where the snapshot lives | Written to `.claude/pipeline-state/{issue}-snapshot.md` before the pool is read (that directory is gitignored), then embedded verbatim as `### Snapshot` under `## Fan-out`, which run.sh commits as the branch's first commit. The tags stay auditable from the record | user-answered | intent |
| D-9 | What the engineer sees while waiting, and the ceiling | plan-interview announces the fan-out once when it launches. The Workflow runs in the background, and the session resumes on its completion notice. Past 30 min of wall-clock it proceeds without the pool and records `Fan-out: failed — exceeded 30 min`. Announcement wording under OR-2 | user-answered | intent |
| D-10 | Sizing | One ticket, one lane run. The section without the fan-out reports nothing, and the fan-out without the section loses the value tally | user-answered | intent |
| D-11 | Other receipt writers | `intake-orchestrator` and `intake-interviewer` write receipts and run `ledger-lint.sh --receipt` (`intake-orchestrator/SKILL.md:334-343`, `intake-interviewer/SKILL.md:228`) but never run the fan-out (D-1). Their receipt-shape lists gain `## Fan-out`, and each writes the skipped form naming its path, so their receipts don't fail the new check | codebase-derived | fact |
| D-12 | Migration | None. `run.sh` never lints a receipt; it reads `$ISSUE-ledger.md` at `run.sh:183`, and the lint runs only where the receipt is written. Receipts written before this ships aren't re-checked | codebase-derived | fact |
| D-13 | Selftest wiring | `workflows-mjs-selftest.sh` runs a hard-coded `run_mjs` list (`:43`, `:49`), so the new selftest must be added to it or its cases go into `runtime-shim-selftest.mjs`. Both `ledger-lint-fixtures/valid-receipt*.md` fixtures gain `## Fan-out`, and each form (disposed, skipped, failed) gets a passing case. CI stays model-free | codebase-derived | fact |
| D-14 | Workflow tool unavailable | plan-interview checks for the Workflow tool before launching, as review-lead (`review-lead/SKILL.md:38-40`) and intake-orchestrator (`:62`) do. If it's absent, the receipt records `Fan-out: failed — Workflow tool unavailable in this session` | codebase-derived | fact |
| D-15 | Which tickets should get the fan-out | Default on at pre-flight (D-1); parked under OR-1 (owner: operator) until `## Fan-out` tallies accumulate | deferred | open |
| D-16 | The announcement wording | Default: "Running the intake fan-out (5 lenses, up to 30 min) alongside exploration; questions start when it returns." Parked under OR-2 | deferred | open |
| D-17 | The lens budget value | Default: about 25 tool calls per lens. Parked under OR-3 | deferred | open |
| D-18 | How the snapshot is embedded | Indented four spaces under `### Snapshot` (a code block), not pasted as a table. `ledger-lint.sh` reads every D-n, OR-n and S-n table row anywhere in the file as this receipt's own rows, so a verbatim register pasted as-is collides with the real ledger. Indentation keeps D-8's verbatim copy and keeps it out of those scans; the lint refuses unindented snapshot rows. Added at build | codebase-derived | fact |
| D-19 | Fable in shipped defaults | The rule that shipped defaults stay `opus` and Fable is override-only is deleted. Fable ships as the `cross` tier and a shipped default uses it where it is useful. Decided 2026-10-04 by the operator | user-answered | intent |
| D-20 | Where Fable ships now | Only where the dispatcher falls back to `reasoning` when Fable cannot be dispatched, and where the record says what was measured: today the intake fan-out (D-7). `code-review.mjs` and `intake-review.mjs` have no such fallback, so their agents stay at `reasoning` until one lands. Written in `model-tiering.md` "Fable" | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Which tickets get the fan-out (arming by ticket shape, or a cheap classifier) | reversible-default-and-flag |
| OR-2 | The wording of the launch announcement | reversible-default-and-flag |
| OR-3 | The per-lens budget value | reversible-default-and-flag |

- **OR-1:** reversing it is a later edit to D-1's trigger. The operator stated on 2026-10-04 that the fan-out "probably should not run for every ticket" and that this "can be optimized later". The `## Fan-out` tallies are the data: a ticket where it added 0 rows and overturned nothing is a negative example. The measured tickets were chosen because their intake decision was later reversed, so the cost of arming on tickets that need no fan-out is unmeasured; revisit OR-1 once 10 lane receipts carry a disposed `## Fan-out` (added 2026-10-04, user-delegated, after the strategy audit).
- **OR-2 and OR-3:** one-line prompt changes. The budget's effect is unmeasured, on the key catches as much as the rest: the measured lenses ran uncapped.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `## Fan-out` section, disposed form: refuter and `Lenses:` lines, tally line, tagged items with their angle, `### Snapshot` | decided (D-6) |
| S-2 | `## Fan-out` skipped form, by the operator or by the orchestrator/interviewer path | decided (D-11) |
| S-3 | `## Fan-out` failed form: retry exhausted, Workflow absent, ceiling exceeded, or a lens cut short | decided (D-5) |
| S-4 | The launch announcement the engineer reads | decided (D-16) |
| S-5 | The wait between launch and the first question | decided (D-9) |
| S-6 | Engineer questions after the pool is consumed | decided (D-2) |
| S-7 | `ledger-lint.sh` violation messages for the new section | decided (D-13) |
| S-8 | `refuter: same-family (fable unavailable)` notice when a repo lacks Fable access | decided (D-7) |
| S-9 | Docs a consumer reads: model-tiering.md's scoped fable exception, namespaces.md | decided (D-7) |
| S-10 | The review session's verdict | out-of-scope — the review does not read `## Fan-out`; its reader is the operator's consumer read (D-6) |
| S-11 | `/workflows` progress display for the fan-out | out-of-scope — operator-facing progress only, phase titles follow the existing workflow scripts' convention |

## Fan-out

Fan-out: skipped — by the operator's intake of this ticket, which predates the fan-out it builds.

## Checks

- `bash plugins/review-toolkit/workflows/workflows-mjs-selftest.sh`
- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`
- `bash plugins/review-toolkit/scripts/check-model-tiers.sh`
