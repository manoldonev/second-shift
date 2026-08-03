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
//     (async (agent, parallel, pipeline, args, log, phase, budget, workflow) => { …body… })
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
// The shim mechanics themselves (stripMeta / makeRunner / the injected fakes) live in
// `runtime-shim-lib.mjs` — a non-glob sibling, so CI never executes it directly — because
// the E2E replay's stage-4/5/8 legs drive production workflows through the same wrapper.
// Two consumers, one definition; see that file's header.
//
// Exit code = number of failed checks (repo selftest convention).

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  makeBudget,
  makeFakeAgent,
  makeFakeWorkflow,
  makeRunner,
  noop,
  parallel,
  pipeline,
  reviewBlock,
  stripMeta,
} from './runtime-shim-lib.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const CODE_REVIEW_MJS = join(HERE, 'code-review.mjs')
const DESIGN_SYNC_MJS = join(HERE, 'design-sync.mjs')
const INTAKE_REVIEW_MJS = join(HERE, 'intake-review.mjs')

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

// A well-formed REVIEW_RESULT block for code-review's FINDINGS_SCHEMA. The field names
// and the verdict enum are NOT interchangeable with the intake/gate schemas — production's
// validateShape rejects a near-miss, which is the point.
const findingsBlock = (verdict = 'approve') =>
  reviewBlock({
    verdict,
    findings: [{ severity: 'minor', title: 't', description: 'd', confidence: 70, file: 'f.ts', line: 1 }],
  })

// The same for design-sync's GATE_SCHEMA (verdict enum pass|warn|block), optionally
// carrying a failClosed marker.
const gateBlock = (extra = {}) =>
  reviewBlock({
    verdict: 'pass',
    findings: [{ severity: 'nit', title: 't', description: 'd', confidence: 60 }],
    ...extra,
  })

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

// ---------------------------------------------------------------------------
// Case G — the injected `workflow` global (the 8th wrapper parameter, #217).
//
// Without it, mutation-gate.mjs and plan-review.mjs die with a ReferenceError before
// reaching a fake — the same class as design-sync.mjs's retired STRUCTURED_OUTPUT_MANDATE
// (Case E0). An 8th parameter that nothing invokes is untested wiring, so this case
// asserts the nested dispatch actually goes THROUGH it, and that the argument really is
// last (a mis-ordered insert would silently shift `args` and is caught by G3).
//
// G1 is deliberately the WEAK assertion and must not be read as the guard. Verified by
// removing the parameter and re-running: G1 stays green, because mutation-gate.mjs wraps
// its propose call in try/catch (`proposalError = 'propose dispatch threw: …'`) and
// swallows the ReferenceError into its own retry loop. G2/G3/G4 are the killers — they go
// red on that mutant. The distinction matters: a future reader trimming this case to "the
// ReferenceError check" would be left with a guard that cannot fail.
// ---------------------------------------------------------------------------
console.log('── Case G: the injected workflow() global')
{
  const MUTATION_GATE_MJS = join(HERE, 'mutation-gate.mjs')
  const gateArgs = {
    worktree: '/tmp/wt',
    base: 'aaa',
    head: 'bbb',
    issue: '217',
    workflowsDir: 'workflows',
    round: 1,
    inputs: {},
    config: { reviewers: {} },
    testFileCommand: 'true {file}',
  }
  // The nested propose call resolves to unit-tests.mjs's envelope. No blocker mutants ⇒
  // no executor dispatches, so the gate reaches its verdict on the proposal alone.
  const f = makeFakeAgent([])
  const w = makeFakeWorkflow([{ result: { mutants: [], mockAuditFindings: [], summary: 'canned' } }])
  let result
  let error
  try {
    result = await makeRunner(MUTATION_GATE_MJS)(f.agent, parallel, pipeline, gateArgs, noop, noop, undefined, w.workflow)
  } catch (e) {
    error = e
  }
  ok('G1 mutation-gate.mjs executes without a ReferenceError on the workflow global', !error || !/is not defined/.test(String(error.message)))
  eq('G2 the nested propose goes through the injected workflow()', w.calls.length, 1)
  ok('G3 the nested dispatch targets unit-tests.mjs (proving args reached the body intact)', String(w.calls[0]?.ref?.scriptPath) === 'workflows/unit-tests.mjs')
  // NOT merely `typeof overall === 'string'` — under the missing-parameter mutant the
  // swallowed ReferenceError produces overall:'infra', which is also a string. Asserting
  // the propose SUCCEEDED is what makes this a killer.
  ok('G4 the canned proposal is consumed (overall is a real verdict, not the infra path)', !!result && result.overall !== 'infra' && typeof result.overall === 'string')
  eq('G5 no executor is dispatched when there are no blocker mutants', f.calls.length, 0)
}

