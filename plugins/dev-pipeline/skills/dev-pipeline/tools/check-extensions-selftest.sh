#!/usr/bin/env bash
# Selftest for check-extensions.sh: known names pass; a typo'd/unknown file fails closed.
set -euo pipefail
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
: > "$TMP/good/.claude/second-shift/doc-routing.md"
: > "$TMP/good/.claude/second-shift/design-tokens/core-catalog.md"
bash "$CHECK" "$TMP/good" >/dev/null 2>&1 && ok "known extension files -> clean" || bad "known files should pass but failed"

# (2) a typo'd filename -> fail closed with UNKNOWN-EXTENSION
mkdir -p "$TMP/bad/.claude/second-shift"
: > "$TMP/bad/.claude/second-shift/blocker-mutants.md.md"     # typo
if bash "$CHECK" "$TMP/bad" >/tmp/ext-selftest.out 2>&1; then
  bad "typo'd file should FAIL but passed"
else
  grep -q "UNKNOWN-EXTENSION:.*blocker-mutants.md.md" /tmp/ext-selftest.out && ok "typo'd file -> UNKNOWN-EXTENSION fail closed" \
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

if [[ "$FAILS" -gt 0 ]]; then echo "check-extensions selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "check-extensions selftest: all green"
