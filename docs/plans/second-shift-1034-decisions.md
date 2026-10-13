# Intake receipt — #1034 Performance review misses cost a new entry point pulls from unchanged code, even when the record names it

Receipt: v2

## Intake steps

Requirements: written ticket — spec-reviewer: needs-revision, 0 blockers, 6 warnings: W1 (no AC block) closed by the operator's AC-1..7 rewrite of the body; W2-W6 resolved as D-2, D-6, D-3, S-8/D-14, D-5/D-16; implementability probe: 11 guess-points, 10 already answered by the record or resolved from code (D-9, D-14, D-15), G-4 asked as D-17
Split: not triggered — one deliverable (the performance seat's selection, its lens and the record's risk rows, all in the review path)
Explore: done — review-lead Reviewer Routing, the pipeline default panel and its opt-in carriers, lead-pass-checklist (out-of-diff reads, New vs pre-existing, Critical trigger, Performance), review/SKILL.md steps 5-6, run.sh's review prompt (:657) and run-selftest's prompt asserts, performance-reviewer.md, code-review.mjs BOUNDED_EXPLORATION and seat prompts, check-emit-deadline.sh, security-reviewer.md, intake interview.md, #993 and #994
Fan-out: skipped — by the operator at the pre-flight notice: no reason given
Dup-scan: no candidates at or above threshold 12
Post-merge scan: none — the ticket carries no AC block, so there is no AC to move
Sizing: opus

## Decision Ledger

