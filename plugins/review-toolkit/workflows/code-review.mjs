export const meta = {
  name: 'review-toolkit-code-review',
  description:
    "Reviewer fan-out for review-lead — used by standalone /review-lead. Dispatches the selected specialist reviewers as parallel agent() calls and returns their structured findings. On panel 'substantial' the seats run at the reasoning tier. Synthesis (dedup, triage, Scope Completeness Gate, cross-reviewer self-check) is NOT done here — it stays in the caller's session on the caller's model, per review-lead's Synthesis Rules.",
  phases: [{ title: 'Review', detail: 'one agent() per selected specialist reviewer' }],
}

// {agentType: tier} — the cost tier each reviewer runs at. The source of truth is each
// agent's frontmatter `model:`; this table restates it because Workflow scripts can't read
// files, and passing `model` explicitly holds the tier whatever agent() does with an omitted
// model. Change a tier in the frontmatter AND here; check-model-tiers.sh validates the pair.
// Plugin-shipped reviewers are keyed by their QUALIFIED name (namespaces.md); repo-local
// reviewers (config reviewers.add) dispatch bare and take their tier from
// args.config.reviewers.modelOverrides (or the 'sonnet' default), NOT this table.
// The qualified keys are also the source of the bare-name normalization below, so a key
// removed here stops normalizing that reviewer too.
// Tier -> dispatch token. INLINED because the Workflow sandbox forbids imports; the
// authority is the `## Tier alphabet` table in ../model-tiering.md, and
// check-model-tiers.sh holds this copy against it. Keys are UNQUOTED deliberately: the
// guard's entry scans match a quoted key followed by a quoted value, so quoted keys would
// read as dispatch-table entries and be reported DANGLING. A comment that writes that
// shape out trips the scan too.
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
  // The transcription sink takes its tier from this table too, so config can retarget it.
  'review-toolkit:structured-emitter': 'emit',
}

// {agentType: tier} on `panel: 'substantial'` only: every specialist seat runs at
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

// Bare (unqualified) agent name, from either `plugin:agent` or a bare form. Config keys
// modelOverrides by bare name (second-shift.config.schema.json).
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// Dispatch-name normalization. agent() needs a plugin reviewer's QUALIFIED name; a bare one
// fails with `agent type not found`, returns in the died-after-retry shape, and synthesis
// renders it as a dark panel, so "nothing ran" reads as "nothing to review".
// Reverse index over REVIEWER_MODEL's qualified keys. A bare name matching exactly ONE
// qualified key resolves to it; a bare name matching two (two plugins shipping the same
// basename) is left alone, because guessing between roots is worse than dispatching what the
// caller asked for. Repo-local `reviewers.add` names match no key and stay bare.
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
// dispatch works regardless of provenance. One hardcoded prefix makes the Scope
// Completeness Gate unsatisfiable for consumers registered under the other two.
const ATLASSIAN_MCP_TOOLSEARCH =
  'select:mcp__atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__claude_ai_Atlassian_Rovo__getJiraIssue,' +
  'mcp__atlassian__getAccessibleAtlassianResources,mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources,mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources,' +
  'mcp__atlassian__getJiraIssueRemoteIssueLinks,mcp__plugin_atlassian_atlassian__getJiraIssueRemoteIssueLinks,mcp__claude_ai_Atlassian_Rovo__getJiraIssueRemoteIssueLinks'

