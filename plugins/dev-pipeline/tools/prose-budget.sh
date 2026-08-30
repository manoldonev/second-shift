#!/usr/bin/env bash
# prose-budget.sh — narrative-bloat judgment for the instruction layer (L2 of the
# agentic-stack debloat, #188; reshaped by #641).
#
# The instruction layer — markdown under a repo's skills/ + agents/ trees — is loaded as
# context. This tool reports its size and flags narrative `#NNN` incident archaeology that
# crept into operational prose. Wired into pipeline-doctor.sh; exit code = number of FAILED
# checks (0 = clean).
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
#   measured  roots + files                 -> per-file report, no ratchet.
#
# #641 — NO COMMITTED BASELINE, on either axis. Two hand-maintained TSVs used to live here:
# `.claude/prose-budget.baseline.tsv` (a per-file word-count ceiling) and
# `.claude/prose-budget-shell.baseline.tsv` (a per-file shell comment-density ceiling). Both
# were measurement registers — a row recording a number the tree can compute — and both are
# deleted, per docs/pipeline-manifesto.md's P4/P5 posture: a register's rows must be
# judgments, not measurements.
#   - The SHELL half's #641 successor script was itself deleted outright by #719 — a
#     symptom-level ratchet, not a control, per docs/pipeline-manifesto.md's P4/P5 posture.
#     This tool no longer measures shell files at all, and nothing replaces the check.
#   - The MARKDOWN half keeps exactly one judgment, unchanged: the narrative `#NNN` flag.
#     Whether an incident reference belongs in loaded context is a human call, not a
#     measurement, so it stays — reported live from the file's own content, no baseline
#     needed to check it against. What is gone is the per-file word-count-vs-baseline growth
#     ratchet; what replaces it is the TOTAL line already printed below, a derived total with
#     nothing committed behind it.
#
# `--update-baseline` is accepted for any script still wired to call it and is a no-op: there
# is nothing left to snapshot.
#
# Usage:
#   prose-budget.sh                 # report + narrative-#NNN check (default)
#   prose-budget.sh --report        # human table only, no pass/fail
#   prose-budget.sh --update-baseline   # no-op (#641); kept so an existing caller does not break
set -uo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[prose-budget] not in a git repo" >&2; exit 2; }
cd "$REPO" || exit 2

MODE="check"
case "${1:-}" in
  --update-baseline) MODE="update" ;;
  --report) MODE="report" ;;
  --check|"") MODE="check" ;;
  *) echo "[prose-budget] unknown arg: $1" >&2; exit 2 ;;
esac

if [[ "$MODE" == "update" ]]; then
  echo "[prose-budget] --update-baseline is a no-op (#641): there is no committed baseline to snapshot any more."
  exit 0
fi

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

fails=0; warns=0; total_words=0; total_nnn=0; tracked=0
ROOTS="$(prose_roots | tr '\n' ' ')"

printf '%-58s %7s %8s %6s  %s\n' "file" "words" "~tokens" "#NNN" "narrative"
printf '%-58s %7s %8s %6s  %s\n' "----" "-----" "-------" "----" "---------"
while IFS= read -r f; do
  tracked=$(( tracked + 1 ))
  w=$(words_of "$f"); c=$(chars_of "$f"); nnn=$(narrative_nnn "$f")
  tok=$(( c / 4 ))
  total_words=$(( total_words + w )); total_nnn=$(( total_nnn + nnn ))
  flag="-"
  if (( nnn > 0 )); then
    flag="[#NNN] $nnn narrative reference(s)"; warns=$(( warns + 1 ))
  fi
  printf '%-58s %7s %8s %6s  %s\n' "$f" "$w" "$tok" "$nnn" "$flag"
done < <(tracked_files)

echo "----"
printf 'TOTAL  %s words (~%s tokens)   narrative #NNN: %s\n' "$total_words" "$(( total_words * 4 / 3 ))" "$total_nnn"

# --- Coverage verdict: n/a vs vacuous vs measured -----------------------------
# The distinction this whole tool turns on. Reporting green while inspecting nothing is
# indistinguishable from success; failing in a repo that legitimately has no instruction
# layer is an unremediable false red. Both are wrong, so they get different outcomes.
MD_COVERAGE="measured"
if (( tracked == 0 )); then
  if [[ -z "${ROOTS// /}" ]]; then
    MD_COVERAGE="n/a"
    echo "[prose-budget] n/a — no instruction layer in this repo (no skills/ or agents/ root found)."
    echo "[prose-budget]   Nothing to measure; this is the expected state for a repo whose skills and agents come from the plugin cache."
  else
    MD_COVERAGE="vacuous"
    echo "[prose-budget] FAIL vacuous coverage: instruction-layer root(s) exist but matched 0 markdown files."
    echo "[prose-budget]   roots searched: $ROOTS"
    echo "[prose-budget]   The gate inspected nothing — a green here would be meaningless."
    fails=$(( fails + 1 ))
  fi
fi

[[ "$MODE" == "report" ]] && exit 0
# ONE combined last line, and it stays last: pipeline-doctor.sh reads the OK message with
# `tail -1`, so splitting this per path would silently drop half of what an operator has been
# reading since #188.
echo "[prose-budget] $fails fail(s), $warns warning(s)  (coverage: md $MD_COVERAGE; narrative #NNN is a judgment call, never a ratchet — see docs/pipeline-manifesto.md's P4/P5 posture)"
exit "$fails"
