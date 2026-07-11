export const meta = {
  name: 'dev-pipeline-stall-probe',
  description:
    'Measures the reviewer StructuredOutput-stall rate over a fixed low-signal diff. Dispatches the historically-stalling reviewers K times each, through the SAME schema + nudge as Stage 8 (workflows/code-review.mjs), catches each result, and counts StructuredOutput deaths vs clean returns. Run it BEFORE and AFTER a reviewer-contract change to measure the change\'s effect on the stall rate. This is a REAL agent-dispatch probe (it costs tokens) — it is NOT an offline node selftest like null-reviewer-selftest.mjs, because agent() is a runtime-injected Workflow global. Invoke via the Workflow tool, never `node`.',
  phases: [{ title: 'Probe' }],
}

// Why a low-signal diff: the stall this probe measures is a reviewer exhausting its
// turn budget on grounding/prose BEFORE the StructuredOutput call (see the ROOT CAUSE
// block in code-review.mjs). The pressure is MAXIMAL on a diff with nothing substantive
// to flag, because the reviewer must ground the ABSENCE of findings across the whole
// diff. The default range `cf8a059^..cf8a059` is exactly that: a pure prettier reformat
// of a plan .md (11 insertions / 11 deletions, zero behavioral content) — a stable
// historical commit, so the probe is reproducible without committing a fixture.
// An even lower-signal alternative is `84e3efa^..84e3efa` (a 2-word docs nit).
//
// To isolate the variable: this probe mirrors the production Stage-8 dispatch EXACTLY
// (same FINDINGS_SCHEMA, same STRUCTURED_OUTPUT_FIRST nudge, same death detector). The
// ONLY thing that differs between a BEFORE and an AFTER run is the reviewer-baseline
// contract the dispatched agents inherit — so a drop in the stall rate is attributable
// to the contract change, not to dispatch differences.

// args: { worktree (REQUIRED — abs repo path the reviewers run git against),
//         base, head (low-signal range; defaults below),
//         reviewers (default the two historically-stalling Sonnet reviewers),
//         k (dispatches per reviewer, default 4), model (default sonnet) }
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  worktree,
  base = 'cf8a059^',
  head = 'cf8a059',
  reviewers = ['review-toolkit:maintainability-reviewer', 'review-toolkit:test-coverage-reviewer'],
  k = 4,
  model = 'sonnet',
  // bounded: append a triage / bounded-exploration instruction to the prompt. Used to
  // A/B test whether disciplining the absence-grounding (vs raising budget / model tier)
  // is what eliminates the stall.
  bounded = false,
} = a
if (!worktree) {
  throw new Error('stall-probe: args.worktree (absolute repo path the reviewers run git against) is required')
}
if (!Array.isArray(reviewers) || reviewers.length === 0) {
  throw new Error('stall-probe: args.reviewers must be a non-empty array of agentType strings')
}
const range = `${base}..${head}`

// Copied verbatim from code-review.mjs so the probe dispatch is identical to production.
// (Permissive: only severity/description/confidence required; findings may be empty —
// so an honest "approve, nothing to flag" is a single valid StructuredOutput call.)
const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['verdict', 'findings'],
  properties: {
    verdict: {
      type: 'string',
      enum: ['approve', 'approve-with-nits', 'request-changes', 'block'],
    },
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
    suppressed: { type: 'array', items: { type: 'string' } },
  },
}

const STRUCTURED_OUTPUT_FIRST =
  ' Call StructuredOutput FIRST with your verdict and findings, before any prose' +
  ' explanation — do not write a long write-up before the structured call.'

// Candidate FIX under test: proportionate absence-grounding. Targets the EXPLORATION
// (tool calls reading files), not the output format — the stall is the reviewer opening
// every file to prove the absence of findings on a large low-signal diff and exhausting
// its turn budget before it emits.
const BOUNDED_EXPLORATION =
  ' TRIAGE FIRST: skim the diff to judge whether it touches your domain at all. If it is' +
  ' docs/config/reformatting — or otherwise has nothing in your domain — emit StructuredOutput' +
  ' immediately (approve, no findings) WITHOUT opening every file. Open files only to ground a' +
  ' SPECIFIC finding you intend to raise; you do NOT have to exhaustively read the whole diff to' +
  ' assert the ABSENCE of findings. Stop exploring and emit StructuredOutput before your budget runs low.'

const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

log(`stall-probe: ${reviewers.join(', ')} × ${k} over ${range} in ${worktree}`)
phase('Probe')

const dispatchOnce = async (agentType, i) => {
  const prompt =
    `Review this change in your domain. Diff scope: \`git -C ${worktree} diff ${range}\`. ` +
    `Return your verdict and a deduplicated list of findings (severity blocker/major/minor/nit, ` +
    `file, line, confidence 0-100). Ignore stylistic issues handled by formatter/linter.` +
    STRUCTURED_OUTPUT_FIRST +
    (bounded ? BOUNDED_EXPLORATION : '')
  try {
    const result = await agent(prompt, { agentType, model, label: `${agentType} #${i + 1}`, phase: 'Probe', schema: FINDINGS_SCHEMA })
    // Capture findings so a bounded-vs-unbounded run can be compared for review QUALITY
    // (does the triage nudge suppress real findings?), not just stall rate.
    const findings = result && Array.isArray(result.findings) ? result.findings : []
    return {
      agentType,
      stalled: false,
      verdict: result && result.verdict,
      findingCount: findings.length,
      findings: findings.map((f) => ({
        severity: f.severity,
        confidence: f.confidence,
        title: f.title || String(f.description || '').slice(0, 80),
      })),
    }
  } catch (err) {
    // A StructuredOutput death is the stall we're measuring; any other rejection
    // (tool/permission/transport) is counted separately so it can't inflate the rate.
    return { agentType, stalled: isNoStructuredOutputError(err), error: String(err) }
  }
}

const thunks = []
for (const agentType of reviewers) {
  for (let i = 0; i < k; i++) thunks.push(() => dispatchOnce(agentType, i))
}
const results = (await parallel(thunks)).filter(Boolean)

const perReviewer = {}
for (const agentType of reviewers) {
  const rs = results.filter((r) => r.agentType === agentType)
  const completed = rs.filter((r) => !r.error)
  const findingCounts = completed.map((r) => r.findingCount || 0)
  perReviewer[agentType] = {
    dispatches: rs.length,
    stalls: rs.filter((r) => r.stalled).length,
    otherErrors: rs.filter((r) => r.error && !r.stalled).length,
    clean: completed.length,
    // Review-quality signal: avg findings per completed dispatch (compare bounded vs unbounded).
    avgFindings: completed.length ? findingCounts.reduce((a, b) => a + b, 0) / completed.length : 0,
    findingCounts,
  }
}
const totalStalls = results.filter((r) => r.stalled).length
log(`stall-probe: ${totalStalls}/${results.length} StructuredOutput stalls (${reviewers.map((rv) => `${rv}: ${perReviewer[rv].stalls}/${perReviewer[rv].dispatches}`).join(', ')})`)

return { range, worktree, k, reviewers, totalDispatches: results.length, totalStalls, perReviewer, results }
