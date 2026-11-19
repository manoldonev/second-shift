export const meta = {
  name: 'review-toolkit-intake-fanout',
  description:
    'Intake fan-out for the Explore stage of /intake-toolkit:intake: a sealed lens writer, then four angles and a pre-mortem working blind. Returns every claim the lenses made, each unverified, for the interviewer to check from its pointer.',
  phases: [
    { title: 'Lenses', detail: 'intake-lens-writer writes the five jobs' },
    { title: 'Widen', detail: 'four angles and a pre-mortem, blind' },
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
// config.reviewers.modelOverrides (bare-keyed) wins over it.
const FANOUT_MODEL = {
  'review-toolkit:intake-lens-writer': 'reasoning',
  'review-toolkit:intake-lens': 'reasoning',
}

const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// The build rules every lens works under. Given to the lens writer verbatim.
const BUILD_RULES = [
  "Independence. Each agent works blind to the others' conclusions. No shared \"war room\" context; it reproduces the self-agreement the lane's never-resume-a-review rule exists to prevent.",
  'Diversity of angle. Each agent gets a different job or framing, never the same prompt N times.',
  'Evidence is the only thing passed between agents. A probe result, a repro, a cited line or commit. Never an opinion or a vote. Anything that travels without its evidence is dropped.',
  "Check, don't trust. The interviewer checks each claim from its pointer before it uses it.",
  'Keep by evidence, not consensus. A claim stays because it was measured or reproduced. One reproduced finding outweighs any number of agreeing agents, and two agents that disagree are settled by running the thing.',
].map((r, i) => `${i + 1}. ${r}`).join('\n')

// args (assembled in-session by /intake's Explore stage):
//   issue      — the ticket id (drives the prompts)
//   issueBody  — the full ticket text (lenses never re-fetch it); on a split, the parent's body
//                plus its slice list, so the lenses see the seams
//   knowledgeSource — optional: the consumer's knowledge provider's answer, as the receipt carries
//                it. Threaded into the lens writer's prompt ONLY: the lenses stay blind to it and
//                check their claims against the code.
//   readRoot   — optional ABSOLUTE path of the checkout the ticket targets
//   checkouts  — optional [{ path, role }]: ABSOLUTE paths of other repos the change meets (a
//                frontend that calls this backend, a client, a sibling service), with what each is
//   protocol   — optional ABSOLUTE paths of the protocol text every agent works under (the
//                intake skill's files and interviewing-baseline's)
//   probeDir   — optional ABSOLUTE path probes may write to (default: no file writes)
//   config     — the consumer config (reviewers.modelOverrides / reviewers.tierMap)
//   ceilingMs  — whole-run wall-clock ceiling (default 30 min)
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { issue, issueBody = '', knowledgeSource = '', readRoot = '', checkouts = [], protocol = [], probeDir = '', config = {}, ceilingMs = 30 * 60 * 1000 } = a
if (!issue) throw new Error('intake-fanout workflow: args.issue is required')
if (!issueBody) throw new Error('intake-fanout workflow: args.issueBody is required (the lenses reason over it)')

const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const tierMap = { ...DEFAULT_TIER_MAP, ...((config && config.reviewers && config.reviewers.tierMap) || {}) }
const resolve = (tier) => tierMap[tier] || tier
const WRITER = 'review-toolkit:intake-lens-writer'
const LENS = 'review-toolkit:intake-lens'
const modelOf = (agentType) => resolve(modelOverrides[bare(agentType)] || FANOUT_MODEL[agentType])
const writerModel = modelOf(WRITER)
const lensModel = modelOf(LENS)
// Every retry runs here, so an override naming a model the account cannot reach still gets one
// attempt on a model it can.
const RETRY_MODEL = resolve('reasoning')
const events = []

const ceilingMin = Math.round(ceilingMs / 60000)
const failed = (reason) => ({ issue, status: 'failed', reason, lenses: [], pool: [], events })

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
const knowledgeBlock = String(knowledgeSource || '').trim()
  ? `The consumer's knowledge source answered a question about this ticket before the fan-out. Use it to make the jobs ` +
    `concrete — a page it cites, a claim worth testing against the code — never as settled fact, and never quote it to a ` +
    `lens as a conclusion: the lenses do not see it, and check against the code.\n\n${knowledgeSource}\n\n`
  : ''

// --- text contract: a sentinel + fenced json block, parsed here (explorer/emitter) ---
const parseReviewResult = (text) => {
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

// Dispatch with ONE retry, on RETRY_MODEL, when the first attempt is dead or unparseable.
const dispatch = async (prompt, valid, opts) => {
  const plan = [opts.model, RETRY_MODEL]
  for (let attempt = 0; attempt < plan.length; attempt++) {
    const model = plan[attempt]
    const label = attempt === 0 ? opts.label : `${opts.label} (retry)`
    const text = await tryAgent(prompt, { ...opts, model, label })
    const parsed = parseReviewResult(text)
    if (parsed && valid(parsed)) return { result: parsed, model }
    if (text != null) events.push(`${label}: no parseable REVIEW_RESULT block`)
  }
  return { result: null, model: null }
}

// --- the run ---
const run = async () => {
  phase('Lenses')
  const writerPrompt =
    `You write the lens prompts for a blind fan-out that runs BEFORE the intake interview on one ticket. ` +
    `Read the ticket, the protocol and the build rules below; you may skim the checkouts to make the jobs concrete.\n` +
    `Write FOUR angles (each a genuinely different framing a single careful engineer would not naturally cover in one pass) ` +
    `and ONE pre-mortem ("this shipped and failed two weeks later — why?", written generically; do not steer it toward ` +
    `mechanisms you suspect). Each job 2–5 sentences, imperative, starting with the angle's name in CAPS then a period. ` +
    `Tell the lens what to read or probe, never what it will find.\n\n${ground}\n\n${ticketBlock}\n` +
    knowledgeBlock +
    `The build rules every lens works under:\n${BUILD_RULES}\n`
  const w = await dispatch(writerPrompt, validWriter, { agentType: WRITER, model: writerModel, label: 'lens-writer', phase: 'Lenses' })
  if (!w.result) return failed('the lens writer produced no usable jobs after one retry')

  phase('Widen')
  const lenses = [
    ...w.result.angles.slice(0, 4).map((x) => ({ key: x.key, job: x.job })),
    { key: 'premortem', job: w.result.premortem },
  ]
  const results = await parallel(
    lenses.map((l) => async () => {
      const prompt =
        `You are one lens in a fan-out that runs BEFORE the intake interview on this ticket. Your job: ${l.job}\n` +
        `Return claims, each with evidence. Every claim needs a pointer the interviewer can open or run. Max 6 claims.\n\n${ground}\n\n${ticketBlock}`
      const r = await dispatch(prompt, validLens, { agentType: LENS, model: lensModel, label: `lens:${l.key}`, phase: 'Widen' })
      if (!r.result) return { key: l.key, model: null, status: 'failed', claims: [] }
      const claims = r.result.claims.slice(0, 6).map((c) => ({
        claim: c.claim,
        pointer: c.pointer,
        observed: c.observed,
        angle: l.key,
        kind: c.kind || 'probed-fact',
        measured_under: c.measured_under || '',
        status: 'unverified',
      }))
      log(`${l.key} (${r.model}): ${claims.length} claims`)
      return { key: l.key, model: r.model, status: 'ok', claims }
    }),
  )
  const ran = results.filter((x) => x && x.status === 'ok')
  const lensSummary = results.map((x) => ({ key: x.key, model: x.model, status: x.status, claims: x.claims.length }))
  if (ran.length === 0) return { ...failed('every lens failed after one retry'), lenses: lensSummary }
  return {
    issue,
    status: ran.length === lenses.length ? 'complete' : 'partial',
    reason: ran.length === lenses.length ? '' : `${lenses.length - ran.length} of ${lenses.length} lenses failed after one retry`,
    lenses: lensSummary,
    pool: ran.flatMap((x) => x.claims),
    events,
  }
}

// Whole-run wall-clock ceiling, the same race intake-review.mjs uses per agent. agent()
// has no abort, so agents past the ceiling keep running in the background; the caller simply
// stops waiting and proceeds without the pool.
let timer
const ceiling = new Promise((resolveCeiling) => {
  timer = setTimeout(() => resolveCeiling(failed(`exceeded ${ceilingMin} min`)), ceilingMs)
})
const out = await Promise.race([run(), ceiling])
clearTimeout(timer)
return out
