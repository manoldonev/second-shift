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
# (d5a) missing lastUpdatedAt anchors at epoch, matching the block's own comment
# ("Missing/unparseable lastUpdatedAt anchors at epoch -> flagged as ancient") and
# the (d5b) unparseable case below. Fixed under #229: `(.lastUpdatedAt // empty)`
# short-circuited the whole `|` pipeline on an absent field (jq binds `|` looser
# than `//`), so a truncated state file with no lastUpdatedAt was silently skipped
# instead of anchored. `(.lastUpdatedAt // "")` always yields a value, so
# `fromdateiso8601? // 0` anchors both the missing and unparseable cases at epoch.
D="$WORK/d5"; mkdir -p "$D"
mkstate 4010.json in_progress 60 'del(.lastUpdatedAt)'
out="$(run_classifier "$D")"
[[ "$out" == *"4010"* ]] && ok "(d5a) missing lastUpdatedAt → flagged ancient, not skipped" \
  || bad "(d5a) missing lastUpdatedAt → expected a stale line, got: [$out]"

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
# (d8) block 9 — the over-envelope classifier. Same extract-and-execute technique
# as the stale-claim block above: the REAL production block is re-hosted here and
# fed canned stage-envelopes.sh output, so these cases cannot pass against a
# classifier that no longer exists.
# ---------------------------------------------------------------------------
ENV_BLOCK="$(sed -n '/# >>> envelope-classify/,/# <<< envelope-classify/p' "$DOCTOR")"
if [[ -z "$ENV_BLOCK" ]]; then
  bad "(d8) envelope-classify sentinels not found in $DOCTOR (block 9 refactored without updating this suite)"
else
  # Run the REAL extracted block over a canned model and report everything the cases
  # need: "<summary>|<lines>|<fail-count>|<emitted>".
  #
  # ALWAYS invoked through command substitution, so the reporter stubs below live in a
  # subshell. That isolation is load-bearing: the production block calls `ok`, and so
  # does THIS suite — defining the stub in the parent shell silently replaced the
  # suite's own reporter and made a case disappear instead of run. (Observed during
  # development: the run went "15 passed, 0 failed" with (d8e) never recorded.)
  #
  # `fail` increments a counter exactly as the production reporter does, which is what
  # makes (d8e)'s never-blocking assertion real rather than assumed.
  run_env_classifier() { # run_env_classifier <json>
    local env_out env_lines env_summary df="0" emitted=""
    # shellcheck disable=SC2034  # $env_out is the eval'd production block's only input
    env_out="$1"
    # shellcheck disable=SC2317,SC2329  # invoked from inside the eval'd production block
    ok()   { emitted+="OK:$1;"; }
    # shellcheck disable=SC2317,SC2329
    warn() { emitted+="WARN:$1;"; }
    # shellcheck disable=SC2317,SC2329
    fail() { df=$((df + 1)); emitted+="FAIL:$1;"; }
    eval "$ENV_BLOCK" >/dev/null
    # printf, not a herestring: `tr <<< ""` would emit a spurious ';' for the
    # herestring's own trailing newline, making "no lines" indistinguishable from
    # "one empty line" — exactly the distinction (d8d) turns on.
    printf '%s|%s|%s|%s\n' "$env_summary" "$(printf '%s' "$env_lines" | tr '\n' ';')" "$df" "$emitted"
  }

  # (d8a) an over-envelope time flag is surfaced, with the record wording.
  out="$(run_env_classifier '{
    "corpus": {"minN": 8, "runsInWindow": 12},
    "trustedWindows": 40,
    "runUnderTest": {"stem": "4242"},
    "timeEnvelopes": [{"stage":"5","floorMet":true}],
    "flags": [{"axis":"time","key":"stage 5","measured":99,"p90":12,"n":10,"record":true}]
  }')"
  if [[ "$out" == *"stage 5: 99 min exceeds corpus p90 12 min (n=10)"* && "$out" == *"a new record"* ]]; then
    ok "(d8a) an over-envelope time flag is surfaced with its measured value and record wording"
  else
    bad "(d8a) over-envelope flag not surfaced — got [$out]"
  fi

  # (d8b) cost flags are NOT surfaced here — block 9 is time-axis only, because cost
  # is written after the run and a pre-flight has nothing to say about it.
  out="$(run_env_classifier '{
    "corpus": {"minN": 8, "runsInWindow": 12},
    "trustedWindows": 40,
    "runUnderTest": {"stem": "4242"},
    "timeEnvelopes": [{"stage":"5","floorMet":true}],
    "flags": [{"axis":"cost","key":"Implementation","measured":50,"p90":20,"n":9,"record":false}]
  }')"
  if [[ "$out" != *"Implementation"* ]]; then
    ok "(d8b) cost-axis flags are not surfaced by the pre-flight block (time axis only)"
  else
    bad "(d8b) cost flag leaked into the pre-flight check — got [$out]"
  fi

  # (d8c) a corpus under the min-n floor reports VACUOUS rather than a clean bill of
  # health — "measured nothing" must never read like "measured and found nothing".
  out="$(run_env_classifier '{
    "corpus": {"minN": 8, "runsInWindow": 3},
    "trustedWindows": 6,
    "runUnderTest": {"stem": "4242"},
    "timeEnvelopes": [{"stage":"5","floorMet":false}],
    "flags": []
  }')"
  if [[ "$out" == VACUOUS:* ]]; then
    ok "(d8c) a below-floor corpus reports VACUOUS, not a pass"
  else
    bad "(d8c) below-floor corpus — expected VACUOUS, got [$out]"
  fi

  # (d8d) a within-envelope run emits no lines at all.
  out="$(run_env_classifier '{
    "corpus": {"minN": 8, "runsInWindow": 12},
    "trustedWindows": 40,
    "runUnderTest": {"stem": "4242"},
    "timeEnvelopes": [{"stage":"5","floorMet":true}],
    "flags": []
  }')"
  if [[ "$out" == "measured 1 stage envelope(s) over 12 run(s), 40 trusted window(s)||0|OK:"* ]]; then
    ok "(d8d) a run inside its envelope produces a measured summary and no flag lines"
  else
    bad "(d8d) within-envelope run — got [$out]"
  fi

  # (d8e) THE never-blocking posture (AC-4), asserted behaviorally over the WHOLE block
  # including its dispatch: run it against a corpus that DOES flag, and confirm nothing
  # reached the failure reporter. The stubs above make `fail` observable, so an arm that
  # started calling it — the one realistic way this advisory check could become a gate —
  # turns this case red. An earlier, narrower sentinel that stopped at the jq left this
  # unguarded, and a mutation demo caught the gap.
  out="$(run_env_classifier '{
    "corpus": {"minN": 8, "runsInWindow": 12},
    "trustedWindows": 40,
    "runUnderTest": {"stem": "4242"},
    "timeEnvelopes": [{"stage":"5","floorMet":true}],
    "flags": [{"axis":"time","key":"stage 5","measured":99,"p90":12,"n":10,"record":false}]
  }')"
  env_fails="$(cut -d'|' -f3 <<< "$out")"
  env_emitted="$(cut -d'|' -f4- <<< "$out")"
  if [[ "$env_fails" == "0" && "$env_emitted" == *"WARN:stage envelopes"* && "$env_emitted" != *"FAIL:"* ]]; then
    ok "(d8e) a flagging run reaches warn() and never fail() — the check cannot move the exit code (AC-4)"
  else
    bad "(d8e) never-blocking violated — fail-count=$env_fails emitted=[$env_emitted]"
  fi
