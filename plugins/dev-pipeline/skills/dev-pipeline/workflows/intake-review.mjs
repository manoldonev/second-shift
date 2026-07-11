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
// `args` arrives as the value passed to Workflow's `args` input. Defensive: it may
// be an object, or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  issue,
  issueBody = '',
  referencedDocs = [],
  agents = ['review-toolkit:spec-reviewer', 'review-toolkit:codebase-explorer'],
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
const STRUCTURED_OUTPUT_FIRST =
  ' Call StructuredOutput FIRST with your verdict and findings, before any prose' +
  ' explanation — do not write a long write-up before the structured call.'

const DISPATCH = [
  {
    agentType: 'review-toolkit:spec-reviewer',
    schema: SPEC_REVIEW_SCHEMA,
    prompt:
      `Review the spec for GitHub issue #${issue} for implementability.${docsNote} ` +
      `Issue body:\n\n${issueBody}\n\n` +
      `Return your verdict and a list of findings. For EACH finding the \`rationale\` field is ` +
      `mandatory and must carry your actual reasoning / how you verified it (file:line where ` +
      `relevant) — the orchestrator uses it to accept or dismiss the finding, so a bare ` +
      `conclusion without rationale is unusable.` +
      STRUCTURED_OUTPUT_FIRST,
  },
  {
    agentType: 'review-toolkit:codebase-explorer',
    schema: CODEBASE_EXPLORER_SCHEMA,
    prompt:
      `Map the impact surface for GitHub issue #${issue}.${docsNote} ` +
      `Issue body:\n\n${issueBody}\n\n` +
      `Return modulesAffected (files to create/modify), crossModuleDependencies, existingPatterns, ` +
      `and estimatedScope. For any non-obvious claim, include it in \`findings\` with concrete ` +
      `\`evidence\` (file:line) so the orchestrator can verify rather than trust it.` +
      STRUCTURED_OUTPUT_FIRST,
  },
]

// Tolerant of both qualified and bare names in the caller-supplied `agents` list.
const selected = DISPATCH.filter((d) => agents.some((x) => bare(x) === bare(d.agentType)))
if (selected.length === 0) {
  throw new Error(`intake-review workflow: no known agent in ${JSON.stringify(agents)} (known: spec-reviewer, codebase-explorer)`)
}

// The Workflow runtime rejects agent() with a message containing the substring
// "StructuredOutput" when a subagent ends without producing structured output. ONLY
// this error class is retried — genuine tool/permission errors fall through to the
// forward-as-error path unretried. Brittle substring match because it is the only
// signal the runtime surfaces; if the message changes the retry stops firing and the
// behavior degrades safely to the pre-retry forward-as-error path. Mirrors
// workflows/code-review.mjs's dispatchReviewer.
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

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
    schema: d.schema,
  }
  try {
    const result = await agent(d.prompt, opts)
    return { agentType: d.agentType, result }
  } catch (err) {
    if (!isNoStructuredOutputError(err)) {
      return { agentType: d.agentType, result: null, error: String(err) }
    }
    log(`${d.agentType}: died without StructuredOutput — retrying once`)
    try {
      const result = await agent(d.prompt, { ...opts, label: `${d.agentType} (retry)` })
      return { agentType: d.agentType, result }
    } catch (retryErr) {
      // Surface BOTH failures so a twice-dead sub-agent's full diagnostic trail survives.
      return {
        agentType: d.agentType,
        result: null,
        error: `retry failed: ${retryErr}; first attempt: ${err}`,
        retried: true,
        failed: true,
      }
    }
  }
}

const results = await parallel(selected.map((d) => () => dispatchIntake(d)))

const byType = (t) => results.find((r) => r && bare(r.agentType) === bare(t)) || { result: null }
return {
  issue,
  specReview: byType('spec-reviewer'),
  codebaseExplorer: byType('codebase-explorer'),
}
