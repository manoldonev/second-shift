# Plan — the planted corpus scores reviews on what they find

## 1. Path-level truth locations

- [ ] 1.1 corpus-selftest: check accepts a path-level {file, side} location outside every hunk and refuses one with no file (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-1]
- [ ] 1.2 check_case accepts a path-level location; only a ranged location satisfies the in-hunk rule (planted/planted.py)
- [ ] 1.3 b6r1vy gains a path-level location on its missing test file; h9x3cd's test-file range becomes path-level (planted/cases/b6r1vy/case.json, planted/cases/h9x3cd/case.json)
- [ ] 1.4 cmd_verify prints a path-level location without a line range (planted/planted.py)

## 2. Matching and parsing

- [ ] 2.1 score-selftest: on a path-level case the judge sees a path-only blocker, a blocker outside every range on that file and a pathless blocker; a ranged-only case judges no pathless blocker (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-2]
- [ ] 2.2 in_range matches a path-level location on any line, and judge_findings sends pathless blockers on path-level cases (planted/planted.py)
- [ ] 2.3 score-selftest: a path with no line parses, backticks and trailing punctuation strip, and/or parses no path, and a later path:line wins (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-3]
- [ ] 2.4 parse_verdict falls back to the first cleaned token with a slash and an extension (planted/planted.py)

## 3. Controls

- [ ] 3.1 corpus-selftest: check passes with no case d4p7sx, reports control 5, and the mutations run on a surviving case (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-4]
- [ ] 3.2 Replace d4p7sx with a control from a merged dayjs PR under a fresh id (planted/cases/)
- [ ] 3.3 Audit every control on one standard and replace each confirmed unclean one; record the verdicts in the PR body (planted/cases/)

## 4. P1 cases

- [ ] 4.1 corpus-selftest: check reports P1 8 (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-6]
- [ ] 4.2 Four new P1 cases from Multi-SWE-bench instances, each breaking an AC where an unchanged caller meets the new code (planted/cases/)

## 5. Session output

- [ ] 5.1 render-selftest: a fake claude's stdout and stderr land in state/session.stdout and state/session.stderr, the record names both, and a timed-out fake keeps what it wrote (plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh) [AC-7]
- [ ] 5.2 review_one streams the session's stdout and stderr to files under state/ and records both paths (planted/planted.py)

## 6. Docs

- [ ] 6.1 docs/testing.md: the corpus counts and the matching rule (docs/testing.md)
