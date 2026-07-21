#!/usr/bin/env bash
# check-bounded-exploration-selftest.sh — proves check-bounded-exploration.sh actually fails the
# things it claims to, and that the live workflows/ tree is currently clean.
#
# Two halves, mirroring diff-range-selftest.sh:
#   (A) FIXTURE CASES — throwaway .mjs files in a temp dir, one per rule. A lint nobody has seen
#       fail is a lint nobody knows works; each case asserts a specific rejection, and case A6
#       asserts the bounded-lookback rule that keeps one marker from covering two adjacent sites.
#   (B) DRIFT GUARDS + REAL-TREE — the lint must pass over the live workflows/ dir (so CI fails when
#       a future dispatch lands unmarked), the site count must be non-zero (a detection regex that
#       matches nothing must never read as green), and the AC-6 retry contract must hold.
#
# Guard greps are FIXED-STRING (grep -F) wherever the token is punctuation-dense — the same reason
# diff-range-selftest.sh gives: a regex-mode `.` would match any character.
#
# Bash 3.2 compatible. Runs under the repo's *-selftest.sh CI loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS="$RUN_DIR/workflows"
LINT="$SCRIPT_DIR/check-bounded-exploration.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t bounded-exploration-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/workflows"
mkdir -p "$FIX"

run_lint() { # run_lint <dir> -> prints nothing, returns the lint's exit code
  bash "$LINT" "$1" >/dev/null 2>&1
}

# ---------- (A) fixture cases ----------

# A1: a schema-carrying dispatch with no marker at all is rejected.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A1 unmarked dispatch is rejected (rc=1)" || bad "A1 expected rc=1, got $rc"

# A2: a nudge marker naming a constant that does not exist is rejected — catches a renamed or
# never-defined nudge, which would otherwise read as a declared disposition.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration: NO_SUCH_CONSTANT
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A2 marker naming an undefined constant is rejected" || bad "A2 expected rc=1, got $rc"

# A3: a well-formed nudge marker whose constant IS defined passes.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const BOUNDED_THING = ' bound your exploration.'
// bounded-exploration: BOUNDED_THING
const r = await agent(prompt + BOUNDED_THING, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "A3 valid nudge marker passes" || bad "A3 expected rc=0, got $rc"

# A4: an opt-out with no reason is rejected — a waiver must be declared, not merely asserted.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration-optout: some-agent
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A4 reasonless opt-out is rejected" || bad "A4 expected rc=1, got $rc"

# A5: `delegated` with no per-entry disposition anywhere in the file is rejected — otherwise the
# verb degrades into a blanket waiver for the whole file.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration-delegated: entries declare their own
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A5 blanket 'delegated' with no per-entry marker is rejected" || bad "A5 expected rc=1, got $rc"

# A6: THE LOOKBACK BOUND. Two sites 3 lines apart with ONE marker above the first: the second must
# still be reported. Without the previous-site floor, the 40-line window would swallow both — which
# is exactly the shape (13 lines apart) that the two intake-review.mjs descriptors have, and the
# conflicting dispositions there are the reason this grammar exists at all.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const BOUNDED_THING = ' bound it.'
// bounded-exploration: BOUNDED_THING
const one = { schema: S }
const two = { schema: S }
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A6 one marker does not cover an adjacent second site" || bad "A6 expected rc=1, got $rc"

# A7: give the second site its own marker and the same file passes — proves A6 failed for the
# lookback bound specifically, not because two sites are inherently unsatisfiable.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const BOUNDED_THING = ' bound it.'
// bounded-exploration: BOUNDED_THING
const one = { schema: S }
// bounded-exploration-optout: two -- deliberately unbounded, it is a control
const two = { schema: S }
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "A7 per-site markers on adjacent sites pass" || bad "A7 expected rc=0, got $rc"

# A8: inline `agent(..., { ... schema: X })` is detected. A line-anchored regex finds only 10 of the
# live tree's sites and misses every inline form — the under-detection that would let this lint
# report green while a quarter of the surface went unguarded.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const r = await agent(prompt, { agentType: 'x', model: 'sonnet', phase: 'P', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A8 inline agent() opts are detected as a site" || bad "A8 expected rc=1, got $rc"

# A9: *-selftest.mjs files are excluded (offline harnesses carry no live dispatches). With only an
# excluded file present the lint finds zero sites, which is itself a failure by design.
rm -f "$FIX/a.mjs"
cat > "$FIX/thing-selftest.mjs" <<'EOF'
const r = await agent(prompt, { schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A9 zero detected sites fails rather than passing vacuously" || bad "A9 expected rc=1, got $rc"

# ---------- (B) drift guards + real tree ----------

out="$(bash "$LINT" "$WORKFLOWS" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "B1 live workflows/ tree is clean"
else
  bad "B1 live workflows/ tree has undeclared dispatches (rc=$rc)"
  echo "$out" >&2
fi

sites="$(printf '%s\n' "$out" | sed -n 's/^check-bounded-exploration: \([0-9]*\) dispatch site.*/\1/p')"
if [ -n "$sites" ] && [ "$sites" -ge 16 ]; then
  ok "B2 live tree detection finds $sites dispatch sites (>=16)"
else
  bad "B2 expected >=16 detected sites in the live tree, got '${sites:-none}'"
fi

# B3/B4: AC-6 — retries dropped 2 -> 1, and the surviving retry is not a verbatim repeat.
for f in plan-review.mjs unit-tests.mjs; do
  if grep -qF 'dispatchSchemaAgent = async (prompt, opts, retries = 1)' "$WORKFLOWS/$f"; then
    ok "B3 $f dispatchSchemaAgent retries = 1"
  else
    bad "B3 $f no longer pins retries = 1 (AC-6)"
  fi
  if grep -qF 'RETRY_ESCALATION' "$WORKFLOWS/$f"; then
    ok "B4 $f retry carries an escalated preamble"
  else
    bad "B4 $f lost RETRY_ESCALATION — a retry would repeat verbatim (AC-6)"
  fi
done

# B5: the probe's plan-shaped arms must dispatch what production dispatches. stall-probe.mjs
# necessarily re-states plan-review.mjs's schema and nudge (Workflow scripts cannot import), so an
# edit to one without the other silently makes the AFTER rate measure a dispatch nobody ships.
for token in "verdict: { type: 'string', enum: ['block', 'fix-and-go', 'pass'] }" "GROUND PROPORTIONATELY"; do
  if grep -qF "$token" "$WORKFLOWS/stall-probe.mjs" && grep -qF "$token" "$WORKFLOWS/plan-review.mjs"; then
    ok "B5 stall-probe and plan-review agree on: ${token:0:38}"
  else
    bad "B5 drift between stall-probe.mjs and plan-review.mjs on: ${token:0:38}"
  fi
done

# B6: the probe keeps an unbounded arm. If `bounded` ever stops gating the nudge there is no
# control, and every AFTER rate becomes unfalsifiable.
if grep -qF 'bounded ? TARGET.nudge' "$WORKFLOWS/stall-probe.mjs"; then
  ok "B6 stall-probe still gates its nudge behind the bounded A/B arg"
else
  bad "B6 stall-probe lost its unbounded control arm"
fi

echo "check-bounded-exploration-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
