#!/usr/bin/env bash
# text-contract-selftest.sh — behavioral tests + lockstep guard for the explorer/emitter
# text contract (parseReviewResult / validateShape), the load-bearing parsing logic the
# #169 stall fix rests on.
#
# WHY THIS EXISTS: Workflow scripts cannot be imported (runtime-injected globals, top-level
# return), so the contract functions are re-stated per file and the earlier guards were
# string-presence only. A bug in the sentinel regex, the last-match rule, or the shape
# validator silently produces null (a dark reviewer) or accepts a malformed object — the
# exact failure class #169 exists to eliminate. This selftest closes that gap with the
# null-reviewer-selftest technique, strengthened:
#   (A) LOCKSTEP — extract the two function bodies from EVERY carrier file and assert all
#       copies are byte-identical. One drifted copy = one dispatcher parsing differently
#       from the rest, invisibly.
#   (B) BEHAVIOR — run the extracted (production, not reference) source through node with
#       adversarial cases: multiple sentinel blocks (last wins), missing sentinel,
#       malformed JSON, missing required keys, bad enums at both levels, non-array where
#       an array is required, absent-optional tolerance.
#
# Node is REQUIRED here (the functions are JavaScript); absence is a FAIL, never a skip —
# a silently-skipped gate is a false green (check-workflows-selftest.sh precedent).
#
# Bash 3.2 compatible. Runs under the repo's *-selftest.sh CI loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS="$RUN_DIR/workflows"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

command -v node >/dev/null 2>&1 || {
  echo "text-contract-selftest: FAIL — node is required to execute the contract functions." >&2
  exit 1
}

TMP="$(mktemp -d -t text-contract-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PARSE_CARRIERS="code-review.mjs plan-review.mjs unit-tests.mjs intake-review.mjs design-sync.mjs figma.mjs stall-probe.mjs"
VALIDATE_CARRIERS="code-review.mjs plan-review.mjs unit-tests.mjs intake-review.mjs design-sync.mjs figma.mjs"

extract() { # extract <file> <fn-header> -> prints the function body to stdout
  sed -n "/^const $2 = ($3) => {\$/,/^}\$/p" "$WORKFLOWS/$1"
}

# ---------- (A) lockstep ----------

ref_parse="$(extract code-review.mjs parseReviewResult 'text')"
[ -n "$ref_parse" ] || bad "A0 could not extract parseReviewResult from code-review.mjs"
drift=0
for f in $PARSE_CARRIERS; do
  cur="$(extract "$f" parseReviewResult 'text')"
  if [ -z "$cur" ]; then
    bad "A1 $f carries no extractable parseReviewResult"
    drift=$((drift + 1))
  elif [ "$cur" != "$ref_parse" ]; then
    bad "A1 $f parseReviewResult drifted from the canonical copy"
    drift=$((drift + 1))
  fi
done
[ "$drift" -eq 0 ] && ok "A1 parseReviewResult byte-identical across all 7 carriers"

ref_validate="$(extract code-review.mjs validateShape 'obj, schema')"
[ -n "$ref_validate" ] || bad "A0 could not extract validateShape from code-review.mjs"
drift=0
for f in $VALIDATE_CARRIERS; do
  cur="$(extract "$f" validateShape 'obj, schema')"
  if [ -z "$cur" ]; then
    bad "A2 $f carries no extractable validateShape"
    drift=$((drift + 1))
  elif [ "$cur" != "$ref_validate" ]; then
    bad "A2 $f validateShape drifted from the canonical copy"
    drift=$((drift + 1))
  fi
done
[ "$drift" -eq 0 ] && ok "A2 validateShape byte-identical across all 6 carriers"

# ---------- (B) behavior — the PRODUCTION source, extracted, not a reference copy ----------

{
  printf '%s\n%s\n' "$ref_parse" "$ref_validate"
  cat <<'EOF'
const assert = (name, cond) => {
  if (cond) console.log('  ok: ' + name)
  else { console.error('  FAIL: ' + name); process.exitCode = 1 }
}

// parseReviewResult
const block = (json) => 'REVIEW_RESULT\n```json\n' + json + '\n```'
assert('B1 valid block parses', JSON.parse(JSON.stringify(parseReviewResult('prose\n' + block('{"a":1}')))).a === 1)
assert('B2 missing sentinel -> null', parseReviewResult('just prose, no sentinel') === null)
assert('B3 malformed JSON -> null', parseReviewResult(block('{"a":')) === null)
assert('B4 LAST block wins when the agent quotes the instruction first',
  parseReviewResult(block('{"which":"first"}') + '\nmore prose\n' + block('{"which":"last"}')).which === 'last')
assert('B5 null/undefined input -> null', parseReviewResult(null) === null && parseReviewResult(undefined) === null)
assert('B6 sentinel without fence -> null', parseReviewResult('REVIEW_RESULT but no fence') === null)

// validateShape — a trinary plan-review-like schema exercises every branch.
const SCHEMA = {
  type: 'object',
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['block', 'fix-and-go', 'pass'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'message'],
        properties: { severity: { type: 'string', enum: ['blocker', 'warning', 'note'] }, message: { type: 'string' } },
      },
    },
    summary: { type: 'string' },
  },
}
const good = { verdict: 'pass', findings: [{ severity: 'note', message: 'm' }] }
assert('B7 valid object passes', validateShape(good, SCHEMA) === true)
assert('B8 missing required key fails', validateShape({ verdict: 'pass' }, SCHEMA) === false)
assert('B9 bad top-level enum fails', validateShape({ verdict: 'maybe', findings: [] }, SCHEMA) === false)
assert('B10 bad enum inside array item fails',
  validateShape({ verdict: 'pass', findings: [{ severity: 'catastrophic', message: 'm' }] }, SCHEMA) === false)
assert('B11 missing item-required key fails',
  validateShape({ verdict: 'pass', findings: [{ severity: 'note' }] }, SCHEMA) === false)
assert('B12 non-array where array required fails',
  validateShape({ verdict: 'pass', findings: 'nope' }, SCHEMA) === false)
assert('B13 absent optional field tolerated', validateShape({ verdict: 'pass', findings: [] }, SCHEMA) === true)
assert('B14 null input fails closed', validateShape(null, SCHEMA) === false)
assert('B15 non-object item fails', validateShape({ verdict: 'pass', findings: ['str'] }, SCHEMA) === false)
EOF
} > "$TMP/behavior.mjs"

if node "$TMP/behavior.mjs" 2>&1; then
  ok "B behavioral suite over the extracted production source (see case lines above)"
else
  bad "B behavioral suite failed — the shipped contract functions misbehave"
fi

echo "text-contract-selftest: $PASS passed, $FAIL failed (plus per-case B lines above)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