// ---------------------------------------------------------------------------
// Case H — args.config delivery path: the SUBSET the dispatch prose passes must carry
// everything code-review.mjs actually reads (#77).
//
// The stage files tell the caller what to put in args.config. That prose cannot be
// guarded by grepping it (CLAUDE.md bans prose-presence guards, and a markdown grep
// cannot fail for a reason a diff reader would not already see). What IS guardable is
// the receiving end: given ONLY the documented subset, does production still resolve a
// model override, and does it still route the tracker branch? Both are silent-failure
// paths — modelOverrides falls back to the shipped table, trackerType defaults to
// 'github' — so neither errors when its key is missing. That is precisely why they need
// a behavioral guard rather than a reviewer's attention.
//
// H2/H3 are the pair that makes this a killer. H2 alone would stay green if `tracker`
// were dropped from the Stage-8 subset and the default happened to match the fixture, so
// H3 pins the opposite branch: the two must DIFFER. Each case also asserts it reached the
// scope-completeness prompt at all — without that, a mis-wired reviewers override would
// assert against runCodeReview's default complexity-reviewer prompt and pass vacuously
// (the failure mode plan review flagged on this very case).
// ---------------------------------------------------------------------------
console.log('── Case H: args.config subset delivery (#77)')
{
  // H1 — a modelOverrides entry survives the subset and reaches the dispatched model.
  // Bare-keyed by agent name, per every consumer's `modelOverrides[bare(agentType)]`.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { modelOverrides: { 'complexity-reviewer': 'fable' } } },
  })
  ok('H1 modelOverrides reaches the dispatched opts.model', calls[0]?.opts?.model === 'fable')
}
{
  // H2 — tracker.type: jira survives the subset and routes the scope reviewer to the MCP.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:scope-completeness-reviewer'],
    issue: 'GH-540',
    config: { reviewers: {}, tracker: { type: 'jira' } },
  })
  const p = String(calls[0]?.prompt ?? '')
  ok('H2a the scope-completeness prompt was actually dispatched (anti-vacuity)', /Verify scope completeness/.test(p))
  ok('H2b tracker.type jira routes the fetch to the Atlassian MCP', /Atlassian MCP/.test(p))
}
{
  // H3 — the same dispatch with `tracker` ABSENT falls back to gh. This is the mutant
  // detector: drop `tracker` from the Stage-8 subset and H2b goes red while this stays
  // green, so the two together prove the key is load-bearing rather than decorative.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:scope-completeness-reviewer'],
    issue: '77',
    config: { reviewers: {} },
  })
  const p = String(calls[0]?.prompt ?? '')
  ok('H3a the scope-completeness prompt was actually dispatched (anti-vacuity)', /Verify scope completeness/.test(p))
  ok('H3b no tracker key falls back to the gh issue view fetch', /gh issue view/.test(p) && !/Atlassian MCP/.test(p))
}

// ---------------------------------------------------------------------------
// Case M — intake-review.mjs's per-agent wall-clock ceiling (#283).
//
// AC-5: a leg that never emits must be declared dark by the CEILING'S TIMER, not by
// exhausting its turn cap. The fake agent behavior below is a function returning a
// promise that never resolves — the turn-cap-exhaustion path (Case B4's analogue: two
// '' attempts, calls.length === 2) cannot even be reached, since dispatchIntake's
// `await agent(...)` never returns and the retry loop never gets a second iteration.
// The ONLY way this test terminates is the ceiling's setTimeout firing, which is
// patched to fire on the next tick so the assertion runs in milliseconds instead of the
// real REVIEWER_CEILING_MS (15 minutes). Patching global setTimeout is safe here: `new
// Function` bodies resolve free variables against the global scope at CALL time (they do
// not close over this file's lexical scope), and clearTimeout still works normally on the
// real timer id the patched setTimeout returns.
// ---------------------------------------------------------------------------
console.log('── Case M: intake-review.mjs per-agent wall-clock ceiling')

const specBlock = (verdict = 'implementable') => reviewBlock({ verdict, findings: [] })
const explorerBlock = () =>
  reviewBlock({
    modulesAffected: [{ module: 'm' }],
    estimatedScope: { filesToCreate: 1, filesToModify: 2, modulesTouched: 1 },
  })

