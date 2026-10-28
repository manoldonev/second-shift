# Plan — the lane review scores a where-the-rule-applies row against every caller

## 1. The lane review prompt

- [ ] 1.1 A `run-rows-selftest.sh` case greps the rendered review prompt `prompt-2.txt` for the reach clause, and fails without it (plugins/dev-pipeline/skills/run/run-rows-selftest.sh) [AC-1] [AC-3]
- [ ] 1.2 Add the reach clause to the review prompt's row scoring, inside the `review-row-reach` lockstep anchor (plugins/dev-pipeline/skills/run/run.sh)

## 2. The by-hand review skill

- [ ] 2.1 A `run-rows-selftest.sh` case runs `check-lockstep-pairs.sh` and finds the two `review-row-reach` copies agree (plugins/dev-pipeline/skills/run/run-rows-selftest.sh) [AC-2]
- [ ] 2.2 Add the same clause to step 6 of the review skill, inside the same anchor (plugins/dev-pipeline/skills/review/SKILL.md)
