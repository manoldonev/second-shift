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
# selftest.sh composes verdict paths that reach a terminal WRITE — milestone
# progressions, gate verdicts, PR-shaped outcomes. Block 8 writes nothing. It is a
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
# (d7-bot) block 3 — bot-resolve classification (#92). Same extract-and-execute
# technique as stale-claim: the REAL production block is re-hosted
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
    # Exported so the eval'd production block (and shellcheck) see them as used.
    export DOCTOR_BOT_RESOLVER="$mock"
    export DOCTOR_BOT_SKIP_PROBE=1
    export GH_BOT=""
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

  # ok → binds GH_BOT and reports resolved, no FAIL (all five AC-8 tokens now covered)
  out_ok="$(run_bot_resolve ok /tmp/mock-wrapper-92.sh)"
  fails_ok="${out_ok%%|*}"; em_ok="${out_ok#*|}"
  if [[ "$fails_ok" == "0" && "$em_ok" == *"OK:bot wrapper resolved at /tmp/mock-wrapper-92.sh"* ]]; then
    ok "(d7-bot) ok → binds GH_BOT and reports resolved, no FAIL"
  else
    bad "(d7-bot) ok → fails=$fails_ok emitted=[$em_ok]"
  fi
fi

# ---------------------------------------------------------------------------
# (dc) section 4b — the selftest-cache-gate that lets pipeline-doctor.sh skip its
# own expensive internal selftest sweep (statectl alone runs ~90s+) on a repeat
# call in an unchanged environment. Same extract-and-execute technique as
# bot-resolve: the REAL production block is re-hosted here against a fixture
# plugin tree + fixture cache file. No scenario-liveness path — like bot-resolve/
# stale-claim, this reaches no terminal write scenario-liveness-selftest.sh could
# compose onto.
# ---------------------------------------------------------------------------
CACHE_GATE_BLOCK="$(sed -n '/# >>> selftest-cache-gate/,/# <<< selftest-cache-gate/p' "$DOCTOR")"
if [[ -z "$CACHE_GATE_BLOCK" ]]; then
  bad "(dc) selftest-cache-gate sentinels not found in $DOCTOR (section 4b refactored without updating this suite)"
