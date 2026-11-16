#!/usr/bin/env bash
# check-no-archeology.sh — fails on an issue number (#123), an AC id (AC-1) or a decision id (D-1)
# in a shell, mjs or python file, a workflow file or a top-level docs/*.md.
#
# A line that carries one is a hit. A file with hits must have a row in
# scripts/no-archeology-baseline.tsv:
#
#   path <TAB> allowed hits <TAB> class <TAB> why
#
#   data      the ids are test data or a format the tool documents, and stay
#   debt      ids still to be swept
#   open-pr   ids still to be swept, in a file an open pull request was changing when the row was written
#
# A file over its count fails, and so does a row whose file has no hits left, so a count only goes
# down. A file under its count passes and the summary says the row can be lowered.
#
# Sample record data is not a hit. These shapes are the ones ledger-lint.sh, plan-coverage.sh and
# verdict-check.sh parse, at the start of a line, of a quoted string or after a literal \n:
#
#   | D-1 | … |          a table row whose first cell is a D, OR, S, RS, PM or F id, to the end of the row
#   AC-1: …   - AC-1      an acceptance-criterion line
#   ACs: AC-1 AC-2        the id list
#
# and anywhere in a line: an [AC-1] tag and `decided (D-1)`. A line that calls ok, bad, pass or fail
# with a string is a test title and is read whole, so an id in a title is a hit whatever its shape.
#
# The patterns cannot tell `#333` the color from `#333` the issue, or an ordinal `#2` from a ticket:
# those are `data` rows or get reworded. Tracker keys of other shapes, and an origin story that names
# no id, are not read.
#
# Usage:
#   check-no-archeology.sh [--list] [repo-root]     (default root: the repo above scripts/)
#   --list   print every hit (file:line:text) and exit 0. Checks nothing.
#
# Exit code = number of violations, capped at 100; 0 = clean.
set -uo pipefail

LIST_ONLY=0
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    -h|--help) sed -n '2,/^# Exit code = number of violations/p' "$0"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$HERE/.." && pwd)}"

BASELINE_REL="scripts/no-archeology-baseline.tsv"
BASELINE="$ROOT/$BASELINE_REL"

SCOPE='\.(sh|mjs|py)$|^\.github/workflows/[^/]+$|^docs/[^/]+\.md$'
# `{` and `$` before the hash are bash's ${#1} and $#, `&` is an HTML entity; a letter after the
# digits is a hex color.
HIT='(^|[^[:alnum:]&{$])#[0-9]+([^[:alnum:]]|$)|(^|[^[:alnum:]])AC-[0-9]+|(^|[^[:alnum:]-])D-[0-9]+'

violations=0
fail() { echo "[no-archeology] ✗ $1" >&2; violations=$((violations + 1)); }

# Tracked files only in a work tree: CI grades a clean checkout. A tracked list that cannot be read
# is a violation, never an empty list, which would grade nothing and pass.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES="$(cd "$ROOT" && git ls-files)" || fail "cannot list tracked files under $ROOT"
else
  FILES="$(cd "$ROOT" && find . -type f -not -path './.git/*' -not -path '*/node_modules/*' | sed 's#^\./##')"
fi
FILES="$(printf '%s\n' "$FILES" | grep -E -- "$SCOPE" | LC_ALL=C sort)"

if [[ -z "$FILES" ]]; then
  fail "no file in scope under $ROOT — nothing was checked"
  exit "$violations"
fi

