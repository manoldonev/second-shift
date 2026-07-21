export const meta = {
  name: 'dev-pipeline-figma',
  description:
    "Stage 3/4/5 Figma dispatch for the dev-pipeline, run natively from the BE session (no claude -p). kind='produce' dispatches a subagent that invokes the REAL figma-faithful(-spec) plugin Skill (Figma MCP; writes the artifact); kind='gate' dispatches the REAL figma-faithful-*-reviewer plugin agent. Verdict/status handling and state writes stay in the dev-pipeline session.",
  phases: [{ title: 'Figma', detail: 'one agent() per produce/gate dispatch' }],
}

// Selected by the design-provider axis (config `design.provider: "figma"`). Stage 1
// flips designDriven only when the provider is figma and a figma.com URL is present;
// Stages 3/5 dispatch this workflow (produce) and Stage 8 routes the figma-faithful
// code reviewer on a figma-provider designDriven run. The produce/gate targets are the
// design-toolkit plugin components (design-toolkit:figma-faithful[-spec],
// design-toolkit:figma-faithful-*-reviewer), passed in via args.target — this workflow
// is namespace-agnostic about them.

// Figma dispatches run at the reasoning tier (was `--model opus` under the retired claude -p path).
// Keep in lockstep with SKILL.md's Model Tier Mapping (reasoning → claude-opus-4-8).
const FIGMA_MODEL = 'opus'

// The Figma MCP tools are DEFERRED in a Workflow subagent — it MUST ToolSearch these schemas before
// calling them (proven by the Task-2 probe; a direct call without ToolSearch hits InputValidationError).
// The namespace depends on HOW the Figma MCP is registered in the session: a top-level server (the
// common setup — `~/.claude.json` mcpServers.figma) exposes `mcp__figma__*`; a plugin-bundled server
// (figma@claude-plugins-official loaded as a plugin) exposes `mcp__plugin_figma_figma__*`. Select BOTH
// namespaces — `select:` returns the names that exist and silently ignores the absent ones, so the same
// dispatch works regardless of provenance.
const FIGMA_MCP_TOOLSEARCH =
  'select:mcp__figma__get_design_context,mcp__plugin_figma_figma__get_design_context,' +
  'mcp__figma__get_variable_defs,mcp__plugin_figma_figma__get_variable_defs,' +
  'mcp__figma__get_screenshot,mcp__plugin_figma_figma__get_screenshot,' +
  'mcp__figma__get_metadata,mcp__plugin_figma_figma__get_metadata'

const PRODUCE_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['status', 'summary'],
  properties: {
    status: { type: 'string', enum: ['ok', 'error'] },
    artifactPath: { type: ['string', 'null'] },
    committed: { type: 'boolean' },
    commitSha: { type: ['string', 'null'] },
    summary: { type: 'string' },
  },
}

const GATE_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['block', 'fix-and-go', 'pass', 'unreachable'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: true,
        required: ['severity', 'message'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          file: { type: 'string' },
          line: { type: ['integer', 'string', 'null'] },
          message: { type: 'string' },
          source: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

// --- StructuredOutput-staller mitigation (shared posture with code-review.mjs, strengthened) ---
// figma `produce` is a heavy action agent (ToolSearch + run the plugin skill + write/commit) — the
// class most prone to ending its turn WITHOUT the forced StructuredOutput call. Same two defenses
// mirrored across every schema-forced workflow: a non-negotiable mandate ("final action MUST be the
// call", correct for an action agent that must act before reporting) + an inline retry on the
// StructuredOutput death class.
const STRUCTURED_OUTPUT_MANDATE =
  ' IMPORTANT: the StructuredOutput tool call is your ONLY deliverable — a prose write-up is' +
  ' discarded and counts as producing nothing. Do your work, then your FINAL action MUST be the' +
  ' StructuredOutput call; if you are running low on budget, call it early with partial results' +
  ' rather than writing a summary. Never end your turn without calling StructuredOutput.'

// Only the StructuredOutput-death error class is retried; genuine tool/permission errors throw
// straight through. Brittle substring match — the only signal the runtime surfaces.
const isNoStructuredOutputError = (err) => /StructuredOutput/.test(String(err))

// One schema'd dispatch with up to `retries` INLINE retries on a StructuredOutput death. Resolves
// to the agent result on success; throws the last error after exhausting retries.
const dispatchSchemaAgent = async (prompt, opts, retries = 2) => {
  let lastErr
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await agent(prompt, attempt === 0 ? opts : { ...opts, label: `${opts.label} (retry ${attempt})` })
    } catch (err) {
      lastErr = err
      if (!isNoStructuredOutputError(err)) throw err
      log(`${opts.label}: died without StructuredOutput — retry ${attempt + 1}/${retries}`)
    }
  }
  throw lastErr
}

// args (assembled in-session by the dispatching Stage; defensive string-or-object):
//   kind        — 'produce' | 'gate'
//   feWorktree  — absolute FE worktree path (ALL file ops / git / reads happen here, not the BE repo)
//   target      — the namespaced plugin component: a Skill (produce) or agentType (gate), e.g.
//                 'design-toolkit:figma-faithful-spec' / 'design-toolkit:figma-faithful-spec-reviewer'
//   inputs      — produce: { jiraSpec?, figmaSources?, bindingSpecPath? }; gate: { artifactPath, bindingSpecPath? }
//   outputPath  — produce: where to write the artifact
//   framesDir   — produce (spec): where to cache frame PNGs
//   produceArgs — produce: { implement?: bool, specFed?: bool }
//   jiraKey     — for labels/logging
const a = typeof args === 'string' ? JSON.parse(args) : args || {}
const { kind, feWorktree, target, inputs = {}, outputPath, framesDir, produceArgs = {}, jiraKey = '' } = a
if (kind !== 'produce' && kind !== 'gate') {
  throw new Error("figma workflow: args.kind must be 'produce' or 'gate'")
}
if (!feWorktree || !target) {
  throw new Error('figma workflow: args.feWorktree and args.target are required')
}

