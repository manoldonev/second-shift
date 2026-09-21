# lean review verdict — #866

verdict=approve
run_id: review-866-1
session_id: 3ae387a4-42ec-431d-8afe-e297df6ab235
rounds: 1
pr: #870
reviewed_head: ec9b1378dc311bfa1b4879f5d8be19d95f14dcce
reviewed_patch_id: 59af075128ce5b54ace12c4670eff9c9e27e7fb4
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full range `2a211712..ec9b1378` (8 files, +176/−13). Panel: pipeline default (scope-completeness only); no opt-ins taken. The security, performance, maintainability, complexity and test-coverage dimensions were covered by the lead pass. a11y and design fidelity were not routed: this repo configures no design provider and no web-component surface, and the spec has no armed `## Design` section.

The change does what the spec says. The `mark` dispatch guard reuses milestone 4's stale-receipt text through one helper, sits after `require_ticket_still_open` and before `cmd_mark`, and is a no-op on an unarmed spec, a missing receipt, or an identity that cannot be computed (D-12/D-13). The close-out path still calls `cmd_mark` directly, so the guard does not touch it. The ratification-by-delegation docs are consistent across interviewing-baseline, the build and review skills, the hand-back record and the consumer template. The boundary's `ratified_by:` check is unchanged.

**Scope reviewer blocker, not upheld.** The scope reviewer flagged (b), stale-verdict merges, as not implemented and not deferred in the issue body. The issue's own Acceptance allows each row to be "shown to be out of scope for this change". The committed spec's D-1 (`user-answered`) does exactly that: it gives the reason (the shipped freshness arm, `reviewed_patch_id` in `boundary-evidence.sh`, already refuses a moved head wherever consumers install the boundary check), and the replay row map lists the 23 (b) rows as out of scope under D-1. The pre-flight ledger is the lane's definition of done. This is an operator resolution, not a silent deferral, and the two artifacts do not contradict each other, so neither a blocker nor a 5d hand-back applies.

The scope reviewer's minor, "net diff stated at merge authorization", is satisfied by the PR body's "Net diff: 7 files, +100/−13 outside `docs/plans/`" line.

CI: `pr-gates` is red only for the missing verdict record, which this round writes. `lint-and-selftests` and `selftests` were pending when this was written. Both touched suites were run locally at the reviewed head: `boundary-evidence-selftest.sh` all green, including (y2), and `milestone-gate-selftest.sh` all green (rc=0), including (dm0)/(dm2)/(dm3).

## Findings

| # | Severity | Location | Finding |
| - | -------- | -------- | ------- |
| 1 | nit | `plugins/dev-pipeline/skills/review/SKILL.md:146` | The added paragraph's first line is not wrapped to the surrounding ~100-column width. Cosmetic only. |
| 2 | nit | `milestone-gate-selftest.sh` (dm3) | The unarmed control asserts only the absence of `renders from`. It would also pass if `mark` failed for an unrelated reason. That is acceptable for what it claims (the guard does not refuse), and (dm0) is the positive control. |

No blockers.

## AC scorecard

| AC-n | score | evidence |
| -- | ----- | -------- |
| AC-1 | satisfied | `require_render_receipt_fresh` at `milestone-gate.sh` dispatch (`mark) require_ticket_still_open; require_render_receipt_fresh`). It exits 1 before `cmd_mark`, so it posts nothing and runs with or without a bot. It returns 0 on an unarmed spec, an absent receipt, or an empty identity. `cmd_5`/`cmd_close_out` call `cmd_mark` as a function and bypass it. Selftests (dm2)/(dm3). |
| AC-2 | satisfied | `render_receipt_stale_msg` is the single definition, read by `cmd_4`'s `fail_milestone 4` and by the guard. The text is byte-identical to the removed literal. The `fail_milestone 4` call site is kept, so the (ac1) count is unchanged; the gate selftest's (ac1) case passes. |
| AC-3 | satisfied | (dm2): a stale receipt at `mark` gives rc=1 and milestone 4's text, and `cmd_mark` is not reached. (dm0): a fresh receipt reaches `cmd_mark`. Both pass locally. |
| AC-4 | satisfied | interviewing-baseline documents the two valid citations: a standing delegation by blob permalink, and an operator comment. The flip advice now says "Ratify before the review handoff". |
| AC-5 | satisfied | build SKILL.md: the P9 bullet ("Under a standing delegation, you ratify it yourself…") and the tracker-writes bullet ("needs no tracker write") agree. |
| AC-6 | satisfied | review SKILL.md step 5d gains the paragraph saying a pending ratification is not a review finding and the boundary settles it. The 5d hand-back text is otherwise unchanged. |
| AC-7 | satisfied | The `cmd_verdict --hand-back ratification` record text names both the operator comment and the committed standing-delegation line's blob permalink. |
| AC-8 | satisfied | The consumer `SECOND-SHIFT.md` template gains a "Ratification can be delegated" bullet: an example line, the permalink form, and the fallback. |
| AC-9 | satisfied | boundary-evidence-selftest (y2): `ratified: yes` plus a blob permalink gives a silent rc=0. Passes locally. |
| AC-10 | satisfied | The diff adds only `docs/plans/second-shift-866-lean.md` (the lane record). No new record key, capability token or register row. The guard reuses the existing string. The boundary's `ratified_by:` check and violation text are untouched (no diff in `boundary-evidence.sh` / `check-lane-chain.sh`). |

## Verdicts

| Reviewer | Verdict | Findings |
| -------- | ------- | -------- |
| Scope Completeness | Fail (blocker not upheld, see summary) | 2 |
| Security | Lead pass — ✅ | 0 |
| Performance | Lead pass — ✅ | 0 |
| Complexity | Lead pass — ✅ | 0 |
| Maintainability | Lead pass — ✅ | 1 nit |
| Test Coverage | Lead pass — ✅ | 1 nit |
