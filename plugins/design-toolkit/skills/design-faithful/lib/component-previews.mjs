// design-faithful — representative component preview set + assembler (#200 push direction).
//
// The "representative set" the issue asks for, split per the intake decision (D1):
//   • Token cards            — emitted mechanically from globals.css (emit-tokens.mjs).
//   • Composite cards        — @acme/ui components that ALREADY bind to acme tokens, so
//                              their previews are faithful transcriptions of the real visuals.
//   • Primitive cards        — stock shadcn primitives (button/badge/card) that use Tailwind
//                              gray/primary classes, rendered via the EXPLICIT, documented
//                              role→token map below (SHADCN_TOKEN_MAP). The map is the one design
//                              decision; it is written down once, not re-invented per component.
//
// Variants are sibling DOM instances within one preview (#194 Probe 4). Pure, dependency-free.

import { emitCard } from './emit-card.mjs'
import { emitTokenCards, tokenRootCss } from './emit-tokens.mjs'

// The documented shadcn-class → acme-token mapping used to render the primitive previews.
// Source of the shadcn classes: packages/ui/src/components/{button,badge,card}.tsx (stock
// Tailwind). Target tokens: apps/web/src/app/globals.css. This is documentation AND the basis the
// primitive bodies below are authored against — keep them in sync.
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

// Confidence ring SVG — a faithful port of packages/ui/src/confidence-ring.tsx so the preview
// math matches the real component rather than hardcoding (possibly wrong) dash values.
function ringSvg(score, tokenVar, size, stroke) {
  const radius = (size - stroke) / 2
  const circumference = 2 * Math.PI * radius
  const center = size / 2
  const color = `var(${tokenVar})`
  if (score === null) {
    return (
      `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="Unscored confidence">` +
      `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="var(--ink-4)" stroke-width="${stroke}"/></svg>`
    )
  }
  const clamped = Math.max(0, Math.min(100, score))
  const fill = (clamped / 100) * circumference
  return (
    `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="${Math.round(clamped)}% confidence">` +
    `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="var(--ink-4)" stroke-width="${stroke}" opacity="0.2"/>` +
    `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" ` +
    `stroke-dasharray="${fill.toFixed(2)} ${circumference.toFixed(2)}" transform="rotate(-90 ${center} ${center})"/>` +
    `<text x="${center}" y="${center}" text-anchor="middle" dominant-baseline="central" fill="${color}" ` +
    `style="font-family:ui-monospace,monospace;font-size:${Math.round(size * 0.32)}px;font-weight:600;">${Math.round(clamped)}%</text></svg>`
  )
}

// confidence-badge tiers (mirrors getTier in confidence-badge.tsx; --low is shared by Low and
// Best-guess<40, differentiated by glyph). bg = color-mix(token, transparent 85%).
const CONF_TIERS = [
  { label: 'High', token: '--hi', glyph: '●●●●●', pct: 92 },
  { label: 'Good', token: '--good', glyph: '●●●●○', pct: 78 },
  { label: 'Moderate', token: '--mod', glyph: '●●●○○', pct: 61 },
  { label: 'Low', token: '--low', glyph: '●●○○○', pct: 47 },
  { label: 'Best guess', token: '--low', glyph: '●○○○○', pct: 22 },
  { label: 'Best guess', token: '--ink-4', glyph: '○○○○○', pct: null }
]

const confidenceBadge = (t) =>
  chip(
    `color:var(${t.token});background:color-mix(in oklab, var(${t.token}), transparent 85%);`,
    `<span aria-hidden="true">${t.glyph}</span><span>${t.label}</span>` +
      (t.pct == null ? '' : `<span style="opacity:.7;font-variant-numeric:tabular-nums;">${t.pct}%</span>`)
  )

// type-chip recipes (verbatim from the .type-* rules in globals.css).
const TYPE_CHIPS = [
  { label: 'Endurance', style: 'background:color-mix(in oklab, var(--hi), transparent 80%);color:var(--hi);' },
  { label: 'Intervals', style: 'background:color-mix(in oklab, var(--accent), transparent 78%);color:var(--accent);' },
  { label: 'Recovery', style: 'background:color-mix(in oklab, var(--good), transparent 80%);color:var(--good);' },
  { label: 'Commute', style: 'background:color-mix(in oklab, var(--mod), transparent 80%);color:var(--mod);' },
  { label: 'Race', style: 'background:color-mix(in oklab, var(--low), transparent 78%);color:var(--low);' },
  { label: 'Group Ride', style: 'background:var(--accent-soft);color:var(--accent);' },
  { label: 'Other', style: 'background:var(--surface-3);color:var(--ink-3);' }
]

// data-stream-chip recipes (verbatim from the .stream-* rules in globals.css).
const STREAM_CHIPS = [
  { label: 'POWER', style: 'background:var(--accent-soft);color:var(--accent);' },
  { label: 'HR', style: 'background:color-mix(in oklab, var(--low), transparent 78%);color:var(--low);' },
  { label: 'CAD', style: 'background:color-mix(in oklab, var(--accent), transparent 78%);color:var(--accent);' },
  { label: 'GPS', style: 'background:color-mix(in oklab, var(--good), transparent 78%);color:var(--good);' },
  // 'HR' again on purpose = the .stream-unavailable variant (dashed border, ink-4) — not a dup bug.
  { label: 'HR', style: 'background:transparent;color:var(--ink-4);border:1px dashed var(--ink-4);' }
]

const SEGMENTS = [
  { label: 'Power', selected: true },
  { label: 'HR', selected: false },
  { label: 'Cadence', selected: false }
]

