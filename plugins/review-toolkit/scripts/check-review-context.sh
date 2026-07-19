#!/usr/bin/env bash
# Verify the per-reviewer review-context extension surface: every file under a
# consumer repo's .claude/second-shift/review-context/ must be named after a
# reviewer in the EFFECTIVE registry, so a typo'd basename is loud instead of
# silently read by nobody (each reviewer self-loads exactly
# review-context/<its-own-name>.md; there is no dispatch-time slicing).
#
#     effective_registry = plugin_registry (review-lead SKILL.md, plugin root)
#                        − config reviewers.remove
#                        + config reviewers.add
#
# Registry extraction mirrors check-reviewer-references.sh (the plugin-shipped
# panel enumeration in review-lead SKILL.md) — keep the two in lockstep.
# check-extensions.sh (dev-pipeline) owns the shallower existence contract
# (the review-context/*.md manifest glob); this script owns basename↔registry.
#
# Failure classes (distinct message, non-zero exit):
#   UNKNOWN-REVIEWER-FILE — basename matches no effective-registry reviewer
#   NOT-MARKDOWN          — a non-.md file under review-context/
#
# Root resolution (env overrides win, for hermetic selftests):
#   PLUGIN root    = $SECOND_SHIFT_PLUGIN_ROOT   or  $SCRIPT_DIR/..
#   CONSUMER root  = $1                           or  $SECOND_SHIFT_REPO_ROOT
#                                                 or  dirname of `git rev-parse
#                                                     --git-common-dir` from $PWD
#   config file    = $SECOND_SHIFT_CONFIG        or  <consumer>/.claude/second-shift.config.json
# Missing review-context/ dir = clean (extension surface unused). Missing
# config = empty deltas. Absent jq = registry deltas skipped with a warning
# (plugin panel still enforced).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SECOND_SHIFT_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
SKILL="$PLUGIN_ROOT/skills/review-lead/SKILL.md"

if [ $# -ge 1 ] && [ -n "$1" ]; then
    CONSUMER_ROOT="$1"
elif [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then
    CONSUMER_ROOT="$SECOND_SHIFT_REPO_ROOT"
else
    CONSUMER_ROOT="$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .)")"
fi

RC_DIR="$CONSUMER_ROOT/.claude/second-shift/review-context"
[ -d "$RC_DIR" ] || { echo "check-review-context: clean (no review-context/ dir)"; exit 0; }

[ -f "$SKILL" ] || { echo "check-review-context: ERROR — review-lead SKILL.md not found at $SKILL" >&2; exit 1; }

CONFIG="${SECOND_SHIFT_CONFIG:-$CONSUMER_ROOT/.claude/second-shift.config.json}"
# jq-absence WARN kept here (the shared helper is silent about it) for behavior parity.
if [ -f "$CONFIG" ] && ! command -v jq >/dev/null 2>&1; then
    echo "check-review-context: WARN — jq unavailable; config reviewer deltas not applied" >&2
fi

# Effective registry (plugin panel ± config deltas) — the single source of truth shared
# with check-review-context-sections.sh (avoids a divergent second copy of the extraction).
# shellcheck source=_effective-registry.sh
. "$SCRIPT_DIR/_effective-registry.sh"
effective="$(compute_effective_registry "$SKILL" "$CONFIG")" \
    || { echo "check-review-context: ERROR — could not parse the plugin panel from $SKILL" >&2; exit 1; }

errors=()
while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    case "$base" in
        *.md) name="${base%.md}"
              grep -qx "$name" <<< "$effective" \
                  || errors+=("UNKNOWN-REVIEWER-FILE: review-context/$base matches no reviewer in the effective registry (panel ± config deltas) — a typo'd name is read by nobody") ;;
        *)    errors+=("NOT-MARKDOWN: review-context/$base — only <reviewer-name>.md files belong here") ;;
    esac
done < <(find "$RC_DIR" -maxdepth 1 -type f -print0)

if [ ${#errors[@]} -gt 0 ]; then
    printf '%s\n' "${errors[@]}" >&2
    exit 1
fi
echo "check-review-context: clean"
