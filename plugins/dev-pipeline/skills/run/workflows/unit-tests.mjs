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

// STRUCTURED_OUTPUT_MANDATE is retired on this dispatcher: both kinds now run their explorer
// schema-FREE via the explorer/emitter transport below (#169 — measured: the forced schema on an
// exploring agent IS the stall mechanism; schema-free 0/8 stalls vs 7/8 at a third of the cost).

// SHIPPING NOTE (#169): the explorer dispatches below send these nudges NOWHERE — the measured
// schema-free arm ran WITHOUT them and the fix ships what was measured. Constants stay defined
// for probe lockstep and future cost tuning behind a new measurement.
// Bounding nudges — formerly the PRIMARY stall fix (see the ROOT CAUSE block in code-review.mjs). One per
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

// --- explorer/emitter transport (the structural stall fix; #169) ---
// The explorer runs schema-FREE and ends with a sentinel + fenced JSON block, parsed and
// validated in-script; the schema objects become validators. The transcription-only emitter
// agent (tools: [], maxTurns: 2) is the only schema carrier — and ONLY for the plan-review
// kind. The mutation kind never routes through the emitter: its blocker mutants carry
// {originalSnippet, mutatedSnippet} patch bytes that Stage 5 applies MECHANICALLY, and a
// transcription model is a corruption surface for verbatim code. A mutation contract miss
// goes straight to the caller's infraFailure envelope instead (Stage 5 re-dispatches once).
const parseReviewResult = (text) => {
  const m = [...String(text ?? '').matchAll(/REVIEW_RESULT\s*```json\s*([\s\S]*?)```/g)]
  if (!m.length) return null
  try {
    return JSON.parse(m[m.length - 1][1])
  } catch {
    return null
  }
}

const validateShape = (obj, schema) => {
  if (!obj || typeof obj !== 'object') return false
  for (const key of schema.required || []) if (!(key in obj)) return false
  const props = schema.properties || {}
  for (const k of Object.keys(props)) {
    const p = props[k]
    if (!(k in obj) || obj[k] == null) continue
    if (p.enum && !p.enum.includes(obj[k])) return false
    if (p.type === 'array') {
      if (!Array.isArray(obj[k])) return false
      if (p.items) {
        for (const it of obj[k]) {
          if (p.items.type === 'string') {
            if (typeof it !== 'string') return false
            continue
          }
          if (!it || typeof it !== 'object') return false
          for (const rk of p.items.required || []) if (!(rk in it)) return false
          const ip = p.items.properties || {}
          for (const ik of Object.keys(ip)) {
            if (ip[ik].enum && ik in it && it[ik] != null && !ip[ik].enum.includes(it[ik])) return false
          }
        }
      }
    }
  }
  return true
}

const emitStructured = (text, opts) =>
  // bounded-exploration-optout: structured-emitter -- tools:[] maxTurns:2 transcription sink;
  //   nothing to explore, which is why it may carry the schema.
  agent(
    'Convert this completed review into the required structured object. Transcribe EXACTLY' +
      ' what the review states — never invent, drop, merge, soften or upgrade findings.' +
      '\n\n---REVIEW---\n' + String(text) + '\n---END---',
    { agentType: 'review-toolkit:structured-emitter', model: 'haiku', label: `${opts.label} (emit)`, phase: opts.phase, schema: opts.schema },
  )

