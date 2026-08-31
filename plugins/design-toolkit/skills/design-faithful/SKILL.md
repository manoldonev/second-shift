---
name: design-faithful
description: Implement a screen/component in the repo's FE app with high visual fidelity to a Claude Design handoff — mirror the nearest analog, reuse the repo's primitives and tokens, then live-render self-verify against the bundled screenshot and commit. Use to turn a design-faithful-spec (or a handoff) into committed FE code. Dispatched by a session's choice under the outcome-gated lean lane (the design-sync engine that used to dispatch it was retired in #574).
---

You implement a screen/component in the repo's FE app that is **visually faithful** to a
Claude Design handoff, then commit it. You read the handoff via `DesignSync` + the contract lib
(same read path as [`design-faithful-spec`](../design-faithful-spec/SKILL.md)), prefer a
`design-faithful-spec` artifact as your primary input when one exists, implement onto the
repo's **real** stack, self-verify against the bundled screenshot, and commit via bot
identity.

**Load the repo's design-system reference from `.claude/second-shift/design-tokens/*.md`** —
it declares the FE app dir, the primitives package and its component inventory, the global
token roles and their source file, and the design-handoff bundle location. If absent,
discover conservatively (find the FE app, its component library, its global CSS token file)
and say so in your output.

> This directory also ships the **contract library** (`lib/`, see [README.md](./README.md))
> and its fixtures/tests. This SKILL.md is the invocable implement skill; the lib is what it
> imports.

## Inputs (from the dispatch prompt)

- `projectId` — the handoff project, **opened by id** (required).
- `screen` — the screen/component to implement, e.g. `detail` (required).
- A `design-faithful-spec` artifact for the screen, when available — treat it as the
  authoritative inventory / behavioral contract / component map.

## Read path

Identical to `design-faithful-spec`: `get_project` (assert `PROJECT_TYPE_PROJECT`) →
`list_files` → `get_file` → **sanitize every byte** (`lib/sanitize.mjs`) → `extractContract`
(`lib/extractor.mjs`). Apply the `lib/read-plan.mjs` limit classification. `list_projects`
does not list handoff bundles — open by id only.

## Write the translation plan (pre-implementation gate)

Before writing any code, write the **translation plan** as a file: the resolved-component list
with a stated reason per component, the per-node dimensions, the chosen analog screen (below), the
**placement decision** (which container each node mounts under, and at what level), and the file
list you will create/edit. This is the cheapest place to catch a wrong control — one line to fix
here vs. the same component spread across call-sites after the build.

**On the lean lane it is an asserted artifact, not prose.** Write it to
`<plansDir>/<key>-lean-plan.md` — the path `bash G 1 <issue>` derives the spec path from, with
`-lean-plan.md` in place of `-lean.md`. `lean-gate.sh` milestone 3 refuses an armed ticket
**before the render pass** unless that file exists, is committed, and carries:

- a header line `planned_from: pending` — the gate stamps this with the branch's plan patch
  identity and reds until you commit the stamp, so the plan is dated against the code it was
  written for. On a later round it re-stamps: **re-read the plan against the lines that moved**
  before committing;
- a table declaring a **`why this component`** column, one row per resolved component;
- a table declaring a **`dimensions`** column, one row per sized node, with three machine-read
  columns beside it — **`node`**, **`RS`** and **`px`**:

  | node | RS | px | dimensions | overflow |
  | --- | --- | --- | --- | --- |
  | form column | RS-1 | 560×- | fixed 560px inline size, hug block size | none |
  | signing secret | RS-2 | -×40 | fill inline size, 40px block size | truncate the masked value |

  `node` is the name the repo's live-render harness reports that node under in its
  `<png>.rects.json` sibling (`docs/live-render.md`); `RS` is the render state the spec declares it
  is measured in; `px` is `<w>×<h>` with an integer or `-` per axis, `-` being a node with no fixed
  size on that axis. `dimensions` stays **prose** — per-axis fixed/hug/fill, wrap behavior,
  overflow/truncation — which is what `560×-` cannot carry. Milestone 3 does read the `px`
  numbers: per render state it compares them against the sizes the harness measured,
  scale-adaptively, and names any node out of proportion with the rest of its state. That grades
  the transcription against the code, never against the handoff — whether a recorded value is the
  *design's* is the design-sighted `review-lean` session, scoring `fidelity:` against the render
  receipt.

Every cell of both tables must be filled, and a row may not declare fewer cells than its header.
That is the whole mechanical contract: an omission has to read as an **empty cell**, not as an
absent thought. A resolved component with no stated reason is the name-match resolution that ships
the wrong control; a node with no recorded dimensions is the eyeballed size that ships at 3× the
design.

