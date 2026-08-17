#!/usr/bin/env bash
# Selftest for check-extensions.sh: known names pass; a typo'd/unknown file fails closed.
set -euo pipefail
# Hermetic hygiene: a verify run exports pipeline seam vars (SECOND_SHIFT_EXTENSION_MANIFEST,
# BRANCH_PREFIX, …) into the test command, and the tools under test honor them as overrides —
# which would clobber this selftest's own fixtures. Unset them so the selftest controls its
# environment regardless of the caller (#34). SECOND_SHIFT_CONFIG left in the list on purpose:
# #569 removed the override from check-extensions.sh, and unsetting a var the tool no longer
# reads is free, whereas leaving it out would make a re-introduced override invisible here.
unset SECOND_SHIFT_CONFIG SECOND_SHIFT_REPO_ROOT SECOND_SHIFT_EXTENSION_MANIFEST BRANCH_PREFIX
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-extensions.sh"
FAILS=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# (1) a repo with only known extension files -> clean
mkdir -p "$TMP/good/.claude/second-shift/design-tokens"
: > "$TMP/good/.claude/second-shift/blocker-mutants.md"
: > "$TMP/good/.claude/second-shift/security-rules.md"
: > "$TMP/good/.claude/second-shift/review-context.md"
mkdir -p "$TMP/good/.claude/second-shift/review-context"
: > "$TMP/good/.claude/second-shift/review-context/db-reviewer.md"
: > "$TMP/good/.claude/second-shift/doc-routing.md"
: > "$TMP/good/.claude/second-shift/design-tokens/core-catalog.md"
bash "$CHECK" "$TMP/good" >/dev/null 2>&1 && ok "known extension files -> clean" || bad "known files should pass but failed"

# (2) a typo'd filename -> fail closed with UNKNOWN-EXTENSION
mkdir -p "$TMP/bad/.claude/second-shift"
: > "$TMP/bad/.claude/second-shift/blocker-mutants.md.md"     # typo
if bash "$CHECK" "$TMP/bad" >"$TMP/ext-selftest.out" 2>&1; then
  bad "typo'd file should FAIL but passed"
else
  grep -q "UNKNOWN-EXTENSION:.*blocker-mutants.md.md" "$TMP/ext-selftest.out" && ok "typo'd file -> UNKNOWN-EXTENSION fail closed" \
    || bad "typo failed but without the expected message"
fi

# (3) no .claude/second-shift/ -> clean (nothing to check)
mkdir -p "$TMP/empty"
bash "$CHECK" "$TMP/empty" >/dev/null 2>&1 && ok "no extension dir -> clean" || bad "empty repo should pass"

# (4) a companion-pack/repo-local file declared in .known-extensions -> allowed
mkdir -p "$TMP/pack/.claude/second-shift/api-testing"
: > "$TMP/pack/.claude/second-shift/review-context.md"
: > "$TMP/pack/.claude/second-shift/api-testing/harness.md"
printf 'api-testing/*.md\n' > "$TMP/pack/.claude/second-shift/.known-extensions"
bash "$CHECK" "$TMP/pack" >/dev/null 2>&1 && ok ".known-extensions allowlist -> companion-pack file allowed" \
  || bad "declared companion-pack file should pass but failed"

# (5) same file WITHOUT the allowlist -> fail closed
rm "$TMP/pack/.claude/second-shift/.known-extensions"
bash "$CHECK" "$TMP/pack" >/dev/null 2>&1 && bad "undeclared companion-pack file should FAIL" \
  || ok "undeclared companion-pack file -> fail closed"

# (6) #569 retired EP-6/EP-7/EP-8, and with them this script's whole config-reading arm. The
# three cases that used to live here asserted the OPPOSITE — that an unresolvable
# stageWorkflows/implementDelegates/planGates reference fails closed — so deleting them would
# leave the removal itself unguarded, and a re-introduced arm would read as green.
#
# What is asserted instead is the removal's consumer-visible consequence: a config carrying a
# reference that CANNOT resolve (a workflow path that does not exist, a bare agent with no
# .claude/agents/ file) is no longer this script's business. That was the second of the three
# arguments for retiring the keys — the arm could only block a pre-flight on behalf of a
# dispatcher that no longer existed, never protect one. config-lint now rejects the keys by
# name, which is where a consumer gets told.
mkdir -p "$TMP/refs/.claude/agents"
cat > "$TMP/refs/.claude/second-shift.config.json" <<'JSON'
{ "stageWorkflows": [ { "stage": 6, "name": "v", "workflow": "scripts/does-not-exist.mjs" } ],
  "implementDelegates": [ { "surface": "unit", "agent": "ghost-reviewer" } ],
  "planGates": [ { "name": "p", "surface": "tests/api/**", "agent": "ghost-plan-reviewer" } ] }
JSON
if bash "$CHECK" "$TMP/refs" >"$TMP/ext-ref.out" 2>&1; then
  ok "retired EP-6/7/8 references are no longer resolved here (#569)"
else
  bad "unresolvable retired-key references should be IGNORED now (got: $(head -3 "$TMP/ext-ref.out" | tr '\n' ' '))"
fi
# ...and the reason that is not merely "it passes": the messages must be gone, not just
# non-fatal. A downgraded-to-warning arm would still pass the case above.
if grep -qE "UNRESOLVED-WORKFLOW|UNRESOLVED-AGENT" "$TMP/ext-ref.out"; then
  bad "the retired reference-resolution arm still emits UNRESOLVED-* diagnostics"
else
  ok "no UNRESOLVED-* diagnostic survives the arm removal"
fi
# The EP-3 arm must still fail closed with a config present — proof the deletion took the
# config arm and not the manifest lint, which shares this script and is NOT retired.
mkdir -p "$TMP/refs/.claude/second-shift"
: > "$TMP/refs/.claude/second-shift/blocker-mutants.md.md"
if bash "$CHECK" "$TMP/refs" >"$TMP/ext-ref2.out" 2>&1; then
  bad "EP-3 manifest lint should still fail closed alongside a config"
else
  grep -q "UNKNOWN-EXTENSION" "$TMP/ext-ref2.out" && ok "EP-3 manifest lint survives the arm removal" \
    || bad "EP-3 failed but without UNKNOWN-EXTENSION"
fi

if [[ "$FAILS" -gt 0 ]]; then echo "check-extensions selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-extensions selftest: all green"
