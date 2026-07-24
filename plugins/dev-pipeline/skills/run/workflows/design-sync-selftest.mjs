#!/usr/bin/env node
// design-sync-selftest.mjs — verifies the design-faithful produce/gate engine (#196).
//
// Style note: like its sibling Workflow scripts (code-review.mjs, unit-tests.mjs,
// null-reviewer-selftest.mjs), this file is NOT covered by the repo `format` script (which globs
// only .{ts,tsx,js,json,md}), so it follows their hand-style: no semicolons, single quotes.
//
// WHAT THIS FILE COVERS (and what moved out of it, #214):
//   It used to carry a REFERENCE HARNESS — hand-written copies of the engine's validation, budget
//   skip, normalizeFailClosed, and both dispatch ladders — on the premise that design-sync.mjs
//   could not be executed under node (top-level `return`, runtime-injected globals). That premise
//   was wrong, and the copies rotted: they still modelled the pre-#169 StructuredOutput transport
//   and stayed green for months while production had moved on. A copy cannot fail on a production
//   edit, which is the only failure that matters.
//
//   Behavioral coverage of the real ladders now lives in runtime-shim-selftest.mjs, which strips
//   the meta block and executes the ACTUAL design-sync.mjs body with injected fakes. (On its first
//   run it found a live ReferenceError on the gate path that every case here passed straight over.)
//
//   What remains here is what the shim cannot reach, all of it reading production as TEXT:
//     Case G — load-bearing token presence in design-sync.mjs.
//     Case H — the engine's inlined FAIL_CLOSED_REASONS vs the #195 contract-types.mjs vocabulary;
//              both sides are extracted from source, so neither can drift unnoticed.
//     Case I — Workflow meta literal-purity across every sibling workflows/*.mjs (a non-literal
//              meta makes the runtime reject the whole script at dispatch; v2.0.0 shipped exactly
//              that defect and it surfaced only on a live canary run).
//
// Mirrors the conventions of null-reviewer-selftest.mjs: numbered cases, pass/fail counters,
// exit code = number of failed cases (0 = all pass).
//
// Run: node .claude/skills/run/workflows/design-sync-selftest.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const DESIGN_SYNC_MJS = join(HERE, 'design-sync.mjs')
// contract-types.mjs lives in the design-toolkit plugin (sibling under plugins/), not
// dev-pipeline. HERE=plugins/dev-pipeline/skills/run/workflows → up 4 to plugins/.
const CONTRACT_TYPES_MJS = join(HERE, '..', '..', '..', '..', 'design-toolkit', 'skills', 'design-faithful', 'lib', 'contract-types.mjs')

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
async function main() {
  // ---- Case G: structural drift-guard against production design-sync.mjs ----
  {
    let src = ''
    try {
      src = readFileSync(DESIGN_SYNC_MJS, 'utf8')
    } catch (e) {
      fail(`G0 could not read design-sync.mjs at ${DESIGN_SYNC_MJS}: ${e}`)
    }
    // parseReviewResult / REVIEW_RESULT are deliberately NOT pinned here: text-contract-selftest.sh
    // already byte-locksteps AND behaviorally executes the extracted production copies of both, and
    // fails if this file stops carrying them. Duplicating them here adds maintenance, not detection.
    const tokens = [
      ['export const meta', 'Workflow loader entry — engine will not register without it'],
      ["phase('Design Sync')", 'progress phase'],
      ["kind === 'produce'", 'produce branch discriminator'],
      ["kind === 'gate'", 'gate branch discriminator'],
      ['implement && !worktree', 'F26 fail-closed guard — implement:true without worktree must throw, not commit to the wrong branch'],
      ['budgetExhausted: true', 'budget clean-skip marker (not a fake block/error)'],
      ['structured-emitter', 'tool-less schema sink — the only schema carrier (#169)'],
      ['dispatchSchemaAgent', 'produce single-agent ladder helper'],
      ['normalizeFailClosed', 'fail-closed → clean-skip mapping (the headline AC behavior)'],
      ['infraFailure', 'produce dispatch-death marker (never a verdict)'],
      ['failClosed', 'agent → engine source-unreachable signal'],
      ['retried: true', 'gate twice-dead flag'],
      ['failed: true', 'gate twice-dead flag'],
      ["'pass'", 'gate trinary verdict value'],
      ["'warn'", 'gate trinary verdict value'],
      ["'block'", 'gate trinary verdict value'],
      ['design-faithful-spec', 'produce (spec) dispatch name — #197 interface contract'],
      ['design-faithful-reviewer', 'gate dispatch name — #198 interface contract'],
      ['a11y-reviewer', 'gate dispatch name — #198 interface contract'],
    ]
    for (const [tok, why] of tokens) {
      src.includes(tok)
        ? pass(`G drift-guard: design-sync.mjs carries \`${tok}\` (${why})`)
        : fail(`G drift-guard: design-sync.mjs is MISSING \`${tok}\` (${why}) — production lost the behavior this selftest validates`)
    }
  }

  // ---- Case H: FAIL_CLOSED_REASONS byte-match the #195 contract-types.mjs FAIL_CLOSED block ----
  // Drift in BOTH directions: a 5th reason added to contract-types.mjs (engine would miss it) or a
  // reason dropped from the engine's inlined list both fail here.
  {
    let ctSrc = ''
    let dsSrc = ''
    try {
      ctSrc = readFileSync(CONTRACT_TYPES_MJS, 'utf8')
      dsSrc = readFileSync(DESIGN_SYNC_MJS, 'utf8')
    } catch (e) {
      fail(`H0 could not read source files: ${e}`)
    }
    // Extract the FAIL_CLOSED Object.freeze({...}) block from contract-types.mjs and pull its
    // string values (the reason vocabulary the #195 lib actually throws).
    const block = ctSrc.match(/FAIL_CLOSED\s*=\s*Object\.freeze\(\{([\s\S]*?)\}\)/)
    if (!block) {
      fail('H1 could not locate the FAIL_CLOSED Object.freeze block in contract-types.mjs')
    } else {
      const ctReasons = [...block[1].matchAll(/:\s*'([a-z][a-z-]*)'/g)].map((m) => m[1]).sort()
      // Extract the engine's OWN inlined array from design-sync.mjs source. This previously read
      // a hand-maintained copy declared inside this selftest, which meant H1 compared
      // contract-types against the HARNESS rather than against production — so a reason added to
      // the engine alone could never fail it. Reading the engine source closes that gap and
      // removes the last mirror from this file (#214).
      const engineBlock = dsSrc.match(/FAIL_CLOSED_REASONS\s*=\s*\[([\s\S]*?)\]/)
      if (!engineBlock) {
        fail('H1 could not locate the FAIL_CLOSED_REASONS array in design-sync.mjs')
      } else {
        const engineReasons = [...engineBlock[1].matchAll(/'([a-z][a-z-]*)'/g)].map((m) => m[1]).sort()
        eq('H1 contract-types FAIL_CLOSED values == engine FAIL_CLOSED_REASONS', ctReasons, engineReasons)
        eq('H2 engine inlines a non-empty reason vocabulary', engineReasons.length > 0, true)
      }
    }
  }

  // ---- Case I: Workflow meta purity (ALL sibling workflows/*.mjs) ----
  // The Workflow runtime requires `export const meta = {...}` to be a PURE LITERAL — a
  // BinaryExpression (string concatenation), template literal, call, spread, or identifier
  // value makes the runtime reject the whole script at dispatch ("non-literal node type in
  // meta"). v2.0.0 shipped design-sync.mjs with a concatenated meta.description and the
  // defect surfaced only at the first real dispatch (a canary run). This case is the
  // offline guard: heuristic literal-purity check (strip string literals, then forbid the
  // non-literal construct tokens) over every sibling workflow script that carries a meta.
  {
    const { readdirSync } = await import('node:fs')
    const metaFiles = readdirSync(HERE)
      .filter((f) => f.endsWith('.mjs'))
      .sort()
      .map((f) => [f, readFileSync(join(HERE, f), 'utf8')])
      // Line-start anchor: `export const meta` may legitimately appear INSIDE a string
      // elsewhere (e.g. this file's own Case-G token list) — only a top-level declaration counts.
      .filter(([, src]) => /^export const meta = \{/m.test(src))
    if (metaFiles.length === 0) fail('I0 no workflow scripts with `export const meta` found — glob broken?')
    for (const [file, src] of metaFiles) {
      // Meta block = from `export const meta = {` at line start to the first `}` at line start
      // (hand-style formatting invariant across these files).
      const m = src.match(/^export const meta = \{([\s\S]*?)\n\}/m)
      if (!m) {
        fail(`I meta-purity: ${file} — could not extract the meta block (formatting drifted?)`)
        continue
      }
      // Strip string literals in ONE left-to-right alternation pass (two sequential passes
      // mis-nest when a double-quoted string contains apostrophes, or vice versa), then any
      // remaining non-literal construct token is a violation.
      const stripped = m[1].replace(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"/g, '')
      const violations = [
        ['+', 'string concatenation (BinaryExpression)'],
        ['`', 'template literal'],
        ['${', 'template interpolation'],
        ['(', 'function call'],
        ['...', 'spread'],
      ].filter(([tok]) => stripped.includes(tok))
      violations.length === 0
        ? pass(`I meta-purity: ${file} meta is a pure literal`)
        : fail(`I meta-purity: ${file} meta contains ${violations.map(([, why]) => why).join(', ')} — the Workflow runtime will reject the script at dispatch`)
    }
  }

  console.log(`\n[design-sync-selftest] ${PASS} passed, ${FAIL} failed`)
  process.exit(FAIL)
}

main().catch((e) => {
  console.error(`[design-sync-selftest] FATAL: ${e?.stack || e}`)
  process.exit(99)
})
