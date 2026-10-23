# Decision record — #1111 Lane review prompt: an AC with no test reads as both a completeness finding and a test-coverage note

Receipt: v4

## Summary

The lane's review prompt says a completeness problem can be a `[blocker]` and a test-coverage problem is a `[note]` only. An acceptance criterion with no proving test reads as both. This change rewrites one sentence of the `review-completeness` block at its two lockstep sites. The missing test is then a completeness finding that can be a `[blocker]`. The run selftest's case (a) asserts the new sentence. The implementability probe was skipped: the deliverable is one sentence, and D-1 fixes its text, so a cold implementer has nothing to guess.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | The amended completeness sentence | "An acceptance criterion with no test that proves it is a completeness finding, not a test-coverage problem, so it can be a `[blocker]`, unless the record's test intent exempts it." It replaces the current sentence in place. The correctness block's must-change-before-merge rule still decides blocker or note. | user-answered | intent |
| D-2 | Where the sentence lands | Both `review-completeness` lockstep sites, verbatim: run.sh and the review SKILL.md. CI's lockstep check holds them equal. run: `git grep -c "LOCKSTEP-BEGIN review-completeness" origin/main` → plugins/dev-pipeline/skills/review/SKILL.md:1, plugins/dev-pipeline/skills/run/run.sh:1 | codebase-derived | fact |
| D-3 | The correctness block | Unchanged at all three sites. Its note-only sentence stays, and the selftest keeps asserting it. run: `git grep -c "test-coverage or repo-convention problem is a" origin/main` → review/SKILL.md:1, run/run-selftest.sh:1, run/run.sh:1, arms/lane-review.md:1 | codebase-derived | fact |
| D-4 | The bench arm | Untouched. It carries only the `review-correctness` block, so the completeness change never reaches it. run: `grep "LOCKSTEP-BEGIN" plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md` → one line, review-correctness | codebase-derived | fact |
| D-5 | The selftest assertion | run-selftest.sh case (a) matches the completeness sentence whole-line with grep -qxF. The build replaces that one literal with D-1's text. run: `grep -n "grep -qxF 'Review the diff for completeness" plugins/dev-pipeline/skills/run/run-selftest.sh` → line 35 | codebase-derived | fact |

Options weighed:
- D-1: "so it can be a `[blocker]`" or "and is a `[blocker]` unless exempt". The operator chose "can be". It is the ticket's form and the form of row D-1 in docs/plans/second-shift-1106-decisions.md. The scheduler's plan-coverage check already reds an AC with no test task before review, so the residual case is a named test that does not prove its AC.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2

AC-1: the recorded review prompt carries D-1's sentence whole-line and still carries the correctness block's note-only sentence
AC-2: run-selftest.sh case (a) is red against the unamended review prompt and green with the amendment

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The review session's prompt, completeness block | decided (D-1) |
| S-2 | The review skill's step 6 completeness block | decided (D-2) |
| S-3 | The bench arm's lane-review prompt | out-of-scope — it has no ticket and no ACs, so its prompt stays byte-identical. |
| S-4 | The run selftest's case (a) assertion | decided (D-5) |

## Checks

- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: implementable, with two warnings on the sentence's exact text and strength. The interview resolved both as D-1.

Split: not triggered. One deliverable, no epic label, one material decision.

Explore: done. Read both lockstep sites, the correctness block, the decisions doc, the run selftest's case (a), the bench arm and the lockstep checker, all at origin/main.

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
