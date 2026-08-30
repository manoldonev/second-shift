# design-toolkit evals

Three eval directories, one per static Figma reviewer, built on the generic
[`agent-eval-kit`](../../review-toolkit/evals/agent-eval-kit/README.md).

| Directory | Agent under test | What it grades |
| --- | --- | --- |
| `figma-faithful-plan-reviewer-eval/` | `figma-faithful-plan-reviewer` | a translation plan, before code |
| `figma-faithful-spec-reviewer-eval/` | `figma-faithful-spec-reviewer` | an FE spec, before code |
| `figma-faithful-reviewer-eval/` | `figma-faithful-reviewer` | an FE diff, after code |

## Why these exist

Until #704 `design-toolkit` was the only plugin with no `evals/` directory, so its three agents
had never been scored against a labeled fixture. #692 then showed each of them clearing a defect
that was **statically visible in its own input**: a translation plan recording no control
dimensions drew zero plan-reviewer findings; a node resolved to the wrong component by layer name
cleared both artifact reviewers; and a lean-shaped spec made the spec reviewer return `N/A`, so
the check written for exactly that case never ran.

#701 gave the plan's `why this component` and `dimensions` columns a gate that asserts they are
non-empty. Non-empty is not right — the agents still have to grade the content, and nothing
measured whether they do. These fixtures are that measurement.

## Operator-run and model-billed. Never in CI.

CI in this repo is model-free by design. The kit spawns `claude -p` subprocesses on your Claude
subscription; there is no API key and no CI lane, and none should be added. Budget before you
start — the kit's README has the quota arithmetic.

## Prerequisite: the plugin must be enabled

`claude -p --agent` resolves a plugin agent as `<plugin>:<agent>` and only when that plugin is
enabled on the machine running the eval, so every `run.sh` here passes
`design-toolkit:figma-faithful-…`. With `design-toolkit@second-shift` disabled the CLI exits 1 in
under a second with `not found. Available agents: …`, every run scores 0, and the result reads
like an agent failure rather than the environment one it is. Check `/plugin` (or the
`enabledPlugins` block in `~/.claude/settings.json`) first, and always smoke before a full run.

Two consequences worth stating plainly:

- **What you measure is the INSTALLED plugin, not your branch.** The installed cache lags an
  unmerged edit. Before recording a number against a prompt change, confirm the two agree —
  `diff plugins/design-toolkit/agents/<agent>.md ~/.claude/plugins/cache/second-shift/design-toolkit/<version>/agents/<agent>.md` —
  and record the answer in the baseline's provenance block.
- **The four older kit evals pass BARE agent names** (`--agent-name security-reviewer`), which no
  longer resolve for a plugin agent. That is a second way in which they are unrunnable as
  committed, alongside their dangling `--fixtures-dir` pointers. Do not copy the pattern.

## Running one

```bash
cd plugins/design-toolkit/evals/<agent>-eval
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "smoke" --smoke
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "my-note"
```

Both model variables are required and must be **version-pinned**; the runner refuses the bare
dispatch aliases. The reason is in the kit README under "Model identity is yours to supply", and
`scripts/check-eval-model-identity.sh` enforces that no pin is ever checked in here.

`--smoke` is one fixture × one run. Do it first — it catches a harness fault before a full run
burns quota.

## Fixture conventions

- **Flat layout**: `fixtures/<name>.md` plus `fixtures/<name>.expected.json`. The runner's
  directory-per-fixture layout is not used here.
- **Fixtures are committed, in-directory.** This departs from the four older kit evals, every one
  of which points `--fixtures-dir` at a path absent from this repo and is therefore unrunnable as
  committed. The shape copied instead is
  `../../intake-toolkit/evals/implementability-probe-eval/fixtures/`.
- **`Acme` is the anonymization convention.** Fixtures derived from a real run carry no real
  customer, product, repo or package identifier. second-shift is a public repo.
- **Every set has a clean control fixture** that must draw no blocker. All three agents declare a
  bias toward passing; a campaign that improves recall by destroying that calibration has not
  improved the agent, and the control is what makes the trade visible.
- **`expected.json` carries `must_not_flag`** alongside `expected_findings`. Naming what is
  *correct* in a fixture is what lets the judge score a false positive, which the older evals'
  ground truth could only do implicitly.

## Rubrics

All three use the same 6/2/2 split over `d1_verdict_correctness`, `d2_finding_grounding`,
`d3_no_fabrication`, for the reason recorded in `docs/plans/second-shift-704-lean.md` (D-4):
#704 grades in binary while the kit scores a weighted rubric, so the verdict dimension carries
the bulk and a per-fixture pass rate reads straight off `per_fixture` in the results JSON while
`overall_pct` still feeds the +10pp/3-run keep-or-revert rule in
`../../dev-pipeline/eval-criteria.md`.

A rubric is **locked during a campaign**. Editing one mid-campaign invalidates every comparison
across rounds.

## Baselines

Each directory carries a `CLOSEOUT-BASELINE.md` recording its measured pre-edit baseline, with the
provenance block a later run needs to compare against it. #704 landed those; the keep-or-revert
campaign that acts on them is #707.

| Agent | Baseline | Headroom |
| --- | ---: | --- |
| `figma-faithful-reviewer` | **100.00%** | none — a regression guard, not a tuning target |
| `figma-faithful-plan-reviewer` | **99.17%** | 0.83pp — likewise |
| `figma-faithful-spec-reviewer` | **72.50%** | 27.5pp, nearly all of it in one fixture |

**Two of the three are at a ceiling, and that is itself the result.** The plan reviewer caught
every #692 defect 3/3 on the first try — so #692's failure was *dispatch*, not capability: that
agent is dispatched by the operator at `figma-faithful` step 7 and by no autonomous lane. Routing
is #705's subject.

The spec reviewer's deficit is one fixture: `01-lean-spec-no-visual-contract` scored **0/3**,
declining a lean-lane spec as `N/A` in every run — the defect #704's AC-4 fixes, and the one place
a #707 campaign has room to move a number.
