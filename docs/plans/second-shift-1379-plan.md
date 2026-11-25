# Plan — a later review lists the findings it saw resolved

## 1. The checker

- [ ] 1.1 Selftest: an approve whose empty `## Findings` holds `None open. 2 resolved, listed in ## Notes.` with two resolved lines in the fold passes; it fails when either count reads 3, when Findings holds a bare `None.`, when the resolved lines have no fold, when the fold has no resolved line, when the fold has no `</details>` line, and on `None open. 0 resolved` (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-3]
- [ ] 1.2 Selftest: an approve whose `## Notes` reach 150 words only through the resolved lines and the two fold lines passes (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-4]
- [ ] 1.3 Selftest: a first-review approve whose empty `## Findings` holds `None.` still passes (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-6]
- [ ] 1.4 Accept the `None open.` line, check the resolved count and the fold shape, and leave the resolved lines and the fold lines out of the Notes count (plugins/dev-pipeline/tools/verdict-check.sh)

## 2. The join

- [ ] 2.1 Selftest: a lane approve with the `None open.` line and a blind blocker joins to a body without that line, and the joined body passes verdict-check (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-5]
- [ ] 2.2 Drop the `None open.` line when the join adds a blind finding, as it drops `None.` (plugins/dev-pipeline/tools/verdict-join.sh)

## 3. The review prompts

- [ ] 3.1 The later-round rules write a resolved line for each resolved finding and later-round note, copy the latest verdict's resolved lines, and remove one while its finding is open again (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md)
- [ ] 3.2 The grammar states the `None open.` line, the resolved fold and the resolved line (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md)
- [ ] 3.3 The style exempts the resolved lines and the fold lines from the 150-word count and the six-sentence limit (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md, plugins/review-toolkit/skills/review-lead/SKILL.md)

## 4. The replay

- [ ] 4.1 Replay the new later-round prompt once on the last needs-work verdict of an earlier lane PR against its next head, and report the draft in the PR body (docs/plans/second-shift-1379-plan.md)
