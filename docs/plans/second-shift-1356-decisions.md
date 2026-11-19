# Decision record — #1356 Intake fan-out: no refuters, no waiting, a Fan-out section that checks

Receipt: v4

## Summary

The intake fan-out loses its refuter stage, and every lens runs on the `reasoning` tier. The interview starts while the fan-out runs, after a short printed notice with no question. Receipt v5 gives the Fan-out section a tally and row links that the lint checks. The build prompt tells the build to read a finding that a row cites.

Open regions: OR-1, no new rule for findings set aside as not material.

Provenance legend: `user-answered` = the operator chose. `user-delegated` = the operator gave the choice to the agent. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Scope of the ticket | One ticket and one PR. It covers the shape of the fan-out and how intake records the pool. The operator declined a two-slice split. | user-answered | intent |
| D-2 | Refuter stage | Removed. Every lens claim reaches the session marked `unverified`. The `intake-refuter` agent file is deleted. | user-answered | intent |
| D-3 | Lens models | Every lens and the lens writer run on the `reasoning` tier by default. `reviewers.modelOverrides` and `reviewers.tierMap` still retarget them. | user-answered | intent |
| D-4 | Retry model | A failed lens or lens-writer dispatch retries once, on the token the `reasoning` tier resolves to. This also covers an override that names an unreachable model. There is no third attempt. The second-family fallback logic goes. | user-delegated | intent |
| D-5 | Fan-out notice | Explore prints the notice text of the ticket's Behavior step 1, verbatim, and asks no question. It launches the workflow before its own exploration. A split's run uses the same text. | user-answered | intent |
| D-6 | Skip by the operator | `skip fan-out` before the pool is read stops the workflow with `TaskStop`. The session reads nothing from it. Every receipt carries `Fan-out: skipped — by the operator, during the run: <reason>`. After the pool is read, the fan-out stays recorded as run. | user-answered | intent |
| D-7 | Skip detection and a later split | Any operator message or free-text answer that contains `skip fan-out` is a skip. Agents already in flight may finish, and their output is not read. A skip stands for a later split, as `explore.md` rules today. | user-delegated | intent |
| D-8 | Start of the interview | Questions go to the operator once the snapshot is written, before the pool is in. The Interview does not close until the pool is read, or the run has ended in its skipped or failed form. | user-answered | intent |
| D-9 | Snapshot content | The snapshot holds the decision register and the facts the session holds from the ticket body, the code and the spec-reviewer findings. It is written before the pool is read. | user-answered | intent |
| D-10 | Finding about a question already asked | The item is tagged `already-had`. Its disposition reads `already had — D-n` and needs no `From:` link. | user-answered | intent |
| D-11 | Finding that contradicts an answer | The session shows the finding beside the earlier answer and asks that question once more. The second answer stands. This covers `user-answered` and `user-delegated` answers. `interviewing-baseline` rules 5 and 6 name the exception. | user-answered | intent |
| D-12 | Finding that contradicts a fact row written after the snapshot | The item is tagged `new`. The session corrects the row in place, and the row gains the `From:` link. The disposition reads `became D-n`, so the corrected row counts in `rows added`. | user-delegated | intent |
| D-13 | Use of a pool item | The session checks an item from its pointer before the item becomes a row, an option or a question. The row carries the check as evidence and a `From: F-n` sentence. A failed check is tagged `not material` with disposition `not used — did not hold: <what the check showed>`. | user-answered | intent |
| D-14 | Build prompt | The prompt keeps "Only the D-n rows bind". It adds one sentence: where a row cites a finding with `From: F-n`, read that finding in the record's Fan-out section, because it is the evidence the row rests on. The prompt's existing departure rule is unchanged. Departs from AC-15: the row has the link anywhere in its cell, not only at its end. | user-answered | intent |
| D-15 | Result of `intake-fanout.mjs` | The result drops `refuter`, and a lens entry drops `survived` and `refuter`. Inputs: `issue` (required), `issueBody` (required), `knowledgeSource`, `readRoot`, `checkouts`, `protocol`, `probeDir`, `config`, `ceilingMs` (all optional), unchanged. Outputs: `issue`, `status`, `reason`, `lenses` (each `key`, `model`, `status`, `claims` as a count), `pool` (each `claim`, `pointer`, `observed`, `angle`, `kind`, `measured_under`, `status: 'unverified'`), `events`. Errors: `status: 'partial'` when a lens fails after its retry; `status: 'failed'` with a `reason` when the lens writer fails, every lens fails, the budget is spent or the ceiling passes; a thrown error when `issue` or `issueBody` is missing. | user-delegated | intent |
| D-16 | Fan-out rules of `ledger-lint.sh --receipt` on a v5 receipt | The lint checks the tally and the row links, and it does not require a `Refuter:` line. Inputs: the receipt path (required). Outputs: exit 0 and no violation when the section holds. Errors: exit 1 with one violation line for each of these. A `became D-n` disposition whose row has no `From:` that names the finding. A `From: F-n` that names an undeclared finding. A `From: F-n` on a row that the finding's disposition does not name. A `rows added` count that differs from the distinct `D-n` in `became` dispositions of rows tagged `new` or `overturned`. A `snapshot claims overturned` count that differs from the rows tagged `overturned`. A `questions added` count that differs from its listed ids, or a listed id that is undeclared or not named in a `became` disposition. Departs from AC-12: a listed question id must also be named in a `became` disposition. | user-delegated | intent |
| D-17 | Grammar of the v5 Fan-out section | `From: F-n` may sit anywhere in the Resolution cell, with several ids comma-separated. `became D-1, D-2` is valid, and each id counts. Only the comma list directly after `became` counts. The zero form is `questions added 0`. The empty pool line is `Pool: empty — no lens made a claim.` Each `Lenses:` entry reads `<key> <model> <claims made>` or `<key> failed`, and the lint checks only that the line is present. Departs from AC-10: `From: F-n` may sit anywhere in the cell, because a departure sentence must end a cell. | user-delegated | intent |
| D-18 | Output of `ledger-lint.sh --receipt-version` | It prints 5. The version table gains one row titled `Fan-out (v5 form)` at v5, identical in the lint and in `interviewing-baseline`. Inputs: none. Outputs: the highest version on one line, exit 0. Errors: none — the call reads no file. run: `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh --receipt-version` → 4 | codebase-derived | fact |
| D-19 | Receipts below v5 | They lint exactly as today, `Refuter:` line and old empty-pool line included. The lint applies a rule only at or above the version that mandates it. cited (convention): plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:420 | codebase-derived | fact |
| D-20 | Plugin version skew | The ticket adds no handling. The house rule is to update all second-shift plugins together. cited (convention): plugins/second-shift/skills/doctor/tools/doctor.sh:340 | codebase-derived | fact |
| D-21 | The `cross` tier | It stays in the tier table and in `DEFAULT_TIER_MAP`, with no shipped user. `model-tiering.md` says so. run: `git grep -l "'cross'" -- 'plugins/*/workflows/*.mjs'` → intake-fanout.mjs and runtime-shim-selftest.mjs only | codebase-derived | fact |
| D-22 | A consumer's `modelOverrides.intake-refuter` key | It is ignored without a warning after the change. The `Changelog:` trailer's Migration line says so. run: `grep -n '"modelOverrides","tierMap"' plugins/dev-pipeline/tools/config-lint.sh` → 272: only the top-level `reviewers` keys are closed | codebase-derived | fact |
| D-23 | Lens prompt and build rules | The lens prompt says every claim needs a pointer the interviewer can open or run. Build rule 4 becomes "Check, don't trust: the interviewer checks each claim from its pointer before it uses it". Build rule 2 loses its model half. | user-delegated | intent |
| D-24 | Criteria that no test can prove | AC-4, AC-5 to AC-10, AC-16 and AC-17 are exempt from a test. The review still scores each one against the diff. | user-answered | intent |
| D-26 | Record of a finding that contradicts an answer | The item is tagged `already-had`. When the second answer changes the row, its disposition reads `became D-n` and the row gains `From: F-n`. The tag keeps it out of `rows added`. | user-delegated | intent |
| D-25 | Findings set aside as not material | No new rule in this ticket. Parked under OR-1. Owner: the operator, at PM-1, after about ten consumer intakes on the new form. | deferred | open |
| D-27 | A v5 Tally line the lint cannot read | The lint refuses a v5 `Tally:` line that lacks one of its three counts. It also refuses a `questions added` list entry that is not a `D-n` id, or that is listed twice. Added in build: a count the lint cannot read is a count it cannot check. | user-delegated | intent |
| D-28 | A failed lens in the workflow result | A lens that fails after its retry has `model: null` and `claims: 0`. Added in build: the `Lenses:` line writes it as `<key> failed`, so no model is shown for it. | user-delegated | intent |

