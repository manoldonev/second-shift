---
name: figma-faithful
description: Faithful Figma-to-code implementation for FE work — enforces token extraction, layout-context reading, real-component resolution, and self-verification so spacing/copy/components are measured, not guessed. Use when building a screen/component from a Figma design. Requires the figma design provider (config `design.provider: "figma"`).
---

You are implementing an FE screen or component from a Figma design. This skill makes the
implementation **measured, not improvised** — every spacing/color/type value traces to a
token, every component to the repo's catalog, and copy is pulled verbatim from Figma rather
than invented.

It exists because the first FE ticket through the autonomous flow shipped with fidelity
failures: spacing eyeballed off screenshots, `px`/hex hardcoded against the theme-unit
convention, and measurement delegated to a subagent that hallucinated a value that was then
trusted. A second pass surfaced three more, all the same defect — **reading the node in
isolation and never its parent context**: an inter-block gap left to the surrounding code (a
16px block gap shipped at 8px, and a stale 24px gap matched instead of fixed), a component
nested inside a neighbour instead of mounted as the sibling the Figma frame tree showed, and
a shared component swapped for a raw `<img>` to dodge a styling quirk. The steps and hard
rules below close all of these gaps — step 3b (layout context), the component-reuse and
hierarchy hard rules, and a parent-frame self-verify.

**Load the repo's design-system reference from `.claude/second-shift/design-tokens/*.md`** —
it declares the FE app dir(s), the primitives package(s) and their component catalog, the
token roles (spacing scale, palette paths, type ramp) and their source file, the sizing
abstraction, and known-good analogs. If absent, discover conservatively (find the FE app, its
component library, its global token/theme source) and **say so in your output**. Where the
reference(s) split behavior across surfaces — e.g. a fixed-theme internal surface vs a
branded / host-relative one — pick the reference for the surface you are building; the
discipline below is the same for every surface, only the value _translation_ differs.

## Figma capability

This skill reads the design via the **figma design provider** (config `design.provider: "figma"`). The
MCP is exposed under one of two tool namespaces depending on how it is installed — tolerate
**both** `mcp__figma__*` and `mcp__plugin_figma_figma__*` (e.g. `get_metadata`,
`get_design_context`, `get_variable_defs`, `get_screenshot`). If neither namespace is
reachable, the capability is not enabled — do not guess values off a screenshot; say the
capability is unavailable and stop.

## Scope

- This is the **implementation** skill. Producing a formal Copy Index, enumerating all
  states, and the BE-field-mapping table are spec-phase concerns owned by the
  [`design-toolkit:figma-faithful-spec`](../figma-faithful-spec/SKILL.md) skill — not here.

## Two modes

This skill has **no hard dependency** on a spec.

- **Standalone mode (no approved spec):** self-resolve copy and components inline via steps
  1–5. Step 2 captures verbatim copy directly from the Figma instances. This is the default.
- **Spec-fed mode (an approved spec / Copy Index exists):** trust the approved Copy Index +
  component list, skip re-derivation, go straight to token translation (step 4) and implement.

Never abort for lack of a spec; spec-fed is an optimization.

## Reference docs (load these)

The authoritative token/component facts are **repo-specific** and live in the repo's
design-tokens extension file(s) at `.claude/second-shift/design-tokens/*.md` (see the load
note above). They typically declare:

- the **component catalog** — Figma node name → the repo's real component + import/source
  path. Used in step 5.
- the **token roles** — the spacing scale (and its px→unit rule), palette paths, and type
  ramp, with their source file. Used in step 4.
- the **sizing abstraction** and any per-surface rules (e.g. a branded surface where a literal
  color/`px` is forbidden). Used in step 4.

If the extension file is absent, discover these conservatively from the FE app and say so.

## Mandated sequence

### 1. Resolve the node

Never accept a section / "DEV-READY" link — it is too big to screenshot and returns sparse
placeholder text. Call `get_metadata` first (structure only, cheap), then `get_design_context`
+ `get_screenshot` on the **specific screen or element** node. If given a section link, read
the metadata, name-match the target child, and pull it individually. Prefer asking the user
for a per-screen "Copy link to selection" URL.

Also read the node's **parent** frame metadata, not just the node — the gaps between this node
and its siblings, and where it sits in the child order, live in the parent's auto-layout, not
in the node itself. You need them in step 3b. Capture the parent's child list (with each
child's `y`/`height`) and the parent's `itemSpacing`.

