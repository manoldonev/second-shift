# Plan — pilot-only P4 candidates and the pilot machinery

## 1. The pilot mark and the check

- [ ] 1.1 Test: the shipped corpus reports at least 32 pilot cases, 8 per pattern, with the class, pattern and cap counts unchanged; a copy whose pilot P4 case has no ranged truth location outside every hunk, or whose pilot case breaks a case rule, fails naming the case (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-1] [AC-2]
- [ ] 1.2 Test: an `instance` of `<owner>__<repo>-pr<N>` passes `check`, and an `instance` in neither form fails naming the case (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-5]
- [ ] 1.3 Add the `PILOT` id set; leave pilot cases out of the class counts, the pattern counts and the cap; report them; require a ranged truth location outside every hunk on a non-frozen P4 case; check the `instance` form (planted.py)

## 2. The pilot run

- [ ] 2.1 Test: the pilot case selection returns only pilot ids, refuses a pilot id without `--pilot` and refuses the lane arm; the record decision writes no changelog row on a pilot run or a pilot rescore (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-3]
- [ ] 2.2 Add `run --pilot`, its helpers, the pilot rescore and the judge-failure message that passes `--pilot` through (planted.py)

## 3. The per-case report

- [ ] 3.1 Test: `planted.py cases` on a canned results file prints right, wrong and noise per case, run and arm, counts unscored records apart, and prints the right rate over a given id set and over every case (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-4]
- [ ] 3.2 Add the model-free `cases` subcommand (planted.py)

## 4. The candidates

- [ ] 4.1 Build at least 32 P4 candidates, 8 per pattern, from vuejs/core instances and merged PRs of other MIT repositories (cases/)
- [ ] 4.2 Add each new upstream's overlay and NOTICE entry, and the NOTICE line on written problem statements (overlays/, NOTICE)

## 5. The text

- [ ] 5.1 Update the subcommand list and the planted-mode section (planted.py, docs/testing.md)
