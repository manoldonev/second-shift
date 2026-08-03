#!/usr/bin/env bash
# lean-gate.sh — the five milestone gates of /dev-pipeline:run-lean, plus the entry
# precondition and the claim helper.
#
# WHY THIS EXISTS: run-lean is OUTCOME-gated, not process-prescribed. The harness asserts
# ARTIFACTS at five ordered milestones and is deliberately silent about the path between
# them — the session may draw on any skill surface it likes, or none. Everything this
# script checks is a file, an exit code, or a tracker record; nothing is a claim about how
# the work was done.
#
# TRUST POSTURE (D-47) — read this before adding a check here. Lean-in-run is NOT
# lean-in-enforcement. Every record this script writes is written by the agent being
# checked, so it is at best tamper-EVIDENT. The binding evidence contract lives at the
# model-free merge boundary (scripts/check-lean-chain.sh) and in the operator-side
# lean-reconcile.sh, where it costs zero run tokens. The fix-budget counter here is
# cost-control, NOT integrity: gaming it means spending more, which the cost block makes
# visible. Do not add an integrity check here and call it enforcement.
#
# AUTHORSHIP (P10) — the one property here that is a check rather than a record. Generation
# must not author evaluation's record. The BUILD role (`entry`, `claim`, `1..5`, `all`) can
# only READ the verdict record; the REVIEW role (`verdict`) can only WRITE it, and refuses to
# run inside the build session at all. Identity is role-keyed on both sides, so a review
# session that provisioned no identity is refused rather than silently inheriting the build's
# — see the RUN_ID persistence section. This one is not merely tamper-evident: the session id
# is harness-assigned, not agent-chosen.
#
# Usage:
#   lean-gate.sh entry  <issue>          entry precondition: the session's audit ledger is live.
#                                        The queue-label reject is the SESSION's step (SKILL.md
#                                        step 1) — it needs a tracker read, so it is not gated
#                                        here. Stated because the two are easy to conflate.
#   lean-gate.sh claim  <issue>          the two bot-wrapper claim writes (AC-15/D-49)
#   lean-gate.sh <1..5> <issue>          evaluate one milestone
#   lean-gate.sh all    <issue>          evaluate 1..5 in order, stop at the first failure
#   lean-gate.sh verdict <issue> --pr <n> --verdict <approve|needs-work> [--rounds <n>]
#                                        [--summary-file <path>]
#                                        REVIEW role: write the committed verdict record.
#
# Exit: 0 = satisfied / ok
#       1 = milestone failed, or a `verdict` authorship refusal (fix and retry — budget remains)
#       2 = usage or environment error
#       4 = fix budget exhausted for that milestone (hard stop; D-19)
#
# Seams (zero-network selftest; the check-pipeline-chain.sh precedent):
#   ${GH:-gh}                the CLI used for reads
#   LEAN_PROGRESS_FILE       override the resolved progress-file path
#   SECOND_SHIFT_CONFIG      override the resolved config path
#   --pr-file <path>         milestone 5: read the PR record from a JSON fixture
#   --comments-file <path>   milestone 5: read the issue comments from a JSON fixture
#
# bash 3.2 compatible (macOS ships it, and CI has a bash-3.2 lane).
set -uo pipefail

GH_CLI="${GH:-gh}"
PR_FILE=""
COMMENTS_FILE=""
VERDICT_VALUE=""
VERDICT_PR=""
VERDICT_ROUNDS=""
SUMMARY_FILE=""

# The fix budget: 3 attempts per milestone, the 4th red hard-stops (D-19). Counted from
# the progress file's `attempt` lines per D-41 — only FAILED evaluations append one.
FIX_BUDGET=3

say()  { echo "[lean-gate] $*"; }
warn() { echo "[lean-gate] $*" >&2; }
envfail() { echo "[lean-gate] $*" >&2; exit 2; }

# ---------------------------------------------------------------- argument parsing
SUB=""
ISSUE=""
POSITIONAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-file)       PR_FILE="${2:-}"; shift 2 ;;
    --comments-file) COMMENTS_FILE="${2:-}"; shift 2 ;;
    --pr)            VERDICT_PR="${2:-}"; shift 2 ;;
    --verdict)       VERDICT_VALUE="${2:-}"; shift 2 ;;
    --rounds)        VERDICT_ROUNDS="${2:-}"; shift 2 ;;
    --summary-file)  SUMMARY_FILE="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,51p' "$0"; exit 0 ;;
    -*)              envfail "unknown option: $1" ;;
    *)
      if [ "$POSITIONAL" -eq 0 ]; then SUB="$1"; POSITIONAL=1
      elif [ "$POSITIONAL" -eq 1 ]; then ISSUE="$1"; POSITIONAL=2
      else envfail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[ -n "$SUB" ]   || envfail "usage: lean-gate.sh <entry|claim|1..5|all|verdict> <issue>"
