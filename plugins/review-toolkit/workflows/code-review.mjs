export const meta = {
  name: 'review-toolkit-code-review',
  description:
    "Reviewer fan-out for review-lead — used by the dev-pipeline review lane and by standalone /review-lead. Dispatches the selected specialist reviewers as parallel agent() calls and returns their structured findings. On panel 'substantial' the seats run at the reasoning tier. Synthesis (dedup, triage, Scope Completeness Gate, cross-reviewer self-check) is NOT done here — it stays in the caller's session on the caller's model, per review-lead's Synthesis Rules.",
  phases: [{ title: 'Review', detail: 'one agent() per selected specialist reviewer' }],
}

// {agentType: model} — the cost tier each reviewer runs at. The source of truth is
// each agent's own frontmatter (the plugin-shipped agent's `model:`); this table
// restates it because Workflow scripts can't read files, and passing `model` explicitly
// guarantees the cheap tier holds regardless of how agent() resolves an omitted model.
// Change a reviewer's tier in its agent frontmatter AND here, in lockstep.
// (check-model-tiers.sh validates these tiers — tolerant of bare and plugin:-qualified
// keys.) Plugin-shipped reviewers are keyed by their QUALIFIED name (namespaces.md);
// repo-local reviewers (config reviewers.add, e.g. acme's orders-reviewer) are
// dispatched bare and get their tier from args.config.reviewers.modelOverrides (or the
// 'sonnet' default), NOT this table.
// Its qualified keys are ALSO the resolution source for the bare-name normalization
// below — so a key removed from here stops normalizing that reviewer as well as
// stopping its tier from resolving.
// Tier -> dispatch token. INLINED because the Workflow sandbox forbids imports; the
// authority is the `## Tier alphabet` table in ../model-tiering.md, and
// check-model-tiers.sh holds this copy against it (TIER-MAP-DRIFT) so the duplication
// is checked rather than merely regretted. Keys are UNQUOTED deliberately: the guard's
// entry scans match a quoted key followed by a quoted value, so quoting these would make
// every tier read as a dispatch-table entry and be reported DANGLING. (Writing that shape
// out here would itself trip the scan — a comment quoting a matched shape is an instance
// of it.)
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
  cross: 'fable',
}

const REVIEWER_MODEL = {
  'review-toolkit:security-reviewer': 'reasoning',
  'review-toolkit:performance-reviewer': 'code',
  'review-toolkit:maintainability-reviewer': 'code',
  'review-toolkit:complexity-reviewer': 'code',
  'review-toolkit:test-coverage-reviewer': 'code',
  'review-toolkit:unit-test-mutation-reviewer': 'code',
  'review-toolkit:db-reviewer': 'code',
  'review-toolkit:pipeline-reviewer': 'code',
  'review-toolkit:scope-completeness-reviewer': 'reasoning',
  'review-toolkit:a11y-reviewer': 'code',
  'design-toolkit:design-faithful-reviewer': 'code',
  'design-toolkit:figma-faithful-reviewer': 'code',
  // The transcription sink dispatches through this table like every other agent (#351).
  // It used to carry a hardcoded inline `model: 'haiku'`, which no consumer could
  // retarget or override — the one governed-set gap this ticket closes.
  'review-toolkit:structured-emitter': 'emit',
}

// {agentType: tier} on `panel: 'substantial'` only (#992): every specialist seat runs at
// `reasoning`. It replaces REVIEWER_MODEL at the TABLE layer and nowhere else, so a consumer
// modelOverrides entry still wins and a seat not named here keeps its REVIEWER_MODEL tier. The
// agents' frontmatter is unchanged, which is what keeps standalone /review-lead on its cheaper
// seats. NOT a frontmatter lockstep: these tiers deliberately differ from the agents' own, so
// check-model-tiers.sh lifts this block out of its frontmatter scans and holds it against the
// `## Substantial panel` table in ../model-tiering.md instead.
const SUBSTANTIAL_MODEL = {
  'review-toolkit:security-reviewer': 'reasoning',
  'review-toolkit:performance-reviewer': 'reasoning',
  'review-toolkit:maintainability-reviewer': 'reasoning',
  'review-toolkit:complexity-reviewer': 'reasoning',
  'review-toolkit:test-coverage-reviewer': 'reasoning',
  'review-toolkit:unit-test-mutation-reviewer': 'reasoning',
}

