#!/usr/bin/env bash
# retro-corpus.sh — era-aware run-corpus enumeration for pipeline-retro / perf-retro (#347).
#
# WHY THIS EXISTS. pipeline-retro and perf-retro (and stage-envelopes.sh, which perf-retro
# calls) consumed only the stage-schema shape: `.claude/pipeline-state/{issue}.json` with a
# top-level `stages` key. A lean/block run's only artifact in that directory is
# `{issue}-lean-progress.md` — wrong extension AND wrong shape — so it was invisible at
# every enumeration site. `corpus` mode enumerates BOTH schema eras side by side, each row
# labeled, so retro tooling aggregates the whole corpus instead of half of it and neither
# era errors on the other's shape (in particular: zero stage files is a normal corpus, not
# a failure, when artifact-schema rows exist — AC-1).
#
# Artifact-schema detection is STRUCTURAL (a `verdict_record:` header key), not a `-lean-`
# filename literal — the same reasoning stage-envelopes.sh's own dedup gives for avoiding
# filename literals: an undocumented future naming convention would silently miss the scan.
# A future non-lean implementation that reuses this receipt shape is covered by construction.
#
# Model identity (issue #347 comment, ratified 2026-08-03): an artifact-schema row's `model`
# field reads the `model:` key `lean-gate.sh` now writes into the progress record (and, when
# present, the verdict record) — no new per-run artifact, just one more key on the existing
# ones. A record written before that key existed, or with LEAN_RUN_MODEL never exported at
# record-creation time, reads "unknown" — a corpus label, not an error.
#
# `open-prs` mode is the second, narrower piece of #347's scope: the operator-visible
# backlog signal pipeline-retro's existing unattended branch reports — open lean-prefixed
# PRs whose linked issue has no comment yet referencing the verdict-record path. It reuses
# milestone 5's own predicate (`lean-gate.sh cmd_5`'s closing-comment check), swept across
# every open lean PR instead of one issue, so it needs no branch checkout.
#
# Usage:
#   retro-corpus.sh corpus   [--window N] [--state-dir <dir>] [--json]
#   retro-corpus.sh open-prs [--pr-list-file <path>] [--comments-dir <dir>] [--json]
#
# Seams (zero-network selftest, the stage-envelopes.sh / lean-gate.sh precedent):
#   STATECTL_STATE_DIR / SECOND_SHIFT_CONFIG / --state-dir   corpus: state-dir resolution
#   ${GH:-gh}                                                open-prs: the CLI used for reads
#   --pr-list-file <path>     open-prs: read the open-PR list from a JSON fixture instead of
#                              `gh pr list` (shape: [{number, headRefName, url}, ...])
#   --comments-dir <dir>      open-prs: read `<dir>/<issue>.json` (a comments-array fixture,
#                              the same shape `gh api .../issues/{n}/comments` returns) instead
#                              of one `gh api` call per candidate issue.
#
# Exit: 0 = enumerated (possibly empty); 2 = usage/environment error.
set -uo pipefail

GH_CLI="${GH:-gh}"
SUB="${1:-}"; shift || true
case "$SUB" in
  corpus|open-prs) : ;;
  *) echo "retro-corpus.sh: usage: retro-corpus.sh <corpus|open-prs> [options]" >&2; exit 2 ;;
esac

WINDOW=15
STATE_DIR_ARG=""
PR_LIST_FILE=""
COMMENTS_DIR=""
EMIT_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --window)        WINDOW="${2:-}"; shift 2 ;;
    --state-dir)     STATE_DIR_ARG="${2:-}"; shift 2 ;;
    --pr-list-file)  PR_LIST_FILE="${2:-}"; shift 2 ;;
    --comments-dir)  COMMENTS_DIR="${2:-}"; shift 2 ;;
    --json)          EMIT_JSON=true; shift ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "retro-corpus.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$WINDOW" in ''|*[!0-9]*) echo "retro-corpus.sh: --window must be a positive integer" >&2; exit 2 ;; esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "retro-corpus.sh: not in a git repo." >&2; exit 2; }
