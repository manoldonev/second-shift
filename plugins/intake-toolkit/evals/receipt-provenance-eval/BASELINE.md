# Baseline

One row per fixture, arm and run set. The row format is in `README.md`, "Recording a run".

## The baseline

| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | answered-rows-kept | fact-rows-kept | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred | no-extra-human-rows | lint-ran | Hand lint clean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-22 | tuning | main | f12cdaa9 | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.76 | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 1/5 (0,2,0,0,0) | 2/5 (2,3,0,0,0) | 5/5 (3,2,3,3,3) | 5/5 | 5/5 |
| 2026-11-22 | held-out | main | a51c410c | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 1.00 | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,2,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 | 3/5 |

### Notes on these rows

- The tuning row was measured on a branch commit. Its skill files equal `main` at a51c410c: the
  branch adds only this case. The held-out row was measured on a worktree at a51c410c with the
  held-out case copied in.
- The subject id is the one the run traces name. The reports name only the alias `sonnet` for the
  judge; the id is what that alias named that day.
- The graders' criteria, weights and bars were frozen at 32b8333c, after four single probe runs.
  The probes forced four fixes. `lint-ran` no longer counts `--receipt-version`.
  `declined-row-deferred` names the decision as the record asks it. `unasked-choice-not-claimed`
  checks its PASS form first and counts a region with an agent-chosen default as not decided. The
  held-out `answered-rows-kept` no longer requires a row for the split answer.
- After the first rows below, f12cdaa9 moved the receipt's path out of `.claude/`. It changed the
  graders' file path and two lines of the system prompt, and no criterion. One probe run per
  fixture confirmed that the session writes the file with no denied call.
- In all ten runs the skill's base directory and `receipt.md` were inside the tree under test, no
  tool call was denied, and no `gh` call was made. No run ended on an API error.
- **Hand lint clean** is the last result of the lint that the session ran. The kept workspaces are
  sealed, so the lint was not run by hand. Two held-out receipts ended with violations: their
  contract surfaces cite open rows, and the replay has no operator to ask.

### Hand read

Each failing vote was read against the receipt. The voted score stands as the recorded score. The
hand-read score is what the criteria give when a person applies them to the same text.

| Fixture | Voted score | Hand-read score | Voted per run | Hand-read per run |
| --- | --- | --- | --- | --- |
| tuning | 0.76 | 0.84 | 0.80, 1.00, 0.67, 0.67, 0.67 | 0.80, 1.00, 0.80, 0.80, 0.80 |
| held-out | 1.00 | 1.00 | 1.00, 1.00, 1.00, 1.00, 1.00 | the same |

| Target grader | Tuning, voted | Tuning, hand read | Held-out, voted | Held-out, hand read |
| --- | --- | --- | --- | --- |
| delegated-rows-labeled | 5/5 | 5/5 | 5/5 | 5/5 |
| unasked-choice-not-claimed | 1/5 | 1/5 | 5/5 | 5/5 |
| declined-row-deferred | 2/5 | 5/5 | 5/5 | 5/5 |

Tuning:

- Runs 1, 3, 4 and 5, `unasked-choice-not-claimed`: true fails. Each receipt dropped the log line
  as an out-of-scope surface and declared no open region for it. Run 2 parked it under a region
  with an agent-chosen default and passed.
- Runs 3, 4 and 5, `declined-row-deferred`: voted 0 of 3 each; the hand read passes all three. In
  each receipt the row about the variable is `deferred`, names OR-1, OR-1 is declared, and the row
  names the operator as owner. Run 1 has the same form and got 2 of 3 votes. The runner shows no
  judge reasoning, so the cause of these votes is not known. On this fixture, read the receipt
  before you trust a fail from this grader.

Held-out: no failing vote. All five receipts parked the unasked choice under a declared open
region.

### Reading against the bar

The bar without a rule change: a case score of at least 0.90, and each target grader passing in at
least 4 of 5 runs.

| Fixture | Case score | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred |
| --- | --- | --- | --- | --- |
| tuning, voted | missed (0.76) | met (5/5) | missed (1/5) | missed (2/5) |
| tuning, hand read | missed (0.84) | met (5/5) | missed (1/5) | met (5/5) |
| held-out, voted | met (1.00) | met (5/5) | met (5/5) | met (5/5) |

What the rows show, with five runs per fixture: every decision the operator made or gave away got
the right label in every receipt. The miss is the choice that nobody made, on the tuning fixture
only: four of five receipts dropped it without a declared open region. On the held-out fixture all
five receipts declared it open.

## First rows, measured with the write denial

These rows are not the baseline. In every one of these runs the runner denied the Write tool for
`.claude/pipeline-state/`. Eight sessions then wrote the file with a shell heredoc. In tuning run 1
and held-out run 3 the runner also denied a shell command that creates the directory, and the
session wrote no file: every file grader failed without a vote, shown as `–`.

| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | answered-rows-kept | fact-rows-kept | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred | no-extra-human-rows | lint-ran | Hand lint clean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-22 | tuning | main | 32b8333c | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.67 | 4/5 (–,3,3,3,3) | 4/5 (–,3,3,3,3) | 4/5 (–,3,3,3,3) | 1/5 (–,0,3,0,0) | 3/5 (–,3,3,3,0) | 4/5 (–,3,3,3,3) | 5/5 | 4/5 |
| 2026-11-22 | held-out | main | a51c410c | claude-opus-5-5 | claude-sonnet-5-5 | 5 | 0.71 | 4/5 (3,3,–,3,3) | 3/5 (3,2,–,0,3) | 4/5 (3,3,–,3,3) | 3/5 (3,0,–,3,3) | 4/5 (3,2,–,3,3) | 3/5 (3,1,–,3,3) | 4/5 | 3/5 |

Hand-read scores of these rows: tuning 0.88, held-out 0.92. The receipt text of the two runs with
no file is in the trace, in the denied Write call, and it passes every file grader.

Hand-read notes on these rows:

- Tuning runs 2, 4 and 5, `unasked-choice-not-claimed`: true fails, the same form as above.
- Tuning run 5, `declined-row-deferred`: voted 0 of 3; the hand read passes it on the criterion's
  clauses. The receipt's region default sets the variable and says the operator chose that,
  although the operator parked exactly that choice. The criterion does not cover this.
- Held-out run 2, `unasked-choice-not-claimed`: a true fail, and the failure this eval looks for.
  A `codebase-derived` row states the unasked choice as a settled part of a read's shape. It is
  the one such receipt in the twenty runs of both sets.
- Held-out run 2, `no-extra-human-rows`: voted 1 of 3; the hand read passes it.
- Held-out run 4, `fact-rows-kept`: voted 0 of 3; the hand read leaves the vote. The row of the
  operator's clone decision carries the command that proves the fact, but does not state the fact.