// Bare (unqualified) agent name — tolerant of both `plugin:agent` and bare forms.
// Used for the special-case dispatch branches below and for modelOverrides lookup
// (config keys reviewers by bare name, per second-shift.config.schema.json).
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// Defensive dispatch-name normalization (#434). This script passes agentType to agent()
// verbatim, so a caller that names a plugin reviewer BARE produces `agent type not found`
// for every reviewer it selected — and those deaths return in the died-after-retry shape,
// which synthesis renders as a fully dark panel rather than as a broken dispatch. The
// failure therefore reads as "nothing to review" instead of "nothing ran". A stale or
// hand-edited caller must degrade to WORKING, not to a silent zero-coverage review.
//
// Reverse index over REVIEWER_MODEL's qualified keys. A bare name matching exactly ONE
// qualified key resolves to it; a bare name matching two (two plugins shipping the same
// basename) is deliberately left alone — guessing between roots is worse than dispatching
// what the caller asked for. Repo-local `reviewers.add` names match no key and stay bare,
// exactly as today.
const QUALIFIED_BY_BARE = Object.keys(REVIEWER_MODEL).reduce((acc, key) => {
  if (!key.includes(':')) return acc
  const b = bare(key)
  acc[b] = b in acc ? null : key
  return acc
}, {})

const resolveAgentType = (t) => (String(t).includes(':') ? String(t) : QUALIFIED_BY_BARE[String(t)] || String(t))

// The Atlassian MCP tools scope-completeness-reviewer fetches the JIRA ticket with
// are DEFERRED in a Workflow subagent and their
// namespace depends on HOW the MCP was registered: a top-level `mcpServers` entry
// exposes `mcp__atlassian__*`; a plugin-bundled server exposes
// `mcp__plugin_atlassian_atlassian__*`; the claude.ai Atlassian (Rovo) integration
// exposes `mcp__claude_ai_Atlassian_Rovo__*`. Select ALL THREE namespaces — `select:`
// returns the names that exist and silently ignores the absent ones, so the same
// dispatch works regardless of provenance. Hardcoding one prefix made the Scope
// Completeness Gate unsatisfiable for consumers registered under the other two.
// (The retired figma.mjs engine documented and mirrored the same both-spellings
// discipline — see docs/namespaces.md.)
const ATLASSIAN_MCP_TOOLSEARCH =
  'select:mcp__atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__claude_ai_Atlassian_Rovo__getJiraIssue,' +
  'mcp__atlassian__getAccessibleAtlassianResources,mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources,mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources,' +
  'mcp__atlassian__getJiraIssueRemoteIssueLinks,mcp__plugin_atlassian_atlassian__getJiraIssueRemoteIssueLinks,mcp__claude_ai_Atlassian_Rovo__getJiraIssueRemoteIssueLinks'

// Findings contract. Kept permissive (only severity/description/confidence required)
// so reviewers don't burn retries on over-strict shapes; file/line/title are optional.
//
// LOCKSTEP, and this file is the CANONICAL side. stall-probe.mjs and tool-discipline-probe.mjs
// each declare their own copy because the Workflow runtime gives them no `import`. Those two
// exist to reproduce production dispatch EXACTLY, which is worthless if their schema has
// drifted from this one — a probe that measures a different contract measures nothing.
// (design-sync.mjs referenced the schema only in a comment, was never a member, and retired
// with #574.) Edit here, edit all three.
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

// args (assembled in-session by the caller, which has Bash to size the diff and route):
//   worktree     — absolute path the reviewers run git against
//   base, head   — git refs bounding the review: a branch, a ref, or a SHA — all accepted.
//                  The range is rendered THREE-DOT (`<base>...<head>`), which is merge-base
//                  semantics by definition: git diffs from merge-base(base, head) to head.
//                  So a `base` BRANCH whose tip has advanced past the branch point does not
//                  leak its own newer commits into the reviewed diff. Under two-dot they
//                  render as deletions and reviewers report the branch as reverting work it
//                  never touched (observed: two false BLOCKERs, #130).
//                  Callers passing an explicit merge-base SHA are unaffected — when base is
//                  already an ancestor of head, merge-base(base, head) == base, so
//                  `base...head` and `base..head` are the same range.
//                  The merge-base is resolved BY GIT at reviewer-run time via three-dot, not
//                  computed here: Workflow scripts have no Bash/filesystem access.
//   issue        — GitHub issue number (drives scope-completeness; omit to skip it)
//   spec         — optional committed decision record path; scope-completeness scores its rows
//   reviewers    — array of agentType strings already selected per review-lead routing
//   changedFiles — array of changed paths (context for the prompt)
//   prContext    — optional free-text branch/PR context
//   requiredSeats — optional array of agentType strings dispatched IN ADDITION to `reviewers`
//                  (#992). Never trims either list; the union is deduped on the resolved name.
//   optInSeats   — optional array of agentType strings whose findings never block: a `blocker`
//                  severity from one of them is rewritten to `major` after the result parses, so
//                  an opt-in seat reaches the verdict as a note. Matched on the bare name.
//   panel        — optional; 'substantial' runs the seats at SUBSTANTIAL_MODEL's tiers and returns
//                  `seats[]` in place of `reviewers[]`. Absent, the dispatch and the return are
//                  exactly what they were before #992.
// `args` arrives as the value passed to Workflow's `args` input. Defensive: it may
// be an object, or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { worktree, base, head, issue, spec, reviewers = [], requiredSeats = [], optInSeats = [], panel, changedFiles = [], prContext = '', config = {} } = a
const substantial = panel === 'substantial'
// Per-reviewer model-tier overrides from the consumer config (bare-keyed).
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
// Consumer tier retargeting, MERGED per tier over the shipped default (#351): a config
// naming one tier leaves the rest alone, so a config that sets none dispatches exactly
// as it did before this seam existed.
const tierMap = { ...DEFAULT_TIER_MAP, ...((config && config.reviewers && config.reviewers.tierMap) || {}) }
// One resolution path for EVERY dispatch in this file. An override or table value that
// names a tier resolves through the map; anything else is already a raw dispatch token
// (the closed union config-lint enforces) and passes through untouched. The substantial
// table sits BETWEEN the override and REVIEWER_MODEL: the override still wins (#992 D-5).
const modelFor = (agentType) => {
  const declared = modelOverrides[bare(agentType)] || (substantial && SUBSTANTIAL_MODEL[agentType]) || REVIEWER_MODEL[agentType] || 'code'
  return tierMap[declared] || declared
}
if (!worktree || !base || !head) {
  throw new Error('code-review workflow: args.worktree, args.base and args.head are required')
}
if (panel !== undefined && !substantial) {
  throw new Error(`code-review workflow: args.panel must be 'substantial' or absent, got ${JSON.stringify(panel)}`)
}
if (!Array.isArray(requiredSeats)) {
  throw new Error('code-review workflow: args.requiredSeats must be an array of agentType strings')
}
if (!Array.isArray(optInSeats)) {
  throw new Error('code-review workflow: args.optInSeats must be an array of agentType strings')
}
const optInSet = new Set(optInSeats.map((r) => bare(r)))
// An opt-in seat's result reaches synthesis with no `blocker`: the cap is applied to the parsed
// result, never to the prompt, so it holds whatever the seat wrote.
const capOptIn = (requested, result) =>
  optInSet.has(bare(requested)) && result && Array.isArray(result.findings)
    ? { ...result, findings: result.findings.map((f) => (f && f.severity === 'blocker' ? { ...f, severity: 'major' } : f)) }
    : result
