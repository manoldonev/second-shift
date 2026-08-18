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
#   cache layout         versioned-sibling dev-pipeline root resolves   -> exit 0
#
# UNKNOWN-MODEL cases (the silent-skip hole). Each is written so the PRE-FIX script
# exits 0 on the same fixture — the hole was invisible, so a case whose fixture already
# failed for another reason would demonstrate nothing:
#   fable override       'fable' in modelOverrides, clean table         -> exit 0
#                        (override values are never enum-checked — the feature)
#   fable in MAP         'fable' as a shipped REVIEWER_MODEL value      -> exit 1 + UNKNOWN-MODEL
#   unknown in MAP       'gpt-4' as a shipped REVIEWER_MODEL value      -> exit 1 + UNKNOWN-MODEL
#   unknown inline/MAP   map file, inline 'gpt-4' on an agentType line  -> exit 1 + UNKNOWN-MODEL
#
# MAP-file inline literal MISMATCH case (#247 — the in-enum counterpart to the
# unknown-inline/MAP case above; both fixtures are written so the PRE-FIX script
# exits 0, since this class was invisible rather than merely wrong):
#   map inline mismatch  map file, inline 'opus' vs structured-emitter's 'haiku'
#                        frontmatter, otherwise-clean table              -> exit 1 + MISMATCH
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
  cat > "$dst/workflows/code-review.mjs" <<MJS
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
  "configVersion": 2,
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

# --- scalar-table files: RETIRED (#574) ----------------------------------------
# The inline-honored / inline-drift pair and the unknown-inline-scalar case drove the
# scalar loop (`const UNIT_TEST_MODEL = ...` in unit-tests.mjs); the loop left with its
# last carrier, and a case exercising a loop that no longer iterates would pass for
# the wrong reason. The MAP-file inline cases below carry the same three properties
# (honored-over-nothing, in-enum lockstep, out-of-enum guard) on the surviving loop.

# --- UNKNOWN-MODEL: model tokens outside opus|sonnet|haiku --------------------
# The pre-fix script baked the enum into its EXTRACTION regexes, so an unknown token
# was not "wrong", it was invisible: the MAP grep never matched the entry, and the
# inline grep's miss fell through to the file's scalar. Every case below is built so
# the PRE-FIX script exits 0 — revert the guard and each of these goes green, which
# is what makes them a real red-on-mutation demo rather than a restatement.

# (a) override — 'fable' is a legal reviewers.modelOverrides VALUE. Overrides are never
# enum-checked (check_pair's override branch treats them as opaque strings), and the
# table here is clean, so this must pass both before and after the guard. This is the
# feature the guard must not break: per-repo tiering stays expressible while shipped
# code stays tri-value.
CFG_FABLE=$(make_override_config "security-reviewer" "fable")
run_cli "$DP" "$CFG_FABLE"
[ $? -eq 0 ] && ok "fable override: legal modelOverrides value, clean table -> exit 0" \
  || fail "fable override expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# (b) 'fable' in a SHIPPED map entry — the mechanical half of the override-only posture.
# Legal in config (case a), an error in a plugin-shipped table.
FABLE_MAP=$(make_dp_variant fablemap "security-reviewer" "fable")
run_cli "$FABLE_MAP"
if [ $? -eq 0 ]; then fail "fable in a shipped MAP entry expected exit 1"; else
  grep -q "UNKNOWN-MODEL: code-review.mjs declares 'security-reviewer' => 'fable'" "$TMP/.stderr" \
    && ok "fable in a shipped MAP entry -> exit 1 + UNKNOWN-MODEL" \
    || fail "fable map: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# (c) an arbitrary out-of-enum token in a shipped map entry. Same path as (b); pinned
# separately because 'fable' is a token we now recognize elsewhere and 'gpt-4' is not,
# so this proves the guard keys on the tier set rather than on a fable special case.
UNKNOWN_MAP=$(make_dp_variant unknownmap "security-reviewer" "gpt-4")
run_cli "$UNKNOWN_MAP"
if [ $? -eq 0 ]; then fail "unknown token in a shipped MAP entry expected exit 1"; else
  grep -q "UNKNOWN-MODEL: code-review.mjs declares 'security-reviewer' => 'gpt-4'" "$TMP/.stderr" \
    && ok "unknown token in a shipped MAP entry -> exit 1 + UNKNOWN-MODEL" \
    || fail "unknown map: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# (e) out-of-enum INLINE literal in a MAP file. The MAP grep cannot see an inline
