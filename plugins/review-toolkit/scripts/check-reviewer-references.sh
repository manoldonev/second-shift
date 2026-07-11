#!/usr/bin/env bash
# Verify the review-lead reviewer registry stays in lockstep with the agent files
# that back it — now across TWO ROOTS after pluginization.
#
# Two-root contract
# -----------------
# The registry text lives in review-lead's SKILL.md, shipped by the review-toolkit
# PLUGIN. The agent files that back registered reviewers live in two places:
#   - PLUGIN root:   generic reviewers shipped with review-toolkit (<plugin>/agents/)
#   - CONSUMER root: repo-local domain reviewers the repo registers via config
#                    (<consumer>/.claude/agents/), declared in reviewers.add
#
# The effective registry a repo actually runs is:
#
#     effective_registry = plugin_registry (review-lead SKILL.md, plugin root)
#                        − config reviewers.remove
#                        + config reviewers.add   (each must resolve to a
#                                                   <consumer>/.claude/agents/<name>.md)
#
# Failure classes (each a distinct message, non-zero exit):
#   (a) DANGLING     — a registry entry has no agent file in EITHER root
#   (b) ORPHAN       — a consumer reviewer-shaped .claude/agents/*.md is registered
#                      nowhere (not in the effective registry; not skip-tagged)
#   (c) REMOVE-UNKNOWN — reviewers.remove names a reviewer the plugin registry never
#                      shipped (a stale/typo delta)
#   (d) SHADOW       — a consumer .claude/agents/<name>.md shadows a plugin-shipped
#                      agent name (the drift tripwire; see docs/namespaces.md rule 5)
# Plus DRIFT — the three registries inside SKILL.md itself disagree.
#
# Root resolution (env overrides win, for hermetic selftests):
#   PLUGIN root    = $SECOND_SHIFT_PLUGIN_ROOT   or  $SCRIPT_DIR/..
#   CONSUMER root  = $SECOND_SHIFT_REPO_ROOT     or  dirname of `git rev-parse
#                                                    --git-common-dir` from $PWD
#   config file    = $SECOND_SHIFT_CONFIG        or  <consumer>/.claude/second-shift.config.json
# Missing config = empty deltas (NOT an error). Missing consumer agents dir = fine.
#
# Modes:
#   - Standalone CLI: errors → stderr, exit 1 on drift, exit 0 if clean.
#   - PreToolUse hook (when invoked from settings.json with JSON stdin):
#     errors → stderr AND emit `permissionDecision: "deny"` JSON to stdout.

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
        # substring plus a `commit`/`commitSha` substring (e.g. a statectl call whose
        # inline `git -C <wt> rev-parse` + expanded JSON payload carry both). That
        # produced spurious denials on non-commit Bash calls (issue #208). The glob's
        # tokenization is engine-internal and unverifiable, so we self-gate here
        # instead of trusting it: allow (exit 0) unless the command actually invokes
        # `git ... commit` as a subcommand. Tolerates leading global option pairs
        # (`-c k=v`, `-C dir`, `--opt`) and requires `commit` as a token at a command
        # boundary, so `git -C <wt> rev-parse HEAD` and a bare `commitSha` substring
        # do NOT match. A commit inside command substitution (`$(git commit …)` or
        # backticks) is intentionally NOT detected (fail-open) — the pipeline never
        # commits that way, and CLI mode is the backstop. CLI mode (no stdin) is
        # unaffected and still runs the full check.
        CMD=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')
        printf '%s' "$CMD" | grep -Eq \
            '(^|[;&|]|&&|\|\|)[[:space:]]*git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--[^[:space:]]+))*[[:space:]]+commit([[:space:]]|$)' \
            || exit 0
    fi
fi

# --- Root resolution -------------------------------------------------------
PLUGIN_ROOT="${SECOND_SHIFT_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
PLUGIN_ROOT=$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd) || PLUGIN_ROOT=""
SKILL="$PLUGIN_ROOT/skills/review-lead/SKILL.md"
PLUGIN_AGENTS="$PLUGIN_ROOT/agents"

