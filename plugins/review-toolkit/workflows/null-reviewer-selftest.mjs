#!/usr/bin/env node
// Reads code-review.mjs as TEXT and pins what executing it cannot show: that the
// dark-reviewer contract tokens are still in the file, and how many prompt branches each
// emit nudge is appended to. The dispatch ladder's behavior is asserted by
// runtime-shim-selftest.mjs, which executes the production body.
//
// Exit code = number of failed cases.
//
// Run: node plugins/review-toolkit/workflows/null-reviewer-selftest.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const CODE_REVIEW_MJS = join(HERE, 'code-review.mjs')

let PASS = 0
let FAIL = 0
const pass = (m) => {
  console.log(`  PASS: ${m}`)
  PASS++
}
const fail = (m) => {
  console.log(`  FAIL: ${m}`)
  FAIL++
}

async function main() {
  let src = ''
  try {
    src = readFileSync(CODE_REVIEW_MJS, 'utf8')
  } catch (e) {
    fail(`F0 could not read code-review.mjs at ${CODE_REVIEW_MJS}: ${e}`)
  }
  const tokens = [
    ['structured-emitter', 'tool-less schema sink — the only schema carrier'],
    ['retried: true', 'twice-dead flag — synthesis must not mistake a dead reviewer for "no findings"'],
    ['failed: true', 'twice-dead flag'],
    ['budgetExhausted: true', 'all-or-nothing budget-skip dark-reviewer marker'],
    ['REVIEWER_CEILING_MS', 'per-reviewer wall-clock ceiling constant — the wedge bound'],
    ['ceiling: true', 'ceiling-timeout diagnostic flag on the reused died-after-retry marker'],
    ['PROGRESSIVE_EMIT', 'emit-as-you-go nudge for the exhaustive reviewers — the turn-cap cure'],
    ['turn-budget:', 'cap-death error string, kept distinct from the text-contract miss'],
    ['ESCALATED_EMIT', 'escalating-retry nudge — without it the retry is bit-identical and reproduces the cap death'],
  ]
  for (const [tok, why] of tokens) {
    src.includes(tok)
      ? pass(`F drift-guard: code-review.mjs carries \`${tok}\` (${why})`)
      : fail(`F drift-guard: code-review.mjs is MISSING \`${tok}\` (${why})`)
  }

  // Count APPENDS (`+\n      PROGRESSIVE_EMIT`), not mentions: the definition and the
  // explanatory comments also contain the bare name, so a mention count cannot tell a
  // wired constant from a dead one.
  const appends = (src.match(/\+\s*\n\s*PROGRESSIVE_EMIT\b/g) || []).length
  appends === 2
    ? pass('F wiring: PROGRESSIVE_EMIT is appended to exactly the 2 exhaustive prompt branches')
    : fail(`F wiring: PROGRESSIVE_EMIT is appended to ${appends} prompt branch(es), expected 2 (scope-completeness + unit-test-mutation)`)

  // The split must stay disjoint: an exhaustive reviewer that also got BOUNDED_EXPLORATION
  // would be told to skip the enumeration that is its deliverable.
  const boundedAppends = (src.match(/\+\s*\n\s*BOUNDED_EXPLORATION\b/g) || []).length
  boundedAppends === 1
    ? pass('F wiring: BOUNDED_EXPLORATION stays on exactly the 1 generic branch')
    : fail(`F wiring: BOUNDED_EXPLORATION is appended to ${boundedAppends} branch(es), expected 1 (generic only)`)

  console.log(`\n[null-reviewer-selftest] ${PASS} passed, ${FAIL} failed`)
  process.exit(FAIL)
}

main().catch((e) => {
  console.error(`[null-reviewer-selftest] FATAL: ${e?.stack || e}`)
  process.exit(99)
})
