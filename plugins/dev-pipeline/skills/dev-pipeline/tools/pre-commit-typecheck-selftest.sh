#!/usr/bin/env bash
#
# Self-test for the pre-commit type-check hook's inert carve-out
# (.claude/hooks/pre-commit-typecheck.sh).
#
# A self-test in the style of claim-selftest.sh / slice-derivation-selftest.sh:
# pure-local, no Claude CLI, no network, no yarn. It SOURCES the hook to obtain its
# `needs_typecheck` predicate (the hook's sourcing guard returns before the gate
# body, so no /dev/stdin read or `yarn type-check` runs) and drives it with
# synthetic staged-path lists, asserting gate (rc 0) vs skip (rc 1) for each.
#
# WHY this exists (#228): the hook gated every staged .mjs/.cjs unconditionally,
# but the inert set (defined in tools/is-inert-diff.sh) already treats
# .claude/**/*.{mjs,cjs} Workflow scripts as INERT (zero tsconfig/eslint/jest
# coverage). The hook mirrors that carve-out for .claude/**/*.{mjs,cjs}. This test
# locks the predicate AND the lockstep contracts the carve-out depends on:
#   - the hook's .claude carve-out extensions match is-inert-diff.sh (the single
#     source of truth for the inert set),
#   - Stage-6 (6-verify.md) delegates the lane decision to is-inert-diff.sh rather
#     than re-inlining the grep, and
#   - the embedded copy of the script in hooks.md matches the real script verbatim.
#
# DRIFT MODEL: the parity tail fails if the hook's inert extension set changes without
# is-inert-diff.sh following (lockstep), if 6-verify.md stops delegating to the script,
# or if hooks.md's embedded ```bash block drifts from the real script — same technique
# as claim-selftest's drift-check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The hook now lives in the plugin's hooks/ dir (out of the skill tree). Locate it
# script-relative; PRE_COMMIT_TYPECHECK overrides. The selftest only SOURCES it for
# needs_typecheck (the sourcing guard returns before the config-aware gate body).
HOOK="${PRE_COMMIT_TYPECHECK:-$SCRIPT_DIR/../../../hooks/pre-commit-typecheck.sh}"
VERIFY="$SCRIPT_DIR/../stages/6-verify.md"
HOOKS_MD="$SCRIPT_DIR/../hooks.md"
ISINERT="$SCRIPT_DIR/is-inert-diff.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
# Load the predicate. Sourcing trips the hook's `BASH_SOURCE[0] != $0` guard, so
# only `needs_typecheck` is defined — the gate body (jq /dev/stdin read, cd, yarn)
# never runs.
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "$HOOK"
if ! declare -f needs_typecheck >/dev/null 2>&1; then
  echo "[self-test] FATAL: sourcing the hook did not define needs_typecheck — the sourcing guard or the function is broken." >&2
  exit 1
fi

# check <desc> <expected-rc> <newline-delimited-staged-paths>
#   expected-rc: 0 = gate (run type-check), 1 = skip
check() {
  local desc="$1" exp="$2" input="$3" rc
  printf '%s' "$input" | needs_typecheck
  rc=$?
  if [ "$rc" -eq "$exp" ]; then
    ok "$desc (rc=$rc)"
  else
    bad "$desc: expected rc=$exp, got rc=$rc"
  fi
}

echo "[self-test] predicate cases (rc 0 = gate, rc 1 = skip)"

# --- SKIP: no JS/TS surface, or every JS/TS-relevant path is inert .claude script ---
check "empty diff -> skip"                       1 ""
check "docs + shell only -> skip"                1 $'README.md\nscripts/run.sh'
check "inert .claude .mjs only -> skip"          1 $'.claude/skills/dev-pipeline/workflows/code-review.mjs'
check "inert .claude .cjs only -> skip"          1 $'.claude/skills/dev-pipeline/workflows/foo.cjs'
check "inert .mjs + docs + shell -> skip"        1 $'.claude/skills/x/workflows/y.mjs\nREADME.md\nrun.sh'
check "two inert .claude scripts -> skip"        1 $'.claude/a/b.mjs\n.claude/c/d.cjs'

