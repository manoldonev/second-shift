#!/usr/bin/env bash
# Verify the model tier each dev-pipeline .mjs dispatch table declares stays in
# lockstep with the dispatched agent's effective model — now across TWO ROOTS and
# with config overrides, after pluginization.
#
# Why this matters: each agent's model tier is the source of truth in its
# `<name>.md` frontmatter, but the Workflow .mjs scripts can't read files, so they
# RE-STATE the tier in a table and pass `model` explicitly. The .mjs value wins at
# runtime — so a frontmatter downgrade that misses the table keeps dispatching the
# more expensive model, silently (cost-increasing drift). This check fails the
# commit when a table and the agent's effective model disagree.
#
# Effective model precedence: config reviewers.modelOverrides > agent frontmatter.
# (Observed need: security-reviewer runs opus in one repo, sonnet in another, from
# the same plugin-shipped agent file — reconciled by a per-repo override.)
#
# Two-root contract
# -----------------
#   .mjs tables      live in the dev-pipeline PLUGIN:
#                    $SECOND_SHIFT_DEV_PIPELINE_ROOT (or $SCRIPT_DIR/../../dev-pipeline)
#                      /skills/dev-pipeline/workflows/
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
# Tables validated (unchanged from the single-root era):
#   - map  REVIEWER_MODEL  in workflows/code-review.mjs
#   - map  INTAKE_MODEL    in workflows/intake-review.mjs
#   - map  DESIGN_MODEL    in workflows/design-sync.mjs
#   - scalar UNIT_TEST_MODEL     in workflows/unit-tests.mjs   (per dispatched agentType)
#   - scalar PLAN_REVIEWER_MODEL in workflows/plan-review.mjs  (same shape)
#   - scalar EXECUTOR_MODEL      in workflows/mutation-gate.mjs (anonymous executors —
#     asserted against dev-pipeline SKILL.md's Model Tiering note instead)
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
    # Cache layout: pick the lexically-newest version dir with the marker path.
    for cand in "$SCRIPT_DIR"/../../../"$name"/*/; do
        [ -d "$cand/$marker" ] || continue
        (cd "$cand" && pwd)
    done | tail -1
}
DEV_PIPELINE_ROOT=$(resolve_sibling_plugin_root dev-pipeline "skills/dev-pipeline/workflows" "${SECOND_SHIFT_DEV_PIPELINE_ROOT:-}")
WF="$DEV_PIPELINE_ROOT/skills/dev-pipeline/workflows"
skill_md="$DEV_PIPELINE_ROOT/skills/dev-pipeline/SKILL.md"

# design-toolkit plugin root -> design-faithful agent-family frontmatter
# (design-sync.mjs / code-review.mjs tables reference these agents, which ship
# in design-toolkit, not review-toolkit). Optional: a consumer without the
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
    msg="UNLOCATABLE: dev-pipeline workflow tables not found via env override, repo-layout sibling ($SCRIPT_DIR/../../dev-pipeline), or cache-layout siblings ($SCRIPT_DIR/../../../dev-pipeline/<ver>) — expected <root>/skills/dev-pipeline/workflows. Set SECOND_SHIFT_DEV_PIPELINE_ROOT to the dev-pipeline plugin root."
    printf '%s\n' "$msg" >&2
    if [ $HOOK_MODE -eq 1 ]; then
        jq -n --arg r "$msg" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: $r
            }
        }'
        exit 0
    fi
    exit 1
fi

errors=()

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
# Precedence: modelOverride > frontmatter. Agent name compared bare.
check_pair() {
    local raw="$1" table_model="$2" table="$3"
    local agent file fm ov expected src
    agent=$(bare "$raw")
    ov=$(override_model "$agent")
    if [ -n "$ov" ]; then
        expected="$ov"; src="modelOverride"
    else
        file=$(agent_file "$agent")
        if [ -z "$file" ]; then
            errors+=("DANGLING: $table declares '$agent' => '$table_model' but no agent file exists in the review-toolkit root ($PLUGIN_AGENTS), the design-toolkit root (${DESIGN_AGENTS:-<not installed>}), or the consumer root, and reviewers.modelOverrides has no entry")
            return
        fi
        fm=$(frontmatter_model "$file")
        if [ -z "$fm" ]; then
            errors+=("NO-FRONTMATTER: $table declares '$agent' => '$table_model' but $file has no 'model:' field (and reviewers.modelOverrides has no entry)")
            return
        fi
        expected="$fm"; src="frontmatter"
    fi
    if [ "$expected" != "$table_model" ]; then
        errors+=("MISMATCH: '$agent' — $src says '$expected' but $table says '$table_model' (expected '$expected')")
    fi
}

# --- Map tables: 'agent': 'model' entries (agent may be plugin:-qualified). ---
for tbl in code-review.mjs intake-review.mjs design-sync.mjs; do
    file="$WF/$tbl"
    [ -f "$file" ] || { errors+=("MISSING-TABLE: $file not found"); continue; }
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        agent=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\1/")
        model=$(printf '%s' "$pair" | sed -E "s/^'([^']+)': '([^']+)'$/\2/")
        check_pair "$agent" "$model" "$tbl"
    done <<< "$(grep -oE "'[a-z0-9:-]+': '(opus|sonnet|haiku)'" "$file")"
done

# --- Scalar tables: const <VAR> = '<model>' applied to each agentType the file
#     dispatches (agentType may be plugin:-qualified). Pairs are "<file>:<VAR>". ---
for spec in "unit-tests.mjs:UNIT_TEST_MODEL" "plan-review.mjs:PLAN_REVIEWER_MODEL"; do
    tbl="${spec%%:*}"
    var="${spec#*:}"
    file="$WF/$tbl"
    if [ ! -f "$file" ]; then
        errors+=("MISSING-TABLE: $file not found")
        continue
    fi
    scalar_model=$(grep -oE "const $var = '(opus|sonnet|haiku)'" "$file" \
        | sed -E "s/.*'([^']+)'.*/\1/")
    if [ -z "$scalar_model" ]; then
        errors+=("PARSE: could not resolve $var in $file")
    else
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            check_pair "$agent" "$scalar_model" "$tbl ($var)"
        done <<< "$(grep -oE "agentType: '[a-z0-9:-]+'" "$file" | sed -E "s/agentType: '([^']+)'/\1/" | sort -u)"
    fi
