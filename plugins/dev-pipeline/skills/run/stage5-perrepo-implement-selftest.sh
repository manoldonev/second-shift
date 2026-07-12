#!/usr/bin/env bash
# stage5-perrepo-implement-selftest.sh — drift guard for the be-fe-pair DUAL-target
# per-repo implement instruction (#48 Phase 3).
#
# Stage 5's implement step is LLM-orchestration prose, not testable bash: for a dual
# `[BE]+[FE]` ticket the model must author code in EVERY target worktree and commit
# per-repo (never mixing repos in one commit). There is no mechanical output to assert,
# so this guards that the load-bearing instruction stays present — a silent removal
# would regress dual-target back to primary-repo-only (the exact #48 gap) with no other
# test catching it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE5_MD="$HERE/stages/5-implement.md"
FAILS=0
ok() { echo "  PASS: $1"; }
no() { echo "  FAIL: $1"; FAILS=$((FAILS+1)); }

echo "[stage5-perrepo-implement-selftest]"
[[ -f "$STAGE5_MD" ]] || { echo "  FAIL: stages/5-implement.md not found at $STAGE5_MD"; exit 1; }

drift() { grep -qF "$1" "$STAGE5_MD" && ok "stage5 carries \`$1\` ($2)" || no "stage5 MISSING \`$1\` ($2)"; }

drift 'be-fe-pair dual-target' 'the dual-target implement bullet'
drift 'git -C <repo worktree> commit' 'the per-repo commit instruction'
drift 'Never mix files from two repos in one commit' 'the one-commit-one-repo rule'
drift '.worktrees.\"<repoId>\".worktreePath' 'per-repo worktree resolution from the map'
# The bullet must be gated on targetRepos so single-target / non-pair runs are unaffected.
drift '.targetRepos' 'the dual-target gate (single-target/non-pair skip the bullet)'

echo "[stage5-perrepo-implement-selftest] $([[ $FAILS -eq 0 ]] && echo 'all green' || echo "$FAILS FAILURE(S)")"
[[ $FAILS -eq 0 ]]
