# decision-questions eval

Grades the questions `plan-interview` would ask on one real ticket. A decision question passes
when it carries its reason with a code location, its options, each option's consequence and a
recommendation (`interviewing-baseline`, loop rules 3 and 4).

**Operator-run and model-billed. Never in CI.** CI in this repo is model-free by design. Run it
when the interview loop rules change, or when a model generation turns over. Written against
Claude Code CLI 2.1.330 and its `claude plugin eval` subcommand.

## What a run does

- `scaffold.sh` fills the empty workspace with `TICKET.md` (from `fixture/`) and a snapshot of this
  repo at commit `3f3e9af5`, the commit the ticket was filed against. The snapshot has no `.git`,
  no `.claude/` and no `plugins/intake-toolkit/`, so the only interview rules a run can read are
  the ones of the plugin under test.
- The session runs `plan-interview` on `TICKET.md` without `AskUserQuestion`. It ends its turn with
  every question the whole interview would ask, numbered, and answers none.
- Five graders score the run (`case.yaml`). The run scores the weighted share of graders that
  passed. The case scores the mean of its five runs.

## Run

Run from the root of a full clone. The scaffold needs commit `3f3e9af5`: when
`git cat-file -t 3f3e9af5` fails, run `git fetch --unshallow` first.

```bash
export SUBJECT_MODEL=<the model under test>
export JUDGE_MODEL=<the model that judges the llm graders>
claude plugin eval plugins/intake-toolkit --case decision-questions-eval \
  --scaffold --allow-tools Bash --disallow-tools AskUserQuestion \
  --ablation none --no-publish \
  --judge-model "$JUDGE_MODEL" --model "$SUBJECT_MODEL"
```

The runner writes its reports to `plugins/intake-toolkit/evals/results/<timestamp>/`, which git
ignores.

The scaffold finds the repo from its own path. If every run fails with `scaffold failed` and the
script's stderr says `not a git repo`, the runner started a copy of the script outside the repo.
Then set the default of `SNAPSHOT_REPO` in `scaffold.sh` to the absolute path of your clone for that
run. The runner passes no other environment variable to the script.

## The "before" arm

The "before" score comes from the rules as they were before the change under test.

1. Find the commit before the change: `git rev-parse <the change's commit on main>^`.
2. Add a worktree there: `git worktree add ../before <that commit>`.
3. Copy this case directory into it:
   `cp -R plugins/intake-toolkit/evals/decision-questions-eval ../before/plugins/intake-toolkit/evals/`.
4. Run the command above from `../before`.

The "after" arm is the same command from the tree that holds the change.

## Check that an arm reads its own rules

After the first run of each arm, open that run's trace in the report. Find the `Skill` call for
`interviewing-baseline`. Its result names the skill's base directory. That directory must be inside
the tree the command ran from, not an installed copy under your home directory. If it is not, the
score belongs to the wrong rules: stop and fix the run before you record it. `plan-interview` makes
no `Skill` call: it loads as the prompt's slash command, from the same plugin.

## Reading the score

The rule change passes when the "after" score is at least 0.90 and at least 0.20 above the "before"
score, with five runs per arm. On a miss, reword the rules and run the "after" arm again, three
rewording passes at most. After a third miss, revert every skill-file change of that rule change
and keep this eval.

## Recording a run

Add one row per arm to `BASELINE.md`, in this form:

```
| Date | Arm | Commit | Subject model | Judge model | Runs | Case score | questions-are-grounded | primary-decision-framed | secondary-decisions-framed |
| 2026-12-01 | before | 1a2b3c4d | <id> | <id> | 5 | 0.42 | 4/5 (3,3,2,3,1) | 0/5 (0,1,0,0,1) | 2/5 (2,1,2,0,1) |
```

- **Arm** is `before` or `after`.
- **Commit** is the commit of the tree the command ran from.
- **Subject model** and **Judge model** are full model ids. The report names only the alias each
  was given (`suite.modelOverride`, `suite.judgeModel`), so write the id that alias named on the
  run's date.
- A row measured on a branch commit says so under the table, with the later commits that changed
  a grader or a rule: a squash merge leaves that commit off `main`.
- Each LLM grader cell is the runs that passed out of the runs, then the PASS votes of each run out
  of three judge votes, in run order.
