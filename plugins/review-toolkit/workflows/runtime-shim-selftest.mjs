#!/usr/bin/env node
// runtime-shim-selftest.mjs — execute WHOLE production Workflow `.mjs` bodies the way
// the Workflow runtime does, and assert their real dispatch ladders behaviorally.
//
// WHY THIS EXISTS
// ---------------
// The suites this file replaces (the since-retired design-sync-selftest.mjs Cases A-F,
// null-reviewer-selftest.mjs Cases A-E/G) were MIRROR HARNESSES: they re-implemented production's
// dispatch logic inside the selftest and then tested the copy. That technique is
// structurally incapable of failing on a production edit, and it rotted exactly as
// you would predict — both suites still modelled the old StructuredOutput-retry
// transport long after production moved to the text-contract + emitter ladder, and
// stayed green the whole time. The same pathology, inside the tests built to prevent it.
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
// Proves: the real dispatch ladders in code-review.mjs and intake-review.mjs behave as
// specified under success, contract-miss-then-retry, emitter fallback, turn-cap death,
// hard-throw, and budget-exhaustion — because THIS FILE EXECUTES THOSE FILES.
// Does not prove: anything about the Workflow runtime itself (concurrency caps, real
// model dispatch, journal semantics). Those remain out of reach of a model-free CI.
//
// The meta-strip is a balanced-brace scan, not a parser. That is sound here because
// Case R below lints every sibling workflow for meta-literal purity (no template
// interpolation, no computed values), so a brace inside a string in the meta block
// cannot ship. (The lint lived in design-sync-selftest.mjs Case I until it retired
// with its engine; it moved here because this file is what its soundness
// underwrites.)
//
// The shim mechanics themselves (stripMeta / makeRunner / the injected fakes) live in
// `runtime-shim-lib.mjs` — a non-glob sibling, so CI never executes it directly — because
// production workflows are driven through the same wrapper.
// Two consumers, one definition; see that file's header.
//
// Exit code = number of failed checks (repo selftest convention).

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  makeBudget,
  makeFakeAgent,
  makeRunner,
  noop,
  parallel,
  pipeline,
  reviewBlock,
  stripMeta,
} from './runtime-shim-lib.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const CODE_REVIEW_MJS = join(HERE, 'code-review.mjs')
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
const ok = (m, cond, detail) => (cond ? pass(m) : fail(detail === undefined || detail === '' ? m : `${m}\n         ${detail}`))

// A well-formed REVIEW_RESULT block for code-review's FINDINGS_SCHEMA. The field names
// and the verdict enum are NOT interchangeable with the intake/gate schemas — production's
// validateShape rejects a near-miss, which is the point.
const findingsBlock = (verdict = 'approve') =>
  reviewBlock({
    verdict,
    findings: [{ severity: 'minor', title: 't', description: 'd', confidence: 70, file: 'f.ts', line: 1 }],
  })

const runCodeReview = (behaviors, argsOverride = {}) => {
  const f = makeFakeAgent(behaviors)
  // log lines are captured rather than dropped: Case Q asserts that a name substitution
  // announces itself, and a silent normalization is the same invisibility class as the
  // bug it fixes.
  const logs = []
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
  return makeRunner(CODE_REVIEW_MJS)(f.agent, parallel, pipeline, args, (m) => logs.push(String(m)), noop, undefined).then((r) => ({
    result: r,
    calls: f.calls,
    logs,
  }))
}

console.log('[runtime-shim-selftest]')