fi

# ---------------------------------------------------------------------------
# (d7-bot) block 3 — bot-resolve classification (#92). Same extract-and-execute
# technique as stale-claim / envelope: the REAL production block is re-hosted
# here against a mock gh-bot.sh. No scenario-liveness path — like doctor block 8,
# this reaches no terminal write (stated per the scenario-first rule).
# ---------------------------------------------------------------------------
BOT_BLOCK="$(sed -n '/# >>> bot-resolve/,/# <<< bot-resolve/p' "$DOCTOR")"
if [[ -z "$BOT_BLOCK" ]]; then
  bad "(d7-bot) bot-resolve sentinels not found in $DOCTOR"
else
  run_bot_resolve() { # status token the mock --status prints; optional path
    local mock_status="$1" mock_path="${2:-}"
    local mock="$WORK/mock-gh-bot-$$.sh"
    cat > "$mock" <<MOCK
#!/usr/bin/env bash
case "\${1:-}" in
  --status) echo "$mock_status"; exit 0 ;;
  --path)
    if [[ -n "$mock_path" ]]; then echo "$mock_path"; fi
    [[ "$mock_status" == "ok" ]] && exit 0 || exit 1
    ;;
  *) exit 99 ;;
esac
MOCK
    chmod +x "$mock"
    local emitted="" fails=0
    # shellcheck disable=SC2317,SC2329
    ok()  { emitted+="OK:$1;"; }
    # shellcheck disable=SC2317,SC2329
    bad() { emitted+="FAIL:$1;"; fails=$((fails+1)); }
    # shellcheck disable=SC2034
    CFG=""
    DOCTOR_BOT_RESOLVER="$mock"
    DOCTOR_BOT_SKIP_PROBE=1
    GH_BOT=""
    eval "$BOT_BLOCK"
    printf '%s|%s\n' "$fails" "$emitted"
  }

  # disabled → no FAIL
  out="$(run_bot_resolve disabled)"
  fails="${out%%|*}"; emitted="${out#*|}"
  if [[ "$fails" == "0" && "$emitted" == *"OK:bot check skipped"* && "$emitted" != *"FAIL:"* ]]; then
    ok "(d7-bot) disabled → skip, no FAIL"
  else
    bad "(d7-bot) disabled → fails=$fails emitted=[$emitted]"
  fi

  # unset-var vs missing-file produce DIFFERENT messages
  out_u="$(run_bot_resolve unset-var)"
  out_m="$(run_bot_resolve missing-file /tmp/missing-wrapper-92.sh)"
  em_u="${out_u#*|}"; em_m="${out_m#*|}"
  if [[ "$em_u" == *"FAIL:bot env var"* && "$em_m" == *"FAIL:bot wrapper missing"* && "$em_u" != "$em_m" ]]; then
    ok "(d7-bot) unset-var vs missing-file produce distinct FAIL messages"
  else
    bad "(d7-bot) message pairing failed — unset=[$em_u] missing=[$em_m]"
  fi

  # not-executable distinct too
  out_n="$(run_bot_resolve not-executable /tmp/not-exec-92.sh)"
  em_n="${out_n#*|}"
  if [[ "$em_n" == *"FAIL:bot wrapper at"* && "$em_n" == *"not executable"* ]]; then
    ok "(d7-bot) not-executable has its own remediation"
  else
    bad "(d7-bot) not-executable emitted=[$em_n]"
  fi
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
echo "[pipeline-doctor-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
