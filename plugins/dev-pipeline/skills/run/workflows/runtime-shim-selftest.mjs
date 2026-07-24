#!/usr/bin/env node
// runtime-shim-selftest.mjs — execute WHOLE production Workflow `.mjs` bodies the way
// the Workflow runtime does, and assert their real dispatch ladders behaviorally.
//
// WHY THIS EXISTS (#214, epic #213)
// --------------------------------
// The suites this file replaces (design-sync-selftest.mjs Cases A-F, null-reviewer-
// selftest.mjs Cases A-E/G) were MIRROR HARNESSES: they re-implemented production's
// dispatch logic inside the selftest and then tested the copy. That technique is
// structurally incapable of failing on a production edit, and it rotted exactly as
// you would predict — both suites still modelled the pre-#169 StructuredOutput-retry
// transport long after production moved to the text-contract + emitter ladder, and
// stayed green the whole time. The #204 pathology, inside the tests built to prevent it.
//
// The blocker was believed to be structural: Workflow bodies carry a top-level `return`
// and reference runtime-injected globals, so `node file.mjs` and even `node --check`
// both fail. That made grep-on-source look like the only available technique.
//
// It is not. Strip the `export const meta = {…}` block and wrap the remainder in an
// async arrow taking the injected globals as parameters, and the body is ordinary
// executable JavaScript:
//
//     (async (agent, parallel, pipeline, args, log, phase, budget) => { …body… })
//
// The top-level `return` becomes a legal return from that arrow. Every global the body
// touches arrives as a parameter we control. So we can drive PRODUCTION code with canned
// agent outputs and assert on what it actually returns — no copies, no mirrors.
//
// WHAT THIS DOES AND DOES NOT PROVE
// ---------------------------------
// Proves: the real dispatch ladders in code-review.mjs and design-sync.mjs behave as
// specified under success, contract-miss-then-retry, emitter fallback, turn-cap death,
// hard-throw, and budget-exhaustion — because THIS FILE EXECUTES THOSE FILES.
// Does not prove: anything about the Workflow runtime itself (concurrency caps, real
// model dispatch, journal semantics). Those remain out of reach of a model-free CI.
//
// The meta-strip is a balanced-brace scan, not a parser. That is sound here because
// design-sync-selftest.mjs Case I lints every sibling workflow for meta-literal purity
// (no template interpolation, no computed values), so a brace inside a string in the
// meta block cannot ship.
//
// Exit code = number of failed checks (repo selftest convention).

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const CODE_REVIEW_MJS = join(HERE, 'code-review.mjs')
const DESIGN_SYNC_MJS = join(HERE, 'design-sync.mjs')

let PASS = 0
let FAIL = 0
const pass = (m) => {
  PASS++
  console.log(`  ok   ${m}`)
}
const fail = (m) => {
  FAIL++
  console.error(`  FAIL ${m}`)
}
const eq = (m, actual, expected) => {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  a === e ? pass(m) : fail(`${m}\n         expected ${e}\n         actual   ${a}`)
}
const ok = (m, cond) => (cond ? pass(m) : fail(m))

// ---------------------------------------------------------------------------
// The shim itself.
// ---------------------------------------------------------------------------

// Strip `export const meta = {…}` by balanced-brace scan. Returns the remaining body.
export const stripMeta = (src) => {
  const i = src.indexOf('export const meta')
  if (i < 0) throw new Error('no `export const meta` block found')
  let j = src.indexOf('{', i)
  if (j < 0) throw new Error('meta block has no opening brace')
  let depth = 0
  let k = j
  for (; k < src.length; k++) {
    if (src[k] === '{') depth++
    else if (src[k] === '}') {
      depth--
      if (depth === 0) {
        k++
        break
      }
    }
  }
  if (depth !== 0) throw new Error('meta block braces never balanced')
  return src.slice(0, i) + src.slice(k)
}

