export const meta = {
  name: 'lean-review',
  description:
    'run-lean milestone-4 gate: dispatches ONE fresh-context generalist reviewer over the lean branch diff and returns a single structured verdict. The session writes the returned verdict into a COMMITTED verdict record; this script never touches the filesystem.',
  phases: [{ title: 'Lean review', detail: 'one generalist reviewer over the branch diff' }],
}

// NO MODEL TABLE — deliberate, and load-bearing (D-2).
//
// Every sibling workflow under skills/run/workflows/ declares a {agentType: model} table that
// check-model-tiers.sh locksteps against agent frontmatter. This file declares none, because
// run-lean makes ZERO model claims: the operator picks the session tier, and the reviewer's
// tier comes from config `reviewers.modelOverrides` under the reserved bare name below. When
// no override is set we pass NO `model` at all and the runtime default applies.
//
// This is safe rather than an evasion: check-model-tiers.sh scans a FIXED list of six named
// tables (code-review, intake-review, design-sync, unit-tests, plan-review, mutation-gate) —
// it does not glob-discover — so a table here would be unscanned anyway, while an override
// with no agent file behind it cannot raise DANGLING. Adding a table would therefore create a
// model claim that nothing locksteps: worse than none.
const LEAN_REVIEWER_OVERRIDE_KEY = 'lean-reviewer'

// args (assembled in-session by the run-lean skill):
//   worktree   — ABSOLUTE path to the lean worktree (the script has no filesystem access,
//                so it cannot resolve a relative path; same contract as code-review.mjs)
//   base, head — the diff range the reviewer reviews
//   issue      — the issue key, for the prompt
//   specPath   — worktree-relative path to the committed lean spec/AC file (the completeness
//                contract the reviewer scores against)
//   round      — 1-based review round; blockers are fixed and re-reviewed within the fix budget
//   config     — ONLY the keys this script reads. Passing the whole parsed config has been
//                observed to break dispatch, so the caller sends { reviewers } and nothing else.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { worktree, base, head, issue, specPath = '', round = 1, config = {} } = a
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}

if (!worktree) throw new Error('lean-review: args.worktree (absolute path) is required')
if (!base || !head) throw new Error('lean-review: args.base and args.head are required')
if (!issue) throw new Error('lean-review: args.issue is required')

// Verdict shape. DELIBERATELY NOT code-review.mjs's findings schema — a distinct minimal
// shape, so no lockstep row is owed (AC-10). Used as an in-script validator, never as a
// dispatch schema for the explorer.
const VERDICT_SHAPE = {
  required: ['verdict', 'findings'],
  enums: { verdict: ['approve', 'needs-work'] },
  findingRequired: ['severity', 'claim', 'rationale', 'confidence'],
  findingEnums: { severity: ['blocker', 'warning', 'note'] },
}

// Wall-clock ceiling (the code-review.mjs rationale, restated because Workflow scripts cannot
// import): the runtime's own agent-stall loop can let a wedged reviewer burn ~90 min before
// agent() settles, and that loop is not reachable from here (no timeout option, no
// AbortController in the sandbox). Bound it in userland and resolve — never reject — to the
// dark-marker shape the caller already handles.
const REVIEWER_CEILING_MS = 15 * 60 * 1000

// The measured transport (D-23). Schema-FREE explorer ending in a sentinel + fenced JSON,
// parsed here; the schema rides only on the tool-less structured-emitter fallback. The
// alternative — schema-forced single dispatch — measured 7/8 dark deaths against 0/8 for this
// shape at a third of the tokens. Last-match-wins, which is what makes progressive re-emission
// free.
const parseVerdict = (text) => {
  const m = [...String(text ?? '').matchAll(/LEAN_REVIEW_RESULT\s*```json\s*([\s\S]*?)```/g)]
  if (!m.length) return null
  try {
    return JSON.parse(m[m.length - 1][1])
  } catch {
    return null
  }
}

