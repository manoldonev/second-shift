# Decision record — #1215 Reviews: one short verdict format for review-lead and the lane

Receipt: v4

## Summary

Both reviewers write one short verdict format. review-lead adopts the lane verdict grammar, and every relevant finding gates in it. The folded `dev: lane vs blind` block becomes one visible line. `verdict-check.sh` enforces the length limits and gains a no-record mode that review-lead and its posting script use. The posted review body leaves out the findings posted inline.

Open regions: OR-1 review-lead keeps `--format report` in the join. OR-2 the void report is unchanged. OR-3 the limit counts skip join-written lines. OR-4 review-lead copies only the lane's style and knowledge-base blocks. OR-5 the no-record mode requires `reviewed-by:` and a Summary. OR-6 coverage-gap lines join `Not reviewed:`. OR-7 an inline comment keeps the reviewer tag.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The bar for every review comment | As short as possible, with nothing essential lost, for a senior or distinguished engineer. A PR carries many comments, so each one must be short enough to be read in full. | user-answered | intent |
| D-2 | Where the report gets short | Everywhere. review-lead writes one short report. The terminal shows it whole. The posted PR body is the same text without the findings posted inline. No second report is written. | user-answered | intent |
| D-3 | Which reviewers follow the principle | Both: review-lead and the lane verdict. | user-answered | intent |
| D-4 | Split the ticket | Not split. One ticket covers both plugins. | user-answered | intent |
| D-5 | review-lead's report format | review-lead writes the lane verdict format and follows the lane's tag rules. Every relevant finding gates, a note the same as a blocker. There is no Suggestions tier and no "With fixes" verdict. | user-answered | intent |
| D-6 | The `dev: lane vs blind` block, in both reviewers | One visible line `lane vs blind: <counts>`, with the counts the block's summary gives today. The pair list, the verdict and session lines and the blind draft are removed. Inputs: none — the join derives the line and the JSON from both drafts. Outputs: the visible line, and the hidden `<!-- plain-vs-lane: {json} -->` line with its current fields, cost and wall time included. Errors: none — the join writes both lines on every joined body. | user-answered | intent |
| D-7 | How coverage is shown in review-lead | No Verdicts table. The Summary holds one `Not reviewed:` line. It names each dark reviewer, each of the three not-selected cases that SKILL.md says must not be invisible, and a missing issue number. The line is absent when everything ran. Departs from AC-4: the line names only those three not-selected cases, not every reviewer that was not selected. | user-answered | intent |
| D-8 | The posted review body and its inline comments | The posting script derives the body from the one report. Each finding in `## Findings` whose first path:line is inside a diff hunk is an inline comment, without its id, site and tag. An inline `[blocker]` keeps one body line `- [blocker] B<n> path:line — <first sentence>`. A finding not posted inline stays in full. When any note went inline, `## Findings` ends with `<k> notes are inline comments.` Departs from AC-8: the pointer line keeps the `- [blocker]` prefix and gives the first sentence, and the count line is added. | user-answered | intent |
| D-9 | review-lead's Data provenance table | Removed from the report. The lead pass still traces the fields. An unverified field on the critical path, or a field that is not stored, stays a finding. | user-answered | intent |
| D-10 | review-lead's Pre-existing gaps list | Removed. A problem that the diff is the first to depend on is still a finding, as today. | user-answered | intent |
| D-11 | The format guard for review-lead | review-lead runs `verdict-check.sh` in its no-record mode before it gives or posts the report. A failing report is rewritten and checked again until it passes. `post-pending-review.sh` runs the same check and refuses a failing report. When the checker cannot run, the terminal shows the report with one line `Format not checked: <why>`, and no post is offered. | user-answered | intent |
| D-12 | Inline comments from the lane | None. The lane keeps its one PR comment, which the next build round reads. The operator: review-lead reviews foreign PRs and is never used on second-shift tickets. | user-answered | intent |
| D-13 | A `## Notes` topic that changed no score or finding | Left out, in both reviewers. Notes keeps the one-line items the rules require and what changed a score or a finding. This rule has no test. The operator exempted it. | user-answered | intent |
| D-14 | Enforce the length limits | `verdict-check.sh` fails a verdict in both modes when `## Summary` has more than 8 lines, `## Notes` has 150 words or more, or a `[note]` finding has more than 4 lines. | user-answered | intent |
| D-15 | The line `Knowledge-base contributions: none` | Dropped in both reviewers. The contributions block appears only when it has a proposal. `verdict-check.sh` fails a verdict that contains the `none` line. | user-answered | intent |
| D-16 | A gate reviewer that went dark in review-lead | The verdict is `needs-work` with line 3 `reason: seat-unavailable`. A scope reviewer that cannot read the ticket gives `reason: ticket-unreadable`. This covers the scope, security and on-demand performance reviewers. | user-answered | intent |
| D-17 | A decision record in review-lead | review-lead never writes `## Decision record rows` and always uses the no-record mode. A plan or record given to it still informs its findings. | user-answered | intent |
| D-18 | The no-record mode's interface | `verdict-check.sh <verdict-file>`, the verdict file alone. Inputs: the verdict file, required; the two record files stay optional as a pair. Outputs: exit 0 when the verdict passes. Errors: exit 1 with one line per broken rule; exit 2 when a file cannot be read. | user-answered | intent |
| D-19 | Exempt the prose-only criteria from tests | AC-4 is exempt, and so is the Notes half of AC-9. No script can check what the model leaves out. The review reads the skill change. | user-answered | intent |
| D-20 | How the posting script finds the sha | It reads the sha from the `reviewed:` line, which stays line 2 in the lane grammar. Line 1 becomes `verdict:`, so the line 1 check changes. run: `sed -n 36,38p plugins/review-toolkit/scripts/post-pending-review.sh` → line 1 must start `reviewed-by: second-shift review-lead`, line 2 is `reviewed: <sha>` | codebase-derived | fact |
| D-21 | Where `run.sh` cuts the findings for the next build round | Today it cuts at the folded block's first line. The cut must move to the new `lane vs blind:` line, with a `run*-selftest.sh` case that fails without it. run: `grep -n 'dev: lane vs blind/ { exit }' plugins/dev-pipeline/skills/run/run.sh` → 2166. cited (convention): CLAUDE.md:147 | codebase-derived | fact |
| D-22 | The posted review's body creation | Already done. The script creates the review with its body in one POST. The ticket's original proposal items for this need no change. run: `grep -c 'commit_id: $sha, body: ' plugins/review-toolkit/scripts/post-pending-review.sh` → 1 | codebase-derived | fact |
| D-23 | The JSON fields the one-line summary may drop | Cost and wall time stay in the hidden JSON line, so the visible line needs no session data. run: `grep -oE '[a-z]+_(cost_usd\|wall_s)' plugins/dev-pipeline/tools/verdict-join.sh \| sort -u` → lane_cost_usd lane_wall_s plain_cost_usd plain_wall_s | codebase-derived | fact |
| D-24 | The join mode review-lead uses | Parked under OR-1. | deferred | open |
| D-25 | The void "review did not run" report | Parked under OR-2. | deferred | open |
| D-26 | What the length limits count | Parked under OR-3. | deferred | open |
| D-27 | Where review-lead keeps the shared rules | Parked under OR-4. | deferred | open |
| D-28 | A note that only the blind review found, in review-lead | The join adds it as a `[blind]` finding, as in the lane. Any finding makes the verdict `needs-work`, so a blind-only note can turn an approve into `needs-work`. | user-answered | intent |
| D-29 | How strict the no-record mode and the posting check are | Parked under OR-5. | deferred | open |
| D-30 | Where review-lead's other coverage lines go | Parked under OR-6. | deferred | open |
| D-31 | The tags and wording in an inline comment | Parked under OR-7. | deferred | open |
| D-32 | How review-lead and the posting script find `verdict-check.sh` | Through `plain-review-tools.sh`, which already locates dev-pipeline's tools dir for the join. Its contract adds `verdict-check.sh`. An older checker exits 2 on one argument, which gives `Format not checked:`. run: `sed -n 2,3p plugins/review-toolkit/scripts/plain-review-tools.sh` → it prints the dev-pipeline tools dir that holds plain-review.sh and verdict-join.sh | codebase-derived | fact |
| D-33 | Suppressed, dismissed and aspirational findings in review-lead | Not listed, as in the lane. review-lead's SKILL.md rules that route them to `## Suppressed` or `## Future improvements` change with it. cited (convention): plugins/dev-pipeline/skills/review/SKILL.md:215 | codebase-derived | fact |
| D-34 | The `lane vs blind:` line when the blind review did not return | `lane vs blind: the blind review did not return`, from the current fold summary. The visible line comes before the hidden JSON line, so the `run.sh` cut drops both. run: `sed -n 210p plugins/dev-pipeline/tools/verdict-join.sh` → `dev: lane vs blind — the blind review did not return` | codebase-derived | fact |
| D-35 | review-lead's Summary lines that D-7 and OR-6 do not place | A recovered reviewer and a fidelity seat's summary each get one `## Notes` line. The empty-selection note is dropped: an empty selection already puts the security and missing-issue entries on `Not reviewed:`. Added in build: the eight-line Summary has no room for them, and no row placed them. | user-delegated | intent |
| D-36 | A `[blind]` note longer than the four-line note limit | The join keeps the note's first line and its first three continuation lines, and appends each later continuation line to the third, so no text is lost and the joined body passes the check. The blind-review prompt is unchanged. Added in build: no session may edit a `[blind]` note, so a long one made the joined body fail the check with no way to fix it, and neither D-14 nor D-28 covered the case. | user-delegated | intent |

