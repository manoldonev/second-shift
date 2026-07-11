export const meta = {
  name: 'dev-pipeline-api-tests',
  description:
    "Stage 4/5 API test dispatch for the dev-pipeline. kind='plan-review' dispatches api-test-plan-reviewer; kind='implement' dispatches api-test-coder. Verdict/status handling and state writes stay in the dev-pipeline session.",
  phases: [{ title: 'API Tests', detail: 'one agent() per plan-review/implement dispatch' }],
}

// Gated by config `gates.apiTests`. Stages 4/5 dispatch this workflow only when the
// api-test tier is enabled AND the change touches a BE surface with an api-test
// convention. Targets are the review-toolkit plugin agents (api-test-plan-reviewer,
// api-test-coder). The `tests/api/` path is the api-testing tier's default
// convention (see the review-toolkit:api-testing skill and its repo extension).

// API test dispatches run at the code tier — keep in lockstep with agent frontmatter (`model: sonnet`).
const API_TEST_MODEL = 'sonnet'

const PLAN_REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['block', 'fix-and-go', 'pass'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'message'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'warning', 'note'] },
          evidence: { type: 'string' },
          impact: { type: 'string' },
          message: { type: 'string' },
          suggestedFix: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

// WRITE-ONLY shape: the coder writes test files and returns the list. Verification (`yarn ci` +
// behavioral) and the scoped commit are owned by the Stage-5 orchestrator — keeping that heavy work
// out of the schema-forced agent turn lowers (but does not eliminate) the StructuredOutput staller,
// and an orchestrator-owned commit means nothing outside tests/api/** can ever be staged.
const IMPLEMENT_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['status', 'summary'],
  properties: {
    status: { type: 'string', enum: ['ok', 'error'] },
    filesWritten: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}

// --- StructuredOutput-staller mitigation (shared posture with code-review.mjs, strengthened) ---
// The api-test-coder is a heavy action agent: it can finish writing files and end its turn WITHOUT
// the forced StructuredOutput call (the GH-844 run hit this twice). Two layered defenses, mirrored
// in every schema-forced workflow: (1) STRUCTURED_OUTPUT_MANDATE makes the call non-negotiable and
// — critically for an action agent — tells it the call is the FINAL step (not "first", which it
// cannot satisfy before writing files); (2) dispatchSchemaAgent retries inline on a StructuredOutput
// death. Together with Stage-5's one workflow re-dispatch this drives the staller to ~zero.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

// The runtime rejects agent() with a message containing "StructuredOutput" when a subagent ends
// without producing structured output. ONLY that error class is retried; genuine tool/permission
// errors throw straight through. Brittle substring match — the only signal the runtime surfaces;
// if the runtime changes the message the retry stops firing and degrades to the unretried path.
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

// One schema'd dispatch with up to `retries` INLINE retries on a StructuredOutput death. Resolves
// to the agent result on success; throws the last error after exhausting retries (the caller maps
// that throw to its infraFailure envelope).
const dispatchSchemaAgent = async (prompt, opts, retries = 2) => {
  let lastErr
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await agent(prompt, attempt === 0 ? opts : { ...opts, label: `${opts.label} (retry ${attempt})` })
    } catch (err) {
      lastErr = err
      if (!isNoStructuredOutputError(err)) throw err
      log(`${opts.label}: died without StructuredOutput — retry ${attempt + 1}/${retries}`)
    }
  }
  throw lastErr
}

// args (assembled in-session by the dispatching Stage; defensive string-or-object):
//   kind      — 'plan-review' | 'implement'
//   worktree  — absolute BE worktree path (ALL file ops / git / reads happen here)
//   target    — 'api-test-plan-reviewer' | 'api-test-coder'
//   inputs    — { planPath, targetSpecPath?, controllersTouched?, changedBackendFiles? }
//   jiraKey   — for labels/logging
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { kind, worktree, target, inputs = {}, jiraKey = '' } = a
if (kind !== 'plan-review' && kind !== 'implement') {
  throw new Error("api-tests workflow: args.kind must be 'plan-review' or 'implement'")
}
if (!worktree || !target) {
  throw new Error('api-tests workflow: args.worktree and args.target are required')
}

const failClosed = (note) =>
  kind === 'plan-review'
    ? { verdict: 'block', findings: [{ severity: 'blocker', message: note }], summary: note }
    : { status: 'error', filesWritten: [], summary: note }

log(`api-tests: ${kind} via ${target} in ${worktree}${jiraKey ? ` (${jiraKey})` : ''}`)
phase('API Tests')

if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping api-tests dispatch')
    // budgetExhausted distinguishes this clean skip from a sub-agent block/error: Stage 4/5 must
    // not map it to api-test-plan-reviewer-block / api-test-coder-error (eval-scored reasons).
    return { kind, target, worktree, budgetExhausted: true }
  }
}

if (!inputs.planPath) {
  throw new Error('api-tests workflow: inputs.planPath is required')
}

let prompt
let opts
if (kind === 'plan-review') {
  prompt =
    `Review the API test plan at \`${inputs.planPath}\`. ` +
    `All file reads / Grep / Glob / Bash must target the BE worktree \`${worktree}\`. ` +
    (inputs.targetSpecPath ? `Target spec: \`${inputs.targetSpecPath}\`. ` : '') +
    (inputs.controllersTouched?.length
      ? `Controllers touched: ${inputs.controllersTouched.join(', ')}. `
      : '') +
    `Load the api-testing skill conventions. Return trinary verdict (block | fix-and-go | pass) and findings.`
  opts = {
    agentType: 'api-test-plan-reviewer',
    model: API_TEST_MODEL,
    label: 'api-test-plan-reviewer',
    phase: 'API Tests',
    schema: PLAN_REVIEW_SCHEMA,
  }
} else {
  if (!inputs.targetSpecPath) {
    throw new Error('api-tests implement: inputs.targetSpecPath is required')
  }
  prompt =
    `Implement API tests per the plan at \`${inputs.planPath}\` in WRITE-ONLY mode. ` +
    `Working directory for ALL file ops / reads: \`${worktree}\`. ` +
    `Target spec: \`${inputs.targetSpecPath}\` (under tests/api/). ` +
    (inputs.controllersTouched?.length
      ? `Backend controllers for reference: ${inputs.controllersTouched.join(', ')}. `
      : '') +
    (inputs.changedBackendFiles?.length
      ? `Changed backend files: ${inputs.changedBackendFiles.join(', ')}. `
      : '') +
    `You are api-test-coder — modify ONLY files under tests/api/. ` +
    `Do NOT run \`yarn ci\`, do NOT run the behavioral suite, do NOT commit — the orchestrator owns ` +
    `verification and the scoped commit. Just write the test files and return the moment they are written. ` +
    `Return {status, filesWritten, summary} with every path you created/modified (all under tests/api/). ` +
    `Set status="error" only if you cannot produce coherent test files.`
  opts = {
    agentType: 'api-test-coder',
    model: API_TEST_MODEL,
    label: 'api-test-coder',
    phase: 'API Tests',
    schema: IMPLEMENT_SCHEMA,
  }
}

prompt += STRUCTURED_OUTPUT_MANDATE

// `infraFailure: true` marks a dispatch/StructuredOutput death (survived the inline retries) so the
// orchestrator + pipeline-retro can tell it apart from a real coder error — never route it to
// api-test-coder-error (eval-scored). Stage 5 may re-dispatch once more, then surfaces it.
const result = await dispatchSchemaAgent(prompt, opts).catch((err) => ({
  ...failClosed('agent dispatch failed: ' + String(err)),
  infraFailure: true,
}))

return { kind, target, worktree, result }
