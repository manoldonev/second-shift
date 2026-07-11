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

// --- StructuredOutput-staller mitigation (the full reused stack) ---
// plan-reviewer is a heavy exploration agent (reads the plan + greps the
// codebase); same layered defenses as code-review.mjs / unit-tests.mjs:
// output-first framing + non-negotiable mandate, inline retry on the
// StructuredOutput death class, and a wall-clock ceiling on the dispatch.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

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
      dispatchSchemaAgent(prompt + STRUCTURED_OUTPUT_MANDATE, {
        agentType: PLAN_REVIEWER_AGENT,
        model: planReviewerModel,
        label: gate,
        phase: 'Plan Review',
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
