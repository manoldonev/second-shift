#!/usr/bin/env bash
# Verify the model tier each dev-pipeline .mjs dispatch table declares stays in
# lockstep with the dispatched agent's effective model — now across TWO ROOTS and
# with config overrides, after pluginization.
#
# Why this matters: each agent's model tier is the source of truth in its
# `<name>.md` frontmatter, but the Workflow .mjs scripts can't read files, so they
# RE-STATE the tier in a table and pass `model` explicitly — so a frontmatter
# downgrade that misses the table keeps dispatching the more expensive model,
# silently (cost-increasing drift). This check fails the commit when a table and
# the agent's effective model disagree.
#
# Runtime precedence: config reviewers.modelOverrides > .mjs table (every
# validated .mjs consults modelOverrides before its table); the winner is then
# RESOLVED through the tier map (shipped default, merged with config reviewers.tierMap).
# The table is the plugin-shipped default, immutable to consumers. So without an override the
# table must equal the frontmatter (plugin-internal lockstep); with an override,
# the table may keep the plugin default OR equal the override — a consumer
# override differing from the shipped table is the per-repo tiering feature
# (observed need: security-reviewer runs opus in one repo, sonnet in another,
# from the same plugin-shipped agent file), and only a table matching neither
# is drift.
#
# Two-root contract
# -----------------
#   .mjs tables      live in the dev-pipeline PLUGIN:
#                    $SECOND_SHIFT_DEV_PIPELINE_ROOT (or $SCRIPT_DIR/../../dev-pipeline)
#                      /workflows/
#                    If this dir is unlocatable the check FAILS naming the override.
#   agent frontmatter is read from BOTH roots:
#                    PLUGIN agents   $SECOND_SHIFT_PLUGIN_ROOT (or $SCRIPT_DIR/..)/agents
#                    CONSUMER agents $SECOND_SHIFT_REPO_ROOT (or the git repo of $PWD)
#                                      /.claude/agents   (backs reviewers.add)
#   config           $SECOND_SHIFT_CONFIG (or <consumer>/.claude/second-shift.config.json)
#                    supplies reviewers.modelOverrides. Missing = no overrides.
#
# Table agent names are parsed tolerant of BOTH bare (`security-reviewer`) and
# qualified (`review-toolkit:security-reviewer`) spellings — another agent is
# namespacing them concurrently — comparing on the bare name.
#
# Direction: table -> effective model. Every (agent, model) pair DECLARED in a
# table must match. The reverse is intentionally NOT checked.
#
# Tables validated:
#   - map  REVIEWER_MODEL  in workflows/code-review.mjs
#   - map  INTAKE_MODEL    in workflows/intake-review.mjs
#     Since #351 these declare an abstract TIER, resolved through the alphabet parsed from
#     model-tiering.md before any comparison. Each file also inlines a DEFAULT_TIER_MAP
#     copy (the sandbox forbids imports) which is held against that same authority.
#     A MAP file's dispatch lines may ALSO carry an inline `model: '<tier>'` literal; that
#     literal is a STANDALONE declaration — MAP files have no scalar to fall through to —
#     and is lockstep-checked directly. No shipped dispatch carries one today: the
#     structured-emitter leg that did was moved INTO both maps by #351, which is what gave
#     it override and tierMap support. The path stays for the next inline carrier.
#   - a map  DESIGN_MODEL (design-sync.mjs), a scalar UNIT_TEST_MODEL (unit-tests.mjs)
#     and a scalar EXECUTOR_MODEL (mutation-gate.mjs) — RETIRED in #574 with their
#     engines; a scalar plan-reviewer constant was RETIRED in #348 with the plan
#     dispatcher. Each spec was removed from its loop, not made optional: a missing
#     table is MISSING-TABLE by design, so a dead spec would red every consumer.
#
# Error classes:
#   MISMATCH / DANGLING / NO-FRONTMATTER  the lockstep failures above.
#   PARSE / MISSING-TABLE / UNLOCATABLE   the script could not read what it validates.
#   UNKNOWN-MODEL                         a token outside the parsed tier alphabet in a
#                                         shipped MAP entry (the two map files) or in an
#                                         inline `model: '<tier>'` literal (BOTH parsed
#                                         workflow files; further carriers existed until
#                                         #348/#574 deleted them). Both used to
#                                         be SILENT: the enum lived inside the extraction
#                                         regexes, so an unknown token was skipped entirely
#                                         (map) or attributed to the file's scalar (inline).
#                                         `fable` and any other non-shipped tier are
#                                         override-only (config reviewers.modelOverrides,
#                                         where values are never enum-checked); in shipped
#                                         code they are an error by design.
#
# NOT validated: agent frontmatter tokens. `frontmatter_model` reads the value without
# enum-checking it, deliberately — frontmatter is read from the CONSUMER root too, so a
# repo-local reviewers.add agent may legitimately declare an override-only tier of its own.
# A shipped agent drifting to an unknown tier while named in a table still fails, as
# MISMATCH rather than UNKNOWN-MODEL.
#
# Modes:
#   - Standalone CLI: errors -> stderr, exit 1 on drift, exit 0 if clean.
#   - PreToolUse hook (invoked from settings.json with JSON stdin):
#     errors -> stderr AND emit `permissionDecision: "deny"` JSON to stdout.

