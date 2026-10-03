export const meta = {
  name: 'review-toolkit-intake-fanout',
  description:
    'Intake fan-out for plan-interview pre-flight: a sealed lens writer, four angles and a pre-mortem working blind, and a cross-family refuter per claim. Returns the evidence pool that survived refutation.',
  phases: [
    { title: 'Lenses', detail: 'intake-lens-writer writes the five jobs' },
    { title: 'Widen', detail: 'four angles and a pre-mortem, blind' },
    { title: 'Refute', detail: 'one intake-refuter per claim, refuted by default' },
  ],
}

// Tier -> dispatch token. INLINED because the Workflow sandbox forbids imports; the authority
// is the `## Tier alphabet` table in ../model-tiering.md, held against this copy by
// check-model-tiers.sh (TIER-MAP-DRIFT). Keys stay unquoted for the reason intake-review.mjs gives.
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
  cross: 'fable',
}

// {agentType: tier}. Lockstep with each agent's frontmatter `model:` via check-model-tiers.sh.
// The refuter ships at `cross` so a model family other than the lenses' checks their claims
// (#916, model-tiering.md "The `cross` tier"). config.reviewers.modelOverrides (bare-keyed) wins.
const FANOUT_MODEL = {
  'review-toolkit:intake-lens-writer': 'reasoning',
  'review-toolkit:intake-lens': 'reasoning',
  'review-toolkit:intake-refuter': 'cross',
}

const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// The rules every lens is built under (#914). Given to the lens writer verbatim.
const BUILD_RULES = [
  'Independence: each lens works blind to the others; no shared context.',
  'Diversity of angle: each lens gets a different job, never the same prompt reworded.',
  'Evidence is the only thing passed on: a probe result, a repro, a cited line or commit; never an opinion or a vote.',
  'Refute, do not confirm: every claim faces a refuter told to break it, refuted by default.',
  'Keep by evidence, not consensus: a claim stays because it was reproduced, not because several agree.',
].join('\n- ')

// args (assembled in-session by plan-interview pre-flight):
//   issue      — the ticket id (drives the prompts)
//   issueBody  — the full ticket text (lenses never re-fetch it)
//   readRoot   — optional ABSOLUTE path every codebase read happens under
//   probeDir   — optional ABSOLUTE path probes may write to (default: no file writes)
//   config     — the consumer config (reviewers.modelOverrides / reviewers.tierMap)
//   ceilingMs  — whole-run wall-clock ceiling (default 30 min, #916 D-9)
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { issue, issueBody = '', readRoot = '', probeDir = '', config = {}, ceilingMs = 30 * 60 * 1000 } = a
if (!issue) throw new Error('intake-fanout workflow: args.issue is required')
if (!issueBody) throw new Error('intake-fanout workflow: args.issueBody is required (the lenses reason over it)')

const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const tierMap = { ...DEFAULT_TIER_MAP, ...((config && config.reviewers && config.reviewers.tierMap) || {}) }
const modelFor = (agentType) => {
  const declared = modelOverrides[bare(agentType)] || FANOUT_MODEL[agentType] || 'reasoning'
  return tierMap[declared] || declared
}
const WRITER = 'review-toolkit:intake-lens-writer'
const LENS = 'review-toolkit:intake-lens'
const REFUTER = 'review-toolkit:intake-refuter'
const lensModel = modelFor(LENS)
const refuterPrimary = modelFor(REFUTER)
const events = []

const ceilingMin = Math.round(ceilingMs / 60000)
const failed = (reason) => ({ issue, status: 'failed', reason, refuter: null, lenses: [], pool: [], events })

if (typeof budget !== 'undefined' && budget && budget.total && budget.remaining() <= 0) {
  log('budget exhausted — skipping the intake fan-out')
  return failed('budget exhausted before the fan-out started')
}

const readRootNote = readRoot
  ? `PINNED READ SURFACE (read first): perform ALL codebase reads inside ${readRoot}; never the main checkout. `
  : ''
const probeNote = probeDir
  ? ` Probes that write files write only under ${probeDir}/ (mkdir -p it).`
  : ' Do not write files; probe with read-only commands.'
const ticketBlock = `Ticket #${issue}:\n\n${issueBody}\n`

