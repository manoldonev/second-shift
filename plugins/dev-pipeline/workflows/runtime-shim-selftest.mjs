#!/usr/bin/env node
// runtime-shim-selftest.mjs — execute WHOLE production Workflow `.mjs` bodies the way
// the Workflow runtime does, and assert their real dispatch ladders behaviorally.
//
// WHY THIS EXISTS (#214, epic #213)
// --------------------------------
// The suites this file replaces (the since-retired design-sync-selftest.mjs Cases A-F,
// null-reviewer-selftest.mjs Cases A-E/G) were MIRROR HARNESSES: they re-implemented production's
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
// Proves: the real dispatch ladders in code-review.mjs and intake-review.mjs behave as
// specified under success, contract-miss-then-retry, emitter fallback, turn-cap death,
// hard-throw, and budget-exhaustion — because THIS FILE EXECUTES THOSE FILES.
// Does not prove: anything about the Workflow runtime itself (concurrency caps, real
// model dispatch, journal semantics). Those remain out of reach of a model-free CI.
//
// The meta-strip is a balanced-brace scan, not a parser. That is sound here because
// Case R below lints every sibling workflow for meta-literal purity (no template
// interpolation, no computed values), so a brace inside a string in the meta block
// cannot ship. (The lint lived in design-sync-selftest.mjs Case I until #574 retired
// that suite with its engine; it moved here because this file is what its soundness
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
const ok = (m, cond) => (cond ? pass(m) : fail(m))

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
  // bug it fixes (#434).
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
// were dropped from the review subset and the default happened to match the fixture, so
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
  // detector: drop `tracker` from the review subset and H2b goes red while this stays
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
// Case T — the tier seam (#351). Dispatch tables now name an abstract tier, and a
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
console.log('── Case T: tier resolution through reviewers.tierMap (#351)')
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
  // T6 — the structured-emitter leg, which carried a hardcoded 'haiku' until #351.
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
  // against the pre-#351 body, whose literal ignored config entirely.
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

// ---------------------------------------------------------------------------
// Case Q — code-review.mjs bare-name normalization (#434).
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
// Relocated verbatim-in-substance from the retired design-sync-selftest.mjs Case I
// (#574): the Workflow runtime requires `export const meta = {...}` to be a PURE
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
// Adding a directory means one entry here plus the matching one in
// tools/check-bounded-exploration.sh, and neither can be silently forgotten.
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

console.log(`\n[runtime-shim-selftest] ${PASS} passed, ${FAIL} failed`)
process.exit(FAIL)