// ---------------------------------------------------------------------------
// Case A — the shim mechanically works on both production bodies.
// ---------------------------------------------------------------------------
console.log('── Case A: meta-strip + wrap executes production bodies')
for (const [name, path] of [
  ['code-review.mjs', CODE_REVIEW_MJS],
  ['intake-review.mjs', INTAKE_REVIEW_MJS],
  ['intake-fanout.mjs', join(HERE, 'intake-fanout.mjs')],
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
// Case B — code-review.mjs reviewer dispatch ladder (the real one).
// ---------------------------------------------------------------------------
console.log('── Case B: code-review.mjs text-contract ladder')

// The opening words of the retry nudge an empty reply earns.
const ESCALATED_MARK = 'YOUR PREVIOUS ATTEMPT AT THIS EXACT REVIEW DIED HAVING WRITTEN NOTHING'

{
  const { result, calls } = await runCodeReview([findingsBlock('approve')])
  eq('B1 success first try returns the parsed result', result.reviewers[0].result.verdict, 'approve')
  eq('B1 success first try dispatches exactly once', calls.length, 1)
  ok('B1 a first-try success carries no retried/failed flags', !result.reviewers[0].retried && !result.reviewers[0].failed)
  eq('B1 range is the THREE-DOT form', result.range, 'aaa...bbb')
  ok('B1 the reviewer is told to diff the three-dot range', calls[0].prompt.includes('diff aaa...bbb`'), calls[0].prompt)
  ok('B1 attempt 0 carries no escalated emit text', !calls[0].prompt.includes(ESCALATED_MARK))
  eq('B1 the return is exactly range, worktree, reviewers', Object.keys(result).sort(), ['range', 'reviewers', 'worktree'])
}

{
  let threw = ''
  try {
    await runCodeReview([findingsBlock('approve')], { reviewers: [] })
  } catch (e) {
    threw = String(e)
  }
  ok('B1 an empty reviewers[] throws before any dispatch', /non-empty array/.test(threw))
}

{
  // Contract miss (no sentinel) then success: the retry repeats the prompt unchanged. An agent
  // that wrote prose needs the format, not an order to stop exploring.
  const { result, calls } = await runCodeReview(['I have thoughts but no sentinel.', findingsBlock('approve')])
  eq('B2 retry after a text-contract miss recovers', result.reviewers[0].result.verdict, 'approve')
  eq('B2 retry dispatches exactly twice', calls.length, 2)
  ok('B2 the second dispatch is labelled a retry', String(calls[1].opts.label).includes('retry'))
  eq('B2 the retry after a sentinel-less reply repeats the prompt unchanged', calls[1].prompt, calls[0].prompt)
  ok('B2 and carries no escalated emit text', !calls[1].prompt.includes(ESCALATED_MARK) && !String(calls[1].opts.label).includes('escalated'))
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
  // rather than at the parser.
  const { result, calls } = await runCodeReview(['', ''])
  const r = result.reviewers[0]
  eq('B4 turn-cap death dispatches twice then gives up', calls.length, 2)
  eq('B4 turn-cap death yields a null result', r.result, null)
  ok('B4 turn-cap death carries the twice-dead markers', r.retried === true && r.failed === true)
  ok('B4 turn-cap death is reported as turn-budget, not a parser miss', String(r.error).startsWith('turn-budget:'))
  ok('B4 attempt 0 carries no escalated emit text', !calls[0].prompt.includes(ESCALATED_MARK))
  ok('B4 the retry after an empty reply carries the escalated emit text', calls[1].prompt.includes(ESCALATED_MARK), calls[1].prompt)
  ok('B4 the escalated text sits ahead of the result format', calls[1].prompt.indexOf(ESCALATED_MARK) < calls[1].prompt.lastIndexOf('REVIEW_RESULT'))
  eq('B4 the escalated retry is labelled as one', calls[1].opts.label, 'review-toolkit:complexity-reviewer (retry, escalated)')
}

{
  const { result, calls } = await runCodeReview(['', findingsBlock('approve')])
  eq('B4b an escalated retry that emits recovers the review', result.reviewers[0].result.verdict, 'approve')
  ok('B4b and it was the escalated prompt that recovered it', calls[1].prompt.includes(ESCALATED_MARK))
}

{
  // Text produced, but never a sentinel -> dark with the OTHER error string. The two
  // causes must stay distinguishable; conflating them cost real triage time.
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
// Case H — the config review-lead's dispatch passes reaches the dispatched agents.
//
// review-lead is the script's one caller, and its dispatch block names the config groups it
// passes. Both reads here fail silently when a group is missing — a model override falls
// back to the shipped table, the tracker defaults to github — so the case takes the group
// names from that block, picks exactly those groups out of a whole consumer config, and
// runs the production body on the result. A dispatch that passes no config, or the whole
// config under one name, picks nothing and H1/H2 go red.
//
// H2/H3 are a pair: H3 runs the same dispatch with no tracker group and must word the
// fetch the other way.
// ---------------------------------------------------------------------------
console.log('── Case H: the config review-lead passes reaches the dispatched agents')
const CONSUMER_CONFIG = {
  configVersion: 3,
  tracker: { type: 'jira', writes: false },
  commands: { app: { lint: 'lint', typecheck: null, test: 'test', format: null } },
  reviewers: { remove: ['db-reviewer'], modelOverrides: { 'complexity-reviewer': 'fable' } },
  paths: { plansDir: 'docs/plans' },
}
const dispatchedConfig = (() => {
  const skill = readFileSync(join(HERE, '..', 'skills', 'review-lead', 'SKILL.md'), 'utf8')
  const dispatch = skill.match(/Workflow\(\{ scriptPath: "[^"]*code-review\.mjs",[\s\S]*?\}\)\n/)
  const groups = dispatch && dispatch[0].match(/\bconfig: \{([^}]*)\}/)
  const names = groups ? groups[1].split(',').map((s) => s.trim()).filter(Boolean) : []
  return Object.fromEntries(names.filter((n) => n in CONSUMER_CONFIG).map((n) => [n, CONSUMER_CONFIG[n]]))
})()
{
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: dispatchedConfig,
  })
  eq('H1 a configured model override reaches the dispatched agent', calls[0]?.opts?.model, 'fable')
}
{
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:scope-completeness-reviewer'],
    issue: 'PROJ-12',
    config: dispatchedConfig,
  })
  const p = String(calls[0]?.prompt ?? '')
  ok('H2a the scope-completeness prompt was dispatched', /Verify scope completeness/.test(p), p)
  ok('H2b under jira the prompt names a JIRA ticket, not a GitHub issue', p.includes('JIRA ticket PROJ-12') && !/GitHub issue/.test(p), p)
  ok('H2c under jira the fetch goes to the Atlassian MCP, not gh', /Atlassian MCP for key `PROJ-12`/.test(p) && !/gh issue view/.test(p), p)
}
{
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:scope-completeness-reviewer'],
    issue: '77',
    config: { reviewers: {} },
  })
  const p = String(calls[0]?.prompt ?? '')
  ok('H3a the scope-completeness prompt was actually dispatched (anti-vacuity)', /Verify scope completeness/.test(p))
  ok('H3b no tracker group words it as a GitHub issue fetched with gh', /GitHub issue #77/.test(p) && /gh issue view 77/.test(p) && !/Atlassian MCP/.test(p), p)
  ok('H3c no spec arg names no decision record', !/Decision record/.test(p))
}
{
  // H4 — a decision record path reaches the scope reviewer as evidence, the path and nothing else.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:scope-completeness-reviewer'],
    issue: '77',
    spec: 'docs/plans/x-77-decisions.md',
    config: { reviewers: {} },
  })
  ok('H4 the spec path is forwarded to the scope reviewer', /Decision record: the committed decision record `docs\/plans\/x-77-decisions\.md`/.test(String(calls[0]?.prompt ?? '')))
}
{
  // H5 — the PR body's link verb decides the gate: a closing keyword scores the whole ticket, any other verb runs
  // partial mode, no verb says nothing (the reviewer's whole-ticket default), and anything but a bare verb throws.
  const scopePrompt = async (issueLink) => {
    const { calls } = await runCodeReview([findingsBlock()], {
      reviewers: ['review-toolkit:scope-completeness-reviewer'],
      issue: '77',
      ...(issueLink === undefined ? {} : { issueLink }),
    })
    return String(calls[0]?.prompt ?? '')
  }
  const closes = await scopePrompt('Closes')
  const fixed = await scopePrompt('fixed')
  const relates = await scopePrompt('Relates to')
  const none = await scopePrompt(undefined)
  ok('H5a a closing keyword scores the whole ticket', /links the ticket with `Closes`, a closing keyword — score the whole ticket/.test(closes) && !/partial mode/.test(closes))
  ok('H5b closing keywords match in any case and tense', /a closing keyword/.test(fixed) && !/partial mode/.test(fixed))
  ok('H5c a non-closing verb runs partial mode', /links the ticket with `Relates to`, not a closing keyword — partial mode/.test(relates))
  ok('H5d no issueLink adds no ticket-link line', /Verify scope completeness/.test(none) && !/Ticket link/.test(none))
  let threw = ''
  try {
    await scopePrompt('Relates to — only the API half is in scope')
  } catch (e) {
    threw = String(e)
  }
  ok('H5e an issueLink that is more than a bare verb throws', /issueLink must be a bare link verb/.test(threw), threw)
}

