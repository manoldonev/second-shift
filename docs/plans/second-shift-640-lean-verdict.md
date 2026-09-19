# lean review verdict — #640

verdict=needs-work
run_id: review-640-1
session_id: dac2a59b-fe13-4dad-b4ee-f785713157d4
rounds: 1
pr: #859
reviewed_head: d7ce6294d7599accf40f3f2eadadf80d8dcadadd
reviewed_patch_id: 403320ff15aa0e8186cffcc7ab73b6c0d5e54157
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full range `49147157..d7ce6294` (nothing to inherit). Panel: pipeline default (scope-completeness only); no opt-ins taken (no `review panel` ledger row, no `reviewers.default[]`). The security dimension was covered by the lead pass. a11y and design-fidelity were not routed because the diff has no web-component surface. The spec's `## Design` section is absent (a shell/gate-only ticket), so fidelity is `not-applicable`.

The PR does what the spec asks at all three layers. The writer refuses an approve at `never-evaluated` (rc 1) and at `unknown` (rc 2) and stamps `ci_state:` on every record. The boundary refuses a non-`evaluated` approve and passes a record with no key. The scheduler stops at class 12 before the REVIEW spawn. Using the head ref as the positive control is the right way to keep an unserved remote from reading as `never-evaluated`. Every AC has a named selftest case behind it, and each case has a non-vacuity partner.

**One blocker, from CI rather than from reading.** The `lint-and-selftests` correctness lane is red at `d7ce6294` on `tools/prose-blockers-selftest.sh`, and this branch causes it: `main` (`49147157`) checks clean. The design is sound. The fix is a one-row register update.

## Strengths

- `merge_ref_state` treats "head absent" as `unknown`, never as `never-evaluated`, so a remote that doesn't serve PR refs can't manufacture a zero-CI stop. `zc4` pins that.
- The boundary reads `ci_state` anchored to the header (`ci_state_key`), and `(ci-body)` proves a body line can't supply the key. That closes the conditional-key injection door the writer's own comment warns about.
- The scenario leg `lean-zero-ci` composes writer → milestone 4 in both directions on one tree (ref absent: 1/no record/12; ref present: 5 → approve → 0).
- The `by-design` disposition gets both a positive case and a negative one (`g5b`/`g5c`), so it can't become a way to excuse a live `| grep -q` site.

## Critical (must fix before merge)

- [Cross-cutting / CI] `plugins/dev-pipeline/skills/review/SKILL.md:146` (confidence: 100). The four AC-8 lines were added inside the step-6 construct that `docs/prose-blocker-triage.tsv` dispositions as `pb-1c207e51` (gate-backed, pointer-kept). Construct IDs are content-derived, so the edit re-keys it to `pb-f448a37c`. `bash tools/prose-blockers.sh check` now reports `pb-f448a37c` UNDISPOSITIONED and `pb-1c207e51` STALE. The CI job `lint-and-selftests` (run 35445189992, job 105902806562, head `d7ce6294`) fails `prose-blockers-selftest.sh`: "this repo's own tree is fully dispositioned — want '0', got '3'". Fix: re-key the triage row to the new ID (same disposition; the gate backing it is still `milestone-gate.sh::verdict`, which now also carries the zero-CI refusal). Alternatively, move the instruction out of that construct. Re-run `bash tools/prose-blockers.sh check` until it prints zero undispositioned constructs.

## Warnings (should fix)

- [Maintainability] `plugins/dev-pipeline/skills/run/orchestrate.sh:1652` (confidence: 85). The post-review `case` still says "2 and 3 are deliberately absent here … an arm for either could only be dead code". With `--pr` on the post-review `verdict_rc`, 2 is now reachable after a spawn: a REVIEW that left no record, followed by an unreadable `ls-remote`, returns 2. Previously that case returned 5 and got the bounded review re-spawn. Now it falls to `*) terminal verdict-gate-failed`. The stop is fail-closed and acceptable, but the comment is false and the terminal slug misnames the cause. Either route 2 to `verdict-gate-unreadable` here too, or correct the comment. Not a blocker: no AC covers the post-review unknown path, and the lane stops instead of proceeding on a guess.

## Suggestions (consider)

None.

## Plan Compliance

Implementation matches the plan. D-1 (both layers), D-2/D-3 (unknown → rc 2 at the writer and pre-spawn), D-5 (no reuse of the rc-11 hand-back), D-7 (`by-design` disposition) and D-8 (network read only with `--pr`) are each visible in the diff.

