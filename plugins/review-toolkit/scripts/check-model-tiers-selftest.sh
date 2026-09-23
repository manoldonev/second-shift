#!/usr/bin/env bash
# Selftest for check-model-tiers.sh — the two-root, config-aware model-tier gate.
#
# Runs hermetically from the plugin dir with NO consumer repo: the plugin root
# (.mjs tables, tier alphabet, agent frontmatter), the design-toolkit root, consumer
# config, and consumer agents are all supplied via env overrides
# (SECOND_SHIFT_PLUGIN_ROOT / SECOND_SHIFT_DESIGN_TOOLKIT_ROOT / SECOND_SHIFT_REPO_ROOT
# / SECOND_SHIFT_CONFIG) pointing at static fixtures under scripts/fixtures/ (plus
# mktemp'd config + mutated-table copies), or by a staged install cache. No git repo
# is required.
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
#   cache layout         own tables in the cache; newest design-toolkit
#                        sibling resolves                               -> exit 0
#
# review-toolkit-only install (hook mode, a staged cache holding only
# review-toolkit/<ver>/, a `git commit` payload):
#   clean tables         design-toolkit rows skipped with a note        -> no deny
#   drifted table        deny, reason names the MISMATCH
#   unknown own row      an unqualified row with no agent file          -> deny, DANGLING
#   no workflows/        deny naming MISSING-TABLE; CLI exit 1
#   no model-tiering.md  deny naming UNPARSEABLE-ALPHABET; CLI exit 1
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
RT="$FX/review-toolkit"      # clean plugin root: tables in lockstep with its agents
DT="$FX/design-toolkit"      # design-toolkit root carrying the design row's agent
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
# Args: <plugin_root> [config_path]
# shellcheck disable=SC2030 # exports are deliberately subshell-scoped per case
run_cli() {
  local root="$1" config="${2:-}"
  (
    export SECOND_SHIFT_PLUGIN_ROOT="$root"
    export SECOND_SHIFT_DESIGN_TOOLKIT_ROOT="$DT"
    export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
    [ -n "$config" ] && export SECOND_SHIFT_CONFIG="$config"
    bash "$CHECK" </dev/null 2>"$TMP/.stderr"
  )
}

# Copy the clean plugin root, then rewrite code-review.mjs's REVIEWER_MODEL.
# Args: <dest_name> <security-reviewer-key> <security-reviewer-model>
make_rt_variant() {
  local key="$2" model="$3" dst="$TMP/$1"
  cp -R "$RT" "$dst"
  cat > "$dst/workflows/code-review.mjs" <<MJS
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
}

const REVIEWER_MODEL = {
  '$key': '$model',
  'performance-reviewer': 'code',
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
  "configVersion": 3,
  "tracker": { "type": "github" },
  "commands": { "app": {} },
  "reviewers": { "modelOverrides": { "$agent": "$model" } }
}
JSON
  printf '%s' "$path"
}

echo "check-model-tiers selftest"

# agreement — clean tables match frontmatter
run_cli "$RT"
[ $? -eq 0 ] && ok "agreement: table == frontmatter -> exit 0" || fail "agreement expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# frontmatter mismatch — code-review says tier 'code' (resolves sonnet) for security-reviewer (frontmatter opus)
DRIFT=$(make_rt_variant driftmap "security-reviewer" "code")
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

# override differs — clean table (tier 'reasoning' -> opus == frontmatter default), modelOverride says
# 'sonnet'. This is the per-repo tiering feature (same plugin-shipped table + agent,
# a different tier per consumer): the table keeps the plugin default and the .mjs
# applies the override at dispatch (modelOverrides[...] || TABLE[...]). Legal.
CFG_DIFFERS=$(make_override_config "security-reviewer" "sonnet")
run_cli "$RT" "$CFG_DIFFERS"
[ $? -eq 0 ] && ok "override differs: table keeps plugin default, override wins at dispatch -> exit 0" \
  || fail "override differs expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# override three-way mismatch — drifted table (tier 'code' -> sonnet), frontmatter 'opus',
# modelOverride 'haiku': the table matches neither the override nor the
# frontmatter default -> genuine drift, mismatch.
CFG_THREEWAY=$(make_override_config "security-reviewer" "haiku")
run_cli "$DRIFT" "$CFG_THREEWAY"
if [ $? -eq 0 ]; then fail "override three-way expected exit 1"; else
  grep -q "MISMATCH: 'security-reviewer'" "$TMP/.stderr" && ok "override three-way: table matches neither override nor frontmatter -> exit 1 + MISMATCH" \
    || fail "override three-way: exit 1 but no MISMATCH line (stderr: $(cat "$TMP/.stderr"))"
