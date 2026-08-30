#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for figma-faithful-plan-reviewer.
#
# Model identity is the operator's, not the repo's (#356). REVIEWER_MODEL and JUDGE_MODEL are
# REQUIRED and must carry version-pinned ids — no default here, and the runner refuses the bare
# dispatch aliases, because `changelog.md` records the reviewer model as the key two rows are
# compared on and a floating alias makes that key meaningless a release later.
#
# Operator-run and model-billed. Never in CI — CI in this repo is model-free by design.
#
# Usage (every form needs both variables):
#   REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh
#   ... ./run.sh "my-note"                        # pass a changelog note
#   ... ./run.sh "smoke" --smoke                  # one fixture x one run
#   ... ./run.sh "baseline" --runs-per-fixture 3 --concurrency 2
#
# Any args after the note are forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$HERE/../../../review-toolkit/evals/agent-eval-kit"
NOTE="${1:-baseline}"
shift || true

: "${REVIEWER_MODEL:?REVIEWER_MODEL is required — set it to a version-pinned model id}"
: "${JUDGE_MODEL:?JUDGE_MODEL is required — set it to a version-pinned model id}"

# The agent normally receives a translation plan by path from `figma-faithful` step 7, or reads
# the committed lean-lane artifact. Here the fixture file IS the plan, so it takes the path
# directly — no override of the reviewer's input discipline is needed, only the anchor that the
# fixture is the whole input and there is no surrounding branch to inspect.
python3 "$KIT/run-eval.py" \
  --agent-name figma-faithful-plan-reviewer \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$HERE/fixtures" \
  --eval-dir "$HERE" \
  --repo-root "$HERE" \
  --reviewer-user-prompt-template 'Review the figma-faithful translation plan at {fixture_path}. That file IS the whole plan — this is an eval, there is no branch checked out and no spec to cross-check, so review what the plan carries and say which checks had no input. Respond strictly in the Output Format specified in your instructions and the reviewer-baseline, ending with the REVIEW_RESULT sentinel and one fenced JSON block. Run ID: {run_id}' \
  --judge-agent-name plan-translation-judge \
  --judge-description "Scores figma-faithful translation-plan reviews on a 3-dim / 10-pt rubric" \
  --runs-per-fixture 3 \
  --concurrency 2 \
  --note "$NOTE" \
  --reviewer-model "$REVIEWER_MODEL" \
  --judge-model "$JUDGE_MODEL" \
  "$@"
