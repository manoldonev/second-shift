# Plan — P1 and gate-exercising cases for the planted corpus, and a 40% cap per upstream

## 1. Tests

- [ ] 1.1 The shipped corpus counts the four new review-hard P1 cases and the four runner P1 cases, and the pinned count line holds the new class counts (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-1]
- [ ] 1.2 A copy whose new review-hard P1 case is cut below 80 changed lines, or loses its distraction, fails naming the case (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-2]
- [ ] 1.3 A copy in which one upstream holds more than 40% of the cases fails naming the upstream and its share, and the shipped corpus passes (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-3]
- [ ] 1.4 A synthetic jest-json runner: the install runs once per base, a missing runner binary fails the build loudly, and `verify` accepts a runner case only when the lane stops on fails-without-the-change for the case's tagged test (plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh) [AC-4]
- [ ] 1.5 A copy whose runner overlay drops the command, or uses a format other than `jest-json`, or whose plan tags a bare file or a path no `when` glob matches, fails naming the case (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-5]

## 2. The check

- [ ] 2.1 Add the 40% cap per upstream, the runner declaration rule and the `expect_stop` field to `check` (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 3. Build and verify

- [ ] 3.1 Install a runner case's dependencies once per upstream and base beside the bare clones, copy them into each checkout, and fail loudly when the runner binary is missing (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 3.2 Make `verify` pass a runner case only on its expected stop (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 4. The cases

- [ ] 4.1 Add the runner overlay (plugins/review-toolkit/evals/code-review-bench-eval/planted/overlays/anuraghazra__github-readme-stats-jest)
- [ ] 4.2 Add four review-hard P1 cases from github-readme-stats, each with one distraction (plugins/review-toolkit/evals/code-review-bench-eval/planted/cases)
- [ ] 4.3 Add four runner P1 cases from github-readme-stats, each with a tagged test that never exercises the change (plugins/review-toolkit/evals/code-review-bench-eval/planted/cases)

## 5. Docs

- [ ] 5.1 Update the planted mode section: the case count, the class counts, the cap, the runner cases and `expect_stop` (docs/testing.md)
