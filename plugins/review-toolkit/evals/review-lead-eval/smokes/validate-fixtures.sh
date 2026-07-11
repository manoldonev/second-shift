#!/usr/bin/env bash
#
# $0 smoke for the review-lead synthesis eval fixtures.
# No Claude CLI, no network — pure local shape/consistency validation.
#
# Asserts, for every fixture in docs/eval-fixtures/review-lead/:
#   1. a sibling <name>.expected.json exists
#   2. the <name>.md embeds a ```json block that parses as a non-empty array
#      of reviewer objects, each with "reviewer" + ("verdict" | "result")
#   3. the <name>.expected.json is valid JSON with a top-level string
#      "expected_verdict" of Yes | No | "With fixes"
#
# Run this in CI / pre-flight. The paid baseline (run.sh) is separate.

set -uo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
FIX="$REPO/docs/eval-fixtures/review-lead"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }
[ -d "$FIX" ] || { echo "FAIL: fixtures dir not found: $FIX"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

shopt -s nullglob
count=0
for md in "$FIX"/*.md; do
  base="$(basename "$md")"
  [ "$base" = "README.md" ] && continue
  count=$((count + 1))
  name="${base%.md}"
  exp="$FIX/$name.expected.json"

  # 1. paired expected.json
  if [ ! -f "$exp" ]; then
    bad "$name: missing $name.expected.json"
    continue
  fi

  # 2. embedded findings JSON block parses as a non-empty array of reviewer objs
  block="$(awk '/^```json$/{f=1;next} /^```$/{if(f){f=0}} f' "$md")"
  if [ -z "$block" ]; then
    bad "$name: no \`\`\`json findings block in .md"
  elif ! printf '%s' "$block" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    bad "$name: findings block is not a non-empty JSON array"
  elif ! printf '%s' "$block" \
      | jq -e 'all(.[]; has("reviewer") and (has("verdict") or has("result")))' >/dev/null 2>&1; then
    bad "$name: a reviewer entry is missing \"reviewer\" or \"verdict\"/\"result\""
  else
    ok "$name: findings block valid ($(printf '%s' "$block" | jq 'length') reviewers)"
  fi

  # 3. expected.json valid + required expected_verdict key with allowed value
  if ! jq -e . "$exp" >/dev/null 2>&1; then
    bad "$name: expected.json is not valid JSON"
  elif ! jq -e '.expected_verdict | type == "string"' "$exp" >/dev/null 2>&1; then
    bad "$name: expected.json missing top-level string \"expected_verdict\""
  elif ! jq -e '.expected_verdict | ascii_downcase | . == "yes" or . == "no" or . == "with fixes"' "$exp" >/dev/null 2>&1; then
    bad "$name: expected_verdict must be Yes | No | \"With fixes\" (got $(jq -c .expected_verdict "$exp"))"
  else
    ok "$name: expected.json valid, expected_verdict=$(jq -c .expected_verdict "$exp")"
  fi
done

if [ "$count" -eq 0 ]; then
  bad "no fixtures found in $FIX"
fi

echo
echo "Result: $PASS passed, $FAIL failed ($count fixtures)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