# Consumer root: env override, else the git repo containing $PWD.
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

# Config: env override, else consumer default. Missing = empty deltas (not error).
if [ -n "${SECOND_SHIFT_CONFIG:-}" ]; then
    CONFIG="$SECOND_SHIFT_CONFIG"
elif [ -n "$REPO_ROOT" ]; then
    CONFIG="$REPO_ROOT/.claude/second-shift.config.json"
else
    CONFIG=""
fi

# Nothing to check if the plugin's review-lead skill isn't present.
[ -f "$SKILL" ] || exit 0

# --- Parse the plugin registry from SKILL.md -------------------------------
# 1. Pre-flight enumeration — names in a single comma-separated parenthetical
#    after "the plugin-shipped panel (" (the registry sentence in
#    "## Pre-flight: dispatch substrate").
preflight=$(
    grep -oE 'the plugin-shipped panel \([^)]+\)' "$SKILL" \
        | grep -oE '[a-z][a-z0-9-]+-reviewer' \
        | sort -u
)

# 2. Reviewer Routing — **bold** registry entries between "## Reviewer Routing"
#    and the next top-level heading. Bold-only, deliberately: prose examples in
#    that section (e.g. the backticked `coaching-reviewer` in the repo-local
#    domain-reviewers row) illustrate consumer-registered reviewers and must not
#    parse into the plugin registry.
routing=$(
    awk '/^## Reviewer Routing/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -oE '\*\*[a-z][a-z0-9-]+-reviewer\*\*' \
        | tr -d '*' \
        | sort -u
)

# 3. Verdict table — first column of the verdict table block, human labels
#    mapped to canonical agent names.
verdict_labels=$(
    awk '/Verdict       \| Findings/{flag=1; next} flag && /^\|/{print; next} flag && !/^\|/{exit}' "$SKILL" \
        | sed -E 's/^\| *([^|]+) *\|.*/\1/' \
        | sed -E 's/[[:space:]]+$//' \
        | grep -v '^$'
)
verdict=$(
    echo "$verdict_labels" \
        | sed -E '
            s/^Scope Completeness$/scope-completeness-reviewer/;
            s/^Security$/security-reviewer/;
            s/^Performance$/performance-reviewer/;
            s/^Database$/db-reviewer/;
            s/^Complexity$/complexity-reviewer/;
            s/^Maintainability$/maintainability-reviewer/;
            s/^Test Coverage$/test-coverage-reviewer/;
            s/^Coaching$/coaching-reviewer/;
            s/^Pipeline$/pipeline-reviewer/;
            s/^Unit Test Mutation$/unit-test-mutation-reviewer/;
            s/^Design Faithful$/design-faithful-reviewer/;
            s/^Accessibility$/a11y-reviewer/;
        ' \
        | grep -E '^[a-z][a-z0-9-]+-reviewer$' \
        | sort -u
)

# Union of the three sub-registries = the plugin registry.
plugin_registry=$(printf '%s\n%s\n%s\n' "$preflight" "$routing" "$verdict" | sort -u | grep -v '^$' || true)

