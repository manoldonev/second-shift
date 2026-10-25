# Decision record — #1124 The lane review reads the record after its code review and blocks on breaks of existing callers or data

Receipt: v4

## Summary

The lane review runs in two passes. Pass 1 reviews the ticket and the code without the record. Pass 2 reads the record and scores its rows. A record row never weakens a pass-1 finding, except under one narrow rule. A finding that shows existing callers or data breaking is a blocker. A notes pass for maintainability, test coverage and conventions ends pass 1. The change lands in `review_prompt()`, the review skill and the bench arm. PM-1 checks that the wording does no harm in a record-less review. The held-out check is the evidence that it works.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How item 1 and item 2 fit | Item 2 is the only exception to item 1. A break of an existing caller or existing data drops to a note only when the ticket or a row names that exact case and accepts it. The row must also carry a decider per D-12. The finding must quote that line. No other record ground removes, dismisses or downgrades a pass-1 finding. | user-answered | intent |
| D-2 | Layout of the two-pass text across the lockstep sites | Items 1 and 2 go into the `review-correctness` block in plain words, such as "the plans directory", "the scratch directory" and "when there is a record". `review_prompt()` and the review skill print the concrete pass-1 diff command and the pass-2 record reads outside the block. The bench arm's framing sentence, outside the block, says pass 2 does not apply there. | user-answered | intent |
| D-3 | Which record-dependent instructions move to pass 2 | Every instruction that reads the record moves to pass 2. These are the record clause and the test-intent exemption of `review-completeness`, the diff line's "against the ticket and the record", and the build's-account line's "from the record". They also include the trace-to-a-row checks on test expectations and policy edits, the verdict-check line and the design-reviewer dispatch. Pass 1 checks the ticket's ACs only. The record path appears nowhere before the pass-2 marker. | user-answered | intent |
| D-4 | How pass 1 stays clean of the record and the build's account | By instruction only. Pass 1 writes its findings to `$SCRATCH/pass-1-findings.md`. It opens no other scratch file, no PR comment, no earlier verdict and no PR description until pass 2. The order is pass 1, then pass 2, then the build's account. The scheduler and the allowlist are unchanged. | user-answered | intent |
| D-5 | Severity rule vs the performance-row paragraph | The severity rule wins. A worst-case bound that breaks an existing caller or existing data is a `[blocker]`, unless D-1's exception applies. Every other bound stays under the performance-row paragraph, a `[note]` unless it breaks what the row decided. | user-answered | intent |
| D-6 | Shape of the manual review skill | Step 1 keeps its token filter and is not a read of the build's account. Pass 1 runs right after checkout, together with the notes pass. Its diff is `origin/<base>...HEAD` with the plans directory excluded. Its findings go to a file in the session's scratchpad. The record read, the step-4 checks and the row scoring follow as pass 2. The build's account comes last. | user-answered | intent |
| D-7 | Closing the dismissal channel | `review-correctness` states that a pass-1 finding is never posted as `Dismissed.` or `Suppressed.` on a record's ground. D-1's exception is the only way such a finding becomes a note. `verdict-style`, the verdict grammar and `verdict-check.sh` are unchanged. | user-answered | intent |
| D-8 | Placement and wording of the notes pass | The notes pass runs at the end of pass 1, before the record is opened, and writes to the pass-1 file. It reports only what it would post, as `[note]`s with file:line. It uses the term "test-coverage", not "test quality". It lives outside `review-correctness`, in `review_prompt()` and the review skill only. | user-answered | intent |
| D-9 | The PM-1 before basis | A fresh paired run. The operator runs main and the PR head together with the same judge, two runs each. The PR states all four per-run F1 values and both means. The 0.03 margin applies to the means. | user-answered | intent |
| D-10 | Whether AC-4 stays an acceptance criterion | AC-4 moved to `## Post-merge checks` as PM-1, with its text unchanged. The operator runs it before merging. The review does not grade it. | user-answered | intent |
| D-11 | Effect on the planted corpus rows | No planted run is required. The build updates `planted/render-selftest.sh` for the new prompt. The PR body states that planted lane rows before this merge used the one-pass prompt. | user-answered | intent |
| D-12 | What counts as "names who decided" | A row with `user-answered` provenance, or `ticket-sourced` with its comment URL, counts. `user-delegated` and `codebase-derived` rows never accept a break. The ticket's own text counts as the operator's. | user-answered | intent |
| D-13 | Existing selftests that pin the rewritten lines | They must change with the prompt. `run-selftest.sh` case (a) greps the diff sentence and the completeness sentence verbatim. `planted/render-selftest.sh` greps the first line and the `git show $FIRST:<record>` command. run: `grep -c 'against the ticket and the record' plugins/dev-pipeline/skills/run/run-selftest.sh` → 1; `grep -n 'You review PR #42' plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh` → 75 | codebase-derived | fact |
| D-14 | Where the AC-3 case reads the rendered prompt | The fake-claude harness captures the review prompt as `prompt-2.txt`, and run.sh writes it as `review-1.1.prompt`. Existing cases grep both files. run: `grep -c 'prompt-2.txt' plugins/dev-pipeline/skills/run/run-selftest.sh` → 17 | codebase-derived | fact |
| D-15 | Whether `$PLANS_DIR` is set wherever `review_prompt()` renders | It is set in run.sh and in the planted renderer, so the pass-1 exclude can use it. run: `grep -n '^PLANS_DIR=' plugins/dev-pipeline/skills/run/run.sh plugins/review-toolkit/evals/code-review-bench-eval/planted/lane-render.sh` → run.sh:225, lane-render.sh:22 | codebase-derived | fact |

