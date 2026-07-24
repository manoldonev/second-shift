#!/usr/bin/env bash
# workflows-mjs-selftest.sh — runs the workflows/ .mjs selftests under CI.
#
# Why this shim exists: CI discovers selftests purely by the `*-selftest.sh` glob
# (.github/workflows/ci.yml), so a `.mjs` selftest is invisible to it no matter how
# thorough it is. Before this file, neither sibling ran in CI:
#   - null-reviewer-selftest.mjs  — executed ONLY by tools/pipeline-doctor.sh, an
#                                   operator diagnostic that CI never invokes.
#   - design-sync-selftest.mjs    — no executor anywhere in the tree.
# Both are real, asserting suites; they were simply unreachable. This shim rides the
# glob and hands them to node.
#
# Deliberately located next to the .mjs files it runs, rather than in skills/run/ or
# tools/ with the other shell harnesses: it is a thin adapter for THIS directory's
# contents, and a reader deleting a workflow selftest should see its runner alongside.
#
# Exit code = number of failed suites (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# node absent is a FAIL, never a silent green — the repo convention, matching
# tools/text-contract-selftest.sh. Both CI lanes provide node; a missing node means
# the environment is wrong, and skipping would report success for suites that never ran.
command -v node >/dev/null 2>&1 || {
  echo "workflows-mjs-selftest: FAIL — node is required to execute the workflows .mjs selftests." >&2
  exit 1
}

FAILS=0
run_mjs() {
  local name="$1" path="$HERE/$1"
  if [[ ! -f "$path" ]]; then
    echo "  FAIL: $name missing at $path" >&2
    FAILS=$((FAILS + 1))
    return
  fi
  echo "── $name"
  if node "$path"; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name (exit $?)" >&2
    FAILS=$((FAILS + 1))
  fi
}

echo "[workflows-mjs-selftest]"
run_mjs design-sync-selftest.mjs
run_mjs null-reviewer-selftest.mjs

echo "[workflows-mjs-selftest] $([[ $FAILS -eq 0 ]] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit $FAILS
