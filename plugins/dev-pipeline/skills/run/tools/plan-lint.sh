#!/usr/bin/env bash
# plan-lint.sh — deterministic structural lint for Stage-3 plan files.
#
# Usage: plan-lint.sh <plan-path> [<state-path>]
#
# Checks (read-only, bash+jq — no network, no writes):
#   1. Mandated section headers present (the unconditional set from
#      stages/3-write-plan.md; the conditional unit-test-surface enumeration
#      is NOT linted).
#   2. Acceptance-criteria traceability table well-formed: every `| AC-n |`
#      row has 4 columns, a non-empty Step(s) cell, and a Test(s) cell that
#      is either non-empty test content or the exact escape hatch
#      `— no test (<category>)` with <category> from the closed enum
#      `non-functional | infra-only | covered-by-selftest | covered-by-render-verify`.
#   3. When <state-path> is given and carries a non-empty `acceptanceCriteria[]`
#      (the Stage-1 snapshot): table rows ⇄ snapshot ids exactly 1:1.
#
# Degradation: no state path / pre-schema state / empty `acceptanceCriteria[]`
# → checks 1-2 only. An empty table under a present traceability header with an
# empty snapshot passes.
#
# Scope honesty (ADR-018): this lint buys structural presence + on-page
# disclosure, NOT coverage enforcement — coverage quality stays with the
# Stage-4 plan-reviewer and the pipeline-retro AC-coverage audit. It reports
# the `— no test` row count on stdout so those consumers can weigh it.
#
# Exit: 0 clean, 1 violations (each named on stderr), 2 usage/IO error.
set -euo pipefail

PLAN="${1:-}"
STATE="${2:-}"

[[ -n "$PLAN" ]] || { echo "plan-lint: usage: plan-lint.sh <plan-path> [<state-path>]" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "plan-lint: plan file not found: $PLAN" >&2; exit 2; }
if [[ -n "$STATE" && ! -f "$STATE" ]]; then
  echo "plan-lint: state file not found: $STATE" >&2; exit 2
fi

VIOLATIONS=0
violate() { echo "plan-lint: VIOLATION: $1" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }

# quoting-safe whitespace trim — xargs aborts on quotes/apostrophes/backslashes in cells
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---- Check 1: mandated section headers -------------------------------------
# A section counts as present when a markdown heading (or a bold-line header)
# matches its pattern, case-insensitive.
section_present() {
  grep -qiE "^(#{1,6}[[:space:]]+|\*\*).*$1" "$PLAN"
}
# name<TAB>pattern — patterns use `.` where hyphen/space variants both occur.
# DO NOT add "Decision Ledger" to this HARD set: it is advisory-only in-pipeline
# (see the advisory check near the bottom of this file). The autonomous contract
# forbids prompting mid-run, so a run legitimately authors the ledger's
# explicit-empty-form or `codebase-derived`/`deferred` rows — but a run that omits
# the section entirely must NOT hard-abort Stage 4 (which maps any plan-lint
# violation to `mark-failed --reason plan-structure-invalid`). Keeping the ledger
# out of this array is what preserves that; the "keep SECTIONS in lockstep with
# stages/3-write-plan.md" instinct is the trap this comment exists to stop.
SECTIONS=$'Context\tcontext
Assumptions\tassumptions
Affected files\taffected files
Reuse inventory\treuse inventory
Implementation steps\timplementation steps
Test strategy\ttest strategy
Acceptance-criteria traceability\tacceptance.criteria traceability
Verification commands\tverification commands
Risks\trisks
Out-of-scope\tout.of.scope'
while IFS=$'\t' read -r name pattern; do
  section_present "$pattern" || violate "missing mandated section: $name"
done <<< "$SECTIONS"

# ---- Check 2: traceability table rows ---------------------------------------
# Rows are matched by the anchored `| AC-n |` first column — never by column
# arithmetic on the whole document. Literal pipes inside cells are GFM-escaped
# (`\|`, enforced by the mandated prettier pass); mask them before splitting so
# they cannot corrupt column parsing.
NO_TEST_ENUM='non-functional|infra-only|covered-by-selftest|covered-by-render-verify'
NO_TEST_COUNT=0
declare -a ROW_IDS=()

