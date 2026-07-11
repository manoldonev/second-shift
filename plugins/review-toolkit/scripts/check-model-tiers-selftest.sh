#!/usr/bin/env bash
# Selftest for check-model-tiers.sh — the two-root, config-aware model-tier gate.
#
# Runs hermetically from the plugin dir with NO consumer repo: the dev-pipeline
# .mjs tables, plugin agent frontmatter, consumer config, and consumer agents are
# all supplied via env overrides (SECOND_SHIFT_DEV_PIPELINE_ROOT /
# SECOND_SHIFT_PLUGIN_ROOT / SECOND_SHIFT_REPO_ROOT / SECOND_SHIFT_CONFIG) pointing
# at static fixtures under scripts/fixtures/ (plus mktemp'd config + mutated-table
# copies). No git repo is required.
#
# Cases:
#   agreement            table == frontmatter                          -> exit 0
#   frontmatter mismatch table 'sonnet' vs frontmatter 'opus'          -> exit 1 + MISMATCH
#   override reconciles  mismatched table, modelOverride matches table -> exit 0
#   override differs     table == frontmatter default, modelOverride
#                        'sonnet' — per-repo tiering; override wins at
#                        dispatch, table keeps the plugin default       -> exit 0
#   override three-way   table matches neither modelOverride nor
#                        frontmatter                                    -> exit 1 + MISMATCH
#   qualified name       table key 'review-toolkit:security-reviewer'  -> exit 0
#
# Convention mirrors check-reviewer-references-selftest.sh. Bash 3.2 compatible.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-model-tiers.sh"
FX="$SCRIPT_DIR/fixtures/model-tiers"
DP="$FX/dev-pipeline"        # clean dev-pipeline root (tables in lockstep)
PLUGIN="$FX/plugin"          # plugin agent frontmatter (source of truth)
[ -x "$CHECK" ] || { echo "FAIL: $CHECK not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not available"; exit 1; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT

# Consumer root is only needed when a config is supplied; a mktemp empty dir does.
EMPTY_CONSUMER="$TMP/empty-consumer"; mkdir -p "$EMPTY_CONSUMER"

# CLI run against explicit roots. stderr -> $TMP/.stderr.
# Args: <dev_pipeline_root> [config_path]
# shellcheck disable=SC2030 # exports are deliberately subshell-scoped per case
run_cli() {
  local dproot="$1" config="${2:-}"
  (
    export SECOND_SHIFT_DEV_PIPELINE_ROOT="$dproot"
    export SECOND_SHIFT_PLUGIN_ROOT="$PLUGIN"
    export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
    [ -n "$config" ] && export SECOND_SHIFT_CONFIG="$config"
    bash "$CHECK" </dev/null 2>"$TMP/.stderr"
  )
}

# Copy the clean dev-pipeline root, then rewrite code-review.mjs's REVIEWER_MODEL.
# Args: <dest_name> <security-reviewer-key> <security-reviewer-model>
make_dp_variant() {
  local key="$2" model="$3" dst="$TMP/$1"
  cp -R "$DP" "$dst"
  cat > "$dst/skills/run/workflows/code-review.mjs" <<MJS
const REVIEWER_MODEL = {
  '$key': '$model',
  'performance-reviewer': 'sonnet',
}
MJS
  printf '%s' "$dst"
}

# Write a config carrying a single reviewers.modelOverrides entry.
# Args: <agent> <model> -> prints the config path
make_override_config() {
  local agent="$1" model="$2" path="$TMP/override-$1-$2.json"
  cat > "$path" <<JSON
{
  "configVersion": 1,
  "tracker": { "type": "github" },
  "topology": { "type": "standalone", "repos": { "app": { "path": ".", "baseBranch": "main" } } },
  "commands": { "app": {} },
  "reviewers": { "modelOverrides": { "$agent": "$model" } }
}
JSON
  printf '%s' "$path"
}

echo "check-model-tiers selftest"

# agreement — clean tables match frontmatter
run_cli "$DP"
[ $? -eq 0 ] && ok "agreement: table == frontmatter -> exit 0" || fail "agreement expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# frontmatter mismatch — code-review says 'sonnet' for security-reviewer (frontmatter opus)
DRIFT=$(make_dp_variant driftmap "security-reviewer" "sonnet")
run_cli "$DRIFT"
if [ $? -eq 0 ]; then fail "frontmatter mismatch expected exit 1"; else
  grep -q "MISMATCH: 'security-reviewer'" "$TMP/.stderr" && ok "frontmatter mismatch -> exit 1 + MISMATCH names agent" \
    || fail "frontmatter mismatch: exit 1 but no MISMATCH line (stderr: $(cat "$TMP/.stderr"))"
fi

# override reconciles — same drifted table, but modelOverride forces 'sonnet' to match
CFG_RECONCILE=$(make_override_config "security-reviewer" "sonnet")
run_cli "$DRIFT" "$CFG_RECONCILE"
[ $? -eq 0 ] && ok "override reconciles: modelOverride matches table -> exit 0" \
  || fail "override reconciles expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# override differs — clean table ('opus' == frontmatter default), modelOverride says
# 'sonnet'. This is the per-repo tiering feature (same plugin-shipped table + agent,
# a different tier per consumer): the table keeps the plugin default and the .mjs
# applies the override at dispatch (modelOverrides[...] || TABLE[...]). Legal.
CFG_DIFFERS=$(make_override_config "security-reviewer" "sonnet")
run_cli "$DP" "$CFG_DIFFERS"
[ $? -eq 0 ] && ok "override differs: table keeps plugin default, override wins at dispatch -> exit 0" \
  || fail "override differs expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# override three-way mismatch — drifted table ('sonnet'), frontmatter 'opus',
# modelOverride 'haiku': the table matches neither the override nor the
# frontmatter default -> genuine drift, mismatch.
CFG_THREEWAY=$(make_override_config "security-reviewer" "haiku")
run_cli "$DRIFT" "$CFG_THREEWAY"
if [ $? -eq 0 ]; then fail "override three-way expected exit 1"; else
  grep -q "MISMATCH: 'security-reviewer'" "$TMP/.stderr" && ok "override three-way: table matches neither override nor frontmatter -> exit 1 + MISMATCH" \
    || fail "override three-way: exit 1 but no MISMATCH line (stderr: $(cat "$TMP/.stderr"))"
fi

# qualified name — table key is plugin:-qualified; compared on the bare name
QUAL=$(make_dp_variant qualmap "review-toolkit:security-reviewer" "opus")
run_cli "$QUAL"
[ $? -eq 0 ] && ok "qualified name: 'review-toolkit:security-reviewer' parsed bare -> exit 0" \
  || fail "qualified name expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# cache layout — installed marketplace cache is cache/<mkt>/<plugin>/<version>/;
# the dev-pipeline root must resolve via the versioned-sibling fallback with NO
# SECOND_SHIFT_DEV_PIPELINE_ROOT override (0.1.0 shipped resolving only the
# marketplace-repo sibling path and UNLOCATABLE-denied every consumer commit).
CACHE_MKT="$TMP/cache/mkt"
mkdir -p "$CACHE_MKT/review-toolkit/0.0.1/scripts" "$CACHE_MKT/dev-pipeline/0.0.1"
cp "$CHECK" "$CACHE_MKT/review-toolkit/0.0.1/scripts/check-model-tiers.sh"
cp -R "$DP/skills" "$CACHE_MKT/dev-pipeline/0.0.1/skills"
# shellcheck disable=SC2030,SC2031 # exports are deliberately subshell-scoped per case
(
  export SECOND_SHIFT_PLUGIN_ROOT="$PLUGIN"
  export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
  bash "$CACHE_MKT/review-toolkit/0.0.1/scripts/check-model-tiers.sh" </dev/null 2>"$TMP/.stderr"
)
[ $? -eq 0 ] && ok "cache layout: versioned-sibling dev-pipeline root resolves -> exit 0" \
  || fail "cache layout expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

echo
echo "[check-model-tiers-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
