// design-faithful — extractor test suite. Run: node --test extractor.test.mjs
// Zero deps (node:test + node:assert), matching the .claude/ tooling convention.

import { test } from 'node:test'
import assert from 'node:assert/strict'

import { sanitize, hasActiveContent } from './sanitize.mjs'
import { extractCss } from './css-tokens.mjs'
import { extractMarkup, parseDsCard } from './html-markup.mjs'
import { planFetch, classifyFetchResult, assertProjectType, BATCH_LIMIT } from './read-plan.mjs'
import { extractContract } from './extractor.mjs'
import { FAIL_CLOSED, FAIL_CLOSED_REASONS, FailClosedError, PROJECT_TYPES } from './contract-types.mjs'

import { stylesCss, detailJsx, screenshots } from '../fixtures/handoff.mjs'
import { probeButtonHtml, noMarkerHtml } from '../fixtures/design-system.mjs'
import { hostileHtml, hostileCss } from '../fixtures/hostile.mjs'

const has = (list, v) => list.includes(v)

// --- sanitize -------------------------------------------------------------

test('sanitize strips script blocks, inline handlers, and js/data urls', () => {
  const out = sanitize(hostileHtml)
  assert.ok(!/<script\b/i.test(out), 'script tag removed')
  assert.ok(!/\sonclick\s*=/i.test(out), 'inline handler removed')
  assert.ok(!/javascript:/i.test(out), 'javascript: url neutralized')
  assert.ok(!/data:text\/html/i.test(out), 'data:text/html neutralized')
  assert.equal(hasActiveContent(out), false)
  assert.ok(out.includes('benign content'), 'benign content preserved')
})

test('sanitize neutralizes javascript: in css and never throws on non-strings', () => {
  assert.ok(!/javascript:/i.test(sanitize(hostileCss)))
  assert.equal(sanitize(null), '')
  assert.equal(sanitize(undefined), '')
  assert.equal(sanitize(42), '')
})

test('sanitize is idempotent', () => {
  const once = sanitize(hostileHtml)
  assert.equal(sanitize(once), once)
})

// --- css extraction -------------------------------------------------------

test('extractCss pulls OKLch tokens grouped by theme selector', () => {
  const css = extractCss(stylesCss)
  const cold = css.themes.find((t) => t.selector === '.theme-cold')
  assert.ok(cold, '.theme-cold theme present')
  const accent = cold.colors.find((c) => c.name === '--accent')
  assert.ok(accent, '--accent token present')
  assert.equal(accent.kind, 'oklch')
  assert.ok(css.themes.find((t) => t.selector === '.theme-warm'), '.theme-warm present')
  assert.ok(css.tokens.find((t) => t.name === '--bg'), '--bg in flat token list')
})

test('extractCss surfaces breakpoints, typography, scales, layout, inferred states', () => {
  const css = extractCss(stylesCss)
  assert.ok(css.breakpoints.some((b) => b.maxWidth === 759), 'max-width:759 breakpoint first-class')
  assert.ok(css.typography.fontFamilies.length > 0, 'font families captured')
  assert.ok(has(css.typography.sizes, '14px'), 'font-size captured')
  assert.ok(has(css.spacingScale, '8px'), 'gap scale captured')
  assert.ok(has(css.radiiScale, '14px'), 'radius captured')
  assert.ok(has(css.layout.primitives, 'flex') && has(css.layout.primitives, 'grid'), 'flex+grid')
  assert.ok(css.layout.primitives.some((p) => p.startsWith('grid-template-columns')), 'grid cols captured')
  const fv = css.inferredStates.find((s) => s.kind === 'focus-visible')
  assert.ok(fv && fv.inferred === true, 'focus-visible inferred state flagged inferred:true')
})

// --- markup extraction ----------------------------------------------------

test('parseDsCard reads marker fields and returns null when absent', () => {
  const card = parseDsCard(probeButtonHtml)
  assert.deepEqual(card, { name: 'Probe Button', group: 'Probe', subtitle: 'Primary / secondary' })
  assert.equal(parseDsCard(noMarkerHtml), null)
})

test('extractMarkup records a diagnostic for a marker-less component (not silent, not error)', () => {
  const m = extractMarkup(noMarkerHtml, { path: 'components/no-marker/index.html' })
  assert.equal(m.card, null)
  assert.ok(m.diagnostics.some((d) => /missing @dsCard marker/.test(d)), 'skip diagnostic recorded')
  assert.ok(has(m.a11y.ariaAttrs, 'aria-label'), 'aria-label captured')
  assert.ok(has(m.semanticTags, 'section'), 'semantic section captured')
})

test('extractMarkup infers variants and flags them inferred:true', () => {
  const m = extractMarkup(probeButtonHtml, { path: 'components/probe-button/index.html' })
  const names = m.variants.map((v) => v.name)
  assert.ok(names.includes('btn-primary') && names.includes('btn-secondary'), 'class-prefix variants')
  assert.ok(names.includes('disabled'), 'data-state variant')
  assert.ok(m.variants.every((v) => v.inferred === true), 'all variants flagged inferred')
})

// --- read-plan (fail-closed limit logic) ----------------------------------

test('planFetch partitions into <=BATCH_LIMIT batches', () => {
  const paths = Array.from({ length: 600 }, (_, i) => `f${i}`)
  const { batches, total } = planFetch({ paths })
  assert.equal(total, 600)
  assert.ok(batches.every((b) => b.length <= BATCH_LIMIT))
  assert.equal(batches.reduce((n, b) => n + b.length, 0), 600)
})