// ---------------------------------------------------------------------------
// Case M — intake-review.mjs's per-agent wall-clock ceiling.
//
// A leg that never emits must be declared dark by the CEILING'S TIMER, not by
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
// Case T — the tier seam. Dispatch tables now name an abstract tier, and a
// config-resolved map turns it into a vendor token. Every assertion here runs the REAL
// code-review.mjs body through the shim, because this is a resolution ORDER contract
// (override > table, then map) and the order is invisible to any static read.
//
// T1/T2 are the pair that makes this a killer, in the same shape as H2/H3: T1 alone
// stays green if the tierMap read is dropped entirely, since the shipped default and
// today's hardcoded token are the same string BY DESIGN — that is the backward-compat
// requirement. T2 retargets the tier so the two diverge, and only a live map read
// survives it. T5/T6 are the same pair for the site this ticket brings into the
// governed set: its model was a hardcoded literal no consumer could reach.
// ---------------------------------------------------------------------------
console.log('── Case T: tier resolution through reviewers.tierMap')
{
  // T1 — no tierMap: the tier resolves to exactly the model dispatched before the seam.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: {} },
  })
  eq('T1 default tierMap resolves code -> sonnet (unchanged for existing consumers)', calls[0]?.opts?.model, 'sonnet')
}
{
  // T2 — a consumer tierMap value REACHES the dispatch. Red if the map is never read.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { tierMap: { code: 'haiku' } } },
  })
  eq('T2 a custom tierMap value reaches the dispatched model', calls[0]?.opts?.model, 'haiku')
}
{
  // T3 — precedence: modelOverrides still beats the tierMap for that agent.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { tierMap: { code: 'haiku' }, modelOverrides: { 'complexity-reviewer': 'opus' } } },
  })
  eq('T3 modelOverrides beats the tierMap', calls[0]?.opts?.model, 'opus')
}
{
  // T4 — MERGE, not replace: retargeting `code` leaves `reasoning` at its shipped default.
  // A replace-semantics implementation resolves this to undefined or to the fallback.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:security-reviewer'],
    config: { reviewers: { tierMap: { code: 'haiku' } } },
  })
  eq('T4 a partial tierMap leaves untargeted tiers at the shipped default', calls[0]?.opts?.model, 'opus')
}
{
  // T5 — an override may itself NAME a tier (the closed union config-lint enforces),
  // and it resolves through the effective map rather than reaching dispatch raw.
  const { calls } = await runCodeReview([findingsBlock()], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { modelOverrides: { 'complexity-reviewer': 'reasoning' } } },
  })
  eq('T5 an override naming a tier resolves through the map', calls[0]?.opts?.model, 'opus')
}
{
  // T6 — the structured-emitter leg, which carried a hardcoded 'haiku' before the tier seam.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitterObject = { verdict: 'approve', findings: [] }
  const { calls } = await runCodeReview([bad, bad, emitterObject], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: {} },
  })
  eq('T6 the emit leg still defaults to haiku', calls[2]?.opts?.model, 'haiku')
}
{
  // T7 — and it now HONORS an override, which is the bypass this ticket closes. Red
  // against the pre-seam body, whose literal ignored config entirely.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitterObject = { verdict: 'approve', findings: [] }
  const { calls } = await runCodeReview([bad, bad, emitterObject], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { modelOverrides: { 'structured-emitter': 'opus' } } },
  })
  eq('T7 the emit leg honors a modelOverrides entry', calls[2]?.opts?.model, 'opus')
}
{
  // T8 — and follows a retargeted `emit` tier too, so a vendor without a haiku-class
  // model can move the sink without naming the agent.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitterObject = { verdict: 'approve', findings: [] }
  const { calls } = await runCodeReview([bad, bad, emitterObject], {
    reviewers: ['review-toolkit:complexity-reviewer'],
    config: { reviewers: { tierMap: { emit: 'sonnet' } } },
  })
  eq('T8 the emit leg follows a retargeted emit tier', calls[2]?.opts?.model, 'sonnet')
}

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
// Case N — intake-review.mjs's referencedDocs content injection.
//
// `referencedDocs[].content` (documented in the args header, line 113)
// used to reach neither dispatch prompt — only `.path` did, via `docsNote`'s "already
// read — do not re-fetch" claim. That told sub-agents not to read files they were
// never given. This case pins that the content now rides in BOTH prompts, and that an
// empty `referencedDocs` (the old default, every existing call site) is unaffected.
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
  // proves the fix is additive and does not alter the old no-docs prompt shape.
  const { calls } = await runIntake([specBlock('implementable'), explorerBlock()])
  const noNote = calls.every((c) => !/Referenced docs|REFERENCED DOC/.test(c.prompt))
  ok('N4 an empty referencedDocs emits no docs note or block on either prompt', noNote)
}