[ -n "$ISSUE" ] || envfail "usage: lean-gate.sh <entry|claim|1..5|all|verdict> <issue>"

case "$SUB" in
  entry|claim|1|2|3|4|5|all|verdict) : ;;
  *) envfail "unknown subcommand '$SUB' (expected entry|claim|1..5|all|verdict)" ;;
esac

# ---------------------------------------------------------------- roots + config
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the worktree root."

# The MAIN checkout, not the worktree: the progress file must survive worktree teardown,
# which is what makes resume work. Same --git-common-dir anchor bot-commit.sh uses.
_common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || envfail "cannot resolve --git-common-dir."
case "$_common" in
  /*) : ;;
  *)  _common="$REPO_ROOT/$_common" ;;
esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" \
  || envfail "cannot resolve the main checkout from '$_common'."

CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"

cfg() { # cfg <jq-filter> <default>
  local v
  if [ -f "$CONFIG" ]; then
    v="$(jq -r "$1" "$CONFIG" 2>/dev/null)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then echo "$v"; return 0; fi
  fi
  echo "$2"
}

PLANS_DIR="$(cfg '.paths.plansDir' 'docs/plans')"
STATE_DIR="$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
BRANCH_PREFIX="$(cfg '.tracker.branchPrefix' 'claude/acme-')"
QUEUE_LABEL="$(cfg '.tracker.labels.queue' 'ready-for-dev')"
CLAIMED_LABEL="$(cfg '.tracker.labels.claimed' 'in-progress')"
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
REPO_SLUG="$(cfg "$HOST_Q" 'acme')"
BASE_BRANCH="$(cfg "$HOST_Q as \$h | .topology.repos[\$h].baseBranch" 'main')"

# ---------------------------------------------------------------- the pinned name table
# ONE derivation, three consumers: this script, scripts/check-lean-chain.sh (running in CI
# with no access to any local convention), and lean-reconcile.sh. A name invented at any
# one of those sites instead of derived here is a drift the CI gate surfaces as a red merge
# boundary on every lean PR — see the plan's pinned-name-table section.

# Branch prefix: replace the FIRST path segment with `lean`. The REQUIRED property is
# MUTUAL non-prefix-matching against the pipeline prefix (AC-9): check-pipeline-chain.sh
# classifies with `head_ref == PREFIX*`, so `lean/` derived from `claude/second-shift-`
# would satisfy a one-directional reading while making EVERY pipeline PR applicable to the
# lean gate. Both directions are asserted below and in the selftest.
lean_branch_prefix() {
  local pipeline_prefix="$1" tail derived
  case "$pipeline_prefix" in
    */*) tail="${pipeline_prefix#*/}" ;;
    *)   tail="$pipeline_prefix" ;;
  esac
  derived="lean/$tail"
  # Pathological input (a configured prefix already under lean/) collapses the two onto
  # each other. Fail loudly rather than return a colliding prefix — a silent collision
  # double-classifies every PR in both gates.
  case "$pipeline_prefix" in
    "$derived"*) echo "[lean-gate] configured tracker.branchPrefix '$pipeline_prefix' collides with the derived lean prefix '$derived' — they must be mutually non-prefix-matching." >&2; return 1 ;;
  esac
  case "$derived" in
    "$pipeline_prefix"*) echo "[lean-gate] derived lean prefix '$derived' prefix-matches the pipeline prefix '$pipeline_prefix' — refusing." >&2; return 1 ;;
  esac
  echo "$derived"
}

LEAN_BRANCH_PREFIX="$(lean_branch_prefix "$BRANCH_PREFIX")" || exit 2
SPEC_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean.md"
VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"
PROGRESS_FILE="${LEAN_PROGRESS_FILE:-$MAIN_ROOT/$STATE_DIR/$ISSUE-lean-progress.md}"

