# Decision record — #1191 review: 'a decision is not a need' did not hold on its first real run — blind arm ignored or inverted it, lead pass demoted findings to prose

Receipt: v4

## Summary

A structure that a ticket's scope or prose prescribes stops counting as a requirement on every review surface. Over-engineering is raised as a finding, never carried only in prose. The change touches the plain-review prompt, review-lead's report and lead-pass checklist, the lane review's lockstep blocks and scope-completeness-reviewer. Acceptance criteria stay binding.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Intake route for the thin ticket | Feature mode. The ticket needs scoreable acceptance criteria, and the failing run is a consumer run with no local reproduction. | user-answered | intent |
| D-2 | Which of the ticket's directions are in scope | The plain review and the lead pass are in. A before/after replay is not part of the ticket. A planted eval class is not filed. The spec-review direction is out. | user-answered | intent |
| D-3 | Whether the lane verdict gets the findings-not-prose rule | Yes. The lane verdict's `## Summary` and `## Notes` carry no over-engineering observation that its findings list does not. | user-answered | intent |
| D-4 | What the plain review counts as a ticket requirement | An outcome, a behavior, an acceptance criterion or an external surface the ticket states. An internal structure its scope or prose prescribes is not one. Its absence gets no finding. | user-answered | intent |
| D-5 | Where review-lead's report may carry over-engineering | Only as a finding in Critical, Warnings or Suggestions, or in Suppressed on confidence alone. Summary, Strengths, Reasoning and Plan Compliance carry none the findings do not. "The ticket prescribed it" or "a style trade-off" never moves a finding out or down. | user-answered | intent |
| D-6 | Whether scope-completeness-reviewer's step 2b gets the rule | Yes. A structure the ticket's scope or prose prescribes is no scope item. Step 3b's record-row scoring is unchanged. | user-answered | intent |
| D-7 | Test intent for the acceptance criteria | AC-1 to AC-6 are exempt, because they change prompt prose and the repo forbids prose-presence guards. AC-7 holds through the existing selftests. | user-answered | intent |
| D-8 | A structure an acceptance criterion prescribes | Acceptance criteria stay binding on every surface, so its absence is still a finding. The over-engineering finding still fires. Challenging a structural AC belongs to intake's spec-reviewer. | user-answered | intent |
| D-9 | The external-surface definition | One definition everywhere, taken from complexity-reviewer.md:29. It is something a party outside the diff's own code reads or calls: a config key, an entry point or command, an API, a stored or on-disk format. No named caller is required. This replaces the named-caller tie-break the interview first chose. | user-answered | intent |
| D-10 | The plain review's blocker definition at plain-review.md:39 | It reads "does not meet a requirement the ticket states", so it inherits the line-30 definition. It stays in place, and with no ticket it has no requirement to apply. | user-answered | intent |
| D-11 | The lead-pass gates on over-engineering | An over-engineering finding meets the Pre-Emit Gate's "Concrete today?" by its cited callers, or by showing there are none. The Complexity section says a plan the ticket prescribes is not a need. A repo-declared Intentional complexity exemption stays legitimate. | user-answered | intent |
| D-12 | review-lead's Plan Compliance section | "Missing" uses D-4's definition of a requirement. Over-engineering listed under "Extra" is also a finding row. | user-answered | intent |
| D-13 | The folded `dev: lane vs blind` block | It is exempt from D-3 and D-5. verdict-join.sh keeps taking only the plain review's blockers into the body. | user-answered | intent |
| D-14 | Whether the lane's `review-correctness` block carries D-4 | Yes, in every copy. A structure the ticket only prescribes is never a completeness `[blocker]` there. | user-answered | intent |
| D-15 | Plan Compliance and Plan/Spec Awareness on a plan file | The same rule applies. A plan task that only prescribes internal structure is not missing when the outcomes are met. SKILL.md's Plan/Spec Awareness gets the same wording. | user-answered | intent |
| D-16 | A scope bullet that reads as both an outcome and a structure | It counts as structure, so scope-completeness does not list it as a scope item. The "when in doubt" calibration follows this. | user-answered | intent |
| D-17 | Whether scope-completeness reports an excluded structure | Yes. Each exclusion is listed in the seat's Notes as `not a scope item: an internal structure the scope prescribes — <bullet>`. | user-answered | intent |
| D-18 | How the no-ticket drop works | It drops one body line by its prefix, plus the blank line after it. D-4's text stays on that one physical line, and the prefix stays unchanged. run: `grep -c '^ticket-only: Also flag a requirement the ticket states$' plugins/dev-pipeline/skills/run/plain-review.md` → 1 | codebase-derived | fact |
| D-19 | The lockstep copies the build edits | `review-correctness` has three copies: review/SKILL.md, run.sh and the eval arm lane-review.md. `verdict-grammar` has two copies. check-lockstep-pairs.sh compares them in CI. run: `grep -rl 'LOCKSTEP-BEGIN verdict-grammar' plugins scripts tools \| wc -l` → 2 | codebase-derived | fact |
| D-20 | Whether the run.sh edit needs a run-selftest case | No. The rule covers a new terminal, refusal or outward write. Prompt text in a lockstep block is held by byte parity. cited (convention): docs/testing.md:323 | codebase-derived | fact |
| D-21 | The plain review's existing over-engineering clause | It already says a ticket that prescribes the structure is not a need, and to quote that line. It needs no new text for that. run: `grep -c 'a ticket that prescribes the structure is not a need for it' plugins/dev-pipeline/skills/run/plain-review.md` → 1 | codebase-derived | fact |
| D-22 | review-lead's severity tiers for over-engineering | They stay unchanged. The two-condition Critical trigger already caps a finding with no failure today at Warning. cited (convention): plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md:145 | codebase-derived | fact |
| D-23 | Whether the lane review runs review-lead | No. The lane review is its own session, and review/SKILL.md never names review-lead. run: `grep -c 'review-lead' plugins/dev-pipeline/skills/review/SKILL.md` → 0 | codebase-derived | fact |
| D-24 | Duplicated lines outside any lockstep marker | run.sh:1132 and :1152 repeat review/SKILL.md:83-85 and :179-180 with no marker. An edit to one of these lines lands in both copies by hand. run: `grep -c 'LOCKSTEP-BEGIN' plugins/dev-pipeline/skills/run/run.sh` → 6 | codebase-derived | fact |

