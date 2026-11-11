# Plan — a review-lead report can be posted on its PR as a pending review

## 1. The posting script

- [ ] 1.1 Selftest: a joined report whose sha is the PR head, with no pending review, makes one create-review call with no event, that sha as commit_id, the two head lines as lines 1 and 2, every report section, the KB block and the machine line, and no dev block, cost line or blind draft (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-1] [AC-2] [AC-3]
- [ ] 1.2 Selftest: a bare @handle and an @org/team are backticked in the body and in an inline comment, while jdoe@example.com and an @ in inline code or a fenced block are unchanged (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-4]
- [ ] 1.3 Selftest: a Critical finding inside a hunk of base...sha gets one right-side inline comment at its loc() line, and a Warning outside every hunk stays body-only while the create still happens (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-5]
- [ ] 1.4 Selftest: a sha that is a PR commit but not the head posts and prints the moved-on line; a sha outside the PR's commits creates nothing and exits non-zero (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-6]
- [ ] 1.5 Selftest: an existing pending review of the caller's means no create, no delete, a non-zero exit and its id in the output (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-7]
- [ ] 1.6 Selftest: a failing create prints gh's error, exits non-zero, makes one create call only and never calls gh-bot.sh (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-8]
- [ ] 1.7 Selftest: across every case the fake gh records no statuses call and no write besides the one review create (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-9]
- [ ] 1.8 Selftest: a report that never went through the join has no machine line and is posted with both head lines (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-10]
- [ ] 1.9 Write post-pending-review.sh, with loc() held as a lockstep pair with verdict-join.sh (plugins/review-toolkit/scripts/post-pending-review.sh, plugins/dev-pipeline/tools/verdict-join.sh)

## 2. The join keeps the head lines

- [ ] 2.1 Selftest: verdict-join --format report keeps a report's reviewed-by line 1 and reviewed line 2 unchanged (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-13]

## 3. review-lead's skill

- [ ] 3.1 Report structure: line 2 `reviewed: <sha>` in dispatch mode (plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 3.2 The void path: a Routing void starts no plain review; a later void runs no join and shows the blind draft labeled as the blind review alone (plugins/review-toolkit/skills/review-lead/SKILL.md)
- [ ] 3.3 The final offer step: one AskUserQuestion, the script run on yes, and the no-offer messages (plugins/review-toolkit/skills/review-lead/SKILL.md)
