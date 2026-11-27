# Plan — the no-progress stop and the ticket amend

## 1. The no-progress stop

- [ ] 1.1 Scenario case: round 1 gets needs-work, the round-2 build pushes nothing, and the run ends `no-progress` with rc 1, no second check run and no second review; the detail line and the PR run block carry the verdict URL, each open finding's id with its first sentence, and the recovery; a `--resume` launch whose round-1 build pushes nothing still gets a review (plugins/dev-pipeline/skills/run/run-later-round-selftest.sh) [AC-1] [AC-2] [AC-3]
- [ ] 1.2 Record the sha, the URL and the findings of each bound verdict; after a collected build, stop with `no-progress` when the pushed head is still that sha; append the detail to the run notes (plugins/dev-pipeline/skills/run/run.sh)
- [ ] 1.3 List `no-progress` in the run.sh header exit table and the run SKILL.md rc-1 row (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/run/SKILL.md)

## 2. The ticket amend

- [ ] 2.1 Move the pause-and-ask cases out of the rows slice into their own scenario slice, unchanged (plugins/dev-pipeline/skills/run/run-rows-selftest.sh, plugins/dev-pipeline/skills/run/run-pause-selftest.sh)
- [ ] 2.2 Assert that the `build-paused` detail tells the operator to amend the ticket when the answer departs from it (plugins/dev-pipeline/skills/run/run-pause-selftest.sh) [AC-5]
- [ ] 2.3 Add the amend sentence to the `build-paused` detail line (plugins/dev-pipeline/skills/run/run.sh)
- [ ] 2.4 Add the amend step to the handoff pause branch of the build prompt and to build/SKILL.md step 3, with the jira `writes: false` fallback (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/build/SKILL.md)
- [ ] 2.5 Add the `Departs from` sentence to a build-time departure row, in the build prompt's record rules and in build/SKILL.md step 3 (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/build/SKILL.md)
