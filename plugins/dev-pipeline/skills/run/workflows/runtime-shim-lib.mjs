// runtime-shim-lib.mjs — execute WHOLE production Workflow `.mjs` bodies the way the
// Workflow runtime does. Shared mechanics for the suites that drive them.
//
// NOT a selftest: the filename deliberately does NOT match the CI discovery globs
// (`*-selftest.sh` / the `.mjs` names `workflows-mjs-selftest.sh` hands to node), so CI
// never executes this file directly. Same posture, and same reason, as
// `skills/run/scenario-lib.sh`: two suites need one definition of the mechanics, and
// duplicating them is how the two drift apart.
//
// It has no dedicated selftest by design — it is pure mechanics with no independent
// contract, and every CI run exercises it through both callers:
//   - workflows/runtime-shim-selftest.mjs — the per-workflow dispatch-ladder cases
//   - workflows/e2e-workflow-leg.mjs      — the E2E replay's stage-4/5/8 legs
//
// WHY THE SHIM EXISTS (#214, epic #213)
// -------------------------------------
// Workflow bodies carry a top-level `return` and reference runtime-injected globals, so
// `node file.mjs` and even `node --check` both fail. That made grep-on-source look like
// the only available technique, and the suites that resulted were MIRROR HARNESSES:
// they re-implemented production's dispatch logic and then tested the copy. Structurally
// incapable of failing on a production edit, and they rotted exactly as you would predict.
//
// Strip the `export const meta = {…}` block and wrap the remainder in an async arrow
// taking the injected globals as parameters, and the body is ordinary executable JS:
//
//     (async (agent, parallel, pipeline, args, log, phase, budget, workflow) => { …body… })
//
// The top-level `return` becomes a legal return from that arrow. Every global the body
// touches arrives as a parameter we control. So PRODUCTION code runs with canned agent
// outputs and we assert on what it actually returns — no copies, no mirrors.
//
// The meta-strip is a balanced-brace scan, not a parser. That is sound because
// design-sync-selftest.mjs Case I lints every sibling workflow for meta-literal purity
// (no template interpolation, no computed values), so a brace inside a string in the meta
// block cannot ship.

import { readFileSync } from 'node:fs'

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

// Build a runnable function from a production workflow body.
//
// PARAMETER ORDER IS THE CONTRACT. `workflow` is LAST, and appending is the only safe
// way to add a global: inserting one anywhere else silently shifts every existing
// positional call site (args would arrive as log), and the cases would then fail for
// reasons that look like production bugs rather than a harness edit.
//
// `workflow` was added for the E2E legs: plan-review.mjs (its unit-test gate) and
// mutation-gate.mjs:101 (its nested propose call) both invoke the `workflow()` global,
// so under a 7-parameter wrapper those two bodies die with a ReferenceError before
// reaching a fake. Callers that drive a workflow which never calls it simply omit the
// argument.
export const makeRunner = (path) => {
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
    'workflow',
    `return (async () => {\n${body}\n})()`,
  )
}

// A fake agent driven by a behavior QUEUE. Each entry is either a string (returned as
// the agent's text), or { throw: 'msg' }, or a function of the dispatch opts, or a plain
// object.
//
// The string-vs-object distinction models the runtime faithfully and is load-bearing:
// a schema-FREE dispatch (every explorer, post-#169) resolves to TEXT that production
// parses itself, while a schema-carrying dispatch (only ever the structured-emitter)
// resolves to an already-VALIDATED OBJECT. Feeding a text block to the emitter leg would
// make production's validateShape reject a string and the case would fail for the wrong
// reason.
export const makeFakeAgent = (behaviors) => {
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

// A fake `workflow()` global, driven by the same behavior-queue shape as makeFakeAgent.
// Production calls it as workflow({ scriptPath }, args) for a nested dispatch; each queue
// entry is the value that nested call resolves to (or { throw } to reject).
export const makeFakeWorkflow = (behaviors) => {
  const calls = []
  const queue = [...behaviors]
  const workflow = async (ref, wargs) => {
    calls.push({ ref, args: wargs })
    const next = queue.length ? queue.shift() : {}
    if (next && typeof next === 'object' && 'throw' in next) throw new Error(next.throw)
    return typeof next === 'function' ? next(ref, wargs) : next
  }
  return { workflow, calls, remaining: () => queue.length }
}

// Runtime doubles. parallel() is a barrier over thunks; pipeline() threads stages.
export const parallel = (thunks) => Promise.all(thunks.map((t) => t()))
export const pipeline = async (items, ...stages) => {
  const out = []
  for (let i = 0; i < items.length; i++) {
    let v = items[i]
    for (const s of stages) v = await s(v, items[i], i)
    out.push(v)
  }
  return out
}
export const noop = () => {}
export const makeBudget = (total, remaining) => ({
  total,
  spent: () => total - remaining,
  remaining: () => remaining,
})