const validateVerdict = (o) => {
  if (!o || typeof o !== 'object') return false
  for (const k of VERDICT_SHAPE.required) if (!(k in o)) return false
  if (!VERDICT_SHAPE.enums.verdict.includes(o.verdict)) return false
  if (!Array.isArray(o.findings)) return false
  for (const f of o.findings) {
    if (!f || typeof f !== 'object') return false
    for (const k of VERDICT_SHAPE.findingRequired) if (!(k in f)) return false
    if (f.severity != null && !VERDICT_SHAPE.findingEnums.severity.includes(f.severity)) return false
  }
  return true
}

// The generalist charter. There is no agent file for this reviewer (D-21) — the prompt IS the
// agent definition, so reviewer-baseline's severity/confidence contract is restated inline
// rather than inherited.
const CHARTER =
  `You are the single independent reviewer for a lean pipeline run on issue #${issue}.` +
  ` There is no reviewer fan-out behind you and no second round of eyes: you are the only` +
  ` review this change gets before it reaches a pull request. Review as a generalist across` +
  ` ALL of these, in priority order:\n` +
  `  1. CORRECTNESS — does the change do what it claims, and is it free of defects that would` +
  ` bite in production? Trace the actual control flow; do not pattern-match.\n` +
  `  2. COMPLETENESS against the acceptance criteria — the committed spec` +
  `${specPath ? ` at \`${specPath}\`` : ''} is the definition of done. Check each numbered AC-n` +
  ` against the diff and say which are satisfied, which are not, and which you could not tell.\n` +
  `  3. POLICY EYES — repo conventions (read CLAUDE.md), test coverage for the behavior added,` +
  ` and anything the change makes stale.\n\n` +
  `SEVERITY CONTRACT (restated here because you inherit no agent doc):\n` +
  `  blocker — a defect, an unmet acceptance criterion, or a policy violation. Must be fixed` +
  ` before merge. Use it only when you can name the concrete failure.\n` +
  `  warning — a real problem that does not block: likely-wrong, fragile, or contested.\n` +
  `  note    — minor or stylistic.\n` +
  `CONFIDENCE is 0-100 and means "how sure am I this is real". Below 50, prefer a warning to a` +
  ` blocker. Every finding's \`rationale\` must carry your actual reasoning and how you verified` +
  ` it (file:line where relevant) — a bare conclusion is unusable.\n\n` +
  `VERDICT: "approve" iff there are no blockers. Any blocker means "needs-work". Do not soften` +
  ` a blocker to keep a run moving, and do not invent one to look thorough.`

const EMIT_CONTRACT =
  '\n\nEMIT AS YOU GO — do NOT save your result for the end. As soon as you have enumerated the' +
  ' changed files, write a COMPLETE LEAN_REVIEW_RESULT block reflecting what you know so far,' +
  ' then keep working and re-emit the whole block each time you learn something. Emitting more' +
  ' than one block is expected: the LAST complete block wins, so an early one costs you nothing.' +
  ' Budget your turns so the final block lands well before your limit — a review you never emit' +
  ' is scored exactly like a review that never ran, and the milestone records no verdict at all.' +
  '\n\nYour FINAL output MUST end with this sentinel line followed by one fenced json block and' +
  ' NOTHING after it:\n\n' +
  'LEAN_REVIEW_RESULT\n```json\n{ "verdict": "approve|needs-work", "summary": "...", "findings":' +
  ' [ { "severity": "blocker|warning|note", "claim": "...", "rationale": "...", "suggestion":' +
  ' "...", "confidence": 0, "file": "...", "line": 0 } ] }\n```'

const PROMPT =
  `${CHARTER}\n\n` +
  `Perform ALL reads (Read/Grep/Glob/Bash) inside the worktree \`${worktree}\`.\n` +
  `The change under review is the diff \`${base}..${head}\`. Start with` +
  ` \`git -C ${worktree} diff --stat ${base}..${head}\`, then read the changed files themselves —` +
  ` review the code, not just the diff hunks.\n` +
  (specPath ? `The acceptance criteria live in \`${worktree}/${specPath}\`. Read it first.\n` : '') +
  `This is review round ${round}.` +
  EMIT_CONTRACT

log(`lean-review: one generalist over ${base}..${head} (round ${round})`)
phase('Lean review')

if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping the lean review dispatch')
    return { issue, round, verdict: null, budgetExhausted: true }
  }
}

