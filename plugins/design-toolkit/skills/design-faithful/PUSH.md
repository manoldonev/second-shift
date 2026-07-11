# design-system push — interactive runbook (#200)

The **push** direction: publish the repo's design system (tokens + a representative component set)
to a Claude Design `PROJECT_TYPE_DESIGN_SYSTEM` project, so future designs are authored against
the repo's actual tokens and components. Code is the source of truth; this is a delta-only
**publish/sync**, never a wholesale replace.

> Load the repo's design-system reference from `.claude/second-shift/design-tokens/*.md` — it
> declares the global token CSS source file, the primitives package, and the design-system
> project name used below. If absent, discover conservatively and say so.

## Why this is a runbook, not an automated step

DesignSync is a **model-invoked tool** and its auth is **interactive-session-bound** — there is no
proven non-interactive/refreshable token (DesignSync probe findings, Probe 7). A Workflow script
has no tool access, so it cannot call DesignSync. The push therefore runs in
an **interactive agent session** (with `/design-login` scopes), eyes-on. The offline-testable
pieces — building the exact card bytes and computing the delta — are the library
(`lib/emit-*.mjs`, `lib/sync-plan.mjs`) and the driver (`tools/build-ds-files.mjs`); this runbook
covers the live tool calls that the library cannot make.

## The emit/sync library

| Piece                        | Role                                                                                                                                                |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/emit-card.mjs`          | `dsCardMarker()` + `emitCard()` — serialize a preview to `components/<slug>/index.html` with a first-line `@dsCard` marker and inline OKLch tokens. |
| `lib/emit-tokens.mjs`        | `tokenRootCss()` + `emitTokenCards()` — the dark-first `:root` block and one swatch card per token ramp, from the repo's global token CSS.         |
| `lib/component-previews.mjs` | `SHADCN_TOKEN_MAP`, `COMPONENT_PREVIEWS`, `buildDesignSystem({globalsCss})` — the representative set + assembler.                                   |
| `lib/sync-plan.mjs`          | `planSync({local, remote})` → `{writes, deletes, unchanged}` — the delta-only basis.                                                                |
| `tools/build-ds-files.mjs`   | offline driver: build → diff vs. an output dir → apply → manifest. Run twice to see the idempotent no-op.                                           |

## Push procedure (interactive session)

1. **Build the local card set.** `node tools/build-ds-files.mjs <globals-css-path>` (the repo's
   global token CSS, per the design-tokens extension file; writes the cards to
   `.out/design-system/`, gitignored), or import `buildDesignSystem` directly. These
   `{path, content}` pairs are the `local` set.

2. **Resolve the target project.**
   - `list_projects` (returns design-system projects only). If the repo's design-system project
     (name per the design-tokens extension file) exists, note its `projectId`.
   - **Cold start (none exists):** `create_project({ name: '<repo design-system project name>' })`
     — its only input is `name`, and it always returns a `PROJECT_TYPE_DESIGN_SYSTEM` project
     (Probe bonus). A freshly created project has no files, so its `remote` set is `[]`.

3. **Read current remote state.** `list_files(projectId)`, then `get_file` each existing
   `components/*/index.html`. **Sanitize every fetched file** (`lib/sanitize.mjs`) before using it —
   `get_file` returns other org members' content (untrusted, ≤256 KiB). These `{path, content}`
   pairs are the `remote` set. On a cold start, skip this — `remote = []`.

4. **Compute the delta.** `planSync({ local, remote })` → `{ writes, deletes, unchanged }`.
   - `writes` — new or byte-changed cards (the only paths to push).
   - `deletes` — stale remote cards under the `components/` tree that are no longer emitted. By
     design, paths outside `components/` (e.g. a `_ds_manifest.json` render artifact, which is NOT
     upload-generated — Probe 3) are never deleted. Do not hand `planSync` a `remote` set padded
     with render artifacts and expect them pruned.
   - If `writes` and `deletes` are both empty, the design system is already in sync — stop.

5. **Git checkpoint (before).** Commit/checkpoint the emitted `.out/` (or record the emitted file
   list) in the repo. This is a **local audit boundary** — it records what was pushed. It is **not**
   a remote rollback: git cannot undo a Claude Design write (see Recovery).

6. **Push the delta.**
   - `finalize_plan({ writes: [<paths in writes>], deletes: [<paths in deletes>] })` — **both**
     arrays are required (empty is fine); every path must be in-plan; it mints a fresh `planId`
     reusable across calls (Probe 6).
   - `write_files(planId, <writes>)` and `delete_files(planId, <deletes>)`, ≤256 files per call
     (split larger sets across calls under the same `planId`).

7. **Git checkpoint (after).** Record completion. Optionally open the project in the Claude Design
   web app to trigger the self-check that compiles `_ds_manifest.json` and to eyeball the cards
   (the card index also reads from the `@dsCard` first-line markers directly).

## Recovery (partial / interrupted push)

A multi-call push can partially apply (the 256/call limit splits a large set; a session can die
mid-push), and there is **no delete-project primitive** — emptying a project leaves a harmless
shell. The git checkpoint records intent but cannot reconcile a half-applied remote project. The
recovery path is the delta itself:

- **Re-run** the procedure. `planSync` re-reads the current remote state and emits only the
  still-missing/changed paths — a partially-applied push converges on re-run (idempotent).
- If a card was written that should not exist, it appears in the next run's `deletes` (stale
  `components/**` path absent from `local`) and is removed via `delete_files`.

## Scope (v1)

Dark-first `:root, .theme-cold` ramp only (no `.theme-warm` / `.lighten`); a **representative** set
of components (the token-bound composites + button/badge/card via `SHADCN_TOKEN_MAP`), not every
export of the repo's primitives package.
