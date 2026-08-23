#!/usr/bin/env bash
# predecessor-gate-selftest.sh — behavioral selftest for tools/predecessor-gate.sh.
#
# Harness shape came from a since-deleted suite's `(mps)` section — deleted with the staged
# lane in #348, leaving this file its only carrier: a one-line helper pipes
# literal fixture text into the tool and the cases assert on stdout / exit code.
# There is deliberately NO `gh` mock anywhere — the tool is pure logic by contract
# (the stage doc owns every tracker read), so there is nothing to mock and CI stays
# model-free and network-free.
#
# Exit code = number of failed checks (repo selftest convention).

set -uo pipefail
unset KEY_PATTERN

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/predecessor-gate.sh"

[[ -x "$GATE" ]] || { echo "[predecessor-gate-selftest] FATAL: $GATE not executable"; exit 99; }

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# pg <body> [KEY_PATTERN] — extract, stdout only (warnings suppressed).
pg() {
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$1" | KEY_PATTERN="$2" bash "$GATE" extract 2>/dev/null
  else
    printf '%s\n' "$1" | bash "$GATE" extract 2>/dev/null
  fi
}

# pg_err <body> — extract, stderr only (the malformed-trailer warning channel).
pg_err() { { printf '%s\n' "$1" | bash "$GATE" extract >/dev/null; } 2>&1; }

echo "== predecessor-gate.sh =="

# extract — trailer combinations (AC-1)

got=$(pg $'Some body text.\n\nPredecessor: #262\nSuccessor: #265')
want=$'predecessor=262\nsuccessor=265'
[[ "$got" == "$want" ]] && pass "(pg1) both trailers → both lines (AC-1)" \
  || fail "(pg1) both trailers → got '$got' (want '$want')"

got=$(pg $'Body.\n\nPredecessor: #262')
[[ "$got" == "predecessor=262" ]] && pass "(pg2) predecessor only → predecessor line only (AC-1)" \
  || fail "(pg2) predecessor only → got '$got' (want predecessor=262)"

got=$(pg $'Body.\n\nSuccessor: #265')
[[ "$got" == "successor=265" ]] && pass "(pg3) successor only → successor line only (AC-1)" \
  || fail "(pg3) successor only → got '$got' (want successor=265)"

got=$(pg $'A plain issue body with no trailers at all.')
rc=$(printf '%s\n' 'no trailers' | bash "$GATE" extract >/dev/null 2>&1; echo $?)
[[ -z "$got" && "$rc" == "0" ]] && pass "(pg4) no trailers → no output, exit 0 (AC-1)" \
  || fail "(pg4) no trailers → got '$got' rc=$rc (want empty, 0)"

got=$(pg $'Predecessor: 262\nSuccessor: 265')
want=$'predecessor=262\nsuccessor=265'
[[ "$got" == "$want" ]] && pass "(pg5) '#' prefix optional — bare numbers extract identically (AC-1)" \
  || fail "(pg5) bare numbers → got '$got' (want '$want')"

# extract — KEY_PATTERN parameterization (AC-1)

got=$(pg $'Predecessor: GH-540\nSuccessor: GH-542' '[A-Z]+-[0-9]+')
want=$'predecessor=GH-540\nsuccessor=GH-542'
[[ "$got" == "$want" ]] && pass "(pg6) jira KEY_PATTERN → jira keys extract (AC-1)" \
  || fail "(pg6) jira KEY_PATTERN → got '$got' (want '$want')"

got=$(pg $'Predecessor: GH-540')
[[ -z "$got" ]] && pass "(pg7) cross-pattern isolation — jira key under the github default does NOT extract (AC-1)" \
  || fail "(pg7) cross-pattern isolation → got '$got' (want empty)"

got=$(pg $'Predecessor: 262' '[A-Z]+-[0-9]+')
[[ -z "$got" ]] && pass "(pg8) cross-pattern isolation, reverse — a bare number under the jira pattern does NOT extract (AC-1)" \
  || fail "(pg8) reverse cross-pattern → got '$got' (want empty)"

# extract — malformed / duplicate handling (AC-1, plan D-2)

got=$(pg $'Predecessor: #two')
rc=$(printf '%s\n' 'Predecessor: #two' | bash "$GATE" extract >/dev/null 2>&1; echo $?)
[[ -z "$got" && "$rc" == "0" ]] && pass "(pg9) malformed value → no line, still exit 0 (fail-open by design)" \
  || fail "(pg9) malformed value → got '$got' rc=$rc (want empty, 0)"

