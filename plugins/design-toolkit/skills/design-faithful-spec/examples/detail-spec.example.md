# FE Spec: Order Detail — "the verdict moment"

> **Worked example, produced offline** by applying the `design-faithful-spec` process to the
> committed handoff fixture `../../design-faithful/fixtures/handoff.mjs` (real `styles.css` +
> `screens/detail.jsx` bytes captured from `design_handoff_acme_redesign/`). No live
> DesignSync call — this is the reproducible AC demonstration (live auth is interactive-only;
> probe-findings Probe 7). It is illustrative, not a build target.

## 0. Source & provenance

| Field | Value |
| --- | --- |
| Handoff project id | `019e07e0-7c05-7ca3-b19d-71eb82e7fc32` (opened by id) |
| Source files | `styles.css`, `screens/detail.jsx`, `screenshots/order-detail.png` |
| Reference screenshot | `design_handoff_acme_redesign/screenshots/order-detail.png` |
| Handoff stack claim | README declares Next 15 / React 19 / Convex / Clerk |
| **Stack-claim mismatch** | **Yes** — acme is Next 14 / React 18 / NestJS+Drizzle. Implement onto the real stack; ignore the handoff's framework/data claims (visual/UX fidelity only). |
| Contract confidence | Good — tokens/layout/copy are observed; all interaction edges are inferred (static source). |

## 1. Completeness inventory

| # | Element | Role / semantics | Source (file:locus) | Disposition | Maps to |
| - | ------- | ---------------- | ------------------- | ----------- | ------- |
| 1 | Back link "← Back to Orders" | navigation button | `detail.jsx` (top `<button onClick={onBack}>`) | reuse | `Button` variant ghost/link (`@acme/ui`) + Next `Link`/router |
| 2 | Verdict card surface | region container, theme-variant (`verdict-cold`/`verdict-warm`) | `detail.jsx` `<div className=verdict-*>` | reuse | `Card` / `CardContent` (`@acme/ui`) on the active theme |
| 3 | Eyebrow "Verdict · Thursday · January 29" | label (date context) | `detail.jsx` eyebrow `<span>` | compose | text, `--ink-3`, uppercase |
| 4 | Order id (mono) | metadata | `detail.jsx` `<span className=mono>{a.id}</span>` | compose | `.mono` (JetBrains Mono), `--ink-4` |
| 5 | "We saw" label | caption | `detail.jsx` | compose | text, `--ink-3` |
| 6 | "4× Priority" headline | `h1` (page main heading) | `detail.jsx` `<h1>` 76px | reuse | semantic `<h1>`; size from typography scale |
| 7 | Verdict description | paragraph w/ emphasis | `detail.jsx` `<p>` + `<strong>` | compose | `<p>` `--ink-2`, `<strong>` `--ink` |
| 8 | "This isn't right" | inline correction button | `detail.jsx` underline `<button>` | reuse | `Button` variant link |
| 9 | Stats strip | bordered row of stat cells | `detail.jsx` `<div className=row borderTop>` | compose | analog: `apps/web/src/app/orders/stats-ribbon.tsx` |
| 10 | Stat cell — Duration `45m` | label + `.hero-num` | `detail.jsx` `<div className=col gap-1>` | compose | label `--ink-3` 10px + hero number |
| 11 | Stat cell — Avg Value `1,050 units` | label + `.hero-num` | `detail.jsx` | compose | as #10 |

## 2. Screen spec

- **Container:** `max-width: 1320px`, centered, `padding: 24px 28px 80px`.
- **Structure:** back link → verdict `Card` (radius 18, `padding: 30px 36px`) → inside it: eyebrow row (`row center gap-2`) → headline block (`We saw` / `h1` / description `p`) → stats strip (`row`, `border-top: 1px var(--line)`, `margin-top: 28`, `padding-top: 22`).
- **Responsive (breakpoint `max-width: 759px`, from contract):** surface radius 14px → 12px; the stats strip switches to a 2-column grid (`grid-template-columns: repeat(2, 1fr); gap: 16px`); interactive targets get `min-height: 44px`.

## 3. Behavioral / state contract