# ---------------------------------------------------------------- RUN_ID persistence
# SKILL.md step 2 says "export RUN_ID first ... it keys every record" — true only if the
# operator's shell survives from `claim` through every later `bash G <n> <issue>` call.
# It does not: this tool is routinely invoked as ONE-SHOT subprocesses (a fresh shell per
# call, only cwd inherited), so an export in the claim call is gone by the next one, and
# every record after it silently stamps `run_id: unset` — exactly the mismatch
# lean-reconcile.sh exists to catch (observed live on #306: claim/verdict carried the real
# id, the progress-file header did not). Fix at the ROOT rather than leaning harder on the
# operator to keep re-exporting it: cache the id to a file the FIRST time it is seen (any
# call made with $RUN_ID set — claim is typically first), and every call without $RUN_ID
# in its own environment reads the cache instead of falling back to "unset".
#
# ROLE-KEYED (P10). There are two caches, not one, and neither role may read the other's.
# Before this split, ANY invocation without an exported RUN_ID resolved the issue's single
# cached id — so a review session working the same issue would stamp the BUILD run's identity
# into the verdict record and the authorship check would compare a value against itself. The
# review role therefore resolves `<issue>-review-run-id` and, finding nothing, resolves
# NOTHING: `verdict` refuses rather than falling through to the build cache. Silent inheritance
# is the exact failure this separation exists to make impossible.
RUN_ID_CACHE="$MAIN_ROOT/$STATE_DIR/$ISSUE-run-id"
REVIEW_RUN_ID_CACHE="$MAIN_ROOT/$STATE_DIR/$ISSUE-review-run-id"
resolve_cached_id() { # resolve_cached_id <cache-path> <persist:0|1>
  if [ -n "${RUN_ID:-}" ]; then
    if [ "$2" = "1" ]; then
      mkdir -p "$(dirname "$1")" 2>/dev/null && printf '%s' "$RUN_ID" > "$1"
    fi
    printf '%s' "$RUN_ID"
  elif [ -s "$1" ]; then
    cat "$1"
  else
    printf 'unset'
  fi
}
if [ "$SUB" = "verdict" ]; then
  # Resolve WITHOUT persisting. The review identity is cached only once the record is actually
  # written (see cmd_verdict), so a REFUSED call cannot seed the cache — otherwise one rejected
  # attempt would make the next call's "no review identity provisioned" refusal vanish, which is
  # the same silent-inheritance failure in a slower form.
  RESOLVED_RUN_ID="$(resolve_cached_id "$REVIEW_RUN_ID_CACHE" 0)"
else
  RESOLVED_RUN_ID="$(resolve_cached_id "$RUN_ID_CACHE" 1)"
fi

