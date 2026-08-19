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
# THE TWO HALVES. The shape/enum lint says a row is WELL-FORMED. The successor clause (#575)
# says its claim is TRUE. A register that records claims but never tests them reads as coverage
# while the tree drifts out from under it — which is what #348 did: rows 56/61/63 asserted
# coverage for four engines whose only `scriptPath` dispatcher had died with the stage docs, and
# this guard was green the whole time because it only ever counted cells.
#
#   1. SHAPE + ENUM: five tab-separated cells, none empty, no duplicate capability, a
#      disposition inside the closed enum. Unconditional, on every row, forever.
#
#   2. SUCCESSOR: require by disposition, check by presence.
#      - `ported` and `already-covered` MUST name at least one successor — those are the
#        dispositions that assert coverage.
#      - ANY row whose successor cell is not the none-token `-` has EVERY comma-separated token
#        resolved as a repo-relative path against the register's tree root, `dropped` and
#        `choreography` included. A fix that moves a false row into an unchecked class is not a
#        fix, and six `dropped` rows do assert a survivor in prose.
#      - A `.mjs` token is additionally DISPATCH-PROBED. Existence alone provably would not have
#        caught #348: design-sync.mjs and figma.mjs were on disk the entire time, and only their
#        dispatch died. Per-shape reachability for .sh / skill / agent tokens is deliberately
#        NOT here — three more discovery mechanisms for a failure nobody has observed.
#
# THE PROBE USES NO `git` SUBCOMMAND, and that is load-bearing rather than stylistic. It reuses
# #574's needle (`scriptPath`) and pathspec (plugins/*/skills/**/*.md plus
# plugins/dev-pipeline/workflows/*.mjs) but roots the scan at the register's own tree. `git grep`
# inside the selftest's plain `mktemp` sandbox errors with EMPTY output, which a probe reads as
# "nothing dispatches anything": it would false-red every .mjs fixture, or invite a not-a-repo
# skip arm that is fail-open by construction. Same file set, same needle, same verdict in CI —
# and a sandbox that can fixture both the reachable and the orphaned case.
#
# WHICH CELLS ARE CHECKED AGAINST TODAY'S TREE. Exactly one. Rows are permanent record: a row is
# never removed when its staged paths die, so the PATH cell is a historical citation and is NOT
# existence-checked — a citation to a deleted file is still true. The SUCCESSOR cell is the
# opposite: a live claim about the tree as it is now, and the only cell whose truth this guard
# can test. The NOTE cell is free text and is never parsed for claims; it routinely names
# scripts that are explicitly NOT the successor (row 1: "claim-issue.sh itself is shared, not
# stage-owned"), so prose extraction would manufacture claims the register never made.
#
# The stages-file coverage clause this header used to describe was deleted in #577, once #348
# landed and the stage docs it gated were gone.
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

# The tree successor tokens resolve against is derived from the REGISTER, not from $HERE and not
# from $PWD. The register lives at <root>/tools/, so <root> is its parent's parent — which is what
# lets the selftest drop a copy into a sandbox and have that sandbox be the whole file universe,
# with no repo, no `git`, and no dependence on the caller's working directory.
ROOT="$(cd "$(dirname "$REGISTER")/.." 2>/dev/null && pwd)" || ROOT=""
if [[ -z "$ROOT" ]]; then
  echo "[capability-parity] FATAL: cannot resolve the register's tree root from $REGISTER" >&2
  exit 2
fi

# Successor accounting for the success line. A clause that silently stops running is exactly how
# this ticket happened, so the counts are reported rather than left implicit: a drop to
# "0 successor claim(s) resolved" is then legible in a CI log without reading this file.
CLAIM_ROWS=0
NONE_ROWS=0
PROBED=0

# Trim leading/trailing spaces. No extglob and no `${var/#...}` regex tricks — stock bash 3.2 on
# the macOS CI lane is the floor. A TAB can never reach here: the row was already split on tabs.
trim() {
  local v="$1"
  while [[ "$v" == " "* ]]; do v="${v# }"; done
  while [[ "$v" == *" " ]]; do v="${v% }"; done
  printf '%s' "$v"
}

# The dispatch-site file set, built once and only if some row actually names a .mjs successor.
# Newline-delimited, not an array — see BASH 3.2 in the header for why this file avoids the
# fancier data structures.
DISPATCH_SITES=""
DISPATCH_SITES_BUILT=0
build_dispatch_sites() {
  [[ "$DISPATCH_SITES_BUILT" -eq 1 ]] && return 0
  DISPATCH_SITES_BUILT=1
  # #574's pathspec. Selftest and probe harnesses are excluded: a dispatch that exists only
  # inside a test fixture is not reachability, it is the fixture asserting itself.
  #
  # The exclusion is `find -name`, i.e. BASENAME-only, and that is not a style preference. Piping
  # the file list through `grep -v -- -selftest\.` matches anywhere in the ABSOLUTE path — and
  # this guard's own selftest runs from `mktemp -d -t capability-parity-selftest.XXXXXX`, whose
  # directory name contains that very substring. Every fixture site under it would be filtered
  # out, the probe would find no dispatcher for anything, and the suite would red on its own
  # sandbox path rather than on any property of the tree.
  DISPATCH_SITES="$(
    find "$ROOT/plugins" -type f ! -name '*-selftest.*' ! -name '*-probe.*' \( \
         \( -path "$ROOT/plugins/*/skills/*" -name '*.md' \) -o \
         \( -path "$ROOT/plugins/dev-pipeline/workflows/*" -name '*.mjs' \) \
       \) 2>/dev/null
  )" || true
  return 0
}

