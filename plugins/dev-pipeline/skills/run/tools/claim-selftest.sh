#!/usr/bin/env bash
#
# Self-test for the Stage 1.A claim swap helper (tools/claim-issue.sh).
#
# A self-test in the style of slice-derivation-selftest.sh, located under tools/
# and wired into pipeline-doctor.sh (block 5e). Pure-local: no Claude CLI, no
# network, no real `gh` — it injects a MOCK bot wrapper via the helper's `GH_BOT`
# env seam and drives the add-labels response so BOTH the successful-add (DELETE
# runs) and failed-add (DELETE skipped, ready-for-dev intact) paths are exercised.
#
# WHY this exists (#183): #170 hardened the claim swap against a silently-failed
# `in-progress` add followed by a successful `ready-for-dev` remove, but the swap
# was model-executed prose with no failure-injection seam, so #170's AC#3 ("exercise
# the failed-add path if feasible") had no automated test. Extracting the swap into
# claim-issue.sh created the seam; this is that test.
#
# FIDELITY: the mock is driven by the add-labels RESPONSE BODY content (the
# jq-extracted label array the helper branches on) AND its exit code — not just a
# clean "array missing the label" case. The 422/jq-error-shaped body (the exact
# failure #170 hardened against) and a pure non-zero POST exit are both covered.
#
# DRIFT MODEL: the parity tail asserts claim-issue.sh still carries the load-bearing
# tokens AND that SKILL.md / 1-intake.md reference the helper rather than re-inlining
# the snippet (the #170/#183 no-duplication goal). Same technique as
# slice-derivation-selftest's drift-check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/claim-issue.sh"
SKILL="$SCRIPT_DIR/../SKILL.md"
INTAKE="$SCRIPT_DIR/../stages/1-intake.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Mock bot wrapper. Emulates `"$GH_BOT" api ...` for the two calls claim-issue.sh
# makes, distinguishing them by scanning the argument string:
#   POST   .../labels                 -> prints $MOCK_ADD_STDOUT (emulates the
#                                        `--jq '[.[].name]'` output), exits $MOCK_ADD_RC
#   DELETE .../labels/ready-for-dev    -> logs its args to $CALL_LOG, touches
#                                        $DELETE_SENTINEL, exits 0
# MOCK_ADD_STDOUT / MOCK_ADD_RC / CALL_LOG / DELETE_SENTINEL arrive via the
# environment the helper inherits from each run_claim invocation.
# ---------------------------------------------------------------------------
MOCK="$TMP/gh-mock.sh"
cat > "$MOCK" <<'MOCKEOF'
#!/usr/bin/env bash
set -uo pipefail
args="$*"
case "$args" in
  *"-X DELETE"*"labels/ready-for-dev"*)
    printf 'DELETE %s\n' "$args" >> "$CALL_LOG"
    : > "$DELETE_SENTINEL"
    exit 0
    ;;
  *"-X POST"*"/labels"*)
    printf 'POST %s\n' "$args" >> "$CALL_LOG"
    printf '%s\n' "$MOCK_ADD_STDOUT"
    exit "$MOCK_ADD_RC"
    ;;
  *)
    echo "[gh-mock] unexpected call: $args" >&2
    exit 99
    ;;
esac
MOCKEOF
chmod +x "$MOCK"

# Drive claim-issue.sh once with a mocked add response. Echoes the helper's exit
# code; side effects (whether DELETE ran) are read from $DELETE_SENTINEL afterward.
#   $1 add stdout (the label array the POST yields, or an error-shaped body)
#   $2 add exit code
#   $3 issue arg passed to the helper (default 183; "" exercises the usage path)
DELETE_SENTINEL="$TMP/delete_called"
CALL_LOG="$TMP/calls.log"
run_claim() {
  local add_stdout="$1" add_rc="$2" issue_arg="${3-183}"
  rm -f "$DELETE_SENTINEL"
  : > "$CALL_LOG"
  # shellcheck disable=SC2086 # issue_arg deliberately unquoted: empty for the no-arg case
  GH_BOT="$MOCK" \
  MOCK_ADD_STDOUT="$add_stdout" \
  MOCK_ADD_RC="$add_rc" \
  CALL_LOG="$CALL_LOG" \
  DELETE_SENTINEL="$DELETE_SENTINEL" \
    bash "$HELPER" $issue_arg >/dev/null 2>&1
  echo "$?"
}

deleted()     { [[ -f "$DELETE_SENTINEL" ]]; }
delete_target_ok() { grep -q 'DELETE .*labels/ready-for-dev' "$CALL_LOG"; }

echo "=== claim-issue.sh: successful-add path (DELETE runs) ==="

# (a) Happy path: add response contains in-progress -> DELETE runs, exit 0.
rc=$(run_claim '["ready-for-dev","in-progress"]' 0)
if [[ "$rc" == "0" ]] && deleted; then ok "happy: add applied -> exit 0, DELETE ran"; else bad "happy: rc=$rc deleted=$(deleted && echo y || echo n)"; fi
# And the DELETE hit the correct label, not just "a DELETE happened".
if delete_target_ok; then ok "happy: DELETE targeted labels/ready-for-dev"; else bad "happy: DELETE target wrong/absent ($(cat "$CALL_LOG"))"; fi

