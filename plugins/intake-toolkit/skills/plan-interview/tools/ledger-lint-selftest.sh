#!/usr/bin/env bash
# ledger-lint-selftest.sh — deterministic checks for ledger-lint.sh (mirrors the
# House selftest culture: fixture + inline mutants, pass/fail counters,
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

# Receipt mode reads `design.provider` from SECOND_SHIFT_CONFIG, else from the config in the
# receipt's own checkout — and the operator's shell exports the first, while the fixtures sit
# in this repo's checkout. Pin it to a config with no provider, so no case reads a machine's
# setup; the design cases below point it at their own.
printf '{}\n' > "$TMP/config-no-design.json"
printf '{"design":{"provider":"figma"}}\n' > "$TMP/config-design.json"
export SECOND_SHIFT_CONFIG="$TMP/config-no-design.json"

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

echo "[ledger-lint-selftest] receipt mode (--receipt): the provenance bar"

# The receipt fixture, reduced to the one row each case mutates, so a case's
# failure names a single cause. Built from the fixture rather than hand-written
# so a schema drift in the fixture surfaces here too.
receipt_with() { # receipt_with <ledger-rows-file> <open-rows-block> [surface-block] [checks-block]
  printf '%s\n' '# R' '## Decision Ledger' \
    '| ID  | Decision | Resolution | Provenance | Kind |' \
    '| --- | -------- | ---------- | ---------- | ---- |'
  cat "$1"
  printf '\n%s\n' '## Open Regions'
  printf '%s\n' "$2"
  printf '\n%s\n' '## Surface Inventory'
  printf '%s\n' "${3-$SURFACE_EMPTY}"
  printf '\n%s\n' '## Checks'
  printf '%s\n' "${4-$CHECKS_EMPTY}"
}

# The explicit empty forms, spelled once each. Cases that are not ABOUT open
# regions (or surfaces) use them so their failure cannot be an open-region or
# surface failure in disguise. SURFACE_EMPTY is `receipt_with`'s default third
# argument, so every case predating the Surface Inventory section keeps naming
# exactly one cause.
OPEN_EMPTY='No open regions — every decision in scope is ratified.'
SURFACE_EMPTY='No user-visible surface — this change renders nothing a user reads.'
CHECKS_EMPTY='No ticket-specific checks — the configured lanes cover this change.'

