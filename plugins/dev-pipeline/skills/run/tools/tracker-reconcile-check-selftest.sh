#!/usr/bin/env bash
# tracker-reconcile-check-selftest.sh — behavioral selftest for tools/tracker-reconcile-check.sh
# (second-shift#149).
#
# Harness shape mirrors predecessor-gate-selftest.sh: `pass`/`fail` helpers, exit code =
# failure count. There is deliberately NO `gh`/`statectl` mock anywhere — the tool is pure
# logic by contract (SKILL.md's resume rule owns the one tracker read), so there is
# nothing to mock and CI stays model-free and network-free.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/tracker-reconcile-check.sh"

[[ -x "$CHECK" ]] || { echo "[tracker-reconcile-check-selftest] FATAL: $CHECK not executable"; exit 99; }

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# tc <args...> — verdict mode, stdout only (stderr suppressed).
tc() { bash "$CHECK" verdict "$@" 2>/dev/null; }
# tc_rc <args...> — verdict mode, exit code only.
tc_rc() { bash "$CHECK" verdict "$@" >/dev/null 2>&1; echo $?; }

echo "== tracker-reconcile-check.sh =="

# ---------------------------------------------------------------------------
# verdict — terminal run-status short-circuits (AC-1)
# ---------------------------------------------------------------------------

got=$(tc completed false)
rc=$(tc_rc completed false)
[[ "$got" == "verdict=not-applicable" && "$rc" == "0" ]] \
  && pass "(trc1) completed + tracker open → not-applicable, rc=0 (AC-1)" \
  || fail "(trc1) completed + tracker open → got '$got' rc=$rc (want not-applicable, 0)"

got=$(tc failed true 155 https://example/pull/155)
rc=$(tc_rc failed true 155 https://example/pull/155)
[[ "$got" == "verdict=not-applicable" && "$rc" == "0" ]] \
  && pass "(trc2) failed + tracker closed + PR → still not-applicable (terminal short-circuits) (AC-1)" \
  || fail "(trc2) failed + closed + PR → got '$got' rc=$rc (want not-applicable, 0)"

# ---------------------------------------------------------------------------
# verdict — in_progress, tracker not closed (AC-1)
# ---------------------------------------------------------------------------

got=$(tc in_progress false)
rc=$(tc_rc in_progress false)
[[ "$got" == "verdict=resume-normal" && "$rc" == "0" ]] \
  && pass "(trc3) in_progress + tracker open → resume-normal, rc=0 (AC-1)" \
  || fail "(trc3) in_progress + open → got '$got' rc=$rc (want resume-normal, 0)"

got=$(tc in_progress false 155 https://example/pull/155)
[[ "$got" == "verdict=resume-normal" ]] \
  && pass "(trc4) in_progress + tracker open, PR pair ignored → resume-normal (AC-1)" \
  || fail "(trc4) in_progress + open + PR → got '$got' (want resume-normal)"

# ---------------------------------------------------------------------------
# verdict — in_progress, tracker closed without a linked PR (AC-1)
# ---------------------------------------------------------------------------

got=$(tc in_progress true)
rc=$(tc_rc in_progress true)
[[ "$got" == "verdict=resume-normal" && "$rc" == "0" ]] \
  && pass "(trc5) in_progress + tracker closed, no PR → resume-normal (manual close, nothing shipped) (AC-1)" \
  || fail "(trc5) in_progress + closed, no PR → got '$got' rc=$rc (want resume-normal, 0)"

# ---------------------------------------------------------------------------
# verdict — in_progress, tracker closed via a named PR: the reconcile case (AC-1)
# ---------------------------------------------------------------------------

got=$(tc in_progress true 155 https://example/pull/155)
rc=$(tc_rc in_progress true 155 https://example/pull/155)
want=$'verdict=reconcile-recommended\nclosingPrNumber=155\nclosingPrUrl=https://example/pull/155'
[[ "$got" == "$want" && "$rc" == "4" ]] \
  && pass "(trc6) in_progress + closed + PR named → reconcile-recommended, rc=4, PR fields echoed (AC-1)" \
  || fail "(trc6) in_progress + closed + PR → got '$got' rc=$rc (want '$want', 4)"

# ---------------------------------------------------------------------------
# verdict — usage errors (AC-1): never a silent resume-normal
# ---------------------------------------------------------------------------

rc=$(tc_rc)
[[ "$rc" == "2" ]] && pass "(trc7) verdict with no args → usage error rc=2" \
  || fail "(trc7) verdict no args → rc=$rc (want 2)"

rc=$(tc_rc in_progress)
[[ "$rc" == "2" ]] && pass "(trc8) verdict missing tracker-closed → usage error rc=2" \
  || fail "(trc8) verdict missing tracker-closed → rc=$rc (want 2)"

rc=$(tc_rc queued false)
[[ "$rc" == "2" ]] && pass "(trc9) unknown run-status → usage error rc=2, never a silent resume" \
  || fail "(trc9) unknown run-status → rc=$rc (want 2)"

rc=$(tc_rc In_Progress false)
[[ "$rc" == "2" ]] && pass "(trc10) run-status is case-sensitive — 'In_Progress' is a usage error" \
  || fail "(trc10) case-sensitive run-status → rc=$rc (want 2)"

rc=$(tc_rc in_progress maybe)
[[ "$rc" == "2" ]] && pass "(trc11) unknown tracker-closed value → usage error rc=2" \
  || fail "(trc11) unknown tracker-closed → rc=$rc (want 2)"

rc=$(tc_rc in_progress TRUE)
[[ "$rc" == "2" ]] && pass "(trc12) tracker-closed is case-sensitive — 'TRUE' is a usage error" \
  || fail "(trc12) case-sensitive tracker-closed → rc=$rc (want 2)"

rc=$(tc_rc in_progress true 155)
[[ "$rc" == "2" ]] && pass "(trc13) pr-number without pr-url → usage error rc=2 (one-of-the-pair)" \
  || fail "(trc13) pr-number only → rc=$rc (want 2)"

rc=$(tc_rc in_progress true "" https://example/pull/155)
[[ "$rc" == "2" ]] && pass "(trc14) pr-url without pr-number → usage error rc=2 (one-of-the-pair)" \
  || fail "(trc14) pr-url only → rc=$rc (want 2)"

rc=$(bash "$CHECK" >/dev/null 2>&1; echo $?)
[[ "$rc" == "2" ]] && pass "(trc15) no mode → usage error rc=2" \
  || fail "(trc15) no mode → rc=$rc (want 2)"

rc=$(bash "$CHECK" bogus >/dev/null 2>&1; echo $?)
[[ "$rc" == "2" ]] && pass "(trc16) unknown mode → usage error rc=2" \
  || fail "(trc16) unknown mode → rc=$rc (want 2)"

err=$(bash "$CHECK" 2>&1 >/dev/null)
[[ "$err" == *"usage"* ]] && pass "(trc17) no-mode usage error prints a usage message to stderr" \
  || fail "(trc17) usage stderr → got '$err' (want it to mention usage)"

echo
echo "tracker-reconcile-check-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
