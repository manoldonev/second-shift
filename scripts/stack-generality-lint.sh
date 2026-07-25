#!/usr/bin/env bash
# stack-generality-lint.sh — regression guard for the mechanizable stack-generality legs.
#
# WHY THIS EXISTS: the Stage-3/5 prompt contracts were genericized off the birth stack
# once before, and the literals crept back because nothing model-free guarded them. This
# lint bans re-entry of the mechanizable ones. It deliberately guards ONLY the legs a
# substring check can honestly decide; the normative-vs-illustrative distinction
# (Drizzle / *.spec.ts / apps/api inside labeled example blocks) is review-verified,
# not linted — a grep cannot tell a normative literal from a labeled illustration or
# from prose describing the anti-pattern to refuse.
#
# Legs (each with a declared path scope and check direction):
#   .project/ absence  — no `.project/` literal in the three dev-pipeline contract files
#                        (file-wide), nor in review-toolkit/agents/doc-updater.md's
#                        FRONTMATTER block. The doc-updater body legitimately mentions
#                        `.project/` (anti-pattern prose and a labeled illustration
#                        block), so only its frontmatter is scanned.
#   unit-testing absence — zero `unit-testing` references under plugins/, excluding the
#                        measurement baseline prose-budget.baseline.tsv (data, not a
#                        reference). This script and its selftest live in scripts/,
#                        outside the scan scope, so they need no self-exclusion.
#   (AC-n) presence    — the literal `(AC-n)` token still present at both convention
#                        sites (the pipeline-retro AC-coverage grep depends on it).
#
# Invocation: CI runs this via stack-generality-lint-selftest.sh's clean-tree case
# (the *-selftest.sh glob on both CI lanes) — no ci.yml registration needed.
#
# Usage: stack-generality-lint.sh [repo-root]   (default: .)
# Exit code = number of violations (doctor convention); 0 = clean.
set -uo pipefail

ROOT="${1:-.}"

violations=0
fail() { echo "[stack-generality] ✗ $1" >&2; violations=$((violations + 1)); }

# ---- .project/ absence -------------------------------------------------------

PROJECT_FILEWIDE=(
  "plugins/dev-pipeline/skills/run/stages/5-implement.md"
  "plugins/dev-pipeline/skills/run/stages/7-doc-update.md"
  "plugins/dev-pipeline/skills/run/SKILL.md"
)
for f in "${PROJECT_FILEWIDE[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    fail "guarded file missing: $f"
  else
    hit="$(grep -n '\.project/' "$ROOT/$f" | head -1 || true)"
    [[ -n "$hit" ]] && fail ".project/ literal reintroduced in $f ($hit)"
  fi
done

DOC_UPDATER="plugins/review-toolkit/agents/doc-updater.md"
if [[ ! -f "$ROOT/$DOC_UPDATER" ]]; then
  fail "guarded file missing: $DOC_UPDATER"
else
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$ROOT/$DOC_UPDATER")"
  if printf '%s\n' "$frontmatter" | grep -q '\.project/'; then
    fail ".project/ literal reintroduced in $DOC_UPDATER frontmatter"
  fi
fi

# ---- unit-testing absence ----------------------------------------------------

if [[ ! -d "$ROOT/plugins" ]]; then
  fail "scan root missing: plugins/"
else
  hits="$(grep -rn 'unit-testing' "$ROOT/plugins" 2>/dev/null | grep -v 'prose-budget\.baseline\.tsv' || true)"
  if [[ -n "$hits" ]]; then
    fail "unit-testing reference(s) reintroduced under plugins/ (first: $(printf '%s\n' "$hits" | head -1))"
  fi
fi

# ---- (AC-n) presence ---------------------------------------------------------

ACN_SITES=(
  "plugins/dev-pipeline/skills/run/stages/5-implement.md"
  "plugins/review-toolkit/skills/mutation-review/SKILL.md"
)
for f in "${ACN_SITES[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    fail "convention site missing: $f"
  elif ! grep -qF '(AC-n)' "$ROOT/$f"; then
    fail "literal (AC-n) token missing from $f (the pipeline-retro AC-coverage grep depends on it)"
  fi
done

if [[ "$violations" -eq 0 ]]; then
  echo "stack-generality-lint: OK"
else
  echo "stack-generality-lint: $violations violation(s)" >&2
fi
exit "$violations"