Where a row below differs from the ticket body's Proposal, the row is binding.

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Relation to #993 | Standalone, and it lands first, on today's routing. #993 (open, unclaimed, second of four with #994 and #995 behind it) edits the same routing text and inherits this when it is built; its `candidates:` line already lists performance. | user-answered | intent |
| D-2 | How the performance seat gets selected in the lane | `performance` becomes a fourth opt-in short name in all three carriers of the pipeline default panel (the `review panel` ledger row, `reviewers.default[]`, and the caller's per-round judgment), with an introduced-surface clause: a new entry point (route, handler, consumer, SDK method) that reaches a data read or existing heavy work. Plus a record arm: a record row or `OR-n` naming a cost, load or performance risk makes performance a required seat decision, dispatched or declined with a reason that answers that row. Never all-seats. | user-answered | intent |
| D-3 | How a record row naming an unmeasured or inherited cost risk is scored | Applies to `D-n` rows (step 5 scores only those; an `OR-n` region feeds D-2's arm, not the table). Its score stays code-vs-row (the row is the operator's decision; a score never overrides it). Its named risk becomes required work for the performance dimension: the review states the worst-case bound as a finding, at the severity the performance rules give it, and the row counts as a named risk that licenses the out-of-diff reads that check it (the named-risk list in `lead-pass-checklist.md`, "How to run the pass"). Supersedes the ticket's "honored only when the review names the bound". | user-answered | intent |
| D-4 | Intake-side carrier | When a row or `OR-n` records a deferred, unmeasured or inherited risk in a specialist's dimension (performance, security, a11y, unit-test-mutation), the interview asks the operator whether to add a `review panel` row naming that seat. The existing carrier then selects it mechanically; D-2's record arm stays as the backstop. | user-answered | intent |
| D-5 | The new performance rule and its severity | "Amplification through a new entry point", stack-agnostic: the cost is the worst request the validation admits times the cost of the unchanged code it reaches. It asks whether the work is bounded before any output exists, whether a runaway guard exists (timeout, query time limit, throttle), whether caller retries multiply it, and whether it runs on shared capacity. Severity uses the existing two-condition Critical trigger, clarified: a new entry point onto an inherited expensive path meets condition 1 (new exposure, not inherited); condition 2 holds when a shipped caller can send the worst admitted request today; otherwise Warning, which the reviewer may hold the merge for (`review/SKILL.md` step 8 grammar). "New vs pre-existing" gains the same reading: new callers or new capacity on an expensive path are new, not `[Pre-existing]`. | user-answered | intent |
| D-6 | How a dispatched performance seat reaches unchanged code | The caller passes each record risk row and the new entry point's `path:line` in `prContext`, so under `BOUNDED_EXPLORATION` the trace grounds a specific finding instead of proving a negative. The turn cap stays 15 and the agent's turn-10 partial-result rule names any untraced path. No `code-review.mjs` change. Supersedes the ticket's turn-budget bullet (a cap raise alone was measured useless, `check-emit-deadline.sh:12-21`). | user-answered | intent |
| D-7 | Proof before shipping | No before/after replay. The change ships on the run-selftest case (D-9) and the existing lints; #993's planted-defect run measures it later. | user-answered | intent |
| D-8 | Security seat coverage of availability/DoS | Unchanged. Runaway work, missing guards and retry amplification live in D-5's performance rule; `security-reviewer.md` keeps its brief. One owner per concern. | user-answered | intent |
| D-9 | run.sh's review prompt and its test | The review prompt mirrors `review/SKILL.md` steps 5 and 6 (run.sh:655 scoring, :657 opt-ins) and changes with D-2 and D-3; a behavior change to `run.sh` lands with a `run-selftest.sh` case that fails without it — run: `grep -c "naming security, a11y or unit-test-mutation" plugins/dev-pipeline/skills/run/run.sh` → 1; cited (convention): CLAUDE.md:119 | codebase-derived | fact |
| D-10 | Where the performance rule text lives | Both `lead-pass-checklist.md` § Performance and `agents/performance-reviewer.md`: the checklist is folded from the agent contracts, which still ship and are dispatchable, and its rules are stack-agnostic — cited (convention): plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md:7 | codebase-derived | fact |
| D-11 | Whether a script parses the opt-in names | None does: selection is read in-session by review-lead, so the opt-in change is prose; `reviewers.default[]` already accepts `performance-reviewer` because it is validated against the shipped registry — run: `grep -rln --include='*.sh' --include='*.mjs' "review panel" plugins scripts tools \| grep -v selftest` → plugins/dev-pipeline/skills/run/run.sh (the prompt echo only) | codebase-derived | fact |
| D-12 | Carrier for the named risk to the seat | `prContext` is free text review-lead fills from the PR context it has; adding the record's risk rows to it changes no script contract — run: `grep -n "any PR context the user provided" plugins/review-toolkit/skills/review-lead/SKILL.md` → 372 | codebase-derived | fact |
| D-13 | Where the intake-side ask (D-4) is written | `plan-interview/SKILL.md`: `/intake`'s Interview stage runs plan-interview's protocol, steps 2 to 5 — run: `grep -n "plan-interview" plugins/intake-toolkit/skills/intake/interview.md` → 10: The interview itself is `plan-interview`'s protocol, steps 2 to 5 | codebase-derived | fact |
| D-14 | Where D-5's "new, not pre-existing" reading lands | In both copies of the carve-out: `lead-pass-checklist.md` "New vs pre-existing" and `reviewer-baseline` Finding Classification, which dispatched seats load; scoped to cost — run: `grep -n "first code to depend" plugins/review-toolkit/skills/reviewer-baseline/SKILL.md plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md` → reviewer-baseline/SKILL.md:72, lead-pass-checklist.md:58 | codebase-derived | fact |
| D-15 | Verdicts row for a dispatched performance seat | Mirrors security's dual rendering: `Pass / Fail` when dispatched, `Lead pass — ✅/❌` when not — run: `grep -n "Security takes the same rendering" plugins/review-toolkit/skills/review-lead/SKILL.md` → 642 | codebase-derived | fact |
| D-16 | Exemptions from D-5's rule | None: no internal-worker or internal-route exemption; review-context may calibrate thresholds, not switch it off | user-answered | intent |
| D-17 | Cost of an unmade performance decision | On D-2's record arm, a record-named risk with neither a dispatch nor a decline is a process `[blocker]`; the review session judges whether a decline answers the row. The diff-surface arm keeps today's rule (recorded on the panel line, never a blocker, `review-lead/SKILL.md:272-274`) | user-answered | intent |
| D-18 | The ticket body | Proposal replaced by AC-1..7 aligned to this record, plus an Out of scope list; Problem and Why kept | user-answered | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The exact wording of D-2's introduced-surface clause and D-2's record arm ("names a cost, load or performance risk") | reversible-default-and-flag |

OR-1: the default is the D-2 text, applied by model judgment the way the security trigger is. Reversing it is cheap: it is prose in three places (review-lead, review/SKILL.md step 6, run.sh's prompt) and no script parses it (D-11).

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The verdict comment's `## Panel` line: performance dispatched or declined, each with a reason | decided (D-2) |
| S-2 | The record-row scores for a row naming a cost risk | decided (D-3) |
| S-3 | The amplification finding: its text, worst-case bound and severity | decided (D-5) |
| S-4 | The intake interview's question asking for a `review panel` row | decided (D-4) |
| S-5 | The lane review prompt run.sh hands the review session | decided (D-9) |
| S-6 | What a dispatched performance seat is told about the named risk | decided (D-6) |
| S-7 | security-reviewer's brief | decided (D-8) |
| S-8 | Standalone `/review-lead` routing with no pipeline panel declared | out-of-scope — the opt-in carriers are read only under the pipeline default panel; the standalone table and its lead pass are unchanged except for D-5's rule text |
| S-9 | A planted case in #993's measurement | out-of-scope — #993 is unbuilt and owns its corpus; no replay here (D-7) |
| S-10 | A consumer's `review-context/performance-reviewer.md` calibration | out-of-scope — additive per-repo context, unchanged |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
