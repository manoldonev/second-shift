# Intake receipt — #991 a review verdict binds only when its own comment backs it

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What `## Decision record rows` may hold besides the table | The table only: the heading, the `\| Row \| Score \| Evidence \|` table and blank lines. Any other line in the section fails the grammar. Prose that sits there today (the record-baseline paragraph, the "acceptance criterion is met" line) moves to `## Notes`, and per-row detail stays in the Evidence cell. Both #983 verdicts carry prose before and after the table, so their fixtures fail on this rule too. Weighed: free prose around the table, ignored by the checker (lenient, but the checker would then have to pick which table is the record table) | user-answered | intent |
| D-2 | Does the lane's review session check its own draft before posting? | Yes. `review_allowlist` adds `Bash(bash *verdict-check.sh*)`, and `review_prompt` tells the session to run the checker on its draft with the two record files and fix the draft until it exits 0, as `review/SKILL.md` step 8 does. The scheduler still runs the checker on the posted body after `verdict()` binds, and that check is the one that decides, since a session checking its own work proves nothing. This keeps the one re-spawn for real misses instead of format slips. Weighed: scheduler check only, as the ticket states it | user-answered | intent |
| D-3 | Does the checker cross-check a row's score against the record diff (`departed` on an edited or added row, `honored` on an unchanged one)? | Out of scope. The checker enforces only the ticket's item-3 rules. How an added row is scored (#983 round 2 scored the added D-8 `honored`) is an open baseline question that this ticket does not settle | user-answered | intent |
| D-4 | How the translation rule treats #990's `unrecorded` finding kind | #991 names only review-lead's Critical and Warning, so it references no token that nothing emits yet. Intake posts a comment on #990 saying that when #990 lands, it adds `unrecorded → [blocker]` to both grammar sites (`run.sh`'s review prompt and `review/SKILL.md`). If #990 has already merged when #991 builds, #991's build adds that line itself. Posted: https://github.com/manoldonev/second-shift/issues/990#issuecomment-6110745607 | user-answered | intent |
| D-5 | Exit code for `verdict-uncheckable` | 1 (stopped for a human), through `exit_code_for`'s default arm, with no new case. It is not an `env-*` slug, because the checker failing to evaluate is the run's own predicate failing, not the environment. The slug joins the exit-1 list in the header table and gets a row in README's terminal table beside `review-unbound` — run: `grep -n '\*) echo 1' plugins/dev-pipeline/skills/run/run.sh` → `114:    *) echo 1 ;;` | codebase-derived | fact |
| D-6 | Which record lines count as `D-n` rows for "every row is scored" | Only unindented lines matching `^\| D-[0-9]+ \|`. A receipt's `## Fan-out` embeds its snapshot register indented four spaces, and those rows are not the record's — run: `grep -l '^    \| D-' docs/plans/*-decisions.md \| wc -l` → 11 (of 26 records with `^\| D-` rows) | codebase-derived | fact |
| D-7 | Source of the AC-1 fixtures | PR #983's verdicts as posted: comment 6107830040 (needs-work, head `1be8b826`) and comment 6108061297 (approve, head `c9ff84e4`). The record `docs/plans/second-shift-979-decisions.md` is read at first commit `7100d01b` and at each head — run: `git cat-file -e 7100d01b:docs/plans/second-shift-979-decisions.md` → rc 0, and the same for heads 1be8b826 and c9ff84e4 | codebase-derived | fact |
| D-8 | Duplicate scan | No candidates — run: `dup-scan.sh --issue 991` → rc=0, no candidates at or above threshold 12 | codebase-derived | fact |
| D-9 | The verdict grammar, checker rules and exit codes, the lane and manual paths, `post-review-status.sh`, the translation rule, the `run.sh:51` amendment, and the verb and trailer | As the ticket body states them, items 1–6 and AC-1 to AC-4: https://github.com/manoldonev/second-shift/issues/991 | ticket-sourced | fact |
| D-10 | Where the lane runs the checker relative to the head-moved check | After it, still before `review_status`. A verdict voided by a moved head already binds nothing and re-runs the checks, so checking its body would only post a notice about a verdict nobody can use. Reason: one miss per review, the one that decides what happens next | user-delegated | intent |
| D-11 | Where the lane reads `reason: render-unavailable` | Line 3 only, in `run.sh` as in the checker; it read any line before. Under the grammar the same words in `## Notes` are prose, and a needs-work whose Notes quote them must not end the run `env-not-ready`. Reason: the grammar places the reason on line 3, and two readers of one body must agree on it | user-delegated | intent |
| D-12 | What a render-unavailable needs-work must still carry | The whole grammar: both required sections, a table that may hold no rows, and `## Findings` that may be `None.`. "Passes on that line alone" is read as the needs-work rule and the every-row rule, not the section grammar. Reason: "in this order and nothing else" admits no exception, and one shape for every verdict keeps one reader | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The exact text of each failed-rule message the checker prints, other than the two AC-1 names ("needs-work with no blocker", "Findings not in the grammar") | reversible-default-and-flag |

OR-1: the build picks one short, stable phrase per rule and lists them all in the PR description. Renaming a phrase later changes only the checker and its selftest, since nothing else parses them: the re-spawn prompt and the notice comment carry them as text.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The verdict comment body, on both the lane and manual paths | decided (D-1) |
| S-2 | The lane review session's own pre-post check | decided (D-2) |
| S-3 | The lane's plain notice comment that links a rejected verdict and names its failed rules | decided (D-9) |
| S-4 | The re-spawn prompt carrying the failed rules | decided (D-9) |
| S-5 | The `second-shift/review` commit status, posted only on a passing body | decided (D-9) |
| S-6 | The manual session's plain PR comment when `post-review-status.sh` refuses | decided (D-9) |
| S-7 | The `terminal: verdict-uncheckable` line, the header exit table and README's terminal table | decided (D-5) |
| S-8 | The checker's stdout listing every failed rule | decided (OR-1 default, rules per D-9) |
| S-9 | Standalone `/review-lead` and `reviewer-baseline` output | out-of-scope — the ticket keeps their vocabulary |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
