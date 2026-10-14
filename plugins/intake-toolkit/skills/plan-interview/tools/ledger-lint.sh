#!/usr/bin/env bash
# ledger-lint.sh — deterministic structural lint for the Decision Ledger
# section of an implementation plan (contract: interviewing-baseline skill).
#
# Usage: ledger-lint.sh [--receipt] <plan-path>
#        ledger-lint.sh --receipt-version     prints the highest receipt version this lint knows
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
# RECEIPT MODE (`--receipt`) adds the provenance bar. An INTAKE receipt is a
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
# Receipt mode also asks a `codebase-derived` row for its evidence, anywhere in the
# Resolution cell: run: `<command>` → <decisive output> (arrow `→` or `->`) for a
# fact checked at intake, or cited (convention|adr): <path:line> for one that cannot
# be run, or cited (kb): <kb-page> for one adopted from the knowledge source's answer.
# A bare `file:line` is a pointer, not a check.
#
# Receipt mode also reads the two sections the scheduler (`run.sh`) takes from the
# record's first commit, with the scheduler's heading rule:
# exact title at any depth, case-insensitive, ANY heading closes it, the FIRST one
# decides.
#
#   `## Checks` — mandatory. One command per line, `- cmd` or `` - `cmd` ``: the
#   ticket-specific commands run against the pushed head beside `commands.*`. A
#   bullet the scheduler's parse would not read as one command is refused, since the
#   scheduler would drop it silently — and so is a line it WOULD run that is not that
#   form (`---`, `-cmd`). Empty form: CHECKS_EMPTY_FORM below.
#
#   `## Design frames` (or `## Design`) — mandatory only when the repo's config sets
#   `design.provider` (SECOND_SHIFT_CONFIG, else <repo>/.claude/second-shift.config.json,
#   <repo> being the main checkout the receipt sits in). At least one
#   `| RS-n | route | state | frame | must-show |` row with every cell filled, or
#   `Design: none — <reason>`. RS rows are shape-checked whenever present: the route
#   smoke reads them on any repo. No escaped pipe (`\|`): the scheduler splits on it.
#
# RECEIPT VERSIONS (#1022). A receipt names its version once, on a `Receipt: v<N>` line before
# its first `##` heading; a receipt with no such line is v1. A section is mandated only on a
# receipt at or above the version that introduced it (RECEIPT_SECTIONS below), so a section added
# later bumps the version instead of failing every receipt written before it. Two `Receipt:`
# lines, one inside a section, one not of that form, and a version above the highest this lint
# knows are each a violation. `--receipt-version` prints that highest version: the scheduler
# (run.sh) refuses to trust a lint that knows fewer versions than the receipt it would check.
#
#   `## Intake steps` — mandatory from v2. One `Key: outcome` line per intake step, each key
#   once, in this order: Requirements, Split, Explore, Fan-out, Dup-scan, Post-merge scan,
#   Sizing. The line starts at the start of the line (no bullet, no indent), and its outcome is
#   neither empty nor a bare dash. Read with section_of, so a sub-heading inside it would cut it
#   short, and is refused.
#
#   `## Knowledge source` — mandated from v3. Exactly one of: a `Provider: <plugin>:<agent>` line
#   followed by the provider's whole answer indented four spaces (a code block, so its headings,
#   rows and `Receipt:` lines are read by no column-0 scan); `Knowledge source: none declared`;
#   `Knowledge source: failed — <text>`. An empty section, any other line that is not indented
#   four spaces, and a `Knowledge source:` line outside those two forms are each refused.
#
#   `## Test intent` — mandated from v4 (#1039). One `ACs: AC-1 AC-2 …` line, the ticket's AC ids
#   as labeled (or `ACs: none — <reason>` when the ticket has no AC block), then one line per id:
#   `AC-n: <the observable behavior its test must prove>` or `AC-n: exempt — <reason>`, or (#1040)
#   `AC-n: holds — <the existing behavior its test keeps>` or `AC-n: unchecked — <tier and reason>`.
#   An id in `ACs:` with no line, a line whose id is not in `ACs:`, a second line for one id, a
#   token in `ACs:` that is not `AC-<n>`, an empty behavior, an exempt, holds or unchecked line with
#   no reason, and any other line are each refused, naming it. dev-pipeline's plan-coverage.sh
#   reads the same section from the committed record and holds the build's plan to its ids; the
#   scheduler keeps holds files off its fails-without-the-change leg and notes unchecked ones unrun.
#   The two #1040 forms are additive inside v4's section: no version bump (its record's OR-1).
#
# Receipt mode also refuses a section title used twice: every reader takes the first copy, so
# the second is never read.
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

# The receipt version table: each mandated receipt section and the version it is mandated from
# (the Decision Ledger is mandated of every plan, receipt or not, and Design frames by the config,
# so neither is here). interviewing-baseline ("Receipt versions") carries the same table, held
# equal by check-lockstep-pairs.sh. A new mandated section is a new row at a new version.
RECEIPT_SECTIONS="$(grep -v 'LOCKSTEP-' <<'TABLE'
# LOCKSTEP-BEGIN receipt-versions
| Section | Mandated from |
| --- | --- |
| Open Regions | v1 |
| Surface Inventory | v1 |
| Checks | v1 |
| Fan-out | v1 |
| Intake steps | v2 |
| Knowledge source | v3 |
| Test intent | v4 |
# LOCKSTEP-END receipt-versions
TABLE
)"
RECEIPT_VERSION_MAX="$(sed -n 's/^|.*| v\([0-9][0-9]*\) |$/\1/p' <<< "$RECEIPT_SECTIONS" | sort -n | tail -n 1)"