fi

# qualified name — table key is plugin:-qualified; compared on the bare name
QUAL=$(make_rt_variant qualmap "review-toolkit:security-reviewer" "reasoning")
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
run_cli "$RT" "$CFG_FABLE"
[ $? -eq 0 ] && ok "fable override: legal modelOverrides value, clean table -> exit 0" \
  || fail "fable override expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# (b) 'fable' in a SHIPPED map entry — the mechanical half of the override-only posture.
# Legal in config (case a), an error in a plugin-shipped table.
FABLE_MAP=$(make_rt_variant fablemap "security-reviewer" "fable")
run_cli "$FABLE_MAP"
if [ $? -eq 0 ]; then fail "fable in a shipped MAP entry expected exit 1"; else
  grep -q "UNKNOWN-MODEL: code-review.mjs declares 'security-reviewer' => 'fable'" "$TMP/.stderr" \
    && ok "fable in a shipped MAP entry -> exit 1 + UNKNOWN-MODEL" \
    || fail "fable map: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# (c) an arbitrary out-of-enum token in a shipped map entry. Same path as (b); pinned
# separately because 'fable' is a token we now recognize elsewhere and 'gpt-4' is not,
# so this proves the guard keys on the tier set rather than on a fable special case.
UNKNOWN_MAP=$(make_rt_variant unknownmap "security-reviewer" "gpt-4")
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
make_rt_map_inline_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$RT" "$dst"
  cat > "$dst/workflows/code-review.mjs" <<MJS
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'reasoning',
}
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
MJS
  printf '%s' "$dst"
}

MAP_INLINE_UNKNOWN=$(make_rt_map_inline_variant map-inline-unknown "gpt-4")
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
# structured-emitter's 'haiku' frontmatter ('reasoning' resolves to opus), so
# UNKNOWN-MODEL cannot fire and the pre-fix script is genuinely silent (exit 0) —
# reverting the guard turns this case green again.
# Args: <dest_name> <inline-model> -> prints the root path
make_rt_map_inline_mismatch_variant() {
  local dst="$TMP/$1" inline="$2"
  cp -R "$RT" "$dst"
  cat > "$dst/workflows/code-review.mjs" <<MJS
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'reasoning',
}
const emit = { agentType: 'review-toolkit:structured-emitter', model: '$inline', label: 'x' }
MJS
  printf '%s' "$dst"
}

MAP_INLINE_MISMATCH=$(make_rt_map_inline_mismatch_variant map-inline-mismatch "reasoning")
run_cli "$MAP_INLINE_MISMATCH"
if [ $? -eq 0 ]; then fail "MAP-file inline literal mismatch expected exit 1"; else
  grep -q "MISMATCH: 'structured-emitter'" "$TMP/.stderr" \
    && ok "MAP-file inline literal locksteped against frontmatter -> exit 1 + MISMATCH" \
    || fail "map inline mismatch: exit 1 but no MISMATCH for structured-emitter (stderr: $(cat "$TMP/.stderr"))"
fi

