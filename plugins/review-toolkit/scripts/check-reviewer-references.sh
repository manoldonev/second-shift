#!/usr/bin/env bash
# Verify the review-lead reviewer registry stays in lockstep with the agent files
# that back it — now across THREE ROOTS after pluginization.
#
# Three-root contract
# -------------------
# The registry text lives in review-lead's SKILL.md, shipped by the review-toolkit
# PLUGIN. The agent files that back registered reviewers live in three places:
#   - PLUGIN root:   generic reviewers shipped with review-toolkit (<plugin>/agents/)
#   - DESIGN root:   the design-fidelity reviewers, shipped by the SIBLING
#                    design-toolkit plugin (<design-toolkit>/agents/). The panel
#                    names them because review-lead routes the design-fidelity
#                    dimension, but review-toolkit does not ship them.
#   - CONSUMER root: repo-local domain reviewers the repo registers via config
#                    (<consumer>/.claude/agents/), declared in reviewers.add
#
# design-toolkit is OPTIONAL. When it is not installed the sibling root resolves
# empty, and the panel names it ships are EXEMPT from DANGLING — a printed notice,
# never a commit denial. Without that exemption every consumer that runs
# review-toolkit without design-toolkit would be commit-blocked by a panel entry it
# never asked for. Which names are design-toolkit-shipped is DECLARED below rather
# than derived from disk: when the root resolves empty there is nothing to derive
# from, and that is exactly the case the exemption has to serve.
#
# The effective registry a repo actually runs is:
#
#     effective_registry = plugin_registry (review-lead SKILL.md, plugin root)
#                        − config reviewers.remove
#                        + config reviewers.add   (each must resolve to a
#                                                   <consumer>/.claude/agents/<name>.md)
#
# Failure classes (each a distinct message, non-zero exit):
#   (a) DANGLING     — a registry entry has no agent file in ANY of the three roots
#   (b) ORPHAN       — a consumer reviewer-shaped .claude/agents/*.md is registered
#                      nowhere (not in the effective registry; not skip-tagged)
#   (c) REMOVE-UNKNOWN — reviewers.remove names a reviewer the plugin registry never
#                      shipped (a stale/typo delta)
#   (d) SHADOW       — a consumer .claude/agents/<name>.md shadows a plugin-shipped
#                      agent name (the drift tripwire; see docs/namespaces.md rule 5)
#   (e) QUALIFY      — a panel entry backed by a PLUGIN agent file is not spelled with
#                      that plugin's prefix, or a reviewers.add name IS prefixed
#                      (docs/namespaces.md rule 2). The panel is a DISPATCH list: its
#                      names reach agent({agentType}) through code-review.mjs, so a bare
#                      plugin name there is an agent type that does not resolve and the
#                      whole fan-out dies. Those deaths return in the died-after-retry
#                      shape, which synthesis renders as a fully dark panel — a review
#                      that reviewed nothing, reported as a coverage gap rather than as
#                      a broken dispatch. The failure is silent by construction, which
#                      is why it needs a pre-commit gate rather than a runtime one.
#                      The expected prefix is DERIVED from the resolving root's own
#                      .claude-plugin/plugin.json `name`, never hardcoded.
# Plus DRIFT — the three registries inside SKILL.md itself disagree.
#
# Root resolution (env overrides win, for hermetic selftests):
#   PLUGIN root    = $SECOND_SHIFT_PLUGIN_ROOT   or  $SCRIPT_DIR/..
#   DESIGN root    = $SECOND_SHIFT_DESIGN_TOOLKIT_ROOT  or the sibling design-toolkit
#                                                    plugin dir (repo or cache layout)
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

