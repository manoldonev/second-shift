# discovery-recall eval

Measures how many of the code facts that change a ticket a `plan-interview` session finds before it
asks its questions. The measure is recall: the share of answer-key facts a run names.

**Operator-run and model-billed. Never in CI.** CI in this repo is model-free by design. Run it
before and after a change to exploration, or when a model generation turns over. Written against
Claude Code CLI 2.1.330 and its `claude plugin eval` subcommand.

The case measures `plan-interview` only. It does not measure `/intake` or its fan-out: on a pasted
ticket, Requirements asks the operator whether to file it and waits, and Explore starts the
interview while the fan-out still runs, so a headless run ends before the fan-out returns.

## What a run does

- `scaffold.sh` fills the empty workspace with `TICKET.md` (from `fixture/`) and a snapshot of this
  repo at commit `3f3e9af5`, the commit the ticket was filed against. The snapshot has no `.git`,
  no `.claude/` and no `plugins/intake-toolkit/`. The fixture and the snapshot are the ones of
  `decision-questions-eval`.
- The session runs `plan-interview` on `TICKET.md` without `AskUserQuestion`. It ends its turn with
  one message and two numbered lists: under `## Facts from the code`, the facts it would record as
  `codebase-derived` rows with their evidence; under `## Questions`, every question the whole
  interview would ask. The prompt does not say what a fact is, so it adds no exploration
  instruction that the skill lacks.
- `case.yaml` grades the run:
  - one `fact-<slug>` grader per answer-key fact. It passes when the final message names the
    problem the fact states, in either list, not only its topic;
  - `no-false-premise`, which fails when the message states a false premise of the ticket as true;
  - `read-the-scheduler` and `no-plan-written`, as in `decision-questions-eval`;
  - `stayed-in-snapshot`, which fails when a tool input names `intake-toolkit/evals` or
    `second-shift-908-decisions`.

The run score mixes recall with the other graders. It is not the measure.

## Warning: the answer key is inside the plugin under test

The answer key lives only in the `fact-` graders' criteria in `case.yaml`. The scaffold keeps it out
of the snapshot, but the runner loads `plugins/intake-toolkit` from the tree the command ran from
and names that path to the session. A session that walks out of its snapshot can read `case.yaml`,
an earlier result, or the fixture ticket's decision record in `docs/plans/`. `stayed-in-snapshot`
catches the paths it names. A read through any other path goes unseen.

## Run

Run from the root of a full clone. The scaffold needs commit `3f3e9af5`: when
`git cat-file -t 3f3e9af5` fails, run `git fetch --unshallow` first.

```bash
export SUBJECT_MODEL=<the model under test>
export JUDGE_MODEL=<the model that judges the llm graders>
claude plugin eval plugins/intake-toolkit --case discovery-recall-eval \
  --scaffold --allow-tools Bash --disallow-tools AskUserQuestion \
  --ablation none --no-publish \
  --judge-model "$JUDGE_MODEL" --model "$SUBJECT_MODEL"
```

The runner writes its reports to `plugins/intake-toolkit/evals/results/<timestamp>/`, which git
ignores. Below, `<result.json>` is the result JSON in that directory.

The scaffold finds the repo from its own path. If every run fails with `scaffold failed` and the
script's stderr says `not a git repo`, the runner started a copy of the script outside the repo.
Then set the default of `SNAPSHOT_REPO` in `scaffold.sh` to the absolute path of your clone for that
run.

## Check each run before you read it

1. **The arm reads its own rules.** After the first run of each arm, open its trace. Find the
   `Skill` call for `interviewing-baseline`. Its result names the skill's base directory. That
   directory must be inside the tree the command ran from, not an installed copy under your home
   directory. If it is not, stop and fix the run before you record it.
2. **The run stayed in its snapshot.** Discard every run that fails `stayed-in-snapshot`, and run
   the case again for the missing runs. Its recall counts facts the session could have read from
   the answer key.

## Read recall

Recall per run is the `fact-` graders passed divided by the `fact-` graders, read from the result
JSON. A run with no `fact-` graders gives `null`:

```bash
jq -c '[.cases[].arms.with[] | [.graders[]? | select(.name | startswith("fact-"))] | if length == 0 then null else ((map(select(.passed == true)) | length) / length) end] | {recall: ., mean: (map(numbers) | if length == 0 then null else add / length end)}' <result.json>
```

A longer facts list can raise recall, so record the length of each run's facts list too. The length
is the count of top-level numbered items under the first heading, `## Facts from the code`, of the
final message. The final message is the `result` event at the end of each run's trace. Each run
object in the result JSON carries its `tracePath`, under `/private/tmp/e-*/out/`, so count soon
after the run, before the system clears that directory:

