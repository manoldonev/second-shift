// design-faithful fixtures — a complete NEUTRAL example spec set for the design-system push.
//
// The lib (lib/component-previews.mjs) is a domain-empty engine: it ships with no hardcoded
// component set. This fixture plays the role of "a consumer's design-system reference" — the
// preview specs, token roles, and type scale a consumer would source from its own
// .claude/second-shift design tokens and pass into buildDesignSystem. It is used by tests and as
// a worked example of the push mechanism. All content here is a generic CRUD web-app design
// system — domain-empty on purpose.
//
// Self-contained (inline render helpers, no imports) so it can be dropped in as an example.
// Feed it in via:  buildDesignSystem({ globalsCss, previews: componentPreviews, ramps: tokenRamps,
//                                       typeScale })

// ── small preview-body helpers ───────────────────────────────────────────────
const chip = (style, text) =>
  `<span style="display:inline-flex;align-items:center;gap:6px;border-radius:999px;` +
  `padding:4px 12px;font-size:12px;font-weight:600;${style}">${text}</span>`

const btn = (style, text) =>
  `<button style="display:inline-flex;align-items:center;justify-content:center;height:40px;` +
  `padding:0 18px;border-radius:8px;border:none;font-size:14px;font-weight:600;cursor:pointer;` +
  `font-family:inherit;${style}">${text}</button>`

// Progress ring SVG — renders a token-coloured arc for a 0–100 value (null = indeterminate).
function ringSvg(value, tokenVar, size, stroke) {
  const radius = (size - stroke) / 2
  const circumference = 2 * Math.PI * radius
  const center = size / 2
  const color = `var(${tokenVar})`
  if (value === null) {
    return (
      `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="Indeterminate">` +
      `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="var(--ink-4)" stroke-width="${stroke}"/></svg>`
    )
  }
  const clamped = Math.max(0, Math.min(100, value))
  const fill = (clamped / 100) * circumference
  return (
    `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="${Math.round(clamped)}%">` +
    `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="var(--ink-4)" stroke-width="${stroke}" opacity="0.2"/>` +
    `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" ` +
    `stroke-dasharray="${fill.toFixed(2)} ${circumference.toFixed(2)}" transform="rotate(-90 ${center} ${center})"/>` +
    `<text x="${center}" y="${center}" text-anchor="middle" dominant-baseline="central" fill="${color}" ` +
    `style="font-family:ui-monospace,monospace;font-size:${Math.round(size * 0.32)}px;font-weight:600;">${Math.round(clamped)}%</text></svg>`
  )
}

// StatusBadge tiers — generic semantic states. --low is shared by Danger and the low neutral,
// differentiated by glyph. bg = color-mix(token, transparent 85%).
export const statusTiers = [
  { label: 'Success', token: '--hi', glyph: '●●●●●', pct: 92 },
  { label: 'Info', token: '--good', glyph: '●●●●○', pct: 78 },
  { label: 'Warning', token: '--mod', glyph: '●●●○○', pct: 61 },
  { label: 'Danger', token: '--low', glyph: '●●○○○', pct: 47 },
  { label: 'Idle', token: '--low', glyph: '●○○○○', pct: 22 },
  { label: 'Unknown', token: '--ink-4', glyph: '○○○○○', pct: null }
]

const statusBadge = (t) =>
  chip(
    `color:var(${t.token});background:color-mix(in oklab, var(${t.token}), transparent 85%);`,
    `<span aria-hidden="true">${t.glyph}</span><span>${t.label}</span>` +
      (t.pct == null ? '' : `<span style="opacity:.7;font-variant-numeric:tabular-nums;">${t.pct}%</span>`)
  )

// Tag-chip recipes — generic record categories.
export const tagChips = [
  { label: 'Active', style: 'background:color-mix(in oklab, var(--hi), transparent 80%);color:var(--hi);' },
  { label: 'Draft', style: 'background:color-mix(in oklab, var(--accent), transparent 78%);color:var(--accent);' },
  { label: 'Archived', style: 'background:color-mix(in oklab, var(--good), transparent 80%);color:var(--good);' },
  { label: 'Pending', style: 'background:color-mix(in oklab, var(--mod), transparent 80%);color:var(--mod);' },
  { label: 'Blocked', style: 'background:color-mix(in oklab, var(--low), transparent 78%);color:var(--low);' },
  { label: 'Featured', style: 'background:var(--accent-soft);color:var(--accent);' },
  { label: 'Other', style: 'background:var(--surface-3);color:var(--ink-3);' }
]