# First `<key>: <token>` in a file, HTML-comment or bare form. Deliberately the SAME extraction
# shape lean-reconcile.sh uses on the same records — two readers of one schema that disagreed
# about what a key looks like would be a silent divergence, not a loud one.
record_key() { # record_key <key> <file>
  [ -f "$2" ] || return 0
  grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# ---------------------------------------------------------------- progress-file primitives
# Append-only markdown. Line shapes are PINNED — check-lean-chain.sh does not read this
# file (it is gitignored and never reaches CI), but lean-reconcile.sh does, and the
# fix-budget counter is derived from it.
#
#   <iso> | milestone-<n> | attempt | <reason>
#   <iso> | milestone-<n> | satisfied
#   milestone-4 | verdict=<approve|needs-work> | round=<n>
#
# Reconciliation keys (AC-14) ride in the header so a run predating #292's general
# verifier stays reconcilable after it lands.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

ensure_progress_file() {
  local dir
  dir="$(dirname "$PROGRESS_FILE")"
  [ -d "$dir" ] || mkdir -p "$dir" || envfail "cannot create progress dir '$dir'."
  if [ ! -f "$PROGRESS_FILE" ]; then
    {
      echo "# lean run — issue $ISSUE"
      echo ""
      echo "run_id: $RESOLVED_RUN_ID"
      echo "session_id: ${CLAUDE_CODE_SESSION_ID:-unset}"
      echo "issue: $ISSUE"
      echo "branch_prefix: $LEAN_BRANCH_PREFIX"
      echo "spec: $SPEC_REL"
      echo "verdict_record: $VERDICT_REL"
      echo ""
    } > "$PROGRESS_FILE"
  fi
}

append_line() { ensure_progress_file; echo "$1" >> "$PROGRESS_FILE"; }

# grep -c, never grep -q: -q exits at the first match, the producer takes SIGPIPE, and
# `set -o pipefail` turns that into a pipeline failure — the documented class that made a
# sibling gate report "absent" precisely when the token was found EARLY in a LONG file.
#
# And never `grep -c … || echo 0`: on zero matches grep PRINTS "0" *and* exits 1, so the
# fallback appends a second "0" and every caller then trips "integer expression expected".
# Capture first, default on the assignment.
count_matches() { # count_matches <pattern> <file> [extra grep args...]
  local pat="$1" file="$2" n
  shift 2
  [ -f "$file" ] || { echo 0; return 0; }
  n="$(grep -c "$@" -- "$pat" "$file" 2>/dev/null)" || n=0
  [ -n "$n" ] || n=0
  echo "$n"
}

# D-41: ONLY a failed evaluation appends an `attempt` line.
append_attempt() { append_line "$(now_iso) | milestone-$1 | attempt | $2"; }

# D-41: a passing evaluation appends AT MOST ONE `satisfied` line per milestone, so
# diagnostic re-runs and `all` sweeps never inflate anything. Idempotent by construction.
append_satisfied() {
  ensure_progress_file
  if [ "$(count_matches "| milestone-$1 | satisfied" "$PROGRESS_FILE" -F)" -eq 0 ]; then
    append_line "$(now_iso) | milestone-$1 | satisfied"
  fi
}

attempt_count() { count_matches "| milestone-$1 | attempt |" "$PROGRESS_FILE" -F; }

# A failed milestone: record the attempt, then decide retry-vs-hard-stop.
fail_milestone() {
  local n="$1" reason="$2" count
  append_attempt "$n" "$reason"
  count="$(attempt_count "$n")"
  warn "✗ milestone-$n: $reason (attempt $count/$FIX_BUDGET)"
  if [ "$count" -gt "$FIX_BUDGET" ]; then
    append_line "$(now_iso) | milestone-$n | budget-exhausted | $count attempts"
    warn "milestone-$n has exhausted its $FIX_BUDGET-attempt fix budget — hard stop."
    return 4
  fi
  return 1
}

pass_milestone() { append_satisfied "$1"; say "✓ milestone-$1${2:+: $2}"; return 0; }

# ---------------------------------------------------------------- entry precondition
# AC-14. The predicate is a NON-EMPTY ledger file for THIS session, anchored at the main
# checkout. Directory existence is explicitly NOT the test — an empty or absent per-session
# file means the hook never fired, and a run whose tool calls left no ledger cannot be
# reconciled by lean-reconcile.sh (or by #292 later). Fail closed.
cmd_entry() {
  local sid ledger
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$sid" ]; then
    warn "✗ entry: CLAUDE_CODE_SESSION_ID is unset — the session's audit ledger cannot be located. Refusing to start."
    return 1
  fi
  ledger="$MAIN_ROOT/.claude/audit/$sid.jsonl"
  if [ ! -s "$ledger" ]; then
    warn "✗ entry: audit ledger '$ledger' is missing or empty — the hook ledger is not live. Refusing to start."
    warn "  Every lean record carries reconciliation keys; without a ledger the run is unverifiable at the merge boundary."
    return 1
  fi
  say "✓ entry: audit ledger live ($(wc -l < "$ledger" | tr -d ' ') lines)."
  return 0
}

# ---------------------------------------------------------------- claim (AC-15 / D-49)
# TWO bot-wrapper writes. Both must be the bot: check-lean-chain.sh filters the comment
# trail on `.user.type == "Bot"`, so an operator-posted claim comment is INVISIBLE to it
# and the merge-boundary gate would fail a legitimately-claimed PR.
cmd_claim() {
  local helper body url
  helper="$(dirname "$(cd "$(dirname "$0")" && pwd)")/run/tools/claim-issue.sh"
  [ -f "$helper" ] || envfail "claim-issue.sh not found at '$helper'."

  # (i) the label swap — reuses the pipeline's add-before-remove + confirm-before-DELETE
  # discipline rather than reimplementing it.
  bash "$helper" "$ISSUE" --queue "$QUEUE_LABEL" --claimed "$CLAIMED_LABEL" \
    || { warn "✗ claim: label swap failed — '$QUEUE_LABEL' left intact."; return 1; }

  # (ii) the marker comment. `lean-claimed`, NEVER `stage: claimed` — a lean-distinct
  # marker so this comment can never pollute check-pipeline-chain.sh's run-family
  # selection if the same issue is later run through full `run`.
  body="$(mktemp -t lean-claim.XXXXXX)" || envfail "mktemp failed."
  {
    echo "<!-- dev-pipeline -->"
    echo "<!-- run_id: $RESOLVED_RUN_ID -->"
    echo "<!-- stage: lean-claimed -->"
    echo ""
    echo "🤖 Claimed by \`/dev-pipeline:run-lean\`."
  } > "$body"
  url="$("${GH_BOT:?GH_BOT must point at the bot wrapper}" api -X POST \
        "repos/{owner}/{repo}/issues/$ISSUE/comments" -F body=@"$body" --jq .html_url 2>&1)"
  local rc=$?
  rm -f "$body"
  [ "$rc" -eq 0 ] || { warn "✗ claim: marker comment failed: $url"; return 1; }
  say "✓ claim: labels swapped and lean-claimed comment posted ($url)"
  return 0
}

# ---------------------------------------------------------------- milestone 1: spec/AC
# AC-3, as resolved at intake (G-1): existence AT THE PINNED PATH plus >= 1 numbered AC-n,
# and NO further content assertion. The path predicate is not an extra check — it is which
# file "exists" means, and check-lean-chain.sh keys its artifact scan off the same shape.
cmd_1() {
  local spec="$REPO_ROOT/$SPEC_REL" n
  [ -f "$spec" ] || { fail_milestone 1 "no committed spec at $SPEC_REL"; return $?; }
  n="$(count_matches '(^|[^A-Za-z])AC-[0-9]+' "$spec" -E)"
  [ "$n" -ge 1 ] || { fail_milestone 1 "spec $SPEC_REL carries no numbered AC-n criterion"; return $?; }
  pass_milestone 1 "$SPEC_REL ($n AC-n reference(s))"
}

# ---------------------------------------------------------------- milestone 2: policy
# D-13: EXACTLY the feature-PR half of CI's pr-gates, run pre-PR so violations die in the
# worktree. Excluded on purpose: the chain gate (not-applicable by prefix), the
# release-PR-only gates (on a feature branch they INVERT check-frozen-files.sh), and the
# lockstep/namespace checks (already covered by milestone 3's selftest sweep).
#
# D-44: these are second-shift REPO artifacts, not plugin payload. Outside this repo the
# gate detects their absence and prints a skip notice — never a silent pass.
cmd_2() {
  local base="origin/$BASE_BRANCH" frozen="$REPO_ROOT/scripts/check-frozen-files.sh"
  local trailer="$REPO_ROOT/scripts/check-changelog-trailer.sh" out rc

  if [ ! -f "$frozen" ] && [ ! -f "$trailer" ]; then
    say "milestone-2: policy gate scripts not present in this repo — SKIPPED (consumer repo; these are second-shift artifacts, not plugin payload)."
    append_line "$(now_iso) | milestone-2 | skipped | policy gate scripts absent (consumer repo)"
    pass_milestone 2 "skipped (consumer repo)"
    return 0
  fi

  if [ -f "$frozen" ]; then
    out="$(cd "$REPO_ROOT" && bash "$frozen" "$base" 2>&1)"; rc=$?
    # The ADVISORY tier (.github/workflows/** rows) prints and continues, so exit code
    # alone loses it. Surface it into the progress file rather than dropping it.
    case "$out" in
      *advisory*|*ADVISORY*)
        append_line "$(now_iso) | milestone-2 | advisory | $(printf '%s' "$out" | tr '\n' ' ')" ;;
    esac
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      fail_milestone 2 "check-frozen-files.sh failed (rc=$rc)"; return $?
    fi
  else
    say "milestone-2: check-frozen-files.sh absent — skip notice."
  fi

  if [ -f "$trailer" ]; then
    out="$(cd "$REPO_ROOT" && bash "$trailer" "$base" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      fail_milestone 2 "check-changelog-trailer.sh failed (rc=$rc)"; return $?
    fi
  else
    say "milestone-2: check-changelog-trailer.sh absent — skip notice."
  fi

  pass_milestone 2 "policy invariants hold against $base"
}