| Surface | State | Behavior | Default | Source |
| ------- | ----- | -------- | ------- | ------ |
| whole screen | loading | skeleton verdict card + stat cells (`Skeleton` from `@acme/ui`) | — | inferred |
| whole screen | empty / not-found | "order not found" + back affordance | — | inferred |
| whole screen | error | message + retry; do not render a partial verdict | — | inferred |
| verdict card | theme | renders `verdict-cold` (dark) or `verdict-warm` (light) per active theme | cold (dark-first) | observed (variant pair) |
| stats strip | populated | the static slice shows 2 cells (Duration, Avg Value); real screen is data-driven and likely shows more — **see Open Questions** | 2 shown | observed (slice) |
| back link, "This isn't right" | hover / focus-visible | focus-visible: `outline: 2px solid var(--accent); outline-offset: 2px` | — | inferred (from CSS) |
| `*` | reduced-motion | `prefers-reduced-motion` collapses animations to ~0 | — | observed |

- **Data-driven, not the literal sample.** The static handoff renders one baked instance
  (`window.ACME_DATA.detail`). In the real screen every value (date, `4× Priority`, item
  detail, stats, id) comes from the order record — the design's strings are the *format*,
  not the content.
- **Transitions:** only those present in CSS (`.act-row` background 140ms; focus outlines) —
  no others invented.

## 4. Design → real-stack component map

| Design element | Real target | Notes |
| -------------- | ----------- | ----- |
| Verdict card surface | `Card` / `CardContent` (`@acme/ui`) | radius/padding via className; lives on the theme |
| Back link, "This isn't right" | `Button` (`@acme/ui`) variants ghost/link | not hand-rolled `<button>` |
| Stats strip | compose, mirroring `apps/web/src/app/orders/stats-ribbon.tsx` | reuse the existing stat-cell pattern |
| Theme cold/warm | acme theme classes in `globals.css` | global, not screen-local |
| Order data | Server-Component `fetch` of the order by id | the established `apps/web` data pattern |

- **Token mapping** (handoff role → acme `globals.css` role; use acme's values, **not
  the handoff's raw token values**): `--bg`→`--bg`, `--surface[-2/-3]`→same, `--ink`/`--ink-2`/
  `--ink-3`/`--ink-4`→same ink ramp, `--line`→`--line`, `--accent`→`--accent`, confidence
  `--hi`/`--good`/`--mod`/`--low`→same tiers.

## 5. Copy index

| Key | Literal text | Notes |
| --- | ------------ | ----- |
| back-link | `← Back to Orders` | leading arrow glyph is part of the copy |
| eyebrow | `Verdict · Thursday · January 29` | "Verdict · " + `<Weekday> · <Month D>` (date is dynamic) |
| saw-label | `We saw` | |
| verdict-headline | `4× Priority` | format `<count>× <TierName>` (dynamic) |
| verdict-desc | `Four batches of 1,240 units (86% of target).` | `1,240 units` is emphasized (`<strong>`) |
| correction | `This isn't right` | |
| stat-label-1 / stat-label-2 | `Duration` / `Avg Value` | |
| stat-value-1 / stat-value-2 | `45m` / `1,050 units` | dynamic |

## 6. Accessibility

- **Landmarks / roles:** verdict `<h1>` is the page's single main heading; the screen body is
  the `main` landmark; back link and correction are real `<button>`/link controls.
- **Focus order & focus-visible:** back link → correction → (stats are non-interactive). All
  focusables get `outline: 2px solid var(--accent); outline-offset: 2px` (from CSS).
- **Reduced motion / skip-link / sr-only:** honor `prefers-reduced-motion`; a `.skip-link`
  (revealed on focus) and `.sr-only` utility exist in the handoff and should carry over.

## 7. Locked formatting / number rules

| Datum | Format | Example from design |
| ----- | ------ | ------------------- |
| Value | integer + `" units"` | `1,240 units`, `1,050 units` |
| Target % | `(<n>% of target)` | `(86% of target)` |
| Headline | `<count>× <TierName>` | `4× Priority` |
| Item detail | `<n> units` | `1,240 units` |
| Duration (summary) | compact `<n>m` / `<h>:<mm>` | `45m` |
| Date | `<Weekday> · <Month D>` | `Thursday · January 29` |

## 8. Open Questions

- [ ] **"This isn't right" correction flow** — the static source has no interaction edge.
  What does it open (inline editor? feedback sheet? re-classify request)? Blocks inventory
  row #8's behavior. → `grill-me`.
- [ ] **Stats strip cardinality** — the fixture slice shows 2 cells; the real order-detail
  screen likely surfaces more (subtotal, tax, line-item count, status…). Which stats, in what order? Blocks
  inventory rows #9–11 and §2 structure. → `grill-me`.
- [ ] **Empty/error copy** — exact strings for not-found / load-error are not in the static
  design (inferred placeholders above). → `grill-me`.