// Findings contract. Kept permissive (only severity/description/confidence required)
// so reviewers don't burn retries on over-strict shapes; file/line/title are optional.
// LOCKSTEP, canonical side: stall-probe.mjs declares its own copy because the Workflow
// runtime gives it no `import`, and a probe with a drifted schema measures a different
// contract. Edit both.
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
//                  The range is rendered THREE-DOT (`<base>...<head>`): git diffs from
//                  merge-base(base, head) to head, so a `base` BRANCH that has advanced past
//                  the branch point does not leak its newer commits into the reviewed diff.
//                  Under two-dot they render as deletions and reviewers report the branch as
//                  reverting work it never touched (observed: two false BLOCKERs).
//                  When base is already an ancestor of head the two forms are the same range.
//                  Git resolves the merge-base at reviewer-run time: Workflow scripts have no
//                  Bash/filesystem access.
//   issue        — GitHub issue number (drives scope-completeness; omit to skip it)
//   spec         — optional committed decision record path; scope-completeness scores its rows
//   issueLink    — optional; the verb the PR body links the issue with, verbatim (`Closes`, `Relates to`).
//                  Absent or a closing keyword, scope-completeness scores the whole ticket; any other verb
//                  runs it in partial mode, where items the diff does not attempt are reported, not failed.
//   reviewers    — array of agentType strings already selected per review-lead routing
//   changedFiles — array of changed paths (context for the prompt)
//   prContext    — optional free-text branch/PR context
//   requiredSeats — optional array of agentType strings dispatched IN ADDITION to `reviewers`.
//                  Never trims either list; the union is deduped on the resolved name.
//   panel        — optional; 'substantial' runs the seats at SUBSTANTIAL_MODEL's tiers and returns
//                  `seats[]` in place of `reviewers[]`.
// `args` may be an object or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { worktree, base, head, issue, issueLink, spec, reviewers = [], requiredSeats = [], panel, changedFiles = [], prContext = '', config = {} } = a
const substantial = panel === 'substantial'
// Per-reviewer model-tier overrides from the consumer config (bare-keyed).
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
// Consumer tier retargeting, MERGED per tier over the shipped default: a config naming one
// tier leaves the rest alone.
const tierMap = { ...DEFAULT_TIER_MAP, ...((config && config.reviewers && config.reviewers.tierMap) || {}) }
// One resolution path for EVERY dispatch in this file. An override or table value that
// names a tier resolves through the map; anything else is already a raw dispatch token
// (the closed union config-lint enforces) and passes through untouched. The substantial
// table sits BETWEEN the override and REVIEWER_MODEL: the override still wins.
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
// Relaxed only for a non-empty requiredSeats: a call with neither still needs a non-empty
// reviewers[], which is what standalone review-lead relies on.
if ((!Array.isArray(reviewers) || (reviewers.length === 0 && requiredSeats.length === 0))) {
  throw new Error('code-review workflow: args.reviewers must be a non-empty array of agentType strings')
}
// The seats this run dispatches. Without requiredSeats or a panel this is `reviewers` verbatim.
// Otherwise it is the union, deduped on the RESOLVED name so a bare and a qualified spelling of
// one reviewer dispatch once; the first spelling seen is the one returned.
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
// scope-completeness-reviewer's prompt embeds the issue number; without it the prompt
// degrades to `gh issue view undefined`, so fail here instead of dispatching it broken.
if (seatNames.some((r) => bare(r) === 'scope-completeness-reviewer') && !issue) {
  throw new Error('code-review workflow: scope-completeness-reviewer requires args.issue (GitHub issue number or JIRA ticket key)')
}
// issueLink is the one piece of PR-authored text that reaches the scope reviewer, so it is held to a bare verb:
// anything longer could carry the scope interpretation the reviewer's independence rule keeps out.
if (issueLink !== undefined && !(typeof issueLink === 'string' && /^[A-Za-z][A-Za-z -]{0,29}$/.test(issueLink))) {
  throw new Error(`code-review workflow: args.issueLink must be a bare link verb such as 'Closes' or 'Relates to', got ${JSON.stringify(issueLink)}`)
}
// GitHub's closing keywords
const CLOSING_LINK = /^(close[sd]?|fix(e[sd])?|resolve[sd]?)$/i