# ---------------------------------------------------------------- milestone 3: green
# D-17: the config commands table DIRECTLY — no verifyctl, and deliberately NO inert-diff
# lane. In a repo whose diffs are mostly shell and markdown, the inert lane would skip the
# suite on exactly the changes that need it most.
cmd_3() {
  local cmd rc sweep
  # lanes[] setup steps first, when present.
  if [ -f "$CONFIG" ]; then
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      say "milestone-3: lane » $cmd"
      ( cd "$REPO_ROOT" && eval "$cmd" ); rc=$?
      [ "$rc" -eq 0 ] || { fail_milestone 3 "lane failed (rc=$rc): $cmd"; return $?; }
    done < <(jq -r --arg s "$REPO_SLUG" '(.commands[$s].lanes // []) | .[] | (.command // .)' "$CONFIG" 2>/dev/null)
  fi

  local key
  for key in lint typecheck test build; do
    cmd="$(cfg ".commands[\"$REPO_SLUG\"].$key" '')"
    [ -n "$cmd" ] || { say "milestone-3: $key is null — skipped."; continue; }
    say "milestone-3: $key » $cmd"
    ( cd "$REPO_ROOT" && eval "$cmd" ); rc=$?
    [ "$rc" -eq 0 ] || { fail_milestone 3 "$key failed (rc=$rc)"; return $?; }
  done

  # D-18: the diff-scoped mutation sweep when the target repo carries one. Absent is a
  # PRINTED skip, never silent — a missing test-the-tests lane must be visible.
  sweep="$REPO_ROOT/tools/mutation-sweep.sh"
  if [ -f "$sweep" ]; then
    say "milestone-3: mutation sweep (diff-scoped) » origin/$BASE_BRANCH"
    ( cd "$REPO_ROOT" && bash "$sweep" --mode pr --base "origin/$BASE_BRANCH" ); rc=$?
    [ "$rc" -eq 0 ] || { fail_milestone 3 "mutation sweep failed (rc=$rc)"; return $?; }
  else
    say "milestone-3: tools/mutation-sweep.sh absent — mutation sweep SKIPPED (notice, not a silent pass)."
    append_line "$(now_iso) | milestone-3 | skipped | mutation-sweep.sh absent"
  fi

  pass_milestone 3 "green gate"
}