// Metadata-chip recipes — generic per-record flags. The final entry (dashed border, ink-4) is the
// "unavailable" variant on purpose, not a duplicate bug.
export const metaChips = [
  { label: 'NEW', style: 'background:var(--accent-soft);color:var(--accent);' },
  { label: 'SYNCED', style: 'background:color-mix(in oklab, var(--good), transparent 78%);color:var(--good);' },
  { label: 'PINNED', style: 'background:color-mix(in oklab, var(--accent), transparent 78%);color:var(--accent);' },
  { label: 'SHARED', style: 'background:color-mix(in oklab, var(--hi), transparent 78%);color:var(--hi);' },
  { label: 'OFFLINE', style: 'background:transparent;color:var(--ink-4);border:1px dashed var(--ink-4);' }
]

// SegmentedControl options — generic view switcher.
export const segments = [
  { label: 'List', selected: true },
  { label: 'Board', selected: false },
  { label: 'Calendar', selected: false }
]

const segment = (s) =>
  `<button style="border:none;border-radius:999px;padding:4px 14px;font-size:14px;font-weight:500;` +
  `cursor:pointer;font-family:inherit;` +
  (s.selected
    ? 'background:var(--surface-3);box-shadow:var(--shadow);color:var(--ink);'
    : 'background:transparent;color:var(--ink-3);') +
  `">${s.label}</button>`

// ── token roles (example) ────────────────────────────────────────────────────
// A neutral role table a consumer would pass as `ramps`. Mirrors the engine's default shape.
export const tokenRamps = [
  { key: 'surfaces', name: 'Surfaces', subtitle: 'bg / surface ramp', names: ['--bg', '--surface', '--surface-2', '--surface-3'] },
  { key: 'ink', name: 'Ink ramp', subtitle: 'text foreground ramp', names: ['--ink', '--ink-2', '--ink-3', '--ink-4'] },
  { key: 'lines', name: 'Lines', subtitle: 'hairline borders', names: ['--line', '--line-2'] },
  { key: 'accent', name: 'Accent', subtitle: 'brand accent', names: ['--accent', '--accent-soft', '--accent-ink'] },
  { key: 'status', name: 'Status tiers', subtitle: 'success / info / warning / danger', names: ['--hi', '--good', '--mod', '--low'] },
  { key: 'vibe', name: 'Radius & shadow', subtitle: 'radius / elevation / grid', names: ['--radius', '--shadow', '--grid'] }
]

// ── type scale (example) ─────────────────────────────────────────────────────
const SANS = "system-ui, -apple-system, 'Segoe UI', sans-serif"
const MONO = 'var(--font-jetbrains-mono, ui-monospace), monospace'
export const typeScale = [
  { name: 'text-lg · 18 / 600', size: 18, weight: 600, family: SANS, sample: 'Section heading' },
  { name: 'base · 16 / 500', size: 16, weight: 500, family: SANS, sample: 'Body copy for a record detail' },
  { name: 'text-sm · 14 / 400', size: 14, weight: 400, family: SANS, sample: 'Secondary label text' },
  { name: 'text-xs · 12 / 600', size: 12, weight: 600, family: SANS, sample: 'STATUS · META · TAG' },
  { name: 'mono · tabular-nums', size: 16, weight: 600, family: MONO, sample: '1,280 · 98%' }
]

// ── the representative preview specs (example) ───────────────────────────────
// Each: { group, name, subtitle, slug, body }. tokenCss is injected by buildDesignSystem.
export const componentPreviews = [
  // Composites — faithful, token-bound.
  {
    group: 'Composites',
    name: 'StatusBadge',
    subtitle: 'success / info / warning / danger / idle / unknown',
    slug: 'status-badge',
    body: `<div class="ds-row">\n    ${statusTiers.map(statusBadge).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'ProgressRing',
    subtitle: 'high / good / moderate / low / indeterminate',
    slug: 'progress-ring',
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
    name: 'TagChip',
    subtitle: 'record-category palette',
    slug: 'tag-chip',
    body: `<div class="ds-row">\n    ${tagChips.map((t) => chip(t.style, t.label)).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'MetaChip',
    subtitle: 'new / synced / pinned / shared / offline',
    slug: 'meta-chip',
    body: `<div class="ds-row">\n    ${metaChips.map((s) => chip(s.style + 'padding:2px 10px;', s.label)).join('\n    ')}\n  </div>`
  },
  {
    group: 'Composites',
    name: 'SegmentedControl',
    subtitle: 'single-select toggle group',
    slug: 'segmented-control',
    body:
      `<div role="group" aria-label="View" style="display:inline-flex;align-items:center;gap:2px;` +
      `border-radius:999px;padding:2px;background:var(--surface-2);">\n    ${segments.map(segment).join('\n    ')}\n  </div>`
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
      `      <div style="font-size:18px;font-weight:600;color:var(--ink);">Record title</div>\n` +
      `      <div style="font-size:14px;color:var(--ink-3);margin-top:4px;">Updated 3 days ago</div>\n` +
      `    </div>\n` +
      `    <div style="padding:16px 20px 20px;font-size:14px;color:var(--ink-2);">` +
      `A short summary of this record's contents.</div>\n  </div>`
  }
]