const runIntake = (behaviors, argsOverride = {}) => {
  const f = makeFakeAgent(behaviors)
  const args = {
    issue: '283',
    issueBody: 'Issue body text.',
    config: { reviewers: {} },
    ...argsOverride,
  }
  return makeRunner(INTAKE_REVIEW_MJS)(f.agent, parallel, pipeline, args, noop, noop, undefined).then((r) => ({
    result: r,
    calls: f.calls,
  }))
}

{
  const origSetTimeout = globalThis.setTimeout
  globalThis.setTimeout = (fn, _ms, ...rest) => origSetTimeout(fn, 0, ...rest)
  try {
    // spec-reviewer's dispatch hangs forever; codebase-explorer resolves normally in the
    // same fan-out. "Per-agent" means the hang must not block the other leg.
    const { result, calls } = await runIntake([() => new Promise(() => {}), explorerBlock()])
    const spec = result.specReview
    const explorer = result.codebaseExplorer
    ok('M1 the hung leg is declared dark via the ceiling, not a parsed result', spec.result === null)
    ok('M2 the hung leg carries the ceiling dark-marker shape', spec.retried === true && spec.failed === true && spec.ceiling === true)
    ok('M3 the ceiling error names the wall-clock ceiling, not the turn cap', /wall-clock ceiling/.test(String(spec.error)))
    ok(
      'M4 the OTHER leg is unaffected by its sibling hanging (per-agent, not fan-out-wide)',
      !!explorer.result && explorer.result.modulesAffected.length === 1,
    )
    ok(
      'M5 only one dispatch was ever attempted for the hung leg (proves darkness came from the timer, not a turn-cap retry loop)',
      calls.filter((c) => c.opts.agentType === 'review-toolkit:spec-reviewer').length === 1,
    )
  } finally {
    globalThis.setTimeout = origSetTimeout
  }
}
{
  // M6: sanity — a normal, microtask-fast fan-out is not falsely marked dark. Runs under
  // the REAL (unpatched) 15-minute ceiling; a normal resolution always wins that race.
  const { result } = await runIntake([specBlock('implementable'), explorerBlock()])
  ok(
    'M6 a normal fan-out completes via the real dispatch, unaffected by the ceiling',
    result.specReview.result.verdict === 'implementable' && !result.specReview.ceiling,
  )
}

// ---------------------------------------------------------------------------
// Case N — intake-review.mjs's referencedDocs content injection (#306).
//
// AC-1/AC-2/AC-3: `referencedDocs[].content` (documented in the args header, line 113)
// used to reach neither dispatch prompt — only `.path` did, via `docsNote`'s "already
// read — do not re-fetch" claim. That told sub-agents not to read files they were
// never given. This case pins that the content now rides in BOTH prompts, and that an
// empty `referencedDocs` (the pre-#306 default, every existing call site) is unaffected.
// ---------------------------------------------------------------------------
console.log('── Case N: intake-review.mjs referencedDocs content injection')

{
  const referencedDocs = [{ path: 'docs/adr/foo.md', content: 'ADR CONTENT XYZ 306' }]
  const { calls } = await runIntake([specBlock('implementable'), explorerBlock()], { referencedDocs })
  const specPrompt = calls.find((c) => c.opts.agentType === 'review-toolkit:spec-reviewer').prompt
  const explorerPrompt = calls.find((c) => c.opts.agentType === 'review-toolkit:codebase-explorer').prompt
  ok('N1 spec-reviewer prompt carries the referenced doc path', specPrompt.includes('docs/adr/foo.md'))
  ok('N2 spec-reviewer prompt carries the referenced doc CONTENT, not just the path', specPrompt.includes('ADR CONTENT XYZ 306'))
  ok('N3 codebase-explorer prompt also carries the referenced doc content', explorerPrompt.includes('ADR CONTENT XYZ 306'))
}

{
  // N4: the default (no referencedDocs passed) must carry no doc note/block at all —
  // proves the fix is additive and does not alter the pre-#306 no-docs prompt shape.
  const { calls } = await runIntake([specBlock('implementable'), explorerBlock()])
  const noNote = calls.every((c) => !/Referenced docs|REFERENCED DOC/.test(c.prompt))
  ok('N4 an empty referencedDocs emits no docs note or block on either prompt', noNote)
}

console.log(`\n[runtime-shim-selftest] ${PASS} passed, ${FAIL} failed`)
process.exit(FAIL)
