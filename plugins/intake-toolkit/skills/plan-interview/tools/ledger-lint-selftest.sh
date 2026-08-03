#!/usr/bin/env bash
# ledger-lint-selftest.sh — deterministic checks for ledger-lint.sh (mirrors the
# plan-lint-selftest culture: fixture + inline mutants, pass/fail counters,
# exit code = number of failures).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/ledger-lint.sh"
FIX="$HERE/ledger-lint-fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

lint_rc() { # lint_rc <plan> — echo exit code, never abort the harness
  set +e
  bash "$LINT" "$@" >/dev/null 2>&1
  echo $?
  set -e
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[ledger-lint-selftest] positive cases"

# (ll-a) valid ledger with every provenance value (incl. escaped pipe in a cell,
#        and a cited ticket-sourced row) → 0
rc=$(lint_rc "$FIX/valid-ledger.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-a) valid ledger (5 rows, all provenance values) → 0" \
  || fail "(ll-a) valid ledger — got rc=$rc"

# (ll-b) explicit empty form (trivial work) → 0
rc=$(lint_rc "$FIX/empty-form-ledger.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-b) explicit empty form → 0" \
  || fail "(ll-b) empty form — got rc=$rc"

# (ll-c) row count reported on stdout
out=$(bash "$LINT" "$FIX/valid-ledger.md" 2>/dev/null)
grep -q "5 ledger row(s)" <<< "$out" \
  && pass "(ll-c) row count reported" \
  || fail "(ll-c) row count — got: $out"

echo "[ledger-lint-selftest] mutants (each must exit 1 with a named violation)"

# (ll-d) missing Decision Ledger section entirely → 1
grep -v -i 'decision ledger' "$FIX/valid-ledger.md" > "$TMP/no-section.md"
rc=$(lint_rc "$TMP/no-section.md")
err=$(bash "$LINT" "$TMP/no-section.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "missing mandated section: Decision Ledger" <<< "$err" \
  && pass "(ll-d) missing section → 1, named" \
  || fail "(ll-d) missing section — rc=$rc err=$err"

# (ll-e) illegal 'assumed' provenance → 1
sed 's/user-answered/assumed/' "$FIX/valid-ledger.md" > "$TMP/assumed.md"
rc=$(lint_rc "$TMP/assumed.md")
err=$(bash "$LINT" "$TMP/assumed.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "assumed" <<< "$err" \
  && pass "(ll-e) 'assumed' provenance → 1, named" \
  || fail "(ll-e) assumed provenance — rc=$rc err=$err"

# (ll-f) empty Resolution cell → 1
sed 's/| 409 |/|  |/' "$FIX/valid-ledger.md" > "$TMP/empty-res.md"
rc=$(lint_rc "$TMP/empty-res.md")
err=$(bash "$LINT" "$TMP/empty-res.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "empty Resolution cell" <<< "$err" \
  && pass "(ll-f) empty Resolution → 1, named" \
  || fail "(ll-f) empty Resolution — rc=$rc err=$err"

# (ll-g) malformed row (3 columns) → 1
printf '# P\n## Decision Ledger\n| ID | Decision | Provenance |\n| --- | --- | --- |\n| D-1 | x | user-answered |\n' > "$TMP/malformed.md"
rc=$(lint_rc "$TMP/malformed.md")
err=$(bash "$LINT" "$TMP/malformed.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "malformed ledger row" <<< "$err" \
  && pass "(ll-g) malformed 3-column row → 1, named" \
  || fail "(ll-g) malformed row — rc=$rc err=$err"

# (ll-h) duplicate D-n id → 1
sed 's/| D-2 |/| D-1 |/' "$FIX/valid-ledger.md" > "$TMP/dup.md"
rc=$(lint_rc "$TMP/dup.md")
err=$(bash "$LINT" "$TMP/dup.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "duplicate ledger rows" <<< "$err" \
  && pass "(ll-h) duplicate D-n id → 1, named" \
  || fail "(ll-h) duplicate id — rc=$rc err=$err"

# (ll-i) header present but no rows AND no empty form → 1
printf '# P\n## Decision Ledger\n\nsome prose, no table, no empty form.\n' > "$TMP/no-rows.md"
rc=$(lint_rc "$TMP/no-rows.md")
err=$(bash "$LINT" "$TMP/no-rows.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "no rows and no explicit empty form" <<< "$err" \
  && pass "(ll-i) header + no rows + no empty form → 1, named" \
  || fail "(ll-i) no rows — rc=$rc err=$err"

# (ll-j) usage errors → exit 2
rc=$(lint_rc)
rc2=$(lint_rc "$TMP/does-not-exist.md")
[[ "$rc" -eq 2 && "$rc2" -eq 2 ]] \
  && pass "(ll-j) missing args / missing file → 2" \
  || fail "(ll-j) usage errors — rc=$rc rc2=$rc2"

# (ll-k) quoting-safe: a cell containing an apostrophe must not abort the trim (7c5b8b16)
printf "# P\n## Decision Ledger\n| ID | Decision | Resolution | Provenance |\n| --- | --- | --- | --- |\n| D-1 | user's choice of index | it's a partial unique index | user-answered |\n" > "$TMP/apostrophe.md"
rc=$(lint_rc "$TMP/apostrophe.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-k) apostrophe/quote in cells → trim survives, 0" \
  || fail "(ll-k) quoting-safe trim — got rc=$rc"

# (ll-l) ticket-sourced row with no cited URL → 1
sed 's|, per the operator.s comment https://example.invalid/tracker/PROJ-9999#comment-7||' \
  "$FIX/valid-ledger.md" > "$TMP/uncited.md"
rc=$(lint_rc "$TMP/uncited.md")
err=$(bash "$LINT" "$TMP/uncited.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "cite the source comment by URL" <<< "$err" \
  && pass "(ll-l) uncited ticket-sourced row → 1, named" \
  || fail "(ll-l) uncited ticket-sourced — rc=$rc err=$err"

# (ll-m) quoting-safe, widened: the trim() that replaced xargs must survive every
# character class xargs chokes on — double quotes, a backslash, and an UNBALANCED
# quote (the classic xargs abort, since xargs parses quoting and dies on an unmatched
# one). (ll-k) covers apostrophes; this widens the same guard so a revert to any
# xargs-based trim fails here rather than surfacing as a hook crash during a live
# ExitPlanMode. Deliberately behavioral: grepping ledger-lint.sh for the ABSENCE of
# `xargs` would assert only that a word is missing from a file (the prose-presence
# class CLAUDE.md bans) and would miss a different quoting-unsafe rewrite.
printf '%s\n' \
  '# P' \
  '## Decision Ledger' \
  '| ID | Decision | Resolution | Provenance |' \
  '| --- | --- | --- | --- |' \
  '| D-1 | use "double quotes" | a back\slash and an unmatched '"'"' | codebase-derived |' \
  > "$TMP/quoting.md"
rc=$(lint_rc "$TMP/quoting.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-m) double quotes, backslash, unmatched quote in cells → trim survives, 0" \
  || fail "(ll-m) quoting-safe trim widened — got rc=$rc"

# (ll-n) the widened guard must still DISCRIMINATE. Surviving exotic quoting is not
# the same as parsing it correctly: a trim that swallowed the cell would also pass
# (ll-m). The same row with an illegal provenance must still be rejected, which is
# only possible if the Provenance cell was actually parsed out. `assumed` remains
# outside the enum after main widened it with `ticket-sourced` (#152).
printf '%s\n' \
  '# P' \
  '## Decision Ledger' \
  '| ID | Decision | Resolution | Provenance |' \
  '| --- | --- | --- | --- |' \
  '| D-1 | use "double quotes" | a back\slash and an unmatched '"'"' | assumed |' \
  > "$TMP/quoting-bad.md"
rc=$(lint_rc "$TMP/quoting-bad.md")
[[ "$rc" -eq 1 ]] \
  && pass "(ll-n) same quote-laden row, illegal provenance → still rejected, 1" \
  || fail "(ll-n) quote-laden discrimination — got rc=$rc"

echo "[ledger-lint-selftest] receipt mode (--receipt): the ratification bar"

# The receipt fixture, reduced to the one row each case mutates, so a case's
# failure names a single cause. Built from the fixture rather than hand-written
# so a schema drift in the fixture surfaces here too.
receipt_with() { # receipt_with <ledger-rows-file> <open-rows-block>
  printf '%s\n' '# R' '## Decision Ledger' \
    '| ID  | Decision | Resolution | Provenance | Kind |' \
    '| --- | -------- | ---------- | ---------- | ---- |'
  cat "$1"
  printf '\n%s\n' '## Open Regions'
  printf '%s\n' "$2"
}

# The explicit empty form, spelled once. Cases that are not ABOUT open regions
# use it so their failure cannot be an open-region failure in disguise.
OPEN_EMPTY='No open regions — every decision in scope is ratified.'

# (ll-o) the fixture receipt — every Kind value, every legal pairing → 0
rc=$(lint_rc --receipt "$FIX/valid-receipt.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-o) valid receipt (5 rows, 3 kinds, 2 open regions) → 0" \
  || fail "(ll-o) valid receipt — got rc=$rc"

# (ll-p) open-region count reported on stdout
out=$(bash "$LINT" --receipt "$FIX/valid-receipt.md" 2>/dev/null)
grep -q "2 open region(s)" <<< "$out" \
  && pass "(ll-p) open-region count reported" \
  || fail "(ll-p) open-region count — got: $out"

# (ll-q) THE BAR. An intent-resolving row backed by a derived or parked
# provenance is the exact comprehension debt receipt mode exists to count, so
# all three illegal backings are driven, not just one — a bar that rejected
# `deferred` while accepting `codebase-derived` would pass a single-case test
# and let the commonest evasion straight through.
for prov in codebase-derived ticket-sourced deferred; do
  printf '%s\n' "| D-1 | Rate limit for the import endpoint | 100/min | $prov | intent |" > "$TMP/row.md"
  receipt_with "$TMP/row.md" "$OPEN_EMPTY" > "$TMP/unratified-$prov.md"
  rc=$(lint_rc --receipt "$TMP/unratified-$prov.md")
  err=$(bash "$LINT" --receipt "$TMP/unratified-$prov.md" 2>&1 >/dev/null || true)
  [[ "$rc" -eq 1 ]] && grep -q "kind 'intent' requires provenance" <<< "$err" \
    && pass "(ll-q) intent row backed by '$prov' → 1, named" \
    || fail "(ll-q) intent row backed by '$prov' — rc=$rc err=$err"
done

# (ll-r) the bar DISCRIMINATES: the same row, ratified, passes. Without this the
# case above is satisfied by a mode that rejects everything.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' > "$TMP/row.md"
receipt_with "$TMP/row.md" "$OPEN_EMPTY" > "$TMP/ratified.md"
rc=$(lint_rc --receipt "$TMP/ratified.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-r) same row, user-answered → 0" \
  || fail "(ll-r) ratified intent row — got rc=$rc"

# (ll-s) a `fact` row backed by a human-attributed provenance is the mirror
# error — a decision relabeled as a derived fact.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | fact |' > "$TMP/row.md"
receipt_with "$TMP/row.md" "$OPEN_EMPTY" > "$TMP/mislabeled.md"
rc=$(lint_rc --receipt "$TMP/mislabeled.md")
err=$(bash "$LINT" --receipt "$TMP/mislabeled.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "kind 'fact' requires provenance" <<< "$err" \
  && pass "(ll-s) fact row backed by user-answered → 1, named" \
  || fail "(ll-s) mislabeled fact row — rc=$rc err=$err"

# (ll-t) an `open` row citing no OR-n at all → 1
printf '%s\n' '| D-1 | Rate limit for the import endpoint | parked, owner reporter | deferred | open |' > "$TMP/row.md"
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | pause-and-ask |' > "$TMP/uncited-open.md"
rc=$(lint_rc --receipt "$TMP/uncited-open.md")
err=$(bash "$LINT" --receipt "$TMP/uncited-open.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "must cite the declared open region" <<< "$err" \
  && pass "(ll-t) open row citing no OR-n → 1, named" \
  || fail "(ll-t) uncited open row — rc=$rc err=$err"

# (ll-u) an `open` row citing an UNDECLARED region → 1. Distinct from (ll-t):
# a citation that resolves to nothing reads as an owned gap in every downstream
# artifact, which is worse than an obviously missing one.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | parked under OR-7 | deferred | open |' > "$TMP/row.md"
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | pause-and-ask |' > "$TMP/dangling-open.md"
rc=$(lint_rc --receipt "$TMP/dangling-open.md")
err=$(bash "$LINT" --receipt "$TMP/dangling-open.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "cites open region 'OR-7', which the Open Regions section does not declare" <<< "$err" \
  && pass "(ll-u) open row citing an undeclared OR-n → 1, named" \
  || fail "(ll-u) dangling open citation — rc=$rc err=$err"

# (ll-v) an open region with a disposition outside the enum → 1. An open region
# with no disposition is an unowned gap, not a declared one.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | parked under OR-1 | deferred | open |' > "$TMP/row.md"
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | figure-it-out-later |' > "$TMP/bad-disp.md"
rc=$(lint_rc --receipt "$TMP/bad-disp.md")
err=$(bash "$LINT" --receipt "$TMP/bad-disp.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "disposition 'figure-it-out-later' not in" <<< "$err" \
  && pass "(ll-v) open region with an illegal disposition → 1, named" \
  || fail "(ll-v) illegal disposition — rc=$rc err=$err"

# (ll-w) a receipt with no Open Regions section at all → 1
printf '%s\n' '# R' '## Decision Ledger' \
  '| ID  | Decision | Resolution | Provenance | Kind |' \
  '| --- | -------- | ---------- | ---------- | ---- |' \
  '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' \
  > "$TMP/no-open-section.md"
rc=$(lint_rc --receipt "$TMP/no-open-section.md")
err=$(bash "$LINT" --receipt "$TMP/no-open-section.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "missing mandated receipt section: Open Regions" <<< "$err" \
  && pass "(ll-w) receipt with no Open Regions section → 1, named" \
  || fail "(ll-w) missing Open Regions — rc=$rc err=$err"

# (ll-x) the section present but empty of rows AND of the explicit empty form → 1
receipt_with <(printf '%s\n' '| D-1 | Rate limit | 100/min | user-answered | intent |') \
  'some prose, no table, no empty form.' > "$TMP/open-no-rows.md"
rc=$(lint_rc --receipt "$TMP/open-no-rows.md")
err=$(bash "$LINT" --receipt "$TMP/open-no-rows.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "Open Regions has no rows and no explicit empty form" <<< "$err" \
  && pass "(ll-x) Open Regions with neither rows nor empty form → 1, named" \
  || fail "(ll-x) empty Open Regions — rc=$rc err=$err"

# (ll-y) MODE ISOLATION, both directions. The Kind cell is receipt-mode only, so
# a 4-column plan ledger must still lint clean by default (it does — every case
# above this block proves it) AND must be REJECTED under --receipt, while the
# 5-column receipt must be rejected WITHOUT it. Without this pair the two modes
# could silently collapse into one permissive parser that accepts both arities.
rc=$(lint_rc --receipt "$FIX/valid-ledger.md")
err=$(bash "$LINT" --receipt "$FIX/valid-ledger.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "expected 5 columns" <<< "$err" \
  && pass "(ll-y1) 4-column plan ledger under --receipt → 1, named" \
  || fail "(ll-y1) plan ledger under receipt mode — rc=$rc err=$err"

rc=$(lint_rc "$FIX/valid-receipt.md")
err=$(bash "$LINT" "$FIX/valid-receipt.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "expected 4 columns" <<< "$err" \
  && pass "(ll-y2) 5-column receipt without --receipt → 1, named" \
  || fail "(ll-y2) receipt in default mode — rc=$rc err=$err"

# (ll-aa) an `open` row backed by anything but `deferred` → 1. The third leg of the
# Kind/provenance bar: (ll-q) drives `intent`, (ll-s) drives `fact`, and without this
# one the `open` arm is only ever exercised by rows that already satisfy it — every
# open row in every fixture is `deferred`, so deleting the check changes no result.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | parked under OR-1 | user-answered | open |' > "$TMP/row.md"
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | pause-and-ask |' > "$TMP/open-not-deferred.md"
rc=$(lint_rc --receipt "$TMP/open-not-deferred.md")
err=$(bash "$LINT" --receipt "$TMP/open-not-deferred.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "kind 'open' requires provenance 'deferred'" <<< "$err" \
  && pass "(ll-aa) open row backed by user-answered → 1, named" \
  || fail "(ll-aa) open row not deferred — rc=$rc err=$err"

# (ll-ab) a Kind outside the closed enum → 1. The default arm is what makes the enum
# CLOSED; without a case driving it, a row could carry any word at all and fall through
# every kind-specific check silently — which is worse than a mislabeled row, because
# nothing downstream would even flag it.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | guess |' > "$TMP/row.md"
receipt_with "$TMP/row.md" "$OPEN_EMPTY" > "$TMP/bad-kind.md"
rc=$(lint_rc --receipt "$TMP/bad-kind.md")
err=$(bash "$LINT" --receipt "$TMP/bad-kind.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "kind 'guess' not in" <<< "$err" \
  && pass "(ll-ab) Kind outside the closed enum → 1, named" \
  || fail "(ll-ab) out-of-enum Kind — rc=$rc err=$err"

# (ll-ac/ad/ae) the Open Regions row parser's own three refusals. Every open-region row
# in every fixture is well-formed, so each of these arms is currently unreachable from
# the suite: deleting any one of them changes no result. They are the section's
# structural checks — the ledger rows above cite these ids, so a row that parses wrong
# takes the citation check down with it.
#
# (ll-ac) wrong arity. A fourth column is not a formatting nit: the parser reads
# Disposition positionally, so an extra cell silently shifts what gets enum-checked.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' > "$TMP/row.md"
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | pause-and-ask | and one more |' > "$TMP/or-arity.md"
rc=$(lint_rc --receipt "$TMP/or-arity.md")
err=$(bash "$LINT" --receipt "$TMP/or-arity.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "malformed open-region row" <<< "$err" \
  && pass "(ll-ac) open-region row of the wrong arity → 1, named" \
  || fail "(ll-ac) malformed open-region row — rc=$rc err=$err"

# (ll-ad) an empty Region cell. The arity is legal, so only this check stands between
# an unnamed region and a receipt that reports "1 open region(s)" as if it declared one.
receipt_with "$TMP/row.md" '| OR-1 |  | pause-and-ask |' > "$TMP/or-blank-region.md"
rc=$(lint_rc --receipt "$TMP/or-blank-region.md")
err=$(bash "$LINT" --receipt "$TMP/or-blank-region.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "OR-1 row has an empty Region cell" <<< "$err" \
  && pass "(ll-ad) open-region row with an empty Region cell → 1, named" \
  || fail "(ll-ad) empty Region cell — rc=$rc err=$err"

# (ll-ae) a duplicated OR-n. Both rows are individually well-formed; the failure is
# that a ledger row citing OR-1 no longer names one region, and the dispositions can
# disagree — the citation check would resolve it to whichever the loop saw first.
receipt_with "$TMP/row.md" '| OR-1 | Rate limiting policy | pause-and-ask |
| OR-1 | Retry ceiling | reversible-default-and-flag |' > "$TMP/or-dupe.md"
rc=$(lint_rc --receipt "$TMP/or-dupe.md")
err=$(bash "$LINT" --receipt "$TMP/or-dupe.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "duplicate open-region rows for: OR-1" <<< "$err" \
  && pass "(ll-ae) duplicated OR-n → 1, named" \
  || fail "(ll-ae) duplicate open-region rows — rc=$rc err=$err"

# (ll-af) --help prints the header, and only the header. `sed -n '2,Np'` is a
# hand-maintained line number: growing the header silently truncates the help text, and
# this repo has been burned by exactly that. Both directions are asserted, because both
# are real failures — the LAST header line must be present (the range did not fall
# short) and the first line of code must not be (it did not over-reach).
out=$(bash "$LINT" --help 2>&1); rc=$?
[[ "$rc" -eq 0 ]] \
  && grep -q 'Exit: 0 clean, 1 violations' <<< "$out" \
  && ! grep -q '^set -euo pipefail' <<< "$out" \
  && pass "(ll-af) --help prints through the last header line and stops before the code" \
  || fail "(ll-af) --help did not print exactly the header — rc=$rc out=$out"

# (ll-z) an unknown option exits 2 rather than being swallowed as a path
rc=$(lint_rc --recipe "$FIX/valid-receipt.md")
[[ "$rc" -eq 2 ]] \
  && pass "(ll-z) unknown option → 2" \
  || fail "(ll-z) unknown option — got rc=$rc"

echo
echo "[ledger-lint-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
