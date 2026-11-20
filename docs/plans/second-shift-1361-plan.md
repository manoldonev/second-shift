# Task plan — blind pass 1 of the lane review

## 1. The blind pass 1 in the lane

- [ ] 1.1 Scenario cases for a lane round: the pass-1 tree and flags, its prompt, the review session after it with its findings, a pass 1 with no findings block or past its limit, its cost, and a default round with the plain session (plugins/dev-pipeline/skills/run/run-pass1-selftest.sh) [AC-1] [AC-2] [AC-3] [AC-4] [AC-5] [AC-8]
- [ ] 1.2 Add the pass-1 prompt file and the pass-1 session to the review round of run.sh, and cut the pass-1 section from the review prompt (plugins/dev-pipeline/skills/run/pass-1-review.md, plugins/dev-pipeline/skills/run/run.sh)
- [ ] 1.3 Teach the fake session of the run suites to answer the pass-1 session, and move each suite to the review that always runs the plain session (plugins/dev-pipeline/skills/run/run-selftest-lib.sh, plugins/dev-pipeline/skills/run/run-joined-selftest.sh, plugins/dev-pipeline/skills/run/run-selftest.sh, plugins/dev-pipeline/skills/run/run-verdict-selftest.sh, plugins/dev-pipeline/skills/run/run-rows-selftest.sh, plugins/dev-pipeline/skills/run/run-detach-selftest.sh, plugins/dev-pipeline/skills/run/run-record-selftest.sh)

## 2. A prompt option for the blind session

- [ ] 2.1 Cases for plain-review.sh run with --prompt, without it, and with an unreadable --prompt file (plugins/dev-pipeline/tools/plain-review-selftest.sh) [AC-6]
- [ ] 2.2 Add --prompt to plain-review.sh run and drop its enabled command (plugins/dev-pipeline/tools/plain-review.sh)
- [ ] 2.3 Cases for an --out at or inside the worktree or a --deny-read path (plugins/dev-pipeline/tools/plain-review-selftest.sh)
- [ ] 2.4 Refuse that out dir with exit 2 before anything is cleared or run (plugins/dev-pipeline/tools/plain-review.sh)

## 3. The blind pass 1 in /dev-pipeline:review

- [ ] 3.1 The skill runs pass 1 with plain-review.sh run --prompt, in an out dir outside its denied scratch dir, and starts pass 2 only on its findings (plugins/dev-pipeline/skills/review/SKILL.md)

## 4. Retire run.joinedReview

- [ ] 4.1 A config that sets run.joinedReview fails config-lint.sh as an unknown run key (plugins/dev-pipeline/tools/config-lint-selftest.sh) [AC-8]
- [ ] 4.2 Remove the key, RUN_JOINED_REVIEW and every plain-review-off path from the lint, the schema, the skills and the docs (plugins/dev-pipeline/tools/config-lint.sh, schema/second-shift.config.schema.json, plugins/review-toolkit/skills/review-lead/SKILL.md)

## 5. Delete the planted mode of the review bench

- [ ] 5.1 Delete code-review-bench-eval/planted/ with its docs and references (plugins/review-toolkit/evals/code-review-bench-eval/README.md, docs/testing.md)
