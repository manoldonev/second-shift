#!/usr/bin/env bash
# plan-scope-paths.sh — extract backtick-quoted path-like tokens from ONE named
# section of a Stage-3 plan file (#109). Used by the Stage-7 checkpoint flow to
# hand statectl.sh's `validate_stage7_payload` a pre-computed `affectedFiles` /
# `outOfScopeFiles` JSON array — statectl itself does no markdown parsing or git
# I/O (see docs/plans/second-shift-109-lean.md "Assumptions").
#
# Usage: plan-scope-paths.sh <plan-file> <section-grep-pattern>
#
# <section-grep-pattern> is matched case-insensitively against a markdown heading
# line (`^#{1,6} ...` or a bold-line `**...**` header), the same heading-match
# convention plan-lint.sh's section_present() uses — e.g. "affected files" or
# "out.of.scope" (dot matches hyphen/space variants, mirroring plan-lint's own
# SECTIONS patterns).
#
# The section body is everything from that heading line (exclusive) to the next
# heading line (exclusive) or EOF. Within that slice, backtick-quoted tokens that
# look like a repo path (contain a slash, dotted final segment) are extracted —
# the exact "path-like" definition plan-lint.sh's Check 5a already established,
# reused verbatim here so the two tools agree on what counts as a path.
#
# Output: a JSON array of the unique matched paths (possibly empty). Never a
# parse failure to emit — an absent section or a section with zero path tokens
# both print `[]`, since the caller (validate_stage7_payload) treats an empty
# affectedFiles/outOfScopeFiles list as legitimate content ("this plan genuinely
# touches/excludes nothing"), not an extraction failure.
#
# Exit: 0 on success (including the empty-array cases above), 2 on usage/IO error.
set -euo pipefail

PLAN="${1:-}"
PATTERN="${2:-}"

[[ -n "$PLAN" && -n "$PATTERN" ]] || { echo "plan-scope-paths: usage: plan-scope-paths.sh <plan-file> <section-grep-pattern>" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "plan-scope-paths: plan file not found: $PLAN" >&2; exit 2; }

HEADING_RE='^(#{1,6}[[:space:]]+|\*\*).*'"$PATTERN"
START_LINE="$(grep -niE "$HEADING_RE" "$PLAN" | head -1 | cut -d: -f1 || true)"

if [[ -z "$START_LINE" ]]; then
  echo "[]"
  exit 0
fi

BT="$(printf '\140')"   # literal backtick, built via octal (avoids SC2016 noise)
# Terminator (#109 round-2 review finding): NOT the same pattern HEADING_RE uses
# to find the START line. That pattern intentionally matches ANY line beginning
# with `**` — fine for a document-wide "does this heading exist" grep (mirrors
# plan-lint.sh's section_present(), which only ever uses it that way). Reused
# unchanged here as a BODY terminator it over-matched: this repo's own plans
# routinely put bold-LEAD prose inside a section body (e.g. "**Note:** ..." or
# "**D-1.** ..."), which is not a section boundary, so the terminator wrongly
# ended the slice there and silently dropped every path token after it. The
# terminator below only ends the section on a REAL markdown heading
# (`#{1,6} ...`) or a STANDALONE bold-line header — the whole trimmed line is
# exactly `**...**`, not prose that merely starts with `**`.
SECTION_BODY="$(awk -v start="$START_LINE" '
  NR == start { in_section=1; next }
  in_section && (/^#{1,6}[[:space:]]/ || /^\*\*[^*]+\*\*[[:space:]]*$/) { exit }
  in_section { print }
' "$PLAN")"

# The trailing `|| true` is load-bearing under `set -euo pipefail`: a grep stage
# that matches zero lines exits 1 (no match), which pipefail would otherwise
# propagate as this script's exit status and `set -e` would abort the script —
# but zero matches is a legitimate outcome here (empty section / no path
# tokens), not an error. Every stage still runs to completion regardless (a pipe
# does not short-circuit on an upstream non-zero exit, only its REPORTED status
# does), so `jq -s .` always emits a well-formed `[]` in that case.
printf '%s\n' "$SECTION_BODY" \
  | grep -oE "${BT}[A-Za-z0-9_./-]+${BT}" \
  | tr -d "\`" \
  | grep -E '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_-]+\.[A-Za-z0-9_.]+$' \
  | sort -u \
  | jq -R 'select(length > 0)' \
  | jq -s . \
  || true
