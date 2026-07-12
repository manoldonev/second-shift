export const meta = {
  name: 'dev-pipeline-mutation-gate',
  description:
    "Stage 5 mutation-gate sequencer for the dev-pipeline. Proposes via nested unit-tests.mjs (schema'd, unchanged child with its own staller mitigations), executes blocker mutants via SEQUENTIAL SCHEMA-FREE executor agents (plain-text MUTANT_RESULT line parsed in JS — the StructuredOutput staller class cannot occur without a forced call), computes the verdict in JS. The strengthen loop (test-writing judgment) and all state writes stay in the dev-pipeline session.",
  phases: [{ title: 'Mutation Gate', detail: 'nested propose workflow + one schema-free agent() per blocker mutant' }],
}

// Executors run at the code tier — keep in lockstep with SKILL.md's Model Tiering
// note (mutation-gate executors: sonnet). Mechanical apply/run/revert work.
// EP-4: the executor is a NAMED logical agent 'mutation-executor'; its tier is the
// shipped default here, overridable via config reviewers.modelOverrides['mutation-executor']
// (resolved below, after args). check-model-tiers.sh asserts this scalar as the default and
// honors the override (no agent-frontmatter counterpart — executors are schema-free agent()
// calls, not a .claude/agents/ type).
const EXECUTOR_MODEL = 'sonnet'

// Parse LAST match wins: the executor prompt itself contains the literal token,
// and an agent may echo the instructions before its final line.
const RESULT_RE = /^MUTANT_RESULT:\s*(KILLED|SURVIVED|UNAPPLIED)\s*$/gm
const parseResult = (text) => {
  const matches = [...String(text ?? '').matchAll(RESULT_RE)]
  return matches.length ? matches[matches.length - 1][1] : null
}

// Per-executor wall-clock ceiling. Unlike code-review.mjs's read-only reviewers,
// a ceiling-orphaned executor KEEPS RUNNING and can keep mutating the shared
// worktree — so a timeout must ABORT the remaining loop (skipped-after-infra),
// never continue past a live orphan (it would corrupt the next mutant's run).
const EXECUTOR_CEILING_MS = 10 * 60 * 1000
const CEILING = Symbol('ceiling')
const withCeiling = (p) =>
  Promise.race([p, new Promise((resolve) => setTimeout(() => resolve(CEILING), EXECUTOR_CEILING_MS))])

// >>> verdict (pure — extracted and executed by the (mg) selftest case) >>>
const computeVerdict = (executions) => {
  const count = (s) => executions.filter((e) => e.status === s).length
  const killed = count('killed')
  const survived = count('survived')
  const unapplied = executions.length - killed - survived - count('skipped-budget') - count('skipped-after-infra')
  const hasFailureEntry = executions.some((e) => e.status === 'unparseable' || e.status === 'infra')
  const hasBudgetSkip = executions.some((e) => e.status === 'skipped-budget')
  let overall
  if (survived > 0) {
    // Survivors are ground truth regardless of later failures.
    overall = 'survived-blockers'
  } else if (executions.length > 0 && killed === 0 && hasFailureEntry) {
    // Zero-verified guard: blockers were proposed but NOTHING was actually
    // verified and at least one genuine failure occurred — an all-unparseable
    // or all-infra run must never pass silently. (An all-skipped-budget run has
    // no failure entry and falls through to budget-skipped below.)
    overall = 'infra'
  } else if (executions.some((e) => e.status === 'infra' || e.status === 'skipped-after-infra')) {
    overall = 'infra'
  } else if (hasBudgetSkip) {
    // Entry-based, not score-based: a partial run (some killed, rest
    // budget-skipped) must signal "incomplete — re-run", not pass.
    overall = 'budget-skipped'
  } else {
    overall = 'pass'
  }
  return { overall, mutationScore: { killed, survived, unapplied } }
}
// <<< verdict <<<

