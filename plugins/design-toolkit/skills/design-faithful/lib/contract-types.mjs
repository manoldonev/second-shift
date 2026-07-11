// design-faithful — contract types + fail-closed reasons.
//
// Plain importable ESM (no top-level return, no injected globals) so the design-faithful
// skills (the DesignSync callers) and the push path's import can `import` this directly. (The
// Workflow engine does NOT import this — its runtime guarantees no ESM import; it inlines the
// FAIL_CLOSED values and drift-guards them. See design-sync.mjs READ BOUNDARY.) JSDoc typedefs document the
// DesignContract output shape — this is the interface every downstream piece builds
// against. `.mjs` files under .claude/ are prettier-ignored and hand-styled (single
// quotes, no semicolons) to match the existing Workflow-script convention.

/**
 * The two Claude Design project shapes.
 * @typedef {'PROJECT_TYPE_PROJECT' | 'PROJECT_TYPE_DESIGN_SYSTEM'} ProjectType
 */
export const PROJECT_TYPES = Object.freeze({
  PROJECT: 'PROJECT_TYPE_PROJECT',
  DESIGN_SYSTEM: 'PROJECT_TYPE_DESIGN_SYSTEM'
})

/**
 * Closed enum of fail-closed reasons. The extractor and read-path helpers only ever
 * raise members of this set; downstream consumers switch on these exact strings.
 */
export const FAIL_CLOSED = Object.freeze({
  SOURCE_UNREACHABLE: 'design-source-unreachable',
  PROJECT_TYPE_MISMATCH: 'project-type-mismatch',
  FILE_TOO_LARGE: 'file-too-large',
  BATCH_OVERFLOW: 'batch-overflow'
})

/** Every fail-closed reason string, for membership checks. @type {ReadonlyArray<string>} */
export const FAIL_CLOSED_REASONS = Object.freeze(Object.values(FAIL_CLOSED))

/**
 * A fail-closed error carrying a closed-enum `reason`. Thrown by the extractor and
 * read-path helpers so callers can branch on `err.reason` without string-matching messages.
 */
export class FailClosedError extends Error {
  /** @param {string} reason @param {string} [detail] */
  constructor(reason, detail) {
    if (!FAIL_CLOSED_REASONS.includes(reason)) {
      throw new Error(`FailClosedError: unknown reason "${reason}"`)
    }
    super(detail ? `${reason}: ${detail}` : reason)
    this.name = 'FailClosedError'
    /** @type {string} */
    this.reason = reason
  }
}

/**
 * @typedef {Object} Token
 * @property {string} name   CSS custom property name, e.g. "--accent"
 * @property {string} value  raw declared value, e.g. "oklch(0.74 0.13 215)"
 * @property {'oklch'|'hex'|'rgb'|'other'} kind  detected color/value kind
 */

/**
 * @typedef {Object} ThemeTokens
 * @property {string} selector  the selector the tokens are scoped to, e.g. ".theme-cold"
 * @property {Token[]} colors   color custom properties found in this block
 * @property {Token[]} other    non-color custom properties (shadows, grid, etc.)
 */

/**
 * @typedef {Object} Breakpoint
 * @property {string} query     the raw @media query text
 * @property {number|null} maxWidth  parsed max-width px, or null if not a max-width query
 */

/**
 * @typedef {Object} InferredState
 * @property {string} source    where it was inferred from (selector or "markup")
 * @property {string} kind      'hover' | 'focus-visible' | 'active' | 'data-attr' | 'class-variant'
 * @property {string} value     the matched token (e.g. ":hover", "data-state", ".on")
 * @property {true} inferred    always true — these are inferred, flagged for human review
 */

/**
 * @typedef {Object} Card
 * @property {string} path       components/<name>/index.html
 * @property {string|null} name  from @dsCard name="…"
 * @property {string|null} group from @dsCard group="…"
 * @property {string|null} subtitle from @dsCard subtitle="…"
 */

/**
 * @typedef {Object} DesignContract
 * @property {ProjectType} projectType
 * @property {Object} source                  { projectId?, fileCount }
 * @property {ThemeTokens[]} themes           tokens grouped by scope selector
 * @property {Token[]} tokens                 flat list of all tokens
 * @property {string[]} spacingScale          ordered spacing values (gap utilities, etc.)
 * @property {string[]} radiiScale            border-radius values seen
 * @property {Object} typography              { fontFamilies, sizes }
 * @property {Breakpoint[]} breakpoints       first-class @media breakpoints
 * @property {Object} layout                  { primitives: string[] } flex/grid/gap/template-columns hints
 * @property {Object} a11y                    { semanticTags, ariaAttrs, landmarks, focusable }
 * @property {Object} inferred                { states: InferredState[], variants: {name,inferred:true}[] }
 * @property {Object[]} screens               handoff screens (PROJECT_TYPE_PROJECT)
 * @property {Card[]} cards                   design-system cards (PROJECT_TYPE_DESIGN_SYSTEM)
 * @property {string[]} screenshots           screenshot path references
 * @property {string[]} diagnostics           non-fatal notes (e.g. component missing @dsCard marker)
 */

/** @returns {DesignContract} an empty contract skeleton for the given type. */
export function emptyContract(projectType) {
  return {
    projectType,
    source: { fileCount: 0 },
    themes: [],
    tokens: [],
    spacingScale: [],
    radiiScale: [],
    typography: { fontFamilies: [], sizes: [] },
    breakpoints: [],
    layout: { primitives: [] },
    a11y: { semanticTags: [], ariaAttrs: [], landmarks: [], focusable: [] },
    inferred: { states: [], variants: [] },
    screens: [],
    cards: [],
    screenshots: [],
    diagnostics: []
  }
}
