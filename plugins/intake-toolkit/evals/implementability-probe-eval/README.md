# implementability-probe eval

Measures whether the probe reports the defects a decision record was deliberately built to hide,
and what the probe adds over a plain session that reads the same two files cold.

**Operator-run and model-billed. Never in CI.** CI in this repo is model-free by design. Run it
when the probe's agent doc changes, or when a model generation turns over. Written against Claude
Code CLI 2.1.330 and its `claude plugin eval` subcommand.

## What a run does

- `scaffold.sh` fills the empty workspace with a snapshot of this repo at commit `b2b4f6e9` and
  three files under `docs/plans/`: the ticket (`fixtures/underspecified-spec.md`), its decision
  record (`fixtures/planted-record.md`) and interview notes (`fixtures/interview-notes.md`).
- The snapshot has no `.git`, no `.claude/`, none of the commit's `docs/plans/`, no
  `plugins/intake-toolkit/evals/`, no `plugins/intake-toolkit/skills/intake/` and no agent file of
  the probe. So a session can read neither the answer keys nor the probe's rules from the workspace.
- The session is handed the ticket and the record. With the plugin, it dispatches
  `intake-toolkit:implementability-probe` on them and ends with the agent's report, unchanged.
  Without the plugin no agent of that name exists, and the session does the job itself from one
  paragraph that says what the agent's `description` line says.
- The record holds four planted defects (`fixtures/planted-defects.md`). The interview notes hold
  two values that exist nowhere else. The session is not handed the notes, so a report that
  repeats one of the values used them.
- Seven graders score a run (`case.yaml`). The run scores the weighted share of graders that passed.
  The case scores the mean of its runs. Three more graders are indicators for the arm with the
  plugin and are not scored.

## Run

Run from the root of a full clone. The scaffold needs commit `b2b4f6e9`: when
`git cat-file -t b2b4f6e9` fails, run `git fetch --unshallow` first.

```bash
export SUBJECT_MODEL=<the model under test>
export JUDGE_MODEL=<the model that judges the llm graders>
export CLAUDE_CODE_EFFORT_LEVEL=high
claude plugin eval plugins/intake-toolkit --case implementability-probe-eval \
  --scaffold --allow-tools Bash --ablation with-without --threshold 0.80 \
  --no-publish --keep-temp \
  --judge-model "$JUDGE_MODEL" --model "$SUBJECT_MODEL" --json <a path>.json
```

The runner runs each arm five times and writes its reports to
`plugins/intake-toolkit/evals/results/<timestamp>/`, which git ignores.

The agent runs at `effort: high`. `CLAUDE_CODE_EFFORT_LEVEL=high` gives the plain session the same
effort.

The scaffold finds the repo from its own path. If every run fails with `scaffold failed` and the
script's stderr says `not a git repo`, the runner started a copy of the script outside the repo.
Then set the default of `SNAPSHOT_REPO` in `scaffold.sh` to the absolute path of your clone for that
run. The runner passes no other environment variable to the script.

## Check a run set before you record it

The exit code alone decides nothing. Exit 1 means a case scored under the threshold, or a run ended
on an API error, or a case failed to load. Exit 2 means the cost ceiling was hit or the credential
was rejected. Read the JSON:

- `partial: true`, or a run whose `error` is an API error, a rate limit or `scaffold failed`: that
  run was not graded. Do not record the set. Run it again whole.
- A run that hit its timeout or its turn cap was still graded. Record the set and count such runs
  under the table. Do not run the set again to get a clean one.

After the first run of each arm, open that run's trace in the report:

- With the plugin, the `Agent` call names `intake-toolkit:implementability-probe` and its result is
  a report. The plugin path in the session's first message is inside the tree the command ran
  from, not an installed copy under your home directory.
- Without the plugin, that `Agent` call fails with `not found` or is not made.
- No tool call in either arm reads `agents/implementability-probe.md`.
- With the plugin, the last message is the agent's report and nothing else.

If one of these does not hold, the score belongs to something else: stop and fix the run.

