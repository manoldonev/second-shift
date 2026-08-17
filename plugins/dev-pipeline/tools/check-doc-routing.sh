#!/usr/bin/env bash
# check-doc-routing.sh — lints that the paths a consumer's doc-routing.md routes to still
# resolve. doc-routing.md (an EP-3 extension file) is checked by basename only
# (extension-manifest.txt) — its CONTENT, a change-category -> doc-path routing map read by
# review-toolkit/agents/doc-updater.md, is not: a routing entry
# pointing at a moved or deleted doc silently misroutes every future doc update with no
# signal. This is the same class of gap check-extensions.sh closes for the extension-file NAMES
# it lints (EP-3), applied one level down to doc-routing.md's row CONTENT.
#
# Scan scope: only markdown table body rows (lines starting with "|"; the header row — the
# first "|"-line of each table — and its "---" separator row are explicitly skipped, tracked
# by a small per-table state machine) and top-level list items (lines starting with "-" or
# "*"). Backtick-quoted spans in those lines are candidate paths; for a list item, only spans
# before an em-dash (" — ") description separator count. Prose and blockquotes are never
# scanned, so directory-name fragments or "plugin:skill" mentions in narrative text are not
# misread as paths.
#
# Resolution: a "#"-suffixed anchor is stripped and checked to file level only; a candidate
# is tried relative to the repo root first, then — if that misses — relative to
# doc-routing.md's own containing directory (ordinary markdown relative-link semantics; real
# routing maps mix both styles, e.g. an explicit ".claude/second-shift/review-context/db-
# reviewer.md" alongside a bare "review-context/*.md" glob). A candidate containing "*" is
# resolved as a shell glob at whichever base it matches under (passes if it matches >=1
# path); anything else must exist as a file or directory at one of the two bases.
#
# doc-routing.md is optional: no file -> clean no-op (this repo's own tree has none today).
#
# Usage: check-doc-routing.sh [consumer-repo-root]   (default: cwd). Exit = failure count.
# Seam: SECOND_SHIFT_DOC_ROUTING overrides the resolved doc-routing.md path (hermetic tests).
set -euo pipefail
ROOT="${1:-.}"
DOC_ROUTING="${SECOND_SHIFT_DOC_ROUTING:-$ROOT/.claude/second-shift/doc-routing.md}"
DOC_ROUTING_DIR="$(cd "$(dirname "$DOC_ROUTING")" 2>/dev/null && pwd || true)"
fails=0

[[ -f "$DOC_ROUTING" ]] || { echo "check-doc-routing: no doc-routing.md — clean (optional extension)"; exit 0; }

# Extract every backtick-quoted span from a line, one per output line.
extract_backticked() {
  # shellcheck disable=SC2016 # literal backtick markers, not command substitution
  printf '%s\n' "$1" | grep -o '`[^`]*`' | sed 's/^`//; s/`$//'
}

resolves_at() {
  local base="$1" candidate="$2"
  [[ -z "$base" ]] && return 1
  if [[ "$candidate" == *'*'* ]]; then
    # shellcheck disable=SC2206
    local matches=($base/$candidate)
    [[ -e "${matches[0]}" ]]
  else
    [[ -e "$base/$candidate" ]]
  fi
}

check_candidate() {
  local raw="$1" src="$2" candidate
  candidate="${raw%%#*}"   # strip a #-suffixed anchor; checked to file level only
  [[ -z "$candidate" ]] && return 0
  if resolves_at "$ROOT" "$candidate" || resolves_at "$DOC_ROUTING_DIR" "$candidate"; then
    return 0
  fi
  echo "DANGLING-DOC-ROUTE: '$src' -> $candidate does not exist (checked repo root and doc-routing.md's own directory)" >&2
  fails=$((fails+1))
}

# Table state machine: "none" (not in a table) -> "header-seen" (the header row was just
# skipped, expecting the --- separator next) -> "body" (scan every row for paths). A
# non-"|" line always resets to "none", so each new table gets its own header skipped.
table_state="none"
while IFS= read -r line; do
  case "$line" in
    '|'*)
      if [[ "$table_state" == "none" ]]; then
        table_state="header-seen"; continue   # the header row itself — never scanned
      fi
      # a separator row contains only |, -, :, and whitespace
      stripped="$(printf '%s' "$line" | tr -d ' \t|:-')"
      if [[ -z "$stripped" ]]; then
        table_state="body"; continue
      fi
      table_state="body"
      while IFS= read -r span; do
        [[ -z "$span" ]] && continue
        check_candidate "$span" "$line"
      done < <(extract_backticked "$line")
      ;;
    '-'*|'*'*)
      table_state="none"
      body="${line%% — *}"
      [[ "$body" == "$line" ]] && body="$line"
      while IFS= read -r span; do
        [[ -z "$span" ]] && continue
        check_candidate "$span" "$line"
      done < <(extract_backticked "$body")
      ;;
    *) table_state="none" ;;
  esac
done < "$DOC_ROUTING"

if [[ "$fails" -gt 0 ]]; then
  echo "check-doc-routing: $fails failure(s) — fail closed" >&2
  exit "$fails"
fi
echo "check-doc-routing: clean"
