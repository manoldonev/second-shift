#!/usr/bin/env bash
# Selftest for check-reviewer-references.sh — the two-root reviewer-registry gate.
#
# Runs hermetically from the plugin dir with NO consumer repo: every root is
# supplied via env override (SECOND_SHIFT_PLUGIN_ROOT / SECOND_SHIFT_REPO_ROOT /
# SECOND_SHIFT_CONFIG) pointing at static fixtures under scripts/fixtures/ (plus a
# mktemp'd empty consumer for the config-absent case). No git repo is required.
#
# Cases (failure-class → fixture):
#   all-green            plugin + consumer-green (reviewers.add resolves)        -> exit 0
#   config-absent        plugin + empty mktemp consumer, no config              -> exit 0
#   (a) DANGLING         plugin-dangling (registry entry, no agent file)        -> exit 1
#   (b) ORPHAN           plugin + consumer-orphan (reviewer file, not in config)-> exit 1
#   (c) REMOVE-UNKNOWN   plugin + consumer-remove-unknown (removes a non-plugin)-> exit 1
#   (d) SHADOW           plugin + consumer-shadow (shadows plugin agent name)   -> exit 1
#   add+override         plugin + consumer-add-override (add + modelOverride)   -> exit 0
#
# Convention mirrors check-model-tiers-selftest.sh: ok()/fail() counters, temp dirs
# cleaned via trap. Bash 3.2 compatible (macOS).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-reviewer-references.sh"
FX="$SCRIPT_DIR/fixtures/reviewer-references"
PLUGIN="$FX/plugin"
PLUGIN_DANGLING="$FX/plugin-dangling"
[ -x "$CHECK" ] || { echo "FAIL: $CHECK not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not available"; exit 1; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT

# Run the gate in CLI mode against explicit roots. Prints exit code; captures
# stderr into $TMP/.stderr. Args: <plugin_root> <repo_root> [config_path]
run_cli() {
  local plugin="$1" repo="$2" config="${3:-}"
  (
    export SECOND_SHIFT_PLUGIN_ROOT="$plugin"
    export SECOND_SHIFT_REPO_ROOT="$repo"
    [ -n "$config" ] && export SECOND_SHIFT_CONFIG="$config"
    bash "$CHECK" </dev/null 2>"$TMP/.stderr"
  )
}

echo "check-reviewer-references selftest"

# all-green — reviewers.add resolves to a consumer agent file
run_cli "$PLUGIN" "$FX/consumer-green" "$FX/consumer-green/.claude/second-shift.config.json"
[ $? -eq 0 ] && ok "all-green: add resolves -> exit 0" || fail "all-green expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# config-absent — empty consumer, no config => empty deltas, plugin registry backed
EMPTY_CONSUMER="$TMP/empty-consumer"; mkdir -p "$EMPTY_CONSUMER"
run_cli "$PLUGIN" "$EMPTY_CONSUMER"
[ $? -eq 0 ] && ok "config-absent: empty deltas -> exit 0" || fail "config-absent expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# (a) DANGLING — plugin registry lists db-reviewer with no agent file in either root
run_cli "$PLUGIN_DANGLING" "$EMPTY_CONSUMER"
if [ $? -eq 0 ]; then fail "(a) dangling expected exit 1"; else
  grep -q "DANGLING:.*db-reviewer" "$TMP/.stderr" && ok "(a) DANGLING: registry entry, no agent file -> exit 1 + message" \
    || fail "(a) dangling: exit 1 but no DANGLING db-reviewer line (stderr: $(cat "$TMP/.stderr"))"
fi

# (b) ORPHAN — consumer orders-reviewer.md registered nowhere (no config)
run_cli "$PLUGIN" "$FX/consumer-orphan"
if [ $? -eq 0 ]; then fail "(b) orphan expected exit 1"; else
  grep -q "ORPHAN:.*orders-reviewer" "$TMP/.stderr" && ok "(b) ORPHAN: unregistered consumer reviewer -> exit 1 + message" \
    || fail "(b) orphan: exit 1 but no ORPHAN line (stderr: $(cat "$TMP/.stderr"))"
fi

# (c) REMOVE-UNKNOWN — reviewers.remove names db-reviewer, not in plugin registry
run_cli "$PLUGIN" "$FX/consumer-remove-unknown" "$FX/consumer-remove-unknown/.claude/second-shift.config.json"
if [ $? -eq 0 ]; then fail "(c) remove-unknown expected exit 1"; else
  grep -q "REMOVE-UNKNOWN:.*db-reviewer" "$TMP/.stderr" && ok "(c) REMOVE-UNKNOWN: stale remove delta -> exit 1 + message" \
    || fail "(c) remove-unknown: exit 1 but no REMOVE-UNKNOWN line (stderr: $(cat "$TMP/.stderr"))"
fi

# (d) SHADOW — consumer security-reviewer.md shadows the plugin-shipped agent name
run_cli "$PLUGIN" "$FX/consumer-shadow"
if [ $? -eq 0 ]; then fail "(d) shadow expected exit 1"; else
  grep -q "SHADOW:.*security-reviewer" "$TMP/.stderr" && ok "(d) SHADOW: consumer shadows plugin agent -> exit 1 + message" \
    || fail "(d) shadow: exit 1 but no SHADOW line (stderr: $(cat "$TMP/.stderr"))"
fi

# add+override — reviewers.add plus a modelOverride (ignored here) stays green
run_cli "$PLUGIN" "$FX/consumer-add-override" "$FX/consumer-add-override/.claude/second-shift.config.json"
[ $? -eq 0 ] && ok "add+override: add resolves, modelOverride ignored -> exit 0" \
  || fail "add+override expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# shipped-SKILL lockstep — the REAL plugin root must parse clean against an empty
# consumer. Fixtures alone cannot catch a rewording of the shipped SKILL.md that
# breaks the parser's anchor phrases (that exact drift shipped in 0.1.0: the
# extraction reworded the pre-flight enumeration to "the plugin-shipped panel (…)"
# while the parser still keyed on "specialist reviewer subagent types (…)",
# producing a guaranteed DRIFT deny on every consumer commit).
REAL_PLUGIN="$SCRIPT_DIR/.."
run_cli "$REAL_PLUGIN" "$EMPTY_CONSUMER"
[ $? -eq 0 ] && ok "shipped-SKILL lockstep: real plugin root parses clean -> exit 0" \
  || fail "shipped-SKILL lockstep expected exit 0 — parser anchors out of lockstep with the shipped SKILL.md (stderr: $(cat "$TMP/.stderr"))"

echo
echo "[check-reviewer-references-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