Options weighed:
- D-1: feature mode or bug mode. The operator chose feature mode.
- D-2: prompt changes with a replay, with a planted class, or without a replay. The operator chose no replay.
- D-8: structural ACs stay binding, or extend the rule to ACs. The operator chose binding.
- D-9: the complexity-reviewer definition, or the named-caller tie-break. The operator chose the complexity-reviewer definition.
- D-10: reword line 39, or leave it. The operator chose to reword it.
- D-11: widen the gates, or fix only checklist :393. The operator chose to widen them.
- D-13: exempt the comparison block, or merge blind notes into the body. The operator chose the exemption.
- D-15: the same rule for plans, ticket requirements only, or today's rule. The operator chose the same rule.
- D-16: doubt makes it a structure, or a scope item. The operator chose structure.
- D-17: list the exclusion in Notes, or drop it silently. The operator chose Notes.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7

AC-1: exempt — prompt prose in plain-review.md; the repo forbids prose-presence guards
AC-2: exempt — prompt prose in plain-review.md and the review-correctness lockstep copies; check-lockstep-pairs.sh guards parity
AC-3: exempt — prompt prose in review-lead's SKILL.md; no test can prove it
AC-4: exempt — prompt prose in lead-pass-checklist.md; no test can prove it
AC-5: exempt — prompt prose in the verdict-grammar lockstep copies; check-lockstep-pairs.sh guards parity
AC-6: exempt — prompt prose in scope-completeness-reviewer.md; no test can prove it
AC-7: holds — with no ticket, the plain-review prompt still drops the ticket-requirement line by its prefix (plain-review-selftest.sh, run-joined-selftest.sh, planted/render-selftest.sh)

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The plain review's findings with a ticket | decided (D-4) |
| S-2 | The plain review's prompt with no ticket | decided (D-18) |
| S-3 | review-lead's finding sections | decided (D-5) |
| S-4 | review-lead's Summary, Strengths and Reasoning | decided (D-5) |
| S-5 | review-lead's Plan Compliance section | decided (D-12) |
| S-6 | The lane verdict's Summary and Notes | decided (D-3) |
| S-7 | The folded lane vs blind comparison block | decided (D-13) |
| S-8 | scope-completeness-reviewer's scope items and Notes | decided (D-17) |
| S-9 | The lane verdict's decision-record rows table | out-of-scope — step 3b row scoring does not change. |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Intake steps

Requirements: interviewed (feature) on a thin ticket. The body was written into #1191 on the operator's yes. spec-reviewer: needs work, and its fixes were folded in.

Split: not split. The Interview returned it at about 10 decisions. It is a bug fix in one rule's carriers, so Split does not decompose it.

Explore: done. Read plain-review.md and its no-ticket drop, review-lead's report and checklist, the lane verdict blocks, scope-completeness-reviewer and verdict-join.sh.

