---
name: design-faithful
description: Implement a screen/component in the repo's FE app with high visual fidelity to a Claude Design handoff — mirror the nearest analog, reuse the repo's primitives and tokens, then live-render self-verify against the bundled screenshot and commit. Use to turn a design-faithful-spec (or a handoff) into committed FE code. Dispatched by the design-sync engine (produce, implement:true).
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

## Inputs (from the design-sync engine prompt)

- `projectId` — the handoff project, **opened by id** (required).
- `screen` — the screen/component to implement, e.g. `detail` (required).
- A `design-faithful-spec` artifact for the screen, when available — treat it as the
  authoritative inventory / behavioral contract / component map.

## Read path

Identical to `design-faithful-spec`: `get_project` (assert `PROJECT_TYPE_PROJECT`) →
`list_files` → `get_file` → **sanitize every byte** (`lib/sanitize.mjs`) → `extractContract`
(`lib/extractor.mjs`). Apply the `lib/read-plan.mjs` limit classification. `list_projects`
does not list handoff bundles — open by id only.

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