// Build a runnable function from a production workflow body. The injected globals are
// exactly the ones the Workflow tool documents: agent, parallel, pipeline, args, log,
// phase, budget.
const makeRunner = (path) => {
  const body = stripMeta(readFileSync(path, 'utf8'))
  // eslint-disable-next-line no-new-func
  return new Function(
    'agent',
    'parallel',
    'pipeline',
    'args',
    'log',
    'phase',
    'budget',
    `return (async () => {\n${body}\n})()`,
  )
}

// A fake agent driven by a behavior QUEUE (the pattern proven in the suite this file
// replaces). Each entry is either a string (returned as the agent's text), or
// { throw: 'msg' }, or a function of the dispatch opts, or a plain object.
//
// The string-vs-object distinction models the runtime faithfully and is load-bearing:
// a schema-FREE dispatch (every explorer, post-#169) resolves to TEXT that production
// parses itself, while a schema-carrying dispatch (only ever the structured-emitter)
// resolves to an already-VALIDATED OBJECT. Feeding a text block to the emitter leg
// would make production's validateShape reject a string and the case would fail for
// the wrong reason.
const makeFakeAgent = (behaviors) => {
  const calls = []
  const queue = [...behaviors]
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    const next = queue.length ? queue.shift() : ''
    if (next && typeof next === 'object' && 'throw' in next) throw new Error(next.throw)
    return typeof next === 'function' ? next(opts) : next
  }
  return { agent, calls, remaining: () => queue.length }
}

// Runtime doubles. parallel() is a barrier over thunks; pipeline() threads stages.
const parallel = (thunks) => Promise.all(thunks.map((t) => t()))
const pipeline = async (items, ...stages) => {
  const out = []
  for (let i = 0; i < items.length; i++) {
    let v = items[i]
    for (const s of stages) v = await s(v, items[i], i)
    out.push(v)
  }
  return out
}
const noop = () => {}
const makeBudget = (total, remaining) => ({ total, spent: () => total - remaining, remaining: () => remaining })

// A well-formed REVIEW_RESULT block for code-review's FINDINGS_SCHEMA. The field names
// and the verdict enum are NOT interchangeable with the intake/gate schemas — production's
// validateShape rejects a near-miss, which is the point.
const findingsBlock = (verdict = 'approve') =>
  'REVIEW_RESULT\n```json\n' +
  JSON.stringify({
    verdict,
    findings: [{ severity: 'minor', title: 't', description: 'd', confidence: 70, file: 'f.ts', line: 1 }],
  }) +
  '\n```'

// The same for design-sync's GATE_SCHEMA (verdict enum pass|warn|block), optionally
// carrying a failClosed marker.
const gateBlock = (extra = {}) =>
  'REVIEW_RESULT\n```json\n' +
  JSON.stringify({
    verdict: 'pass',
    findings: [{ severity: 'nit', title: 't', description: 'd', confidence: 60 }],
    ...extra,
  }) +
  '\n```'

const runCodeReview = (behaviors, argsOverride = {}) => {
  const f = makeFakeAgent(behaviors)
  const args = {
    worktree: '/tmp/wt',
    base: 'aaa',
    head: 'bbb',
    issue: '214',
    reviewers: ['review-toolkit:complexity-reviewer'],
    changedFiles: ['a.ts'],
    config: { reviewers: {} },
    ...argsOverride,
  }
  return makeRunner(CODE_REVIEW_MJS)(f.agent, parallel, pipeline, args, noop, noop, undefined).then((r) => ({
    result: r,
    calls: f.calls,
  }))
}

console.log('[runtime-shim-selftest]')

