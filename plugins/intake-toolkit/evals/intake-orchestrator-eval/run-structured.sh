#!/usr/bin/env bash
#
# "WITH structured hand-off" variant of run.sh (issue #134).
#
# Drives the same fixtures and the same expected.json as run.sh, but feeds the
# sub-agent output as the rationale-carrying STRUCTURED object (via
# agents-template.structured.json + the *-structured.txt mocks) and tells the
# orchestrator to reason over the parsed object. Pair the pass-rate of this run
# against the prose baseline (run.sh): a token win with ANY verdict/finding drift
# is a FAIL. Identical pass set across both => reasoning-equivalence proven.
#
# NOTE on scope (issue #134, decision D1): the eval kit mocks sub-agents via the
# Task-tool `--agents` flag; it does NOT run the live `intake-review.mjs` Workflow.
# This harness therefore proves the orchestrator's REASONING-equivalence over a
# schema-shaped object, not the live Workflow runtime (validated separately).
#
# Usage:
#   ./run-structured.sh                      # default note, 5 runs/fixture
#   ./run-structured.sh "my-note"            # pass a changelog note
#   ./run-structured.sh "smoke" --smoke      # 1 fixture × 1 run
#
# Any args after the note are forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-structured-handoff}"
shift || true

read -r -d '' PROMPT <<'PROMPT_EOF' || true
You are being evaluated as the intake-orchestrator. Run your full checklist on the GitHub issue below. RUN_ID: {run_id}.

ISSUE #{issue_number} ({issue_state})
Title: {issue_title}
Labels: {issue_labels}

<body>
{issue_body}
</body>

<prior_comments>
{issue_comments}
</prior_comments>

EVAL CONSTRAINTS (important):
- This is an isolated evaluation. Do NOT execute `gh` commands — the environment has no GitHub access and all `gh` calls will fail.
- Skip Step 0's `gh issue view` call; the issue body, labels, prior comments, and metadata above ARE the canonical data.
- For every side effect you would normally perform (creating sub-issues, editing the parent issue, posting a comment), describe it clearly in your final output instead of executing it.
- Dispatch the Task() sub-agents (spec-reviewer, codebase-explorer) where your checklist calls for them — those are wired to mocks that will respond. (Task dispatch is the EVAL-HARNESS transport only; production dispatches the same fan-out via the Workflow tool / intake-review.mjs. The eval kit cannot mock Workflow agent() calls, so it drives the equivalent Task path — the orchestrator's reasoning over the structured object is identical either way.) In this run the mocks return your sub-agents' RATIONALE-CARRYING STRUCTURED OUTPUT (JSON matching the intake schema: spec-reviewer => {verdict, findings[{severity, category, claim, impact, rationale, suggestion, confidence}]}; codebase-explorer => {modulesAffected, crossModuleDependencies, existingPatterns, estimatedScope, findings}). Parse and reason over the structured object — use each finding's `rationale`/`evidence` to accept or dismiss it, exactly as you would with prose. Dependency analysis is an in-session subroutine (no Task hop) — run it inline over the codebase-explorer object.

Respond with your final intake comment in the machine-readable format your instructions specify. Include:
- The `<!-- dev-pipeline -->` / `<!-- stage: intake -->` / `<!-- status: ... -->` markers
- Your type classification
- Your decomposition verdict (no-split / sub-issues / stacked-prs / escalate / skip-already-decomposed)
- If sub-issues or stacked-prs: an explicit list of the slices you would create (titles + one-line scope each)
- Any label/assignee edits you would apply to the parent issue
- If escalating: the escalation reason (needs-intake-review / needs-spec-work) and the question for the human
PROMPT_EOF

python3 "$HERE/../../../review-toolkit/evals/agent-eval-kit/run-eval.py" \
  --agent-name intake-orchestrator \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$REPO/docs/eval-fixtures/intake-orchestrator" \
  --eval-dir "$HERE" \
  --agents-template "$HERE/agents-template.structured.json" \
  --reviewer-model claude-opus-4-7 \
  --judge-model claude-sonnet-4-6 \
  --reviewer-user-prompt-template "$PROMPT" \
  --judge-agent-name intake-judge \
  --judge-description "Scores intake-orchestrator outputs on 7-dim rubric" \
  --runs-per-fixture 5 \
  --concurrency 4 \
  --note "$NOTE" \
  "$@"