// retries = 1 — one escalated re-explore on a contract miss, never a verbatim repeat.
// opts.allowEmit gates rung 2 (true for plan-review, false for mutation-review).
const dispatchSchemaAgent = async (prompt, opts, retries = 1) => {
  let lastText = null
  for (let attempt = 0; attempt <= retries; attempt++) {
    const text = await agent(
      (attempt === 0 ? prompt : prompt + RETRY_ESCALATION) + opts.epilogue,
      { agentType: opts.agentType, model: opts.model, label: attempt === 0 ? opts.label : `${opts.label} (retry ${attempt})`, phase: opts.phase },
    )
    const parsed = parseReviewResult(text)
    if (parsed && validateShape(parsed, opts.schema)) return parsed
    lastText = text
    log(`${opts.label}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : 'no sentinel'}) — attempt ${attempt + 1}/${retries + 1}`)
  }
  if (opts.allowEmit && /REVIEW_RESULT/.test(String(lastText ?? ''))) {
    const emitted = await emitStructured(lastText, opts)
    if (emitted && validateShape(emitted, opts.schema)) return emitted
    throw new Error('text-contract: emitter produced an invalid shape — declared dark')
  }
  throw new Error('text-contract: explorer never produced a parseable REVIEW_RESULT block — declared dark')
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
    `Load the unit-testing skill. Return trinary verdict (block | fix-and-go | pass) and findings.`
  opts = {
    agentType: 'review-toolkit:unit-test-plan-reviewer',
    model: modelOverrides['unit-test-plan-reviewer'] || UNIT_TEST_MODEL,
    label: 'unit-test-plan-reviewer',
    phase: 'Unit Tests',
    // bounded-exploration-optout: validator-reference -- this schema: key never rides a
    //   dispatch; dispatchSchemaAgent uses it for validateShape and the tool-less emitter only.
    schema: PLAN_REVIEW_SCHEMA,
    allowEmit: true,
    epilogue:
      '\n\nWrite your review, grounding as much as you need. Your FINAL output MUST end with' +
      ' this sentinel line followed by one fenced json block and NOTHING after it:\n\n' +
      'REVIEW_RESULT\n```json\n{ "verdict": "block|fix-and-go|pass", "findings": [ { "severity":' +
      ' "blocker|warning|note", "message": "...", "evidence": "...", "impact": "...",' +
      ' "suggestedFix": "..." } ], "summary": "..." }\n```',
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
    `Return {mutants, mockAuditFindings, summary}.`
  opts = {
    agentType: 'review-toolkit:unit-test-mutation-reviewer',
    model: modelOverrides['unit-test-mutation-reviewer'] || UNIT_TEST_MODEL,
    label: 'unit-test-mutation-reviewer',
    phase: 'Unit Tests',
    // bounded-exploration-optout: validator-reference -- this schema: key never rides a
    //   dispatch; validateShape-only. NO emitter for this kind: patch bytes must never
    //   transit a transcription model.
    schema: MUTATION_REVIEW_SCHEMA,
    allowEmit: false,
    epilogue:
      '\n\nWrite your review. Your FINAL output MUST end with this sentinel line followed by one' +
      ' fenced json block and NOTHING after it (escape code snippets into valid JSON strings):\n\n' +
      'REVIEW_RESULT\n```json\n{ "mutants": [ { "severity": "blocker|warning|note",' +
      ' "classification": "survived|untested", "file": "...", "specPath": "...",' +
      ' "originalSnippet": "...", "mutatedSnippet": "...", "predictedKilled": false,' +
      ' "message": "...", "suggestedFix": "..." } ], "mockAuditFindings": [ { "severity":' +
      ' "warning|note", "specPath": "...", "message": "...", "evidence": "..." } ],' +
      ' "summary": "..." }\n```',
  }
}

// The epilogue (per-kind, in opts) replaces the retired STRUCTURED_OUTPUT_MANDATE append.

// `infraFailure: true` marks a dispatch/StructuredOutput death that survived the inline retries, so
// the orchestrator + pipeline-retro can tell it apart from a real agent verdict — never route it to
// a `*-block` (eval-tracked). Stage 5 may re-dispatch once more, then surfaces it.
const result = await dispatchSchemaAgent(prompt, opts).catch((err) => ({
  ...failClosed('agent dispatch failed: ' + String(err)),
  infraFailure: true,
}))

return { kind, target, worktree, result }
