#!/usr/bin/env bash
# Fills the eval workspace, the current directory, with the ticket and repo snapshot of the
# decision-questions case, and adds INTERVIEW.md. The two cases share one ticket and one snapshot
# commit, so that scaffold stays their only owner.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$CASE_DIR/../decision-questions-eval/scaffold.sh"
cp "$CASE_DIR/fixture/INTERVIEW.md" ./INTERVIEW.md
