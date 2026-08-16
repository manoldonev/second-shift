#!/usr/bin/env bash
# predecessor-gate.sh — sequential-ordering backstop for `sub-issues-sequential`
# decompositions. Pure logic: no network, no `gh`, no config reads.
#
# Ordering is normally enforced by keeping blocked successors OUT of the queue —
# `create-sub-tickets` creates sequential sub-issues N>1 without the queue label, and
# the operator labels the successor when merging the predecessor's PR. This tool is
# the backstop for the one case that slips past that: an EARLY-LABELED successor
# arriving via the queue query with its predecessor still open.
#
# The stage doc (stages/1-intake.md) owns every tracker read and composes two calls:
#
#   1. extract        — successor body on stdin; prints the trailer keys it found
#   2. <fetch predecessor state>   (paid ONLY when `extract` printed a predecessor key)
#   3. verdict <state> — proceed / skip-blocked
#
# Splitting it this way keeps network reads in the stage doc and the tool pure logic
# fed via stdin/args, so its selftest and the liveness scenarios run with zero network
# and nothing to mock.
#
# Usage:
#   printf '%s' "$ISSUE_BODY" | predecessor-gate.sh extract
#   KEY_PATTERN='[A-Z]+-[0-9]+' printf '%s' "$BODY" | predecessor-gate.sh extract
#   predecessor-gate.sh verdict closed   # -> exit 0, proceed to claim
#   predecessor-gate.sh verdict open     # -> exit 3, skip without claiming
#
# Modes:
#   extract           Read an issue body on stdin. Print `predecessor=<key>` and/or
#                     `successor=<key>`, one per line; a line is OMITTED when its
#                     trailer is absent. Always exits 0.
#   verdict <state>   The gate semantics, given the predecessor's tracker state.
#
# Env:
#   KEY_PATTERN — anchored regex fragment the trailer's key must match. Default
#                 `[0-9]+` (github issue numbers); a jira consumer passes
#                 `[A-Z]+-[0-9]+`. Mirrors config `tracker.keyPattern`, supplied by
#                 the caller rather than read here (the env-seam convention for a
#                 config value a pure-logic tool must not read). A leading `#` on the
#                 value is optional and stripped.
#
# Trailer form (strict, full-line):  `Predecessor: #263`  /  `Successor: GH-540`
#   - Leading whitespace is tolerated; trailing whitespace and a `\r` (CRLF bodies
#     from the GitHub API) are stripped before matching.
#   - DUPLICATES of one kind: the LAST occurrence wins (git trailer convention).
#   - A line that starts like a trailer but whose value does not match KEY_PATTERN
#     prints NO line for that kind, emits a warning on stderr, and still exits 0.
#     The gate fails OPEN here by design: it is a backstop, not the primary
#     enforcement, so a malformed trailer must be visible in the run log rather
#     than abort a run. See the exit table.
#   - KNOWN LIMITATION: a trailer quoted inside a fenced code block IS extracted —
#     there is no fence-state tracking. The strict full-line anchor already excludes
#     the inline-backticked prose mentions that actually occur in these bodies
#     (`- \`Predecessor:\`/\`Successor:\` trailers rendered per …` does not match).
#
# Exit:
#   0  extract: always. verdict: predecessor `closed` — proceed to claim.
#   2  usage error (unknown mode, missing/invalid verdict state).
#   3  verdict: predecessor `open` — skip-blocked, do NOT claim.
#
# macOS ships bash 3.2 as /bin/bash; this script stays 3.2-compatible (the selftest
# drift-check runs there).

set -uo pipefail

MODE="${1:-}"
PATTERN="${KEY_PATTERN:-[0-9]+}"

usage() {
  echo "[predecessor-gate] usage: predecessor-gate.sh extract   (issue body on stdin)" >&2
  echo "[predecessor-gate]        predecessor-gate.sh verdict <open|closed>" >&2
}

# extract_trailers — scan stdin for the two trailer kinds, last-match-wins.
extract_trailers() {
  local pred="" succ=""
  local line
  # Anchored full-line matchers, built once from $PATTERN.
  local pred_re="^[[:space:]]*Predecessor:[[:space:]]*#?(${PATTERN})[[:space:]]*$"
  local succ_re="^[[:space:]]*Successor:[[:space:]]*#?(${PATTERN})[[:space:]]*$"
  # Prefix matchers: a line that LOOKS like a trailer of this kind. Used only to
  # distinguish "absent" from "present but unparseable".
  local pred_pfx="^[[:space:]]*Predecessor:"
  local succ_pfx="^[[:space:]]*Successor:"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # GitHub API bodies are CRLF; strip the CR so the `$` anchor can match.
    line="${line%$'\r'}"
    if [[ "$line" =~ $pred_re ]]; then
      pred="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ $pred_pfx ]]; then
      echo "[predecessor-gate] warning: unparseable Predecessor trailer: $line" >&2
    fi
    if [[ "$line" =~ $succ_re ]]; then
      succ="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ $succ_pfx ]]; then
      echo "[predecessor-gate] warning: unparseable Successor trailer: $line" >&2
    fi
  done

  [[ -n "$pred" ]] && echo "predecessor=$pred"
  [[ -n "$succ" ]] && echo "successor=$succ"
  return 0
}

case "$MODE" in
  extract)
    if [[ $# -gt 1 ]]; then
      echo "[predecessor-gate] extract takes no arguments (body on stdin); got: ${*:2}" >&2
      exit 2
    fi
    extract_trailers
    exit 0
    ;;
  verdict)
    STATE="${2:-}"
    case "$STATE" in
      closed) exit 0 ;;
      open)   exit 3 ;;
      "")     echo "[predecessor-gate] verdict requires a state argument (open|closed)" >&2; exit 2 ;;
      *)      echo "[predecessor-gate] unknown predecessor state: '$STATE' (want open|closed)" >&2; exit 2 ;;
    esac
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    echo "[predecessor-gate] unknown mode: '$MODE'" >&2
    usage
    exit 2
    ;;
esac