### 2. Handle sparse dumps

If the dump shows `{Label}` / `"Text"` / "Option 1" placeholders, the real copy lives one
level deeper in instance nodes. Drill into the instance node IDs and pull them individually
**before** drafting. Block implementation until verbatim copy is in hand or a string is
explicitly flagged TBD for the designer. Never paraphrase or invent copy.

### 3. Extract tokens

Call `get_variable_defs` on the node and build a **token table** — every spacing, color,
type, and icon-weight value the node uses. This table is the load-bearing artifact: it is what
a reviewer diffs the rendered styles against. Do not skip it; it is a precondition to the
step-7 plan gate. Use this format (step 3 fills the first two columns from `get_variable_defs`;
step 4 fills the third):

| Figma value     | Figma token       | Repo output    | Notes |
| --------------- | ----------------- | -------------- | ----- |
| `8px` (gap)     | `--space/xs`      | _(step 4)_     |       |
| `#383d47`       | `--text-primary`  | _(step 4)_     |       |
| `14px SemiBold` | `Text/groupTitle` | _(step 4)_     |       |

### 3b. Layout context — sibling spacing & placement

Layout context is measured the same way for every surface; only the px→unit _translation_
differs and defers to step 4 (per the repo's design-system reference). The step-3 token table
captures what's INSIDE the node; the fidelity failures that survive it live in the **parent**
frame: the gap between the node and its neighbours, and where the node sits in the parent's
child order. Measure both from the parent frame's `get_metadata` — never from the existing
code's current spacing.

- **Sibling gaps.** Read the parent's `itemSpacing`, or compute it from adjacent children along
  the parent's main axis — `next.y − (this.y + this.height)` for a column parent,
  `next.x − (this.x + this.width)` for a row parent. Add one token-table row per distinct
  inter-block gap (e.g. `section → banner = 16px`) and translate it in step 4 like any other
  spacing row — a theme-unit `gap`/`rowGap` value per the repo's spacing scale. A block-level
  gap is a token like any other; an isolated-node read misses it entirely.
- **Placement = hierarchy.** The node's parent in the Figma tree is its container in the
  markup tree, and its siblings stay siblings. A node that sits as a sibling of the
  cards/section in the parent frame is a sibling at that level — **not** nested inside a
  neighbouring component for convenience. Decide the mount point from the parent's child list
  before writing code, and state it in the step-7 plan ("renders as a sibling of X, under
  container Y, gap Z"). A control shown in a different region of the screen (e.g. a field in
  the right rail, not the content column) mounts in **that** region's component — read the
  frame tree, do not co-locate it with the nearest block for convenience.
- **Sizing & fill behavior.** Capture each node's auto-layout sizing per axis — fixed
  (`348px`), hug-contents, or fill-container — plus the parent's wrap behavior, fixed
  dimensions (e.g. card `200px` tall), and overflow/truncation (ellipsis / a clamped height).
  These are NOT in `get_variable_defs` and they dictate the CSS: a wrap row of fill-container
  cards is a **grid** with equal fixed-width columns (an incomplete last row keeps its column
  width — **no stretch**), NOT a flex row with `flexGrow:1` (which stretches the last row to
  fill). State sizing/fill/overflow per node in the step-7 plan — a token-only read misses
  stretch, fixed height, and truncation entirely.

Do not infer block spacing or placement from the file you're editing — the existing value may
itself be wrong (a 24px gap where Figma says 16px is a finding to fix, not a precedent to
match).

### 4. Translate

Map each row of the token table via the repo's design-system reference **for the surface you
are building**:

- **spacing** → the repo's spacing-scale value (e.g. `px ÷ base` → a theme-unit number),
- **color** → a palette path / token role — **never a raw hex where a token exists**; on a
  branded / theme-driven surface a literal color defeats the theme, so a hex is always a
  finding,
- **sizing** (`width`/`height`/`fontSize`) → the repo's sizing abstraction (e.g. a
  `pxToRem`-style helper) where the reference mandates one — never a raw `px`/`rem` on a
  host-relative surface,
- **type** → the repo's type-ramp variant; never a raw `fontFamily`/`fontSize`/`fontWeight`
  where a variant exists,
- **icon weight** → the icon-set prefix the node renders.

An off-scale value (not on the spacing scale, a hex not in the palette, a size not in the ramp)
gets a **named module-level constant with a one-line comment** explaining why — only then.

