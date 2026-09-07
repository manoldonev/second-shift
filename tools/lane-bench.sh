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
# that is `run`'s job, and tools/lane-bench-classes.tsv is the data both read. `score` reads that
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
# WHAT `run` DOES. One cell, end to end: it checks the arm's ref out into a worktree, writes the
# plugin-directory manifest `lane-bench-arm.sh` loads from it, files a fresh substrate issue and
# queue-labels it, drops the ticket's fixture receipt at the gate's ledger path, launches the ARM'S
# OWN scheduler detached under `nohup`, waits for the launch ledger's terminal row, classifies it
# through the table, reads each payload session's RESOLVED model id back out of its transcript,
# appends the row, and hands it to `score`. Four things are refused before the first side effect —
# a cell id already in the results file, a dirty second-shift checkout, an arm whose harness_sha or
# cli_version disagrees with an existing row of the same arm, and an eval config whose tracker host
# is not the substrate — because a cell that refuses after filing has already written to a tracker.
#
# Usage:
#   lane-bench.sh run --arm <name> ( --arm-ref <ref> | --skeleton --control-ref <sha> )
#                     --results <tsv> --config <eval config> --substrate <owner/repo>
#                     --ticket <role> --repeat <n> --body <file> --receipt <file>
#                     --overlay <dir> --defects <tsv>
#
#     --arm       the arm's NAME, the cell id's middle field: control, skeleton, or a candidate's
#     --arm-ref   the second-shift ref this arm IS; the worktree is cut from it
#     --skeleton  assemble the floor (dev-pipeline + audit-toolkit) from --control-ref's worktree
#     --substrate <owner/repo>, what the tracker-host assertion compares `gh repo view` against.
#                 An argument and not a literal, by the anonymization rule
#     --ticket    the corpus role, 1..7 · --repeat the repeat number
#     --body      the corpus ticket's issue body; its first `# ` heading is the issue title
#     --receipt   the ticket's fixture receipt, copied to <stateDir>/<issue>-ledger.md
#
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
# EXIT: 0 the row was written (including the empty and `unscorable` forms) · 1 (`run` only) the
# row was written and the cell is `lane-error` after its one re-run · 2 a refusal, which leaves the
# results file untouched.
#
# Seams, each with a shipped default pointing at the real thing:
#   LEAN_BENCH_SS_ROOT            the second-shift checkout arms are cut from (default: this
#                                 script's own repository)
#   LEAN_BENCH_LANE_BIN           the lane scheduler (default: the ARM worktree's own)
#   LEAN_BENCH_POLL_SECS          seconds between launch-ledger reads (default 30)
#   LEAN_BENCH_CELL_CEILING_SECS  wall-clock bound on one cell (default 28800)
#   STATECTL_STATE_DIR            the substrate's pipeline state dir, retro-corpus.sh's ladder
#   ${GH:-gh}                     the tracker/code-host CLI
set -uo pipefail

TAB=$'\t'
SELF="$(basename "$0")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$HERE" ] || { echo "[lane-bench] FATAL: cannot resolve this script's own directory" >&2; exit 2; }

die() { echo "[lane-bench] $*" >&2; exit 2; }

# The 19-column results contract (#811 Data Contracts). Columns 13..19 are the ones `score`
# writes; 1..12 belong to `run` (#813) and this script never touches them.
# The terminal-class table. BOTH subcommands read it: `run` derives a cell's class from its
# terminal slug, `score` validates the one class it writes itself.
CLASSES="$HERE/lane-bench-classes.tsv"

# ---- config resolution (#812 D-9) --------------------------------------------------------------
cfg() { # cfg <jq-filter> <default>
  local v
  v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
  if [ -n "$v" ] && [ "$v" != "null" ]; then printf '%s\n' "$v"; return 0; fi
  printf '%s\n' "$2"
}

HEADER="cell_id${TAB}ticket_role${TAB}arm${TAB}repeat${TAB}harness_sha${TAB}cli_version${TAB}build_model${TAB}review_model${TAB}terminal_slug${TAB}terminal_class${TAB}rounds${TAB}wall_min${TAB}pr_head_sha${TAB}tests_passed${TAB}tests_total${TAB}defects_at_head${TAB}defects_named${TAB}review_catch${TAB}scored_at"
NCOLS=19

