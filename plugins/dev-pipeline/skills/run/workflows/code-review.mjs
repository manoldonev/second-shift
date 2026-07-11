export const meta = {
  name: 'dev-pipeline-code-review',
  description:
    "Reviewer fan-out for review-lead — used by dev-pipeline Stage 8 and by standalone /review-lead (and pr-revision). Dispatches the selected specialist reviewers as parallel agent() calls and returns their structured findings. Synthesis (dedup, triage, Scope Completeness Gate, cross-reviewer self-check) is NOT done here — it stays in the caller's session on the caller's model, per review-lead's Synthesis Rules.",
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
const REVIEWER_MODEL = {
  'review-toolkit:security-reviewer': 'opus',
  'review-toolkit:performance-reviewer': 'sonnet',
  'review-toolkit:maintainability-reviewer': 'sonnet',
  'review-toolkit:complexity-reviewer': 'sonnet',
  'review-toolkit:test-coverage-reviewer': 'sonnet',
  'review-toolkit:unit-test-mutation-reviewer': 'sonnet',
  'review-toolkit:db-reviewer': 'sonnet',
  'review-toolkit:pipeline-reviewer': 'sonnet',
  'review-toolkit:scope-completeness-reviewer': 'opus',
  'review-toolkit:a11y-reviewer': 'sonnet',
  'design-toolkit:design-faithful-reviewer': 'sonnet',
  'design-toolkit:figma-faithful-reviewer': 'sonnet',
}

// Bare (unqualified) agent name — tolerant of both `plugin:agent` and bare forms.
// Used for the special-case dispatch branches below and for modelOverrides lookup
// (config keys reviewers by bare name, per second-shift.config.schema.json).
const bare = (t) => (String(t).includes(':') ? String(t).split(':').pop() : String(t))

// Findings contract. Kept permissive (only severity/description/confidence required)
// so reviewers don't burn retries on over-strict shapes; file/line/title are optional.
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

// args (assembled in-session by Stage 8, which has Bash to size the diff and route):
//   worktree     — absolute path the reviewers run git against
//   base, head   — git range (reviewers run `git -C <worktree> diff <base>..<head>`)
//   issue        — GitHub issue number (drives scope-completeness; omit to skip it)
//   reviewers    — array of agentType strings already selected per review-lead routing
//   changedFiles — array of changed paths (context for the prompt)
//   prContext    — optional free-text branch/PR context
// `args` arrives as the value passed to Workflow's `args` input. Defensive: it may
// be an object, or (per the Workflow contract's stringified-args caveat) a JSON string.
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { worktree, base, head, issue, reviewers = [], changedFiles = [], prContext = '', config = {} } = a
// Per-reviewer model-tier overrides from the consumer config (bare-keyed).
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
if (!worktree || !base || !head) {
  throw new Error('code-review workflow: args.worktree, args.base and args.head are required')
}
if (!Array.isArray(reviewers) || reviewers.length === 0) {
  throw new Error('code-review workflow: args.reviewers must be a non-empty array of agentType strings')
}
// scope-completeness-reviewer's prompt embeds the issue number; without it the
// prompt degrades to `#undefined` / `gh issue view undefined`. The caller is
// supposed to include this reviewer only when an issue is referenced — make that
// contract explicit here rather than silently producing a broken dispatch.
if (reviewers.some((r) => bare(r) === 'scope-completeness-reviewer') && !issue) {
  throw new Error('code-review workflow: scope-completeness-reviewer requires args.issue (GitHub issue number)')
}

// Workflow runtime globals used below — injected by the Workflow runtime, not
// imported: log(), phase(), parallel(), agent(). See the Workflow tool API.
const range = `${base}..${head}`
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
//   - BOUNDING THE EXPLORATION fixes it: the dispatch-time triage nudge (BOUNDED_EXPLORATION below)
//     took maintainability-reviewer from ~50% to 0/12 AND cut tokens ~45% — the wasted exhaustive
//     exploration WAS the problem. Placement is load-bearing: the identical instruction sitting in
//     the inherited reviewer-baseline doc did NOT work (4/6 uncured); only the dispatch-time nudge did.
//
// Mitigations, in order: (1) BOUNDED_EXPLORATION below — the PRIMARY fix; caps the absence-grounding
// exploration so the reviewer emits instead of stalling. (2) STRUCTURED_OUTPUT_FIRST — emit the
// structured verdict first; kept (cheap, right on principle) though it is not the stall cure. (3) the
// one-shot retry in dispatchReviewer() recovers residual stochastic deaths. (4) the dark-reviewer
// coverage-gap contract (review-lead Synthesis Rules + stages/8-code-review.md) backstops anything
// that still goes dark, surfaced as a coverage gap and never silently dropped. Drift-guard:
// workflows/null-reviewer-selftest.mjs. reviewer-baseline carries the same principle as documented
// contract ("Proportionate grounding"); this file is the operative delivery.
const STRUCTURED_OUTPUT_FIRST =
  ' Call StructuredOutput FIRST with your verdict and findings, before any prose' +
  ' explanation — do not write a long write-up before the structured call.'

// Bounded exploration / triage — the PRIMARY stall fix (see ROOT CAUSE above for the evidence).
// Caps the absence-grounding exploration that exhausts a reviewer's turn budget on a large diff.
// NOT appended to scope-completeness-reviewer, whose job is to exhaustively verify every scope item.
const BOUNDED_EXPLORATION =
  ' TRIAGE FIRST: skim the diff to judge whether it touches your domain at all. If it is' +
  ' docs/config/reformatting — or otherwise has nothing in your domain — emit StructuredOutput' +
  ' immediately (approve, no findings) WITHOUT opening every file. Open files only to ground a' +
  ' SPECIFIC finding you intend to raise; you do NOT have to exhaustively read the whole diff to' +
  ' assert the ABSENCE of findings. Stop exploring and emit StructuredOutput before your budget runs low.'

// Per-reviewer wall-clock ceiling (#219). The Workflow runtime's own agent-stall loop
// (multiple attempts × a no-progress window) can let a genuinely wedged reviewer burn
// ~90 min before agent() settles — observed in run #183, where one dark reviewer added
// ~90 min to a Stage 8 whose five other reviewers had finished in minutes. That loop is
// a RUNTIME property: it is NOT reachable from this script (agent() exposes no
// timeout/abort option, and there is no AbortController in the Workflow sandbox). So we
// bound it in userland — race each reviewer's dispatch against this ceiling and, on
// timeout, resolve to the SAME died-after-retry dark marker the caller already handles
// (a ceiling timeout is a SUB-CAUSE of `died-after-retry`, not a new dark case). The
// orphaned agent() keeps running in the runtime until its own stall loop terminates it,
// but it does NOT block parallel()/the fan-out from returning (the runtime does not wait
// on an orphaned pending promise). Single tunable knob.
//   15 min: >=2.5x the largest observed healthy single-reviewer turn (bounded above by the
//   ~6 min aggregate Stage-8 wall-clock of runs #195/#218), ~6x tighter than the #183 wedge.
//   Raise it if a future large-diff run legitimately needs a longer single reviewer turn.
const REVIEWER_CEILING_MS = 15 * 60 * 1000

log(`code-review: ${reviewers.length} reviewers over ${range} in ${worktree}`)
phase('Review')

// Cost discipline. The Workflow runtime enforces the operator's turn token budget
// (the "+Nk" launch directive) across every agent() call in the run — all three
// Stage 8 rounds draw on one shared pool — and makes agent() throw once it is
// spent; the per-reviewer .catch below already turns that into a forwarded error
// rather than a crash. Surface the posture, and if the budget is already spent,
// skip the fan-out cleanly instead of dispatching calls that will all throw.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left before fan-out`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping reviewer fan-out (synthesis sees zero reviewers)')
    // budgetExhausted is the dark-reviewer signal for this all-or-nothing skip:
    // the fan-out never dispatched, so `reviewers` is empty by construction (NOT a
    // partial subset) and EVERY selected reviewer is dark. Synthesis treats this
    // distinctly from a single reviewer that died after retry (which is PRESENT in
    // `reviewers` as a failed:true entry). Mirrors intake-review.mjs's budget marker.
    return { range, worktree, reviewers: [], budgetExhausted: true }
  }
}