### 5. Resolve components

For each Figma component name, look up the real component in the repo's component catalog (the
design-tokens extension file; try the Figma-alias table first, then the leaf name). If nothing
resolves, mark it an **Open Question** and surface it — never guess an import or rebuild a
primitive that already exists. If the primitives package has no matching component, prefer
composing from existing ones; a genuinely local wrapper (checked for under the app's own
components dir) may exist — reuse it before reaching for a raw primitive.

### 6. Mirror the analog

Mirror the structure (routing, data-fetching, form pattern) of the closest existing screen in
the same FE app/surface. Reference the repo's existing convention sources by path — its ADR /
architecture / reference docs and `CLAUDE.md` (whichever the repo's context router declares) —
rather than restating them. The design-tokens extension file may list known-good analogs by
domain; until such an index exists, find the nearest existing screen in that app and mirror it,
and **say which one**.

### 7. Surface the translation plan (pre-implementation gate)

Before writing any code, emit the **translation plan** as a discrete artifact: the completed
token table (steps 3–4, all columns filled, **including the step-3b inter-block gap rows**),
the resolved-component list (step 5), the **placement decision** from step 3b (which container
each node mounts under, and at what level), the chosen analog (step 6), and the file list you
will create/edit. This is the cheapest place to catch a wrong token row — one line to fix here
vs. the same value spread across call-sites after the build. In an autonomous pipeline this
artifact is the gate [`design-toolkit:figma-faithful-plan-reviewer`](../../agents/figma-faithful-plan-reviewer.md)
reviews, and the pipeline branches on its verdict (`block` → fix the table and re-emit;
`fix-and-go` / `pass` → proceed to step 8). Run manually, surface it for the same check before
continuing.

### 8. Implement

Write the code against the token table (step 3/4) and the resolved components (step 5). Use
logical / direction-aware layout props (block/inline start & end) and full property names,
theme-unit spacing values, and palette paths. No raw `px`/hex where a token exists. On a
branded / host-relative surface: no hardcoded hex (palette paths — branding), the repo's
sizing abstraction for sizing, the repo's type-ramp variant for type; logical props are
mandatory where the surface renders RTL.

### 9. Self-verify

Re-read your own styling / token usage against the step-3 token table — every value must trace
to a token or a justified named constant. This is self-attestation by the same agent that wrote
the code, so it is the weakest link; the real enforcement is that the **token table exists as a
visible artifact** a reviewer (or a future pixel-diff gate) can check against.

Then re-open the **parent** frame screenshot (not just the node) and confirm: (a) every gap
between top-level blocks matches a step-3b row, (b) the component nests at the same level as the
node does in the Figma frame tree, and (c) the step-3b **sizing/fill** behavior holds — no
stretch on an incomplete wrap row, fixed dimensions applied, overflow truncated. The
block-level rhythm, placement, and sizing behavior are exactly what an isolated-node read
misses — verify them against the parent, not against the file you started from.

**Live-render verify (when a dev server is reachable — the strongest check).** The token table
and a Figma-blind code reviewer cannot see layout _behavior_, _placement_, or _default state_ in
the running app. When a dev server is up, render the implemented screen (e.g. with a headless Playwright
script at the feature URL), screenshot it, and compare against the cached Figma frame for:
placement (each control under the right container — a field in the right rail, not the content
column), sizing/fill (no unintended stretch on an incomplete row; fixed dimensions hold —
measure the rendered rects where decisive), truncation, and default/empty state (no field
renders empty-with-a-validation-error on load). This catches what every static gate misses: a
token table and a Figma-blind reviewer can all pass while the grid stretches, a control sits in
the wrong column, or an input loads empty — only a live render against the design surfaces those.

**Output contract.** Surface, alongside the implementation:

1. the **completed token table** (all three columns filled, including the step-3b inter-block
   gap rows),
2. the **placement decision** — where each node mounts in the markup tree (sibling vs nested),
   per the Figma frame hierarchy,
3. the **resolved-component list** — each Figma component name → the real import used,
4. any **Open Questions** — unresolved components, TBD copy, and off-scale values that became
   named constants.

## Hard rules (not advisory)

- **No eyeballing.** Step 3 (token extraction via `get_variable_defs`) is a precondition to the
  step-7 plan gate. Spacing/color/type values come from the MCP token data, never from
  estimating a screenshot.
- **No raw literals when an abstraction exists.** No raw `px`/hex where a token exists — logical
  layout props + theme units + palette paths. On a branded / host-relative surface: no hardcoded
  hex (breaks the theme), the repo's sizing abstraction for sizing, the type-ramp variant for
  type, logical props for RTL. Off-scale values get a named constant + comment.
- **Never delegate fidelity-critical measurement to a subagent.** Spacing, tokens, and copy are
  pulled by the main agent from the MCP. Subagents may parallelize independent instance-node copy
  pulls (deterministic), but never _measure_ from screenshots — a subagent's visual estimate is
  exactly what failed before.
- **Measure gaps BETWEEN elements, not just inside them.** A node's spacing to its siblings lives
  in the parent auto-layout frame (step 3b), not in the node's own `get_variable_defs`. Pull the
  parent frame and tokenise every inter-block gap; never let a block-level gap default to whatever
  the surrounding code already has (it may be wrong).
- **Figma hierarchy = markup hierarchy.** A node that is a sibling in the parent frame is a
  sibling in the markup; do not nest it inside a neighbouring component for convenience. Mount it
  where the frame tree puts it — including across screen regions (a right-rail field belongs in
  the rail's component, not the content column).
- **Capture and verify layout BEHAVIOR, not just tokens.** Item sizing/fill (stretch vs
  fixed-width grid columns), fixed dimensions, wrap, overflow/truncation, control placement, and
  default/empty state are part of fidelity, and `get_variable_defs` does not encode them. Capture
  them in step 3b, state them in the step-7 plan, and — when a dev server is reachable — confirm
  them with a live render (step 9). A clean token table is necessary, not sufficient.
- **Reuse the component the codebase already uses — never drop to a raw primitive to dodge a
  quirk.** If a node maps to a component that already appears in the target file or the nearest
  analog, reuse that exact usage including its documented style override. When a design-system
  component has an awkward default (e.g. an image primitive that is `position: absolute`), `Grep`
  the file for how it's already tamed and copy that — emitting a raw `<img>`/`<div>`/`<button>` to
  sidestep the quirk is a regression, not a fix.
- **A sparse Figma dump blocks implementation** until the instance nodes are pulled.
- **Follow the repo's coding conventions.** Match the repo's established conventions (export style,
  function style, import style, formatting) — these are not fidelity rules, but violating them
  draws review nits that derail a faithful PR. Read a neighbouring file and mirror it; run the
  repo's formatter before finishing.

## Worked example

A sub-checkbox group. The node's `get_variable_defs` gives an `8px` vertical gap and `body`
text; the inline indent is a detached `22px` (an optical alignment to the radio label, off a
4px scale).

**Token table (steps 3–4)** — the `Repo output` column shows one repo's mapping (a 4px spacing
base, theme-unit spacing numbers, a type-ramp variant); translate per **your** repo's reference:

| Figma value                 | Figma token  | Repo output                   | Notes                                                        |
| --------------------------- | ------------ | ----------------------------- | ------------------------------------------------------------ |
| `8px` (gap)                 | `--space/xs` | `gap={2}`                     | 8 ÷ 4                                                        |
| `22px` (inline start)       | _detached_   | `RADIO_LABEL_INDENT` constant | off-scale (5.5 units) → named + commented                    |
| `14px` Regular              | `Text/body`  | `<Text variant='body'>`       |                                                              |
| `16px` (group → next block) | `--space/m`  | parent `gap={4}`              | **step 3b** sibling gap (16 ÷ 4); measured from the _parent_ |

**Placement (step 3b):** in the parent frame this group is a sibling of the next section, so it
mounts as a sibling under the parent container — not nested inside the section above it.

Note what the table caught: a screenshot-eyeball would plausibly have written `gap={1}` (4px)
for that gap; the `--space/xs` token says `gap={2}` (8px). The one raw value (`22px`) is forced
through a named constant + comment rather than dropped inline — the only escape hatch the hard
rules allow. And the `16px` inter-block gap (step 3b) is captured as the parent's `rowGap`,
measured from the parent frame rather than left to whatever the existing file happened to use.

**Branded-surface contrast.** On a branded / host-relative surface the same group keeps
`gap={2}` (spacing units scale with the host font), but a literal color like `#383d47` becomes a
palette path (`text.primary` — branded, never a hex), and a fixed `width: 220px` becomes the
repo's sizing abstraction (e.g. `pxToRem(220)`) — never a raw `px`/`rem`.
