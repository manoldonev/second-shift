#!/usr/bin/env bash
# design-lib-selftest.sh — runs this directory's `node --test` suites under CI.
#
# CI discovers selftests by the `*-selftest.sh` glob (.github/workflows/ci.yml), so a
# `.test.mjs` suite runs in CI only through a shim like this one, as
# workflows/workflows-mjs-selftest.sh does for review-toolkit. It sits beside the
# suites it runs, so a reader deleting a suite sees its runner.
#
# Exit code = number of failed suites (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# node absent is a FAIL, never a silent green: skipping would report success for
# suites that never ran.
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