console.log('── Case P: intake-review.mjs pins the read surface')
{
  const { calls } = await runIntake([specBlock('implementable'), explorerBlock()], { readRoot: '/w/pinned-base' })
  eq('P1 both intake agents were dispatched', calls.map((c) => c.opts.agentType).sort(), ['review-toolkit:codebase-explorer', 'review-toolkit:spec-reviewer'])
  for (const c of calls) {
    ok(`P2 ${c.opts.agentType} is told first to read only inside the pinned checkout`, c.prompt.startsWith('PINNED READ SURFACE') && c.prompt.includes('inside /w/pinned-base'), c.prompt.slice(0, 200))
    ok(`P3 ${c.opts.agentType} is told not to read the main checkout`, /Do NOT read from the main repo checkout/.test(c.prompt))
  }
}
{
  const { calls } = await runIntake([specBlock('implementable'), explorerBlock()])
  ok('P4 without readRoot no prompt carries a pin', calls.length === 2 && calls.every((c) => !/PINNED READ SURFACE/.test(c.prompt)))
}

// ---------------------------------------------------------------------------
// Case TI — the tier seam on the OTHER ladder.
//
// Case T proves the contract against code-review.mjs. intake-review.mjs carries a
// byte-identical `tierMap` merge and `modelFor`, and that identity is exactly why it went
// uncovered: the code is the same code, so the ladder reads as already-tested. It is not —
// `modelFor` is a separate closure over a separate `config` destructure in a separate file,
// and nothing outside this block executes it.
//
// Measured at the round-1 head, in an isolated worktree, before these cases existed:
//   - drop the consumer tierMap read here (`{ ...DEFAULT_TIER_MAP }`)   -> suite 76/76 GREEN
//   - drop the resolution entirely (`modelFor` returns `declared`, so the
//     fan-out dispatches the literal string 'reasoning' as a model)     -> suite 76/76 GREEN
//   - the SAME first mutation on code-review.mjs                        -> suite 74/2 RED
// The third line is the control: the technique kills where coverage exists and does not kill
// where it does not, which is what makes the first two a gap rather than a mutation that
// silently no-op'd.
//
// TI1/TI2 are the T1/T2 pair for this ladder, and the pairing carries the same reason: TI1
// alone survives BOTH mutations above, because the shipped default and the pre-seam hardcoded
// token are the same string by design. Only a retarget separates a live map read from a dead
// one, so a default-only case here would be vacuous coverage.
//
// `args.agents` selects a single descriptor, which is what makes `calls[i]` positional here
// the way `args.reviewers` does in Case T.
// ---------------------------------------------------------------------------
console.log('── Case TI: tier resolution on the intake ladder')
{
  // TI1 — no tierMap: `reasoning` resolves to exactly what spec-reviewer dispatched before.
  const { calls } = await runIntake([specBlock()], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: {} },
  })
  eq('TI1 default tierMap resolves reasoning -> opus (unchanged for existing consumers)', calls[0]?.opts?.model, 'opus')
}
{
  // TI2 — a consumer tierMap value REACHES the intake dispatch. Red if the map is never read.
  const { calls } = await runIntake([specBlock()], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: { tierMap: { reasoning: 'haiku' } } },
  })
  eq('TI2 a custom tierMap value reaches the intake dispatch', calls[0]?.opts?.model, 'haiku')
}
{
  // TI3 — precedence: modelOverrides still beats the tierMap on this ladder too.
  const { calls } = await runIntake([specBlock()], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: { tierMap: { reasoning: 'haiku' }, modelOverrides: { 'spec-reviewer': 'sonnet' } } },
  })
  eq('TI3 modelOverrides beats the tierMap on the intake ladder', calls[0]?.opts?.model, 'sonnet')
}
{
  // TI4 — MERGE, not replace: retargeting `reasoning` leaves `code` at its shipped default.
  // A replace-semantics implementation resolves the explorer to undefined or to the fallback.
  const { calls } = await runIntake([explorerBlock()], {
    agents: ['review-toolkit:codebase-explorer'],
    config: { reviewers: { tierMap: { reasoning: 'haiku' } } },
  })
  eq('TI4 a partial tierMap leaves the intake explorer at the shipped default', calls[0]?.opts?.model, 'sonnet')
}
{
  // TI5 — an override may itself NAME a tier, and resolves through the effective map rather
  // than reaching dispatch raw as the literal string 'emit'.
  const { calls } = await runIntake([explorerBlock()], {
    agents: ['review-toolkit:codebase-explorer'],
    config: { reviewers: { modelOverrides: { 'codebase-explorer': 'emit' } } },
  })
  eq('TI5 an intake override naming a tier resolves through the map', calls[0]?.opts?.model, 'haiku')
}
{
  // TI6 — intake's emit leg, which carried the same hardcoded 'haiku' before the tier seam. Two
  // sentinel-bearing but unparseable attempts drive the ladder into emitStructured.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitted = { verdict: 'implementable', findings: [] }
  const { calls } = await runIntake([bad, bad, emitted], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: {} },
  })
  eq('TI6 the intake emit leg still defaults to haiku', calls[2]?.opts?.model, 'haiku')
}
{
  // TI7 — and honors an override, the bypass this ticket closes on BOTH engines.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitted = { verdict: 'implementable', findings: [] }
  const { calls } = await runIntake([bad, bad, emitted], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: { modelOverrides: { 'structured-emitter': 'opus' } } },
  })
  eq('TI7 the intake emit leg honors a modelOverrides entry', calls[2]?.opts?.model, 'opus')
}
{
  // TI8 — and follows a retargeted `emit` tier.
  const bad = 'REVIEW_RESULT\n```json\n{not valid json,,,}\n```'
  const emitted = { verdict: 'implementable', findings: [] }
  const { calls } = await runIntake([bad, bad, emitted], {
    agents: ['review-toolkit:spec-reviewer'],
    config: { reviewers: { tierMap: { emit: 'sonnet' } } },
  })
  eq('TI8 the intake emit leg follows a retargeted emit tier', calls[2]?.opts?.model, 'sonnet')
}

