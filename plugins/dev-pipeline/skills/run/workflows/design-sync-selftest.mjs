#!/usr/bin/env node
// design-sync-selftest.mjs — verifies the design-faithful produce/gate engine (#196).
//
// Style note: like its sibling Workflow scripts (code-review.mjs, unit-tests.mjs,
// null-reviewer-selftest.mjs), this file is NOT covered by the repo `format` script (which globs
// only .{ts,tsx,js,json,md}), so it follows their hand-style: no semicolons, single quotes.
//
// WHY THIS IS SELF-CONTAINED (and does not import design-sync.mjs):
//   design-sync.mjs is a Workflow script, NOT a node-importable ESM module. It uses a top-level
//   `return` (the Workflow runtime wraps the body in an async function) and references
//   runtime-injected globals (agent, parallel, args, log, phase, budget) with no imports.
//   `node --check` rejects its top-level return, and importing it under node would throw on the
//   undefined globals. So this selftest carries a REFERENCE harness that mirrors the engine's pure
//   decision logic (validation, budget skip, normalizeFailClosed, the produce dispatchSchemaAgent
//   retry, the gate dispatchReviewer retry), PLUS a structural drift-guard (Cases G/H) that reads
//   design-sync.mjs as text and asserts the load-bearing tokens are present and the inlined
//   FAIL_CLOSED_REASONS byte-match contract-types.mjs — so the production engine cannot silently
//   lose the behavior this selftest validates, nor drift from the #195 fail-closed enum.
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
const throws = async (label, fn, regex) => {
  try {
    await fn()
    fail(`${label} — expected throw, got none`)
  } catch (e) {
    regex.test(String(e)) ? pass(label) : fail(`${label} — threw ${JSON.stringify(String(e))}, wanted ${regex}`)
  }
}

// ---------------------------------------------------------------------------
// Reference harness — faithful copies of design-sync.mjs's pure decision logic, with the Workflow
// globals (agent, log) injected as params so the control flow is exercisable under plain node.
// Prompt-building is elided (irrelevant to the decisions). Drift-guards (Cases G/H) keep these in
// sync with production.
// ---------------------------------------------------------------------------
const FAIL_CLOSED_REASONS = ['design-source-unreachable', 'project-type-mismatch', 'file-too-large', 'batch-overflow']
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

const normalizeFailClosed = (result) => {
  const fc = result && result.failClosed
  if (fc && typeof fc.reason === 'string' && FAIL_CLOSED_REASONS.includes(fc.reason)) {
    return fc.detail === undefined ? { reason: fc.reason } : { reason: fc.reason, detail: fc.detail }
  }
  return null
}

// Mirrors the args-validation block in design-sync.mjs.
function validateArgs(a) {
  const { kind, projectId, screen, reviewers = ['design-faithful-reviewer', 'a11y-reviewer'], worktree, base, head } = a
  if (kind !== 'produce' && kind !== 'gate') {
    throw new Error("design-sync workflow: args.kind must be 'produce' or 'gate'")
  }
  if (kind === 'produce' && (!projectId || !screen)) {
    throw new Error('design-sync produce: args.projectId and args.screen are required')
  }
  if (kind === 'gate') {
    if (!worktree || !base || !head) {
      throw new Error('design-sync gate: args.worktree, args.base and args.head are required')
    }
    if (!Array.isArray(reviewers) || reviewers.length === 0) {
      throw new Error('design-sync gate: args.reviewers must be a non-empty array of agentType strings')
    }
  }
  return true
}

// Mirrors the budget clean-skip in design-sync.mjs.
function budgetCleanSkip(kind, budget) {
  if (budget && budget.total && budget.remaining() <= 0) return { kind, budgetExhausted: true }
  return null
}

// Mirrors dispatchSchemaAgent() (produce path).
function makeDispatchSchemaAgent({ agent, log }) {
  return async function dispatchSchemaAgent(opts, retries = 2) {
    let lastErr
    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        return await agent(attempt === 0 ? opts : { ...opts, label: `${opts.label} (retry ${attempt})` })
      } catch (err) {
        lastErr = err
        if (!isNoStructuredOutputError(err)) throw err
        log(`${opts.label}: died without StructuredOutput — retry ${attempt + 1}/${retries}`)
      }
    }
    throw lastErr
  }
}

// Mirrors the produce-path .catch → infraFailure envelope.
const produceCatch = (err) => ({ summary: 'agent dispatch failed: ' + String(err), infraFailure: true })

// Mirrors dispatchGateReviewer() (gate path).
function makeDispatchGateReviewer({ agent, log }) {
  return async function dispatchGateReviewer(agentType) {
    const annotate = (result) => {
      const failClosed = normalizeFailClosed(result)
      return failClosed ? { agentType, result, failClosed } : { agentType, result }
    }
    try {
      return annotate(await agent({ agentType, attempt: 1 }))
    } catch (err) {
      if (!isNoStructuredOutputError(err)) return { agentType, result: null, error: String(err) }
      log(`${agentType}: died without StructuredOutput — retrying once`)
      try {
        return annotate(await agent({ agentType, attempt: 2 }))
      } catch (retryErr) {
        return {
          agentType,
          result: null,
          error: `retry failed: ${retryErr}; first attempt: ${err}`,
          retried: true,
          failed: true,
        }
      }
    }
  }
}

