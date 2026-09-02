#!/usr/bin/env bash
# classify-capture-selftest.sh — behavioral suite for tools/classify-capture.sh (#779).
#
# EVERY CASE RUNS AGAINST A SYNTHETIC CAPTURE FILE, never a real stream-json log — the tool's
# whole job is a scan for `type: "result"` events plus a two-field read of the governing one, and
# a fixture lets one case state exactly one property of that.
#
# THE PAIR THAT MATTERS is (d) and (f): a capture with no `result` event anywhere — including one
# that never started emitting JSON at all — must read as TRUNCATED, not as a clean negative. That
# is the exact failure #779 exists to stop: a reaped BUILD session's capture read at face value.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/classify-capture.sh"

[[ -f "$TOOL" ]] || { echo "[classify-capture-selftest] FATAL: $TOOL is missing"; exit 99; }

FAIL=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/classify-capture-selftest.XXXXXX")" || exit 99
trap 'rm -rf "$TMP"' EXIT INT TERM

run() { bash "$TOOL" "$@" > "$TMP/out" 2>&1; echo $?; }
dump() { sed 's/^/    | /' "$TMP/out" >&2; }

SYS='{"type":"system","subtype":"init"}'
ASSISTANT='{"type":"assistant","message":{"role":"assistant"}}'

# ---------------------------------------------------------------------------------------
# (a) AC-2 rc=0 — a complete, successful run.
# ---------------------------------------------------------------------------------------
printf '%s\n%s\n{"type":"result","subtype":"success","is_error":false}\n' "$SYS" "$ASSISTANT" \
  > "$TMP/success.jsonl"
RC="$(run "$TMP/success.jsonl")"
if [[ "$RC" -eq 0 ]] && grep -qF 'COMPLETE' "$TMP/out" && grep -qF 'subtype=success' "$TMP/out"; then
  ok "(a) AC-2: subtype=success, is_error=false exits 0 and names COMPLETE"
else
  bad "(a) AC-2: expected rc=0 naming COMPLETE, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (b) AC-2 rc=1 via is_error:true — a run that completed but failed.
# ---------------------------------------------------------------------------------------
printf '%s\n{"type":"result","subtype":"success","is_error":true}\n' "$SYS" > "$TMP/is-error.jsonl"
RC="$(run "$TMP/is-error.jsonl")"
if [[ "$RC" -eq 1 ]] && grep -qF 'FAILED' "$TMP/out" && grep -qF 'is_error=true' "$TMP/out"; then
  ok "(b) AC-2: is_error=true exits 1 and names FAILED with the is_error value"
else
  bad "(b) AC-2: expected rc=1 naming FAILED/is_error=true, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (c) AC-2 rc=1 via a non-success subtype — is_error:false does not save it.
# ---------------------------------------------------------------------------------------
printf '{"type":"result","subtype":"error_max_turns","is_error":false}\n' > "$TMP/subtype.jsonl"
RC="$(run "$TMP/subtype.jsonl")"
if [[ "$RC" -eq 1 ]] && grep -qF 'subtype=error_max_turns' "$TMP/out"; then
  ok "(c) AC-2: a non-success subtype exits 1 and names the subtype, even with is_error=false"
else
  bad "(c) AC-2: expected rc=1 naming the subtype, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (d) AC-2 rc=2 — a killed run: system/assistant events, no result event at all. This is the
# #777 shape this tool exists for.
# ---------------------------------------------------------------------------------------
printf '%s\n%s\n%s\n' "$SYS" "$ASSISTANT" "$ASSISTANT" > "$TMP/truncated.jsonl"
RC="$(run "$TMP/truncated.jsonl")"
if [[ "$RC" -eq 2 ]] && grep -qF 'TRUNCATED' "$TMP/out"; then
  ok "(d) AC-2: a capture with events but no result line exits 2 and names TRUNCATED"
else
  bad "(d) AC-2: expected rc=2 naming TRUNCATED, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (e) AC-2 rc=2 — an empty file is truncated too, not a usage error: the predicate is "carries