// ---------------------------------------------------------------------------
// Case Q — code-review.mjs bare-name normalization.
//
// The bug: review-lead's panel named plugin reviewers BARE, code-review.mjs passed
// agentType to agent() verbatim, and every dispatch died with `agent type not found`.
// Those deaths return in the died-after-retry shape, so synthesis rendered a fully dark
// panel — a coverage-gap note and a "Ready to merge?" verdict over ZERO reviewers. The
// normalization is the defensive half (the lint is the preventive half): a stale caller
// must degrade to WORKING, not to a silent zero-coverage review.
//
// Three properties, and the third is the one that is easy to get wrong: the DISPATCHED
// name is qualified, the MODEL follows the qualified key, and the RETURNED agentType is
// the caller's own spelling — because review-lead Step 4b enumerates budget-skipped
// darkness by comparing the returned set against the set it passed as args.reviewers.
// ---------------------------------------------------------------------------
console.log('── Case Q: code-review.mjs bare-name normalization')
{
  const { result, calls, logs } = await runCodeReview([findingsBlock('approve')], {
    reviewers: ['security-reviewer'],
  })
  eq('Q1 a bare plugin name is DISPATCHED qualified', calls[0].opts.agentType, 'review-toolkit:security-reviewer')
  eq('Q1 the qualified key also restores the declared model tier', calls[0].opts.model, 'opus')
  eq('Q1 the RETURNED agentType is the caller-passed spelling (Step 4b compares against it)', result.reviewers[0].agentType, 'security-reviewer')
  ok('Q1 the substitution announces itself', logs.some((l) => /normalized/.test(l) && /review-toolkit:security-reviewer/.test(l)))
  ok('Q1 the review still lands (the whole point: degrade to working)', result.reviewers[0].result.verdict === 'approve')
}
{
  // An already-qualified name is untouched and silent — normalization must not narrate
  // on the path every healthy caller takes.
  const { result, calls, logs } = await runCodeReview([findingsBlock('approve')], {
    reviewers: ['review-toolkit:performance-reviewer'],
  })
  eq('Q2 an already-qualified name dispatches unchanged', calls[0].opts.agentType, 'review-toolkit:performance-reviewer')
  eq('Q2 and returns unchanged', result.reviewers[0].agentType, 'review-toolkit:performance-reviewer')
  ok('Q2 no substitution is logged when none happened', !logs.some((l) => /normalized/.test(l)))
}
{
  // A repo-local `reviewers.add` name matches no table key, so it stays bare end to end
  // and takes the 'sonnet' default — exactly today's behavior. If normalization ever
  // guessed a prefix here it would break every consumer's domain reviewer.
  const { result, calls, logs } = await runCodeReview([findingsBlock('approve')], {
    reviewers: ['orders-reviewer'],
  })
  eq('Q3 a repo-local bare name dispatches bare', calls[0].opts.agentType, 'orders-reviewer')
  eq('Q3 and keeps the sonnet default', calls[0].opts.model, 'sonnet')
  eq('Q3 and returns bare', result.reviewers[0].agentType, 'orders-reviewer')
  ok('Q3 nothing is logged for a name that matched no table key', !logs.some((l) => /normalized/.test(l)))
}
{
  // The dark path returns the caller's spelling too. This is the assertion that would
  // have caught a "fix" that normalized the returned name as well: the review still goes
  // dark here, and Step 4b must still be able to match it against args.reviewers.
  const { result, calls } = await runCodeReview(['', ''], { reviewers: ['security-reviewer'] })
  eq('Q4 a normalized dispatch that dies twice is dispatched qualified', calls[0].opts.agentType, 'review-toolkit:security-reviewer')
  eq('Q4 but its dark marker still names the caller-passed spelling', result.reviewers[0].agentType, 'security-reviewer')
  ok('Q4 and is still a well-formed twice-dead marker', result.reviewers[0].result === null && result.reviewers[0].failed === true)
}

