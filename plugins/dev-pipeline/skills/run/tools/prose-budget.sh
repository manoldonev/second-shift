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
# SHELL PATH (#552). The markdown ratchet above left the lane's own shell guards unwatched, and
# those are majority prose: three of them carry 45-60% comment lines. The shell path measures
# comment DENSITY rather than size — four fields per file (total, non-blank, comment, and the
# comment-to-non-blank ratio), ratcheted on the ratio. Non-blank is the denominator so the
# metric does not move under whitespace reflow.
#
# It diverges from the markdown path in exactly three places, each deliberate:
#   roots      prose_roots() PLUS tools/. tools/run-selftests.sh is one of the three files this
#              exists to measure and lives under none of the four discovered roots.
#   baseline   its own file (<repo>/.claude/prose-budget-shell.baseline.tsv). The markdown
#              baseline's check-mode lookup reads column 2 as the ceiling; a shell row has no
#              meaningful `words` value, so sharing the file would fork that lookup by
#              extension. Keeping them apart leaves the markdown file byte-identical.
#   coverage   computed INDEPENDENTLY. A root holding markdown and zero .sh files is n/a for
#              this path, not vacuous — otherwise every markdown-only consumer starts failing.
#
# Comment counting is TEXTUAL: any line matching ^[[:space:]]*# counts, shebang included, and a
# heredoc body line beginning with # counts too. That approximation is accepted rather than
# special-cased — it matches how this tool already counts words, and it stays reproducible by
# hand, which a heredoc-aware parser would not be.
#
# Usage:
#   prose-budget.sh                 # check current sizes against baseline (default)
#   prose-budget.sh --report        # human table only, no pass/fail
#   prose-budget.sh --update-baseline   # write both repo-local baselines under <repo>/.claude
#
# Tunables (env):
#   PROSE_TOLERANCE_PCT          allowed markdown growth over baseline before FAIL (default 5)
#   PROSE_SHELL_TOLERANCE_PP     allowed shell ratio growth, in PERCENTAGE POINTS (default 5)
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

# The shell ratchet has NO stub companion. On the markdown side the stub exists so a consumer
# that never ran --update-baseline gets warnings instead of a hard failure; here the same
# outcome falls out of the file simply being absent (have_shell_baseline=0 -> every file NEW),
# so shipping one would only add an artifact whose header-only-ness needs its own guard.
SHELL_BASELINE="$REPO/.claude/prose-budget-shell.baseline.tsv"

TOL="${PROSE_TOLERANCE_PCT:-5}"
# Percentage POINTS, added — not a percentage of the baseline. A ratio ratchet stated
# multiplicatively would mean something different at 20% than at 60%, and the successor slices
# (#553, #554) state their targets in points.
SH_TOL_PP="${PROSE_SHELL_TOLERANCE_PP:-5}"
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

# --- shell path (#552) --------------------------------------------------------
# Roots are prose_roots() PLUS tools/, appended with the same exists-only filter — that filter
# is what lets the caller tell n/a from vacuous, so tools/ must obey it rather than being
# emitted unconditionally. PROSE_ROOTS flows through prose_roots() unchanged, which is the
# injection seam the selftest drives.
shell_roots() {
  prose_roots
  [[ -d tools ]] && printf '%s\n' "tools"
  return 0
}

# Every *.sh under those roots is a candidate — generic, not a list of the three motivating
# files. `-fixtures/` is excluded for the same reason markdown excludes it: fixture scripts are
# selftest INPUT DATA, and ratcheting them would fail the budget for editing a test.
tracked_shell_files() {
  local roots
  roots="$(shell_roots | tr '\n' ' ')"
  [[ -n "${roots// /}" ]] || return 0
  # shellcheck disable=SC2086  # deliberate word-splitting: roots is a space-separated dir list
  find $roots -type f -name '*.sh' 2>/dev/null \
    | grep -v -- '-fixtures/' \
    | LC_ALL=C sort
}

# Raw (pre-exclusion) match count. This is the ONLY thing that separates the shell path's two
# zero-file outcomes, and AC-4/AC-9 turn on the distinction: zero raw matches means the repo
# simply has no shell under its roots (n/a), whereas raw matches that the exclusion filter ate
# means the scan looked at a tree of nothing but fixtures (vacuous).
raw_shell_matches() {
  local roots
  roots="$(shell_roots | tr '\n' ' ')"
  [[ -n "${roots// /}" ]] || { echo 0; return 0; }
  # shellcheck disable=SC2086  # deliberate word-splitting: roots is a space-separated dir list
  find $roots -type f -name '*.sh' 2>/dev/null | grep -c . | tr -d ' '
}

total_lines_of()   { wc -l < "$1" | tr -d ' '; }
nonblank_of()      { grep -c '[^[:space:]]' "$1" | tr -d ' '; }
comment_lines_of() { grep -c '^[[:space:]]*#' "$1" | tr -d ' '; }

