#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for plan-reviewer.
#
# Usage:
#   ./run.sh                    # default baseline, 6 runs/fixture
#   ./run.sh "my-note"          # pass a changelog note
#   ./run.sh "smoke" --smoke    # one fixture x one run
#   ./run.sh "custom" --runs-per-fixture 3 --concurrency 2
#
# A/B a reviewer model (the changelog row records model= so two rows diff cleanly):
#   ./run.sh "opus-baseline"                                # default (runner --model)
#   REVIEWER_MODEL=claude-sonnet-4-6 ./run.sh "sonnet-ab"   # the B run
# then compare the two model=... rows in changelog.md.
#
# REVIEWER_MODEL (env) sets the reviewer model first-class; default unset = the
# runner's --model default. Any args after the note are also forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-baseline}"
shift || true
REVIEWER_MODEL="${REVIEWER_MODEL:-}"

python3 "$HERE/../agent-eval-kit/run-eval.py" \
  --agent-name plan-reviewer \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$REPO/docs/plans/test-fixtures" \
  --eval-dir "$HERE" \
  --reviewer-user-prompt-template 'Review the plan at {fixture_path}. Respond strictly in the Output Format specified in your instructions. Run ID: {run_id}' \
  --judge-agent-name plan-review-judge \
  --judge-description "Scores plan reviews on 8-dim rubric" \
  --runs-per-fixture 6 \
  --concurrency 4 \
  --note "$NOTE" \
  ${REVIEWER_MODEL:+--reviewer-model "$REVIEWER_MODEL"} \
  "$@"
