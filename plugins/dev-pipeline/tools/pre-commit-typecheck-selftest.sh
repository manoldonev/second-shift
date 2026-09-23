#!/usr/bin/env bash
#
# Self-test for the pre-commit type-check hook (hooks/pre-commit-typecheck.sh): its
# inert carve-out, and the commands-key resolution the executed gate body does.
#
# A self-test in the style of claim-selftest.sh:
# pure-local, no Claude CLI, no network, no yarn. It SOURCES the hook to obtain its
# `needs_typecheck` predicate (the hook's sourcing guard returns before the gate
# body, so no /dev/stdin read or `yarn type-check` runs) and drives it with
# synthetic staged-path lists, asserting gate (rc 0) vs skip (rc 1) for each.
#
# WHY this exists (#228): the hook gated every staged .mjs/.cjs unconditionally,
# but .claude/**/*.{mjs,cjs} Workflow scripts have zero tsconfig/eslint/jest
# coverage. The hook carves them out. This test locks the predicate AND:
#   - the hook's .claude carve-out is exactly .claude/**/*.(mjs|cjs),
#   - the embedded copy of the script in hooks.md matches the real script verbatim.
#
# DRIFT MODEL: the parity tail fails if the hook's carve-out extension set changes, or
# if hooks.md's embedded ```bash block drifts from the real script — same technique as
# claim-selftest's drift-check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The hook now lives in the plugin's hooks/ dir (out of the skill tree). Locate it
# script-relative; PRE_COMMIT_TYPECHECK overrides. The selftest only SOURCES it for
# needs_typecheck (the sourcing guard returns before the config-aware gate body).
HOOK="${PRE_COMMIT_TYPECHECK:-$SCRIPT_DIR/../hooks/pre-commit-typecheck.sh}"
HOOKS_MD="$SCRIPT_DIR/../hooks.md"

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
check "inert .claude .mjs only -> skip"          1 $'.claude/workflows/code-review.mjs'
check "inert .claude .cjs only -> skip"          1 $'.claude/workflows/foo.cjs'
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

# --- Gate body: the commands key is resolved from the MAIN checkout's directory name,
#     whatever the hook's cwd. Two keys, so only the directory-name rule can pick one.
echo "[self-test] commands-key resolution (hook executed, two-key config)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MAIN="$TMP/myapp"
mkdir -p "$MAIN/sub" "$MAIN/.claude"
git -C "$MAIN" init -q
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '%s' '{"commands":{"myapp":{"typecheck":"echo TYPECHECK-RAN; exit 1"},"other":{}}}' > "$MAIN/.claude/second-shift.config.json"
: > "$MAIN/sub/a.ts"; git -C "$MAIN" add sub/a.ts
git -C "$MAIN" worktree add -q "$TMP/wt" -b wt 2>/dev/null
mkdir -p "$TMP/wt/.claude" "$TMP/wt/sub"
cp "$MAIN/.claude/second-shift.config.json" "$TMP/wt/.claude/"
: > "$TMP/wt/sub/a.ts"; git -C "$TMP/wt" add sub/a.ts
run_hook() { jq -n --arg c "$2" '{cwd:$c}' | env -u SECOND_SHIFT_CONFIG bash "$HOOK" 2>/dev/null | grep -q '"permissionDecision": "deny"' && ok "$1 -> deny" || bad "$1: typecheck did not run or did not deny"; }
run_hook "main checkout root cwd"      "$MAIN"
run_hook "main checkout subdirectory"  "$MAIN/sub"
run_hook "linked worktree subdirectory" "$TMP/wt/sub"

# Parity / drift tail.
echo "[self-test] carve-out + embedded-copy parity"

# (1) The hook carves out exactly .claude/**/*.(mjs|cjs). The exact `(mjs|cjs)` literal
#     doubles as the drift guard — change the hook's extension set and this fails until
#     the selftest is updated too.
if grep -qF '^\.claude/.*\.(mjs|cjs)$' "$HOOK"; then
  ok "hook carve-out is exactly .claude/**/*.(mjs|cjs)"
else
  bad "hook carve-out pattern '^\\.claude/.*\\.(mjs|cjs)\$' not found in $HOOK (extension set drifted?)"
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
