#!/usr/bin/env bash
# second-shift-ci-check-selftest.sh — hermetic selftest for the consumer CI evidence gate.
# Contract: exit = number of FAILED checks; ref lockstep drift and a real config-lint
# violation are FAILs; "couldn't verify" (fetch/tool failure) is a non-fatal WARN. The
# config-lint fetch is stubbed via SECOND_SHIFT_CONFIG_LINT so no case touches the network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/second-shift-ci-check.sh"
YML="$HERE/second-shift-ci.yml"
FAILS=0
check() { if [ "$2" -eq 0 ]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# stub config-lint: SECOND_SHIFT_CONFIG_LINT points here; its exit code is controlled
# by the STUB_RC env var so one stub covers both the pass and violation cases.
STUB="$TMP/config-lint-stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_RC:-0}"
EOF
chmod +x "$STUB"

# Build a consumer repo fixture. $1 = settings ref, $2 = lockfile ref, $3 = lockfile repo.
make_repo() {
  local dir="$1" set_ref="$2" lock_ref="$3" lock_repo="$4"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/settings.json" <<EOF
{ "extraKnownMarketplaces": { "second-shift": { "source": { "source": "github", "repo": "$lock_repo", "ref": "$set_ref" } } } }
EOF
  cat > "$dir/.claude/second-shift.lock.json" <<EOF
{ "lockfileVersion": 1, "marketplace": { "name": "second-shift", "repo": "$lock_repo", "ref": "$lock_ref" }, "plugins": { "dev-pipeline": "2.2.4" }, "generatedBy": "second-shift:onboard@1.5.0" }
EOF
  cat > "$dir/.claude/second-shift.config.json" <<'EOF'
{ "configVersion": 1, "tracker": { "type": "github" }, "topology": { "type": "standalone", "repos": { "r": { "path": ".", "baseBranch": "main" } } }, "commands": { "r": {} } }
EOF
}

echo "second-shift-ci-check selftest:"

# (1) matched refs + stub lint exits 0 → all OK, exit 0
make_repo "$TMP/ok" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/ok" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "matched refs + lint ok: exit 0"                 "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "matched refs: reports ref lockstep OK"          "$(grep -q "settings ref == lockfile ref" <<<"$out" && echo 0 || echo 1)"
check "matched refs: reports config-lint passed"       "$(grep -q "config-lint passed" <<<"$out" && echo 0 || echo 1)"

# (2 · AC-3) drifted refs → FAIL, "disagree", exit >=1
make_repo "$TMP/drift" "v9.8.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/drift" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "drifted refs: exit >=1 (AC-3)"                  "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "drifted refs: FAIL names the disagreement (AC-3)" "$(grep -q "disagree" <<<"$out" && grep -q "FAIL" <<<"$out" && echo 0 || echo 1)"

# (3 · AC-2) config-lint violation → FAIL, exit >=1
make_repo "$TMP/lintfail" "v9.9.0" "v9.9.0" "manoldonev/second-shift"
out="$(cd "$TMP/lintfail" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=1 bash "$TOOL")"; rc=$?
check "config-lint violation: exit >=1 (AC-2)"         "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"
check "config-lint violation: FAIL names it (AC-2)"    "$(grep -q "config-lint reported violations" <<<"$out" && echo 0 || echo 1)"

# (4) canary form (ref: main) matched → exit 0
make_repo "$TMP/canary" "main" "main" "manoldonev/second-shift"
out="$(cd "$TMP/canary" && SECOND_SHIFT_CONFIG_LINT="$STUB" STUB_RC=0 bash "$TOOL")"; rc=$?
check "canary ref main matched: exit 0"                "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# (5) couldn't-verify is a WARN, not a FAIL: matched refs, no config-lint seam, empty
#     lockfile repo forces the fetch to be skipped with a WARN (no network) → exit 0.
make_repo "$TMP/warn" "v9.9.0" "v9.9.0" ""
out="$(cd "$TMP/warn" && unset SECOND_SHIFT_CONFIG_LINT; bash "$TOOL")"; rc=$?
check "fetch un-verifiable: exit stays 0 (WARN not FAIL)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "fetch un-verifiable: emits a WARN line"         "$(grep -q "WARN" <<<"$out" && grep -q "could not verify" <<<"$out" && echo 0 || echo 1)"

# (6) missing lockfile → FAIL, exit >=1
mkdir -p "$TMP/nolock/.claude"
out="$(cd "$TMP/nolock" && bash "$TOOL")"; rc=$?
check "no lockfile: exit >=1"                          "$([ "$rc" -ge 1 ] && echo 0 || echo 1)"

# (7) the emitted workflow YAML wires the check correctly
check "yml: triggers on pull_request"                  "$(grep -q "pull_request" "$YML" && echo 0 || echo 1)"
check "yml: runs the check script"                     "$(grep -q "second-shift-ci-check.sh" "$YML" && echo 0 || echo 1)"
check "yml: passes github.token as GH_TOKEN"           "$(grep -q "GH_TOKEN" "$YML" && grep -q "github.token" "$YML" && echo 0 || echo 1)"

if [ "$FAILS" -gt 0 ]; then echo "second-shift-ci-check selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "second-shift-ci-check selftest: all green"
