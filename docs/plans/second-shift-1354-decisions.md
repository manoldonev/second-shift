# Decision record — #1354 implementability-probe: record round runs out of turns before reporting

Receipt: v4

## Summary

The implementability probe gets a 30-turn cap with a turn-20 emit deadline. Its report marks unfinished items `unverified`. receipt.md resumes a partial record round up to two times and then asks the operator. The ticket-body round is removed, so the probe runs once, on the finished record.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The failure this fix targets | The capped record round returned a partial report. The turn-10 deadline held, but it stopped verification early. The operator had to lift that deadline through a resume. | user-answered | intent |
| D-2 | The probe's turn budget | `implementability-probe.md` goes from `maxTurns: 15` to `maxTurns: 30`. Its deadline sentence becomes "By turn 20 (of your 30 maximum)". The verified run needed 27 tool uses. | user-answered | intent |
| D-3 | A turn cap per dispatch | Not possible. A cap lives only in the agent's frontmatter, so the round's budget is the agent's cap. run: `git grep -n "maxTurns" -- 'plugins/**/*.mjs' \| wc -l` → 5 hits, all comments or log strings, none an `agent()` option | codebase-derived | fact |
| D-4 | The lint on the new cap and deadline | `check-emit-deadline.sh` checks every agent above cap 15. It needs D ≤ ⌈2N/3⌉, here 20 ≤ 20. The body's N must equal the frontmatter cap. Selftest case B1 lints the live tree in the test sweep. run: `grep -n "DEFAULT_CAP=15" plugins/review-toolkit/scripts/check-emit-deadline.sh; grep -n "B1 live" plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh` → line 54; line 196 | codebase-derived | fact |
| D-5 | The probe report's partial marking | The output format gains an `unverified` status. An AC line can read `AC-n unverified — <what was not read>`. A guess-point with unfinished grounding is `G-n [unverified] <the fork>`. This replaces the `[human]` fallback at the deadline. There is no emit-as-you-go. Inputs: the finished record's path (required), the ticket body (required). Outputs: the report sections of the agent doc. Each AC line is covered, departed, absent or unverified. Errors: none — at the cap the harness returns the output marked partial. | user-answered | intent |
| D-6 | A record round that ends partial | The report is not final while the harness marks it partial or it holds an `unverified` item. The session resumes the same probe with SendMessage and tells it to finish the unverified items. It resumes at most 2 times. Then it asks the operator to accept the report as partial or to resume again, recommending resume. A partial round is recorded only on the operator's word. This replaces "The record round runs once. It never loops." | user-answered | intent |
| D-7 | Where a partial round is recorded | On the receipt's `Requirements:` step line, where committed receipts record the probe's outcome. run: `git grep -l "Requirements:.*implementability probe" -- docs/plans \| wc -l` → 3 receipts | codebase-derived | fact |
| D-8 | The ticket-body probe round | Removed. The probe runs once, on the finished record and the ticket body. receipt.md loses "### 3. Implementability probe", its "two rounds" sentences and the exit-gates sentence about "one more round". The §3 routing list (operator's → question, code → fact row, undecided → `OR-n`) moves into "Probe the record", which cites it today. The SKILL.md gate row, `.claude/SECOND-SHIFT.md` and `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` say one round. This reverses #1344's "The two-round cap stays." | user-answered | intent |
| D-9 | When the one probe round runs | Whenever the ticket has an AC block, as the record round does today. A ticket with no AC block gets no probe. Its receipt's `Requirements:` line says so and why. The old skip rule for a bug, a chore or small scope goes with the removed round. | user-answered | intent |
| D-10 | The agent's body-only mode | Removed. The agent doc always expects the finished record with the ticket body. Eval README steps 1 to 4 are retired. BASELINE.md drops run 1 and the body-round part of run 2. | user-answered | intent |
| D-11 | `seeded-gaps.md` after the body-only eval goes | Kept. `planted-defects.md` scores the record round's leftover body gaps against it. run: `grep -n "seeded-gaps" plugins/intake-toolkit/evals/implementability-probe-eval/fixtures/planted-defects.md` → line 18 | codebase-derived | fact |
| D-12 | How the fix is proven | PM-1, on the next real intake whose record holds about 30 rows and 15 ACs. No new eval fixture. | user-answered | intent |
| D-13 | The ticket body | Rewritten on the operator's yes. The Proposal and Acceptance match D-2, D-5, D-6, D-8 and D-9. The first acceptance item moved to `## Post-merge checks` as PM-1. The Problem now says the capped run returned a partial report. | user-answered | intent |
| D-14 | Test intent for AC-1 to AC-4 | All four are exempt. They change agent and skill prose and frontmatter, and CI is model-free. PM-1 proves the behavior. Selftest case B1 still checks the D-2 pair. | user-answered | intent |
| D-15 | How a resumed probe gets past its deadline | The agent doc says: on a resume, the deadline counts from the resume. When the resume message says the report was cut short, the probe finishes the whole report. Otherwise it works only the named unverified items. Either way it re-sends the whole report. The session's resume message says "cut short, finish the whole report" when the harness marked the report partial, and otherwise names the unverified items. The no-`Task` rule moves from §3 into "Probe the record". A session with no SendMessage makes zero resumes and goes to the operator question. Changed in build: a report the harness cuts at the cap can hold no `unverified` item, so a resume that names only unverified items gave the probe no work and spent both resumes. | user-delegated | intent |
| D-16 | Items still `unverified` in a report the operator accepts as partial | Each one becomes its own `OR-n` with disposition `pause-and-ask`. A ticket AC that the accepted report does not list counts as `unverified`. The build stops on it and asks. It never guesses an unchecked AC or guess-point. Changed in build: a report the harness cut short can omit AC lines, and without this sentence an omitted AC would get no `OR-n`. | user-delegated | intent |

Options weighed:

- D-1: no report, a partial report, or not sure. The operator chose a partial report, and the deadline lifted by a resume.
- D-2: one file at 30/20, a second agent file for the record round, or 15/10 with resumes only. The operator chose one file at 30/20.
- D-5: an `unverified` marker only, or the marker plus emit-as-you-go. The operator chose the marker only.
- D-6: at most 2 resumes then ask, resume with no bound, or ask at once. The operator chose at most 2 resumes then ask.
- D-8: drop the round in this ticket, a separate ticket, or keep it. The operator chose to drop it here.
- D-9: whenever the ticket has an AC block, or every ticket. The operator chose the AC-block rule.
- D-10: keep the body-only mode in the agent and eval, or remove it. The operator chose to remove it.
- D-12: a large eval fixture plus PM-1, or PM-1 on the next real intake. The operator chose the next real intake.
- D-13: rewrite the body, or keep it and mark departures. The operator chose the rewrite.
- D-14: exempt all four, or a selftest case for AC-1. The operator chose to exempt all four.
- D-15: the agent doc restarts the deadline on a resume, or the resume message lifts it. The operator chose the agent doc.
- D-16: a pause-and-ask `OR-n` per item, a question per item, or only the `Requirements:` line. The operator chose a pause-and-ask `OR-n` per item.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: exempt — a frontmatter cap and a deadline sentence in an agent doc. Selftest case B1 checks the pair at the head.
AC-2: exempt — the probe's output format is prose in an agent doc. No model-free test can show the agent using it.
AC-3: exempt — the resume rule is prose in receipt.md. No model-free test can show a session following it.
AC-4: exempt — removing the round edits skill, doc and template prose. No test can prove it.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The probe's report, read by the intake session | contract (D-5) |
| S-2 | The probe's turn cap and emit deadline | decided (D-2) |
| S-3 | receipt.md "Probe the record" on a partial report | decided (D-6) |
| S-4 | The question to the operator after two resumes | decided (D-6) |
| S-5 | The receipt line for a partial round | decided (D-7) |
| S-6 | receipt.md's ticket-body round and its routing list | decided (D-8) |
| S-7 | The SKILL.md gate row and both SECOND-SHIFT.md lines | decided (D-8) |
| S-8 | A ticket with no AC block | decided (D-9) |
| S-9 | The probe eval README and BASELINE.md | decided (D-10) |
| S-10 | The eval's `seeded-gaps.md` answer key | decided (D-11) |
| S-11 | The resume message and the resumed probe's deadline | decided (D-15) |
| S-12 | A session with no `Task` or no SendMessage | decided (D-15) |
| S-13 | Unverified items left in an accepted partial report | decided (D-16) |

## Checks

- `bash plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs-revision, 0 blockers, 8 warnings. The interview settled them, and the operator approved a rewritten body. The ticket-body probe round was skipped: the scope is prose, and D-8 removes that round. The record round returned a full report in 12 tool uses, with AC-1 to AC-4 covered. It raised three guess-points, settled as D-15 and D-16.

Split: not triggered. No epic label and one deliverable. The register reached 10 operator decisions, but they all edit one set of about eight files in one capability.

Explore: done. Read the probe agent, receipt.md, SKILL.md, check-emit-deadline.sh and its selftest, the progressive-emit and escalated-emit code in code-review.mjs, the probe eval and three committed receipts. Checked the subagent docs for cap and resume behavior.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: the first acceptance item needs a live model run. On the operator's answer it moved to `## Post-merge checks` as PM-1 (D-12, D-13).

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
