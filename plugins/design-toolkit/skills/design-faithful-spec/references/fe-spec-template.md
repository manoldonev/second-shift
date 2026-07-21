# FE Spec: <screen/component name>

> Filled in by the `design-faithful-spec` skill from a sanitized Claude Design handoff
> contract (the `extractContract` output of the contract lib). One spec per screen/component.
> **Faithful = visual/UX fidelity onto the repo's real stack** (per the repo's
> `.claude/second-shift/design-tokens/*.md` reference, or conservative discovery), never the
> handoff README's stack claims.
>
> Rules that apply to every section:
> - **No silent drops.** Every element the handoff renders gets a row in the inventory.
> - **Infer, never invent.** A static handoff has no interaction edges. Where behavior is
>   inferred, say so and mark it. Where it is genuinely ambiguous, it goes to **Open
>   Questions** (and the implementer routes it to the engineer, e.g. via an interview skill
>   such as `intake-toolkit:grill-me` where installed) — it is never guessed into a
>   definite statement.
> - **Map to the real component**, not a hand-rolled clone (see the component-map section).

## 0. Source & provenance

| Field | Value |
| --- | --- |
| Handoff project id | `<projectId>` (opened by id; `list_projects` does not list handoff bundles) |
| Source files | `<styles.css, screens/<name>.jsx, screenshots/<name>.png>` |
| Reference screenshot | `<contract.screenshots[] entry for this screen>` |
| Handoff stack claim | `<what the handoff README declares, e.g. Next15/React19/Convex/Clerk>` |
| **Stack-claim mismatch** | `<the delta vs the repo's real stack — flag explicitly, or "none">` |
| Contract confidence | `<High / Good / Moderate / Low — how much was extracted vs inferred>` |

## 1. Completeness inventory

One row per rendered element — **no silent drops**. `Disposition` is what happens to it in
the real implementation: `reuse` (a primitive from the repo's primitives package / existing
FE-app component), `compose` (built from primitives), `new` (no analog — justify), or `drop`
(with reason).

| # | Element | Role / semantics | Source (file:locus) | Disposition | Maps to |
| - | ------- | ---------------- | ------------------- | ----------- | ------- |
| 1 | `<e.g. Back button>` | `<button / link / heading / region>` | `<screens/<name>.jsx>` | `<reuse>` | `<Button from the primitives package>` |

## 2. Screen spec(s)

For each screen/region: layout (container width, padding, the flex/grid structure from the
contract's `layout.primitives`), the visual hierarchy, and the responsive behavior at the
contract's `breakpoints`.

- **Container:** `<max-width, padding>`
- **Structure:** `<the row/col/grid composition>`
- **Responsive:** `<what changes at each breakpoint — e.g. "≤759px: stats strip → 2-col grid, min tap target 44px">`

## 3. Behavioral / state contract

The part a static source **cannot** encode — fill from the contract's inferred markers plus
explicit reasoning. Every inferred row MUST be marked `inferred`.

| Surface | State | Behavior | Default | Source |
| ------- | ----- | -------- | ------- | ------ |
| `<whole screen>` | loading | `<skeleton? which primitives-package Skeleton?>` | — | inferred |
| `<whole screen>` | empty | `<empty-state copy + affordance>` | — | inferred |
| `<whole screen>` | error | `<message + retry?>` | — | inferred |
| `<list/repeating group>` | populated | `<row template, ordering, truncation/overflow rule>` | `<n shown>` | `<observed / inferred>` |
| `<interactive el>` | hover / focus-visible / active | `<token/transition from contract.inferred.states>` | — | inferred |

- **Repeating-group behavior:** `<how many rendered, sort, truncation, "show more">`
- **Truncation / overflow:** `<text clamp, ellipsis, scroll>`
- **Transitions:** `<inferred from CSS transition/animation; never invented>`

## 4. Design → real-stack component map

Each design element → the concrete target in the repo. Reuse before composing; compose
before new. Primitive inventory and `cn()`/class-merge utility location: per the repo's
design-tokens extension file (or conservative discovery).

| Design element | Real target | Notes |
| -------------- | ----------- | ----- |
| `<card surface>` | `<Card / CardHeader / CardContent from the primitives package>` | — |
| `<segmented toggle>` | `<the primitives-package toggle-group component>` | — |
| `<chart>` | `<the repo's chart-library wrapper component>` | — |
| `<data fetch>` | `<the repo's established data-fetch pattern>` | — |

- **Tokens:** map handoff CSS custom properties → the repo's global token of the same role
  (roles + source file per the design-tokens extension file). Use the repo's tokens, **not
  the handoff's raw token values**.

## 5. Copy index

Every literal string the screen renders (so nothing is paraphrased in implementation).

| Key | Literal text | Notes (casing, dynamic parts) |
| --- | ------------ | ----------------------------- |
| `<back-link>` | `<"← Back to Orders">` | — |

## 6. Accessibility

From the contract's `a11y` block + inferred. Landmarks, roles, focus order, focus-visible
treatment, contrast intent, reduced-motion, skip-link, `sr-only` usage.

- **Landmarks / roles:** `<...>`
- **Focus order & focus-visible:** `<...>`
- **Reduced motion / skip-link / sr-only:** `<...>`

## 7. Locked formatting / number rules

The formatting the design fixes — units, rounding, date/number formats. The implementation
must not silently change these.

| Datum | Format | Example from design |
| ----- | ------ | ------------------- |
| `<value>` | `<integer + " units">` | `<"1,240 units">` |
| `<duration>` | `<"m" / "h:mm">` | `<"45m">` |
| `<date>` | `<"Weekday · Month D">` | `<"Thursday · January 29">` |

## 8. Open Questions

Anything a static source cannot determine and that materially affects implementation. These
are NOT guessed — route each to the engineer (e.g. via `intake-toolkit:grill-me` where
installed, or a human) before implementing the affected part.

- [ ] `<question — and which inventory rows / behavioral rows it blocks>`
