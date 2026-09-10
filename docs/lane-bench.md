# The lane bench

[`docs/consumer-eval.md`](consumer-eval.md) asks whether a release is better or worse to use than
the last one, and answers it with four numbers and the maintainer's judgment. It is deliberately
un-automated, and it is deliberately about a *release*. It cannot answer the question that comes
up every time a plugin, a skill, a reviewer agent or a gate is proposed for deletion: **would
cutting this make the lane worse, and by how much?**

That question has, until now, been settled by argument. The lane bench settles it with a measured
delta against a fixed control: replay a fixed corpus of tickets through the pipeline once per
**harness arm**, on a synthetic repo built for the purpose, and score each run against a hidden
acceptance-test overlay and a list of seeded defects. The score is deterministic — two mechanical
detectors per defect, no judge model — so a cell scored today and re-scored next month gives the
same number.

**Everything measured happens outside this repository.** The corpus, the substrate, the hidden
tests, the seeded defects, the pre-registration and the result rows all live privately. This
repository carries the protocol, the terminal-class map, and the scorer.

## The anonymization rule

The measured substrate and the bench that drives it are **private repositories, named in
second-shift artifacts only as "the private eval substrate"**. No issue, comment, PR, commit or
document here names a consumer repository, an organization, or a GitHub App — not the substrate's,
not a real consumer's. The concrete URLs live in the operator's local receipts. This rule binds
the artifacts of the bench's own development as much as its results.

## The arm definition

An **arm** is a git worktree of second-shift at a commit, loaded into the lane's payload sessions
with `--setting-sources ''` and one `--plugin-dir` per plugin directory in that worktree. Three
kinds:

| arm           | what it is                                                                                                                         |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **control**   | the full kit at the series' pinned second-shift commit. Every delta is measured against this.                                      |
| **skeleton**  | `dev-pipeline` + `audit-toolkit` from the control worktree, and nothing else. A fixed floor: the least kit that still runs a lane. |
| **candidate** | any second-shift ref — a branch that trims one skill, deletes one agent, cuts a plugin, or rewrites a gate.                        |

The arm is a **ref**, not a plugin selection. Plugin-grain arms were considered and rejected:
without skill or agent grain underneath them they answer nothing a `git diff` does not, and a
branch expresses any cut a plugin list can.

`--setting-sources ''` removes user and project permission grants and settings-declared hooks
**in every arm alike**. That is a shared confound, not a bias, and it is registered as one in the
pre-registration.

## The corpus obligation

**Seven tickets, fixed in role, replayed every series.** Roles 1 through 7 bind in this order, so
a slot is comparable against itself across arms rather than only in aggregate:

| role | what it must exercise                                                                           |
| ---- | ----------------------------------------------------------------------------------------------- |
| 1    | the happy path — a single-round pass, end to end                                                |
| 2    | a seeded ambiguity that must cost a pause-and-ask, not a guess                                  |
| 3    | a bug carrying a reproduction and a hidden regression test                                      |
| 4    | a multi-file cross-module change carrying seeded defects, for review depth                      |
| 5    | a change whose obvious implementation touches a file the substrate's policy freezes             |
| 6    | a ticket whose body contradicts its receipt, so the lane must reconcile or record an intent gap |
| 7    | a change needing existing-state migration at the stack edge                                     |

Each ticket carries a **fixture receipt** — intake is done once, outside the measured run, so no
cell measures the interview — a **hidden-test overlay**, and a **seeded-defect list**. All three
live in the bench repo. **No ref of the substrate contains a hidden test or a defect list**: an
arm session that could read the answer sheet would be scoring itself.

**Each cell files a fresh issue.** Lane state is keyed on the issue number and none of it is
deleted, so a reused issue would report series-to-series elapsed time as run time and the figure
would still look like a run — the same trap `docs/consumer-eval.md` names for its own corpus.

## The gold

Two mechanical detectors, no judge model.

- **Build correctness** is the hidden-test overlay, copied onto the PR head and run there. The
  overlay's own `run.sh` is the verdict channel: it prints one `TEST <id> PASS|FAIL` line per
  hidden test. A per-test channel is the point — the substrate's configured `test` command
  reports a single exit code, which cannot say *which* hidden test a defect broke, and the
  detector pair below needs exactly that.
