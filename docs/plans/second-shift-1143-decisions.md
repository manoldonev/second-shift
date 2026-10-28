# Decision record — #1143 dev-pipeline: keep the consumer PR template first and collapse pipeline sections and verdict rows

Receipt: v4

## Summary

A lane PR body shows the consumer template first, filled by the build. Every pipeline-only section follows it in one collapsed block that the build writes, and `run.sh` fills its run report inside that block in place. The verdict comment folds its rows table under a checked score count. A new `post-review-status.sh --recheck` re-checks a verdict comment edited after posting.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Split the ticket? | One ticket. The PR-body half and the verdict half ship in one PR. | user-answered | intent |
| D-2 | Who owns the one collapsed pipeline block? | The build writes it after the template: one `<details>` with Review focus, Decisions made for you, Checks, the `Decision record:` link, `Record baseline:` and an empty `<!-- pipeline-cost-block -->` marker pair. `write_run_block` replaces the marker region in place. It appends only when the body has no marker. `run.sh` never writes the link or the baseline. This supersedes the ticket's line that `run.sh` writes them. | user-answered | intent |
| D-3 | What does the fold's `<summary>` show? | The build writes `<summary>second-shift</summary>`. At each terminal `run.sh` rewrites the summary of the fold holding its marker region to `second-shift: <outcome> after <n> round(s) · verdict <v> · CI <ci> · $<cost>`. Each note of a failed write appends ` · ` and a short flag: status NOT posted, verdict notice NOT posted, verdicts NOT all minimized, NOT a draft, still a draft. The full notes sit inside. The nested `Run details` fold is flattened into the one block. | user-answered | intent |
| D-4 | Where do the build's other sections go? | The build fills the template's own sections with what changes and the changes. It writes no `## What this changes` heading of its own. The Closes line goes where the template asks for linked issues, else after the template. Review focus, Decisions, Checks, link and baseline go in the fold, not in a PR comment. | user-answered | intent |
| D-5 | `## Before you merge` placement | Dropped when it has nothing to say. When it has content, it stays visible above the fold, right after the template. | user-answered | intent |
| D-6 | Body when the repo has no PR template | A stand-in above the fold: `## What this changes` (at most 80 words), `## Changes`, Before you merge when non-empty, the Closes line, then the fold. | user-answered | intent |
| D-7 | Order against #1019 | #1143 lands first and does not wait for #1019. There is no code dependency. Whichever builds second rebases the shared prompt lines. | user-answered | intent |
| D-8 | Re-run on a body written before the change | `run.sh` replaces its marker region in place. When no fold encloses the region, it wraps only its own block in a fold with the D-3 summary. It never moves or deletes a line the build wrote. | user-answered | intent |
| D-9 | Rows-table summary grammar | One line: `<details><summary><N> rows: <k> honored, <k> departed, <k> violated, <k> undeterminable</summary>`. Scores keep this order. Zero counts are omitted. It always says `rows`. A blank line follows it. `</details>` stands on its own line after the table. `<details open>` fails. Under a `reason:` line, N counts the table's rows. `verdict-check.sh` fails counts that differ from the table. | user-answered | intent |
| D-10 | Visibility of rows that are not honored | A verdict that folds the rows table must have `## Summary`, and `verdict-check.sh` fails it otherwise. The existing naming rule then shows every row that is not honored above the fold. A bare-table verdict without Summary still passes. | user-answered | intent |
| D-11 | Re-check a verdict edited after posting? | In scope: `post-review-status.sh` gains a `--recheck` mode. | user-answered | intent |
| D-12 | `--recheck` interface | `post-review-status.sh [--repo r] --recheck <comment-id> <pr> <sha> <record-at-head> <record-at-first> <target-url>`. It reads the comment body by id through `$GH`. Then it runs the existing path unchanged: verdict-check, plan coverage on an approve, and the status the verdict implies on `<sha>`. | user-answered | intent |
| D-13 | `--recheck` on a failing body | A broken rule, or red plan coverage on an approve, posts `error` under `second-shift/review` on `<sha>`. The description names the first failed rule. It prints every rule and exits 1. A recheck that cannot evaluate posts nothing and exits 2. A failed post exits 3. | user-answered | intent |
| D-14 | Tests for AC-3 and AC-5 | Both are `holds`. Today's code already finds a folded link and baseline and passes a bare table. Their tests must keep passing and stay off the fails-without-the-change check. | user-answered | intent |
| D-15 | Tests for AC-1 and AC-6 | AC-1 is `exempt`: the layout is model output from prompt prose, and the review scores the prompt diff. AC-6 is `holds`: `check-lockstep-pairs.sh` keeps passing on the edited pair. | user-answered | intent |
| D-16 | ACs for the decided behavior | The ticket body was amended at intake with AC-9 to AC-14 and a new AC-8. AC-1 to AC-7 stay verbatim. | user-answered | intent |
| D-17 | Fold the verdict's `## Notes` too? | No. Notes stays as it is. | user-answered | intent |
| D-18 | Who calls `--recheck`? | Whoever edits a posted verdict in place, by hand. No automatic trigger. `review/SKILL.md` keeps "Never edit it." for the review session and gains one line naming `--recheck`. | user-answered | intent |
| D-19 | The interactive build's body recipe | `build/SKILL.md` restates the body order and changes in lockstep with the build prompt — run: `grep -n 'Record baseline' plugins/dev-pipeline/skills/build/SKILL.md` → 56: then the record link, `Record baseline:` and `Closes` | codebase-derived | fact |
| D-20 | The PR-body readers find folded lines | `pr_conventions` greps the record path anywhere. The review's read and `baseline_follows` match `Record baseline:` per line — run: `grep -nE 'grep -qF "\$RECORD_REL"\|\^Record baseline: \[0-9a-f\]' plugins/dev-pipeline/skills/run/run.sh` → 1343 and 1366 | codebase-derived | fact |
| D-21 | `post-review-status.sh` delegates the grammar | It runs `verdict-check.sh` on the body, so AC-7 follows from AC-4 — run: `grep -n 'verdict-check.sh' plugins/dev-pipeline/tools/post-review-status.sh` → 41: rules="$(bash "$HERE/verdict-check.sh" "$BODY" "$4" "$5")" | codebase-derived | fact |
| D-22 | Other parsers of the rows table | None in production besides `verdict-check.sh`. The other hits are selftests — run: `grep -rln 'Decision record rows' plugins scripts tools \| grep -v -e fixtures -e selftest` → verdict-check.sh, review/SKILL.md, run.sh | codebase-derived | fact |
| D-23 | The lockstep pair for the grammar text | `scripts/check-lockstep-pairs.sh` anchor `verdict-grammar`, `review/SKILL.md` against `run.sh` — run: `bash scripts/check-lockstep-pairs.sh \| grep verdict-grammar` → PASS: verdict-grammar (verbatim) | codebase-derived | fact |