// Workflow runtime globals used below — injected by the Workflow runtime, not
// imported: log(), phase(), parallel(), agent(). See the Workflow tool API.
// THREE-DOT is load-bearing — see the base/head contract above. Two-dot re-admits base-only
// commits as phantom deletions.
const range = `${base}...${head}`
const fileList = changedFiles.length ? changedFiles.join(', ') : '(see diff)'
// Why reviewers die before they emit (measured by workflows/stall-probe.mjs on a 1326-line
// low-signal diff, maintainability-reviewer): they exhaust their turn budget GROUNDING THE
// ABSENCE of findings, opening files across the whole diff to prove a clean verdict, because
// reviewer-baseline gives "no findings" the same open-and-cite requirement as a real finding.
//   - Size-driven: a TINY low-signal diff never stalls (0/8); a LARGE one does (~57% across runs).
//   - Not the output shape: emitting the structured result first with no prose preamble
//     (stall-probe.mjs's STRUCTURED_OUTPUT_FIRST) did NOT move the rate (2/8 -> 2/8), so it is not
//     in production. Moving the grounding into schema fields did NOT move it either.
//   - More budget only half-helps at ~2x cost: opus dropped it to ~25% but still stalled.
//   - BOUNDING THE EXPLORATION fixes it: BOUNDED_EXPLORATION took maintainability-reviewer from
//     ~50% to 0/12 AND cut tokens ~45%. Placement is load-bearing: the identical instruction in
//     the reviewer-baseline doc did NOT work (4/6 uncured); only the dispatch-time nudge did.
//
// Mitigations, in order: (1) BOUNDED_EXPLORATION below, the PRIMARY fix. (2) the one-shot retry in
// dispatchReviewer(); an attempt that returned EMPTY text is retried with ESCALATED_EMIT appended,
// because a verbatim retry of a turn-cap death reproduces it. (3) the dark-reviewer contract
// (review-lead Step 4b): the SESSION re-dispatches once, NARROWED to that reviewer's domain, which
// this file cannot do because it dispatched against the whole range; only what survives THAT is a
// coverage gap. A gap is a NOTE for most reviewers, a hard "Ready to merge? = No" for security
// (whose dimension the lead pass skipped because this fan-out spawned it) and a VOID for design
// fidelity on an armed spec. When the WHOLE panel goes dark, review-lead voids the round (its
// Step 4b-void). Guards: workflows/runtime-shim-selftest.mjs executes THIS body against the real
// ladder; workflows/null-reviewer-selftest.mjs Case F pins the load-bearing tokens + emit wiring.
// --- explorer/emitter transport (the structural stall fix) ---
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

// Bounded exploration / triage — the PRIMARY stall fix (evidence above). Caps the
// absence-grounding exploration that exhausts a reviewer's turn budget on a large diff.
// NOT appended to the exhaustive reviewers, whose job is to verify every item.
// The deadline is a NUMBER because an agent has no view of its remaining turns, so "emit before
// your budget runs low" is not a deadline it can act on. Measured: a generic-branch reviewer died
// on BOTH fan-out attempts with no text, then returned a grounded verdict in 17 tool calls when
// re-dispatched at the SAME tier with nothing added but the numbered deadline.
// 8 is safe at the smallest cap in the panel (security-reviewer's 15, which emits by turn 10); a
// per-agent number belongs in the agent doc, which may be later than this floor. An early number
// costs nothing because parseReviewResult() takes the last block, so re-emission is free.
const BOUNDED_EXPLORATION =
  ' TRIAGE FIRST: skim the diff to judge whether it touches your domain at all. If it is' +
  ' docs/config/reformatting — or otherwise has nothing in your domain — emit your result' +
  ' immediately (approve, no findings) WITHOUT opening every file. Open files only to ground a' +
  ' SPECIFIC finding you intend to raise; you do NOT have to exhaustively read the whole diff to' +
  ' assert the ABSENCE of findings.' +
  ' HARD EMIT DEADLINE: by your 8th tool call at the latest, STOP exploring and write a COMPLETE' +
  ' result reflecting what you know so far — even if that is approve with no findings, and even if' +
  ' you feel under-grounded. You may then keep working and re-emit the whole result whenever you' +
  ' learn something; the LAST complete result wins, so an early one costs you nothing. A review you' +
  ' never emit is scored exactly like a review that never ran, and your entire domain is then' +
  ' recorded as unverified — an under-grounded emitted review is strictly more useful than a' +
  ' perfect unemitted one.'

// The counterpart nudge for the two EXHAUSTIVE reviewers, which cannot take BOUNDED_EXPLORATION
// without losing the coverage that IS their deliverable. Same turn-budget death, inverted cure:
// "write down what you have as you go", so the wall truncates a result instead of erasing one.
// Raising the cap does NOT fix it. Measured at maxTurns 30: scope-completeness-reviewer died on
// BOTH attempts (31 and 33 tool calls, no result), while security-reviewer in the same fan-out —
// opus, HALF the cap, an explicit turn-numbered emit deadline in its doc — completed. The variable
// is the deadline, not the budget.
// Safe for exactly these two because a truncated result can only under-claim:
//   - scope-completeness-reviewer is fail-closed by contract ("Default to FAIL when the evidence
//     is ambiguous"), so its honest early skeleton is every item [unsatisfied], refined upward
//     only as evidence lands. A cut-short result over-reports FAIL, never a false PASS.
//   - unit-test-mutation-reviewer's unreached mutants are simply absent, and an absent mutant
//     never blocks (execution-verified blocking is the propose-mode orchestrator's, not this fan-out's).
// The dark path is unchanged: nothing transcribes partial text, and a missing sentinel is still dark.
// LOCKSTEP, canonical side: intake-review.mjs declares its own copy for its exhaustive reviewer,
// because the Workflow runtime gives it no `import`.
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