# --- GATE: any real source, lockfile, or a .mjs/.cjs OUTSIDE .claude ---
check "apps/api .ts present -> gate"             0 $'apps/api/src/foo.service.ts'
check "apps/web .tsx present -> gate"            0 $'apps/web/components/Foo.tsx'
check "plain .js present -> gate"                0 $'scripts/build.js'
check "package.json present -> gate"             0 $'package.json'
check ".json under .claude present -> gate"      0 $'.claude/settings.json'
check "yarn.lock present -> gate"                0 $'yarn.lock'
check ".mjs OUTSIDE .claude -> gate"             0 $'apps/web/next.config.mjs'
check ".cjs OUTSIDE .claude -> gate"             0 $'tools/jest.config.cjs'

# --- MIXED: inert .claude script + a real source in the same commit -> gate ---
check "inert .mjs + real .ts -> gate"            0 $'.claude/x/workflows/y.mjs\napps/api/src/foo.ts'
check "inert .cjs + package.json -> gate"        0 $'.claude/x/workflows/y.cjs\npackage.json'

# ---------------------------------------------------------------------------
# Parity / drift tail.
# ---------------------------------------------------------------------------
echo "[self-test] lockstep + embedded-copy parity"

# (1) Lockstep: the hook carves out exactly .claude/**/*.(mjs|cjs); is-inert-diff.sh
#     (the single source of truth for the inert set) lists both extensions under .claude.
#     The exact `(mjs|cjs)` literal doubles as the drift guard — change the hook's
#     extension set and this fails until the selftest + is-inert-diff.sh are updated too.
if grep -qF '^\.claude/.*\.(mjs|cjs)$' "$HOOK"; then
  ok "hook carve-out is exactly .claude/**/*.(mjs|cjs)"
else
  bad "hook carve-out pattern '^\\.claude/.*\\.(mjs|cjs)\$' not found in $HOOK (extension set drifted?)"
fi
for ext in mjs cjs; do
  if grep -qF "^\\.claude/.*\\.$ext\$" "$ISINERT"; then
    ok "is-inert-diff.sh inert regex covers .claude/**/*.$ext (lockstep with hook carve-out)"
  else
    bad "is-inert-diff.sh missing inert entry '^\\.claude/.*\\.$ext\$' — hook carve-out and the single-source classifier out of lockstep"
  fi
done

# (1b) Delegation: Stage 6 calls is-inert-diff.sh rather than re-inlining the grep.
#      Guards against a future edit reverting 6-verify.md to an inline classifier,
#      which would silently re-fork the single source of truth.
if grep -qF 'is-inert-diff.sh' "$VERIFY"; then
  ok "6-verify.md delegates the inert-lane decision to is-inert-diff.sh"
else
  bad "6-verify.md no longer calls is-inert-diff.sh — the inert classifier may have been re-inlined (single-source drift)"
fi

# (2) Embedded-copy parity: the fenced bash block under the
#     "### .claude/hooks/pre-commit-typecheck.sh" heading in hooks.md must match the
#     real script verbatim. Extract the block (exclusive of the fence lines) and diff
#     against the file. awk prints each in-block line followed by \n, so the
#     extraction ends with the script's final line + newline — matching the real
#     file's trailing newline. No fence delimiters leak into the comparison.
#     The backtick fence char is passed via -v (bt) so the awk program holds no
#     literal backticks — bash 3.2 mis-parses backticks nested in $(...).
BT="$(printf '\140')"  # backtick, built from octal — no literal backtick in source
EMBED="$(awk -v bt="$BT" '
  $0 ~ "^### .*pre-commit-typecheck\\.sh"  { found = 1 }
  found && $0 == (bt bt bt "bash")         { inblock = 1; next }
  inblock && $0 == (bt bt bt)              { exit }
  inblock                                  { print }
' "$HOOKS_MD")"
if [ -z "$EMBED" ]; then
  bad "could not extract the embedded pre-commit-typecheck.sh block from hooks.md"
elif diff <(printf '%s\n' "$EMBED") "$HOOK" >/dev/null 2>&1; then
  ok "hooks.md embedded copy matches the real hook script verbatim"
else
  bad "hooks.md embedded copy has drifted from $HOOK — regenerate the embedded bash block"
fi

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
