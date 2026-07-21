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

// --- explorer/emitter transport (the structural stall fix; #169) ---
// Explorers dispatch schema-FREE and end with a sentinel + fenced JSON block parsed here;
// the schema objects become in-script validators, and only the transcription-only
// structured-emitter agent (tools: [], maxTurns: 2) ever carries a schema — fired solely
// when a sentinel-bearing block failed to parse. Missing sentinel = truncation = dark.
// Measured basis: plan-reviewer opus k=8 — schema-forced 7/8 deaths 0 usable; schema-free
// 0/8, 8/8 usable at a third of the tokens, detection parity 6.75 vs 6.63.
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
    { agentType: 'review-toolkit:structured-emitter', model: 'haiku', label: `${opts.label} (emit)`, phase: 'Design Sync', schema: opts.schema },
  )

// The contract-miss dispatch ladder. Name and signature kept for callers: one escalated
// re-explore on a miss, then the emitter (sentinel present) or a dark throw. The caller's
// existing catch maps the throw to its infraFailure envelope, exactly as before.
const dispatchSchemaAgent = async (prompt, opts, retries = 1) => {
  let lastText = null
  for (let attempt = 0; attempt <= retries; attempt++) {
    const text = await agent(prompt + opts.epilogue, {
      ...(opts.agentType ? { agentType: opts.agentType } : {}),
      model: opts.model,
      label: attempt === 0 ? opts.label : `${opts.label} (retry ${attempt})`,
      phase: opts.phase,
    })
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
//   base, head — git refs bounding the review: branch, ref, or SHA (required). Rendered
//                THREE-DOT (`<base>...<head>`) = merge-base semantics, so an advanced base
//                branch never leaks its own commits into the reviewed diff (#130). An
//                explicit merge-base SHA is unaffected (base already an ancestor of head).
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
    `{ summary, failClosed: { reason } } where reason is one of: ${reasonList}.`

  const opts = {
    // bounded-exploration-optout: design produce -- a produce dispatch WRITES a spec or
    //   implements a screen; "emit early without opening files" is semantically wrong for work
    //   whose whole output depends on reading the design and the surrounding code.
    agentType: skill,
    model: modelOverrides[skillBare] || DESIGN_MODEL[skill] || 'sonnet',
    label: skill,
    phase: 'Design Sync',
    // bounded-exploration-optout: validator-reference -- feeds validateShape and the emitter;
    //   the explorer dispatch itself is schema-free (#169).
    schema: PRODUCE_SCHEMA,
    epilogue:
      '\n\nAfter completing the work, your FINAL output MUST end with this sentinel line followed' +
      ' by one fenced json block and NOTHING after it:\n\n' +
      'REVIEW_RESULT\n```json\n{ "summary": "...", "artifactPath": "...", "committed": false,' +
      ' "changedFiles": [], "failClosed": { "reason": "...", "detail": "..." } }\n```' +
      '\n(omit failClosed entirely on success)',
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
// THREE-DOT is load-bearing (#130) — see the base/head contract above.
const range = `${base}...${head}`
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
  // Explorer/emitter ladder — dark-marker shapes unchanged.
  const GATE_EPILOGUE =
    '\n\nWrite your review. Your FINAL output MUST end with this sentinel line followed by one' +
    ' fenced json block and NOTHING after it:\n\n' +
    'REVIEW_RESULT\n```json\n{ "verdict": "pass|warn|block", "findings": [ { "severity":' +
    ' "blocker|major|minor|nit", "file": "...", "line": 0, "title": "...", "description": "...",' +
    ' "confidence": 0 } ], "failClosed": { "reason": "..." } }\n```' +
    '\n(omit failClosed entirely unless you could not read the design source)'
  let lastText = null
  for (let attempt = 0; attempt < 2; attempt++) {
    let text
    try {
      text = await agent(prompt + GATE_EPILOGUE, {
        agentType,
        model,
        label: attempt === 0 ? agentType : `${agentType} (retry)`,
        phase: 'Design Sync',
      })
    } catch (err) {
      return attempt === 0
        ? { agentType, result: null, error: String(err) }
        : { agentType, result: null, error: `retry failed: ${err}`, retried: true, failed: true }
    }
    const parsed = parseReviewResult(text)
    if (parsed && validateShape(parsed, GATE_SCHEMA)) return annotate(parsed)
    lastText = text
    log(`${agentType}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : 'no sentinel'})${attempt === 0 ? ' — retrying once' : ''}`)
  }
  if (/REVIEW_RESULT/.test(String(lastText ?? ''))) {
    try {
      // bounded-exploration-optout: validator-reference -- this schema: key parameterizes the
      //   emitter helper (whose own dispatch site carries the structured-emitter marker).
      const emitted = await emitStructured(lastText, { label: agentType, schema: GATE_SCHEMA })
      if (emitted && validateShape(emitted, GATE_SCHEMA)) return annotate(emitted)
    } catch (emitErr) {
      return { agentType, result: null, error: `emit failed: ${emitErr}`, retried: true, failed: true }
    }
  }
  return {
    agentType,
    result: null,
    error: 'text-contract: explorer never produced a parseable REVIEW_RESULT block after retry — declared dark',
    retried: true,
    failed: true,
  }
}

const results = await parallel(reviewers.map((agentType) => () => dispatchGateReviewer(agentType)))
return { kind, range, worktree, reviewers: results.filter(Boolean) }