Options weighed:

- D-1: one ticket, or two sequential slices (receipt v5 first, then the workflow and the stages). The operator chose one ticket.
- D-2: remove the stage, refute only the claims the session uses, or keep the stage behind a config switch. The operator chose removal.
- D-3: keep today's tiers, add a per-lens override, or move all lenses to Opus. The operator chose all lenses on Opus.
- D-5: a one-line notice, a question that lets the session explore meanwhile, or today's blocking question. The operator chose a short printed notice and approved its wording.
- D-8: ask while the fan-out runs, keep the hold, or hold with a short cap. The operator chose to ask while it runs.
- D-9: widen the snapshot, change the meaning of `new`, or drop the tags. The operator chose the wider snapshot.
- D-11: ask once more as new evidence, record without asking, or keep the interview open until the pool. The operator chose to ask once more.
- D-13: a fifth tag `did not hold`, the tag `not material`, or no row for a failed finding. The operator chose `not material`.
- D-14: the row binds and the finding must be read, the finding binds too, or no prompt change. The operator chose the first.
- D-16: the lint checks the tally against the rows, the tally line is removed, or it stays unchecked. The operator chose the check.
- D-24: exempt all nine, exempt only the prose criteria, or no exemption. The operator chose all nine.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether findings set aside as `not material` need a rule that catches a wrong discard | reversible-default-and-flag |