RECEIPT=0
PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --receipt) RECEIPT=1; shift ;;
    --receipt-version) echo "$RECEIPT_VERSION_MAX"; exit 0 ;;
    -h|--help) awk 'NR > 1 && /^set -euo pipefail/ {exit} NR > 1' "$0"; exit 0 ;;
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

# Mechanical canonical of the interviewing-baseline provenance enum.
# SINGLE-SITED, and deliberately: this file holds the only MACHINE copy of the enum. The
# prose mirrors in interviewing-baseline are a markdown table, which neither relation can
# compare against a shell assignment. Guarded behaviorally by ledger-lint-selftest.sh.
# The LOCKSTEP markers that once wrapped THIS assignment named two pairs that no longer
# exist; removed in #604.
PROVENANCE_ENUM='user-answered|user-delegated|codebase-derived|deferred|ticket-sourced'
EMPTY_FORM='No material decisions — all choices codebase-derived.'

# Receipt-mode vocabulary. Single-sited on purpose: nothing else copies these, so
# they need no lockstep row.
KIND_ENUM='intent|fact|open'
INTENT_PROVENANCE='user-answered|user-delegated'
FACT_PROVENANCE='codebase-derived|ticket-sourced'
DISPOSITION_ENUM='pause-and-ask|reversible-default-and-flag'
OPEN_EMPTY_FORM='No open regions — every decision in scope is ratified.'
SURFACE_DISPOSITION_ENUM='decided|out-of-scope'
SURFACE_EMPTY_FORM='No user-visible surface — this change renders nothing a user reads.'
CHECKS_EMPTY_FORM='No ticket-specific checks — the configured lanes cover this change.'
FANOUT_TAG_ENUM='new|already-had|overturned|not material'
FANOUT_EMPTY_POOL='Pool: empty — no claim survived refutation.'
FANOUT_SKIP_BY='by the operator'   # the one name a fan-out skip may carry (#1023), read case-insensitively at a word end
INTAKE_STEP_KEYS='Requirements|Split|Explore|Fan-out|Dup-scan|Post-merge scan|Sizing'
KS_NONE='Knowledge source: none declared'
KS_PROVIDER_NAME='[^[:space:]:]+:[^[:space:]:]+'   # the namespaced agent type, <plugin>:<agent>

# The receipt's version, from its `Receipt:` line (receipt check 0 below); v1 until read.
RECEIPT_V=1
mandated() { # mandated <section title as in RECEIPT_SECTIONS> — 0 when this receipt's version mandates it
  local since
  since="$(awk -F'|' -v s="$1" '{t = $2; gsub(/^ +| +$/, "", t)} t == s {v = $3; gsub(/[ v]/, "", v); print v; exit}' <<< "$RECEIPT_SECTIONS")"
  [[ -n "$since" ]] || { echo "ledger-lint: internal: the receipt version table has no row for '$1'" >&2; exit 2; }
  (( RECEIPT_V >= since ))
}

# The scheduler's section reader, its awk byte for byte (run.sh `section_of`): exact title at
# any depth, case-folded, ANY heading closes, the FIRST such section decides. The lint must
# read the section the scheduler reads, or a receipt that lints clean can still refuse there.
section_of() { # section_of <title-regex> <path>
  awk -v h="$1" 'on && /^#+[[:space:]]/ {on=0; done=1} !done && tolower($0) ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {on=1; next} on' "$2"
}
has_section() { # has_section <title-regex> <path>
  grep -qiE "^#+[[:space:]]+$1[[:space:]]*\$" "$2"
}

# `design.provider` from the config the scheduler reads. Prints the provider or nothing; exits
# 2 when a present config cannot be read, because "no provider" and "a config this could not
# read" are different facts, and the second would silently waive the frames section.
design_provider() { # design_provider <receipt-path>
  local cfg="${SECOND_SHIFT_CONFIG:-}" common
  if [[ -z "$cfg" ]]; then
    common="$(git -C "$(dirname "$1")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
    cfg="$(dirname "$common")/.claude/second-shift.config.json"
  fi
  [[ -f "$cfg" ]] || return 0
  command -v jq >/dev/null 2>&1 || { echo "ledger-lint: jq is required to read $cfg" >&2; exit 2; }
  jq -e . "$cfg" >/dev/null 2>&1 || { echo "ledger-lint: config $cfg is present but not JSON" >&2; exit 2; }
  jq -r '.design.provider // empty' "$cfg"
}

# The section detector, ONE copy.
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

