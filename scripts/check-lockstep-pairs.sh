#!/usr/bin/env bash
# check-lockstep-pairs.sh — mechanically enforce contract pairs that are duplicated
# across files and can only drift silently.
#
# Some contracts exist in two or three places by necessity: an agent whose independence
# contract forbids reading pipeline docs keeps an inline copy of a rule; three Workflow
# scripts each declare the same schema because the runtime gives them no import. The
# prose at those sites says "keep verbatim" / "must match byte-for-byte" — and until this
# script, nothing checked it.
#
# This replaces the prose-presence guard class (grep a token out of a markdown file),
# which could only tell you a word was still present, never that two copies still agree.
#
# Lives in repo-level scripts/ rather than in a plugin because the pairs span plugins.
#
# Usage:
#   bash scripts/check-lockstep-pairs.sh [manifest] [repo-root]
# Defaults: scripts/lockstep-manifest.tsv, the repo root inferred from this script's dir.
#
# Manifest rows are TAB-separated (blank lines and #-comments ignored):
#   pair-id <TAB> relation <TAB> fileA <TAB> anchorA <TAB> fileB <TAB> anchorB
#
# relation:
#   verbatim   both blocks must match after collapsing whitespace runs to one space
#              and trimming (the text-contract-selftest.sh idiom — indentation and
#              line-wrapping are not the contract; the tokens are).
#   subset-of  each block's FIRST single-quoted '...|...' literal is split on `|`;
#              every token of fileB's literal must appear in fileA's. For deliberate
#              narrowings — e.g. a human-attributed subset of a wider provenance enum,
#              where verbatim would be wrong.
#
# Blocks are delimited by marker comments carrying the anchor id, in whatever comment
# syntax the host file uses:
#   # LOCKSTEP-BEGIN <anchor>        ... # LOCKSTEP-END <anchor>          (shell, mjs)
#   <!-- LOCKSTEP-BEGIN <anchor> --> ... <!-- LOCKSTEP-END <anchor> -->   (markdown)
# The marker lines themselves are never part of the compared block.
#
# A missing marker is a FAILURE, not a skip: a pair that silently stops being checked is
# the exact failure mode this script exists to prevent.
#
# Exit code = number of failed pairs (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${1:-$HERE/lockstep-manifest.tsv}"
ROOT="${2:-$(cd "$HERE/.." && pwd)}"

[[ -f "$MANIFEST" ]] || { echo "[lockstep] FATAL: manifest not found: $MANIFEST" >&2; exit 99; }

FAILS=0
CHECKED=0
ok()  { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }

# extract <file> <anchor> — emit the lines strictly between the BEGIN/END markers.
# Prints nothing and returns 1 when either marker is absent.
extract() {
  local file="$1" anchor="$2"
  awk -v a="$anchor" '
    $0 ~ ("LOCKSTEP-BEGIN[ \t]+" a "([ \t]|$|[ \t]*-->)") { inblock = 1; seen = 1; next }
    $0 ~ ("LOCKSTEP-END[ \t]+"   a "([ \t]|$|[ \t]*-->)") { inblock = 0; closed = 1; next }
    inblock { print }
    END { if (!seen || !closed) exit 1 }
  ' "$file"
}

# normalize — collapse whitespace runs to a single space and trim, so indentation and
# line wrapping are not part of the contract.
normalize() { tr '\n' ' ' | tr -s ' \t' ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

# first_enum — the first single-quoted literal containing a `|`, with quotes stripped.
first_enum() { grep -o "'[^']*|[^']*'" | head -n1 | tr -d "'"; }

while IFS=$'\t' read -r pair relation fa aa fb ab; do
  # Skip blanks and comments.
  case "${pair:-}" in ''|'#'*) continue ;; esac
  [[ -n "${relation:-}" && -n "${fa:-}" && -n "${aa:-}" && -n "${fb:-}" && -n "${ab:-}" ]] || {
    bad "$pair: malformed manifest row (need 6 tab-separated fields)"
    continue
  }
  CHECKED=$((CHECKED + 1))

  PA="$ROOT/$fa"
  PB="$ROOT/$fb"
  [[ -f "$PA" ]] || { bad "$pair: fileA missing: $fa"; continue; }
  [[ -f "$PB" ]] || { bad "$pair: fileB missing: $fb"; continue; }

  BA=$(extract "$PA" "$aa") || { bad "$pair: no LOCKSTEP-BEGIN/END '$aa' block in $fa"; continue; }
  BB=$(extract "$PB" "$ab") || { bad "$pair: no LOCKSTEP-BEGIN/END '$ab' block in $fb"; continue; }
  [[ -n "$BA" ]] || { bad "$pair: block '$aa' in $fa is empty"; continue; }
  [[ -n "$BB" ]] || { bad "$pair: block '$ab' in $fb is empty"; continue; }

  case "$relation" in
    verbatim)
      NA=$(printf '%s' "$BA" | normalize)
      NB=$(printf '%s' "$BB" | normalize)
      if [[ "$NA" == "$NB" ]]; then
        ok "$pair (verbatim): $fa == $fb"
      else
        bad "$pair (verbatim): $fa and $fb have DRIFTED"
        diff <(printf '%s\n' "$BA") <(printf '%s\n' "$BB") | sed 's/^/      /' >&2
      fi
      ;;
    subset-of)
      EA=$(printf '%s' "$BA" | first_enum)
      EB=$(printf '%s' "$BB" | first_enum)
      if [[ -z "$EA" || -z "$EB" ]]; then
        bad "$pair (subset-of): no single-quoted '...|...' literal in ${EA:+$fb}${EA:-$fa}"
        continue
      fi
      missing=""
      # bash 3.2: no readarray/associative arrays — split on | with IFS.
      OLDIFS="$IFS"; IFS='|'
      for tok in $EB; do
        case "|$EA|" in *"|$tok|"*) ;; *) missing="$missing $tok" ;; esac
      done
      IFS="$OLDIFS"
      if [[ -z "$missing" ]]; then
        ok "$pair (subset-of): $fb ⊆ $fa"
      else
        bad "$pair (subset-of): $fb has token(s) absent from $fa:$missing"
      fi
      ;;
    *)
      bad "$pair: unknown relation '$relation' (expected verbatim | subset-of)"
      ;;
  esac
done < "$MANIFEST"

echo "[lockstep] $CHECKED pair(s) checked, $FAILS failed"
exit $FAILS
