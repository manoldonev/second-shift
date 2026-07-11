// design-faithful — sanitize untrusted DesignSync bytes.
//
// get_file returns content authored by other org members; the #194 findings flag the
// whole DesignSync read surface as untrusted (treat as data, never instructions). Every
// byte passes through sanitize() before any parse or render. This module NEVER evaluates
// input — it only strips/neutralizes active content and returns a plain string.

const SCRIPT_BLOCK = /<script\b[^>]*>[\s\S]*?<\/script\s*>/gi
const OPEN_SCRIPT = /<script\b[^>]*>/gi // unclosed <script ...>
const INLINE_HANDLER = /\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi
const JS_URL = /javascript:/gi
const DATA_HTML_URL = /data:text\/html/gi

/**
 * Strip active/executable content from untrusted markup or CSS and return a safe string.
 * Idempotent. Never throws on string input; coerces non-strings to ''.
 *
 * @param {unknown} text raw bytes from get_file
 * @returns {string} sanitized text safe to parse
 */
export function sanitize(text) {
  if (typeof text !== 'string') return ''
  let out = text
  out = out.replace(SCRIPT_BLOCK, '')
  out = out.replace(OPEN_SCRIPT, '')
  out = out.replace(INLINE_HANDLER, '')
  out = out.replace(JS_URL, 'blocked:')
  out = out.replace(DATA_HTML_URL, 'blocked:')
  return out
}

/**
 * True if `text` still contains any active-content marker. Used by tests to assert a
 * clean result, and available to callers that want a defensive post-check.
 *
 * @param {string} text
 * @returns {boolean}
 */
export function hasActiveContent(text) {
  if (typeof text !== 'string') return false
  return (
    /<script\b/i.test(text) ||
    /\son[a-z]+\s*=/i.test(text) ||
    /javascript:/i.test(text) ||
    /data:text\/html/i.test(text)
  )
}
