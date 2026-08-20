#!/usr/bin/env bash
# checked-call.sh — the three-outcome checked-call idiom, SOURCED (never executed).
#
# WHY THIS EXISTS. `producer | grep -q P` has two outcomes where the world has three. If the
# producer dies, `grep` sees an empty stream and reports no match; under `pipefail` the dead
# producer also makes the whole pipeline non-zero, which reads as "no match" again. Either way
# the caller learns "no" — and "no" is not what happened. The measured cost: a failed
# `claude mcp list` misdetects a consumer's tracker during onboarding, silently, with the
# `2>/dev/null` discarding the one clue.
#
# The contract is the RETURN CODE VOCABULARY, and it is shared beyond this function:
# `lean-gate.sh`'s check_pause_and_ask uses the same numbers for the capture-shaped version of
# the same defect: a capture whose failure arm returned 0, where 0 meant "clear". One rule
# covers both — **2 means you may not treat this as a negative.**
#
# SOURCE it; there is nothing to run:
#   . "$SCRIPT_DIR/checked-call.sh"
#
# LOCKSTEP. `plugins/second-shift/skills/onboard/tools/detect.sh` needs the same function and
# lives in a DIFFERENT PLUGIN, where a sibling `source` would be a cross-plugin path resolved by
# hop count — the trap #469 was filed for. So it carries a byte-identical inline copy, held by the
# `checked-call` LOCKSTEP markers on both sides. `verbatim` covers the WHOLE block, comments
# included: the comments are what tell the next reader that rc 2 means UNKNOWN and must not be
# folded into a caller's `else`. A copy that kept the code and dropped that paragraph would be
# the fail-open this idiom exists to remove, reintroduced one call site at a time.
#
# bash-3.2-safe: indexed arrays only, no `declare -A`, no `${arr[@]}` expansion while empty.

# LOCKSTEP-BEGIN checked-call
# checked_match — run a producer and match its stdout, with THREE outcomes.
#
#   checked_match <grep-arg>... -- <producer> [arg]...
#
#   0  the producer succeeded and its output MATCHED
#   1  the producer succeeded and its output did NOT match — a genuine negative
#   2  the producer FAILED — the answer is UNKNOWN, and the caller must say so
#   3  usage error (falls into a caller's default arm, which is the safe one)
#
# The grep args are passed through verbatim and MUST carry the pattern under `-e`. That is not
# ceremony: `--` is this function's own separator, so the option-terminator form callers would
# otherwise reach for is unavailable, and `-e` removes the leading-hyphen ambiguity entirely.
#
# The producer's stderr is discarded, deliberately: an error message that reached the matcher
# could MATCH, turning a dead call into a false positive — the same defect pointed the other way.
# Its exit status is the diagnostic instead, published as CHECKED_MATCH_RC for the caller's
# message. Only the producer's own exit status decides outcome 2 — with one benign overlap: a
# `grep` that cannot run its own pattern also exits 2, which lands the caller in the same
# "unknown" arm. That is the conservative direction, and the alternative (a malformed pattern
# read as a genuine negative) is the defect this function exists to remove.
# shellcheck disable=SC2034  # read by CALLERS, for the message an unknown outcome owes.
CHECKED_MATCH_RC=0
checked_match() {
  local out rc gn=0
  local gopts=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    gopts[gn]="$1"; gn=$((gn + 1)); shift
  done
  [ "$#" -gt 0 ] || { echo "checked_match: missing '--' between the grep args and the producer" >&2; return 3; }
  shift
  [ "$gn" -gt 0 ] || { echo "checked_match: no grep args given (the pattern goes under -e)" >&2; return 3; }
  [ "$#" -gt 0 ] || { echo "checked_match: no producer command given" >&2; return 3; }

  out="$("$@" 2>/dev/null)"; rc=$?
  CHECKED_MATCH_RC=$rc
  [ "$rc" -eq 0 ] || return 2

  grep -q "${gopts[@]}" <<<"$out"
}
# LOCKSTEP-END checked-call
