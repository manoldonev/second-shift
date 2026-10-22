#!/usr/bin/env bash
#
# Score a code reviewer against the Martian Code Review Bench offline set (data/): known bugs per
# PR, the benchmark's own matching rule, precision/recall/F1 per arm.
#
# Model identity is the operator's, not the repo's (#356). REVIEWER_MODEL and JUDGE_MODEL are
# REQUIRED. Each may be a version-pinned id or one of the CLI's dispatch aliases: the changelog row
# records the id the CLI resolved, never the alias. The judge must be the other model family from
# the reviewer; the harness checks that on the resolved ids and refuses otherwise.
#
# Operator-run and model-billed. Never in CI — CI in this repo is model-free by design. A full
# 10-PR arm is roughly 45 session-minutes on the seat the checkouts' remote resolves to, plus the
# judge's calls; smoke first.
#
# Usage (every form needs both variables):
#   REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --smoke
#   ... ./run.sh --arm plain --arm review-lead-lane --set dev --runs 2 --note "baseline"
#   ... ./run.sh --calibration-only --set dev          # the judge gate alone
#   ... ./run.sh --arm plain --set heldout --runs 2    # the held-out set: never used to tune a prompt
#
# --reviewer is accepted as an alias of --arm. Any other arg is forwarded to bench.py.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

: "${REVIEWER_MODEL:?REVIEWER_MODEL is required — a version-pinned model id, or a CLI alias (the row records the resolved id)}"
: "${JUDGE_MODEL:?JUDGE_MODEL is required — the other model family from the reviewer}"

bash "$HERE/check-data.sh"

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer) args+=(--arm "$2"); shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done

exec python3 "$HERE/bench.py" --eval-dir "$HERE" \
  --reviewer-model "$REVIEWER_MODEL" --judge-model "$JUDGE_MODEL" \
  ${args[@]+"${args[@]}"}
