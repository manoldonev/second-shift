# Plan — a later review gates only what changed since the last reviewed head

## 1. The last reviewed head and the changed-line set

- [ ] 1.1 Selftest: the tool takes the latest unedited lane verdict with no reason line, by a Bot or the writer account, and writes each line within 3 lines of a hunk of `git diff <reviewed> <head>`, new side (plugins/dev-pipeline/tools/changed-lines-selftest.sh) [AC-1]
- [ ] 1.2 Selftest: with no earlier lane verdict, unreadable comments or an unreadable reviewed sha, the tool writes no changed-line set (plugins/dev-pipeline/tools/changed-lines-selftest.sh) [AC-2]
- [ ] 1.3 Add the tool that finds the last reviewed head and writes the changed-line set (plugins/dev-pipeline/tools/changed-lines.sh)

## 2. The join

- [ ] 2.1 Selftest: with a changed-line set, the join leaves out a plain blocker and a plain note sited outside it, adds one sited inside it, keeps a siteless one, counts the left-out ones, and exits 2 on an unreadable set (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-3]
- [ ] 2.2 Selftest: with no changed-line set, the join adds every unpaired plain finding as today (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-2]
- [ ] 2.3 Add `--changed <file>` to the join and the new count to its machine line, version 4 (plugins/dev-pipeline/tools/verdict-join.sh)

## 3. The checker

- [ ] 3.1 Selftest: an approve whose `## Notes` reaches 150 words only through later-round notes passes (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-5]
- [ ] 3.2 Leave the later-round note lines out of the `## Notes` word count (plugins/dev-pipeline/tools/verdict-check.sh)

## 4. The scheduler and the manual review

- [ ] 4.1 Scenario: a second review round gets the first verdict's reviewed sha and the changed-line set in its prompt and its join, and the first round gets neither (plugins/dev-pipeline/skills/run/run-later-round-selftest.sh) [AC-1]
- [ ] 4.2 The scheduler reads the set before each review and hands it to pass 2 and the join; the later-review prompt block; the build prompt sentence (plugins/dev-pipeline/skills/run/run.sh)
- [ ] 4.3 The manual review does the same in step 2 and step 8; the grammar, style and grounds copies change in lockstep (plugins/dev-pipeline/skills/review/SKILL.md, plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 4.4 The interactive build reads later-round notes as optional (plugins/dev-pipeline/skills/build/SKILL.md)

## 5. The replay

- [ ] 5.1 Replay the new pass 2 once on a later-round head of an earlier lane PR, with the earlier verdict's sha as the base, and show its findings beside the earlier verdict's in the PR body (docs/plans/second-shift-1374-decisions.md)