while IFS= read -r line; do
  masked="${line//\\|/${PIPE_SENTINEL:-__PLAN_LINT_PIPE__}}"
  IFS='|' read -r -a cells <<< "$masked"
  # 4-column row splits into: leading-empty, id, criterion, steps, tests[, trailing-empty]
  if (( ${#cells[@]} < 5 || ${#cells[@]} > 6 )); then
    violate "malformed traceability row (expected 4 columns): $line"
    continue
  fi
  id="$(trim "${cells[1]}")"
  steps="$(trim "${cells[3]}")"
  tests="$(trim "${cells[4]}")"
  ROW_IDS+=("$id")
  [[ -n "$steps" ]] || violate "$id row has an empty Step(s) cell"
  if [[ -z "$tests" ]]; then
    violate "$id row has an empty Test(s) cell (use tests or '— no test (<category>)')"
  elif [[ "$tests" =~ ^(—|--)[[:space:]]*no[[:space:]]test ]]; then
    if [[ "$tests" =~ ^(—|--)[[:space:]]*no[[:space:]]test[[:space:]]*\((${NO_TEST_ENUM})\)$ ]]; then
      NO_TEST_COUNT=$((NO_TEST_COUNT + 1))
    else
      violate "$id row: no-test justification must be '— no test (<category>)' with category in {${NO_TEST_ENUM//|/ | }}: got '$tests'"
    fi
  fi
done < <(grep -E '^\|[[:space:]]*AC-[0-9]+[[:space:]]*\|' "$PLAN" || true)

# Duplicate row ids are a violation regardless of state presence.
if (( ${#ROW_IDS[@]} > 0 )); then
  dupes=$(printf '%s\n' "${ROW_IDS[@]}" | sort | uniq -d)
  [[ -z "$dupes" ]] || violate "duplicate traceability rows for: $(echo "$dupes" | tr '\n' ' ')"
fi

# ---- Check 3: 1:1 with the Stage-1 snapshot ---------------------------------
if [[ -n "$STATE" ]]; then
  if ! SNAPSHOT_IDS=$(jq -er '.acceptanceCriteria // [] | .[].id' "$STATE" 2>/dev/null); then
    SNAPSHOT_IDS=""
  fi
  if [[ -n "$SNAPSHOT_IDS" ]]; then
    while IFS= read -r sid; do
      hits=0
      if (( ${#ROW_IDS[@]} > 0 )); then
        for rid in "${ROW_IDS[@]}"; do [[ "$rid" == "$sid" ]] && hits=$((hits + 1)); done
      fi
      (( hits == 1 )) || violate "snapshot id $sid has $hits traceability row(s) (expected exactly 1)"
    done <<< "$SNAPSHOT_IDS"
    if (( ${#ROW_IDS[@]} > 0 )); then
      for rid in "${ROW_IDS[@]}"; do
        grep -qx "$rid" <<< "$SNAPSHOT_IDS" || violate "table row $rid does not exist in the state acceptanceCriteria snapshot"
      done
    fi
  fi
  # Empty/absent snapshot → structure-only by design (pre-schema resumes, no-AC runs).
fi

# ---- Advisory: Decision Ledger presence (never a violation) -------------------
# Deep checks live in plan-interview/tools/ledger-lint.sh; in-pipeline the ledger
# is advisory-only (user-provenance rows can only come from a pre-flight
# /plan-interview — the autonomous contract forbids prompting mid-run), so a
# missing section WARNS but never trips the Stage-4 hard gate. Deliberately kept
# out of the mandated-SECTIONS array above.
if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$PLAN"; then
  echo "plan-lint: WARNING (advisory): no Decision Ledger section — see stages/3-write-plan.md / interviewing-baseline"
fi

echo "plan-lint: ${NO_TEST_COUNT} '— no test' row(s), ${#ROW_IDS[@]} traceability row(s)"
if (( VIOLATIONS > 0 )); then
  echo "plan-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "plan-lint: OK"
exit 0