_common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || { echo "retro-corpus.sh: cannot resolve --git-common-dir." >&2; exit 2; }
case "$_common" in /*) : ;; *) _common="$REPO_ROOT/$_common" ;; esac
MAIN_ROOT="$(cd "$_common/.." 2>/dev/null && pwd)" \
  || { echo "retro-corpus.sh: cannot resolve the main checkout." >&2; exit 2; }

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
BRANCH_PREFIX="$(cfg '.tracker.branchPrefix' 'claude/acme-')"
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
REPO_SLUG="$(cfg "$HOST_Q" 'acme')"

# Same extraction shape lean-gate.sh / lean-reconcile.sh use on these records — a third
# reader disagreeing about what a key looks like would be a silent divergence.
record_key() { # record_key <key> <file>
  [ -f "$2" ] || return 0
  grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" "$2" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}
record_verdict() {
  [ -f "$1" ] || return 0
  grep -oE 'verdict=[A-Za-z-]+' "$1" 2>/dev/null | head -n1 | sed -E 's/^verdict=//'
}

# ============================================================== corpus mode
state_dir() {
  if [ -n "$STATE_DIR_ARG" ]; then printf '%s\n' "$STATE_DIR_ARG"; return 0; fi
  if [ -n "${STATECTL_STATE_DIR:-}" ]; then printf '%s\n' "$STATECTL_STATE_DIR"; return 0; fi
  printf '%s\n' "$MAIN_ROOT/$(cfg '.paths.pipelineStateDir' '.claude/pipeline-state')"
}

cmd_corpus() {
  local dir f stem tk sa model row rows="[]"
  dir="$(state_dir)"
  [ -d "$dir" ] || { echo "retro-corpus.sh: no state dir at $dir" >&2; exit 2; }

  # ---- stage-schema rows: has("stages"), minus both quarantine families (perf-retro Step 1 /
  # stage-envelopes.sh precedent, unchanged) ----
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in *-stale-*|*-released-*) continue ;; esac
    [ "$(jq -r 'has("stages")' "$f" 2>/dev/null)" = "true" ] || continue
    stem="$(basename "$f" .json)"
    tk="$(jq -r '.ticketKey // ""' "$f" 2>/dev/null)"
    sa="$(jq -r '.startedAt // ""' "$f" 2>/dev/null)"
    row="$(jq -n -c --arg stem "$stem" --arg tk "$tk" --arg sa "$sa" \
      '{stem: $stem, ticketKey: $tk, era: "stage", startedAt: (if $sa == "" then null else $sa end), model: "unknown"}')"
    rows="$(jq -c --argjson r "$row" '. + [$r]' <<<"$rows")"
  done

  # ---- artifact-schema rows: structural detection (a `verdict_record:` header key), never
  # a `-lean-` filename literal ----
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    grep -q '^verdict_record:' "$f" 2>/dev/null || continue
    stem="$(basename "$f" .md)"
    tk="$(record_key issue "$f")"
    model="$(record_key model "$f")"; [ -n "$model" ] || model="unknown"
    # startedAt surrogate: this record carries no header timestamp (only append-line ones do)
    # — the first append line's ISO stamp is the earliest observed activity on this run.
    sa="$(grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' "$f" 2>/dev/null | head -n1)"
    local vrel vpath hasverdict=false
    vrel="$(record_key verdict_record "$f")"
    if [ -n "$vrel" ]; then
      vpath="$REPO_ROOT/$vrel"
      [ "$(record_verdict "$vpath")" = "approve" ] && hasverdict=true
    fi
    row="$(jq -n -c --arg stem "$stem" --arg tk "$tk" --arg sa "$sa" --arg model "$model" --argjson hv "$hasverdict" \
      '{stem: $stem, ticketKey: $tk, era: "artifact", startedAt: (if $sa == "" then null else $sa end), model: $model, hasApprovedVerdict: $hv}')"
    rows="$(jq -c --argjson r "$row" '. + [$r]' <<<"$rows")"
  done

  rows="$(jq -c --argjson w "$WINDOW" '(sort_by(.startedAt // "") | reverse) | .[0:$w]' <<<"$rows")"

  if [ "$EMIT_JSON" = "true" ]; then
    printf '%s\n' "$rows"
  else
    jq -r '.[] | "\(.era)\t\(.ticketKey)\t\(.startedAt // "unknown")\t\(.model)"' <<<"$rows"
  fi
}

# ============================================================== open-prs mode
# Mirrors lean-gate.sh's derived-prefix formula (already duplicated a second time, verbatim,
# in lean-reconcile.sh's VERDICT_REL — this is the established pattern for this one small
# naming formula, not a new drift risk beyond what already exists).
lean_branch_prefix() {
  local pipeline_prefix="$1" tail derived
  case "$pipeline_prefix" in
    */*) tail="${pipeline_prefix#*/}" ;;
    *)   tail="$pipeline_prefix" ;;
  esac
  derived="lean/$tail"
  printf '%s\n' "$derived"
}