# cache layout — installed marketplace cache is cache/<mkt>/<plugin>/<version>/. The
# tables and alphabet resolve from the script's own version dir with NO
# SECOND_SHIFT_PLUGIN_ROOT override, and the design-toolkit root through the
# versioned-sibling fallback with no SECOND_SHIFT_DESIGN_TOOLKIT_ROOT override.
#
# TWO design-toolkit versions, 0.0.9 and 0.0.10, so this also pins NUMERIC ordering. Both
# carry the marker dir (agents) and so are both candidates; only 0.0.10 carries the agent
# at the tier the table declares, and 0.0.9 is a decoy at 'opus'. Glob order is lexical
# and sorts 0.0.10 BEFORE 0.0.9, so a last-wins pick resolves the decoy and reports
# MISMATCH.
# Args: <dest_name> -> prints the staged script path (cache holds review-toolkit only)
stage_rt_cache() {
  local ver="$TMP/$1/mkt/review-toolkit/0.0.1"
  mkdir -p "$ver/scripts"
  cp "$CHECK" "$ver/scripts/check-model-tiers.sh"
  cp -R "$RT/agents" "$RT/workflows" "$RT/model-tiering.md" "$ver/"
  printf '%s' "$ver/scripts/check-model-tiers.sh"
}
CACHE_CHECK=$(stage_rt_cache cache)
CACHE_MKT="$TMP/cache/mkt"
mkdir -p "$CACHE_MKT/design-toolkit/0.0.9/agents" "$CACHE_MKT/design-toolkit/0.0.10"
cp -R "$DT/agents" "$CACHE_MKT/design-toolkit/0.0.10/agents"
printf 'model: opus\n---\ndecoy\n' > "$CACHE_MKT/design-toolkit/0.0.9/agents/design-faithful-reviewer.md"
# shellcheck disable=SC2030,SC2031 # exports are deliberately subshell-scoped per case
(
  unset SECOND_SHIFT_PLUGIN_ROOT SECOND_SHIFT_DESIGN_TOOLKIT_ROOT SECOND_SHIFT_CONFIG
  export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
  bash "$CACHE_CHECK" </dev/null 2>"$TMP/.stderr"
)
[ $? -eq 0 ] && ok "cache layout: own tables + newest design-toolkit sibling resolve -> exit 0" \
  || fail "cache layout expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# --- review-toolkit-only install, hook mode -----------------------------------
# The tables and alphabet ship in this plugin, so a missing one is a broken install:
# the hook denies naming the cause. design-toolkit rows are skipped when design-toolkit
# is not installed, so a review-toolkit-only repo can still commit.
# Args: <staged_script> [design-toolkit override] -> hook stdout in $TMP/.stdout, stderr in $TMP/.stderr
# shellcheck disable=SC2030,SC2031 # exports are deliberately subshell-scoped per case
run_hook() {
  (
    unset SECOND_SHIFT_PLUGIN_ROOT SECOND_SHIFT_DESIGN_TOOLKIT_ROOT SECOND_SHIFT_CONFIG
    [ -n "${2:-}" ] && export SECOND_SHIFT_DESIGN_TOOLKIT_ROOT="$2"
    export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
    jq -n --arg cwd "$EMPTY_CONSUMER" '{cwd: $cwd, tool_input: {command: "git commit -m x"}}' \
      | bash "$1" >"$TMP/.stdout" 2>"$TMP/.stderr"
  )
}
# The same staged script as a CLI run. Args: <staged_script>
# shellcheck disable=SC2030,SC2031 # exports are deliberately subshell-scoped per case
run_staged_cli() {
  (
    unset SECOND_SHIFT_PLUGIN_ROOT SECOND_SHIFT_DESIGN_TOOLKIT_ROOT SECOND_SHIFT_CONFIG
    export SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER"
    bash "$1" </dev/null 2>/dev/null
  )
}
# deny_reason: the hook's permissionDecisionReason, empty when it did not deny.
deny_reason() {
  jq -r 'select(.hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason' \
    "$TMP/.stdout" 2>/dev/null
}
# expect_deny <label> <staged_script> <reason-pattern> [design-toolkit override]
expect_deny() {
  run_hook "$2" "${4:-}"
  local reason
  reason=$(deny_reason)
  if grep -q "$3" <<<"$reason"; then
    ok "$1 -> hook denies, reason names $3"
  else
    fail "$1: expected a deny naming $3 (stdout: $(cat "$TMP/.stdout"); stderr: $(cat "$TMP/.stderr"))"
  fi
}

RT_ONLY=$(stage_rt_cache rtonly)
run_hook "$RT_ONLY"
if [ -z "$(deny_reason)" ] && grep -q "design-toolkit" "$TMP/.stderr"; then
  ok "review-toolkit only, clean tables: design-toolkit rows skipped with a note, commit allowed"
else
  fail "review-toolkit only, clean tables: expected no deny plus a design-toolkit note (stdout: $(cat "$TMP/.stdout"); stderr: $(cat "$TMP/.stderr"))"
fi

# An override that does not resolve is a wrong path, not an absent plugin: no skip.
expect_deny "review-toolkit only, unresolvable design-toolkit override" "$RT_ONLY" \
  "DANGLING: code-review.mjs declares 'design-faithful-reviewer'" "$TMP/no-such-design-toolkit"

