#!/usr/bin/env bash
#
# The planted mode of the code-review bench: a plain review with the ticket against the lane's review, on
# the planted cases under cases/. Right, wrong, harm and noise per class and arm, appended to changelog.md.
#
# REVIEWER_MODEL and JUDGE_MODEL are REQUIRED, as for the known-bug bench: an id or a CLI alias, and the
# judge on the other model family. The judge's calibration on the bench's dev set runs first.
#
# Operator-run and model-billed. Never in CI — CI runs only the model-free selftests beside this file. The
# cases clone their upstreams at depth 1 into the cache dir on first use.
#
# Usage:
#   REVIEWER_MODEL=<id|alias> JUDGE_MODEL=<id|alias> ./run.sh --arm plain --arm lane --runs 3 --note "why"
#   ... ./run.sh --arm lane --case <id> --runs 1 --no-record      # one case, nothing recorded
#
# Any arg is forwarded to `planted.py run`.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

: "${REVIEWER_MODEL:?REVIEWER_MODEL is required — a version-pinned model id, or a CLI alias (the row records the resolved id)}"
: "${JUDGE_MODEL:?JUDGE_MODEL is required — the other model family from the reviewer}"

python3 "$HERE/planted.py" check
exec python3 "$HERE/planted.py" run --reviewer-model "$REVIEWER_MODEL" --judge-model "$JUDGE_MODEL" "$@"
