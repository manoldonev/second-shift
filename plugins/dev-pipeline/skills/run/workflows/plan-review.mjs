export const meta = {
  name: 'dev-pipeline-plan-review',
  description:
    'Stage 4 sequencer for the dev-pipeline. Deterministically chains the mandated plan gates — plan-reviewer, design FE-spec review, unit-test plan review — and returns ONE consolidated verdict. Makes the mandated dispatches a single observable Workflow call (closes the skipped-dispatch drift class). Verdict handling, mark-failed writes, and interactive block-presentation stay in the dev-pipeline session.',
  phases: [{ title: 'Plan Review', detail: 'plan-reviewer agent + design/unit-test gate dispatches' }],
}

// plan-reviewer runs at the reasoning tier — keep in lockstep with the plugin-shipped
// review-toolkit:plan-reviewer frontmatter (model: opus) and SKILL.md's Model Tiering
// row for Stage 4. Enforced by review-toolkit/scripts/check-model-tiers.sh. A per-agent
// override in args.config.reviewers.modelOverrides (bare-keyed) wins.
const PLAN_REVIEWER_MODEL = 'opus'
const PLAN_REVIEWER_AGENT = 'review-toolkit:plan-reviewer'

// Same trinary shape the unit-tests plan-review kind uses.
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

// STRUCTURED_OUTPUT_MANDATE is retired on this dispatcher: the explorer runs schema-free
// (see the explorer/emitter block below), so there is no forced call to mandate. The text
// lives on only in stall-probe.mjs's schema-forced control arm, which measures the old path.

// The PRIMARY stall fix for this dispatcher. Deliberately NOT code-review.mjs's wording: that one
// says a reviewer need not exhaustively read the diff to assert the ABSENCE of findings, which is
// right for a domain reviewer and wrong here — a plan reviewer's entire job is checking plan claims
// against the codebase, so telling it to stop grounding would gut the gate. This variant bounds HOW
// grounding happens, not WHETHER: batch the cheap existence checks, sample the expensive content
// reads, open a file only to support a finding you intend to raise.
//
// SHIPPING NOTE (#169): the explorer dispatch below sends this nudge NOWHERE — the measured
// 0/8-stall / 8/8-usable arm ran WITHOUT it, and the fix ships exactly what was measured. The
// constant stays defined verbatim because stall-probe.mjs's control arm copies it in lockstep
// (drift guard B5) and it remains available for future cost tuning behind a new measurement.
// Inventory completeness is explicitly exempted because planReviewerGate also serves the design
// FE-spec gate, whose rubric demands one row per rendered element with no silent drops — the same
// exhaustiveness class that justifies the scope-completeness-reviewer opt-out in code-review.mjs.
// Sampling THAT would defeat the gate, so the carve-out is stated rather than left to inference.
const BOUNDED_PLAN_GROUNDING =
  ' GROUND PROPORTIONATELY: verify that the paths and symbols the plan references exist using' +
  ' BATCHED checks (one ls/glob/grep covering many paths — not one Read per path). Read a file in' +
  ' full only when its CONTENT is needed to support a specific finding you intend to raise; a plan' +
  ' reference that merely needs to exist does not need a read. You do NOT have to open every' +
  ' referenced file to conclude the plan is grounded. This bounds how you ground, not whether — it' +
  ' never licenses skipping a completeness inventory this prompt asks for, nor asserting a claim' +
  ' you did not check. Stop exploring and emit StructuredOutput before your budget runs low.'

// Appended ONLY to a retry. Repeating an attempt verbatim is a foregone conclusion when the death
// was a turn-budget wall rather than a stochastic drop, and the two are indistinguishable from here
// (the runtime surfaces no turn count; the error string is identical). Rather than invent a
// discriminator that does not exist, make the second attempt materially different and cheaper.
// Measured motivation: one Stage-4 run burned 480k tokens and ~23 min re-deriving its first
// attempt's result across six dispatches that all died at 24-28 tool calls.
const RETRY_ESCALATION =
  ' RETRY CONTEXT: your previous attempt exhausted its turn budget exploring and never emitted a' +
  ' verdict, which counts as producing nothing. Explore MARKEDLY less this time — trust the plan' +
  ' text where you cannot cheaply verify it, and call StructuredOutput as early as you can defend,' +
  ' with partial findings if necessary. An early partial verdict is worth far more than no verdict.'