// The Workflow runtime rejects agent() with a message containing the substring
// "StructuredOutput" when a subagent ends without producing structured output
// (observed in the #151 run: "subagent completed without calling StructuredOutput
// (after 2 in-conversation nudges)"). ONLY this error class is retried — genuine
// tool/permission errors fall through to the forward-as-error path unretried.
// This is a brittle substring match because it is the only signal the runtime
// surfaces; if the runtime ever changes the message the retry stops firing and the
// behavior degrades safely to the pre-retry forward-as-error path.
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

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
const dispatchReviewer = async (agentType) => {
  // Override (bare-keyed) wins over the table's per-agent default, else 'sonnet'.
  const model = modelOverrides[bare(agentType)] || REVIEWER_MODEL[agentType] || 'sonnet'
  let prompt
  if (bare(agentType) === 'scope-completeness-reviewer') {
    // Independence rule (review-lead): evidence ONLY — issue number + branch/base.
    // No scope paraphrase, no diff summary; the reviewer fetches the issue itself.
    prompt =
      `Verify scope completeness for GitHub issue #${issue}. ` +
      `Branch head \`${head}\` vs base \`${base}\`; repo worktree \`${worktree}\` ` +
      `(run \`git -C ${worktree} diff ${range}\` to see the change). ` +
      `Fetch the issue yourself with \`gh issue view ${issue}\` and classify each scope item ` +
      `against the diff. Return your verdict and findings.` +
      STRUCTURED_OUTPUT_FIRST
  } else if (bare(agentType) === 'unit-test-mutation-reviewer') {
    prompt =
      `Mutation review in ADVISORY mode on unit tests for this change. ` +
      `Diff scope: \`git -C ${worktree} diff ${range}\`. Changed files: ${fileList}.` +
      (prContext ? ` Context: ${prContext}.` : '') +
      ` Load the unit-testing skill. Propose mutants and predict survived/untested — LLM prediction ONLY; ` +
      `do NOT apply mutants or run tests (this fan-out has no executor). ` +
      `Blocker-class mutants map to severity \`major\` (never \`blocker\` — only the Stage-5 ` +
      `execution-verified gate can block). No Stryker. ` +
      `Return verdict and findings (severity major/minor/nit, file, line, confidence 0-100).` +
      STRUCTURED_OUTPUT_FIRST
  } else {
    prompt =
      `Review this change in your domain. Diff scope: \`git -C ${worktree} diff ${range}\`. ` +
      `Changed files: ${fileList}.` +
      (prContext ? ` Context: ${prContext}.` : '') +
      ` Return your verdict and a deduplicated list of findings (severity blocker/major/minor/nit, ` +
      `file, line, confidence 0-100). Ignore stylistic issues handled by formatter/linter.` +
      STRUCTURED_OUTPUT_FIRST +
      BOUNDED_EXPLORATION
  }
  try {
    const result = await agent(prompt, { agentType, model, label: agentType, phase: 'Review', schema: FINDINGS_SCHEMA })
    return { agentType, result }
  } catch (err) {
    if (!isNoStructuredOutputError(err)) {
      return { agentType, result: null, error: String(err) }
    }
    log(`${agentType}: died without StructuredOutput — retrying once`)
    try {
      const result = await agent(prompt, {
        agentType,
        model,
        label: `${agentType} (retry)`,
        phase: 'Review',
        schema: FINDINGS_SCHEMA,
      })
      return { agentType, result }
    } catch (retryErr) {
      // Surface BOTH failures — the retry error AND the original first-attempt
      // error — so a twice-dead reviewer's full diagnostic trail survives, not
      // just the second death.
      return {
        agentType,
        result: null,
        error: `retry failed: ${retryErr}; first attempt: ${err}`,
        retried: true,
        failed: true,
      }
    }
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
  reviewers.map((agentType) => () => withCeiling(agentType, dispatchReviewer(agentType))),
)

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
