# `figma-faithful-reviewer` eval

Scores `design-toolkit:figma-faithful-reviewer` against twelve labeled diffs.
See [`../README.md`](../README.md) for the shared conventions, the quota warning, and why these
evals exist.

## Fixtures

| Fixture | Planted defect | Surface | Expected verdict |
| --- | --- | --- | --- |
| `01-branded-raw-literals` | hardcoded hexes, a raw `px` width, a hardcoded `rem`, a literal `fontFamily`, raw type | branded | `revise` |
| `02-hand-rolled-primitive` | raw `<input>`, `<select>` and two raw `<button>`s where the catalog exports `TextField`, `Select` and `Button` | fixed-theme | `revise` |
| `03-physical-style-props` | `marginTop` / `paddingLeft` / `paddingRight` / `marginRight` / `marginLeft`, the `bgcolor` alias, and physical `top` / `right` | branded, RTL-capable | `revise` |
| `04-control-clean` | none — theme units, palette paths, ramp variants, real components | fixed-theme | `approve` |
| `05-theme-redundant-sx-button` | `sx={{ textTransform: 'none' }}` restates the Button theme override | fixed-theme | `revise` |
| `06-theme-redundant-sx-tag` | `sx={{ textTransform: 'uppercase', paddingInline: 2 }}` restates the Tag theme override | fixed-theme | `revise` |
| `07-false-comment-button-wrap` | a comment says Button labels wrap; the override sets `whiteSpace: 'nowrap'` | fixed-theme | `revise` |
| `08-false-comment-menu-zindex` | a comment says Menu's paper sits at `zIndex` 1; the override sets 1300 | fixed-theme | `revise` |
| `09-ellipsis-defeated-by-sx` | a caller `whiteSpace` in `sx` overrides `Typography`'s `ellipsis` | fixed-theme | `revise` |
| `10-aria-label-misrouted` | `aria-label` on `TextField` lands on the FormControl root, not the `<input>` | fixed-theme | `revise` |
| `11-conformance-control-clean` | none — each wrapper used as designed, and a true comment | fixed-theme | `approve` |
| `12-size-keyed-override-clean` | none — a theme value keyed on `size='small'`, with the diff on the default size | fixed-theme | `approve` |

Fixtures 01-03 come from the agent's own checklist (#704 pre-flight D-5), one per rule family,
split deliberately across the two surfaces so the fixed-theme-vs-branded distinction the
reference exists to encode is exercised rather than assumed.

Fixtures 05-11 are the **library-conformance** set (#1077). They carry no token violation, so a
token finding on any of them is a false positive. Each planted defect shows only in the installed
`acme-ui` source, and each `.expected.json` names the source lines that prove it in a
`disproving` list of `{"path", "line"}` entries, relative to this directory. There are two
fixtures per class: a theme-redundant `sx`, a false justification comment, and wrapper-API
misuse. On the control, `disproving` names the lines that disprove each near-miss. The judge
gives full grounding credit only to a finding that cites the installed source, and, on 07 and 08,
says the comment is false.
Fixture 12 (the #1076 follow-up) is the condition-rule control: the installed theme sets the
value the diff writes, but only under `size='small'`, so a reviewer that flags it cited a line
that does not apply under the diff's size.

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

## The `acme-ui` stand-in

`fixtures/app/packages/acme-ui/` is a fictional package, `@acme/acme-ui`, with a version in its
`package.json`. `fixtures/app/package.json` declares it as a workspace, so the fixtures' imports
from `@acme/acme-ui` resolve to it. Nothing is installed, and no real library is vendored: a
reviewer can judge the stand-in only by reading it. `--repo-root` points at this directory, so
the agent's cwd contains the reference and the stand-in and nothing else.

The components the conformance fixtures render have bodies: `Button`, `Tag`, `Menu`,
`Typography` (an `ellipsis` prop) and `TextField` (unnamed props land on the FormControl root).
`src/theme/overrides.ts` holds the theme overrides, and `src/system/Box.tsx` merges a
component's `sx` array left to right, so a caller's `sx` wins. The design-system reference under
`fixtures/design-tokens/` does not mention any of this; only the source does.

The other components are one-line export stubs. The agent's own rule is "don't self-suppress
import findings — verify them in the repo", so fixture 02 is only a fair test if the catalog's
source paths resolve to something greppable. Every component, stub or body, keeps an
`export const <Name>` line for that grep.

A reviewer that flags the hand-rolled primitives **without** checking, and one that suppresses the
finding **because** it did not check, both fail fixture 02 — the first on grounding, the second on
recall.

## The model-free check

`check-fixtures.sh` checks that every `fixtures/*.expected.json` parses and that every
`disproving` entry names a file inside the stand-in and a line that exists in it. It does not
check what the line says. Run it after any edit to the stand-in: a moved line is the fixture
author's to re-cite. `check-fixtures-selftest.sh` runs in CI.

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