done

# --- EXECUTOR_MODEL (mutation-gate.mjs): a constrained scalar with NO agent
#     frontmatter counterpart — the executors are anonymous agent() calls. Assert
#     (a) the constant parses as a known tier, and (b) it equals the tier the
#     dev-pipeline SKILL.md Model Tiering note states for the executors. ---
mg="$WF/mutation-gate.mjs"
if [ -f "$mg" ]; then
    mg_model=$(grep -oE "const EXECUTOR_MODEL = '(opus|sonnet|haiku)'" "$mg" \
        | sed -E "s/.*'([^']+)'.*/\1/")
    if [ -z "$mg_model" ]; then
        errors+=("PARSE: could not resolve EXECUTOR_MODEL in $mg (must be a literal opus|sonnet|haiku)")
    elif [ -f "$skill_md" ]; then
        skill_note=$(grep -oE "mutation-gate executors: (opus|sonnet|haiku)" "$skill_md" \
            | sed -E "s/.*: //" | head -1)
        if [ -z "$skill_note" ]; then
            errors+=("PARSE: SKILL.md Model Tiering has no 'mutation-gate executors: <tier>' note to lockstep EXECUTOR_MODEL against")
        elif [ "$mg_model" != "$skill_note" ]; then
            errors+=("MISMATCH: 'mutation-gate executors' — SKILL.md says '$skill_note' but mutation-gate.mjs (EXECUTOR_MODEL) says '$mg_model'")
        fi
    fi
fi

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
