export const meta = {
  name: 'dev-pipeline-intake-review',
  description:
    "Stage 1 intake evidence-gathering fan-out for the dev-pipeline. Dispatches spec-reviewer and codebase-explorer as parallel agent() calls and returns their rationale-carrying structured findings. Critical evaluation, gap resolution, dependency analysis, and the decomposition decision are NOT done here — they stay in the intake-orchestrator session on the caller's model. This mirrors workflows/code-review.mjs (the Stage 8 reviewer fan-out).",
  phases: [{ title: 'Intake', detail: 'spec-reviewer + codebase-explorer in parallel' }],
}

// {agentType: model} — the tier each intake sub-agent runs at. Source of truth is
// each plugin-shipped agent's frontmatter (`model:`); restated here because Workflow
// scripts can't read files, and passing `model` explicitly guarantees the intended
// tier regardless of how agent() resolves an omitted model. Change a sub-agent's tier
// in its agent frontmatter AND here, in lockstep. Keys are QUALIFIED (namespaces.md);
// args.config.reviewers.modelOverrides (bare-keyed) wins per agent.
const INTAKE_MODEL = {
  'review-toolkit:spec-reviewer': 'opus',
  'review-toolkit:codebase-explorer': 'sonnet',
}

// Bare (unqualified) agent name — tolerant of both `plugin:agent` and bare forms.
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// spec-reviewer structured contract. The orchestrator's value is critically
// evaluating these findings and dismissing false positives — it CANNOT do that
// from {finding, confidence} alone, so `rationale` is REQUIRED and must be
// substantive (the agent's reasoning / how it verified), never a one-liner.
// Kept permissive (additionalProperties) so the agent doesn't burn retries on
// shape; only the load-bearing fields are required.
const SPEC_REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['verdict', 'findings'],
  properties: {
    verdict: {
      type: 'string',
      enum: ['implementable', 'needs-revision', 'blocked'],
    },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'claim', 'rationale', 'confidence'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'warning', 'note'] },
          category: { type: 'string' },
          claim: { type: 'string' },
          impact: { type: 'string' },
          // Load-bearing: the evidence / reasoning the orchestrator needs to
          // accept or DISMISS this finding. Never a one-liner.
          rationale: { type: 'string' },
          suggestion: { type: 'string' },
          confidence: { type: 'integer' },
          file: { type: 'string' },
          line: { type: ['integer', 'string', 'null'] },
        },
      },
    },
  },
}

// codebase-explorer structured contract. Its sections are already structured;
// the schema captures them. `findings[].evidence` (file:line) is the
// rationale-carrying field — it lets the orchestrator verify a claimed
// dependency/impact rather than trust it.
const CODEBASE_EXPLORER_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['modulesAffected', 'estimatedScope'],
  properties: {
    modulesAffected: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['module'],
        properties: {
          module: { type: 'string' },
          filesToCreate: { type: 'array', items: { type: 'string' } },
          filesToModify: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    crossModuleDependencies: { type: 'array', items: { type: 'string' } },
    existingPatterns: { type: 'array', items: { type: 'string' } },
    estimatedScope: {
      type: 'object',
      additionalProperties: true,
      properties: {
        filesToCreate: { type: 'integer' },
        filesToModify: { type: 'integer' },
        modulesTouched: { type: 'integer' },
      },
    },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['observation', 'evidence'],
        properties: {
          observation: { type: 'string' },
          evidence: { type: 'string' }, // file:line
          confidence: { type: 'integer' },
        },
      },
    },
  },
}

// args (assembled in-session by Stage 1 intake):
//   issue        — GitHub issue number (drives the prompts)
//   issueBody    — the full issue body text (so the sub-agents don't re-fetch)
//   referencedDocs — optional array of {path, content} the orchestrator pre-read (max 5)
//   agents       — optional subset to dispatch (default both). Bug/chore intake passes
//                  ['spec-reviewer'] for the spec-review-only path.
//   readRoot     — optional ABSOLUTE path to the Stage-1 pinned read surface (the
//                  detached origin/<base> worktree from Step 1.P). When set, every
//                  sub-agent is instructed to perform ALL codebase reads under it and
//                  never the main checkout (whose branch/dirty state must not inform
//                  intake — see stages/1-intake.md Step 1.P / issue #59). Empty = the
//                  legacy unpinned behavior (reads resolve against the session CWD).
// `args` arrives as the value passed to Workflow's `args` input. Defensive: it may
// be an object, or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  issue,
  issueBody = '',
  referencedDocs = [],
  agents = ['review-toolkit:spec-reviewer', 'review-toolkit:codebase-explorer'],
  readRoot = '',
  config = {},
} = a
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
if (!issue) {
  throw new Error('intake-review workflow: args.issue (GitHub issue number) is required')
}
if (!issueBody) {
  throw new Error('intake-review workflow: args.issueBody is required (the sub-agents reason over it)')
}
if (!Array.isArray(agents) || agents.length === 0) {
  throw new Error('intake-review workflow: args.agents must be a non-empty array (default ["spec-reviewer","codebase-explorer"])')
}

