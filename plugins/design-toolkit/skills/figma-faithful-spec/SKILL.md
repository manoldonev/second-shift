---
name: figma-faithful-spec
description: Transcribe an existing Figma design + ticket into a faithful FE spec — verbatim Copy Index, component identity, state coverage, BE-field map. Use when a Figma design already exists; not for shaping a feature that is still undecided. Requires the Figma design capability (config `gates.figma`).
---

You are turning a ticket + an existing Figma design into a structured FE spec — the contract
that the [`design-toolkit:figma-faithful`](../figma-faithful/SKILL.md) skill then implements
faithfully. Your job is to **capture what the design says**, verbatim and completely: every
element, every string, every component, every state, every persisted field. Not to design, not
to explore — the design is already decided in Figma.

**You are the only agent with Figma access.** Every downstream reviewer
([`design-toolkit:figma-faithful-spec-reviewer`](../../agents/figma-faithful-spec-reviewer.md),
[`design-toolkit:figma-faithful-reviewer`](../../agents/figma-faithful-reviewer.md)) is blind to
the design — they can only check the spec against itself, never against Figma. So **completeness
here is load-bearing**: anything you omit from the scene is invisible from this point on and
silently never gets built. Be EXTRA careful at step 2b (Describe the Scene) — the most common
and most glaring failure is not a wrong value, it's a **dropped element**: a persistent banner /
footer / helper line that appears in a populated state was simply never listed, because the spec
captured "the primary component + the empty state" and skipped a full walk of the frame tree.