const segment = (s) =>
  `<button style="border:none;border-radius:999px;padding:4px 14px;font-size:14px;font-weight:500;` +
  `cursor:pointer;font-family:inherit;` +
  (s.selected
    ? 'background:var(--surface-3);box-shadow:var(--shadow);color:var(--ink);'
    : 'background:transparent;color:var(--ink-3);') +
  `">${s.label}</button>`

// Type scale. globals.css defines NO --text-* custom properties, so the typographic scale is the
// Tailwind size steps the previewed components actually use (text-xs/sm/base/lg) plus the two
// families: system-ui for body/UI and JetBrains Mono for numerics (var(--font-jetbrains-mono),
// referenced by confidence-ring.tsx). Authored here — the one Tokens card NOT extracted from
// globals.css — so the issue's "type scale" token card is faithful to what the design system uses.
const SANS = "system-ui, -apple-system, 'Segoe UI', sans-serif"
const MONO = 'var(--font-jetbrains-mono, ui-monospace), monospace'
const TYPE_SCALE = [
  { name: 'text-lg · 18 / 600', size: 18, weight: 600, family: SANS, sample: 'Threshold effort' },
  { name: 'base · 16 / 500', size: 16, weight: 500, family: SANS, sample: 'Detected from an outdoor ride' },
  { name: 'text-sm · 14 / 400', size: 14, weight: 400, family: SANS, sample: '4 × 8 min @ FTP' },
  { name: 'text-xs · 12 / 600', size: 12, weight: 600, family: SANS, sample: 'POWER · HR · CAD' },
  { name: 'mono · tabular-nums', size: 16, weight: 600, family: MONO, sample: '274 W · 92%' }
]

const typeScaleRow = (t) =>
  `<div class="ds-stack" style="gap:2px;">` +
  `<span style="font-size:11px;font-family:ui-monospace,monospace;color:var(--ink-3);">${t.name}</span>` +
  `<span style="font-size:${t.size}px;font-weight:${t.weight};font-family:${t.family};color:var(--ink);` +
  `font-variant-numeric:tabular-nums;">${t.sample}</span></div>`

/** The "Type scale" Tokens card (authored — see TYPE_SCALE note). @param {string} tokenCss */
export function typeScaleCard(tokenCss) {
  return emitCard({
    group: 'Tokens',
    name: 'Type scale',
    subtitle: 'system-ui · JetBrains Mono numerics',
    slug: 'tokens-type-scale',
    tokenCss,
    body: `<div class="ds-stack" style="gap:16px;">\n    ${TYPE_SCALE.map(typeScaleRow).join('\n    ')}\n  </div>`
  })
}

// ── the representative preview specs ─────────────────────────────────────────
// Each: { group, name, subtitle, slug, body }. tokenCss is injected by buildDesignSystem.
export const COMPONENT_PREVIEWS = [
  // Composites — faithful, token-bound.
  {
    group: 'Composites',
    name: 'ConfidenceBadge',
    subtitle: 'High / Good / Moderate / Low / Best guess',
    slug: 'confidence-badge',
    body: `<div class="ds-row">\n    ${CONF_TIERS.map(confidenceBadge).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'ConfidenceRing',
    subtitle: 'High / Good / Moderate / Low / Unscored',
    slug: 'confidence-ring',
    body:
      `<div class="ds-row" style="gap:18px;">\n    ` +
      [
        ringSvg(92, '--hi', 48, 5),
        ringSvg(78, '--good', 48, 5),
        ringSvg(61, '--mod', 48, 5),
        ringSvg(47, '--low', 48, 5),
        ringSvg(null, '--ink-4', 48, 5)
      ].join('\n    ') +
      `\n  </div>`
  },
  {
    group: 'Composites',
    name: 'TypeChip',
    subtitle: 'ride-type palette',
    slug: 'type-chip',
    body: `<div class="ds-row">\n    ${TYPE_CHIPS.map((t) => chip(t.style, t.label)).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'DataStreamChip',
    subtitle: 'power / hr / cadence / gps / unavailable',
    slug: 'data-stream-chip',
    body: `<div class="ds-row">\n    ${STREAM_CHIPS.map((s) => chip(s.style + 'padding:2px 10px;', s.label)).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'SegmentedControl',
    subtitle: 'single-select toggle group',
    slug: 'segmented-control',
    body:
      `<div role="group" aria-label="Metric" style="display:inline-flex;align-items:center;gap:2px;` +
      `border-radius:999px;padding:2px;background:var(--surface-2);">\n    ${SEGMENTS.map(segment).join('\n    ')}\n  </div>`
  },
  // Primitives — via SHADCN_TOKEN_MAP.
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
      `      <div style="font-size:18px;font-weight:600;color:var(--ink);">Threshold effort</div>\n` +
      `      <div style="font-size:14px;color:var(--ink-3);margin-top:4px;">4 × 8 min @ FTP</div>\n` +
      `    </div>\n` +
      `    <div style="padding:16px 20px 20px;font-size:14px;color:var(--ink-2);">` +
      `Detected from a chaotic outdoor ride.</div>\n  </div>`
  }
]

/**
 * Assemble the full local design-system file set from the acme token source.
 * @param {{globalsCss: string}} input  already-sanitized apps/web globals.css text
 * @returns {{path:string, content:string}[]}  token cards + component cards, ready for planSync
 */
export function buildDesignSystem(input) {
  const globalsCss = (input && input.globalsCss) || ''
  const tokenCss = tokenRootCss(globalsCss)
  // Token cards: the CSS-property ramps (emitTokenCards) + the authored Type scale card.
  const tokenCards = [...emitTokenCards(globalsCss), typeScaleCard(tokenCss)]
  const componentCards = COMPONENT_PREVIEWS.map((spec) => emitCard({ ...spec, tokenCss }))
  return [...tokenCards, ...componentCards]
}