RT_DRIFT=$(stage_rt_cache rtdrift)
perl -pi -e "s/'security-reviewer': 'reasoning'/'security-reviewer': 'code'/" "$(dirname "$RT_DRIFT")/../workflows/code-review.mjs"
expect_deny "review-toolkit only, drifted table" "$RT_DRIFT" "MISMATCH: 'security-reviewer'"

RT_GHOST=$(stage_rt_cache rtghost)
perl -pi -e "s/('performance-reviewer': 'code',)/\$1\n  'review-toolkit:ghost-reviewer': 'code',/" "$(dirname "$RT_GHOST")/../workflows/code-review.mjs"
expect_deny "review-toolkit only, own row with no agent file" "$RT_GHOST" "DANGLING: code-review.mjs declares 'ghost-reviewer'"

RT_NOWF=$(stage_rt_cache rtnowf)
rm -rf "$(dirname "$RT_NOWF")/../workflows"
expect_deny "no workflows/ dir" "$RT_NOWF" "MISSING-TABLE"
run_staged_cli "$RT_NOWF"
[ $? -eq 1 ] && ok "no workflows/ dir -> CLI exit 1" || fail "no workflows/ dir: CLI expected exit 1"

RT_NOALPHA=$(stage_rt_cache rtnoalpha)
rm -f "$(dirname "$RT_NOALPHA")/../model-tiering.md"
expect_deny "no model-tiering.md" "$RT_NOALPHA" "UNPARSEABLE-ALPHABET"
run_staged_cli "$RT_NOALPHA"
[ $? -eq 1 ] && ok "no model-tiering.md -> CLI exit 1" || fail "no model-tiering.md: CLI expected exit 1"

# --- #351: the alphabet is PARSED, so it is variable ---------------------------
# Every case below would pass vacuously against a guard with a hardcoded
# opus|sonnet|haiku constant, because that guard never reads the doc at all. Each is
# written so breaking the specific new mechanism it names turns it red.

# Build a plugin root on a CUSTOM alphabet: the doc table and both engines'
# inline maps agree on tier names that are not the shipped ones.
# Args: <dest_name> <tierA> <tierB> <tierC> -> prints the root path
make_rt_custom_alphabet() {
  local dst="$TMP/$1" a="$2" b="$3" c="$4"
  cp -R "$RT" "$dst"
  cat > "$dst/model-tiering.md" <<DOC
# fixture (custom alphabet)

## Tier alphabet

| Tier | Dispatch token | Model | Rationale |
| ---- | -------------- | ----- | --------- |
| $a | opus | claude-opus-4-8 | deep |
| $b | sonnet | claude-sonnet-4-6 | fast |
| $c | haiku | claude-haiku-4-5 | sink |
DOC
  cat > "$dst/workflows/code-review.mjs" <<MJS
const DEFAULT_TIER_MAP = {
  $a: 'opus',
  $b: 'sonnet',
  $c: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': '$a',
  'performance-reviewer': '$b',
}
MJS
  cat > "$dst/workflows/intake-review.mjs" <<MJS
const DEFAULT_TIER_MAP = {
  $a: 'opus',
  $b: 'sonnet',
  $c: 'haiku',
}

const INTAKE_MODEL = {
  'spec-reviewer': '$a',
}
MJS
  printf '%s' "$dst"
}

# Write a config carrying a single reviewers.tierMap entry.
# Args: <tier> <dispatch-token> -> prints the config path
make_tiermap_config() {
  local tier="$1" token="$2" path="$TMP/tiermap-$1-$2.json"
  cat > "$path" <<JSON
{
  "configVersion": 3,
  "tracker": { "type": "github" },
  "commands": { "app": {} },
  "reviewers": { "tierMap": { "$tier": "$token" } }
}
JSON
  printf '%s' "$path"
}

# custom alphabet — tier names the shipped guard never heard of, resolving to the same
# models the frontmatter declares. Red if the alphabet is hardcoded anywhere.
CUSTOM=$(make_rt_custom_alphabet customalpha deep fast sink)
run_cli "$CUSTOM"
[ $? -eq 0 ] && ok "custom alphabet: parsed tier names lockstep against frontmatter -> exit 0" \
  || fail "custom alphabet expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# counter-scan NON-VACUITY under a custom alphabet. The unrestricted scans must judge
