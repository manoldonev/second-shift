#!/usr/bin/env bash
#
# Self-test for the Stage-1 read-surface pin wiring (#59).
#
# A drift-check in the style of claim-selftest.sh's parity tail: pure-local, no
# Claude CLI, no network. The pin is model-executed prose (stages/1-intake.md
# Step 1.P) plus ONE code seam — the `readRoot` arg in workflows/intake-review.mjs
# that prefixes every dispatch prompt with the pinned-read instruction. This test
# pins the load-bearing tokens of that seam so a refactor cannot silently drop the
# pin from one (or both) dispatch prompts.
#
# AC-5 (the `non-main-base-autonomous` reason value is retained, re-semanticized to the
# pin-failure trigger rather than renamed) is NOT guarded here — it is guarded where it
# is mechanically enforceable, in statectl-selftest.sh: the validator enum is generated
# from the state-schema.md row, so its regenerate-and-diff drift check plus the
# mark-failed case cover deletion both with and without regeneration.
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

# The three markdown-prose checks that used to sit here were deleted (#214):
#   - the state-schema.md `non-main-base-autonomous` row grep was DOUBLY redundant: the
#     statectl enum is GENERATED from that very row (gen-statectl-validators.sh), and
#     statectl-selftest.sh guards both mutation paths — its regenerate-and-diff drift
#     check catches deletion without regeneration, and its mark-failed case catches
#     deletion WITH regeneration. That is where the AC-5 guarantee actually lives.
#   - the two `intake-pin-` prose anchors (1-intake.md / 10-cleanup.md) were the banned
#     prose-presence class: independent greps, not a comparison, so a consistent rename
#     across both files false-passes and an inconsistent one is visible in the diff. The
#     coupling is recorded in scripts/lockstep-manifest.tsv as a DROPPED entry.
# What remains above is the sanctioned exception: token pins on a Workflow-runtime .mjs
# seam that can be neither executed nor node --check'ed.

echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
