#!/usr/bin/env bash
#
# Self-test for the Stage 1.A claim swap helper (tools/claim-issue.sh).
#
# A self-test in the style of the other tools/ harnesses, located under tools/
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
# the snippet (the #170/#183 no-duplication goal).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/claim-issue.sh"

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
#   DELETE .../labels/$MOCK_QUEUE_LABEL -> logs its args to $CALL_LOG, touches
#                                        $DELETE_SENTINEL, exits 0 (label defaults to
#                                        ready-for-dev; case (g) drives a custom one)
# MOCK_ADD_STDOUT / MOCK_ADD_RC / CALL_LOG / DELETE_SENTINEL arrive via the
# environment the helper inherits from each run_claim invocation.
# ---------------------------------------------------------------------------
MOCK="$TMP/gh-mock.sh"
cat > "$MOCK" <<'MOCKEOF'
#!/usr/bin/env bash
set -uo pipefail
args="$*"
case "$args" in
  *"-X DELETE"*"labels/${MOCK_QUEUE_LABEL:-ready-for-dev}"*)
    printf 'DELETE %s\n' "$args" >> "$CALL_LOG"
    : > "$DELETE_SENTINEL"
    exit 0
    ;;
  *"-X POST"*"/labels"*)
    # The label name travels on STDIN (--input -), never in argv — record both so a
    # hardcoded claimed label is catchable, not just a hardcoded queue label.
    post_body="$(cat 2>/dev/null || true)"
    printf 'POST %s BODY=%s\n' "$args" "$post_body" >> "$CALL_LOG"
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
  # Extra args (case (g)'s --queue/--claimed) are optional; callers passing only
  # two or three args must be unaffected.
  if [[ $# -gt 3 ]]; then shift 3; else shift $#; fi
  rm -f "$DELETE_SENTINEL"
  : > "$CALL_LOG"
  # shellcheck disable=SC2086 # issue_arg deliberately unquoted: empty for the no-arg case
  GH_BOT="$MOCK" \
  MOCK_ADD_STDOUT="$add_stdout" \
  MOCK_ADD_RC="$add_rc" \
  MOCK_QUEUE_LABEL="${MOCK_QUEUE_LABEL:-ready-for-dev}" \
  CALL_LOG="$CALL_LOG" \
  DELETE_SENTINEL="$DELETE_SENTINEL" \
    bash "$HELPER" $issue_arg "$@" >/dev/null 2>&1
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

# (g) CONFIG-DRIVEN LABELS (#11) — the behavioral case the token pin could not give us.
# Every case above runs on the DEFAULT labels, so a mutant that hardcodes the DELETE URL
# to `labels/ready-for-dev` (a plausible default-inlining refactor, or a partial #11
# revert) emits byte-identical calls and passes all of them. Production calls this helper
# with CONFIG-RESOLVED labels (stages/1-intake.md), so on a consumer with a custom queue
# label that mutant 404s the DELETE, the script swallows it (set -uo pipefail, no -e) and
# exits 0 — leaving the issue claimed-but-still-queued, the silent label-corruption class
# #170/#183 exist to prevent. Drive non-default labels end to end and assert BOTH calls
# target them.
rc=$(MOCK_QUEUE_LABEL="triage-ready" run_claim '["triage-ready","wip"]' 0 183 --queue triage-ready --claimed wip)
if [[ "$rc" == "0" ]] && deleted; then
  ok "custom labels: --queue/--claimed honored end to end (exit 0, DELETE ran)"
else
  bad "custom labels: rc=$rc deleted=$(deleted && echo y || echo n)"
fi
if grep -q 'DELETE .*labels/triage-ready' "$CALL_LOG"; then
  ok "custom labels: DELETE targeted labels/triage-ready (not the hardcoded default)"
else
  bad "custom labels: DELETE did not target labels/triage-ready ($(cat "$CALL_LOG"))"
fi
if grep -q 'BODY=.*wip' "$CALL_LOG"; then
  ok "custom labels: POST added the configured claimed label (wip)"
else
  bad "custom labels: POST did not add 'wip' ($(cat "$CALL_LOG"))"
fi

# ---------------------------------------------------------------------------
# Drift parity: assert the helper still carries the load-bearing tokens this
# self-test models, AND that the prose call-sites reference the helper rather than
# re-inlining the snippet (the #170/#183 no-duplication goal).
# ---------------------------------------------------------------------------
echo "=== drift parity vs helper + prose call-sites ==="
parity()     { # label, pattern, file
  if grep -Eq -- "$2" "$3"; then ok "${3##*/} contains: $1"; else bad "${3##*/} MISSING token ($1) — drifted from this self-test: /$2/"; fi
}

if [[ ! -f "$HELPER" ]]; then
  bad "claim-issue.sh not found at $HELPER"
else
  # Only the pin the behavioral half genuinely cannot reach is kept (#214). The confirm
  # branch, the exit-1 abort, the DELETE target and the GH_BOT seam are all proven by the
  # cases above — the seam by the mock working at all, and case (g) now covers the
  # config-driven label path that used to rest on a token pin. The three markdown greps
  # over SKILL.md / 1-intake.md were the banned prose-presence class: they assert only
  # that prose contains words, and the anti-inline pattern could not even match a
  # re-inline of the helper's current form.
  parity "bot wrapper under \$HOME/.config/<repo>/" '\.config/.*gh-as-bot\.sh'   "$HELPER"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