Fan-out: ran — 24 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. Every AC is checkable from the diff.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: failure-trace opus 5/6 · requirement-boundary fable 3/6 · cross-surface-consistency opus 6/6 · harness-and-join-mechanics fable 5/6 · premortem fable 5/6
Tally: rows added 6 · snapshot claims overturned 2 · questions added 4

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | failure-trace | The blocker definition at `plain-review.md:39` is a second route to the absent-structure blocker. | new | became D-10 |
| F-2 | failure-trace | Checklist :393 makes a ticket-stated plan a need, and Plan Compliance is a prose outlet (`lead-pass-checklist.md:393`). | new | became D-11 and D-12 |
| F-3 | failure-trace | Do-not-flag exemptions can absorb over-engineering (`lead-pass-checklist.md:379`, :387, :429). | new | not material — D-5 forbids moving a finding out; D-11 keeps repo exemptions |
| F-4 | failure-trace | The Pre-Emit Gate's "Concrete today?" drops every over-engineering finding (`lead-pass-checklist.md:166`). | new | became D-11 |
| F-5 | failure-trace | The no-ticket drop removes only the prefixed line 30 (`plain-review.sh:87`). | already-had | became D-18 |
| F-6 | requirement-boundary | Text outside line 30 survives a no-ticket run (`plain-review.md:32`). | already-had | became D-18 |
| F-7 | requirement-boundary | A file format other plugin versions read falls between the definitions (`bot-commit.sh:16`). | new | became D-9 |
| F-8 | requirement-boundary | Plan Compliance and the Reasoning line are prose slots AC-2 missed (`review-lead/SKILL.md:731`, :769). | new | became D-5 and D-12 |
| F-9 | cross-surface-consistency | `review-correctness` has a third copy in the eval arm (`arms/lane-review.md:13`). | overturned (snapshot: "Edited with review/SKILL.md" in two copies) | became D-19 |
| F-10 | cross-surface-consistency | Two duplicated run.sh lines sit outside any lockstep marker (`run.sh:1132`, :1152). | new | became D-24 |
| F-11 | cross-surface-consistency | verdict-join.sh parks every plain-only note in the folded block (`verdict-join.sh:12`). | already-had | became D-13 |
| F-12 | cross-surface-consistency | Plan/Spec Awareness scores an absent plan task as missing (`review-lead/SKILL.md:163`). | new | became D-12 and D-15 |
| F-13 | cross-surface-consistency | A config key the ticket asks for is a need in complexity-reviewer but not under the tie-break (`complexity-reviewer.md:29`). | overturned (snapshot: "a scope item only when the ticket names a caller outside the checkout") | became D-9 |
| F-14 | cross-surface-consistency | Line 39 and the "when in doubt, FAIL" calibration still push toward failing a structure (`scope-completeness-reviewer.md:183`). | new | became D-10 and D-16 |
| F-15 | harness-and-join-mechanics | The `ticket-only:` drop is a single physical line prefix match (`plain-review.sh:82`). | already-had | became D-18 |
| F-16 | harness-and-join-mechanics | Line 32's ticket wording stays in the no-ticket prompt (`plain-review.md:32`). | already-had | became D-18 |
| F-17 | harness-and-join-mechanics | verdict-check.sh treats `## Notes` as prose (`verdict-check.sh:150`). | not material | not material — confirms D-3; no format changes |
| F-18 | harness-and-join-mechanics | The join enrols findings only from the finding sections (`verdict-join.sh:199`). | new | not material — evidence for D-5 |
| F-19 | harness-and-join-mechanics | Three `review-correctness` copies; a stale local worktree reds the checker (`check-lockstep-pairs.sh:113`). | overturned (snapshot: "Edited with review/SKILL.md" in two copies) | became D-19 |
| F-20 | premortem | The join breaks AC-3's wording unless the block is exempt (`verdict-join.sh:187`). | already-had | became D-13 |
| F-21 | premortem | A wrapped second line of AC-1's text survives as an orphan (`plain-review.sh:87`). | already-had | became D-18 |
| F-22 | premortem | Line 39 can still rate an absent structure a blocker (`plain-review.md:39`). | new | became D-10 |
| F-23 | premortem | Plan Compliance's Missing and Extra re-score or absorb the prescription (`review-lead/SKILL.md:731`). | new | became D-12 |
| F-24 | premortem | The checklist re-wording ships with no measured evidence (`lead-pass-checklist.md:415`). | not material | not material — the operator declined a replay in D-2 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Intake route | Feature mode (operator). |
    | D-2 | Scope | Plain-review requirement line; review-lead report + lead-pass checklist; lane verdict Summary/Notes (+ run.sh lockstep copies); scope-completeness step 2b. No replay, no planted case, spec-reviewer out. |
    | D-3 | Structural AC | ACs stay binding everywhere; only scope/prose prescriptions stop being requirements. |
    | D-4 | External-surface tie-break | A scope item only when the ticket names a caller outside the checkout. |
    | D-5 | Test intent | AC-1..AC-4 exempt (prompt prose); AC-5 holds via plain-review-selftest.sh and run-joined-selftest.sh. |
    | D-6 | ticket-only drop | Per-line by prefix; the new sentence goes on line 30, prefix unchanged. |
    | D-7 | run.sh lockstep copies | Edited with review/SKILL.md; check-lockstep-pairs.sh guards; no run-selftest case (prompt text is not a run.sh behavior change). |
    | D-8 | Lane review and review-lead | The lane review does not run review-lead; grep count 0. |
    | D-9 | AC-2 of the first draft | Retired: plain-review.md:32 already says it. |
    | D-10 | Joined lane-vs-blind block under ## Notes | Unexamined: holds plain-only findings verbatim; open whether AC-3 exempts it. |

</details>
