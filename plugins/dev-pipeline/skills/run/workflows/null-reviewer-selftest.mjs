#!/usr/bin/env node
// null-reviewer-selftest.mjs — verifies the Stage 8 dark-reviewer contract (#168).
//
// Style note: like its sibling Workflow scripts (code-review.mjs, intake-review.mjs),
// this file is NOT covered by the repo `format` script (which globs only
// .{ts,tsx,js,json,md}), so it follows their hand-style: no semicolons, single quotes.
//
// WHY THIS IS SELF-CONTAINED (and does not import code-review.mjs):
//   code-review.mjs is a Workflow script, NOT a node-importable ESM module. It uses
//   a top-level `return` (the Workflow runtime wraps the body in an async function)
//   and references runtime-injected globals (agent, parallel, args, log, phase,
//   budget) with no imports. `node --check` rejects its top-level return, and
//   importing it under node would throw on the undefined globals. So this selftest
//   carries a REFERENCE harness that mirrors dispatchReviewer()'s retry semantics,
//   PLUS a structural drift-guard (Case F) that reads code-review.mjs as text and
//   asserts the load-bearing tokens are still present — so the production script
//   cannot silently lose the behavior this selftest validates.
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

// ---------------------------------------------------------------------------
// Reference harness — a faithful copy of code-review.mjs's dispatchReviewer()
// retry semantics, with the Workflow globals (agent, log) injected as params so
// the control flow is exercisable under plain node. The prompt-building is elided
// (irrelevant to the retry decision); only the try / retry / classify flow is
// reproduced. The drift-guard (Case F) keeps this in sync with production.
// ---------------------------------------------------------------------------
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

