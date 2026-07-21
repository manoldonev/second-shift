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
  reviewers,
  k = 4,
  model,
  // target: which production dispatch this run imitates. See TARGETS below.
  target = 'diff-reviewer',
  // planPath: the low-signal input for the plan-shaped targets. Default is a plan already on the
  // base branch (263 lines, 51 distinct file references) so the probe keeps the reproducibility
  // property the diff-range default has — see the planPin note in TARGETS.
  planPath = 'docs/plans/160-prose-debloat-scoping.md',
  // bounded: append a triage / bounded-exploration instruction to the prompt. Used to
  // A/B test whether disciplining the absence-grounding (vs raising budget / model tier)
  // is what eliminates the stall.
  bounded = false,
} = a
if (!worktree) {
  throw new Error('stall-probe: args.worktree (absolute repo path the reviewers run git against) is required')
}
const TARGET = TARGETS[target]
if (!TARGET) {
  throw new Error(`stall-probe: unknown args.target '${target}' (known: ${Object.keys(TARGETS).join(', ')})`)
}
// Explicit args still win; otherwise the target supplies its production agents and tier.
const AGENTS = Array.isArray(reviewers) && reviewers.length ? reviewers : TARGET.agents
const MODEL = model || TARGET.model
if (!Array.isArray(AGENTS) || AGENTS.length === 0) {
  throw new Error('stall-probe: args.reviewers must be a non-empty array of agentType strings')
}
const range = `${base}..${head}`
// What this arm measured, echoed into the return so a recorded rate is self-describing.
const inputRef = target === 'diff-reviewer' ? range : `${planPath}@${PLAN_PIN}`

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

// Copied verbatim from plan-review.mjs so a plan-shaped arm dispatches identically to production.
// The trinary shape is NOT interchangeable with FINDINGS_SCHEMA above: plan reviewers return
// block|fix-and-go|pass, diff reviewers return approve|...|block. Measuring one with the other's
// schema would not be measuring the dispatch that stalls.
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

// Production plan-shaped dispatches append the MANDATE, not code-review's FIRST. An arm carrying
// the wrong one is not measuring the dispatch that died — copied verbatim from plan-review.mjs.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

// The plan-shaped candidate FIX under test. Verbatim from plan-review.mjs's constant of the same
// name — the AFTER arm must carry the exact text production ships, or it measures something else.
const BOUNDED_PLAN_GROUNDING =
  ' GROUND PROPORTIONATELY: verify that the paths and symbols the plan references exist using' +
  ' BATCHED checks (one ls/glob/grep covering many paths — not one Read per path). Read a file in' +
  ' full only when its CONTENT is needed to support a specific finding you intend to raise; a plan' +
  ' reference that merely needs to exist does not need a read. You do NOT have to open every' +
  ' referenced file to conclude the plan is grounded. This bounds how you ground, not whether — it' +
  ' never licenses skipping a completeness inventory this prompt asks for, nor asserting a claim' +
  ' you did not check. Stop exploring and emit StructuredOutput before your budget runs low.'

