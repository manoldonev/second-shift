#!/bin/bash

# needs_typecheck: read newline-delimited staged paths on stdin; return 0 (gate —
# run type-check) when a type-check is warranted, 1 (skip) otherwise.
#
# The type-check gates only commits that stage JS/TS-relevant files (sources, json
# config, lockfile). Skip when there is no JS/TS surface at all (docs/shell-only —
# also saves ~30s on every docs commit), OR when every JS/TS-relevant staged path
# is an inert .claude/**/*.{mjs,cjs} Workflow script. Those scripts live outside the
# yarn workspace tree and are referenced by no tsconfig/eslint/jest config, so
# type-check gives them zero coverage — gating on them is pure wasted node_modules
# install + run. This mirrors the Stage-6 inert lane; the inert set is defined once in
# the dev-pipeline skill's tools/is-inert-diff.sh (the single source of truth), and
# the .claude/**/*.{mjs,cjs} pattern below is kept in lockstep with it (asserted by
# pre-commit-typecheck-selftest.sh).
# A .mjs/.cjs OUTSIDE .claude/ (e.g. apps/web/next.config.mjs) is not inert and
# still gates.
needs_typecheck() {
  local relevant
  relevant=$(grep -E '(\.(ts|tsx|js|jsx|mjs|cjs|json)$|^yarn\.lock$)')
  [ -z "$relevant" ] && return 1
  # Gate iff at least one JS/TS-relevant path is NOT an inert .claude script.
  printf '%s\n' "$relevant" | grep -qvE '^\.claude/.*\.(mjs|cjs)$'
}

# When sourced (e.g. by pre-commit-typecheck-selftest.sh) expose needs_typecheck and
# stop before the gate body — which reads the hook event JSON from /dev/stdin and
# would otherwise block. Executed directly, BASH_SOURCE[0] == $0 and this is skipped.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then return 0 2>/dev/null; fi

CWD=$(jq -r '.cwd' < /dev/stdin)
cd "$CWD" || exit 1

# Static context: the typecheck command comes from the consumer repo's
# .claude/second-shift.config.json (host repo = the topology.repos entry with
# path "."; override: SECOND_SHIFT_CONFIG). No repo, no config, or a null
# typecheck command => nothing to gate — fail OPEN (the repo has not onboarded
# a typecheck lane; a plugin-shipped hook must not block commits in arbitrary repos).
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CFG="${SECOND_SHIFT_CONFIG:-$ROOT/.claude/second-shift.config.json}"
[ -f "$CFG" ] || exit 0
HOST=$(jq -r '.topology.repos | to_entries[] | select(.value.path == ".") | .key' "$CFG" 2>/dev/null | head -n1)
[ -n "$HOST" ] || exit 0
TYPECHECK_CMD=$(jq -r --arg h "$HOST" '.commands[$h].typecheck // empty' "$CFG" 2>/dev/null)
[ -n "$TYPECHECK_CMD" ] || exit 0

if ! git diff --cached --name-only | needs_typecheck; then
  exit 0
fi

if ! bash -c "$TYPECHECK_CMD" 2>&1; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "type-check failed — fix type errors before committing."
    }
  }'
  exit 0
fi

exit 0
