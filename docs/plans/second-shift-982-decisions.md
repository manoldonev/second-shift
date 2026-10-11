# 982 — intake receipt

A receipt's `codebase-derived` row states its evidence: the command it ran, or why it is only cited. Pre-flight by plan-interview at base b473c1c7; fan-out ran; dup-scan rc 0.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Evidence-form grammar the lint accepts | Lenient, value-first: the form may follow the decided value anywhere in the Resolution cell; `run:` and `cited` are case-insensitive; the arrow is `→` or `->`; the command sits in a single- or double-backtick code span; a `\|` inside the command or the output is escaped as `\|`; violation text shows `\|`, never the internal pipe placeholder. Weighed: strict anchored grammar as the ticket reads (natural variants such as a value prefix, `->` and `Run:` go red at agent runtime, per the fan-out probe of 32 variants) | user-answered | intent |
| D-2 | Rows that record a choice rather than a fact | `design-intent` is dropped; the `cited` reason enum is `convention\|adr`. A compound row gives `run:` evidence for the fact behind its choice. A pure agent choice is not `codebase-derived`: it is asked and recorded as `user-answered` or `user-delegated`. Weighed: keep `design-intent` narrowly (it must point at a committed doc line), or as the ticket reads (the fan-out predicts it becomes the catch-all) | user-answered | intent |
| D-3 | Enforcement at release | Hard fail in `--receipt` mode, no warn-only phase and no header gate. The skill prose ships in the same release, and the only `--receipt` call is at intake time (`intake-orchestrator/SKILL.md:347`) | codebase-derived | fact |
| D-4 | Readers of committed receipts | No script re-lints a committed receipt: `run.sh` reads only Checks and Design (`run.sh:372-373`), and the `reconcile` mode that compared committed rows was deleted in #889. The review session is told to score every row of the record (`run.sh:596`); it reads Resolution text as prose, and the forms add text without removing any | codebase-derived | fact |
| D-5 | Where the check sits in the lint | Inside the row loop right after the `ticket-sourced` URL check (`ledger-lint.sh:231-233`), gated on receipt mode; default (4-column) mode unchanged, which keeps `exitplan-ledger-gate.sh:47` unaffected | codebase-derived | fact |
| D-6 | Example rows in the skill text | Generic, repo-agnostic examples in the existing `class-validator` style of `interviewing-baseline`; no ticket keys or origin stories (repo doc rule) | codebase-derived | fact |
| D-7 | Transcript scope for the fabrication and tool-call reads | The intake session's `.jsonl` plus its `subagents/workflows/wf_*/agent-*.jsonl`: fan-out lens and refuter commands live there, and a `run:` row copied from pool evidence would otherwise read as fabricated | codebase-derived | fact |
| D-8 | Corpus for the ~20-receipt read | Intake-time records: the lane PR's first commit (the scheduler commits the receipt first, `run.sh:938`), not main's post-BUILD records, which carry departure edits | codebase-derived | fact |
| D-9 | Offline effect test | Under OR-1. Out of this ticket; it runs only on the operator's go (ticket body). Owner: operator, before the ~20-receipt read | deferred | open |
| D-10 | Mirror sites | `plan-reviewer.md:98`, `design-faithful-plan-reviewer.md:187-189` and `figma-faithful-plan-reviewer.md:130` mirror only the provenance enum, which is unchanged: no edit | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether and when the offline effect test runs | pause-and-ask |

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Lint violation messages an interviewer or operator reads | decided (D-1) |
| S-2 | Skill prose the interviewer follows in the three emitting skills and the baseline | decided (D-2) |
| S-3 | Receipt rows BUILD and the review session read | decided (D-4) |
| S-4 | Release-note text from the Changelog trailer | decided (D-3) |
| S-5 | A zero-row receipt using the empty form, which skips the rule entirely | out-of-scope — pre-existing behavior; the read's provenance-share check watches for it |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: lint-parser-probe opus 6/6 · reader-and-caller-census fable 4/6 · author-runtime-feasibility opus 6/6 · measurement-and-incentives fable 2/6 · premortem fable 3/6
Tally: rows added 4 · snapshot claims overturned 2 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | lint-parser-probe | Today's receipt mode accepts every malformed form; the check belongs after the URL check at `ledger-lint.sh:231-233` | already-had | became D-5 |
| F-2 | lint-parser-probe | The pipe placeholder leaks into violation text, and an unescaped pipe fails on arity with a misleading cross-reference | new | became D-1 |
| F-3 | lint-parser-probe | Only literal `→` matches; `->` and other arrows go red | overturned (snapshot: "open: accept only → or also ->") | became D-1 |
| F-4 | lint-parser-probe | The ticket leaves the form's placement, case and spacing open; value-prefixed rows go red when anchored | new | became D-1 |
| F-5 | lint-parser-probe | A single-backtick capture rejects double-backtick code spans | new | became D-1 |
| F-6 | lint-parser-probe | 9 of 25 committed records already fail today's receipt lint | already-had | became D-4 |
| F-7 | reader-and-caller-census | The review prompt scores every row, so a model reads codebase-derived Resolution text downstream | overturned (snapshot: "none re-lint committed receipts; review-lead review-panel row is intent-only") | became D-4 |
| F-8 | reader-and-caller-census | 7 of 23 committed receipts fail the receipt lint with no migration done | already-had | became D-4 |
| F-9 | reader-and-caller-census | 140 codebase-derived rows on main; none run-like, 50 bare file:line | not material | not material — baseline for the read, already in the ticket |
| F-10 | reader-and-caller-census | A `reconcile` re-lint mode existed and was deleted | new | became D-4 |
| F-11 | author-runtime-feasibility | Every emitting context has Bash | not material | not material — confirms feasibility, no decision |
| F-12 | author-runtime-feasibility | Of 20 sampled rows, 5 clean run, 5 cited, 6 compound, 4 a choice | new | became D-2 |
| F-13 | author-runtime-feasibility | An undefined design-intent reason becomes the catch-all | new | became D-2 |
| F-14 | author-runtime-feasibility | Cited line numbers drift; run: facts still reproduce | not material | not material — supports the ticket's premise |
| F-15 | author-runtime-feasibility | The fabrication read misses commands run in fan-out subagents | new | became D-7 |
| F-16 | author-runtime-feasibility | Escaped pipes already parse in every row loop | already-had | became D-1 |
| F-17 | measurement-and-incentives | A zero-row empty-form receipt and relabeled rows pass receipt mode | not material | not material — pre-existing; scoped out as S-5 |
| F-18 | measurement-and-incentives | The read's corpus and transcript scope are open | new | became D-8 |
| F-19 | premortem | Fan-out commands live in subagent transcripts, not the session file | already-had | became D-7 |
| F-20 | premortem | An unescaped pipe in the output fails as a malformed row | new | became D-1 |
| F-21 | premortem | `->` and multi-line output go red at agent runtime | already-had | became D-1 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Enforcement at release: hard fail vs warn-first | hard fail in receipt mode; the prose ships in the same release and only intake-time lint reads receipts |
    | D-2 | Arrow token in the run: form | open: accept only → or also -> |
    | D-3 | cited reason enum completeness | open: convention, adr, design-intent; is an external-doc reason needed |
    | D-4 | Exemplar source in skill text | generic, repo-agnostic examples in the existing class-validator style (no ticket archeology) |
    | D-5 | Offline effect test | out of scope for this ticket (operator go, separate) |
    | D-6 | Which emitters change | plan-interview, intake-interviewer, intake-orchestrator, interviewing-baseline (canonical) |
    | D-7 | Readers affected | none re-lint committed receipts; review-lead review-panel row is intent-only |
    | D-8 | Mirror sites | plan-reviewer.md:98, design-faithful-plan-reviewer.md:187-189, figma-faithful-plan-reviewer.md:130 mirror only the provenance enum: unchanged |
