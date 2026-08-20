#!/usr/bin/env bash
# ledger-lint.sh — deterministic structural lint for the Decision Ledger
# section of an implementation plan (contract: interviewing-baseline skill).
#
# Usage: ledger-lint.sh [--receipt] <plan-path>
#        ledger-lint.sh --reconcile <receipt-path> <plan-path>
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
# requires exactly four columns, so exitplan-ledger-gate.sh and
# every in-plan Decision Ledger see no schema change at all.
#
# Receipt mode also requires a `## Surface Inventory` section, the structural
# sibling of `## Open Regions`. The register a ledger records is whatever the
# interview chose to admit, so "the register is empty" is an exit criterion the
# interview grades itself against. The inventory is the other side: an
# enumeration of the surfaces and states the work implies, each one either
# `decided` (citing the D-n that decides it) or `out-of-scope` (with a reason).
# It cannot tell you the enumeration was complete — but it turns a surface
# nobody thought about into a surface nobody LISTED, which is a thing a reader
# and a script can both see.
#
#   | ID  | Surface                          | Disposition                     |
#   | --- | -------------------------------- | ------------------------------- |
#   | S-1 | Empty state when no rows load    | decided (D-3)                   |
#   | S-2 | Print stylesheet                 | out-of-scope — no print in this |
#
# RECONCILE MODE (`--reconcile <receipt-path>`) is the third mode, and the only
# one that reads TWO documents. An intake receipt is binding input to the build
# run it is handed to; until #517 nothing in the lane held it beside the spec the
# run committed, so a receipt row could be dropped, or silently re-decided the
# other way, and leave no trace for the review session to notice its absence
# against. This mode holds them side by side.
#
# It binds exactly the receipt rows whose Provenance is `user-answered` or
# `user-delegated` — the rows that cost an operator an interview, and the ones a
# reviewer cannot re-derive from the code the way a `codebase-derived` row can be.
# The predicate keys on PROVENANCE and not on the receipt's `Kind` cell: 12 of the
# 41 on-disk receipts predate Kind and carry no such cell, so a Kind-keyed rule
# would silently no-op on them.
#
# For each bound row the plan must carry a `| D-n |` row under the same id, whose
# Resolution is either the receipt's — compared whitespace-normalized and
# case-sensitively, markdown left as content — or a departure:
#
#   | D-4 | Scope of the fix | DEPARTURE — narrowed to the one call site, because |
#
# The reason after `DEPARTURE` is REQUIRED, mirroring the `Design: none — <reason>`
# disarm the lean gate already enforces at the same milestone: a departure is a
# decision, and an undocumented one is indistinguishable from an omission.
#
# The mode is INERT when the receipt binds no rows, and it is deliberately narrow:
# it runs no structural check on either document (the caller lints those in default
# mode) and it says nothing about the receipt's `OR-n` regions, which the lean gate's
# own `check_pause_and_ask` already owns. What it cannot do is notice a row the
# interview never wrote down — the same ceiling receipt mode has.
#
# Scope honesty: this lint buys structural presence + on-page disclosure,
# NOT decision quality — a load-bearing decision missing from the ledger
# entirely is the plan-reviewer's judgment call, not this script's. Receipt mode
# does not raise that ceiling: it makes an UNDISCLOSED parked decision a lint
# error, and an unlisted surface a visible omission; it cannot make an unasked
# question findable.
#
# Exit: 0 clean, 1 violations (each named on stderr), 2 usage/IO error.
set -euo pipefail

RECEIPT=0
RECONCILE=""
PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --receipt) RECEIPT=1; shift ;;
    # The value is REQUIRED and read here rather than defaulted: `--reconcile` with no
    # path would otherwise consume the plan as its receipt and then lint a plan that is
    # not there, which reports "file not found" for the wrong file.
    --reconcile)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ledger-lint: --reconcile needs a receipt path" >&2; exit 2; }
      RECONCILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,98p' "$0"; exit 0 ;;
    -*) echo "ledger-lint: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$PLAN" ]] || { echo "ledger-lint: unexpected argument: $1" >&2; exit 2; }
      PLAN="$1"; shift ;;
  esac
done

[[ -n "$PLAN" ]] || { echo "ledger-lint: usage: ledger-lint.sh [--receipt] <plan-path>" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "ledger-lint: plan file not found: $PLAN" >&2; exit 2; }
# The two extending modes answer different questions about different documents — is THIS
# receipt well-formed, versus does this plan carry THAT receipt forward — so combining them
# would silently pick one. Refuse instead of guessing which the caller meant.
if (( RECEIPT == 1 )) && [[ -n "$RECONCILE" ]]; then
  echo "ledger-lint: --receipt and --reconcile are different modes; pass one" >&2; exit 2