## What a regression looks like

| Regression | Grader |
| --- | --- |
| Hit count drops: the probe stopped reporting a planted defect | `departure-reported`, `changed-meaning-reported`, `absent-criterion-reported`, `thin-row-fork-reported` |
| The probe asks again for a decision that an `intent` row settled | `departure-kept-off-guess-points` |
| Padding: more than 12 guess-points, or 3 or more that the agent doc excludes | `no-padding`, and the indicator `twelve-or-fewer` |
| Blindness leaks: the report uses the interview notes | `no-blindness-leak` |

The case passes at a score of 0.80 or more for the arm with the plugin. A blindness leak in that
arm voids the run set, whatever its score. The difference between the arms is reported and gates
nothing: at five runs per arm a difference under 0.15 reads as no measured difference.

Class disagreement on its own is **not** a regression and no grader scores it. `human` vs
`codebase` turns on whether the repo actually settles the question, and the probe grounds that
against live code while the answer key was written once. A disagreement the probe defends with a
citation is a better answer than the key's, and the key is what gets corrected.

No criterion and no bar changes after a scored run. A grader changes only for a mechanical defect,
and the change goes under the table in `BASELINE.md`.

## What the comparison does not show

- The agent runs with its own 30-turn cap. The comparison is the agent as shipped against a plain
  session, not the agent doc's text alone.
- The report of the arm with the plugin passes through the session that dispatched the agent.
- The eval measures one round. The Receipt stage of `/intake-toolkit:intake` resumes a report that
  is partial or holds an `unverified` item; the eval does not. The indicator `report-complete`
  counts the runs with no `unverified` item.
- `skills/interviewing-baseline/SKILL.md` stays in the snapshot, because it is the record contract
  an implementer has. It says a settled row is not asked again, so the difference on
  `departure-kept-off-guess-points` is a lower bound.
- `no-blindness-leak` sees only a report that repeats a value from the notes. A session that reads
  the notes and silently drops the guess-points they answer is not detected.
- `fixtures/planted-record.md` is in-sample: the agent doc was changed after a failure on it
  (`BASELINE.md`, the manual runs). A held-out fixture exists and is kept outside this repo, so
  that no session that edits the agent doc can read its key. Its rows are in `BASELINE.md`.

## Recording a run

Add one row per fixture and arm to `BASELINE.md`, in this form:

```
| Date | Fixture | Arm | Commit | Subject model | Judge model | Runs | Case score | departure-reported | departure-kept-off-guess-points | changed-meaning-reported | absent-criterion-reported | thin-row-fork-reported | no-padding | no-blindness-leak | control-reported-covered | Dispatched | Complete | 12 or fewer |
| 2026-12-01 | tuning | with | 1a2b3c4d | <id> | <id> | 5 | 0.87 | 5/5 (3,3,3,2,3) | 4/5 (3,3,0,3,2) | 5/5 (3,3,3,3,3) | 5/5 (3,3,3,3,3) | 4/5 (3,1,3,3,3) | 5/5 (3,3,3,3,3) | 5/5 | n/a | 5/5 | 4/5 | 5/5 |
```

- **Fixture** is `tuning` (the fixture in this directory) or `held-out`.
- **Arm** is `with` or `without`.
- **Commit** is the commit of the tree the command ran from.
- **Subject model** and **Judge model** are full model ids. The report names only the alias each
  was given, so write the id that alias named on the run's date.
- An LLM grader cell is the runs that passed out of the runs, then the PASS votes of each run out
  of three judge votes, in run order. A regex cell is the runs that passed out of the runs.
- `control-reported-covered` exists only in the held-out case and is `n/a` in a tuning row.
- **Dispatched**, **Complete** and **12 or fewer** are the indicators `probe-dispatched`,
  `report-complete` and `twelve-or-fewer`. They are `n/a` in a `without` row.
- Under the table, per run set: the difference between the arms, the count of runs that hit a
  timeout or a turn cap, the count of blindness leaks in the arm without the plugin, and any grader
  change with its commit.