set -uo pipefail

# Resolve this script's own dir BEFORE any cd (hook mode cd's to the consumer cwd).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Hook-mode detection: stdin is a pipe carrying JSON with .cwd.
HOOK_MODE=0
if [ ! -t 0 ]; then
    HOOK_INPUT=$(cat)
    if [ -n "$HOOK_INPUT" ] && echo "$HOOK_INPUT" | jq -e .cwd >/dev/null 2>&1; then
        HOOK_MODE=1
        cd "$(echo "$HOOK_INPUT" | jq -r '.cwd')" || exit 0

        # Self-gate on the REAL command. A PreToolUse `if:` matcher sees only the
        # outer command string, and the configured glob (`Bash(git -c * commit *)`)
        # over-matches non-commit commands that merely contain a `git -c`/`git -C`
        # substring plus a `commit`/`commitSha` substring (issue #208). The glob's
        # tokenization is engine-internal and unverifiable, so we self-gate here:
        # allow (exit 0) unless the command actually invokes `git ... commit` as a
        # subcommand. Mirrors check-reviewer-references.sh verbatim.
        CMD=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')
        printf '%s' "$CMD" | grep -Eq \
            '(^|[;&|]|&&|\|\|)[[:space:]]*git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--[^[:space:]]+))*[[:space:]]+commit([[:space:]]|$)' \
            || exit 0
    fi
fi