// bounded-exploration-optout: structured-emitter -- tools:[] maxTurns:2 transcription sink;
//   nothing to explore, which is why it may carry the schema.
const emitStructured = (text) =>
  agent(
    'Convert this completed review into the required structured object. Transcribe EXACTLY' +
      ' what the review states — never invent, drop, merge, soften or upgrade findings.' +
      '\n\n---REVIEW---\n' + String(text) + '\n---END---',
    {
      agentType: 'review-toolkit:structured-emitter',
      model: 'haiku',
      label: 'lean-reviewer (emit)',
      phase: 'Lean review',
      schema: {
        type: 'object',
        additionalProperties: true,
        required: ['verdict', 'findings'],
        properties: {
          verdict: { type: 'string', enum: ['approve', 'needs-work'] },
          summary: { type: 'string' },
          findings: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: true,
              required: ['severity', 'claim', 'rationale', 'confidence'],
              properties: {
                severity: { type: 'string', enum: ['blocker', 'warning', 'note'] },
                claim: { type: 'string' },
                rationale: { type: 'string' },
                suggestion: { type: 'string' },
                confidence: { type: 'integer' },
                file: { type: 'string' },
                line: { type: ['integer', 'string', 'null'] },
              },
            },
          },
        },
      },
    },
  )

// One dispatch, ONE inline retry on a contract miss, then the emitter. A missing sentinel on
// both attempts is darkness — reported as such, never silently downgraded to "no findings",
// because milestone 4 blocks on anything that is not a committed verdict=approve and a dark
// reviewer must not read as an approval.
const dispatchReview = async () => {
  const opts = { label: 'lean-reviewer', phase: 'Lean review' }
  const override = modelOverrides[LEAN_REVIEWER_OVERRIDE_KEY]
  if (override) opts.model = override // absent ⇒ no `model` key at all ⇒ runtime default (D-2)

  let lastText = null
  for (let attempt = 0; attempt < 2; attempt++) {
    let text
    try {
      // bounded-exploration-optout: schema-free-explorer -- the explorer dispatch carries no
      //   schema by construction (D-23); its bounding rides in EMIT_CONTRACT above.
      text = await agent(PROMPT, { ...opts, label: attempt === 0 ? 'lean-reviewer' : 'lean-reviewer (retry)' })
    } catch (err) {
      return attempt === 0
        ? { verdict: null, error: String(err), failed: true }
        : { verdict: null, error: `retry failed: ${err}`, retried: true, failed: true }
    }
    const parsed = parseVerdict(text)
    if (parsed && validateVerdict(parsed)) return { ...parsed, round }
    lastText = text
    log(`lean-reviewer: text-contract miss (${/LEAN_REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : 'no sentinel'})${attempt === 0 ? ' — retrying once' : ''}`)
  }

  if (/LEAN_REVIEW_RESULT/.test(String(lastText ?? ''))) {
    try {
      const emitted = await emitStructured(lastText)
      if (emitted && validateVerdict(emitted)) return { ...emitted, round }
    } catch (emitErr) {
      return { verdict: null, error: `emit failed: ${emitErr}`, retried: true, failed: true }
    }
  }
  return {
    verdict: null,
    error: 'text-contract: reviewer never produced a parseable LEAN_REVIEW_RESULT block after retry — declared dark',
    retried: true,
    failed: true,
  }
}

const withCeiling = (p) => {
  let timer
  const ceiling = new Promise((resolve) => {
    timer = setTimeout(
      () =>
        resolve({
          verdict: null,
          error: `dispatch exceeded the wall-clock ceiling (${REVIEWER_CEILING_MS}ms) — declared dark`,
          retried: true,
          failed: true,
          ceiling: true,
        }),
      REVIEWER_CEILING_MS,
    )
  })
  return Promise.race([p, ceiling]).then((r) => {
    clearTimeout(timer)
    return r
  })
}

const result = await withCeiling(dispatchReview())

// The session — not this script — writes the COMMITTED verdict record (D-46). The Workflow has
// no filesystem access, and that separation is deliberate: the record is a diffable artifact
// the merge-boundary gate re-asserts, so it must be produced by something that can commit.
return { issue, round, ...result }
