#!/usr/bin/env bash
# design-lib-selftest.sh — runs this directory's `node --test` suites under CI.
#
# Why this shim exists: CI discovers selftests purely by the `*-selftest.sh` glob
# (.github/workflows/ci.yml), so a `.test.mjs` suite is invisible to it no matter how
# thorough it is. Before this file, design-toolkit shipped two real, asserting node
# test suites that NO CI lane executed:
#   - extractor.test.mjs
#   - emit.test.mjs
# They were never broken — they were simply unreachable. This shim rides the glob and
# hands them to node, exactly as workflows/workflows-mjs-selftest.sh does for the
# dev-pipeline .mjs selftests.
#
# Deliberately located next to the suites it runs, rather than in a central tests/
# dir: it is a thin adapter for THIS directory's contents, and a reader deleting a
# test suite should see its runner alongside.
#
# Exit code = number of failed suites (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# node absent is a FAIL, never a silent green — the repo convention, matching
# workflows/workflows-mjs-selftest.sh and tools/text-contract-selftest.sh. Both CI
# lanes provide node; a missing node means the environment is wrong, and skipping
# would report success for suites that never ran.
command -v node >/dev/null 2>&1 || {
  echo "design-lib-selftest: FAIL — node is required to execute the design-faithful lib test suites." >&2
  exit 1
}

FAILS=0
run_suite() {
  local name="$1" path="$HERE/$1"
  if [[ ! -f "$path" ]]; then
    echo "  FAIL: $name missing at $path" >&2
    FAILS=$((FAILS + 1))
    return
  fi
  echo "── $name"
  if node --test "$path"; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name (exit $?)" >&2
    FAILS=$((FAILS + 1))
  fi
}

echo "[design-lib-selftest]"
run_suite extractor.test.mjs
run_suite emit.test.mjs

echo "[design-lib-selftest] $([[ $FAILS -eq 0 ]] && echo 'all green' || echo "$FAILS FAILURE(S)")"
exit $FAILS