# hits <list|count> — `file:line:text` per hit, or `path<TAB>hits` per file with at least one.
# grep narrows to text files that carry an id at all (-I skips a binary file whatever its name);
# awk then drops the sample-data shapes before it tests a line. \047 is a single quote.
hits() {
  local cand
  cand="$(cd "$ROOT" && printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -IlE -- "$HIT" /dev/null)"
  [[ -n "$cand" ]] || return 0
  # shellcheck disable=SC2016
  (cd "$ROOT" && printf '%s\n' "$cand" | tr '\n' '\0' | NA_HIT="$HIT" NA_MODE="$1" xargs -0 awk '
    BEGIN { hit = ENVIRON["NA_HIT"]; list = (ENVIRON["NA_MODE"] == "list") }
    FNR == 1 && prev != "" && !list && n > 0 { print prev "\t" n }
    FNR == 1 { prev = FILENAME; n = 0 }
    {
      t = $0
      if (t !~ /(^|[^[:alnum:]_-])(ok|bad|pass|fail)[ \t]+["\047]/) {
        gsub(/(^|["\047]|\\n)[ \t]*\|[ \t]*(D|OR|S|RS|PM|F)-[0-9]+[ \t]*\|[^"\047\\]*/, " ", t)
        gsub(/(^|["\047]|\\n)[ \t]*(- AC-[0-9]+|AC-[0-9]+:)/, " ", t)
        gsub(/ACs:([ \t]+AC-[0-9]+)+/, " ", t)
        gsub(/\[AC-[0-9]+\]/, " ", t)
        gsub(/decided[ \t]*\(D-[0-9]+\)/, " ", t)
      }
      if (t ~ hit) { if (list) print FILENAME ":" FNR ":" $0; else n++ }
    }
    END { if (!list && n > 0) print prev "\t" n }')
}

if [[ $LIST_ONLY -eq 1 ]]; then
  hits list
  exit 0
fi

COUNTS="$(hits count)"

if [[ ! -f "$BASELINE" ]]; then
  fail "the baseline is missing: $BASELINE_REL"
  exit "$violations"
fi

REPORT="$(NA_COUNTS="$COUNTS" awk -F'\t' '
  BEGIN {
    n = split(ENVIRON["NA_COUNTS"], rows, "\n")
    for (i = 1; i <= n; i++) { if (split(rows[i], f, "\t") == 2) { hits[f[1]] = f[2]; order[++m] = f[1] } }
  }
  /^#/ || /^[[:space:]]*$/ { next }
  {
    path = $1
    if (NF < 4 || $4 == "") { print "FAIL\t" path ": malformed row (need path, count, class, why — tab-separated)"; next }
    if ($2 !~ /^[0-9]+$/ || $2 == 0) { print "FAIL\t" path ": the count must be a positive number, got \"" $2 "\""; next }
    if ($3 != "data" && $3 != "debt" && $3 != "open-pr") { print "FAIL\t" path ": unknown class \"" $3 "\" (data | debt | open-pr)"; next }
    if (path in allowed) { print "FAIL\t" path ": listed twice"; next }
    allowed[path] = $2; nrows++
    if (!(path in hits)) { print "FAIL\t" path ": STALE — the row allows " $2 " hit(s) and the file has none. Delete the row."; next }
    if (hits[path] < $2) { print "NOTE\t" path ": " hits[path] " hit(s), the row allows " $2 " — lower it" }
  }
  END {
    for (i = 1; i <= m; i++) {
      p = order[i]
      if (!(p in allowed)) { print "FAIL\t" p ": " hits[p] " line(s) carry an issue number, AC id or decision id. Remove them: the PR body is the one link to the ticket." }
      else if (hits[p] > allowed[p]) { print "FAIL\t" p ": " hits[p] " hit(s), the baseline allows " allowed[p] ". Remove the new id; the count only goes down." }
      if (p in allowed) { left += hits[p] }
    }
    print "SUM\t" nrows + 0 "\t" left + 0
  }' "$BASELINE")"

sum_files=0; sum_hits=0
while IFS=$'\t' read -r kind a b; do
  case "$kind" in
    FAIL) fail "$a" ;;
    NOTE) echo "[no-archeology] note: $a" ;;
    SUM)  sum_files="$a"; sum_hits="$b" ;;
  esac
done <<<"$REPORT"

if [[ $violations -eq 0 ]]; then
  echo "[no-archeology] ✓ $(printf '%s\n' "$FILES" | grep -c .) file(s) checked; $sum_hits hit(s) allowed across $sum_files baseline file(s)."
else
  echo "[no-archeology] list the lines with: bash scripts/check-no-archeology.sh --list" >&2
fi
[[ $violations -gt 100 ]] && violations=100
exit "$violations"