# A receipt's `codebase-derived` row names its evidence in the Resolution cell, anywhere in
# it (the decided value usually comes first), in one of two forms:
#   run: `<command>` → <decisive output>     executed at intake; `->` is the arrow too, and the
#                                            command may sit in a double-backtick span
#   cited (convention|adr): <path:line>      the fact cannot be executed
#   cited (kb): <kb-page>                    adopted from the knowledge source's answer, the page
#                                            copied from its Sources: list (the form is checked,
#                                            never that the page exists)
# `run:` and `cited` are case-insensitive. A `|` in the command or output is escaped as `\|`,
# which the row loop has already masked, so it never splits a cell here. A row recording an
# agent's choice rather than a fact is not `codebase-derived` at all, so the reason enum has no
# catch-all.
CITED_REASON_ENUM='convention|adr|kb'
CITED_FORMS="'cited (convention|adr): <path:line>' or 'cited (kb): <kb-page>'"
EVIDENCE_EDGE='(^|[^A-Za-z0-9_-])'
RUN_TOKEN="${EVIDENCE_EDGE}[Rr][Uu][Nn]:[[:space:]]*"
CITED_TOKEN="${EVIDENCE_EDGE}[Cc][Ii][Tt][Ee][Dd][[:space:]]*"
# A code span holding at least one non-blank character: double-backtick first, so a command
# carrying its own backticks reads as one span.
# shellcheck disable=SC2016  # markdown backticks
CODE_SPAN='(``([^`]|`[^`])*[^`[:space:]]([^`]|`[^`])*``|`[^`]*[^`[:space:]][^`]*`)'
RUN_FORM="${RUN_TOKEN}${CODE_SPAN}[[:space:]]*(→|->)[[:space:]]*[^[:space:]]"
CITED_FORM="${CITED_TOKEN}\\((${CITED_REASON_ENUM})\\):[[:space:]]*[^[:space:]]"
CITED_ANY="${CITED_TOKEN}(\\(([^)]*)\\))?[[:space:]]*:"

