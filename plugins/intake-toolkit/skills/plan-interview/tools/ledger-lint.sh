#!/usr/bin/env bash
# ledger-lint.sh — deterministic structural lint for the Decision Ledger
# section of an implementation plan (contract: interviewing-baseline skill).
#
# Usage: ledger-lint.sh <plan-path>
#
# Checks (read-only, pure bash — no network, no writes):
#   1. A `## Decision Ledger` section header is present (any heading level,
#      or a bold-line header), case-insensitive.
#   2. The section carries EITHER the explicit empty form
#      `No material decisions — all choices codebase-derived.`
#      OR at least one `| D-n |` table row.
#   3. Every `| D-n |` row has 4 columns, a non-empty Decision cell, a
#      non-empty Resolution cell, and a Provenance cell from the closed enum
#      `user-answered | user-delegated | codebase-derived | deferred |
#      ticket-sourced`. (`assumed` is deliberately NOT legal — ask, ground,
#      or defer.)
#   4. A `ticket-sourced` row cites its source comment: the Resolution cell
#      must contain an `https://` URL. Tracker-neutral by design — the repo
#      models `tracker.type` as github|jira, so this is deliberately NOT a
#      github.com-shaped pattern.
#   5. No duplicate D-n ids.
#
# Scope honesty: this lint buys structural presence + on-page disclosure,
# NOT decision quality — a load-bearing decision missing from the ledger
# entirely is the plan-reviewer's judgment call, not this script's.
#
# Exit: 0 clean, 1 violations (each named on stderr), 2 usage/IO error.
set -euo pipefail

PLAN="${1:-}"

[[ -n "$PLAN" ]] || { echo "ledger-lint: usage: ledger-lint.sh <plan-path>" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "ledger-lint: plan file not found: $PLAN" >&2; exit 2; }

VIOLATIONS=0
violate() { echo "ledger-lint: VIOLATION: $1" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }

# mirror of interviewing-baseline provenance enum — keep verbatim
PROVENANCE_ENUM='user-answered|user-delegated|codebase-derived|deferred|ticket-sourced'
EMPTY_FORM='No material decisions — all choices codebase-derived.'

# quoting-safe whitespace trim — xargs aborts on quotes/apostrophes/backslashes in cells
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---- Check 1: section header -------------------------------------------------
if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$PLAN"; then
  violate "missing mandated section: Decision Ledger (run plan-interview; trivial work uses the explicit empty form)"
  echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi

# ---- Check 2/3: rows or explicit empty form ----------------------------------
ROW_COUNT=0
declare -a ROW_IDS=()

while IFS= read -r line; do
  masked="${line//\\|/__LEDGER_LINT_PIPE__}"
  IFS='|' read -r -a cells <<< "$masked"
  # 4-column row splits into: leading-empty, id, decision, resolution, provenance[, trailing-empty]
  if (( ${#cells[@]} < 5 || ${#cells[@]} > 6 )); then
    violate "malformed ledger row (expected 4 columns: ID | Decision | Resolution | Provenance): $line"
    continue
  fi
  id="$(trim "${cells[1]}")"
  decision="$(trim "${cells[2]}")"
  resolution="$(trim "${cells[3]}")"
  provenance="$(trim "${cells[4]}")"
  ROW_IDS+=("$id")
  ROW_COUNT=$((ROW_COUNT + 1))
  [[ -n "$decision" ]] || violate "$id row has an empty Decision cell"
  [[ -n "$resolution" ]] || violate "$id row has an empty Resolution cell"
  if ! [[ "$provenance" =~ ^(${PROVENANCE_ENUM})$ ]]; then
    violate "$id row: provenance '$provenance' not in {${PROVENANCE_ENUM//|/ | }} ('assumed' is not legal — ask, ground, or defer)"
  fi
  # Check 4: a ticket-sourced row must cite the comment it adopted. Without the
  # citation the value is indistinguishable from an assumption, which is the
  # failure mode the closed enum exists to prevent. Tracker-neutral on purpose.
  if [[ "$provenance" == "ticket-sourced" && "$resolution" != *"https://"* ]]; then
    violate "$id row: 'ticket-sourced' provenance requires the Resolution cell to cite the source comment by URL (https://...)"
  fi
done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$PLAN" || true)

if (( ROW_COUNT == 0 )); then
  grep -qF "$EMPTY_FORM" "$PLAN" || \
    violate "Decision Ledger has no rows and no explicit empty form ('$EMPTY_FORM')"
fi

# ---- Check 4: duplicate ids ---------------------------------------------------
if (( ${#ROW_IDS[@]} > 0 )); then
  dupes=$(printf '%s\n' "${ROW_IDS[@]}" | sort | uniq -d)
  [[ -z "$dupes" ]] || violate "duplicate ledger rows for: $(echo "$dupes" | tr '\n' ' ')"
fi

echo "ledger-lint: ${ROW_COUNT} ledger row(s)"
if (( VIOLATIONS > 0 )); then
  echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "ledger-lint: OK"
exit 0
