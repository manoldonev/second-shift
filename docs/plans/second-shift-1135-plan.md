# Plan — the planted corpus promotes the pilot candidates a plain review gets wrong

## 1. The scored corpus

- [ ] 1.1 Pin the shipped `check` line to 49 cases with P4 16 and the four pattern counts, assert the six promoted ids sit in `PROMOTED` and not in `PILOT`, and that no dropped candidate's case directory exists while `check` passes (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-1] [AC-2] [AC-5]
- [ ] 1.2 Delete the 26 dropped candidate case directories, and remove the six promoted ids from `PILOT` (plugins/review-toolkit/evals/code-review-bench-eval/planted/cases, plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 1.3 Rebase the corpus-selftest pins, pattern-floor fixtures and cap fixtures on the promoted corpus (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-5]
- [ ] 1.4 State the promoted counts in the planted-mode section (docs/testing.md)

## 2. The outside-every-hunk rule

- [ ] 2.1 A copy whose promoted case keeps only its inside-hunk truth range fails `check` naming the case, for each promoted id (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-3]
- [ ] 2.2 Add `PROMOTED` and apply the rule to `PILOT` and `PROMOTED` (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 3. The pilot machinery with an empty PILOT

- [ ] 3.1 `check` prints `pilot 0 P4`, and the seven pilot checks run on fixture ids injected through `check_corpus` (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-4]
- [ ] 3.2 `check_corpus` and `check_case` take `pilot_ids` and `promoted_ids` that default to the constants (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 3.3 `run --pilot` with an empty `PILOT` exits non-zero with a no-pilot-cases message before any model call, and `select_cases` refuses `--pilot` on an empty pilot set (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-7]
- [ ] 3.4 Refuse `--pilot` when there are no pilot cases, in `main` before the bench loads and in `select_cases` (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