// Workflow runtime globals used below — injected by the runtime, not imported:
// log(), phase(), parallel(), agent(). See the Workflow tool API.
const docsNote = referencedDocs.length
  ? ` Referenced docs already read (do not re-fetch): ${referencedDocs.map((d) => d.path).join(', ')}.`
  : ''

// Stage-1 read-surface pin (issue #59): prefixed to EVERY dispatch prompt so the
// sub-agents ground against origin/<base>, not the operator's checkout. Leads the
// prompt (not appended) so it is the first instruction the agent reads.
const readRootNote = readRoot
  ? `PINNED READ SURFACE (read first): perform ALL codebase reads (Read/Grep/Glob/Bash) inside ${readRoot} — ` +
    `a pinned checkout of the configured base branch. Do NOT read from the main repo checkout: its branch and ` +
    `working-tree state are unrelated to this analysis and must not inform it. `
  : ''

log(`intake-review: ${agents.join(' + ')} for issue #${issue}`)
phase('Intake')

// Cost discipline — same posture as code-review.mjs: the runtime enforces the
// operator's turn token budget across every agent() call and makes agent() throw
// once spent. Skip cleanly if already exhausted rather than dispatching throwing calls.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left before fan-out`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping intake fan-out')
    // budgetExhausted distinguishes this clean skip from a sub-agent crash: both
    // leave specReview null, but only a crash should trigger needs-intake-review.
    return { issue, specReview: null, codebaseExplorer: null, budgetExhausted: true }
  }
}

// Tell the sub-agent to emit the structured verdict FIRST, before any prose. Mirrors
// code-review.mjs: a Sonnet agent that writes its full prose write-up before the
// structured call can exhaust its turn budget and die without ever calling
// StructuredOutput. The agents' own contract (reviewer-baseline / their agent files)
// makes structured the sole output under schema dispatch; this nudge reinforces it at
// dispatch time.
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
    { agentType: 'review-toolkit:structured-emitter', model: 'haiku', label: `${opts.label} (emit)`, phase: 'Intake', schema: opts.schema },
  )


// PROPHYLACTIC, not a measured fix — and the distinction is load-bearing. Both agents in this file
// emitted cleanly in the run that motivated the wider change (spec-reviewer 18 tool calls,
// codebase-explorer 12, against the 24-28 range where dispatches die), so there is no stall here to
// cure and no before/after rate to cite. It ships for uniform coverage, so the lint's rule has no
// silent hole, and it is exempt from the "a nudge lands with its measurement" guardrail precisely
// because it is not claimed as a fix. If it ever needs defending, the probe's avgFindings
// comparison — not a stall rate — is the instrument.
const BOUNDED_SPEC_GROUNDING =
  ' GROUND PROPORTIONATELY: the issue body is your primary artifact. Consult the codebase to check' +
  ' a specific claim you intend to raise as a finding — not to build general familiarity, and not' +
  ' to prove the absence of findings across the repo. Stop exploring and emit your final result' +
  ' before your budget runs low.'

// Per-entry dispositions. These two descriptors take OPPOSITE treatment yet share one agent() call
// downstream — the shape that forced the lint grammar's `delegated` verb (see dispatchIntake).
const DISPATCH = [
  {
    // bounded-exploration-optout: validator-reference -- consumed as d.schema by validateShape and
    //   the emitter; the explorer dispatch is schema-free. Its bounding text (BOUNDED_SPEC_GROUNDING)
    //   rides in the prompt below.
    agentType: 'review-toolkit:spec-reviewer',
    schema: SPEC_REVIEW_SCHEMA,
    prompt:
      readRootNote +
      `Review the spec for GitHub issue #${issue} for implementability.${docsNote} ` +
      `Issue body:\n\n${issueBody}\n\n` +
      `Return your verdict and a list of findings. For EACH finding the \`rationale\` field is ` +
      `mandatory and must carry your actual reasoning / how you verified it (file:line where ` +
      `relevant) — the orchestrator uses it to accept or dismiss the finding, so a bare ` +
      `conclusion without rationale is unusable.` +
      BOUNDED_SPEC_GROUNDING,
    epilogue:
      '\n\nWrite your review. Your FINAL output MUST end with this sentinel line followed by one' +
      ' fenced json block and NOTHING after it:\n\n' +
      'REVIEW_RESULT\n```json\n{ "verdict": "implementable|needs-revision|blocked", "findings":' +
      ' [ { "severity": "blocker|warning|note", "category": "...", "claim": "...", "impact": "...",' +
      ' "rationale": "...", "suggestion": "...", "confidence": 0, "file": "...", "line": 0 } ] }\n```',
  },
  {
    // bounded-exploration-optout: validator-reference -- consumed as d.schema by validateShape and
    //   the emitter; the explorer dispatch is schema-free. No bounding text either: mapping the
    //   impact surface IS this agent's deliverable (same class as scope-completeness-reviewer).
    agentType: 'review-toolkit:codebase-explorer',
    schema: CODEBASE_EXPLORER_SCHEMA,
    prompt:
      readRootNote +
      `Map the impact surface for GitHub issue #${issue}.${docsNote} ` +
      `Issue body:\n\n${issueBody}\n\n` +
      `Return modulesAffected (files to create/modify), crossModuleDependencies, existingPatterns, ` +
      `and estimatedScope. For any non-obvious claim, include it in \`findings\` with concrete ` +
      `\`evidence\` (file:line) so the orchestrator can verify rather than trust it.`,
    epilogue:
      '\n\nWrite your report. Your FINAL output MUST end with this sentinel line followed by one' +
      ' fenced json block and NOTHING after it:\n\n' +
      'REVIEW_RESULT\n```json\n{ "modulesAffected": [ { "module": "...", "filesToCreate": [],' +
      ' "filesToModify": [] } ], "crossModuleDependencies": [], "existingPatterns": [],' +
      ' "estimatedScope": { "filesToCreate": 0, "filesToModify": 0, "modulesTouched": 0 },' +
      ' "findings": [ { "observation": "...", "evidence": "file:line", "confidence": 0 } ] }\n```',
  },
]