# --- Root resolution -------------------------------------------------------
# Sibling plugin roots (dev-pipeline -> .mjs tables; design-toolkit -> the
# design-faithful agent family). Two on-disk layouts exist:
#   marketplace repo:  plugins/review-toolkit/scripts -> ../../<plugin>
#   installed cache:   cache/<mkt>/review-toolkit/<ver>/scripts
#                        -> ../../../<plugin>/<ver>  (versioned siblings)
# Env override wins; otherwise try repo layout, then the newest cache sibling
# that actually carries the marker path.
# Args: <plugin-name> <marker-subpath> [env-override-value]
resolve_sibling_plugin_root() {
    local name="$1" marker="$2" override="${3:-}"
    if [ -n "$override" ]; then
        (cd "$override" 2>/dev/null && pwd)
        return
    fi
    local cand
    cand=$(cd "$SCRIPT_DIR/../../$name" 2>/dev/null && pwd) || cand=""
    if [ -n "$cand" ] && [ -d "$cand/$marker" ]; then
        echo "$cand"
        return
    fi
    # Cache layout: pick the HIGHEST version dir with the marker path. Glob order is
    # lexical, so the bare `tail -1` this used to be ranked 9.0.0 above 10.0.0. ASCENDING +
    # `tail -1` rather than a reversed sort: BSD sort ignores a global `-r` once per-key
    # modifiers are present, which would silently select the OLDEST version there.
    for cand in "$SCRIPT_DIR"/../../../"$name"/*/; do
        [ -d "$cand/$marker" ] || continue
        printf '%s\t%s\n' "$(basename "$cand")" "$(cd "$cand" && pwd)"
    done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-
}
DEV_PIPELINE_ROOT=$(resolve_sibling_plugin_root dev-pipeline "workflows" "${SECOND_SHIFT_DEV_PIPELINE_ROOT:-}")
WF="$DEV_PIPELINE_ROOT/workflows"

# design-toolkit plugin root -> design-faithful agent-family frontmatter
# (the code-review.mjs table references these agents, which ship in
# design-toolkit, not review-toolkit). Optional: a consumer without the
# design-toolkit plugin resolves this empty, and those agents fall through to
# the consumer root like any other name.
DESIGN_TOOLKIT_ROOT=$(resolve_sibling_plugin_root design-toolkit "agents" "${SECOND_SHIFT_DESIGN_TOOLKIT_ROOT:-}")
DESIGN_AGENTS="${DESIGN_TOOLKIT_ROOT:+$DESIGN_TOOLKIT_ROOT/agents}"

# review-toolkit plugin root -> generic reviewer agent frontmatter.
PLUGIN_ROOT="${SECOND_SHIFT_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
PLUGIN_ROOT=$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd) || PLUGIN_ROOT=""
PLUGIN_AGENTS="$PLUGIN_ROOT/agents"

# Consumer root -> repo-local (reviewers.add) agent frontmatter + config.
if [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then
    REPO_ROOT="$SECOND_SHIFT_REPO_ROOT"
else
    gcd=$(git rev-parse --git-common-dir 2>/dev/null) || gcd=""
    if [ -n "$gcd" ]; then
        case "$gcd" in /*) : ;; *) gcd="$PWD/$gcd" ;; esac
        REPO_ROOT=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) || REPO_ROOT=""
    else
        REPO_ROOT=""
    fi
fi
CONSUMER_AGENTS=""
[ -n "$REPO_ROOT" ] && CONSUMER_AGENTS="$REPO_ROOT/.claude/agents"

if [ -n "${SECOND_SHIFT_CONFIG:-}" ]; then
    CONFIG="$SECOND_SHIFT_CONFIG"
elif [ -n "$REPO_ROOT" ]; then
    CONFIG="$REPO_ROOT/.claude/second-shift.config.json"
else
    CONFIG=""
fi

# The .mjs tables are the reason this check exists — if we can't find them, fail
# loudly naming the override rather than silently passing.
if [ -z "$DEV_PIPELINE_ROOT" ] || [ ! -d "$WF" ]; then
    msg="UNLOCATABLE: dev-pipeline workflow tables not found via env override, repo-layout sibling ($SCRIPT_DIR/../../dev-pipeline), or cache-layout siblings ($SCRIPT_DIR/../../../dev-pipeline/<ver>) — expected <root>/workflows. Set SECOND_SHIFT_DEV_PIPELINE_ROOT to the dev-pipeline plugin root."
    printf '%s\n' "$msg" >&2
    if [ $HOOK_MODE -eq 1 ]; then
        # Standalone adoption (#14, F57): the sibling dev-pipeline plugin isn't
        # installed, so the .mjs model-tier lockstep contract is not in force — a
        # repo adopting review-toolkit alone must NOT have its commits denied. Fail
        # OPEN (allow the commit). The standalone CLI path still exits 1 (advisory).
        echo "[check-model-tiers] dev-pipeline plugin not installed — standalone repo, hook allows the commit (lockstep check applies only with dev-pipeline present)." >&2
        exit 0
    fi
    exit 1
fi

errors=()

# --- The tier alphabet, parsed from its authority ----------------------------
# Shipped dispatch tables name an abstract TIER (`reasoning`), never a vendor token
# (`opus`). The tier -> dispatch-token map is declared exactly once, in the
# `## Tier alphabet` table of the dev-pipeline plugin's model-tiering.md, and parsed
# here. The `.mjs` engines inline a DEFAULT_TIER_MAP copy because the Workflow sandbox
# forbids imports; check_inline_default_map below holds each copy against this table,
# which is what makes "one authority" true rather than aspirational.
#
# Bash 3.2 compatibility (CI runs a stock-3.2 macOS lane where `declare -A` fails OPEN):
# the map travels as TAB-separated text and is looked up with awk. No associative
# arrays anywhere in this script.
ALPHABET_DOC="$DEV_PIPELINE_ROOT/model-tiering.md"

# Section-anchored: only rows inside `## Tier alphabet` feed the map, so a future table
# elsewhere in the doc cannot silently extend the alphabet. The header row ('Tier') and
# the separator row (dashes) fail the lowercase-token patterns and drop out.
# The parse itself is duplicated in dev-pipeline's config-lint.sh, which needs the same
# alphabet to judge a modelOverrides value. Two copies rather than one import: config-lint.sh is
# in a DIFFERENT PLUGIN, where a sibling `source` is a hop-count path that breaks under the
# version-keyed install cache. Held by the `tier-alphabet-parse` LOCKSTEP markers — the block
# between them is compared verbatim by scripts/check-lockstep-pairs.sh. Edit one, edit both.
parse_default_tier_map() { # parse_default_tier_map <doc-path>
    [ -f "$1" ] || return 0
# LOCKSTEP-BEGIN tier-alphabet-parse
    awk '
        /^##[[:space:]]+Tier alphabet[[:space:]]*$/ { inseg = 1; next }
        inseg && /^##[[:space:]]/                   { inseg = 0 }
        inseg && /^\|/ {
            n = split($0, c, "|")
            if (n < 4) next
            tier = c[2]; tok = c[3]
            gsub(/^[ \t]+|[ \t]+$/, "", tier)
            gsub(/^[ \t]+|[ \t]+$/, "", tok)
            if (tier ~ /^[a-z][a-z0-9_-]*$/ && tok ~ /^[a-z][a-z0-9_.-]*$/)
                printf "%s\t%s\n", tier, tok
        }
    ' "$1"
# LOCKSTEP-END tier-alphabet-parse
}

# `<tier>` -> dispatch token, or empty when the tier is not in the given map.
map_lookup() { # map_lookup <map-text> <key>
    printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2; exit }'
}

DEFAULT_TIER_MAP_TEXT="$(parse_default_tier_map "$ALPHABET_DOC")"
if [ -z "$DEFAULT_TIER_MAP_TEXT" ]; then
    errors+=("UNPARSEABLE-ALPHABET: no '## Tier alphabet' table with Tier and Dispatch-token columns in $ALPHABET_DOC. That table is the single authority for the tier -> model default map; without it every shipped table entry is unresolvable, so this fails loud rather than falling back to a hardcoded alphabet that would drift from the doc.")
fi

# Consumer tierMap (reviewers.tierMap), MERGED over the shipped default per tier: a
# consumer naming one tier retargets only that tier. Used ONLY to resolve an override
# value that names a tier — never for the table/frontmatter lockstep, which is held
# against the shipped default so that a consumer retargeting a tier is not drift. Same
# posture the modelOverrides precedent already sets below.
config_tier_map() {
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || return 0
    jq -r '(.reviewers.tierMap // {}) | to_entries[] | "\(.key)\t\(.value)"' "$CONFIG" 2>/dev/null
}
EFFECTIVE_TIER_MAP_TEXT="$(
    printf '%s\n%s\n' "$DEFAULT_TIER_MAP_TEXT" "$(config_tier_map)" \
        | awk -F'\t' '
            NF == 2 { if (!($1 in seen)) { order[++n] = $1; seen[$1] = 1 } m[$1] = $2 }
            END     { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], m[order[i]] }'
)"

# Strip a leading `plugin:` qualifier, leaving the bare agent name.
bare() { printf '%s' "$1" | sed -E 's/^[^:]+://'; }

# Path to an agent's frontmatter file: review-toolkit root, then the
# design-toolkit sibling (design-faithful family), then the consumer root.
agent_file() {
    local a="$1"
    if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_AGENTS/$a.md" ]; then
        printf '%s' "$PLUGIN_AGENTS/$a.md"
    elif [ -n "$DESIGN_AGENTS" ] && [ -f "$DESIGN_AGENTS/$a.md" ]; then
        printf '%s' "$DESIGN_AGENTS/$a.md"
    elif [ -n "$CONSUMER_AGENTS" ] && [ -f "$CONSUMER_AGENTS/$a.md" ]; then
        printf '%s' "$CONSUMER_AGENTS/$a.md"
    else
        printf ''
    fi
}

# Frontmatter `model:` for a file path, or empty if the file/field is missing.
frontmatter_model() {
    local file="$1"
    [ -n "$file" ] && [ -f "$file" ] || { printf ''; return; }
    grep -m1 '^model:' "$file" | sed -E 's/^model:[[:space:]]*//; s/[[:space:]]+$//'
}