else
  # run_cache_gate <cache-mtime|none> <verifiedAt|literal> <tree-mtime> <now-epoch> <match|mismatch>
  # ALWAYS invoked through command substitution ($(...) below), same load-bearing
  # isolation as run_env_classifier/run_bot_resolve above: the block re-defines
  # ok()/bad() as stub reporters, and bash functions are NOT lexically scoped — a
  # direct (non-substitution) call would permanently overwrite this FILE's own
  # ok()/bad(), silently breaking every assertion after it (the exact "15 passed, 0
  # failed" trap documented on run_env_classifier). The subshell $(...) forks means
  # the redefinition dies with it. Three fields come back over stdout, "@@"-joined
  # (hit|emitted|fingerprint) since a subshell cannot hand a variable back any other
  # way; field3 (this run's REAL bash/jq/node fingerprint) is threaded into "match"
  # fixtures on later calls — never hand-duplicated, since a second copy of the
  # bash/jq/node probe would be exactly the mirror harness CLAUDE.md bans and could
  # silently drift from the production formula.
  run_cache_gate() {
    local cache_mtime="$1" verified_at="$2" tree_mtime="$3" now="$4" env_mode="$5"
    local pdir cfile emitted="" env_field
    pdir="$WORK/cg-plugins-$$-$RANDOM"; mkdir -p "$pdir"
    printf 'x' > "$pdir/seed.txt"; touch -t "$tree_mtime" "$pdir/seed.txt"
    cfile="$WORK/cg-cache-$$-$RANDOM.json"; rm -f "$cfile"
    if [[ "$cache_mtime" != "none" ]]; then
      env_field="${_CAPTURED_FP_ENV:-placeholder}"
      [[ "$env_mode" == "mismatch" ]] && env_field="bash:0.0.0 jq:none node:none"
      if [[ "$env_mode" == "corrupt" ]]; then
        printf '{"env":"%s","verifiedAt":"banana"}' "$env_field" > "$cfile"
      else
        jq -n --arg env "$env_field" --argjson at "$verified_at" '{env: $env, verifiedAt: $at}' > "$cfile"
      fi
      touch -t "$cache_mtime" "$cfile"
    fi
    # shellcheck disable=SC2317,SC2329
    ok()  { emitted+="OK:$1;"; }
    # shellcheck disable=SC2317,SC2329
    bad() { emitted+="FAIL:$1;"; }
    # shellcheck disable=SC2034  # $PLUGINS_DIR is consumed by the eval'd production block
    PLUGINS_DIR="$pdir"
    export DOCTOR_CACHE_FILE="$cfile"
    export DOCTOR_CACHE_NOW="$now"
    SELFTEST_CACHE_HIT=""
    eval "$CACHE_GATE_BLOCK"
    printf '%s@@%s@@%s\n' "${SELFTEST_CACHE_HIT:-0}" "$emitted" "$_FP_ENV"
  }
  field1() { printf '%s' "${1%%@@*}"; }                        # hit
  field2() { local r="${1#*@@}"; printf '%s' "${r%%@@*}"; }    # emitted
  field3() { printf '%s' "${1##*@@}"; }                        # this-run fingerprint

  # Seed _CAPTURED_FP_ENV with THIS run's real fingerprint via the production block
  # itself, decoupled from any numbered case below so reordering them can't break it.
  out="$(run_cache_gate none 0 202001010000 1000000 match)"
  _CAPTURED_FP_ENV="$(field3 "$out")"

  # (dc1) no cache file at all → MISS, silent (no ok()/bad() from the gate itself)
  out="$(run_cache_gate none 0 202001010000 1000000 match)"
  hit="$(field1 "$out")"; em="$(field2 "$out")"
  if [[ "$hit" == "0" && -z "$em" ]]; then
    ok "(dc1) no cache file → MISS, silent"
  else
    bad "(dc1) no cache file → hit=$hit emitted=[$em]"
  fi

  # (dc2) matching env, fresh (age 100s), tree not newer than the cache → HIT
  out="$(run_cache_gate 202001010000 1000000 201901010000 1000100 match)"
  hit="$(field1 "$out")"; em="$(field2 "$out")"
  if [[ "$hit" == "1" && "$em" == *"OK:internal selftest sweep: cached clean"* ]]; then
    ok "(dc2) matching env + fresh + unchanged tree → HIT"
  else
    bad "(dc2) matching env + fresh → hit=$hit emitted=[$em]"
  fi

  # (dc3) mismatched interpreter fingerprint → MISS despite fresh + unchanged tree
  out="$(run_cache_gate 202001010000 1000000 201901010000 1000100 mismatch)"
  hit="$(field1 "$out")"
  [[ "$hit" == "0" ]] \
    && ok "(dc3) mismatched interpreter fingerprint → MISS" \
    || bad "(dc3) mismatched env → hit=$hit"

  # (dc4) matching env + fresh, but a plugin-tree file is NEWER than the cache
  # (simulates a plugin update since the cache was written) → MISS
  out="$(run_cache_gate 202001010000 1000000 202601010000 1000100 match)"
  hit="$(field1 "$out")"
  [[ "$hit" == "0" ]] \
    && ok "(dc4) plugin tree changed since the cache was written → MISS" \
    || bad "(dc4) changed tree → hit=$hit"

  # (dc5) TTL boundary: age 86399s (just under 24h) → HIT
  out="$(run_cache_gate 202001010000 1000000 201901010000 $((1000000 + 86399)) match)"
  hit="$(field1 "$out")"
  [[ "$hit" == "1" ]] \
    && ok "(dc5) age 86399s (just under the 24h TTL) → HIT" \
    || bad "(dc5) age 86399s → hit=$hit"

  # (dc6) TTL boundary: age exactly 86400s (24h) → MISS — the TTL is a defense-in-
  # depth expiry that fires even on an otherwise-matching fingerprint.
  out="$(run_cache_gate 202001010000 1000000 201901010000 $((1000000 + 86400)) match)"
  hit="$(field1 "$out")"
  [[ "$hit" == "0" ]] \
    && ok "(dc6) age exactly 86400s (24h TTL boundary) → MISS" \
    || bad "(dc6) age 86400s → hit=$hit"

  # (dc7) clock skew: now BEFORE verifiedAt (negative age) → MISS, fail-closed rather
  # than treating an unmodeled clock jump as an infinitely-fresh cache.
  out="$(run_cache_gate 202001010000 1000000 201901010000 999900 match)"
  hit="$(field1 "$out")"
  [[ "$hit" == "0" ]] \
    && ok "(dc7) verifiedAt in the future (clock skew) → MISS, fail-closed" \
    || bad "(dc7) future verifiedAt → hit=$hit"

  # (dc8) cache file exists but "verifiedAt" is non-numeric ("banana") → MISS, no
  # crash, no FAIL. jq happily extracts a non-numeric string; the real crash-risk is
  # unguarded arithmetic on it ($(( )) on a non-numeric operand kills a non-
  # interactive bash outright, even without -e) — this proves that does NOT happen.
  out="$(run_cache_gate 202001010000 0 201901010000 1000100 corrupt)"
  hit="$(field1 "$out")"; em="$(field2 "$out")"
  if [[ "$hit" == "0" && "$em" != *"FAIL:"* ]]; then
    ok "(dc8) non-numeric verifiedAt → MISS, no crash, never FAIL"
  else
    bad "(dc8) non-numeric verifiedAt → hit=[$hit] emitted=[$em] (expected a graceful MISS, got empty output if the gate crashed)"
  fi
