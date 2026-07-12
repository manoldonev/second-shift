#!/usr/bin/env bash
# second-shift-doctor-selftest.sh — hermetic selftest for the consumer thin-check template.
# Contract: presence check against the version-keyed cache; ALWAYS exit 0; silent when
# healthy; silent (not broken) when jq is absent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-doctor.sh"
FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# lockfile (lock-v1 shape) + fake cache tree
mkdir -p "$TMP/repo/.claude"
cat > "$TMP/repo/.claude/second-shift.lock.json" <<'EOF'
{
  "lockfileVersion": 1,
  "marketplace": { "name": "second-shift", "repo": "manoldonev/second-shift", "ref": "v9.9.0" },
  "plugins": { "dev-pipeline": "2.1.0", "audit-toolkit": "2.0.0" },
  "generatedBy": "second-shift:onboard@1.0.0"
}
EOF
CACHE="$TMP/cache"
mkdir -p "$CACHE/dev-pipeline/2.1.0" "$CACHE/audit-toolkit/2.0.0"

echo "second-shift-doctor (thin check) selftest:"

# (a) all cache dirs present → silent, exit 0
out="$(cd "$TMP/repo" && SECOND_SHIFT_CACHE_DIR="$CACHE" bash "$TOOL")"; rc=$?
check "healthy: exit 0"    "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"
check "healthy: no output" "$([[ -z "$out" ]] && echo 0 || echo 1)"

# (b) one missing → nudge names the plugin, still exit 0
rm -rf "$CACHE/dev-pipeline/2.1.0"
out="$(cd "$TMP/repo" && SECOND_SHIFT_CACHE_DIR="$CACHE" bash "$TOOL")"; rc=$?
check "missing: exit stays 0"        "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"
check "missing: nudge text"          "$(grep -q "missing your accelerators" <<< "$out" && echo 0 || echo 1)"
check "missing: names the plugin"    "$(grep -q "dev-pipeline" <<< "$out" && echo 0 || echo 1)"

# (d) "latest" lockfile (canary form): any cached version satisfies the check
mkdir -p "$TMP/repo-latest/.claude" "$CACHE/audit-toolkit/2.0.0"
cat > "$TMP/repo-latest/.claude/second-shift.lock.json" <<'EOF'
{
  "lockfileVersion": 1,
  "marketplace": { "name": "second-shift", "repo": "manoldonev/second-shift", "ref": "main" },
  "plugins": { "dev-pipeline": "latest", "audit-toolkit": "latest" },
  "generatedBy": "second-shift:onboard@1.2.0"
}
EOF
mkdir -p "$CACHE/dev-pipeline/3.4.5"   # ANY version dir counts for "latest"
out="$(cd "$TMP/repo-latest" && SECOND_SHIFT_CACHE_DIR="$CACHE" bash "$TOOL")"; rc=$?
check "latest: exit 0"          "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"
check "latest: silent when any version cached" "$([[ -z "$out" ]] && echo 0 || echo 1)"
rm -rf "$CACHE/dev-pipeline"           # plugin dir gone entirely → nudge fires
out="$(cd "$TMP/repo-latest" && SECOND_SHIFT_CACHE_DIR="$CACHE" bash "$TOOL")"; rc=$?
check "latest: missing plugin dir nudges" "$(grep -q "dev-pipeline" <<< "$out" && echo 0 || echo 1)"
check "latest: still exit 0"    "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"

# (c) no jq on PATH → silent exit 0 (SessionStart must never break a session)
mkdir -p "$TMP/bin"
for b in bash sh dirname basename cat grep; do
  p="$(command -v "$b" 2>/dev/null)" && ln -s "$p" "$TMP/bin/$b" 2>/dev/null || true
done
out="$(cd "$TMP/repo" && SECOND_SHIFT_CACHE_DIR="$CACHE" PATH="$TMP/bin" bash "$TOOL")"; rc=$?
check "no jq: exit 0"    "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"
check "no jq: silent"    "$([[ -z "$out" ]] && echo 0 || echo 1)"

if [[ "$FAILS" -gt 0 ]]; then echo "second-shift-doctor selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "second-shift-doctor selftest: all green"