err=$(pg_err $'Predecessor: #two')
case "$err" in
  *"unparseable Predecessor trailer"*) pass "(pg10) malformed value → warning on stderr (the fail-open is visible)" ;;
  *) fail "(pg10) malformed warning → got '$err'" ;;
esac

got=$(pg $'Predecessor: #100\nsome prose\nPredecessor: #262')
[[ "$got" == "predecessor=262" ]] && pass "(pg11) duplicate trailers → LAST wins (git trailer convention)" \
  || fail "(pg11) duplicate trailers → got '$got' (want predecessor=262)"

# (pg12) The anti-false-positive case, driven by this repo's own issue-body shape:
# inline-backticked prose mentioning the trailer names must NOT extract, while a
# real trailer in the same body must. Without the strict full-line anchor, #263's
# own body would have yielded a bogus predecessor.
body=$'- `Predecessor:`/`Successor:` trailers rendered per `tracker.keyPattern` (D-3/D-14)\n- each blocked body states "queue when <predecessor> is closed"\n\nSuccessor: #265'
got=$(pg "$body")
[[ "$got" == "successor=265" ]] && pass "(pg12) inline-backticked prose does NOT extract; the real trailer still does" \
  || fail "(pg12) prose false-positive → got '$got' (want successor=265)"

# (pg13) CRLF bodies — the GitHub API returns \r\n, so the `$` anchor must not be
# defeated by a trailing CR.
got=$(printf 'Predecessor: #262\r\nSuccessor: #265\r\n' | bash "$GATE" extract 2>/dev/null)
want=$'predecessor=262\nsuccessor=265'
[[ "$got" == "$want" ]] && pass "(pg13) CRLF body → trailers still extract (GitHub API line endings)" \
  || fail "(pg13) CRLF body → got '$got' (want '$want')"

# (pg14) A body whose final line is the trailer with NO trailing newline.
got=$(printf 'body\nSuccessor: #265' | bash "$GATE" extract 2>/dev/null)
[[ "$got" == "successor=265" ]] && pass "(pg14) final line without trailing newline still extracts" \
  || fail "(pg14) no trailing newline → got '$got' (want successor=265)"

rc=$(printf 'x\n' | bash "$GATE" extract stray-arg >/dev/null 2>&1; echo $?)
[[ "$rc" == "2" ]] && pass "(pg15) extract with a stray argument → usage error rc=2" \
  || fail "(pg15) extract stray arg → rc=$rc (want 2)"

# verdict — the gate semantics (AC-1)

vrc() { bash "$GATE" verdict "$@" >/dev/null 2>&1; echo $?; }

rc=$(vrc closed)
[[ "$rc" == "0" ]] && pass "(pg16) verdict closed → exit 0 (proceed) (AC-1)" \
  || fail "(pg16) verdict closed → rc=$rc (want 0)"

rc=$(vrc open)
[[ "$rc" == "3" ]] && pass "(pg17) verdict open → exit 3 (skip-blocked) (AC-1)" \
  || fail "(pg17) verdict open → rc=$rc (want 3)"

rc=$(vrc)
[[ "$rc" == "2" ]] && pass "(pg18) verdict with no state → usage error rc=2 (AC-1)" \
  || fail "(pg18) verdict no arg → rc=$rc (want 2)"

rc=$(vrc merged)
[[ "$rc" == "2" ]] && pass "(pg19) verdict with an unknown state → rc=2, never a silent proceed (AC-1)" \
  || fail "(pg19) verdict unknown state → rc=$rc (want 2)"

rc=$(vrc CLOSED)
[[ "$rc" == "2" ]] && pass "(pg20) verdict state is case-sensitive — 'CLOSED' is a usage error, not a proceed" \
  || fail "(pg20) verdict CLOSED → rc=$rc (want 2)"

rc=$(bash "$GATE" >/dev/null 2>&1; echo $?)
[[ "$rc" == "2" ]] && pass "(pg21) no mode → usage error rc=2" \
  || fail "(pg21) no mode → rc=$rc (want 2)"

rc=$(bash "$GATE" bogus >/dev/null 2>&1; echo $?)
[[ "$rc" == "2" ]] && pass "(pg22) unknown mode → usage error rc=2" \
  || fail "(pg22) unknown mode → rc=$rc (want 2)"

echo
echo "predecessor-gate-selftest: $PASS passed, $FAIL failed"
exit "$FAIL"