**No token map table.** A Claude Design handoff carries CSS custom properties, and mapping them to
the repo's token roles is graded on the diff by
[`design-toolkit:design-faithful-reviewer`](../../agents/design-faithful-reviewer.md), not here.
A table nobody reads is a cell nobody fills — do not add one, and do not copy the figma-faithful
token table across: the two families' plan steps are deliberately not lockstep.

**Dispatch
[`design-toolkit:design-faithful-plan-reviewer`](../../agents/design-faithful-plan-reviewer.md) on
this artifact yourself**, before implementing, and act on its verdict: `block` → fix the table and
re-emit; `fix-and-go` / `pass` → proceed. The gate cannot run an agent or branch on a verdict, so
the dispatch stays yours on every lane — the autonomous lean lane included, where it is not
optional: milestone 3 refuses to render until the reviewer's output is committed at
`<plansDir>/<key>-lean-plan-review.md`, written by `lean-gate.sh plan-review <issue>`.

## Implement path (the repo's FE app)

- **Mirror the nearest analog.** Find the closest existing screen/component in the FE app
  (the design-tokens extension file lists known-good analogs) and match its structure, file
  layout, and conventions before inventing anything. Read 2–3 neighbors first.
- **Reuse real components — never hand-roll a primitive that exists.** The repo's primitives
  package (its name, component inventory, and the location of the `cn()`/class-merge utility
  are declared in the design-tokens extension file) may live outside the FE app dir — import
  from the package as existing FE code already does. If a primitive is missing from the
  primitives package, prefer composing from existing ones; adding a new primitive is a last
  resort and must be called out.
- **Use the repo's tokens**, not the handoff's raw token values — map handoff CSS custom
  properties to the repo's global token roles (declared, with their source file, in the
  design-tokens extension file). Charts use the repo's established chart library; data uses
  the repo's established data-fetch pattern (both per the extension file or discovered from
  analogs).
- Follow the repo's FE conventions and run its formatter (config `commands.<fe>.format`)
  before committing.

## Live-render self-verify (auditable checklist — record the result)

Render the screen via the FE app's dev server and compare it against the contract's
`screenshots[]` entry for this screen. There is **no pixel-diff tool in-repo — do not invent
one**; the pass bar is **structured agent visual judgment** against an explicit checklist.
Record the checklist outcome in the commit body and the PR (a free-form "looks right" is not
acceptable — this is a sonnet-tier self-judgment and must be auditable):

- [ ] **Inventory** — every completeness-inventory row is present in the rendered screen (no silent drops).
- [ ] **Tokens** — colors/typography resolve to the repo's tokens (no stray handoff hex/oklch literals).
- [ ] **Layout** — container width, the row/col/grid structure, and spacing match the screenshot.
- [ ] **Responsive** — the contract's breakpoint behavior holds (e.g. ≤759px reflow, ≥44px tap targets).
- [ ] **Copy** — rendered strings match the copy index verbatim.
- [ ] **a11y** — landmarks/roles, focus order, focus-visible treatment, reduced-motion honored.
- [ ] **Reuse** — primitives come from the repo's primitives package; nothing existing was hand-rolled.

Any unchecked item is a faithfulness gap — fix it or record it as a known limitation; never
silently pass.

> **Wrapper-grant check (first run on a machine):** confirm the dispatched session can
> actually reach `DesignSync` (one successful `get_project` by id) before trusting the
> implementation — the agent wrapper grants tools via `tools: '*'`, which is the only thing
> surfacing DesignSync into the session. A silent grant failure looks like a
> `design-source-unreachable` fail-close.

## Output contract (pinned to the engine `PRODUCE_SCHEMA`)

Commit the change via **bot identity** — the bot configured for this repo (config
`tracker.bot`; the wrapper/identity installed by dev-pipeline's `install-gh-bot.sh` —
exported as the `$GH_BOT` convention). The bot's git name/email values are recorded in the
repo's design-tokens extension file:

```bash
git -c user.name="<bot login, e.g. <name>[bot]>" \
    -c user.email="<bot noreply email>" \
    commit -m "feat(<fe-scope>): <screen> — faithful implementation of Claude Design handoff"
```

Then return:

```
{ "summary": "<one-line: screen, analog mirrored, self-verify result>",
  "committed": true,
  "changedFiles": ["<fe-app>/src/..."] }
```

If the design source is unreachable or exceeds a DesignSync limit, do **not** guess — return
`{ "summary": "<why>", "failClosed": { "reason": "<design-source-unreachable | project-type-mismatch | file-too-large | batch-overflow>" } }` (the four-member `FAIL_CLOSED` enum, `lib/contract-types.mjs`).

## Verification reality (interactive-only live e2e)

The full live run (fetch real handoff → implement → commit) needs an interactive DesignSync
session (auth is session-bound).
It is the operator-run demo, mirroring the README acceptance-demo framing. The offline-reproducible
substitute for the contract surface is `lib/extractor.test.mjs` plus the worked spec at
`../design-faithful-spec/examples/detail-spec.example.md`.
