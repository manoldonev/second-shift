#!/usr/bin/env bash
# prose-budget.sh — instruction-layer bloat ratchet (L2 of the agentic-stack debloat, #188).
#
# The instruction layer — markdown under a repo's skills/ + agents/ trees — is loaded as
# context. This tool makes "without the bloat" measurable: it records each file's size
# against a committed baseline ceiling and fails when a file grows past it, and it flags
# narrative `#NNN` incident archaeology that crept into operational prose.
#
# Mirrors the statectl drift-check posture (committed baseline + mechanical check).
# Wired into pipeline-doctor.sh; exit code = number of FAILED checks (0 = clean).
#
# LAYOUTS. Two are supported, additively — a repo may use either or both:
#   consumer     .claude/skills, .claude/agents
#   plugin repo  plugins/*/skills, plugins/*/agents
# A de-vendored marketplace consumer has NEITHER (its instruction layer lives in the
# plugin cache, not the repo). That is a legitimate steady state, so the three coverage
# outcomes are distinguished — this is the whole point of the gate:
#   n/a       no root exists on disk        -> reported, exit 0. NOT a failure.
#   vacuous   a root exists, 0 files match  -> FAIL. The gate would otherwise be measuring
#                                              nothing while reporting green.
#   measured  roots + files                 -> normal ratchet.
#
# BASELINE. Resolved repo-local first (<repo>/.claude/prose-budget.baseline.tsv), else the
# neutral header-only stub shipped beside this script. `--update-baseline` always writes the
# repo-local path — never the plugin copy, which for an installed plugin is a read-only cache
# and whose contents would otherwise be inherited by every other consumer.
#
# Usage:
#   prose-budget.sh                 # check current sizes against baseline (default)
#   prose-budget.sh --report        # human table only, no pass/fail
#   prose-budget.sh --update-baseline   # write <repo>/.claude/prose-budget.baseline.tsv
#
# Tunables (env):
#   PROSE_TOLERANCE_PCT          allowed growth over baseline before FAIL (default 5)
#   PROSE_ROOTS                  space-separated scan roots, overriding discovery
#   PROSE_ALLOW_EMPTY_BASELINE   permit --update-baseline to write an empty baseline
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[prose-budget] not in a git repo" >&2; exit 2; }
cd "$REPO" || exit 2

# Repo-local baseline wins; the shipped stub is the fallback. Resolution order matters:
# a repo that has authored its own baseline gets staleness checks, a repo falling back to
# the stub does not (the stub describes no repo, so unresolved rows there mean nothing).
REPO_BASELINE="$REPO/.claude/prose-budget.baseline.tsv"
STUB_BASELINE="$SCRIPT_DIR/prose-budget.baseline.tsv"
if [[ -f "$REPO_BASELINE" ]]; then
  BASELINE="$REPO_BASELINE"; BASELINE_IS_LOCAL=1
else
  BASELINE="$STUB_BASELINE"; BASELINE_IS_LOCAL=0
fi

TOL="${PROSE_TOLERANCE_PCT:-5}"
MODE="check"
case "${1:-}" in
  --update-baseline) MODE="update" ;;
  --report) MODE="report" ;;
  --check|"") MODE="check" ;;
  *) echo "[prose-budget] unknown arg: $1" >&2; exit 2 ;;
esac

# Instruction-layer scan roots that actually exist on disk. Emitting only existing dirs is
# what lets the caller tell "no instruction layer" (n/a) apart from "a root matched nothing"
# (vacuous) — `find` on a missing dir cannot make that distinction.
prose_roots() {
  if [[ -n "${PROSE_ROOTS:-}" ]]; then
    # shellcheck disable=SC2086  # deliberate word-splitting: PROSE_ROOTS is space-separated
    for d in $PROSE_ROOTS; do [[ -d "$d" ]] && printf '%s\n' "$d"; done
    return
  fi
  for d in .claude/skills .claude/agents plugins/*/skills plugins/*/agents; do
    [[ -d "$d" ]] && printf '%s\n' "$d"
  done
}

