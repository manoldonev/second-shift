# Baseline

One row per arm and run set. The row format is in `README.md`, "Recording a run".

| Date | Arm | Commit | Subject model | Judge model | Runs | Case score | questions-are-grounded | primary-decision-framed | secondary-decisions-framed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-22 | before | b2b4f6e9 | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.67 | 5/5 (3,3,3,3,3) | 0/5 (0,0,0,0,0) | 5/5 (3,3,3,3,3) |
| 2026-11-22 | after | 93b09385 | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.73 | 5/5 (3,3,3,3,3) | 1/5 (0,1,3,1,1) | 5/5 (3,3,3,3,3) |
| 2026-11-22 | after | 68ef736a | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.93 | 5/5 (3,3,3,3,3) | 4/5 (3,3,3,0,3) | 5/5 (3,3,3,3,3) |

The reports of 2026-11-22 name the aliases `opus` and `sonnet`. The ids are what those aliases named
that day.

The two "after" rows were measured on the pull request's branch, and a squash merge leaves both
commits off `main`. They come before commit 3343293c, which anchored `read-the-scheduler` on a call
that reads the file and changed rule 6, and before the commit that anchored that grader on
`skills/run/run.sh`. No "after" row is scored on the tree that merges.
