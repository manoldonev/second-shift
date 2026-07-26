#!/usr/bin/env bash
# start-slice.sh — stacked-PR starting-slice derivation: the persisted-vs-seed
# precedence rule plus the all-slices-already-pushed short-circuit.
#
# Extracted from the inline block in stages/1-intake.md ("Slice-derivation
# pre-check"), which now invokes this tool. The rule was previously prose-only,
# so no test could drive it: a harness re-implementation would have asserted the
# harness against itself rather than against the rule the pipeline runs. Same
# motivation, and the same markdown-calls-tool shape, as tools/max-pushed-slice.sh.
#
# What this tool owns (and what it deliberately does NOT):
#   OWNS      the precedence branch (persisted `currentSlice` wins over any
#             derived value) and the all-pushed short-circuit.
#   NOT OWNED the remote derivation itself (`git fetch` + `git ls-remote` piped
#             through max-pushed-slice.sh). That stays in the stage doc, so this
#             tool needs no network, no git repo, and no fixture remote.
#
# The caller supplies the derived value via --max-pushed ONLY when this tool asks
# for it. That two-call shape is deliberate: making --max-pushed mandatory would
# force the caller to do the remote derivation on every stacked resume, including
# the ones where the persisted value wins and the network round-trip is pure
# waste. Emitting a `need-max-pushed` verdict instead preserves the original
# control flow exactly.
#
# Usage:
#   start-slice.sh <state-path> <total-slices> [--max-pushed <n>]
#
# Output (stdout) — verdict line, then the value line where one applies. The
# verdict-line-then-data shape mirrors tools/slice-scope.sh.
#   persisted        + line 2 = the persisted currentSlice
#   seed             + line 2 = max-pushed + 1
#   all-pushed       (no value line) — every slice is already pushed; nothing to do
#   need-max-pushed  (no value line) — no persisted value; caller must derive
#                    max-pushed and call again with --max-pushed
#
# Exit: 0 on any verdict (a verdict is data, not an error), 2 on usage/IO error.
set -uo pipefail

die() { echo "start-slice: $1" >&2; exit 2; }

STATE_PATH=""
TOTAL_SLICES=""
MAX_PUSHED=""
MAX_PUSHED_SET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-pushed)
      [[ $# -ge 2 ]] || die "--max-pushed requires a value"
      MAX_PUSHED="$2"; MAX_PUSHED_SET=1; shift 2 ;;
    -*) die "unknown option '$1'" ;;
    *)
      if [[ -z "$STATE_PATH" ]]; then
        STATE_PATH="$1"
      elif [[ -z "$TOTAL_SLICES" ]]; then
        TOTAL_SLICES="$1"
      else
        die "unexpected argument '$1'"
      fi
      shift ;;
  esac
done

[[ -n "$STATE_PATH" && -n "$TOTAL_SLICES" ]] \
  || die "usage: start-slice.sh <state-path> <total-slices> [--max-pushed <n>]"
[[ -f "$STATE_PATH" ]] || die "state file not found: $STATE_PATH"
[[ "$TOTAL_SLICES" =~ ^[0-9]+$ ]] || die "<total-slices> must be a non-negative integer, got '$TOTAL_SLICES'"
if [[ "$MAX_PUSHED_SET" -eq 1 ]]; then
  [[ "$MAX_PUSHED" =~ ^[0-9]+$ ]] || die "--max-pushed must be a non-negative integer, got '$MAX_PUSHED'"
fi

# Precedence: a persisted currentSlice is authoritative (state-schema.md
# "Stacked-PR slice state"). Read it with the same `// empty` guard the stage doc
# used, so both an absent key and a JSON null resolve to the seed path.
PERSISTED=$(jq -r '.currentSlice // empty' "$STATE_PATH" 2>/dev/null) \
  || die "could not parse state file: $STATE_PATH"

if [[ -n "$PERSISTED" && "$PERSISTED" != "null" ]]; then
  # Deliberately unconditional on --max-pushed: precedence means the derived
  # value does not get a vote, and the all-pushed short-circuit lives in the
  # seed branch only (it did in the extracted block too).
  echo "persisted"
  echo "$PERSISTED"
  exit 0
fi

if [[ "$MAX_PUSHED_SET" -eq 0 ]]; then
  echo "need-max-pushed"
  exit 0
fi

if [[ "$MAX_PUSHED" -ge "$TOTAL_SLICES" ]]; then
  echo "all-pushed"
  exit 0
fi

echo "seed"
echo $((MAX_PUSHED + 1))