// ---------------------------------------------------------------------------
// Case R — Workflow meta literal-purity across every sibling workflows/*.mjs.
// Relocated verbatim-in-substance from the retired design-sync-selftest.mjs Case I:
// the Workflow runtime requires `export const meta = {...}` to be a PURE
// LITERAL — a BinaryExpression (string concatenation), template literal, call,
// spread, or identifier value makes the runtime reject the whole script at dispatch
// ("non-literal node type in meta"). v2.0.0 shipped a workflow with a concatenated
// meta.description and the defect surfaced only at the first real dispatch (a canary
// run). This case is the offline guard, and it is load-bearing for THIS file too:
// stripMeta's balanced-brace scan is sound only while meta blocks are pure literals,
// so it lives beside the consumer of the invariant.
//
// The scanned set is a LIST of workflow directories. A workflow outside it is both
// unlinted AND unsafe to drive through the shim, so the discovery assertion below
// walks the plugin root's siblings and fails on any workflows/ dir not in the list.
// Adding a directory means one entry here, and it cannot be silently forgotten.
// ---------------------------------------------------------------------------
console.log('── Case R: workflow meta literal-purity (relocated from design-sync-selftest Case I)')
{
  const { readdirSync, existsSync, statSync } = await import('node:fs')
  const PLUGIN_SIBLINGS = join(HERE, '..', '..')
  const WORKFLOW_DIRS = [HERE].filter((d) => existsSync(d))
  const discovered = readdirSync(PLUGIN_SIBLINGS)
    .map((s) => join(PLUGIN_SIBLINGS, s, 'workflows'))
    .filter((d) => existsSync(d) && statSync(d).isDirectory())
  // Extracted rather than inlined so its FAIL branch can be driven with a synthetic
  // tree: a discovery check that only ever sees the real, currently-clean layout
  // asserts nothing about what it does when a directory IS missing from the list.
  const unlistedDirs = (found, listed) => found.filter((d) => !listed.includes(d))
  const unlisted = unlistedDirs(discovered, WORKFLOW_DIRS)
  ok(
    `R-discovery every workflows/ dir under the plugin root is in the scanned set (${discovered.length})`,
    unlisted.length === 0,
  )
  const planted = join(PLUGIN_SIBLINGS, 'planted-skill', 'workflows')
  eq(
    'R-discovery-nv a workflows/ dir outside the scanned set is reported, not silently skipped',
    unlistedDirs([...discovered, planted], WORKFLOW_DIRS),
    [planted],
  )
  const metaFiles = WORKFLOW_DIRS.flatMap((dir) =>
    readdirSync(dir)
      .filter((f) => f.endsWith('.mjs'))
      .sort()
      .map((f) => [dir === HERE ? f : `${dir}/${f}`, readFileSync(join(dir, f), 'utf8')]),
  )
    // Line-start anchor: `export const meta` may legitimately appear INSIDE a string
    // elsewhere — only a top-level declaration counts.
    .filter(([, src]) => /^export const meta = \{/m.test(src))
  ok('R0 workflow scripts with `export const meta` found (glob not broken)', metaFiles.length > 0)
  for (const [file, src] of metaFiles) {
    // Meta block = from `export const meta = {` at line start to the first `}` at line
    // start (hand-style formatting invariant across these files).
    const m = src.match(/^export const meta = \{([\s\S]*?)\n\}/m)
    if (!m) {
      fail(`R meta-purity: ${file} — could not extract the meta block (formatting drifted?)`)
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
      ? pass(`R meta-purity: ${file} meta is a pure literal`)
      : fail(
          `R meta-purity: ${file} meta contains ${violations.map(([, why]) => why).join(', ')} — the Workflow runtime will reject the script at dispatch`,
        )
  }
}

// ---------------------------------------------------------------------------
// Case FO — intake-fanout.mjs: the production body /intake's Explore stage dispatches. A lens
// writer, then five lenses, every dispatch and retry on the `reasoning` token. Nothing checks a
// claim inside the workflow, so every claim a lens made reaches the pool, unverified, for the
// interviewer to check from its pointer. One retry, on `reasoning`; a lens dead after it makes
// the run partial; the ceiling, a failed lens writer and an exhausted budget each return the
// failed form; modelOverrides and tierMap still retarget the dispatches.
// ---------------------------------------------------------------------------
console.log('── Case FO: intake-fanout.mjs every claim unverified, the reasoning tier, one retry, failure forms')
{
const runFanout = makeRunner(join(HERE, 'intake-fanout.mjs'))
const ARGS = { issue: 42, issueBody: 'Add a status route.' }
const WRITER_OUT = reviewBlock({
  angles: [1, 2, 3, 4].map((i) => ({ key: `angle-${i}`, job: `ANGLE ${i}. Read the caller.` })),
  premortem: 'PRE-MORTEM. It shipped and failed.',
})
const claim = (key, n) => ({ claim: `${key} claim ${n}`, pointer: `src/a.ts:${n}`, observed: `line ${n}`, measured_under: 'node 20', kind: 'probed-fact' })
const lensOut = (key, n = 2) => reviewBlock({ claims: Array.from({ length: n }, (_, i) => claim(key, i + 1)) })
const keyOf = (label) => label.replace(/^lens:| \(.*\)$/g, '')
const RESULT_KEYS = 'events,issue,lenses,pool,reason,status'

// A fake agent routed by role; `handlers` override per role. Records every dispatch.
const fakeAgent = (handlers = {}) => {
  const calls = []
  const agent = async (prompt, opts) => {
    calls.push({ prompt, opts })
    const role = String(opts.agentType).split(':').pop()
    const h = handlers[role]
    if (h) return h(prompt, opts, calls)
    if (role === 'intake-lens-writer') return WRITER_OUT
    if (role === 'intake-lens') return lensOut(keyOf(opts.label))
    throw new Error(`unexpected agent ${opts.agentType}`)
  }
  return { agent, calls }
}
const go = (agent, args = ARGS, budget = undefined) => runFanout(agent, parallel, pipeline, args, noop, noop, budget)
const byRole = (calls, re) => calls.filter((c) => re.test(c.opts.agentType))
const triesOf = (calls, key) => byRole(calls, /intake-lens$/).filter((c) => keyOf(c.opts.label) === key).map((c) => c.opts.model)

// --- A: every claim of every lens reaches the pool, unverified, evidence only ---
{
  const { agent, calls } = fakeAgent({ 'intake-lens': (prompt, opts) => lensOut(keyOf(opts.label), keyOf(opts.label) === 'premortem' ? 8 : 2) })
  const r = await go(agent)
  ok('FO A status complete with five lenses', r.status === 'complete' && r.lenses.length === 5, JSON.stringify(r.lenses))
  const roles = [...new Set(calls.map((c) => String(c.opts.agentType).split(':').pop()))].sort().join(',')
  ok('FO A only the lens writer and the lenses are dispatched', roles === 'intake-lens,intake-lens-writer', roles)
  ok('FO A every claim of every lens is in the pool, the pre-mortem cut at 6 (4 x 2 + 6)', r.pool.length === 14, `${r.pool.length} items`)
  ok('FO A each angle keeps both of its claims', [1, 2, 3, 4].every((i) => r.pool.filter((p) => p.angle === `angle-${i}`).length === 2))
  ok("FO A every pool item is status 'unverified'", r.pool.length > 0 && r.pool.every((p) => p.status === 'unverified'), JSON.stringify(r.pool.map((p) => p.status)))
  const keys = [...new Set(r.pool.map((p) => Object.keys(p).sort().join(',')))]
  ok('FO A every pool item carries exactly the six evidence fields and its status', keys.length === 1 && keys[0] === 'angle,claim,kind,measured_under,observed,pointer,status', keys.join(' | '))
  const p = r.pool[0] || {}
  ok('FO A a pool item carries the claim as the lens wrote it',
    p.claim === 'angle-1 claim 1' && p.pointer === 'src/a.ts:1' && p.observed === 'line 1' && p.angle === 'angle-1' && p.kind === 'probed-fact' && p.measured_under === 'node 20',
    JSON.stringify(p))
}

// --- B: the reasoning tier for every dispatch, and the result shape ---
{
  const { agent, calls } = fakeAgent()
  const r = await go(agent)
  const models = calls.map((c) => `${c.opts.label}=${c.opts.model}`)
  ok('FO B with no config the lens writer and every lens run on opus', calls.length === 6 && calls.every((c) => c.opts.model === 'opus'), models.join(','))
  ok('FO B the result has no refuter field', Object.keys(r).sort().join(',') === RESULT_KEYS, Object.keys(r).sort().join(','))
  const lensKeys = [...new Set(r.lenses.map((l) => Object.keys(l).sort().join(',')))]
  ok('FO B each lens entry is key, model, status and claims only', lensKeys.length === 1 && lensKeys[0] === 'claims,key,model,status', lensKeys.join(' | '))
  eq('FO B each lens entry records its model and its claim count', r.lenses.map((l) => [l.key, l.model, l.status, l.claims]), [
    ['angle-1', 'opus', 'ok', 2],
    ['angle-2', 'opus', 'ok', 2],
    ['angle-3', 'opus', 'ok', 2],
    ['angle-4', 'opus', 'ok', 2],
    ['premortem', 'opus', 'ok', 2],
  ])
}

// --- B2: what every agent is grounded in ---
{
  const { agent, calls } = fakeAgent()
  await go(agent, { ...ARGS, readRoot: '/w/be', checkouts: [{ path: '/w/fe', role: 'The admin frontend that calls this backend' }], protocol: ['/s/plan-interview/SKILL.md', '/s/interviewing-baseline/SKILL.md'] })
  ok('FO B2 every agent is handed the consumer checkout', calls.every((c) => c.prompt.includes('The admin frontend that calls this backend is the checkout /w/fe')))
  ok('FO B2 every agent is handed the protocol text', calls.every((c) => c.prompt.includes('/s/plan-interview/SKILL.md and /s/interviewing-baseline/SKILL.md')))
  const w = byRole(calls, /intake-lens-writer/)[0]
  ok("FO B2 the lens writer's build rules check claims at the interviewer and mix no models", w && /Check, don't trust\. The interviewer checks each claim from its pointer/.test(w.prompt) && !/Mixing models|refut/i.test(w.prompt))
  const lens = byRole(calls, /intake-lens$/)
  ok('FO B2 every lens is asked for a pointer the interviewer can open or run', lens.length === 5 && lens.every((c) => c.prompt.includes('Every claim needs a pointer the interviewer can open or run')) && !lens.some((c) => /refuter/i.test(c.prompt)))
}

// --- B3: the knowledge source reaches the lens writer only ---
{
  const KS = 'Provider: <plugin>:<provider-agent>\n\n    Audit rows are retained.\n\n    Sources:\n    - <kb-page>'
  const { agent, calls } = fakeAgent()
  const r = await go(agent, { ...ARGS, knowledgeSource: KS })
  const w = byRole(calls, /intake-lens-writer/)
  ok('FO B3 the lens writer is handed the knowledge source answer whole', w.length === 1 && w[0].prompt.includes(KS))
  const leaked = calls.filter((c) => !/intake-lens-writer/.test(c.opts.agentType) && /Audit rows are retained|kb-page|knowledge source/i.test(c.prompt))
  ok('FO B3 no lens sees it', r.status === 'complete' && calls.length > 1 && leaked.length === 0, leaked.map((c) => c.opts.label).join(','))
  const { agent: plain, calls: plainCalls } = fakeAgent()
  await go(plain)
  ok('FO B3 without one, the writer prompt carries no knowledge-source block', !/knowledge source/i.test(byRole(plainCalls, /intake-lens-writer/)[0].prompt))
}

// --- C: a lens that dies once is retried once, on opus ---
{
  let died = false
  const { agent, calls } = fakeAgent({
    'intake-lens': (prompt, opts) => {
      if (keyOf(opts.label) === 'angle-1' && !died) {
        died = true
        throw new Error('safeguard block')
      }
      return lensOut(keyOf(opts.label))
    },
  })
  const r = await go(agent)
  const a1 = r.lenses.find((l) => l.key === 'angle-1')
  ok('FO C the blocked lens recovered on its retry, on opus', r.status === 'complete' && a1 && a1.status === 'ok' && a1.model === 'opus', JSON.stringify(a1))
  ok('FO C its first attempt and its retry both ran on opus', triesOf(calls, 'angle-1').join(',') === 'opus,opus', triesOf(calls, 'angle-1').join(','))
  ok('FO C its claims reach the pool', r.pool.filter((p) => p.angle === 'angle-1').length === 2)
}

// --- C2: an override that names a model the account cannot reach retries on reasoning ---
{
  const { agent, calls } = fakeAgent({
    'intake-lens': (prompt, opts) => {
      if (opts.model === 'fable') throw new Error('model not available')
      return lensOut(keyOf(opts.label))
    },
  })
  const r = await go(agent, { ...ARGS, config: { reviewers: { modelOverrides: { 'intake-lens': 'fable' } } } })
  ok('FO C2 every lens tried the override first, then opus, and no third time', ['angle-1', 'angle-2', 'angle-3', 'angle-4', 'premortem'].every((k) => triesOf(calls, k).join(',') === 'fable,opus'), byRole(calls, /intake-lens$/).map((c) => c.opts.label + '@' + c.opts.model).join(','))
  ok('FO C2 the run completes, each lens recorded on opus', r.status === 'complete' && r.lenses.every((l) => l.status === 'ok' && l.model === 'opus'), JSON.stringify(r.lenses))
  ok('FO C2 no claim is lost (pool 10)', r.pool.length === 10, `${r.pool.length} items`)
}

// --- C3: modelOverrides and tierMap still retarget the dispatches ---
{
  const { agent, calls } = fakeAgent()
  await go(agent, { ...ARGS, config: { reviewers: { modelOverrides: { 'intake-lens': 'code' } } } })
  const lens = byRole(calls, /intake-lens$/)
  ok('FO C3 an intake-lens override (a tier) retargets every lens', lens.length === 5 && lens.every((c) => c.opts.model === 'sonnet'), lens.map((c) => c.opts.model).join(','))
  ok('FO C3 and leaves the lens writer on opus', byRole(calls, /intake-lens-writer/).every((c) => c.opts.model === 'opus'))
  const { agent: tm, calls: tmCalls } = fakeAgent()
  await go(tm, { ...ARGS, config: { reviewers: { tierMap: { reasoning: 'sonnet' } } } })
  ok('FO C3 a tierMap entry for reasoning retargets the writer and every lens', tmCalls.length === 6 && tmCalls.every((c) => c.opts.model === 'sonnet'), tmCalls.map((c) => c.opts.model).join(','))
  let died = false
  const { agent: tr, calls: trCalls } = fakeAgent({
    'intake-lens-writer': () => {
      if (!died) {
        died = true
        throw new Error('transient')
      }
      return WRITER_OUT
    },
  })
  await go(tr, { ...ARGS, config: { reviewers: { tierMap: { reasoning: 'sonnet' } } } })
  const wt = byRole(trCalls, /intake-lens-writer/).map((c) => c.opts.model).join(',')
  ok('FO C3 and the retry follows the retargeted reasoning tier', wt === 'sonnet,sonnet', wt)
}

// --- D: a lens dies twice ---
{
  const { agent, calls } = fakeAgent({
    'intake-lens': (prompt, opts) => {
      if (keyOf(opts.label) === 'angle-1') throw new Error('safeguard block')
      return lensOut(keyOf(opts.label))
    },
  })
  const r = await go(agent)
  ok('FO D a dead lens makes the run partial, not failed', r.status === 'partial' && /1 of 5/.test(r.reason), `${r.status} ${r.reason}`)
  const a1 = r.lenses.find((l) => l.key === 'angle-1')
  ok("FO D the dead lens is listed as status 'failed' with no claims", a1 && a1.status === 'failed' && a1.claims === 0, JSON.stringify(a1))
  ok('FO D the dead lens was tried twice, both on opus, and no third time', triesOf(calls, 'angle-1').join(',') === 'opus,opus', triesOf(calls, 'angle-1').join(','))
  ok('FO D the other lenses still fill the pool (4 x 2)', r.pool.length === 8, `${r.pool.length} items`)
}

// --- D2: a lens that returns no parseable block twice fails too ---
{
  const { agent } = fakeAgent({
    'intake-lens': (prompt, opts) => (keyOf(opts.label) === 'premortem' ? 'I looked around but wrote no block.' : lensOut(keyOf(opts.label))),
  })
  const r = await go(agent)
  ok('FO D2 an unparseable lens fails after its retry, and the run is partial', r.status === 'partial' && r.lenses.find((l) => l.key === 'premortem').status === 'failed', JSON.stringify(r.lenses))
}

// --- E: the lens writer dies once and recovers on its retry ---
{
  let died = false
  const { agent, calls } = fakeAgent({
    'intake-lens-writer': () => {
      if (!died) {
        died = true
        throw new Error('transient')
      }
      return WRITER_OUT
    },
  })
  const r = await go(agent)
  const wt = byRole(calls, /intake-lens-writer/).map((c) => c.opts.model).join(',')
  ok('FO E the writer recovers on one retry, on opus', r.status === 'complete' && wt === 'opus,opus', `${r.status} ${wt}`)
}

// --- E2: every lens fails ---
{
  const { agent } = fakeAgent({ 'intake-lens': () => { throw new Error('safeguard block') } })
  const r = await go(agent)
  ok('FO E2 every lens failing fails the run, lenses still listed', r.status === 'failed' && /every lens failed/.test(r.reason) && r.lenses.length === 5 && r.pool.length === 0, JSON.stringify(r))
}

// --- F: the whole-run ceiling ---
{
  const { agent } = fakeAgent({ 'intake-lens-writer': () => new Promise(() => {}) })
  const r = await go(agent, { ...ARGS, ceilingMs: 30 })
  ok('FO F the ceiling returns the failed form with an empty pool', r.status === 'failed' && /exceeded/.test(r.reason) && r.pool.length === 0, JSON.stringify(r))
}

// --- G: the lens writer fails ---
{
  const { agent } = fakeAgent({ 'intake-lens-writer': () => 'no block' })
  const r = await go(agent)
  ok('FO G a writer with no usable jobs fails the run', r.status === 'failed' && /lens writer/.test(r.reason), r.reason)
}

// --- H: budget exhausted ---
{
  const { agent, calls } = fakeAgent()
  const r = await go(agent, ARGS, makeBudget(1000, 0))
  ok('FO H an exhausted budget fails before any dispatch', r.status === 'failed' && calls.length === 0, `${calls.length} dispatches`)
}

// --- I: the failed form has the result's shape, with no refuter field ---
{
  const { agent } = fakeAgent({ 'intake-lens-writer': () => 'no block' })
  const r = await go(agent)
  ok('FO I the failed form carries the same fields and no refuter', Object.keys(r).sort().join(',') === RESULT_KEYS, Object.keys(r).sort().join(','))
}

}

console.log(`\n[runtime-shim-selftest] ${PASS} passed, ${FAIL} failed`)
process.exit(FAIL)
