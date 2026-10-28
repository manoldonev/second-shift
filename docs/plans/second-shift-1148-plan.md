# Plan — the blind-prove arm's verdict rule and the compare step

## 1. The verdict rule

- [ ] 1.1 Selftest cases for the rule: an unquoted DIFFERS candidate under an approve, a valid ticket quote, a short and an absent quote, UNPROVEN and SAME probes, a removed test expectation read from the diff, and one case-run through blind_prove_one whose record keeps both verdict texts (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-1] [AC-2] [AC-3] [AC-5]
- [ ] 1.2 The rule in planted.py: proven candidates, removed expectations, the quote check, coverage by site, the amended verdict, and the call in blind_prove_one before collect (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 1.3 The rule paragraph in intent's prompt (plugins/review-toolkit/evals/code-review-bench-eval/planted/arms/intent.md)

## 2. The compare step

- [ ] 2.1 Selftest cases for `compare` on two fixture results files: the per-case table, the totals, r2n5ax apart, and PASS or FAIL per criterion under --pm1 (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-4]
- [ ] 2.2 The `compare` subcommand in planted.py (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 3. The record

- [ ] 3.1 Rows for the details the record leaves open (docs/plans/second-shift-1148-decisions.md)
