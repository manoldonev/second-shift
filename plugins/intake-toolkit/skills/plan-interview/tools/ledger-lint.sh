#!/usr/bin/env bash
# ledger-lint.sh — deterministic structural lint for the Decision Ledger
# section of an implementation plan (contract: interviewing-baseline skill).
#
# Usage: ledger-lint.sh [--receipt] <plan-path>
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
# RECEIPT MODE (`--receipt`) adds the ratification bar. An INTAKE receipt is a
# stronger artifact than an in-plan ledger: it is what a build run is handed as
# the definition of settled intent, so it has to distinguish a decision the
# human made from a fact somebody derived. Provenance alone cannot express that
# — the failure mode is a row that resolves intent while wearing a
# `codebase-derived` label, so any rule keyed on provenance is circular. Receipt
# rows therefore carry a fifth `Kind` cell over a closed three-value enum:
#
#   intent  the human resolved it        provenance: user-answered, user-delegated
#   fact    derived from code or ticket  provenance: codebase-derived, ticket-sourced
#   open    parked                       provenance: deferred, and the Resolution
#                                        must cite an OR-n declared in the receipt's
#                                        `## Open Regions` section
#
# The provenance enum below is UNTOUCHED by this mode: receipt mode extends
# behavior, it does not fork the vocabulary the lockstep manifest pins.
#
# The Kind cell is receipt-mode ONLY. Without `--receipt` this script still
# requires exactly four columns, so plan-lint.sh, exitplan-ledger-gate.sh and
# every in-plan Decision Ledger see no schema change at all.
#
# Scope honesty: this lint buys structural presence + on-page disclosure,
# NOT decision quality — a load-bearing decision missing from the ledger
# entirely is the plan-reviewer's judgment call, not this script's. Receipt mode
# does not raise that ceiling: it makes an UNDISCLOSED parked decision a lint
# error; it cannot make an unasked question findable.
#
# Exit: 0 clean, 1 violations (each named on stderr), 2 usage/IO error.
set -euo pipefail

RECEIPT=0
PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --receipt) RECEIPT=1; shift ;;
    -h|--help) sed -n '2,51p' "$0"; exit 0 ;;
    -*) echo "ledger-lint: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$PLAN" ]] || { echo "ledger-lint: unexpected argument: $1" >&2; exit 2; }
      PLAN="$1"; shift ;;
  esac
done

[[ -n "$PLAN" ]] || { echo "ledger-lint: usage: ledger-lint.sh [--receipt] <plan-path>" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "ledger-lint: plan file not found: $PLAN" >&2; exit 2; }

VIOLATIONS=0
violate() { echo "ledger-lint: VIOLATION: $1" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }

# mirror of interviewing-baseline provenance enum — keep verbatim.
# Mechanical canonical of TWO lockstep pairs (scripts/lockstep-manifest.tsv):
# plan-lint.sh's PROVENANCE_ENUM copies this literal verbatim, and its HUMAN_PROVENANCE
# is a subset of it. Nothing may sit between the markers below — verbatim compares the
# whole block.
# LOCKSTEP-BEGIN provenance-enum
PROVENANCE_ENUM='user-answered|user-delegated|codebase-derived|deferred|ticket-sourced'
# LOCKSTEP-END provenance-enum
EMPTY_FORM='No material decisions — all choices codebase-derived.'

# Receipt-mode vocabulary. Single-sited on purpose: nothing else copies these, so
# they need no lockstep row. The merge-boundary gate reads the intent-gap record's
# `ratified:` key and deliberately does NOT re-validate dispositions — a second
# copy of an enum is duplicate machinery, which this repo's manifest calls worse
# than none.
KIND_ENUM='intent|fact|open'
INTENT_PROVENANCE='user-answered|user-delegated'
FACT_PROVENANCE='codebase-derived|ticket-sourced'
DISPOSITION_ENUM='pause-and-ask|reversible-default-and-flag'
OPEN_EMPTY_FORM='No open regions — every decision in scope is ratified.'

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
declare -a OPEN_CITATIONS=()

