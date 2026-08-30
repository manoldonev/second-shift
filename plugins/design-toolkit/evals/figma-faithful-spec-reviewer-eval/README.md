# `figma-faithful-spec-reviewer` eval

Scores `design-toolkit:figma-faithful-spec-reviewer` against four labeled specs.
See [`../README.md`](../README.md) for the shared conventions, the quota warning, and why these
evals exist.

## Fixtures

| Fixture | Planted defect | Expected verdict |
| --- | --- | --- |
| `01-lean-spec-no-visual-contract` | a lean-lane spec: token table plus embedded translation plan, no Copy Index, **no visual contract** for any rendered node | `block`, and **not** `N/A` |
| `02-placeholder-copy` | a full spec whose Copy Index still carries `{Description}`, `{Label}` and an `Option 1` component-default string | `block` |
| `03-unresolvable-node-ref` | a screen referenced by a "DEV-READY" section link at `node-id=0-1` rather than the frame's own `fileKey` + `nodeId` | `block` |
| `04-control-clean` | none — complete inventory, visual contract, copy, field map and state coverage | `pass` |

## `N/A` is a wrong answer here, and that is the point

Fixture 01 is #704's fixture 3 and the oracle for its AC-4. Before that change the agent's
explicit-input discipline fired on "no Copy Index / Components / Screens sections" and its prompt
said outright that *every* lean-lane input returns `N/A` — so the checklist row written for
exactly this case, "a token table is not a visual contract", never ran on the lane where it was
needed.

The rubric therefore scores `N/A` as a wrong verdict on **every** fixture in this set: all four
are design artifacts, and declining one is the failure being measured. A pre-AC-4 baseline scoring
0 on fixture 01 is a finding, not a harness fault.

The complement matters too. `must_not_flag` on fixture 01 names the absent Copy Index and the
absent Element Inventory: the right behavior is to review what the artifact carries and say which
checks had no input, **not** to manufacture a Blocker for a section this artifact shape does not
have.

## What the control fixture is protecting

`04-control-clean` carries several near-miss opportunities: acceptance criteria whose negative
cases are phrased as positive assertions, an explicit `Open Questions: None` rather than an
omitted section, a `Card` used with a documented default-override, and switch dimensions off the
spacing scale. A Warning on any of them is a false positive; the pass is zero Blockers **and**
zero Warnings.

## Invocation

```bash
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "smoke" --smoke
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "my-note"
```

The prompt template deliberately does **not** say what shape the input is. Whether the agent
reviews a lean-lane spec or declines it is the measurement; a template that pre-classified the
input would grade the template.