# config reviewers.modelOverrides[agent], or empty.
override_model() {
    local a="$1"
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || { printf ''; return; }
    jq -r --arg a "$a" '.reviewers.modelOverrides[$a] // empty' "$CONFIG" 2>/dev/null
}

# Compare a single (table agent, table-model) pair against the effective model.
# Precedence at runtime: modelOverride > table (every validated .mjs looks up
# args.config.reviewers.modelOverrides before its table). The table itself is the
# PLUGIN-SHIPPED default, immutable to consumers — so when an override exists, the
# table is allowed to keep the plugin default (override wins at dispatch) or to
# already equal the override; either is consistent. A consumer override differing
# from the shipped table is the FEATURE (per-repo tiering from the same plugin),
# not drift. Without an override, table ↔ frontmatter lockstep is required as
# before. Agent name compared bare.
#
# TIERS (#351): the table now declares a tier, so both sides are compared as RESOLVED
# dispatch tokens. The table resolves through the SHIPPED DEFAULT map — never the
# consumer's — so a repo retargeting a tier in `reviewers.tierMap` is not drift, exactly
# as a differing `modelOverrides` value is not. An override value may itself name a tier
# (the closed union config-lint enforces), so it resolves through the EFFECTIVE map;
# a value naming no tier is already a raw dispatch token and passes through.
check_pair() {
    local raw="$1" table_model="$2" table="$3"
    local agent file fm ov table_resolved ov_resolved
    agent=$(bare "$raw")
    ov=$(override_model "$agent")
    file=$(agent_file "$agent")

    table_resolved=$(map_lookup "$DEFAULT_TIER_MAP_TEXT" "$table_model")
    if [ -z "$table_resolved" ]; then
        # Unreachable from the enum-anchored loop (it only yields in-alphabet tiers) and
        # reported by the counter-scan when it is not. Belt and braces: never compare
        # against an empty string, which would equal every missing frontmatter.
        errors+=("UNRESOLVED-TIER: $table declares '$agent' => '$table_model', which the tier alphabet in $ALPHABET_DOC does not define")
        return
    fi
    if [ -z "$file" ]; then
        if [ -z "$ov" ]; then
            errors+=("DANGLING: $table declares '$agent' => '$table_model' but no agent file exists in the review-toolkit root ($PLUGIN_AGENTS), the design-toolkit root (${DESIGN_AGENTS:-<not installed>}), or the consumer root, and reviewers.modelOverrides has no entry")
            return
        fi
        # Override present with no agent file anywhere: the override still names the
        # runtime model; nothing further to lockstep against.
        return
    fi
    fm=$(frontmatter_model "$file")
    if [ -z "$fm" ]; then
        if [ -z "$ov" ]; then
            errors+=("NO-FRONTMATTER: $table declares '$agent' => '$table_model' but $file has no 'model:' field (and reviewers.modelOverrides has no entry)")
            return
        fi
        fm="$ov"
    fi
    if [ -n "$ov" ]; then
        ov_resolved=$(map_lookup "$EFFECTIVE_TIER_MAP_TEXT" "$ov")
        [ -n "$ov_resolved" ] || ov_resolved="$ov"
        if [ "$table_resolved" != "$ov_resolved" ] && [ "$table_resolved" != "$fm" ]; then
            errors+=("MISMATCH: '$agent' — table $table says tier '$table_model' (resolves to '$table_resolved'), which matches neither the modelOverride ('$ov' => '$ov_resolved') nor the agent frontmatter default ('$fm')")
        fi
        return
    fi
    if [ "$fm" != "$table_resolved" ]; then
        errors+=("MISMATCH: '$agent' — frontmatter says '$fm' but $table says tier '$table_model', which resolves to '$table_resolved' (expected a tier resolving to '$fm')")
    fi
}

