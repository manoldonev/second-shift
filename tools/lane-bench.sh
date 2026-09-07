#!/usr/bin/env bash
# lane-bench.sh — the lane bench's scorer. `docs/lane-bench.md` is the protocol; this is the
# half of it that a machine can check.
#
# WHY THIS EXISTS. The bench replays a fixed corpus of tickets through the lean lane once per
# harness arm, so that a change to second-shift is kept or reverted from a measured delta rather
# than from an argument. That only works if the score is deterministic: a cell scored today and
# the same cell re-scored next month must produce the same numbers, and neither may be a
# judgment. So the gold is two detectors per seeded defect — a hidden test that fails while the
# defect is present, and a regex over the verdict records that matches when a reviewer names it —
# and this script evaluates both. No model is called and nothing is estimated.
#
# WHAT `score` DOES NOT DO. It does not derive a cell's terminal class from its terminal slug;
# that is `run`'s job (#813), and tools/lane-bench-classes.tsv is its data. `score` reads that
# file for exactly one thing: validating the `unscorable` class it writes itself. It also does
# not run the substrate's configured `test` command — the overlay's own `run.sh` is the verdict
# channel, because a bench needs one test id per hidden test and a repo's test command reports a
# single exit code (#812 D-1).
#
# A CELL IS SCORED ON ITS PR, NOT ON ITS CLASS. If exactly one PR exists on the lane branch it is
# overlaid and scored whatever the lane terminated as — a `pr-unapproved` cell's diff is still a
# diff, and the arm still gets whatever credit its tests earn. Only PR PRESENCE decides whether
# the score columns are written.
#
# EMPTY IS NOT ZERO. A cell with no PR gets EMPTY score columns, never zeros: a zero is a
# measurement that the code failed the hidden tests, and no code was measured. The same holds for
# `unscorable`, which is a state the operator fixes (an overlay that cannot apply, an ambiguous
# PR) rather than a result the arm earned.
#
# Usage:
#   lane-bench.sh score --results <tsv> --cell <id> --issue <n> --config <eval config>
#                       --overlay <dir> --defects <tsv>
#
#     --results   the bench repo's results TSV; the row keyed on --cell is rewritten in place
#     --cell      the cell id, e.g. t4-control-r2
#     --issue     the substrate issue this cell ran on. The results row does not carry it and
#                 the cell id does not encode it, so it is an input (#812 D-19)
#     --config    the eval config selecting the substrate; its directory's parent is the
#                 substrate root
#     --overlay   the ticket's hidden-test overlay directory; must contain run.sh
#     --defects   the ticket's seeded-defect TSV: id, file, description, test_id, verdict_regex
#
# EXIT: 0 the row was written (including the empty and `unscorable` forms) · 2 a refusal, which
# leaves the results file untouched.
set -uo pipefail

TAB=$'\t'
SELF="$(basename "$0")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$HERE" ] || { echo "[lane-bench] FATAL: cannot resolve this script's own directory" >&2; exit 2; }

die() { echo "[lane-bench] $*" >&2; exit 2; }

# The 19-column results contract (#811 Data Contracts). Columns 13..19 are the ones `score`
# writes; 1..12 belong to `run` (#813) and this script never touches them.
HEADER="cell_id${TAB}ticket_role${TAB}arm${TAB}repeat${TAB}harness_sha${TAB}cli_version${TAB}build_model${TAB}review_model${TAB}terminal_slug${TAB}terminal_class${TAB}rounds${TAB}wall_min${TAB}pr_head_sha${TAB}tests_passed${TAB}tests_total${TAB}defects_at_head${TAB}defects_named${TAB}review_catch${TAB}scored_at"
NCOLS=19

SUB="${1:-}"
[ -n "$SUB" ] || die "usage: $SELF score --results <tsv> --cell <id> --issue <n> --config <cfg> --overlay <dir> --defects <tsv>"
shift

case "$SUB" in
  score) : ;;
  -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
  *) die "unknown subcommand: $SUB (this slice ships 'score' only; 'run' is #813)" ;;
esac

RESULTS=""; CELL=""; ISSUE=""; CONFIG=""; OVERLAY=""; DEFECTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --results) RESULTS="${2:-}"; shift 2 ;;
    --cell)    CELL="${2:-}";    shift 2 ;;
    --issue)   ISSUE="${2:-}";   shift 2 ;;
    --config)  CONFIG="${2:-}";  shift 2 ;;
    --overlay) OVERLAY="${2:-}"; shift 2 ;;
    --defects) DEFECTS="${2:-}"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *)  die "unexpected argument: $1" ;;
  esac
