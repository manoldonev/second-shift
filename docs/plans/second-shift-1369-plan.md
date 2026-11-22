# Plan — discovery-recall-eval

## 1. Scaffold

- [ ] 1.1 Selftest: the scaffold writes the snapshot and the ticket, and a repo without the snapshot commit exits non-zero with one stderr line and an empty workspace (plugins/intake-toolkit/evals/discovery-recall-eval/scaffold-selftest.sh) [AC-3]
- [ ] 1.2 Copy the scaffold and the fixture ticket from decision-questions-eval (plugins/intake-toolkit/evals/discovery-recall-eval/scaffold.sh, plugins/intake-toolkit/evals/discovery-recall-eval/fixture/TICKET.md)

## 2. Case

- [ ] 2.1 Draft the answer key from the earlier ticket's record and fix diff, with a snapshot line per fact (plugins/intake-toolkit/evals/discovery-recall-eval/case.yaml)
- [ ] 2.2 Write the run shape, the prompt with its two headings, the fact- graders, no-false-premise, read-the-scheduler, no-plan-written and stayed-in-snapshot (plugins/intake-toolkit/evals/discovery-recall-eval/case.yaml)

## 3. Docs

- [ ] 3.1 Write the README: run command, trace check, discard rule, recall jq line, facts-list count, held-out recipe, row format, anchor recipe and the answer-key warning (plugins/intake-toolkit/evals/discovery-recall-eval/README.md)
- [ ] 3.2 Add an empty BASELINE.md (plugins/intake-toolkit/evals/discovery-recall-eval/BASELINE.md)
