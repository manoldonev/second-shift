#!/usr/bin/env bash
# plan-lint-selftest.sh — deterministic checks for plan-lint.sh (mirrors the
# statectl-selftest culture: fixture + inline mutants, pass/fail counters,
# exit code = number of failures).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/plan-lint.sh"
FIX="$HERE/plan-lint-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

lint_rc() { # lint_rc <plan> [<state>] — echo exit code, never abort the harness
  set +e
  bash "$LINT" "$@" >/dev/null 2>&1
  echo $?
  set -e
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[plan-lint-selftest] positive cases"

# (pl-a) valid fixture + matching state → exit 0 (incl. escaped pipe in a cell)
rc=$(lint_rc "$FIX/valid-plan.md" "$FIX/valid-state.json")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-a) valid plan + matching snapshot → 0" \
  || fail "(pl-a) valid plan — got rc=$rc"

# (pl-b) valid fixture, no state arg → structure-only, exit 0
rc=$(lint_rc "$FIX/valid-plan.md")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-b) no state arg → structure-only, 0" \
  || fail "(pl-b) no state arg — got rc=$rc"

# (pl-c) zero-AC refactor plan (header-present empty table) + empty snapshot → 0
rc=$(lint_rc "$FIX/zero-ac-plan.md" "$FIX/zero-ac-state.json")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-c) zero-AC plan + empty snapshot → 0" \
  || fail "(pl-c) zero-AC plan — got rc=$rc"

# (pl-d) no-test row count is reported on stdout
out=$(bash "$LINT" "$FIX/valid-plan.md" "$FIX/valid-state.json" 2>/dev/null)
grep -q "1 '— no test' row(s)" <<< "$out" \
  && pass "(pl-d) no-test count reported" \
  || fail "(pl-d) no-test count — got: $out"

# (pl-m) apostrophe in a Test(s) cell → 0. Regression guard: the cells were once
# trimmed via `echo ... | xargs`, which reads its input with shell quoting rules and
# aborts with "unterminated quote" on a lone apostrophe — failing the whole lint on a
# legitimate plan (a test named coverage-can't-fail). awk, not sed, so the apostrophe
# never traverses this harness's own shell quoting.
awk -v q="'" '{ sub(/example\.service\.spec \(AC-1\)/, "coverage-can" q "t-fail (AC-1)"); print }' \
  "$FIX/valid-plan.md" > "$TMP/apostrophe.md"
if ! grep -q "coverage-can.t-fail" "$TMP/apostrophe.md"; then
  fail "(pl-m) fixture setup — apostrophe cell was not written"
else
  rc=$(lint_rc "$TMP/apostrophe.md" "$FIX/valid-state.json")
  [[ "$rc" -eq 0 ]] \
    && pass "(pl-m) apostrophe in Test cell → 0" \
    || fail "(pl-m) apostrophe in Test cell — got rc=$rc"
fi

echo "[plan-lint-selftest] mutants (each must exit 1 with a named violation)"