// Relaxed only for a non-empty requiredSeats (#992 D-10): a call with
// neither still needs a non-empty reviewers[], which is what standalone review-lead relies on.
if ((!Array.isArray(reviewers) || (reviewers.length === 0 && requiredSeats.length === 0))) {
  throw new Error('code-review workflow: args.reviewers must be a non-empty array of agentType strings')
}
// The seats this run dispatches. Without requiredSeats or a panel this is `reviewers` verbatim
// (AC-4). Otherwise it is the union, deduped on the RESOLVED name so a bare and a qualified
// spelling of one reviewer dispatch once; the first spelling seen is the one returned.
const seatNames = (() => {
  if (!substantial && requiredSeats.length === 0) return reviewers
  const seen = new Set()
  return [...reviewers, ...requiredSeats].filter((r) => {
    const k = resolveAgentType(r)
    if (seen.has(k)) return false
    seen.add(k)
    return true
  })
})()
// scope-completeness-reviewer's prompt embeds the issue number; without it the
// prompt degrades to `#undefined` / `gh issue view undefined`. The caller is
// supposed to include this reviewer only when an issue is referenced — make that
// contract explicit here rather than silently producing a broken dispatch.
if (seatNames.some((r) => bare(r) === 'scope-completeness-reviewer') && !issue) {
  throw new Error('code-review workflow: scope-completeness-reviewer requires args.issue (GitHub issue number or JIRA ticket key)')
}