# no result event", and an empty file satisfies that exactly.
# ---------------------------------------------------------------------------------------
: > "$TMP/empty.jsonl"
RC="$(run "$TMP/empty.jsonl")"
if [[ "$RC" -eq 2 ]] && grep -qF 'TRUNCATED' "$TMP/out"; then
  ok "(e) AC-2: an empty capture exits 2 (truncated), not a usage error"
else
  bad "(e) AC-2: expected rc=2 for an empty file, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (f) AC-3 rc=3 — a missing file cannot be classified.
# ---------------------------------------------------------------------------------------
RC="$(run "$TMP/does-not-exist.jsonl")"
[[ "$RC" -eq 3 ]] \
  && ok "(f) AC-3: a nonexistent capture file exits 3, not 2 — could-not-read stays distinct from truncated" \
  || { bad "(f) AC-3: expected rc=3 for a missing file, got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (g) AC-3 rc=3 — a line that is not valid JSON is a usage error, not silently skipped or
# treated as a non-result line.
# ---------------------------------------------------------------------------------------
printf '%s\nnot json at all\n' "$SYS" > "$TMP/malformed.jsonl"
RC="$(run "$TMP/malformed.jsonl")"
[[ "$RC" -eq 3 ]] \
  && ok "(g) AC-3: a line that fails to parse as JSON exits 3 rather than being ignored" \
  || { bad "(g) AC-3: expected rc=3 for a malformed line, got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (h) AC-3 rc=3 — no argument at all.
# ---------------------------------------------------------------------------------------
RC="$(run)"
[[ "$RC" -eq 3 ]] \
  && ok "(h) AC-3: no argument exits 3" \
  || { bad "(h) AC-3: expected rc=3 with no argument, got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (i) AC-4 — two result events: the LAST governs, and the count is surfaced. An early success
# followed by a later failure must read as FAILED, not success.
# ---------------------------------------------------------------------------------------
printf '{"type":"result","subtype":"success","is_error":false}\n{"type":"result","subtype":"success","is_error":true}\n' \
  > "$TMP/multi.jsonl"
RC="$(run "$TMP/multi.jsonl")"
if [[ "$RC" -eq 1 ]] && grep -qF '2 result events' "$TMP/out" && grep -qF 'is_error=true' "$TMP/out"; then
  ok "(i) AC-4: the later of two result events governs, and the count of 2 is surfaced"
else
  bad "(i) AC-4: expected rc=1 naming '2 result events' and is_error=true, got rc=$RC"; dump
fi

# ---------------------------------------------------------------------------------------
# (j) AC-4 — the reverse order: a later SUCCESS governs over an earlier failure, proving this
# is not just "any failure anywhere wins".
# ---------------------------------------------------------------------------------------
printf '{"type":"result","subtype":"success","is_error":true}\n{"type":"result","subtype":"success","is_error":false}\n' \
  > "$TMP/multi-recovers.jsonl"
RC="$(run "$TMP/multi-recovers.jsonl")"
[[ "$RC" -eq 0 ]] \
  && ok "(j) AC-4: a later successful result governs over an earlier failed one" \
  || { bad "(j) AC-4: expected rc=0 (later result wins), got rc=$RC"; dump; }

# ---------------------------------------------------------------------------------------
# (k) AC-2 — a result event carrying no is_error key at all is not treated as false: an
# unmodelled shape must fail closed toward FAILED, never toward a silent COMPLETE.
# ---------------------------------------------------------------------------------------
printf '{"type":"result","subtype":"success"}\n' > "$TMP/no-is-error.jsonl"
RC="$(run "$TMP/no-is-error.jsonl")"
[[ "$RC" -eq 1 ]] \
  && ok "(k) AC-2: a result event with no is_error key fails closed to rc=1, not a silent 0" \
  || { bad "(k) AC-2: expected rc=1 for a missing is_error key, got rc=$RC"; dump; }

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "[classify-capture-selftest] all checks passed"
else
  echo "[classify-capture-selftest] $FAIL check(s) failed" >&2
fi
exit "$FAIL"