# Tracked instruction-layer files: markdown under the discovered roots, excluding
# `*-fixtures/` trees. Fixture markdown is lint/selftest INPUT DATA, never context-loaded
# prose — ratcheting it would fail the budget for editing a test fixture.
tracked_files() {
  local roots
  roots="$(prose_roots | tr '\n' ' ')"
  [[ -n "${roots// /}" ]] || return 0
  # shellcheck disable=SC2086  # deliberate word-splitting: roots is a space-separated dir list
  find $roots -type f -name '*.md' 2>/dev/null \
    | grep -v -- '-fixtures/' \
    | LC_ALL=C sort
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
  # Refuse to snapshot nothing. Writing an empty baseline is exactly how a gate ends up
  # measuring nothing while reporting green — regenerating against roots that resolve to
  # no files would cement the very failure this tool exists to catch.
  if [[ -z "$(tracked_files)" && -z "${PROSE_ALLOW_EMPTY_BASELINE:-}" ]]; then
    echo "[prose-budget] refusing to write an empty baseline — 0 files matched." >&2
    echo "[prose-budget]   roots searched: $(prose_roots | tr '\n' ' ')" >&2
    echo "[prose-budget]   fix the scan roots (or set PROSE_ALLOW_EMPTY_BASELINE=1 if the repo genuinely has no instruction layer)." >&2
    exit 2
  fi
  mkdir -p "$(dirname "$REPO_BASELINE")"
  {
    echo -e "# path\twords\tchars\tnarrative_nnn   (regenerate with: prose-budget.sh --update-baseline)"
    while IFS= read -r f; do
      printf '%s\t%s\t%s\t%s\n' "$f" "$(words_of "$f")" "$(chars_of "$f")" "$(narrative_nnn "$f")"
    done < <(tracked_files)
  } > "$REPO_BASELINE"
  echo "[prose-budget] baseline written: $REPO_BASELINE ($(grep -vc '^#' "$REPO_BASELINE") files)"
  exit 0
fi

# Baseline lookup. macOS ships bash 3.2 (no associative arrays) and pipeline
# scripts must stay 3.2-compatible — so look the baseline up per-file with awk
# (below) instead of building a path→words map.
have_baseline=0; [[ -f "$BASELINE" ]] && have_baseline=1

fails=0; warns=0; total_words=0; total_nnn=0; tracked=0
ROOTS="$(prose_roots | tr '\n' ' ')"

printf '%-58s %7s %8s %6s  %s\n' "file" "words" "~tokens" "#NNN" "vs baseline"
printf '%-58s %7s %8s %6s  %s\n' "----" "-----" "-------" "----" "-----------"
while IFS= read -r f; do
  tracked=$(( tracked + 1 ))
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

# --- Coverage verdict: n/a vs vacuous vs measured -----------------------------
# The distinction this whole tool turns on. Reporting green while inspecting nothing is
# indistinguishable from success; failing in a repo that legitimately has no instruction
# layer is an unremediable false red. Both are wrong, so they get different outcomes.
if (( tracked == 0 )); then
  if [[ -z "${ROOTS// /}" ]]; then
    echo "[prose-budget] n/a — no instruction layer in this repo (no skills/ or agents/ root found)."
    echo "[prose-budget]   Nothing to measure; this is the expected state for a repo whose skills and agents come from the plugin cache."
    [[ "$MODE" == "report" ]] && exit 0
    echo "[prose-budget] 0 fail(s), 0 warning(s)  (coverage: n/a)"
    exit 0
  fi
  echo "[prose-budget] FAIL vacuous coverage: instruction-layer root(s) exist but matched 0 markdown files."
  echo "[prose-budget]   roots searched: $ROOTS"
  echo "[prose-budget]   The gate inspected nothing — a green here would be meaningless."
  fails=$(( fails + 1 ))
fi

# --- Baseline staleness -------------------------------------------------------
# Scoped to a REPO-LOCAL baseline. The shipped stub describes no particular repo, so an
# unresolved row there carries no signal — checking it would fail every consumer that
# never ran --update-baseline.
if (( have_baseline )) && (( BASELINE_IS_LOCAL )); then
  rows=0; stale=0
  while IFS=$'\t' read -r p _rest; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    rows=$(( rows + 1 ))
    if [[ ! -f "$p" ]]; then
      stale=$(( stale + 1 ))
      echo "[prose-budget] stale baseline row (path no longer exists): $p"
    fi
  done < "$BASELINE"
  if (( rows > 0 && stale == rows && tracked > 0 )); then
    # Every row describes a layout that no longer exists, yet files WERE found — the
    # baseline is measuring a different repo shape than the one on disk.
    echo "[prose-budget] FAIL stale baseline: all $rows row(s) unresolvable while $tracked file(s) were tracked."
    echo "[prose-budget]   Regenerate with: prose-budget.sh --update-baseline"
    fails=$(( fails + 1 ))
  elif (( stale > 0 )); then
    echo "[prose-budget] $stale of $rows baseline row(s) no longer resolve — consider --update-baseline"
    warns=$(( warns + stale ))
  fi
elif (( tracked > 0 )) && (( ! BASELINE_IS_LOCAL )); then
  echo "[prose-budget] note: no repo-local baseline — every file reports NEW. Snapshot one with: prose-budget.sh --update-baseline"
fi

[[ "$MODE" == "report" ]] && exit 0
echo "[prose-budget] $fails fail(s), $warns warning(s)  (tolerance +${TOL}% over baseline)"
exit "$fails"
