#!/usr/bin/env bash
# check-fail-open-shapes.sh — repo-wide guard against constructs where a FAILED call is
# indistinguishable from a genuine NEGATIVE result.
#
# WHY THIS EXISTS: `producer | grep -q P` has two outcomes where the world has three. A dead
# producer leaves grep an empty stream, which reports "no match"; under `pipefail` the dead
# producer also makes the pipeline non-zero, which reads as "no match" again. The caller learns
# "no", and "no" is not what happened. The sanctioned replacement is `checked_match`
# (plugins/dev-pipeline/skills/run/tools/checked-call.sh), whose rc 2 means UNKNOWN.
#
# WHY A GUARD AND NOT A CONVENTION: two of the three worst instances on record were never in a
# file at all — a session typed them into a shell. A lint cannot see those, and pretending
# otherwise would be the point of this comment. What it CAN do is name the shape and bind it
# everywhere the shape is visible, so the rule exists as code for anyone to check against
# instead of as prose nobody reads.
#
# THE DENOMINATOR IS THIS SCRIPT'S OWN OUTPUT. Three independent measurements of "the sites"
# once disagreed (17 / 18 / 26) purely on scoping, which makes any completeness claim against a
# COUNT unfalsifiable. So `--list` prints the enumeration, that output IS the denominator by
# definition, and every row of it must be dispositioned in fail-open-sites.tsv. Neither half can
# rot quietly: an unclassified site reds, and a row whose anchor matches nothing reds as drift.
#
# Legs (each with a declared scope and check direction) — deliberately only the ones a substring
# check can honestly decide, the stack-generality-lint.sh posture:
#
#   pipeline       every command-producer `| grep -q` site is dispositioned in the TSV.
#                  VARIABLE producers (`printf … | grep -q`) are excluded: #522 already
#                  converted that shape wholesale, and its hazard is SIGPIPE, not fail-open.
#   tsv-integrity  every TSV row resolves — known disposition, anchor still present in its
#                  file, and (for anything but `converted`) still covering a live site.
#   pgrep-count    `pgrep -c` / `pgrep -fc` is banned outright. The counting form exits 1 on
#                  "no match", which is what invites the `|| echo 0` fabrication that reported
#                  "0 competitors" while 33 processes were live. The repo's one legitimate
#                  pgrep uses the sanctioned `pgrep -f … | wc -l`.
#
# NOT a leg, on purpose: `$(… || echo <default>)` generally. Measured over this tree it matches
# 51 files, nearly all of them the `$(cond && echo a || echo b)` ternary or a `jq … || echo
# <config default>` — legitimate, and a guard that reds on them would be baselined away within a
# week. `pgrep-count` is the honestly-decidable slice of that family.
#
# Usage:
#   check-fail-open-shapes.sh [--list] [repo-root]     (default root: the repo above scripts/)
#   --list   print the denominator (file<TAB>line<TAB>text) and exit 0. Checks nothing.
#
# Exit code = number of violations (doctor convention); 0 = clean.
set -uo pipefail

LIST_ONLY=0
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    # Range-free: print the header comment up to (and not past) its last line, so an edit to
    # the prose above cannot silently start leaking `set -uo pipefail` into --help.
    -h|--help) sed -n '2,/^# Exit code = number of violations/p' "$0"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$HERE/.." && pwd)}"

TSV_REL="scripts/fail-open-sites.tsv"
TSV="$ROOT/$TSV_REL"

# This script and its selftest carry the banned shapes as data — a guard that scanned its own
# pattern definitions could never be clean. Named explicitly rather than pruned by directory,
# so nothing else in scripts/ gets a free pass.
SELF_EXCLUDE='scripts/check-fail-open-shapes\.sh|scripts/check-fail-open-shapes-selftest\.sh'
# Two data exclusions, both for the same reason — the file is never executed, so a shape in it
# is quoted shell, not a call site:
#   docs/plans/   the run-artifact archive: frozen specs and verdict records.
#   *.tsv         every table in this repo, and pointedly tools/mutation-*.tsv, which is a
#                 CORPUS OF DELIBERATELY BROKEN SHELL. Scanning it for banned shapes is a
#                 category error: a catalog row whose whole job is to describe reintroducing
#                 one would red the guard for saying so.
# Both arms match against `relpath:line:text`, which is why the .tsv arm anchors on the path
# separator rather than on `$` — end-of-line here is the end of the matched TEXT.
SCAN_EXCLUDE="^(docs/plans/|$SELF_EXCLUDE)|^[^:]*\\.tsv:"

# A pipe (never `||`) into a grep whose option cluster contains `q`. Covers -q, -qi, -qiE,
# -Eq, -Fxq, -qxF.
PIPE_GREPQ='(^|[^|])\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q[A-Za-z]*'
# The producer shape #522 already owns: a VARIABLE piped through printf/echo.
VAR_PRODUCER='(printf|echo)[^|]*\|[[:space:]]*grep'

violations=0
fail() { echo "[fail-open] ✗ $1" >&2; violations=$((violations + 1)); }

