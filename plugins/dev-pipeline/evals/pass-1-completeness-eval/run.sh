#!/usr/bin/env bash
#
# Measure the completeness half of the lane's pass-1 review: does a review report a ticket criterion
# that the change leaves out, or leaves untested, and does it raise no such claim on the complete change.
#
# Model identity is the operator's, not the repo's. REVIEWER_MODEL and JUDGE_MODEL are REQUIRED. Each
# may be a version-pinned id or one of the CLI's aliases: the changelog row records the id the CLI
# resolved. The judge must be on another tier than the reviewer.
#
# Operator-run and model-billed. Never in CI. --check-fixture is model-free and needs neither variable.
#
# Usage:
#   ./run.sh --check-fixture [--fixture tuning]
#   REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --judge-sanity
#   REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm pass-1 --arm plain --runs 5 --note "why"
#
# Every other argument goes to eval.py; `./run.sh --help` lists them.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

billed=1
for a in "$@"; do
  case "$a" in --check-fixture|-h|--help) billed=0 ;; esac
done
if [ "$billed" = 1 ]; then
  : "${REVIEWER_MODEL:?REVIEWER_MODEL is required: a version-pinned model id, or a CLI alias (the row records the resolved id)}"
  : "${JUDGE_MODEL:?JUDGE_MODEL is required: a model on another tier than the reviewer}"
else
  export REVIEWER_MODEL="${REVIEWER_MODEL:-unset}" JUDGE_MODEL="${JUDGE_MODEL:-unset}"
fi

exec python3 "$HERE/eval.py" "$@"