// Workflow runtime globals used below — injected by the Workflow runtime, not
// imported: log(), phase(), parallel(), agent(). See the Workflow tool API.
// THREE-DOT is load-bearing (#130) — see the base/head contract above. Do not
// "simplify" to two-dot: it re-admits base-only commits as phantom deletions.
const range = `${base}...${head}`
const fileList = changedFiles.length ? changedFiles.join(', ') : '(see diff)'
// ROOT CAUSE (measured by workflows/stall-probe.mjs — refines the earlier #168/#182 analysis):
// reviewers die "without calling StructuredOutput" because they exhaust their turn budget
// GROUNDING THE ABSENCE of findings — opening files across the whole diff to prove nothing is
// wrong — and die before they emit. Every reviewer inherits `reviewer-baseline`, whose grounding
// precondition makes "no findings" carry the same open-and-cite requirement as a real finding;
// on a large diff that means reading many files just to assert a clean verdict.
//
// The earlier analysis correctly identified the absence-grounding requirement as the cost driver,
// but attributed it to PROSE volume (writing a long write-up before the structured call). The probe
// falsified that: the cost is the absence-grounding EXPLORATION (the tool calls that open files),
// not the output shape. Evidence (range 2583ee3, a 1326-line low-signal diff, maintainability-reviewer):
//   - Signal-scaled and real: a TINY low-signal diff never stalls (0/8); a LARGE one does (~57%
//     across runs). The driver is diff SIZE under a clean verdict — "ground the absence across the
//     whole diff" — exactly as predicted.
//   - NOT the prose framing: STRUCTURED_OUTPUT_FIRST (emit structured first, no prose preamble) did
//     NOT move the rate (2/8 -> 2/8). Relocating grounding into schema fields (a reviewer-baseline
//     rewrite) did NOT move it either.
//   - More budget only half-helps at ~2x cost: opus dropped it to ~25% but still stalled.
//   - A DISPATCH-TIME NUDGE fixes it: a triage nudge at the dispatch took maintainability-reviewer
//     from ~50% to 0/12 AND cut tokens ~45% — the wasted exhaustive exploration WAS the problem.
//     Placement is load-bearing: the identical instruction sitting in the inherited reviewer-baseline
//     doc did NOT work (4/6 uncured); only the dispatch-time nudge did. That nudge's "read less"
//     half was later measured against a public set of PRs with known bugs and retired (see
//     GENERIC_READ below); its numbered emit deadline is the half that stays.
//
// Mitigations, in order: (1) GENERIC_READ + PROGRESSIVE_EMIT below — the PRIMARY fix; a numbered
// first-emit deadline so the reviewer emits instead of stalling. (2) STRUCTURED_OUTPUT_FIRST — emit the
// structured verdict first; kept (cheap, right on principle) though it is not the stall cure. (3) the
// one-shot retry in dispatchReviewer() recovers residual stochastic deaths, and since #855 it
// ESCALATES against the deterministic one: an attempt that returns EMPTY text is retried with
// ESCALATED_EMIT appended, never bit-identically, because a verbatim retry of a turn-cap death just
// reproduces it. (4) the dark-reviewer contract (review-lead Step 4b) backstops what still goes
// dark: the SESSION must re-dispatch once, and its edge over rung 3 is the NARROWING to that
// reviewer's domain — the part this file cannot do, because it dispatched against the whole range —
// and only what survives THAT is a coverage gap. A gap is
// then a NOTE for most reviewers, but a hard "Ready to merge? = No" for security (whose dimension
// the lead pass skipped precisely because this fan-out spawned it) and a VOID for design fidelity on
// an armed spec. When the WHOLE panel goes dark, review-lead voids the round and answers no merge
// question at all (its Step 4b-void). Guards:
// workflows/runtime-shim-selftest.mjs executes THIS body against the real ladder;
// workflows/null-reviewer-selftest.mjs Case F pins the load-bearing tokens + emit wiring. reviewer-baseline carries the same principle as documented
// contract ("Proportionate grounding"); this file is the operative delivery.
// --- explorer/emitter transport (the structural stall fix; #169) ---
// The stall class is `schema AND can-explore` in one agent; measured on plan-reviewer (opus,
// k=8, worst-case plan): schema-forced 7/8 deaths, 0 usable; schema-free text contract 0/8,
// 8/8 usable at a third of the tokens, detection parity 6.75 vs 6.63. Explorers dispatch
// schema-FREE and end with a sentinel + fenced JSON block parsed here; the schema objects
// become in-script validators, and only the transcription-only structured-emitter agent
// (tools: [], maxTurns: 2) ever carries a schema — fired solely when a sentinel-bearing
// block failed to parse. Missing sentinel = truncation = dark, never the emitter.
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
    { agentType: 'review-toolkit:structured-emitter', model: modelFor('review-toolkit:structured-emitter'), label: `${opts.label} (emit)`, phase: 'Review', schema: opts.schema },
  )

const FINDINGS_EPILOGUE =
  '\n\nWrite your review, grounding as much as you need. Your FINAL output MUST end with this' +
  ' sentinel line followed by one fenced json block and NOTHING after it:\n\n' +
  'REVIEW_RESULT\n```json\n{ "verdict": "approve|approve-with-nits|request-changes|block",' +
  ' "findings": [ { "severity": "blocker|major|minor|nit", "file": "...", "line": 0, "title": "...",' +
  ' "description": "...", "confidence": 0 } ], "suppressed": [] }\n```'

// The generic branch's own nudge. It replaced a bounding nudge that told the seat to open files
// only to ground a finding it already intended and to stop exploring by its 8th tool call: that
// nudge cured the turn-cap deaths it was written for and was then measured against a public set
// of PRs with known bugs, where the seats it bound found less than a plain prompt did, and every
// bug humans later found in an approved PR sat in an unchanged file — a caller of the changed
// unit. The numbered deadline stays, because the deadline was the half that cured the deaths (see
// the PROGRESSIVE_EMIT block below for the evidence); the "read less" half goes.
const GENERIC_READ =
  ' Read the callers and consumers of each changed unit in unchanged files; the bug is usually' +
  ' there when the diff itself reads fine. Write your first complete REVIEW_RESULT block by your' +
  ' 8th tool call, then keep reading and re-emit the whole block each time you learn something.'