// Target-keyed dispatch table. Each entry mirrors ONE production dispatch: same schema, same prompt
// shape, same mandate/nudge text, same model tier. Extending the probe to a new agent is adding a
// row, not editing the dispatch loop.
//
// planPin: the plan-shaped default input is a live path on the base branch, so pin the commit that
// introduced it when quoting a rate. The diff-shaped default is already SHA-pinned (see the header);
// this keeps the plan-shaped arms equally reproducible after the file is edited.
//
// MODEL TIERS are re-stated here and are NOT covered by check-model-tiers.sh, which validates six
// named tables and does not include this file. A change to PLAN_REVIEWER_MODEL or UNIT_TEST_MODEL
// must be mirrored here by hand or the instrument silently drifts from production. Accepted, known
// gap; extending that lint's file list is the follow-up.
const PLAN_PIN = '521b387'
const TARGETS = {
  // The original diff-shaped arm — unchanged default so existing invocations behave as before.
  'diff-reviewer': {
    // bounded-exploration-optout: probe target -- measurement control; the nudge is this probe's
    //   independent variable, supplied per-arm via the `bounded` arg.
    schema: FINDINGS_SCHEMA,
    model: 'sonnet',
    agents: ['review-toolkit:maintainability-reviewer', 'review-toolkit:test-coverage-reviewer'],
    nudge: BOUNDED_EXPLORATION,
    build: (agentType) =>
      `Review this change in your domain. Diff scope: \`git -C ${worktree} diff ${base}..${head}\`. ` +
      `Return your verdict and a deduplicated list of findings (severity blocker/major/minor/nit, ` +
      `file, line, confidence 0-100). Ignore stylistic issues handled by formatter/linter.` +
      STRUCTURED_OUTPUT_FIRST,
  },
  // The Stage-4 gate that aborted runs #165 and #169 at 6/6 apiece.
  'plan-reviewer': {
    // bounded-exploration-optout: probe target -- measurement control, as above.
    schema: PLAN_REVIEW_SCHEMA,
    model: 'opus',
    agents: ['review-toolkit:plan-reviewer'],
    nudge: BOUNDED_PLAN_GROUNDING,
    build: () =>
      `Review the implementation plan at \`${planPath}\`. ` +
      `All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
      `Verify plan grounding (every referenced path/symbol exists or is tagged [NEW]/[UNVERIFIED]), ` +
      `completeness against the required plan sections, consistency with codebase patterns, and ` +
      `missed downstream impacts. Return trinary verdict (block | fix-and-go | pass) and findings.` +
      STRUCTURED_OUTPUT_MANDATE,
  },
  // The Stage-4 child plan-review.mjs nests via workflow() (unit-tests.mjs kind: 'plan-review').
  'unit-test-plan-reviewer': {
    // bounded-exploration-optout: probe target -- measurement control, as above.
    schema: PLAN_REVIEW_SCHEMA,
    model: 'sonnet',
    agents: ['review-toolkit:unit-test-plan-reviewer'],
    nudge: BOUNDED_PLAN_GROUNDING,
    build: () =>
      `Review the unit test strategy in the plan at \`${planPath}\`. ` +
      `All file reads / Grep / Glob / Bash must target the worktree \`${worktree}\`. ` +
      `Load the unit-testing skill. Return trinary verdict (block | fix-and-go | pass) and findings.` +
      STRUCTURED_OUTPUT_MANDATE,
  },
}

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

log(`stall-probe: [${target}] ${AGENTS.join(', ')} × ${k} (${bounded ? 'bounded' : 'unbounded'}) over ${inputRef} in ${worktree}`)
phase('Probe')

const dispatchOnce = async (agentType, i) => {
  const prompt = TARGET.build(agentType) + (bounded ? TARGET.nudge : '')
  try {
    // bounded-exploration-optout: stall-probe -- THE MEASUREMENT CONTROL. The nudge is the
    //   independent variable here, applied via the `bounded` arg. Mandating it at this site would
    //   delete the unbounded arm and destroy the instrument that measures the fix.
    const result = await agent(prompt, { agentType, model: MODEL, label: `${agentType} #${i + 1}`, phase: 'Probe', schema: TARGET.schema })
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
for (const agentType of AGENTS) {
  for (let i = 0; i < k; i++) thunks.push(() => dispatchOnce(agentType, i))
}
const results = (await parallel(thunks)).filter(Boolean)

const perReviewer = {}
for (const agentType of AGENTS) {
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
log(`stall-probe: ${totalStalls}/${results.length} StructuredOutput stalls (${AGENTS.map((rv) => `${rv}: ${perReviewer[rv].stalls}/${perReviewer[rv].dispatches}`).join(', ')})`)

return { target, inputRef, range, worktree, k, bounded, model: MODEL, reviewers: AGENTS, totalDispatches: results.length, totalStalls, perReviewer, results }