# (pl-e) dropped Test(s) cell
sed 's/— no test (infra-only)//' "$FIX/valid-plan.md" > "$TMP/dropped-test.md"
rc=$(lint_rc "$TMP/dropped-test.md" "$FIX/valid-state.json")
err=$(bash "$LINT" "$TMP/dropped-test.md" "$FIX/valid-state.json" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "empty Test(s) cell" <<< "$err" \
  && pass "(pl-e) dropped Test cell → 1, named" \
  || fail "(pl-e) dropped Test cell — rc=$rc err=$err"

# (pl-f) deleted mandated section
grep -v '^## Reuse inventory' "$FIX/valid-plan.md" > "$TMP/no-reuse.md"
rc=$(lint_rc "$TMP/no-reuse.md" "$FIX/valid-state.json")
err=$(bash "$LINT" "$TMP/no-reuse.md" "$FIX/valid-state.json" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "missing mandated section: Reuse inventory" <<< "$err" \
  && pass "(pl-f) deleted section → 1, named" \
  || fail "(pl-f) deleted section — rc=$rc err=$err"

# (pl-g) invalid no-test category
sed 's/— no test (infra-only)/— no test (trivial)/' "$FIX/valid-plan.md" > "$TMP/bad-category.md"
rc=$(lint_rc "$TMP/bad-category.md" "$FIX/valid-state.json")
err=$(bash "$LINT" "$TMP/bad-category.md" "$FIX/valid-state.json" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "no-test justification" <<< "$err" \
  && pass "(pl-g) invalid no-test category → 1, named" \
  || fail "(pl-g) invalid category — rc=$rc err=$err"

# (pl-g2) a acme-specific category IS accepted (covered-by-selftest)
sed 's/— no test (infra-only)/— no test (covered-by-selftest)/' "$FIX/valid-plan.md" > "$TMP/selftest-cat.md"
rc=$(lint_rc "$TMP/selftest-cat.md" "$FIX/valid-state.json")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-g2) covered-by-selftest category accepted → 0" \
  || fail "(pl-g2) covered-by-selftest — rc=$rc"

# (pl-h) AC↔table mismatch: snapshot id with no row
jq '.acceptanceCriteria += [{"id":"AC-3","text":"extra","negative":false,"source":"explicit"}]' \
  "$FIX/valid-state.json" > "$TMP/extra-ac-state.json"
rc=$(lint_rc "$FIX/valid-plan.md" "$TMP/extra-ac-state.json")
err=$(bash "$LINT" "$FIX/valid-plan.md" "$TMP/extra-ac-state.json" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "AC-3 has 0 traceability row(s)" <<< "$err" \
  && pass "(pl-h) snapshot id without row → 1, named" \
  || fail "(pl-h) snapshot mismatch — rc=$rc err=$err"

# (pl-i) AC↔table mismatch: table row not in snapshot
sed 's/| AC-2  |/| AC-9  |/' "$FIX/valid-plan.md" > "$TMP/unknown-row.md"
rc=$(lint_rc "$TMP/unknown-row.md" "$FIX/valid-state.json")
err=$(bash "$LINT" "$TMP/unknown-row.md" "$FIX/valid-state.json" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "AC-9 does not exist" <<< "$err" \
  && pass "(pl-i) table row outside snapshot → 1, named" \
  || fail "(pl-i) unknown row — rc=$rc err=$err"

# (pl-j) usage errors → exit 2
rc=$(lint_rc)
rc2=$(lint_rc "$TMP/does-not-exist.md")
[[ "$rc" -eq 2 && "$rc2" -eq 2 ]] \
  && pass "(pl-j) missing args / missing file → 2" \
  || fail "(pl-j) usage errors — rc=$rc rc2=$rc2"

echo "[plan-lint-selftest] Decision Ledger advisory (must WARN, never violate)"

# (pl-k) a plan with no Decision Ledger section still passes (exit 0) but emits the advisory warning
rc=$(lint_rc "$FIX/valid-plan.md" "$FIX/valid-state.json")   # valid-plan.md has no ## Decision Ledger
out=$(bash "$LINT" "$FIX/valid-plan.md" "$FIX/valid-state.json" 2>/dev/null || true)
[[ "$rc" -eq 0 ]] && grep -q "WARNING (advisory): no Decision Ledger" <<< "$out" \
  && pass "(pl-k) missing Decision Ledger → advisory WARNING, still exit 0" \
  || fail "(pl-k) ledger advisory — rc=$rc out=$out"

# (pl-l) anti-resync guard: Decision Ledger is NOT in the hard mandated-SECTIONS
#        set (else the Stage-4 gate would false-abort autonomous ledger-less runs)
if grep -qi 'Decision Ledger' "$LINT" \
   && ! grep -qE '^(Decision Ledger|.*\\tdecision ledger)' "$LINT"; then
  pass "(pl-l) Decision Ledger excluded from hard SECTIONS (advisory-only)"
else
  fail "(pl-l) Decision Ledger must NOT appear as a SECTIONS row (hard-lint would false-abort Stage 4)"
fi

echo
echo "[plan-lint-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
