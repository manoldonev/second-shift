# FE spec template

Bundled with the `figma-faithful-spec` skill. This is the structure every transcribed FE spec follows. **Mandated** sections are always present; **conditional** sections appear only when the trigger applies. Fill placeholders verbatim from Figma + the ticket — never paraphrase copy, never invent.

This template is self-contained — follow the section structure below directly (every section is tagged **mandated** or **conditional**). If you reference an older spec for shape, reconcile it to this structure and do not copy its headings verbatim.

---

## Summary _(mandated)_

One paragraph: what this screen/flow is and the goal it serves. State the in-scope boundary here.

## Actors _(mandated)_

Who interacts with this surface (e.g. internal operator, end user) and what each can do. A spec with no actors is a gap a general spec reviewer flags.

## Dependencies _(mandated)_

BE tickets (with keys), library/component versions, feature flags, and any ordering constraints (what must ship first).

## Routes _(mandated)_

Every route this work adds or touches, with the path and the screen it renders.

## Element Inventory _(mandated)_

The completeness backbone (skill step 2b). For **every** state frame, a full `get_metadata` walk of the frame tree — **one row per node**, not just the primary component. Every later section (Screens, Components, Copy Index) reconciles against this table; a row with no downstream coverage is a dropped element.

| Node (name + id) | Copy (verbatim / TBD) | Component | Appears in states |
| ---------------- | --------------------- | --------- | ----------------- |

Capture persistent elements (banners, footers, helper lines, chrome) **once**, with their full state-presence — a node that shows in a populated state must not be omitted because only the empty-state frame was inventoried.

## Screens _(mandated)_

For each screen/element node (one subsection each):

- **Figma node:** file key + node id (the specific screen node, not the section).
- **Layout:** structure in words (columns, sticky panels, ordering).
- **Components:** the repo components used (full list goes in the Components table below).
- **State coverage:** every state this screen renders — empty / loading / error / in-flight / disabled / populated.
- **State transitions:** a `trigger → from-state → to-state → resulting UI` table. Transitions are **inferred** (the Figma MCP does not expose prototype edges) — any unclear trigger/target/guard/initial-state must be resolved with the user or parked in Open Questions, **never assumed**.

## BE field map _(mandated)_

| FE control | BE field (entity.field) | Notes |
| ---------- | ----------------------- | ----- |

One row per persisted value; map each FE control to the named BE field from the linked ticket. Flag any FE control with no BE field, and any BE field with no FE control.

## Components _(mandated)_

| Figma component name | Repo component | Import |
| -------------------- | -------------- | ------ |

Resolved via the repo's component catalog (from `.claude/second-shift/design-tokens/*.md`, or discovered conservatively from the FE app's component library). Unresolved → list in Open Questions, never guess.

## Copy Index _(mandated)_

Every user-facing string, **verbatim** from the Figma instance nodes. Headings, labels, helper text, button text, captions, snackbars, validation messages, empty-state copy. Mark anything not yet in Figma as `TBD — <what's missing>`.

## Locked formatting / number rules _(mandated)_

The exact rendered formatting the design fixes — so implementation can't silently change rounding, unit suffixes, thousands separators, currency-symbol placement, or date patterns. One row per formatted datum, read from the Figma instance's rendered text node (the Copy Index captures the verbatim string; this captures the _rule_ behind it). Write `N/A — no formatted numeric/date data on this screen` if the screen renders none.

| Datum             | Format                                                | Example from design |
| ----------------- | ----------------------------------------------------- | ------------------- |
| Price / total     | currency, 2-dp, thousands separator, leading symbol   | `$1,234.50`         |
| Quantity          | integer (no decimals)                                 | `12`                |
| Discount          | percentage, integer                                   | `15%`               |
| Order / ship date | `MMM D, YYYY` (match the Figma format)                | `Jun 21, 2026`      |

## Acceptance Criteria _(mandated)_

Observable, testable behavior. Include at least one **negative** AC (what must NOT happen / what is rejected). A general spec reviewer requires testable ACs with a negative case.

## Open Questions _(mandated)_

Numbered list for the designer/PM: every TBD, every unresolved component, every behavior the Figma doesn't settle. This is where undecided behavior goes — do not invent an answer.

## Out of scope _(mandated)_

What this spec deliberately excludes.

---

## Terminology _(conditional — only if copy/naming is in flux)_

Figma label → shipped copy mapping, where the two differ or a name is still being decided.

## Mutation flows _(conditional — only if the screen mutates state)_

For each create/update/delete/toggle: trigger → request → success UI → failure UI.

## Per-section validation _(conditional — only if the screen has validated inputs)_

Per field: rules, and FE-side mirrors of any BE invariant (with the BE source).

## Design Decisions _(conditional — only where the implementation deviates from a 1:1 Figma transcription)_

Any choice not dictated by Figma, with its rationale. For a faithful transcription this is usually empty.
