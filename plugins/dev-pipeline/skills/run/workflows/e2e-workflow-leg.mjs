// e2e-workflow-leg.mjs — drive ONE production Workflow `.mjs` body with canned agent
// output and print the verdict the E2E replay feeds into a statectl write.
//
// NOT a selftest: the filename deliberately does NOT match the CI discovery globs, so CI
// never executes it directly. It is a helper for `../e2e-replay-selftest.sh`, which is
// what exercises every branch below on both lanes.
//
// WHY A SEPARATE FILE
// -------------------
// The replay harness is shell (it drives statectl, verifyctl, claim-issue.sh, git). The
// stage-4/5/8 seams are Workflow `.mjs` bodies, executable only through the runtime shim,
// which is JavaScript. Rather than re-type the wrapper into the shell harness with
// `node -e` (unreadable, and a second copy of the mechanics), the shell shells out here
// once per leg and parses one JSON line.
//
// WHAT THIS PROVES, AND WHAT IT DOES NOT
// --------------------------------------
// Proves: at each of those three stages the REAL production sequencer runs, consumes
// canned agent output, and returns a verdict of the shape the stage prose says it writes
// to state. So a production edit that changes the verdict vocabulary breaks the replay.
// Does not prove: the reviewers' judgment, or the prose that decides what to do with a
// verdict. A model-free CI asserts the mechanical shadow of prose gates — never the prose.
//
// Per-workflow ladder behavior (retry, emitter fallback, turn-cap death) is NOT retested
// here; that is runtime-shim-selftest.mjs's tier. These legs exist to produce verdicts.
//
// Usage:  node e2e-workflow-leg.mjs <plan-review|mutation-gate|code-review>
// Output: one JSON object on stdout. Exit 0 on success, 1 on an unknown leg or a throw.

import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { makeFakeAgent, makeFakeWorkflow, makeRunner, noop, parallel, pipeline } from './runtime-shim-lib.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))

// A well-formed REVIEW_RESULT block for the plan-reviewer / code-reviewer text contract.
// Production parses this itself (explorer dispatches are schema-free, #169), so the fake
// agent must hand back TEXT here — an object would be the emitter leg's shape and
// validateShape would reject it.
const reviewBlock = (payload) => `REVIEW_RESULT\n\`\`\`json\n${JSON.stringify(payload)}\n\`\`\``

const LEGS = {
  // Stage 4 — plan-review.mjs. Its `overall` is what the stage writes via
  // `statectl plan-review-set --overall`.
  'plan-review': async () => {
    // PLAN_REVIEW_SCHEMA, not the code-review FINDINGS_SCHEMA: `findings[].message` here
    // vs `findings[].title/description` there, and a block|fix-and-go|pass verdict enum
    // vs approve|request-changes. Production's validateShape rejects the near-miss and
    // the leg comes back `infra` — which is how this was caught, and why the leg asserts
    // on `overall` rather than merely "it ran".
    const f = makeFakeAgent([
      reviewBlock({
        verdict: 'pass',
        findings: [{ severity: 'note', message: 'canned plan review', evidence: 'fixture' }],
        summary: 'canned plan review',
      }),
    ])
    const w = makeFakeWorkflow([])
    const args = {
      worktree: '/tmp/e2e-wt',
      planPath: 'docs/plans/acme-9001.md',
      issue: '9001',
      workflowsDir: 'workflows',
      design: { enabled: false },
      unitTests: { enabled: false },
      planGates: [],
      briefPath: null,
      config: { reviewers: {} },
    }
    const r = await makeRunner(join(HERE, 'plan-review.mjs'))(
      f.agent, parallel, pipeline, args, noop, noop, undefined, w.workflow,
    )
    return { leg: 'plan-review', overall: r.overall, gates: r.gates.map((g) => g.gate), dispatches: f.calls.length }
  },

  // Stage 5 — mutation-gate.mjs. This repo has no mutation surface
  // (commands.<host>.unitTestScope is null), so the replay writes no state from this
  // verdict; the leg proves the sequencer executes, routes its nested propose through the
  // injected workflow() global, and returns a consumable verdict. Stated rather than
  // implied, so nobody reads a missing state write as a dropped assertion.
  'mutation-gate': async () => {
    const f = makeFakeAgent([])
    const w = makeFakeWorkflow([{ result: { mutants: [], mockAuditFindings: [], summary: 'canned proposal' } }])
    const args = {
      worktree: '/tmp/e2e-wt',
      base: 'aaa',
      head: 'bbb',
      issue: '9001',
      workflowsDir: 'workflows',
      round: 1,
      inputs: {},
      config: { reviewers: {} },
      testFileCommand: 'true {file}',
    }
    const r = await makeRunner(join(HERE, 'mutation-gate.mjs'))(
      f.agent, parallel, pipeline, args, noop, noop, undefined, w.workflow,
    )
    return { leg: 'mutation-gate', overall: r.overall, nestedDispatches: w.calls.length, executions: r.executions.length }
  },

  // Stage 8 — code-review.mjs. The replay turns a clean round into
  // `statectl review-rounds --set 1`.
  'code-review': async () => {
    const f = makeFakeAgent([
      reviewBlock({
        verdict: 'approve',
        findings: [{ severity: 'minor', title: 'canned', description: 'd', confidence: 70, file: 'a.sh', line: 1 }],
      }),
    ])
    const args = {
      worktree: '/tmp/e2e-wt',
      base: 'aaa',
      head: 'bbb',
      issue: '9001',
      reviewers: ['review-toolkit:complexity-reviewer'],
      changedFiles: ['a.sh'],
      config: { reviewers: {} },
    }
    const r = await makeRunner(join(HERE, 'code-review.mjs'))(
      f.agent, parallel, pipeline, args, noop, noop, undefined, undefined,
    )
    const dark = r.reviewers.filter((x) => x && x.result === null).length
    return {
      leg: 'code-review',
      range: r.range,
      reviewers: r.reviewers.length,
      dark,
      verdict: r.reviewers[0] && r.reviewers[0].result ? r.reviewers[0].result.verdict : null,
    }
  },
}

const leg = process.argv[2]
if (!leg || !LEGS[leg]) {
  console.error(`e2e-workflow-leg: unknown leg '${leg ?? ''}' (known: ${Object.keys(LEGS).join(', ')})`)
  process.exit(1)
}
try {
  console.log(JSON.stringify(await LEGS[leg]()))
} catch (e) {
  console.error(`e2e-workflow-leg: ${leg} threw: ${e && e.stack ? e.stack : e}`)
  process.exit(1)
}
// EXPLICIT exit, not a fallthrough. plan-review.mjs and code-review.mjs race each
// dispatch against a 15-minute ceiling timer that production never needs to clear (the
// real runtime tears the process down). Under the shim that timer keeps node's event loop
// alive, so a script that merely reaches its end hangs for fifteen minutes instead of
// returning. runtime-shim-selftest.mjs does not hit this only because it ends in
// process.exit(FAIL); this file needs the same. Removing it turns the replay into a
// timeout, not a failure.
process.exit(0)