# --- The inlined DEFAULT_TIER_MAP copies -------------------------------------
# The Workflow sandbox forbids imports, so each engine inlines the alphabet. This holds
# every copy against the parsed authority, which is the whole content of "one authority"
# once removal is impossible. Keys are UNQUOTED in the .mjs on purpose: the entry scans
# below match `'key': 'value'`, so a quoted tier map would read as a dispatch table and
# every tier would be reported DANGLING.
check_inline_default_map() { # check_inline_default_map <file> <tbl>
    local file="$1" tbl="$2" block pair tier tok expect
    block=$(sed -n "/const DEFAULT_TIER_MAP = {/,/^}/p" "$file")
    if [ -z "$block" ]; then
        errors+=("MISSING-TIER-MAP: $tbl inlines no 'const DEFAULT_TIER_MAP = {' block, so its tier resolution cannot be held against $ALPHABET_DOC")
        return
    fi
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        tier=$(printf '%s' "$pair" | sed -E "s/^[[:space:]]*([a-z][a-z0-9_-]*):[[:space:]]*'([^']+)'.*/\1/")
        tok=$(printf '%s' "$pair" | sed -E "s/^[[:space:]]*([a-z][a-z0-9_-]*):[[:space:]]*'([^']+)'.*/\2/")
        expect=$(map_lookup "$DEFAULT_TIER_MAP_TEXT" "$tier")
        if [ -z "$expect" ]; then
            errors+=("TIER-MAP-DRIFT: $tbl inlines tier '$tier', which the alphabet in $ALPHABET_DOC does not declare")
        elif [ "$expect" != "$tok" ]; then
            errors+=("TIER-MAP-DRIFT: $tbl inlines '$tier' => '$tok' but $ALPHABET_DOC declares '$tier' => '$expect'")
        fi
    done <<< "$(printf '%s\n' "$block" | grep -E "^[[:space:]]*[a-z][a-z0-9_-]*:[[:space:]]*'[^']+'")"

    # Reverse direction: a tier the authority declares but the engine omits would fall
    # through to the engine's own default at dispatch, silently, so absence is drift too.
    while IFS=$'\t' read -r tier _tok; do
        [ -z "$tier" ] && continue
        grep -qE "^[[:space:]]*$tier:[[:space:]]*'[^']+'" <<<"$block" && continue
        errors+=("TIER-MAP-DRIFT: $ALPHABET_DOC declares tier '$tier' but $tbl's DEFAULT_TIER_MAP omits it")
    done <<< "$DEFAULT_TIER_MAP_TEXT"
}