// The nudge for every dispatched seat: the exhaustive two (scope-completeness, unit-test-mutation)
// cannot take a bounding nudge without losing the coverage that IS their deliverable (#183), and
// the generic seats now take the same cure for the same death mode — the turn-budget wall — so the
// wall truncates a result instead of erasing one. Not "explore less", but "write down what you
// have as you go".
//
// Raising the cap does NOT fix this and has now been measured twice. #175 raised both agents
// 15 -> 30; at the new cap scope-completeness-reviewer still died on BOTH attempts of a
// standalone review-lead run (31 and 33 tool calls, final text "I'll fetch the issue and the
// diff.", agents_error 0). The control in that same fan-out is security-reviewer: opus,
// effort high, HALF the cap (maxTurns 15) — and it completed, because its agent doc carries an
// explicit turn-numbered emit deadline. The variable is the deadline, not the budget: an agent
// told to enumerate exhaustively and never told when to stop will spend any finite budget.
//
// A truncated result can only under-claim, which is what makes early emission safe:
//   - scope-completeness-reviewer is fail-closed by contract ("Default to FAIL when the evidence
//     is ambiguous"), so its honest early skeleton is every item [unsatisfied], refined upward
//     only as evidence lands. A cut-short result over-reports FAIL, never a false PASS.
//   - unit-test-mutation-reviewer's unreached mutants are simply absent, and an absent mutant
//     never blocks (execution-verified blocking is the propose-mode orchestrator's, not this fan-out's).
//   - a generic seat's early block is the findings it has so far; a death after it loses the
//     findings it had not reached, never the ones it had. The seat that is still exploring at the
//     wall with nothing written is the one shape that loses everything, and it is the shape this
//     nudge forbids.
// This does NOT weaken the dark path (#175's stated non-fix): nothing transcribes partial text
// and no parser changes — the AGENT emits a well-formed block, and a missing sentinel is still
// dark. parseReviewResult() is already last-match-wins, which is what makes re-emission free.
//
// LOCKSTEP, canonical side (#283, narrowed from a triple in #348). Same cannot-`import` class
// as FINDINGS_SCHEMA above: intake-review.mjs declares its own copy of this nudge for its
// exhaustive-class reviewer, and a copy that drifts silently re-opens the #175/#183
// turn-cap-death class one file at a time.
// LOCKSTEP-BEGIN progressive-emit
const PROGRESSIVE_EMIT =
  ' EMIT AS YOU GO — do NOT save your result for the end. As soon as you have enumerated your' +
  ' items (before classifying them), write a COMPLETE REVIEW_RESULT block reflecting what you' +
  ' know so far, then keep working and re-emit the whole block each time you learn something.' +
  ' Emitting more than one block is expected here and overrides the single-block instruction' +
  ' below: the LAST complete block wins, so an early one costs you nothing and refinement is' +
  ' free. Your enumeration must stay exhaustive — this governs when you write, never how much' +
  ' you cover. Budget your turns so the final block is written well before your limit: a review' +
  ' you never emit is scored exactly like a review that never ran, and your entire domain is' +
  ' then recorded as unverified.'
// LOCKSTEP-END progressive-emit

// The RETRY nudge, appended only when attempt 0 came back with EMPTY text (#855).
//
// Until this existed the retry was BIT-IDENTICAL — same prompt, same tier, same agent — which is
// worthless against a death that is deterministic rather than stochastic. The ROOT CAUSE block
// above says so, and deferred the cure to the session ("the SESSION must re-dispatch once with a
// changed prompt"). That works and stays as the third rung (review-lead Step 4b), but it spends a
// full dark round first, and on a design-ARMED spec that round is VOID rather than merely reduced
// — the fidelity reviewer's darkness answers no merge question at all. Doing it here on attempt 2
// is the same cure one rung earlier.
//
// Appended ONLY on empty text, never on a parse miss. The two deaths want opposite things: an
// agent that wrote an unparseable block needs the FORMAT restated, which the emitter rung below
// already owns; an agent that wrote nothing needs permission to stop reading. Telling a
// parse-miss agent to cut its exploration short would trade a recoverable result for a thinner one.
//
// The number restates GENERIC_READ's 8 as an absolute, because this attempt has evidence the
// first one blew past it: the agent already demonstrated that its own reading of "by your 8th
// tool call" did not bind. Measured on the run that motivated this (#855): the same agent, same
// tier, same cap, died twice at 18 tool calls with empty text, then returned a grounded verdict in
// 20 when re-dispatched with a numbered deadline and a narrowed ask.
const ESCALATED_EMIT =
  ' RETRY — YOUR PREVIOUS ATTEMPT AT THIS EXACT REVIEW DIED HAVING WRITTEN NOTHING. It ran out of' +
  ' turns still exploring, so its entire domain was recorded as unverified. Do not repeat that' +
  ' shape. STOP EXPLORING NOW and emit a COMPLETE result from what you can establish in your' +
  ' first 8 tool calls, even if that is approve with no findings and even if you feel' +
  ' under-grounded. Name anything you could not reach as `unable to verify — pointer needed:' +
  ' <specific file or fact>` rather than opening it. You may re-emit the whole block later if you' +
  ' learn more — the LAST complete block wins — but the first one must exist before you read' +
  ' anything further.'

