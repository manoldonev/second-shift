# lean review verdict — #868

verdict=approve
run_id: review-868-1
session_id: b598b13e-07ba-469d-9cd7-c3bb5953798b
rounds: 1
pr: #873
reviewed_head: 512e3d0b133fc4c35caed8d5b6eb11032648c889
reviewed_patch_id: 7e018939936ca4d1a0b62938a53ef8f290535727
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review — PR #873 (issue #868), round 1

Range: `4491dc16..512e3d0b` (full branch; `G delta` found nothing to inherit). Panel: the pipeline default (only scope-completeness), with no opt-ins taken. The lead pass covered performance, maintainability, complexity, test coverage and security.

This record carries two scorecards on purpose, as the PR body says. The installed writer (14.0.1) reads only the AC scorecard. The branch's boundary reads the Decision scorecard, because the spec declares 8 intent rows (D-1–D-7, D-13).

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | note (operator-owned) | issue #868 Acceptance bullet 3; spec D-7/D-8 | The installed scope-completeness reviewer returned FAIL on one item: "a replay on the consumer head names the departed row" is not in the diff. D-7 is `user-answered` and gives the replay to the operator, after the PR opens and before merge authorization, with the result recorded in the PR body. D-8 parks it under OR-1. The build is barred from running it, so no build round can clear it. Under this PR's own rule (the record governs the ticket), it is not a code finding. **Merge authorization still waits on the operator's replay**, as the PR body already says. |
| 2 | warning | `plugins/review-toolkit/skills/review-lead/SKILL.md:347` vs `:373` | The general rule "**Do NOT pass** the plan/spec to sub-agents" was left unqualified. The new scope-completeness dispatch item 3 now passes the spec path. A reader of line 347 would drop the arg. Fix: add "except the lane spec path to scope-completeness-reviewer (below)". |
| 3 | suggestion | `boundary-evidence-selftest.sh` (scd) | No (scd) case covers `undeterminable` beside approve in Decision mode. The line is shared with the AC arm (sc4), so only the Decision message variant goes untested. |

Verified locally at the reviewed head: `boundary-evidence-selftest.sh`, `milestone-gate-selftest.sh`, `scenario-liveness-selftest.sh`, `check-lane-chain-selftest.sh` and `runtime-shim-selftest.mjs` are all green. Net diff outside `docs/plans/` is +316/−319.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | boundary-evidence.sh `spec_intent_rows` (provenance-keyed, DEPARTURE marker) + `scorecard_violations` keyed D/AC; one reader for the `scorecard` subcommand and `arm_verdict`; the writer's `--print-schema --spec` in milestone-gate.sh cmd_verdict |
| AC-2 | satisfied | boundary-evidence.sh violated / undeterminable / undeclared-departed / `decided_by` refusals under approve; the no-Decision-section refusal (no legacy arm); selftest scd2–scd4 |
| AC-3 | satisfied | scope-completeness-reviewer.md Step 3b (intent rows, file:line, `## Gap` names D-n, `decided_by` or the legacy `ratified: yes` pair), Step 2 row-governs rule, Step 5 FAIL on a failing row |
| AC-4 | satisfied | code-review.mjs `spec` arg forwarded as the path only; review-lead SKILL dispatch item 3; runtime-shim H3c/H4 |
| AC-5 | satisfied | review/SKILL.md step 5 (transcribe, no AC beside, build-authored limit stated) and step 5d (record governs) |
| AC-6 | satisfied | scenario-liveness `(lean-decision-scorecard)` drives writer → m4 → boundary, including the hand-edited violated case; boundary-evidence (scd1–scd6); no new file |
| AC-7 | satisfied | tools/capability-parity.tsv (both rows) and docs/testing.md name the Decision scorecard |
| AC-8 | satisfied | `git diff --stat 4491dc16..HEAD` outside docs/plans = +316/−319, stated in the PR body; no new gate, record kind or key |

## Decision scorecard

| D-n | score | evidence |
| --- | --- | --- |
| D-1 | honored | base 4491dc16 is #872; scope-completeness-reviewer.md Step 3b reads `decided_by:` and the legacy `ratified: yes` pair; review/SKILL.md 5d is rewritten in #872's place |
| D-2 | honored | boundary-evidence.sh `spec_intent_rows` keys on the Provenance cell; review/SKILL.md step 5 states the build-authored / ledger-lint --reconcile limit |
| D-3 | honored | boundary-evidence.sh `scorecard_violations` keyed by the declared id set; milestone-gate.sh cmd_verdict retargets the same refusal (`--print-schema --spec`); "never both" is a skill instruction, per the spec's Notes |
| D-4 | honored | scope-completeness-reviewer.md rewritten in place (name unchanged), Step 3b plus Step 2 precedence; code-review.mjs forwards the path only; the review skill says transcribe, not re-score |
| D-5 | honored | boundary-evidence.sh `D_SCORECARD_SCORES` enum and the approve-arm refusals; an unmarked departure is refused as departed |
| D-6 | honored | no legacy arm: boundary-evidence-selftest scd2; the commit's Changelog Migration line |
| D-7 | honored | the PR body flags the operator's replay as owed before merge authorization; the build ran none (see finding 1) |
| D-13 | honored | the validator does not parse the intent-gap prose; scope-completeness-reviewer.md Step 3b requires `## Gap` to name the D-n |
