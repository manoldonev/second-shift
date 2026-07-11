// design-faithful — component-preview assembler (design-system push direction).
//
// This is the ENGINE, not a product design system. It is domain-empty by default: the exported
// COMPONENT_PREVIEWS below carry only generic, universal shadcn primitives (button/badge/card) —
// no product domain. A consumer drives the richer surface by passing its own preview specs +
// token roles (sourced from its .claude/second-shift design-system reference) into
// buildDesignSystem; the defaults leak nothing.
//
// The split (per the intake decision D1) a consumer reference is expected to follow:
//   • Token cards      — emitted mechanically from globals.css (emit-tokens.mjs).
//   • Composite cards  — components that ALREADY bind to the consumer's tokens, so their previews
//                        are faithful transcriptions of the real visuals (consumer-supplied).
//   • Primitive cards  — stock shadcn primitives (button/badge/card) that use Tailwind
//                        gray/primary classes, rendered via an EXPLICIT, documented role→token
//                        map (SHADCN_TOKEN_MAP). The map is the one design decision; it is written
//                        down once, not re-invented per component.
//
// Variants are sibling DOM instances within one preview. Pure, dependency-free.
// See fixtures/component-previews.mjs for a complete neutral example spec set (composites too).

import { emitCard } from './emit-card.mjs'
import { emitTokenCards, tokenRootCss, TOKEN_RAMPS } from './emit-tokens.mjs'

// The documented shadcn-class → design-token mapping a consumer uses to render its primitive
// previews. Source of the shadcn classes: the consumer's ui package (stock Tailwind). Target
// tokens: the consumer's globals.css. This is documentation AND the basis primitive bodies are
// authored against — a consumer keeps the two in sync.
export const SHADCN_TOKEN_MAP = Object.freeze({
  'bg-primary': '--accent fill, --accent-ink text',
  'bg-gray-100 / dark:bg-gray-800 (secondary)': '--surface-2 fill, --ink text',
  'border-gray-200 / dark:border-gray-800 (outline)': '--line border, transparent fill, --ink text',
  'ghost': '--ink-2 text on transparent (hover → --surface-2)',
  'bg-red-500 (destructive)': '--low fill, --accent-ink text',
  'text-foreground / text-gray-500 (muted)': '--ink / --ink-3 text',
  'rounded-md / rounded-xl': '8px / var(--radius)',
  'shadow-sm': 'var(--shadow)'
})

// ── small preview-body helpers ───────────────────────────────────────────────
const chip = (style, text) =>
  `<span style="display:inline-flex;align-items:center;gap:6px;border-radius:999px;` +
  `padding:4px 12px;font-size:12px;font-weight:600;${style}">${text}</span>`

const btn = (style, text) =>
  `<button style="display:inline-flex;align-items:center;justify-content:center;height:40px;` +
  `padding:0 18px;border-radius:8px;border:none;font-size:14px;font-weight:600;cursor:pointer;` +
  `font-family:inherit;${style}">${text}</button>`

// ── Type scale ───────────────────────────────────────────────────────────────
// globals.css typically defines NO --text-* custom properties, so the typographic scale is the
// Tailwind size steps the previewed components actually use (text-xs/sm/base/lg) plus two
// families: system-ui for body/UI and a mono for numerics (var(--font-jetbrains-mono)). This
// neutral default is domain-empty; a consumer passes its own scale into typeScaleCard.
const SANS = "system-ui, -apple-system, 'Segoe UI', sans-serif"
const MONO = 'var(--font-jetbrains-mono, ui-monospace), monospace'
const TYPE_SCALE = [
  { name: 'text-lg · 18 / 600', size: 18, weight: 600, family: SANS, sample: 'Section heading' },
  { name: 'base · 16 / 500', size: 16, weight: 500, family: SANS, sample: 'Body copy for a record detail' },
  { name: 'text-sm · 14 / 400', size: 14, weight: 400, family: SANS, sample: 'Secondary label text' },
  { name: 'text-xs · 12 / 600', size: 12, weight: 600, family: SANS, sample: 'STATUS · META · TAG' },
  { name: 'mono · tabular-nums', size: 16, weight: 600, family: MONO, sample: '1,280 · 98%' }
]

const typeScaleRow = (t) =>
  `<div class="ds-stack" style="gap:2px;">` +
  `<span style="font-size:11px;font-family:ui-monospace,monospace;color:var(--ink-3);">${t.name}</span>` +
  `<span style="font-size:${t.size}px;font-weight:${t.weight};font-family:${t.family};color:var(--ink);` +
  `font-variant-numeric:tabular-nums;">${t.sample}</span></div>`

/**
 * The "Type scale" Tokens card.
 * @param {string} tokenCss inlined `:root { … }` block
 * @param {{name:string, size:number, weight:number, family:string, sample:string}[]} [scale]
 *   the type scale rows, sourced from the consumer's design-system reference. Defaults to the
 *   neutral TYPE_SCALE.
 */
