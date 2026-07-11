#!/usr/bin/env bash
# prose-budget.sh — instruction-layer bloat ratchet (L2 of the agentic-stack debloat, #188).
#
# The instruction layer (.claude/skills/**/*.md + .claude/agents/*.md) is loaded as
# context. This tool makes "without the bloat" measurable: it records each file's size
# against a committed baseline ceiling and fails when a file grows past it, and it flags
# narrative `#NNN` incident archaeology that crept into operational prose.
#
# Mirrors the statectl drift-check posture (committed baseline + mechanical check).
# Wired into pipeline-doctor.sh; exit code = number of FAILED checks (0 = clean).
#
# Usage:
#   prose-budget.sh                 # check current sizes against baseline (default)
#   prose-budget.sh --report        # human table only, no pass/fail
#   prose-budget.sh --update-baseline   # rewrite the committed baseline from current sizes
#
# Tunables (env):
#   PROSE_TOLERANCE_PCT   allowed growth over baseline before FAIL (default 5)
set -uo pipefail

# The committed baseline ships alongside this script (in the plugin), so locate it
# script-relative — it is NOT under the consumer repo the tracked files are scanned from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="$SCRIPT_DIR/prose-budget.baseline.tsv"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[prose-budget] not in a git repo" >&2; exit 2; }
cd "$REPO" || exit 2
TOL="${PROSE_TOLERANCE_PCT:-5}"
MODE="check"
case "${1:-}" in
  --update-baseline) MODE="update" ;;
  --report) MODE="report" ;;
  --check|"") MODE="check" ;;
  *) echo "[prose-budget] unknown arg: $1" >&2; exit 2 ;;
esac

# Tracked instruction-layer files: all markdown under skills/ + agents/.
tracked_files() {
  find .claude/skills .claude/agents -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
}

# Narrative-#NNN gate: count `#<2-4 digits>` references in operational prose, EXCLUDING
#   - fenced code blocks (``` ... ```) — PR/issue-body templates and examples live there
#   - functional template tokens `#{...}` (e.g. `#{ISSUE}`)
# Reports a count; archaeology belongs in git history, not loaded context.
narrative_nnn() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence { next }
    {
      line = $0
      gsub(/#\{[^}]*\}/, "", line)            # drop functional templates #{...}
      n = gsub(/#[0-9][0-9][0-9]?[0-9]?/, "&", line)
      total += n
    }
    END { print total + 0 }
  ' "$1"
}

words_of() { wc -w < "$1" | tr -d ' '; }
chars_of() { wc -m < "$1" | tr -d ' '; }

if [[ "$MODE" == "update" ]]; then
  {
    echo -e "# path\twords\tchars\tnarrative_nnn   (regenerate with: prose-budget.sh --update-baseline)"
    while IFS= read -r f; do
      printf '%s\t%s\t%s\t%s\n' "$f" "$(words_of "$f")" "$(chars_of "$f")" "$(narrative_nnn "$f")"
    done < <(tracked_files)
  } > "$BASELINE"
  echo "[prose-budget] baseline written: $BASELINE ($(grep -vc '^#' "$BASELINE") files)"
  exit 0
fi

# Baseline lookup. macOS ships bash 3.2 (no associative arrays) and pipeline
# scripts must stay 3.2-compatible — so look the baseline up per-file with awk
# (below) instead of building a path→words map.
have_baseline=0; [[ -f "$BASELINE" ]] && have_baseline=1

fails=0; warns=0; total_words=0; total_nnn=0
printf '%-58s %7s %8s %6s  %s\n' "file" "words" "~tokens" "#NNN" "vs baseline"
printf '%-58s %7s %8s %6s  %s\n' "----" "-----" "-------" "----" "-----------"
while IFS= read -r f; do
  w=$(words_of "$f"); c=$(chars_of "$f"); nnn=$(narrative_nnn "$f")
  tok=$(( c / 4 ))
  total_words=$(( total_words + w )); total_nnn=$(( total_nnn + nnn ))
  status="-"
  base=""
  (( have_baseline )) && base=$(awk -F'\t' -v p="$f" '$1==p {print $2; exit}' "$BASELINE")
  if [[ -z "$base" ]]; then
    status="NEW (add to baseline)"; warns=$(( warns + 1 ))
  else
    ceiling=$(( base + base * TOL / 100 ))
    if (( w > ceiling )); then
      status="FAIL grew $base->$w (>+${TOL}%)"; fails=$(( fails + 1 ))
    elif (( w < base )); then
      status="ok shrank $base->$w"
    else
      status="ok"
    fi
  fi
  flag=""; (( nnn > 0 )) && flag=" [#NNN]" && warns=$(( warns + 1 ))
  printf '%-58s %7s %8s %6s  %s%s\n' "${f#.claude/}" "$w" "$tok" "$nnn" "$status" "$flag"
done < <(tracked_files)

echo "----"
printf 'TOTAL  %s words (~%s tokens)   narrative #NNN: %s\n' "$total_words" "$(( total_words * 4 / 3 ))" "$total_nnn"
[[ "$MODE" == "report" ]] && exit 0
echo "[prose-budget] $fails fail(s), $warns warning(s)  (tolerance +${TOL}% over baseline)"
exit "$fails"
