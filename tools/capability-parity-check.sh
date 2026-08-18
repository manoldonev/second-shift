#!/usr/bin/env bash
# capability-parity-check.sh — the guard over tools/capability-parity.tsv.
#
# WHAT IT IS FOR. #348 deletes the staged lane, and its parity story is keyed on deleted
# PATHS. That catches an orphaned reference; it cannot catch a BEHAVIOR disappearing, because
# a behavior whose only implementation is a stage doc leaves nothing behind to dangle. The
# register is the record of what each staged-lane capability's fate was decided to be, and this
# guard is what makes a deletion answerable to it — as a PRECONDITION, not a deletion trigger.
# While a stage doc no row names is PRESENT, this reds. So coverage must exist before any
# deletion can land, and at deletion time every removed doc was already dispositioned. (Note
# which way that runs: deleting an uncovered doc is what makes the clause stop firing, which is
# exactly why the clause has to fire on presence.)
#
# LIFETIME — read this before "fixing" the coverage clause. Two jobs, with different
# lifespans:
#
#   1. TRANSITIONAL: the coverage clause below (every existing stages/*.md file is named by
#      some row). It is the gate on #348's deletions. Once #348 lands and the stage docs are
#      gone, this clause matches zero files and is VACUOUS **BY DESIGN**. That is the success
#      condition, not a regression, and it is not a reason to delete the clause: the stage docs
#      exist until they do not, and a guard that removed itself on the way out would leave the
#      final deletion ungated.
#
#   2. PERMANENT: the shape and enum lints. They apply unconditionally, to every row, forever —
#      including rows whose staged paths no longer exist. Rows are permanent record; a
#      disposition outlives the implementation it dispositioned, which is the entire point of
#      the file. Never delete a row because its paths died.
#
# A row's paths are therefore NOT existence-checked. They are historical citations, and a
# citation to a deleted file is still true.
#
# BASH 3.2 — read this before "simplifying" the two newline-delimited accumulators below into
# associative arrays. CI runs the whole selftest set on a macOS lane PATH-shimmed to stock
# /bin/bash 3.2, which has no `declare -A`. There, an associative subscript is evaluated
# ARITHMETICALLY: `${SEEN[$capability]}` parses a capability name as identifiers, `set -u`
# kills the shell mid-loop, and the process exits **0**. The failure mode is silent success on
# a register this guard never judged — the exact false-green it exists to prevent — so the cost
# of that simplification is not a diagnosable error, it is an inert oracle.
#
# Usage: capability-parity-check.sh [register.tsv]
#
# Exit:  0 = clean
#        1 = one or more violations (each printed to stderr)
#        2 = usage / environment error
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REGISTER="${1:-$HERE/capability-parity.tsv}"

VIOLATIONS=0
err() { echo "[capability-parity] $1" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }

if [[ ! -f "$REGISTER" ]]; then
  echo "[capability-parity] FATAL: register not found at $REGISTER" >&2
  exit 2
fi

# The closed disposition enum (D-15). `choreography` is a first-class value, not a synonym for
# `dropped`: the parent's rule requires a choreography death to be a RECORDED decision, so it
# must be expressible here rather than folded into the general drop.
is_disposition() {
  case "$1" in
    ported|dropped|already-covered|choreography) return 0 ;;
    *) return 1 ;;
  esac
}

# Newline-delimited accumulators, not associative arrays — see BASH 3.2 in the header.
# SEEN_CAPABILITY holds "<line>\t<capability>" rows.
SEEN_CAPABILITY=""
ROWS=0
LINENO_=0

while IFS= read -r line || [[ -n "$line" ]]; do
  LINENO_=$((LINENO_ + 1))
  case "$line" in ''|'#'*) continue ;; esac

  # Field count by tab count, NOT by `read -a`: a trailing empty field is invisible to the
  # latter, so a row ending in a bare tab would silently read as three cells and skip the
  # empty-cell check below.
  tabs="${line//[!$'\t']/}"
  if [[ "${#tabs}" -ne 3 ]]; then
    err "line $LINENO_: malformed row — expected 4 tab-separated fields, found $(( ${#tabs} + 1 ))"
    continue
  fi

  # Split by hand rather than with `IFS=$'\t' read`. Tab is an IFS *whitespace* character, so
  # that read collapses a run of tabs into one delimiter: a row with an empty middle cell
  # would silently shift every later cell one to the left, and the empty disposition this
  # exists to catch would arrive here wearing the note's text. The tab count is already known
  # to be exactly 3, so these expansions are exact and preserve empty cells.
  capability="${line%%$'\t'*}"; rest="${line#*$'\t'}"
  paths="${rest%%$'\t'*}";      rest="${rest#*$'\t'}"
  disposition="${rest%%$'\t'*}"
  note="${rest#*$'\t'}"
  ROWS=$((ROWS + 1))

  if [[ -z "${capability// }" || -z "${paths// }" || -z "${note// }" ]]; then
    err "line $LINENO_: malformed row — capability, path and note cells must all be non-empty"
    continue
  fi

  # Exact field equality, and the needle arrives through ENVIRON rather than `-v`: awk applies
  # backslash-escape processing to a `-v` assignment, ENVIRON is passed through untouched. A
  # TAB is a safe delimiter because the row was already split on TABs, so no cell holds one.
  prev_line="$(printf '%s' "$SEEN_CAPABILITY" | c="$capability" awk -F'\t' '$2 == ENVIRON["c"] { print $1; exit }')"
  if [[ -n "$prev_line" ]]; then
    err "line $LINENO_: duplicate capability '$capability' (first seen at line $prev_line)"
    continue
  fi
  SEEN_CAPABILITY="${SEEN_CAPABILITY}${LINENO_}"$'\t'"${capability}"$'\n'

  # Unconditional (D-16): the enum is validated on every row regardless of whether its paths
  # still exist. An empty cell and an off-enum value are the same violation class — a row that
  # records no decision.
  if ! is_disposition "$disposition"; then
    err "line $LINENO_: capability '$capability' has disposition '$disposition' — not one of ported|dropped|already-covered|choreography"
    continue
  fi
done < "$REGISTER"

if [[ "$ROWS" -eq 0 ]]; then
  err "register $REGISTER contains no rows"
fi

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "[capability-parity] $VIOLATIONS violation(s) in $REGISTER" >&2
  exit 1
fi

echo "[capability-parity] OK — $ROWS capability row(s), every disposition in enum."
exit 0
