// design-faithful — design-system card emit (the push direction).
//
// Pure, dependency-free ESM. The inverse of lib/html-markup.mjs (which PARSES a
// components/<name>/index.html preview into a contract): here we SERIALIZE a component
// preview into the same on-disk shape DesignSync expects — a standalone HTML document whose
// first line is the @dsCard marker (the card-index source of truth) and
// whose styling is self-contained (inline acme OKLch tokens, no external stylesheet).
//
// .mjs under .claude/ is prettier-ignored and hand-styled (single quotes, no semicolons) to
// match the existing read-path lib (css-tokens.mjs / html-markup.mjs / util.mjs).

const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/

/**
 * Escape a string for safe embedding in a double-quoted HTML attribute / the @dsCard marker.
 * `&` first so we don't double-encode, then `"`, `<`, `>`. The read-path parser
 * (parseDsCard) does not decode entities, so escaping is what keeps a value containing a
 * literal quote from corrupting the marker into spurious key="value" pairs.
 * @param {string} text
 */
export function escAttr(text) {
  return String(text == null ? '' : text)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

/**
 * Build the first-line @dsCard marker. Empty/absent fields are omitted (parseDsCard treats a
 * missing field as null), and every value is attribute-escaped so it round-trips through the
 * lenient KV parser without breaking the marker.
 *
 * @param {{group?:string, name?:string, subtitle?:string}} fields
 * @returns {string} e.g. `<!-- @dsCard group="Tokens" name="Surfaces" -->`
 */
export function dsCardMarker(fields = {}) {
  const order = ['group', 'name', 'subtitle']
  const parts = order
    .filter((k) => fields[k] != null && String(fields[k]).length > 0)
    .map((k) => `${k}="${escAttr(fields[k])}"`)
  return `<!-- @dsCard ${parts.join(' ')} -->`
}

// Default preview frame — a dark-first surface using acme tokens, with two small layout
// helpers the preview bodies use to lay variants out as sibling instances.
const DEFAULT_FRAME = `  *, *::before, *::after { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 24px;
    background: var(--bg, #18181b);
    color: var(--ink, #fafafa);
    font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 16px;
  }
  .ds-stack { display: flex; flex-direction: column; align-items: flex-start; gap: 12px; }
  .ds-row { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
  .ds-swatch {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 11px;
    font-family: ui-monospace, 'SF Mono', Menlo, monospace;
    color: var(--ink-3, #888);
  }
  .ds-swatch > .chip {
    width: 96px;
    height: 56px;
    border-radius: 10px;
    border: 1px solid var(--line, #333);
  }
  .ds-swatch > .name { color: var(--ink-2, #bbb); }`

/**
 * Serialize one component preview to its components/<slug>/index.html file.
 *
 * @param {{group?:string, name:string, subtitle?:string, slug:string, tokenCss?:string,
 *          body:string, baseStyles?:string}} spec
 *   - `tokenCss`  — a `:root { … }` block of acme tokens (from emit-tokens.tokenRootCss) so
 *                   the preview renders faithfully standalone. Optional (token swatch cards that
 *                   already inline their own values can omit it).
 *   - `body`      — the inner HTML of <body>: variant instances as sibling DOM nodes.
 *   - `baseStyles`— optional extra CSS appended after the default preview frame.
 * @returns {{path:string, content:string}}
 */
export function emitCard(spec) {
  const { group, name, subtitle, slug, tokenCss = '', body = '', baseStyles = '' } = spec || {}
  if (!slug || !SLUG_RE.test(slug)) {
    throw new Error(`emitCard: slug must be kebab-case [a-z0-9-], got ${JSON.stringify(slug)}`)
  }
  if (!name) throw new Error('emitCard: name is required')

  const marker = dsCardMarker({ group, name, subtitle })
  const css = [tokenCss, DEFAULT_FRAME, baseStyles].filter(Boolean).join('\n')
  const content =
    `${marker}\n` +
    '<!DOCTYPE html>\n' +
    '<html lang="en">\n' +
    '<head>\n' +
    '<meta charset="utf-8">\n' +
    `<title>${escAttr(name)}</title>\n` +
    '<style>\n' +
    `${css}\n` +
    '</style>\n' +
    '</head>\n' +
    '<body>\n' +
    `${body}\n` +
    '</body>\n' +
    '</html>\n'
  return { path: `components/${slug}/index.html`, content }
}