// --- explorer/emitter transport (the structural stall fix; #169) ---
// The stall class is `schema AND can-explore` in ONE agent. Measured on this exact dispatch
// (opus, k=8, 51-file-reference plan): schema-forced 7/8 deaths with 0 usable verdicts;
// schema-free text contract 0/8 with 8/8 usable at a third of the tokens. So the schema
// NEVER rides on the exploring dispatch. The explorer reviews schema-free and ends with a
// sentinel + fenced JSON block, parsed and validated in-script; only the transcription-only
// emitter agent (tools: [], maxTurns: 2 — it cannot explore) ever carries the schema, and
// only when a sentinel-bearing block failed to parse. A MISSING sentinel means the explorer
// truncated — that goes DARK (throw → the caller's existing infra path), never to the
// emitter: transcribing a truncated exploration would launder incompleteness into a
// valid-looking verdict.
const REVIEW_RESULT_EPILOGUE =
  '\n\nWrite your review, grounding as much as you need. Your FINAL output MUST end with' +
  ' this sentinel line followed by one fenced json block and NOTHING after it:\n\n' +
  'REVIEW_RESULT\n```json\n{ "verdict": "block|fix-and-go|pass", "findings": [ { "severity":' +
  ' "blocker|warning|note", "message": "...", "evidence": "...", "impact": "...",' +
  ' "suggestedFix": "..." } ], "summary": "..." }\n```'

// Last-match-wins: the agent may quote the instruction mid-prose (mutation-gate precedent).
const parseReviewResult = (text) => {
  const m = [...String(text ?? '').matchAll(/REVIEW_RESULT\s*```json\s*([\s\S]*?)```/g)]
  if (!m.length) return null
  try {
    return JSON.parse(m[m.length - 1][1])
  } catch {
    return null
  }
}

// In-script validator: the schema objects stop being dispatch schemas and become checkers —
// required keys plus enum membership, one level into array items. Downstream shapes unchanged.
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

// Rung 2: the transcription-only schema sink. Its input is complete in the prompt; with
// tools: [] and maxTurns: 2 it cannot exhaust a budget, so schema-forcing is safe here.
const emitStructured = (text, opts) =>
  // bounded-exploration-optout: structured-emitter -- tools:[] maxTurns:2 transcription sink;
  //   it has nothing to explore, which is precisely why it may carry the schema.
  agent(
    'Convert this completed review into the required structured object. Transcribe EXACTLY' +
      ' what the review states — never invent, drop, merge, soften or upgrade findings.' +
      '\n\n---REVIEW---\n' + String(text) + '\n---END---',
    { agentType: 'review-toolkit:structured-emitter', model: 'haiku', label: `${opts.label} (emit)`, phase: opts.phase, schema: opts.schema },
  )

// The dispatch ladder. Signature and name kept for the callers and drift guards:
// retries = 1 — one escalated re-explore on a contract miss (truncation or bad JSON can be
// stochastic), never a verbatim repeat.
const dispatchSchemaAgent = async (prompt, opts, retries = 1) => {
  let lastText = null
  for (let attempt = 0; attempt <= retries; attempt++) {
    const text = await agent(
      (attempt === 0 ? prompt : prompt + RETRY_ESCALATION) + REVIEW_RESULT_EPILOGUE,
      { agentType: opts.agentType, model: opts.model, label: attempt === 0 ? opts.label : `${opts.label} (retry ${attempt})`, phase: opts.phase },
    )
    const parsed = parseReviewResult(text)
    if (parsed && validateShape(parsed, opts.schema)) return parsed
    lastText = text
    log(`${opts.label}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : 'no sentinel'}) — attempt ${attempt + 1}/${retries + 1}`)
  }
  if (/REVIEW_RESULT/.test(String(lastText ?? ''))) {
    const emitted = await emitStructured(lastText, opts)
    if (emitted && validateShape(emitted, opts.schema)) return emitted
    throw new Error('text-contract: emitter produced an invalid shape — declared dark')
  }
  throw new Error('text-contract: explorer never produced the REVIEW_RESULT block (truncation) — declared dark')
}