function fakeAgent(behaviors) {
  let calls = 0
  const fn = async () => {
    const b = behaviors[calls] ?? behaviors[behaviors.length - 1]
    calls++
    if (b.throw !== undefined) throw b.throw
    return b.ok
  }
  fn.callCount = () => calls
  return fn
}

const noopLog = () => {}
const soError = new Error('subagent completed without calling StructuredOutput (after 2 in-conversation nudges)')

async function main() {
  // ---- Case A: args validation ----
  {
    await throws('A1 bad kind throws', async () => validateArgs({ kind: 'frobnicate' }), /must be 'produce' or 'gate'/)
    await throws('A2 produce without projectId throws', async () => validateArgs({ kind: 'produce', screen: 'detail' }), /projectId and args.screen/)
    await throws('A3 produce without screen throws', async () => validateArgs({ kind: 'produce', projectId: 'p1' }), /projectId and args.screen/)
    eq('A4 produce with projectId+screen ok', validateArgs({ kind: 'produce', projectId: 'p1', screen: 'detail' }), true)
    await throws('A5 gate without head throws', async () => validateArgs({ kind: 'gate', worktree: '/w', base: 'a' }), /worktree, args.base and args.head/)
    await throws('A6 gate with empty reviewers throws', async () => validateArgs({ kind: 'gate', worktree: '/w', base: 'a', head: 'b', reviewers: [] }), /non-empty array/)
    eq('A7 gate with defaults ok', validateArgs({ kind: 'gate', worktree: '/w', base: 'a', head: 'b' }), true)
  }

  // ---- Case B: budget clean-skip (NOT a fake block) ----
  {
    eq('B1 exhausted budget → clean skip', budgetCleanSkip('gate', { total: 100, remaining: () => 0 }), { kind: 'gate', budgetExhausted: true })
    eq('B2 budget remaining → no skip', budgetCleanSkip('produce', { total: 100, remaining: () => 50 }), null)
    eq('B3 no budget set → no skip', budgetCleanSkip('produce', { total: null, remaining: () => 0 }), null)
    eq('B4 skip shape carries no verdict/block', Object.keys(budgetCleanSkip('gate', { total: 1, remaining: () => 0 })).sort(), ['budgetExhausted', 'kind'])
  }

  // ---- Case C: normalizeFailClosed ----
  {
    eq('C1 known reason → marker', normalizeFailClosed({ failClosed: { reason: 'design-source-unreachable' } }), { reason: 'design-source-unreachable' })
    eq('C2 known reason preserves detail', normalizeFailClosed({ failClosed: { reason: 'file-too-large', detail: 'styles.css' } }), { reason: 'file-too-large', detail: 'styles.css' })
    eq('C3 unknown reason → null (cannot mask a real verdict)', normalizeFailClosed({ failClosed: { reason: 'made-up' } }), null)
    eq('C4 no failClosed → null', normalizeFailClosed({ verdict: 'block', findings: [] }), null)
    eq('C5 null/undefined result → null', normalizeFailClosed(undefined), null)
    eq('C6 all four #195 reasons are recognized', FAIL_CLOSED_REASONS.map((r) => normalizeFailClosed({ failClosed: { reason: r } }) !== null), [true, true, true, true])
  }

  // ---- Case D: dispatchSchemaAgent retry (produce path) ----
  {
    const okVal = { summary: 'wrote spec', artifactPath: 'docs/x.md' }
    {
      const agent = fakeAgent([{ ok: okVal }])
      const d = makeDispatchSchemaAgent({ agent, log: noopLog })
      eq('D1 success first try', await d({ label: 'design-faithful-spec' }), okVal)
      eq('D2 success calls agent once', agent.callCount(), 1)
    }
    {
      const agent = fakeAgent([{ throw: soError }, { ok: okVal }])
      const d = makeDispatchSchemaAgent({ agent, log: noopLog })
      eq('D3 SO death then recover', await d({ label: 'design-faithful-spec' }), okVal)
      eq('D4 recover calls agent twice', agent.callCount(), 2)
    }
    {
      const agent = fakeAgent([{ throw: soError }, { throw: soError }, { throw: soError }])
      const d = makeDispatchSchemaAgent({ agent, log: noopLog })
      await throws('D5 SO death exhausts retries → throws', async () => d({ label: 'design-faithful-spec' }, 2), /StructuredOutput/)
      eq('D6 retries=2 means 3 attempts total', agent.callCount(), 3)
    }
    {
      const agent = fakeAgent([{ throw: new Error('permission denied: tool DesignSync') }])
      const d = makeDispatchSchemaAgent({ agent, log: noopLog })
      await throws('D7 genuine error throws immediately', async () => d({ label: 'design-faithful' }), /permission denied/)
      eq('D8 genuine error NOT retried', agent.callCount(), 1)
    }
    // produce .catch → infraFailure envelope
    {
      const out = produceCatch(soError)
      eq('D9 produce dispatch-death maps to infraFailure (not a verdict)', [out.infraFailure, typeof out.summary], [true, 'string'])
    }
  }

  // ---- Case E: dispatchGateReviewer retry + failClosed annotation (gate path) ----
  {
    {
      const agent = fakeAgent([{ ok: { verdict: 'pass', findings: [] } }])
      const d = makeDispatchGateReviewer({ agent, log: noopLog })
      eq('E1 success → {agentType,result}', await d('design-faithful-reviewer'), { agentType: 'design-faithful-reviewer', result: { verdict: 'pass', findings: [] } })
      eq('E2 success calls agent once', agent.callCount(), 1)
    }
    {
      const agent = fakeAgent([{ ok: { verdict: 'block', findings: [], failClosed: { reason: 'design-source-unreachable' } } }])
      const d = makeDispatchGateReviewer({ agent, log: noopLog })
      const out = await d('a11y-reviewer')
      eq('E3 known failClosed is annotated onto the entry', out.failClosed, { reason: 'design-source-unreachable' })
      // The whole entry is still forwarded (agentType + full result intact) alongside the marker, so
      // the caller reads it as a clean skip, not a dropped reviewer or a real `block`.
      eq('E4 fail-closed reviewer forwarded with agentType+result intact (clean skip, not block)', [out.agentType, out.result.verdict, out.result.findings.length], ['a11y-reviewer', 'block', 0])
    }
    {
      const agent = fakeAgent([{ throw: soError }, { ok: { verdict: 'warn', findings: [] } }])
      const d = makeDispatchGateReviewer({ agent, log: noopLog })
      eq('E5 SO death then recover', await d('design-faithful-reviewer'), { agentType: 'design-faithful-reviewer', result: { verdict: 'warn', findings: [] } })
      eq('E6 recover calls agent twice', agent.callCount(), 2)
    }
    {
      const agent = fakeAgent([{ throw: soError }, { throw: soError }])
      const d = makeDispatchGateReviewer({ agent, log: noopLog })
      const out = await d('a11y-reviewer')
      eq('E7 twice-dead result null + retried/failed', [out.result, out.retried, out.failed], [null, true, true])
      eq('E8 twice-dead calls agent twice (one retry, not a loop)', agent.callCount(), 2)
    }
    {
      const agent = fakeAgent([{ throw: new Error('permission denied: tool Bash') }])
      const d = makeDispatchGateReviewer({ agent, log: noopLog })
      const out = await d('design-faithful-reviewer')
      eq('E9 genuine error forwarded, not retried', [out.result, out.retried, out.failed], [null, undefined, undefined])
      eq('E10 genuine error calls agent once', agent.callCount(), 1)
    }
  }

  // ---- Case F: isNoStructuredOutputError predicate semantics ----
  {
    eq('F1 matches the runtime death message', isNoStructuredOutputError(soError), true)
    eq('F2 matches a bare string containing the token', isNoStructuredOutputError('...StructuredOutput...'), true)
    eq('F3 rejects an unrelated error', isNoStructuredOutputError(new Error('permission denied')), false)
    eq('F4 rejects empty/undefined', isNoStructuredOutputError(undefined), false)
  }

  // ---- Case G: structural drift-guard against production design-sync.mjs ----
  {
    let src = ''
    try {
      src = readFileSync(DESIGN_SYNC_MJS, 'utf8')
    } catch (e) {
      fail(`G0 could not read design-sync.mjs at ${DESIGN_SYNC_MJS}: ${e}`)
    }
    const tokens = [
      ['export const meta', 'Workflow loader entry — engine will not register without it'],
      ["phase('Design Sync')", 'progress phase'],
      ["kind === 'produce'", 'produce branch discriminator'],
      ["kind === 'gate'", 'gate branch discriminator'],
      ['budgetExhausted: true', 'budget clean-skip marker (not a fake block/error)'],
      ['isNoStructuredOutputError', 'retry-decision predicate name'],
      ['/StructuredOutput/.test', 'predicate regex (the only signal the runtime surfaces)'],
      ['dispatchSchemaAgent', 'produce single-agent retry helper'],
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
      const engineReasons = [...FAIL_CLOSED_REASONS].sort()
      eq('H1 contract-types FAIL_CLOSED values == engine FAIL_CLOSED_REASONS', ctReasons, engineReasons)
      // And assert the engine SOURCE inlines exactly those (catches the reference harness drifting
      // from production even if the harness copy above happens to match contract-types).
      const allInEngineSrc = engineReasons.every((r) => dsSrc.includes(`'${r}'`))
      eq('H2 engine source inlines every reason string', allInEngineSrc, true)
    }
  }

  console.log(`\n[design-sync-selftest] ${PASS} passed, ${FAIL} failed`)
  process.exit(FAIL)
}

main().catch((e) => {
  console.error(`[design-sync-selftest] FATAL: ${e?.stack || e}`)
  process.exit(99)
})