Options weighed:

- D-1: item 2 as the only exception, or no exception at all. The operator chose the only exception.
- D-2: abstract text in the block with commands outside, or a new anchor for the passes. The operator chose abstract text in the block.
- D-3: move all record-dependent lines to pass 2, or only the block and line 1. The operator chose all of them.
- D-4: instruction only, or the scheduler moving scratch files. The operator chose instruction only.
- D-5: the severity rule wins, or the performance paragraph wins. The operator chose the severity rule.
- D-6: pass 1 right after checkout, or the existing steps with a pass marker. The operator chose pass 1 after checkout.
- D-7: a sentence in the block, or a new verdict-check rule as well. The operator chose the sentence.
- D-8: the end of pass 1, or after pass 2. The operator chose the end of pass 1.
- D-9: a fresh paired run, or reuse of the 0.55 row. The operator chose a fresh paired run.
- D-10: move to PM-1, or keep as AC-4. The operator chose PM-1.
- D-11: state the break, or add a planted row. The operator chose to state the break.
- D-12: user-answered or ticket-sourced only, or any provenance. The operator chose user-answered or ticket-sourced.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: the rendered review prompt carries a pass-1 section, a pass-2 section, the severity rule and the notes pass, and `check-lockstep-pairs.sh` passes with the notes pass outside `review-correctness`
AC-2: the first line of the rendered review prompt names no decision record
AC-3: in the rendered review prompt, the record path first appears after the pass-2 marker, and the pass-1 diff command excludes the plans directory

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The rendered lane review prompt | decided (D-2) |
| S-2 | The manual review skill's checklist | decided (D-6) |
| S-3 | The bench arm's prompt | decided (D-2) |
| S-4 | The verdict comment's dismissed and suppressed notes | decided (D-7) |
| S-5 | The PR body's PM-1 numbers | decided (D-9) |
| S-6 | The planted corpus's rendered lane prompt | decided (D-11) |

## Checks

- `bash scripts/check-lockstep-pairs.sh`
- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/bench-arms-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs-spec-work, 1 blocker and 8 gaps. All were operator choices, so the Interview settled them.

Split: not split. The change is one prompt contract held verbatim across three files. A slice would ship a self-contradicting prompt.

Explore: done. Read `review_prompt()`, the review skill, the bench arm, the lockstep checker, the run selftests and the planted renderer.