// Wall-clock ceiling (mirrors code-review.mjs): race the full dispatch against a
// 15-minute timer; on timeout RESOLVE (never reject) to null so the caller maps
// it to an infraFailure gate entry. The orphaned agent keeps running but stops
// blocking the sequencer.
const CEILING_MS = 15 * 60 * 1000
const withCeiling = (dispatchPromise) =>
  Promise.race([
    dispatchPromise,
    new Promise((resolve) => setTimeout(() => resolve(null), CEILING_MS)),
  ])

// args (assembled in-session by Stage 4; applicability flags computed from
// state IN-SESSION so the script's skips are deterministic):
//   worktree     — ABSOLUTE worktree path (Stage 4 resolves the repo-relative
//                  state worktreePath against repo root — Workflow scripts
//                  cannot resolve a relative path themselves)
//   planPath     — the implementation plan (worktree-relative or absolute, passed through)
//   issue        — issue number, for labels/logging
//   workflowsDir — absolute path to this workflows/ dir (scripts cannot read
//                  files or introspect their own location — the caller supplies it)
//   design       — { enabled, provider, specPath } (designDriven runs; provider ∈
//                  claude-design|figma selects the spec rubric; specPath = the
//                  Stage-3 FE-spec artifact, e.g. docs/design-specs/<screen>-spec.md)
//   planGates    — EP-8 additive plan gates: [{ name, surface?, agent }] (Stage 4 passes the
//                  surface-applicable set; each runs after the built-in gates as an additive
//                  trinary plan reviewer — a block maps to plan-reviewer-block)
//   unitTests    — { enabled, planPath, modulesTouched, mutationTargets }
//   briefPath    — ABSOLUTE main-repo path to the Product-Essence Brief, or null.
//                  Never worktree-relative: the reviewer's cwd is the worktree and
//                  worktrees don't carry gitignored main-repo files.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  worktree,
  planPath,
  issue = '',
  workflowsDir,
  design = { enabled: false },
  unitTests = { enabled: false },
  planGates = [],
  briefPath = null,
  config = {},
} = a
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const planReviewerModel = modelOverrides['plan-reviewer'] || PLAN_REVIEWER_MODEL
if (!worktree || !planPath || !workflowsDir) {
  throw new Error('plan-review workflow: args.worktree, args.planPath and args.workflowsDir are required')
}
if (design.enabled && !design.specPath) {
  throw new Error('plan-review workflow: design.enabled requires design.specPath')
}

