export const meta = {
  name: 'dev-pipeline-design-sync',
  description:
    "design-faithful produce/gate engine for the dev-pipeline. kind='produce' dispatches the design-faithful-spec skill to write the repo's FE spec artifact (implement:true → the design-faithful skill, which writes the repo's FE code + commits in-session, grounding app dir/tokens from .claude/second-shift/design-tokens/*.md); kind='gate' dispatches the FE review agents (design-faithful-reviewer / a11y-reviewer) in parallel and returns their trinary verdicts. Results are normalized into the same envelope shape as the review fan-out (code-review.mjs). Aggregate gate-verdict synthesis is NOT done here — it stays in the caller's session (#199 integration), mirroring code-review.mjs.",
  phases: [{ title: 'Design Sync', detail: 'produce (1 agent) or gate (1..N reviewer agents)' }],
}

// ── READ BOUNDARY (#196 decision) ───────────────────────────────────────────
// A Workflow script's runtime injects only agent()/parallel()/log()/phase()/budget + args —
// NO tool access and NO Node/fs. So this engine CANNOT call DesignSync, run extractContract, or
// do git/fs. The DesignSync read (get_project/list_files/get_file) + contract extraction AND any
// FE-app write+commit happen INSIDE the dispatched agent's session: design-faithful /
// design-faithful-spec (#197) carry the DesignSync tool and load the #195 design-faithful lib via
// their skill body. The engine only dispatches and normalizes.
//
// This SUPERSEDES the #195 header comments in lib/read-plan.mjs and lib/contract-types.mjs that
// name "#196's engine" as a possible DesignSync caller / direct importer of the lib — that path is
// not taken (a Workflow script cannot). Those stale comments get a one-line correction during #197,
// where the skill becomes the actual DesignSync caller. The engine's only tie to the #195 contract
// adapter is the fail-closed reason vocabulary below, which is INLINED (not imported) because the
// Workflow runtime does not guarantee ESM import: every sibling Workflow script (code-review.mjs /
// intake-review.mjs / unit-tests.mjs) imports nothing and uses only injected globals.
// design-sync-selftest.mjs drift-guards this inlined enum byte-for-byte against contract-types.mjs
// so it cannot rot.

// {agentType/skill: model} — the tier each dispatched agent runs at. Source of truth is each
// agent's own frontmatter (.claude/agents/<name>.md `model:`) once #197/#198 land; restated here
// because Workflow scripts can't read files and passing `model` explicitly guarantees the tier
// regardless of how agent() resolves an omitted one. Keep in lockstep with #197/#198 frontmatter.
// NOTE: the selftest drift-guards only FAIL_CLOSED_REASONS (against contract-types.mjs), NOT this
// table — there is no source of truth to diff it against until #197/#198 land, so it can drift
// silently. Update it by hand when those agents' frontmatter sets their model tiers.
// Keys are QUALIFIED plugin-shipped agent names (namespaces.md). args.config.reviewers
// .modelOverrides (bare-keyed) wins per agent.
const DESIGN_MODEL = {
  'design-toolkit:design-faithful-spec': 'opus', // produce: FE-spec reasoning (#197)
  'design-toolkit:design-faithful': 'sonnet', // produce + implement: code generation (#197)
  'design-toolkit:design-faithful-reviewer': 'sonnet', // gate (#198)
  'review-toolkit:a11y-reviewer': 'sonnet', // gate (#198)
}

// Bare (unqualified) agent name — tolerant of both `plugin:agent` and bare forms.
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// Inlined copy of the FAIL_CLOSED values in design-faithful/lib/contract-types.mjs (#195). NOT
// imported — see READ BOUNDARY. design-sync-selftest.mjs asserts this list byte-matches the
// contract-types.mjs FAIL_CLOSED block (drift-guard in BOTH directions: a 5th reason added there,
// or one dropped here, fails the selftest).
const FAIL_CLOSED_REASONS = [
  'design-source-unreachable',
  'project-type-mismatch',
  'file-too-large',
  'batch-overflow',
]

