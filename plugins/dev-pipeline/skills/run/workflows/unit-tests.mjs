export const meta = {
  name: 'dev-pipeline-unit-tests',
  description:
    "Stage 4/5 unit test dispatch for the dev-pipeline. kind='plan-review' dispatches unit-test-plan-reviewer; kind='mutation-review' dispatches unit-test-mutation-reviewer. Verdict handling and state writes stay in the dev-pipeline session.",
  phases: [{ title: 'Unit Tests', detail: 'one agent() per plan-review/mutation-review dispatch' }],
}

// Keep in lockstep with agent frontmatter (`model: sonnet`). A per-agent override in
// args.config.reviewers.modelOverrides (bare-keyed) wins over this default.
const UNIT_TEST_MODEL = 'sonnet'

// Bare (unqualified) agent name — tolerant of both `plugin:agent` and bare forms.
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

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

// Stage-5 PROPOSE-ONLY shape: the agent proposes mutants + patches; it does NOT apply/run/revert
// or emit a verdict. The Stage-5 orchestrator executes the blocker-class patches (apply → run spec →
// revert) and computes the verdict + mutationScore from the results. Keeping execution out of the
// schema-forced agent turn lowers (but does not eliminate) the StructuredOutput staller — the
// mandate + inline retry below are what actually drive it to ~zero.
const MUTATION_REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['mutants', 'summary'],
  properties: {
    mutants: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'classification', 'file', 'message'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'warning', 'note'] },
          classification: { type: 'string', enum: ['survived', 'untested'] },
          file: { type: 'string' },
          specPath: { type: 'string' },
          // Required for blocker-class mutants so the orchestrator can apply → run → revert.
          originalSnippet: { type: 'string' },
          mutatedSnippet: { type: 'string' },
          predictedKilled: { type: 'boolean' },
          message: { type: 'string' },
          suggestedFix: { type: 'string' },
        },
      },
    },
    mockAuditFindings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'message'],
        properties: {
          severity: { type: 'string', enum: ['warning', 'note'] },
          specPath: { type: 'string' },
          message: { type: 'string' },
          evidence: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

// --- StructuredOutput-staller mitigation (shared posture with code-review.mjs, strengthened) ---
// unit-test-mutation-reviewer is a heavy exploration agent: it greps/reads broadly then can end its
// turn WITHOUT the forced StructuredOutput call. Same two defenses mirrored across every
// schema-forced workflow: a non-negotiable mandate ("final action MUST be the call") + an inline
// retry on the StructuredOutput death class. With Stage-5's one re-dispatch this drives the staller
// to ~zero. The plan-review path shares the same dispatch and benefits too.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

// Bounding nudges — the PRIMARY stall fix (see the ROOT CAUSE block in code-review.mjs). One per
// kind, because the two dispatches have opposite exhaustiveness needs and one shared wording would
// be wrong for one of them.
//
// plan-review kind: the agent checks a plan's test strategy against the codebase, so bound HOW it
// grounds (batch the existence checks, sample the content reads), never WHETHER — that would gut
// the gate. Mirrors plan-review.mjs's constant of the same name; restated because Workflow scripts
// cannot import.
const BOUNDED_PLAN_GROUNDING =
  ' GROUND PROPORTIONATELY: verify that referenced paths and symbols exist using BATCHED checks' +
  ' (one ls/glob/grep covering many paths — not one Read per path). Read a file in full only when' +
  ' its CONTENT is needed to support a specific finding you intend to raise. You do NOT have to' +
  ' open every referenced file to conclude the test strategy is sound. Stop exploring and emit' +
  ' StructuredOutput before your budget runs low.'

// mutation-review kind: enumerating mutants across the changed surface IS the deliverable, so this
// bounds the SWEEP (stay inside the diff rather than touring the codebase), not the enumeration.
// That distinction is why unit-test-mutation-reviewer is a declared opt-out on the code-review.mjs
// side, where the same agent has no diff-scoped range to anchor a bound to.
const BOUNDED_MUTATION_SWEEP =
  ' BOUND YOUR SWEEP: enumerate mutants for the files in the stated diff range and their co-located' +
  ' specs. Do not tour the wider codebase for context — read outside the changed files only when a' +
  ' specific mutant you are proposing depends on it. Fewer well-grounded mutants beat an exhaustive' +
  ' tour that never emits. Stop exploring and emit StructuredOutput before your budget runs low.'

// Appended ONLY to a retry, so a second attempt is never a verbatim repeat of one that hit a turn
// wall. The runtime surfaces no turn count and the error string is identical for a stochastic death
// and a budget wall, so this changes what the retry DOES rather than inventing a discriminator.
const RETRY_ESCALATION =
  ' RETRY CONTEXT: your previous attempt exhausted its turn budget exploring and never emitted,' +
  ' which counts as producing nothing. Explore MARKEDLY less this time and call StructuredOutput as' +
  ' early as you can defend, with partial results if necessary.'

// Only the StructuredOutput-death error class is retried; genuine tool/permission errors throw
// straight through. Brittle substring match — the only signal the runtime surfaces.
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

// One schema'd dispatch with up to `retries` INLINE retries on a StructuredOutput death. Resolves
// to the agent result on success; throws the last error after exhausting retries (the caller maps
// that throw to its infraFailure envelope).
// retries = 1 (was 2): repeating an identical attempt after a turn-budget death is a foregone
// conclusion — measured at 480k wasted tokens across six such dispatches in one Stage-4 run.
const dispatchSchemaAgent = async (prompt, opts, retries = 1) => {
  let lastErr
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await agent(
        attempt === 0 ? prompt : prompt + RETRY_ESCALATION,
        attempt === 0 ? opts : { ...opts, label: `${opts.label} (retry ${attempt})` },
      )
    } catch (err) {
      lastErr = err
      if (!isNoStructuredOutputError(err)) throw err
      log(`${opts.label}: died without StructuredOutput — retry ${attempt + 1}/${retries}`)
    }
  }
  throw lastErr
}