OR-1 default: no new rule. The session keeps stating a reason in each disposition, as today. The operator chose this default. Reversing it costs one later ticket, decided at PM-1.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9 AC-10 AC-11 AC-12 AC-13 AC-14 AC-15 AC-16 AC-17

AC-1: a run dispatches no `intake-refuter`, and its pool holds every claim of every lens, each `unverified`, with the six evidence fields
AC-2: with no config every lens, the lens writer and each retry run on the `reasoning` token, a lens overridden to an unreachable model retries on `reasoning`, and an `intake-lens` override and a `tierMap` entry still retarget the lenses
AC-3: the result has no `refuter` field, a lens entry has only `key`, `model`, `status` and `claims`, and a lens that fails after its retry makes the run `partial`
AC-4: exempt — a file deletion; `check-dispatchers-and-readers.sh` and `check-model-tiers.sh` in Checks hold the rest
AC-5: exempt — the notice is wording in `explore.md`; the repo forbids tests that only grep for prose
AC-6: exempt — the skip rule is wording in `explore.md`
AC-7: exempt — the snapshot rule is wording in `explore.md`
AC-8: exempt — the interview timing is wording in `explore.md` and `interview.md`
AC-9: exempt — the late-finding rule is wording in `interview.md` and `interviewing-baseline`
AC-10: exempt — the check-before-use rule is wording in `explore.md` and `interviewing-baseline`
AC-11: on a v5 receipt the lint refuses a `became D-n` with no `From:` on that row, a `From:` to an undeclared finding, and a `From:` the finding's disposition does not name
AC-12: on a v5 receipt the lint refuses a tally whose `rows added`, `snapshot claims overturned` or `questions added` disagrees with the rows
AC-13: a v5 receipt with no `Refuter:` line and the new empty-pool line lints clean, and a v4 receipt still needs its `Refuter:` line and still accepts the old empty-pool line
AC-14: `ledger-lint.sh --receipt-version` prints 5, and the lockstep check passes with the v5 row on both sides
AC-15: the build prompt that `run.sh` writes holds "Only the D-n rows bind" and the sentence about a row that has `From: F-n`
AC-16: exempt — it restates that the tests of AC-1 to AC-3 and AC-11 to AC-13 exist
AC-17: exempt — it is the wording of five doc and skill files

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The fan-out notice the operator reads | decided (D-5) |
| S-2 | The operator's `skip fan-out` and its receipt line | decided (D-6) |
| S-3 | The question asked again on a late contradiction | decided (D-11) |
| S-4 | The result that `intake-fanout.mjs` returns | contract (D-15) |
| S-5 | The v5 Fan-out section that the lint parses | contract (D-16) |
| S-6 | The output of `ledger-lint.sh --receipt-version` | contract (D-18) |
| S-7 | The build prompt's sentence on cited findings | decided (D-14) |
| S-8 | The lens prompt and the build rules | decided (D-23) |
| S-9 | The `reviewers.modelOverrides` and `tierMap` config keys | decided (D-22) |
| S-10 | The wording of the new lint violations | out-of-scope — the build words them in the style of the lint's existing violations. |
| S-11 | `model-tiering.md` and the other docs | decided (D-21) |

## Checks

- bash scripts/check-lockstep-pairs.sh
- bash scripts/check-dispatchers-and-readers.sh
- bash plugins/review-toolkit/scripts/check-model-tiers.sh

## Intake steps

Requirements: interviewed (feature) on a ticket that had a key and no criteria. The operator settled eleven decisions. The body was assembled from them and replaced the ticket body on the operator's yes. spec-reviewer: two blockers, both fixed in the body. The implementability probe ran on the ticket body and returned 14 guess-points, all routed into rows. Its record round found no build-blocking point. It reported three departures, each now marked on its row.

Split: not split. The operator kept one ticket. The workflow, the stage text and the v5 lint depend on each other.

Explore: done. Read the workflow, its selftest case FO, the Fan-out lint check, the version table, the tier doc and the build prompt.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. PM-1 already sits under Post-merge checks.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