// Produce result contract (PROVISIONAL — #197's design-faithful-spec / design-faithful build their
// StructuredOutput payloads to this shape). Permissive (additionalProperties) so the agent does not
// burn retries on shape; only `summary` is required. `failClosed` is the agent's
// source-unreachable / DesignSync-limit signal (reason ∈ FAIL_CLOSED_REASONS) which the engine
// surfaces as a clean skip, never a block/error.
const PRODUCE_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['summary'],
  properties: {
    summary: { type: 'string' },
    artifactPath: { type: 'string' }, // spec path written (implement:false)
    committed: { type: 'boolean' }, // implement:true — did the agent commit
    changedFiles: { type: 'array', items: { type: 'string' } },
    failClosed: {
      type: 'object',
      additionalProperties: true,
      required: ['reason'],
      properties: { reason: { type: 'string' }, detail: { type: 'string' } },
    },
  },
}

// Gate result contract (PROVISIONAL — #198's design-faithful-reviewer / a11y-reviewer build to
// this). Trinary verdict. The findings severity enum matches code-review.mjs's FINDINGS_SCHEMA
// (blocker|major|minor|nit), NOT unit-tests.mjs's (blocker|warning|note) — #198 reviewers use this
// one. `failClosed` lets a reviewer that cannot read the design source signal it instead of
// emitting a false block.
const GATE_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['pass', 'warn', 'block'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'description', 'confidence'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          file: { type: 'string' },
          line: { type: ['integer', 'string', 'null'] },
          title: { type: 'string' },
          description: { type: 'string' },
          confidence: { type: 'integer' },
        },
      },
    },
    failClosed: {
      type: 'object',
      additionalProperties: true,
      required: ['reason'],
      properties: { reason: { type: 'string' }, detail: { type: 'string' } },
    },
  },
}

// --- StructuredOutput-staller mitigation (shared posture with unit-tests.mjs / code-review.mjs) ---
// A schema-forced agent can end its turn on prose WITHOUT the StructuredOutput call. Two defenses:
// a non-negotiable mandate appended to every prompt, plus an inline retry on the StructuredOutput
// death class.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

// Only the StructuredOutput-death error class is retried; genuine tool/permission errors throw
// straight through. Brittle substring match — the only signal the runtime surfaces (if the runtime
// ever changes the message the retry stops firing and degrades to the unretried path).
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

// One schema'd dispatch with up to `retries` INLINE retries on a StructuredOutput death. Resolves
// to the agent result on success; throws the last error after exhausting retries (the produce
// caller maps that throw to its infraFailure envelope). Used for the single-agent produce path.
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

// If the agent reported a KNOWN fail-closed reason, return the validated marker; else null. Only a
// reason in FAIL_CLOSED_REASONS counts — an unknown string is NOT treated as fail-closed, so it can
// never masquerade as a clean skip and mask a real verdict.
const normalizeFailClosed = (result) => {
  const fc = result && result.failClosed
  if (fc && typeof fc.reason === 'string' && FAIL_CLOSED_REASONS.includes(fc.reason)) {
    return fc.detail === undefined ? { reason: fc.reason } : { reason: fc.reason, detail: fc.detail }
  }
  return null
}