fi

VIOLATIONS=0
violate() { echo "ledger-lint: VIOLATION: $1" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }

# Mechanical canonical of the interviewing-baseline provenance enum.
# SINGLE-SITED, and deliberately: this file holds the only MACHINE copy of the enum. The
# prose mirrors in interviewing-baseline are a markdown table, which neither relation can
# compare against a shell assignment, and #517/#562 both declined to give lean-gate.sh a
# second parser for exactly this reason. Guarded behaviorally by ledger-lint-selftest.sh.
# The LOCKSTEP markers here named two pairs that no longer exist; removed in #604.
PROVENANCE_ENUM='user-answered|user-delegated|codebase-derived|deferred|ticket-sourced'
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
SURFACE_DISPOSITION_ENUM='decided|out-of-scope'
SURFACE_EMPTY_FORM='No user-visible surface — this change renders nothing a user reads.'

# The section detector, ONE copy. Both check 1 and reconcile mode ask this question, and
# a second in-file copy is the shape #562's review round already named: two greps that agree
# only until somebody widens one. (lean-gate.sh's own copy is the deliberate exception the
# manifest records — a caller that must answer before it can decide whether to call at all.)
has_ledger_section() { # has_ledger_section <path>
  grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$1"
}

# quoting-safe whitespace trim — xargs aborts on quotes/apostrophes/backslashes in cells
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---- RECONCILE MODE (#517) ---------------------------------------------------
# Runs INSTEAD of the structural checks below and exits: the caller lints each
# document in its own mode, and doing both here would report a plan's malformed row
# twice under two different sentences. The lean gate makes exactly these two calls.

# OR-1's default normalization, and the whole of what "the same Resolution" means.
# Every run of whitespace collapses to one space and the ends are trimmed, so a
# re-wrapped cell still reads as carried. Nothing else is stripped: backticks and
# emphasis are CONTENT, and a spec that quietly drops a row's emphasis has changed
# what a reader takes from it. Case-sensitive for the same reason.
normalize_ws() { # normalize_ws <cell>
  local s="$1"
  s="${s//$'\t'/ }"
  while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
  trim "$s"
}

# `| D-n |` rows as `id<TAB>provenance<TAB>normalized-resolution`, from EITHER
# document. The 4-column (plan, pre-Kind receipt) and 5-column (receipt) arities
# read identically here because Provenance is the fourth column in both — which is
# also why this deliberately does not enforce an arity: a malformed row is the other
# modes' finding, and refusing to parse it here would report the same defect twice.
# `\|` is masked on both sides, exactly as the loops below mask it, so an escaped
# pipe compares equal to itself rather than splitting one cell into two.
ledger_rows() { # ledger_rows <path>
  local line masked id resolution provenance
  local -a cells
  while IFS= read -r line; do
    masked="${line//\\|/__LEDGER_LINT_PIPE__}"
    IFS='|' read -r -a cells <<< "$masked"
    (( ${#cells[@]} >= 5 )) || continue
    id="$(trim "${cells[1]}")"
    resolution="$(normalize_ws "${cells[3]}")"
    provenance="$(trim "${cells[4]}")"
    printf '%s\t%s\t%s\n' "$id" "$provenance" "$resolution"
  done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$1" || true)
}

if [[ -n "$RECONCILE" ]]; then
  [[ -f "$RECONCILE" ]] || { echo "ledger-lint: receipt file not found: $RECONCILE" >&2; exit 2; }
  # EXPLICIT, because the alternative fails open. Every read below is a `grep ... || true`,
  # so an unreadable receipt would yield no rows, bind nothing, and report a clean
  # reconciliation — "no ledger" and "a ledger this could not read" are different facts and
  # the second may never report CLEAR. The caller turns this 2 into an environment refusal,
  # which is also what keeps it off the milestone's fix budget.
  [[ -r "$RECONCILE" ]] || { echo "ledger-lint: receipt file not readable: $RECONCILE" >&2; exit 2; }

  RECEIPT_ROWS="$(ledger_rows "$RECONCILE")"
  PLAN_ROWS="$(ledger_rows "$PLAN")"

  BOUND=0
  while IFS=$'\t' read -r r_id r_prov _r_res; do
    [[ -n "$r_id" ]] || continue
    [[ "$r_prov" =~ ^(${INTENT_PROVENANCE})$ ]] || continue
    BOUND=$((BOUND + 1))
  done <<< "$RECEIPT_ROWS"

  CARRIED=0
  DEPARTED=0
  # INERT when the receipt binds nothing. Most receipts predate this mode and many
  # bind no intent row at all; a mode that demanded a section from them would refuse
  # every such spec for a receipt that asked nothing of it.
  if (( BOUND > 0 )); then
    # The section is mandated once a row is bound, and its absence is reported ONCE
    # rather than once per row: a spec with no Decision Ledger has one defect, and
    # eight sentences saying so buries it. This is also the arm that catches a spec
    # carrying rows under no heading at all.
    if ! has_ledger_section "$PLAN"; then
      violate "the pre-flight receipt $RECONCILE carries $BOUND row(s) the plan must carry forward, but $PLAN has no Decision Ledger section at all"
    else
      while IFS=$'\t' read -r r_id r_prov r_res; do
        [[ -n "$r_id" ]] || continue
        [[ "$r_prov" =~ ^(${INTENT_PROVENANCE})$ ]] || continue

        p_res=""
        p_found=0
        while IFS=$'\t' read -r p_id _p_prov p_r; do
          [[ "$p_id" == "$r_id" ]] || continue
          p_found=1; p_res="$p_r"; break
        done <<< "$PLAN_ROWS"

        if (( p_found == 0 )); then
          # The silent-drop failure, and the one the explicit empty form falls into:
          # a plan claiming "No material decisions" against a non-empty receipt has no
          # row for any bound id, so it lands here per row rather than needing a rule
          # of its own.
          violate "$r_id ($r_prov) is in the pre-flight receipt $RECONCILE but not in $PLAN's Decision Ledger — carry the row forward, or record it as 'DEPARTURE — <reason>'"
          continue
        fi

        # Prefix-anchored on a non-word boundary, the idiom the surface-inventory
        # disposition check already uses: `DEPARTURE — x` and `DEPARTURE: x` both read
        # as a departure while `DEPARTURES were made` does not.
        if [[ "$p_res" =~ ^DEPARTURE([^A-Za-z0-9-]|$) ]]; then
          if [[ "${p_res#*DEPARTURE}" =~ [A-Za-z0-9] ]]; then
            DEPARTED=$((DEPARTED + 1))
          else
            violate "$r_id row in $PLAN is marked DEPARTURE but states no reason — the form is 'DEPARTURE — <reason>', because an undocumented departure is indistinguishable from an omission"
          fi
        elif [[ "$p_res" != "$r_res" ]]; then
          # The unflagged-reversal failure. Row presence alone would pass here and
          # leave the reversal to reviewer habit, which is the posture that failed.
          violate "$r_id row in $PLAN resolves differently from the pre-flight receipt $RECONCILE, with no departure marker. receipt: '$r_res' / plan: '$p_res'"
        else
          CARRIED=$((CARRIED + 1))
        fi
      done <<< "$RECEIPT_ROWS"
    fi
  fi

  echo "ledger-lint: reconcile: $BOUND bound, $CARRIED carried, $DEPARTED departure(s)"
  if (( VIOLATIONS > 0 )); then
    echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
    exit 1
  fi
  exit 0
fi

# ---- Check 1: section header -------------------------------------------------
if ! has_ledger_section "$PLAN"; then
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
SURFACE_ROW_COUNT=0
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

  # ---- Receipt check D: the surface inventory ---------------------------------
  # The ledger's exit criterion is "the register is empty", where the register is
  # whatever the interview chose to admit — so an interview that never asked about
  # the empty state exits satisfied. The inventory is the independent axis: the
  # surfaces and states the work implies, each one accounted for. `decided` cites
  # the ledger row that decides it; `out-of-scope` says why not. A script cannot
  # judge whether the enumeration was complete, but it can refuse an inventory
  # that leaves a listed surface unaccounted for.
  declare -a SURFACE_IDS=()
  declare -a SURFACE_CITATIONS=()
  if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*surface inventory' "$PLAN"; then
    violate "missing mandated receipt section: Surface Inventory (enumerate the surfaces and states this work implies — each one 'decided (D-n)' or 'out-of-scope — <reason>' — or state the explicit empty form '$SURFACE_EMPTY_FORM')"
  fi

  while IFS= read -r line; do
    masked="${line//\\|/__LEDGER_LINT_PIPE__}"
    IFS='|' read -r -a cells <<< "$masked"
    # 3-column row: leading-empty, id, surface, disposition — same arity
    # discipline as the two loops above.
    ncells="$(normalize_arity "${#cells[@]}" "${cells[$(( ${#cells[@]} - 1 ))]}" 4)"
    if (( ncells != 4 )); then
      violate "malformed surface row (expected 3 columns: ID | Surface | Disposition): $line"
      continue
    fi
    s_id="$(trim "${cells[1]}")"
    s_surface="$(trim "${cells[2]}")"
    s_disp="$(trim "${cells[3]}")"
    SURFACE_IDS+=("$s_id")
    SURFACE_ROW_COUNT=$((SURFACE_ROW_COUNT + 1))
    [[ -n "$s_surface" ]] || violate "$s_id row has an empty Surface cell"

    # The disposition token is a PREFIX of the cell, because both values carry a
    # payload after it. Anchored on a non-word boundary so `decided (D-3)` and
    # `decided(D-3)` both read as `decided` while `decidedly` does not.
    s_token=""
    if [[ "$s_disp" =~ ^(${SURFACE_DISPOSITION_ENUM})([^A-Za-z0-9-]|$) ]]; then
      s_token="${BASH_REMATCH[1]}"
    fi
    case "$s_token" in
      decided)
        # An uncited `decided` is the inventory's version of a silent assumption:
        # it claims a decision exists without naming one, so nothing downstream
        # can check that it does.
        d_ref="$(printf '%s' "$s_disp" | grep -oE 'D-[0-9]+' | head -n1 || true)"
        if [[ -z "$d_ref" ]]; then
          violate "$s_id row: disposition 'decided' must cite the ledger row that decides it (a D-n id)"
        else
          SURFACE_CITATIONS+=("$s_id $d_ref")
        fi
        ;;
      out-of-scope)
        # Scoping a surface out is a legitimate answer; scoping it out silently is
        # the batch-blessing move in miniature, so the reason is the whole content
        # of the row.
        if ! [[ "${s_disp#*out-of-scope}" =~ [A-Za-z0-9] ]]; then
          violate "$s_id row: disposition 'out-of-scope' must carry the reason it is out of scope"
        fi
        ;;
      *)
        violate "$s_id row: disposition '$s_disp' not in {${SURFACE_DISPOSITION_ENUM//|/ | }} — a listed surface that is neither decided nor explicitly scoped out is the gap this section exists to make countable"
        ;;
    esac
  done < <(grep -E '^\|[[:space:]]*S-[0-9]+[[:space:]]*\|' "$PLAN" || true)

  if (( SURFACE_ROW_COUNT == 0 )); then
    grep -qF "$SURFACE_EMPTY_FORM" "$PLAN" || \
      violate "Surface Inventory has no rows and no explicit empty form ('$SURFACE_EMPTY_FORM')"
  fi

  if (( ${#SURFACE_IDS[@]} > 0 )); then
    s_dupes=$(printf '%s\n' "${SURFACE_IDS[@]}" | sort | uniq -d)
    [[ -z "$s_dupes" ]] || violate "duplicate surface rows for: $(echo "$s_dupes" | tr '\n' ' ')"
  fi

  # A `decided` row citing a D-n the ledger never declares is the dangling-citation
  # failure again — it reads as a covered surface everywhere downstream.
  if (( ${#SURFACE_CITATIONS[@]} > 0 )); then
    for citation in "${SURFACE_CITATIONS[@]}"; do
      cited_row="${citation%% *}"
      cited_decision="${citation##* }"
      found=0
      if (( ${#ROW_IDS[@]} > 0 )); then
        for d_id in "${ROW_IDS[@]}"; do
          if [[ "$d_id" == "$cited_decision" ]]; then
            found=1
            break
          fi
        done
      fi
      if (( found == 0 )); then
        violate "$cited_row row cites decision '$cited_decision', which the Decision Ledger does not declare"
      fi
    done
  fi
fi

echo "ledger-lint: ${ROW_COUNT} ledger row(s)"
if (( RECEIPT == 1 )); then
  echo "ledger-lint: ${OPEN_ROW_COUNT} open region(s)"
  echo "ledger-lint: ${SURFACE_ROW_COUNT} surface(s)"
fi
if (( VIOLATIONS > 0 )); then
  echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "ledger-lint: OK"
exit 0