export function typeScaleCard(tokenCss, scale = TYPE_SCALE) {
  return emitCard({
    group: 'Tokens',
    name: 'Type scale',
    subtitle: 'system-ui · mono numerics',
    slug: 'tokens-type-scale',
    tokenCss,
    body: `<div class="ds-stack" style="gap:16px;">\n    ${scale.map(typeScaleRow).join('\n    ')}\n  </div>`
  })
}

// ── the representative preview specs ─────────────────────────────────────────
// Domain-empty by default: only generic, universal shadcn primitives (via SHADCN_TOKEN_MAP), with
// neutral placeholder copy. A consumer passes its own richer specs — each
// { group, name, subtitle, slug, body } (tokenCss is injected by buildDesignSystem) — sourced from
// its design-system reference. See fixtures/component-previews.mjs for a complete neutral example
// set including composites.
export const COMPONENT_PREVIEWS = [
  {
    group: 'Primitives',
    name: 'Button',
    subtitle: 'default / secondary / outline / ghost / destructive',
    slug: 'button',
    body:
      `<div class="ds-row">\n    ` +
      [
        btn('background:var(--accent);color:var(--accent-ink);', 'Default'),
        btn('background:var(--surface-2);color:var(--ink);', 'Secondary'),
        btn('background:transparent;color:var(--ink);border:1px solid var(--line);', 'Outline'),
        btn('background:transparent;color:var(--ink-2);', 'Ghost'),
        btn('background:var(--low);color:var(--accent-ink);', 'Destructive')
      ].join('\n    ') +
      `\n  </div>`
  },
  {
    group: 'Primitives',
    name: 'Badge',
    subtitle: 'default / secondary / outline / destructive',
    slug: 'badge',
    body:
      `<div class="ds-row">\n    ` +
      [
        chip('background:var(--accent);color:var(--accent-ink);padding:2px 10px;font-size:12px;', 'Default'),
        chip('background:var(--surface-2);color:var(--ink);padding:2px 10px;font-size:12px;', 'Secondary'),
        chip('background:transparent;color:var(--ink);border:1px solid var(--line);padding:2px 10px;font-size:12px;', 'Outline'),
        chip('background:var(--low);color:var(--accent-ink);padding:2px 10px;font-size:12px;', 'Destructive')
      ].join('\n    ') +
      `\n  </div>`
  },
  {
    group: 'Primitives',
    name: 'Card',
    subtitle: 'surface container with header + content',
    slug: 'card',
    body:
      `<div style="width:300px;background:var(--surface);border:1px solid var(--line);` +
      `border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;">\n` +
      `    <div style="padding:20px 20px 0;">\n` +
      `      <div style="font-size:18px;font-weight:600;color:var(--ink);">Record title</div>\n` +
      `      <div style="font-size:14px;color:var(--ink-3);margin-top:4px;">Updated 3 days ago</div>\n` +
      `    </div>\n` +
      `    <div style="padding:16px 20px 20px;font-size:14px;color:var(--ink-2);">` +
      `A short summary of this record's contents.</div>\n  </div>`
  }
]

/**
 * Assemble the full local design-system file set from a consumer's token source + preview specs.
 * @param {{globalsCss?: string,
 *          previews?: {group?:string, name:string, subtitle?:string, slug:string, body:string}[],
 *          ramps?: {key:string, name:string, subtitle?:string, names:string[]}[],
 *          typeScale?: {name:string, size:number, weight:number, family:string, sample:string}[]}} input
 *   - `globalsCss` — already-sanitized globals.css text (the consumer's token source).
 *   - `previews`   — component preview specs from the consumer's design-system reference. Defaults
 *                    to the neutral/empty COMPONENT_PREVIEWS so the published output hardcodes none.
 *   - `ramps`      — token roles (see emit-tokens.TOKEN_RAMPS). Defaults to the neutral TOKEN_RAMPS.
 *   - `typeScale`  — type scale rows (see typeScaleCard). Defaults to the neutral TYPE_SCALE.
 * @returns {{path:string, content:string}[]}  token cards + component cards, ready for planSync
 */
export function buildDesignSystem(input) {
  const globalsCss = (input && input.globalsCss) || ''
  const previews = (input && input.previews) || COMPONENT_PREVIEWS
  const ramps = (input && input.ramps) || TOKEN_RAMPS
  const typeScale = (input && input.typeScale) || TYPE_SCALE
  const tokenCss = tokenRootCss(globalsCss)
  // Token cards: the CSS-property ramps (emitTokenCards) + the authored Type scale card.
  const tokenCards = [...emitTokenCards(globalsCss, ramps), typeScaleCard(tokenCss, typeScale)]
  const componentCards = previews.map((spec) => emitCard({ ...spec, tokenCss }))
  return [...tokenCards, ...componentCards]
}
