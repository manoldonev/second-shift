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
#   .claude/second-shift/.known-extensions (exact path — extensionless) ·
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

# ---------------------------------------------------------------------------------------
# Why each pattern is inert
#
# The shared rationale: the path lives outside the yarn workspace tree (apps/*, packages/*)
# and is referenced by no tsconfig/eslint/jest config, so the configured lint/type-check/
# test commands (config commands.<host>.*) give it ZERO coverage. Running the suite is then
# pure wasted install+build cost for a guaranteed-identical result. Each carve-out below is
# anchored narrowly on purpose, so a path that could feed the JS/TS suite still selects
# SUITE.
#
# .claude/**/*.{mjs,cjs} — Workflow scripts. The dev-pipeline Workflow scripts under
#   .claude/skills/.../workflows/ get zero coverage per the shared rationale. Their real
#   verification is the plan-specific commands (syntax wrap-`node --check`, predicate unit
#   tests), which run on BOTH lanes, so marking them inert loses no coverage. A .mjs/.cjs
#   anywhere else (e.g. apps/web/next.config.mjs) is not matched and still selects SUITE.
#   The repo .prettierignore lists the same .claude/**/*.mjs glob, so a direct
#   `prettier --check`/`--write` on these paths is a no-op too — the inert-lane decision
#   and the repo-level prettier contract stay in lockstep. The pre-commit type-check hook
#   (.claude/hooks/pre-commit-typecheck.sh) reuses this same carve-out, kept in lockstep
#   with this file by its pre-commit-typecheck-selftest.sh.
#
# .claude/**/*.tsv — pipeline-internal data (e.g. .claude/prose-budget.baseline.tsv) read
#   only by a shell tool (prose-budget.sh). Zero coverage per the shared rationale, and it
#   is outside the prettier format-glob *.{ts,tsx,js,json,md}, so the INERT-lane
#   `prettier --check` already skips it. Anchor is deliberately .claude/-scoped: a .tsv
#   anywhere else (e.g. an apps/** fixture consumed by a *.test.ts) still selects SUITE.
#
# .claude/**/*.{json,jsonl} — cost-tracking fixtures (read by pipeline-cost-block.sh /
#   cost-block-selftest.sh), .claude/settings.json, the audit .jsonl ledgers, etc. The
#   load-bearing reason is the zero-coverage fact above — NOT a narrower "fixture read by
#   a shell tool" framing — and it holds for every .claude/-scoped JSON/JSONL whether or
#   not a shell tool reads it. Real verification is the plan-specific commands (e.g. the
#   cost-block selftest), which run on both lanes. Unlike .tsv, .json IS in the prettier
#   format-glob, so the INERT-lane `prettier --check` still checks changed .json paths
#   (correct — that is the format gate doing its job); .jsonl is outside it and is skipped.
#   Anchor is .claude/-scoped: tsconfig.json, package.json, or an apps/** fixture consumed
#   by a *.test.ts is not matched and still selects SUITE.
#
# .claude/**/*.py — tooling: the agent-eval-kit harness
#   (pipeline-state/agent-eval-kit/run-eval.py) and the per-eval rubric.py files. Zero
#   coverage per the shared rationale; real verification is Python tooling (ruff /
#   `python -c "import ast; ast.parse(...)"`) run as plan-specific commands, which fire on
#   both lanes. Like .tsv/.jsonl it is outside the prettier format-glob. Anchor is
#   .claude/-scoped: a .py anywhere else (services/ml-service/**, covered by ruff/pytest)
#   still selects SUITE — the conservative default for files with real coverage.
#
# .claude/second-shift/.known-extensions — the consumer extension allowlist, read by
#   exactly one reader: tools/check-extensions.sh (ALLOW="$SS/.known-extensions"). Zero
#   coverage per the shared rationale. Being extensionless it is outside the prettier
#   format-glob too, so no format coverage is lost. Without this carve-out a diff that only
#   adds/edits/deletes the allowlist pays the full SUITE lane for a guaranteed-identical
#   result (observed: a single .known-extensions deletion forced SUITE on an otherwise
#   config+Markdown diff). Unlike the extension-scoped carve-outs above, the anchor is the
#   EXACT canonical path, not .claude/-wide: check-extensions.sh reads this one location
#   and no other, so a same-named file elsewhere (.claude/other/.known-extensions, a
#   repo-root .known-extensions) still selects SUITE. This keeps the boundary at "config
#   that cannot affect lint/type-check/test" rather than widening it to "any extensionless
#   dotfile under .claude/" — consistent with the .npmrc/.nvmrc/.yarnrc.yml exclusion below.
#
# .prettierignore / .gitignore (any depth) — changing .prettierignore can only alter which
#   files Prettier SKIPS; it cannot change the lint/type-check/test result, and the format
#   gate is independently scoped to the changed *.{ts,tsx,js,json,md} paths, not recomputed
#   from the ignore file. .gitignore is the same class: it only alters which paths git
#   ignores, never the result computed over the working tree (an ignore rule does not
#   untrack already-tracked sources, and the suite runs over the files present). So such an
#   edit is provably suite-irrelevant. The boundary is deliberately narrow — config that
#   cannot affect lint/type-check/test, NOT "any extensionless dotfile": .npmrc, .nvmrc and
#   .yarnrc.yml change toolchain/install behavior and still correctly select SUITE.
# ---------------------------------------------------------------------------------------

# The canonical inert regex — the single definition for the whole pipeline. `.json` and
# `.jsonl` are folded into `jsonl?`; the ignore files allow a `(^|/)` prefix so a nested
# .gitignore / .prettierignore matches at any depth.
INERT_RE='(\.md$|\.sh$|^\.github/workflows/.*\.yml$|^\.claude/.*\.mjs$|^\.claude/.*\.cjs$|^\.claude/.*\.py$|^\.claude/.*\.tsv$|^\.claude/.*\.jsonl?$|^\.claude/second-shift/\.known-extensions$|(^|/)\.prettierignore$|(^|/)\.gitignore$)'

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
