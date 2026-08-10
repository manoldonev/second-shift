#!/usr/bin/env bash
# Selftest for check-eval-model-neutrality.sh — the guard that keeps vendor model identity out
# of the runnable eval surface under plugins/*/evals/**.
#
# What it has to prove, beyond "it runs":
#   - each of the FOUR violation shapes reds, and names the offending file;
#   - the record-file exemption holds for every name on the list, tested with the SAME literal
#     that reds elsewhere — otherwise a green here would only mean the fixture was clean;
#   - the false-positive floor: prose that names the aliases in English, and a note string that
#     merely contains one, both stay green. A guard that flags those gets disabled by whoever
#     hits it first;
#   - an empty scan set is rc=2, distinct from a violation's rc=1 — the vacuity arm is the one
#     that stops a relocated eval surface from reading as clean;
#   - the real tree passes.
#
# CI runs this via the *-selftest.sh glob on both lanes, incl. macOS bash 3.2.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-eval-model-neutrality.sh"
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SURFACE="$TMP/plugins/demo-toolkit/evals/demo-eval"
mkdir -p "$SURFACE"

# The literal that must red in machinery and stay silent in a record file. One string, used in
# both roles, so the exemption cases cannot pass by being vacuously clean.
PIN='claude-opus-4-7'

reset_fixture() {
    rm -rf "${SURFACE:?}"/*
    cat > "$SURFACE/run.sh" <<'EOF'
#!/usr/bin/env bash
: "${REVIEWER_MODEL:?REVIEWER_MODEL is required}"
python3 run-eval.py --reviewer-model "$REVIEWER_MODEL"
EOF
    cat > "$SURFACE/agents-template.json" <<'EOF'
{ "mock": { "model": "{{mock_model}}", "effort": "low" } }
EOF
}

# One invocation per assertion, output captured so the report can be inspected without a second
# run. Deliberately NOT `check | grep -q`: `grep -q` exits on first match, the check dies of
# SIGPIPE, and `pipefail` turns a successful match into a non-zero pipeline.
LAST_OUT=""
check_run() {
    LAST_OUT=$(bash "$CHECK" "$1" 2>&1)
    return $?
}

expect_rc() {
    local want="$1" label="$2" root="${3:-$TMP}" got
    check_run "$root"
    got=$?
    if [ "$got" = "$want" ]; then
        echo "PASS: $label (rc=$got)"
    else
        echo "FAIL: $label — expected rc=$want, got rc=$got" >&2
        echo "$LAST_OUT" >&2
        fail=1
    fi
}

# Assert the LAST captured report contains a substring (no pipe, no SIGPIPE hazard).
expect_report_contains() {
    case "$LAST_OUT" in
        *"$1"*) echo "PASS: $2" ;;
        *) echo "FAIL: $2 — report did not mention '$1'" >&2; echo "$LAST_OUT" >&2; fail=1 ;;
    esac
}

# 1) Green on the real tree. This is what makes the guard an assertion about THIS repo and not
#    only about its fixtures.
if bash "$CHECK" "$REPO_ROOT" >/dev/null 2>&1; then
    echo "PASS: real tree carries no vendor model identity in the runnable eval surface"
else
    echo "FAIL: real tree should pass the eval-model-neutrality check" >&2
    bash "$CHECK" "$REPO_ROOT" >&2 || true
    fail=1
fi

# 2) Green on a clean fixture.
reset_fixture
expect_rc 0 "clean fixture passes"

# 3) Red on a versioned vendor pin, and the message names the file.
reset_fixture
echo "MODEL_DEFAULT=\"$PIN\"" >> "$SURFACE/run.sh"
expect_rc 1 "versioned vendor pin reds"
expect_report_contains "demo-eval/run.sh" "the violation report names the offending file"
expect_report_contains "$PIN" "the violation report quotes the offending literal"

# 4) Red on a floating alias as a --…model flag value.
reset_fixture
echo '  --judge-model sonnet \' >> "$SURFACE/run.sh"
expect_rc 1 "floating alias in a --model flag position reds"

# 5) Red on a floating alias as a JSON "model" value — the shape the agents templates carry.
reset_fixture
cat > "$SURFACE/agents-template.json" <<'EOF'
{ "mock": { "model": "haiku", "effort": "low" } }
EOF
expect_rc 1 "floating alias in a JSON model position reds"

# 6) Red on a floating alias in a *MODEL= assignment.
reset_fixture
echo 'REVIEWER_MODEL=opus ./run.sh "a-run"' > "$SURFACE/README.md"
expect_rc 1 "floating alias in a *MODEL= assignment reds"

# 7) The false-positive floor. Prose naming the aliases in English, and a note string that
#    merely contains one, are NOT model positions and must stay green.
reset_fixture
cat > "$SURFACE/README.md" <<'EOF'
To prove parity before downgrading a sub-agent from Opus to Sonnet, run the A arm and the
B arm with distinguishable notes:

    REVIEWER_MODEL=<pin-A> ./run.sh "sonnet-ab"
    REVIEWER_MODEL=<pin-B> ./run.sh "haiku-probe"

then compare the two model=... rows in changelog.md.
EOF
expect_rc 0 "prose naming the aliases, and note strings containing them, stay green"

# 8) The record-file exemption, one case per name, each carrying the literal that reds in (3).
for record in changelog.md FINAL-REPORT.md CLOSEOUT-BASELINE.md BASELINE.md KNOWN_ISSUES.md FIXTURE-AUDIT.md; do
    reset_fixture
    echo "2026-01-01 | model=$PIN | score=91.0%" > "$SURFACE/$record"
    expect_rc 0 "record file $record keeps its model attribution"
done

# 9) The runner's own output file is excluded too.
reset_fixture
echo "{\"reviewer_model\": \"$PIN\"}" > "$SURFACE/results-20260101T000000Z.json"
expect_rc 0 "results-*.json runner output is excluded"

# 10) A record NAME outside the eval surface earns no exemption — the exclusion is scoped to
#     what the scan reaches, and the scan reaches only */evals/*. Placing machinery one level
#     up must not be scanned at all (it is not the eval surface), so the fixture stays green
#     while the pin sits outside.
reset_fixture
echo "MODEL=\"$PIN\"" > "$TMP/plugins/demo-toolkit/not-an-eval.sh"
expect_rc 0 "files outside */evals/* are not this guard's surface"

# 11) Compiled bytecode is pruned rather than scanned as text.
reset_fixture
mkdir -p "$SURFACE/__pycache__"
echo "MODEL = \"$PIN\"" > "$SURFACE/__pycache__/runner.cpython-314.pyc"
expect_rc 0 "__pycache__ is pruned"

# 12) An empty scan set is rc=2 — NOT rc=0, and distinguishable from a violation's rc=1.
EMPTY="$TMP/empty-root"
mkdir -p "$EMPTY/plugins/demo-toolkit"
expect_rc 2 "an empty scan set refuses instead of reporting a vacuous pass" "$EMPTY"
expect_report_contains "scanned 0 files" "the empty-scan refusal says why"

# 13) A root that does not exist refuses too.
expect_rc 2 "a nonexistent root refuses" "$TMP/no-such-dir"

if [ "$fail" -ne 0 ]; then
    echo "check-eval-model-neutrality-selftest: FAILED" >&2
    exit 1
fi
echo "check-eval-model-neutrality-selftest: OK"
exit 0