// Fail-closed envelopes — gate.unreachable is treated as block by the stage; produce.error aborts the stage.
const failClosed = (note) =>
  kind === 'gate'
    ? { verdict: 'unreachable', findings: [], summary: note }
    : { status: 'error', artifactPath: null, committed: false, commitSha: null, summary: note }

log(`figma: ${kind} via ${target} in ${feWorktree}${jiraKey ? ` (${jiraKey})` : ''}`)
phase('Figma')

// Cost discipline: the Workflow budget bounds the agent() call. Budget-exhausted skips dispatch
// cleanly — Stage 3/4/5 must not map it to figma-mcp-unreachable / figma-*-reviewer-block.
if (typeof budget !== 'undefined' && budget && budget.total) {
  log(`budget: ${Math.round(budget.remaining() / 1000)}k / ${Math.round(budget.total / 1000)}k tokens left`)
  if (budget.remaining() <= 0) {
    log('budget exhausted — skipping figma dispatch')
    return { kind, target, feWorktree, budgetExhausted: true }
  }
}

let prompt
let opts
if (kind === 'gate') {
  if (!inputs.artifactPath) {
    throw new Error('figma gate: inputs.artifactPath is required')
  }
  // Real reviewer agent (plugin agentType), fresh context. Evidence only: it reads the artifact +
  // its own FE reference docs. Figma-blind by design (tools: Read/Grep/Glob/Bash) — no MCP needed.
  prompt =
    `Review the figma artifact at \`${inputs.artifactPath}\`. ` +
    `All file reads / Grep / Glob / Bash must target the FE worktree \`${feWorktree}\` (NOT the BE repo) — ` +
    `resolve your reference docs there.` +
    (inputs.bindingSpecPath ? ` Cross-check against the binding spec at \`${inputs.bindingSpecPath}\`.` : '') +
    ` Return your trinary verdict (block | fix-and-go | pass) and findings.`
  // bounded-exploration-optout: figma gate -- unprobed surface, deliberately deferred; no measured
  //   stall and no before/after rate, which the issue guardrail requires before shipping a nudge.
  opts = { agentType: target, model: FIGMA_MODEL, label: target, phase: 'Figma', schema: GATE_SCHEMA }
} else {
  if (!outputPath) {
    throw new Error('figma produce: args.outputPath is required')
  }
  const implement = produceArgs.implement === true
  // Real plugin Skill, invoked inside a fresh subagent. Figma MCP tools are DEFERRED — the subagent
  // MUST ToolSearch them first (proven by the Task-2 probe).
  prompt =
    `You are running the design-toolkit figma-faithful skill from a BE-rooted session. ` +
    `Working directory for ALL file ops / git / reads: \`${feWorktree}\` (NOT the BE repo). ` +
    `FIRST call ToolSearch with query "${FIGMA_MCP_TOOLSEARCH}" to load the deferred Figma MCP tool schemas — ` +
    `the query lists both namespaces this session might expose them under (\`mcp__figma__*\` for a top-level ` +
    `Figma MCP, \`mcp__plugin_figma_figma__*\` for a plugin-bundled one); ToolSearch returns whichever are ` +
    `present. Use the EXACT tool names returned. They are NOT callable until you ToolSearch them ` +
    `(a direct call fails with InputValidationError). ` +
    `THEN invoke the Skill \`${target}\` (the real plugin skill — do not improvise its steps) and execute its ` +
    `full mandated sequence against the inputs: ` +
    (inputs.jiraSpec ? `JIRA spec provided; ` : '') +
    (inputs.figmaSources ? `figmaSources=${JSON.stringify(inputs.figmaSources)}; ` : '') +
    (inputs.bindingSpecPath ? `spec-fed from \`${inputs.bindingSpecPath}\` (trust its Copy Index); ` : '') +
    (framesDir ? `cache frame PNGs under \`${framesDir}\` (one per nodeId, ':'→'-', verify non-empty); ` : '') +
    `write the resulting artifact to \`${outputPath}\`. ` +
    (implement
      ? `IMPLEMENT mode: after the skill writes code, commit it in the FE worktree ` +
        `(\`git -C ${feWorktree} add -A && git commit\` with a conventional-commit message; do NOT push) ` +
        `and report committed=true with the resulting commitSha.`
      : `PLAN/SPEC mode: write the artifact only — do NOT write component code, do NOT commit (committed=false).`) +
    ` On any failure (Figma MCP unreachable, unresolved sparse dump, etc.) set status="error". ` +
    `Return {status, artifactPath, committed, commitSha, summary}.`
  // bounded-exploration-optout: figma produce -- a produce dispatch writes the artifact and may
  //   commit; bounding its reads would bound the deliverable itself.
  opts = { model: FIGMA_MODEL, label: `produce:${target}`, phase: 'Figma', schema: PRODUCE_SCHEMA }
}

prompt += STRUCTURED_OUTPUT_MANDATE

// A StructuredOutput death that survived the inline retries is flagged infraFailure so the stage can
// tell it apart from a genuine MCP-unreachable / spec error — never map it to figma-mcp-unreachable.
const result = await dispatchSchemaAgent(prompt, opts).catch((err) => ({
  ...failClosed('agent dispatch failed: ' + String(err)),
  ...(isNoStructuredOutputError(err) ? { infraFailure: true } : {}),
}))

return { kind, target, feWorktree, result }
