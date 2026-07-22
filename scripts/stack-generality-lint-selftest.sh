#!/usr/bin/env bash
# stack-generality-lint-selftest.sh — proves stack-generality-lint.sh can FAIL.
#
# A guard that only ever returns green is indistinguishable from no guard, so every
# leg is exercised on a seeded violation (and the scoped legs in BOTH directions).
# The final case runs the lint against the REAL repo root — that case is load-bearing
# twice over: it proves the current tree is clean, and because CI discovers
# *-selftest.sh by glob on both lanes, it IS the lint's CI invocation path (no ci.yml
# registration).
#
# Runs under the repo's *-selftest.sh loop (SKIP_STRESS has no effect here).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/stack-generality-lint.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[[ -f "$LINT" ]] || { echo "stack-generality-lint-selftest: lint not found at $LINT" >&2; exit 2; }

passes=0
fails=0
ok()  { echo "  ok: $1"; passes=$((passes + 1)); }
bad() { echo "  ✗ $1" >&2; fails=$((fails + 1)); }

# Explicit XXXXXX template: GNU mktemp rejects a -t template without them.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stack-generality-selftest.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

FIX="$TMP/fixture"
STAGES="plugins/dev-pipeline/skills/run/stages"

# A minimal clean tree mirroring the guarded paths. The doc-updater BODY deliberately
# mentions `.project/` — the legitimate case the frontmatter-only scope must not flag.
build_fixture() {
  rm -rf "$FIX"
  mkdir -p "$FIX/$STAGES" \
           "$FIX/plugins/dev-pipeline/skills/run/tools" \
           "$FIX/plugins/review-toolkit/agents" \
           "$FIX/plugins/review-toolkit/skills/mutation-review"
  printf 'attach the literal (AC-n) token; resolve conventions via the doc router\n' \
    > "$FIX/$STAGES/5-implement.md"
  printf 'scans the declared documentation roots\n' > "$FIX/$STAGES/7-doc-update.md"
  printf 'generic router prose\n' > "$FIX/plugins/dev-pipeline/skills/run/SKILL.md"
  printf -- '---\nname: doc-updater\ndescription: routes via the declared doc roots\n---\nbody may say never assume .project/ — that is the anti-pattern prose\n' \
    > "$FIX/plugins/review-toolkit/agents/doc-updater.md"
  printf 'convention text carrying the (AC-n) token\n' \
    > "$FIX/plugins/review-toolkit/skills/mutation-review/SKILL.md"
}

lint_rc() {
  bash "$LINT" "$1" >/dev/null 2>&1
  echo "$?"
}

echo "stack-generality-lint-selftest:"

# 1. Clean fixture → 0. Also proves the pass direction of the frontmatter-only scope
#    (the fixture's doc-updater BODY contains `.project/` and must not trip the leg).
build_fixture
rc="$(lint_rc "$FIX")"
if [[ "$rc" -eq 0 ]]; then ok "clean fixture exits 0 (incl. .project/ in doc-updater body)"; else bad "clean fixture rc=$rc (want 0)"; fi

# 2. Seeded .project/ literal in a stage file → fails.
build_fixture
printf 'read .project/reference/conventions.md first\n' >> "$FIX/$STAGES/5-implement.md"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -ge 1 ]]; then ok "seeded .project/ in 5-implement.md fails (rc=$rc)"; else bad "seeded .project/ in stage file not caught"; fi

# 3. Seeded .project/ in doc-updater FRONTMATTER → fails (the other direction of the scope).
build_fixture
printf -- '---\nname: doc-updater\ndescription: cross-references against .project/ docs\n---\nclean body\n' \
  > "$FIX/plugins/review-toolkit/agents/doc-updater.md"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -ge 1 ]]; then ok "seeded .project/ in doc-updater frontmatter fails (rc=$rc)"; else bad "frontmatter .project/ not caught"; fi

# 4. Seeded unit-testing reference in a .md → fails.
build_fixture
printf 'see the unit-testing skill\n' >> "$FIX/$STAGES/7-doc-update.md"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -ge 1 ]]; then ok "seeded unit-testing ref in .md fails (rc=$rc)"; else bad "unit-testing ref in .md not caught"; fi

# 5. Seeded unit-testing reference in a .mjs prompt string → fails.
build_fixture
printf 'prompt = "Load the unit-testing skill." +\n' > "$FIX/plugins/dev-pipeline/skills/run/tools/example.mjs"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -ge 1 ]]; then ok "seeded unit-testing ref in .mjs fails (rc=$rc)"; else bad "unit-testing ref in .mjs not caught"; fi

# 6. unit-testing occurrence in prose-budget.baseline.tsv → passes (documented exclusion).
build_fixture
printf '.claude/skills/unit-testing/SKILL.md\t966\t7697\t0\n' \
  > "$FIX/plugins/dev-pipeline/skills/run/tools/prose-budget.baseline.tsv"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -eq 0 ]]; then ok "prose-budget.baseline.tsv occurrence excluded (rc=0)"; else bad "documented exclusion tripped the leg (rc=$rc)"; fi

# 7. Removed (AC-n) token from a convention site → fails.
build_fixture
printf 'convention text with the token stripped\n' \
  > "$FIX/plugins/review-toolkit/skills/mutation-review/SKILL.md"
rc="$(lint_rc "$FIX")"
if [[ "$rc" -ge 1 ]]; then ok "missing (AC-n) token fails (rc=$rc)"; else bad "missing (AC-n) token not caught"; fi

# 8. Clean-tree case over the REAL repo root — the lint's CI invocation path.
rc="$(lint_rc "$REPO_ROOT")"
if [[ "$rc" -eq 0 ]]; then
  ok "real repo root is clean (rc=0)"
else
  bad "real repo root has $rc violation(s) — run: bash scripts/stack-generality-lint.sh ."
fi

echo "stack-generality-lint-selftest: $passes passed, $fails failed"
exit "$fails"