log(`plan-review: sequencing gates for ${issue ? `#${issue}` : planPath} in ${worktree}`)
phase('Plan Review')

// Gate ledger — all three gates ALWAYS appear (with skip markers when not run)
// so pipeline-retro can audit coverage from the return value alone.
const gates = []
let blocked = false
let budgetSkipped = false
let infra = false
let fixAndGo = false

const budgetLeft = () =>
  typeof budget === 'undefined' || !budget || !budget.total || budget.remaining() > 0

// Fold one gate's trinary result into the ledger + overall flags.
const recordVerdict = (gate, result) => {
  const verdict = result.verdict
  const findings = Array.isArray(result.findings) ? result.findings : []
  const entry = {
    gate,
    verdict,
    blockers: findings.filter((f) => f.severity === 'blocker').map((f) => f.message),
    warnings: findings.filter((f) => f.severity !== 'blocker').map((f) => f.message),
    summary: result.summary || '',
  }
  gates.push(entry)
  if (verdict === 'block') blocked = true
  if (verdict === 'fix-and-go') fixAndGo = true
}

const recordSkip = (gate, why) => gates.push({ gate, skipped: why })

const recordInfra = (gate, error) => {
  gates.push({ gate, infraFailure: true, error: String(error) })
  infra = true
}

// Should the next gate dispatch at all?
const skipReason = () => {
  if (blocked) return 'prior-block'
  if (budgetSkipped || !budgetLeft()) return 'budget'
  return null
}

// One plan-reviewer dispatch with the full staller stack; folds the result into
// the ledger. Gates 1 (plan) and 2 (design FE spec) share this — acme has no
// dedicated design-spec-reviewer agent (design-faithful-reviewer reviews CODE),
// so the FE-spec gate is a second plan-reviewer dispatch with the
// design-faithful-spec rubric (mirrors the pre-sequencer Stage-4 prose).
const planReviewerGate = async (gate, prompt) => {
  const why = skipReason()
  if (why) {
    if (why === 'budget') budgetSkipped = true
    recordSkip(gate, why)
    return
  }
  try {
    const result = await withCeiling(
      dispatchSchemaAgent(prompt, {
        agentType: PLAN_REVIEWER_AGENT,
        model: planReviewerModel,
        label: gate,
        phase: 'Plan Review',
        // bounded-exploration-optout: validator-reference -- this schema: key never rides a
        //   dispatch; dispatchSchemaAgent uses it for validateShape and the tool-less emitter only.
        schema: PLAN_REVIEW_SCHEMA,
      }),
    )
    if (result === null) {
      recordInfra(gate, `dispatch exceeded the wall-clock ceiling (${CEILING_MS}ms) — declared dark`)
    } else {
      recordVerdict(gate, result)
    }
  } catch (err) {
    recordInfra(gate, err)
  }
}

// EP-8: dispatch a consumer-registered plan-gate agent (an additive Stage-4 plan reviewer) with the
// SAME trinary schema + staller stack + ledger folding as the built-in gates. `agentType` is the
// consumer/companion-pack agent; `model` comes from modelOverrides (bare-keyed) or the 'sonnet' default.
const planGateAgent = async (gate, agentType, model, prompt) => {
  const why = skipReason()
  if (why) {
    if (why === 'budget') budgetSkipped = true
    recordSkip(gate, why)
    return
  }
  try {
    const result = await withCeiling(
      dispatchSchemaAgent(prompt, {
        agentType,
        model,
        label: gate,
        phase: 'Plan Review',
        // bounded-exploration-optout: validator-reference -- this schema: key never rides a
        //   dispatch; dispatchSchemaAgent uses it for validateShape and the tool-less emitter only.
        schema: PLAN_REVIEW_SCHEMA,
      }),
    )
    if (result === null) recordInfra(gate, `dispatch exceeded the wall-clock ceiling (${CEILING_MS}ms) — declared dark`)
    else recordVerdict(gate, result)
  } catch (err) {
    recordInfra(gate, err)
  }
}

// ---- Gate 1: plan-reviewer (direct agent dispatch) ----
await planReviewerGate(
  'plan-reviewer',
  `Review the implementation plan at \`${planPath}\`. ` +
    `All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
    `Verify plan grounding (every referenced path/symbol exists or is tagged [NEW]/[UNVERIFIED]), ` +
    `completeness against the required plan sections, consistency with codebase patterns, and ` +
    `missed downstream impacts. ` +
    (briefPath
      ? `A Product-Essence Brief exists at the absolute path \`${briefPath}\` (main repo, outside the worktree) — read it and verify the plan honors its binding intent: a plan step contradicting a resolved QUARANTINE decision or a settled user guardrail is a Blocker. `
      : '') +
    `Return trinary verdict (block | fix-and-go | pass) and findings.`,
)