fi

# ---------------------------------------------------------------------------
# (dw) section 4b's cache-write back half — "a clean sweep refreshes the
# cache; a dirty one leaves it untouched". A SEPARATE sentinel from
# selftest-cache-gate above: the gate decides hit/miss BEFORE the sweep runs;
# this decides whether the sweep's OUTCOME gets persisted AFTER it runs. Same
# extract-and-execute technique — no gh/network, and critically no real
# selftest sweep either (that would reintroduce the exact ~90s+ cost this
# feature exists to avoid paying on every test run too).
# ---------------------------------------------------------------------------
CACHE_WRITE_BLOCK="$(sed -n '/# >>> selftest-cache-write/,/# <<< selftest-cache-write/p' "$DOCTOR")"
if [[ -z "$CACHE_WRITE_BLOCK" ]]; then
  bad "(dw) selftest-cache-write sentinels not found in $DOCTOR (section 4b refactored without updating this suite)"
else
  # run_cache_write <fails> <fails-before-sweep> <pre-existing-cache-content|none>
  # Echoes the cache file's content afterward, or the literal "none" if absent.
  run_cache_write() {
    local fails="$1" before="$2" pre="$3"
    local sdir cfile
    sdir="$WORK/cw-state-$$-$RANDOM"; cfile="$sdir/doctor-selftest-cache.json"
    mkdir -p "$sdir"
    [[ "$pre" != "none" ]] && printf '%s' "$pre" > "$cfile"
    # shellcheck disable=SC2034  # all six are consumed by the eval'd production block
    FAILS="$fails" _FAILS_BEFORE_SWEEP="$before" STATE_DIR="$sdir" \
      _CACHE_FILE="$cfile" _FP_ENV="test-env-marker" _CACHE_NOW=1234567
    eval "$CACHE_WRITE_BLOCK"
    if [[ -f "$cfile" ]]; then cat "$cfile"; else printf 'none'; fi
  }

  # (dw1) clean sweep (FAILS unchanged) + no pre-existing cache → writes a fresh one
  out="$(run_cache_write 3 3 none)"
  if [[ "$out" == *'"env": "test-env-marker"'* && "$out" == *'"verifiedAt": 1234567'* ]]; then
    ok "(dw1) clean sweep → cache written with the current fingerprint"
  else
    bad "(dw1) clean sweep → expected a fresh cache write, got [$out]"
  fi

  # (dw2) dirty sweep (FAILS grew past the pre-sweep snapshot) + no pre-existing
  # cache → stays absent, never fabricates a clean record for a broken toolkit
  out="$(run_cache_write 4 3 none)"
  [[ "$out" == "none" ]] \
    && ok "(dw2) dirty sweep, no prior cache → stays absent" \
    || bad "(dw2) dirty sweep → expected no cache file, got [$out]"

  # (dw3) dirty sweep + a pre-existing cache → left byte-for-byte untouched, not
  # overwritten with a falsely-clean record (a stale cache just stays stale/expired,
  # which is a MISS on its own terms — never actively re-stamped as fresh)
  out="$(run_cache_write 4 3 '{"env":"old-env","verifiedAt":1}')"
  if [[ "$out" == *'"env":"old-env"'* && "$out" == *'"verifiedAt":1'* ]]; then
    ok "(dw3) dirty sweep, prior cache present → left untouched"
  else
    bad "(dw3) dirty sweep with a prior cache → expected it untouched, got [$out]"
  fi