// Per-reviewer wall-clock ceiling (#219). The Workflow runtime's own agent-stall loop
// (multiple attempts × a no-progress window) can let a genuinely wedged reviewer burn
// ~90 min before agent() settles — observed in run #183, where one dark reviewer added
// ~90 min to a review round whose five other reviewers had finished in minutes. That loop is
// a RUNTIME property: it is NOT reachable from this script (agent() exposes no
// timeout/abort option, and there is no AbortController in the Workflow sandbox). So we
// bound it in userland — race each reviewer's dispatch against this ceiling and, on
// timeout, resolve to the SAME died-after-retry dark marker the caller already handles
// (a ceiling timeout is a SUB-CAUSE of `died-after-retry`, not a new dark case). The
// orphaned agent() keeps running in the runtime until its own stall loop terminates it,
// but it does NOT block parallel()/the fan-out from returning (the runtime does not wait
// on an orphaned pending promise). Single tunable knob.
//   15 min: >=2.5x the largest observed healthy single-reviewer turn (bounded above by the
//   ~6 min aggregate fan-out wall-clock of runs #195/#218), ~6x tighter than the #183 wedge.
//   Raise it if a future large-diff run legitimately needs a longer single reviewer turn.
const REVIEWER_CEILING_MS = 15 * 60 * 1000

// One seats[] entry per requested seat on the substantial panel (#992).
const seatEntry = (agentType, model, status, findings, extra = {}) => ({ agentType, model, status, findings, ...extra })

log(`code-review: ${seatNames.length} reviewers over ${range} in ${worktree}${substantial ? ' (substantial panel)' : ''}`)
phase('Review')

// Cost discipline. The Workflow runtime enforces the operator's turn token budget
// (the "+Nk" launch directive) across every agent() call in the run — all three
// review rounds draw on one shared pool — and makes agent() throw once it is
// spent; the per-reviewer .catch below already turns that into a forwarded error
// rather than a crash. Surface the posture, and if the budget is already spent,
// skip the fan-out cleanly instead of dispatching calls that will all throw.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left before fan-out`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping reviewer fan-out (synthesis sees zero reviewers)')
    // The seats[] form (#992 OR-1): every requested seat is listed dark rather than omitted, so
    // a caller counting darkness needs no second list.
    if (substantial) {
      return { range, worktree, seats: seatNames.map((s) => seatEntry(s, modelFor(resolveAgentType(s)), 'dark', [])), budgetExhausted: true }
    }
    // budgetExhausted is the dark-reviewer signal for this all-or-nothing skip:
    // the fan-out never dispatched, so `reviewers` is empty by construction (NOT a
    // partial subset) and EVERY selected reviewer is dark. Synthesis treats this
    // distinctly from a single reviewer that died after retry (which is PRESENT in
    // `reviewers` as a failed:true entry). Mirrors intake-review.mjs's budget marker.
    return { range, worktree, reviewers: [], budgetExhausted: true }
  }
}

// The StructuredOutput death class is structurally impossible here (#169): no explorer
// carries a schema, and the emitter cannot explore. The contract-miss ladder below owns retry.