// args (assembled in-session by Stage 5):
//   worktree     — ABSOLUTE worktree path (executors apply/run/revert here;
//                  the per-spec test command runs from ${worktree})
//   base, head   — git SHAs bounding the reviewed range (propose child contract)
//   issue        — issue number, for labels/logging
//   workflowsDir — absolute path to this workflows/ dir (scripts cannot
//                  introspect their own location — the caller supplies it)
//   round        — 1 | 2 (audit labeling; round 2 is the post-strengthen re-run)
//   inputs       — { modulesTouched, specPaths, changedBackendFiles, mutationTargets }
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { worktree, base, head, issue = '', workflowsDir, round = 1, inputs = {}, config = {}, testFileCommand } = a
// EP-4: resolve the 'mutation-executor' tier via the standard modelOverrides idiom (bare-keyed).
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const executorModel = modelOverrides['mutation-executor'] || EXECUTOR_MODEL
if (!worktree || !base || !head || !workflowsDir) {
  throw new Error('mutation-gate workflow: args.worktree, args.base, args.head and args.workflowsDir are required')
}

log(`mutation-gate: round ${round} over ${base}..${head} in ${worktree}${issue ? ` (#${issue})` : ''}`)
phase('Mutation Gate')

const budgetLeft = () =>
  typeof budget === 'undefined' || !budget || !budget.total || budget.remaining() > 0

// ---- Phase a: budget ----
if (!budgetLeft()) {
  log('budget exhausted — skipping mutation gate')
  return { overall: 'budget-skipped', round, executions: [], mutationScore: null, survivedMutants: [] }
}

// ---- Phase b: propose (nested child, one in-script re-dispatch on infra) ----
const proposeOnce = () =>
  workflow(
    { scriptPath: `${workflowsDir}/unit-tests.mjs` },
    { kind: 'mutation-review', worktree, base, head, target: 'unit-test-mutation-reviewer', inputs, issue, config },
  )

let proposal = null
let proposalError = null
for (let attempt = 0; attempt < 2 && !proposal; attempt++) {
  let ret
  try {
    ret = await proposeOnce()
  } catch (err) {
    proposalError = `propose dispatch threw: ${err}`
    continue
  }
  if (ret && ret.budgetExhausted) {
    return { overall: 'budget-skipped', round, executions: [], mutationScore: null, survivedMutants: [] }
  }
  if (ret && ret.result && ret.result.infraFailure) {
    proposalError = ret.result.summary || 'propose infraFailure (survived child retries)'
    if (attempt === 0) log('propose: infraFailure — one in-script re-dispatch')
    continue
  }
  if (!ret || !ret.result || !Array.isArray(ret.result.mutants)) {
    proposalError = `unexpected propose return shape: ${JSON.stringify(ret).slice(0, 200)}`
    continue
  }
  proposal = ret.result
}
if (!proposal) {
  return { overall: 'infra', round, proposalError, executions: [], mutationScore: null, survivedMutants: [] }
}
const { mutants = [], mockAuditFindings = [], summary: proposalSummary = '' } = proposal

// ---- Blocker selection ----
const blockers = mutants.filter((m) => m.severity === 'blocker')
const executions = []
const executable = []
for (const m of blockers) {
  if (m.originalSnippet && m.mutatedSnippet && m.specPath) {
    executable.push(m)
  } else {
    // "An unverifiable mutant must never block" (unit-testing skill) —
    // warning-class ledger entry, counts as unapplied.
    executions.push({ file: m.file, specPath: m.specPath || null, message: m.message, status: 'unapplied', reason: 'missing-patch-fields' })
  }
}
log(`propose: ${mutants.length} mutants, ${blockers.length} blockers (${executable.length} executable)`)

// Fail closed: executable mutants require a per-spec runner. The dispatching stage
// passes testFileCommand from commands.<host>.testFile; an empty one means the gate is
// enabled without a runner (issue #9). Never default to a hardcoded command that would
// run the wrong test framework (e.g. yarn on a pytest repo) — throw instead.
if (executable.length > 0 && !testFileCommand) {
  throw new Error('mutation-gate workflow: executable mutants exist but args.testFileCommand is empty (commands.<host>.testFile is null). Configure the per-spec runner or disable the gate (unitTestScope null). Failing closed rather than defaulting to a hardcoded command.')
}

// ---- Phase c: sequential executor loop (schema-free — no StructuredOutput,
// no dispatchSchemaAgent: that death class does not exist without a schema) ----
const executorPrompt = (m, i, n) =>
  `You are a mutation-testing executor (mutant ${i + 1}/${n}). Work ONLY inside the worktree \`${worktree}\`.\n\n` +
  `0. If \`git -C ${worktree} status --porcelain\` prints anything, run ` +
  `\`git -C ${worktree} checkout -- .\` first (a previous executor may have died mid-apply).\n` +
  `1. Read \`${worktree}/${m.file}\`, then use the Edit tool to replace this EXACT snippet (old_string -> new_string):\n` +
  `---ORIGINAL---\n${m.originalSnippet}\n---MUTATED---\n${m.mutatedSnippet}\n---END---\n` +
  `If Edit fails because the snippet is not found or not unique, do NOT improvise an equivalent edit — ` +
  `skip to step 3 and report UNAPPLIED.\n` +
  // Per-spec test invocation is config-driven (commands.<repo>.testFile, a template
  // with a {file} placeholder), resolved by the dispatching stage and passed as
  // testFileCommand. Guaranteed non-empty here (the executable>0 && !testFileCommand
  // fail-closed guard above rejects a null runner — no hardcoded acme default). Run
  // from the worktree root.
  `2. Run \`${testFileCommand.replace('{file}', m.specPath)}\` from \`${worktree}\`.\n` +
  `3. ALWAYS revert, even if a previous step errored: \`git -C ${worktree} checkout -- ${m.file}\`, ` +
  `then confirm \`git -C ${worktree} status --porcelain\` is empty.\n` +
  `4. Classification: ANY test failure in step 2 means the mutant was KILLED. All tests passing means it SURVIVED. ` +
  `Do not commit, do not push, do not edit any other file, and never "fix" the test.\n\n` +
  `END your reply with exactly one line and nothing after it:\n` +
  `MUTANT_RESULT: KILLED    (or SURVIVED, or UNAPPLIED)`

let abortRest = null // 'skipped-after-infra' | 'skipped-budget'
for (const [i, m] of executable.entries()) {
  if (abortRest || !budgetLeft()) {
    executions.push({ file: m.file, specPath: m.specPath, message: m.message, status: abortRest || 'skipped-budget' })
    continue
  }
  let status = null
  let attempts = 0
  for (let attempt = 0; attempt < 2 && status === null; attempt++) {
    attempts++
    const label = `mutant-exec ${i + 1}/${executable.length}: ${m.file}${attempt ? ' (retry)' : ''}`
    try {
      const reply = await withCeiling(
        agent(executorPrompt(m, i, executable.length), { model: executorModel, label, phase: 'Mutation Gate' }),
      )
      if (reply === CEILING) {
        // Orphaned executor may still be mutating the shared worktree — abort
        // the remaining loop rather than run the next mutant against dirty state.
        executions.push({ file: m.file, specPath: m.specPath, message: m.message, status: 'infra', ceiling: true, attempts })
        abortRest = 'skipped-after-infra'
        status = 'recorded'
        break
      }
      const parsed = parseResult(reply)
      if (parsed) {
        executions.push({ file: m.file, specPath: m.specPath, message: m.message, status: parsed.toLowerCase(), attempts })
        status = 'recorded'
      } else if (attempt === 1) {
        executions.push({ file: m.file, specPath: m.specPath, message: m.message, status: 'unparseable', attempts })
        status = 'recorded'
      }
    } catch (err) {
      if (attempt === 1) {
        executions.push({ file: m.file, specPath: m.specPath, message: m.message, status: 'infra', error: String(err), attempts })
        status = 'recorded'
      }
    }
  }
}

// ---- Phase d: verdict ----
const { overall, mutationScore } = computeVerdict(executions)
const survivedMutants = executions
  .filter((e) => e.status === 'survived')
  .map((e) => {
    const src = executable.find((m) => m.file === e.file && m.specPath === e.specPath)
    return { ...e, suggestedFix: src?.suggestedFix, originalSnippet: src?.originalSnippet, mutatedSnippet: src?.mutatedSnippet }
  })

log(`mutation-gate: overall=${overall} score=${JSON.stringify(mutationScore)}`)
return { overall, round, proposalSummary, mockAuditFindings, executions, mutationScore, survivedMutants }