fi

# ---------------------------------------------------------------------------
# (ot) the OTel / cost-attribution section (#432)
#
# Same extract-and-execute technique as the classifier above: the block is delimited by
# `# >>> otel-telemetry-classify` / `# <<< otel-telemetry-classify` and re-hosted here with
# `ok`/`warn` stubbed to plain echoes, so the assertions drive the REAL production branches.
#
# INVARIANT GUARDED: doctor stops reporting a healthy OTel section for a machine that exports
# nothing. Before this, every check here passed on a shell with no CLAUDE_CODE_ENABLE_TELEMETRY —
# the one variable that decides whether a run can report cost at all — and a machine whose
# metrics file had just rotated read as having no telemetry at all.
# ---------------------------------------------------------------------------
OTEL_BLOCK="$(sed -n '/# >>> otel-telemetry-classify/,/# <<< otel-telemetry-classify/p' "$DOCTOR")"
if [[ -z "$OTEL_BLOCK" ]]; then
  bad "(ot0) otel-telemetry-classify sentinels not found in $DOCTOR (block refactored without updating this suite)"
else
  # run_otel <metrics-file> [VAR=value…] — echoes the block's stubbed ok:/warn: lines.
  run_otel() {
    local mf="$1"; shift
    # shellcheck disable=SC2016  # `$1` is the CHILD's positional (passed as `_ "$mf"` below) —
    # expanding it here would bake the parent's argv into the extracted block instead.
    env "$@" bash -c '
      set -uo pipefail
      ok()   { echo "ok: $1"; }
      warn() { echo "warn: $1"; }
      OTEL_METRICS_FILE="$1"
      '"$OTEL_BLOCK"'
    ' _ "$mf" 2>&1
  }

  OT="$WORK/otel"; mkdir -p "$OT"
  : > "$OT/metrics.jsonl"                       # present but EMPTY, as right after a rotation
  printf '{"resourceMetrics":[]}\n' > "$OT/metrics-2026-05-01T10-10-00.000-size.jsonl"

  # (ot1) the rotated-but-healthy machine: empty live file, full backup → still "can fire".
  out="$(run_otel "$OT/metrics.jsonl" CLAUDE_CODE_ENABLE_TELEMETRY=1)"
  if [[ "$out" == *"ok: OTel metrics present in a rotated backup"* ]]; then
    ok "(ot1) an empty live metrics file beside a non-empty rotated backup reads as present"
  else
    bad "(ot1) expected the rotated-backup ok line, got [$out]"
  fi

  # (ot2) genuinely nothing: no live file, no backup → the warn, naming the skip it will record.
  OT2="$WORK/otel-empty"; mkdir -p "$OT2"
  out="$(run_otel "$OT2/metrics.jsonl" CLAUDE_CODE_ENABLE_TELEMETRY=1)"
  if [[ "$out" == *"warn: no OTel metrics at"* && "$out" == *"nor any rotated backup"* ]]; then
    ok "(ot2) no live file and no backup still warns — the rotation tolerance is not a blanket pass"
  else
    bad "(ot2) expected the no-metrics warn, got [$out]"
  fi

  # (ot3) the variable that actually decides whether this shell's sessions export anything.
  # `env -u` is load-bearing: inheriting the operator's own exporting shell makes this vacuous.
  out="$(run_otel "$OT/metrics.jsonl" -u CLAUDE_CODE_ENABLE_TELEMETRY)"
  if [[ "$out" == *"warn: CLAUDE_CODE_ENABLE_TELEMETRY not enabled"* && "$out" == *"unrecoverable after the run"* ]]; then
    ok "(ot3) an unset CLAUDE_CODE_ENABLE_TELEMETRY warns, and names the consequence"
  else
    bad "(ot3) expected the telemetry-off warn naming the consequence, got [$out]"
  fi

  # (ot4) the other direction — a value that does NOT enable telemetry must not read as enabled.
  # `0` is the trap: a bare -n test on the variable calls it set and reports the section healthy.
  out="$(run_otel "$OT/metrics.jsonl" CLAUDE_CODE_ENABLE_TELEMETRY=0)"
  if [[ "$out" == *"warn: CLAUDE_CODE_ENABLE_TELEMETRY not enabled"* ]]; then
    ok "(ot4) CLAUDE_CODE_ENABLE_TELEMETRY=0 warns — presence alone is not enablement"
  else
    bad "(ot4) expected the warn for the literal 0, got [$out]"
  fi

  # (ot5) enabled reads as enabled, so neither branch can be a constant.
  out="$(run_otel "$OT/metrics.jsonl" CLAUDE_CODE_ENABLE_TELEMETRY=1)"
  if [[ "$out" == *"ok: CLAUDE_CODE_ENABLE_TELEMETRY enabled"* ]]; then
    ok "(ot5) CLAUDE_CODE_ENABLE_TELEMETRY=1 reads as enabled"
  else
    bad "(ot5) expected the enabled ok line, got [$out]"
  fi
