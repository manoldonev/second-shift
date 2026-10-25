# Plan — the lane review reads the record after its code review

## 1. The lane review prompt

- [ ] 1.1 A case in run-selftest.sh renders the review prompt and checks the two passes, the severity rule, the notes pass after the correctness block, a first line that names no record, the record path only after the pass-2 marker, and a pass-1 diff that excludes the plans directory (plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-1] [AC-2] [AC-3]
- [ ] 1.2 Split review_prompt() into pass 1, pass 2 and the build's account, with the new review-completeness and review-correctness blocks and the notes pass (plugins/dev-pipeline/skills/run/run.sh)

## 2. The lockstep sites

- [ ] 2.1 Run pass 1 right after checkout in the review skill, then the record steps as pass 2, then the build's account (plugins/dev-pipeline/skills/review/SKILL.md)
- [ ] 2.2 Carry the new review-correctness block into the bench arm, whose framing says pass 2 does not apply (plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md)

## 3. The planted corpus

- [ ] 3.1 The planted renderer's selftest checks that the record read sits after the pass-2 marker (plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh)