SUB="${1:-}"
[ -n "$SUB" ] || die "usage: $SELF run --arm <name> ... | $SELF score --results <tsv> --cell <id> --issue <n> ...  ($SELF --help)"
shift

case "$SUB" in
  score|run) : ;;
  -h|--help) sed -n '2,78p' "$0"; exit 0 ;;
  *) die "unknown subcommand: $SUB (this script ships 'run' and 'score')" ;;
esac

# ================================================================================================
# `run` — one bench cell, end to end (#813)
# ================================================================================================
# WHAT A CELL IS. One (ticket role, arm, repeat). `run` checks the arm's ref out into a worktree,
# writes the manifest that `lane-bench-arm.sh` loads from it, files a fresh substrate issue,
# queue-labels it, drops the ticket's fixture receipt where the gate will look for it, launches
# the ARM'S OWN scheduler detached, waits for the launch ledger's terminal row, classifies it,
# reads the payload sessions' resolved model ids back out of their transcripts, appends the row,
# and hands it to `score`.
#
# EVERY REFUSAL COMES BEFORE THE FIRST SIDE EFFECT. A duplicate cell id, a dirty second-shift
# checkout, an arm whose harness or CLI disagrees with an existing row of the same arm, and an
# eval config that does not resolve to the substrate are all decided before an issue is filed —
# a cell that refuses after filing has already written to a tracker, which is the one thing
# AC-10 exists to prevent.
#
# THE LAUNCH IS DETACHED AND THE VERDICT IS READ FROM THE LEDGER, never from the scheduler's
# stdout: a cell runs for tens of minutes and the operator's shell is not the right place to hold
# it open, and the scheduler's exit code is many-to-one over the terminals this has to tell apart
# (#811 D-31).
cmd_run() {
  local ARM="" ARM_REF="" SKELETON=0 CONTROL_REF="" ROLE="" REPEAT="" \
        BODY="" RECEIPT="" SUBSTRATE="" GH_CLI
  RESULTS=""; CONFIG=""; OVERLAY=""; DEFECTS=""
  GH_CLI="${GH:-gh}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --arm)         ARM="${2:-}";         shift 2 ;;
      --arm-ref)     ARM_REF="${2:-}";     shift 2 ;;
      --skeleton)    SKELETON=1;           shift   ;;
      --control-ref) CONTROL_REF="${2:-}"; shift 2 ;;
      --results)     RESULTS="${2:-}";     shift 2 ;;
      --config)      CONFIG="${2:-}";      shift 2 ;;
      --ticket)      ROLE="${2:-}";        shift 2 ;;
      --repeat)      REPEAT="${2:-}";      shift 2 ;;
      --overlay)     OVERLAY="${2:-}";     shift 2 ;;
      --defects)     DEFECTS="${2:-}";     shift 2 ;;
      --receipt)     RECEIPT="${2:-}";     shift 2 ;;
      --body)        BODY="${2:-}";        shift 2 ;;
      --substrate)   SUBSTRATE="${2:-}";   shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  die "unexpected argument: $1" ;;
    esac
  done

  [ -n "$ARM" ]       || die "--arm is required: it is the cell id's middle field and an arm REF does not spell a name"
  [ -n "$RESULTS" ]   || die "--results is required"
  [ -n "$CONFIG" ]    || die "--config is required"
  [ -n "$ROLE" ]      || die "--ticket is required (the corpus role, 1..7)"
  [ -n "$REPEAT" ]    || die "--repeat is required"
  [ -n "$OVERLAY" ]   || die "--overlay is required"
  [ -n "$DEFECTS" ]   || die "--defects is required"
  [ -n "$RECEIPT" ]   || die "--receipt is required: intake is done once, outside the measured run, so no cell measures the interview"
  [ -n "$BODY" ]      || die "--body is required (the corpus ticket's issue body)"
  [ -n "$SUBSTRATE" ] || die "--substrate <owner/repo> is required: it is what the tracker-host assertion compares against, and it is deliberately not a literal in this repository"
  case "$ROLE"   in ''|*[!0-9]*) die "--ticket must be a corpus role number, got '$ROLE'" ;; esac
  case "$REPEAT" in ''|*[!0-9]*) die "--repeat must be a positive integer, got '$REPEAT'" ;; esac
  case "$SUBSTRATE" in */*) : ;; *) die "--substrate must be <owner>/<repo>, got '$SUBSTRATE'" ;; esac

  local REF
  if [ "$SKELETON" -eq 1 ]; then
    [ -z "$ARM_REF" ]     || die "--skeleton and --arm-ref are alternatives: the skeleton IS the control worktree, cut down to two plugin directories"
    [ -n "$CONTROL_REF" ] || die "--skeleton requires --control-ref: the skeleton's kit is taken from the control worktree, so it moves with the series' pin and not with a ref of its own"
    REF="$CONTROL_REF"
  else
    [ -n "$ARM_REF" ]     || die "one of --arm-ref <ref> or --skeleton --control-ref <sha> is required"
    [ -z "$CONTROL_REF" ] || die "--control-ref belongs to --skeleton; an --arm-ref cell takes its kit from that ref"
    REF="$ARM_REF"
  fi

  local CELL="t${ROLE}-${ARM}-r${REPEAT}"

  [ -f "$RESULTS" ] || die "no results file at $RESULTS"
  [ -w "$RESULTS" ] || die "cannot write the results file: $RESULTS"
  local HDR_LINE
  HDR_LINE="$(head -n1 "$RESULTS")" || die "cannot read the header line of $RESULTS"
  [ "$HDR_LINE" = "$HEADER" ] \
    || die "$RESULTS does not carry the $NCOLS-column header this runner writes against — refusing to append a row to a file whose shape it cannot vouch for"

  # A cell id is the row's key, so a second row under one id would make the cell unscoreable and
  # the arm's mean quietly weighted. The matrix is resumed by re-running the cells that have no
  # row, which is only meaningful if this refuses.
  awk -F"$TAB" -v c="$CELL" 'NR > 1 && $1 == c { found = 1 } END { exit !found }' "$RESULTS" \
    && die "$RESULTS already carries a row for cell '$CELL' — re-score it with '$SELF score', or pick another repeat"

  for f in "$BODY" "$RECEIPT" "$DEFECTS"; do
    [ -f "$f" ] || die "no file at $f"
  done
  [ -d "$OVERLAY" ] || die "no overlay directory at $OVERLAY"
  [ -f "$OVERLAY/run.sh" ] || die "overlay $OVERLAY carries no run.sh — score would refuse this cell after it had already run"
  [ -f "$CONFIG" ] || die "no eval config at $CONFIG"
  jq empty "$CONFIG" 2>/dev/null || die "eval config is not parseable JSON: $CONFIG"

  local TITLE
  TITLE="$(grep -m1 '^# ' "$BODY" | sed 's/^# *//')"
  [ -n "$TITLE" ] || die "$BODY has no '# ' heading to take the issue title from — the corpus file carries its own title so a role's issue text is fixed by the corpus, not by the invocation"

  # ---- the arm ---------------------------------------------------------------------------------
  local SS_ROOT
  SS_ROOT="${LEAN_BENCH_SS_ROOT:-$(cd "$HERE/.." && pwd)}"
  git -C "$SS_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$SS_ROOT is not a git repository — there is no second-shift checkout to cut an arm worktree from"
  # An arm is a COMMIT. A dirty checkout would put uncommitted work in front of the payload
  # sessions under a `harness_sha` that does not describe it, and every row of that arm would then
  # be attributed to a tree nobody can check out again.
  local DIRT
  DIRT="$(git -C "$SS_ROOT" status --porcelain 2>/dev/null | head -n5)"
  [ -z "$DIRT" ] || die "the second-shift checkout at $SS_ROOT is not clean — an arm is a commit, and a cell run from a dirty tree records a harness_sha that does not describe what ran:"$'\n'"$DIRT"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-bench-run.XXXXXX")" || die "cannot create a scratch directory"
  ARM_WT="$WORK/arm"
  trap 'lane_bench_run_cleanup' EXIT
  git -C "$SS_ROOT" worktree add --detach "$ARM_WT" "$REF" >/dev/null 2>&1 \
    || die "cannot check '$REF' out into an arm worktree — the ref is unreachable in $SS_ROOT"

  local HARNESS_SHA CLI_VERSION
  HARNESS_SHA="$(git -C "$ARM_WT" rev-parse HEAD 2>/dev/null)"
  [ -n "$HARNESS_SHA" ] || die "cannot read the arm worktree's HEAD"
  CLI_VERSION="$(claude --version 2>/dev/null | awk '{ print $1; exit }')"
  [ -n "$CLI_VERSION" ] || die "'claude --version' said nothing — the series is keyed on the CLI version and a row cannot carry an unknown one"

  # WITHIN ONE ARM THE HARNESS IS A CONSTANT BY DEFINITION (docs/lane-bench.md, The series). A
  # second harness_sha or cli_version under the same arm name means two different kits are being
  # averaged together under one label, which is exactly the confusion the bench exists to remove.
  local DRIFT
  DRIFT="$(awk -F"$TAB" -v a="$ARM" -v h="$HARNESS_SHA" -v v="$CLI_VERSION" '
    NR > 1 && $3 == a && ($5 != h || $6 != v) { print $1 " carries " $5 "/" $6; found = 1; exit }
    END { exit !found }' "$RESULTS")" \
    && die "arm '$ARM' already has a row at a different harness/CLI: $DRIFT, this cell is $HARNESS_SHA/$CLI_VERSION — within one arm the harness is a constant, so these rows do not belong to one series"

  MANIFEST="$WORK/manifest"
  : > "$MANIFEST"
  if [ "$SKELETON" -eq 1 ]; then
    # The floor: the least kit that still runs a lane. Taken from the CONTROL worktree, so the
    # skeleton moves with the series' pin rather than with a ref of its own.
    local p
    for p in dev-pipeline audit-toolkit; do
      [ -d "$ARM_WT/plugins/$p" ] || die "the control worktree at $REF has no plugins/$p — the skeleton is that plugin plus audit-toolkit and cannot be assembled without it"
      printf '%s\n' "$ARM_WT/plugins/$p" >> "$MANIFEST"
    done
  else
    local d
    for d in "$ARM_WT"/plugins/*/; do
      [ -f "${d}.claude-plugin/plugin.json" ] || continue
      printf '%s\n' "${d%/}" >> "$MANIFEST"
    done
  fi
  [ -s "$MANIFEST" ] || die "no plugin directory in $ARM_WT/plugins carries a .claude-plugin/plugin.json — the arm at $REF has no kit to load"

  # ---- the substrate ---------------------------------------------------------------------------
  local CFG_DIR CFG_ABS ROOT PLANS_DIR BRANCH_PREFIX REPO_SLUG STATE_DIR QUEUE_LABEL
  CFG_DIR="$(cd "$(dirname "$CONFIG")" && pwd)" || die "cannot resolve the eval config's directory"
  CFG_ABS="$CFG_DIR/$(basename "$CONFIG")"
  ROOT="$(cd "$CFG_DIR/.." && pwd)" || die "cannot resolve the substrate root above $CFG_DIR"
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "the substrate root $ROOT is not a git repository"
  [ "$ROOT" != "$SS_ROOT" ] || die "the eval config at $CONFIG resolves to the second-shift checkout itself — a cell run against it would file issues and post comments on this repository's own tracker"

  PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
  BRANCH_PREFIX="$(cfg '.tracker.branchPrefix' '')"
  [ -n "$BRANCH_PREFIX" ] || die "the eval config declares no tracker.branchPrefix — the lane branch cannot be named"
  REPO_SLUG="$(cfg '(.topology.repos | to_entries[] | select(.value.path==".") | .key)' '')"
  [ -n "$REPO_SLUG" ] || die "the eval config has no topology.repos entry whose path is '.'"
  QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
  STATE_DIR="${STATECTL_STATE_DIR:-$ROOT/$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')}"

  # AC-10'S RUNG. Everything downstream of here writes to a tracker, so this is the last moment
  # the bench can still be sure which one. A `gh` read that ERRORS is a refusal and not a pass:
  # the whole point is that an unverified host is exactly the case this must not run in.
  local HOST_JSON HOST_RC HOST
  HOST_JSON="$( (cd "$ROOT" && "$GH_CLI" repo view --json nameWithOwner) 2>&1 )"
  HOST_RC=$?
  [ "$HOST_RC" -eq 0 ] || die "could not resolve the tracker host at $ROOT (gh exit $HOST_RC): $HOST_JSON — a read that errored is not a read that agreed"
  HOST="$(printf '%s' "$HOST_JSON" | jq -r '.nameWithOwner // empty' 2>/dev/null)"
  [ "$HOST" = "$SUBSTRATE" ] \
    || die "the eval config at $CONFIG resolves tracker host '$HOST', not the substrate '$SUBSTRATE' — refusing to run a cell that would file an issue, swap a label and post comments on it"

  # ---- the cell, at most twice ------------------------------------------------------------------
  local attempt=1 rerun=0
  while : ; do
    lane_bench_cell "$attempt"
    [ "$CELL_CLASS" = "lane-error" ] || break
    if [ "$attempt" -eq 1 ]; then
      echo "[lane-bench] cell $CELL terminated '$CELL_SLUG' → lane-error on substrate issue #$CELL_ISSUE; re-running once with a fresh issue (docs/lane-bench.md)." >&2
      attempt=2; rerun=1
      continue
    fi
    echo "[lane-bench] cell $CELL terminated '$CELL_SLUG' → lane-error a SECOND time (substrate issue #$CELL_ISSUE). Recording the row and stopping: two lane errors is an operator's problem, not a re-run's." >&2
    break
  done

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\t\t\t\t\t\t\n' \
    "$CELL" "$ROLE" "$ARM" "$REPEAT" "$HARNESS_SHA" "$CLI_VERSION" \
    "$CELL_BUILD_MODEL" "$CELL_REVIEW_MODEL" "$CELL_SLUG" "$CELL_CLASS" \
    "$CELL_ROUNDS" "$CELL_WALL" >> "$RESULTS" \
    || die "cannot append the row for '$CELL' to $RESULTS"

  bash "$0" score --results "$RESULTS" --cell "$CELL" --issue "$CELL_ISSUE" \
       --config "$CFG_ABS" --overlay "$OVERLAY" --defects "$DEFECTS"
  local SCORE_RC=$?
  [ "$SCORE_RC" -eq 0 ] || die "the row for '$CELL' was appended but 'score' refused it (exit $SCORE_RC) — the row stands, unscored, and re-running 'score' on it is the fix"

  echo "[lane-bench] cell $CELL: substrate issue #$CELL_ISSUE, terminal $CELL_SLUG → $CELL_CLASS."
  [ "$CELL_CLASS" = "lane-error" ] && return 1
  [ "$rerun" -eq 1 ] && echo "[lane-bench] (this cell took its one re-run.)"
  return 0
}

# The cell's own scratch state is torn down here rather than in a `trap` written at each `mktemp`:
# the arm worktree is registered in the second-shift checkout, so removing the directory without
# telling git would leave a stale entry that the next `worktree add` on the same path refuses.
# shellcheck disable=SC2317,SC2329  # invoked indirectly by cmd_run's EXIT trap. Both codes:
# 0.10+ reports SC2329 on the function, 0.9.0 (what CI installs) reports SC2317 on its body.
lane_bench_run_cleanup() {
  [ -n "${ARM_WT:-}" ] && [ -d "$ARM_WT" ] \
    && git -C "${LEAN_BENCH_SS_ROOT:-$(cd "$HERE/.." && pwd)}" worktree remove --force "$ARM_WT" >/dev/null 2>&1
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
  return 0
}

# lane_bench_cell <attempt> — files an issue, launches the lane, waits, classifies. Sets
# CELL_ISSUE, CELL_SLUG, CELL_CLASS, CELL_ROUNDS, CELL_WALL, CELL_BUILD_MODEL, CELL_REVIEW_MODEL.
lane_bench_cell() {
  local attempt="$1" url

  # AS THE OPERATOR'S OWN IDENTITY, not the bot's: the bench measures what a lane does with a
  # ticket a human filed, and the claim comment the lane posts is the bot's own write.
  url="$( (cd "$ROOT" && "$GH_CLI" issue create --repo "$SUBSTRATE" --title "$TITLE" --body-file "$BODY") 2>&1 )" \
    || die "could not file the cell's issue on $SUBSTRATE (attempt $attempt): $url"
  CELL_ISSUE="$(printf '%s\n' "$url" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -n1)"
  [ -n "$CELL_ISSUE" ] || die "gh filed the cell's issue but printed no issue URL to read a number out of: $url"

  # THE QUEUE LABEL IS THE LANE'S INTAKE EVIDENCE. Without it `orchestrate-lean.sh` rejects the
  # launch at preflight with the resumable code, and the cell would measure a refusal.
  local lbl
  lbl="$( (cd "$ROOT" && "$GH_CLI" issue edit "$CELL_ISSUE" --repo "$SUBSTRATE" --add-label "$QUEUE_LABEL") 2>&1 )" \
    || die "could not apply the queue label '$QUEUE_LABEL' to $SUBSTRATE#$CELL_ISSUE: $lbl"

  # THE FIXTURE RECEIPT, at the path the gate computes. Intake is done once, outside the measured
  # run, so a cell measures the lane and not the interview.
  mkdir -p "$STATE_DIR" || die "cannot create the substrate's state dir at $STATE_DIR"
  cp "$RECEIPT" "$STATE_DIR/$CELL_ISSUE-ledger.md" \
    || die "cannot write the cell's receipt to $STATE_DIR/$CELL_ISSUE-ledger.md"

  local LEDGER LANE_BIN log
  LEDGER="$STATE_DIR/$CELL_ISSUE-lean-launches.tsv"
  # THE ARM'S OWN SCHEDULER, because the arm ref IS the harness under test — a cell that ran the
  # checkout's scheduler against the arm's plugins would measure a kit nobody ships. The WRAPPER,
  # by contrast, is this runner's sibling and is constant across arms: a wrapper that varied with
  # the arm would be a confound on the quantity being measured (#811 D-51).
  LANE_BIN="${LEAN_BENCH_LANE_BIN:-$ARM_WT/plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh}"
  [ -r "$LANE_BIN" ] || die "no readable lane scheduler at $LANE_BIN"
  log="$WORK/cell-$CELL_ISSUE-lane.log"

  # DETACHED UNDER `nohup`, and the ledger is what is read afterwards (#811 D-31). Both models are
  # passed explicitly and the round cap is 2, per the protocol's cost bound; the review basis is
  # fixed text so the same string appears on every cell of every arm and cannot become a variable.
  ( cd "$ROOT" || exit 1
    export LEAN_SPAWN_BIN="$HERE/lane-bench-arm.sh"
    export LEAN_ARM_MANIFEST="$MANIFEST"
    export SECOND_SHIFT_CONFIG="$CFG_ABS"
    nohup bash "$LANE_BIN" "$CELL_ISSUE" \
      --build-model opus --review-model opus \
      --review-model-basis 'lane bench: both roles pinned to one tier so a cell measures the kit' \
      --max-rounds 2 > "$log" 2>&1 &
  ) || die "could not launch the lane for $SUBSTRATE#$CELL_ISSUE"

  local poll ceiling deadline term
  poll="${LEAN_BENCH_POLL_SECS:-30}"
  ceiling="${LEAN_BENCH_CELL_CEILING_SECS:-28800}"
  deadline=$(( $(date +%s) + ceiling ))
  term=""
  while : ; do
    if [ -f "$LEDGER" ]; then
      term="$(awk -F"$TAB" '$4 == "terminal" { print $5; exit }' "$LEDGER")"
      [ -n "$term" ] && break
    fi
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep "$poll"
  done

  CELL_SLUG="$(printf '%s' "$term" | awk '{ print $1 }')"
  CELL_WALL="$(lane_bench_wall "$LEDGER")"

  if [ -z "$CELL_SLUG" ]; then
    # A LANE THAT NEVER TERMINATED is a class the bench cannot read, which is what lane-error
    # means. The slug column carries the fact rather than an empty cell, because `score` refuses a
    # row with a blank pre-score column and a blank here would be indistinguishable from a bug.
    CELL_SLUG="no-terminal-row"
    CELL_CLASS="lane-error"
  else
    CELL_CLASS="$(lane_bench_class "$CELL_SLUG" "$STATE_DIR/$CELL_ISSUE-lean-progress.md" "${BRANCH_PREFIX}${CELL_ISSUE}")"
  fi

  CELL_ROUNDS="$(git -C "$ROOT" show "${BRANCH_PREFIX}${CELL_ISSUE}:$PLANS_DIR/$REPO_SLUG-$CELL_ISSUE-lean-verdict.md" 2>/dev/null \
                 | sed -n 's/^rounds:[[:space:]]*//p' | head -n1)"

  CELL_BUILD_MODEL="$(lane_bench_model "$LEDGER" BUILD)"
  CELL_REVIEW_MODEL="$(lane_bench_model "$LEDGER" REVIEW)"
}

