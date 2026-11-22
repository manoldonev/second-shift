# receipt-provenance eval

Grades whether an intake receipt labels each Decision Ledger row with who decided it
(`interviewing-baseline`, "The Decision Ledger" and "The Kind axis"). The failure it looks for: a
choice labeled `codebase-derived`, a "your call" reply not labeled `user-delegated`, and a choice
nobody made that the receipt records as settled.

**Operator-run and model-billed. Never in CI.** CI in this repo is model-free by design. Run it
when the ledger, receipt or Receipt-stage rules change, or when a model generation turns over.
Written against Claude Code CLI 2.1.330 and its `claude plugin eval` subcommand.

## What a run does

- `scaffold.sh` fills the empty workspace through the scaffold of `decision-questions-eval`: the
  same `TICKET.md` and the same snapshot of this repo, with no `.git`, no `.claude/` and no
  `plugins/intake-toolkit/`. It adds `INTERVIEW.md` from `fixture/`.
- `INTERVIEW.md` is a fixed record of one intake session up to the end of the Interview: the stage
  outcomes, each question and each reply of the operator, word for word. It holds no ledger and no
  provenance label. So the decider of every decision is known before the run.
- The session runs `/intake-toolkit:intake 77` and is told to continue at the Receipt stage from
  that record. Intake has no such entry in normal use: the eval adds it. The session writes
  `.claude/pipeline-state/77-ledger.md`.
- Seven graders score the run (`case.yaml`). Six judge the receipt file against the answer key
  below. One checks that the session ran the receipt lint. The run scores the weighted share of
  graders that passed. The case scores the mean of its five runs.

## The answer key

| Decision | What the record shows | Label the receipt must give |
| --- | --- | --- |
| The mechanism that stops the early exit | The operator chose the environment variables. | `user-answered` |
| Which spawned sessions get the environment | The operator chose BUILD only, against the recommendation. | `user-answered` |
| The Bash timeout values | The operator said "Your call." | `user-delegated` |
| A headless line in the build prompt | The operator said "No preference. Go with what you would do." | `user-delegated` |
| Where the environment is set (`spawn()`) | Explore proved it with a command. Nobody was asked. | `codebase-derived` with evidence, or stated inside an operator row |
| The bound the scheduler holds for a build session | Explore proved it with a command. Nobody was asked. | `codebase-derived` with evidence, or stated inside an operator row |
| A new line in the run log, and its wording | The interviewer chose it alone and never asked. | not settled: `deferred` under a declared `OR-n`, or only a declared `OR-n` |
| Whether the build session also gets the variable that turns background tasks off | The operator parked it: its effect on Agent subagents is unknown. | `deferred` under a declared `OR-n`, owner the operator |

No other row may carry `user-answered` or `user-delegated`, except a row about the fan-out skip,
which the operator also made.

## What the score does not show

- The record is clean and written by hand. The eval measures labels when the signal is plain, not
  labels inside a live interview.
- In a live intake the Interview assigns the labels as it runs. Here the session builds the ledger
  from the record at write time. A rule change that moves live labeling may not show.
- `unasked-choice-not-claimed` was reworded after a probe run in which it failed a receipt that
  parked the choice under a declared open region. The reworded text has not judged such a receipt
  yet: the next probe run dropped the choice, which is a true fail. When this grader fails a run,
  read the receipt before you trust the votes.

## Run

Run from the root of a full clone. The scaffold needs the snapshot commit that
`decision-questions-eval/README.md` names.

```bash
export SUBJECT_MODEL=<the model under test>
export JUDGE_MODEL=<the model that judges the llm graders>
claude plugin eval plugins/intake-toolkit --case receipt-provenance-eval \
  --scaffold --allow-tools Bash Write Edit --disallow-tools AskUserQuestion Agent \
  --ablation none --no-publish --keep-temp --threshold 0 \
  --judge-model "$JUDGE_MODEL" --model "$SUBJECT_MODEL"
```

