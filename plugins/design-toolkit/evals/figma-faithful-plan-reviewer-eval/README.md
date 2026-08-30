# `figma-faithful-plan-reviewer` eval

Scores `design-toolkit:figma-faithful-plan-reviewer` against four labeled translation plans.
See [`../README.md`](../README.md) for the shared conventions, the quota warning, and why these
evals exist.

## Fixtures

| Fixture | Planted defect | Expected verdict |
| --- | --- | --- |
| `01-missing-dimension-rows` | a control-bearing screen whose `dimensions` table has a header and separator and **zero rows** | `block` |
| `02-name-match-resolution` | a `why this component` cell that restates the layer name; the resolved component renders steppers the plan never describes | `block` |
| `03-spacing-arithmetic` | `16px → rowGap={2}` on a 4px base, twice (an intra-node row and a step-3b inter-block row), plus a raw `px` sizing row on a branded surface | `block` |
| `04-control-clean` | none — correct arithmetic, populated dimensions, justified resolutions | `pass` |

Fixtures 01 and 02 are #704's fixtures 1 and 2, derived from the #692 run. Fixture 03 exercises
the checklist's highest-value row (token-table arithmetic) at both scopes, because the inter-block
rows are called out separately and a reviewer that grades only the intra-node rows catches one of
the two.

Each fixture is deliberately **correct everywhere except the planted defect**. That is what makes
the score mean something: the only route to a Blocker is to grade the content, not to notice that
a cell is empty. #701's gate already asserts non-emptiness, and non-emptiness is not the check.

## What the control fixture is protecting

`04-control-clean` carries four near-miss opportunities: a `deferred` ledger provenance that is
legal but reads like an unanswered question, a switch control whose 36×20px dimensions are off
the 4px spacing scale (a dimension is a measurement, not a spacing token), a `Card` used with a
documented default-override rather than avoided, and a 720px max no token covers. A Blocker on
any of them is a false positive.

## Invocation

```bash
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "smoke" --smoke
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "my-note"
```

Defaults are `--runs-per-fixture 3 --concurrency 2`. `--repo-root` is this directory, so the
agent's cwd holds nothing but the fixture set — the eval is hermetic, and a reviewer cannot
accidentally ground a finding in second-shift's own tree.