# --- UNKNOWN-MODEL: tokens outside the known tier set ------------------------
# The enum below is baked into the EXTRACTION regexes of the two scans that follow
# this block, which is what made an out-of-enum token invisible rather than wrong:
# the MAP grep never matched the entry (so check_pair never saw it), and the inline
# grep's miss fell through to the file's scalar (so the dispatch was attributed to a
# model it does not use). Both were silent — a 'gpt-4' or 'fable' entry left the
# script green. These two scans re-read the same text with the model alternation
# UNRESTRICTED and error on anything outside the set, so the enum-anchored parse
# sites above/below can keep their tri-value strictness without a blind spot.
#
# The shipped alphabet is now VARIABLE (#351): it is whatever `## Tier alphabet` in
# model-tiering.md declares, so this constant is derived rather than written. What did
# NOT change is which layer is restricted — only the enum-anchored EXTRACTION regexes
# below take this variable; the two counter-scans keep matching `'[^']+'` unrestricted
# and merely VALIDATE against it, which is the two-layer design that stops an
# out-of-alphabet token from going invisible.
#
# `fable`, and every raw vendor token, is now out-of-alphabet in shipped code by
# construction: the alphabet holds TIER names, and `fable` is not a tier. A consumer
# still names it in reviewers.modelOverrides, where values are never enum-checked. That
# keeps the override-only posture mechanical instead of listed.
#
# NOT guarded: agent frontmatter (`frontmatter_model` above). It is read from the
# consumer root as well as the plugin root, so a repo-local reviewers.add agent may
# legitimately declare an override-only tier in its own frontmatter — enum-guarding
# it would reject exactly the per-repo expressibility modelOverrides exists to give.
# A SHIPPED agent that drifts to an unknown tier while named in a table still fails,
# as MISMATCH rather than UNKNOWN-MODEL, so the failure direction stays safe.
KNOWN_TIERS_RE="$(printf '%s\n' "$DEFAULT_TIER_MAP_TEXT" | awk -F'\t' 'NF == 2 { printf "%s%s", sep, $1; sep = "|" }')"
# An empty alphabet already errored above; keep the regex non-empty so `^()$` cannot
# match every token and turn the counter-scans into silent no-ops on the way out.
[ -n "$KNOWN_TIERS_RE" ] || KNOWN_TIERS_RE='\0^NONE'

