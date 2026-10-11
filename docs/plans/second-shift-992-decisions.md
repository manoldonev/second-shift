# Intake receipt — #992 The review fan-out takes required seats and has Fable refute their findings

Engineer-logged ticket; plan-interview pre-flight. Design handoff: none (workflow-script, agent-doc and guard-script work; no UI surface).

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Refuter agent | A new review-toolkit agent `finding-refuter` (frontmatter `fable`, table tier `cross`, a row in REVIEWER_MODEL). Its verdict is three-valued: `reproduced` / `refuted` (evidence required) / `unverified` (it could not re-derive the finding). "Could not confirm" is `unverified`, never `refuted`. `intake-refuter` and intake-fanout.mjs stay untouched (they are the measured #916 arm) | user-answered | intent |
| D-2 | A refuter that is dark, returns unparseable text, or is still pending at the refute ceiling | Outcome `unverified`; the finding stands (fail closed). Do NOT port refuteOne's `v.result ? v.result.refuted : true`, which fails open | user-answered | intent |
| D-3 | Authority for the substantial tier table | A parsed `## Substantial panel` table in model-tiering.md, on the same pattern as the tier alphabet / TIER-MAP-DRIFT. `SUBSTANTIAL_MODEL` in code-review.mjs is excluded from the whole-file frontmatter pair scan and held against that doc table instead. check-model-tiers-selftest gets a drift case where a substantial row drops to `code`, which the current comparison would pass silently | user-answered | intent |
| D-4 | What trips the Fable-unavailable fallback | Only a thrown dispatch error that is not a budget exhaustion counts toward the two-failure trip. Empty or unparseable refuter text makes that refuter `unverified` and is not counted. One retry per refuter, re-picked through `live()`, so a tripped run retries on Opus. Outcomes then record `same-family (fable unavailable)`; otherwise the family is computed against madeBy | user-answered | intent |
| D-5 | Consumer `reviewers.modelOverrides` vs the substantial tier | The override wins (repo-wide precedence override > table). SUBSTANTIAL_MODEL replaces REVIEWER_MODEL only at the table layer. `seats[].model` records the model the seat actually dispatched on | user-answered | intent |
| D-6 | Ceilings on the substantial path | Seats keep today's 15-min `REVIEWER_CEILING_MS` (a ceiling only guards against wedges: agent() cannot abort, so a tighter one turns slow-but-healthy Opus seats dark and saves nothing on healthy runs). The refute phase gets its own 3-min ceiling (≈4× the slowest refuter observed in the intake run, 11–45 s); any refuter still pending is `unverified`. No args seam: both are constants. DEPARTS from ticket item 6's 7-min seat ceiling, by the operator | user-answered | intent |
| D-7 | Mutation-seat majors in the Refute phase | Excluded, like scope-completeness: unit-test-mutation-reviewer findings are LLM predictions with no executor, and its rule is that an unverified mutant never blocks. Its majors pass through marked `unrefuted`. DEPARTS from ticket item 3's "every blocker or major", by the operator | user-answered | intent |
| D-8 | Return shape | On `panel: 'substantial'` and in refute-only mode, `seats[]` REPLACES `reviewers[]`: one entry per seat `{agentType, model, status: returned\|dark, findings, reproduced, refuted, unverified}`. The three outcome fields are counts; each finding carries `outcome` and `family` in place. A no-panel call returns exactly `{range, worktree, reviewers}` as today (AC-4). review-lead cannot read substantial-path output until #993 teaches it | user-answered | intent |
| D-9 | Producer of a refute-only finding | Each refute element may carry an optional `madeBy` (a model token). The refuter dispatches on `other(madeBy)` and family is computed as intake-fanout computes it. With madeBy absent: refute on `cross` and record family `cross (producer unstated)`. The seat path sets madeBy to the seat's dispatched model | user-answered | intent |
| D-10 | Non-empty-reviewers guard | Relaxed only when `refute` is present (refute-only, empty array included) or `requiredSeats` is non-empty; a call with neither still throws, so standalone review-lead's "rejects an empty reviewers[]" text (SKILL.md:119,383) stays true and is left for #993 — run: `grep -n "non-empty array" plugins/review-toolkit/workflows/code-review.mjs` → 177 | codebase-derived | fact |
| D-11 | FINDINGS_SCHEMA | Unchanged. outcome/family/madeBy ride its `additionalProperties: true`, so the LOCKSTEP copies in stall-probe.mjs / tool-discipline-probe.mjs need no edit — run: `sed -n 106,135p plugins/review-toolkit/workflows/code-review.mjs \| grep -c "additionalProperties: true"` → 2 | codebase-derived | fact |
| D-12 | Emit deadline enrolment | performance- and complexity-reviewer get maintainability-reviewer.md:170's turn-10-of-15 line; both are added to DEADLINE_AT_DEFAULT. The WHY-ONLY-THIS-ONE comment AND the FAIL text ("its dispatch site appends no bounding nudge", false for these two, which get BOUNDED_EXPLORATION) are amended. The selftest's B13 liveness loop grows to cover both — run: `grep -n "dispatch site appends no bounding nudge" plugins/review-toolkit/scripts/check-emit-deadline.sh` → 344 | codebase-derived | fact |
| D-13 | Budget-exhausted return on the substantial path | Parked under OR-1 | deferred | open |
| D-14 | Dedupe of reviewers ∪ requiredSeats | Parked under OR-2 | deferred | open |
| D-15 | model-tiering.md's "code-review.mjs … do not yet" sentence | Updated: code-review.mjs's refute path now degrades as intake-fanout does; the Substantial panel table lands beside the alphabet (D-3) — run: `grep -n "do not$" plugins/review-toolkit/model-tiering.md` → 46 | codebase-derived | fact |
| D-16 | Shipped tier/deadline tables are linted only by the commit hook, not CI | This receipt's Checks run both guards against the shipped files; wiring them into CI is out of scope (named to the operator) — run: `grep -rln "check-emit-deadline.sh\|check-model-tiers.sh" .github/` → no output | codebase-derived | fact |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Budget-exhausted return on the substantial path: `seats[]` lists every requested seat (reviewers ∪ requiredSeats) as `status: dark`, plus `budgetExhausted: true` | reversible-default-and-flag |
| OR-2 | `reviewers ∪ requiredSeats` deduped on the resolved (qualified) name, so a bare and a qualified spelling dispatch once | reversible-default-and-flag |

Both defaults are cheap to reverse. They touch only the substantial-path return, which no caller reads until #993/#994. Each follows from D-8's one-entry-per-seat shape, and the build flags each in the PR body.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | code-review.mjs return on `panel: 'substantial'` | decided (D-8) |
| S-2 | Refute-only return, including the empty array | decided (D-8) |
| S-3 | No-panel return and dispatch (AC-4) | decided (D-8) |
| S-4 | Per-finding outcome and family record | decided (D-2) |
| S-5 | Family when Fable is unavailable or the producer is unstated | decided (D-9) |
| S-6 | Budget-exhausted substantial return | decided (D-13) |
| S-7 | check-model-tiers.sh drift error for the substantial table | decided (D-3) |
| S-8 | check-emit-deadline.sh FAIL text and enrolment | decided (D-12) |
| S-9 | model-tiering.md fallback and substantial-panel prose | decided (D-15) |
| S-10 | Workflow phase list in /workflows (a `Refute` phase in meta) | out-of-scope — meta is a static literal (Case R), so the phase is listed on no-panel runs too; nothing a caller reads changes |
| S-11 | review-lead SKILL.md synthesis text | out-of-scope — #993 owns review-lead; the no-panel contract it describes is unchanged (D-10) |

## Checks

- `bash plugins/review-toolkit/scripts/check-model-tiers.sh`
- `bash plugins/review-toolkit/scripts/check-model-tiers-selftest.sh`
- `bash plugins/review-toolkit/scripts/check-emit-deadline.sh`
- `bash plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh`
- `node plugins/review-toolkit/workflows/runtime-shim-selftest.mjs`
- `node plugins/review-toolkit/workflows/null-reviewer-selftest.mjs`

## Design frames

Design: none — the change renders no screen; it is workflow-script, agent-doc and guard-script work.

## Fan-out

Refuter: same-family (fable unavailable) — Fable hit its account usage limit mid-run; every refuter ran on opus
Lenses: caller-contract opus 6/6 · wall-clock-budget opus 6/6 · refuter-reach opus 5/6 · guard-liveness opus 5/6 · premortem opus 4/6
Tally: rows added 4 · snapshot claims overturned 1 · questions added 3

Three lenses (wall-clock-budget, guard-liveness, premortem) failed their first dispatch on Fable ("You've reached your Fable limit") and completed on their opus retry.

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | caller-contract | The non-empty-reviewers guard rejects refute-only and requiredSeats-only calls (`code-review.mjs:176-178`) | already-had | became D-10 |
| F-2 | caller-contract | A SUBSTANTIAL table in REVIEWER_MODEL's shape turns check-model-tiers red with MISMATCH (`check-model-tiers.sh:487`) | already-had | became D-3 |
| F-3 | caller-contract | No dedupe on the reviewer union; a budget skip drops required seats from darkness accounting (`code-review.mjs:431-441,612`) | new | became D-13 and D-14 |
| F-4 | caller-contract | AC-4 cannot be file-identical: meta is static, so a Refute phase is listed on no-panel runs (`code-review.mjs:1-6`) | new | became S-10 |
| F-5 | caller-contract | outcome/family fit FINDINGS_SCHEMA's additionalProperties; editing the schema forces three LOCKSTEP copies (`code-review.mjs:109,120`) | new | became D-11 |
| F-6 | caller-contract | Refute-only findings carry no producer, so family cannot be computed (`intake-fanout.mjs:176-180`) | already-had | became D-9 |
| F-7 | wall-clock-budget | Concurrency waves break the 7+3 arithmetic (`code-review.mjs:612-613`) | new | became D-6 |
| F-8 | wall-clock-budget | A 7-min ceiling over both attempts starves the #855 escalated retry (`code-review.mjs:523-560`) | new | became D-6 |
| F-9 | wall-clock-budget | A verbatim port needs two slow Fable failures before falling back, missing a 3-min ceiling (`intake-fanout.mjs:82-85,147-163`) | overturned (snapshot: "port intake-fanout dispatch() verbatim") | became D-4 |
| F-10 | wall-clock-budget | A budget throw counts as a Fable failure and mislabels the run (`intake-fanout.mjs:125-139`) | overturned (snapshot: "port intake-fanout dispatch() verbatim") | became D-4 |
| F-11 | wall-clock-budget | refuteOne maps a dark refuter to refuted (`intake-fanout.mjs:178-181`) | new | became D-2 |
| F-12 | wall-clock-budget | Orphaned agents past a ceiling keep drawing on the shared budget (`code-review.mjs:414-416`) | new | became D-6 |
| F-13 | refuter-reach | A dark refuter drops the claim in intake-fanout; the ticket wants unverified (`intake-fanout.mjs:215-216`) | new | became D-2 |
| F-14 | refuter-reach | intake-refuter defaults to refuted, is boolean-only, and is intake-framed (`intake-refuter.md:19-31`) | already-had | became D-1 |
| F-15 | refuter-reach | Mutation majors are predictions; refuting them collides with never-block (`unit-test-mutation-reviewer.md:11,38,103-106`) | new | became D-7 |
| F-16 | refuter-reach | Verdicts bind to findings by array position; filter(Boolean) would shift them (`code-review.mjs:624`) | not material | not material — build-level care; AC-1's per-finding reproduced/refuted/unverified cases catch a misbinding |
| F-17 | refuter-reach | intake-fanout has no phase ceiling to port, only a whole-run race returning an empty pool (`intake-fanout.mjs:262-271`) | new | became D-6 |
| F-18 | guard-liveness | A substantial row drifting down to `code` passes the current comparison silently (`check-model-tiers.sh:350-352`) | new | became D-3 |
| F-19 | guard-liveness | check-model-tiers runs only as a commit hook, never in CI on the shipped tables (`.github/` grep empty) | new | became D-16 |
| F-20 | guard-liveness | Case M zeroes every timer, so no test can tell ceiling values apart (`runtime-shim-selftest.mjs:435-436`) | new | became D-6 |
| F-21 | guard-liveness | Port fails open; family is wrong for a fable-overridden seat (`intake-fanout.mjs:169-181`) | new | became D-2 |
| F-22 | guard-liveness | Enrolment without B13 growth passes; the FAIL text is false for these two agents (`check-emit-deadline.sh:344`) | new | became D-12 |
| F-23 | premortem | Verbatim refuteOne plus intake-refuter's refuted-by-default discredits real blockers (`intake-fanout.mjs:179`) | already-had | became D-1 |
| F-24 | premortem | The substantial table reds the guard; the naive escapes break AC-4 or hide the table (`check-model-tiers.sh:475-480`) | already-had | became D-3 |
| F-25 | premortem | Empty text (a turn-cap death) counts as a Fable failure, giving a false family record (`intake-fanout.mjs:125-138`) | overturned (snapshot: "port intake-fanout dispatch() verbatim") | became D-4 |
| F-26 | premortem | 7-min Opus seat ceiling is unmeasured; the mutation seat (maxTurns 30) is most at risk (`code-review.mjs:417-420`) | new | became D-6 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Refuter agent identity | open — recommend a new review-toolkit agent (finding-refuter, frontmatter `fable`, table tier `cross`) over reusing intake-refuter, whose doc is intake-framed and whose behavior is the measured #916 arm |
    | D-2 | Refuter default when it cannot confirm | open — recommend three-valued output (reproduced / refuted-with-evidence / unverified); intake-refuter's refuted-by-default would fail OPEN on a true blocker |
    | D-3 | Consumer modelOverrides vs the substantial tier | open — recommend override wins (repo-wide precedence override > table), seats[].model records actual |
    | D-4 | Authority the substantial table is held against in check-model-tiers.sh | open — recommend a parsed `## Substantial panel` table in model-tiering.md (TIER-MAP-DRIFT pattern); SUBSTANTIAL entries must also escape the whole-file 'agent': 'tier' frontmatter grep or they read as MISMATCH |
    | D-5 | Return shape under panel substantial | open — recommend keep reviewers[] unchanged (review-lead Step 4b darkness reads it) and add seats[] + per-finding outcome/family; standalone returns exactly today's shape |
    | D-6 | Refuter retry / Fable fallback under a 3-min phase ceiling | port intake-fanout dispatch(): one retry re-picked through live(); parallel refuters all failing at once otherwise never trip the fallback |
    | D-7 | requiredSeats ∪ reviewers dedup; reviewers non-empty check relaxed only for refute-only mode | codebase-shaped |
    | D-8 | Family recording for refute-only findings (madeBy unknown) | open — compare madeBy when present, else treat as reasoning |
    | D-9 | model-tiering.md "do not yet" sentence updated for code-review.mjs | codebase-derived |
    | D-10 | perf/complexity emit deadline line = maintainability-reviewer.md:170 verbatim; enrol in DEADLINE_AT_DEFAULT; amend WHY ONLY THIS ONE | ticket |