# Ratio in TENTHS OF A PERCENT as an integer: 541 = 54.1%. Stock bash 3.2 has no float
# arithmetic, and (( )) truncates — so round half up explicitly. This is not cosmetic:
# lean-gate.sh at 3e83e46 is 2494/4612, where truncation gives 540 and rounding gives 541, and
# 541 is the number #552's AC-6 states. A plain c*1000/n agrees with the other two motivating
# files and silently disagrees on the one that matters.
ratio_tenths() {
  local c="$1" n="$2"
  (( n == 0 )) && { echo 0; return 0; }
  echo $(( (c * 1000 + n / 2) / n ))
}

# 541 -> "54.1". Kept out of the callers so the two-place split happens once.
fmt_ratio() { printf '%s.%s' "$(( $1 / 10 ))" "$(( $1 % 10 ))"; }

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
  # The shell baseline is written only when there is something to write. An empty shell set
  # raises no refusal of its own: per AC-4 that is the legitimate n/a state (a repo with a
  # markdown instruction layer and no .sh under its roots is ordinary), so the refusal above
  # stays keyed on the markdown set exactly as it was.
  if [[ -n "$(tracked_shell_files)" ]]; then
    {
      echo -e "# path\ttotal\tnonblank\tcomments\tratio_tenths   (regenerate with: prose-budget.sh --update-baseline)"
      echo -e "# ratio_tenths is comment lines / non-blank lines in tenths of a percent: 541 = 54.1%."
      while IFS= read -r f; do
        nb=$(nonblank_of "$f"); cm=$(comment_lines_of "$f")
        printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$(total_lines_of "$f")" "$nb" "$cm" "$(ratio_tenths "$cm" "$nb")"
      done < <(tracked_shell_files)
    } > "$SHELL_BASELINE"
    echo "[prose-budget] shell baseline written: $SHELL_BASELINE ($(grep -vc '^#' "$SHELL_BASELINE") files)"
  else
    echo "[prose-budget] shell baseline: nothing to write — 0 shell file(s) under the scan roots."
  fi
  exit 0
fi

# Baseline lookup. macOS ships bash 3.2 (no associative arrays) and pipeline
# scripts must stay 3.2-compatible — so look the baseline up per-file with awk
# (below) instead of building a path→words map.
have_baseline=0; [[ -f "$BASELINE" ]] && have_baseline=1
# No stub fallback on the shell side, so local-ness and existence are the same question here.
have_shell_baseline=0; [[ -f "$SHELL_BASELINE" ]] && have_shell_baseline=1

fails=0; warns=0; total_words=0; total_nnn=0; tracked=0
ROOTS="$(prose_roots | tr '\n' ' ')"
SH_ROOTS="$(shell_roots | tr '\n' ' ')"

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
  # Print the path as-is. The old `${f#.claude/}` strip assumed a single-rooted layout;
  # with two layouts it fires for one and not the other, so the column silently mixed
  # stripped and unstripped paths.
  printf '%-58s %7s %8s %6s  %s%s\n' "$f" "$w" "$tok" "$nnn" "$status" "$flag"
done < <(tracked_files)

echo "----"
printf 'TOTAL  %s words (~%s tokens)   narrative #NNN: %s\n' "$total_words" "$(( total_words * 4 / 3 ))" "$total_nnn"

# --- shell comment-density table (#552) ---------------------------------------
# Its own table rather than extra columns on the one above: the two field sets are disjoint
# (words / ~tokens / #NNN against total / non-blank / comments / ratio), so a shared table
# would be mostly empty cells in both directions.
sh_tracked=0; sh_comments=0; sh_nonblank=0
printf '\n%-58s %7s %8s %8s %7s  %s\n' "shell file" "total" "nonblank" "comments" "ratio" "vs baseline"
printf '%-58s %7s %8s %8s %7s  %s\n'   "----------" "-----" "--------" "--------" "-----" "-----------"
while IFS= read -r f; do
  sh_tracked=$(( sh_tracked + 1 ))
  t=$(total_lines_of "$f"); nb=$(nonblank_of "$f"); cm=$(comment_lines_of "$f")
  r=$(ratio_tenths "$cm" "$nb")
  sh_comments=$(( sh_comments + cm )); sh_nonblank=$(( sh_nonblank + nb ))
  sh_status="-"
  sh_base=""
  (( have_shell_baseline )) && sh_base=$(awk -F'\t' -v p="$f" '$1==p {print $5; exit}' "$SHELL_BASELINE")
  if [[ -z "$sh_base" ]]; then
    sh_status="NEW (add to baseline)"; warns=$(( warns + 1 ))
  else
    # Additive in points, so the ceiling is baseline + tolerance*10 tenths.
    sh_ceiling=$(( sh_base + SH_TOL_PP * 10 ))
    if (( r > sh_ceiling )); then
      # `FAIL ratio grew` is deliberately NOT a superstring of the markdown path's
      # `FAIL grew` — pipeline-doctor.sh branches on these literals, and an overlap would
      # let one path's failure be reported with the other path's remediation.
      sh_status="FAIL ratio grew $(fmt_ratio "$sh_base")%->$(fmt_ratio "$r")% (>+${SH_TOL_PP}pp)"; fails=$(( fails + 1 ))
    elif (( r < sh_base )); then
      sh_status="ok shrank $(fmt_ratio "$sh_base")%->$(fmt_ratio "$r")%"
    else
      sh_status="ok"
    fi
  fi
  printf '%-58s %7s %8s %8s %6s%%  %s\n' "$f" "$t" "$nb" "$cm" "$(fmt_ratio "$r")" "$sh_status"