# MAP entries, whole-file — the same shape the enum-anchored grep uses, minus the
# enum. Deliberately unrestricted rather than region-extracted: it matches only
# genuine table entries across both surviving MAP files today (16/16 — 13 in
# code-review.mjs, 3 in intake-review.mjs, the emitter row included since #351), and a
# future non-tier `'key': 'value'` string map tripping it fails LOUD, which is the safe
# direction for this script. The count moves whenever a table gains an agent; it is
# documentation of the scan's current precision, never an assertion the script checks.
scan_unknown_map_entries() {
    local file="$1" tbl="$2" pair m a
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        m=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\2/")
        grep -qE "^($KNOWN_TIERS_RE)\$" <<<"$m" && continue
        a=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\1/")
        errors+=("UNKNOWN-MODEL: $tbl declares '$a' => '$m', which is not a known tier ($KNOWN_TIERS_RE). Shipped tables carry plugin defaults only; per-repo tiers (including 'fable') belong in config reviewers.modelOverrides.")
    done <<< "$(grep -oE "'[a-z0-9:-]+': '[^']+'" "$file")"
}

# Inline `model:` literals on agentType-bearing lines. Runs over BOTH parsed
# workflow files (it named five until #574/#584 retired three engines):
# the MAP grep above cannot see an inline literal at all
# (`model:` is an unquoted key). This scan catches an OUT-OF-ENUM inline literal
# in either file; the MAP loop's own inline pass
# (below, in the `code-review.mjs`/`intake-review.mjs` for-loop)
# separately lockstep-checks an IN-ENUM inline literal there against frontmatter, so
# the two together cover both failure modes in the MAP files.
# A `model:` that is an EXPRESSION (`modelOverrides[...] || SCALAR`) carries no
# literal, does not match, and keeps falling through to the scalar as before.
scan_unknown_inline_literals() {
    local file="$1" tbl="$2" line m a
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        grep -qE "model: '[^']+'" <<<"$line" || continue
        m=$(printf '%s' "$line" | sed -E "s/.*model: '([^']+)'.*/\1/")
        grep -qE "^($KNOWN_TIERS_RE)\$" <<<"$m" && continue
        a=$(printf '%s' "$line" | sed -E "s/.*agentType: '([^']+)'.*/\1/")
        errors+=("UNKNOWN-MODEL: $tbl dispatches '$a' with inline model '$m', which is not a known tier ($KNOWN_TIERS_RE). Shipped dispatches carry plugin defaults only; per-repo tiers (including 'fable') belong in config reviewers.modelOverrides.")
    done <<< "$(grep -E "agentType: '[a-z0-9:-]+'" "$file")"
}