// One reviewer dispatch, with ONE automatic retry when the dispatch dies without
// StructuredOutput. The retry runs INLINE inside this task closure (it awaits a
// second agent() before resolving) so it adds no new task to parallel() and
// inherits the existing concurrency cap automatically.
//   - success (first or second attempt) → { agentType, result } (no flags;
//     a retried success is indistinguishable from a first-try success)
//   - non-StructuredOutput rejection     → { agentType, result: null, error }
//     (today's behavior, no retry)
//   - StructuredOutput death twice        → { agentType, result: null, error,
//     retried: true, failed: true } — flagged so synthesis cannot mistake a dead
//     reviewer for a clean "no findings".
// `requested` is the name the CALLER passed; `dispatched` is what actually reaches agent().
// They differ only when normalization fired. Every object returned from here carries
// `agentType: requested` — NOT the resolved name — because review-lead's Step 4b enumerates
// budget-skipped darkness by comparing the returned set against the set it passed as
// args.reviewers. Handing back a name the caller never selected breaks that comparison, and
// would trade this bug for a quieter one. The log line below is the visibility the whole
// failure class lacked.
const dispatchReviewer = async (requested) => {
  const dispatched = resolveAgentType(requested)
  if (dispatched !== requested) {
    log(`reviewer name normalized: '${requested}' dispatched as '${dispatched}' (plugin reviewers are addressed qualified — docs/namespaces.md rule 2)`)
  }
  // Override (bare-keyed) wins over the table's per-agent default, else 'sonnet'. Keyed on
  // the RESOLVED name, so normalization recovers the reviewer's declared tier too — a bare
  // security-reviewer that fell through to 'sonnet' is a silently downgraded review.
  const model = modelFor(dispatched)
  let prompt
  if (bare(dispatched) === 'scope-completeness-reviewer') {
    // Independence rule (review-lead): evidence ONLY — issue/ticket ref + branch/base.
    // No scope paraphrase, no diff summary; the reviewer fetches the ticket itself.
    // Tracker-branch the fetch (#16): github -> `gh issue view`; jira -> Atlassian MCP.
    const trackerType = (config && config.tracker && config.tracker.type) || 'github'
    const ref = trackerType === 'jira' ? `JIRA ticket ${issue}` : `GitHub issue #${issue}`
    const fetchInstr =
      trackerType === 'jira'
        ? `Fetch the ticket yourself via the Atlassian MCP for key \`${issue}\` (responseContentFormat "markdown"). Do NOT assume the \`mcp__atlassian__*\` prefix — the tools are deferred and their namespace depends on how the MCP was registered. FIRST call ToolSearch with query "${ATLASSIAN_MCP_TOOLSEARCH}" to load whichever of the three Atlassian namespaces this session exposes (\`mcp__atlassian__*\`, \`mcp__plugin_atlassian_atlassian__*\`, or \`mcp__claude_ai_Atlassian_Rovo__*\`), then call the exact \`getJiraIssue\` / \`getAccessibleAtlassianResources\` names it returns; ToolSearch silently omits absent namespaces`
        : `Fetch the issue yourself with \`gh issue view ${issue}\``
    prompt =
      `Verify scope completeness for ${ref}. ` +
      `Branch head \`${head}\` vs base \`${base}\`; repo worktree \`${worktree}\` ` +
      `(run \`git -C ${worktree} diff ${range}\` to see the change). ` +
      `${fetchInstr} and classify each scope item against the diff. ` +
      (spec ? `Decision record: the committed decision record \`${spec}\`. ` : '') +
      `Return your verdict and findings.` +
      PROGRESSIVE_EMIT
  } else if (bare(dispatched) === 'unit-test-mutation-reviewer') {
    prompt =
      `Mutation review in ADVISORY mode on unit tests for this change. ` +
      `Diff scope: \`git -C ${worktree} diff ${range}\`. Changed files: ${fileList}.` +
      (prContext ? ` Context: ${prContext}.` : '') +
      ` Propose mutants and predict survived/untested — LLM prediction ONLY; ` +
      `do NOT apply mutants or run tests (this fan-out has no executor). ` +
      `Blocker-class mutants map to severity \`major\` (never \`blocker\` — only the propose-mode ` +
      `execution-verified gate can block). No Stryker. ` +
      `Return verdict and findings (severity major/minor/nit, file, line, confidence 0-100).` +
      PROGRESSIVE_EMIT
  } else {
    prompt =
      `Review this change in your domain. Diff scope: \`git -C ${worktree} diff ${range}\`. ` +
      `Changed files: ${fileList}.` +
      (prContext ? ` Context: ${prContext}.` : '') +
      ` Return your verdict and a deduplicated list of findings (severity blocker/major/minor/nit, ` +
      `file, line, confidence 0-100). Ignore stylistic issues handled by formatter/linter.` +
      GENERIC_READ +
      PROGRESSIVE_EMIT
  }
  // Prompt-branch dispositions (doc, transport-independent): every branch carries PROGRESSIVE_EMIT,
  // the "write as you go" cure for the turn-budget death; the generic branch carries GENERIC_READ
  // ahead of it (read the changed unit's callers, first block by the 8th tool call). No branch
  // carries a bounding nudge any more: "read less" was measured to lose the callers where the bugs
  // that reached production sat. null-reviewer-selftest Case F pins the wiring.
  //
  // Explorer/emitter ladder. Dark-marker shapes are UNCHANGED from the schema era — review-lead
  // synthesis keys on { result: null } + { retried: true, failed: true } and must keep doing so.
  let lastText = null
  for (let attempt = 0; attempt < 2; attempt++) {
    // The retry ESCALATES rather than repeating (#855) — but only against the empty-text death,
    // which is the deterministic one. `lastText` is unset on attempt 0 and holds attempt 0's text
    // on attempt 1, so this is also the test for "the previous attempt wrote nothing": a parse
    // miss leaves a non-empty string here and takes the unchanged prompt.
    const escalate = attempt > 0 && !String(lastText ?? '').trim()
    let text
    try {
      text = await agent(prompt + (escalate ? ESCALATED_EMIT : '') + FINDINGS_EPILOGUE, {
        agentType: dispatched,
        model,
        label: attempt === 0 ? dispatched : `${dispatched} (retry${escalate ? ', escalated' : ''})`,
        phase: 'Review',
      })
    } catch (err) {
      // Hard dispatch errors (tool/permission/budget) — forwarded, twice-dead-flagged on the retry.
      return attempt === 0
        ? { agentType: requested, result: null, error: String(err) }
        : { agentType: requested, result: null, error: `retry failed: ${err}`, retried: true, failed: true }
    }
    const parsed = parseReviewResult(text)
    if (parsed && validateShape(parsed, FINDINGS_SCHEMA)) return { agentType: requested, result: capOptIn(requested, parsed) }
    lastText = text
    const emptyText = !String(text ?? '').trim()
    log(
      `${dispatched}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : emptyText ? 'empty text' : 'no sentinel'})${attempt === 0 ? (emptyText ? ' — retrying once, escalated' : ' — retrying once') : ''}`
    )
  }
  if (/REVIEW_RESULT/.test(String(lastText ?? ''))) {
    try {
      // bounded-exploration-optout: validator-reference -- this schema: key parameterizes the
      //   emitter helper (whose own dispatch site carries the structured-emitter marker).
      const emitted = await emitStructured(lastText, { label: dispatched, schema: FINDINGS_SCHEMA })
      if (emitted && validateShape(emitted, FINDINGS_SCHEMA)) return { agentType: requested, result: capOptIn(requested, emitted) }
    } catch (emitErr) {
      return { agentType: requested, result: null, error: `emit failed: ${emitErr}`, retried: true, failed: true }
    }
  }
  // Missing sentinel (truncation) or unmappable text: dark, with the SAME twice-dead marker.
  // The two causes get DIFFERENT error strings because they point triage at different layers,
  // and conflating them cost real time (#183): a turn-cap death reported as "never produced a
  // parseable block" reads as a transport/parser bug, so the investigation goes to the sentinel
  // and the emitter — when in fact the agent wrote nothing at all and the fix is an emit
  // deadline in its doc. Empty final text with a tool-call count at the cap is the cap signature.
  // The returned SHAPE is identical in both cases: review-lead synthesis and 8-code-review.md
  // detect darkness via { result: null } + { retried: true, failed: true }, never via this string.
  const producedNothing = !String(lastText ?? '').trim()
  return {
    agentType: requested,
    result: null,
    error: producedNothing
      ? 'turn-budget: agent emitted no text on either attempt (maxTurns cap reached mid-exploration — needs an emit deadline, not a bigger cap) — declared dark'
      : 'text-contract: explorer produced text but no parseable REVIEW_RESULT block after retry — declared dark',
    retried: true,
    failed: true,
  }
}

