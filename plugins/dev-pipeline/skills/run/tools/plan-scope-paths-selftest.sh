#!/usr/bin/env bash
# plan-scope-paths-selftest.sh — fixture-based checks for plan-scope-paths.sh
# (#109). Mirrors plan-lint-selftest.sh's culture: fixture + counters, exit code
# = number of failures.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/plan-scope-paths.sh"
FIX="$HERE/plan-scope-paths-fixtures"
LINT_FIX="$HERE/plan-lint-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

tool_rc() { # tool_rc <args...> — echo exit code, never abort the harness
  set +e
  bash "$TOOL" "$@" >/dev/null 2>&1
  echo $?
  set -e
}

echo "[plan-scope-paths-selftest] cases"

# (pp-a) multiple Affected-files paths, one duplicated → deduped array of 2
out=$(bash "$TOOL" "$FIX/multi-path-plan.md" "affected files")
count=$(jq 'length' <<< "$out")
has_service=$(jq 'index("apps/api/src/modules/widget/widget.service.ts") != null' <<< "$out")
has_controller=$(jq 'index("apps/api/src/modules/widget/widget.controller.ts") != null' <<< "$out")
if [[ "$count" == "2" && "$has_service" == "true" && "$has_controller" == "true" ]]; then
  pass "(pp-a) multi-path Affected-files section → deduped 2-element array"
else
  fail "(pp-a) multi-path Affected-files — count=$count out=$out"
fi

# (pp-b) Out-of-scope section path extracted, scoped to ONLY that section (does
# not leak the Affected-files paths from the same document)
out=$(bash "$TOOL" "$FIX/multi-path-plan.md" "out.of.scope")
count=$(jq 'length' <<< "$out")
has_module=$(jq 'index("apps/api/src/modules/widget/widget.module.ts") != null' <<< "$out")
if [[ "$count" == "1" && "$has_module" == "true" ]]; then
  pass "(pp-b) Out-of-scope section → its own path only, section-scoped"
else
  fail "(pp-b) Out-of-scope section — count=$count out=$out"
fi

# (pp-c) prose-only section (no backtick paths) → empty array, not an error
rc=$(tool_rc "$FIX/no-paths-plan.md" "affected files")
out=$(bash "$TOOL" "$FIX/no-paths-plan.md" "affected files")
if [[ "$rc" == "0" && "$out" == "[]" ]]; then
  pass "(pp-c) prose-only section → [] (rc=0)"
else
  fail "(pp-c) prose-only section — rc=$rc out=$out"
fi

# (pp-d) section entirely absent from the plan → [] (rc=0), not an error
rc=$(tool_rc "$FIX/multi-path-plan.md" "nonexistent section xyz")
out=$(bash "$TOOL" "$FIX/multi-path-plan.md" "nonexistent section xyz")
if [[ "$rc" == "0" && "$out" == "[]" ]]; then
  pass "(pp-d) absent section → [] (rc=0)"
else
  fail "(pp-d) absent section — rc=$rc out=$out"
fi

# (pp-e) missing plan file → usage error, rc=2
rc=$(tool_rc "$FIX/does-not-exist.md" "affected files")
[[ "$rc" == "2" ]] \
  && pass "(pp-e) missing plan file → rc=2" \
  || fail "(pp-e) missing plan file — rc=$rc"

# (pp-f) missing args → usage error, rc=2
rc=$(tool_rc)
[[ "$rc" == "2" ]] \
  && pass "(pp-f) missing args → rc=2" \
  || fail "(pp-f) missing args — rc=$rc"

# (pp-g) shared plan-lint fixture, real single-path Affected-files section
out=$(bash "$TOOL" "$LINT_FIX/valid-plan.md" "affected files" | jq -c .)
[[ "$out" == '["apps/api/src/modules/example/example.service.ts"]' ]] \
  && pass "(pp-g) plan-lint's shared valid-plan.md fixture → single path" \
  || fail "(pp-g) shared fixture — out=$out"

echo "[plan-scope-paths-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