# lane_bench_class <slug> <progress record> <branch> — the terminal class, from the shipped table.
#
# CHOSEN BY THE CLASS PAIR, NEVER BY THE SLUG (#811 D-55). Two families in
# lane-bench-classes.tsv need a fact beyond the slug, and each is identifiable by the pair of
# classes its rows offer: `{paused, no-pr}` is decided by a milestone-1 pause-and-ask row,
# `{pr-unapproved, no-pr}` by PR presence. A slug the table does not list, or a pair this does not
# model, is `lane-error` — the bench re-runs a cell whose class it cannot read rather than
# guessing one for it.
lane_bench_class() {
  local slug="$1" progress="$2" branch="$3" classes pair
  classes="$(awk -F"$TAB" -v s="$slug" '!/^#/ && NF >= 2 && $1 == s { print $2 }' "$CLASSES" | sort -u | tr '\n' ' ')"
  pair="$(printf '%s' "$classes" | tr -s ' ' | sed 's/ $//')"
  case "$pair" in
    approved|paused|no-pr|pr-unapproved|unscorable|lane-error) printf '%s' "$pair"; return 0 ;;
    'no-pr paused')
      # 2>/dev/null rather than a preceding [ -f ]: a missing progress record and one carrying no
      # such row are the same answer here, and the two-predicate form only offers a `&&` for a
      # mutation to flip into an `||` that happens to agree on both fixtures.
      if grep -q 'pause-and-ask' "$progress" 2>/dev/null; then printf 'paused'; else printf 'no-pr'; fi
      return 0 ;;
    'no-pr pr-unapproved')
      if lane_bench_has_pr "$branch"; then printf 'pr-unapproved'; else printf 'no-pr'; fi
      return 0 ;;
    *) printf 'lane-error'; return 0 ;;
  esac
}