// ---------------------------------------------------------------------------
// Case A — the shim mechanically works on both production bodies.
// ---------------------------------------------------------------------------
console.log('── Case A: meta-strip + wrap executes production bodies')
for (const [name, path] of [
  ['code-review.mjs', CODE_REVIEW_MJS],
  ['design-sync.mjs', DESIGN_SYNC_MJS],
]) {
  try {
    makeRunner(path)
    pass(`A ${name} strips its meta block and compiles under the runtime wrapper`)
  } catch (e) {
    fail(`A ${name} failed to compile under the runtime wrapper: ${e.message}`)
  }
}
// The wrapper is load-bearing precisely because the naive forms fail. Pin that the body
// really does carry a top-level return (the reason `node --check` cannot be used here).
{
  const raw = readFileSync(CODE_REVIEW_MJS, 'utf8')
  ok('A code-review.mjs carries a top-level return (why node --check cannot check it)', /\n\s{0,2}return \{/.test(raw))
}

// ---------------------------------------------------------------------------
// Case B — code-review.mjs reviewer dispatch ladder (the real one, #169).
// ---------------------------------------------------------------------------
console.log('── Case B: code-review.mjs text-contract ladder')

{
  const { result, calls } = await runCodeReview([findingsBlock('approve')])
  eq('B1 success first try returns the parsed result', result.reviewers[0].result.verdict, 'approve')
  eq('B1 success first try dispatches exactly once', calls.length, 1)
  ok('B1 a first-try success carries no retried/failed flags', !result.reviewers[0].retried && !result.reviewers[0].failed)
  eq('B1 range is the THREE-DOT form (#130)', result.range, 'aaa...bbb')
}

{
  // Contract miss (no sentinel) then success — the escalated inline retry.
  const { result, calls } = await runCodeReview(['I have thoughts but no sentinel.', findingsBlock('approve')])
  eq('B2 retry after a text-contract miss recovers', result.reviewers[0].result.verdict, 'approve')
  eq('B2 retry dispatches exactly twice', calls.length, 2)
  ok('B2 the second dispatch is labelled a retry', String(calls[1].opts.label).includes('retry'))
  ok('B2 a recovered retry is indistinguishable from a first-try success', !result.reviewers[0].failed)
}

{
  // Sentinel present but unparseable on both attempts -> the structured-emitter fallback.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  // The emitter leg carries the schema, so the runtime hands back a validated OBJECT.
  const emitterObject = {
    verdict: 'request-changes',
    findings: [{ severity: 'major', title: 't', description: 'd', confidence: 80 }],
  }
  const { result, calls } = await runCodeReview([bad, bad, emitterObject])
  eq('B3 emitter fallback recovers a sentinel-bearing unparseable block', result.reviewers[0].result.verdict, 'request-changes')
  eq('B3 emitter fallback costs a third dispatch', calls.length, 3)
  eq('B3 the fallback is the tool-less structured-emitter', calls[2].opts.agentType, 'review-toolkit:structured-emitter')
  ok('B3 the emitter is the ONLY schema carrier in the ladder', !!calls[2].opts.schema && !calls[0].opts.schema && !calls[1].opts.schema)
}

{
  // Empty text on both attempts = the maxTurns-cap death. Must be dark AND must carry
  // the turn-budget error signature, which is what points triage at an emit deadline
  // rather than at the parser (#183).
  const { result, calls } = await runCodeReview(['', ''])
  const r = result.reviewers[0]
  eq('B4 turn-cap death dispatches twice then gives up', calls.length, 2)
  eq('B4 turn-cap death yields a null result', r.result, null)
  ok('B4 turn-cap death carries the twice-dead markers', r.retried === true && r.failed === true)
  ok('B4 turn-cap death is reported as turn-budget, not a parser miss', String(r.error).startsWith('turn-budget:'))
}

{
  // Text produced, but never a sentinel -> dark with the OTHER error string. The two
  // causes must stay distinguishable; conflating them cost real triage time (#183).
  const { result } = await runCodeReview(['prose only', 'prose only again'])
  ok('B5 sentinel-less text is dark via the text-contract string', String(result.reviewers[0].error).startsWith('text-contract:'))
  ok('B5 sentinel-less text still carries the twice-dead markers', result.reviewers[0].retried === true)
}

{
  // A hard dispatch throw on the FIRST attempt returns immediately — production does
  // NOT retry a transport/permission/budget throw, only a text-contract miss. (This
  // assertion was written backwards first; executing production corrected it.)
  const { result, calls } = await runCodeReview([{ throw: 'boom' }])
  eq('B6 a first-attempt throw is NOT retried', calls.length, 1)
  eq('B6 a thrown dispatch yields a null result', result.reviewers[0].result, null)
  ok('B6 the throw is forwarded, never dropped', String(result.reviewers[0].error).includes('boom'))
  ok('B6 a first-attempt throw is NOT flagged twice-dead', !result.reviewers[0].retried && !result.reviewers[0].failed)
}

{
  // The `retry failed:` branch is reachable only when attempt 0 MISSES the contract
  // (no throw) and attempt 1 then throws — the one path that flags twice-dead on a throw.
  const { result, calls } = await runCodeReview(['no sentinel here', { throw: 'died on retry' }])
  eq('B7 miss-then-throw dispatches twice', calls.length, 2)
  ok('B7 a throw on the retry IS flagged twice-dead', result.reviewers[0].retried === true && result.reviewers[0].failed === true)
  ok('B7 the error names the retry', String(result.reviewers[0].error).includes('retry failed'))
}

// ---------------------------------------------------------------------------
// Case C — code-review.mjs budget clean-skip (all-or-nothing).
// ---------------------------------------------------------------------------
console.log('── Case C: code-review.mjs budget clean-skip')
{
  const f = makeFakeAgent([findingsBlock()])
  const args = {
    worktree: '/tmp/wt',
    base: 'aaa',
    head: 'bbb',
    issue: '214',
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: {} },
  }
  const result = await makeRunner(CODE_REVIEW_MJS)(f.agent, parallel, pipeline, args, noop, noop, makeBudget(100000, 0))
  eq('C1 exhausted budget returns the budgetExhausted marker', result.budgetExhausted, true)
  eq('C1 exhausted budget dispatches NOTHING (all-or-nothing)', f.calls.length, 0)
  eq('C1 exhausted budget yields an empty reviewer set by construction', result.reviewers, [])
}

