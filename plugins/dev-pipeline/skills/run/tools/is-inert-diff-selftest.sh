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
# defaults (any path that could feed the JS/TS suite), mixed diffs, and the optional
# argv[1] pattern override in all three of its states — absent, present, malformed.
#
# DRIFT MODEL: there is NO mirror of INERT_RE in this file. An earlier revision carried a
# CANONICAL_RE copy plus a golden-master tail that re-derived the expected lane from it;
# both were deleted once it was clear the tail's only failure mode was stale transcription
# of a regex the check table already pins behaviorally. The per-pattern check() cases below
# are what assert intended behavior, and every new alternative needs one. The dangerous
# direction is inert-set WIDENING (it skips the suite), covered by the hard suite rows; a
# mis-narrowed regex only misroutes an inert diff to the conservative SUITE lane — wasted
# CI, never a skipped verification. If a future edit re-inlines the grep into 6-verify.md
# (so the script stops being the single definition), pre-commit-typecheck-selftest.sh's
# delegation assertion catches that — not this test.

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

# run <newline-delimited-paths> [pattern] -> sets $? from the script. An ABSENT 4th
# argument and an EMPTY one are distinct inputs to the caller but must behave
# identically (both fall back to the shipped default) — check() below exercises both.
run() {
  if [ "$#" -ge 2 ]; then
    printf '%s' "$1" | bash "$SCRIPT" "$2" >/dev/null 2>&1
  else
    printf '%s' "$1" | bash "$SCRIPT" >/dev/null 2>&1
  fi
}

# check <desc> <expected-lane: inert|suite> <newline-delimited-paths> [override-pattern]
check() {
  local desc="$1" exp="$2" input="$3" rc lane
  if [ "$#" -ge 4 ]; then run "$input" "$4"; else run "$input"; fi
  rc=$?
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

# --- OVERRIDE (argv[1]): the config-supplied pattern REPLACES the default outright ---
# This is the non-JS/TS consumer's escape hatch: a repo whose product surface IS *.sh
# must be able to remove `\.sh$` from the inert set so its configured lint/test lanes
# actually run. The override value below is the shipped default minus that one
# alternative — the exact hand-copy a consumer writes into stageParams.inertPattern.
OVERRIDE_NO_SH='(\.md$|^\.github/workflows/.*\.yml$|^\.claude/.*\.mjs$|^\.claude/.*\.cjs$|^\.claude/.*\.py$|^\.claude/.*\.tsv$|^\.claude/.*\.jsonl?$|^\.claude/second-shift/\.known-extensions$|(^|/)\.prettierignore$|(^|/)\.gitignore$)'

echo "[self-test] argv[1] pattern override"
# Absent override — the regression guard: today's behavior must be byte-identical.
check "override absent: *.sh"          inert "scripts/build.sh"
# Empty override — an unset/empty config key must fall back to the default, NOT match
# everything (an empty ERE matches every line, which would classify the whole repo inert).
check "override empty: *.sh"           inert "scripts/build.sh"          ""
check "override empty: .ts"            suite "apps/api/x.ts"             ""
# Present override — the AC-1' unit half: *.sh now selects SUITE.
check "override present: *.sh"         suite "scripts/build.sh"          "$OVERRIDE_NO_SH"
check "override present: *.sh nested"  suite "plugins/x/tools/y.sh"      "$OVERRIDE_NO_SH"
# Present override — AC-2's discriminator: the rest of the set still classifies inert,
# so the override narrows exactly what it says and nothing else.
check "override present: *.md"         inert "README.md"                 "$OVERRIDE_NO_SH"
check "override present: .gitignore"   inert ".gitignore"                "$OVERRIDE_NO_SH"
check "override present: mixed sh+md"  suite $'README.md\nscripts/b.sh'  "$OVERRIDE_NO_SH"

# --- MALFORMED OVERRIDE: fail CLOSED to suite, and say so on stderr ---
# `grep -E` exits 2 on an uncompilable pattern. The pre-override code read any non-zero
# as "no non-inert path found" and reported INERT — i.e. a typo'd override would have
# become a silent repo-wide verification skip. This is the one case where getting it
# wrong is dangerous rather than merely wasteful, so it asserts BOTH the lane and the
# diagnostic.
echo "[self-test] malformed override fails closed"
check "malformed override -> suite"    suite "README.md"                 "("
MALFORMED_ERR="$(printf '%s' "README.md" | bash "$SCRIPT" "(" 2>&1 >/dev/null)"
if [ -n "$MALFORMED_ERR" ]; then
  ok "malformed override -> non-empty stderr diagnostic"
else
  bad "malformed override: expected a stderr diagnostic, got none"
fi

echo "[self-test] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