// ---- Gate 2: design FE-spec review (designDriven runs only) ----
// Strictly serial after Gate 1, first-block short-circuits (matches the
// pre-sequencer "after plan-reviewer passes" ordering and saves tokens).
if (design.enabled) {
  // Provider-aware rubric (design axis): claude-design → design-faithful-spec template;
  // figma → figma-faithful-spec template. Same rubric-driven plan-reviewer dispatch for both
  // (symmetric with the claude-design path, which has no dedicated spec-reviewer agent); the
  // figma family also ships design-toolkit:figma-faithful-spec-reviewer for direct/manual review.
  const isFigma = design.provider === 'figma'
  const engineNote = isFigma ? 'Stage-3 figma-faithful engine' : 'Stage-3 design-sync engine'
  const templateNote = isFigma ? 'figma-faithful-spec' : 'design-faithful-spec'
  await planReviewerGate(
    'design-fe-spec',
    `Review the ${isFigma ? 'figma-faithful' : 'design-faithful'} FE spec artifact at \`${design.specPath}\` ` +
      `(produced by the ${engineNote}). All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
      `Apply the ${templateNote} template rules as the rubric: a completeness inventory with NO ` +
      `silent drops (one row per rendered element), a design→real-stack component map (@acme/ui / ` +
      `nearest apps/web analog / uplot / Server-Component fetch, acme token roles — never the ` +
      `handoff's raw token values), a behavioral/state contract with every inference flagged ` +
      `\`inferred\`, and any handoff-README stack-claim mismatch flagged. ` +
      `Return trinary verdict (block | fix-and-go | pass) and findings.`,
  )
} else {
  recordSkip('design-fe-spec', 'not-applicable')
}

// ---- Gate 3: unit-test plan review (strengthen surface only) ----
// Nested child workflow; it self-handles its own budget/staller and returns
// either { budgetExhausted } or { result } — fold both into the ledger.
if (unitTests.enabled) {
  const gate = 'unit-test-plan'
  const why = skipReason()
  if (why) {
    if (why === 'budget') budgetSkipped = true
    recordSkip(gate, why)
  } else {
    try {
      const ret = await workflow(
        { scriptPath: `${workflowsDir}/unit-tests.mjs` },
        {
          kind: 'plan-review',
          worktree,
          target: 'unit-test-plan-reviewer',
          issue,
          config,
          inputs: {
            planPath: unitTests.planPath || planPath,
            modulesTouched: unitTests.modulesTouched,
            mutationTargets: unitTests.mutationTargets,
          },
        },
      )
      if (ret && ret.budgetExhausted) {
        budgetSkipped = true
        recordSkip(gate, 'budget')
      } else if (ret && ret.result && ret.result.infraFailure) {
        recordInfra(gate, ret.result.summary || 'dispatch infra failure (survived inline retries)')
      } else if (ret && ret.result && ret.result.verdict) {
        recordVerdict(gate, ret.result)
      } else {
        recordInfra(gate, `unexpected child return shape: ${JSON.stringify(ret).slice(0, 200)}`)
      }
    } catch (err) {
      recordInfra(gate, err)
    }
  }
} else {
  recordSkip('unit-test-plan', 'not-applicable')
}

// ---- Gate 4+: consumer plan gates (EP-8 `planGates`) — additive, blocking, strictly serial ----
// Registered via config `planGates: [{name, surface, agent}]`; Stage 4 passes the applicable set
// (surface-filtered in-session). Each is an ADDITIVE plan reviewer — it can only make a passing
// plan-review block, never waive a built-in gate. A `block` folds into `blocked` and the stage maps
// it to `plan-reviewer-block` (no per-extension reason). First-block short-circuit applies.
for (const pg of Array.isArray(planGates) ? planGates : []) {
  const agentType = pg.agent
  const bareName = String(agentType).includes(':') ? String(agentType).split(':').pop() : String(agentType)
  const model = modelOverrides[bareName] || 'sonnet'
  await planGateAgent(
    `plan-gate:${pg.name}`,
    agentType,
    model,
    `Review the implementation plan at \`${planPath}\` for your domain concern` +
      (pg.surface ? ` (scope: \`${pg.surface}\`)` : '') +
      `. All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
      `You ADD a plan gate — surface real blockers in your domain; if the plan is fine for your concern, pass. ` +
      `Return trinary verdict (block | fix-and-go | pass) and findings.`,
  )
}

// Consolidated verdict. Precedence: block > infra > budget-skipped >
// fix-and-go > pass. A budget skip is NEVER folded into block (preserves the
// per-gate budgetExhausted contract: re-run when budget allows, no *-block
// reason); residual infra is NEVER mapped to a *-block reason either — the
// stage re-dispatches once, then surfaces it as infra.
const overall = blocked
  ? 'block'
  : infra
    ? 'infra'
    : budgetSkipped
      ? 'budget-skipped'
      : fixAndGo
        ? 'fix-and-go'
        : 'pass'

log(`plan-review: overall=${overall} (${gates.map((g) => `${g.gate}:${g.verdict || g.skipped || 'infra'}`).join(', ')})`)
return { planPath, issue, gates, overall }
