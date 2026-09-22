# lean review verdict — #877

verdict=approve
run_id: review-877-1
session_id: bdbb70c6-404d-4a5f-a53f-c5e78972222a
rounds: 1
pr: #880
reviewed_head: 59823d08362568aa369cfdcde5ed853b1251a859
reviewed_patch_id: a7a939f7e6c5a9083a1bb88a394531784458a376
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 1, full range `7e258fcf..59823d08` (13 files, +216/−431). The PR retires `config-grill.sh`'s `T4.mutation-plumbing` and `T1.mutation-sweep` checks together with the `unadopted[]` severity (the envelope becomes `{findings, notEvaluated}`), drops doctor's unadopted-note rendering and onboard's unadopted-blocking rule plus the "gates to enable" question, renumbers the batch, and rewrites the schema/docs wording so `gates.mutation` reads accepted-but-unread. Selftests are re-pointed at surviving checks (`T4.design-liverender` for doctor, `T5.missing-script` for the multi-repo scoping case), and one new case pins retired-id waivers as inert. Implementation matches the spec. No blockers.

Panel: pipeline default (scope-completeness only); no opt-ins taken (no `review panel` ledger row, no `reviewers.default`). a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`). Lead pass covered performance, maintainability, complexity, test coverage and security.

CI at head `59823d08`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass. `pr-gates` is red only because the committed verdict record (`*-877-lean-verdict.md`) was missing. That is a policy gate, and this record is what clears it. The review session also ran `config-grill-selftest.sh`, `doctor-selftest.sh` and `config-lint-selftest.sh` locally (all green), and shellcheck on the touched tool dirs was clean.

## Decision scorecard

| D-n | score | evidence |
| --- | ----- | -------- |
| D-1 | honored | `config-grill.sh` emits `{findings, notEvaluated}` and `add_unadopted`/`UNADOPTED` are gone; `doctor.sh` unadopted comment and note loop removed; `onboard/SKILL.md` accept predicate is "no unwaived `findings[]`"; `docs/config-schema.md` `grillWaivers` row and schema description drop the unadopted wording; `config-t1-waived.json` and the `grill-unadopted*` scenarios deleted |
| D-2 | honored | `docs/onboarding.md` "Mutation: the repo-carried sweep" section deleted; one paragraph remains stating `gates.mutation` is accepted, read by nothing, removed at the next batched major |

## Findings

| # | severity | dimension | location | finding |
| - | -------- | --------- | -------- | ------- |
| 1 | suggestion | Maintainability | `plugins/second-shift/skills/onboard/tools/config-grill.sh:394` | The new comment cites "config-grill.sh:252's trigger-4 row". Line 252 is inside the `T4.design-liverender` block; the retirement note is at ~240. A line-number self-reference is already stale; name the trigger instead. |
| 2 | suggestion | Maintainability | `plugins/second-shift/skills/onboard/tools/config-grill.sh` (former trigger-4 `else` branch) | The `T4.commands` notEvaluated entry ("no topology.repos entry resolves to the evaluated root, so there is no command table to check") was removed along with the mutation block. The spec does not mention it. The per-repo `topology.<id>` notes still fire, so the practical effect is small, but a config with no resolvable repo now skips T5 without saying so. |
| 3 | suggestion | Maintainability | `plugins/dev-pipeline/tools/config-lint.sh:257` (not in diff) | A comment's worked check-id example still reads `T4.mutation-plumbing.api`; AC-7 moved the docs/schema examples to `T5.missing-script.api.lint` but not this one. |

No critical or warning findings.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| -------- | ------- | -------- | ---------------- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ✅ | 3 (suggestions) | 80-85 |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** Yes

**Reasoning:** Both intent rows are honored, every AC is reflected in the diff with re-vehicled tests that keep the FAIL/waived/scoping paths live, and CI correctness lanes are green at the reviewed head. The three suggestions are comment/diagnostic nits and do not block.
