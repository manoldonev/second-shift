#!/usr/bin/env bash
#
# Self-test for the Stage-1 read-surface pin wiring (#59).
#
# A drift-check in the style of claim-selftest.sh's parity tail: pure-local, no
# Claude CLI, no network. The pin is model-executed prose (stages/1-intake.md
# Step 1.P) plus ONE code seam — the `readRoot` arg in workflows/intake-review.mjs
# that prefixes every dispatch prompt with the pinned-read instruction. This test
# pins the load-bearing tokens of that seam so a refactor cannot silently drop the
# pin from one (or both) dispatch prompts, and guards AC-5: the
# `non-main-base-autonomous` reason value is retained (re-semanticized to the
# pin-failure trigger, never renamed/retired).
#
# WHY grep-shaped (and grep-ONLY): intake-review.mjs runs inside the Workflow
# tool's runtime (its globals — agent()/parallel()/log() — are injected there, and
# the script body executes in an async context that permits top-level `return`),
# so it can be neither executed nor even `node --check`ed here — the top-level
# returns are a SyntaxError to node's module parser by design. Token assertions
# are the same technique null-reviewer-selftest.mjs uses for code-review.mjs's
# load-bearing tokens.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")"                    # skills/run
WORKFLOW="$RUN_DIR/workflows/intake-review.mjs"
SCHEMA="$RUN_DIR/state-schema.md"
INTAKE_STAGE="$RUN_DIR/stages/1-intake.md"
CLEANUP_STAGE="$RUN_DIR/stages/10-cleanup.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

echo "intake-readroot-selftest: Stage-1 read-pin wiring (#59)"

# --- (1) intake-review.mjs carries the readRoot seam --------------------------
if grep -q "readRoot = ''" "$WORKFLOW"; then
  ok "intake-review.mjs destructures readRoot (default '')"
else
  bad "intake-review.mjs lost the readRoot destructure"
fi

if grep -q 'PINNED READ SURFACE' "$WORKFLOW"; then
  ok "intake-review.mjs carries the pinned-read instruction text"
else
  bad "intake-review.mjs lost the PINNED READ SURFACE instruction"
fi

# Both dispatch prompts (spec-reviewer AND codebase-explorer) must lead with the
# note — one occurrence per DISPATCH entry.
NOTE_USES=$(grep -c 'readRootNote +' "$WORKFLOW")
if [[ "$NOTE_USES" -ge 2 ]]; then
  ok "readRootNote prefixes both dispatch prompts ($NOTE_USES uses)"
else
  bad "readRootNote must prefix BOTH dispatch prompts (found $NOTE_USES use(s))"
fi

# --- (2) AC-5 guard: reason value retained, re-semanticized not renamed --------
# shellcheck disable=SC2016  # literal backticks in the schema row, no expansion intended
if grep -q '`non-main-base-autonomous`' "$SCHEMA"; then
  ok "state-schema.md retains the non-main-base-autonomous reason row"
else
  bad "state-schema.md lost the non-main-base-autonomous reason row (AC-5)"
fi

# --- (3) prose contract anchors: Step 1.P + Stage-10 backstop ------------------
if grep -q 'Step 1.P' "$INTAKE_STAGE" && grep -q 'intake-pin-' "$INTAKE_STAGE"; then
  ok "stages/1-intake.md documents Step 1.P with the intake-pin worktree"
else
  bad "stages/1-intake.md lost the Step 1.P pin contract"
fi

if grep -q 'intake-pin-' "$CLEANUP_STAGE"; then
  ok "stages/10-cleanup.md removes the intake pin worktree (crash backstop)"
else
  bad "stages/10-cleanup.md lost the intake-pin removal backstop"
fi

echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
