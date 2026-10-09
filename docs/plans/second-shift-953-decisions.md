# Intake receipt — #953

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which surfaces carry the plan/spec-time rule | plan-interview, plan-reviewer and spec-reviewer. unit-test-plan-reviewer is dropped: nothing dispatches it since #584 deleted `unit-tests.mjs`, so a rule there has no reader. plan-reviewer is kept even though no harness step dispatches it (the ExitPlanMode hook runs `ledger-lint.sh` only, `exitplan-ledger-gate.sh:47`; `config-lint.sh:101` says there is no plan gate): it runs by hand before plans are finalized. Wiring plan-reviewer into any flow is out of scope | user-answered | intent |
| D-2 | What counts as a persisted field | #950 record D-25 verbatim, as shipped in `db-reviewer.md:54`: a field of an entity whose schema, model, DDL or mapping lives in this repo; third-party API payloads and in-memory JSON are out | codebase-derived | fact |
| D-3 | Which trigger the upstream rules use | db-reviewer's, on all three surfaces: a stored field the change newly reads but does not write AND that is feature-critical or crosses a service boundary (`db-reviewer.md:54`). Not the wider BUILD-prompt trigger (`run.sh:518`) | user-answered | intent |
| D-4 | Where plan-reviewer gets the consumer's round-trip trap list | The shared `## Database stack` section of `review-context.md`, which plan-reviewer already self-loads (`plan-reviewer.md:15`). No new load of `review-context/db-reviewer.md`, and the "exactly that reviewer" contract (`extension-points.md:18`) and `section-catalog.txt` stay unchanged. The `## Database stack` prose in `docs/extension-points.md` gains one clause saying plan-reviewer applies the traps at plan time when they are in the shared file; the H2 template is unchanged | user-answered | intent |
| D-5 | plan-reviewer severities, including when no schema can be cited | Mirror db-reviewer: the plan does not cite the persisting schema line or name the round-trip test, and the schema is in this repo → Warning. Schema not in this repo → out of scope per D-2. Schema not locatable within budget → `unable to verify — pointer needed: <entity schema>` (`db-reviewer.md:61`), not a Warning. The schema shows the field is not persisted and it is on the critical path → Blocker, the planning-vocabulary form of #950's Critical (review-lead `SKILL.md:397` vocabulary table) | user-answered | intent |
| D-6 | Where and how the plan-interview rule lands | A new item in the step-2 *How it is built* list (`plan-interview/SKILL.md`, next to `migration/rollout`, which it points to for the backfill half instead of restating it): the persisting schema line, every writer (including ones that bypass the schema), and whether existing records carry the field. It lands as a `codebase-derived` row citing `file:line`, or a `deferred` row, which in a receipt maps to an Open Region (ledger-lint parses Open Regions only under `--receipt`) | codebase-derived | fact |
| D-7 | Enforcement and tests | Prose only; no prose-presence guards and no new selftest. Nothing model-free can decide that a field crosses a boundary (#950 D-20). The repo bans prose-presence guards (CLAUDE.md, writing-tests), and no existing guard keys on the edited sections | codebase-derived | fact |
| D-8 | implementability-probe | Unchanged: it already enumerates every point a spec leaves to a guess (`implementability-probe.md:3`), and an untraced newly read field is one | codebase-derived | fact |
| D-9 | Where the spec-reviewer rule lands | One bullet under `### Data Contracts and Boundaries` (`spec-reviewer.md:146`): if the spec depends on a stored field (per D-2/D-3), does it say where it is persisted and whether existing records carry it? Missing → Warning ("developer will have to guess", `spec-reviewer.md:77`) | codebase-derived | fact |
| D-10 | Noise at plan time | Parked under OR-1 | deferred | open |
| D-11 | Which plan types plan-reviewer runs the *Newly read stored fields* check on | Every type, Feature add included, overriding the `## Downstream Impact` section's behavior-change/refactor gate (`plan-reviewer.md:50`) for this one check. Reason: D-5 placed it under Downstream Impact, and the type gate would have left feature-add plans — the case #953 names — unchecked | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Plan-time noise: #950's 0/60 (F-1) was measured over diffs, and the plan-time trigger reads the fields a plan or spec names. No plan corpus is measured | reversible-default-and-flag |

OR-1 default: ship without a plan-time measurement. If later intake runs show the rule firing on incidental reads, tightening the prose is a one-line follow-up.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | plan-interview register: the data-provenance question at pre-flight and in plan mode | decided (D-6) |
| S-2 | plan-reviewer report: a *Newly read stored fields* finding under Downstream Impact | decided (D-5) |
| S-3 | spec-reviewer report: the Data Contracts and Boundaries finding | decided (D-9) |
| S-4 | unit-test-plan-reviewer report | out-of-scope — no dispatcher since #584, so the agent is dropped from this change |
| S-5 | Consumer docs: the `## Database stack` paragraph in `docs/extension-points.md` | decided (D-4) |
| S-6 | `section-catalog.txt` and the context-coverage report | out-of-scope — unchanged, since plan-reviewer is not an effective-registry reader and no load is added |
| S-7 | implementability-probe output | decided (D-8) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: dispatch-reach opus 5/6 · rule-fidelity-951 fable 5/6 · stack-agnostic-trigger opus 4/6 · ledger-and-interview-cost fable 2/6 · premortem fable 4/6
Tally: rows added 3 · snapshot claims overturned 2 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | dispatch-reach | The ExitPlanMode hook runs ledger-lint only and never dispatches plan-reviewer (`exitplan-ledger-gate.sh:47`) | already-had | became D-1 |
| F-2 | dispatch-reach | The pipeline has no plan gate; `planGates` is a lint error (`config-lint.sh:101`) | already-had | became D-1 |
| F-3 | dispatch-reach | No production flow dispatches plan-reviewer or unit-test-plan-reviewer; code-review.mjs and intake-review.mjs list neither | overturned (snapshot: "plan-reviewer dispatched by intake-review.mjs, code-review.mjs") | became D-1 |
| F-4 | dispatch-reach | plan-reviewer loads the shared review-context.md, never `review-context/db-reviewer.md` (`plan-reviewer.md:15`) | already-had | became D-4 |
| F-5 | dispatch-reach | plan-interview is the only surface a flow enforces (`run.sh:791`); its `migration/rollout` item already covers backfill | new | became D-6 |
| F-6 | rule-fidelity-951 | #951's severities are in review-lead's confidence vocabulary, so Blocker/Warning on planning agents is a translation (review-lead `SKILL.md:397`) | new | became D-5 |
| F-7 | rule-fidelity-951 | #951 shipped two triggers: the BUILD prompt's wider one (`run.sh:518`) and db-reviewer's narrower one (`db-reviewer.md:54`) | new | became D-3 |
| F-8 | rule-fidelity-951 | The section catalog cannot record plan-reviewer as a reader, because readers must be effective-registry names | already-had | became D-4 |
| F-9 | rule-fidelity-951 | No selftest keys on the section names the change edits | new | became D-7 |
| F-10 | rule-fidelity-951 | The ticket's "runs before ExitPlanMode and in pipeline pre-flight" has no harness step behind it | already-had | became D-1 |
| F-11 | stack-agnostic-trigger | The docs template puts `## Database stack` in the shared file plan-reviewer already loads; the gap is per-reviewer-file consumers only | already-had | became D-4 |
| F-12 | stack-agnostic-trigger | D-25 literally matches this repo's checked-in config JSON Schema | new | not material — #950 measured 0/60 under its persisted-field definition in this repo (its F-1), so it is folded into D-2 |
| F-13 | stack-agnostic-trigger | With no in-repo schema, "uncited → Warning" fires every time; db-reviewer's escape is an `unable to verify` line | new | became D-5 |
| F-14 | stack-agnostic-trigger | Nothing tells a consumer with no Database stack section that plan-reviewer is working on an inferred stack | new | not material — `plan-reviewer.md:15` already says "discover it conservatively ... and say so" |
| F-15 | ledger-and-interview-cost | ledger-lint does not require a citation on a `codebase-derived` row | new | not material — enforcement is prose by design (D-7) |
| F-16 | ledger-and-interview-cost | Open Regions are parsed only under `--receipt`; the plan-mode gate runs without it | new | became D-6 |
| F-17 | premortem | No harness path dispatches plan-reviewer at ExitPlanMode or lane pre-flight | already-had | became D-1 |
| F-18 | premortem | unit-test-plan-reviewer has no dispatcher since #584 deleted `unit-tests.mjs` | overturned (snapshot: "unit-test-plan-reviewer Mock boundary bullet mirrors D-42" in scope) | became D-1 |
| F-19 | premortem | The plumbing load cannot be recorded in the section catalog | already-had | became D-4 |
| F-20 | premortem | #951's 0/60 was measured over diffs; at plan time there is no diff and no plan corpus was measured | new | became D-10 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | How plan-reviewer gets the consumer's round-trip trap list | open: plan-reviewer already self-loads shared review-context.md (plan-reviewer.md:15) but not review-context/db-reviewer.md; catalog reader tokens must be effective-registry names and plan-reviewer is not one (section-catalog.txt:13,31). Candidate: cross-read under the existing "reader = dimension" semantic |
    | D-2 | What counts as a persisted field | #950 record D-25, verbatim (db-reviewer.md:54) |
    | D-3 | plan-reviewer severities | uncited → Warning; schema shows not persisted + critical path → Blocker (ticket; plan-reviewer.md:72 ladder) |
    | D-4 | Enforcement | prose only; no prose-presence guards (#950 D-20; CLAUDE.md writing-tests rule) |
    | D-5 | implementability-probe | unchanged (ticket) |
    | D-6 | Where plan-reviewer actually runs | NOT in plan-interview pre-flight or the ExitPlanMode hook (lint only); dispatched by intake-review.mjs, code-review.mjs, and by hand. Ticket's "runs in pipeline pre-flight" is inaccurate; on the lane path the plan-interview bullet is the operative plan-time check. Open: add a dispatch site or not |
    | D-7 | plan-interview placement | new bullet in step 2 "How it is built" (SKILL.md:85-92) |
    | D-8 | unit-test-plan-reviewer | Mock boundary bullet mirrors #950 D-42 |
    | D-9 | spec-reviewer | Data Contracts and Boundaries bullet |
