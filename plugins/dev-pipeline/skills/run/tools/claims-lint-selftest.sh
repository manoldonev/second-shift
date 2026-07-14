#!/usr/bin/env bash
# claims-lint-selftest.sh — fixture-driven selftest for claims-lint.sh (#68).
# Maps 1:1 to the issue's acceptance cases: (a) expired claim -> FAIL naming the id;
# (b) failing probe -> WARN with remediation; (c) probe over vanished root ->
# probe-broken, not a pass; (d) passing probe -> no "verified" wording anywhere.
# Plus: the DSL rejects arbitrary command strings, the expiry x probe matrix
# (expired + passing probe still FAILs), grammar fail-closed, and quiet no-op paths.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/claims-lint.sh"
FIX="$HERE/claims-lint-fixtures"
FAILS=0

# Deterministic "today" — the fixture expiry facts never rot.
export SECOND_SHIFT_CLAIMS_TODAY="2026-01-01"

check() { # $1 = label, $2 = expectation result (0 ok / 1 fail)
  if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS + 1)); fi
}

run_lint() { # $1 = fixture dir; sets OUT and RC
  set +e
  OUT=$("$LINT" "$FIX/$1" 2>&1)
  RC=$?
  set -e
}

expect() { # $1 = fixture, $2 = expected rc (numeric or "nonzero"), $3.. = required substrings
  local fixture="$1" wantrc="$2"; shift 2
  run_lint "$fixture"
  if [[ "$wantrc" == "nonzero" ]]; then
    [[ "$RC" -ne 0 ]] && check "$fixture exits nonzero" 0 || check "$fixture exits nonzero (got $RC)" 1
  else
    [[ "$RC" -eq "$wantrc" ]] && check "$fixture exits $wantrc" 0 || check "$fixture exits $wantrc (got $RC)" 1
  fi
  local s
  for s in "$@"; do
    if grep -qF "$s" <<< "$OUT"; then
      check "$fixture output mentions '$s'" 0
    else
      check "$fixture output mentions '$s' (got: $(head -2 <<< "$OUT" | tr '\n' ' '))" 1
    fi
  done
}

echo "claims-lint selftest:"

# (a) expired claim -> FAIL naming the claim id.
expect expired nonzero "expired claim 'no-auth-system'"

# expiry x probe matrix: a PASSING probe never suppresses the expiry FAIL.
expect expired-with-passing-probe nonzero "expired claim 'no-auth-system'"
run_lint expired-with-passing-probe
grep -q "not-yet-contradicted" <<< "$OUT" \
  && check "matrix: probe evaluated (not-yet-contradicted) alongside the expiry FAIL" 0 \
  || check "matrix: probe evaluated alongside the expiry FAIL" 1

# reverify-by is mandatory; version/ref form is rejected in v1.
expect missing-reverify nonzero "has no reverify-by"
expect version-form nonzero "not date-form"

# (b) failing probe -> loud WARN with the remediation line; NOT a FAIL (exit 0).
expect probe-failing 0 "probe failing for claim 'no-auth-system'" \
  "re-verify the claim against the code and edit the prose" \
  "audit smell"

# (c) probe over a vanished root -> probe-broken, never a silent pass.
expect probe-broken 0 "probe-broken for claim 'no-auth-system'" "probe target vanished"
run_lint probe-broken
grep -q "not-yet-contradicted: 1\|1 probe(s) not-yet-contradicted" <<< "$OUT" \
  && check "probe-broken is not counted as a holding probe" 1 \
  || check "probe-broken is not counted as a holding probe" 0

# (d) passing probe -> exit 0 and NO "verified" wording anywhere in the output.
run_lint passing
[[ "$RC" -eq 0 ]] && check "passing exits 0" 0 || check "passing exits 0 (got $RC)" 1
if grep -qi "verified" <<< "$OUT"; then
  check "passing output contains no 'verified' wording (a pass never mints evidence)" 1
else
  check "passing output contains no 'verified' wording (a pass never mints evidence)" 0
fi
grep -q "not-yet-contradicted" <<< "$OUT" \
  && check "passing probe reported as not-yet-contradicted" 0 \
  || check "passing probe reported as not-yet-contradicted" 1
grep -q "probe-less (expiry-only): no-web-tests" <<< "$OUT" \
  && check "probe-less claims surface as the one quiet summary slug list" 0 \
  || check "probe-less claims surface as the one quiet summary slug list" 1

# DSL rejects arbitrary command strings (all three smuggling shapes).
expect injection nonzero "arbitrary command strings are rejected" "shell metacharacters"
run_lint injection
[[ "$RC" -eq 3 ]] && check "injection: all three smuggled probes rejected (rc=3)" 0 \
  || check "injection: all three smuggled probes rejected (rc=3, got $RC)" 1

# Unknown keys fail closed (a typo'd waiver must be loud).
expect parse-error nonzero "unrecognized line"

# Quiet no-op paths: no fences / no extension dir at all.
expect no-claims 0
run_lint no-claims
[[ -z "$OUT" ]] && check "no-claims produces no output" 0 || check "no-claims produces no output" 1
NODIR="$(mktemp -d -t claims-nodir.XXXXXX)"
set +e; OUT=$("$LINT" "$NODIR" 2>&1); RC=$?; set -e
[[ "$RC" -eq 0 && -z "$OUT" ]] && check "repo without .claude/second-shift is a silent exit 0" 0 \
  || check "repo without .claude/second-shift is a silent exit 0" 1
rmdir "$NODIR"

echo ""
if [[ "$FAILS" -eq 0 ]]; then
  echo "claims-lint selftest: OK"
else
  echo "claims-lint selftest: $FAILS failed check(s)" >&2
  exit 1
fi