# lane_bench_has_pr <branch> — true when the lane branch carries at least one PR.
# A `gh` read that errors is fatal, not false: scoring an errored read as "no PR" would classify a
# cell that produced a reviewed PR as `no-pr` and drop it out of every comparison it belongs in.
lane_bench_has_pr() {
  local out rc n
  out="$( (cd "$ROOT" && "$GH_CLI" pr list --head "$1" --state all --json number) 2>&1 )"
  rc=$?
  [ "$rc" -eq 0 ] || die "could not list PRs for '$1' (gh exit $rc): $out — a read that errored is not a read that found nothing"
  n="$(printf '%s' "$out" | jq 'length' 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) die "gh returned something that is not a JSON array for '$1': $out" ;; esac
  [ "$n" -gt 0 ]
}

# lane_bench_wall <ledger> — whole minutes from the launch row to the terminal row.
#
# The epoch conversion is arithmetic in awk rather than a `date` call: the two `date` dialects
# that parse an ISO stamp take incompatible flags, and a dual-form fallback fails DIRTY — the
# wrong dialect exits non-zero having already printed nothing, and a wall figure silently becomes
# the other one's idea of "now".
lane_bench_wall() {
  local a b
  [ -f "$1" ] || return 0
  a="$(awk -F"$TAB" '$4 == "launch" { print $1; exit }' "$1")"
  b="$(awk -F"$TAB" '$4 == "terminal" { print $1; exit }' "$1")"
  [ -n "$a" ] && [ -n "$b" ] || return 0
  awk -v a="$a" -v b="$b" '
    function ep(s,   y, mo, d, h, mi, se, era, yoe, doy, doe, days) {
      y = substr(s, 1, 4) + 0; mo = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
      h = substr(s, 12, 2) + 0; mi = substr(s, 15, 2) + 0; se = substr(s, 18, 2) + 0
      if (mo <= 2) y--
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      days = era * 146097 + doe - 719468
      return days * 86400 + h * 3600 + mi * 60 + se
    }
    BEGIN { printf "%d\n", int((ep(b) - ep(a) + 30) / 60) }'
}

