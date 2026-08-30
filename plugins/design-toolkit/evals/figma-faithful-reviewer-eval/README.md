# `figma-faithful-reviewer` eval

Scores `design-toolkit:figma-faithful-reviewer` against four labeled diffs.
See [`../README.md`](../README.md) for the shared conventions, the quota warning, and why these
evals exist.

## Fixtures

| Fixture | Planted defect | Surface | Expected verdict |
| --- | --- | --- | --- |
| `01-branded-raw-literals` | hardcoded hexes, a raw `px` width, a hardcoded `rem`, a literal `fontFamily`, raw type | branded | `revise` |
| `02-hand-rolled-primitive` | raw `<input>`, `<select>` and two raw `<button>`s where the catalog exports `TextField`, `Select` and `Button` | fixed-theme | `revise` |
| `03-physical-style-props` | `marginTop` / `paddingLeft` / `paddingRight` / `marginRight` / `marginLeft`, the `bgcolor` alias, and physical `top` / `right` | branded, RTL-capable | `revise` |
| `04-control-clean` | none — theme units, palette paths, ramp variants, real components | fixed-theme | `approve` |

The three defect fixtures come from the agent's own checklist (#704 pre-flight D-5), one per rule
family, split deliberately across the two surfaces so the fixed-theme-vs-branded distinction the
reference exists to encode is exercised rather than assumed.

## The synthetic design-system reference

This agent's first act is to load `.claude/second-shift/design-tokens/*.md`. second-shift has no
FE app and no such reference, so the eval ships one under `fixtures/design-tokens/`, named in the
prompt template:

| File | Surface | What it fixes |
| --- | --- | --- |
| `acme-ui-catalog.md` | — | Figma-node → component lookup, source paths, and an **affordance notes** table recording what each component actually draws |
| `acme-ui-design-tokens-console.md` | fixed-theme | 4px spacing base, hex→path palette table, type ramp, the named-constant escape hatch |
| `acme-ui-design-tokens-storefront.md` | branded / host-relative | no value table; abstraction-only rules; `pxToRem` sizing; RTL, so logical props are a correctness rule |

It describes a **fictional organization**. Its structure is modelled on two real consumer
references; nothing is copied from them — not a token value, not a palette entry, not a component
name, not a path, not a sentence.

## Why there are export stubs

`fixtures/app/packages/acme-ui/src/components/*.tsx` are one-line export stubs. The agent's own
rule is "don't self-suppress import findings — verify them in the repo", so fixture 02 is only a
fair test if the catalog's source paths resolve to something greppable. `--repo-root` points at
this directory, so the agent's cwd contains both the reference and the stubs and nothing else.

A reviewer that flags the hand-rolled primitives **without** checking, and one that suppresses the
finding **because** it did not check, both fail fixture 02 — the first on grounding, the second on
recall.

## What the control fixture is protecting

The agent's stated calibration is "bias toward passing", and half the point of `04-control-clean`
is that this survives a campaign. It offers four near-misses: an off-scale `px` literal that IS
correctly named-and-commented (the reference's one escape hatch), a bare `'1px solid'` hairline
with no matching token, a logical prop taking a string rather than a unit number, and layout
containers. A Warning on any of them is a false positive.

## Invocation

```bash
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "smoke" --smoke
REVIEWER_MODEL=<version-pinned-id> JUDGE_MODEL=<version-pinned-id> ./run.sh "my-note"
```

The prompt template carries two overrides, both forced: the fixture contents ARE the diff (there
is no branch to `git diff`, same shape as `security-reviewer-eval/run.sh`), and the design-system
reference lives at a fixture path rather than the repo path the agent expects.
