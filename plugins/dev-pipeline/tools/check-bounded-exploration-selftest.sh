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
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS="$PLUGIN_DIR/workflows"
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
# never-defined nudge. Nudge markers are only legal in probe files post-graduation, so the
# fixture is probe-named.
rm -f "$FIX/a.mjs"
cat > "$FIX/a-probe.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration: NO_SUCH_CONSTANT
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A2 marker naming an undefined constant is rejected" || bad "A2 expected rc=1, got $rc"

# A3: a well-formed nudge marker whose constant IS defined passes — in a probe file, the one
# place the schema-forced control arm legitimately lives.
cat > "$FIX/a-probe.mjs" <<'EOF'
const S = { type: 'object' }
const BOUNDED_THING = ' bound your exploration.'
// bounded-exploration: BOUNDED_THING
const r = await agent(prompt + BOUNDED_THING, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "A3 valid nudge marker passes" || bad "A3 expected rc=0, got $rc"

# A4: an opt-out with no reason is rejected — a waiver must be declared, not merely asserted.
rm -f "$FIX/a-probe.mjs"
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration-optout: some-agent
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A4 reasonless opt-out is rejected" || bad "A4 expected rc=1, got $rc"

# A5: `delegated` with no per-entry disposition anywhere in the file is rejected — otherwise the
# verb degrades into a blanket waiver. Probe-named: production files reject delegated outright (G4).
rm -f "$FIX/a.mjs"
cat > "$FIX/a-probe.mjs" <<'EOF'
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
rm -f "$FIX/a.mjs"
cat > "$FIX/a-probe.mjs" <<'EOF'
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
cat > "$FIX/a-probe.mjs" <<'EOF'
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
rm -f "$FIX/a-probe.mjs"
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const r = await agent(prompt, { agentType: 'x', model: 'sonnet', phase: 'P', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A8 inline agent() opts are detected as a site" || bad "A8 expected rc=1, got $rc"

# A8b: a COMMENT mentioning "schema:" is not a dispatch site — prose documentation must not
# demand a marker (observed live: "// No schema: the death class cannot occur" tripped the
# detector before this rule).
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// No schema: this call is deliberately schema-free, the death class cannot occur.
const r = await agent(prompt, { agentType: 'x' })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A8b comment-only schema: mention is not a site (zero real sites fails)" || bad "A8b expected rc=1 (no real sites), got $rc"

# G1: GRADUATION — a nudge marker on a schema site in a PRODUCTION file is rejected even when the
# constant exists: schema on an exploring dispatch is the retired class (#169).
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const BOUNDED_THING = ' bound it.'
// bounded-exploration: BOUNDED_THING
const r = await agent(prompt + BOUNDED_THING, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "G1 nudge marker on a production schema site is rejected (retired class)" || bad "G1 expected rc=1, got $rc"

# G2: GRADUATION — an opt-out with a non-blessed target on a production schema site is rejected;
# only structured-emitter and validator-reference may carry/reference a schema there.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration-optout: some-agent -- its job is exhaustive, honest waiver
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "G2 non-blessed opt-out target on a production schema site is rejected" || bad "G2 expected rc=1, got $rc"

# G3: GRADUATION — the two blessed forms pass in a production file.
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
const emit = (text) =>
  // bounded-exploration-optout: structured-emitter -- tools:[] transcription sink
  agent(text, { agentType: 'review-toolkit:structured-emitter', schema: S })
const opts = {
  // bounded-exploration-optout: validator-reference -- feeds validateShape only
  schema: S,
}
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "G3 emitter + validator-reference forms pass in a production file" || bad "G3 expected rc=0, got $rc"

# G4: GRADUATION — 'delegated' on a production schema site is rejected (retired verb there).
cat > "$FIX/a.mjs" <<'EOF'
const S = { type: 'object' }
// bounded-exploration-optout: validator-reference -- keeps the file non-delegated-only
const V = { schema: S }
// bounded-exploration-delegated: entries declare their own
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "G4 delegated on a production schema site is rejected" || bad "G4 expected rc=1, got $rc"

# A9: *-selftest.mjs files are excluded (offline harnesses carry no live dispatches). With only an
# excluded file present the lint finds zero sites, which is itself a failure by design.
rm -f "$FIX/a.mjs"
cat > "$FIX/thing-selftest.mjs" <<'EOF'
const r = await agent(prompt, { schema: S })
EOF
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "A9 zero detected sites fails rather than passing vacuously" || bad "A9 expected rc=1, got $rc"

# D1-D5: declared-dormancy rule (#175). Each fixture carries one validly-marked schema site so
# rc isolates the dormancy verdict from the zero-sites guard.

# D1: a defined-but-unreferenced BOUNDED_* with no dormant marker is rejected.
rm -f "$FIX/thing-selftest.mjs"
cat > "$FIX/a.mjs" <<'EOF2'
const S = { type: 'object' }
const BOUNDED_DEAD = ' never wired.'
// bounded-exploration-optout: validator-reference -- schema used only as an in-script validator
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF2
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "D1 undeclared dead constant is rejected (rc=1)" || bad "D1 expected rc=1, got $rc"

# D2: the same dead constant with a reasoned dormant marker passes.
cat > "$FIX/a.mjs" <<'EOF2'
const S = { type: 'object' }
// bounded-exploration-dormant: BOUNDED_DEAD -- kept for probe lockstep
const BOUNDED_DEAD = ' never wired.'
// bounded-exploration-optout: validator-reference -- schema used only as an in-script validator
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF2
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "D2 declared-dormant dead constant passes" || bad "D2 expected rc=0, got $rc"

# D3: a dormant marker with no reason after the separator is rejected — declaration means a
# stated reason, same contract as opt-out.
cat > "$FIX/a.mjs" <<'EOF2'
const S = { type: 'object' }
// bounded-exploration-dormant: BOUNDED_DEAD --
const BOUNDED_DEAD = ' never wired.'
// bounded-exploration-optout: validator-reference -- schema used only as an in-script validator
const r = await agent(prompt, { agentType: 'x', schema: S })
EOF2
run_lint "$FIX"; rc=$?
[ "$rc" -eq 1 ] && ok "D3 reasonless dormant marker is rejected" || bad "D3 expected rc=1, got $rc"

# D4: a referenced (wired) constant needs no marker — the rule keys on reachability, not naming.
cat > "$FIX/a.mjs" <<'EOF2'
const S = { type: 'object' }
const BOUNDED_LIVE = ' bound your sweep.'
const prompt2 = prompt + BOUNDED_LIVE
// bounded-exploration-optout: validator-reference -- schema used only as an in-script validator
const r = await agent(prompt2, { agentType: 'x', schema: S })
EOF2
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "D4 wired constant passes without a marker" || bad "D4 expected rc=0, got $rc"

# D5: probe files are exempt from the dormancy rule (their arms are the measurement control).
rm -f "$FIX/a.mjs"
cat > "$FIX/a-probe.mjs" <<'EOF2'
const S = { type: 'object' }
const BOUNDED_THING = ' bound your exploration.'
const BOUNDED_PROBE_ONLY = ' dead in a probe, deliberately.'
// bounded-exploration: BOUNDED_THING
const r = await agent(prompt + BOUNDED_THING, { agentType: 'x', schema: S })
EOF2
run_lint "$FIX"; rc=$?
[ "$rc" -eq 0 ] && ok "D5 probe file is exempt from the dormancy rule" || bad "D5 expected rc=0, got $rc"
rm -f "$FIX/a-probe.mjs"

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

# B3: AC-6 — retries dropped 2 -> 1 on EVERY carrier of dispatchSchemaAgent.
# plan-review.mjs left this list in #348 (deleted with Stage 4). The carriers are enumerated
# rather than globbed, so a file that silently stops carrying the helper is a B3 failure
# rather than an invisible drop from the loop.
for f in unit-tests.mjs design-sync.mjs figma.mjs; do
  if grep -qF 'dispatchSchemaAgent = async (prompt, opts, retries = 1)' "$WORKFLOWS/$f"; then
    ok "B3 $f dispatchSchemaAgent retries = 1"
  else
    bad "B3 $f no longer pins retries = 1 (AC-6)"
  fi
done

# B4: the surviving retry is not a verbatim repeat. NARROWER than B3 by contract, not by
# oversight: RETRY_ESCALATION is the exploration-nudge escalation, and only the two
# exploration-class dispatchers ever carried it — plan-review.mjs (deleted in #348) and
# unit-tests.mjs. design-sync.mjs and figma.mjs carry the retries=1 pin without it, and
# always have; asserting it on them would be a new requirement wearing a regression's clothes.
# shellcheck disable=SC2043  # one carrier since #348 deleted plan-review.mjs; kept as a loop
# because the contract is "every exploration-class dispatcher", not "this one file".
for f in unit-tests.mjs; do
  if grep -qF 'RETRY_ESCALATION' "$WORKFLOWS/$f"; then
    ok "B4 $f retry carries an escalated preamble"
  else
    bad "B4 $f lost RETRY_ESCALATION — a retry would repeat verbatim (AC-6)"
  fi
done

# B5: the probe's plan-shaped arms must dispatch what production dispatches. stall-probe.mjs
# necessarily re-states the plan-shaped schema and nudge (Workflow scripts cannot import), so an
# edit to one without the other silently makes the AFTER rate measure a dispatch nobody ships.
#
# RE-ANCHORED in #348, and this is the load-bearing half of that deletion for #291. The
# production side used to be plan-review.mjs — Stage 4's dispatcher, now deleted — so the
# lockstep would have died with it, leaving the probe's plan-shaped arm free to drift away from
# anything shipped. It does not die: `unit-tests.mjs` in its `kind: 'plan-review'` mode carries
# BOTH tokens verbatim and survives the deletion, so it is the production counterpart now. The
# probe still measures a dispatch that ships.
PROD_PLAN_SHAPED="$WORKFLOWS/unit-tests.mjs"
for token in "verdict: { type: 'string', enum: ['block', 'fix-and-go', 'pass'] }" "GROUND PROPORTIONATELY"; do
  if grep -qF "$token" "$WORKFLOWS/stall-probe.mjs" && grep -qF "$token" "$PROD_PLAN_SHAPED"; then
    ok "B5 stall-probe and unit-tests (plan-review mode) agree on: ${token:0:38}"
  else
    bad "B5 drift between stall-probe.mjs and unit-tests.mjs on: ${token:0:38}"
  fi
done

# B6: the probe keeps an unbounded arm. If `bounded` ever stops gating the nudge there is no
# control, and every AFTER rate becomes unfalsifiable.
if grep -qF 'bounded ? TARGET.nudge' "$WORKFLOWS/stall-probe.mjs"; then
  ok "B6 stall-probe still gates its nudge behind the bounded A/B arg"
else
  bad "B6 stall-probe lost its unbounded control arm"
fi

# B7/B8: declaration order in stall-probe.mjs. A `const` sits in its temporal dead zone until its
# declaration executes, so a table that closes over a constant declared BELOW it throws before a
# single agent dispatches. `node --check` cannot see this (TDZ is a runtime error) and no offline
# harness can execute a Workflow script, so assert the order textually. This bit twice while the
# TARGETS table was being written — once for TARGETS itself, once for a nudge constant it closes
# over — which is why B8 checks the whole closure rather than the one name that failed first.
SP="$WORKFLOWS/stall-probe.mjs"
t_line="$(grep -n '^const TARGETS = {' "$SP" | cut -d: -f1)"
u_line="$(grep -n '^const TARGET = TARGETS\[' "$SP" | cut -d: -f1)"
if [ -n "$t_line" ] && [ -n "$u_line" ] && [ "$t_line" -lt "$u_line" ]; then
  ok "B7 stall-probe defines TARGETS (line $t_line) before resolving it (line $u_line)"
else
  bad "B7 stall-probe resolves TARGETS before defining it — temporal dead zone at dispatch"
fi

if [ -n "$t_line" ] && [ -n "$u_line" ]; then
  # Every SHOUTY_CASE identifier referenced inside the table must be declared above it.
  body_end=$((u_line - 1))
  refs="$(sed -n "$((t_line + 1)),${body_end}p" "$SP" \
    | grep -oE '\b[A-Z][A-Z0-9_]{3,}\b' | sort -u)"
  bad_refs=""
  for r in $refs; do
    # TARGET/TARGETS are the table and its resolution, not things it closes over.
    case "$r" in TARGET|TARGETS) continue ;; esac
    d="$(grep -n "^const ${r} " "$SP" | cut -d: -f1 | head -1)"
    [ -z "$d" ] && continue # not a local const (enum literal, arg name, etc.)
    [ "$d" -lt "$t_line" ] || bad_refs="$bad_refs $r"
  done
  if [ -z "$bad_refs" ]; then
    ok "B8 every constant the TARGETS table closes over is declared above it"
  else
    bad "B8 TARGETS closes over constant(s) declared below it (TDZ at dispatch):$bad_refs"
  fi
fi

# --- C1: the scanned set spans EVERY workflow directory that exists ------------------------
# A lint anchored to a directory list reports a confident green while never having opened the
# files outside it — the self-neutralization class this lint exists to prevent, turned on the
# lint itself. Until the lean lane's in-build reviewer became a separate review session, the shape
# of this case was "the default scan covers MORE files than skills/run alone". With one
# directory left that comparison is unsatisfiable, and re-anchoring it to "the counts are
# equal" would assert nothing about a directory added later.
#
# The invariant that survives the removal is the one worth pinning: the lint refuses to run
# against a stale list. C1a drives the real tree (every discovered dir is listed); C1b PLANTS
# an unlisted workflows/ directory under skills/ and asserts the lint fails rather than
# silently skipping it. C1b is what makes this non-vacuous — without it, the case would pass
# on a lint that had no self-check at all.
C1_OUT="$(bash "$LINT" 2>&1)"; c1_rc=$?
C1_FILES="$(printf '%s' "$C1_OUT" | sed -nE 's/.*across ([0-9]+) file\(s\).*/\1/p')"
if [ "$c1_rc" -eq 0 ] && [ -n "$C1_FILES" ] && [ "$C1_FILES" -ge 1 ]; then
  ok "C1a the default scan runs clean over the real tree and opened $C1_FILES file(s)"
else
  bad "C1a default scan rc=$c1_rc files='$C1_FILES': $C1_OUT"
fi

# The planted directory goes in a MIRROR of the skills/ layout under $TMP, never in the real
# tree: the lint resolves its roots from BASH_SOURCE, so copying it into the mirror is all it
# takes, and an interrupted run then cannot leave a stray directory in the repo.
# #348 changed the mirror's SHAPE, not the case: the lint moved from skills/run/tools/ to the
# plugin's own tools/, so the mirror is now a plugin root rather than a skills/ tree, and the
# planted directory goes under its skills/ subtree — exactly where a future skill-shipped
# workflows/ dir would appear.
MIRROR="$TMP/plugin"
mkdir -p "$MIRROR/tools" "$MIRROR/workflows"
cp "$LINT" "$MIRROR/tools/"
cp "$WORKFLOWS"/*.mjs "$MIRROR/workflows/"   # the real, known-clean corpus
MIRROR_LINT="$MIRROR/tools/$(basename "$LINT")"

# Control first: the mirror itself must be clean, or C1b would "pass" for the wrong reason.
bash "$MIRROR_LINT" >/dev/null 2>&1; c1ctl_rc=$?
mkdir -p "$MIRROR/skills/other-skill/workflows"
cp "$MIRROR/workflows/"*.mjs "$MIRROR/skills/other-skill/workflows/"
C1B_OUT="$(bash "$MIRROR_LINT" 2>&1)"; c1b_rc=$?
if [ "$c1ctl_rc" -eq 0 ] && [ "$c1b_rc" -ne 0 ] && grep -q 'absent from WORKFLOW_DIRS' <<<"$C1B_OUT"; then
  ok "C1b a workflows/ directory outside WORKFLOW_DIRS fails the lint instead of being silently skipped"
else
  bad "C1b control rc=$c1ctl_rc (want 0), planted rc=$c1b_rc (want non-zero): $C1B_OUT"
fi

echo "check-bounded-exploration-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
