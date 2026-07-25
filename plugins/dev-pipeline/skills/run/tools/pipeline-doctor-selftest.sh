#!/usr/bin/env bash
#
# pipeline-doctor-selftest.sh — behavioral coverage for the ONE pure branch of
# tools/pipeline-doctor.sh: block 8's stale-claim classifier.
#
# INVARIANT GUARDED: an orphaned run (status in_progress, last state write >= 30
# min ago) is surfaced to the operator, and nothing else is. Both directions are
# load-bearing. A false negative hides a stranded claim from the queue forever —
# the issue stays invisible and unclaimable. A false positive tells the operator
# to reclaim a run a live session still owns, which corrupts that run's worktree.
#
# WHY NO SCENARIO COVERS IT (CLAUDE.md scenario-first rule): scenario-liveness-
# selftest.sh composes verdict paths that reach a terminal WRITE — statectl
# transitions, gate verdicts, PR-shaped outcomes. Block 8 writes nothing. It is a
# read-only operator diagnostic that runs OUTSIDE any pipeline run, over state
# files left behind by runs that already died. There is no verdict path to
# compose it onto, so a scenario cannot reach it.
#
# TECHNIQUE: extract-and-execute, not grep. The classifier block is delimited in
# pipeline-doctor.sh by `# >>> stale-claim-classify` / `# <<< stale-claim-classify`
# and is re-hosted here inside our own loop (the block's `continue` is why it must
# run in a loop). We execute the REAL production block against fixture state dirs
# — a hand-copied predicate would be the mirror harness CLAUDE.md bans, and a grep
# for the `case` pattern would be the prose-presence guard it also bans.
#
# The rest of pipeline-doctor.sh is deliberately NOT covered here: blocks 1-7 shell
# out to gh, the network, and sibling selftests, so running them would violate the
# operator-safety contract (no gh, no network in tests). Their branch conditions
# are covered in isolation by tools/prose-budget-selftest.sh T11.
#
# Operator-safe: no gh, no network, no Claude CLI. bash-3.2-safe. Runs in CI via
# the '*-selftest.sh' discovery loop.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="${PIPELINE_DOCTOR:-$SCRIPT_DIR/pipeline-doctor.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

command -v jq >/dev/null 2>&1 || {
  echo "pipeline-doctor-selftest: FAIL — jq is required to execute the extracted classifier." >&2
  exit 1
}
[[ -f "$DOCTOR" ]] || {
  echo "pipeline-doctor-selftest: FAIL — pipeline-doctor.sh not found at $DOCTOR" >&2
  exit 1
}

# --- extract the production classifier ----------------------------------------
CLASSIFY_BLOCK="$(sed -n '/# >>> stale-claim-classify/,/# <<< stale-claim-classify/p' "$DOCTOR")"
if [[ -z "$CLASSIFY_BLOCK" ]]; then
  echo "pipeline-doctor-selftest: FAIL — stale-claim-classify sentinels not found in $DOCTOR." >&2
  echo "  (block 8 was refactored without updating this suite — that is the regression this guard exists for)" >&2
  exit 1
fi

WORK="$(mktemp -d -t pipeline-doctor-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ISO8601-Z timestamp N seconds in the past, computed by jq so it is portable
# across BSD and GNU date.
ago() { jq -rn --argjson s "$1" 'now - $s | todate'; }