// args (assembled in-session by the dispatching Stage):
//   kind      — 'plan-review' | 'mutation-review'
//   worktree  — ABSOLUTE worktree path (the dispatching Stage resolves the repo-relative
//               state `worktreePath` against repo root before passing — Workflow scripts cannot
//               resolve a relative path themselves; matches code-review.mjs's contract).
//   target    — 'unit-test-plan-reviewer' | 'unit-test-mutation-reviewer'
//   base, head — git refs bounding mutation-review (required): branch, ref, or SHA. The
//                agent runs `git diff base...head` — THREE-DOT, i.e. merge-base semantics,
//                so an advanced base branch never leaks its own commits into the reviewed
//                diff (#130). An explicit merge-base SHA is unaffected.
//   inputs    — { planPath?, modulesTouched?, specPaths?, changedBackendFiles? }
//   issue     — for labels/logging
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { kind, worktree, target, base, head, inputs = {}, issue = '', config = {} } = a
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
if (kind !== 'plan-review' && kind !== 'mutation-review') {
  throw new Error("unit-tests workflow: args.kind must be 'plan-review' or 'mutation-review'")
}
if (!worktree || !target) {
  throw new Error('unit-tests workflow: args.worktree and args.target are required')
}
if (kind === 'mutation-review' && (!base || !head)) {
  throw new Error('unit-tests mutation-review: args.base and args.head are required')
}

const failClosed = (note) =>
  kind === 'plan-review'
    ? { verdict: 'block', findings: [{ severity: 'blocker', message: note }], summary: note }
    : {
        verdict: 'block',
        mutationScore: { killed: 0, survived: 0, untested: 0 },
        findings: [{ severity: 'blocker', message: note }],
        summary: note,
      }

