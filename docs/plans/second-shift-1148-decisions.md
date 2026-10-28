# Decision record — #1148 The blind-prove arm turns an unexcused proven difference into a blocker, and the bench compares it with plain

Receipt: v4

## Summary

After the intent stage ends, the harness amends its verdict. A proven difference, or a test expectation the diff removes, becomes a blocker unless intent grounds it. Grounding is a blocker of intent's own at that site, or a verbatim quote of the ticket or the record. `planted.py compare` sets the arm beside plain's and the lane's stored runs and can print PM-1's verdict.

Open regions: OR-1 several probes for one candidate. OR-2 where the rule runs and what the record keeps. OR-3 the quote check's details.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Whether intent is told the rule | Yes. Intent's prompt states the rule and the quote form. Intent either files the blocker itself or quotes the line that asks for the change. | user-answered | intent |
| D-2 | Which intent finding covers a candidate | A finding in the candidate's file within 3 lines of its site. A blocker there, or a finding with a grounding quote, covers it. An unquoted note there is upgraded to a blocker in place, with no duplicate. | user-answered | intent |
| D-3 | Where removed expectations come from | The harness reads the diff without a model. One counts if all three hold. It is a `-` line in a test file, matched by the overlay's test globs or a `test`, `__tests__` or `spec` path. It holds `expect(`, `assert`, `toBe` or `toEqual`. The `+` side does not re-add it verbatim. `.snap` files never count. Its site is the base-side `path:line`. | user-answered | intent |
| D-4 | What a grounding quote is | A double-quoted span of at least 20 characters. It must appear in the case's `ticket.md` or `record.md` after whitespace normalization. | user-answered | intent |
| D-5 | What an injected blocker says | `[blocker] Hn path:line —` hunt's candidate text verbatim, then `Proven:` with the command and each side's rc and an output excerpt. A removed expectation quotes the removed line and says no ticket or record line asks for it. Ids `Hn` never collide with intent's ids. | user-answered | intent |
| D-6 | An `approve` that gains a blocker | It becomes `needs-work`. | user-answered | intent |
| D-7 | Unscored arm case-runs in PM-1 | They count as not right, out of all attempted case-runs. Nothing is re-run before PM-1 is read. | user-answered | intent |
| D-8 | What `compare` prints | Per case and run: right, wrong, noise and harm for the arm, plain and lane. Then the totals: right counts and the delta against plain, the held-out five against the lane by right count, and harm per control against plain. `--pm1` adds PASS or FAIL per criterion. `r2n5ax` gets its own line outside the totals. | user-answered | intent |
| D-9 | Cases set apart in PM-1 | `r2n5ax` is reported apart. `mn7cuh` stays in the decisive set, and the record notes that the hand probe touched it. | user-answered | intent |
| D-10 | PM-1 controls | All five controls. A control fails if the arm blocks it in more runs than plain did. | user-answered | intent |
| D-11 | The truth version behind the stored baseline | The stored file was judged with #1144's truth text. The re-judge ran on the working copy that #1144 then committed. run: `git show origin/main:plugins/review-toolkit/evals/code-review-bench-eval/planted/cases/la2swf/case.json \| grep -c 'drops the old skip'` → 1 | codebase-derived | fact |
| D-12 | Several probes for one candidate | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-13 | Where the rule runs and what the record keeps | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-14 | The quote check's details | Parked under OR-3 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: tell intent the rule, or enforce it silently. The operator chose to tell it.
- D-2: match by site within 3 lines, or by candidate id. The operator chose the site.
- D-3: the harness reads the diff, or hunt lists the removals. The operator chose the harness.
- D-4: a verbatim span of at least 20 characters, or a row id. The operator chose the verbatim span.
- D-5: hunt's candidate plus the probe evidence, or a fixed sentence. The operator chose the candidate and evidence.
- D-7: count as not right, or leave out. The operator chose not right.
- D-8: numbers plus a PM-1 verdict, or numbers only. The operator chose the verdict too.
- D-9: keep `mn7cuh` in, or report it apart. The operator chose to keep it in.
- D-10: all five controls with plain as the baseline, or three without `h4n8qe`. The operator chose all five.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Several probes for one candidate, or none | reversible-default-and-flag |
| OR-2 | Where the rule runs and what the record keeps | reversible-default-and-flag |
| OR-3 | The quote check's details | reversible-default-and-flag |

- OR-1 default: any `DIFFERS` among a candidate's probes makes it proven. A candidate with no probe adds no blocker. The intake chose it. Reversing it is a one-line rule change.
- OR-2 default: the rule runs in the orchestrator before `collect`. The record keeps intent's original verdict and the amended `text`, so a rescore scores the amended one. A stage that stopped the case-run gets no rule. The intake chose it. Reversing it is a call-site change.
- OR-3 default: straight and curly double quotes both count. The length is counted after normalization, and the match is case-sensitive. Any one valid span grounds the finding. The intake chose it. Reversing it is a test edit.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5

AC-1: a fixture with an unquoted `DIFFERS` candidate and an `approve` comes out `needs-work` with an `Hn` blocker at the candidate's site carrying hunt's text and the probe evidence
AC-2: a finding with a valid 20-character quote from the ticket stays as filed, and a short or absent quote does not ground it
AC-3: an `UNPROVEN` or `SAME` probe adds no blocker
AC-4: `compare` on two fixture results files prints the per-case table, the totals, `r2n5ax` apart, and PASS or FAIL per criterion under `--pm1`
AC-5: the rule's selftest covers all five fixture cases in the ticket, including a removed expectation found from the diff

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The amended verdict text | decided (D-5) |
| S-2 | The intent prompt's rule paragraph | decided (D-1) |
| S-3 | `compare` output | decided (D-8) |
| S-4 | `compare --pm1` verdict lines | decided (D-8) |
| S-5 | The record's two verdict texts | decided (D-13) |
| S-6 | The lane and plain review prompts | out-of-scope — this slice does not touch them. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`

## Intake steps

Requirements: the parent #1145 as filed. spec-reviewer found three blockers. The split answered them.

Split: split into #1146, #1147 and #1148 (sequential). This receipt is for #1148.

Explore: done. Read parse_verdict, score_review, case_report and tally, and the stored baseline. The implementability probe ran once, and the interview answered its blocking points.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC moved. PM-1 was already a post-merge check.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
