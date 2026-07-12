// design-faithful — token-swatch card emit (design-system push direction).
//
// Turns a consumer's globals.css OKLch custom properties into Claude Design "Tokens" cards.
// Reuses the read-path extractor (css-tokens.extractCss) rather than re-parsing: the dark-first
// `:root, .theme-*` ramp is extractCss(...).themes[0]. We deliberately take ONLY the first
// theme block so any `.theme-*.lighten` light-mode overrides never leak into the dark-first
// :root block we inline into every preview (the v1 scope is the dark canonical ramp only).
//
// Pure, dependency-free, hand-styled to match the sibling lib.

import { extractCss } from './css-tokens.mjs'
import { emitCard, escAttr } from './emit-card.mjs'

// Neutral default token roles. Each ramp lists the token names that belong to it; emit skips any
// name the source CSS does not define, so trimming globals.css never produces an empty/garbage
// swatch. Domain-empty by design — a consumer supplies its own ramp roles by passing a `ramps`
// argument to emitTokenCards sourced from its design-system reference; these are only the fallback.
export const TOKEN_RAMPS = [
  { key: 'surfaces', name: 'Surfaces', subtitle: 'bg / surface ramp', names: ['--bg', '--surface', '--surface-2', '--surface-3'] },
  { key: 'ink', name: 'Ink ramp', subtitle: 'text foreground ramp', names: ['--ink', '--ink-2', '--ink-3', '--ink-4'] },
  { key: 'lines', name: 'Lines', subtitle: 'hairline borders', names: ['--line', '--line-2'] },
  { key: 'accent', name: 'Accent', subtitle: 'brand accent', names: ['--accent', '--accent-soft', '--accent-ink'] },
  { key: 'status', name: 'Status tiers', subtitle: 'success / info / warning / danger', names: ['--hi', '--good', '--mod', '--low'] },
  { key: 'vibe', name: 'Radius & shadow', subtitle: 'radius / elevation / grid', names: ['--radius', '--shadow', '--grid'] }
]

// Names that are NOT colour fills even though extractCss may bucket them as colours (a shadow is
// a multi-line box-shadow recipe; a radius is a length) — they render as a demo box, not a chip.
const RADIUS_TOKENS = new Set(['--radius'])
const SHADOW_TOKENS = new Set(['--shadow'])

// The dark-first ramp's tokens, in declared order. Selection is by first-theme membership
// (extractCss themes[0]) — NOT selector-string equality, which fails because any leading
// brace-less `@tailwind` lines get absorbed into the first block's selector prefix. Taking
// themes[0] also excludes any `.theme-*.lighten` light-mode block (themes[1]). Operates on an
// already-parsed `themes` array so a single extractCss() call can feed both the :root block and
// the token map.
function firstThemeTokens(themes) {
  const first = (themes && themes[0]) || { colors: [], other: [] }
  return [...first.colors, ...first.other]
}

/** Render a token list as a `:root { … }` block string. */
function rootCssFrom(tokens) {
  return `:root {\n${tokens.map((t) => `  ${t.name}: ${t.value};`).join('\n')}\n}`
}

/**
 * The dark-first `:root { … }` token block, as a string to inline into every preview.
 * @param {string} cssText already-sanitized globals.css text
 * @returns {string}
 */
export function tokenRootCss(cssText) {
  return rootCssFrom(firstThemeTokens(extractCss(cssText).themes))
}

/** Render one token as a labelled swatch / radius box / shadow box (keyed off the token name). */
function renderToken(name, value) {
  const label = `<span class="name">${escAttr(name)}</span><span>${escAttr(value)}</span>`
  if (RADIUS_TOKENS.has(name)) {
    return (
      `<div class="ds-swatch"><div class="chip" ` +
      `style="background: var(--surface-2); border-radius: var(${name});"></div>${label}</div>`
    )
  }
  if (SHADOW_TOKENS.has(name)) {
    return (
      `<div class="ds-swatch"><div class="chip" ` +
      `style="background: var(--surface); box-shadow: var(${name});"></div>${label}</div>`
    )
  }
  return `<div class="ds-swatch"><div class="chip" style="background: var(${name});"></div>${label}</div>`
}

/**
 * Emit one Tokens card per ramp present in the source CSS.
 * @param {string} cssText already-sanitized globals.css text
 * @param {{key:string, name:string, subtitle?:string, names:string[]}[]} [ramps]
 *   token roles to emit, sourced from the consumer's design-system reference. Defaults to the
 *   neutral TOKEN_RAMPS so the published output hardcodes no domain-specific roles.
 * @returns {{path:string, content:string}[]}
 */
export function emitTokenCards(cssText, ramps = TOKEN_RAMPS) {
  const list = firstThemeTokens(extractCss(cssText).themes) // single parse feeds both below
  const tokens = new Map(list.map((t) => [t.name, t.value]))
  const tokenCss = rootCssFrom(list)
  const cards = []
  for (const ramp of ramps) {
    const present = ramp.names.filter((n) => tokens.has(n))
    if (present.length === 0) continue
    const body = `<div class="ds-row">\n${present.map((n) => '    ' + renderToken(n, tokens.get(n))).join('\n')}\n  </div>`
    cards.push(
      emitCard({ group: 'Tokens', name: ramp.name, subtitle: ramp.subtitle, slug: `tokens-${ramp.key}`, tokenCss, body })
    )
  }
  return cards
}