Fan-out: ran — 28 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: AC-4 moved to PM-1 on the operator's yes.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: pass-one-isolation opus 6/6 · instruction-conflicts fable 5/6 · copies-and-consumers opus 6/6 · acceptance-verifiability fable 6/6 · premortem fable 5/6
Tally: rows added 4 · snapshot claims overturned 0 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | pass-one-isolation | The build's `pr-body.md` draft is still in the shared scratch directory when the review starts (`run.sh:1621`). | new | became D-4 |
| F-2 | pass-one-isolation | The scheduler writes `record-at-first.md` into scratch before it spawns the review (`run.sh:1851`). | new | became D-4 |
| F-3 | pass-one-isolation | The completeness block and the trace lines still point pass 1 at the record (`run.sh:1103,1122`). | already-had | became D-3 |
| F-4 | pass-one-isolation | A plans-directory exclude drops the record and the plan, but `gh pr diff` and the log still show them. | new | became D-4 |
| F-5 | pass-one-isolation | The review allowlist cannot enforce pass-1 isolation, since Read and git are unscoped (`run.sh:1204`). | new | became D-4 |
| F-6 | pass-one-isolation | The review skill reads the record and scores rows before its code review (`review/SKILL.md:41-106`). | already-had | became D-6 |
| F-7 | instruction-conflicts | `run-selftest.sh:34` pins two sentences that bind pass 1 to the record. | new | became D-13 |
| F-8 | instruction-conflicts | The completeness block's test-intent exemption is a record-driven removal (`run.sh:1103`). | already-had | became D-3 |
| F-9 | instruction-conflicts | The performance-row rule lets a row make a breaking finding a note (`run.sh:1098`). | already-had | became D-5 |
| F-10 | instruction-conflicts | `verdict-check.sh` treats finding text as free text, so it enforces no quoted line or dismissal rule. | new | became D-7 |
| F-11 | instruction-conflicts | The lockstep check carries items 1 and 2 verbatim into an arm with no ticket and no record. | already-had | became D-2 |
| F-12 | copies-and-consumers | The block is a quoted heredoc and the arm formats braces, so it holds no variable (`run.sh:1101`). | already-had | became D-2 |
| F-13 | copies-and-consumers | Lines 1092, 1096, 1099 and 1117 send the reviewer to the record outside the block. | already-had | became D-3 |
| F-14 | copies-and-consumers | The bench scores every comment, so only item 1 can move the PM-1 F1 (`rules.md:19`). | already-had | became D-2 |
| F-15 | copies-and-consumers | The skill finds the record from PR-body tokens and runs its steps in reverse order. | already-had | became D-6 |
| F-16 | copies-and-consumers | The design dispatch hands over the record, and an old verdict stays on the PR on a re-spawn. | new | became D-3 and D-4 |
| F-17 | copies-and-consumers | Pass 1's findings file would sit beside `record-at-first.md` in scratch (`run.sh:1851`). | new | became D-4 |
| F-18 | acceptance-verifiability | The run selftests assert prompt text by grepping the prompt the fake claude captured (`run-selftest-lib.sh:100`). | new | became D-14 |
| F-19 | acceptance-verifiability | `review_prompt()` reads no `PLANS_DIR` today, and both AC-3 assertions fail on main. | new | became D-15 |
| F-20 | acceptance-verifiability | `run-selftest.sh` case (a) pins the diff sentence that item 1 rewrites (`run-selftest.sh:34-39`). | new | became D-13 |
| F-21 | acceptance-verifiability | Grepping the captured prompt is an accepted test tier, not a prose-presence guard (`docs/testing.md:323`). | new | became D-14 |
| F-22 | acceptance-verifiability | The 0.55 before row's per-run split is gone, because its results file is gitignored (`changelog.md:14`). | new | became D-9 |
| F-23 | acceptance-verifiability | The only measured run spread is a sibling arm's, about 0.01. | new | became D-9 |
| F-24 | premortem | The `Dismissed.` channel the replay failed through stays open under an unchanged grammar (`run.sh:1132`). | new | became D-7 |
| F-25 | premortem | AC-3 binds only the record path, while other lines still pull the record into pass 1. | already-had | became D-3 |
| F-26 | premortem | Items 1 and 2 cannot be followed in the bench arm, so PM-1 cannot register their effect. | already-had | became D-2 |
| F-27 | premortem | The 0.03 margin compares two-run means that hide their spread (`bench.py:447`). | new | became D-9 |
| F-28 | premortem | Planted lane rows become non-comparable once the prompt changes (`planted/lane-render.sh:40`). | already-had | became D-11 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Item 1 vs item 2 on a row downgrading a finding | Ask. Recommend: item 2's exact-case + decider + quoted-line clause is the only exception to item 1 |
    | D-2 | Where the concrete pass-1/pass-2 commands live, given the block is a quoted heredoc locked verbatim with SKILL.md and the bench arm | Ask. Recommend: the block states the passes abstractly; run.sh and SKILL.md render the concrete commands ($PLANS_DIR exclude, $FIRST) outside it |
    | D-3 | review-completeness block's "every row of the record" clause | Ask. Recommend: moves to pass 2; completeness in pass 1 is ticket ACs only |
    | D-4 | Record-dependent lines outside the block (verdict-check, trace test-expectation and policy edits to a row) | Ask. Recommend: all move under pass 2; AC-3's "named only in pass 2" scoped to that |
    | D-5 | "Read the build's own account last" ordering | Ask/delegate. Recommend: pass 1 → pass 2 → build's account |
    | D-6 | Manual review skill: scratch dir for pass-1 findings and step reorder (steps 3-6) | Ask. Recommend: session scratchpad file; step order pass 1 (step 6 moves before 3/5) |
    | D-7 | Bench arm framing: it has no ticket and no record | Ask. Recommend: arm framing sentence (outside the block) says pass 2 does not apply |
    | D-8 | Severity rule vs deferred-performance-row paragraph | Ask. Recommend: severity rule wins for breaks of existing callers/data |
    | D-9 | AC-4 before row | Fact: changelog row lane-review sha=666d16c opus/sonnet runs=2 f1=0.55. Ask fresh paired vs that row |
    | D-10 | AC-4 checkable before merge? | Post-merge scan question |
    | D-11 | planted/render-selftest.sh asserts the prompt's first line and the record git-show command | Fact: must be updated with the change |
    | D-12 | Planted corpus lane arm renders the real review_prompt, so it shifts too | Ask whether AC-4 covers a planted before/after |
    | D-13 | "Names who decided": provenance label suffices? | Ask. Recommend: the provenance label counts |

</details>