# ---------------------------------------------------------------- milestone 4: review
# D-22/D-46: the COMMITTED verdict record is the record of record. The progress-file line
# is a local counter only — the lean chain gate re-asserts the committed record at the
# merge boundary, so a hand-typed local line cannot reach a merge.
#
# READ-ONLY BY CONSTRUCTION. This milestone never writes to the verdict record — not to
# create it, not to stamp it, not to "normalize" it. The build session's only relationship
# to that file is reading one somebody else wrote; the moment this function can write it,
# the P10 separation below is decorative. The suite asserts the file is byte- and
# mtime-identical across a full `all` sweep.
cmd_4() {
  local rec="$REPO_ROOT/$VERDICT_REL" v_run v_sess b_prog_run b_prog_sess b_cached cand
  [ -f "$rec" ] || { fail_milestone 4 "no committed verdict record at $VERDICT_REL"; return $?; }
  if [ "$(count_matches 'verdict=approve' "$rec" -F)" -eq 0 ]; then
    fail_milestone 4 "verdict record $VERDICT_REL does not read verdict=approve"; return $?
  fi
  # The reconciliation keys are what make the record checkable against the audit ledger.
  v_run="$(record_key run_id "$rec")"
  v_sess="$(record_key session_id "$rec")"
  if [ -z "$v_run" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no run_id reconciliation key"; return $?
  fi
  if [ -z "$v_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL carries no session_id reconciliation key — the review session's audit ledger cannot be located, so the verdict is unreconcilable"; return $?
  fi

  # AUTHORSHIP (P10). THREE build identities are compared, not one:
  #   - the id resolved for THIS invocation (env or build cache),
  #   - the id sitting in the build run-id cache file,
  #   - the id the build run stamped into the progress-file header.
  # The cache arm is the load-bearing one. A review session that never provisioned its own
  # RUN_ID used to resolve the BUILD cache, and the record it wrote then looked "distinct"
  # only in the sense that nobody had checked. Comparing against the cache file directly
  # catches that whether or not this invocation happens to have RUN_ID in its environment.
  b_cached=""; [ -s "$RUN_ID_CACHE" ] && b_cached="$(cat "$RUN_ID_CACHE")"
  b_prog_run="$(record_key run_id "$PROGRESS_FILE")"
  b_prog_sess="$(record_key session_id "$PROGRESS_FILE")"
  for cand in "$RESOLVED_RUN_ID" "$b_cached" "$b_prog_run"; do
    [ -n "$cand" ] || continue
    if [ "$v_run" = "$cand" ]; then
      fail_milestone 4 "verdict record $VERDICT_REL carries the BUILD run's identity ('$v_run') — the session that wrote the code may not author its own review verdict (P10). Produce the record from a separate review session: 'lean-gate.sh verdict $ISSUE --pr <n> --verdict approve'."
      return $?
    fi
  done
  if [ -n "$b_prog_sess" ] && [ "$v_sess" = "$b_prog_sess" ]; then
    fail_milestone 4 "verdict record $VERDICT_REL names the BUILD session ('$v_sess') as its author — the review must run in a separate context (P10)."
    return $?
  fi

  pass_milestone 4 "$VERDICT_REL reads verdict=approve, authored by review run $v_run"
}

# ---------------------------------------------------------------- verdict (REVIEW role)
# The ONLY write path to the verdict record, and it lives in this script rather than a second
# one for a single reason: the pinned name table above is the sole derivation of VERDICT_REL,
# and a name invented at a second site is exactly the drift the merge-boundary gate turns red.
#
# It never evaluates a milestone, never appends to the progress file (that file belongs to the
# build run), and never touches the build run-id cache. Those omissions are what let milestone
# 4 stay a pure read while the record still comes from here.
#
# The refusals are ordered cheapest-first and every one of them fails CLOSED. In particular a
# build run whose progress header records no session id is refused outright: without it there
# is nothing to separate the review from, and "unverifiable" must never resolve to "fine".
cmd_verdict() {
  local sess b_prog_sess b_prog_run b_cached rec body c
  sess="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sess" ] \
    || envfail "verdict: CLAUDE_CODE_SESSION_ID is unset — the review session cannot be identified, so its authorship cannot be separated from the build's."
  [ -f "$PROGRESS_FILE" ] \
    || envfail "verdict: no build progress file at $PROGRESS_FILE — there is no build run on #$ISSUE to review."

  b_prog_sess="$(record_key session_id "$PROGRESS_FILE")"
  b_prog_run="$(record_key run_id "$PROGRESS_FILE")"
  b_cached=""; [ -s "$RUN_ID_CACHE" ] && b_cached="$(cat "$RUN_ID_CACHE")"

  if [ -z "$b_prog_sess" ] || [ "$b_prog_sess" = "unset" ]; then
    warn "✗ verdict: the build progress file records no session id, so authorship separation is unverifiable. Refusing."
    return 1
  fi
  if [ "$sess" = "$b_prog_sess" ]; then
    warn "✗ verdict: this IS the build session ($sess) — the build session may not author its own review verdict (P10)."
    warn "  Run the review from a fresh top-level session: /dev-pipeline:review-lean <pr>."
    return 1
  fi

  if [ "$RESOLVED_RUN_ID" = "unset" ]; then
    warn "✗ verdict: no review identity provisioned. Export RUN_ID (e.g. review-$ISSUE-1) before the first verdict call; it is cached at $REVIEW_RUN_ID_CACHE for later ones."
    warn "  The build cache at $RUN_ID_CACHE is deliberately NOT consulted — inheriting the build's id would defeat the separation this refusal exists for."
    return 1
  fi
  for c in "$b_prog_run" "$b_cached"; do
    [ -n "$c" ] || continue
    if [ "$RESOLVED_RUN_ID" = "$c" ]; then
      warn "✗ verdict: the review identity '$RESOLVED_RUN_ID' IS the build run's. Provision a distinct RUN_ID for the review session."
      return 1
    fi
  done

  case "$VERDICT_VALUE" in
    approve|needs-work) : ;;
    *) envfail "verdict: --verdict must be 'approve' or 'needs-work' (got '$VERDICT_VALUE')." ;;
  esac
  [ -n "$VERDICT_PR" ] || envfail "verdict: --pr <number> is required — the record names the PR it reviewed."
  [ -n "$VERDICT_ROUNDS" ] || VERDICT_ROUNDS=1
  case "$VERDICT_ROUNDS" in
    ''|*[!0-9]*) envfail "verdict: --rounds must be a positive integer (got '$VERDICT_ROUNDS')." ;;
  esac

  body=""
  if [ -n "$SUMMARY_FILE" ]; then
    [ -f "$SUMMARY_FILE" ] || envfail "verdict: --summary-file '$SUMMARY_FILE' does not exist."
    body="$(cat "$SUMMARY_FILE")"
  fi

  rec="$REPO_ROOT/$VERDICT_REL"
  mkdir -p "$(dirname "$rec")" || envfail "verdict: cannot create '$(dirname "$rec")'."
  # Cache the review identity only now — every refusal above has passed, so this is a real
  # review round and later calls in the same round may resolve it from a fresh shell.
  mkdir -p "$(dirname "$REVIEW_RUN_ID_CACHE")" 2>/dev/null \
    && printf '%s' "$RESOLVED_RUN_ID" > "$REVIEW_RUN_ID_CACHE"
  {
    echo "# lean review verdict — #$ISSUE"
    echo ""
    echo "verdict=$VERDICT_VALUE"
    echo "run_id: $RESOLVED_RUN_ID"
    echo "session_id: $sess"
    echo "rounds: $VERDICT_ROUNDS"
    echo "pr: #$VERDICT_PR"
    echo ""
    if [ -n "$body" ]; then printf '%s\n' "$body"; fi
  } > "$rec"

  say "✓ verdict: $VERDICT_REL written (verdict=$VERDICT_VALUE, run_id=$RESOLVED_RUN_ID, round $VERDICT_ROUNDS)"
  say "  It is evidence only once COMMITTED to the PR's head branch — commit and push it."
  return 0
}

