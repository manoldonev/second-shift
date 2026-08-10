#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for plan-reviewer.
#
# Model identity is the operator's, not the repo's (#356). REVIEWER_MODEL and JUDGE_MODEL are
# REQUIRED and must carry version-pinned ids — no default here, and the runner refuses the bare
# dispatch aliases, because `changelog.md` records the reviewer model as the key two rows are
# compared on and a floating alias makes that key meaningless a release later.
#
# Usage (every form needs both variables):
#   REVIEWER_MODEL=<pin> JUDGE_MODEL=<pin> ./run.sh
#   ... ./run.sh "my-note"          # pass a changelog note
#   ... ./run.sh "smoke" --smoke    # one fixture x one run
#   ... ./run.sh "custom" --runs-per-fixture 3 --concurrency 2
#
# A/B a reviewer model (the changelog row records model= so two rows diff cleanly): run twice
# with the same JUDGE_MODEL and two different REVIEWER_MODEL pins and distinguishable notes,
# then compare the two model=... rows in changelog.md.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-baseline}"
shift || true

: "${REVIEWER_MODEL:?REVIEWER_MODEL is required — set it to a version-pinned model id}"
: "${JUDGE_MODEL:?JUDGE_MODEL is required — set it to a version-pinned model id}"

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
  --reviewer-model "$REVIEWER_MODEL" \
  --judge-model "$JUDGE_MODEL" \
  "$@"
