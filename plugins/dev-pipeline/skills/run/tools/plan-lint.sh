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
#      Slice mode (#204): with a valid `decomposition.slices[]` partition AND a
#      non-null `currentSlice`, the universe narrows to this slice's acIds — a
#      row for another slice's AC violates (fabricated coverage). A partition
#      failing the union-integrity check voids slice mode (full-snapshot
#      universe, fail-closed).
#   4. Decision Ledger provenance legality: a `| D-n |` row carrying a
#      human-attributed provenance (`user-answered` / `user-delegated`) is a
#      hard FAIL unless the backing `{issue}-ledger.md` — the sibling of the
#      passed <state-path> — exists. `codebase-derived` / `deferred` rows pass
#      unconditionally, and an absent ledger section (or the explicit empty
#      form) is untouched by this check (the section stays advisory, below).
#      Fail-closed when human-attributed rows are present but no <state-path>
#      was given to resolve the ledger context.
#   5. [NEW] grounding-tag presence (#175 retro): eval criterion 2 is grep-scored,
#      so a reference the plan CREATES must carry the literal [NEW] tag — prose
#      conventions score FAIL at retro time regardless of grounding quality.
#      5a. A backtick-quoted repo path (contains /, dotted final segment, top
#          directory exists in the plan's repo, not .claude/-scoped) that does
#          not exist on disk must sit on a line carrying [NEW] or [UNVERIFIED].
#      5b. Two or more creation-verb steps (Add/Create/Introduce at a numbered
#          or bulleted step) with ZERO [NEW] tokens anywhere in the plan is the
#          run-#175 shape: planned creations with no tags. One named violation.
#   6. Decision Ledger hydration completeness (#190): the FORWARD twin of Check 4.
#      When a backing {issue}-ledger.md carries >=1 `| D-n |` row, Stage 3 mandates
#      hydrating those rows into the plan's Decision Ledger section VERBATIM, so
#      each backing row must reappear with a whitespace-trimmed-equal Decision,
#      Resolution, AND Provenance cell. A missing plan row, a drifted cell, or (when
#      the backing ledger has rows) a wholly absent Decision Ledger section is one
#      named violation each. No backing ledger / empty-form / zero-row backing → a
#      no-op (byte-identical to a no-backing run; the section stays advisory below).
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
# DO NOT add "Decision Ledger" to this HARD set: its presence is only CONDITIONALLY
# hard. Absent a backing pre-flight ledger it is advisory-only in-pipeline (see the
# advisory check near the bottom of this file) — the autonomous contract forbids
# prompting mid-run, so a run legitimately authors the ledger's explicit-empty-form or
# `codebase-derived`/`deferred` rows, and a run that omits the section entirely must
# NOT hard-abort Stage 4 (which maps any plan-lint violation to `mark-failed --reason
# plan-structure-invalid`). Its presence becomes hard ONLY when a backing ledger with
# >=1 `D-n` row exists — enforced by Check 6, NOT by this unconditional array. Keeping
# the ledger out of this array is what preserves the advisory default; the "keep
# SECTIONS in lockstep with stages/3-write-plan.md" instinct is the trap this comment
# exists to stop.
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
# Slice mode (#204): when the state also carries the Stage-1 AC->slice partition
# (`decomposition.slices[]`) AND a non-null `currentSlice`, the Check-3 universe
# narrows to THIS slice's acIds — a slice plan rows only the ACs it implements,
# and a row for another slice's AC is fabricated coverage (one named violation).
# Integrity fail-closed: a partition whose acIds union != the snapshot id set
# voids slice mode and the universe stays the FULL snapshot (degradation grades
# more, never less). Contract: state-schema.md "Stacked-PR AC partition".
if [[ -n "$STATE" ]]; then
  if ! SNAPSHOT_IDS=$(jq -er '.acceptanceCriteria // [] | .[].id' "$STATE" 2>/dev/null); then
    SNAPSHOT_IDS=""
  fi
  UNIVERSE_IDS="$SNAPSHOT_IDS"
  SLICE_MODE=""
  if [[ -n "$SNAPSHOT_IDS" ]]; then
    CUR_SLICE=$(jq -r '.currentSlice // empty' "$STATE" 2>/dev/null || true)
    if [[ -n "$CUR_SLICE" && "$CUR_SLICE" != "null" ]]; then
      PARTITION_OK=$(jq -r '
        (.decomposition.slices // []) as $slices
        | (.acceptanceCriteria // [] | map(.id)) as $snap
        | ($slices | length) > 0 and (([$slices[].acIds[]] | sort | unique) == ($snap | sort | unique))
      ' "$STATE" 2>/dev/null || echo false)
      if [[ "$PARTITION_OK" == "true" ]]; then
        SLICE_IDS=$(jq -r --argjson n "$CUR_SLICE" \
          '.decomposition.slices[] | select(.slice == $n) | .acIds[]' "$STATE" 2>/dev/null || true)
        if [[ -n "$SLICE_IDS" ]]; then
          UNIVERSE_IDS="$SLICE_IDS"
          SLICE_MODE=1
        fi
      fi
    fi
  fi
  if [[ -n "$UNIVERSE_IDS" ]]; then
    while IFS= read -r sid; do
      hits=0
      if (( ${#ROW_IDS[@]} > 0 )); then
        for rid in "${ROW_IDS[@]}"; do [[ "$rid" == "$sid" ]] && hits=$((hits + 1)); done
      fi
      (( hits == 1 )) || violate "snapshot id $sid has $hits traceability row(s) (expected exactly 1)"
    done <<< "$UNIVERSE_IDS"
    if (( ${#ROW_IDS[@]} > 0 )); then
      for rid in "${ROW_IDS[@]}"; do
        if ! grep -qx "$rid" <<< "$UNIVERSE_IDS"; then
          if [[ -n "$SLICE_MODE" ]] && grep -qx "$rid" <<< "$SNAPSHOT_IDS"; then
            violate "table row $rid belongs to another slice (slice mode: universe is slice ${CUR_SLICE}'s acIds — a row for another slice's AC is fabricated coverage)"
          else
            violate "table row $rid does not exist in the state acceptanceCriteria snapshot"
          fi
        fi
      done
    fi
  fi
  # Empty/absent snapshot → structure-only by design (pre-schema resumes, no-AC runs).
fi

# ---- Check 4: Decision Ledger provenance legality ---------------------------
# Human-attributed provenance (user-answered / user-delegated) asserts a human
# made the call. In-pipeline that is legitimate ONLY when a pre-flight
# /plan-interview wrote the backing {issue}-ledger.md; the autonomous contract
# forbids prompting mid-run, so a run authoring such a row with no backing file is
# the fabrication class this check closes (a run negotiating its provenance to
# satisfy a gate). codebase-derived / deferred rows pass unconditionally, and a
# plan that omits the ledger (or uses the explicit empty form) is untouched here —
# the section stays advisory (below), NOT a mandated hard-gated section.
#
# mirror of interviewing-baseline provenance enum — the HUMAN-ATTRIBUTED SUBSET;
# keep in lockstep with plan-interview/tools/ledger-lint.sh's PROVENANCE_ENUM. If
# #147 adds an operator-attributed value, it joins this subset here too.
# Enforced as a `subset-of` pair by scripts/check-lockstep-pairs.sh — deliberately NOT
# verbatim: this literal is a proper narrowing of the canonical enum.
# LOCKSTEP-BEGIN provenance-enum
HUMAN_PROVENANCE='user-answered|user-delegated'
# LOCKSTEP-END provenance-enum
# The backing ledger is the SIBLING of the state file: both live in the main-repo
# .claude/pipeline-state/, keyed by the same issue number ({issue}.json /
# {issue}-ledger.md). Derived from <state-path> — no extra argument, no call-site
# change. Empty when no state path was passed (fail-closed branch below).
LEDGER_FILE=""
[[ -n "$STATE" ]] && LEDGER_FILE="$(dirname "$STATE")/$(basename "$STATE" .json)-ledger.md"

declare -a HUMAN_ROWS=()
while IFS= read -r line; do
  masked="${line//\\|/${PIPE_SENTINEL:-__PLAN_LINT_PIPE__}}"
  IFS='|' read -r -a cells <<< "$masked"
  # cells[1] is the anchored `D-n` id (the row grep guarantees it). Scan every
  # OTHER cell for a cell whose ENTIRE trimmed content is a human-attributed
  # provenance token — not just cells[4] — so a malformed (wrong-column-count) row
  # cannot smuggle a human provenance past the gate (in-pipeline ledger-lint.sh
  # does not run, so this is the only gate). The `^...$` anchor keeps prose that
  # merely mentions the enum from false-positiving — only a bare-token cell matches.
  did="$(trim "${cells[1]}")"
  human=0
  for (( ci = 2; ci < ${#cells[@]}; ci++ )); do
    [[ "$(trim "${cells[ci]}")" =~ ^(${HUMAN_PROVENANCE})$ ]] && { human=1; break; }
  done
  (( human == 1 )) && HUMAN_ROWS+=("$did")
done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$PLAN" || true)

if (( ${#HUMAN_ROWS[@]} > 0 )); then
  if [[ -n "$LEDGER_FILE" && -f "$LEDGER_FILE" ]]; then
    : # backed by a pre-flight ledger — the human-attributed rows are legitimate
  elif [[ -n "$LEDGER_FILE" ]]; then
    violate "Decision Ledger row(s) ${HUMAN_ROWS[*]} carry human-attributed provenance (${HUMAN_PROVENANCE//|/ / }) but no backing ledger file exists at $LEDGER_FILE — an autonomous run may only use codebase-derived/deferred (run /plan-interview pre-flight to author human-attributed rows)"
  else
    # No state path ⇒ the ledger context is unresolvable. Fail closed rather than
    # silently no-op: the #110 fabrication happened on a crash-recovery resume.
    violate "Decision Ledger row(s) ${HUMAN_ROWS[*]} carry human-attributed provenance (${HUMAN_PROVENANCE//|/ / }) but no state path was given to resolve the backing {issue}-ledger.md (fail-closed)"
  fi
fi

# ---- Check 5: [NEW] grounding-tag presence (#175 retro) ---------------------
# 5a: nonexistent untagged path = either a planned creation (tag it [NEW]) or a
# typo (fix it). Precision guards: token must contain a slash and a dotted final
# segment (skips branch names like origin/main), its top directory must exist in
# the plan's repo (skips fixture plans referencing a fictional tree), and
# .claude/ paths are skipped (pipeline-state artifacts live in the MAIN repo and
# are legitimately absent from worktrees).
BT="$(printf '\140')"   # a literal backtick, built via octal so grep patterns can double-quote it (avoids SC2016 noise)
PLAN_ROOT="$(git -C "$(cd "$(dirname "$PLAN")" && pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$PLAN_ROOT" ]]; then
  while IFS= read -r pline; do
    lineno="${pline%%:*}"; content="${pline#*:}"
    grep -qE '\[(NEW|UNVERIFIED)\]' <<< "$content" && continue
    while IFS= read -r tok; do
      [[ -z "$tok" ]] && continue
      [[ "$tok" == .claude/* ]] && continue
      topdir="${tok%%/*}"
      [[ -d "$PLAN_ROOT/$topdir" ]] || continue
      [[ -e "$PLAN_ROOT/$tok" ]] && continue
      violate "line $lineno references \`$tok\` which does not exist — tag it [NEW] (planned creation) or fix the path (grounding-tag rule, stages/3-write-plan.md)"
    done < <(grep -oE "${BT}[A-Za-z0-9_./-]+${BT}" <<< "$content" | tr -d "\`" \
             | grep -E '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_-]+\.[A-Za-z0-9_.]+$' || true)
  done < <(grep -nE "${BT}[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+${BT}" "$PLAN" || true)
fi
# 5b: the run-#175 shape — creation-verb steps with zero tags anywhere.
CREATION_LINES=$(grep -cE '^[[:space:]]*([0-9]+\.|-)[[:space:]].*\b(Add|add|Create|create|Introduce|introduce)\b' "$PLAN") || true
if (( ${CREATION_LINES:-0} >= 2 )) && ! grep -q '\[NEW\]' "$PLAN"; then
  violate "$CREATION_LINES creation-verb step(s) but zero [NEW] grounding tags anywhere in the plan — tag every reference the plan creates with the literal [NEW] token (grounding-tag rule, stages/3-write-plan.md; eval criterion 2 is grep-scored)"
fi

# ---- Check 6: Decision Ledger hydration completeness (#190) ------------------
# The FORWARD twin of Check 4. When a pre-flight /plan-interview wrote the backing
# {issue}-ledger.md, Stage 3 mandates hydrating its rows into the plan's Decision
# Ledger section VERBATIM (stages/3-write-plan.md). This gate enforces that: every
# backing `D-n` row must reappear in the plan with a whitespace-trimmed-equal
# Decision, Resolution, AND Provenance cell (all three — "verbatim", not a subset).
#
# Parse rule: positional per the canonical `ID | Decision | Resolution | Provenance`
# schema (mirror of plan-interview/tools/ledger-lint.sh, which validated the backing
# ledger's shape/enum at pre-flight) that verbatim hydration preserves — cells[2]=
# Decision, cells[3]=Resolution, cells[4]=Provenance. A plan that reorders its ledger
# columns while claiming verbatim hydration has itself drifted, so a mismatch there is
# a correct violation, not a false positive. Comparison uses trim() (leading/trailing
# only — neutralizes prettier's per-table column padding); internal whitespace is
# significant.
#
# Scope: no-op unless a backing ledger with >=1 `D-n` row exists ($LEDGER_FILE is the
# same sibling-of-state path Check 4 derived). An absent / empty-form / zero-row
# backing ledger has nothing to hydrate, so behavior is byte-identical to a no-backing
# run (preserves the existing corpus). bash 3.2 — parallel indexed arrays, no assoc.
LEDGER_MISSING_SECTION=0
if [[ -n "$LEDGER_FILE" && -f "$LEDGER_FILE" ]]; then
  declare -a BACK_ID=() BACK_DEC=() BACK_RES=() BACK_PROV=()
  while IFS= read -r line; do
    masked="${line//\\|/${PIPE_SENTINEL:-__PLAN_LINT_PIPE__}}"
    IFS='|' read -r -a cells <<< "$masked"
    # Malformed backing row (wrong column count): ledger-lint owns it at pre-flight;
    # Check 6 only hydration-checks well-formed backing rows.
    (( ${#cells[@]} < 5 || ${#cells[@]} > 6 )) && continue
    BACK_ID+=("$(trim "${cells[1]}")")
    BACK_DEC+=("$(trim "${cells[2]}")")
    BACK_RES+=("$(trim "${cells[3]}")")
    BACK_PROV+=("$(trim "${cells[4]}")")
  done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$LEDGER_FILE" || true)

  if (( ${#BACK_ID[@]} > 0 )); then
    # Backing ledger carries material rows → the plan MUST carry a hydrated section.
    if ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$PLAN"; then
      violate "backing ledger $LEDGER_FILE carries ${#BACK_ID[@]} decision row(s) but the plan has no Decision Ledger section — hydrate them verbatim (stages/3-write-plan.md)"
      LEDGER_MISSING_SECTION=1
    else
      declare -a PLAN_ID=() PLAN_DEC=() PLAN_RES=() PLAN_PROV=()
      while IFS= read -r line; do
        masked="${line//\\|/${PIPE_SENTINEL:-__PLAN_LINT_PIPE__}}"
        IFS='|' read -r -a cells <<< "$masked"
        (( ${#cells[@]} < 5 || ${#cells[@]} > 6 )) && continue
        PLAN_ID+=("$(trim "${cells[1]}")")
        PLAN_DEC+=("$(trim "${cells[2]}")")
        PLAN_RES+=("$(trim "${cells[3]}")")
        PLAN_PROV+=("$(trim "${cells[4]}")")
      done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$PLAN" || true)

      for (( bi = 0; bi < ${#BACK_ID[@]}; bi++ )); do
        bid="${BACK_ID[bi]}"
        found=-1
        for (( pi = 0; pi < ${#PLAN_ID[@]}; pi++ )); do
          [[ "${PLAN_ID[pi]}" == "$bid" ]] && { found="$pi"; break; }
        done
        if (( found < 0 )); then
          violate "backing ledger row $bid is not hydrated into the plan's Decision Ledger section (Stage-3 verbatim mandate)"
          continue
        fi
        [[ "${PLAN_DEC[found]}" == "${BACK_DEC[bi]}" ]] || violate "$bid Decision cell drifted from the backing ledger (verbatim hydration required)"
        [[ "${PLAN_RES[found]}" == "${BACK_RES[bi]}" ]] || violate "$bid Resolution cell drifted from the backing ledger (verbatim hydration required)"
        [[ "${PLAN_PROV[found]}" == "${BACK_PROV[bi]}" ]] || violate "$bid Provenance '${PLAN_PROV[found]}' does not match the backing ledger '${BACK_PROV[bi]}' (verbatim hydration required)"
      done
    fi
  fi
fi

# ---- Advisory: Decision Ledger presence (never a violation) -------------------
# Deep checks live in plan-interview/tools/ledger-lint.sh; in-pipeline the ledger
# is advisory-only (user-provenance rows can only come from a pre-flight
# /plan-interview — the autonomous contract forbids prompting mid-run), so a
# missing section WARNS but never trips the Stage-4 hard gate. Deliberately kept
# out of the mandated-SECTIONS array above. Suppressed when Check 6 already
# hard-flagged the same absent section (a backing ledger with rows) — else the
# missing section would be reported twice.
if (( LEDGER_MISSING_SECTION == 0 )) \
   && ! grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger' "$PLAN"; then
  echo "plan-lint: WARNING (advisory): no Decision Ledger section — see stages/3-write-plan.md / interviewing-baseline"
fi

echo "plan-lint: ${NO_TEST_COUNT} '— no test' row(s), ${#ROW_IDS[@]} traceability row(s)"
if (( VIOLATIONS > 0 )); then
  echo "plan-lint: FAIL — $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "plan-lint: OK"
exit 0