// args (assembled in-session by the dispatching Stage / #199):
//   kind       — 'produce' | 'gate' (required)
//   issue      — for logging
//   --- produce ---
//   implement  — false → write the FE spec; true → implement code + commit (default false)
//   projectId  — DesignSync handoff project id (opened BY ID; required)
//   screen     — screen/component name, e.g. 'detail' (required)
//   specPath   — target path for the spec artifact (implement:false; optional)
//   --- gate ---
//   reviewers  — agentType[] (default ['design-faithful-reviewer','a11y-reviewer'])
//   worktree   — ABSOLUTE worktree path the reviewers run git against (required)
//   base, head — git range the reviewers diff (required)
//   changedFiles — string[] context for the prompt
//   prContext  — free-text context
// `args` arrives as the value passed to Workflow's `args` input. Defensive: it may be an object,
// or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  kind,
  issue = '',
  implement = false,
  projectId,
  screen,
  specPath,
  reviewers = ['design-toolkit:design-faithful-reviewer', 'review-toolkit:a11y-reviewer'],
  worktree,
  base,
  head,
  changedFiles = [],
  prContext = '',
  config = {},
} = a
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}

if (kind !== 'produce' && kind !== 'gate') {
  throw new Error("design-sync workflow: args.kind must be 'produce' or 'gate'")
}
if (kind === 'produce' && (!projectId || !screen)) {
  throw new Error('design-sync produce: args.projectId and args.screen are required')
}
// F26: implement:true writes code and COMMITS. Without an explicit worktree the
// design-faithful skill works in the session's default checkout and the commits
// land on the wrong branch. Fail closed rather than silently corrupt the ticket
// branch. (implement:false only writes a spec artifact — worktree stays optional.)
if (kind === 'produce' && implement && !worktree) {
  throw new Error('design-sync produce: args.worktree is required when implement:true — without it the design-faithful skill writes/commits to the session default checkout instead of the ticket worktree (F26)')
}
if (kind === 'gate') {
  if (!worktree || !base || !head) {
    throw new Error('design-sync gate: args.worktree, args.base and args.head are required')
  }
  if (!Array.isArray(reviewers) || reviewers.length === 0) {
    throw new Error('design-sync gate: args.reviewers must be a non-empty array of agentType strings')
  }
}

// Workflow runtime globals used below — injected by the runtime, not imported: log(), phase(),
// parallel(), agent(), budget. See the Workflow tool API.
log(
  `design-sync: ${kind}` +
    (kind === 'produce'
      ? ` (${implement ? 'implement' : 'spec'}, project ${projectId}, screen ${screen})`
      : ` (${reviewers.join(' + ')})`) +
    (issue ? ` (#${issue})` : ''),
)
phase('Design Sync')

// Cost discipline — same posture as code-review.mjs / unit-tests.mjs: the runtime enforces the
// operator's turn token budget across every agent() call and makes agent() throw once spent. Skip
// cleanly if already exhausted rather than dispatching throwing calls. NOT a fake block/error: the
// caller must not map budgetExhausted to a gate `block` or a produce failure.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping design-sync dispatch')
    return { kind, budgetExhausted: true }
  }
}

