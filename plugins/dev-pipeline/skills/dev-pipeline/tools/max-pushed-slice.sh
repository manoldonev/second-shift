#!/usr/bin/env bash
# max-pushed-slice.sh — compute the highest pushed stacked-PR slice number for an
# issue from a list of git refs on stdin.
#
# Single source of truth for the slice-derivation parse used by BOTH:
#   - Stage 1 seeding (stages/1-intake.md — seed currentSlice when absent)
#   - Stage 2 stacked-PR resume sanity guard (stages/2-worktree.md — D1)
# Extracting it here removes the duplicated inline loop that previously carried a
# ref-parsing bug (`${ref##*/}` stripped the `claude/` prefix, so no ref ever
# matched and the result was always 0). See #147.
#
# The branch-name namespace is config-driven (tracker.branchPrefix): github lineage
# "claude/acme-", JIRA lineage a per-user "jdoe/". Pass it via $BRANCH_PREFIX;
# it defaults to "claude/acme-" so pre-config callers are unchanged.
#
# Usage:
#   BRANCH_PREFIX="$(jq -r '.tracker.branchPrefix // "claude/acme-"' "$CFG")"
#   git ls-remote --heads origin "${BRANCH_PREFIX}${KEY}*" | awk '{print $2}' \
#     | BRANCH_PREFIX="$BRANCH_PREFIX" bash .../tools/max-pushed-slice.sh "$KEY"
#
# Input  (stdin): one ref per line. Accepts full refs (`refs/heads/<prefix><key>`)
#                 or short names (`<prefix><key>`); the `refs/heads/` prefix is
#                 stripped if present. Non-matching lines are ignored.
# Arg 1:          the ticket key (github issue number or JIRA key).
# Env:            BRANCH_PREFIX — branch namespace prepended to the key
#                 (default "claude/acme-"). Should be regex-safe (branch prefixes
#                 are typically [a-z0-9/-]).
# Output (stdout): the highest pushed slice number — the unsuffixed branch
#                 `<prefix><key>` counts as slice 1, `…-pr<N>` as slice N.
#                 Prints `0` when no matching ref is present (fresh / nothing pushed).
# Exit:           0 on success; 2 on a usage error (missing ticket key).
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible (the selftest
# drift-check runs there).

set -uo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "[max-pushed-slice] usage: max-pushed-slice.sh <ticket-key> (refs on stdin)" >&2
  exit 2
fi
PREFIX="${BRANCH_PREFIX:-claude/acme-}"

MAX=0
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  # Strip ONLY the refs/heads/ prefix (if present) — keep the `<prefix>/...` segment.
  name="${ref#refs/heads/}"
  if [[ "$name" == "${PREFIX}${ISSUE}" ]]; then
    (( MAX < 1 )) && MAX=1
  elif [[ "$name" =~ ^${PREFIX}${ISSUE}-pr([0-9]+)$ ]]; then
    n="${BASH_REMATCH[1]}"
    (( n > MAX )) && MAX=$n
  fi
done

echo "$MAX"
