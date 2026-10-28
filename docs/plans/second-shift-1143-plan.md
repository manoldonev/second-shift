# Plan — keep the consumer PR template first and fold the pipeline sections and verdict rows

## 1. The verdict's folded rows table

- [ ] 1.1 verdict-check passes a folded rows table under a correct summary, and still fails an unscored row or an unknown score inside the fold (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-4] [AC-8]
- [ ] 1.2 verdict-check passes a bare-table verdict, with and without a Summary (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-5]
- [ ] 1.3 verdict-check fails a fold whose summary counts differ from the table, and a fold with no Summary (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-11] [AC-12]
- [ ] 1.4 verdict-check.sh accepts the one-line rows summary, checks its counts, and requires a Summary beside a fold (plugins/dev-pipeline/tools/verdict-check.sh)
- [ ] 1.5 the lockstep check passes with the edited verdict-grammar pair (scripts/check-lockstep-pairs-selftest.sh) [AC-6]
- [ ] 1.6 the verdict-grammar text asks for the folded table in review/SKILL.md and run.sh (plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/run/run.sh)

## 2. The re-check of a posted verdict

- [ ] 2.1 post-review-status posts the status for a folded verdict; --recheck re-posts a passing comment and posts error on a failing one (plugins/dev-pipeline/tools/post-review-status-selftest.sh) [AC-7] [AC-13] [AC-14] [AC-8]
- [ ] 2.2 post-review-status.sh gains --recheck <comment-id>, and review/SKILL.md names it (plugins/dev-pipeline/tools/post-review-status.sh, plugins/dev-pipeline/skills/review/SKILL.md)

## 3. The PR body's one pipeline fold

- [ ] 3.1 run.sh replaces its marker region inside the build's fold in place, rewrites the fold's summary, flags a status not posted, and folds only its own block when no fold encloses it (plugins/dev-pipeline/skills/run/run-block-selftest.sh) [AC-2] [AC-9] [AC-10] [AC-8]
- [ ] 3.2 pr_conventions finds the record link and the baseline inside the fold (plugins/dev-pipeline/skills/run/run-block-selftest.sh) [AC-3]
- [ ] 3.3 write_run_block replaces the region in place, writes the outcome summary, and wraps an unfolded region (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/run/run-selftest.sh)
- [ ] 3.4 the build prompt and build/SKILL.md put the template first and the pipeline sections in one fold (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/build/SKILL.md)
