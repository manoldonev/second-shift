#!/usr/bin/env bash
# Selftest for check-fixtures.sh — the model-free guard on the figma-faithful-reviewer eval's
# expected files.
#
# What it has to prove, beyond "it runs":
#   - the shipped fixtures pass, and they include at least six planted-defect conformance fixtures
#     and one conformance control, each naming a disproving line in the `acme-ui` stand-in;
#   - an expected file that does not parse reds, and the report names it;
#   - a cited line that is not in its file reds, and the report names the citation;
#   - a cited file that does not exist, a path outside the stand-in, a line that is not a positive
#     integer, and an empty citation list each red;
#   - an empty fixture set is rc=2, distinct from a violation's rc=1.
#
# No install, no network, no model. CI runs this via the *-selftest.sh glob, incl. macOS bash 3.2.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-fixtures.sh"
fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
COPY="$TMP/eval"

# A fresh copy of the shipped eval's fixtures per case, so each case breaks exactly one thing.
reset_copy() {
    rm -rf "$COPY"
    mkdir -p "$COPY"
    cp -R "$SCRIPT_DIR/fixtures" "$COPY/fixtures"
}

# Rewrites one expected file through jq, so a case edits the citation it means to and no other.
rewrite() {
    local file="$1" filter="$2"
    jq "$filter" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

LAST_OUT=""
expect_rc() {
    local want="$1" label="$2" root="$3" got
    LAST_OUT=$(bash "$CHECK" "$root" 2>&1)
    got=$?
    if [ "$got" = "$want" ]; then
        echo "PASS: $label (rc=$got)"
    else
        echo "FAIL: $label — expected rc=$want, got rc=$got" >&2
        echo "$LAST_OUT" >&2
        fail=1
    fi
}

expect_report_contains() {
    case "$LAST_OUT" in
        *"$1"*) echo "PASS: $2" ;;
        *) echo "FAIL: $2 — report did not mention '$1'" >&2; echo "$LAST_OUT" >&2; fail=1 ;;
    esac
}

# 1) The shipped fixtures pass.
expect_rc 0 "the shipped fixtures parse and every cited line exists" "$SCRIPT_DIR"

# 2) The shipped set carries the conformance fixtures the eval needs: at least six planted defects
#    and one clean control, each with a non-empty `disproving` list.
revise=0
approve=0
for f in "$SCRIPT_DIR"/fixtures/*.expected.json; do
    verdict=$(jq -r 'if ((.disproving // []) | length) > 0 then .expected_verdict else "none" end' "$f" 2>/dev/null)
    case "$verdict" in
        revise) revise=$((revise + 1)) ;;
        approve) approve=$((approve + 1)) ;;
    esac
done
if [ "$revise" -ge 6 ] && [ "$approve" -ge 1 ]; then
    echo "PASS: the shipped set has $revise planted-defect conformance fixtures and $approve conformance control(s)"
else
    echo "FAIL: expected at least 6 planted-defect conformance fixtures and 1 control with disproving lines, found $revise and $approve" >&2
    fail=1
fi

# The target of the citation cases: the first shipped expected file that cites the stand-in.
TARGET=""
for f in "$SCRIPT_DIR"/fixtures/*.expected.json; do
    if [ "$(jq '(.disproving // []) | length' "$f" 2>/dev/null)" -gt 0 ] 2>/dev/null; then
        TARGET=$(basename "$f")
        break
    fi
done
if [ -z "$TARGET" ]; then
    echo "FAIL: no shipped expected file carries a disproving citation; the citation cases cannot run" >&2
    echo "check-fixtures-selftest: FAILED" >&2
    exit 1
fi

# 3) An expected file that does not parse.
reset_copy
printf '{ "expected_verdict": "revise",\n' > "$COPY/fixtures/01-branded-raw-literals.expected.json"
expect_rc 1 "an expected file that does not parse reds" "$COPY"
expect_report_contains "01-branded-raw-literals.expected.json" "the parse failure names the file"

# 4) A cited line past the end of its file.
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0].line = 9999'
expect_rc 1 "a cited line past the end of its file reds" "$COPY"
expect_report_contains ":9999" "the missing-line report names the citation"

# 5) A cited file that does not exist in the stand-in.
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0].path = "fixtures/app/packages/acme-ui/src/components/NoSuchThing.tsx"'
expect_rc 1 "a cited file that does not exist reds" "$COPY"
expect_report_contains "NoSuchThing.tsx" "the missing-file report names the path"

# 6) A path outside the stand-in, even though the file and the line exist.
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0] = {"path": "fixtures/design-tokens/acme-ui-catalog.md", "line": 3}'
expect_rc 1 "a citation outside the acme-ui stand-in reds" "$COPY"
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0].path = "fixtures/app/packages/acme-ui/../../../design-tokens/acme-ui-catalog.md"'
expect_rc 1 "a citation that climbs out of the stand-in with .. reds" "$COPY"

# 7) A line that is not a positive integer.
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0].line = 0'
expect_rc 1 "line 0 reds" "$COPY"
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving[0].line = "12"'
expect_rc 1 "a line given as a string reds" "$COPY"

# 8) An empty citation list.
reset_copy
rewrite "$COPY/fixtures/$TARGET" '.disproving = []'
expect_rc 1 "an empty disproving list reds" "$COPY"

# 9) An empty fixture set refuses rather than passing vacuously.
mkdir -p "$TMP/empty/fixtures"
expect_rc 2 "an empty fixture set refuses" "$TMP/empty"

if [ "$fail" -ne 0 ]; then
    echo "check-fixtures-selftest: FAILED" >&2
    exit 1
fi
echo "check-fixtures-selftest: OK"
exit 0