# An N-column row splits into N+1 cells: the leading empty before the first pipe,
# then one per column. A row with trailing whitespace after the closing pipe adds
# one more, blank. Receipt mode adds the Kind cell, so the expected arity shifts
# by one; the parse is otherwise identical, so the count lives in a variable
# rather than in two copies of the loop.
#
# EXACT, never a range. A [min,max] pair wide enough to tolerate the optional
# trailing blank in one mode overlaps the next mode's canonical arity — measured:
# `[5,6]` accepts a canonical FIVE-column row, so a receipt would have linted
# clean in default mode with its Kind cell simply unread, and the two modes would
# have quietly collapsed into one permissive parser.
EXPECTED_CELLS=5
COLUMN_SHAPE='4 columns: ID | Decision | Resolution | Provenance'
if (( RECEIPT == 1 )); then
  EXPECTED_CELLS=6
  COLUMN_SHAPE='5 columns: ID | Decision | Resolution | Provenance | Kind'
fi

# Drop ONE trailing blank cell, and only when dropping it lands on the expected
# arity. Unconditional stripping would turn a row with a genuinely empty last
# column into a "malformed row" report instead of the specific violation that
# empty cell earns.
normalize_arity() { # normalize_arity <n-cells> <last-cell> <expected>
  if (( $1 == $3 + 1 )) && [[ -z "$(trim "$2")" ]]; then
    echo "$3"
  else
    echo "$1"
  fi
}

while IFS= read -r line; do
  masked="${line//\\|/__LEDGER_LINT_PIPE__}"
  IFS='|' read -r -a cells <<< "$masked"
  ncells="$(normalize_arity "${#cells[@]}" "${cells[$(( ${#cells[@]} - 1 ))]}" "$EXPECTED_CELLS")"
  if (( ncells != EXPECTED_CELLS )); then
    violate "malformed ledger row (expected $COLUMN_SHAPE): $line"
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

  # ---- Receipt check A: the ratification bar --------------------------------
  # The whole point of the Kind axis. An `intent` row asserts a human resolved
  # it, so only the two human-attributed provenance values may back that claim;
  # everything else is a derived fact or a parked decision wearing an intent
  # label, which is the comprehension debt this bar exists to count.
  if (( RECEIPT == 1 )); then
    kind="$(trim "${cells[5]}")"
    case "$kind" in
      intent)
        if ! [[ "$provenance" =~ ^(${INTENT_PROVENANCE})$ ]]; then
          violate "$id row: kind 'intent' requires provenance from {${INTENT_PROVENANCE//|/ | }}, got '$provenance' — an intent-resolving row backed by a derived or parked provenance is unratified. Ask the human, or reclassify the row (kind 'fact' for a derived fact, kind 'open' mapped to a declared open region)."
        fi
        ;;
      fact)
        if ! [[ "$provenance" =~ ^(${FACT_PROVENANCE})$ ]]; then
          violate "$id row: kind 'fact' requires provenance from {${FACT_PROVENANCE//|/ | }}, got '$provenance'"
        fi
        ;;
      open)
        if [[ "$provenance" != "deferred" ]]; then
          violate "$id row: kind 'open' requires provenance 'deferred', got '$provenance'"
        fi
        # A parked decision that names no region is indistinguishable from a
        # silent assumption — the exact failure the closed enum exists to stop.
        region="$(printf '%s' "$resolution" | grep -oE 'OR-[0-9]+' | head -n1 || true)"
        if [[ -z "$region" ]]; then
          violate "$id row: kind 'open' must cite the declared open region it falls under (an OR-n id) in its Resolution cell"
        else
          OPEN_CITATIONS+=("$id $region")
        fi
        ;;
      *)
        violate "$id row: kind '$kind' not in {${KIND_ENUM//|/ | }}"
        ;;
    esac
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

