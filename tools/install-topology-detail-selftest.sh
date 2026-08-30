#!/usr/bin/env bash
#
# install-topology-detail-selftest.sh — behavioral coverage for the ONE reporting path in
# tools/install-topology-selftest.sh that never runs on a green tree: the `detail` string a
# RED line carries.
#
# INVARIANT GUARDED: when a staged suite fails, the one line install-topology prints about it
# names THAT SUITE'S OWN failure, not a line that merely contains the substring "fail".
#
# WHY THIS IS WORTH A SUITE (#664). install-topology is a nightly guard, so its red line is
# usually the only thing a human reads about a failure — the captured log is deleted with
# $BASE on exit and never leaves the runner. The line composed the detail as
# `grep -iE 'FAIL|error|No such|not found' "$log" | head -1`, and for
# pipeline-doctor-selftest.sh the first line matching that is a PASSING one:
# `ok: (d3) completed + failed at 24h → never stale`. Seven consecutive nightly reds
# therefore named a green case while the real `FAIL: (inv/sibling)` sat 37 lines below,
# unquoted. The defect was not that the guard failed to catch a regression — it caught it
# every night — but that it could not say what it had caught.
#
# WHY NO SCENARIO COVERS IT (CLAUDE.md scenario-first rule): scenario-liveness-selftest.sh
# composes verdict paths through the lean gate to a terminal WRITE. This path is inside a
# selftest harness that runs outside any pipeline run, writes nothing, and is reached only
# when another suite has already exited non-zero. There is no verdict path to compose it onto.
#
# WHY NOT INSIDE install-topology-selftest.sh ITSELF: that file stages and runs every shipped
# suite — ~5 to 10 minutes, nightly-only since #620. A guard for three lines of grep must not
# inherit that cost, or it runs a day late for a defect the PR lane could have caught. This
# suite stages nothing and needs no plugins.
#
# TECHNIQUE: extract-and-execute, not grep. The block is delimited in
# install-topology-selftest.sh by `# >>> red-detail` / `# <<< red-detail` and is re-hosted
# here against fixture logs. A hand-copied grep would be the mirror harness CLAUDE.md bans:
# it could not fail when the real composition drifts.
#
# Operator-safe: no gh, no network, no Claude CLI. bash-3.2-safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${INSTALL_TOPOLOGY_SH:-$SCRIPT_DIR/install-topology-selftest.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$GUARD" ]] || {
  echo "install-topology-detail-selftest: FAIL — not found at $GUARD" >&2
  exit 1
}

DETAIL_BLOCK="$(sed -n '/# >>> red-detail/,/# <<< red-detail/p' "$GUARD")"
if [[ -z "$DETAIL_BLOCK" ]]; then
  echo "install-topology-detail-selftest: FAIL — red-detail sentinels not found in $GUARD." >&2
  echo "  (the scoring loop was refactored without updating this suite — that is the regression this guard exists for)" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-topology-detail-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Run the REAL block against a fixture log. detail() <rc> <log-body> → the composed string.
RESULTS="$WORK/results"
mkdir -p "$RESULTS"
# shellcheck disable=SC2034  # read by the EXTRACTED block's 124 arm, not by this file
SUITE_TIMEOUT=1200
detail() { # detail <rc> <log-body>
  # shellcheck disable=SC2034  # rc and idx are read by the EXTRACTED block, not by this file
  local rc="$1" body="$2" idx=0001
  printf '%s\n' "$body" > "$RESULTS/$idx.log"
  ( set -uo pipefail
    detail=""
    eval "$DETAIL_BLOCK"
    printf '%s\n' "$detail" )
}

# ---------------------------------------------------------------------------
# (t1) THE #664 REGRESSION. A passing line containing "failed" sits ABOVE the real FAIL line.
# This is pipeline-doctor-selftest.sh's actual output shape, trimmed to the two lines that
# decide it: the whole defect is which of them the detail quotes.
# ---------------------------------------------------------------------------
t1_log='  ok: (d3) completed + failed at 24h → never stale (terminal by contract)
  ok: (d4) quarantined files skipped
  FAIL: (inv/sibling) pipeline-doctor delegates to selftest(s) that do not exist'
t1_out="$(detail 1 "$t1_log")"
case "$t1_out" in
  *"(inv/sibling)"*)
    ok "(t1) a passing line containing 'failed' does not outrank the suite's own FAIL line" ;;
  *"(d3)"*)
    bad "(t1) the detail named the PASSING (d3) line — the loose substring sweep is deciding again, so a nightly red points at a green case. Got:[$t1_out]" ;;
  *)
    bad "(t1) expected the FAIL line, got:[$t1_out]" ;;
esac

# (t1b) control for (t1): the marker preference must not be a blanket "always take the last
# line" or "always skip line 1". With the FAIL line FIRST, it is still the one quoted.
t1b_log='  FAIL: (inv/sibling) the real failure
  ok: (d3) completed + failed at 24h → never stale'
t1b_out="$(detail 1 "$t1b_log")"
case "$t1b_out" in
  *"(inv/sibling)"*) ok "(t1b) control — a FAIL line in first position is still the one quoted" ;;
  *) bad "(t1b) control — expected the FAIL line, got:[$t1b_out]" ;;
esac