check_evidence() { # check_evidence <row-id> <resolution-cell, pipes masked>
  local id="$1" cell="$2" shown reason
  [[ "$cell" =~ $RUN_FORM || "$cell" =~ $CITED_FORM ]] && return 0
  # Violation text shows the cell as the author wrote it, never the internal placeholder.
  shown="${cell//__LEDGER_LINT_PIPE__/\\|}"
  if [[ "$cell" =~ $CITED_ANY ]]; then
    reason="${BASH_REMATCH[3]:-}"
    reason="$(trim "${reason//__LEDGER_LINT_PIPE__/\\|}")"
    if [[ -z "$reason" ]]; then
      violate "$id row: 'cited' names no reason — the form is $CITED_FORMS: $shown"
    elif ! [[ "$reason" =~ ^(${CITED_REASON_ENUM})$ ]]; then
      violate "$id row: cited reason '$reason' not in {${CITED_REASON_ENUM//|/ | }} — a row that records a choice rather than a fact is not codebase-derived: ask it, and record it user-answered or user-delegated: $shown"
    elif [[ "$reason" == kb ]]; then
      violate "$id row: 'cited (kb):' names no source after the colon (the page, copied from the answer's Sources: list): $shown"
    else
      violate "$id row: 'cited ($reason):' names no source after the colon (a path:line): $shown"
    fi
  elif [[ "$cell" =~ $RUN_TOKEN ]]; then
    if [[ "$cell" =~ ${RUN_TOKEN}${CODE_SPAN} ]]; then
      violate "$id row: 'run:' needs the decisive output after an arrow — 'run: \`<command>\` → <output>' (or '->'): $shown"
    else
      violate "$id row: 'run:' needs a non-empty command in a code span — 'run: \`<command>\` → <output>': $shown"
    fi
  else
    violate "$id row: a codebase-derived receipt row states its evidence in the Resolution cell — 'run: \`<command>\` → <decisive output>' for a fact checked at intake, or $CITED_FORMS for one that cannot be run: $shown"
  fi
}

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
    violate "malformed ledger row (expected $COLUMN_SHAPE; a '|' inside a cell is escaped as '\\|'): $line"
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
  # Receipt check: a codebase-derived row states its evidence — the command it ran,
  # or why the fact is only cited.
  if (( RECEIPT == 1 )) && [[ "$provenance" == "codebase-derived" ]]; then
    check_evidence "$id" "$resolution"
  fi

  # ---- Receipt check A: the provenance bar ---------------------------------
  # The whole point of the Kind axis. An `intent` row asserts a human resolved
  # it, so only the two human-attributed provenance values may back that claim;
  # everything else is a derived fact or a parked decision wearing an intent
  # label, which is the comprehension debt this bar exists to count.
  if (( RECEIPT == 1 )); then
    kind="$(trim "${cells[5]}")"
    case "$kind" in
      intent)
        if ! [[ "$provenance" =~ ^(${INTENT_PROVENANCE})$ ]]; then
          violate "$id row: kind 'intent' requires provenance from {${INTENT_PROVENANCE//|/ | }}, got '$provenance' — an intent-resolving row backed by a derived or parked provenance names no human decision. Ask the human, or reclassify the row (kind 'fact' for a derived fact, kind 'open' mapped to a declared open region)."
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
CHECK_COUNT=0
FRAME_ROW_COUNT=0
FANOUT_ROW_COUNT=0
STEP_COUNT=0
if (( RECEIPT == 1 )); then
  # ---- Receipt check 0: the version line, and one title per section (#1022) ----------------
  # Read first: the version decides which sections the checks below mandate. Lines at the start
  # of a line only, so a receipt quoted in the indented Fan-out snapshot is not read as this one's.
  RECEIPT_LINES="$(awk '/^##+[[:space:]]/ {sec = 1} tolower($0) ~ /^receipt:/ {sub(/\r$/, ""); print (sec ? "in" : "top") "\t" $0}' "$PLAN")"
  if [[ -n "$RECEIPT_LINES" ]]; then
    n_receipt="$(grep -c . <<< "$RECEIPT_LINES")"
    (( n_receipt == 1 )) || violate "the receipt carries $n_receipt 'Receipt:' lines — it names its version once, before its first '##' heading"
    while IFS=$'\t' read -r where line; do
      [[ "$where" == top ]] || violate "'Receipt:' line inside a '##' section — it goes once, before the first '##' heading: $line"
    done <<< "$RECEIPT_LINES"
    first="$(head -n 1 <<< "$RECEIPT_LINES" | cut -f2-)"
    if [[ "$first" =~ ^Receipt:[[:space:]]*v([0-9]+)[[:space:]]*$ ]] && (( 10#${BASH_REMATCH[1]} >= 1 )); then
      RECEIPT_V=$(( 10#${BASH_REMATCH[1]} ))
      if (( RECEIPT_V > RECEIPT_VERSION_MAX )); then
        violate "the receipt is v$RECEIPT_V, newer than this lint knows (v$RECEIPT_VERSION_MAX) — it was written by a newer intake-toolkit than the one linting it; update intake-toolkit"
        RECEIPT_V=$RECEIPT_VERSION_MAX
      fi
    else
      violate "malformed version line (the form is 'Receipt: v<N>', N from 1): $first"
    fi
  fi
  while IFS= read -r title; do
    [[ -n "$title" ]] && violate "section title '$title' is used twice — every reader takes the first copy, so the second is never read: merge them, or rename one"
  done < <(awk '/^#+[[:space:]]/ {t = $0; sub(/\r$/, "", t); sub(/^#+[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t); if (seen[tolower(t)]++ == 1) print t}' "$PLAN")

  declare -a OPEN_IDS=()
  if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*open regions' "$PLAN" && mandated 'Open Regions'; then
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
  if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*surface inventory' "$PLAN" && mandated 'Surface Inventory'; then
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

  # ---- Receipt check E: the checks the scheduler runs ---------------------------
  # An absent section is a silent claim that nothing beyond the configured lanes verifies
  # this change, so it is mandatory, with an empty form, like the two sections above.
  if ! has_section 'checks' "$PLAN"; then
    mandated 'Checks' && violate "missing mandated receipt section: Checks (list the ticket-specific commands the scheduler runs against the pushed head, one per line as '- cmd', or state the explicit empty form '$CHECKS_EMPTY_FORM')"
  else
    CHECKS_SEC="$(section_of 'checks' "$PLAN")"
    while IFS= read -r line; do
      # Classify every line the scheduler runs — its predicate is '^- *', so '---' and '-cmd'
      # are commands to it — plus the indented and '*'/'+' bullets it silently drops.
      [[ "$line" =~ ^- || "$line" =~ ^[[:space:]]*[-*+]([[:space:]]|$) ]] || continue
      # shellcheck disable=SC2016  # markdown backticks
      cmd="$(printf '%s\n' "$line" | sed -n 's/^- *`\{0,1\}\([^`]*\)`\{0,1\} *$/\1/p')"
      if [[ "$line" =~ ^-[[:space:]] && -n "$(trim "$cmd")" ]]; then
        CHECK_COUNT=$((CHECK_COUNT + 1))
      else
        violate "Checks line is not one command the scheduler can read (the form is '- cmd' or '- \`cmd\`', at the start of the line, no inner backticks): $line"
      fi
    done <<< "$CHECKS_SEC"
    if (( CHECK_COUNT == 0 )) && ! grep -qF "$CHECKS_EMPTY_FORM" <<< "$CHECKS_SEC"; then
      violate "Checks has no command and no explicit empty form ('$CHECKS_EMPTY_FORM')"
    fi
  fi

  # ---- Receipt check F: the design frames the route smoke reads ---------------
  # The row shape is checked wherever rows appear — the smoke reads them on any repo — but
  # the section is required only where `design.provider` is set: the scheduler refuses there
  # (env-design-undeclared) on a receipt that neither arms nor disarms the ticket.
  PROVIDER="$(design_provider "$PLAN")" || exit 2
  DESIGN_SEC="$(section_of 'design( frames)?' "$PLAN")"
  DISARMED=0
  if grep -qiE '^[[:space:]]*Design:[[:space:]]*none([[:space:]]|$)' <<< "$DESIGN_SEC"; then
    # Stricter than the scheduler, which takes any non-space after 'none' (so a bare dash):
    # the reason must carry a word. A receipt that passes here still passes there.
    if grep -qiE '^[[:space:]]*Design:[[:space:]]*none[[:space:]]+.*[[:alnum:]]' <<< "$DESIGN_SEC"; then
      DISARMED=1
    else
      violate "Design frames disarms this ticket but states no reason — the form is 'Design: none — <reason>'"
    fi
  fi
  while IFS= read -r line; do
    # The scheduler splits frames rows on every '|', escaped or not, so an escaped pipe would
    # reach the route smoke as different cells than the lint read.
    if [[ "$line" == *'\|'* ]]; then
      violate "design frames row carries an escaped pipe '\\|', which the scheduler splits as a cell boundary — drop the pipe from the cell: $line"
      continue
    fi
    IFS='|' read -r -a cells <<< "$line"
    # 5-column row: leading-empty, RS, route, state, frame, must-show.
    ncells="$(normalize_arity "${#cells[@]}" "${cells[$(( ${#cells[@]} - 1 ))]}" 6)"
    if (( ncells != 6 )); then
      violate "malformed design frames row (expected 5 columns: RS | route | state | frame | must-show): $line"
      continue
    fi
    rs_id="$(trim "${cells[1]}")"
    FRAME_ROW_COUNT=$((FRAME_ROW_COUNT + 1))
    [[ -n "$(trim "${cells[2]}")" ]] || violate "$rs_id row has an empty route cell"
    [[ -n "$(trim "${cells[3]}")" ]] || violate "$rs_id row has an empty state cell"
    [[ -n "$(trim "${cells[4]}")" ]] || violate "$rs_id row has an empty frame cell"
    [[ -n "$(trim "${cells[5]}")" ]] || violate "$rs_id row has an empty must-show cell — the record's only per-row assertion; name a data-test id or a copy string taken from the frame"
  done < <(grep -E '^\|[[:space:]]*RS-[0-9]+[[:space:]]*\|' <<< "$DESIGN_SEC" || true)
  if [[ -n "$PROVIDER" ]] && (( FRAME_ROW_COUNT == 0 && DISARMED == 0 )); then
    violate "config sets design.provider '$PROVIDER', so the receipt needs a Design frames section carrying at least one '| RS-n | route | state | frame | must-show |' row, or the disarm 'Design: none — <reason>'"
  fi

  # ---- Receipt check G: the fan-out section (#916) ------------------------------------
  # What the intake fan-out achieved over plain intake, per ticket: each surviving evidence
  # item tagged against the interviewer's pre-pool snapshot, a tally, and the snapshot itself
  # so the tags stay auditable from the committed record. A receipt that ran no fan-out says
  # so — skipped (by the operator) or failed (what) — because an absent section reads exactly like
  # a fan-out nobody ran and nobody recorded. Only the operator skips it (#1023): a skip in any
  # other name is a stage deciding on its own that the evidence was not worth gathering.
  if ! has_section 'fan-out' "$PLAN"; then
    mandated 'Fan-out' && violate "missing mandated receipt section: Fan-out (the tagged evidence pool with its Tally, Refuter and Snapshot, or one explicit form: 'Fan-out: skipped — by the operator <where / why>' or 'Fan-out: failed — <what>')"
  else
    FANOUT_SEC="$(section_of 'fan-out' "$PLAN")"
    if grep -qiE "^[[:space:]]*Fan-out:[[:space:]]*skipped[[:space:]]*(—|–|-|:)?[[:space:]]*${FANOUT_SKIP_BY}([^[:alnum:]_]|\$)" <<< "$FANOUT_SEC" \
      || grep -qiE '^[[:space:]]*Fan-out:[[:space:]]*failed[[:space:]]+.*[[:alnum:]]' <<< "$FANOUT_SEC"; then
      : # the operator's skip, or a reasoned failure, is the whole section
    elif grep -qiE '^[[:space:]]*Fan-out:[[:space:]]*skipped[[:space:]]+.*[[:alnum:]]' <<< "$FANOUT_SEC"; then
      violate "Fan-out skip does not name the operator — only the operator skips the fan-out; the form is 'Fan-out: skipped — by the operator <where / why>': $(grep -iE '^[[:space:]]*Fan-out:[[:space:]]*skipped' <<< "$FANOUT_SEC" | head -n 1)"
    elif grep -qiE '^[[:space:]]*Fan-out:[[:space:]]*(skipped|failed)' <<< "$FANOUT_SEC"; then
      violate "Fan-out states a skip or failure without saying who or what — the forms are 'Fan-out: skipped — by the operator <where / why>' and 'Fan-out: failed — <what>'"
    else
      grep -qiE '^[[:space:]]*Tally:[[:space:]]*.*[[:alnum:]]' <<< "$FANOUT_SEC" || \
        violate "Fan-out has no 'Tally:' line (rows added · snapshot claims overturned · questions added) — the tally is what the section exists to show"
      grep -qiE '^[[:space:]]*Refuter:[[:space:]]*.*[[:alnum:]]' <<< "$FANOUT_SEC" || \
        violate "Fan-out has no 'Refuter:' line — say which model family checked the claims (e.g. 'cross (opus/fable alternating)' or 'same-family (fable unavailable)')"
      grep -qiE '^[[:space:]]*Lenses:[[:space:]]*.*[[:alnum:]]' <<< "$FANOUT_SEC" || \
        violate "Fan-out has no 'Lenses:' line — name every lens the run dispatched, the model it ran on and claims kept of claims made, so a lens that never contributes shows in the record"
      # section_of stops at the '### Snapshot' heading, so look for it between '## Fan-out' and
      # the next '## ' heading rather than anywhere in the receipt.
      awk 'tolower($0) ~ /^##[[:space:]]+fan-out/ {on=1; next} on && /^##[[:space:]]/ {on=0} on && tolower($0) ~ /^###+[[:space:]]+snapshot[[:space:]]*$/ {f=1} END {exit !f}' "$PLAN" || \
        violate "Fan-out has no '### Snapshot' subsection — the interviewer's pre-pool register, verbatim, is what makes the tags auditable"
      # The snapshot is a register too, so a pasted-as-is copy would be read as live ledger,
      # region and surface rows by every table scan above. Indenting it four spaces keeps it
      # verbatim (markdown renders it as a code block) and out of those scans.
      if awk 'tolower($0) ~ /^#+[[:space:]]+snapshot[[:space:]]*$/ {on=1; next} on && /^#+[[:space:]]/ {on=0} on && /^\|/ {bad=1} END {exit !bad}' "$PLAN"; then
        violate "Fan-out's Snapshot carries unindented table rows — indent the snapshot four spaces (a code block), or its rows are read as this receipt's own ledger"
      fi
      while IFS= read -r line; do
        masked="${line//\\|/__LEDGER_LINT_PIPE__}"
        IFS='|' read -r -a cells <<< "$masked"
        ncells="$(normalize_arity "${#cells[@]}" "${cells[$(( ${#cells[@]} - 1 ))]}" 6)"
        if (( ncells != 6 )); then
          violate "malformed fan-out row (expected 5 columns: ID | Angle | Claim | Tag | Disposition): $line"
          continue
        fi
        f_id="$(trim "${cells[1]}")"
        f_tag="$(trim "${cells[4]}")"
        f_disp="$(trim "${cells[5]}")"
        FANOUT_ROW_COUNT=$((FANOUT_ROW_COUNT + 1))
        [[ -n "$(trim "${cells[2]}")" ]] || violate "$f_id row has an empty Angle cell — name the lens that produced the item"
        [[ -n "$(trim "${cells[3]}")" ]] || violate "$f_id row has an empty Claim cell"
        f_token=""
        if [[ "$f_tag" =~ ^(${FANOUT_TAG_ENUM})([^A-Za-z0-9-]|$) ]]; then
          f_token="${BASH_REMATCH[1]}"
        fi
        case "$f_token" in
          overturned)
            [[ "${f_tag#overturned}" =~ [A-Za-z0-9] ]] || \
              violate "$f_id row: tag 'overturned' must name the snapshot claim it overturned"
            ;;
          new|already-had|'not material') ;;
          *) violate "$f_id row: tag '$f_tag' not in {${FANOUT_TAG_ENUM//|/ | }}" ;;
        esac
        if [[ -z "$f_disp" ]]; then
          violate "$f_id row has an empty Disposition cell — say what became of the item (the D-n it became, or why it did not)"
        fi
        for d_ref in $(printf '%s' "$f_disp" | grep -oE 'D-[0-9]+' || true); do
          found=0
          for d_id in "${ROW_IDS[@]}"; do [[ "$d_id" == "$d_ref" ]] && { found=1; break; }; done
          (( found == 1 )) || violate "$f_id row cites decision '$d_ref', which the Decision Ledger does not declare"
        done
      done < <(grep -E '^\|[[:space:]]*F-[0-9]+[[:space:]]*\|' <<< "$FANOUT_SEC" || true)
      if (( FANOUT_ROW_COUNT == 0 )) && ! grep -qF "$FANOUT_EMPTY_POOL" <<< "$FANOUT_SEC"; then
        violate "Fan-out has no 'F-n' rows and no empty-pool line ('$FANOUT_EMPTY_POOL')"
      fi
    fi
  fi

  # ---- Receipt check H: the intake steps (#1022) -----------------------------------------
  # What each intake step did, in a fixed order, so a reader of the record never has to guess
  # which parts of intake ran. Shape-checked wherever present; mandated from v2.
  STEP_ORDER="${INTAKE_STEP_KEYS//|/, }"
  if ! has_section 'intake steps' "$PLAN"; then
    if mandated 'Intake steps'; then
      violate "missing mandated receipt section: Intake steps (a v$RECEIPT_V receipt records each intake step's outcome, one 'Key: outcome' line per step, in this order: $STEP_ORDER)"
    fi
  else
    # section_of closes at ANY heading, so a sub-heading inside the section would cut the steps
    # after it out of what every reader sees.
    sub="$(awk '!on && tolower($0) ~ /^#+[[:space:]]+intake steps[[:space:]]*$/ {match($0, /^#+/); d = RLENGTH; on = 1; next} on && /^#+[[:space:]]/ {match($0, /^#+/); if (RLENGTH > d) print; exit}' "$PLAN")"
    [[ -z "$sub" ]] || violate "Intake steps carries a sub-heading, which ends the section for every reader — drop it, keep the steps in one block: $sub"
    STEPS_SEEN="|"; last_idx=-1; last_key=""
    while IFS= read -r line; do
      line="${line%$'\r'}"
      if [[ "$line" =~ ^(${INTAKE_STEP_KEYS}):(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"; outcome="$(trim "${BASH_REMATCH[2]}")"
        if [[ "$STEPS_SEEN" == *"|$key|"* ]]; then
          violate "Intake steps has more than one '$key:' line — one line per step"
          continue
        fi
        STEPS_SEEN="$STEPS_SEEN$key|"; STEP_COUNT=$((STEP_COUNT + 1))
        [[ -n "$outcome" && ! "$outcome" =~ ^(-|—|–)$ ]] || \
          violate "Intake steps '$key:' records no outcome — say what the step did, or why it did not run"
        # The step line says skipped too, so it names the same skipper the section must (#1023).
        if [[ "$key" == 'Fan-out' ]] && grep -qiE '^skipped([^[:alnum:]_]|$)' <<< "$outcome" \
          && ! grep -qiE "^skipped[[:space:]]*(—|–|-|:)?[[:space:]]*${FANOUT_SKIP_BY}([^[:alnum:]_]|\$)" <<< "$outcome"; then
          violate "Fan-out skip does not name the operator — only the operator skips the fan-out; the Intake steps form is 'Fan-out: skipped — by the operator <where / why>': Fan-out: $outcome"
        fi
        idx=0; IFS='|' read -r -a keys <<< "$INTAKE_STEP_KEYS"
        while [[ "${keys[$idx]}" != "$key" ]]; do idx=$((idx + 1)); done
        (( idx > last_idx )) || violate "Intake steps '$key:' comes after '$last_key:' — the order is $STEP_ORDER"
        last_idx=$idx; last_key="$key"
      elif [[ "$line" =~ ^[[:space:]]*([-*+][[:space:]]+)?(${INTAKE_STEP_KEYS}): ]]; then
        violate "Intake steps line is not read as a step — the form is 'Key: outcome' at the start of the line, with no bullet or indent: $line"
      fi
    done <<< "$(section_of 'intake steps' "$PLAN")"
    IFS='|' read -r -a keys <<< "$INTAKE_STEP_KEYS"
    for key in "${keys[@]}"; do
      [[ "$STEPS_SEEN" == *"|$key|"* ]] || violate "Intake steps has no '$key:' line (the keys, spelled so, in order: $STEP_ORDER)"
    done
  fi

  # ---- Receipt check I: the knowledge source (#1032) --------------------------------------
  # What the consumer-declared knowledge provider answered, or why nothing did. The answer is
  # opaque: it is embedded whole, indented four spaces, so the headings, table rows and
  # `Receipt:` lines it may carry stay out of every column-0 scan (section_of, the ledger and
  # region loops, the version line, verdict-check). Shape-checked wherever present; mandated from v3.
  KS_FORM="absent"
  if ! has_section 'knowledge source' "$PLAN"; then
    if mandated 'Knowledge source'; then
      violate "missing mandated receipt section: Knowledge source (a v$RECEIPT_V receipt carries exactly one form: 'Provider: <plugin>:<agent>' followed by the answer indented four spaces, '$KS_NONE', or 'Knowledge source: failed — <the first line of the error>')"
    fi
  else
    n_provider=0; n_none=0; n_failed=0; n_answer=0; answer_before=0
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      if [[ "$line" == '    '* ]]; then
        n_answer=$((n_answer + 1))
        (( n_provider > 0 )) || answer_before=1
      elif [[ "$line" =~ ^Provider:[[:space:]]*(.*)$ ]]; then
        n_provider=$((n_provider + 1))
        name="$(trim "${BASH_REMATCH[1]}")"
        [[ "$name" =~ ^${KS_PROVIDER_NAME}$ ]] || \
          violate "Knowledge source 'Provider:' names no namespaced agent type — the form is 'Provider: <plugin>:<agent>': $line"
      elif [[ "$line" =~ ^Knowledge\ source: ]]; then
        if [[ "$line" =~ ^${KS_NONE}[[:space:]]*$ ]]; then
          n_none=$((n_none + 1))
        elif [[ "$line" =~ ^Knowledge\ source:[[:space:]]*failed[[:space:]]*(—|–|-|:)[[:space:]]*.*[[:alnum:]] ]]; then
          n_failed=$((n_failed + 1))
        else
          violate "Knowledge source line is neither '$KS_NONE' nor 'Knowledge source: failed — <what failed>': $line"
        fi
      else
        violate "Knowledge source line is not indented four spaces — only the 'Provider:' line and the 'Knowledge source:' forms sit at the start of a line; the answer is indented four spaces so its own headings and rows are never read as this receipt's: $line"
      fi
    done <<< "$(section_of 'knowledge source' "$PLAN")"
    n_forms=$(( (n_provider > 0 ? 1 : 0) + n_none + n_failed ))
    if (( n_provider > 1 )); then
      violate "Knowledge source carries $n_provider 'Provider:' lines — one provider answers, named once"
    fi
    if (( n_forms == 0 && n_answer == 0 )); then
      violate "Knowledge source is empty — it carries exactly one form: the 'Provider:' line and the answer, '$KS_NONE', or 'Knowledge source: failed — <what failed>'"
    elif (( n_forms > 1 || (n_none + n_failed > 0 && n_answer > 0) )); then
      violate "Knowledge source carries more than one form — exactly one of: the 'Provider:' line and the answer, '$KS_NONE', or 'Knowledge source: failed — <what failed>'"
    elif (( n_provider == 0 )); then
      (( n_none + n_failed > 0 )) || violate "Knowledge source carries an answer with no 'Provider: <plugin>:<agent>' line naming who answered"
    else
      (( n_answer > 0 )) || violate "Knowledge source names a provider but carries no answer — embed the whole answer under the 'Provider:' line, indented four spaces"
      (( answer_before == 0 )) || violate "Knowledge source carries answer text before its 'Provider:' line — the line naming who answered comes first"
    fi
    if (( n_provider > 0 )); then KS_FORM="provider"
    elif (( n_none > 0 )); then KS_FORM="none declared"
    elif (( n_failed > 0 )); then KS_FORM="failed"
    else KS_FORM="malformed"; fi
  fi

  # ---- Receipt check J: the test intent (#1039) ------------------------------------------
  # Per acceptance criterion, the behavior its test must prove, or an exemption with a reason. The
  # `ACs:` line is the id set: the lint is offline and never reads the ticket, so an id dropped while
  # transcribing it is invisible here (the record's accepted residual). Ids compare as exact strings,
  # never inferred from contiguity. Shape-checked wherever present; mandated from v4.
  TI_FORM="absent"
  if ! has_section 'test intent' "$PLAN"; then
    if mandated 'Test intent'; then
      violate "missing mandated receipt section: Test intent (a v$RECEIPT_V receipt opens it with 'ACs: AC-1 AC-2 …', the ticket's AC ids, or 'ACs: none — <reason>', then one line per id: 'AC-n: <the observable behavior its test must prove>' or 'AC-n: exempt — <reason>')"
    fi
  else
    n_acs=0; acs_none=0; acs_ids=" "; line_ids=" "; n_exempt=0; n_holds=0; n_unchecked=0
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      if [[ "$line" =~ ^ACs:(.*)$ ]]; then
        n_acs=$((n_acs + 1))
        (( n_acs == 1 )) || continue
        body="$(trim "${BASH_REMATCH[1]}")"
        if [[ "$body" =~ ^none([^[:alnum:]_]|$) ]]; then
          if [[ "$body" =~ ^none[[:space:]]*(—|–|-|:)[[:space:]]*.*[[:alnum:]] ]]; then acs_none=1
          else violate "Test intent 'ACs: none' states no reason — the form is 'ACs: none — <why the ticket has no AC block>': $line"; fi
        elif [[ -z "$body" ]]; then
          violate "Test intent 'ACs:' line lists no id — list the ticket's AC ids as labeled, or 'ACs: none — <reason>'"
        else
          read -r -a toks <<< "$body"
          for tok in "${toks[@]}"; do
            if [[ ! "$tok" =~ ^AC-[0-9]+$ ]]; then
              violate "Test intent 'ACs:' token '$tok' is not an AC id — the line lists 'AC-<n>' ids only, space-separated (a PM-n item is never one): $line"
            elif [[ "$acs_ids" == *" $tok "* ]]; then
              violate "Test intent 'ACs:' lists $tok twice"
            else
              acs_ids="$acs_ids$tok "
            fi
          done
        fi
      elif [[ "$line" =~ ^(AC-[0-9]+):(.*)$ ]]; then
        id="${BASH_REMATCH[1]}"; rest="$(trim "${BASH_REMATCH[2]}")"
        (( n_acs > 0 )) || violate "Test intent line for $id comes before the 'ACs:' line — the section opens with it"
        if [[ "$line_ids" == *" $id "* ]]; then
          violate "Test intent has more than one line for $id — one line per id"
          continue
        fi
        line_ids="$line_ids$id "
        if [[ -z "$rest" ]]; then
          violate "Test intent line for $id states no behavior — say what its test must prove, or 'exempt — <reason>'"
        elif [[ "$rest" =~ ^[Ee]xempt([^[:alnum:]_]|$) ]]; then
          n_exempt=$((n_exempt + 1))
          [[ "$rest" =~ ^[Ee]xempt[[:space:]]*(—|–|-|:)[[:space:]]*.*[[:alnum:]] ]] || \
            violate "Test intent exempts $id with no reason — the form is '$id: exempt — <why no test can prove it>'"
        elif [[ "$rest" =~ ^[Hh]olds([^[:alnum:]_]|$) ]]; then
          n_holds=$((n_holds + 1))
          [[ "$rest" =~ ^[Hh]olds[[:space:]]*(—|–|-|:)[[:space:]]*.*[[:alnum:]] ]] || \
            violate "Test intent marks $id holds with no behavior — the form is '$id: holds — <the existing behavior its test keeps>'"
        elif [[ "$rest" =~ ^[Uu]nchecked([^[:alnum:]_]|$) ]]; then
          n_unchecked=$((n_unchecked + 1))
          [[ "$rest" =~ ^[Uu]nchecked[[:space:]]*(—|–|-|:)[[:space:]]*.*[[:alnum:]] ]] || \
            violate "Test intent marks $id unchecked with no reason — the form is '$id: unchecked — <the tier, and why the scheduler cannot run it>'"
        fi
      else
        violate "Test intent line is neither the 'ACs:' line nor an 'AC-n: …' line at the start of the line: $line"
      fi
    done <<< "$(section_of 'test intent' "$PLAN")"
    if (( n_acs == 0 )); then
      violate "Test intent has no 'ACs:' line — open the section with the ticket's AC ids ('ACs: AC-1 AC-2 …') or 'ACs: none — <reason>'"
    elif (( n_acs > 1 )); then
      violate "Test intent carries $n_acs 'ACs:' lines — the id set is named once"
    fi
    for id in $acs_ids; do
      [[ "$line_ids" == *" $id "* ]] || \
        violate "Test intent has no line for $id — state the behavior its test must prove ('$id: <behavior>'), or exempt it with a reason ('$id: exempt — <reason>')"
    done
    for id in $line_ids; do
      [[ "$acs_ids" == *" $id "* ]] || \
        violate "Test intent has a line for $id, which the 'ACs:' line does not list — an id the ticket does not define, or one missing from 'ACs:'"
    done
    if (( acs_none == 1 )); then TI_FORM="none — no AC block"
    elif (( n_acs > 0 )); then TI_FORM="$(wc -w <<< "$acs_ids" | tr -d ' ') AC(s), $n_exempt exempt"
      (( n_holds + n_unchecked == 0 )) || TI_FORM="$TI_FORM, $n_holds holds, $n_unchecked unchecked"
    else TI_FORM="malformed"; fi
  fi
fi

echo "ledger-lint: ${ROW_COUNT} ledger row(s)"
if (( RECEIPT == 1 )); then
  echo "ledger-lint: ${OPEN_ROW_COUNT} open region(s)"
  echo "ledger-lint: ${SURFACE_ROW_COUNT} surface(s)"
  echo "ledger-lint: ${CHECK_COUNT} check(s)"
  echo "ledger-lint: ${FRAME_ROW_COUNT} design frame(s)"
  echo "ledger-lint: ${FANOUT_ROW_COUNT} fan-out item(s)"
  echo "ledger-lint: ${STEP_COUNT} intake step(s)"
  echo "ledger-lint: knowledge source: ${KS_FORM}"
  echo "ledger-lint: test intent: ${TI_FORM}"
  echo "ledger-lint: receipt v${RECEIPT_V}"
fi
if (( VIOLATIONS > 0 )); then
  echo "ledger-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "ledger-lint: OK"
exit 0