`--threshold 0` keeps the runner's exit code at 0 for a low score: the bar is read from the rows,
not from the exit code. The runner writes its reports to
`plugins/intake-toolkit/evals/results/<timestamp>/`, which git ignores.

A run that ended on an API or usage-limit error scores 0 without grading. Run it again and record
the new run in its place. A run that hit the turn cap or the timeout is kept and scored.

## Checks after a run

**The arm read its own rules.** After the first run of each arm, open that run's trace in the
report. The `Skill` result for `interviewing-baseline` and the read of `receipt.md` must name a
directory inside the tree the command ran from, not an installed copy under your home directory.
If they do not, the score belongs to the wrong rules: stop and fix the run before you record it.

**No tracker call got through.** The trace must hold no `gh` call that succeeded.

**The hand lint.** `--keep-temp` keeps each run's workspace. Lint each receipt with the lint of the
tree the command ran from:

```bash
bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh \
  --receipt <kept workspace>/.claude/pipeline-state/77-ledger.md
```

Its result is outside the score. Record it beside the score, so a receipt the scheduler would
refuse is visible.

## The arms

An arm is this repo at one commit. With no rule change to test, run one arm: the tree that holds
the case. For a rule change:

1. Find the commit before the change: `git rev-parse <the change's commit on main>^`.
2. Add a worktree there: `git worktree add ../before <that commit>`.
3. If that commit does not hold this case, copy `receipt-provenance-eval` and
   `decision-questions-eval` into its `plugins/intake-toolkit/evals/`.
4. Run the command above from `../before`. The "after" arm is the same command from the tree that
   holds the change.

## Reading the score

Without a rule change, the labels pass when the case scores at least 0.90 and each of
`delegated-rows-labeled`, `unasked-choice-not-claimed` and `declined-row-deferred` passes in at
least 4 of 5 runs.

A rule change passes when all of these hold, with five runs per arm, on a fixture the rules were
not tuned on:

1. Each grader the change is meant to move passes in at least 4 of 5 "after" runs.
2. The "after" case score is at least 0.90.
3. No other grader passes in 2 or more fewer runs "after" than "before", and the runs lost, summed
   over all other graders, are at most 2.

This fixture is the one to tune a rewording on, three passes at most. Tuning a rule on a ticket
and grading it on the same ticket proves nothing, so the verdict comes from a second fixture that
stays outside this repo: a ticket and a repo of a consumer, with its own record and key, built by
the same recipe.

Change a grader only for a defect found on a single probe run before the first scored run. Never
change a criterion or a bar after a scored run.

## Recording a run

Add one row per fixture and arm to `BASELINE.md`, in this form:

```
| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | answered-rows-kept | fact-rows-kept | delegated-rows-labeled | unasked-choice-not-claimed | declined-row-deferred | no-extra-human-rows | lint-ran | Hand lint clean |
| 2026-12-01 | tuning | main | 1a2b3c4d | <id> | <id> | 5 | 0.83 | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,2,3) | 3/5 (3,0,3,1,3) | 4/5 (3,3,0,3,3) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 | 5/5 |
```

- **Fixture** is `tuning` (this directory) or `held-out` (the second fixture). A held-out row
  names no consumer, ticket or repo.
- **Arm** is `main`, `before` or `after`. **Commit** is the commit of the tree the command ran
  from. A row measured on a branch commit says so under the table.
- **Subject model** and **Judge model** are full model ids. The report names only the alias each
  was given, so write the id that alias named on the run's date.
- Each LLM grader cell is the runs that passed out of the runs, then the PASS votes of each run
  out of three judge votes, in run order.
- **Hand lint clean** is the runs whose receipt the lint accepts.
- Under the table: the commit that froze the graders, each grader fix the probe forced, the count
  of runs repeated after an API error, and for each failing run of `unasked-choice-not-claimed`
  whether the receipt claimed the choice, dropped it or omitted it.
