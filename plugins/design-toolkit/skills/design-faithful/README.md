# design-faithful — DesignSync adapter (read + push)

The foundation of the `design-faithful` capability (epic #193), in both directions:

- **Read** — turn a Claude Design project into a structured, sanitized **design contract** that
  the #196 engine consumes (`lib/extractor.mjs` and friends).
- **Push** — emit the repo's own design system (tokens + a representative component set) as Claude
  Design `@dsCard` previews and sync them delta-only to a design-system project
  (`lib/emit-*.mjs`, `lib/sync-plan.mjs`, `tools/build-ds-files.mjs`, [`PUSH.md`](./PUSH.md)).

The repo-specific inputs (FE app dir, primitives package + inventory, global token CSS source,
design-handoff bundle location, design-system project name, bot identity) live in the consumer
repo's `.claude/second-shift/design-tokens/*.md` reference — the code and docs here read from it
or fall back to conservative discovery.

This directory ships the contract **library** (`lib/`) + its fixtures, tests, and the push
driver/runbook, plus the invocable **`design-faithful` implement skill** (`SKILL.md`) — the skill
body imports the lib to read a handoff and implement a screen in the repo's FE app. The sibling
spec-producing skill lives at [`../design-faithful-spec/`](../design-faithful-spec/SKILL.md).

> `SKILL.md` here is the **implement** skill (dispatched by the #196 engine as `agentType`
> `design-faithful`); `lib/*.mjs` are plain importable ESM the skill loads.

## What's here

| File                         | Role                                                                                                                                                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/contract-types.mjs`     | `DesignContract` JSDoc typedefs, the `inferred:true` marker convention, the `FAIL_CLOSED` reason enum + `FailClosedError`. The interface #196/#200 build against.                                |
| `lib/sanitize.mjs`           | `sanitize(text)` — strip `<script>`, inline `on*=` handlers, `javascript:`/`data:text/html` URLs. Runs on every byte before any parse. Never evaluates input.                                    |
| `lib/css-tokens.mjs`         | `extractCss(css)` — OKLch/hex tokens grouped by theme selector, spacing/radii scales, typography, first-class `@media` breakpoints, layout primitives, inferred pseudo-states.                   |
| `lib/html-markup.mjs`        | `parseDsCard(html)`, `extractMarkup(html, {path})` — `@dsCard` marker, semantic/ARIA markup, inferred states + variants (flagged `inferred:true`), missing-marker diagnostic.                    |
| `lib/read-plan.mjs`          | Pure read-path limit logic: `planFetch`, `classifyFetchResult`, `assertProjectType`. Maps tool results to the four fail-closed reasons.                                                          |
| `lib/extractor.mjs`          | `extractContract({projectType, files})` — sanitize → dispatch by shape → assemble the contract.                                                                                                  |
| `lib/extractor.test.mjs`     | `node --test` suite for the read path (zero deps).                                                                                                                                               |
| `lib/emit-card.mjs`          | **Push.** `dsCardMarker()` + `emitCard()` — serialize a preview to `components/<slug>/index.html` with a first-line `@dsCard` marker and inline OKLch tokens (the inverse of `html-markup.mjs`). |
| `lib/emit-tokens.mjs`        | **Push.** `tokenRootCss()` (dark-first `:root` block, reuses `extractCss`) + `emitTokenCards()` — one swatch card per token ramp.                                                                |
| `lib/component-previews.mjs` | **Push.** `SHADCN_TOKEN_MAP`, `COMPONENT_PREVIEWS`, `buildDesignSystem({globalsCss})` — the representative set (token-bound composites + primitives via the documented map) + assembler.         |
| `lib/sync-plan.mjs`          | **Push.** `planSync({local, remote})` → `{writes, deletes, unchanged}` — the delta-only, idempotent sync basis.                                                                                  |
| `lib/emit.test.mjs`          | `node --test` suite for the push path (zero deps).                                                                                                                                               |
| `tools/build-ds-files.mjs`   | **Push.** Offline build driver: assemble cards → diff vs. an output dir → apply → manifest. Run twice to see the idempotent no-op.                                                               |
| `PUSH.md`                    | **Push.** The interactive live-push runbook (the DesignSync calls the library cannot make).                                                                                                      |
| `fixtures/*.mjs`             | Real captured handoff bytes + a design-system pair + a hostile-input sample, as exported strings.                                                                                                |

## The read-path boundary

`DesignSync` is a model-invoked **tool**, not an importable function — so the actual
`get_project` / `list_files` / `get_file` calls are made by the orchestrating agent: the
`design-faithful` / `design-faithful-spec` skills, which carry the tool. (The #196 Workflow
engine has no tool/fs access — it only dispatches those skills; see its READ BOUNDARY note.)
The code here is **pure**: it operates on already-fetched bytes. Shape-specific
discovery (per the #194 DesignSync probe findings):

- **`PROJECT_TYPE_PROJECT`** (handoff bundle) — open **by project id** via
  `get_project → list_files → get_file`. `list_projects` is **design-system-only** and returns
  `[]` for handoff bundles, so it is **not** used for this shape. The repo's handoff bundle
  location is declared in the design-tokens extension file (the committed fixtures were captured
  from acme's `design_handoff_acme_redesign/`).
- **`PROJECT_TYPE_DESIGN_SYSTEM`** — `list_projects` lists these; read
  `components/*/index.html` and parse the first-line `@dsCard` marker directly (do **not** rely
  on `_ds_manifest.json`, which is a web-app render artifact, absent after a headless push).

Apply the limits with `read-plan.mjs`: a `get_file` returning `truncated:true` →
`file-too-large`; a null/error result → `design-source-unreachable`; a batch beyond 256 →
`batch-overflow`; a project whose `type` ≠ expected → `project-type-mismatch`. **Sanitize every
`get_file` result before parsing** — its content is authored by other org members (untrusted).

## Usage

```js
import { extractContract } from './lib/extractor.mjs'
import { classifyFetchResult, assertProjectType } from './lib/read-plan.mjs'
// (caller fetches via the DesignSync tool, then:)
const contract = extractContract({
  projectType: 'PROJECT_TYPE_PROJECT',
  files: { css: [{ path: 'styles.css', text }], screens: [{ path, text }], screenshots: [...] }
})
```

## Acceptance demo (real project, interactive)

The live acceptance path ("real handoff → populated contract") needs an interactive DesignSync
session (design scopes; the project is opened by id). It is **not** a CI unit test. The committed
fixtures in `fixtures/handoff.mjs` are **real bytes captured live** from a handoff bundle
(acme's `design_handoff_acme_redesign/`: `styles.css` + `screens/detail.jsx`), so the e2e
test ("assembles a handoff contract from real fixtures") IS the acceptance assertion, reproducible
offline. A consumer repo re-runs the live demo against its own handoff bundle by opening that
project by id, fetching its `styles.css` + a screen, and passing them to `extractContract`.

## Push direction — emit + sync

`buildDesignSystem` turns the repo's global token CSS + a representative set of the repo's
primitives into `components/<name>/index.html` cards; `planSync` computes the delta against the
project's current files; the cards are pushed delta-only via DesignSync. Code is the source of
truth — the push is idempotent on re-run.

```js
import { buildDesignSystem } from './lib/component-previews.mjs';
import { planSync } from './lib/sync-plan.mjs';
const local = buildDesignSystem({ globalsCss }); // emitted card bytes
const plan = planSync({ local, remote }); // remote = sanitized list_files/get_file
// finalize_plan({ writes: plan.writes, deletes: plan.deletes }) → write_files/delete_files
```

Same constraint split as the read path: DesignSync auth is interactive-session-bound, so the live
push is an eyes-on step — see [`PUSH.md`](./PUSH.md). The **offline analogue** of the live push is
the driver, which produces the exact card bytes and (run twice) demonstrates the delta-only
idempotency without DesignSync:

```bash
# <globals-css-path> = the repo's global token CSS, per the design-tokens extension file
node tools/build-ds-files.mjs <globals-css-path>   # cold: writes N cards
node tools/build-ds-files.mjs <globals-css-path>   # re-run: 0 writes (in sync)
```

## Tests

```bash
node --test lib/extractor.test.mjs   # read path
node --test lib/emit.test.mjs        # push path
```

Zero external deps (`node:test` + `node:assert`) — the convention for `.claude/` tooling. These
`.mjs` files are in `.prettierignore` and hand-styled to match the existing Workflow scripts.