Options weighed:

- D-2: a short PR copy only, or one short report everywhere. The operator chose everywhere.
- D-3: review-lead only, or both reviewers. The operator chose both.
- D-4: two parallel slices, or one ticket. The operator chose one ticket.
- D-5: shared rules with separate formats, or one format. The operator chose one format.
- D-6: remove the block, keep a one-line summary, or keep the folded block. The operator chose the one-line summary.
- D-7: one `Not reviewed:` line, or that line plus a folded table. The operator chose the line.
- D-8: pointer lines with a count line, or pointer lines only. The operator chose pointer lines with a count line.
- D-9: remove the table, or keep it in Notes. The operator chose to remove it.
- D-10: drop the list, or one Notes line each. The operator chose to drop it.
- D-11: the same checker, or a skill rule only. The operator chose the checker. Unchecked: post with a warning, or no post. The operator chose no post.
- D-12: the lane keeps one comment, or posts inline too. The operator chose one comment.
- D-13: leave the topic out, or keep one sentence. The operator chose to leave it out.
- D-14: the checker enforces, or prose rules only. The operator chose the checker.
- D-15: drop the `none` line, or keep it. The operator chose to drop it.
- D-16: the lane's reason line, or a blocker finding. The operator chose the reason line.
- D-17: never write the table, or score a record when one exists. The operator chose never.
- D-18: one argument, or an explicit flag. The operator chose one argument.
- D-19: exempt both, or require tests. The operator chose to exempt both.
- D-7 (reading): the three must-be-visible skips only, or every reviewer not selected. The operator chose the three.
- D-28: add blind notes as in the lane, or keep dropping them. The operator chose to add them.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The join mode review-lead uses | reversible-default-and-flag |
| OR-2 | The void "review did not run" report | reversible-default-and-flag |
| OR-3 | What the length limits count | reversible-default-and-flag |
| OR-4 | Where review-lead keeps the shared rules | reversible-default-and-flag |
| OR-5 | How strict the no-record mode and the posting check are | reversible-default-and-flag |
| OR-6 | Where review-lead's other coverage lines go | reversible-default-and-flag |
| OR-7 | The tags and wording in an inline comment | reversible-default-and-flag |