- **Review depth** is the seeded-defect list, TSV, one row per defect:
  `id, file, description, test_id, verdict_regex`. Each defect carries **its own detector pair**:
  `test_id` names a hidden test that fails while the defect is present, and `verdict_regex` is an
  extended regex over verdict-record text that matches when a reviewer names it. `defects_at_head`
  counts the first; `defects_named` counts the second, across **every committed version** of the
  verdict record on the lane branch, so a defect named in round 1 and dropped from round 2's
  record still counts.

The two detectors are independent by design. A cell can leave a defect in the code and still have
a reviewer name it; a cell can fix a defect no reviewer mentioned. Conflating them into one score
would make both unreadable.

## The pinned-base recipe

Unchanged from [`docs/consumer-eval.md`'s](consumer-eval.md#the-pinned-base-recipe): cut an eval
base branch in the substrate from the pinned substrate commit; write an alternate config differing
from the committed one in **exactly** `topology.repos.<host>.baseBranch`; select it with
`SECOND_SHIFT_CONFIG`. The substrate's default branch is neither modified nor rewound. Every
launch passes the build model, the review model and the round cap explicitly, never by default.

## The metrics

Each has one exact source. Nothing is estimated and nothing is inferred from a figure of a
different shape.

| metric                         | exact source                                                                                                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `terminal_slug`                | the `terminal` row of the run's `<stateDir>/<issue>-lean-launches.tsv`.                                                           |
| `terminal_class`               | that slug, through [`tools/lane-bench-classes.tsv`](../tools/lane-bench-classes.tsv).                                             |
| `rounds`                       | the committed verdict record's `rounds:` header key.                                                                              |
| `wall_min`                     | the launch ledger's `launch` row to its `terminal` row.                                                                           |
| `pr_head_sha`                  | `gh pr list --head <branchPrefix><issue>`'s `headRefOid`, read at scoring time.                                                   |
| `tests_passed` / `tests_total` | `PASS` lines and `TEST` lines of the overlay's `run.sh`, at that head.                                                            |
| `defects_at_head`              | seeded defects whose `test_id` line reads `FAIL` at that head.                                                                    |
| `defects_named`                | seeded defects whose `verdict_regex` matches any committed version of the verdict record on the lane branch.                      |
| `review_catch`                 | `defects_named/<defects seeded>`, written as that literal fraction; **`n/a`** when no verdict record exists on the branch at all. |

`review_catch` is `n/a`, never `0/n`, for an arm with no reviewer — every cell of an arm without
`review-toolkit` looks like that, and `0/n` would claim a reviewer looked and missed.

**A cell is scored on its PR, not on its class.** If exactly one PR exists on the lane branch it
is overlaid and scored whatever the lane terminated as: a `pr-unapproved` cell's diff is still a
diff. Only PR *presence* decides whether the score columns are written.

**Empty is not zero.** A cell with no PR gets empty score columns; so does an `unscorable` one. A
zero is the measurement that code failed the hidden tests, and no code was measured in either case.

## The results row

One TSV row per cell, in the bench repo, nineteen columns:

```
cell_id  ticket_role  arm  repeat  harness_sha  cli_version  build_model  review_model
terminal_slug  terminal_class  rounds  wall_min  pr_head_sha  tests_passed  tests_total
defects_at_head  defects_named  review_catch  scored_at
```

`cell_id` is `t<role>-<arm>-r<repeat>` — `t4-control-r2`. `build_model` and `review_model` carry
**resolved model ids**, read from the payload transcript, never an alias: `opus` moves with
releases, and a series that recorded the alias could not tell a model change from a kit change.

Columns 1 through 12 are written by the runner; **13 through 19 are the scorer's**, and
`tools/lane-bench.sh score` writes only those. Re-scoring a cell overwrites them and refreshes
`scored_at`; it never touches the columns that identify the cell. `score` needs the cell's issue
number as an input (`--issue`): the row does not carry it and the cell id does not encode it.

## Terminal classes

Six: `approved`, `paused`, `no-pr`, `pr-unapproved`, `lane-error`, `unscorable`.

The per-slug map is **data**, not prose:
[`tools/lane-bench-classes.tsv`](../tools/lane-bench-classes.tsv). It is not duplicated here,
because a second copy would be a paragraph nothing can check. The file covers the lane
scheduler's **full slug vocabulary**, and `tools/lane-bench-selftest.sh` holds that claim to
account: it derives the vocabulary out of the shipped `orchestrate-lean.sh` call sites and reds
when the table and the scheduler disagree in either direction, or when the derivation itself stops
matching the scheduler's shape.

Two families need a fact beyond the slug, and carry it in the row's `condition` column:
`build-no-pr` is `paused` with a milestone-1 `pause-and-ask` row in the progress record and
`no-pr` without one, and the five verdict-side stops are `pr-unapproved` with a PR on the branch
and `no-pr` without. `review-paused` — the review handed the round back with an unratified
`pause-and-ask` intent-gap record and no verdict (P9) — is `paused` from the slug alone. A slug
the table does not list is `lane-error` — a cell is re-run, not scored,
on a class the bench cannot read.

`lane-error` cells are **re-run once with a fresh issue**; a second `lane-error` is recorded and
the operator is told. Every other class is recorded as it stands.

## The two tiers, and the cost bound

| tier      | shape                                          | what it is for            |
| --------- | ---------------------------------------------- | ------------------------- |
| **smoke** | 3 tickets (roles 1, 4, 6) × 1 repeat = 3 cells | direction                 |
| **full**  | 7 tickets × 3 repeats = 21 cells               | a keep-or-revert decision |

A candidate whose smoke delta sits inside the pre-registered noise band is **not promoted to
full** unless the operator says why.

**The bound is the operator's subscription rate limit, not money.** Every cell runs on the
subscription; none is API-billed. So cells run **sequentially**, one lane at a time — concurrent
lanes on one machine contend for CPU, the selftest sweep and the tracker rate limit, and a lane
assumes it is the only run on the machine. Each cell is launched with `--max-rounds 2`. Cells are
idempotent by cell id and the matrix is resumable, because a rate limit or a sleeping machine will
interrupt it.

A series baseline is control and skeleton at the full tier: 7 × 2 × 3 = **42 lane runs**. Each
further candidate is 21.

**A series relies on the scheduler stopping every session it settles** (#827): each lane run spawns
two, and a machine working through dozens of cells otherwise accumulates one resident process per
spawn until it runs out of memory mid-cell.

## Comparability

**`rounds` and `wall_min` compare within an arm only.** `/dev-pipeline:review`'s implementation is
`review-toolkit`'s `review-lead`, so an arm without that plugin obtains a result from no reviewer
at all — and the verdict gate refuses a `--panel` that names none (/dev-pipeline:review 5c, #825), so an
arm with no reviewer available writes no verdict record: every one of its cells terminates
`review-dark`, spends no round and spawns no second build.
Its `rounds` and `wall_min` are structurally smaller for a reason that has nothing to do with lane
quality, and `review_catch` is structurally `n/a`. Comparing those two columns across arms
measures the asymmetry, not the kit. The columns that compare across arms are the test and defect
columns.

## The series

A **series** is the tuple: the control's `harness_sha`, the resolved build model id, the resolved
review model id, the `cli_version`, and the substrate commit. **Rows compare only within a
series.**

- **A new model generation opens a new series** and re-baselines control and skeleton at the full
  tier — all 42 runs — before any candidate is scored against it.
- **The corpus is append-only.** A ticket's role, its overlay and its defect list are fixed once
  authored; changing one opens a new series rather than editing history.
- A `cli_version` or `harness_sha` that differs from an existing row of the same arm is a
  **refusal**, not a row: within one arm the harness is a constant by definition.

## Pre-registration

**Before any scored row exists, the operator commits a pre-registration to the bench repo, in one
commit.** It fixes, in advance:

- the **keep-or-revert rule** — what delta, on which columns, decides that a candidate ships;
- the **noise band** — the spread within which two arms are not distinguishable, taken from the
  control's own repeat-to-repeat variance;
- the **minimum detectable effect** the full tier can resolve at 21 cells per arm;
- the **predictions** for the candidate;
- the **confound register**, which must name at least the two shared confounds above: settings
  sources removed in every arm alike, and the `review-dark` asymmetry on `rounds` and `wall_min`.

**Those values are the operator's and are never written here.** This document names the fields and
fixes the rule that they precede the first scored row; it carries no numbers. A protocol that
shipped its own thresholds would invite them to be edited after the result is in, which is the one
thing pre-registration exists to prevent.

## Scoring a cell

```bash
tools/lane-bench.sh score \
  --results <bench-repo>/results.tsv --cell t4-control-r2 --issue <substrate issue> \
  --config <eval config> --overlay <bench-repo>/overlays/t4 --defects <bench-repo>/defects/t4.tsv
```

It resolves the PR, checks the head out into a scratch worktree, applies the overlay, runs it,
evaluates both detectors, and rewrites that row's columns 13 through 19. It refuses — exit 2,
results file untouched — on a missing or half-written row, an overlay with no `run.sh`, a seeded
defect naming a test the overlay never reports, an unparseable config, a results file whose header
is not the nineteen-column contract, or a `gh` read that errors. A read that errored is not a read
that found nothing.

## Running a cell

```bash
tools/lane-bench.sh run \
  --arm control --arm-ref <second-shift sha> --substrate <owner>/<repo> \
  --results <bench-repo>/results.tsv --config <eval config> \
  --ticket 4 --repeat 2 \
  --body <bench-repo>/tickets/t4.md --receipt <bench-repo>/receipts/t4.md \
  --overlay <bench-repo>/overlays/t4 --defects <bench-repo>/defects/t4.tsv
```

`--skeleton --control-ref <sha>` in place of `--arm-ref` builds the floor from the control
worktree instead of the arm's whole kit.

**The arm reaches the payload sessions through a wrapper, not through a flag.**
`tools/lane-bench-arm.sh` is handed to the lane as `LEAN_SPAWN_BIN`; it appends
`--setting-sources ''` and one `--plugin-dir` per manifest entry to a **session dispatch** and
`exec`s every other call on that handle — `agents --json --all`, `stop <id>` — through unmodified.
It is transparent by contract, not by courtesy: the scheduler reads the session id out of the
child's `backgrounded · <id> · <name>` line **by field position**, so one byte of the wrapper's
own on stdout would break every spawn. The manifest is written per cell and never checked in; an
unset, unreadable or empty one, or an entry naming a missing directory, is an exit-2 refusal.

What `run` does, in order: cuts the arm worktree and records `harness_sha` from it and
`cli_version` from `claude --version`; writes the manifest; **files a fresh issue as the
operator's own identity** and applies `tracker.labels.queue`; copies the ticket's fixture receipt
to `<stateDir>/<issue>-ledger.md`, the path the gate computes, so no cell measures the interview;
launches **the arm worktree's own** `orchestrate-lean.sh` detached under `nohup` with
`SECOND_SHIFT_CONFIG`, `LEAN_SPAWN_BIN` and `LEAN_ARM_MANIFEST` exported and both models, the
review-model basis and `--max-rounds 2` passed explicitly; polls the launch ledger for its
`terminal` row; classifies it; reads each payload session's **resolved model id** out of its
transcript; appends the row; and calls `score`.

The wrapper is the runner's own sibling and is the same file in every arm — a wrapper that varied
with the arm would be a confound on the quantity being measured. The **scheduler** is the arm's,
because the arm ref is the harness under test.

**Four refusals land before the first side effect** — a cell id already in the results file, a
dirty second-shift checkout, a `harness_sha` or `cli_version` disagreeing with an existing row of
the same arm, and an eval config whose tracker host is not the substrate. That last one is AC-10's
rung, and it is compared against an operator-supplied `--substrate <owner>/<repo>` rather than a
literal in this repository. A refusal that fired after the issue was filed would already have
written to a tracker, and an exit code cannot take that back.

A cell whose lane never writes a terminal row inside `LEAN_BENCH_CELL_CEILING_SECS` is
`lane-error` on the slug `no-terminal-row`, and takes the same single re-run. A second
`lane-error` records the row and exits 1: the row is a fact about the arm, and 1 rather than 2
says the results file was written.
