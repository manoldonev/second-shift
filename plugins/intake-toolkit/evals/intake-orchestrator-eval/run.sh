#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for intake-orchestrator.
#
# Usage:
#   ./run.sh                      # default baseline, 5 runs/fixture
#   ./run.sh "my-note"            # pass a changelog note
#   ./run.sh "smoke" --smoke      # 1 fixture × 1 run
#   ./run.sh "custom" --runs-per-fixture 3 --concurrency 2
#
# Any args after the note are forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-baseline}"
shift || true

# Sub-agent mocks run at haiku/low (if --agents supports per-agent model),
# judge runs at sonnet to save cost vs opus (see plan §Cost discipline).
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
- Do dispatch the Task() sub-agents (spec-reviewer, codebase-explorer) where your checklist calls for them — those are wired to mocks that will respond. Dependency analysis is now an in-session subroutine (no Task hop) — run it inline over the codebase-explorer output, do not dispatch a Task for it.

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
  --agents-template "$HERE/agents-template.json" \
  --reviewer-model claude-opus-4-7 \
  --judge-model claude-sonnet-4-6 \
  --reviewer-user-prompt-template "$PROMPT" \
  --judge-agent-name intake-judge \
  --judge-description "Scores intake-orchestrator outputs on 7-dim rubric" \
  --runs-per-fixture 5 \
  --concurrency 4 \
  --note "$NOTE" \
  "$@"
