#!/usr/bin/env bash
#
# Wrapper to invoke the generic agent-eval-kit runner for the review-lead
# SYNTHESIS-ONLY eval.
#
# review-lead is a SKILL, not an `--agent` target, and its synthesis runs over
# findings already produced by code-review.mjs. So this campaign drives the thin
# `review-lead-synth` wrapper agent (`.claude/agents/review-lead-synth.md`), which
# loads the review-lead skill and consolidates a canned reviewer-findings set from
# each fixture. The wrapper resolves the skill by repo-root-relative path, so
# run-eval.py's --repo-root must point at the repo (it does, via $REPO below).
#
# NOTE: there is NO baseline yet. The first invocation establishes it. A real run
# spawns `claude -p` subprocesses and costs money — do not run it from the
# dev-pipeline; use the $0 smoke (smokes/validate-fixtures.sh) for CI/pre-flight.
#
# Usage:
#   ./run.sh                    # default note, 5 runs/fixture
#   ./run.sh "my-note"          # pass a changelog note
#   ./run.sh "smoke" --smoke    # one fixture x one run
#
# A/B a reviewer model (the changelog row records model= so two rows diff cleanly):
#   ./run.sh "opus-baseline"                                # default claude-opus-4-7
#   REVIEWER_MODEL=claude-sonnet-4-6 ./run.sh "sonnet-ab"   # the B run
# then compare the two model=... rows in changelog.md.
#
# REVIEWER_MODEL (env) sets the reviewer model first-class; default = claude-opus-4-7
# (today's behavior). Any args after the note are also forwarded to the runner.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
NOTE="${1:-baseline}"
shift || true
REVIEWER_MODEL="${REVIEWER_MODEL:-claude-opus-4-7}"

# shellcheck disable=SC2016 # backticked markdown in the prompt template is literal by design
python3 "$HERE/../agent-eval-kit/run-eval.py" \
  --agent-name review-lead-synth \
  --rubric "$HERE/rubric.py" \
  --fixtures-dir "$REPO/docs/eval-fixtures/review-lead" \
  --eval-dir "$HERE" \
  --repo-root "$REPO" \
  --reviewer-model "$REVIEWER_MODEL" \
  --judge-model claude-sonnet-4-6 \
  --reviewer-user-prompt-template 'You are review-lead in synthesis-only mode. Read the PR context + canned reviewer findings at {fixture_path} and produce your consolidated review report exactly per the review-lead skill Report structure — ending in the `## Verdicts` table and a `**Ready to merge?** Yes / No / With fixes` line. Do not run gh or dispatch reviewers. Run ID: {run_id}' \
  --judge-agent-name review-lead-synth-judge \
  --judge-description "Scores review-lead synthesis outputs on the 5-dim rubric" \
  --runs-per-fixture 5 \
  --concurrency 4 \
  --note "$NOTE" \
  "$@"
