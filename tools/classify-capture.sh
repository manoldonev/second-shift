#!/usr/bin/env bash
# classify-capture.sh — tells a truncated `claude -p --output-format stream-json` capture apart
# from one that ran to completion (#779).
#
# WHY THIS EXISTS. A BUILD session's detached probe can be reaped at the spawn boundary mid-run.
# What it leaves behind is a capture with no findings in it — and at face value that is
# indistinguishable from a capture that ran to completion and genuinely found nothing. Measured
# 2026-09-02 on #777: a 2.3 MB, 831-line capture, killed roughly 7 minutes into a comparable
# 20-30 minute run, carries no `result` event anywhere. Read as a clean negative, that is a false
# measurement entering a frozen-adjacent registration document (D-1).
#
# THE PREDICATE (D-3). A capture is complete iff it carries a `type: "result"` event. A clean run
# terminates with `{"type":"result","subtype":"success","is_error":false,...}`; a reaped one does
# not, because the child process was killed rather than allowed to finish its turn.
#
# THREE VERDICTS, NOT TWO (D-4). Truncated and completed-but-failed carry different remedies —
# re-run versus investigate — so collapsing them recreates the ambiguity this exists to remove.
#
# A FOURTH, DISTINCT FROM ALL THREE: a checker that cannot read its input must not report a
# verdict about that input. A missing file, an unreadable one, or a line that is not valid JSON
# is a usage error, never silently folded into "truncated" — truncation is a claim about what the
# capture DOES contain, not about whether this tool could open it.
#
# THE LAST `result` EVENT GOVERNS (D-8). A capture can carry more than one — a concatenated run,
# or a caller appending to an existing file. The count is surfaced when it exceeds one so an
# operator can tell that happened; OR-1's stated default, cheap to reverse because nothing
# committed depends on it yet.
#
# Usage:
#   classify-capture.sh <capture-file>
#
# EXIT: 0 complete, subtype "success", is_error false.
#       1 complete, but is_error true or a subtype other than "success".
#       2 truncated — no `type: "result"` event anywhere, including an empty file.
#       3 usage error — missing argument, unreadable file, or a line that is not valid JSON.
set -uo pipefail

die() { echo "[classify-capture] $1" >&2; exit 3; }

[[ $# -eq 1 ]] || die "usage: classify-capture.sh <capture-file>"
CAPTURE="$1"
[[ -f "$CAPTURE" && -r "$CAPTURE" ]] || die "capture file is absent or unreadable: $CAPTURE"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/classify-capture.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

: > "$TMP/results"
LN=0
while IFS= read -r line || [[ -n "$line" ]]; do
  LN=$((LN + 1))
  [[ -n "$line" ]] || continue
  jq -e . >/dev/null 2>&1 <<<"$line" || die "line $LN is not valid JSON: $CAPTURE"
  TYPE="$(jq -r '.type // empty' <<<"$line")"
  [[ "$TYPE" == "result" ]] && printf '%s\n' "$line" >> "$TMP/results"
done < "$CAPTURE"

COUNT="$(wc -l < "$TMP/results" | tr -d ' ')"

if [[ "$COUNT" -eq 0 ]]; then
  echo "[classify-capture] TRUNCATED — $CAPTURE stops without a type:\"result\" event; this is an incomplete run, not a negative result."
  exit 2
fi

if [[ "$COUNT" -gt 1 ]]; then
  echo "[classify-capture] note: $COUNT result events found in $CAPTURE; the last one governs the verdict."
fi

LAST="$(tail -n 1 "$TMP/results")"
SUBTYPE="$(jq -r '.subtype // "null"' <<<"$LAST")"
IS_ERROR="$(jq -r 'if has("is_error") then (.is_error | tostring) else "null" end' <<<"$LAST")"

if [[ "$SUBTYPE" == "success" && "$IS_ERROR" == "false" ]]; then
  echo "[classify-capture] COMPLETE — $CAPTURE ran to completion successfully (subtype=success, is_error=false)."
  exit 0
fi

echo "[classify-capture] FAILED — $CAPTURE ran to completion but the run failed (subtype=$SUBTYPE, is_error=$IS_ERROR)."
exit 1
