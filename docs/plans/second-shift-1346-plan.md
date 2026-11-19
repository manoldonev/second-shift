# Plan — a caller-facing surface states its request and response shapes

## 1. Lint: the `contract` disposition

- [ ] 1.1 Selftest cases: a contract row whose cited row lacks `Inputs:`, `Outputs:` or `Errors:` fails, naming the missing label (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh) [AC-1]
- [ ] 1.2 Selftest case: a contract row that cites an `open` row fails, named (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh) [AC-2]
- [ ] 1.3 Selftest cases: a contract row whose cited row has a `cited (convention|adr)` path missing from the repo, or outside it, fails, named; a receipt outside a git checkout fails, named (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh) [AC-3]
- [ ] 1.4 Selftest cases: a contract row whose cited row carries the three labels and an existing path lints clean, as do `none — <reason>` labels and a `cited (kb)` pointer; the same unlabeled row cited `decided` stays clean (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh) [AC-4]
- [ ] 1.5 Add `contract (D-n)` to the surface disposition enum in ledger-lint.sh; check the cited row's kind, its three labels and its cited paths against the repo root from the git common dir (plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh)

## 2. No-archeology lint

- [ ] 2.1 Selftest: `contract (D-n)` in a record row is data, and in a message it is a hit (scripts/check-no-archeology-selftest.sh)
- [ ] 2.2 Drop `contract (D-n)` in a line that opens a record row, as `decided (D-n)` is dropped (scripts/check-no-archeology.sh)

## 3. Rule text

- [ ] 3.1 interviewing-baseline SKILL.md: the widened surface definition, the `contract` disposition and its row contract, the path check, the empty-form limit, and the shape sentences outside the 40-word guide (plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md)
- [ ] 3.2 receipt.md Surface Inventory and "Lint it" bullets, and the 40-word note; interview.md Exit; plan-interview SKILL.md step 3 (plugins/intake-toolkit/skills/intake/receipt.md, plugins/intake-toolkit/skills/intake/interview.md, plugins/intake-toolkit/skills/plan-interview/SKILL.md)
- [ ] 3.3 split.md Step 1: one sentence that the quarantine does not exempt a caller-facing interface from a `contract` row (plugins/intake-toolkit/skills/intake/split.md)