- OR-1 default: review-lead keeps `--format report`. That mode now takes the verdict path, blind notes included (D-28), and the JSON still says `"format":"report"`. The intake agent chose it. Reversing it changes one flag value.
- OR-2 default: unchanged. The void report stays free-form, unchecked and never posted. The intake agent chose it. Reversing it means one more grammar form.
- OR-3 default: the Summary limit counts non-blank lines. The Notes count skips the knowledge-base block, the hidden JSON line, the `Joined review:` line and the `lane vs blind:` line. The intake agent chose it. Reversing it changes the count rule.
- OR-4 default: review-lead's SKILL.md carries byte-identical lockstep copies of the lane's `verdict-style` and `kb-contributions` blocks only. It states its own grammar outside them: the lane grammar without the record rows (D-17). It copies no `verdict-grammar` or review-pass block, because those require the record. The intake agent chose it. Reversing it moves text.
- OR-5 default: the one-argument mode requires the `reviewed-by:` line and `## Summary`, as AC-1 lists them. The posting script requires line 1 `verdict:` and `reviewed-by: second-shift review-lead` on line 3, or on line 4 after a `reason:` line. The intake agent chose it. Reversing it relaxes two checks.
- OR-6 default: a `[Coverage gap]` line and the reduced-coverage note become entries on the `Not reviewed:` line. The partial-mode `Not delivered by this PR (linked as <verb>): <items>` stays one Summary line. The intake agent chose it. Reversing it moves lines.
- OR-7 default: an inline comment drops the finding's id, its site and its `[blocker]` or `[note]` tag. It keeps a reviewer tag and shows `[blind]` as `[Blind review]`, as today. The pointer line's first sentence uses the join's first-sentence excerpt. The count line reads `1 note is an inline comment.` for one. The intake agent chose it. Reversing it changes the comment text.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8 AC-9 AC-10