test('planFetch on empty paths returns an empty plan', () => {
  assert.deepEqual(planFetch({ paths: [] }), { batches: [], projectType: undefined, total: 0 })
  assert.deepEqual(planFetch({}), { batches: [], projectType: undefined, total: 0 })
})

test('planFetch rejects an over-ceiling batch size as batch-overflow', () => {
  assert.throws(() => planFetch({ paths: [] }, { batchSize: 300 }), (e) => e instanceof FailClosedError && e.reason === FAIL_CLOSED.BATCH_OVERFLOW)
})

test('classifyFetchResult maps truncated -> file-too-large, null/error -> source-unreachable', () => {
  assert.throws(() => classifyFetchResult({ truncated: true }, 'big.css'), (e) => e.reason === FAIL_CLOSED.FILE_TOO_LARGE)
  assert.throws(() => classifyFetchResult(null, 'x'), (e) => e.reason === FAIL_CLOSED.SOURCE_UNREACHABLE)
  assert.throws(() => classifyFetchResult({ error: 'boom' }, 'x'), (e) => e.reason === FAIL_CLOSED.SOURCE_UNREACHABLE)
  assert.deepEqual(classifyFetchResult({ content: 'ok' }, 'x'), { path: 'x', content: 'ok' })
  // non-string content coerces to '' rather than leaking a non-string into parsers
  assert.deepEqual(classifyFetchResult({ content: 42 }, 'x'), { path: 'x', content: '' })
})

test('assertProjectType enforces the expected shape', () => {
  assert.equal(assertProjectType({ type: PROJECT_TYPES.PROJECT }, PROJECT_TYPES.PROJECT), PROJECT_TYPES.PROJECT)
  assert.throws(() => assertProjectType({ type: PROJECT_TYPES.DESIGN_SYSTEM }, PROJECT_TYPES.PROJECT), (e) => e.reason === FAIL_CLOSED.PROJECT_TYPE_MISMATCH)
})

// --- contract types -------------------------------------------------------

test('FAIL_CLOSED enum has all four reasons and FailClosedError validates', () => {
  for (const r of ['design-source-unreachable', 'project-type-mismatch', 'file-too-large', 'batch-overflow']) {
    assert.ok(FAIL_CLOSED_REASONS.includes(r), `${r} in enum`)
  }
  assert.throws(() => new FailClosedError('not-a-reason'))
})

// --- end-to-end: PROJECT_TYPE_PROJECT -------------------------------------

test('extractContract assembles a handoff contract from real fixtures', () => {
  const c = extractContract({
    projectType: PROJECT_TYPES.PROJECT,
    files: {
      css: [{ path: 'styles.css', text: stylesCss }],
      screens: [{ path: 'screens/detail.jsx', text: detailJsx }],
      screenshots
    }
  })
  assert.equal(c.projectType, PROJECT_TYPES.PROJECT)
  assert.ok(c.themes.find((t) => t.selector === '.theme-cold'), 'tokens by theme')
  assert.ok(c.tokens.find((t) => t.name === '--accent' && t.kind === 'oklch'), 'oklch accent token')
  assert.ok(c.breakpoints.some((b) => b.maxWidth === 759), 'breakpoint')
  assert.ok(c.layout.primitives.includes('flex'), 'layout primitive')
  assert.ok(c.a11y.semanticTags.includes('h1') && c.a11y.focusable.includes('button'), 'a11y')
  assert.ok(c.inferred.states.some((s) => s.kind === 'focus-visible' && s.inferred === true), 'inferred focus state')
  assert.ok(c.inferred.variants.some((v) => v.name === 'verdict-cold'), 'verdict variant')
  assert.equal(c.screenshots.length, 3, 'screenshot refs')
  assert.equal(c.screens.length, 1, 'one screen')
})

// --- end-to-end: PROJECT_TYPE_DESIGN_SYSTEM -------------------------------

test('extractContract assembles a design-system contract and skips marker-less components', () => {
  const c = extractContract({
    projectType: PROJECT_TYPES.DESIGN_SYSTEM,
    files: {
      components: [
        { path: 'components/probe-button/index.html', text: probeButtonHtml },
        { path: 'components/no-marker/index.html', text: noMarkerHtml }
      ]
    }
  })
  assert.equal(c.cards.length, 1, 'only the marked component becomes a card')
  assert.equal(c.cards[0].name, 'Probe Button')
  assert.equal(c.cards[0].group, 'Probe')
  assert.ok(c.diagnostics.some((d) => /missing @dsCard marker/.test(d)), 'skip diagnostic surfaced')
  assert.ok(c.inferred.variants.some((v) => v.name === 'btn-primary'), 'variant from class prefix')
  assert.ok(c.inferred.variants.some((v) => v.name === 'disabled'), 'variant from data-state')
  assert.ok(c.a11y.semanticTags.includes('section'), 'semantic section from second component')
  assert.ok(c.inferred.states.every((s) => s.inferred === true), 'all inferred states flagged')
  assert.ok(c.inferred.variants.every((v) => v.inferred === true), 'all inferred variants flagged')
})

test('extractContract rejects an unknown project type as project-type-mismatch', () => {
  assert.throws(() => extractContract({ projectType: 'NOPE', files: {} }), (e) => e instanceof FailClosedError && e.reason === FAIL_CLOSED.PROJECT_TYPE_MISMATCH)
})
