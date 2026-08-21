#!/usr/bin/env bash
# ledger-carry-forward.sh — project an intake receipt's Decision Ledger onto the
# four-column shape a committed plan carries.
#
# Usage: ledger-carry-forward.sh <receipt-path>
#
# WHY THIS EXISTS. A receipt's ledger is five columns —
# `ID | Decision | Resolution | Provenance | Kind` — and a plan's is four. ledger-lint.sh
# enforces each arity EXACTLY, and that is a measured decision recorded at its own source:
# a permissive column range collapses receipt mode and plan mode into one parser. The
# consequence lands on whoever carries the rows across. A verbatim copy fails on column
# count before anyone reads what it says, and the lint additionally reports a
# receipt-shaped ledger as "0 ledger rows" and then adds a violation for the emptiness it
# manufactured. Measured once at four milestone-1 refusals in six minutes, two of the
# three fix attempts spent on a table rather than on a design problem.
#
# So this is the mechanical route: the rows are never retyped between two schemas.
#
# WHAT IT IS NOT. Not a second validator. It refuses only what it cannot PROJECT — a
# `| D-n |` row at neither arity, and a document with no rows and no explicit empty form.
# The provenance enum, the receipt's Kind bar, duplicate ids and the ticket-sourced
# citation are ledger-lint.sh's to judge, in whichever mode the caller runs it. A second
# copy of those rules here would be the third parser #562 already declined to add.
#
# THE CONTRACT, precisely:
#
#   * Rows are found with the same whole-file grep the lint uses, so "the rows" means the
#     same set on both sides — including any that sit outside the section heading.
#   * `Decision`, `Resolution` and `Provenance` are reproduced BYTE-FOR-BYTE, their
#     surrounding padding included, and an escaped `\|` inside a cell survives as itself.
#     Only the `Kind` cell is dropped.
#   * The output is the whole `## Decision Ledger` section, so it is a lintable document
#     in its own right: `ledger-lint.sh <output>` passes for every receipt that passes
#     `ledger-lint.sh --receipt`.
#   * IDEMPOTENT. Four-column rows pass through untouched, so projecting this script's
#     own output reproduces it byte-for-byte. Reading both arities is not the permissive
#     parser the lint rejects: the lint still refuses each arity in the other's mode, and
#     a projector is the one place where reading both IS the job.
#   * Nothing reaches stdout unless the whole projection succeeded. A partial table
#     redirected into a file would be a silently dropped row wearing a clean exit.
#
# Exit: 0 clean, 1 an input this cannot project (each reason named on stderr), 2 usage/IO.
set -euo pipefail

SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    -*) echo "ledger-carry-forward: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$SRC" ]] || { echo "ledger-carry-forward: unexpected argument: $1" >&2; exit 2; }
      SRC="$1"; shift ;;
  esac
done

[[ -n "$SRC" ]] || { echo "ledger-carry-forward: usage: ledger-carry-forward.sh <receipt-path>" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "ledger-carry-forward: receipt file not found: $SRC" >&2; exit 2; }
# EXPLICIT, for the reason ledger-lint.sh's reconcile mode states about the same read: the
# row scan below ends in `|| true`, so an unreadable receipt would yield no rows and then
# be reported as "no ledger" — a different fact, and one that never reports FAIL.
[[ -r "$SRC" ]] || { echo "ledger-carry-forward: receipt file not readable: $SRC" >&2; exit 2; }

# The one contract string this script must reproduce byte-for-byte rather than merely
# recognise, which is why it is a copy at all. Held to ledger-lint.sh's copy by the
# lockstep pair: a drifting empty form would make this script emit a line the lint
# rejects, and neither file would look wrong on its own.
# LOCKSTEP-BEGIN ledger-empty-form
EMPTY_FORM='No material decisions — all choices codebase-derived.'
# LOCKSTEP-END ledger-empty-form

# Raw inter-pipe substrings of a table row, into CELLS.
#
# Deliberately NOT ledger-lint.sh's mask-with-a-sentinel-and-split idiom. That parse is
# destructive by design — it trims and whitespace-normalizes on the way out — whereas
# byte-preservation is this script's whole contract, and unmasking a cell that happened to
# contain the sentinel would corrupt it silently. A left-to-right walk that treats `\|` as
# one character needs no sentinel and hands back the substrings untouched.
#
# It reproduces `IFS='|' read -r -a`'s arity exactly, which is what lets "5 cells" mean
# here what it means there: that read yields NO field after a trailing delimiter, so the
# walk's final empty segment is dropped.
CELLS=()
split_row() { # split_row <line>
  local line="$1" cur="" ch n i
  CELLS=()
  n=${#line}
  for (( i = 0; i < n; i++ )); do
    ch="${line:i:1}"
    if [[ "${line:i:2}" == '\|' ]]; then
      cur+='\|'
      i=$((i + 1))
      continue
    fi
    if [[ "$ch" == '|' ]]; then
      CELLS+=("$cur")
      cur=""
      continue
    fi
    cur+="$ch"
  done
  CELLS+=("$cur")
  if [[ -z "${CELLS[${#CELLS[@]} - 1]}" ]]; then
    CELLS=("${CELLS[@]:0:${#CELLS[@]} - 1}")
  fi
}

ROWS=()
ERRORS=0

while IFS= read -r line; do
  split_row "$line"
  n=${#CELLS[@]}
  # Ignore ONE trailing blank cell, and only where ignoring it lands on a legal arity —
  # the rule ledger-lint.sh's normalize_arity already applies, for its reason: stripping
  # unconditionally would turn a row with a genuinely empty last column into a "malformed
  # row" report instead of the specific violation that empty cell earns from the lint.
  if (( n == 6 || n == 7 )) && [[ "${CELLS[$((n - 1))]}" =~ ^[[:space:]]*$ ]]; then
    n=$((n - 1))
  fi
  # 6 cells is a five-column receipt row, 5 a four-column plan row; the projection is the
  # same take-the-first-four either way, so the arity decides only whether there is a Kind
  # cell to drop. Anything else is named and stops the run.
  if (( n != 5 && n != 6 )); then
    printf 'ledger-carry-forward: ERROR: unprojectable ledger row — expected 4 columns (ID | Decision | Resolution | Provenance) or 5 (plus Kind), found %d: %s\n' \
      "$((n - 1))" "$line" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  ROWS+=("|${CELLS[1]}|${CELLS[2]}|${CELLS[3]}|${CELLS[4]}|")
done < <(grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' "$SRC" || true)

if (( ERRORS > 0 )); then
  echo "ledger-carry-forward: FAIL — $ERRORS unprojectable row(s) in $SRC; nothing written" >&2
  exit 1
fi

if (( ${#ROWS[@]} == 0 )); then
  # Emitting the empty form here on no evidence would assert something the receipt never
  # said — that no material decision was made — so an input carrying neither rows nor the
  # form is a refusal, not a default.
  grep -qF "$EMPTY_FORM" "$SRC" || {
    echo "ledger-carry-forward: FAIL — $SRC has no | D-n | ledger rows and no explicit empty form ('$EMPTY_FORM'); nothing to carry forward" >&2
    exit 1
  }
  printf '## Decision Ledger\n\n%s\n' "$EMPTY_FORM"
  echo "ledger-carry-forward: projected the explicit empty form from $SRC" >&2
  exit 0
fi

printf '## Decision Ledger\n\n'
printf '| ID | Decision | Resolution | Provenance |\n'
printf '| --- | --- | --- | --- |\n'
printf '%s\n' "${ROWS[@]}"
echo "ledger-carry-forward: projected ${#ROWS[@]} row(s) from $SRC" >&2
