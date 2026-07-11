// design-faithful — HTML / JSX markup contract extraction.
//
// Pure, regex-based (no deps). Operates on already-sanitized markup. The
// @dsCard first-line marker is the card-index source of truth (NOT _ds_manifest.json,
// which is a web-app render artifact). Inferred states/variants are flagged inferred:true
// for human review.

import { uniq, dedupeBy, stateKey } from './util.mjs'

const DS_CARD = /<!--\s*@dsCard\b([^>]*?)-->/i
const KV = /([a-z][a-z0-9-]*)\s*=\s*"([^"]*)"/gi
const TAG = /<([a-z][a-z0-9]*)\b/gi
const ARIA = /\b(aria-[a-z]+|role)\s*=/gi
const ALT = /\balt\s*=/gi
const TABINDEX = /\btabindex\s*=/gi
const CLASS_STRING = /class(?:Name)?\s*=\s*(?:"([^"]*)"|'([^']*)')/gi
const CLASS_EXPR = /class(?:Name)?\s*=\s*\{([^{}]*)\}/gi // JSX expression: className={cond ? 'a' : 'b'}
const STRING_LIT = /"([^"]*)"|'([^']*)'|`([^`]*)`/g
const DATA_VARIANT = /\bdata-(?:variant|state)\s*=\s*"([^"]*)"/gi
const PSEUDO = /:(hover|focus-visible|active)\b/gi

const SEMANTIC_TAGS = new Set([
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'button', 'nav', 'header', 'footer',
  'main', 'section', 'article', 'aside', 'ul', 'ol', 'li', 'a', 'label', 'table',
  'svg', 'strong', 'em', 'figure', 'figcaption'
])
const LANDMARK_TAGS = new Set(['nav', 'header', 'footer', 'main', 'section', 'aside'])
const FOCUSABLE_TAGS = new Set(['button', 'a', 'input', 'select', 'textarea'])

/**
 * Parse the first-line @dsCard marker into its fields.
 * @param {string} html
 * @returns {{name:string|null, group:string|null, subtitle:string|null}|null} null if no marker
 */
export function parseDsCard(html) {
  const text = typeof html === 'string' ? html : ''
  const m = text.match(DS_CARD)
  if (!m) return null
  /** @type {Record<string,string>} */
  const fields = {}
  let kv
  KV.lastIndex = 0
  while ((kv = KV.exec(m[1])) !== null) fields[kv[1].toLowerCase()] = kv[2]
  return {
    name: fields.name || null,
    group: fields.group || null,
    subtitle: fields.subtitle || null
  }
}

/**
 * Extract semantic markup, a11y signals, inferred states and variants from a markup string.
 *
 * @param {string} html already-sanitized HTML/JSX
 * @param {{path?:string}} [opts]
 * @returns {{card:object|null, semanticTags:string[], a11y:{ariaAttrs:string[],landmarks:string[],focusable:string[]},
 *           inferredStates:object[], variants:object[], diagnostics:string[]}}
 */
export function extractMarkup(html, opts = {}) {
  const text = typeof html === 'string' ? html : ''
  const path = opts.path || '(inline)'
  const diagnostics = []

  const card = parseDsCard(text)
  if (card === null && /(^|\/)components\//.test(path)) {
    // Design-system component preview with no first-line @dsCard marker:
    // skip (no card) but record it — never silent, never errored.
    diagnostics.push(`component ${path} missing @dsCard marker — skipped (no card index entry)`)
  }

  // Semantic tags.
  const tags = []
  let m
  TAG.lastIndex = 0
  while ((m = TAG.exec(text)) !== null) {
    const tag = m[1].toLowerCase()
    if (SEMANTIC_TAGS.has(tag)) tags.push(tag)
  }
  const semanticTags = uniq(tags)

  // a11y.
  const ariaAttrs = []
  ARIA.lastIndex = 0
  while ((m = ARIA.exec(text)) !== null) ariaAttrs.push(m[1].toLowerCase())
  if (ALT.test(text)) ariaAttrs.push('alt')
  if (TABINDEX.test(text)) ariaAttrs.push('tabindex')
  const landmarks = semanticTags.filter((t) => LANDMARK_TAGS.has(t))
  const focusable = semanticTags.filter((t) => FOCUSABLE_TAGS.has(t))

  // Class tokens → inferred variants (prefix-grouped) + state-toggle classes.
  const classTokens = []
  CLASS_STRING.lastIndex = 0
  while ((m = CLASS_STRING.exec(text)) !== null) {
    const raw = m[1] || m[2] || ''
    for (const c of raw.split(/\s+/)) if (c) classTokens.push(c)
  }
  // JSX expression attributes — pull class names out of any string literal inside
  // className={...} (ternaries, template parts), e.g. className={warm ? 'a' : 'b'}.
  CLASS_EXPR.lastIndex = 0
  while ((m = CLASS_EXPR.exec(text)) !== null) {
    const body = m[1]
    let s
    STRING_LIT.lastIndex = 0
    while ((s = STRING_LIT.exec(body)) !== null) {
      const raw = s[1] || s[2] || s[3] || ''
      for (const c of raw.split(/\s+/)) if (c) classTokens.push(c)
    }
  }
  const inferredStates = []
  for (const c of uniq(classTokens)) {
    if (c === 'on' || c === 'active' || c === 'selected') {
      inferredStates.push({ source: 'markup', kind: 'class-variant', value: `.${c}`, inferred: true })
    }
  }
  PSEUDO.lastIndex = 0
  while ((m = PSEUDO.exec(text)) !== null) {
    inferredStates.push({ source: 'markup', kind: m[1].toLowerCase(), value: `:${m[1]}`, inferred: true })
  }

  // Variants: modifier classes sharing a prefix (e.g. btn-primary / btn-secondary),
  // plus any data-variant / data-state values.
  const variants = inferVariants(classTokens)
  DATA_VARIANT.lastIndex = 0
  while ((m = DATA_VARIANT.exec(text)) !== null) {
    variants.push({ name: m[1], inferred: true })
  }

  return {
    card,
    semanticTags,
    a11y: { ariaAttrs: uniq(ariaAttrs), landmarks, focusable },
    inferredStates: dedupeBy(inferredStates, stateKey),
    variants: dedupeBy(variants, (v) => v.name),
    diagnostics
  }
}

/** Group hyphenated class tokens by prefix; a prefix with 2+ modifiers yields variants. */
function inferVariants(classTokens) {
  /** @type {Map<string,Set<string>>} */
  const byPrefix = new Map()
  for (const c of classTokens) {
    const i = c.lastIndexOf('-')
    if (i <= 0) continue
    const prefix = c.slice(0, i)
    if (!byPrefix.has(prefix)) byPrefix.set(prefix, new Set())
    byPrefix.get(prefix).add(c)
  }
  const variants = []
  for (const [, members] of byPrefix) {
    if (members.size >= 2) for (const name of members) variants.push({ name, inferred: true })
  }
  return variants
}