fi

# ---------------------------------------------------------------------------
# (rs) resolve_sibling — the cache rung must pick the HIGHEST version, not the
# lexically-last one. Same extract-and-execute technique as the blocks above: the
# real function is lifted out by its sentinels and run against a staged cache, so
# a hand-copied resolver — the mirror harness CLAUDE.md bans — never enters.
#
# 9.0.0 vs 10.0.0 is the whole point of those numbers. `ls -1 | sort -r` is lexical
# and puts 9.0.0 first, so the loop's first hit was the SUPERSEDED sibling. Any pair
# below 10 agrees under both orderings and cannot tell them apart. BOTH versions
# carry the file, so the `-f` filter cannot decide it either — only the ordering can.
# ---------------------------------------------------------------------------
RS_BLOCK="$(sed -n '/# >>> resolve-sibling/,/# <<< resolve-sibling/p' "$DOCTOR")"
if [[ -z "$RS_BLOCK" ]]; then
  bad "(rs) resolve-sibling sentinels not found in $DOCTOR — the function was refactored without updating this guard"
else
  RS="$WORK/rs"
  mkdir -p "$RS/cache/dev-pipeline/1.0.0/skills/run/tools" \
           "$RS/cache/review-toolkit/9.0.0/scripts" \
           "$RS/cache/review-toolkit/10.0.0/scripts"
  echo "superseded" > "$RS/cache/review-toolkit/9.0.0/scripts/marker.sh"
  echo "current"    > "$RS/cache/review-toolkit/10.0.0/scripts/marker.sh"
  rs_out="$(PLUGINS_DIR="$RS/cache/dev-pipeline" \
            SCRIPT_DIR="$RS/cache/dev-pipeline/1.0.0/skills/run/tools" \
            bash -c "$RS_BLOCK
