# Decision record — #1139 The lane review scores a where-the-rule-applies row against every caller

Receipt: v4

## Summary

The lane review's row scoring changes for a row that says where a rule applies. Such a row is `honored` only when every caller in the repository at the head gets the rule. A caller left outside makes the row `violated`, and the review files a `[blocker]` at that caller. The clause lands in `run.sh` and `review/SKILL.md` under one lockstep anchor. A post-merge planted run decides whether it stays.

Open regions: OR-1 the clause wording and anchor name, the build's default.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which review changes, and the case's truth | The lane review only. The plain review files the `mn7cuh` break as a blocker in 3 of 3 stored runs. The case's truth stays a P4 blocker. | user-answered | intent |
| D-2 | What the lane change is | A clause in row scoring. A row that says where or to what a rule applies is `honored` only when the review names each caller and shows each one gets the rule. | user-answered | intent |
| D-3 | What a `violated` reach row produces | A `[blocker]` at the uncovered caller's file:line, with a concrete input the caller handles differently from the rule. A violated row is already a blocker. The bench scores a P4 case right only through a matched blocker. run: `grep -c "A violated or undeterminable row is a blocker" plugins/dev-pipeline/skills/run/run.sh` → 1 | codebase-derived | fact |
| D-4 | Which callers a row can exclude | A caller that the row or the ticket itself names as outside the rule does not count. No provenance condition applies to that row. | user-answered | intent |
| D-5 | How far "every caller" reaches | Every caller in the repository at the head. A caller that only passes an opt-in along is followed up to the callers that decide it. External and dynamic callers do not count. | user-answered | intent |
| D-6 | How the two copies stay the same | Both copies sit inside one new `LOCKSTEP-BEGIN` anchor, which `scripts/check-lockstep-pairs.sh` compares. cited (convention): .claude/skills/writing-tests/SKILL.md:13 | codebase-derived | fact |
| D-7 | The selftest | A `run*-selftest.sh` case greps the rendered review prompt `prompt-2.txt` for the clause. It fails without the clause. run: `grep -c "prompt-2.txt" plugins/dev-pipeline/skills/run/run-rows-selftest.sh` → 4 | codebase-derived | fact |
| D-8 | When the replay runs | Post-merge, as PM-1, by the operator on `main` before the next release. On a fail the operator reverts the clause by a PR. | user-answered | intent |
| D-9 | The PM-1 case set and pass rule | 17 cases × 3 runs against the stored lane in `planted-results-20261028T091739Z.json`. `mn7cuh` must be right in at least 2 of 3. The other 11 bug cases get no fewer right. No control is harmed more. | user-answered | intent |
| D-10 | The clause wording and the anchor name | Parked under OR-1 (owner: the build, by its default) | deferred | open |

Options weighed:

- D-1: lane only with the truth kept, both reviews, or the case dropped to a note. The operator chose lane only with the truth kept.
- D-2: a row-scoring reach clause, a pass-1 caller list, or no change. The operator chose the row-scoring clause.
- D-4: any row or the ticket can exclude a caller, or only a row with named provenance. The operator chose any row or the ticket.
- D-5: callers in the repository at the head, or unlistable callers scored `undeterminable`. The operator chose the repository at the head.
- D-8: post-merge with a revert on fail, or pre-merge in the build. The operator chose post-merge.
- D-9: the 17 PM-1 cases, the full 49-case row, or `mn7cuh` alone. The operator chose the 17 cases.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The clause wording and the lockstep anchor name | reversible-default-and-flag |

OR-1 default: the build words the clause from AC-1 and names the anchor. The intake chose it. Reversing it is a text edit in two files.

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: the review prompt `run.sh` renders carries the reach clause, and a `run*-selftest.sh` case finds it in `prompt-2.txt`
AC-2: `review/SKILL.md` carries the same clause inside the same lockstep anchor, and `check-lockstep-pairs.sh` passes
AC-3: the selftest case fails when the clause is removed from `run.sh`

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The lane review prompt's row-scoring instruction | decided (D-2) |
| S-2 | The by-hand review skill's row-scoring step | decided (D-6) |
| S-3 | The verdict a violated reach row produces | decided (D-3) |
| S-4 | The plain review and other bench arms | out-of-scope — the plain review already catches this break. |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-rows-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: interviewed (feature) from a decision ticket. The operator answered the reframe, fix, replay and pass rule. spec-reviewer: one blocker and three gaps, all folded in. The body was replaced on the operator's yes.

Split: not triggered. The ticket has one deliverable, no epic label, and fewer than ten decisions.

Explore: done. Read the row-scoring line, the lockstep blocks, `score_review`, the `mn7cuh` case and upstream PR 15209.

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