// ---------------------------------------------------------------------------
// Case D — design-sync.mjs args validation (rebuilt from the deleted Case A).
// ---------------------------------------------------------------------------
console.log('── Case D: design-sync.mjs args validation')
const runDesignSync = (behaviors, args, budget) => {
  const f = makeFakeAgent(behaviors)
  return makeRunner(DESIGN_SYNC_MJS)(f.agent, parallel, pipeline, args, noop, noop, budget).then(
    (result) => ({ result, calls: f.calls }),
    (error) => ({ error, calls: f.calls }),
  )
}
{
  const { error } = await runDesignSync([], { kind: 'nonsense' })
  ok('D1 an illegal kind is rejected', !!error && /args.kind must be/.test(error.message))
}
{
  const { error } = await runDesignSync([], { kind: 'produce', screen: 'detail' })
  ok('D2 produce without projectId is rejected', !!error && /projectId and args.screen are required/.test(error.message))
}
{
  const { error } = await runDesignSync([], { kind: 'produce', implement: true, projectId: 'p', screen: 'detail' })
  ok('D3 produce implement:true without a worktree is rejected (F26)', !!error && /args.worktree is required when implement:true/.test(error.message))
}
{
  const { error } = await runDesignSync([], { kind: 'gate', worktree: '/tmp/wt', base: 'a', head: 'b', reviewers: [] })
  ok('D4 gate with an empty reviewer set is rejected', !!error && /reviewers must be a non-empty array/.test(error.message))
}

