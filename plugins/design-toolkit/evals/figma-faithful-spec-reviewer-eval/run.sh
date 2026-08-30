#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for figma-faithful-spec-reviewer.
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

# The agent takes a spec artifact by path, so the fixture path goes straight in. What the template
# must NOT do is tell the agent what shape the input is: fixture 01 is a lean-lane spec, and
# whether the agent reviews it or declines it as "not a figma-faithful spec" is the thing #704's
# AC-4 measures. A prompt that pre-classified the input would grade the prompt, not the agent.
python3 "$KIT/run-eval.py" \
  --agent-name figma-faithful-spec-reviewer \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$HERE/fixtures" \
  --eval-dir "$HERE" \
  --repo-root "$HERE" \
  --reviewer-user-prompt-template 'Review the design artifact at {fixture_path}. That file IS the whole input — this is an eval, there is no branch checked out and no component catalog in this repo to resolve imports against. Apply your own input discipline and your own checklist. Respond strictly in the Output Format specified in your instructions and the reviewer-baseline, ending with the REVIEW_RESULT sentinel and one fenced JSON block. Run ID: {run_id}' \
  --judge-agent-name figma-spec-judge \
  --judge-description "Scores figma-faithful spec reviews on a 3-dim / 10-pt rubric" \
  --runs-per-fixture 3 \
  --concurrency 2 \
  --note "$NOTE" \
  --reviewer-model "$REVIEWER_MODEL" \
  --judge-model "$JUDGE_MODEL" \
  "$@"