# ---- Receipt check B: open regions are receipt content ------------------------
# A receipt that declares nothing open is making a claim ("I know everything that
# matters"), and the point of the section is to make that claim explicit rather
# than implicit. The lint requires the section and the shape; whether ZERO open
# regions is honest for the scope at hand is a reviewer judgment, not a script's
# — spec-reviewer's discovery-coverage checklist owns it.
OPEN_ROW_COUNT=0
if (( RECEIPT == 1 )); then
  declare -a OPEN_IDS=()
  if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*open regions' "$PLAN"; then
    violate "missing mandated receipt section: Open Regions (declare the regions you deliberately left open with a disposition, or state the explicit empty form '$OPEN_EMPTY_FORM')"
  fi

  while IFS= read -r line; do
    masked="${line//\\|/__LEDGER_LINT_PIPE__}"
    IFS='|' read -r -a cells <<< "$masked"
    # 3-column row: leading-empty, id, region, disposition — same arity discipline
    # as the ledger loop above.
    ncells="$(normalize_arity "${#cells[@]}" "${cells[$(( ${#cells[@]} - 1 ))]}" 4)"
    if (( ncells != 4 )); then
      violate "malformed open-region row (expected 3 columns: ID | Region | Disposition): $line"
      continue
    fi
    or_id="$(trim "${cells[1]}")"
    or_region="$(trim "${cells[2]}")"
    or_disp="$(trim "${cells[3]}")"
    OPEN_IDS+=("$or_id")
    OPEN_ROW_COUNT=$((OPEN_ROW_COUNT + 1))
    [[ -n "$or_region" ]] || violate "$or_id row has an empty Region cell"
    if ! [[ "$or_disp" =~ ^(${DISPOSITION_ENUM})$ ]]; then
      violate "$or_id row: disposition '$or_disp' not in {${DISPOSITION_ENUM//|/ | }} — an open region with no disposition is an unowned gap, not a declared one"
    fi
  done < <(grep -E '^\|[[:space:]]*OR-[0-9]+[[:space:]]*\|' "$PLAN" || true)

  if (( OPEN_ROW_COUNT == 0 )); then
    grep -qF "$OPEN_EMPTY_FORM" "$PLAN" || \
      violate "Open Regions has no rows and no explicit empty form ('$OPEN_EMPTY_FORM')"
  fi

  if (( ${#OPEN_IDS[@]} > 0 )); then
    or_dupes=$(printf '%s\n' "${OPEN_IDS[@]}" | sort | uniq -d)
    [[ -z "$or_dupes" ]] || violate "duplicate open-region rows for: $(echo "$or_dupes" | tr '\n' ' ')"
  fi

  # ---- Receipt check C: every parked row maps to a DECLARED region ------------
  # Citing OR-7 when the section declares OR-1 and OR-2 is worse than citing
  # nothing: it reads as a mapped, owned gap in every downstream artifact.
  if (( ${#OPEN_CITATIONS[@]} > 0 )); then
    for citation in "${OPEN_CITATIONS[@]}"; do
      cited_row="${citation%% *}"
      cited_region="${citation##* }"
      found=0
      if (( ${#OPEN_IDS[@]} > 0 )); then
        for or_id in "${OPEN_IDS[@]}"; do
          if [[ "$or_id" == "$cited_region" ]]; then
            found=1
            break
          fi
        done
      fi
      if (( found == 0 )); then
        violate "$cited_row row cites open region '$cited_region', which the Open Regions section does not declare"
      fi
    done
  fi
fi

echo "ledger-lint: ${ROW_COUNT} ledger row(s)"
if (( RECEIPT == 1 )); then
  echo "ledger-lint: ${OPEN_ROW_COUNT} open region(s)"
fi
if (( VIOLATIONS > 0 )); then
  echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "ledger-lint: OK"
exit 0