# --- Config deltas ---------------------------------------------------------
adds=""
removes=""
if [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
    adds=$(jq -r '.reviewers.add[]?.name // empty' "$CONFIG" 2>/dev/null | grep -v '^$' | sort -u)
    removes=$(jq -r '.reviewers.remove[]? // empty' "$CONFIG" 2>/dev/null | grep -v '^$' | sort -u)
fi

# effective_registry = (plugin_registry − removes) + adds
effective=$( { comm -23 <(printf '%s\n' "$plugin_registry") <(printf '%s\n' "$removes"); printf '%s\n' "$adds"; } | grep -v '^$' | sort -u )

errors=()

# --- DRIFT: the three sub-registries inside SKILL.md must agree ------------
diff_p_r=$(diff <(echo "$preflight") <(echo "$routing") || true)
diff_p_v=$(diff <(echo "$preflight") <(echo "$verdict") || true)
if [ -n "$diff_p_r" ]; then
    errors+=("DRIFT: Pre-flight enumeration vs Reviewer Routing differ:"$'\n'"$diff_p_r")
fi
if [ -n "$diff_p_v" ]; then
    errors+=("DRIFT: Pre-flight enumeration vs Verdict table differ:"$'\n'"$diff_p_v")
fi

# --- (c) REMOVE-UNKNOWN: every remove must name a plugin-shipped reviewer ---
while IFS= read -r r; do
    [ -z "$r" ] && continue
    grep -qx "$r" <<< "$plugin_registry" \
        || errors+=("REMOVE-UNKNOWN: reviewers.remove names '$r' but it is not a plugin-shipped reviewer (absent from the review-lead registry)")
done <<< "$removes"

# --- (a) DANGLING: every effective entry must resolve to an agent file ------
#     plugin-origin names resolve in EITHER root; reviewers.add names must
#     resolve in the CONSUMER root specifically.
while IFS= read -r name; do
    [ -z "$name" ] && continue
    if grep -qx "$name" <<< "$adds"; then
        if [ -z "$CONSUMER_AGENTS" ] || [ ! -f "$CONSUMER_AGENTS/$name.md" ]; then
            errors+=("DANGLING: reviewers.add registers '$name' but <consumer>/.claude/agents/$name.md does not exist")
        fi
    else
        if { [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_AGENTS/$name.md" ]; } \
           && { [ -z "$CONSUMER_AGENTS" ] || [ ! -f "$CONSUMER_AGENTS/$name.md" ]; }; then
            errors+=("DANGLING: review-lead registry references '$name' but no agent file exists in the plugin root ($PLUGIN_AGENTS) or the consumer root")
        fi
    fi
done <<< "$effective"

shopt -s nullglob

# --- (d) SHADOW: consumer files must not shadow a plugin-shipped agent name -
if [ -n "$CONSUMER_AGENTS" ] && [ -d "$CONSUMER_AGENTS" ] && [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_AGENTS" ]; then
    for f in "$CONSUMER_AGENTS"/*.md; do
        name=$(basename "$f" .md)
        if [ -f "$PLUGIN_AGENTS/$name.md" ]; then
            errors+=("SHADOW: consumer $CONSUMER_AGENTS/$name.md shadows plugin-shipped agent '$name' — remove or rename the consumer copy (drift tripwire; see docs/namespaces.md rule 5)")
        fi
    done
fi

# --- (b) ORPHAN: consumer reviewer-shaped files must be registered ----------
#     "reviewer-shaped" heuristic preserved from the single-root era: *-reviewer.md.
#     A file that shadows a plugin agent is reported by (d), not here.
if [ -n "$CONSUMER_AGENTS" ] && [ -d "$CONSUMER_AGENTS" ]; then
    for f in "$CONSUMER_AGENTS"/*-reviewer.md; do
        name=$(basename "$f" .md)
        if [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_AGENTS" ] && [ -f "$PLUGIN_AGENTS/$name.md" ]; then
            continue  # shadow case — owned by (d)
        fi
        if ! grep -qx "$name" <<< "$effective"; then
            if ! grep -q '<!-- review-lead-skip:' "$f"; then
                errors+=("ORPHAN: consumer reviewer '$name' ($CONSUMER_AGENTS/$name.md) is registered nowhere — add it to reviewers.add in the config or tag it with '<!-- review-lead-skip: ... -->'")
            fi
        fi
    done
fi

if [ ${#errors[@]} -gt 0 ]; then
    printf '%s\n\n' "${errors[@]}" >&2
    if [ $HOOK_MODE -eq 1 ]; then
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: "review-lead reviewer registry drift — see stderr for details. Run review-toolkit/scripts/check-reviewer-references.sh to reproduce."
            }
        }'
        exit 0
    else
        exit 1
    fi
fi

exit 0