# ---------------------------------------------------------------- milestone 5: exit
# D-42: the most externally-visible artifacts are GATED, not prose-mandated.
cmd_5() {
  local pr comments url draft body

  # "Progress file current" is asserted as: milestones 1-4 each left a `satisfied` record.
  #
  # NOT as "the file exists". That check cannot hold: failing any milestone appends an
  # attempt line, appending creates the file, so a bare existence check heals itself between
  # the first run and the second — it reports absent once and passes forever after, which is
  # worse than not checking at all. Asserting the 1-4 records is stable (an M5 attempt line
  # never satisfies M1-4) and is what the contract actually means.
  local m missing=""
  for m in 1 2 3 4; do
    [ "$(count_matches "| milestone-$m | satisfied" "$PROGRESS_FILE" -F)" -ge 1 ] || missing="$missing $m"
  done
  if [ -n "$missing" ]; then
    fail_milestone 5 "progress file is not current — milestone(s)$missing left no satisfied record, so there is nothing to certify"
    return $?
  fi

  if [ -n "$PR_FILE" ]; then
    [ -f "$PR_FILE" ] || envfail "--pr-file '$PR_FILE' does not exist."
    pr="$(cat "$PR_FILE")"
  else
    pr="$("$GH_CLI" pr list --head "$LEAN_BRANCH_PREFIX$ISSUE" --state open \
          --json number,url,body,isDraft --limit 1 2>&1)" \
      || { warn "$pr"; fail_milestone 5 "could not list PRs for $LEAN_BRANCH_PREFIX$ISSUE"; return $?; }
  fi
  printf '%s' "$pr" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { fail_milestone 5 "no open PR found for branch $LEAN_BRANCH_PREFIX$ISSUE"; return $?; }

  draft="$(printf '%s' "$pr" | jq -r '.[0].isDraft')"
  body="$(printf '%s' "$pr" | jq -r '.[0].body // ""')"
  url="$(printf '%s' "$pr" | jq -r '.[0].url')"

  [ "$draft" = "false" ] || { fail_milestone 5 "PR $url is still a draft (D-27 requires a ready PR)"; return $?; }
  # Same capture-first discipline as count_matches — these read a string, not a file.
  local n_closes n_spec
  n_closes="$(printf '%s' "$body" | grep -c -i -E "closes[[:space:]]+#$ISSUE")" || n_closes=0
  [ "$n_closes" -ge 1 ] \
    || { fail_milestone 5 "PR body carries no 'Closes #$ISSUE'"; return $?; }
  n_spec="$(printf '%s' "$body" | grep -c -F -- "$SPEC_REL")" || n_spec=0
  [ "$n_spec" -ge 1 ] \
    || { fail_milestone 5 "PR body does not link the committed spec ($SPEC_REL)"; return $?; }

  if [ -n "$COMMENTS_FILE" ]; then
    [ -f "$COMMENTS_FILE" ] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
    comments="$(cat "$COMMENTS_FILE")"
  else
    comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$ISSUE/comments" --paginate 2>&1)" \
      || { warn "$comments"; fail_milestone 5 "could not fetch the comment trail for #$ISSUE"; return $?; }
  fi
  printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || envfail "comment trail is not a JSON array."

  # The closing comment must REFERENCE the verdict record — that reference is what ties
  # the tracker record to the committed artifact the chain gate checks.
  local closing
  closing="$(printf '%s' "$comments" | jq -r --arg v "$VERDICT_REL" \
    '[ .[] | select((.body // "") | contains($v)) ] | length')"
  [ "$closing" -ge 1 ] \
    || { fail_milestone 5 "no closing comment on #$ISSUE references the verdict record ($VERDICT_REL)"; return $?; }

  pass_milestone 5 "exit artifacts present ($url)"
}

