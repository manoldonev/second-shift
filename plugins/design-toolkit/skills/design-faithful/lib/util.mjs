// design-faithful — shared list helpers.
//
// Single home for the dedup helpers used across css-tokens / html-markup / extractor, so
// the inferred-state dedup key format can never drift between the CSS and markup paths.

/** Order-preserving unique. */
export function uniq(list) {
  return [...new Set(list)]
}

/** Order-preserving dedup by a derived key. */
export function dedupeBy(list, keyFn) {
  const seen = new Set()
  const out = []
  for (const item of list) {
    const k = keyFn(item)
    if (seen.has(k)) continue
    seen.add(k)
    out.push(item)
  }
  return out
}

/** Canonical key for an InferredState — must be identical across every producer. */
export const stateKey = (s) => `${s.source}|${s.kind}|${s.value}`