# Write a fixture state file into the case dir $D. mkstate <filename> <status>
# <age-seconds> [extra-jq]; extra-jq lets a case corrupt a single field without
# re-spelling the whole doc.
#
# Hard-fails on a bad write. Every negative case here asserts SILENCE, so a
# fixture that never lands makes the whole suite green for the wrong reason —
# the exact false-green this file exists to prevent. Caught in development when
# mkstate wrote to $WORK instead of $D: 6 cases "passed" against empty dirs.
mkstate() {
  local name="$1" st_val="$2" age="$3" extra="${4:-.}"
  jq -n --arg key "${name%%.*}" --arg st "$st_val" --arg ts "$(ago "$age")" '
    { ticketKey: $key, runId: "run-fixture", status: $st,
      currentStage: 5, lastUpdatedAt: $ts, stages: { "5": { status: "started" } } }
  ' | jq "$extra" > "$D/$name"
  if [[ ! -s "$D/$name" ]] || ! jq empty "$D/$name" 2>/dev/null; then
    echo "pipeline-doctor-selftest: FAIL — fixture $D/$name did not write as valid JSON" >&2
    exit 1
  fi
}

# Run the REAL extracted block over every *.json in a dir; echo the emitted lines.
run_classifier() { # run_classifier <state-dir>
  local sf stale_line
  for sf in "$1"/*.json; do
    [[ -f "$sf" ]] || continue
    # shellcheck disable=SC2034  # $sf is consumed by the eval'd production block
    eval "$CLASSIFY_BLOCK"
    [[ -n "$stale_line" ]] && printf '%s\n' "$stale_line"
  done
  return 0
}

# ---------------------------------------------------------------------------
# (d1) the fail direction: an orphaned in_progress run IS surfaced
# ---------------------------------------------------------------------------
D="$WORK/d1"; mkdir -p "$D"
mkstate 4001.json in_progress 3600
out="$(run_classifier "$D")"
if [[ "$out" == *"4001"* && "$out" == *"stage=5"* && "$out" == *"min-ago"* ]]; then
  ok "(d1) in_progress 60min → surfaced, with ticket key + stage + age"
else
  bad "(d1) in_progress 60min → expected a stale line, got: [$out]"
fi

# ---------------------------------------------------------------------------
# (d2) the 30-minute boundary — the threshold is the whole contract
# ---------------------------------------------------------------------------
D="$WORK/d2"; mkdir -p "$D"
mkstate 4002.json in_progress 120        # 2 min — fresh
out="$(run_classifier "$D")"
[[ -z "$out" ]] && ok "(d2a) in_progress 2min → not stale" \
  || bad "(d2a) in_progress 2min → expected silence, got: [$out]"

D="$WORK/d2b"; mkdir -p "$D"
mkstate 4003.json in_progress 1860       # 31 min — just over
out="$(run_classifier "$D")"
[[ "$out" == *"4003"* ]] && ok "(d2b) in_progress 31min → stale (>= 30 boundary holds)" \
  || bad "(d2b) in_progress 31min → expected a stale line, got: [$out]"

D="$WORK/d2c"; mkdir -p "$D"
mkstate 4004.json in_progress 1740       # 29 min — just under
out="$(run_classifier "$D")"
[[ -z "$out" ]] && ok "(d2c) in_progress 29min → not stale (< 30 boundary holds)" \
  || bad "(d2c) in_progress 29min → expected silence, got: [$out]"

# ---------------------------------------------------------------------------
# (d3) terminal states are never stale, however old — they exited by contract
# ---------------------------------------------------------------------------
D="$WORK/d3"; mkdir -p "$D"
mkstate 4005.json completed 86400
mkstate 4006.json failed    86400
out="$(run_classifier "$D")"
[[ -z "$out" ]] && ok "(d3) completed + failed at 24h → never stale (terminal by contract)" \
  || bad "(d3) terminal states → expected silence, got: [$out]"

# ---------------------------------------------------------------------------
# (d4) quarantined artifacts are resolved, not stale — the filename filter.
# Executed, not grepped: these files WOULD be flagged on content alone.
# ---------------------------------------------------------------------------
D="$WORK/d4"; mkdir -p "$D"
mkstate 4007-released-20260101T000000Z.json in_progress 86400
mkstate 4008-stale-20260101T000000Z.json    in_progress 86400
out="$(run_classifier "$D")"
if [[ -z "$out" ]]; then
  ok "(d4) quarantined -released- / -stale- files skipped despite stale-shaped content"
else
  bad "(d4) quarantined files → expected silence, got: [$out]"
fi

# Control for (d4): identical content under a normal name IS flagged, proving the
# filter — not the content — is what silenced the pair above.
D="$WORK/d4b"; mkdir -p "$D"
mkstate 4009.json in_progress 86400
out="$(run_classifier "$D")"
[[ "$out" == *"4009"* ]] && ok "(d4b) control — same content, normal filename → flagged" \
  || bad "(d4b) control → expected a stale line, got: [$out]"

# ---------------------------------------------------------------------------
# (d5) undeterminable freshness.
#
# (d5a) CHARACTERIZES A KNOWN DIVERGENCE, it does not bless it. The block's own
# comment claims "Missing/unparseable lastUpdatedAt anchors at epoch -> flagged as
# ancient", and that is true for UNPARSEABLE (d5b) but FALSE for MISSING. In
#   (.lastUpdatedAt // empty) | fromdateiso8601? // 0
# `|` binds looser than `//`, so an absent field makes the left side yield `empty`
# and the entire pipeline short-circuits: `$age` never binds and the file is
# skipped. A truncated or corrupt state file with no lastUpdatedAt is therefore
# invisible to the stale-claim check forever — a fail-open in the same class this
# ticket was filed about, found by writing this case.
#
# Pinned as-is deliberately: #215 is a coverage ticket and this run characterizes
# rather than changes gate behavior (plan Decision Ledger D-7). When the one-token
# fix lands, this case flips to the (d5b) expectation and that flip is the signal.
D="$WORK/d5"; mkdir -p "$D"
mkstate 4010.json in_progress 60 'del(.lastUpdatedAt)'
out="$(run_classifier "$D")"
[[ -z "$out" ]] && ok "(d5a) missing lastUpdatedAt → silently skipped (known fail-open, D-7 — NOT the documented behavior)" \
  || bad "(d5a) missing lastUpdatedAt → expected silence per current behavior, got: [$out]"

D="$WORK/d5b"; mkdir -p "$D"
mkstate 4011.json in_progress 60 '.lastUpdatedAt = "not-a-timestamp"'
out="$(run_classifier "$D")"
[[ "$out" == *"4011"* ]] && ok "(d5b) unparseable lastUpdatedAt → flagged ancient, not skipped" \
  || bad "(d5b) unparseable lastUpdatedAt → expected a stale line, got: [$out]"

# ---------------------------------------------------------------------------
# (d6) non-state JSON in the dir is ignored — the shape guard.
# The state dir also holds -eval.json / -verify.json / brief artifacts.
# ---------------------------------------------------------------------------
D="$WORK/d6"; mkdir -p "$D"
mkstate 4012.json in_progress 86400 'del(.runId)'                 # no runId
mkstate 4013.json in_progress 86400 '.runId = 42'                 # runId not a string
mkstate 4014.json in_progress 86400 '.stages = "not-an-object"'   # stages wrong type
printf '{"criteria":{}}\n' > "$D/4015-eval.json"                  # a sibling artifact
printf 'not json at all\n' > "$D/4016.json"                       # unparseable
out="$(run_classifier "$D")"
if [[ -z "$out" ]]; then
  ok "(d6) malformed / non-state JSON ignored (runId, stages shape guards + parse errors)"
else
  bad "(d6) malformed JSON → expected silence, got: [$out]"
fi

# ---------------------------------------------------------------------------
# (d7) an empty state dir is silent (no glob-literal leakage)
# ---------------------------------------------------------------------------
D="$WORK/d7"; mkdir -p "$D"
out="$(run_classifier "$D")"
[[ -z "$out" ]] && ok "(d7) empty state dir → silent, unexpanded glob not treated as a file" \
  || bad "(d7) empty state dir → expected silence, got: [$out]"

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
echo "[pipeline-doctor-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