if (kind === 'produce') {
  const skillBare = implement ? 'design-faithful' : 'design-faithful-spec'
  const skill = `design-toolkit:${skillBare}`
  const reasonList = FAIL_CLOSED_REASONS.join(', ')
  // args.worktree: anchor ALL repo reads/writes/commits to the pipeline worktree.
  // REQUIRED when implement:true (enforced fail-closed above, F26) — without it the
  // dispatched agent works in the session's default checkout and commits land on the
  // wrong branch. Optional for implement:false (spec-only, no commits).
  const worktreeClause = worktree
    ? ` All repository reads, writes, and commits MUST target the worktree at \`${worktree}\` ` +
      `(absolute path) — never the default checkout.`
    : ''
  const prompt =
    `Load the ${skill} skill.${worktreeClause} Open the Claude Design handoff project by id \`${projectId}\` via the ` +
    `DesignSync tool (get_project → list_files → get_file), sanitize each file, and extract the ` +
    `design contract using the design-faithful lib (#195). Then ` +
    (implement
      ? `implement the "${screen}" screen/component in the repo's FE app. The skill grounds the FE app ` +
        `dir, primitives package, and token/component vocabulary from \`.claude/second-shift/design-tokens/*.md\` ` +
        `(or conservative discovery when that file is absent) — mirror the nearest analog, reuse the repo's ` +
        `real components and tokens, live-render self-verify against the bundled screenshot — and commit per ` +
        `repo convention (bot identity). Return { summary, committed, changedFiles }.`
      : `produce the repo's FE spec for the "${screen}" screen` +
        (specPath ? ` and write it to \`${specPath}\`` : '') +
        `. Return { summary, artifactPath }.`) +
    ` If the design source is unreachable or exceeds a DesignSync limit, do NOT guess — return ` +
    `{ summary, failClosed: { reason } } where reason is one of: ${reasonList}.` +
    STRUCTURED_OUTPUT_MANDATE

  const opts = {
    agentType: skill,
    model: modelOverrides[skillBare] || DESIGN_MODEL[skill] || 'sonnet',
    label: skill,
    phase: 'Design Sync',
    schema: PRODUCE_SCHEMA,
  }

  // `infraFailure: true` marks a dispatch/StructuredOutput death that survived the inline retries,
  // so the caller can tell it apart from a real agent result — never a produce "failure" verdict.
  const result = await dispatchSchemaAgent(prompt, opts).catch((err) => ({
    summary: 'agent dispatch failed: ' + String(err),
    infraFailure: true,
  }))

  // A known fail-closed reason is surfaced as a top-level clean-skip marker (parallel to
  // budgetExhausted) so the caller branches on it without a real block/error.
  const failClosed = normalizeFailClosed(result)
  return failClosed ? { kind, implement, failClosed } : { kind, implement, result }
}

// kind === 'gate' — parallel reviewer fan-out, mirroring code-review.mjs's dispatchReviewer:
// forward (do not drop) a reviewer that errored so the caller can surface it; a reviewer that died
// without StructuredOutput AND failed its one retry carries { retried, failed }; a reviewer that
// reported a known fail-closed reason carries { failClosed } so synthesis reads it as a clean skip,
// not a false `block`.
const fileList = changedFiles.length ? changedFiles.join(', ') : '(see diff)'
const range = `${base}..${head}`
const reasonList = FAIL_CLOSED_REASONS.join(', ')

const dispatchGateReviewer = async (agentType) => {
  const model = modelOverrides[bare(agentType)] || DESIGN_MODEL[agentType] || 'sonnet'
  const prompt =
    `Review this FE design change in your domain (${agentType}). ` +
    `Diff scope: \`git -C ${worktree} diff ${range}\`. Changed files: ${fileList}.` +
    (prContext ? ` Context: ${prContext}.` : '') +
    ` Return a trinary verdict (pass | warn | block) and a deduplicated list of findings ` +
    `(severity blocker/major/minor/nit, file, line, confidence 0-100). Ignore stylistic issues ` +
    `handled by formatter/linter. If you cannot read the design source to compare against, return ` +
    `{ verdict, findings, failClosed: { reason } } with reason one of: ${reasonList} — rather than ` +
    `a false block.` +
    STRUCTURED_OUTPUT_MANDATE
  const annotate = (result) => {
    const failClosed = normalizeFailClosed(result)
    return failClosed ? { agentType, result, failClosed } : { agentType, result }
  }
  try {
    const result = await agent(prompt, { agentType, model, label: agentType, phase: 'Design Sync', schema: GATE_SCHEMA })
    return annotate(result)
  } catch (err) {
    if (!isNoStructuredOutputError(err)) {
      return { agentType, result: null, error: String(err) }
    }
    log(`${agentType}: died without StructuredOutput — retrying once`)
    try {
      const result = await agent(prompt, {
        agentType,
        model,
        label: `${agentType} (retry)`,
        phase: 'Design Sync',
        schema: GATE_SCHEMA,
      })
      return annotate(result)
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

const results = await parallel(reviewers.map((agentType) => () => dispatchGateReviewer(agentType)))
return { kind, range, worktree, reviewers: results.filter(Boolean) }