Options weighed:
- D-1: two parallel slices, two sequential slices, or one ticket. The operator chose one ticket.
- D-2: the build writes the fold and `run.sh` fills it in place, `run.sh` owns the fold and lifts the build's region, or `run.sh` also writes the link and the baseline. The operator chose the first.
- D-3: outcome plus every failed-write flag, or outcome plus status NOT posted only. The operator chose every flag.
- D-4: fill the template and fold the pipeline-only sections, fold everything, or also keep Checks visible. The operator chose the first.
- D-5: visible above the fold, or inside it. The operator chose visible.
- D-6: a minimal stand-in, or only Closes. The operator chose the stand-in.
- D-7: #1143 first and independent, or block it on #1019. The operator chose independent.
- D-8: fold only its own block, or migrate the whole body. The operator chose its own block.
- D-9: fixed and checked counts, or format asked and not checked. Then strict one-line form, or lenient. The operator chose fixed, checked and strict.
- D-10: required with a fold, required always, or unchanged. The operator chose required with a fold.
- D-11: in this ticket, or a follow-up. The operator chose in.
- D-12: comment id replaces body-file, or comment id alone with the rest derived. The operator chose the first.
- D-13: overwrite with `error`, or report only. Then unevaluable posts nothing, or also `error`. The operator chose `error`, and nothing when unevaluable.
- D-14: both holds, or AC-3 as a new position check. The operator chose both holds.
- D-15: AC-1 exempt and AC-6 holds, or both exempt. The operator chose the first.
- D-16: amend the ticket, or rows only. The operator chose to amend.
- D-17: leave Notes, or allow folding it. The operator chose to leave it.
- D-18: manual for whoever edits, or also lift "Never edit it". The operator chose manual.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9 AC-10 AC-11 AC-12 AC-13 AC-14

AC-1: exempt — the layout is model output from prompt prose; the review scores the build-prompt and build/SKILL.md diff
AC-2: run.sh rewriting the run block of a body whose fold holds the marker pair replaces the region in place, leaving one region, one fold, and the link and baseline lines unchanged
AC-3: holds — pr_conventions and the review's body read find the record link and the baseline inside the fold
AC-4: verdict-check passes a verdict whose rows table is folded under a correct summary, and still fails an unscored row or an unknown score inside the fold
AC-5: holds — a bare-table verdict, with and without ## Summary, still passes verdict-check
AC-6: holds — check-lockstep-pairs.sh passes with the edited verdict-grammar pair
AC-7: post-review-status.sh posts the status for a verdict whose rows table is folded
AC-8: each test of AC-2, AC-4, AC-7 and AC-9 to AC-14 fails on the record commit
AC-9: run.sh rewrites the enclosing fold's summary to the outcome line, with a status NOT posted flag when no status was posted
AC-10: on a body with no fold around the marker region, run.sh wraps only its own block in a fold and leaves every other line unchanged
AC-11: verdict-check fails a folded verdict whose summary counts differ from the table
AC-12: verdict-check fails a verdict that folds the rows table and has no ## Summary
AC-13: post-review-status.sh --recheck on a passing comment re-posts the status the verdict implies
AC-14: post-review-status.sh --recheck on a failing comment posts error under second-shift/review on the sha and exits 1

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | PR body above the fold, with a template | decided (D-4) |
| S-2 | PR body above the fold, no template | decided (D-6) |
| S-3 | Before you merge, empty and non-empty | decided (D-5) |
| S-4 | The fold before the first terminal | decided (D-2) |
| S-5 | The fold's summary after a terminal | decided (D-3) |
| S-6 | A failed status, draft or minimize write | decided (D-3) |
| S-7 | A round-2 build editing the decisions table | decided (D-2) |
| S-8 | A re-run on a body from before the change | decided (D-8) |
| S-9 | Verdict with the rows table folded | decided (D-9) |
| S-10 | Verdict with a row not honored | decided (D-10) |
| S-11 | Verdict without a fold, posted earlier | decided (D-14) |
| S-12 | Verdict Notes section | decided (D-17) |
| S-13 | Recheck of a passing edited verdict | decided (D-12) |
| S-14 | Recheck of a failing edited verdict | decided (D-13) |
| S-15 | Jira ticket heading and built-by marker placement | out-of-scope — the ticket's Out list leaves them to #1019 |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: blocked on block ownership and AC-5. Both became interview questions, settled as D-2 and D-14.

Split: not split. Two deliverables triggered it. The operator kept one ticket over the two-slice recommendation.

Explore: done. Read the build prompt, cost_block, write_run_block, pr_conventions, verdict-check.sh, post-review-status.sh and the lockstep pairs.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