# is_dispatched <basename> — true when some dispatch site carries BOTH `scriptPath` and the
# basename on ONE line. Two separate greps piped together would be wrong twice over: it would
# match a file that mentions the engine in prose and dispatches something else entirely, and
# under `set -o pipefail` a `grep -q` consumer that matches EARLY kills its producer with SIGPIPE
# and the pipeline reports 141 — a match scored as a miss. One awk pass, needle through ENVIRON
# so awk applies no backslash processing to it.
is_dispatched() {
  local base="$1" f
  build_dispatch_sites
  [[ -n "$DISPATCH_SITES" ]] || return 1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if b="$base" awk 'index($0, "scriptPath") && index($0, ENVIRON["b"]) { hit = 1; exit } END { exit(hit ? 0 : 1) }' "$f" 2>/dev/null; then
      return 0
    fi
  done <<< "$DISPATCH_SITES"
  return 1
}

# check_successor <line> <capability> <cell> — resolves every token in a non-`-` successor cell.
# One message per failing token (not per row): a row that names three successors and loses two of
# them should say so twice, or the second death is invisible until the first is fixed.
check_successor() {
  local ln="$1" cap="$2" buf="$3" token more=1
  while [[ "$more" -eq 1 ]]; do
    case "$buf" in
      *,*) token="${buf%%,*}"; buf="${buf#*,}" ;;
      *)   token="$buf"; more=0 ;;
    esac
    token="$(trim "$token")"

    if [[ -z "$token" ]]; then
      err "line $ln: capability '$cap' has an empty successor token — no doubled or trailing commas; record 'no successor' as the whole cell being '-'"
      continue
    fi
    if [[ "$token" == "-" ]]; then
      err "line $ln: capability '$cap' mixes the none-token '-' with real successors — '-' is the whole cell or it is not there"
      continue
    fi
    # Repo-relative, closed. An absolute token or one climbing out with '..' resolves against
    # whatever the host machine happens to carry, which is green-on-my-laptop, not a claim.
    case "$token" in
      /*)      err "line $ln: capability '$cap' names successor '$token' — successors are repo-relative paths, not absolute ones"; continue ;;
      ..|../*|*/..|*/../*)
               err "line $ln: capability '$cap' names successor '$token' — successors are repo-relative paths and may not climb out of the tree with '..'"; continue ;;
    esac

    if [[ ! -e "$ROOT/$token" ]]; then
      err "line $ln: capability '$cap' names successor '$token' which does not exist — the disposition claims coverage this tree does not have"
      continue
    fi

    case "$token" in
      *.mjs)
        PROBED=$((PROBED + 1))
        if ! is_dispatched "$(basename "$token")"; then
          err "line $ln: capability '$cap' names successor '$token', which exists but nothing dispatches — no file under plugins/*/skills/**/*.md or plugins/dev-pipeline/workflows/*.mjs names it alongside 'scriptPath' (the #348 shape: an engine on disk with no caller)"
        fi
        ;;
    esac
  done
}

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
  if [[ "${#tabs}" -ne 4 ]]; then
    err "line $LINENO_: malformed row — expected 5 tab-separated fields, found $(( ${#tabs} + 1 ))"
    continue
  fi

  # Split by hand rather than with `IFS=$'\t' read`. Tab is an IFS *whitespace* character, so
  # that read collapses a run of tabs into one delimiter: a row with an empty middle cell
  # would silently shift every later cell one to the left, and the empty disposition this
  # exists to catch would arrive here wearing the note's text. The tab count is already known
  # to be exactly 3, so these expansions are exact and preserve empty cells.
  capability="${line%%$'\t'*}"; rest="${line#*$'\t'}"
  paths="${rest%%$'\t'*}";      rest="${rest#*$'\t'}"
  disposition="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  successor="${rest%%$'\t'*}"
  note="${rest#*$'\t'}"
  ROWS=$((ROWS + 1))

  # The successor cell joins this clause rather than getting an empty-means-none arm of its own.
  # An empty cell records nothing; "this capability has no successor" is a DECISION and is spelled
  # `-`. Reading blank as none is how a backfill that silently skipped a row would pass.
  if [[ -z "${capability// }" || -z "${paths// }" || -z "${successor// }" || -z "${note// }" ]]; then
    err "line $LINENO_: malformed row — capability, path, successor and note cells must all be non-empty (a successor-less row spells it '-')"
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

  # REQUIRE BY DISPOSITION. `ported` and `already-covered` are the two values that assert the
  # behavior still exists somewhere; a row making that assertion and naming nothing is the shape
  # this guard exists to refuse.
  successor="$(trim "$successor")"
  if [[ "$successor" == "-" ]]; then
    case "$disposition" in
      ported|already-covered)
        err "line $LINENO_: capability '$capability' is '$disposition' but names no successor — a disposition that asserts coverage must name the artifact providing it"
        continue
        ;;
    esac
    NONE_ROWS=$((NONE_ROWS + 1))
    continue
  fi

  # CHECK BY PRESENCE. Every non-`-` cell is resolved whatever the disposition, so a `dropped`
  # row that still asserts a survivor is held to it too — rows 56/61/63 stopped being false by
  # changing CLASS, not by becoming true, and the ticket's own two-arm proposal would have let
  # that through.
  CLAIM_ROWS=$((CLAIM_ROWS + 1))
  check_successor "$LINENO_" "$capability" "$successor"
done < "$REGISTER"

if [[ "$ROWS" -eq 0 ]]; then
  err "register $REGISTER contains no rows"
fi

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "[capability-parity] $VIOLATIONS violation(s) in $REGISTER" >&2
  exit 1
fi

echo "[capability-parity] OK — $ROWS capability row(s), every disposition in enum; $CLAIM_ROWS successor claim(s) resolved, $PROBED dispatch-probed, $NONE_ROWS row(s) claim none."
exit 0