cmd_open_prs() {
  local prefix prs rows="[]" n issue vrel comments has verdictless row
  prefix="$(lean_branch_prefix "$BRANCH_PREFIX")"

  if [ -n "$PR_LIST_FILE" ]; then
    [ -f "$PR_LIST_FILE" ] || { echo "retro-corpus.sh: --pr-list-file '$PR_LIST_FILE' does not exist." >&2; exit 2; }
    prs="$(cat "$PR_LIST_FILE")"
  else
    prs="$("$GH_CLI" pr list --state open --json number,headRefName,url --limit 100 2>&1)" \
      || { echo "retro-corpus.sh: gh pr list failed: $prs" >&2; exit 2; }
  fi
  printf '%s' "$prs" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "retro-corpus.sh: open-pr list is not a JSON array." >&2; exit 2; }

  n="$(jq 'length' <<<"$prs")"
  local i=0
  while [ "$i" -lt "$n" ]; do
    local head url pr
    head="$(jq -r ".[$i].headRefName" <<<"$prs")"
    pr="$(jq -r ".[$i].number" <<<"$prs")"
    url="$(jq -r ".[$i].url" <<<"$prs")"
    i=$((i + 1))
    case "$head" in
      "$prefix"*) : ;;
      *) continue ;;
    esac
    issue="${head#"$prefix"}"
    case "$issue" in ''|*[!0-9]*) continue ;; esac

    vrel="$PLANS_DIR/$REPO_SLUG-$issue-lean-verdict.md"

    if [ -n "$COMMENTS_DIR" ]; then
      local cf="$COMMENTS_DIR/$issue.json"
      if [ -f "$cf" ]; then comments="$(cat "$cf")"; else comments="[]"; fi
    else
      comments="$("$GH_CLI" api "repos/{owner}/{repo}/issues/$issue/comments" --paginate 2>&1)" \
        || comments="[]"
    fi
    printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || comments="[]"

    has="$(jq -r --arg v "$vrel" '[ .[] | select((.body // "") | contains($v)) ] | length' <<<"$comments")"
    if [ "$has" -ge 1 ]; then verdictless=false; else verdictless=true; fi

    row="$(jq -n -c --argjson pr "$pr" --arg issue "$issue" --arg head "$head" --arg url "$url" \
      --arg vrel "$vrel" --argjson verdictLess "$verdictless" \
      '{pr: $pr, issue: ($issue | tonumber), headRefName: $head, url: $url, verdictRecord: $vrel, verdictLess: $verdictLess}')"
    rows="$(jq -c --argjson r "$row" '. + [$r]' <<<"$rows")"
  done

  if [ "$EMIT_JSON" = "true" ]; then
    printf '%s\n' "$rows"
  else
    jq -r '.[] | select(.verdictLess) | "verdict-less: PR #\(.pr) (issue #\(.issue), \(.headRefName)) — \(.url)"' <<<"$rows"
  fi
}

case "$SUB" in
  corpus)   cmd_corpus ;;
  open-prs) cmd_open_prs ;;
esac
