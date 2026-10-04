export const meta = {
  name: 'review-toolkit-intake-fanout',
  description:
    'Intake fan-out for plan-interview pre-flight: a sealed lens writer, four angles and a pre-mortem working blind across two model families, and a refuter per claim from the family that did not make it. Returns the evidence pool that survived refutation.',
  phases: [
    { title: 'Lenses', detail: 'intake-lens-writer writes the five jobs' },
    { title: 'Widen', detail: 'four angles and a pre-mortem, blind, families alternating' },
    { title: 'Refute', detail: 'one intake-refuter per claim, the other family, refuted by default' },
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
// These are the agents' own defaults; the lens and refuter tiers a run actually uses are chosen
// per lens below. config.reviewers.modelOverrides (bare-keyed) wins over both.
const FANOUT_MODEL = {
  'review-toolkit:intake-lens-writer': 'reasoning',
  'review-toolkit:intake-lens': 'reasoning',
  'review-toolkit:intake-refuter': 'cross',
}

// The arm the consumer replay measured (#916): the four angles alternate the two model families,
// the pre-mortem runs on the second family, and every claim is refuted by the family that did
// not make it. Mixing families is the variable under test (build rule 2), so it ships as measured.
const ANGLE_TIERS = ['reasoning', 'cross', 'reasoning', 'cross']
const PREMORTEM_TIER = 'cross'

const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// #914's build rules, as the measured lens writer read them. Given to the lens writer verbatim.
const BUILD_RULES = [
  "Independence. Each agent works blind to the others' conclusions. No shared \"war room\" context; it reproduces the self-agreement the lane's never-resume-a-review rule exists to prevent.",
  'Diversity of angle, then of model. Each agent gets a different job or framing, never the same prompt N times. Mixing models (for example Opus with Fable) is a variable under test, not an assumption.',
  'Evidence is the only thing passed between agents. A probe result, a repro, a cited line or commit. Never an opinion or a vote. Anything that travels without its evidence is dropped.',
  "Refute, don't confirm. Every surviving claim faces a verifier told to break it, with refuted as the default when it cannot confirm.",
  'Keep by evidence, not consensus. A claim stays because it was measured or reproduced. One reproduced finding outweighs any number of agreeing agents, and two agents that disagree are settled by running the thing.',
].map((r, i) => `${i + 1}. ${r}`).join('\n')

// args (assembled in-session by plan-interview pre-flight):
//   issue      — the ticket id (drives the prompts)
//   issueBody  — the full ticket text (lenses never re-fetch it)
//   readRoot   — optional ABSOLUTE path of the checkout the ticket targets
//   checkouts  — optional [{ path, role }]: ABSOLUTE paths of other repos the change meets (a
//                frontend that calls this backend, a client, a sibling service), with what each is
//   protocol   — optional ABSOLUTE paths of the protocol text every agent works under (the
//                plan-interview and interviewing-baseline skill files)
//   probeDir   — optional ABSOLUTE path probes may write to (default: no file writes)
//   config     — the consumer config (reviewers.modelOverrides / reviewers.tierMap)
//   ceilingMs  — whole-run wall-clock ceiling (default 30 min, #916 D-9)
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { issue, issueBody = '', readRoot = '', checkouts = [], protocol = [], probeDir = '', config = {}, ceilingMs = 30 * 60 * 1000 } = a
if (!issue) throw new Error('intake-fanout workflow: args.issue is required')
if (!issueBody) throw new Error('intake-fanout workflow: args.issueBody is required (the lenses reason over it)')

const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const tierMap = { ...DEFAULT_TIER_MAP, ...((config && config.reviewers && config.reviewers.tierMap) || {}) }
const resolve = (tier) => tierMap[tier] || tier
const WRITER = 'review-toolkit:intake-lens-writer'
const LENS = 'review-toolkit:intake-lens'
const REFUTER = 'review-toolkit:intake-refuter'
const writerModel = resolve(modelOverrides[bare(WRITER)] || FANOUT_MODEL[WRITER])
const lensOverride = modelOverrides[bare(LENS)] ? resolve(modelOverrides[bare(LENS)]) : null
const refuterOverride = modelOverrides[bare(REFUTER)] ? resolve(modelOverrides[bare(REFUTER)]) : null
const FIRST = resolve('reasoning')
const SECOND = resolve('cross')
const twoFamilies = FIRST !== SECOND
const other = (m) => (!twoFamilies ? m : m === SECOND ? FIRST : SECOND)
const events = []

// The second family may be out of this account's reach. It is declared down after two failed
// dispatches with no success, never on one (a single dead agent is not an access problem), and
// from then on every dispatch meant for it runs on the first family instead.
let secondOk = false
let secondFails = 0
const secondDown = () => !secondOk && secondFails >= 2
const live = (m) => (twoFamilies && m === SECOND && secondDown() ? FIRST : m)

const ceilingMin = Math.round(ceilingMs / 60000)
const failed = (reason) => ({ issue, status: 'failed', reason, refuter: null, lenses: [], pool: [], events })

if (typeof budget !== 'undefined' && budget && budget.total && budget.remaining() <= 0) {
  log('budget exhausted — skipping the intake fan-out')
  return failed('budget exhausted before the fan-out started')
}

// What every agent is grounded in, as the measured replay grounded it: the checkouts it may read,
// the protocol it works under, and where it may write.
const ground = [
  readRoot ? `The repo the ticket targets is the checkout ${readRoot}; perform its reads there, never in the main checkout.` : '',
  ...checkouts.filter((c) => c && c.path).map((c) => `${c.role || 'A repo this change meets'} is the checkout ${c.path}.`),
  readRoot ? 'Read code ONLY in those checkouts. Never modify them.' : '',
  protocol.length ? `The protocol you operate under: ${protocol.join(' and ')}.` : '',
  probeDir ? `Probes that write files write only under ${probeDir}/ (mkdir -p it).` : 'Do not write files; probe with read-only commands.',
  'If anything in your context hints at how this ticket was eventually resolved, do not use it.',
].filter(Boolean).join('\n')
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
  let t = null
  try {
    t = await agent(prompt, opts)
    t = t == null || t === '' ? null : t
  } catch (err) {
    events.push(`${opts.label}: dispatch failed (${String(err).slice(0, 160)})`)
  }
  if (twoFamilies && opts.model === SECOND) {
    if (t != null) secondOk = true
    else if (!secondOk && ++secondFails === 2) {
      events.push(`'${SECOND}' could not be dispatched twice; the rest of this run uses '${FIRST}' in its place`)
    }
  }
  return t
}

// Dispatch with ONE retry (#916 D-5): a dead or unparseable first attempt is retried once on
// `retryModel` (the other family when the run has one, else the same model). Each attempt picks
// its model when it runs, so one the run has since found unreachable is skipped. A retry that
// could not be dispatched at all (no access, dead) is not the retry D-5 promises: one more
// attempt follows, on the first attempt's model or, when that is the unreachable one, the other.
const dispatch = async (prompt, valid, opts, retryModel) => {
  const plan = [opts.model, retryModel]
  let first = null
  for (let attempt = 0; attempt < plan.length; attempt++) {
    const model = live(plan[attempt])
    if (attempt === 0) first = model
    const label = attempt === 0 ? opts.label : `${opts.label} (retry${attempt > 1 ? ', same tier' : ''})`
    const text = await tryAgent(prompt, { ...opts, model, label })
    const parsed = parseResult(text)
    if (parsed && valid(parsed)) return { result: parsed, model }
    if (text != null) events.push(`${label}: no parseable REVIEW_RESULT block`)
    if (text == null && attempt === 1) {
      const fallback = model !== first ? first : live(model) !== model ? live(model) : null
      if (fallback) plan.push(fallback)
    }
  }
  return { result: null, model: null }
}

// One refuter per claim, from the family that did not make it (`madeBy` is the model the lens
// actually ran on, retries included). It keeps that family on its retry, because a same-family
// retry is the check the measured arm never ran; only an unreachable family falls back.
const refuteOne = async (c, lensKey, madeBy, i) => {
  const prompt =
    `Refute this claim made during a cold intake of the ticket below. Default to refuted=true unless ` +
    `you confirm it by opening the cited file, re-running the cited command, or reading the cited doc. ` +
    `A reasoning-only claim is refuted unless you can ground it yourself (say what grounded it).\n\n${ground}\n\n${ticketBlock}\n` +
    `Claim (${c.kind || 'claim'}): ${c.claim}\nPointer: ${c.pointer}\nObserved: ${c.observed}\n` +
    `Measured under: ${c.measured_under || 'not stated'}`
  const model = refuterOverride || other(madeBy)
  const v = await dispatch(prompt, validVerdict, { agentType: REFUTER, model, label: `refute:${lensKey}#${i + 1}`, phase: 'Refute' }, model)
  return {
    refuted: v.result ? v.result.refuted : true,
    family: v.model == null ? null : v.model === madeBy ? 'same' : 'cross',
  }
}

// --- the run ---
const run = async () => {
  phase('Lenses')
  const writerPrompt =
    `You write the lens prompts for a blind fan-out that runs BEFORE a plan-interview on one ticket. ` +
    `Read the ticket, the protocol and the build rules below; you may skim the checkouts to make the jobs concrete.\n` +
    `Write FOUR angles (each a genuinely different framing a single careful engineer would not naturally cover in one pass) ` +
    `and ONE pre-mortem ("this shipped and failed two weeks later — why?", written generically; do not steer it toward ` +
    `mechanisms you suspect). Each job 2–5 sentences, imperative, starting with the angle's name in CAPS then a period. ` +
    `Tell the lens what to read or probe, never what it will find.\n\n${ground}\n\n${ticketBlock}\n` +
    `The build rules every lens works under:\n${BUILD_RULES}\n`
  const w = await dispatch(writerPrompt, validWriter, { agentType: WRITER, model: writerModel, label: 'lens-writer', phase: 'Lenses' }, other(writerModel))
  if (!w.result) return failed('the lens writer produced no usable jobs after one retry')

  const lenses = [
    ...w.result.angles.slice(0, 4).map((x, i) => ({ key: x.key, job: x.job, model: lensOverride || resolve(ANGLE_TIERS[i]) })),
    { key: 'premortem', job: w.result.premortem, model: lensOverride || resolve(PREMORTEM_TIER) },
  ]
  const results = await pipeline(
    lenses,
    async (l) => {
      const prompt =
        `You are one lens in a fan-out that runs BEFORE a plan-interview on this ticket. Your job: ${l.job}\n` +
        `Return claims, each with evidence. A reasoning-only claim is dropped unless a refuter can ground it. Max 6 claims.\n\n${ground}\n\n${ticketBlock}`
      const r = await dispatch(prompt, validLens, { agentType: LENS, model: l.model, label: `lens:${l.key}`, phase: 'Widen' }, lensOverride ? l.model : other(l.model))
      return { l, r }
    },
    async ({ l, r }) => {
      if (!r.result) return { key: l.key, model: null, status: 'failed', claims: 0, survived: [], sameFamily: 0 }
      const claims = r.result.claims.slice(0, 6)
      const verdicts = await parallel(claims.map((c, i) => () => refuteOne(c, l.key, r.model, i)))
      const survived = claims
        .filter((c, i) => verdicts[i] && verdicts[i].refuted === false)
        .map((c) => ({
          claim: c.claim,
          pointer: c.pointer,
          observed: c.observed,
          angle: l.key,
          kind: c.kind || 'probed-fact',
          measured_under: c.measured_under || '',
          status: 'unrefuted',
        }))
      const sameFamily = verdicts.filter((v) => v && v.family === 'same').length
      log(`${l.key} (${r.model}): ${survived.length}/${claims.length} survive`)
      return { key: l.key, model: r.model, status: 'ok', claims: claims.length, survived, sameFamily }
    },
  )
  const ran = results.filter((x) => x && x.status === 'ok')
  const pool = ran.flatMap((x) => x.survived)
  const lensSummary = results.map((x) => ({
    key: x.key,
    model: x.model,
    status: x.status,
    claims: x.claims,
    survived: x.survived.length,
    refuter: x.status !== 'ok' ? null : x.sameFamily ? 'same-family' : 'cross',
  }))
  if (ran.length === 0) return { ...failed('every lens failed after one retry'), lenses: lensSummary }
  const sameKeys = ran.filter((x) => x.sameFamily).map((x) => x.key)
  const unavailable = secondDown() ? ` (${SECOND} unavailable)` : ''
  const refuter = !twoFamilies
    ? 'same-family (configured)'
    : sameKeys.length === 0
      ? `cross (${FIRST}/${SECOND} alternating)`
      : sameKeys.length === ran.length
        ? `same-family${unavailable}`
        : `same-family for ${sameKeys.join(', ')}${unavailable}; cross for the rest`
  return {
    issue,
    status: ran.length === lenses.length ? 'complete' : 'partial',
    reason: ran.length === lenses.length ? '' : `${lenses.length - ran.length} of ${lenses.length} lenses failed after one retry`,
    refuter,
    lenses: lensSummary,
    pool,
    events,
  }
}

// Whole-run wall-clock ceiling (#916 D-9), the same race intake-review.mjs uses per agent. agent()
// has no abort, so agents past the ceiling keep running in the background; the caller simply
// stops waiting and proceeds without the pool.
let timer
const ceiling = new Promise((resolveCeiling) => {
  timer = setTimeout(() => resolveCeiling(failed(`exceeded ${ceilingMin} min`)), ceilingMs)
})
const out = await Promise.race([run(), ceiling])
clearTimeout(timer)
return out
