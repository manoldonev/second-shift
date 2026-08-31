# `design-faithful-plan-reviewer` eval

Scores `design-toolkit:design-faithful-plan-reviewer` against four labeled translation plans.
See [`../README.md`](../README.md) for the shared conventions, the quota warning, and why these
evals exist.

**The baseline is OWED, not measured.** See [`CLOSEOUT-BASELINE.md`](./CLOSEOUT-BASELINE.md) — the
agent is newer than the installed plugin cache the runner dispatches from, and a reading taken
before the release that ships it measures the environment, not the agent.

## Fixtures

| Fixture | Planted defect | Expected verdict |
| --- | --- | --- |
| `01-missing-dimension-rows` | a control-bearing screen with **no dimensions table at all** | `block` |
| `02-name-match-resolution` | a `why this component` cell that restates the handoff node name, and a second reading `closest match`; the resolved component renders steppers the plan never describes | `block` |
| `03-unwired-state-no-analog` | an `RS-n` state the plan's own spec table declares with no row in its wiring table, and no analog named anywhere | `block` |
| `04-control-clean` | none — justified resolutions, populated dimensions, all four states wired | `pass` |

Fixtures 01 and 02 are the #692 defects in the claude-design shape. Fixture 03 covers the two
checks that need the spec and the plan read **together**: the wiring table looks complete on its
own, and the missing analog is an absence rather than a bad cell — both are things a reviewer that
grades tables cell-by-cell will miss.

Each fixture is deliberately **correct everywhere except the planted defect**. That is what makes
the score mean something: the only route to a Blocker is to grade the content, not to notice that
a cell is empty. The gate already asserts non-emptiness, and non-emptiness is not the check.

Every fixture that carries a dimensions table declares the `node`/`RS`/`px` triple beside the
prose cell, so each one is a plan `plan_violations` accepts. That is deliberate: a corpus whose
control is a shape milestone 3 refuses outright would train the reviewer to pass a plan the gate
rejects, and score it down for saying so. Fixture 01 is the exception, and its absent table is the
planted defect.

## The claude-design-specific trap

Every fixture carries **no token table**, because a design-faithful plan mandates none — a
handoff carries CSS custom properties, and token-role mapping is graded on the diff by
`design-faithful-reviewer`. A reviewer carrying its figma sibling's token-arithmetic section will
demand a table that should not exist, and every `expected.json` here scores that as a fabrication
on `d3`. That is the one dimension on which this instrument is not a copy of the figma one.

## What the control fixture is protecting

`04-control-clean` carries four near-miss opportunities: a `deferred` ledger provenance that is
legal but reads like an unanswered question, a fixed 560px form-column width that no token covers
(a dimension is a measurement, not a spacing token), a signing-secret field composed from
`TextField` plus an `endAdornment` rather than a dedicated primitive, and an event-type picker
whose resolution explicitly rejects the nearer `Select`. A Blocker on any of them is a false
positive.

## Invocation

```bash
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "smoke" --smoke
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "my-note"
```

Defaults are `--runs-per-fixture 3 --concurrency 2`. `--repo-root` is this directory, so the
agent's cwd holds nothing but the fixture set — the eval is hermetic, and a reviewer cannot
accidentally ground a finding in second-shift's own tree.