// The RETRY nudge, appended only when attempt 0 came back with EMPTY text. A verbatim retry is
// worthless against a deterministic turn-cap death. The session's re-dispatch (review-lead
// Step 4b) cures it too, but only after a full dark round, which on a design-ARMED spec is VOID;
// this is the same cure one rung earlier.
// Never on a parse miss: that agent needs the FORMAT restated, which the emitter rung owns, and
// telling it to cut its exploration short would trade a recoverable result for a thinner one.
// The 8 restates BOUNDED_EXPLORATION's deadline as an absolute, because the first attempt already
// blew past it. Measured: the same agent, tier and cap died twice at 18 tool calls with empty
// text, then returned a grounded verdict in 20 when re-dispatched with a numbered deadline and a
// narrowed ask.
const ESCALATED_EMIT =
  ' RETRY — YOUR PREVIOUS ATTEMPT AT THIS EXACT REVIEW DIED HAVING WRITTEN NOTHING. It ran out of' +
  ' turns still exploring, so its entire domain was recorded as unverified. Do not repeat that' +
  ' shape. STOP EXPLORING NOW and emit a COMPLETE result from what you can establish in your' +
  ' first 8 tool calls, even if that is approve with no findings and even if you feel' +
  ' under-grounded. Name anything you could not reach as `unable to verify — pointer needed:' +
  ' <specific file or fact>` rather than opening it. You may re-emit the whole block later if you' +
  ' learn more — the LAST complete block wins — but the first one must exist before you read' +
  ' anything further.'

// Per-reviewer wall-clock ceiling. The Workflow runtime's own agent-stall loop can let a wedged
// reviewer burn ~90 min before agent() settles (observed: one dark reviewer added ~90 min to a
// round whose five other reviewers finished in minutes). agent() exposes no timeout/abort option
// and the sandbox has no AbortController, so each dispatch races this ceiling and, on timeout,
// resolves to the SAME died-after-retry dark marker the caller already handles. The orphaned
// agent() keeps running until its own stall loop ends it, but does NOT block parallel().
//   15 min: >=2.5x the largest observed healthy single-reviewer turn (the whole fan-out took
//   ~6 min), ~6x tighter than the observed wedge. Raise it if a large-diff run needs a longer turn.
const REVIEWER_CEILING_MS = 15 * 60 * 1000

// One seats[] entry per requested seat on the substantial panel.
const seatEntry = (agentType, model, status, findings, extra = {}) => ({ agentType, model, status, findings, ...extra })

log(`code-review: ${seatNames.length} reviewers over ${range} in ${worktree}${substantial ? ' (substantial panel)' : ''}`)
phase('Review')

// The Workflow runtime enforces the operator's token budget across every agent() call in the
// run and makes agent() throw once it is spent. If it is already spent, skip the fan-out
// instead of dispatching calls that will all throw.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left before fan-out`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping reviewer fan-out (synthesis sees zero reviewers)')
    // Every requested seat is listed dark rather than omitted, so a caller counting darkness
    // needs no second list.
    if (substantial) {
      return { range, worktree, seats: seatNames.map((s) => seatEntry(s, modelFor(resolveAgentType(s)), 'dark', [])), budgetExhausted: true }
    }
    // budgetExhausted marks this all-or-nothing skip: `reviewers` is empty by construction
    // (NOT a partial subset) and EVERY selected reviewer is dark, unlike a reviewer that died
    // after retry (PRESENT in `reviewers` as a failed:true entry). Mirrors intake-review.mjs.
    return { range, worktree, reviewers: [], budgetExhausted: true }
  }
}

