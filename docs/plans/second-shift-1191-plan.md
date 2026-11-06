# Plan — a prescribed structure is not a requirement, and over-engineering is a finding

## 1. Plain review

- [ ] 1.1 The no-ticket prompt still drops the requirement line, with its new text, by its prefix; the existing selftests pass unchanged (plugins/dev-pipeline/tools/plain-review-selftest.sh, plugins/dev-pipeline/skills/run/run-joined-selftest.sh, plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh) [AC-7]
- [ ] 1.2 Define a ticket requirement on the `Also flag a requirement the ticket states` line, keep its prefix, use the external-surface definition in the over-engineering paragraph, and reword the blocker definition (plugins/dev-pipeline/skills/run/plain-review.md)

## 2. Lane review lockstep blocks

- [ ] 2.1 Add the requirement definition and the external-surface definition to every `review-correctness` copy (plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/run/run.sh, plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md)
- [ ] 2.2 Say in both `verdict-grammar` copies that `## Summary` and `## Notes` carry no over-engineering observation the findings do not; exempt the folded lane vs blind block (plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/run/run.sh)

## 3. review-lead

- [ ] 3.1 Report and triage: over-engineering only as a finding or in Suppressed on confidence; Plan Compliance and Plan/Spec Awareness use the requirement definition (plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 3.2 Pre-Emit Gate "Concrete today?" for over-engineering; the Complexity section says a plan the ticket prescribes is not a need (plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md)

## 4. scope-completeness-reviewer

- [ ] 4.1 Step 2b and the calibration treat a prescribed internal structure as no scope item and list each exclusion in Notes (plugins/review-toolkit/agents/scope-completeness-reviewer.md)