log(`unit-tests: ${kind} via ${target} in ${worktree}${kind === 'mutation-review' ? ` (${base}...${head})` : ''}${issue ? ` (#${issue})` : ''}`)
phase('Unit Tests')

if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping unit-tests dispatch')
    // Clean skip: NOT a fake block. Stage 4/5 must not map budgetExhausted to
    // unit-test-plan-reviewer-block / unit-test-mutation-reviewer-block (eval-tracked reasons).
    return { kind, target, worktree, budgetExhausted: true }
  }
}

let prompt
let opts
if (kind === 'plan-review') {
  if (!inputs.planPath) {
    throw new Error('unit-tests plan-review: inputs.planPath is required')
  }
  prompt =
    `Review the unit test strategy in the plan at \`${inputs.planPath}\`. ` +
    `All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
    (inputs.modulesTouched?.length
      ? `Modules touched: ${inputs.modulesTouched.join(', ')}. `
      : '') +
    (inputs.mutationTargets?.length
      ? `Planned mutation targets: ${inputs.mutationTargets.join('; ')}. `
      : '') +
    `Load the unit-testing skill. Return trinary verdict (block | fix-and-go | pass) and findings.` +
    BOUNDED_PLAN_GROUNDING
  // bounded-exploration: BOUNDED_PLAN_GROUNDING
  opts = {
    agentType: 'review-toolkit:unit-test-plan-reviewer',
    model: modelOverrides['unit-test-plan-reviewer'] || UNIT_TEST_MODEL,
    label: 'unit-test-plan-reviewer',
    phase: 'Unit Tests',
    schema: PLAN_REVIEW_SCHEMA,
  }
} else {
  // THREE-DOT is load-bearing (#130) — see the base/head contract above.
  const range = `${base}...${head}`
  const fileList = inputs.changedBackendFiles?.length
    ? inputs.changedBackendFiles.join(', ')
    : '(run git diff --name-only)'
  prompt =
    `Mutation review in PROPOSE-ONLY mode on unit tests for apps/api changes in worktree \`${worktree}\`. ` +
    `Diff scope: \`git -C ${worktree} diff ${range}\` — review ONLY lines changed in this ticket's commit range; ` +
    `do not flag pre-existing test gaps outside the diff. ` +
    (inputs.modulesTouched?.length
      ? `Production modules (plan context): ${inputs.modulesTouched.join(', ')}. `
      : '') +
    (inputs.specPaths?.length ? `Spec files (plan context): ${inputs.specPaths.join(', ')}. ` : '') +
    `Changed files in range: ${fileList}. ` +
    `Load the unit-testing skill. Propose mutants, classify survived/untested, audit mock-only assertions. ` +
    `Do NOT apply mutants or run tests — for each blocker-class mutant predicted survived/untested, emit a ` +
    `uniquely-matching {originalSnippet, mutatedSnippet} patch so the orchestrator can verify it by execution. ` +
    `No Stryker. No verdict (the orchestrator computes it). ` +
    `Return {mutants, mockAuditFindings, summary}.` +
    BOUNDED_MUTATION_SWEEP
  // bounded-exploration: BOUNDED_MUTATION_SWEEP
  opts = {
    agentType: 'review-toolkit:unit-test-mutation-reviewer',
    model: modelOverrides['unit-test-mutation-reviewer'] || UNIT_TEST_MODEL,
    label: 'unit-test-mutation-reviewer',
    phase: 'Unit Tests',
    schema: MUTATION_REVIEW_SCHEMA,
  }
}

prompt += STRUCTURED_OUTPUT_MANDATE

// `infraFailure: true` marks a dispatch/StructuredOutput death that survived the inline retries, so
// the orchestrator + pipeline-retro can tell it apart from a real agent verdict — never route it to
// a `*-block` (eval-tracked). Stage 5 may re-dispatch once more, then surfaces it.
const result = await dispatchSchemaAgent(prompt, opts).catch((err) => ({
  ...failClosed('agent dispatch failed: ' + String(err)),
  infraFailure: true,
}))

return { kind, target, worktree, result }