function makeDispatchReviewer({ agent, log }) {
  return async function dispatchReviewer(agentType) {
    try {
      const result = await agent(agentType, { attempt: 1 })
      return { agentType, result }
    } catch (err) {
      if (!isNoStructuredOutputError(err)) {
        return { agentType, result: null, error: String(err) }
      }
      log(`${agentType}: died without StructuredOutput — retrying once`)
      try {
        const result = await agent(agentType, { attempt: 2 })
        return { agentType, result }
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

// A fake agent() driven by a queue of behaviors, one per call.
// Behavior: { ok: <value> } resolves; { throw: <Error|string> } rejects.
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

// Reference copy of code-review.mjs's withCeiling() (#219). Races a reviewer's dispatch
// promise against a wall-clock ceiling; on timeout resolves (never rejects) to the
// died-after-retry dark-marker shape (+ ceiling:true) so the caller's existing dark
// handling is unchanged. ceilingMs is a param here so Case G can use a tiny ceiling.
function makeWithCeiling(ceilingMs) {
  return function withCeiling(agentType, dispatchPromise) {
    let timer
    const ceiling = new Promise((resolve) => {
      timer = setTimeout(
        () =>
          resolve({
            agentType,
            result: null,
            error: `dispatch exceeded the per-reviewer wall-clock ceiling (${ceilingMs}ms) — declared dark`,
            retried: true,
            failed: true,
            ceiling: true,
          }),
        ceilingMs,
      )
    })
    return Promise.race([dispatchPromise, ceiling]).then((r) => {
      clearTimeout(timer)
      return r
    })
  }
}

const noopLog = () => {}
const soError = new Error('subagent completed without calling StructuredOutput (after 2 in-conversation nudges)')

async function main() {
  // ---- Case A: success first try -> { agentType, result }, agent called once ----
  {
    const agent = fakeAgent([{ ok: { verdict: 'approve', findings: [] } }])
    const dispatch = makeDispatchReviewer({ agent, log: noopLog })
    const out = await dispatch('maintainability-reviewer')
    eq('A1 success-first-try return shape', out, {
      agentType: 'maintainability-reviewer',
      result: { verdict: 'approve', findings: [] },
    })
    eq('A2 success-first-try calls agent exactly once', agent.callCount(), 1)
    eq('A3 success has no retried/failed flags', [out.retried, out.failed], [undefined, undefined])
  }

  // ---- Case B: StructuredOutput death then success -> retry recovers ----
  {
    const agent = fakeAgent([{ throw: soError }, { ok: { verdict: 'approve-with-nits', findings: [] } }])
    const dispatch = makeDispatchReviewer({ agent, log: noopLog })
    const out = await dispatch('test-coverage-reviewer')
    eq('B1 retry-recovered return shape', out, {
      agentType: 'test-coverage-reviewer',
      result: { verdict: 'approve-with-nits', findings: [] },
    })
    eq('B2 retry-recovered calls agent twice', agent.callCount(), 2)
    eq('B3 retry-recovered carries NO failed flag (indistinguishable from first-try success)', out.failed, undefined)
  }

  // ---- Case C: StructuredOutput death twice -> { result: null, retried, failed } ----
  {
    const agent = fakeAgent([{ throw: soError }, { throw: soError }])
    const dispatch = makeDispatchReviewer({ agent, log: noopLog })
    const out = await dispatch('maintainability-reviewer')
    eq('C1 twice-dead result is null', out.result, null)
    eq('C2 twice-dead retried+failed flags set', [out.retried, out.failed], [true, true])
    eq('C3 twice-dead calls agent twice (one retry, not a loop)', agent.callCount(), 2)
    matches('C4 twice-dead error preserves both attempts', out.error, /first attempt/)
  }

  // ---- Case D: genuine (non-StructuredOutput) error -> forwarded, NOT retried ----
  {
    const agent = fakeAgent([{ throw: new Error('permission denied: tool Bash') }])
    const dispatch = makeDispatchReviewer({ agent, log: noopLog })
    const out = await dispatch('security-reviewer')
    eq('D1 non-SO error result is null', out.result, null)
    eq('D2 non-SO error is NOT retried (agent called once)', agent.callCount(), 1)
    eq('D3 non-SO error carries no retried/failed flags', [out.retried, out.failed], [undefined, undefined])
  }

  // ---- Case E: isNoStructuredOutputError predicate semantics ----
  {
    eq('E1 matches the runtime death message', isNoStructuredOutputError(soError), true)
    eq('E2 matches a bare string containing the token', isNoStructuredOutputError('...StructuredOutput...'), true)
    eq('E3 rejects an unrelated error', isNoStructuredOutputError(new Error('permission denied')), false)
    eq('E4 rejects empty/undefined', isNoStructuredOutputError(undefined), false)
  }

  // ---- Case G: wall-clock ceiling (#219) ----
  // A dispatch that resolves before the ceiling passes through UNCHANGED; a dispatch
  // that never resolves (a wedged reviewer) yields the died-after-retry marker shape
  // (+ ceiling:true) at the ceiling, so the caller's dark handling is unchanged.
  {
    const withCeiling = makeWithCeiling(20) // 20ms — fast + deterministic
    // G-fast: a dispatch that resolves quickly wins the race, marker NOT applied.
    const fast = Promise.resolve({ agentType: 'security-reviewer', result: { verdict: 'approve', findings: [] } })
    const outFast = await withCeiling('security-reviewer', fast)
    eq('G1 sub-ceiling dispatch passes through unchanged', outFast, {
      agentType: 'security-reviewer',
      result: { verdict: 'approve', findings: [] },
    })
    eq('G2 sub-ceiling dispatch carries no ceiling/failed flags', [outFast.ceiling, outFast.failed], [undefined, undefined])
    // G-wedge: a never-resolving dispatch hits the ceiling -> died-after-retry marker.
    const wedged = new Promise(() => {}) // never settles (the wedged-reviewer case)
    const outWedged = await withCeiling('maintainability-reviewer', wedged)
    eq('G3 ceiling-timed-out result is null', outWedged.result, null)
    eq('G4 ceiling-timed-out reuses died-after-retry shape', [outWedged.retried, outWedged.failed], [true, true])
    eq('G5 ceiling-timed-out carries the additive ceiling diagnostic flag', outWedged.ceiling, true)
    matches('G6 ceiling-timed-out error names the ceiling', outWedged.error, /wall-clock ceiling/)
  }

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
    const tokens = [
      ['parseReviewResult', 'text-contract extractor — the explorer dispatches schema-free (#169)'],
      ['REVIEW_RESULT', 'sentinel token of the explorer text contract (#169)'],
      ['structured-emitter', 'tool-less schema sink — the only schema carrier (#169)'],
      ['retried: true', 'twice-dead flag — synthesis must not mistake a dead reviewer for "no findings"'],
      ['failed: true', 'twice-dead flag'],
      ['budgetExhausted: true', 'all-or-nothing budget-skip dark-reviewer marker (#168)'],
      ['REVIEWER_CEILING_MS', 'per-reviewer wall-clock ceiling constant (#219) — the wedge bound'],
      ['ceiling: true', 'ceiling-timeout diagnostic flag (#219) on the reused died-after-retry marker'],
      ['`${base}...${head}`', 'THREE-DOT review range (#130) — two-dot renders base-only commits as phantom deletions'],
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