# --- Map tables: 'agent': 'model' entries (agent may be plugin:-qualified). ---
for tbl in code-review.mjs intake-review.mjs; do
    file="$WF/$tbl"
    [ -f "$file" ] || { errors+=("MISSING-TABLE: $file not found"); continue; }
    check_inline_default_map "$file" "$tbl"
    scan_unknown_map_entries "$file" "$tbl"
    scan_unknown_inline_literals "$file" "$tbl"
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        agent=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\1/")
        model=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\2/")
        check_pair "$agent" "$model" "$tbl"
    done <<< "$(grep -oE "'[a-z0-9:-]+': '($KNOWN_TIERS_RE)'" "$file")"

    # Inline `model:` literals on agentType-bearing dispatch lines. Unlike the scalar
    # loop below, a MAP file has no file-level scalar to fall through to — the inline
    # literal IS the declaration, checked directly against frontmatter/override. This
    # is what closes the gap scan_unknown_inline_literals only enum-checked: an
    # IN-ENUM inline literal here (e.g. structured-emitter's 'haiku') used to reach
    # neither loop's MISMATCH check.
    inline_pairs=$(
        grep -E "agentType: '[a-z0-9:-]+'" "$file" | while IFS= read -r line; do
            grep -qE "model: '($KNOWN_TIERS_RE)'" <<<"$line" || continue
            a=$(printf '%s' "$line" | sed -E "s/.*agentType: '([^']+)'.*/\1/")
            m=$(printf '%s' "$line" | sed -E "s/.*model: '($KNOWN_TIERS_RE)'.*/\1/")
            printf '%s\t%s\n' "$a" "$m"
        done | sort -u
    )
    while IFS=$'\t' read -r agent model; do
        [ -z "$agent" ] && continue
        check_pair "$agent" "$model" "$tbl (inline)"
    done <<< "$inline_pairs"
done

# --- Scalar tables: RETIRED. The registry held UNIT_TEST_MODEL (unit-tests.mjs)
# until #574 retired that engine, and the plan-reviewer scalar until #348 retired its
# dispatcher. Each spec was removed rather than made conditional — a missing table is
# MISSING-TABLE by design, so a dead spec would red every consumer. A future scalar
# carrier re-adds the registry loop this comment replaces (see git history for its
# shape: per-dispatch inline `model:` literals override the file scalar). ---

if [ ${#errors[@]} -gt 0 ]; then
    printf '%s\n' "${errors[@]}" >&2
    if [ $HOOK_MODE -eq 1 ]; then
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: "model-tier drift between a dev-pipeline .mjs table and agent frontmatter/override — see stderr. Run review-toolkit/scripts/check-model-tiers.sh to reproduce."
            }
        }'
        exit 0
    else
        exit 1
    fi
fi

exit 0