done < <(tracked_shell_files)
printf 'SHELL  %s files   comment lines %s / %s non-blank (%s%%)\n' \
  "$sh_tracked" "$sh_comments" "$sh_nonblank" "$(fmt_ratio "$(ratio_tenths "$sh_comments" "$sh_nonblank")")"

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
    # NO early exit here any more (#552). It used to `exit 0` on this branch, which meant a
    # repo with tools/*.sh and no skills/ or agents/ root never reached the shell path at all
    # — the two coverages have to be computed independently to be worth anything.
  else
    MD_COVERAGE="vacuous"
    echo "[prose-budget] FAIL vacuous coverage: instruction-layer root(s) exist but matched 0 markdown files."
    echo "[prose-budget]   roots searched: $ROOTS"
    echo "[prose-budget]   The gate inspected nothing — a green here would be meaningless."
    fails=$(( fails + 1 ))
  fi
fi

# Shell coverage, computed independently of the markdown verdict above. The asymmetry with the
# markdown path is the point: there, a root with zero files is vacuous, because a repo that has
# an instruction layer has markdown in it by definition. Here, a repo can perfectly well carry
# skills and agents and no shell at all, so zero raw matches is n/a. Only matches that the
# fixture filter ate are vacuous — the scan looked, and looked at nothing but test data.
SH_COVERAGE="measured"
if (( sh_tracked == 0 )); then
  if [[ -z "${SH_ROOTS// /}" ]] || [[ "$(raw_shell_matches)" == "0" ]]; then
    SH_COVERAGE="n/a"
    echo "[prose-budget] shell: n/a — no shell files under the scan roots (nothing to measure)."
  else
    SH_COVERAGE="vacuous"
    echo "[prose-budget] FAIL vacuous shell coverage: root(s) matched shell files but every one was excluded."
    echo "[prose-budget]   roots searched: $SH_ROOTS"
    echo "[prose-budget]   Every match fell under a -fixtures/ tree, so the ratchet inspected nothing."
    fails=$(( fails + 1 ))
  fi
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

# Shell baseline staleness — the markdown block's shape, over the shell file.
#
# The counters are named sh_rows/sh_stale rather than reusing rows/stale, and that is load
# bearing rather than style: tools/mutation-catalog.tsv's prose-budget-stale-gate row anchors
# the markdown check with the literal sed pattern `stale == rows`. A second site carrying the
# same expression would make that mutant apply in two places at once, quietly changing what the
# catalog row measures while it still reported a kill.
if (( have_shell_baseline )); then
  sh_rows=0; sh_stale=0
  while IFS=$'\t' read -r p _rest; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    sh_rows=$(( sh_rows + 1 ))
    if [[ ! -f "$p" ]]; then
      sh_stale=$(( sh_stale + 1 ))
      echo "[prose-budget] stale shell baseline row (path no longer exists): $p"
    fi
  done < "$SHELL_BASELINE"
  if (( sh_rows > 0 && sh_stale == sh_rows && sh_tracked > 0 )); then
    echo "[prose-budget] FAIL stale shell baseline: all $sh_rows row(s) unresolvable while $sh_tracked shell file(s) were tracked."
    echo "[prose-budget]   Regenerate with: prose-budget.sh --update-baseline"
    fails=$(( fails + 1 ))
  elif (( sh_stale > 0 )); then
    echo "[prose-budget] $sh_stale of $sh_rows shell baseline row(s) no longer resolve — consider --update-baseline"
    warns=$(( warns + sh_stale ))
  fi
elif (( sh_tracked > 0 )); then
  echo "[prose-budget] note: no shell baseline — every shell file reports NEW. Snapshot one with: prose-budget.sh --update-baseline"
fi

[[ "$MODE" == "report" ]] && exit 0
# ONE combined last line, and it stays last: pipeline-doctor.sh reads the OK message with
# `tail -1`, so splitting this per path would silently drop half of what an operator has been
# reading since #188. Both tolerances are named because the counts now span two metrics and
# "+5%" would be wrong for the shell half of them.
echo "[prose-budget] $fails fail(s), $warns warning(s)  (coverage: md $MD_COVERAGE, sh $SH_COVERAGE; tolerance: md +${TOL}% words, sh +${SH_TOL_PP}pp ratio)"
exit "$fails"
