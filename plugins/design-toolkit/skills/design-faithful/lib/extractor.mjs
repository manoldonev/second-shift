// design-faithful — top-level contract extractor.
//
// extractContract({ projectType, files }) -> DesignContract. Pure: operates on
// already-fetched bytes (the DesignSync read orchestration is the caller's job; see
// SKILL.md). Sanitizes every byte before parsing, dispatches by project shape, and
// assembles the structured contract that the read engine and push path consume.

import { emptyContract, FAIL_CLOSED, FailClosedError, PROJECT_TYPES } from './contract-types.mjs'
import { sanitize } from './sanitize.mjs'
import { extractCss } from './css-tokens.mjs'
import { extractMarkup } from './html-markup.mjs'
import { uniq, dedupeBy, stateKey } from './util.mjs'

const STYLE_BLOCK = /<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi

/**
 * @param {{projectType:string, files:object}} input
 * @returns {import('./contract-types.mjs').DesignContract}
 */
export function extractContract(input) {
  const projectType = input && input.projectType
  if (!Object.values(PROJECT_TYPES).includes(projectType)) {
    throw new FailClosedError(FAIL_CLOSED.PROJECT_TYPE_MISMATCH, `unknown projectType ${projectType}`)
  }
  const files = (input && input.files) || {}
  const contract = emptyContract(projectType)

  if (projectType === PROJECT_TYPES.PROJECT) {
    extractHandoff(files, contract)
  } else {
    extractDesignSystem(files, contract)
  }

  finalize(contract)
  return contract
}

/** PROJECT_TYPE_PROJECT: README + screens/*.jsx + styles.css + screenshots/. */
function extractHandoff(files, contract) {
  const cssFiles = Array.isArray(files.css) ? files.css : []
  for (const f of cssFiles) {
    mergeCss(contract, extractCss(sanitize(f.text)))
    contract.source.fileCount++
  }

  const screens = Array.isArray(files.screens) ? files.screens : []
  for (const s of screens) {
    const markup = extractMarkup(sanitize(s.text), { path: s.path })
    mergeMarkup(contract, markup)
    contract.screens.push({
      name: s.path,
      semanticTags: markup.semanticTags,
      a11y: markup.a11y,
      variants: markup.variants
    })
    contract.source.fileCount++
  }

  if (typeof files.readme === 'string') {
    mergeMarkup(contract, extractMarkup(sanitize(files.readme), { path: 'README.md' }))
    contract.source.fileCount++
  }

  for (const shot of Array.isArray(files.screenshots) ? files.screenshots : []) {
    contract.screenshots.push(shot)
  }
}

/** PROJECT_TYPE_DESIGN_SYSTEM: components/<name>/index.html + @dsCard markers. */
function extractDesignSystem(files, contract) {
  const components = Array.isArray(files.components) ? files.components : []
  for (const c of components) {
    const sanitizedHtml = sanitize(c.text)
    const markup = extractMarkup(sanitizedHtml, { path: c.path })
    mergeMarkup(contract, markup)
    if (markup.card) {
      contract.cards.push({
        path: c.path,
        name: markup.card.name,
        group: markup.card.group,
        subtitle: markup.card.subtitle
      })
    }
    // Component previews embed their CSS in <style> — pull tokens + inferred states out too.
    let m
    STYLE_BLOCK.lastIndex = 0
    while ((m = STYLE_BLOCK.exec(sanitizedHtml)) !== null) mergeCss(contract, extractCss(m[1]))
    contract.source.fileCount++
  }
}

function mergeCss(contract, css) {
  for (const theme of css.themes) {
    const existing = contract.themes.find((t) => t.selector === theme.selector)
    if (existing) {
      existing.colors.push(...theme.colors)
      existing.other.push(...theme.other)
    } else {
      contract.themes.push(theme)
    }
  }
  contract.tokens.push(...css.tokens)
  contract.spacingScale.push(...css.spacingScale)
  contract.radiiScale.push(...css.radiiScale)
  contract.typography.fontFamilies.push(...css.typography.fontFamilies)
  contract.typography.sizes.push(...css.typography.sizes)
  contract.breakpoints.push(...css.breakpoints)
  contract.layout.primitives.push(...css.layout.primitives)
  contract.inferred.states.push(...css.inferredStates)
}

function mergeMarkup(contract, markup) {
  contract.a11y.semanticTags.push(...markup.semanticTags)
  contract.a11y.ariaAttrs.push(...markup.a11y.ariaAttrs)
  contract.a11y.landmarks.push(...markup.a11y.landmarks)
  contract.a11y.focusable.push(...markup.a11y.focusable)
  contract.inferred.states.push(...markup.inferredStates)
  contract.inferred.variants.push(...markup.variants)
  contract.diagnostics.push(...markup.diagnostics)
}

/** Dedupe the accumulated lists so the final contract is stable and noise-free. */
function finalize(contract) {
  contract.spacingScale = uniqSpacing(contract.spacingScale)
  contract.radiiScale = uniq(contract.radiiScale)
  contract.typography.fontFamilies = uniq(contract.typography.fontFamilies)
  contract.typography.sizes = uniq(contract.typography.sizes)
  contract.layout.primitives = uniq(contract.layout.primitives)
  contract.a11y.semanticTags = uniq(contract.a11y.semanticTags)
  contract.a11y.ariaAttrs = uniq(contract.a11y.ariaAttrs)
  contract.a11y.landmarks = uniq(contract.a11y.landmarks)
  contract.a11y.focusable = uniq(contract.a11y.focusable)
  contract.screenshots = uniq(contract.screenshots)
  contract.diagnostics = uniq(contract.diagnostics)
  contract.inferred.states = dedupeBy(contract.inferred.states, stateKey)
  contract.inferred.variants = dedupeBy(contract.inferred.variants, (v) => v.name)
}

/** Sort spacing values numerically where possible (e.g. "4px","8px","12px"). */
function uniqSpacing(values) {
  const seen = new Set()
  const out = []
  for (const v of values) {
    if (seen.has(v)) continue
    seen.add(v)
    out.push(v)
  }
  return out.sort((a, b) => (parseFloat(a) || 0) - (parseFloat(b) || 0))
}
