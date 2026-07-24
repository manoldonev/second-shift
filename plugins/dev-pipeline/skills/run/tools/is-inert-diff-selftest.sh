#!/usr/bin/env bash
#
# Self-test for is-inert-diff.sh — the single source of truth for the dev-pipeline
# INERT-lane classifier.
#
# A self-test in the style of pre-commit-typecheck-selftest.sh / claim-selftest.sh:
# pure-local, no Claude CLI, no network, no yarn. It drives the real script with
# synthetic newline-delimited path lists and asserts INERT (exit 0) vs SUITE (exit 1).
#
# Coverage: every inert pattern (each in isolation, including nested-path ignore files,
# the .json/.jsonl fold, and the exact-path .known-extensions carve-out), the SUITE
# defaults (any path that could feed the JS/TS suite), and mixed diffs. Plus a
# GOLDEN-MASTER tail that re-derives the expected lane from the CANONICAL_RE mirror
# embedded here and asserts the script agrees over the whole case list.
#
# DRIFT MODEL: CANONICAL_RE is a LOCKSTEP MIRROR of the script's INERT_RE, not a frozen
# historical baseline — a deliberate change to the inert set updates BOTH copies in the
# same commit. What the tail buys is transcription-drift detection: an edit that lands in
# only one copy fails it. Because the mirror moves with the regex, the tail alone cannot
# prove a NEW alternative is correct — the per-pattern check() cases above are what assert
# intended behavior, and every new alternative needs one. If a future edit re-inlines the
# grep into 6-verify.md (so the script stops being the single definition),
# pre-commit-typecheck-selftest.sh's delegation assertion catches that — not this test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/is-inert-diff.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

if [ ! -x "$SCRIPT" ]; then
  echo "[self-test] FATAL: $SCRIPT missing or not executable" >&2
  exit 1
fi

# run <newline-delimited-paths> -> echoes the lane token and sets $? from the script.
run() { printf '%s' "$1" | bash "$SCRIPT" >/dev/null 2>&1; }

# check <desc> <expected-lane: inert|suite> <newline-delimited-paths>
check() {
  local desc="$1" exp="$2" input="$3" rc lane
  run "$input"; rc=$?
  if [ "$rc" -eq 0 ]; then lane=inert; else lane=suite; fi
  if [ "$lane" = "$exp" ]; then
    ok "$desc -> $lane"
  else
    bad "$desc: expected $exp, got $lane (rc=$rc)"
  fi
}

echo "[self-test] classification (inert = exit 0, suite = exit 1)"

# --- INERT: each pattern in isolation ---
check "empty diff"                     inert ""
check "*.md (root)"                    inert "README.md"
check "*.md (nested)"                  inert "docs/plans/acme-249.md"
check "*.sh (root)"                    inert "run.sh"
check "*.sh (nested, any path)"        inert "apps/api/scripts/seed.sh"
check ".github/workflows/*.yml"        inert ".github/workflows/ci.yml"
check ".claude .mjs"                   inert ".claude/skills/run/workflows/code-review.mjs"
check ".claude .cjs"                   inert ".claude/skills/x/workflows/y.cjs"
check ".claude .py"                    inert ".claude/pipeline-state/agent-eval-kit/run-eval.py"
check ".claude .tsv"                   inert ".claude/prose-budget.baseline.tsv"
check ".claude .json"                  inert ".claude/settings.json"
check ".claude .jsonl"                 inert ".claude/audit/ledger.jsonl"
check ".known-extensions (canonical)"  inert ".claude/second-shift/.known-extensions"
check ".prettierignore (root)"         inert ".prettierignore"
check ".prettierignore (nested)"       inert "packages/core/.prettierignore"
check ".gitignore (root)"              inert ".gitignore"
check ".gitignore (nested)"            inert "apps/web/.gitignore"
check "all-inert multi-line"           inert $'README.md\nrun.sh\n.claude/x/y.mjs\n.gitignore'

# --- SUITE: any path that could feed the JS/TS suite ---
check ".ts source"                     suite "apps/api/src/foo.service.ts"
check ".tsx source"                    suite "apps/web/components/Foo.tsx"
check "package.json"                   suite "package.json"
check ".mjs OUTSIDE .claude"           suite "apps/web/next.config.mjs"
check ".cjs OUTSIDE .claude"           suite "tools/jest.config.cjs"
check ".json OUTSIDE .claude"          suite "tsconfig.json"
check ".tsv OUTSIDE .claude"           suite "apps/api/test/fixtures/data.tsv"
check ".py OUTSIDE .claude"            suite "services/ml-service/app.py"
check "yarn.lock"                      suite "yarn.lock"
check ".npmrc (not an inert dotfile)"  suite ".npmrc"
check ".yarnrc.yml (not workflow yml)" suite ".yarnrc.yml"
check "yml outside workflows"          suite "config/app.yml"
# The .known-extensions carve-out is anchored to the ONE canonical location
# (check-extensions.sh reads $ROOT/.claude/second-shift/.known-extensions and
# nowhere else). Same-named file at any other path keeps selecting SUITE.
check ".known-extensions elsewhere"    suite ".claude/other/.known-extensions"
check ".known-extensions (root)"       suite ".known-extensions"

# --- MIXED: any non-inert path forces SUITE (order-independent) ---
check "inert + .ts (ts last)"          suite $'README.md\napps/api/x.ts'
check "inert + .ts (ts first)"         suite $'apps/api/x.ts\nREADME.md'
check ".claude .mjs + package.json"    suite $'.claude/x/y.mjs\npackage.json'
check ".known-extensions + .ts"        suite $'.claude/second-shift/.known-extensions\napps/api/x.ts'
check ".known-extensions + .md"        inert $'.claude/second-shift/.known-extensions\nREADME.md'

# Salvaged from the deleted golden-master parity tail (#214): these two inputs were the
# ONLY ones the tail covered that the check table did not. The tail itself was a mirror
# of INERT_RE whose sole failure mode was stale transcription, and the dangerous
# direction (inert-set WIDENING, which skips the suite) is covered by the table's hard
# suite rows. A mis-narrowed regex here only misroutes an inert diff to the conservative
# SUITE lane — wasted CI, never a skipped verification.
check ".claude subtree .py"            inert $'.claude/x/y.py'
check ".claude subtree .tsv"           inert $'.claude/x/y.tsv'

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
