#!/usr/bin/env bash
#
# is-inert-diff.sh — single source of truth for the dev-pipeline INERT-lane classifier.
#
# Reads a newline-delimited list of changed file paths on STDIN and classifies the diff
# as INERT (exit 0) or SUITE (exit 1). A diff is INERT iff EVERY path matches the inert
# pattern set below; ANY non-matching path ⇒ SUITE — the conservative default, so a path
# that could feed the JS/TS suite always selects SUITE.
#
# Inert iff every path matches one of:
#   *.md (any path) · *.sh (any path) · .github/workflows/*.yml ·
#   .claude/**/*.{mjs,cjs,py,tsv,json,jsonl} ·
#   .prettierignore (any depth) · .gitignore (any depth)
#
# Output contract: the EXIT CODE is the contract (0 = inert, 1 = suite); the lane token
# (`inert`/`suite`) is also echoed to stdout for callers that want the string. Callers
# that branch on the exit code suppress the token with `>/dev/null`.
#
# This script never computes a diff itself — each caller feeds its OWN already-correct
# diff on stdin, so the wrong ref can never reach the classifier:
#   - stages/6-verify.md           feeds `git diff --name-only "$BASE"..HEAD` (branch diff)
#   - .claude/hooks/pre-commit-typecheck.sh feeds `git diff --cached --name-only` (staged)
#
# The pre-commit hook is NOT routed through this classifier: its needs_typecheck() is a
# DIFFERENT, JS/TS-relevance-gated predicate that shares only the .claude/**/*.{mjs,cjs}
# carve-out. pre-commit-typecheck-selftest.sh asserts that shared sub-pattern against this
# script so the two stay in lockstep.

# The canonical inert regex — the single definition for the whole pipeline. `.json` and
# `.jsonl` are folded into `jsonl?`; the ignore files allow a `(^|/)` prefix so a nested
# .gitignore / .prettierignore matches at any depth.
INERT_RE='(\.md$|\.sh$|^\.github/workflows/.*\.yml$|^\.claude/.*\.mjs$|^\.claude/.*\.cjs$|^\.claude/.*\.py$|^\.claude/.*\.tsv$|^\.claude/.*\.jsonl?$|(^|/)\.prettierignore$|(^|/)\.gitignore$)'

# inert iff there is NO line that fails to match. `grep -vE` selects the non-inert paths;
# if it selects any (exit 0) the diff is SUITE, otherwise (exit 1) it is INERT. Output is
# discarded — only the exit code matters. This reuses the exact grep evaluation the
# Stage-6 inline idiom used (`grep -vE … && LANE=suite || LANE=inert`), so classification
# is byte-identical. `grep -vE` (not `grep -qvE`) is deliberate: `-q` short-circuits and
# trips a BSD-grep early-exit quirk, whereas plain `-vE` reproduces the original exit code.
if grep -vE "$INERT_RE" >/dev/null; then
  echo suite
  exit 1
else
  echo inert
  exit 0
fi