## Pre-existing gaps (not blocking this PR)

- The read proves only that a merge ref is present. It doesn't prove the ref is current for the head. A merge ref left over from an earlier evaluated head reads as `evaluated`. The spec states this limit ("distinguishes merge-ref-present from merge-ref-absent"), and it is outside #640's born-conflicting target.

## Suppressed (below confidence threshold)

- [Scope completeness] `plugins/dev-pipeline/skills/review/SKILL.md:166` (confidence: 60). The issue names `review-lean/SKILL.md`. The file was renamed and D-4 records the mapping, so this is correct as written.

## CI

- `mutation-sweep-pr`: pass at `d7ce6294`.
- `pr-gates`: red at `d7ce6294`. That is the lane-chain policy gate, which has no verdict record to read before this round lands. It is recorded, not a blocker (merge-boundary refusal ≠ review round).
- `lint-and-selftests`: **fail** at `d7ce6294`. One suite failed: `tools/prose-blockers-selftest.sh`, the blocker above. Every suite this diff touches passes in that same job: boundary-evidence, milestone-gate, scenario-liveness, orchestrate and check-fail-open-shapes. Those are cited here, not re-run.
- `selftests (macos, bash 3.2)`: pending at review time.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cmd_verdict` refuses approve at `never-evaluated`, rc 1, naming the state and "never whether it was red or green". `milestone-gate-selftest.sh` (zc1) asserts rc 1, the message and no record. |
| AC-2 | satisfied | `echo "ci_state: $VERDICT_CI_STATE"` is emitted unconditionally, and the key is added to `LANE_VERDICT_HEADER_KEYS`. `arm_verdict` refuses approve at any non-`evaluated` value. `boundary-evidence-selftest.sh` covers (ci-never-evaluated/unknown/bogus) and (ci-evaluated). |
| AC-3 | satisfied | An absent key passes (`[ -n "$VERDICT_CI_STATE" ]` guard), shown by (ci-absent). The `fail-open-sites.tsv` row uses `by-design`, and `check-fail-open-shapes.sh` accepts it with converted's rules (g5b clean, g5c red on a live site). |
| AC-4 | satisfied | `cmd_4` returns 12 with `--pr`, no record and no merge ref (zc7). `verdict_rc` passes `--pr "$PR"` (c1/r6). The pre-spawn `elif [ "$rc" -eq 12 ]` stops at `ci-never-evaluated`. (vr5) asserts one spawn, no review, no second round and `--pr 11` on the read, and (vr6) covers the post-review 12. |
| AC-5 | satisfied | needs-work writes at `never-evaluated`, stamped (zc2). The boundary judges approves only (ci-needs-work). Milestone 4 still reads class 1 for that record (zc11). |
| AC-6 | satisfied | An unreadable remote gives `unknown`, and the writer calls `envfail` (rc 2) on approve (zc3). A remote that serves no head is also `unknown` (zc4). needs-work stamps `unknown` (zc5). Milestone 4 `--pr` returns 2 (zc8), and the pre-spawn path already routes that to `verdict-gate-unreadable`. |
| AC-7 | satisfied | `LANE_PR_REMOTE`, `MERGE_REF_TRIES` and `MERGE_REF_BACKOFF` are documented in the gate's env-seam list. The suites use local bare repositories. (zc10) shows no read without `--pr`. |
| AC-8 | unsatisfied | The content is right: `review/SKILL.md` step 6 gains four lines (don't retry, don't rewrite as needs-work, post and stop, a found blocker is still needs-work), and the rule lives in the gate. But the edit re-keys the triaged prose construct `pb-1c207e51` → `pb-f448a37c`, and `lint-and-selftests` is red on `prose-blockers-selftest.sh` at `d7ce6294`. A correctness lane contradicts the change this AC delivers. |
| AC-9 | satisfied | Rows added: `gate-ablation-classes.tsv` `m4/ci-never-evaluated` (milestone 4), the AC-3 fail-open row, three `gates-signal` rows in `gate-buckets.tsv`, and `lane-bench-classes.tsv` `ci-never-evaluated lane-error`. `scenario-liveness-selftest.sh` gains the (lean-zero-ci) leg with the ref-present non-vacuity half. |

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Cross-cutting (CI) | Fail | 1 (blocker) | 100 |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ❌ | 1 (warning) | 85 |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** No. The one blocker is the prose-blocker triage row the SKILL.md edit re-keyed, which reds `lint-and-selftests`. The warning is optional.