// --- text contract: a sentinel + fenced json block, parsed here (#169 explorer/emitter) ---
const parseResult = (text) => {
  const m = [...String(text ?? '').matchAll(/REVIEW_RESULT\s*```json\s*([\s\S]*?)```/g)]
  if (!m.length) return null
  try {
    return JSON.parse(m[m.length - 1][1])
  } catch {
    return null
  }
}
const isStr = (v) => typeof v === 'string' && v.trim().length > 0
const validWriter = (r) =>
  r && Array.isArray(r.angles) && r.angles.length >= 4 && r.angles.slice(0, 4).every((x) => x && isStr(x.key) && isStr(x.job)) && isStr(r.premortem)
const validLens = (r) => r && Array.isArray(r.claims) && r.claims.every((c) => c && isStr(c.claim) && isStr(c.pointer) && isStr(c.observed))
const validVerdict = (r) => r && typeof r.refuted === 'boolean'

// One dispatch: resolves to the agent's text, or null when the dispatch threw or came back
// empty (a dead agent, a safeguard block, a model the account cannot reach).
const tryAgent = async (prompt, opts) => {
  try {
    const t = await agent(prompt, opts)
    return t == null || t === '' ? null : t
  } catch (err) {
    events.push(`${opts.label}: dispatch failed (${String(err).slice(0, 160)})`)
    return null
  }
}

// Set once a retry on another family could not be dispatched; later retries then stay on the
// same tier instead of spending a call on a model this account cannot reach.
let otherFamilyDown = false

// Dispatch with ONE retry (#916 D-5): a dead or unparseable first attempt is retried once on
// `retryModel` (the other family when the run has one, else the same model). A retry on the other
// family that cannot be dispatched at all (no access, dead) is not the retry D-5 promises: it
// falls back once to the first attempt's model.
const dispatch = async (prompt, valid, opts, retryModel) => {
  const crossRetry = retryModel !== opts.model
  const models = [opts.model, crossRetry && otherFamilyDown ? opts.model : retryModel]
  for (let attempt = 0; attempt < models.length; attempt++) {
    const model = models[attempt]
    const label = attempt === 0 ? opts.label : `${opts.label} (retry${attempt > 1 ? ', same tier' : ''})`
    const text = await tryAgent(prompt, { ...opts, model, label })
    const parsed = parseResult(text)
    if (parsed && valid(parsed)) return { result: parsed, model }
    if (text != null) events.push(`${label}: no parseable REVIEW_RESULT block`)
    if (text == null && attempt === 1 && model !== opts.model) {
      otherFamilyDown = true
      models.push(opts.model)
    }
  }
  return { result: null, model: null }
}

// --- the cross-family refuter, with a one-call availability probe (#916 D-7) ---
// The first refuter dispatch tries the `cross` model. If it cannot run (no access, dead), every
// refuter in the run uses the lens family and the pool records it. One failed call is the cost.
const sameFamilyConfigured = refuterPrimary === lensModel
let crossGate = null
let refuterFamily = sameFamilyConfigured ? 'same-family (configured)' : `cross (${refuterPrimary})`

const refuteOne = async (c, lensKey, i) => {
  const prompt =
    readRootNote +
    `Refute this claim made while preparing the intake interview for the ticket below. Default to refuted=true ` +
    `unless you confirm it yourself.${probeNote}\n\n${ticketBlock}\n` +
    `Claim (${c.kind || 'claim'}): ${c.claim}\nPointer: ${c.pointer}\nObserved: ${c.observed}\n` +
    `Measured under: ${c.measured_under || 'not stated'}`
  const opts = { agentType: REFUTER, label: `refute:${lensKey}#${i + 1}`, phase: 'Refute' }
  let model = lensModel
  if (!sameFamilyConfigured) {
    if (!crossGate) {
      let settle
      crossGate = new Promise((r) => (settle = r))
      const first = await tryAgent(prompt, { ...opts, model: refuterPrimary })
      if (first == null) {
        refuterFamily = 'same-family (fable unavailable)'
        events.push(`refuter: '${refuterPrimary}' could not be dispatched; every refuter in this run uses '${lensModel}'`)
        settle(false)
      } else {
        settle(true)
        const parsed = parseResult(first)
        if (parsed && validVerdict(parsed)) return parsed
        // The one retry this claim gets (D-5), on the same model: it just proved reachable.
        const again = parseResult(await tryAgent(prompt, { ...opts, model: refuterPrimary, label: `${opts.label} (retry)` }))
        return again && validVerdict(again) ? again : { refuted: true, checked: 'no verdict after retry — refuted by default' }
      }
    } else if (await crossGate) {
      model = refuterPrimary
    }
  }
  const retryModel = model === refuterPrimary ? lensModel : model
  const v = await dispatch(prompt, validVerdict, { ...opts, model }, retryModel)
  return v.result || { refuted: true, checked: 'no verdict after retry — refuted by default' }
}