// Race one reviewer's full dispatch (both attempts) against the wall-clock ceiling
// (#219). On timeout, resolve — NEVER reject — to the died-after-retry dark-marker shape
// so the caller's EXISTING dark-reviewer handling treats a wedged reviewer identically to
// one that died after its retry (review-lead detects darkness via { result: null } +
// { retried: true, failed: true }; reusing that shape is what keeps the handling
// unchanged). `ceiling: true` is an additive diagnostic flag the handling does not branch
// on. clearTimeout on the winning branch so a reviewer that resolves in time leaves no
// pending timer. dispatchReviewer() never rejects (every internal path returns an object),
// so the race always resolves and the .then() always runs.
const withCeiling = (agentType, dispatchPromise) => {
  let timer
  const ceiling = new Promise((resolve) => {
    timer = setTimeout(
      () =>
        resolve({
          agentType,
          result: null,
          error: `dispatch exceeded the per-reviewer wall-clock ceiling (${REVIEWER_CEILING_MS}ms) — declared dark`,
          retried: true,
          failed: true,
          ceiling: true,
        }),
      REVIEWER_CEILING_MS,
    )
  })
  return Promise.race([dispatchPromise, ceiling]).then((r) => {
    clearTimeout(timer)
    return r
  })
}

const results = await parallel(
  seatNames.map((agentType) => () => withCeiling(agentType, dispatchReviewer(agentType))),
)

// The substantial panel (#992): seats[] — one entry per seat, in the order requested, each with
// the model it dispatched on and whether it returned.
if (substantial) {
  const seats = seatNames.map((requested, i) => {
    const r = results[i]
    const model = modelFor(resolveAgentType(requested))
    const returned = !!(r && r.result)
    const findings = returned && Array.isArray(r.result.findings) ? r.result.findings : []
    return seatEntry(requested, model, returned ? 'returned' : 'dark', findings, returned ? { verdict: r.result.verdict } : { error: r ? r.error : 'no result' })
  })
  return { range, worktree, seats }
}

// Each entry is { agentType, result } on success or { agentType, result: null, error }
// on failure — error entries are intentionally FORWARDED (not dropped) so in-session
// synthesis can surface a reviewer that died. A reviewer that died without
// StructuredOutput AND failed its one automatic retry additionally carries
// { retried: true, failed: true } so synthesis treats it distinctly from a clean
// "no findings". A reviewer that exceeded the per-reviewer wall-clock ceiling reaches
// the SAME { result: null, retried: true, failed: true } shape (plus { ceiling: true })
// — a ceiling timeout is a sub-cause of died-after-retry, not a new dark case.
// filter(Boolean) only guards against a null slot parallel() itself might inject.
return { range, worktree, reviewers: results.filter(Boolean) }