# ---------------------------------------------------------------------------
# (t2) the marker set. Suites in this tree emit `FAIL:`, `FATAL:` and `RED:`; a marker the
# preference does not know falls back to the loose sweep and the defect returns for that
# suite alone. Each is asserted with a decoy above it, so a pass means the marker WON, not
# that it happened to be the only line.
# ---------------------------------------------------------------------------
for t2_marker in FAIL FATAL RED ERROR; do
  t2_out="$(detail 1 "  ok: this line says failed and comes first
$t2_marker: the real one")"
  case "$t2_out" in
    *"the real one"*)
      ok "(t2/$t2_marker) a leading $t2_marker marker outranks an earlier prose match" ;;
    *)
      bad "(t2/$t2_marker) the $t2_marker marker did not win over the decoy — that marker is unrecognized, so suites using it still report the wrong line. Got:[$t2_out]" ;;
  esac
done

# ---------------------------------------------------------------------------
# (t3) the FALLBACK is still live. A suite that dies before printing any marker — the
# `No such file or directory` class the original grep was written for — must still get a
# detail. Dropping the fallback in favour of the marker preference would turn those reds
# into `rc=127 — ` with nothing after the dash.
# ---------------------------------------------------------------------------
t3_out="$(detail 127 "bash: /staged/thing.sh: No such file or directory")"
case "$t3_out" in
  *"No such file"*) ok "(t3) a log with no marker line still falls back to the loose sweep" ;;
  *) bad "(t3) the fallback is dead — a marker-less failure reports nothing. Got:[$t3_out]" ;;
esac

# (t3b) an EMPTY log must not crash the block or lose the rc.
t3b_out="$(detail 3 "")"
case "$t3b_out" in
  "rc=3 — "*) ok "(t3b) an empty log still carries the rc, and nothing crashes" ;;
  *) bad "(t3b) expected an rc-carrying detail for an empty log, got:[$t3b_out]" ;;
esac

# ---------------------------------------------------------------------------
# (t4) the rc is part of the line. It is the only machine-readable field a reader gets once
# $BASE is deleted, and a detail that drops it cannot be triaged at all.
# ---------------------------------------------------------------------------
t4_out="$(detail 42 "FAIL: something")"
case "$t4_out" in
  "rc=42 — FAIL: something") ok "(t4) the composed detail is 'rc=<n> — <the suite's line>'" ;;
  *) bad "(t4) expected 'rc=42 — FAIL: something', got:[$t4_out]" ;;
esac

# ---------------------------------------------------------------------------
# (t5) leading whitespace is stripped. Most suites indent their FAIL lines two spaces; a
# detail that keeps the indent reads as a broken column in the summary.
# ---------------------------------------------------------------------------
t5_out="$(detail 1 "      FAIL: indented deeply")"
case "$t5_out" in
  "rc=1 — FAIL: indented deeply") ok "(t5) leading whitespace is stripped from the quoted line" ;;
  *) bad "(t5) expected the indent stripped, got:[$t5_out]" ;;
esac

# ---------------------------------------------------------------------------
# (t6) the INFRA arms. 124, 125 and a signal death are not assertion failures — no case in
# the suite decided anything — so each is named rather than described by whatever the log
# happened to contain. The fixture log carries a PASS line on purpose: these arms must not
# read it at all, and the whole #664 disease is a red quoting a line that had just succeeded.
# ---------------------------------------------------------------------------
t6_log='  PASS: milestone-1 fails when the lean spec is absent'

t6_out="$(detail 124 "$t6_log")"
case "$t6_out" in
  *"timed out after 1200s"*) ok "(t6/124) a timeout is named as the bound, and does not quote the log" ;;
  *) bad "(t6/124) expected the timeout wording, got:[$t6_out]" ;;
esac

t6_out="$(detail 125 "$t6_log")"
case "$t6_out" in
  *"no verdict written"*) ok "(t6/125) a worker that wrote no verdict is named as infra, and does not quote the log" ;;
  *) bad "(t6/125) expected the no-verdict wording, got:[$t6_out]" ;;
esac

# 143 = SIGTERM. Observed for real: an outer reaper took the process group mid-suite, and the
# detail read `rc=143 — PASS: milestone-1 fails when the lean spec is absent` — a red naming an
# assertion that had just passed, on a tree with nothing wrong with it.
for t6_sig in 130 137 143; do
  t6_out="$(detail "$t6_sig" "$t6_log")"
  case "$t6_out" in
    *"PASS:"*)
      bad "(t6/$t6_sig) a signal-killed suite quoted a PASSING line from its log — the loose sweep is deciding for a run that reached no verdict. Got:[$t6_out]" ;;
    *"killed by signal $((t6_sig - 128))"*)
      ok "(t6/$t6_sig) a signal-killed suite is named as infra, with the signal number" ;;
    *)
      bad "(t6/$t6_sig) expected the signal wording, got:[$t6_out]" ;;
  esac
done

# (t6-control) the signal range must not swallow an ORDINARY non-zero rc. A suite exiting 1
# is a real failure and has to keep quoting its own FAIL line; a range that reached down to it
# would silence every genuine red into "infra, not a result".
t6c_out="$(detail 1 "  FAIL: (inv/sibling) the real failure")"
case "$t6c_out" in
  *"(inv/sibling)"*) ok "(t6-control) rc=1 is still a real failure and still quotes the suite's FAIL line" ;;
  *) bad "(t6-control) the infra arms swallowed an ordinary failure. Got:[$t6c_out]" ;;
esac

echo "[install-topology-detail-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