// One reviewer dispatch with ONE automatic retry, run INLINE in this task closure so it adds no
// task to parallel() and inherits its concurrency cap.
//   - success (either attempt)      → { agentType, result }
//   - dispatch error on attempt 0   → { agentType, result: null, error } (no retry)
//   - dead on both attempts         → { agentType, result: null, error, retried: true, failed: true },
//     flagged so synthesis cannot mistake a dead reviewer for a clean "no findings".
// `requested` is the name the CALLER passed; `dispatched` is what reaches agent(). Every object
// returned carries `agentType: requested` — NOT the resolved name — because review-lead's Step 4b
// finds budget-skipped darkness by comparing the returned set with the args.reviewers it passed.
const dispatchReviewer = async (requested) => {
  const dispatched = resolveAgentType(requested)
  if (dispatched !== requested) {
    log(`reviewer name normalized: '${requested}' dispatched as '${dispatched}' (plugin reviewers are addressed qualified — docs/namespaces.md rule 2)`)
  }
  // Keyed on the RESOLVED name, so a normalized bare name keeps its declared tier rather than
  // falling through to the default.
  const model = modelFor(dispatched)
  let prompt
  if (bare(dispatched) === 'scope-completeness-reviewer') {
    // Independence rule (review-lead): evidence ONLY — issue/ticket ref + branch/base.
    // No scope paraphrase, no diff summary; the reviewer fetches the ticket itself.
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
      (issueLink === undefined
        ? ''
        : CLOSING_LINK.test(issueLink.trim())
          ? `Ticket link: the PR body links the ticket with \`${issueLink}\`, a closing keyword — score the whole ticket. `
          : `Ticket link: the PR body links the ticket with \`${issueLink}\`, not a closing keyword — partial mode. `) +
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
      BOUNDED_EXPLORATION
  }
  // The two exhaustive branches carry PROGRESSIVE_EMIT and the generic branch BOUNDED_EXPLORATION;
  // every branch carries exactly one of the two, and null-reviewer-selftest Case F pins the pair.
  // Dark-marker shapes are a contract: review-lead synthesis keys on { result: null } +
  // { retried: true, failed: true }.
  let lastText = null
  for (let attempt = 0; attempt < 2; attempt++) {
    // The retry ESCALATES only against the empty-text death, the deterministic one. `lastText` is
    // unset on attempt 0 and holds attempt 0's text on attempt 1; a parse miss leaves a non-empty
    // string here and takes the unchanged prompt.
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
    if (parsed && validateShape(parsed, FINDINGS_SCHEMA)) return { agentType: requested, result: parsed }
    lastText = text
    const emptyText = !String(text ?? '').trim()
    log(
      `${dispatched}: text-contract miss (${/REVIEW_RESULT/.test(String(text ?? '')) ? 'invalid json' : emptyText ? 'empty text' : 'no sentinel'})${attempt === 0 ? (emptyText ? ' — retrying once, escalated' : ' — retrying once') : ''}`
    )
  }
  if (/REVIEW_RESULT/.test(String(lastText ?? ''))) {
    try {
      const emitted = await emitStructured(lastText, { label: dispatched, schema: FINDINGS_SCHEMA })
      if (emitted && validateShape(emitted, FINDINGS_SCHEMA)) return { agentType: requested, result: emitted }
    } catch (emitErr) {
      return { agentType: requested, result: null, error: `emit failed: ${emitErr}`, retried: true, failed: true }
    }
  }
  // Missing sentinel (truncation) or unmappable text: dark, with the SAME twice-dead marker.
  // The two causes get DIFFERENT error strings because they point triage at different layers: a
  // turn-cap death reported as a parse miss sends the investigation to the parser, when the agent
  // wrote nothing and the fix is an emit deadline in its doc.
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

// Race one reviewer's full dispatch (both attempts) against the wall-clock ceiling. On timeout,
// resolve — NEVER reject — to the died-after-retry dark-marker shape, so the caller's dark-reviewer
// handling treats a wedged reviewer like one that died after its retry. `ceiling: true` is a
// diagnostic flag nothing branches on. dispatchReviewer() never rejects, so the race always
// resolves and the .then() always runs.
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

// The substantial panel: seats[] — one entry per seat, in the order requested, each with
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

// Error entries are FORWARDED, not dropped, so in-session synthesis can surface a reviewer that
// died. A twice-dead or timed-out reviewer carries { result: null, retried: true, failed: true }
// (a timeout adds { ceiling: true }). filter(Boolean) guards against a null slot from parallel().
return { range, worktree, reviewers: results.filter(Boolean) }
