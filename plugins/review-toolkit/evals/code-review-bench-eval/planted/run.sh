#!/usr/bin/env bash
#
# The planted mode of the code-review bench: a plain review with the ticket against the lane's review, on
# the planted cases under cases/. Right, wrong, harm and noise per class and arm, appended to changelog.md.
#
# JUDGE_MODEL is REQUIRED, as for the known-bug bench: an id or a CLI alias on the other model family from
# every reviewer. The plain and lane arms need REVIEWER_MODEL; the blind-prove arm needs HUNT_MODEL,
# PROVE_MODEL (the other family from hunt) and INTENT_MODEL instead. planted.py refuses a missing one before
# any session. The judge's calibration on the bench's dev set runs first.
#
# Operator-run and model-billed. Never in CI — CI runs only the model-free selftests beside this file. The
# cases clone their upstreams at depth 1 into the cache dir on first use.
#
# Usage:
#   REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --arm lane --runs 3 --note "why"
#   ... ./run.sh --arm lane --case <id> --runs 1 --no-record      # one case, nothing recorded
#   HUNT_MODEL=<id> PROVE_MODEL=<id> INTENT_MODEL=<id> JUDGE_MODEL=<id> ./run.sh --arm blind-prove --runs 3 --note "why"
#
# Any arg is forwarded to `planted.py run`.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

: "${JUDGE_MODEL:?JUDGE_MODEL is required — the other model family from every reviewer}"

python3 "$HERE/planted.py" check
exec python3 "$HERE/planted.py" run --reviewer-model "${REVIEWER_MODEL:-}" --judge-model "$JUDGE_MODEL" "$@"