# against the PARSED alphabet, not a constant: 'sonnet' is a legal dispatch token and was
# a legal tier before this change, so a guard still holding the old constant reports
# nothing here.
CUSTOM_BAD=$(make_rt_custom_alphabet customalpha-bad deep fast sink)
cat > "$CUSTOM_BAD/workflows/code-review.mjs" <<'MJS'
const DEFAULT_TIER_MAP = {
  deep: 'opus',
  fast: 'sonnet',
  sink: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'sonnet',
}
MJS
run_cli "$CUSTOM_BAD"
if [ $? -eq 0 ]; then fail "out-of-alphabet token under a custom alphabet expected exit 1"; else
  grep -q "UNKNOWN-MODEL: code-review.mjs declares 'security-reviewer' => 'sonnet'" "$TMP/.stderr" \
    && ok "counter-scan judges against the PARSED alphabet, not a constant -> exit 1 + UNKNOWN-MODEL" \
    || fail "custom-alphabet counter-scan: exit 1 but no UNKNOWN-MODEL line (stderr: $(cat "$TMP/.stderr"))"
fi

# a consumer tierMap is NEVER drift (D-18). Clean shipped tables, frontmatter 'opus',
# and a config retargeting 'reasoning' to haiku. Lockstep is held against the SHIPPED
# default, so this must stay silent — a guard resolving the table through the EFFECTIVE
# map reports MISMATCH here and makes tierMap unusable.
CFG_TIERMAP=$(make_tiermap_config "reasoning" "haiku")
run_cli "$RT" "$CFG_TIERMAP"
if [ $? -eq 0 ]; then
  ok "consumer tierMap retargeting a tier is not drift -> exit 0"
else
  fail "consumer tierMap must not MISMATCH (stderr: $(cat "$TMP/.stderr"))"
fi

# TIER-MAP-DRIFT (value): an engine's inlined copy disagrees with the authority. This is
# the check that makes "one authority" true while the sandbox forbids deleting the copies.
DRIFT_MAP=$(make_rt_variant tiermapdrift "security-reviewer" "reasoning")
cat > "$DRIFT_MAP/workflows/code-review.mjs" <<'MJS'
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'haiku',
  emit: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'reasoning',
}
MJS
run_cli "$DRIFT_MAP"
if [ $? -eq 0 ]; then fail "inline tier-map drift expected exit 1"; else
  grep -q "TIER-MAP-DRIFT: code-review.mjs inlines 'code' => 'haiku'" "$TMP/.stderr" \
    && ok "inline DEFAULT_TIER_MAP held against the authority -> exit 1 + TIER-MAP-DRIFT" \
    || fail "tier-map drift: exit 1 but no TIER-MAP-DRIFT line (stderr: $(cat "$TMP/.stderr"))"
fi

# TIER-MAP-DRIFT (omission): a tier the authority declares but the engine omits would
# fall through to the engine's own default at dispatch, silently. Absence is drift too,
# and a value-only comparison passes this fixture.
OMIT_MAP=$(make_rt_variant tiermapomit "security-reviewer" "reasoning")
cat > "$OMIT_MAP/workflows/code-review.mjs" <<'MJS'
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'reasoning',
}
MJS
run_cli "$OMIT_MAP"
if [ $? -eq 0 ]; then fail "omitted tier expected exit 1"; else
  grep -q "TIER-MAP-DRIFT: .* declares tier 'emit' but code-review.mjs's DEFAULT_TIER_MAP omits it" "$TMP/.stderr" \
    && ok "a tier the authority declares and an engine omits -> exit 1 + TIER-MAP-DRIFT" \
    || fail "tier-map omission: exit 1 but no omission line (stderr: $(cat "$TMP/.stderr"))"
fi

# UNPARSEABLE-ALPHABET: without the table there is no map, and every table entry would be
# unresolvable. Fail loud rather than falling back to a hardcoded alphabet that would
# reintroduce exactly the drift this ticket removes.
NOALPHA=$(make_rt_variant noalpha "security-reviewer" "reasoning")
cat > "$NOALPHA/model-tiering.md" <<'DOC'
# fixture with no alphabet table

Prose only.
DOC
run_cli "$NOALPHA"
if [ $? -eq 0 ]; then fail "missing alphabet table expected exit 1"; else
  grep -q "UNPARSEABLE-ALPHABET" "$TMP/.stderr" \
    && ok "no '## Tier alphabet' table -> exit 1 + UNPARSEABLE-ALPHABET" \
    || fail "missing alphabet: exit 1 but no UNPARSEABLE-ALPHABET line (stderr: $(cat "$TMP/.stderr"))"
fi

echo
echo "[check-model-tiers-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