# Sibling design-toolkit root. Two on-disk layouts exist — mirrors
# check-model-tiers.sh's resolve_sibling_plugin_root verbatim:
#   marketplace repo:  plugins/review-toolkit/scripts -> ../../design-toolkit
#   installed cache:   cache/<mkt>/review-toolkit/<ver>/scripts
#                        -> ../../../design-toolkit/<ver>  (versioned siblings)
# Env override wins; otherwise repo layout, then the newest cache sibling that
# actually carries an agents/ dir. Resolves EMPTY when design-toolkit is absent.
resolve_design_toolkit_root() {
    local override="${SECOND_SHIFT_DESIGN_TOOLKIT_ROOT:-}"
    if [ -n "$override" ]; then
        (cd "$override" 2>/dev/null && pwd)
        return
    fi
    local cand
    cand=$(cd "$SCRIPT_DIR/../../design-toolkit" 2>/dev/null && pwd) || cand=""
    if [ -n "$cand" ] && [ -d "$cand/agents" ]; then
        echo "$cand"
        return
    fi
    for cand in "$SCRIPT_DIR"/../../../design-toolkit/*/; do
        [ -d "$cand/agents" ] || continue
        (cd "$cand" && pwd)
    done | tail -1
}
DESIGN_TOOLKIT_ROOT=$(resolve_design_toolkit_root)
DESIGN_AGENTS="${DESIGN_TOOLKIT_ROOT:+$DESIGN_TOOLKIT_ROOT/agents}"
[ -n "$DESIGN_AGENTS" ] && [ -d "$DESIGN_AGENTS" ] || DESIGN_AGENTS=""

# Panel names shipped by design-toolkit, not review-toolkit. See the three-root
# contract above for why this is declared rather than derived.
DESIGN_TOOLKIT_PANEL='design-faithful-reviewer
figma-faithful-reviewer'

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

# Standalone adoption (#14, F17): in HOOK mode with NO consumer second-shift config,
# the reviewer-registry lockstep contract is not in force — a repo that adopts
# review-toolkit alone (no dev-pipeline, no config) must not have its commits denied.
# Fail OPEN (allow the commit); the orphan/shadow deny loops below apply only to
# onboarded repos. The standalone CLI path still runs the checks (advisory).
if [ "$HOOK_MODE" -eq 1 ] && { [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; }; then
    echo "[check-reviewer-references] no second-shift config — standalone repo, hook allows the commit (checks run only when onboarded)." >&2
    exit 0
fi

# --- Parse the plugin registry from SKILL.md -------------------------------
# 1. Pre-flight enumeration — names in a single comma-separated parenthetical
#    after "the plugin-shipped panel (" (the registry sentence in
#    "## Pre-flight: dispatch substrate").
preflight=$(
    grep -oE 'the plugin-shipped panel \([^)]+\)' "$SKILL" \
        | grep -oE '[a-z][a-z0-9-]+-reviewer' \
        | sort -u
)

# 1b. The SAME parenthetical, entries kept WHOLE so a `plugin:` prefix survives.
#     Every other consumer of the panel wants bare names and gets them from $preflight
#     above (which strips prefixes as a side effect of its -oE pattern — the property
#     that lets the panel be qualified without touching DRIFT or _effective-registry.sh).
#     Failure class (e) is the one reader for which the prefix IS the subject, so it
#     needs its own parse rather than a re-derivation from the stripped set.
preflight_raw=$(
    grep -oE 'the plugin-shipped panel \([^)]+\)' "$SKILL" \
        | sed -E 's/^the plugin-shipped panel \(//; s/\)$//' \
        | tr ',' '\n' \
        | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -E '^([a-z][a-z0-9-]*:)?[a-z][a-z0-9-]+-reviewer$' \
        | sort -u
)

# The `<plugin>` half of a `<plugin>:<agent>` reference, read from the root's OWN manifest.
# Derived rather than hardcoded because it has to be right in both on-disk layouts, and the
# installed-cache layout puts the VERSION in the root's basename
# (cache/<marketplace>/<plugin>/<version>/) — a basename heuristic would read "4.0.0" as the
# plugin name and deny every consumer commit. Returns non-zero when the manifest is missing
# or unreadable; the caller degrades to a printed notice rather than guessing a prefix.
plugin_name_of() {
    local root="$1" n
    [ -n "$root" ] && [ -f "$root/.claude-plugin/plugin.json" ] || return 1
    n=$(jq -r '.name // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null) || return 1
    [ -n "$n" ] || return 1
    printf '%s\n' "$n"
}

# 2. Reviewer Routing — **bold** registry entries between "## Reviewer Routing"
#    and the next top-level heading. Bold-only, deliberately: prose examples in
#    that section (e.g. the backticked `orders-reviewer` in the repo-local
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
            s/^Orders$/orders-reviewer/;
            s/^Pipeline$/pipeline-reviewer/;
            s/^Unit Test Mutation$/unit-test-mutation-reviewer/;
            s/^Design Faithful$/design-faithful-reviewer/;
            s/^Figma Faithful$/figma-faithful-reviewer/;
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
#     plugin-origin names resolve in ANY of the three roots; reviewers.add names
#     must resolve in the CONSUMER root specifically. A design-toolkit-shipped
#     panel name with design-toolkit NOT installed is exempt and noticed instead.
exempt_design=()
while IFS= read -r name; do
    [ -z "$name" ] && continue
    if grep -qx "$name" <<< "$adds"; then
        if [ -z "$CONSUMER_AGENTS" ] || [ ! -f "$CONSUMER_AGENTS/$name.md" ]; then
            errors+=("DANGLING: reviewers.add registers '$name' but <consumer>/.claude/agents/$name.md does not exist")
        fi
        continue
    fi
    if { [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_AGENTS/$name.md" ]; } \
       || { [ -n "$DESIGN_AGENTS" ] && [ -f "$DESIGN_AGENTS/$name.md" ]; } \
       || { [ -n "$CONSUMER_AGENTS" ] && [ -f "$CONSUMER_AGENTS/$name.md" ]; }; then
        continue
    fi
    if [ -z "$DESIGN_AGENTS" ] && grep -qx "$name" <<< "$DESIGN_TOOLKIT_PANEL"; then
        exempt_design+=("$name")
        continue
    fi
    errors+=("DANGLING: review-lead registry references '$name' but no agent file exists in the review-toolkit root ($PLUGIN_AGENTS), the design-toolkit root (${DESIGN_AGENTS:-<not installed>}), or the consumer root")
done <<< "$effective"

if [ ${#exempt_design[@]} -gt 0 ]; then
    echo "[check-reviewer-references] notice: design-toolkit is not installed — the design-fidelity dimension will not run, and its panel entries (${exempt_design[*]}) are exempt from DANGLING." >&2
fi

# --- (e) QUALIFY: plugin-backed panel entries carry their plugin's prefix ----
#     Scoped to the pre-flight panel deliberately. It is the only sub-registry whose
#     entries are DISPATCH names; the Routing sub-registry's parse anchors
#     `\*\*[a-z][a-z0-9-]+-reviewer\*\*`, which a qualified name does not match (so
#     qualifying it would empty that set and fire DRIFT), and the Verdict table's first
#     column carries human display labels that are sed-mapped to agent names below.
unqualified_roots=""
while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    case "$raw" in
        *:*) entry_prefix="${raw%%:*}"; entry_bare="${raw##*:}" ;;
        *)   entry_prefix="";           entry_bare="$raw" ;;
    esac
    # A consumer-registered name is governed by the reviewers.add loop below, not here.
    grep -qx "$entry_bare" <<< "$adds" && continue
    if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_AGENTS/$entry_bare.md" ]; then
        origin_root="$PLUGIN_ROOT"
    elif [ -n "$DESIGN_AGENTS" ] && [ -f "$DESIGN_AGENTS/$entry_bare.md" ]; then
        origin_root="$DESIGN_TOOLKIT_ROOT"
    else
        # Backed by no plugin root: DANGLING already reported it, or the
        # design-toolkit-absent exemption already noticed it (with the root unresolvable
        # there is no manifest to derive a prefix from), or it resolves only in the
        # consumer root — which (b) ORPHAN and (d) SHADOW own.
        continue
    fi
    expected=$(plugin_name_of "$origin_root") || {
        unqualified_roots="$unqualified_roots$origin_root"$'\n'
        continue
    }
    [ "$entry_prefix" = "$expected" ] && continue
    if [ -z "$entry_prefix" ]; then
        errors+=("QUALIFY: review-lead panel entry '$raw' is backed by the '$expected' plugin but is named BARE — panel names are dispatch names, so this one does not resolve at agent() and takes the whole fan-out dark. Write '$expected:$entry_bare' (docs/namespaces.md rule 2)")
    else
        errors+=("QUALIFY: review-lead panel entry '$raw' carries the prefix '$entry_prefix' but its agent file resolves in the '$expected' plugin — write '$expected:$entry_bare' (docs/namespaces.md rule 2)")
    fi
done <<< "$preflight_raw"

if [ -n "$unqualified_roots" ]; then
    echo "[check-reviewer-references] notice: no readable .claude-plugin/plugin.json under $(printf '%s' "$unqualified_roots" | sort -u | tr '\n' ' ')— panel entries backed there are exempt from QUALIFY (their plugin prefix cannot be derived)." >&2
fi

# --- (f) reviewers.add names stay BARE --------------------------------------
#     The other half of rule 2, and the reason the panel's qualification is safe: bareness
#     is what distinguishes a repo-local agent from a plugin-shipped one. A prefixed add
#     name also cannot resolve — DANGLING looks for <consumer>/.claude/agents/<name>.md —
#     but the DANGLING message points at a missing file rather than at the prefix.
while IFS= read -r a; do
    [ -z "$a" ] && continue
    case "$a" in
        *:*) errors+=("QUALIFY: reviewers.add registers '$a' with a plugin prefix — repo-local reviewers are referenced BARE (that bareness is the disambiguation from plugin-shipped names; docs/namespaces.md rule 2)") ;;
    esac
done <<< "$adds"

shopt -s nullglob

# --- (d) SHADOW: consumer files must not shadow a plugin-shipped agent name -
#     Design-toolkit-shipped names are tested by DESIGN_TOOLKIT_PANEL membership,
#     NOT by file presence in $DESIGN_AGENTS: the tripwire must still fire when
#     design-toolkit is absent. Otherwise registering those names in the panel
#     would silently retire the tripwire for exactly them — the consumer copy
#     resolves DANGLING through the consumer-root clause and escapes ORPHAN by
#     being in $effective, so it would be accepted with no error and no notice.
if [ -n "$CONSUMER_AGENTS" ] && [ -d "$CONSUMER_AGENTS" ] && [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_AGENTS" ]; then
    for f in "$CONSUMER_AGENTS"/*.md; do
        name=$(basename "$f" .md)
        if [ -f "$PLUGIN_AGENTS/$name.md" ] || grep -qx "$name" <<< "$DESIGN_TOOLKIT_PANEL"; then
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
