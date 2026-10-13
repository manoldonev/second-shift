# #1040 — the scheduler proves each tagged test fails without the change: task plan

## 1. Tests

- [ ] 1.1 run.sh scenario cases: a tagged test file that passes on the record commit's tree with the head's tagged files applied makes the run red, its log naming the AC and the file; every tagged file not marked holds failing there, with the checks green at the head, lets the run go on to review; both cases fail with the check removed from run.sh (plugins/dev-pipeline/skills/run/run-record-selftest.sh) [AC-6] [AC-7] [AC-8]
- [ ] 1.2 the fake build session writes a per-session tree of files into the worktree before it pushes (plugins/dev-pipeline/skills/run/run-selftest-lib.sh)
- [ ] 1.3 plan-coverage cases: the holds and unchecked forms, a tagged task naming no test file, the --files map (plugins/dev-pipeline/tools/plan-coverage-selftest.sh)
- [ ] 1.4 ledger-lint cases: holds and unchecked lines with and without a reason (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh)
- [ ] 1.5 config-lint cases: a well-formed testRunners list, and each malformed entry named (plugins/dev-pipeline/tools/config-lint-selftest.sh)

## 2. Implementation

- [ ] 2.1 plan-coverage.sh: the holds and unchecked forms, test files required on tagged tasks, a --files output mode carrying the AC-to-file map (plugins/dev-pipeline/tools/plan-coverage.sh)
- [ ] 2.2 run.sh: the fails-without-the-change leg after the coverage check, its log and run-block lines, the restore on exit and on a re-launch, the build prompt's instruction, the plan-position note's wording (plugins/dev-pipeline/skills/run/run.sh)
- [ ] 2.3 ledger-lint.sh accepts the holds and unchecked forms, each with its reason (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh)
- [ ] 2.4 the testRunners config key: config-lint, the JSON schema, the schema guide (plugins/dev-pipeline/tools/config-lint.sh, schema/second-shift.config.schema.json, docs/config-schema.md)
- [ ] 2.5 intake writes the two forms and puts each to the operator (plugins/intake-toolkit/skills/intake/receipt.md, plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md)
- [ ] 2.6 the handoff path: the review notes the check was not run, the build skill lists it among what the scheduler does not do (plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/build/SKILL.md)
- [ ] 2.7 the decision record: D-8's departure and the rows the build decided (docs/plans/second-shift-1040-decisions.md)