resolve_sibling review-toolkit scripts/marker.sh" 2>/dev/null)"
  case "$rs_out" in
    */review-toolkit/10.0.0/*) ok "(rs) the cache rung resolves the highest version, not the lexically-last" ;;
    */review-toolkit/9.0.0/*)  bad "(rs) resolved the SUPERSEDED 9.0.0 — the version sort is lexical, so 9.0.0 outranks 10.0.0" ;;
    *)                         bad "(rs) resolve_sibling returned [$rs_out], expected the 10.0.0 sibling" ;;
  esac
fi

# ---------------------------------------------------------------------------
# (inv) every selftest the doctor DELEGATES to must exist
#
# INVARIANT: an invocation may not outlive its subject. Delete a selftest and leave
# the doctor's `bash "$SCRIPT_DIR/<name>-selftest.sh"` behind, and bash returns 127,
# the `if` takes the else arm, and the doctor reports a permanent FAIL for the drift
# of a check that no longer exists — a red no consumer can act on.
#
# This does NOT run the delegates — that would break the no-gh/no-network contract
# the header states. It resolves their PATHS, which is the property that rots. It is
# not a prose-presence guard: it fails on a real filesystem fact (a deleted subject),
# which is exactly what a grep for the literal could not do.
DOCTOR_DIR="$(cd "$(dirname "$DOCTOR")" && pwd)"
PLUGINS_ROOT="$(cd "$DOCTOR_DIR/../.." && pwd)"

# Arm 1: same-plugin delegates, invoked as "$SCRIPT_DIR/<name>-selftest.sh".
missing=""
seen=0
# shellcheck disable=SC2016  # deliberate: `$SCRIPT_DIR` is the literal TEXT being matched in the
# doctor's source, not a variable to expand here.
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  seen=$((seen + 1))
  [[ -f "$DOCTOR_DIR/$name" ]] || missing="$missing $name"
done < <(grep -oE '\$SCRIPT_DIR/[a-z0-9-]+-selftest\.sh' "$DOCTOR" | sed 's|^\$SCRIPT_DIR/||' | sort -u)

if [[ "$seen" -eq 0 ]]; then
  bad "(inv) found no \$SCRIPT_DIR selftest delegations in $DOCTOR — the extraction pattern drifted, so this guard is inert"
elif [[ -n "$missing" ]]; then
  bad "(inv) pipeline-doctor delegates to selftest(s) that do not exist:$missing — the invocation outlived its subject (the #348 plan-lint class)"
else
  ok "(inv) all $seen same-plugin selftest delegations resolve to a real file"
fi

# Arm 2: cross-plugin delegates, invoked as `resolve_sibling <plugin> <relpath>`.
# Checked against the in-repo sibling, which is what a release ships.
missing=""
seen=0
while IFS= read -r pair; do
  [[ -z "$pair" ]] && continue
  seen=$((seen + 1))
  plug="${pair%% *}"; rel="${pair#* }"
  [[ -f "$PLUGINS_ROOT/$plug/$rel" ]] || missing="$missing $plug/$rel"
done < <(grep -oE 'resolve_sibling [a-z-]+ [A-Za-z0-9/_.-]+-selftest\.sh' "$DOCTOR" \
           | sed 's|^resolve_sibling ||' | sort -u)

if [[ "$seen" -eq 0 ]]; then
  bad "(inv) found no resolve_sibling selftest delegations in $DOCTOR — the extraction pattern drifted, so this arm is inert"
elif [[ -n "$missing" ]]; then
  bad "(inv) pipeline-doctor delegates to sibling selftest(s) that do not exist:$missing"
else
  ok "(inv) all $seen cross-plugin selftest delegations resolve to a real file"
fi

# Probe: the guard must FAIL on a doctor that names a deleted subject. Without this,
# a drifted extraction pattern would report the same green as a clean tree.
PROBE="$WORK/probe-doctor.sh"
# shellcheck disable=SC2016  # deliberate: the injected line must carry the literal `$SCRIPT_DIR`
# so the extraction below sees the same shape it sees in the real doctor.
{ cat "$DOCTOR"; echo 'bash "$SCRIPT_DIR/definitely-deleted-selftest.sh"'; } > "$PROBE"
probe_missing=""
# shellcheck disable=SC2016  # same literal-text match as arm 1.
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  [[ -f "$DOCTOR_DIR/$name" ]] || probe_missing="$probe_missing $name"
done < <(grep -oE '\$SCRIPT_DIR/[a-z0-9-]+-selftest\.sh' "$PROBE" | sed 's|^\$SCRIPT_DIR/||' | sort -u)
case "$probe_missing" in
  *definitely-deleted-selftest.sh*) ok "(inv-probe) the arm-1 check reports a delegation whose subject is absent" ;;
  *) bad "(inv-probe) arm 1 did NOT catch an injected delegation to a deleted selftest — the guard is inert" ;;
esac

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
echo "[pipeline-doctor-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