# lane_bench_model <ledger> <role> — the RESOLVED model id of that role's first payload session.
#
# `--model opus` is an alias that moves with releases (#811 D-46), so the row carries what the
# session actually ran. The ledger's spawn row records the CLI's SHORT id while the transcript is
# named for the full one, so the read globs on that id as a PREFIX — the glob-not-slug-derivation
# precedent of orchestrate-lean.sh's transcript_close, widened by one wildcard. More than one
# match is a refusal: two sessions whose ids share a prefix are two candidate answers, and picking
# the first would put another session's model id on this row.
lane_bench_model() {
  local sid f found n model
  sid="$(awk -F"$TAB" -v r="role=$2" '$4 == "spawn" && index($5, r) { print $5; exit }' "$1" \
         | sed -n 's/.*[[:space:]]id=\([^[:space:]]*\).*/\1/p')"
  # No spawn row for the role at all: an arm without review-toolkit terminates `review-dark` and
  # never spawns a REVIEW session. `n/a` is the same word review_catch carries for the same
  # reason, and an EMPTY column is not available — `score` refuses a row with a blank column 1..10.
  [ -n "$sid" ] || { printf 'n/a'; return 0; }
  found=""; n=0
  for f in "$HOME"/.claude/projects/*/"$sid"*.jsonl; do
    [ -f "$f" ] || continue
    found="$f"; n=$((n + 1))
  done
  [ "$n" -eq 1 ] || die "session '$sid' ($2) has $n transcript(s) under \$HOME/.claude/projects — a series is keyed on the resolved model id, so a row carrying a guessed one is worse than a missing cell"
  model="$(jq -r 'select(.type == "assistant") | .message.model // empty' "$found" 2>/dev/null | head -n1)"
  [ -n "$model" ] || die "the transcript $found carries no assistant message with a model id — the alias is exactly what this column exists not to record"
  printf '%s' "$model"
}

if [ "$SUB" = "run" ]; then
  cmd_run "$@"
  exit $?
fi

# ================================================================================================
# `score` — the cell's gold, from its PR (#812)
# ================================================================================================

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

[ -f "$CLASSES" ] || die "no terminal-class table at $CLASSES"
awk -F"$TAB" '!/^#/ && NF >= 2 && $2 == "unscorable" { found = 1 } END { exit !found }' "$CLASSES" \
  || die "$CLASSES declares no 'unscorable' class — the one value this script writes into terminal_class is not in its own table"

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
# `|| [ -n "$d_id" ]`: a hand-authored TSV whose last row carries no trailing newline would
# otherwise be read into the vars and then dropped, silently shrinking review_catch's
# denominator and skipping that defect's D-6 detector-pair refusal.
while IFS="$TAB" read -r d_id d_file d_desc d_test d_re || [ -n "$d_id" ]; do
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
  # Matched as literal fields, not as a pattern: a test id carrying an ERE metacharacter
  # would otherwise match more TEST lines than its own and mis-score defects_at_head.
  line="$(awk -v t="$t" 'NF == 3 && $1 == "TEST" && $2 == t && ($3 == "PASS" || $3 == "FAIL") { print; exit }' "$RUN_OUT")"
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