# (ll-o) the fixture receipt — every Kind value, every legal pairing → 0
rc=$(lint_rc --receipt "$FIX/valid-receipt.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-o) valid receipt (5 rows, 3 kinds, 2 open regions) → 0" \
  || fail "(ll-o) valid receipt — got rc=$rc"

# (ll-p) open-region and surface counts reported on stdout
out=$(bash "$LINT" --receipt "$FIX/valid-receipt.md" 2>/dev/null)
grep -q "2 open region(s)" <<< "$out" && grep -q "3 surface(s)" <<< "$out" \
  && pass "(ll-p) open-region and surface counts reported" \
  || fail "(ll-p) receipt counts — got: $out"

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

# (ll-r) the bar DISCRIMINATES: the same row, user-answered, passes. Without this the
# case above is satisfied by a mode that rejects everything.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' > "$TMP/row.md"
receipt_with "$TMP/row.md" "$OPEN_EMPTY" > "$TMP/ratified.md"
rc=$(lint_rc --receipt "$TMP/ratified.md")
[[ "$rc" -eq 0 ]] \
  && pass "(ll-r) same row, user-answered → 0" \
  || fail "(ll-r) user-answered intent row — got rc=$rc"

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
  '' '## Surface Inventory' "$SURFACE_EMPTY" \
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

echo "[ledger-lint-selftest] receipt mode (--receipt): the surface inventory"

# The inventory's cases all share one well-formed ledger, so a failure names a
# surface-row cause and not a provenance-bar one. D-1 and D-2 exist, D-9 does not
# — that asymmetry is what the dangling-citation case rides on.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |
| D-2 | Empty-list copy | "Nothing imported yet" | user-answered | intent |' > "$TMP/surface-ledger.md"
surface_receipt() { # surface_receipt <surface-block>
  receipt_with "$TMP/surface-ledger.md" "$OPEN_EMPTY" "$1"
}

# (ll-ag) a well-formed inventory, both dispositions → 0. The discriminator: every
# refusal below is satisfied by a mode that rejects every inventory, and this is the
# only case that says otherwise.
surface_receipt '| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Loading state for the import list | decided (D-1) |
| S-2 | Print stylesheet | out-of-scope — nothing here is printed |' > "$TMP/surface-ok.md"
rc=$(lint_rc --receipt "$TMP/surface-ok.md")
err=$(bash "$LINT" --receipt "$TMP/surface-ok.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 0 ]] \
  && pass "(ll-ag) well-formed surface inventory (both dispositions) → 0" \
  || fail "(ll-ag) well-formed inventory — rc=$rc err=$err"

# (ll-ah) no Surface Inventory section at all → 1. THE point of the section: a receipt
# that lists no surfaces is claiming the work implies none, and the claim has to be
# made rather than left implicit. Built inline because `receipt_with` always emits one.
printf '%s\n' '# R' '## Decision Ledger' \
  '| ID  | Decision | Resolution | Provenance | Kind |' \
  '| --- | -------- | ---------- | ---------- | ---- |' \
  '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' \
  '' '## Open Regions' "$OPEN_EMPTY" \
  > "$TMP/no-surface-section.md"
rc=$(lint_rc --receipt "$TMP/no-surface-section.md")
err=$(bash "$LINT" --receipt "$TMP/no-surface-section.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "missing mandated receipt section: Surface Inventory" <<< "$err" \
  && pass "(ll-ah) receipt with no Surface Inventory section → 1, named" \
  || fail "(ll-ah) missing Surface Inventory — rc=$rc err=$err"

# (ll-ai) the section present but empty of rows AND of the explicit empty form → 1.
# Distinct from (ll-ah): a heading with prose under it reads as an inventory to a
# human skimming the receipt, which is the worse of the two failures.
surface_receipt 'some prose about the UI, no table, no empty form.' > "$TMP/surface-no-rows.md"
rc=$(lint_rc --receipt "$TMP/surface-no-rows.md")
err=$(bash "$LINT" --receipt "$TMP/surface-no-rows.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "Surface Inventory has no rows and no explicit empty form" <<< "$err" \
  && pass "(ll-ai) Surface Inventory with neither rows nor empty form → 1, named" \
  || fail "(ll-ai) empty Surface Inventory — rc=$rc err=$err"

# (ll-aj) the explicit empty form alone → 0. Genuinely surface-free work (a lint, a
# CI change) must have a legal way through; without this case the section would be
# a tax that every backend ticket pays in invented rows.
surface_receipt "$SURFACE_EMPTY" > "$TMP/surface-empty-form.md"
rc=$(lint_rc --receipt "$TMP/surface-empty-form.md")
err=$(bash "$LINT" --receipt "$TMP/surface-empty-form.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 0 ]] \
  && pass "(ll-aj) Surface Inventory explicit empty form → 0" \
  || fail "(ll-aj) surface empty form — rc=$rc err=$err"

# (ll-ak) a disposition outside the closed enum → 1. The default arm is what makes the
# enum closed; without it a surface could carry any word and fall through both
# disposition-specific checks silently — an unaccounted surface that reads as accounted.
surface_receipt '| S-1 | Loading state for the import list | probably fine |' > "$TMP/surface-bad-disp.md"
rc=$(lint_rc --receipt "$TMP/surface-bad-disp.md")
err=$(bash "$LINT" --receipt "$TMP/surface-bad-disp.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "disposition 'probably fine' not in" <<< "$err" \
  && pass "(ll-ak) surface disposition outside the enum → 1, named" \
  || fail "(ll-ak) illegal surface disposition — rc=$rc err=$err"

# (ll-al) `decided` citing no D-n → 1. The inventory's version of a silent assumption:
# it asserts a decision exists without naming one.
surface_receipt '| S-1 | Loading state for the import list | decided |' > "$TMP/surface-uncited.md"
rc=$(lint_rc --receipt "$TMP/surface-uncited.md")
err=$(bash "$LINT" --receipt "$TMP/surface-uncited.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "disposition 'decided' must cite the ledger row" <<< "$err" \
  && pass "(ll-al) 'decided' citing no D-n → 1, named" \
  || fail "(ll-al) uncited decided row — rc=$rc err=$err"

# (ll-am) `decided` citing a D-n the ledger does not declare → 1. Distinct from (ll-al)
# for the same reason (ll-u) is distinct from (ll-t): a citation resolving to nothing
# reads as a covered surface in every downstream artifact.
surface_receipt '| S-1 | Loading state for the import list | decided (D-9) |' > "$TMP/surface-dangling.md"
rc=$(lint_rc --receipt "$TMP/surface-dangling.md")
err=$(bash "$LINT" --receipt "$TMP/surface-dangling.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "S-1 row cites decision 'D-9', which the Decision Ledger does not declare" <<< "$err" \
  && pass "(ll-am) 'decided' citing an undeclared D-n → 1, named" \
  || fail "(ll-am) dangling surface citation — rc=$rc err=$err"

# (ll-an) `out-of-scope` with no reason → 1. Scoping a surface out is legitimate;
# scoping it out silently is the batch-blessing move in miniature.
surface_receipt '| S-1 | Print stylesheet | out-of-scope |' > "$TMP/surface-no-reason.md"
rc=$(lint_rc --receipt "$TMP/surface-no-reason.md")
err=$(bash "$LINT" --receipt "$TMP/surface-no-reason.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "must carry the reason it is out of scope" <<< "$err" \
  && pass "(ll-an) 'out-of-scope' with no reason → 1, named" \
  || fail "(ll-an) reasonless out-of-scope — rc=$rc err=$err"

# (ll-ao) the token is a PREFIX match on a non-word boundary, so a word that merely
# starts with a legal token is not one. Without this the enum check degrades to a
# substring test and `decidedly unclear` lints clean as a decided surface.
surface_receipt '| S-1 | Loading state for the import list | decidedly unclear (D-1) |' > "$TMP/surface-prefix.md"
rc=$(lint_rc --receipt "$TMP/surface-prefix.md")
err=$(bash "$LINT" --receipt "$TMP/surface-prefix.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "disposition 'decidedly unclear (D-1)' not in" <<< "$err" \
  && pass "(ll-ao) a disposition merely PREFIXED by a legal token → 1, named" \
  || fail "(ll-ao) prefix-boundary discrimination — rc=$rc err=$err"

# (ll-ap) an empty Surface cell. The arity is legal, so only this check stands between
# an unnamed surface and a receipt reporting "1 surface(s)" as if it listed one.
surface_receipt '| S-1 |  | decided (D-1) |' > "$TMP/surface-blank.md"
rc=$(lint_rc --receipt "$TMP/surface-blank.md")
err=$(bash "$LINT" --receipt "$TMP/surface-blank.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "S-1 row has an empty Surface cell" <<< "$err" \
  && pass "(ll-ap) surface row with an empty Surface cell → 1, named" \
  || fail "(ll-ap) empty Surface cell — rc=$rc err=$err"

# (ll-aq) wrong arity. Disposition is read positionally, so a fourth column silently
# shifts what gets enum-checked — the same failure (ll-ac) guards on open regions.
surface_receipt '| S-1 | Loading state | decided (D-1) | and one more |' > "$TMP/surface-arity.md"
rc=$(lint_rc --receipt "$TMP/surface-arity.md")
err=$(bash "$LINT" --receipt "$TMP/surface-arity.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "malformed surface row" <<< "$err" \
  && pass "(ll-aq) surface row of the wrong arity → 1, named" \
  || fail "(ll-aq) malformed surface row — rc=$rc err=$err"

# (ll-ar) a duplicated S-n. Both rows are individually well-formed; the failure is that
# the inventory no longer accounts for two distinct surfaces, and a reader counting
# rows against the scope gets the wrong number.
surface_receipt '| S-1 | Loading state | decided (D-1) |
| S-1 | Empty state | decided (D-2) |' > "$TMP/surface-dupe.md"
rc=$(lint_rc --receipt "$TMP/surface-dupe.md")
err=$(bash "$LINT" --receipt "$TMP/surface-dupe.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 1 ]] && grep -q "duplicate surface rows for: S-1" <<< "$err" \
  && pass "(ll-ar) duplicated S-n → 1, named" \
  || fail "(ll-ar) duplicate surface rows — rc=$rc err=$err"

# (ll-as) MODE ISOLATION for the new section, matching (ll-y). The inventory is
# receipt-only, so an in-plan ledger must lint clean by default — otherwise every
# ExitPlanMode in every consumer repo starts failing on a section the plan contract
# never mentions.
#
# The plan here carries a Surface Inventory that is malformed on EVERY axis the
# receipt checks: no empty form, a duplicated id, a blank Surface cell, a
# disposition outside the enum, and a `decided` citing a D-n the ledger does not
# declare. A plan ledger with no S-n rows at all (which is what `valid-ledger.md`
# is, and what (ll-a) already drives) cannot distinguish "the parser is gated off"
# from "the parser ran and found nothing" — this fixture can.
printf '%s\n' '# P' '## Decision Ledger' \
  '| ID  | Decision | Resolution | Provenance |' \
  '| --- | -------- | ---------- | ---------- |' \
  '| D-1 | Rate limit for the import endpoint | 100/min | user-answered |' \
  '' '## Surface Inventory' \
  '| ID | Surface | Disposition |' \
  '| --- | --- | --- |' \
  '| S-1 |  | probably fine |' \
  '| S-1 | Loading state | decided (D-9) |' \
  > "$TMP/plan-with-surfaces.md"
rc=$(lint_rc "$TMP/plan-with-surfaces.md")
err=$(bash "$LINT" "$TMP/plan-with-surfaces.md" 2>&1 >/dev/null || true)
[[ "$rc" -eq 0 ]] \
  && pass "(ll-as) plan carrying a malformed Surface Inventory, default mode → 0" \
  || fail "(ll-as) surface check leaked into default mode — rc=$rc err=$err"

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

echo "[ledger-lint-selftest] receipt mode: ## Checks (#886)"

# The scheduler runs these commands against the pushed head, read from the record's first
# commit — so the lint must read the section the way the scheduler reads it.
printf '%s\n' '| D-1 | Rate limit for the import endpoint | 100/min | user-answered | intent |' > "$TMP/ck-row.md"
ck_lint() { # ck_lint <receipt> — sets rc, out, err
  rc=$(lint_rc --receipt "$1")
  out=$(bash "$LINT" --receipt "$1" 2>/dev/null || true)
  err=$(bash "$LINT" --receipt "$1" 2>&1 >/dev/null || true)
}

# (ll-ck1) both command forms count, backticked and bare → 0
ck_lint "$FIX/valid-receipt.md"
[[ "$rc" -eq 0 ]] && grep -q "2 check(s)" <<< "$out" \
  && pass "(ll-ck1) the fixture's two checks, '- \`cmd\`' and '- cmd', are read → 0" \
  || fail "(ll-ck1) valid checks — rc=$rc out=$out err=$err"

# (ll-ck2) no section at all → 1, naming the section AND its empty form, as Open Regions does
receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" > "$TMP/ck-none.md"
grep -v -e '^## Checks' -e "$CHECKS_EMPTY" "$TMP/ck-none.md" > "$TMP/ck-absent.md"
ck_lint "$TMP/ck-absent.md"
[[ "$rc" -eq 1 ]] && grep -q "missing mandated receipt section: Checks" <<< "$err" && grep -qF "$CHECKS_EMPTY" <<< "$err" \
  && pass "(ll-ck2) receipt with no Checks section → 1, naming the section and its empty form" \
  || fail "(ll-ck2) missing Checks — rc=$rc err=$err"

# (ll-ck3) the explicit empty form alone → 0 (the discriminator for ck2)
ck_lint "$TMP/ck-none.md"
[[ "$rc" -eq 0 ]] && grep -q "0 check(s)" <<< "$out" \
  && pass "(ll-ck3) Checks explicit empty form → 0" \
  || fail "(ll-ck3) checks empty form — rc=$rc err=$err"

# (ll-ck4) a heading with prose and no command, no empty form → 1
receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" "$SURFACE_EMPTY" 'run the usual things.' > "$TMP/ck-prose.md"
ck_lint "$TMP/ck-prose.md"
[[ "$rc" -eq 1 ]] && grep -q "Checks has no command and no explicit empty form" <<< "$err" \
  && pass "(ll-ck4) Checks with neither a command nor the empty form → 1, named" \
  || fail "(ll-ck4) prose-only Checks — rc=$rc err=$err"

# (ll-ck5) a bullet the scheduler's parse drops (inner backticks, an indented or `*` bullet) → 1.
# Without this the lint counts a check the scheduler silently never runs.
# shellcheck disable=SC2016  # markdown backticks
# '---' and '-cmd' are the other direction: the scheduler RUNS them ('--', 'cmd').
for bad in '- run `yarn test` then `yarn lint`' '  - yarn test' '* yarn test' '---' '-echo nospace'; do
  receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" "$SURFACE_EMPTY" "$bad" > "$TMP/ck-bad.md"
  ck_lint "$TMP/ck-bad.md"
  [[ "$rc" -eq 1 ]] && grep -q "Checks line is not one command the scheduler can read" <<< "$err" \
    && pass "(ll-ck5) unreadable check line '$bad' → 1, named" \
    || fail "(ll-ck5) unreadable check line '$bad' — rc=$rc err=$err"
done

# (ll-ck6) THE HEADING RULE, the scheduler's (AC-3). Any depth and any case open the section;
# a longer title does not; any heading closes it; the first section decides.
receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" > "$TMP/ck-base.md"
sed 's/^## Checks$/#### CHECKS/' "$TMP/ck-base.md" > "$TMP/ck-depth.md"
ck_lint "$TMP/ck-depth.md"
[[ "$rc" -eq 0 ]] \
  && pass "(ll-ck6a) '#### CHECKS' is the section → 0" \
  || fail "(ll-ck6a) depth/case — rc=$rc err=$err"

sed 's/^## Checks$/## Checks we might add later/' "$TMP/ck-base.md" > "$TMP/ck-longer.md"
ck_lint "$TMP/ck-longer.md"
[[ "$rc" -eq 1 ]] && grep -q "missing mandated receipt section: Checks" <<< "$err" \
  && pass "(ll-ck6b) '## Checks we might add later' is not the section → 1" \
  || fail "(ll-ck6b) longer title — rc=$rc err=$err"

receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" "$SURFACE_EMPTY" 'see below.
## Notes
- yarn test' > "$TMP/ck-closed.md"
ck_lint "$TMP/ck-closed.md"
[[ "$rc" -eq 1 ]] && grep -q "Checks has no command and no explicit empty form" <<< "$err" \
  && pass "(ll-ck6c) a command under the NEXT heading is not a check → 1" \
  || fail "(ll-ck6c) any heading closes — rc=$rc err=$err"

receipt_with "$TMP/ck-row.md" "$OPEN_EMPTY" "$SURFACE_EMPTY" 'see below.' > "$TMP/ck-first.md"
printf '\n%s\n%s\n' '## Checks' '- yarn test' >> "$TMP/ck-first.md"
ck_lint "$TMP/ck-first.md"
[[ "$rc" -eq 1 ]] && grep -q "Checks has no command and no explicit empty form" <<< "$err" \
  && pass "(ll-ck6d) the FIRST Checks section decides; a second one is not read → 1" \
  || fail "(ll-ck6d) first section decides — rc=$rc err=$err"

echo "[ledger-lint-selftest] receipt mode: ## Design frames (#886)"

# (ll-df1) a provider repo, frames table with every cell filled → 0, rows counted
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$FIX/valid-receipt-design.md"
[[ "$rc" -eq 0 ]] && grep -q "2 design frame(s)" <<< "$out" \
  && pass "(ll-df1) design.provider set, two filled RS rows → 0" \
  || fail "(ll-df1) valid frames — rc=$rc out=$out err=$err"

# Every design case below starts from that fixture with the section swapped.
grep -v -e '^## Design frames' -e '^| RS' -e '^| --- | --- | --- | --- | --- |' -e '^| RS |' \
  "$FIX/valid-receipt-design.md" > "$TMP/df-none.md"
df_with() { # df_with <heading> <body> — the no-frames receipt plus one design section
  cat "$TMP/df-none.md"; printf '\n%s\n%s\n' "$1" "$2"
}

# (ll-df2) provider set and no section → 1, naming the provider and both forms
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-none.md"
[[ "$rc" -eq 1 ]] && grep -q "config sets design.provider 'figma'" <<< "$err" && grep -q "Design: none — <reason>" <<< "$err" \
  && pass "(ll-df2) design.provider set, no Design frames section → 1, named" \
  || fail "(ll-df2) missing frames — rc=$rc err=$err"

# (ll-df3) ...and WITHOUT a provider the same receipt is clean: the section is optional (AC-2)
ck_lint "$TMP/df-none.md"
[[ "$rc" -eq 0 ]] \
  && pass "(ll-df3) no design.provider, no Design frames section → 0" \
  || fail "(ll-df3) section required without a provider — rc=$rc err=$err"

# (ll-df4) the section with neither a row nor a disarm → 1
df_with '## Design frames' 'The screens are in Figma.' > "$TMP/df-prose.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-prose.md"
[[ "$rc" -eq 1 ]] && grep -q "config sets design.provider" <<< "$err" \
  && pass "(ll-df4) Design frames with neither an RS row nor a disarm → 1" \
  || fail "(ll-df4) prose-only frames — rc=$rc err=$err"

# (ll-df5) a disarm with no reason → 1; with one → 0
df_with '## Design frames' 'Design: none' > "$TMP/df-bare.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-bare.md"
[[ "$rc" -eq 1 ]] && grep -q "disarms this ticket but states no reason" <<< "$err" \
  && pass "(ll-df5a) 'Design: none' with no reason → 1, named" \
  || fail "(ll-df5a) bare disarm — rc=$rc err=$err"
df_with '## Design frames' 'Design: none — this ticket renders no new screen' > "$TMP/df-disarm.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-disarm.md"
[[ "$rc" -eq 0 ]] \
  && pass "(ll-df5b) 'Design: none — <reason>' → 0" \
  || fail "(ll-df5b) reasoned disarm — rc=$rc err=$err"
# (ll-df5c) a dash with nothing after it is not a reason
for bare in 'Design: none —' 'Design: none - ' 'Design: none --'; do
  df_with '## Design frames' "$bare" > "$TMP/df-dash.md"
  SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-dash.md"
  [[ "$rc" -eq 1 ]] && grep -q "disarms this ticket but states no reason" <<< "$err" \
    && pass "(ll-df5c) '$bare' (a dash, no reason) → 1, named" \
    || fail "(ll-df5c) dash-only disarm '$bare' — rc=$rc err=$err"
done

# (ll-df6) a row with an empty must-show cell → 1: it is the route smoke's only assertion.
# Driven on a repo WITHOUT a provider too — the smoke reads rows wherever they are.
df_with '## Design frames' '| RS | route | state | frame | must-show |
| --- | --- | --- | --- | --- |
| RS-1 | /imports | empty | 815:2201 |  |' > "$TMP/df-nomust.md"
for cfg in config-design config-no-design; do
  SECOND_SHIFT_CONFIG="$TMP/$cfg.json" ck_lint "$TMP/df-nomust.md"
  [[ "$rc" -eq 1 ]] && grep -q "RS-1 row has an empty must-show cell" <<< "$err" \
    && pass "(ll-df6) RS row with an empty must-show cell ($cfg) → 1, named" \
    || fail "(ll-df6) empty must-show ($cfg) — rc=$rc err=$err"
done

# (ll-df7) the gate's 4-column RS row (AC refs, no frame, no must-show) → 1, not read as armed
df_with '## Design frames' '| RS-1 | /imports | empty | AC-1 |' > "$TMP/df-4col.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-4col.md"
[[ "$rc" -eq 1 ]] && grep -q "malformed design frames row" <<< "$err" \
  && pass "(ll-df7) a 4-column RS row → 1, named" \
  || fail "(ll-df7) 4-column row — rc=$rc err=$err"

# (ll-df7b) an escaped pipe in a cell → 1: the scheduler splits on it, so its cells differ
df_with '## Design frames' '| RS-1 | /imports | empty | 815:2201 | a \| b |' > "$TMP/df-esc.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-esc.md"
[[ "$rc" -eq 1 ]] && grep -q "escaped pipe" <<< "$err" \
  && pass "(ll-df7b) an RS row with an escaped pipe → 1, named" \
  || fail "(ll-df7b) escaped pipe — rc=$rc err=$err"

# (ll-df8) '## Design' is the section too, as the gate accepted it (AC-3); '## Design notes' is not
df_with '### design' '| RS-1 | /imports | empty | 815:2201 | Nothing imported yet |' > "$TMP/df-short.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-short.md"
[[ "$rc" -eq 0 ]] && grep -q "1 design frame(s)" <<< "$out" \
  && pass "(ll-df8a) '### design' carries the frames → 0" \
  || fail "(ll-df8a) short title — rc=$rc err=$err"
df_with '## Design notes' '| RS-1 | /imports | empty | 815:2201 | Nothing imported yet |' > "$TMP/df-notes.md"
SECOND_SHIFT_CONFIG="$TMP/config-design.json" ck_lint "$TMP/df-notes.md"
[[ "$rc" -eq 1 ]] && grep -q "config sets design.provider" <<< "$err" \
  && pass "(ll-df8b) '## Design notes' is not the section → 1" \
  || fail "(ll-df8b) longer title — rc=$rc err=$err"

# (ll-df9) with SECOND_SHIFT_CONFIG unset, the config is the one in the receipt's own checkout
# (<repo>/.claude/second-shift.config.json), as the scheduler reads it.
mkdir -p "$TMP/repo/.claude/pipeline-state"
git -C "$TMP/repo" init -q
cp "$TMP/config-design.json" "$TMP/repo/.claude/second-shift.config.json"
cp "$TMP/df-none.md" "$TMP/repo/.claude/pipeline-state/1-ledger.md"
rc=$(env -u SECOND_SHIFT_CONFIG bash "$LINT" --receipt "$TMP/repo/.claude/pipeline-state/1-ledger.md" >/dev/null 2>&1; echo $?)
rc2=$(env -u SECOND_SHIFT_CONFIG bash "$LINT" --receipt "$TMP/df-none.md" >/dev/null 2>&1; echo $?)
[[ "$rc" -eq 1 && "$rc2" -eq 0 ]] \
  && pass "(ll-df9) no SECOND_SHIFT_CONFIG: the receipt's checkout config arms the rule; outside a checkout nothing does" \
  || fail "(ll-df9) config fallback — in-repo rc=$rc, no-repo rc=$rc2"

# (ll-df10) a config that is present but not JSON → 2, never a silent 'no provider'
printf '{not json\n' > "$TMP/config-broken.json"
rc=$(SECOND_SHIFT_CONFIG="$TMP/config-broken.json" lint_rc --receipt "$TMP/df-none.md")
[[ "$rc" -eq 2 ]] \
  && pass "(ll-df10) unparseable config → 2" \
  || fail "(ll-df10) unparseable config — rc=$rc"

echo
echo "[ledger-lint-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
