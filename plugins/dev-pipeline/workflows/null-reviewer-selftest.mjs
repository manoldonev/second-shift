#!/usr/bin/env node
// null-reviewer-selftest.mjs — verifies the Stage 8 dark-reviewer contract (#168).
//
// Style note: like its sibling Workflow scripts (code-review.mjs, intake-review.mjs),
// this file is NOT covered by the repo `format` script (which globs only
// .{ts,tsx,js,json,md}), so it follows their hand-style: no semicolons, single quotes.
//
// WHAT THIS FILE COVERS (and what moved out of it, #214):
//   It used to carry a REFERENCE HARNESS mirroring dispatchReviewer()'s retry semantics,
//   on the premise that code-review.mjs could not be executed under node (top-level
//   `return`, runtime-injected globals). The premise was wrong and the copy rotted: it
//   modelled the pre-#169 StructuredOutput-retry transport — including a predicate
//   (isNoStructuredOutputError) production no longer has — and stayed green throughout.
//   A copy cannot fail on a production edit, which is the only failure worth catching.
//
//   Behavioral coverage of the real ladder now lives in runtime-shim-selftest.mjs, which
//   strips the meta block and executes the ACTUAL code-review.mjs body with injected fakes.
//
//   What remains here is Case F alone — the structural drift-guard reading code-review.mjs
//   as TEXT. Its load-bearing half is the WIRING COUNTS (PROGRESSIVE_EMIT appended to
//   exactly 2 exhaustive branches, BOUNDED_EXPLORATION to exactly 1): check-bounded-
//   exploration.sh greps only `^const BOUNDED_[A-Z_]+`, so PROGRESSIVE_EMIT wiring is
//   invisible to it and this is the only guard on it in the tree.
//
// Mirrors the conventions of statectl-selftest.sh: numbered cases, pass/fail
// counters, exit code = number of failed cases (0 = all pass).
//
// Run: node .claude/skills/run/workflows/null-reviewer-selftest.mjs

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
const eq = (label, got, want) => {
  const g = JSON.stringify(got)
  const w = JSON.stringify(want)
  g === w ? pass(label) : fail(`${label} — got ${g}, want ${w}`)
}
// Like eq(), but asserts `str` matches `regex` — keeps the pass/fail format uniform
// for the one case (C4) that checks a substring rather than deep equality.
const matches = (label, str, regex) => {
  regex.test(String(str)) ? pass(label) : fail(`${label} — ${JSON.stringify(str)} did not match ${regex}`)
}

async function main() {
  // ---- Case F: structural drift-guard against the production code-review.mjs ----
  // The reference harness above is only trustworthy if production still carries the
  // same load-bearing behavior. Assert the stable tokens are present (NOT whitespace
  // or the cosmetic retry label, per the #168 plan-review warning).
  {
    let src = ''
    try {
      src = readFileSync(CODE_REVIEW_MJS, 'utf8')
    } catch (e) {
      fail(`F0 could not read code-review.mjs at ${CODE_REVIEW_MJS}: ${e}`)
    }
    // #169: the transport converted to explorer/emitter — the old StructuredOutput retry
    // predicate is retired; the contract tokens below are its replacements. The reference
    // harness above still models the DARK-MARKER CONTRACT (result/error/retried/failed/
    // ceiling shapes), which is transport-independent and unchanged; the transport itself
    // is guarded by check-bounded-exploration-selftest.sh and the stall probe.
    // parseReviewResult / REVIEW_RESULT are covered stronger by text-contract-selftest.sh, which
    // byte-locksteps AND executes the extracted production copies; the three-dot range token is
    // guarded by diff-range-selftest.sh Cases C-F (backtick-free token + a two-dot ABSENCE check
    // that also catches a partial fix). Duplicating them here is maintenance, not detection.
    const tokens = [
      ['structured-emitter', 'tool-less schema sink — the only schema carrier (#169)'],
      ['retried: true', 'twice-dead flag — synthesis must not mistake a dead reviewer for "no findings"'],
      ['failed: true', 'twice-dead flag'],
      ['budgetExhausted: true', 'all-or-nothing budget-skip dark-reviewer marker (#168)'],
      ['REVIEWER_CEILING_MS', 'per-reviewer wall-clock ceiling constant (#219) — the wedge bound'],
      ['ceiling: true', 'ceiling-timeout diagnostic flag (#219) on the reused died-after-retry marker'],
      ['PROGRESSIVE_EMIT', 'emit-as-you-go nudge for the exhaustive reviewers (#183) — the turn-cap cure'],
      ['turn-budget:', 'cap-death error string, kept distinct from the text-contract miss (#183)'],
    ]
    for (const [tok, why] of tokens) {
      src.includes(tok)
        ? pass(`F drift-guard: code-review.mjs carries \`${tok}\` (${why})`)
        : fail(`F drift-guard: code-review.mjs is MISSING \`${tok}\` (${why}) — production lost the behavior this selftest validates`)
    }

    // F-wiring: a constant that exists but reaches no prompt is the exact rot
    // check-bounded-exploration.sh was written for ("shipped on exactly one of six
    // dispatchers and the omission went unnoticed for months"). PROGRESSIVE_EMIT is not
    // BOUNDED_*, so that lint's dormancy rule does not see it — pin its wiring here.
    // Count APPENDS (`+\n      PROGRESSIVE_EMIT`), not mentions: the definition and the
    // explanatory comments also contain the bare name, so a mention count cannot tell a
    // wired constant from a dead one.
    const appends = (src.match(/\+\s*\n\s*PROGRESSIVE_EMIT\b/g) || []).length
    appends === 2
      ? pass('F wiring: PROGRESSIVE_EMIT is appended to exactly the 2 exhaustive prompt branches')
      : fail(`F wiring: PROGRESSIVE_EMIT is appended to ${appends} prompt branch(es), expected 2 (scope-completeness + unit-test-mutation)`)

    // The bounded/progressive split must stay disjoint: an exhaustive reviewer that also
    // got BOUNDED_EXPLORATION would be told to skip the exhaustive enumeration that IS
    // its deliverable — the failure mode the exemption exists to prevent.
    const boundedAppends = (src.match(/\+\s*\n\s*BOUNDED_EXPLORATION\b/g) || []).length
    boundedAppends === 1
      ? pass('F wiring: BOUNDED_EXPLORATION stays on exactly the 1 generic branch')
      : fail(`F wiring: BOUNDED_EXPLORATION is appended to ${boundedAppends} branch(es), expected 1 (generic only)`)
  }

  console.log(`\n[null-reviewer-selftest] ${PASS} passed, ${FAIL} failed`)
  process.exit(FAIL)
}

main().catch((e) => {
  console.error(`[null-reviewer-selftest] FATAL: ${e?.stack || e}`)
  process.exit(99)
})