// Tolerant of both qualified and bare names in the caller-supplied `agents` list.
const selected = DISPATCH.filter((d) => agents.some((x) => bare(x) === bare(d.agentType)))
if (selected.length === 0) {
  throw new Error(`intake-review workflow: no known agent in ${JSON.stringify(agents)} (known: spec-reviewer, codebase-explorer)`)
}

// The StructuredOutput death class is structurally impossible here (#169): explorers carry
// no schema, and the emitter cannot explore. The contract-miss ladder in dispatchIntake owns retry.

// One intake dispatch with ONE automatic retry when it dies without StructuredOutput.
// The retry runs INLINE in this task closure (awaits a second agent() before resolving)
// so it adds no new task to parallel() and inherits the concurrency cap. This gives
// intake the same protection code-review already had — the #199 run lost a spec-reviewer
// to a StructuredOutput death this retry would have recovered.
//   - success (first or second attempt) → { agentType, result }
//   - non-StructuredOutput rejection     → { agentType, result: null, error } (no retry;
//     forwarded so the orchestrator can fall back to its own reading and note the gap)
//   - StructuredOutput death twice        → { agentType, result: null, error,
//     retried: true, failed: true } — flagged so the orchestrator cannot mistake a dead
//     sub-agent for a clean result.
const dispatchIntake = async (d) => {
  const opts = {
    agentType: d.agentType,
    model: modelOverrides[bare(d.agentType)] || INTAKE_MODEL[d.agentType] || 'sonnet',
    label: d.agentType,
    phase: 'Intake',
    // bounded-exploration-optout: validator-reference -- pass-through of the per-descriptor
    //   validator schema; the explorer dispatch in the ladder below is schema-free.
    schema: d.schema,
  }
  // Explorer/emitter ladder — dark-marker shapes unchanged (the orchestrator keys on
  // { result: null } and { retried: true, failed: true }).
  let lastText = null
  for (let attempt = 0; attempt < 2; attempt++) {
    let text
    try {
      text = await agent(d.prompt + d.epilogue, {
        agentType: opts.agentType,
        model: opts.model,
        label: attempt === 0 ? d.agentType : `${d.agentType} (retry)`,
        phase: opts.phase,
      })
    } catch (err) {
      return attempt === 0
        ? { agentType: d.agentType, result: null, error: String(err) }
        : { agentType: d.agentType, result: null, error: `retry failed: ${err}`, retried: true, failed: true }
    }
    const parsed = parseReviewResult(text)
    if (parsed && validateShape(parsed, d.schema)) return { agentType: d.agentType, result: parsed }
    lastText = text
    log(`${d.agentType}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : 'no sentinel'})${attempt === 0 ? ' — retrying once' : ''}`)
  }
  if (/REVIEW_RESULT/.test(String(lastText ?? ''))) {
    try {
      // bounded-exploration-optout: validator-reference -- this schema: key parameterizes the
      //   emitter helper (whose own dispatch site carries the structured-emitter marker).
      const emitted = await emitStructured(lastText, { label: d.agentType, schema: d.schema })
      if (emitted && validateShape(emitted, d.schema)) return { agentType: d.agentType, result: emitted }
    } catch (emitErr) {
      return { agentType: d.agentType, result: null, error: `emit failed: ${emitErr}`, retried: true, failed: true }
    }
  }
  return {
    agentType: d.agentType,
    result: null,
    error: 'text-contract: explorer never produced a parseable REVIEW_RESULT block after retry — declared dark',
    retried: true,
    failed: true,
  }
}

const results = await parallel(selected.map((d) => () => dispatchIntake(d)))

const byType = (t) => results.find((r) => r && bare(r.agentType) === bare(t)) || { result: null }
return {
  issue,
  specReview: byType('spec-reviewer'),
  codebaseExplorer: byType('codebase-explorer'),
}
