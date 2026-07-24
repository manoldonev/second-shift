export const meta = {
  name: 'dev-pipeline-tool-discipline-probe',
  description:
    'Measures how a reviewer-baseline tool-preference instruction affects reviewer Bash discipline over a shell-heavy diff. Dispatches shell-touching reviewers K times under ONE selected instruction arm (baseline | grep-nudge | strict-one-command), through the SAME schema + StructuredOutput nudge as Stage 8, and captures each reviewer\'s completion vs StructuredOutput death. Run one arm per invocation, A/B the arms, to measure an instruction proposal instead of asserting it. This is a REAL agent-dispatch probe (it costs tokens) — NOT an offline node selftest — because agent() is a runtime-injected Workflow global. Invoke via the Workflow tool, never `node`.',
  phases: [{ title: 'Probe' }],
}

// ── MEASURED BASELINE (three-arm dispatch experiment, 27 reviewer dispatches over a
//    shell-heavy diff) — the empirical result this probe exists to reproduce / re-test:
//
//   arm = 'baseline'            (no tool-preference instruction)
//       ~71% of reviewer Bash calls are COMPOUND-shaped (cd-chains, `;`/newline
//       batching, pipes). That shape — not grep itself — is what the harness annotates
//       "shell syntax (string) that cannot be statically analyzed".
//   arm = 'grep-nudge'         ("use Grep/Glob, not Bash")
//       NULL effect: 71.3% vs the 71.4% baseline compound rate. The harness does not
//       expose Grep/Glob to reviewer agents when Bash is present (its own error redirects
//       to Bash grep/find), so the nudge steers nothing.
//   arm = 'strict-one-command' ("one analyzable command per call")
//       compound rate 72% -> 54%, BUT 3/6 reviewers DIED at the maxTurns cap: compound
//       Bash is rational turn-budget batching, and banning it trades cosmetic annotation
//       noise for MISSING reviews. Measured risk-increasing.
//   Also measured: the `F=$(find …); grep "$F"` substitution idiom occurs 0 times in 236
//   measured Bash calls (rare, not routine) — so a ban on it is cheap and low-collateral.
//
// WHAT THIS PROBE CAPTURES DIRECTLY vs EXTERNALLY:
//   - DIRECTLY: the StructuredOutput death rate per arm (the harmful signal of the strict
//     arm — reviewers exhausting the turn budget and never emitting). agent() surfaces a
//     death as a rejection; the death detector below counts it.
//   - EXTERNALLY: the compound-Bash-SHAPE rate is NOT observable from agent()'s return
//     (which is the final structured result, not the tool-call transcript). Measure it
//     post-run from the session audit ledger (audit-toolkit / .claude/audit/*.jsonl) by
//     classifying each reviewer Bash call as compound vs single. This probe's job is to
//     produce the dispatches under a fixed arm reproducibly; the shape classification is
//     a ledger pass over the run it produced.
//
// WHY A SHELL-HEAVY DIFF: the compound-Bash pressure is maximal when the diff is itself
// shell (.sh) — the reviewer greps/reads across many shell files to ground its verdict,
// which is exactly where compound batching (and, under the strict arm, turn-cap death)
// shows up. The default range `4df8fc8^..4df8fc8` is a stable historical shell-heavy
// commit (8 changed .sh files) so the probe is reproducible without committing a fixture.

// args: { worktree (REQUIRED — abs repo path the reviewers run git against),
//         base, head (shell-heavy range; defaults below),
//         reviewers (default the shell-touching reviewers),
//         k (dispatches per reviewer, default 3 → 9 per arm, 27 across the 3 arms),
//         model (default sonnet),
//         arm ('baseline' | 'grep-nudge' | 'strict-one-command', default 'baseline') }
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const {
  worktree,
  base = '4df8fc8^',
  head = '4df8fc8',
  reviewers = [
    'review-toolkit:maintainability-reviewer',
    'review-toolkit:complexity-reviewer',
    'review-toolkit:security-reviewer',
  ],
  k = 3,
  model = 'sonnet',
  arm = 'baseline',
} = a
if (!worktree) {
  throw new Error('tool-discipline-probe: args.worktree (absolute repo path the reviewers run git against) is required')
}
if (!Array.isArray(reviewers) || reviewers.length === 0) {
  throw new Error('tool-discipline-probe: args.reviewers must be a non-empty array of agentType strings')
}
const ARMS = ['baseline', 'grep-nudge', 'strict-one-command']
if (!ARMS.includes(arm)) {
  throw new Error(`tool-discipline-probe: args.arm must be one of ${ARMS.join(' | ')} (got '${arm}')`)
}
const range = `${base}..${head}`

