#!/usr/bin/env bash
#
# Self-test for the stacked-PR outer-loop SLICE DERIVATION algorithm.
#
# A self-test in the style of statectl-selftest.sh, located under tools/.
# Pure-local, $0, no Claude CLI / no network / no git remote calls.
#
# WHY this exists (issue #149): the slice-derivation pre-check in
# stages/1-intake.md ("Stacked-PR Outer Loop") is the densest pseudo-code in the
# pipeline and had the least coverage. This self-test exercises the algorithm
# across scenarios AND drift-guards against the source so a future refactor of
# 1-intake.md can't silently diverge from what is tested here.
#
# DRIFT MODEL: this script RE-IMPLEMENTS the algorithm locally (the source lives
# as inline pseudo-code in a markdown stage file, not as an importable function).
# The `parity_check` at the end greps 1-intake.md for the load-bearing tokens so
# divergence fails loudly rather than passing against stale logic. Same technique
# as statectl-selftest's validator drift-check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTAKE_STAGE="$SCRIPT_DIR/../stages/1-intake.md"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
# Faithful re-implementation of stages/1-intake.md slice-derivation (lines
# ~65-92). Inputs are passed explicitly so there is NO git / statectl dependency:
#   $1 ISSUE_NUMBER
#   $2 TOTAL_SLICES
#   $3 PERSISTED   — the persisted .currentSlice ("" / "null" when absent)
#   stdin          — newline-separated branch refs exactly as
#                    `git ls-remote --heads origin ... | awk '{print $2}'` emits
#                    them, i.e. full "refs/heads/claude/acme-149[-prK]".
# Output (stdout): "START=<n>"  or  "ALL_PUSHED"
# ---------------------------------------------------------------------------
derive_start_slice() {
  local ISSUE_NUMBER="$1" TOTAL_SLICES="$2" PERSISTED="$3"
  local START_SLICE MAX_N ref name n

  if [[ -n "$PERSISTED" && "$PERSISTED" != "null" ]]; then
    echo "START=$PERSISTED"
    return 0
  fi

  MAX_N=0
  while read -r ref; do
    [[ -z "$ref" ]] && continue
    # MUST match the source: strip ONLY refs/heads/ (not `##*/`, which over-strips
    # the claude/ segment so nothing ever matches — the bug this self-test caught).
    name="${ref#refs/heads/}"
    if [[ "$name" == "claude/acme-${ISSUE_NUMBER}" ]]; then
      (( MAX_N < 1 )) && MAX_N=1
    elif [[ "$name" =~ ^claude/acme-${ISSUE_NUMBER}-pr([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
      (( n > MAX_N )) && MAX_N=$n
    fi
  done

  if [[ "$MAX_N" -ge "$TOTAL_SLICES" ]]; then
    echo "ALL_PUSHED"
    return 0
  fi
  START_SLICE=$((MAX_N + 1))
  echo "START=$START_SLICE"
}

# All refs below are full "refs/heads/..." forms — exactly what
# `git ls-remote --heads origin ... | awk '{print $2}'` emits in the source.
expect() {
  local desc="$1" want="$2" got="$3"
  [[ "$got" == "$want" ]] && ok "$desc → $got" || bad "$desc: want '$want' got '$got'"
}

echo "=== slice-derivation algorithm ==="

# 1. Persisted currentSlice is authoritative — wins even when branches disagree.
got=$(printf 'refs/heads/claude/acme-149\nrefs/heads/claude/acme-149-pr2\nrefs/heads/claude/acme-149-pr3\n' \
  | derive_start_slice 149 3 "2")
expect "persisted currentSlice precedence (=2, branches say all pushed)" "START=2" "$got"

# 2. Persisted absent, only slice-1 unsuffixed branch pushed → resume at slice 2.
got=$(printf 'refs/heads/claude/acme-149\n' | derive_start_slice 149 3 "")
expect "seed: slice 1 only (unsuffixed)" "START=2" "$got"

# 3. Persisted absent, up to pr2 pushed → resume at slice 3.
got=$(printf 'refs/heads/claude/acme-149\nrefs/heads/claude/acme-149-pr2\n' \
  | derive_start_slice 149 3 "")
expect "seed: up to pr2" "START=3" "$got"

# 4. Persisted absent, all 3 slices pushed → all-pushed early exit.
got=$(printf 'refs/heads/claude/acme-149\nrefs/heads/claude/acme-149-pr2\nrefs/heads/claude/acme-149-pr3\n' \
  | derive_start_slice 149 3 "")
expect "seed: all slices pushed → ALL_PUSHED" "ALL_PUSHED" "$got"

# 5. Persisted absent, no matching branches → start at slice 1.
got=$(printf '' | derive_start_slice 149 3 "")
expect "seed: no branches → slice 1" "START=1" "$got"

# 6. Out-of-order refs + a higher pr at/above TOTAL → ALL_PUSHED (MAX_N>=TOTAL).
got=$(printf 'refs/heads/claude/acme-149-pr3\nrefs/heads/claude/acme-149\nrefs/heads/claude/acme-149-pr2\n' \
  | derive_start_slice 149 3 "")
expect "seed: out-of-order refs, max=3" "ALL_PUSHED" "$got"

# 7. "null" persisted is treated as absent (falls through to seed).
got=$(printf 'refs/heads/claude/acme-149\n' | derive_start_slice 149 3 "null")
expect "persisted='null' treated as absent" "START=2" "$got"

# 8. Cross-issue isolation: branches for OTHER issues must not bump MAX_N.
#    (149 vs 1490 / 14 / 1490-pr5 — exact-equality + anchored regex must reject.)
got=$(printf 'refs/heads/claude/acme-1490\nrefs/heads/claude/acme-14\nrefs/heads/claude/acme-1490-pr5\nrefs/heads/claude/acme-149\n' \
  | derive_start_slice 149 3 "")
expect "cross-issue refs ignored (only 149 counts)" "START=2" "$got"

# 9. Cross-issue isolation with NO real 149 branch → slice 1 (foreign refs inert).
got=$(printf 'refs/heads/claude/acme-1490-pr2\nrefs/heads/claude/acme-150\n' \
  | derive_start_slice 149 3 "")
expect "only foreign refs → slice 1" "START=1" "$got"

# ---------------------------------------------------------------------------
# branchPrefix parameterization: the REAL max-pushed-slice.sh honors
# $BRANCH_PREFIX so one helper serves both trackers (github "claude/acme-",
# jira "jdoe/"). Default (unset) stays "claude/acme-".
# ---------------------------------------------------------------------------
echo "=== branchPrefix parameterization (real max-pushed-slice.sh) ==="
MPS="$SCRIPT_DIR/max-pushed-slice.sh"
# github default (no BRANCH_PREFIX): unsuffixed + pr2 → 2
got=$(printf 'refs/heads/claude/acme-149\nrefs/heads/claude/acme-149-pr2\n' | bash "$MPS" 149)
expect "default prefix (claude/acme-): max=2" "2" "$got"
# jira prefix jdoe/ with a JIRA key gh-540: unsuffixed + pr3 → 3
got=$(printf 'refs/heads/jdoe/gh-540\nrefs/heads/jdoe/gh-540-pr3\n' | BRANCH_PREFIX="jdoe/" bash "$MPS" gh-540)
expect "jira prefix (jdoe/, key gh-540): max=3" "3" "$got"
# cross-key isolation under a custom prefix: gh-5400 must not bump gh-540
got=$(printf 'refs/heads/jdoe/gh-5400\nrefs/heads/jdoe/gh-540\n' | BRANCH_PREFIX="jdoe/" bash "$MPS" gh-540)
expect "jira prefix cross-key isolation: max=1" "1" "$got"

# ---------------------------------------------------------------------------
# Drift parity: assert 1-intake.md still carries the load-bearing tokens this
# self-test models. If the stage is refactored, this fails loudly.
# ---------------------------------------------------------------------------
echo "=== drift parity vs derivation source files ==="
# The ref-parsing primitives (refs/heads strip, pr-suffix regex) were refactored out
# of 1-intake.md into the shared helper max-pushed-slice.sh; the inline pre-check
# tokens (currentSlice precedence, unsuffixed match, MAX_N, all-pushed guard) stay in
# 1-intake.md. parity_check takes the file so each token is asserted where it lives.
MAX_PUSHED="$SCRIPT_DIR/max-pushed-slice.sh"
parity_check() {
  local label="$1" pattern="$2" file="${3:-$INTAKE_STAGE}"
  if grep -Eq -- "$pattern" "$file"; then
    ok "${file##*/} contains: $label"
  else
    bad "${file##*/} MISSING token ($label) — derivation drifted from this self-test: /$pattern/"
  fi
}
if [[ ! -f "$INTAKE_STAGE" ]]; then
  bad "1-intake.md not found at $INTAKE_STAGE"
elif [[ ! -f "$MAX_PUSHED" ]]; then
  bad "max-pushed-slice.sh not found at $MAX_PUSHED"
else
  # Inline in 1-intake.md (the slice-derivation pre-check):
  parity_check "currentSlice precedence read"   'currentSlice // empty'
  parity_check "unsuffixed slice-1 match"       'claude/acme-\$\{ISSUE_NUMBER\}'
  parity_check "MAX_N accumulator"              'MAX_N'
  # shellcheck disable=SC2016 # literal $TOTAL_SLICES is the grep pattern, not an expansion
  parity_check "all-pushed early-exit guard"    'MAX_N" -ge "\$TOTAL_SLICES'
  # Refactored into the shared helper max-pushed-slice.sh:
  parity_check "refs/heads-only ref strip"      'name="\$\{ref#refs/heads/\}"'    "$MAX_PUSHED"
  parity_check "pr-suffix capture regex"        '-pr\(\[0-9\]\+\)\$'              "$MAX_PUSHED"
  parity_check "branchPrefix parameterization"  'PREFIX="\$\{BRANCH_PREFIX:-claude/acme-\}"' "$MAX_PUSHED"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
