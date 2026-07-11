#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for security-reviewer.
#
# Usage:
#   ./run.sh                       # default baseline, 6 runs/fixture
#   ./run.sh "my-note"             # pass a changelog note
#   ./run.sh "smoke" --smoke       # one fixture x one run
#   ./run.sh "custom" --runs-per-fixture 3 --concurrency 2
#
# Any args after the note are forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-baseline}"
shift || true

# The reviewer's own prompt says "Run `git diff` to see changes", but in this
# eval there is no checked-out branch — the fixture file IS the diff. Tell the
# reviewer to read the fixture directly and treat its contents as the PR diff.
# shellcheck disable=SC2016 # backticked markdown in the prompt template is literal by design
python3 "$HERE/../agent-eval-kit/run-eval.py" \
  --agent-name security-reviewer \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$REPO/docs/eval-fixtures/security-reviewer" \
  --eval-dir "$HERE" \
  --reviewer-user-prompt-template 'Security-review the diff at {fixture_path}. The file contents ARE the PR diff — do NOT run `git diff` (this is an eval; no branch is checked out). Read the fixture file directly and apply your full security rubric. You MAY Read or Grep adjacent real repo files to check sibling-pattern context (the diff references real Acme paths). Respond strictly in the Output Format specified in your instructions and the reviewer-baseline. Run ID: {run_id}' \
  --judge-agent-name security-review-judge \
  --judge-description "Scores security reviews on 5-dim / 10-pt rubric" \
  --runs-per-fixture 6 \
  --concurrency 4 \
  --note "$NOTE" \
  "$@"
