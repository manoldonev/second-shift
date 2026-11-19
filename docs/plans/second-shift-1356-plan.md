# Task plan — intake fan-out: no refuters, no waiting, a Fan-out section that checks

## 1. The workflow

- [ ] 1.1 Rewrite case FO for a run with no refuter: every lens claim in the pool as `unverified` with the six evidence fields, every dispatch and retry on the `reasoning` token, an unreachable override retried on `reasoning`, `intake-lens` overrides and `tierMap` still retarget, the result has no `refuter` and each lens entry only `key`, `model`, `status`, `claims`, a lens dead after its retry makes the run `partial` (plugins/review-toolkit/workflows/runtime-shim-selftest.mjs) [AC-1] [AC-2] [AC-3]
- [ ] 1.2 Drop the refuter stage, the family alternation and the second-family fallback; one retry on the `reasoning` token; reword the build rules and the lens prompt (plugins/review-toolkit/workflows/intake-fanout.mjs)
- [ ] 1.3 Delete the refuter agent and its tier entries; reword the lens agent (plugins/review-toolkit/agents/intake-refuter.md, plugins/review-toolkit/agents/intake-lens.md, plugins/review-toolkit/scripts/check-model-tiers.sh)

## 2. The receipt lint

- [ ] 2.1 Add v5 Fan-out cases: a `became D-n` row with no `From:`, a `From:` to an undeclared finding, a `From:` the finding's disposition does not name, each tally count that disagrees with the rows, a question id not declared or not named; no `Refuter:` line and the new empty-pool line on v5; a v4 receipt still needs `Refuter:` and accepts the old empty-pool line; `--receipt-version` prints 5 (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh) [AC-11] [AC-12] [AC-13] [AC-14]
- [ ] 2.2 Add the v5 fixture receipt (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-fixtures/valid-receipt-v5.md)
- [ ] 2.3 Add the `Fan-out (v5 form)` row at v5 and the v5 arm of check G (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh)

## 3. The build prompt

- [ ] 3.1 Assert the build prompt keeps "Only the D-n rows bind" and carries the sentence on a row that cites `From: F-n` (plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-15]
- [ ] 3.2 Add the sentence to the build prompt (plugins/dev-pipeline/skills/run/run.sh)

## 4. The stage texts and docs

- [ ] 4.1 The notice, the launch order, the skip, the snapshot, the interview while the fan-out runs, check-before-use (plugins/intake-toolkit/skills/intake/explore.md)
- [ ] 4.2 The interview start, the close condition, `already-had`, the asked-again rule (plugins/intake-toolkit/skills/intake/interview.md)
- [ ] 4.3 The v5 Fan-out section, rules 5 and 6, the version table row (plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md)
- [ ] 4.4 The receipt, the skill table, the tier doc and the namespaces doc (plugins/intake-toolkit/skills/intake/receipt.md, plugins/intake-toolkit/skills/intake/SKILL.md, plugins/review-toolkit/model-tiering.md, docs/namespaces.md)