# ---------------------------------------------------------------- all
# G-2, load-bearing: `satisfied` is a RECORD, not a CACHE. Every milestone is re-evaluated
# against the CURRENT tree on every sweep. Short-circuiting on a stored `satisfied` line is
# exactly how a green gate from before a milestone-4 fix round would certify code that
# never passed it.
run_milestone() { # explicit dispatch, not "cmd_$1": an indirect call hides every callee
  case "$1" in                        # from static analysis (shellcheck SC2329) and from
    1) cmd_1 ;;                       # a reader grepping for call sites.
    2) cmd_2 ;;
    3) cmd_3 ;;
    4) cmd_4 ;;
    5) cmd_5 ;;
    *) envfail "run_milestone: unknown milestone '$1'" ;;
  esac
}

cmd_all() {
  local n rc
  for n in 1 2 3 4 5; do
    run_milestone "$n"; rc=$?
    if [ "$rc" -ne 0 ]; then
      say "all: stopped at milestone-$n (rc=$rc)"
      return "$rc"
    fi
  done
  say "all: milestones 1-5 satisfied."
  return 0
}

# ---------------------------------------------------------------- dispatch
case "$SUB" in
  entry)   cmd_entry ;;
  claim)   cmd_claim ;;
  verdict) cmd_verdict ;;
  all)     cmd_all ;;
  *)       run_milestone "$SUB" ;;
esac
exit $?