# enumerate — the recipe. Prints `relpath<TAB>lineno<TAB>text`, one live site per line.
enumerate() {
  grep -rnE --binary-files=without-match \
      --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=__pycache__ \
      -- "$PIPE_GREPQ" "$ROOT" 2>/dev/null \
    | sed -e "s#^$ROOT/##" \
    | grep -vE "$SCAN_EXCLUDE" \
    | grep -vE "$VAR_PRODUCER" \
    | sed -E "s#^([^:]+):([0-9]+):#\\1$(printf '\t')\\2$(printf '\t')#" \
    | LC_ALL=C sort -t"$(printf '\t')" -k1,1 -k2,2n
}

SITES="$(enumerate)"

if [[ $LIST_ONLY -eq 1 ]]; then
  [[ -n "$SITES" ]] && printf '%s\n' "$SITES"
  exit 0
fi

# ---- leg: pipeline + tsv-integrity -------------------------------------------

if [[ ! -f "$TSV" ]]; then
  fail "the disposition table is missing: $TSV_REL — the denominator has nothing to be checked against"
else
  # Rows: file <TAB> disposition <TAB> anchor <TAB> why
  COVERED_ROWS="$(mktemp "${TMPDIR:-/tmp}/fail-open-rows.XXXXXX")"
  trap 'rm -f "$COVERED_ROWS"' EXIT

  while IFS=$'\t' read -r rfile rdisp ranchor rwhy; do
    case "${rfile:-}" in ''|'#'*) continue ;; esac
    if [[ -z "${rdisp:-}" || -z "${ranchor:-}" || -z "${rwhy:-}" ]]; then
      fail "malformed row (need 4 tab-separated fields): ${rfile}"
      continue
    fi
    case "$rdisp" in
      converted|safe|out-of-scope|not-a-site) : ;;
      *) fail "$rfile: unknown disposition '$rdisp' (converted | safe | out-of-scope | not-a-site)"; continue ;;
    esac
    if [[ ! -f "$ROOT/$rfile" ]]; then
      fail "$rfile: dispositioned file does not exist — the row is stale"
      continue
    fi
    if ! grep -qF -- "$ranchor" "$ROOT/$rfile"; then
      fail "$rfile: ANCHOR DRIFT — '$ranchor' no longer appears in the file. Re-anchor the row (or drop it if the site is gone); an anchor that matches nothing disposes of nothing."
      continue
    fi
    # Which enumerated sites does this row claim? Through ENVIRON, never `awk -v`: -v
    # interprets backslash escapes, and anchors quote shell regexes full of them — `\$`
    # would silently become `$` and the row would match nothing while reading as a typo.
    hits="$(FO_F="$rfile" FO_A="$ranchor" awk -F'\t' \
              '$1 == ENVIRON["FO_F"] && index($3, ENVIRON["FO_A"]) > 0 { c++ } END { print c + 0 }' <<<"$SITES")"
    if [[ "$rdisp" == "converted" ]]; then
      if [[ "$hits" -gt 0 ]]; then
        fail "$rfile: row is marked 'converted' but its anchor still covers a live \`| grep -q\` site — the conversion was reverted, or the anchor points at the wrong line"
      fi
    elif [[ "$hits" -eq 0 ]]; then
      fail "$rfile: row disposes of '$ranchor' as '$rdisp', but the enumeration finds no such site — the row outlived what it excused. Drop it, or mark it 'converted'."
    fi
    printf '%s\t%s\n' "$rfile" "$ranchor" >> "$COVERED_ROWS"
  done < "$TSV"

  # Every enumerated site must be claimed by some non-converted row.
  while IFS=$'\t' read -r sfile sline stext; do
    [[ -n "${sfile:-}" ]] || continue
    if ! FO_F="$sfile" FO_T="$stext" awk -F'\t' \
           '$1 == ENVIRON["FO_F"] && index(ENVIRON["FO_T"], $2) > 0 { found = 1 } END { exit found ? 0 : 1 }' \
           "$COVERED_ROWS"; then
      fail "$sfile:$sline UNCLASSIFIED command-producer \`| grep -q\` — a dead producer here is indistinguishable from a genuine no. Convert it to checked_match, or add a row to $TSV_REL saying why it is safe:
      $(printf '%s' "$stext" | sed -e 's/^[[:space:]]*//')"
    fi
  done <<<"$SITES"
fi

# ---- leg: pgrep-count --------------------------------------------------------

pg="$(grep -rnE --binary-files=without-match \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=__pycache__ \
        -- 'pgrep[[:space:]]+-[A-Za-z]*c' "$ROOT" 2>/dev/null \
      | sed -e "s#^$ROOT/##" | grep -vE "$SCAN_EXCLUDE")"
if [[ -n "$pg" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    fail "the counting \`pgrep -c\` form exits 1 on 'no match', which is what invites a \`|| echo 0\` that reports zero while processes are live. Use \`pgrep -f … | wc -l\`: $line"
  done <<<"$pg"
fi

# ---- verdict -----------------------------------------------------------------

if [[ $violations -eq 0 ]]; then
  n="$(printf '%s' "$SITES" | grep -c . || true)"
  echo "[fail-open] ✓ $n enumerated site(s), all dispositioned; no banned shapes."
fi
exit "$violations"
