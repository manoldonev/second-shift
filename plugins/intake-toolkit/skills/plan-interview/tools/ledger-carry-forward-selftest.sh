#!/usr/bin/env bash
# ledger-carry-forward-selftest.sh — behavioral checks for ledger-carry-forward.sh
# (House selftest culture: shipped fixtures + inline mutants, pass/fail counters,
# exit code = number of failures).
#
# The two properties worth naming, because everything else here is a variation on them:
#
#   COMPOSITION. The helper's reason to exist is that ledger-lint.sh passes its output in
#   default mode for every receipt that passes --receipt mode. Cases (cf-b) and (cf-d)
#   assert BOTH halves — the fixture really does pass --receipt — so a green here cannot
#   mean "the premise was never true".
#
#   NO PARTIAL PROJECTION. A dropped row that still exits 0 is the failure this helper
#   exists to make impossible, so the malformed-row cases assert an EMPTY stdout, not just
#   a non-zero exit: a run that emitted its good rows and then failed would leave a
#   plausible-looking table behind for a caller that redirected it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CF="$HERE/ledger-carry-forward.sh"
LINT="$HERE/ledger-lint.sh"
FIX="$HERE/ledger-lint-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RC=0
run_cf() { # run_cf <args...> — never aborts the harness; fills $RC, $TMP/stdout, $TMP/stderr
  set +e
  bash "$CF" "$@" >"$TMP/stdout" 2>"$TMP/stderr"
  RC=$?
  set -e
}

lint_rc() { # lint_rc <args...> — echo ledger-lint's exit code
  set +e
  bash "$LINT" "$@" >/dev/null 2>&1
  echo $?
  set -e
}