done

[ -n "$RESULTS" ] || die "--results is required"
[ -n "$CELL" ]    || die "--cell is required"
[ -n "$ISSUE" ]   || die "--issue is required: the results row does not carry it and the cell id does not encode it"
[ -n "$CONFIG" ]  || die "--config is required"
[ -n "$OVERLAY" ] || die "--overlay is required"
[ -n "$DEFECTS" ] || die "--defects is required"

case "$ISSUE" in ''|*[!0-9]*) die "--issue must be a positive integer, got '$ISSUE'" ;; esac
[ -f "$RESULTS" ] || die "no results file at $RESULTS"
[ -r "$RESULTS" ] || die "cannot read results file: $RESULTS"
[ -d "$OVERLAY" ] || die "no overlay directory at $OVERLAY"
[ -f "$OVERLAY/run.sh" ] || die "overlay $OVERLAY carries no run.sh — the per-test verdict channel is that script (#812 D-1)"
[ -f "$DEFECTS" ] || die "no seeded-defect list at $DEFECTS"
[ -f "$CONFIG" ] || die "no eval config at $CONFIG"
jq empty "$CONFIG" 2>/dev/null || die "eval config is not parseable JSON: $CONFIG (jq empty '$CONFIG' names the parse error)"

CLASSES="$HERE/lane-bench-classes.tsv"
[ -f "$CLASSES" ] || die "no terminal-class table at $CLASSES"
awk -F"$TAB" '!/^#/ && NF >= 2 && $2 == "unscorable" { found = 1 } END { exit !found }' "$CLASSES" \
  || die "$CLASSES declares no 'unscorable' class — the one value this script writes into terminal_class is not in its own table"

# ---- config resolution (#812 D-9) --------------------------------------------------------------
cfg() { # cfg <jq-filter> <default>
  local v
  v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
  if [ -n "$v" ] && [ "$v" != "null" ]; then printf '%s\n' "$v"; return 0; fi
  printf '%s\n' "$2"
}
PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
BRANCH_PREFIX="$(cfg '.tracker.branchPrefix' '')"
[ -n "$BRANCH_PREFIX" ] || die "the eval config declares no tracker.branchPrefix — the lane branch cannot be named"
REPO_SLUG="$(cfg '(.topology.repos | to_entries[] | select(.value.path==".") | .key)' '')"
[ -n "$REPO_SLUG" ] || die "the eval config has no topology.repos entry whose path is '.' — the verdict record's path cannot be derived"

# The substrate root is the parent of the directory holding the config (#812 D-9), so an eval
# config at <root>/.claude/eval.json resolves <root>.
CFG_DIR="$(cd "$(dirname "$CONFIG")" && pwd)" || die "cannot resolve the eval config's directory"
ROOT="$(cd "$CFG_DIR/.." && pwd)" || die "cannot resolve the substrate root above $CFG_DIR"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "the substrate root $ROOT is not a git repository"

BRANCH="${BRANCH_PREFIX}${ISSUE}"
VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"

# ---- the results row ---------------------------------------------------------------------------
# Compared as a whole string rather than by piping the header into a quiet matcher: a producer
# that dies inside a pipeline is indistinguishable from a genuine non-match, and this is the
# check standing between the scorer and rewriting a file whose columns mean something else.
HDR_LINE="$(head -n1 "$RESULTS")" || die "cannot read the header line of $RESULTS"
[ "$HDR_LINE" = "$HEADER" ] \
  || die "$RESULTS does not carry the 19-column header this scorer writes against — refusing to rewrite a file whose shape it cannot vouch for"

ROW="$(awk -F"$TAB" -v c="$CELL" 'NR > 1 && $1 == c { print; found = 1; exit } END { exit !found }' "$RESULTS")" \
  || die "no row for cell '$CELL' in $RESULTS"