// --- the run ---
const run = async () => {
  phase('Lenses')
  const writerPrompt =
    readRootNote +
    `Write the five lens jobs for the intake fan-out on this ticket.\n\n${ticketBlock}\n` +
    `The rules every lens works under:\n- ${BUILD_RULES}\n`
  const w = await dispatch(writerPrompt, validWriter, { agentType: WRITER, model: modelFor(WRITER), label: 'lens-writer', phase: 'Lenses' }, refuterPrimary === lensModel ? modelFor(WRITER) : refuterPrimary)
  if (!w.result) return failed('the lens writer produced no usable jobs after one retry')

  const lenses = [
    ...w.result.angles.slice(0, 4).map((x) => ({ key: x.key, job: x.job })),
    { key: 'premortem', job: w.result.premortem },
  ]
  const lensRetry = sameFamilyConfigured ? lensModel : refuterPrimary
  const results = await pipeline(
    lenses,
    async (l) => {
      const prompt =
        readRootNote +
        `You are one lens in a fan-out that runs before a plan-interview on this ticket. Your job: ${l.job}${probeNote}\n\n${ticketBlock}`
      const r = await dispatch(prompt, validLens, { agentType: LENS, model: lensModel, label: `lens:${l.key}`, phase: 'Widen' }, lensRetry)
      return { l, r }
    },
    async ({ l, r }) => {
      if (!r.result) return { key: l.key, model: null, status: 'failed', claims: 0, survived: [] }
      const claims = r.result.claims.slice(0, 6)
      const verdicts = await parallel(claims.map((c, i) => () => refuteOne(c, l.key, i)))
      const survived = claims
        .map((c, i) => ({ c, v: verdicts[i] }))
        .filter((x) => x.v && x.v.refuted === false)
        .map(({ c, v }) => ({
          claim: c.claim,
          pointer: c.pointer,
          observed: c.observed,
          angle: l.key,
          kind: c.kind || 'probed-fact',
          measured_under: c.measured_under || '',
          status: 'unrefuted',
          checked: (v && v.checked) || '',
        }))
      log(`${l.key}: ${survived.length}/${claims.length} survive`)
      return { key: l.key, model: r.model, status: 'ok', claims: claims.length, survived }
    },
  )
  const ran = results.filter((x) => x && x.status === 'ok')
  const pool = ran.flatMap((x) => x.survived)
  const lensSummary = results.map((x) => ({ key: x.key, model: x.model, status: x.status, claims: x.claims, survived: x.survived.length }))
  if (ran.length === 0) return { ...failed('every lens failed after one retry'), lenses: lensSummary }
  return {
    issue,
    status: ran.length === lenses.length ? 'complete' : 'partial',
    reason: ran.length === lenses.length ? '' : `${lenses.length - ran.length} of ${lenses.length} lenses failed after one retry`,
    refuter: refuterFamily,
    lenses: lensSummary,
    pool,
    events,
  }
}

// Whole-run wall-clock ceiling (#916 D-9), the same race intake-review.mjs uses per agent. agent()
// has no abort, so agents past the ceiling keep running in the background; the caller simply
// stops waiting and proceeds without the pool.
let timer
const ceiling = new Promise((resolve) => {
  timer = setTimeout(() => resolve(failed(`exceeded ${ceilingMin} min`)), ceilingMs)
})
const out = await Promise.race([run(), ceiling])
clearTimeout(timer)
return out
