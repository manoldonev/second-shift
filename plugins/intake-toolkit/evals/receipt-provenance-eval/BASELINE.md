# Baseline

One row per fixture, arm and run set. The row format is in `README.md`, "Recording a run".

| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | answered-rows-kept | fact-rows-kept | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred | no-extra-human-rows | lint-ran | Hand lint clean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-22 | tuning | main | 32b8333c | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.67 | 4/5 (–,3,3,3,3) | 4/5 (–,3,3,3,3) | 4/5 (–,3,3,3,3) | 1/5 (–,0,3,0,0) | 3/5 (–,3,3,3,0) | 4/5 (–,3,3,3,3) | 5/5 | 4/5 |
| 2026-11-22 | held-out | main | a51c410c | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.71 | 4/5 (3,3,–,3,3) | 3/5 (3,2,–,0,3) | 4/5 (3,3,–,3,3) | 3/5 (3,0,–,3,3) | 4/5 (3,2,–,3,3) | 3/5 (3,1,–,3,3) | 4/5 | 3/5 |

A `–` is a run with no receipt file: every file grader failed without a vote. See "Runs with no
receipt file".

## Notes on these rows

- The tuning row was measured on a branch commit. Its skill files equal `main` at a51c410c: the
  branch adds only this case. The held-out row was measured on a worktree at a51c410c with the
  held-out case copied in.
- The subject id is the one the run traces name. The reports name only the alias `sonnet` for the
  judge; the id is what that alias named that day.
- The graders were frozen at 32b8333c, after four single probe runs and before these rows. The
  probes forced four fixes. `lint-ran` no longer counts `--receipt-version`. `declined-row-deferred`
  names the decision as the record asks it. `unasked-choice-not-claimed` checks its PASS form
  first and counts a region with an agent-chosen default as not decided. The held-out
  `answered-rows-kept` no longer requires a row for the split answer.
- No run ended on an API error, so no run was repeated.
- **Hand lint clean** here is the last result of the lint that the session ran. The kept
  workspaces are sealed, so the lint was not run by hand. The held-out receipt of run 1 ended with
  11 violations: its contract surfaces cite open rows, and the replay has no operator to ask.

## Runs with no receipt file

Tuning run 1 and held-out run 3 wrote no file. In every run the harness denied the Write tool for
`.claude/pipeline-state/`. Eight sessions then wrote the file with a shell heredoc. In these two
runs the harness also denied a shell command that creates the directory, and the session tried no
other write. The receipt text is in the trace, in the denied Write call. These two runs measure
the harness, not the labels.

## Hand read

Each failing vote was read against the receipt. The voted score stands as the recorded score. The
hand-read score is what the criteria give when a person applies them to the same text.

| Fixture | Voted score | Hand-read score | Voted per run | Hand-read per run |
| --- | --- | --- | --- | --- |
| tuning | 0.67 | 0.88 | 0.07, 0.80, 1.00, 0.80, 0.67 | 1.00, 0.80, 1.00, 0.80, 0.80 |
| held-out | 0.71 | 0.92 | 1.00, 0.67, 0.00, 0.87, 1.00 | 1.00, 0.80, 0.93, 0.87, 1.00 |

| Target grader | Tuning, voted | Tuning, hand read | Held-out, voted | Held-out, hand read |
| --- | --- | --- | --- | --- |
| delegated-rows-labeled | 4/5 | 5/5 | 4/5 | 5/5 |
| unasked-choice-not-claimed | 1/5 | 2/5 | 3/5 | 4/5 |
| declined-row-deferred | 3/5 | 5/5 | 4/5 | 5/5 |

Tuning:

- Run 1, no file. The receipt text in the trace passes every file grader: both answered rows, both
  delegated rows, both facts with evidence, the declined row, and the unasked choice as a
  `deferred` row under a declared region with an agent-chosen default.
- Runs 2, 4 and 5, `unasked-choice-not-claimed`: true fails. Each receipt dropped the log line as
  an out-of-scope surface and declared no open region for it.
- Run 3, `unasked-choice-not-claimed`: a pass on a receipt that parked the choice under a region
  with an agent-chosen default. This is the form the reworded grader had not judged before.
- Run 5, `declined-row-deferred`: voted 0 of 3; the hand read passes it on the criterion's
  clauses. The row is `deferred`, names a declared region and names the operator as owner. The
  receipt has a real weakness that the criterion does not cover: its region default sets the
  variable and says the operator chose that, although the operator parked exactly that choice.

Held-out:

- Run 2, `unasked-choice-not-claimed`: a true fail, and the failure this eval looks for. A
  `codebase-derived` row states the unasked choice as a settled part of a read's shape.
- Run 2, `no-extra-human-rows`: voted 1 of 3; the hand read passes it. Every human-labeled row is
  about a decision the operator made.
- Run 3, no file. The receipt text in the trace passes every file grader. `lint-ran` fails: the
  session had no file to lint.
- Run 4, `fact-rows-kept`: voted 0 of 3; the hand read leaves the vote. The row of the operator's
  clone decision carries the command that proves the clone fact, but does not state the fact. The
  criterion asks for the fact to be stated.

## Reading against the bar

The bar without a rule change: a case score of at least 0.90, and each target grader passing in at
least 4 of 5 runs.

| Fixture | Case score | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred |
| --- | --- | --- | --- | --- |
| tuning, voted | missed (0.67) | met (4/5) | missed (1/5) | missed (3/5) |
| tuning, hand read | missed (0.88) | met (5/5) | missed (2/5) | met (5/5) |
| held-out, voted | missed (0.71) | met (4/5) | missed (3/5) | met (4/5) |
| held-out, hand read | met (0.92) | met (5/5) | met (4/5) | met (5/5) |

What the rows show, with five runs per fixture: every decision the operator made or gave away got
the right label in every receipt. The miss is the choice that nobody made. Four of ten receipts
recorded it as settled or dropped it without a declared open region.