// Copied verbatim from code-review.mjs / stall-probe.mjs so the probe dispatch is
// identical to production. (Permissive: only severity/description/confidence required.)
// LOCKSTEP-BEGIN findings-schema
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
// LOCKSTEP-END findings-schema

const STRUCTURED_OUTPUT_FIRST =
  ' Call StructuredOutput FIRST with your verdict and findings, before any prose' +
  ' explanation — do not write a long write-up before the structured call.'

// The instruction under test, appended to the reviewer prompt. 'baseline' appends
// nothing (the control). The other two are the MEASURED-null and MEASURED-harmful
// instructions — kept here so a future proposal is A/B'd against them, not re-asserted.
const ARM_INSTRUCTION = {
  baseline: '',
  'grep-nudge':
    ' Use the Grep and Glob tools to search the codebase instead of shelling out to' +
    ' Bash grep/find. (MEASURED NULL — the harness does not expose Grep/Glob to reviewer' +
    ' agents when Bash is present; retained as the control arm, not a recommendation.)',
  'strict-one-command':
    ' Issue exactly ONE statically-analyzable command per Bash call — no cd-chains, no' +
    ' `;`/newline batching, no pipes. (MEASURED HARMFUL — killed 3/6 reviewers at the' +
    ' maxTurns cap; retained as the control arm, not a recommendation.)',
}

const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

log(`tool-discipline-probe [arm=${arm}]: ${reviewers.join(', ')} × ${k} over ${range} in ${worktree}`)
phase('Probe')

const dispatchOnce = async (agentType, i) => {
  const prompt =
    `Review this change in your domain. Diff scope: \`git -C ${worktree} diff ${range}\`. ` +
    `Return your verdict and a deduplicated list of findings (severity blocker/major/minor/nit, ` +
    `file, line, confidence 0-100). Ignore stylistic issues handled by formatter/linter.` +
    STRUCTURED_OUTPUT_FIRST +
    ARM_INSTRUCTION[arm]
  try {
    // bounded-exploration-optout: tool-discipline-probe -- arm-controlled instrument. The prompt
    //   is set by ARM_INSTRUCTION so the arms stay comparable; a mandated nudge would contaminate
    //   every arm and make the A/B meaningless.
    const result = await agent(prompt, { agentType, model, label: `${agentType} #${i + 1} [${arm}]`, phase: 'Probe', schema: FINDINGS_SCHEMA })
    const findings = result && Array.isArray(result.findings) ? result.findings : []
    return {
      agentType,
      arm,
      stalled: false,
      verdict: result && result.verdict,
      findingCount: findings.length,
    }
  } catch (err) {
    // A StructuredOutput death is the turn-cap death the strict arm measures; any other
    // rejection (tool/permission/transport) is counted separately so it can't inflate it.
    return { agentType, arm, stalled: isNoStructuredOutputError(err), error: String(err) }
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
  perReviewer[agentType] = {
    dispatches: rs.length,
    stalls: rs.filter((r) => r.stalled).length,
    otherErrors: rs.filter((r) => r.error && !r.stalled).length,
    clean: completed.length,
  }
}
const totalStalls = results.filter((r) => r.stalled).length
log(
  `tool-discipline-probe [arm=${arm}]: ${totalStalls}/${results.length} StructuredOutput deaths ` +
    `(${reviewers.map((rv) => `${rv}: ${perReviewer[rv].stalls}/${perReviewer[rv].dispatches}`).join(', ')})`
)
log('tool-discipline-probe: compound-Bash-shape rate is a post-run audit-ledger pass — not captured here (see header).')

return { arm, range, worktree, k, reviewers, totalDispatches: results.length, totalStalls, perReviewer, results }
