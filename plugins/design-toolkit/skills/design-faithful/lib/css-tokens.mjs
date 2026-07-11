// design-faithful — CSS contract extraction.
//
// Pure, regex-based (no deps). Operates on already-sanitized CSS text. Design
// tokens are inline OKLch CSS custom properties grouped under theme selectors
// (.theme-cold / .theme-warm) — there is no token JSON — so the extractor parses custom
// properties out of the CSS directly.

import { uniq, dedupeBy, stateKey } from './util.mjs'

const BLOCK = /([^{}]+)\{([^{}]*)\}/g
const CUSTOM_PROP = /(--[a-z0-9-]+)\s*:\s*([^;]+);/gi
const MEDIA = /@media\s*([^{]+)\{/gi
const FONT_FAMILY = /font-family\s*:\s*([^;}]+)[;}]/gi
const FONT_SIZE = /font-size\s*:\s*(\d+)px/gi
const BORDER_RADIUS = /border-radius\s*:\s*([^;}]+)[;}]/gi
const GAP = /(?:^|[\s;{])gap\s*:\s*([^;}]+)[;}]/gi
const GRID_COLS = /grid-template-columns\s*:\s*([^;}]+)[;}]/gi
const PSEUDO = /:(hover|focus-visible|active)\b/gi
const DATA_ATTR = /\[(data-[a-z0-9-]+)/gi

/** @param {string} value @returns {'oklch'|'hex'|'rgb'|'other'} */
function colorKind(value) {
  const v = value.toLowerCase()
  if (v.includes('oklch(')) return 'oklch'
  if (/#[0-9a-f]{3,8}\b/.test(v)) return 'hex'
  if (v.includes('rgb(') || v.includes('rgba(')) return 'rgb'
  return 'other'
}

/** Is this custom property a color token (vs a shadow/grid/vibe token)? */
function isColorToken(value) {
  return colorKind(value) !== 'other'
}

/** Normalize a declared value: drop a trailing `!important` and surrounding whitespace. */
function clean(value) {
  return value.replace(/\s*!important\s*$/i, '').trim()
}

/**
 * Extract tokens, scales, typography, breakpoints, layout primitives, and inferred
 * pseudo-state hints from a CSS document.
 *
 * @param {string} cssText already-sanitized CSS
 * @returns {{themes:object[], tokens:object[], spacingScale:string[], radiiScale:string[],
 *           typography:{fontFamilies:string[],sizes:string[]}, breakpoints:object[],
 *           layout:{primitives:string[]}, inferredStates:object[]}}
 */
export function extractCss(cssText) {
  // Strip CSS comments first so they don't leak into selector captures
  // (e.g. "/* COLD */ .theme-cold" → ".theme-cold").
  const css = (typeof cssText === 'string' ? cssText : '').replace(/\/\*[\s\S]*?\*\//g, '')
  /** @type {Map<string, {selector:string, colors:object[], other:object[]}>} */
  const themes = new Map()
  const tokens = []

  let block
  BLOCK.lastIndex = 0
  while ((block = BLOCK.exec(css)) !== null) {
    const selector = block[1].trim().replace(/\s+/g, ' ')
    const body = block[2]
    let prop
    CUSTOM_PROP.lastIndex = 0
    while ((prop = CUSTOM_PROP.exec(body)) !== null) {
      const name = prop[1]
      const value = prop[2].trim()
      const token = { name, value, kind: colorKind(value) }
      tokens.push(token)
      if (!themes.has(selector)) themes.set(selector, { selector, colors: [], other: [] })
      const bucket = themes.get(selector)
      if (isColorToken(value)) bucket.colors.push(token)
      else bucket.other.push(token)
    }
  }

  // Breakpoints — first-class.
  const breakpoints = []
  let m
  MEDIA.lastIndex = 0
  while ((m = MEDIA.exec(css)) !== null) {
    const query = m[1].trim()
    const mw = query.match(/max-width\s*:\s*(\d+)px/i)
    breakpoints.push({ query, maxWidth: mw ? Number(mw[1]) : null })
  }

  // Typography.
  const fontFamilies = []
  FONT_FAMILY.lastIndex = 0
  while ((m = FONT_FAMILY.exec(css)) !== null) fontFamilies.push(m[1].trim())
  const sizes = []
  FONT_SIZE.lastIndex = 0
  while ((m = FONT_SIZE.exec(css)) !== null) sizes.push(`${m[1]}px`)

  // Radii scale.
  const radii = []
  BORDER_RADIUS.lastIndex = 0
  while ((m = BORDER_RADIUS.exec(css)) !== null) radii.push(clean(m[1]))

  // Spacing scale (gap declarations).
  const gaps = []
  GAP.lastIndex = 0
  while ((m = GAP.exec(css)) !== null) gaps.push(clean(m[1]))

  // Layout primitives.
  const primitives = []
  if (/display\s*:\s*flex/i.test(css)) primitives.push('flex')
  if (/display\s*:\s*grid/i.test(css)) primitives.push('grid')
  if (gaps.length) primitives.push('gap')
  GRID_COLS.lastIndex = 0
  while ((m = GRID_COLS.exec(css)) !== null) primitives.push(`grid-template-columns: ${clean(m[1])}`)

  // Inferred pseudo-state hints.
  const inferredStates = []
  PSEUDO.lastIndex = 0
  while ((m = PSEUDO.exec(css)) !== null) {
    inferredStates.push({ source: 'css', kind: m[1].toLowerCase(), value: `:${m[1]}`, inferred: true })
  }
  DATA_ATTR.lastIndex = 0
  while ((m = DATA_ATTR.exec(css)) !== null) {
    inferredStates.push({ source: 'css', kind: 'data-attr', value: m[1], inferred: true })
  }

  return {
    themes: [...themes.values()].filter((t) => t.colors.length || t.other.length),
    tokens,
    spacingScale: uniq(gaps),
    radiiScale: uniq(radii),
    typography: { fontFamilies: uniq(fontFamilies), sizes: uniq(sizes) },
    breakpoints,
    layout: { primitives: uniq(primitives) },
    inferredStates: dedupeBy(inferredStates, stateKey)
  }
}
