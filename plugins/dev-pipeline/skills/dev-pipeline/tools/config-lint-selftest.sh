#!/usr/bin/env bash
# config-lint-selftest.sh — fixture-driven selftest for config-lint.sh
# Valid fixtures must pass; invalid fixtures must fail AND mention the expected violation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/config-lint.sh"
FIX="$HERE/config-lint-fixtures"
FAILS=0

check() { # $1 = label, $2 = expectation result (0 ok / 1 fail)
  if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS + 1)); fi
}

echo "config-lint selftest:"

for f in "$FIX"/valid-*.json; do
  if "$LINT" "$f" > /dev/null 2>&1; then check "$(basename "$f") passes" 0; else check "$(basename "$f") passes" 1; fi
done

expect_violation() { # $1 = fixture, $2 = expected substring in error output
  local out
  if out=$("$LINT" "$FIX/$1" 2>&1); then
    check "$1 fails" 1
  elif grep -qF "$2" <<< "$out"; then
    check "$1 fails mentioning '$2'" 0
  else
    check "$1 fails mentioning '$2' (got: $(head -3 <<< "$out" | tr '\n' ' '))" 1
  fi
}

expect_violation invalid-bad-tracker.json           "tracker.type must be github|jira"
expect_violation invalid-pair-missing-fe.json       "be-fe-pair requires repos.be and repos.fe"
expect_violation invalid-unknown-repo-and-tier.json "commands keyed by unknown repo ids: ghost"
expect_violation invalid-unknown-repo-and-tier.json "reviewers.modelOverrides.security-reviewer: must be haiku|sonnet|opus"
expect_violation invalid-tracker-unknown-key.json   "tracker: unknown keys"
expect_violation invalid-bot-app-unknown-key.json   "tracker.bot.app: unknown keys"

# missing file → usage error (3), not a lint failure
if "$LINT" "$FIX/does-not-exist.json" > /dev/null 2>&1; then rc=0; else rc=$?; fi
check "missing file exits 3" "$([[ "$rc" -eq 3 ]] && echo 0 || echo 1)"

if [[ "$FAILS" -gt 0 ]]; then echo "config-lint selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "config-lint selftest: all green"