echo "=== claim-issue.sh: failed-add path (DELETE skipped, ready-for-dev intact) ==="

# (b) Add response is a non-empty array WITHOUT in-progress (faithful: the branch
#     condition is body content, not HTTP status) -> abort, no DELETE.
rc=$(run_claim '["ready-for-dev"]' 0)
if [[ "$rc" == "1" ]] && ! deleted; then ok "failed-add (label missing, non-empty array) -> exit 1, no DELETE"; else bad "failed-add (missing): rc=$rc deleted=$(deleted && echo y || echo n)"; fi

# (c) Add response is an empty array -> abort, no DELETE.
rc=$(run_claim '[]' 0)
if [[ "$rc" == "1" ]] && ! deleted; then ok "failed-add (empty array) -> exit 1, no DELETE"; else bad "failed-add (empty): rc=$rc deleted=$(deleted && echo y || echo n)"; fi

# (d) 422-shaped failure: jq runs against a non-array error object, emits a jq error
#     (here on stdout to model a captured non-array body) AND a non-zero exit — the
#     exact silent-failure shape #170 hardened against. Must abort, no DELETE.
rc=$(run_claim 'jq: error (at <stdin>:0): Cannot iterate over object' 5)
if [[ "$rc" == "1" ]] && ! deleted; then ok "failed-add (422/jq-error body, rc=5) -> exit 1, no DELETE"; else bad "failed-add (422/jq-error): rc=$rc deleted=$(deleted && echo y || echo n)"; fi

# (e) Pure POST failure: empty stdout AND non-zero exit (proves the confirm/abort
#     branch still fires under `set -o pipefail` rather than the script dying).
rc=$(run_claim '' 1)
if [[ "$rc" == "1" ]] && ! deleted; then ok "failed-add (empty body + rc=1) -> exit 1, no DELETE"; else bad "failed-add (empty+rc1): rc=$rc deleted=$(deleted && echo y || echo n)"; fi

echo "=== claim-issue.sh: usage contract ==="

# (f) No issue number -> usage error, exit 2, no POST/DELETE.
rc=$(run_claim '["ready-for-dev","in-progress"]' 0 "")
if [[ "$rc" == "2" ]] && ! deleted; then ok "no issue arg -> exit 2 (usage), no calls"; else bad "usage: rc=$rc deleted=$(deleted && echo y || echo n)"; fi

# ---------------------------------------------------------------------------
# Drift parity: assert the helper still carries the load-bearing tokens this
# self-test models, AND that the prose call-sites reference the helper rather than
# re-inlining the snippet (the #170/#183 no-duplication goal).
# ---------------------------------------------------------------------------
echo "=== drift parity vs helper + prose call-sites ==="
parity()     { # label, pattern, file
  if grep -Eq -- "$2" "$3"; then ok "${3##*/} contains: $1"; else bad "${3##*/} MISSING token ($1) — drifted from this self-test: /$2/"; fi
}
anti_parity() { # label, pattern, file (must NOT be present)
  if grep -Eq -- "$2" "$3"; then bad "${3##*/} STILL inlines ($1) — duplication the helper was meant to remove: /$2/"; else ok "${3##*/} no longer inlines: $1"; fi
}

if [[ ! -f "$HELPER" ]]; then
  bad "claim-issue.sh not found at $HELPER"
else
  # shellcheck disable=SC2016 # literal $ADDED is the grep pattern, not an expansion
  parity "claimed-label add confirm branch" '\[\[ "\$ADDED" =='                  "$HELPER"
  # shellcheck disable=SC2016 # literal $QUEUE_LABEL is the grep pattern, not an expansion
  parity "queue-label DELETE (config-driven)" 'labels/\$QUEUE_LABEL'             "$HELPER"
  parity "config label args (#11)"          '\-\-queue) *QUEUE_LABEL'            "$HELPER"
  parity "failed-add abort (exit 1)"      'exit 1'                               "$HELPER"
  parity "injectable GH_BOT env seam"     'GH_BOT:-'                             "$HELPER"
  parity "bot wrapper under \$HOME/.config/<repo>/" '\.config/.*gh-as-bot\.sh'   "$HELPER"
fi

if [[ ! -f "$SKILL" ]]; then bad "SKILL.md not found at $SKILL"; else
  parity      "claim-issue.sh invocation"     'claim-issue\.sh'   "$SKILL"
  anti_parity "old inline add-labels pipeline" 'ADDED=\$\(echo'   "$SKILL"
fi
if [[ ! -f "$INTAKE" ]]; then bad "1-intake.md not found at $INTAKE"; else
  parity "claim-issue.sh invocation" 'claim-issue\.sh' "$INTAKE"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