```bash
jq -r '.cases[].arms.with[].tracePath' <result.json> | while IFS= read -r t; do
  jq -s 'map(select(.type == "result")) | last | .result // "" | split("\n") as $l | ([$l | to_entries[] | select(.value | test("^#{1,6}[ \t]*Facts from the code[ \t]*$")) | .key] | first) as $s | if $s == null then null else ($l[$s + 1:] | (map(test("^#{1,6}[ \t]")) | index(true)) as $e | (if $e == null then . else .[:$e] end) | map(select(test("^[0-9]+[.)][ \t]"))) | length) end' "$t"
done
```

`null` means the message has no `## Facts from the code` heading.

Five runs per arm show only a recall gap near 0.2 or more. A smaller gap between two arms is inside
the run-to-run variance.

`no-false-premise` checks only the premises its criteria list. The judge cannot read the snapshot,
so a false claim about any other line passes.

## The answer key

The key was drafted from the fixture ticket's decision record
(`docs/plans/second-shift-908-decisions.md`) and the diff of the change that closed the ticket, not
from a fresh reading of the code. A fact entered the key only when a line at `3f3e9af5` anchors it.
A fact whose force comes from documented Claude Code behavior entered when its criteria state that
behavior. A fact with no line in the snapshot stayed out: a measurement, a `.claude/` file,
`plugins/intake-toolkit/`, or git history alone. The ticket's off-by-one `run.sh:475` (the function
is at line 476) is not in the key: a grader on it rewards copying the ticket.

Criteria, weights and any pass bar are fixed before the first scored run. A probe run may fix a
grader defect. It never moves a bar.

To check an anchor, print its line at the snapshot commit:

```bash
git show 3f3e9af5:<path> | sed -n <n>p
```

| Grader | Anchors at `3f3e9af5` |
| --- | --- |
| `fact-resume-breaks-fresh-process` | `plugins/dev-pipeline/skills/run/run.sh` 42; `plugins/dev-pipeline/skills/run/run-selftest.sh` 144 |
| `fact-repo-settings-override-env` | `plugins/dev-pipeline/skills/run/run.sh` 243 |
| `fact-timeouts-do-not-stop-chosen-background` | `CLAUDE.md` 93-94 |
| `fact-claude-md-note-conflicts` | `CLAUDE.md` 93-94 |
| `fact-review-needs-background` | `plugins/dev-pipeline/skills/run/run.sh` 451, 467-468 |
| `fact-review-background-wait` | `plugins/dev-pipeline/skills/run/run.sh` 190, 467-468 |
| `fact-timeout-inside-the-bound` | `plugins/dev-pipeline/skills/run/run.sh` 216, 245 |
| `fact-cap-accepts-fractions` | `plugins/dev-pipeline/skills/run/run.sh` 185-186, 189 |
| `fact-build-allowlist-has-no-workflow` | `plugins/dev-pipeline/skills/run/run.sh` 458 |
| `fact-bg-spawn-history` | `CHANGELOG.md` 904; `plugins/dev-pipeline/skills/run/run.sh` 712 |
| `no-false-premise` | `plugins/dev-pipeline/skills/run/run.sh` 42, 243 |

## A held-out case

The fixture is in-sample: the skill's rules were fitted to this ticket once. A held-out case on a
consumer ticket shows whether a gain carries over. It never enters this repo.

1. Make a case folder outside every repo.
2. Write a scaffold that snapshots the consumer repo at the commit the ticket was scoped against,
   without `.claude/` and without tracked secrets, and copies the ticket in as `TICKET.md`.
3. Write the answer key from the scoping before any run: one `fact-<slug>` grader per fact, and
   `no-false-premise` with the premises the code contradicts. Copy the other graders and the run
   shape from this `case.yaml`.
4. For each arm, copy the case folder into `plugins/intake-toolkit/evals/` of a worktree of that
   arm and run the command above from that worktree.
5. Keep the results and the traces in the case folder.

## Recording a run

Add one row per arm to `BASELINE.md`, in this form:

```
| Date | Case | Arm | Commit | Subject model | Judge model | Runs | Recall per run | Recall mean | Facts-list length per run | no-false-premise |
| 2026-12-01 | fixture | before | 1a2b3c4d | <id> | <id> | 5 | 0.4, 0.5, 0.3, 0.4, 0.5 | 0.42 | 7, 9, 6, 8, 9 | 5/5 (3,3,3,2,3) |
```

- **Case** is `fixture` or `held-out`. A held-out row names no consumer and no ticket.
- **Arm** is `before` or `after`. **Commit** is the commit of the tree the command ran from.
- **Subject model** and **Judge model** are full model ids. The report names only the alias each
  was given, so write the id that alias named on the run's date.
- **Runs** counts the runs kept after the checks above. Name each discarded run under the table.
- **no-false-premise** is the runs that passed out of the runs, then the PASS votes of each run out
  of three judge votes, in run order.