# dispatch at all (`model:` is an unquoted key), so without this case the guard could
# ship covering only the map entries and every other case would still pass.
# Args: <dest_name> <inline-model> -> prints the root path
make_dp_map_inline_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$DP" "$dst"
  cat > "$dst/workflows/code-review.mjs" <<MJS
const REVIEWER_MODEL = {
  'security-reviewer': 'opus',
}
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
MJS
  printf '%s' "$dst"
}

MAP_INLINE_UNKNOWN=$(make_dp_map_inline_variant map-inline-unknown "gpt-4")
run_cli "$MAP_INLINE_UNKNOWN"
if [ $? -eq 0 ]; then fail "unknown inline literal (MAP file) expected exit 1"; else
  grep -q "UNKNOWN-MODEL: code-review.mjs dispatches 'review-toolkit:structured-emitter' with inline model 'gpt-4'" "$TMP/.stderr" \
    && ok "unknown inline literal in a MAP file -> exit 1 + UNKNOWN-MODEL" \
    || fail "map inline unknown: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# --- MAP-file inline literal MISMATCH (in-enum drift) --------------------------
# The gap #247 closes: an IN-ENUM inline literal in a MAP file used to reach neither
# loop's lockstep check (the MAP grep can't see it; the scalar loop's inline handling
# never iterates the MAP files) — only OUT-OF-ENUM tokens were caught, by
# scan_unknown_inline_literals. This fixture uses 'opus', a KNOWN tier, against
# structured-emitter's 'haiku' frontmatter, with an otherwise-clean map entry, so
# UNKNOWN-MODEL cannot fire and the pre-fix script is genuinely silent (exit 0) —
# reverting the guard turns this case green again.
# Args: <dest_name> <inline-model> -> prints the root path
make_dp_map_inline_mismatch_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$DP" "$dst"
  cat > "$dst/workflows/code-review.mjs" <<MJS
const REVIEWER_MODEL = {
  'security-reviewer': 'opus',
}
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
MJS
  printf '%s' "$dst"
}

MAP_INLINE_MISMATCH=$(make_dp_map_inline_mismatch_variant map-inline-mismatch "opus")
run_cli "$MAP_INLINE_MISMATCH"
if [ $? -eq 0 ]; then fail "MAP-file inline literal mismatch expected exit 1"; else
  grep -q "MISMATCH: 'structured-emitter'" "$TMP/.stderr" \
    && ok "MAP-file inline literal locksteped against frontmatter -> exit 1 + MISMATCH" \
    || fail "map inline mismatch: exit 1 but no MISMATCH for structured-emitter (stderr: $(cat "$TMP/.stderr"))"
fi

# cache layout — installed marketplace cache is cache/<mkt>/<plugin>/<version>/;
# the dev-pipeline root must resolve via the versioned-sibling fallback with NO
# SECOND_SHIFT_DEV_PIPELINE_ROOT override (0.1.0 shipped resolving only the
# marketplace-repo sibling path and UNLOCATABLE-denied every consumer commit).
#
# TWO sibling versions, 0.0.9 and 0.0.10, so this also pins NUMERIC ordering. Both carry the
# marker dir (workflows) and so are both candidates; only 0.0.10 carries the real
# workflows. Glob order is lexical and sorts 0.0.10 BEFORE 0.0.9, so a last-wins pick resolves
# the empty 0.0.9 and the run fails to find what it needs. Staging a single version — which is
# what this case did — asserts that the fallback resolves SOMETHING, never that it resolves the
# newest, so it could not tell the two orderings apart.
CACHE_MKT="$TMP/cache/mkt"
mkdir -p "$CACHE_MKT/review-toolkit/0.0.1/scripts" "$CACHE_MKT/dev-pipeline/0.0.10" \
         "$CACHE_MKT/dev-pipeline/0.0.9/workflows"
cp "$CHECK" "$CACHE_MKT/review-toolkit/0.0.1/scripts/check-model-tiers.sh"
cp -R "$DP/workflows" "$CACHE_MKT/dev-pipeline/0.0.10/workflows"
cp "$DP/model-tiering.md" "$CACHE_MKT/dev-pipeline/0.0.10/model-tiering.md"
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
