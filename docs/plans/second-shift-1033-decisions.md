# Intake receipt — #1033 dev-pipeline: the review proposes knowledge-base contributions

Receipt: v2

## Intake steps

Requirements: the ticket body as written (parent #1017) — spec-reviewer: needs-revision, 2 blockers (pre-#1028 wiring) re-pointed in the slice bodies, 5 gaps resolved from the code, 7 questions carried to the Interview
Split: split into #1032, #1033 (sequential) — this receipt is #1033's; queue when #1032 is closed
Explore: done — run.sh's review prompt and verdict grammar, review/SKILL.md, verdict-check, minimize-verdicts, review-lead's Plan/Spec Awareness and report, the section catalog
Fan-out: ran once for the #1017 split — 5 items touch this slice, see Fan-out
Dup-scan: no candidates at or above threshold 12
Post-merge scan: no AC to move; PM-1 already sits under Post-merge checks
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Who applies the inclusion test and writes the proposals | review-lead, in every report, lane or standalone: it loads `review-context.md` and the record it already finds (Plan/Spec Awareness), applies the declared inclusion test and writes the block. `run.sh`'s review prompt and the manual review's step 8 tell the verdict session to carry review-lead's block into the verdict's `## Notes` under the lead line `Knowledge-base contributions:`; neither applies the test itself. A `run-selftest.sh` case fails without the prompt instruction. | user-answered | intent |
| D-2 | Does the manual /dev-pipeline:review emit the line | Yes, the same as the lane review (see D-1). | user-answered | intent |
| D-3 | Which verdict carries the proposals | Every verdict, the full list: each review re-derives it from the record and the diff at the head it reviews, so the binding verdict is complete when minimize-verdicts collapses the earlier ones. | user-answered | intent |
| D-4 | What is proposed when the record has no provider answer (`none declared`, `failed — …`, or a receipt without the section) | Change gaps only, against the declared inclusion test, or `Knowledge-base contributions: none`. | user-answered | intent |
| D-5 | Default proposal format when the consumer's section declares none | One line per proposal: `- <kb-page> — <what to add or correct> (<lookup gap \| change gap \| kb stale \| kb ahead>)`; a declared format replaces it. | user-answered | intent |
| D-6 | OR-3: how a standalone review-lead finds the knowledge-source answer | The committed record it already locates through Plan/Spec Awareness; no new argument, and never uncommitted intake state. With a record it carries lookup gaps and kb-conflict rows; without one, change gaps only. | user-answered | intent |
| D-7 | Where the block sits in review-lead's report | A named `### Knowledge-base contributions` section in the report structure, present only when a sink is declared, holding the lead line and one proposal per line, or `Knowledge-base contributions: none`. | user-answered | intent |
| D-8 | Proposals from a code/KB conflict | Read from #1032's marker on the record's rows: `kb-conflict: <kb-page> (kb stale)` → a correction proposal for the page; `(kb ahead)` → no correction, and a proposal only when the page states the aspirational state as current rather than as direction. Settled at #1032's intake (its D-7). | user-answered | intent |
| D-9 | The sink section's catalog row and reader | `Knowledge-base contributions` with the reader token for review-lead's lead pass, added under #1032's non-reviewer token mechanism (its D-2); the docs template in `docs/extension-points.md` mirrors the row. | user-answered | intent |
| D-10 | A sink section that is present but empty or TODO-bodied | Treated as absent: no contributions line — cited (convention): docs/extension-points.md:142 | codebase-derived | fact |
| D-11 | Verdict grammar | Unchanged: `## Notes` is free prose that counts toward nothing in both verdict paths — run: `grep -c 'Nothing in it counts toward the verdict' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/skills/review/SKILL.md` → 1 and 1 | codebase-derived | fact |
| D-12 | Where the review reads the record | At its first commit and at the head — run: `grep -c 'git show \$FIRST:\$RECORD_REL' plugins/dev-pipeline/skills/run/run.sh` → 1 | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The verdict's `## Notes` with proposals | decided (D-1) |
| S-2 | The verdict's `## Notes` with `Knowledge-base contributions: none` | decided (D-4) |
| S-3 | A verdict on a repo with no sink declared, or an empty sink section | decided (D-10) |
| S-4 | review-lead's report section for the proposals | decided (D-7) |
| S-5 | A manual /dev-pipeline:review verdict | decided (D-2) |
| S-6 | The collapsed earlier verdicts on a multi-round PR | decided (D-3) |
| S-7 | The consumer authoring the sink section from the docs template | decided (D-9) |
| S-8 | Doctor's section report for the sink row | decided (D-9) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Run: shared with the #1017 split — slices #1032, #1033
Refuter: cross (opus/fable alternating)
Lenses: receipt-embedding-parsers opus 4/6 · intake-stage-sequencing fable 4/6 · dispatch-runtime-trust opus 5/6 · evidence-provenance-readers fable 2/6 · premortem fable 5/6
Tally: rows added 0 · snapshot claims overturned 0 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-3 | receipt-embedding-parsers | An unindented heading in the answer cuts `## Knowledge source` for later readers, this slice's review included (`run.sh:396`) | already-had | not material — #1032 indents the answer, so the review reads it whole |
| F-10 | dispatch-runtime-trust | The review session can resolve consumer plugin agents (`run.sh:353`, `:697`) | not material | not material — the sink reads the record and dispatches no provider |
| F-12 | dispatch-runtime-trust | verdict-check scores unindented `\| D-n \|` rows anywhere in the record (`verdict-check.sh:23-24`) | not material | not material — the proposals live in `## Notes`, which holds no rows; #1032 indents the answer |
| F-18 | premortem | `## Notes` has no harness reader, and minimize-verdicts collapses earlier verdicts once one binds (`minimize-verdicts.sh:2-13`) | new | became D-3 |
| F-19 | premortem | A non-reviewer reader token in the catalog is dropped silently from the degraded-readers report (`check-review-context-sections.sh:216-220`) | already-had | became D-9 |

### Snapshot

    | ID | Slice | Decision | Resolution (pre-pool) |
    | --- | --- | --- | --- |
    | D-1 | #1032 | Which /intake stage dispatches the provider | open — lean: Requirements' last act, once the ticket body exists, before Split, codebase-explorer, the fan-out and any Interview question |
    | D-2 | #1032 | May the operator skip the dispatch | open — lean: no skip form; the consumer's opt-out is `none declared` |
    | D-3 | #1032 | Embedding the verbatim answer | indent four spaces, as the Fan-out snapshot is |
    | D-4 | #1032 | `Knowledge source:` key in `## Intake steps` | open — lean: no new key |
    | D-5 | #1032 | Split rule | one dispatch per intake, on the parent before Split; each slice receipt carries the whole answer |
    | D-6 | #1032 | OR-1 order vs the lens writer | follows D-1: the answer exists before Explore, handed to the fan-out in its issueBody |
    | D-7 | #1032 | OR-2 section-lint ownership | open, pause-and-ask |
    | D-8 | #1032 | Receipt version | `Knowledge source` is a v3 row (current max v2) |
    | D-9 | #1032 | `kb` cited reason sites | ledger-lint.sh CITED_REASON_ENUM + messages; interviewing-baseline; intake/receipt.md |
    | D-10 | #1032 | First intake-side extension file | intake-toolkit reads nothing under .claude/second-shift today |
    | D-11 | #1032 | Provider name form | namespaced `<plugin>:<agent>`, read from the consumer's section |
    | D-12 | #1033 | Manual /dev-pipeline:review emits the contributions line | open — lean: yes, parity with run.sh's prompt |
    | D-13 | #1033 | Sink section's catalog reader token | depends on OR-2 |
    | D-14 | #1033 | OR-3 standalone review-lead | default as stated |
    | D-15 | #1033 | Record with no answer (none/failed/older receipt) | change gaps only |