**Load the repo's design-system reference from `.claude/second-shift/design-tokens/*.md`** — its
**component catalog** (Figma node name → the repo's real component + import) is what step 4
resolves against. This skill captures component **identity**; token translation
(spacing/color/type → the repo's abstractions) happens at implementation time in
`figma-faithful`, so this skill does not touch the token-role tables. If the extension file is
absent, resolve components conservatively from the FE app's component library and **say so**.

## Figma capability

This skill reads the design via the **Figma design capability** (config `gates.figma`). The MCP
is exposed under one of two tool namespaces depending on how it is installed — tolerate **both**
`mcp__figma__*` and `mcp__plugin_figma_figma__*` (`get_metadata`, `get_design_context`,
`get_variable_defs`, `get_screenshot`, `get_code_connect_map`). If neither namespace is
reachable, the capability is not enabled — say so and stop; do not transcribe from a static
image alone.

## When to use this (vs an interview skill)

These do **not** stack:

- Use **`figma-faithful-spec`** when a Figma design exists and the job is to transcribe it
  faithfully.
- Use an **interview skill** (e.g. `intake-toolkit:intake-interviewer` where installed) when the
  feature is still being shaped and the spec must be elicited by interview.
- If a Figma design exists but some behavior is still undecided, **transcribe what Figma shows
  and route the open behavior to the Open Questions section — do not switch to an interview
  skill.**

## Scope

- Produces the **spec** (the WHAT). The implementation plan / task breakdown is a planning skill's
  (or `figma-faithful`'s) job — not here.
- FE work on any surface. It captures component **identity**; token translation happens at
  implementation time in `figma-faithful`.

## Reference docs (load these)

- `references/fe-spec-template.md` — the structure every spec follows (mandated vs conditional
  sections). Bundled next to this file.
- the repo's **component catalog** — from `.claude/second-shift/design-tokens/*.md` (Figma node
  name → the repo's component + import). Used in step 4. If absent, resolve conservatively and say
  so.

## Mandated sequence

> Steps 1–2 are the same node-resolution discipline as `figma-faithful` steps 1–2. Keep the two
> in sync if either changes.

### 1. Resolve nodes

A section / "DEV-READY" link is a fine **input** — it's usually what you're handed — but never
`get_design_context`/`get_screenshot` the section node directly: it's too big to screenshot and
returns sparse placeholder text. Instead, `get_metadata` on the section first (structure only —
node IDs, names, positions), name-match the target child frames, and pull `get_design_context` +
`get_screenshot` on each **specific screen/element** node individually. (A per-screen "Copy link
to selection" URL from the user is even better, but resolving a section link this way is
expected.)

### 2. Sparse-dump drill → verbatim copy

If a dump shows `{Label}` / `"Text"` / "Option 1" placeholders, the real strings live in instance
nodes one level deeper. Drill into the instance node IDs and pull them individually. **Never
paraphrase or invent copy** — capture it verbatim, or mark it `TBD` for the designer. This is the
core spec job.

### 2b. Describe the Scene — the exhaustive element inventory (be EXTRA careful here)

This is the completeness step, and you are the only agent who can do it — downstream is blind to
Figma. Applies to every surface.

For **every** state frame resolved in step 1, walk the **complete** `get_metadata` child tree and
inventory **every** node — not just the obvious component. Headers, banners, footers, helper
lines, illustrations, dividers, tags, empty-state chrome: each child node is an element of the
scene and gets a row. Do not stop at "the primary component"; do not assume a node is decorative
and skip it.

Emit a visible **Element Inventory** table — one row per node:

| Node (name + id) | Copy (verbatim / TBD) | Component (step 4) | Visual contract (step 2c) | Appears in states |
| ---------------- | --------------------- | ------------------ | ------------------------- | ----------------- |

Rules that make it load-bearing:

- **Diff states against each other.** A persistent element (a guidance banner, a footer) appears
  in several state frames; capture it **once** with its full state-presence, so "populated state +
  a persistent banner" cannot vanish. A node present in one frame but missing from another is
  either a real state difference (record it) or your omission (fix it) — decide deliberately,
  never by skipping. The classic miss: a "read our documentation" banner that shows in the
  populated state gets dropped because only the empty-state frame was inventoried.
- **Every later section reconciles against this table.** Every inventory row must end up with a
  Copy Index entry (step 2), a resolved component (step 4), a **visual contract** (step 2c), and a
  state-presence (step 3). A node in the inventory with no downstream coverage is a dropped
  element — the exact failure this step exists to prevent. This table is what
  `figma-faithful-spec-reviewer` diffs the rest of the spec against.
- **No silent drops.** If a node genuinely needs no spec coverage (pure visual spacer), say so
  explicitly in its row — don't omit it.

### 2c. Measure the visual contract — size, structure, and component overrides (be EXTRA careful here)

Copy + component identity + states is NOT a faithful contract. Spacing/color/type tokens (step 3
of implementation) are necessary, not sufficient — they say nothing about how big an element is,
how its children are distributed, or which component defaults must be overridden. A spec that
omits these forces the implementer to guess, and a guess that compiles ships a wrong screen.

For every **rendered** node in the inventory, measure (from `get_metadata` for boxes/positions and
`get_design_context` / `get_variable_defs` for fills/strokes — **never imply a value**) and record
in its **Visual contract** cell:

- **Dimensions** per axis — fixed (`w` / `h` in px), hug-contents, or fill-container; flag fixed
  heights explicitly (a card that must stay one height regardless of content).
- **Layout & distribution** — direction, justify/align, child order, gaps between children, and any
  child that floats / is absolutely positioned (takes no layout space).
- **Sizing/fill of repeating groups** — fixed-width vs fill-container columns, wrap behavior, and
  whether an incomplete last row stretches (a wrap row of fill-container items → a fixed-column
  grid that does NOT stretch the last row; never a flex row with `flexGrow:1`).
- **Border** — width and color **per state** (e.g. 1px unselected, 2px primary selected).
- **Shadow/elevation** — present (with values) or explicitly **flat**.
- **Padding** and **overflow/truncation** (single-line ellipsis, N-line clamp,
  fixed-height-with-overflow).
- **Inter-block gaps** to sibling sections, on **both** sides of any divider.
- **Default/initial state** — which option is preselected, what a field defaults to (so no control
  renders empty-with-a-validation-error on load).
- **Component defaults to override** — name them: e.g. a card that ships an elevation shadow and a
  border that out-specifies plain style props, or a numeric field that stretches full-width by
  default. The implementer must know to override these, not discover them.

If a property can't be measured (an asset whose aspect differs from the frame, a value the dump
doesn't expose), record it as `TBD — verify before merge`, never a guess. **Rule: if the design
shows it, the spec measures it.**

### 3. Map the state machine (not just a state list)

A Figma section is usually a visual state machine: each frame is a state, and the
buttons/affordances imply transitions. Capture both:

- **States** — for each screen, list every state the implementation must cover: empty / loading /
  error / in-flight / disabled / populated. A state the spec omits is a state the implementation
  will miss.
- **Transitions** — a table of `trigger → from-state → to-state → resulting UI` (e.g. "click Save
  → editing → in-flight → success snackbar + navigate to list").

**Critical — transitions are INFERRED, never transcribed, so never assume.** The Figma Dev-Mode
MCP does **not** expose prototype reactions/flows/connectors — verified: none of `get_metadata` /
`get_design_context` / `get_variable_defs` / `get_code_connect_map` / `get_screenshot` return
interaction edges; a real frame dump contains only layout, code, tokens, and a screenshot. So the
state frames are retrievable but the edges between them are not — you reconstruct them from frame
names, on-screen affordances (button labels), copy, and the linked BE ticket.

Because you are inferring, do **not** silently fill a gap. When a trigger, target state, guard, or
the initial state is unclear or ambiguous, **resolve it with the user before finalizing** the spec
(via an interview skill such as `intake-toolkit:grill-me` where installed). If it stays unresolved
after that, record it explicitly in Open Questions — never invent a transition.

**Decision Ledger mapping** (contract: the `interviewing-baseline` protocol, via `intake-toolkit`
where installed): every Open Questions entry doubles as a `deferred` ledger row, and every
ambiguity resolved with the user lands as `user-answered`. When the spec feeds an implementation
plan, carry these rows into the plan's `## Decision Ledger` so nothing parked here silently becomes
an assumption downstream.

### 4. Resolve component identity

For each Figma component name, look up the repo's real component in the component catalog (from the
design-tokens extension file; Figma-alias table first, then leaf name). Unresolved → an **Open
Question**, never a guess.

### 5. Map the BE contract

From the linked BE ticket, map each persisted field → the FE control that sets it, and capture any
BE invariant the FE must mirror (with the BE source). Flag FE controls with no BE field and BE
fields with no FE control.

### 6. Assemble the spec

Fill `references/fe-spec-template.md` — every mandated section, conditional sections only where
they apply. The Copy Index is verbatim and mandatory.

### 7. Self-check (visible artifact, not a silent pass)

Emit a checklist alongside the spec:

- [ ] **every node in the step-2b Element Inventory has downstream coverage** — a Copy Index entry,
  a resolved component, a step-2c visual contract, and a state-presence; no inventory row is left
  dangling (the dropped-element guard),
- [ ] **every rendered node has a measured visual contract** (step 2c) — dimensions,
  layout/distribution, border-by-state, shadow/flat, padding, inter-block gaps, truncation, default
  state, and named component-default overrides; no measurable property left to the implementer to
  guess (anything unmeasurable is an explicit `TBD — verify before merge`),
- [ ] every visible-text node has a Copy Index entry (or an explicit TBD),
- [ ] every Figma component is resolved to an import or flagged as an Open Question,
- [ ] every screen's states are enumerated,
- [ ] every state transition has a resolved trigger + target — or was resolved with the user and
  parked in Open Questions, **never assumed**,
- [ ] every BE field is mapped,
- [ ] every formatted number/date/currency has a row in **Locked formatting / number rules** (or
  that section is explicitly `N/A`).

Surface it so the approval gate (below) can diff it — do not just assert "done."

## Enforcement

The independent checks at spec time are the **human approval gate** plus the step-7 checklist (a
visible artifact the approver diffs). The sibling `design-toolkit:figma-faithful-reviewer` agent
reviews **implementation** diffs, not this spec — and it is static, so it confirms styling uses the
right abstractions and components are real, **not** that copy, values, or states match Figma. Those
remain the approval gate's job until a deferred pixel-diff/screenshot gate closes the loop. The
spec is also written to pass a general spec reviewer's blocker-level checks (goal, scope, Actors,
testable + negative ACs) where one is available.

## Output

A structured FE-spec markdown following the template, **presented for approval** — never auto-posted
to the tracker; the user decides where it lands. When handed to `figma-faithful`, it triggers that
skill's spec-fed mode (trust the Copy Index + component list, skip re-derivation).