AC-1: `verdict-check.sh` with one argument passes a review-lead verdict in the lane format and fails one that has `## Decision record rows`
AC-2: `verdict-check.sh` with one argument fails a verdict that has a Strengths, Suggestions or Verdicts section, or a `Ready to merge?` line
AC-3: `verdict-check.sh` with one argument fails `verdict: approve` when the verdict has a finding
AC-4: exempt — a rule for what the model writes in its Summary; no script can check it
AC-5: `post-pending-review.sh` posts nothing and exits non-zero when the report fails `verdict-check.sh`
AC-6: `verdict-check.sh` fails a 9-line Summary, a 150-word Notes section and a 5-line note in both modes, and passes each at its limit
AC-7: `verdict-join.sh` writes one `lane vs blind:` line and the hidden JSON line, and no `dev: lane vs blind` fold, in both formats
AC-8: `post-pending-review.sh` leaves an inline note out of the body, keeps one pointer line for an inline blocker, and keeps a finding outside the diff in full
AC-9: `verdict-check.sh` fails a verdict that contains the line `Knowledge-base contributions: none`
AC-10: `run.sh` hands the next build round the findings without the `lane vs blind:` line (a run-selftest case)

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | review-lead's report in the terminal | decided (D-5) |
| S-2 | The posted pending-review body | decided (D-8) |
| S-3 | Inline review comments on a foreign PR | decided (D-8) |
| S-4 | The lane verdict PR comment | decided (D-13) |
| S-5 | The `lane vs blind:` line and its hidden JSON line | contract (D-6) |
| S-6 | The `Not reviewed:` Summary line | decided (D-7) |
| S-7 | The `reason:` line in a review-lead verdict | decided (D-16) |
| S-8 | `verdict-check.sh` command-line interface | contract (D-18) |
| S-9 | The terminal line `Format not checked: <why>` | decided (D-11) |
| S-10 | The findings `run.sh` hands the next build round | decided (D-21) |
| S-11 | `verdict-join.sh` command-line arguments | out-of-scope — its arguments do not change; its output is S-5. |
| S-12 | The void "review did not run" report | out-of-scope — it stays as it is, under the OR-2 default. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written, against review-toolkit 11.9.0. spec-reviewer: needs work, with two operator-only blockers. The interview closed both, and the operator approved a rewritten title and body with AC-1 to AC-10.

Split: not split. The register passed 10 decisions and returned here. codebase-explorer mapped about 25 files in two plugins. The operator chose one ticket over two parallel slices.

Explore: done. Read review-lead's report contract, the posting script, the join, the checker, the lane grammar and three recent lane verdicts. A research Workflow on community practice for review comments ran: 4 Opus seats, 4 Opus refuters and an Opus synthesis.

Fan-out: skipped — by the operator at the intake notice: replaced by a research Workflow on community practice for review verdict comments

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: replaced by a research Workflow on community practice for review verdict comments

</details>