NF_ROW="$(printf '%s' "$ROW" | awk -F"$TAB" '{ print NF }')"
[ "$NF_ROW" = "$NCOLS" ] || die "the row for '$CELL' has $NF_ROW column(s), not $NCOLS"
# Columns 1..10 identify the cell and its terminal; `run` writes them and `score` never does, so a
# blank one means the row was hand-started rather than produced by a run. 11 and 12 are legitimately
# empty on a cell that never reached a round.
MISSING="$(printf '%s' "$ROW" | awk -F"$TAB" '{ for (i = 1; i <= 10; i++) if ($i == "") printf "%s%d", (n++ ? "," : ""), i }')"
[ -z "$MISSING" ] || die "the row for '$CELL' is missing pre-score column(s) $MISSING — those are '$SELF run''s to write, not this scorer's"

# ---- the seeded defects ------------------------------------------------------------------------
# Read into parallel indexed arrays: bash 3.2 has no associative arrays.
D_ID=(); D_TEST=(); D_RE=()
while IFS="$TAB" read -r d_id d_file d_desc d_test d_re; do
  case "$d_id" in ''|'#'*) continue ;; esac
  [ "$d_id" = "id" ] && continue
  [ -n "$d_test" ] || die "seeded defect '$d_id' carries no test_id"
  [ -n "$d_re" ]   || die "seeded defect '$d_id' carries no verdict_regex"
  : "$d_file $d_desc"
  D_ID+=("$d_id"); D_TEST+=("$d_test"); D_RE+=("$d_re")
done < "$DEFECTS"
SEEDED="${#D_ID[@]}"
[ "$SEEDED" -gt 0 ] || die "$DEFECTS declares no seeded defects — review_catch would divide by zero"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-bench-score.XXXXXX")" || die "cannot create a scratch directory"
WT="$WORK/head"
trap '[ -d "$WT" ] && git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

now_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# write_row <pr_head_sha> <tests_passed> <tests_total> <at_head> <named> <catch> [terminal_class]
# Rewrites the cell's row atomically, touching only columns 13..19 plus, when a seventh argument
# is given, column 10.
write_row() {
  local out
  out="$(mktemp "$(dirname "$RESULTS")/.lane-bench-results.XXXXXX")" || die "cannot stage the results rewrite"
  awk -F"$TAB" -v OFS="$TAB" -v c="$CELL" \
      -v sha="$1" -v tp="$2" -v tt="$3" -v ah="$4" -v dn="$5" -v rc="$6" -v cls="${7:-}" -v at="$(now_utc)" '
    NR > 1 && $1 == c {
      if (cls != "") $10 = cls
      $13 = sha; $14 = tp; $15 = tt; $16 = ah; $17 = dn; $18 = rc; $19 = at
    }
    { print }
  ' "$RESULTS" > "$out" || { rm -f "$out"; die "the results rewrite failed"; }
  mv "$out" "$RESULTS" || { rm -f "$out"; die "cannot replace $RESULTS"; }
}

say_summary() { # say_summary <class> <passed> <total> <at_head> <named> <catch>
  printf '%s %s %s/%s %s %s %s\n' "$CELL" "$1" "$2" "$3" "$4" "$5" "$6"
}

# ---- resolve the PR (#812 D-4) -----------------------------------------------------------------
PR_JSON="$( (cd "$ROOT" && "${GH:-gh}" pr list --head "$BRANCH" --state all --json number,headRefOid) 2>&1 )"
PR_RC=$?
[ "$PR_RC" -eq 0 ] || die "could not list PRs for '$BRANCH' (gh exit $PR_RC): $PR_JSON — a read that errored is not a read that found nothing"
PR_COUNT="$(printf '%s' "$PR_JSON" | jq 'length' 2>/dev/null)"
case "$PR_COUNT" in ''|*[!0-9]*) die "gh returned something that is not a JSON array for '$BRANCH': $PR_JSON" ;; esac

if [ "$PR_COUNT" -eq 0 ]; then
  write_row "" "" "" "" "" ""
  say_summary "no-pr-found" "" "" "" "" ""
  echo "[lane-bench] no PR on '$BRANCH' — score columns left empty, which is not a zero."
  exit 0
fi

if [ "$PR_COUNT" -gt 1 ]; then
  write_row "" "" "" "" "" "" "unscorable"
  say_summary "unscorable" "" "" "" "" ""
  echo "[lane-bench] $PR_COUNT PRs on '$BRANCH' — the cell cannot be scored against one of them; terminal_class set to 'unscorable' and the score columns left empty." >&2
  exit 0
fi