# The Decision Ledger rows of a document, verbatim — what "byte-for-byte" is measured over.
rows_of() { grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$1" || true; }

echo "[ledger-carry-forward-selftest] projection of a real receipt"

# (cf-a) the shipped receipt fixture projects to its five rows, in order, with the Kind
#        column gone and the escaped pipe in D-2 intact.
run_cf "$FIX/valid-receipt.md"
cp "$TMP/stdout" "$TMP/projected.md"
# `|| true`, and not decoration: under pipefail an empty projection would make the first
# grep fail, abort the suite on set -e, and report zero FAILs for a helper that emitted
# nothing — a red that reads like a crash instead of like the case it is.
ids=$(grep -oE '^\|[[:space:]]*D-[0-9]+' "$TMP/projected.md" | grep -oE 'D-[0-9]+' | tr '\n' ' ' || true)
n_rows=$(rows_of "$TMP/projected.md" | wc -l | tr -d ' ')
if [[ "$RC" -eq 0 ]] && [[ "$n_rows" -eq 5 ]] && [[ "$ids" == "D-1 D-2 D-3 D-4 D-5 " ]]; then
  pass "(cf-a) receipt fixture → 5 rows, ids in receipt order"
else
  fail "(cf-a) rc=$RC rows=$n_rows ids='$ids'"
fi

# (cf-a2) the Kind cell is gone and Provenance is now the last column of every row.
if ! grep -qE '\|[[:space:]]*(intent|fact|open)[[:space:]]*\|' "$TMP/projected.md" \
  && [[ "$(grep -cE '\|[[:space:]]*(user-answered|user-delegated|codebase-derived|deferred|ticket-sourced)[[:space:]]*\|$' "$TMP/projected.md")" -eq 5 ]]; then
  pass "(cf-a2) Kind dropped; Provenance is the trailing column on all 5 rows"
else
  fail "(cf-a2) Kind survived or Provenance is not trailing: $(cat "$TMP/projected.md")"
fi

# (cf-a3) an escaped pipe inside a cell survives the projection as itself. The fixture's
#         D-2 Decision cell is the only place in the corpus that carries one.
if grep -qF 'shows A \| B' "$TMP/projected.md"; then
  pass "(cf-a3) escaped pipe survives the projection"
else
  fail "(cf-a3) escaped pipe lost: $(grep 'D-2' "$TMP/projected.md" || true)"
fi

# (cf-a4) the row count is reported — on stderr, so stdout stays a pure document. This is
#         the receipt that nothing was dropped quietly.
if grep -q 'projected 5 row(s)' "$TMP/stderr"; then
  pass "(cf-a4) row count reported on stderr"
else
  fail "(cf-a4) row count — got: $(cat "$TMP/stderr")"
fi

echo "[ledger-carry-forward-selftest] composition with ledger-lint.sh"

# (cf-b) AC-3, both halves: the fixture passes --receipt, and its projection passes the
#        default (plan) mode. Asserting only the second half would go green on a premise
#        that had quietly stopped holding.
premise=$(lint_rc --receipt "$FIX/valid-receipt.md")
projected=$(lint_rc "$TMP/projected.md")
if [[ "$premise" -eq 0 ]] && [[ "$projected" -eq 0 ]]; then
  pass "(cf-b) receipt passes --receipt, and its projection passes default mode"
else
  fail "(cf-b) receipt-mode rc=$premise, projection plan-mode rc=$projected"
fi

# (cf-c) idempotence: projecting the projection reproduces it byte-for-byte.
run_cf "$TMP/projected.md"
if [[ "$RC" -eq 0 ]] && cmp -s "$TMP/stdout" "$TMP/projected.md"; then
  pass "(cf-c) projecting the output is a no-op"
else
  fail "(cf-c) rc=$RC; diff: $(diff "$TMP/projected.md" "$TMP/stdout" || true)"
fi

# (cf-j) the mechanism (cf-c) rests on, probed on its own: a four-column PLAN row passes
#        through untouched. The shipped plan fixture carries an escaped pipe too, so this
#        also pins that the pass-through path is not the one doing the unescaping.
run_cf "$FIX/valid-ledger.md"
rows_of "$FIX/valid-ledger.md" > "$TMP/plan-rows-in"
rows_of "$TMP/stdout" > "$TMP/plan-rows-out"
if [[ "$RC" -eq 0 ]] && cmp -s "$TMP/plan-rows-in" "$TMP/plan-rows-out"; then
  pass "(cf-j) four-column plan rows pass through byte-for-byte"
else
  fail "(cf-j) rc=$RC; diff: $(diff "$TMP/plan-rows-in" "$TMP/plan-rows-out" || true)"
fi

echo "[ledger-carry-forward-selftest] the explicit empty form"

# A receipt in the explicit empty form. Built from the SHIPPED empty-form fixture rather
# than by retyping the sentence, so this suite holds no third copy of a string whose whole
# contract is that its copies agree.
{
  cat "$FIX/empty-form-ledger.md"
  printf '\n## Open Regions\n\nNo open regions — every decision in scope is ratified.\n'
  printf '\n## Surface Inventory\n\nNo user-visible surface — this change renders nothing a user reads.\n'
} > "$TMP/empty-receipt.md"

# (cf-d) the empty form projects to the empty form, passes the lint, and is idempotent.
premise=$(lint_rc --receipt "$TMP/empty-receipt.md")
run_cf "$TMP/empty-receipt.md"
cp "$TMP/stdout" "$TMP/empty-projected.md"
projected=$(lint_rc "$TMP/empty-projected.md")
run_cf "$TMP/empty-projected.md"
if [[ "$premise" -eq 0 ]] && [[ "$RC" -eq 0 ]] && [[ "$projected" -eq 0 ]] \
  && grep -qF 'No material decisions' "$TMP/empty-projected.md" \
  && cmp -s "$TMP/stdout" "$TMP/empty-projected.md"; then
  pass "(cf-d) empty-form receipt → empty-form plan, lint-clean and idempotent"
else
  fail "(cf-d) receipt-mode rc=$premise, plan-mode rc=$projected, reproject rc=$RC, out: $(cat "$TMP/empty-projected.md")"
fi

echo "[ledger-carry-forward-selftest] arity normalization"

# (cf-k) a five-column row with whitespace after its closing pipe still reads as five
#        columns and projects to four.
printf '## Decision Ledger\n\n| D-1 | Widget | Yes | codebase-derived | fact | \n' > "$TMP/trailing-5.md"
run_cf "$TMP/trailing-5.md"
if [[ "$RC" -eq 0 ]] && [[ "$(rows_of "$TMP/stdout")" == '| D-1 | Widget | Yes | codebase-derived |' ]]; then
  pass "(cf-k) trailing whitespace after a 5-column row → 4 columns"
else
  fail "(cf-k) rc=$RC row='$(rows_of "$TMP/stdout")'"
fi

# (cf-l) the other side of the same rule: a four-column row with trailing whitespace is
#        still four columns, and its Provenance is not mistaken for a Kind cell.
printf '## Decision Ledger\n\n| D-1 | Widget | Yes | codebase-derived | \n' > "$TMP/trailing-4.md"
run_cf "$TMP/trailing-4.md"
if [[ "$RC" -eq 0 ]] && [[ "$(rows_of "$TMP/stdout")" == '| D-1 | Widget | Yes | codebase-derived |' ]]; then
  pass "(cf-l) trailing whitespace after a 4-column row → 4 columns"
else
  fail "(cf-l) rc=$RC row='$(rows_of "$TMP/stdout")'"
fi

# (cf-i) padding inside the preserved cells is content, not decoration: an aligned receipt
#        projects to an aligned plan.
printf '## Decision Ledger\n\n| D-1  | Widget   | Yes   | codebase-derived | fact |\n' > "$TMP/aligned.md"
run_cf "$TMP/aligned.md"
if [[ "$RC" -eq 0 ]] && [[ "$(rows_of "$TMP/stdout")" == '| D-1  | Widget   | Yes   | codebase-derived |' ]]; then
  pass "(cf-i) cell padding is preserved byte-for-byte"
else
  fail "(cf-i) rc=$RC row='$(rows_of "$TMP/stdout")'"
fi

echo "[ledger-carry-forward-selftest] refusals (loud, and nothing on stdout)"

# (cf-e) a six-column row alongside a good one → exit 1, the bad row named, and NOT ONE
#        row on stdout. The good row is the point: a partial table is the silent drop.
printf '## Decision Ledger\n\n| D-1 | Widget | Yes | codebase-derived | fact |\n| D-2 | Gadget | No | deferred | open | extra |\n' > "$TMP/six-col.md"
run_cf "$TMP/six-col.md"
if [[ "$RC" -eq 1 ]] && grep -q 'unprojectable ledger row' "$TMP/stderr" \
  && grep -q 'D-2 | Gadget' "$TMP/stderr" && [[ ! -s "$TMP/stdout" ]]; then
  pass "(cf-e) 6-column row → 1, row named, stdout empty"
else
  fail "(cf-e) rc=$RC stdout=$(wc -c < "$TMP/stdout") err=$(cat "$TMP/stderr")"
fi

# (cf-f) the same for a row with too FEW columns — the shape a hand-trimmed receipt row
#        lands in when the Resolution cell is the one that got dropped.
printf '## Decision Ledger\n\n| D-1 | Widget | codebase-derived |\n' > "$TMP/three-col.md"
run_cf "$TMP/three-col.md"
if [[ "$RC" -eq 1 ]] && grep -q 'found 3' "$TMP/stderr" && [[ ! -s "$TMP/stdout" ]]; then
  pass "(cf-f) 3-column row → 1, column count named, stdout empty"
else
  fail "(cf-f) rc=$RC stdout=$(wc -c < "$TMP/stdout") err=$(cat "$TMP/stderr")"
fi

# (cf-g) no rows and no empty form → a refusal, not a manufactured "no decisions were
#        made". Emitting the form here would assert something the receipt never said.
printf '# R\n\n## Decision Ledger\n\nsome prose, no table, no empty form.\n' > "$TMP/no-rows.md"
run_cf "$TMP/no-rows.md"
if [[ "$RC" -eq 1 ]] && grep -q 'no explicit empty form' "$TMP/stderr" && [[ ! -s "$TMP/stdout" ]]; then
  pass "(cf-g) no rows and no empty form → 1, named, stdout empty"
else
  fail "(cf-g) rc=$RC stdout=$(wc -c < "$TMP/stdout") err=$(cat "$TMP/stderr")"
fi

# (cf-h) IO and usage errors are 2, distinct from 1 — a caller must be able to tell "this
#        input has no projection" from "this run never read an input at all".
run_cf "$TMP/does-not-exist.md"
rc_missing=$RC
run_cf --nonsense
rc_opt=$RC
run_cf
rc_none=$RC
if [[ "$rc_missing" -eq 2 ]] && [[ "$rc_opt" -eq 2 ]] && [[ "$rc_none" -eq 2 ]]; then
  pass "(cf-h) missing file / unknown option / no argument → 2"
else
  fail "(cf-h) missing=$rc_missing option=$rc_opt none=$rc_none"
fi

echo "[ledger-carry-forward-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
