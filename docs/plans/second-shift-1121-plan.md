# Plan — hard P4 cases for the planted corpus

## 1. Tests

- [ ] 1.1 The shipped corpus counts ten P4 cases and all four patterns, and a copy that drops a pattern's only case fails naming the pattern (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-1]
- [ ] 1.2 A copy whose new case has no distraction fails, and a copy whose distraction sits within WINDOW of a truth range fails (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-2]
- [ ] 1.3 A copy whose new case is cut below 80 changed lines outside the plan fails naming the case, and the frozen under-80 cases still pass (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-3]

## 2. The check

- [ ] 2.1 Freeze the 29 existing case ids, and add the 80-line floor, the distraction rule, truth.pattern and the pattern coverage to `check` (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 3. The cases

- [ ] 3.1 Add the vuejs/core overlay and its NOTICE line (plugins/review-toolkit/evals/code-review-bench-eval/planted/overlays/vuejs__core, plugins/review-toolkit/evals/code-review-bench-eval/planted/NOTICE)
- [ ] 3.2 Add six P4 cases from github-readme-stats and vuejs/core, one or more per pattern, each with one distraction (plugins/review-toolkit/evals/code-review-bench-eval/planted/cases)

## 4. Docs

- [ ] 4.1 Update the planted mode section: the case count, the class counts and the new case.json fields (docs/testing.md)