PR_HEAD="$(printf '%s' "$PR_JSON" | jq -r '.[0].headRefOid' 2>/dev/null)"
[ -n "$PR_HEAD" ] && [ "$PR_HEAD" != "null" ] || die "the PR on '$BRANCH' carries no headRefOid"

git -C "$ROOT" worktree add --detach "$WT" "$PR_HEAD" >/dev/null 2>&1 \
  || die "cannot check out $PR_HEAD into a worktree — the head is unreachable in $ROOT"

# ---- overlay ------------------------------------------------------------------------------------
if ! cp -R "$OVERLAY"/. "$WT"/ 2>/dev/null; then
  write_row "$PR_HEAD" "" "" "" "" "" "unscorable"
  say_summary "unscorable" "" "" "" "" ""
  echo "[lane-bench] the overlay $OVERLAY could not be applied onto $PR_HEAD — terminal_class set to 'unscorable', never a zero." >&2
  exit 0
fi

RUN_OUT="$WORK/run.out"
( cd "$WT" && bash ./run.sh ) > "$RUN_OUT" 2>&1
# run.sh's own exit status is deliberately not read: it is non-zero whenever any hidden test
# fails, which is the ordinary case this whole script exists to measure. The TEST lines are the
# channel, and their ABSENCE is what means the run said nothing.

TESTS_TOTAL="$(grep -cE '^TEST[[:space:]]+[^[:space:]]+[[:space:]]+(PASS|FAIL)[[:space:]]*$' "$RUN_OUT")"
if [ "$TESTS_TOTAL" -eq 0 ]; then
  write_row "$PR_HEAD" "" "" "" "" "" "unscorable"
  say_summary "unscorable" "" "" "" "" ""
  echo "[lane-bench] the overlay's run.sh printed no TEST line at $PR_HEAD — nothing was measured, so terminal_class is 'unscorable' rather than 0/0." >&2
  exit 0
fi
TESTS_PASSED="$(grep -cE '^TEST[[:space:]]+[^[:space:]]+[[:space:]]+PASS[[:space:]]*$' "$RUN_OUT")"

# ---- detector 1: does each seeded defect's hidden test still fail at head? -----------------------
AT_HEAD=0
i=0
while [ "$i" -lt "$SEEDED" ]; do
  t="${D_TEST[$i]}"
  line="$(grep -E "^TEST[[:space:]]+${t}[[:space:]]+(PASS|FAIL)[[:space:]]*$" "$RUN_OUT" | head -n1)"
  [ -n "$line" ] || die "seeded defect '${D_ID[$i]}' names test id '$t', which the overlay's run.sh did not report at $PR_HEAD — the detector pair is broken, and scoring it as 'not present' would credit the arm for a test that never ran"
  case "$line" in *FAIL) AT_HEAD=$((AT_HEAD + 1)) ;; esac
  i=$((i + 1))
done

# ---- detector 2: did any verdict record on the branch name the defect? --------------------------
VERSIONS="$(git -C "$ROOT" log --format=%H "$PR_HEAD" -- "$VERDICT_REL" 2>/dev/null)"
NAMED=0
CATCH="n/a"
if [ -n "$VERSIONS" ]; then
  RECORDS="$WORK/records.txt"
  : > "$RECORDS"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    git -C "$ROOT" show "$sha:$VERDICT_REL" >> "$RECORDS" 2>/dev/null
    printf '\n' >> "$RECORDS"
  done <<EOF
$VERSIONS
EOF
  i=0
  while [ "$i" -lt "$SEEDED" ]; do
    if grep -qE "${D_RE[$i]}" "$RECORDS"; then NAMED=$((NAMED + 1)); fi
    i=$((i + 1))
  done
  CATCH="$NAMED/$SEEDED"
else
  # No verdict record ever landed on this branch — every cell of an arm without review-toolkit
  # looks like this. `n/a` and a NAMED of 0 are different claims and the row must carry the first.
  NAMED=""
fi

write_row "$PR_HEAD" "$TESTS_PASSED" "$TESTS_TOTAL" "$AT_HEAD" "$NAMED" "$CATCH"
CLS="$(printf '%s' "$ROW" | awk -F"$TAB" '{ print $10 }')"
say_summary "$CLS" "$TESTS_PASSED" "$TESTS_TOTAL" "$AT_HEAD" "$NAMED" "$CATCH"
exit 0