// ---------------------------------------------------------------------------
// Case E — design-sync.mjs gate-reviewer first-throw returns {error} immediately.
// This is the behavior the deleted mirror got WRONG: it modelled a retry that
// production does not perform on a throw.
// ---------------------------------------------------------------------------
console.log('── Case E: design-sync.mjs gate dispatch ladder')
{
  const gateArgs = {
    kind: 'gate',
    worktree: '/tmp/wt',
    base: 'a',
    head: 'b',
    issue: '214',
    reviewers: ['design-toolkit:design-faithful-reviewer'],
    config: { reviewers: {} },
  }
  const { result, calls, error } = await runDesignSync([{ throw: 'transport died' }], gateArgs)
  // REGRESSION GUARD (#214): before this PR the gate path referenced the retired
  // STRUCTURED_OUTPUT_MANDATE (#169), an identifier design-sync.mjs never defines, so
  // EVERY gate dispatch died with ReferenceError before reaching a model. The mirror
  // harness could not see it — it exercised its own copy of dispatchGateReviewer.
  // Executing the real body is the only technique that catches this class.
  ok('E0 the gate path executes without a ReferenceError (retired-global regression)', !error || !/is not defined/.test(String(error.message)))
  eq('E1 a first-attempt throw is NOT retried (production returns immediately)', calls.length, 1)
  const entry = result && Array.isArray(result.reviewers) ? result.reviewers[0] : undefined
  ok('E1 the throw is forwarded as an error entry', !!entry && entry.result === null && !!entry.error)
  ok('E1 a first-throw is NOT flagged twice-dead', !!entry && !entry.retried && !entry.failed)
}

// ---------------------------------------------------------------------------
// Case F — design-sync.mjs normalizeFailClosed, exercised END TO END.
// The deleted Case C tested an in-file COPY of this function. Here the real one runs:
// we feed a fail-closed payload through the production gate and assert the envelope.
// ---------------------------------------------------------------------------
console.log('── Case F: design-sync.mjs fail-closed normalization (end-to-end)')
{
  const FAIL_CLOSED = ['design-source-unreachable', 'project-type-mismatch', 'file-too-large', 'batch-overflow']
  const gateArgs = {
    kind: 'gate',
    worktree: '/tmp/wt',
    base: 'a',
    head: 'b',
    issue: '214',
    reviewers: ['design-toolkit:design-faithful-reviewer'],
    config: { reviewers: {} },
  }
  for (const reason of FAIL_CLOSED) {
    const { result, error } = await runDesignSync([gateBlock({ failClosed: { reason, detail: 'd' } })], gateArgs)
    const blob = JSON.stringify(result ?? String(error))
    ok(`F ${reason} survives normalization into the returned envelope`, blob.includes(reason))
  }
  // An UNKNOWN reason must NOT be promoted to a fail-closed marker — that is the whole
  // point of the allowlist (an unknown string masquerading as a clean skip would mask a
  // real verdict).
  const { result } = await runDesignSync([gateBlock({ failClosed: { reason: 'totally-made-up-reason' } })], gateArgs)
  const unknownEntry = result.reviewers[0]
  // The raw agent payload still carries the bogus marker under `result` — that is fine
  // and expected. What must NOT happen is PROMOTION to the entry-level `failClosed`
  // annotation, which is what downstream reads. Assert on structure, not substring.
  ok('F an UNKNOWN failClosed reason is not promoted to the entry-level marker', !('failClosed' in unknownEntry))
  const { result: knownResult } = await runDesignSync(
    [gateBlock({ failClosed: { reason: 'file-too-large', detail: 'd' } })],
    gateArgs,
  )
  ok(
    'F the known-reason path DOES promote (proving the check above is not vacuous)',
    'failClosed' in knownResult.reviewers[0] && knownResult.reviewers[0].failClosed.reason === 'file-too-large',
  )
}

console.log(`\n[runtime-shim-selftest] ${PASS} passed, ${FAIL} failed`)
process.exit(FAIL)
