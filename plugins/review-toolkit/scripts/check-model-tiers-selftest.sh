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
#   inline honored       scalar file, inline 'haiku' over 'sonnet'      -> exit 0
#   inline drift         scalar file, inline 'opus' vs haiku fm         -> exit 1 + MISMATCH
#   cache layout         versioned-sibling dev-pipeline root resolves   -> exit 0
#
# UNKNOWN-MODEL cases (the silent-skip hole). Each is written so the PRE-FIX script
# exits 0 on the same fixture — the hole was invisible, so a case whose fixture already
# failed for another reason would demonstrate nothing:
#   fable override       'fable' in modelOverrides, clean table         -> exit 0
#                        (override values are never enum-checked — the feature)
#   fable in MAP         'fable' as a shipped REVIEWER_MODEL value      -> exit 1 + UNKNOWN-MODEL
#   unknown in MAP       'gpt-4' as a shipped REVIEWER_MODEL value      -> exit 1 + UNKNOWN-MODEL
#   unknown inline/scalar scalar file, inline 'gpt-4', scalar == the
#                        dispatched agent's frontmatter tier            -> exit 1 + UNKNOWN-MODEL
#   unknown inline/MAP   map file, inline 'gpt-4' on an agentType line  -> exit 1 + UNKNOWN-MODEL
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

# --- scalar-table files: a dispatch may re-state its tier INLINE ---------------
# Regression guard. A scalar-table file (`const UNIT_TEST_MODEL = 'sonnet'`) can also
# dispatch an agent with an explicit `model: '<tier>'` on the dispatch itself; that
# literal is what runs, not the scalar. The checker used to attribute EVERY agentType
# in the file to the scalar, so a `model: 'haiku'` dispatch inside a sonnet file was
# reported as drift and DENIED EVERY COMMIT IN THE REPO while the code was correct.
# Copy the dev-pipeline fixture and rewrite unit-tests.mjs with such a dispatch.
# Args: <dest_name> <inline-model-for-structured-emitter> -> prints the root path
make_dp_inline_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$DP" "$dst"
  cat > "$dst/skills/run/workflows/unit-tests.mjs" <<MJS
const UNIT_TEST_MODEL = 'sonnet'
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
const plan = { agentType: 'unit-test-plan-reviewer', model: modelOverrides['unit-test-plan-reviewer'] || UNIT_TEST_MODEL }
MJS
  printf '%s' "$dst"
}

# honored — inline 'haiku' matches structured-emitter's frontmatter, so no drift,
# even though the file's scalar is 'sonnet'. (The sibling dispatch with no inline
# literal must still fall through to the scalar and match its own frontmatter.)
INLINE_OK=$(make_dp_inline_variant inline-ok "haiku")
run_cli "$INLINE_OK"
[ $? -eq 0 ] && ok "scalar table: inline model literal is honored over the scalar -> exit 0" \
  || fail "inline model expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# still locksteped — an inline literal is a re-statement like any other, so an inline
# 'opus' against haiku frontmatter is real drift. Proves the fix narrowed the SOURCE
# of the declared model without opening a blind spot.
INLINE_DRIFT=$(make_dp_inline_variant inline-drift "opus")
run_cli "$INLINE_DRIFT"
if [ $? -eq 0 ]; then fail "inline model drift expected exit 1"; else
  grep -q "MISMATCH: 'structured-emitter'" "$TMP/.stderr" && ok "scalar table: inline literal still locksteped against frontmatter -> exit 1 + MISMATCH" \
    || fail "inline drift: exit 1 but no MISMATCH for structured-emitter (stderr: $(cat "$TMP/.stderr"))"
fi

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

# (d) out-of-enum INLINE literal in a scalar file. make_dp_inline_variant is NOT usable
# here: it hardcodes `const UNIT_TEST_MODEL = 'sonnet'` plus a sibling unit-test-plan-reviewer
# dispatch, so pre-fix the unknown token falls through to 'sonnet' and is compared against
# structured-emitter's 'haiku' frontmatter -> MISMATCH, exit 1. That would make the demo
# vacuous (the fixture fails before AND after). This variant sets the scalar EQUAL to the
# dispatched agent's frontmatter tier and writes only the inline dispatch, so the
# fall-through lands on a matching value and the pre-fix script is genuinely silent.
# Args: <dest_name> <scalar> <inline-model> -> prints the root path
make_dp_inline_scalar_variant() {
  local dst="$TMP/$1" scalar="$2" inline="$3"
  cp -R "$DP" "$dst"
  cat > "$dst/skills/run/workflows/unit-tests.mjs" <<MJS
const UNIT_TEST_MODEL = '$scalar'
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
MJS
  printf '%s' "$dst"
}

INLINE_UNKNOWN=$(make_dp_inline_scalar_variant inline-unknown "haiku" "gpt-4")
run_cli "$INLINE_UNKNOWN"
if [ $? -eq 0 ]; then fail "unknown inline literal (scalar file) expected exit 1"; else
  grep -q "UNKNOWN-MODEL: unit-tests.mjs dispatches 'review-toolkit:structured-emitter' with inline model 'gpt-4'" "$TMP/.stderr" \
    && ok "unknown inline literal in a scalar file -> exit 1 + UNKNOWN-MODEL" \
    || fail "inline unknown: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# (e) out-of-enum INLINE literal in a MAP file. The reason the scan is not scoped to the
# scalar loop: a map file's inline dispatch is reached by neither loop today (the MAP grep
# cannot see it — `model:` is an unquoted key — and the inline handling lives inside the
# scalar `for spec in` list). Without this case the guard could ship covering 2 of 5 files
# and every other case would still pass.
# Args: <dest_name> <inline-model> -> prints the root path
make_dp_map_inline_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$DP" "$dst"
  cat > "$dst/skills/run/workflows/code-review.mjs" <<MJS
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
