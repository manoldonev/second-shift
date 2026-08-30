#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for figma-faithful-reviewer.
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

# Two overrides, both forced by what this agent expects and this repo does not have.
#
# 1. THE DIFF. The reviewer's own Process step 1 is "diff against the configured base branch", but
#    in an eval there is no branch checked out — the fixture file IS the diff. Same shape as
#    ../../../review-toolkit/evals/security-reviewer-eval/run.sh.
# 2. THE DESIGN-SYSTEM REFERENCE. The agent loads `.claude/second-shift/design-tokens/*.md` to
#    ground every rule it applies. second-shift has no FE app and no such reference, so the eval
#    ships a synthetic two-surface one (a fixed-theme surface and a branded host-relative surface)
#    under fixtures/design-tokens/ and names its path here. `--repo-root` points at this directory
#    so the agent's cwd contains both that reference and the greppable component export stubs
#    under fixtures/app/ — the eval measures whether the agent VERIFIES a catalog component exists
#    before flagging a hand-rolled substitute, which needs something real to grep.
#
# shellcheck disable=SC2016 # backticked markdown in the prompt template is literal by design
python3 "$KIT/run-eval.py" \
  --agent-name figma-faithful-reviewer \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$HERE/fixtures" \
  --eval-dir "$HERE" \
  --repo-root "$HERE" \
  --reviewer-user-prompt-template 'Review the diff at {fixture_path} for design-token fidelity. The file contents ARE the diff — do NOT run `git diff` (this is an eval; no branch is checked out). This repo has no FE app, so read the design-system reference at fixtures/design-tokens/ instead of `.claude/second-shift/design-tokens/`: fixtures/design-tokens/acme-ui-catalog.md is the component catalog, fixtures/design-tokens/acme-ui-design-tokens-console.md governs files under apps/console/, and fixtures/design-tokens/acme-ui-design-tokens-storefront.md governs files under apps/storefront/. The catalog names source paths under packages/acme-ui/; those files exist as export stubs under fixtures/app/, so grep there when you need to confirm a component is real. No approved FE spec or Copy Index is discoverable — say so and skip copy review. Respond strictly in the Output Format specified in your instructions and the reviewer-baseline, ending with the REVIEW_RESULT sentinel and one fenced JSON block. Run ID: {run_id}' \
  --judge-agent-name figma-fidelity-judge \
  --judge-description "Scores design-token fidelity reviews on a 3-dim / 10-pt rubric" \
  --runs-per-fixture 3 \
  --concurrency 2 \
  --note "$NOTE" \
  --reviewer-model "$REVIEWER_MODEL" \
  --judge-model "$JUDGE_MODEL" \
  "$@"
