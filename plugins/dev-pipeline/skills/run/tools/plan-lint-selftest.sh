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

# (pl-m) apostrophe in a trimmed cell → 0. Regression guard: the cells were once
# trimmed via `echo ... | xargs`, which reads its input with shell quoting rules and
# aborts with "unterminated quote" on a lone apostrophe — failing the whole lint on a
# legitimate plan (a test named coverage-can't-fail). awk, not sed, so the apostrophe
# never traverses this harness's own shell quoting.
# Covers BOTH trimmed cells that can legitimately carry prose — Step(s) and Test(s) —
# because trim() is applied at three separate call sites; exercising one would not
# catch a partial revert of another. (The id cell is excluded by design: an AC id
# containing an apostrophe never matches the anchored `| AC-n |` row grep.)
awk -v q="'" '{ sub(/example\.service\.spec \(AC-1\)/, "coverage-can" q "t-fail (AC-1)");
                sub(/\| 1       \|/, "| 1 (per D-1" q "s note) |"); print }' \
  "$FIX/valid-plan.md" > "$TMP/apostrophe.md"
if ! grep -q "coverage-can.t-fail" "$TMP/apostrophe.md"; then
  fail "(pl-m) fixture setup — apostrophe cell was not written"
else
  rc=$(lint_rc "$TMP/apostrophe.md" "$FIX/valid-state.json")
  [[ "$rc" -eq 0 ]] \
    && pass "(pl-m) apostrophe in Step(s) + Test(s) cells → 0" \
    || fail "(pl-m) apostrophe in Step(s) + Test(s) cells — got rc=$rc"
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

echo "[plan-lint-selftest] Decision Ledger provenance legality (Check 4)"

# Build a plan carrying a Decision Ledger, plus a state file whose SIBLING ledger
# path Check 4 derives. State named 156.json so the sibling is $TMP/156-ledger.md
# (the derivation is filename-based: dirname(state)/$(basename state .json)-ledger.md).
LEDGER_STATE="$TMP/156.json"
cp "$FIX/valid-state.json" "$LEDGER_STATE"
make_ledger_plan() { # make_ledger_plan <out> <ledger-rows-block>
  cp "$FIX/valid-plan.md" "$1"
  { printf '\n## Decision Ledger\n\n'
    printf '| ID | Decision | Resolution | Provenance |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '%s\n' "$2"
  } >> "$1"
}

# (pl-n) AC-1: human-attributed provenance + state present, NO sibling ledger → FAIL, names row + path
make_ledger_plan "$TMP/human-noledger.md" "| D-1 | 404 vs 409 on duplicate import | 409 | user-delegated |"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/human-noledger.md" "$LEDGER_STATE")
err=$(bash "$LINT" "$TMP/human-noledger.md" "$LEDGER_STATE" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "D-1" <<< "$err" && grep -q "156-ledger.md" <<< "$err" \
  && pass "(pl-n) human provenance, no backing ledger → 1, names row + path (AC-1)" \
  || fail "(pl-n) human provenance, no ledger — rc=$rc err=$err"

# (pl-o) AC-2: the SAME plan passes once the backing {issue}-ledger.md exists (existence-only)
: > "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/human-noledger.md" "$LEDGER_STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-o) human provenance + backing ledger present → 0 (AC-2)" \
  || fail "(pl-o) human provenance + backing ledger — rc=$rc"
rm -f "$TMP/156-ledger.md"

# (pl-p) AC-3: codebase-derived/deferred-only ledger is unaffected (no backing file needed)
make_ledger_plan "$TMP/grounded.md" "$(printf '| D-1 | DTO validation library | class-validator (repo convention) | codebase-derived |\n| D-2 | Backfill order | deferred to next milestone (owner: reporter) | deferred |')"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/grounded.md" "$LEDGER_STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-p) codebase-derived/deferred rows only → 0 (AC-3)" \
  || fail "(pl-p) grounded rows — rc=$rc"

# (pl-q) invariant: the explicit empty form (no rows, no human provenance) still passes
cp "$FIX/valid-plan.md" "$TMP/empty-form.md"
printf '\n## Decision Ledger\n\nNo material decisions — all choices codebase-derived.\n' >> "$TMP/empty-form.md"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/empty-form.md" "$LEDGER_STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-q) explicit empty form → 0 (ledger stays advisory, not hard-gated)" \
  || fail "(pl-q) explicit empty form — rc=$rc"

# (pl-r) AC-4: apostrophe in a ledger cell must not break parsing — the human row is
# still detected (regression guard, mirrors pl-m for the AC table). awk injects a lone
# apostrophe so it never traverses this harness's own shell quoting.
awk -v q="'" 'BEGIN{print "| D-1 | Owner" q "s call on retention window | keep 30d | user-answered |"}' > "$TMP/apostrophe-row.txt"
make_ledger_plan "$TMP/apostrophe-ledger.md" "$(cat "$TMP/apostrophe-row.txt")"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/apostrophe-ledger.md" "$LEDGER_STATE")
err=$(bash "$LINT" "$TMP/apostrophe-ledger.md" "$LEDGER_STATE" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "D-1" <<< "$err" \
  && pass "(pl-r) apostrophe in ledger cell — human row still parsed → 1, names D-1 (AC-4)" \
  || fail "(pl-r) apostrophe ledger cell — rc=$rc err=$err"

# (pl-s) fail-closed: human provenance with NO state arg (degraded/resume path) → FAIL
rc=$(lint_rc "$TMP/apostrophe-ledger.md")
err=$(bash "$LINT" "$TMP/apostrophe-ledger.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "fail-closed" <<< "$err" \
  && pass "(pl-s) human provenance, no state path → 1 (fail-closed)" \
  || fail "(pl-s) fail-closed no-state — rc=$rc err=$err"

# (pl-t) evasion guard: a MALFORMED (wrong-column-count) row carrying human provenance
# is still caught — Check 4 scans every cell, not just the 4th column.
make_ledger_plan "$TMP/malformed-human.md" "| D-1 | user-delegated |"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/malformed-human.md" "$LEDGER_STATE")
err=$(bash "$LINT" "$TMP/malformed-human.md" "$LEDGER_STATE" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "D-1" <<< "$err" \
  && pass "(pl-t) malformed row with human provenance still caught → 1" \
  || fail "(pl-t) malformed-human — rc=$rc err=$err"

# (pl-u) no false positive: the enum mentioned in prose (Decision/Resolution) — with a
# codebase-derived provenance — must NOT trip the gate (the `^...$` cell anchor guards this).
make_ledger_plan "$TMP/prose.md" "| D-1 | When to use user-delegated vs user-answered | prefer user-delegated for your-call cases | codebase-derived |"
rm -f "$TMP/156-ledger.md"
rc=$(lint_rc "$TMP/prose.md" "$LEDGER_STATE")
[[ "$rc" -eq 0 ]] \
  && pass "(pl-u) enum in prose cell, provenance codebase-derived → 0 (no false positive)" \
  || fail "(pl-u) prose false-positive — rc=$rc"

echo
echo "[plan-lint-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
