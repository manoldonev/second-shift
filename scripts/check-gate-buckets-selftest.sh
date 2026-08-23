#!/usr/bin/env bash
#
# check-gate-buckets-selftest.sh — behavioral coverage for scripts/check-gate-buckets.sh.
#
# INVARIANT GUARDED: the enumerator and the register check EACH OTHER, and every way they can
# disagree reds INDEPENDENTLY. An enumerated refusal site with no row (g2); an anchor that no
# longer resolves in its file (g3); a row whose anchor resolves but covers no live site (g4); a
# site two rows dispose of differently (g5). A guard with only the happy path would stay green
# while the register quietly stopped describing the tree — the exact failure mode the
# denominator-as-artifact design exists to prevent, and the one #636 was filed against.
#
# THE SAFETY ARM IS THE OTHER HALF (g7/g8/g9). AC-5 is register-INTERNAL: a bucket that never
# yields must carry the empty yield cell, and a cell naming an OVERRIDE_GATES value must be
# gates-process. Both directions are cased, because the thing being prevented — a future edit
# wiring a red test lane to an operator waiver — is a one-cell edit that no proximity reading
# would catch.
#
# THE NEGATIVE DIRECTION (g17) pins what the recipe must NOT enumerate: a mention in a comment, a
# helper's own definition line, and a primitive's name sitting in ARGUMENT position. An enumerator
# that reds on those gets an exclusion baselined into it within a week, and then it guards nothing.
#
# TECHNIQUE: fixture trees under mktemp, each carrying the five corpus paths and its own
# scripts/gate-buckets.tsv, handed to the REAL guard as its repo root. No production file is
# written.
#
# Operator-safe: no gh, no network. bash-3.2-safe. Runs in CI via the '*-selftest.sh' loop.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${GATE_BUCKETS_GUARD:-$HERE/check-gate-buckets.sh}"

PASS=0
FAILS=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; [ -n "${2:-}" ] && printf '    %s\n' "$2" >&2; }

[ -f "$GUARD" ] || { echo "check-gate-buckets-selftest: FAIL — guard not found at $GUARD" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate-buckets-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

TAB="$(printf '\t')"
LG='plugins/dev-pipeline/skills/build-lean/lean-gate.sh'
LE='plugins/dev-pipeline/skills/build-lean/lean-evidence.sh'
OL='plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh'
OO='plugins/dev-pipeline/tools/operator-override.sh'
CC='scripts/check-lean-chain.sh'

row() { printf '%s%s%s%s%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$4" "$TAB" "$5"; }

# new_fixture <name> — the five corpus files with one or two refusal sites each, and a register
# that disposes of every one of them. Green by construction; each case below breaks exactly one
# thing.
new_fixture() {
  local d="$WORK/$1"
  mkdir -p "$d/$(dirname "$LG")" "$d/$(dirname "$OL")" "$d/$(dirname "$OO")" "$d/scripts"
  cat > "$d/$LG" <<'EOF'
#!/usr/bin/env bash
envfail() { echo "$1" >&2; exit 2; }
fail_milestone() { echo "$@" >&2; }
#   [ -f spec ] || { fail_milestone 1 "a retired site kept only as prose"; }
cmd_1() {
  [ -f spec ] || { fail_milestone 1 "no committed spec on the branch"; return $?; }
  [ -n "$CFG" ] || envfail "cannot read the config"
}
EOF
  cat > "$d/$LE" <<'EOF'
#!/usr/bin/env bash
envfail() { echo "$1" >&2; exit 2; }
note_violation() { echo "$1" >&2; }
arm_identity() {
  note_violation "verdict record carries the BUILD run's identity"
  [ -n "$PR" ] || envfail "no PR body to read"
}
EOF
  cat > "$d/$OL" <<'EOF'
#!/usr/bin/env bash
terminal() { launch_note terminal "$1 rc=$2"; exit "$2"; }
envfail() { terminal "$1" 2 "$2"; }
main() {
  terminal preflight-rejected 2 "preflight rejected — nothing was spawned."
  envfail env-no-git-repo "not in a git repo."
}
EOF
  cat > "$d/$OO" <<'EOF'
#!/usr/bin/env bash
OVERRIDE_GATES='intake-unqueued spec-open-region'
OVERRIDE_SCOPES='intake-attestation open-region-resolution'
envfail() { echo "$1" >&2; exit 2; }
cmd_record() { [ -n "$1" ] || envfail "record: --decision is required"; }
EOF
  cat > "$d/$CC" <<'EOF'
#!/usr/bin/env bash
fail()    { echo "$1" >&2; exit 1; }
envfail() { echo "$1" >&2; exit 2; }
note_violation() { echo "$1" >&2; }
check() {
  note_violation "no committed lean spec"
  [ -n "$BODY" ] || fail "PR body carries no resolvable issue reference"
  [ -n "$ROOT" ] || envfail "no repo root"
}
EOF
  {
    printf '# fixture register\n\n'
    row "$LG::fail_milestone" gates-signal 'fail_milestone 1 "no committed spec on the branch"' - 'fixture: objective absence.'
    row "$LG::envfail"        not-a-gate   'envfail '                                            - 'environment refusal — fixture.'
    row "$LE::note_violation" gates-llm    "note_violation \"verdict record carries the BUILD run's identity\"" - 'fixture: P10 defense.'
    row "$LE::envfail"        not-a-gate   'envfail '                                            - 'environment refusal — fixture.'
    row "$OL::terminal"       gates-signal 'terminal preflight-rejected 2 '                      - 'fixture: objective probe failure.'
    row "$OL::envfail"        not-a-gate   'envfail env-'                                        - 'environment refusal — fixture.'
    row "$OO::envfail"        not-a-gate   'envfail '                                            - 'usage error — fixture.'
    row "$CC::note_violation" gates-signal 'note_violation "no committed lean spec"'             - 'fixture: objective absence.'
    row "$CC::fail"           gates-signal 'fail "PR body carries no resolvable issue reference"' - 'fixture: objective absence.'
    row "$CC::envfail"        not-a-gate   'envfail '                                            - 'environment refusal — fixture.'
  } > "$d/scripts/gate-buckets.tsv"
  printf '%s' "$d"
}

run_guard() { bash "$GUARD" "$1" 2>&1; }

echo "== the real tree =="
# THIS is what makes the guard grade production from the selftest sweep as well as from its
# ci.yml step: without a case pointing it at the actual repo it would only ever see fixtures.
out="$(bash "$GUARD" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "(g0) THE REPO ITSELF: every enumerated refusal site carries exactly one bucket"
else
  bad "(g0) THE REPO ITSELF: guard is red (rc=$rc)" "$out"
fi

echo "== the fixture baseline =="
D="$(new_fixture green)"
out="$(run_guard "$D")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "(g1) a fully dispositioned fixture is green"
else bad "(g1) a fully dispositioned fixture is green" "$out"; fi
case "$out" in
  *"coverage (sites per row)"*) ok "(g1b) AC-4: the covered-site count is printed per row" ;;
  *) bad "(g1b) AC-4: the covered-site count is printed per row" "$out" ;;
esac
# The summary's two numbers are the contract stated back: 10 enumerated sites, 10 register rows.
# Asserting the VALUES and not just the shape is what makes the counting itself guarded — a
# summary that says "all dispositioned" over a miscounted denominator reads exactly like a pass.
case "$out" in
  *"10 enumerated refusal site(s) across 5 file(s), all bucketed by 10 register row(s)"*)
    ok "(g1c) the verdict line reports the denominator and the register size, both exact" ;;
  *) bad "(g1c) the verdict line reports both counts exactly" "$out" ;;
esac

echo "== the three disagreements, each independently =="

D="$(new_fixture unclassified)"
grep -v 'no committed spec on the branch' "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g2) a site with no row reds" "$out" ;;
  *UNCLASSIFIED*) ok "(g2) a site with no row reds as UNCLASSIFIED" ;;
  *) bad "(g2) a site with no row reds as UNCLASSIFIED" "$out" ;;
esac

D="$(new_fixture drift)"
sed 's/no committed spec on the branch/a message that no longer exists/' "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g3) an anchor matching nothing reds" "$out" ;;
  *"ANCHOR DRIFT"*) ok "(g3) an anchor matching nothing in the file reds as ANCHOR DRIFT" ;;
  *) bad "(g3) an anchor matching nothing in the file reds as ANCHOR DRIFT" "$out" ;;
esac

D="$(new_fixture outlived)"
row "$LG::fail_milestone" gates-signal 'fail_milestone 1 "a retired site kept only as prose"' - 'fixture: the site is gone, only the comment is left.' >> "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g4) a row whose anchor resolves but covers no live site reds" "$out" ;;
  *"outlived what it classified"*) ok "(g4) a row resolving only into a COMMENT reds — the anchor is in the file, the site is not" ;;
  *) bad "(g4) a row resolving only into a COMMENT reds" "$out" ;;
esac

D="$(new_fixture ambiguous)"
row "$LG::fail_milestone" gates-process 'fail_milestone 1 "no committed spec' 'unwired — fixture' 'fixture: a second, disagreeing claim on the same site.' >> "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g5) AC-1: a site claimed by two disagreeing rows reds" "$out" ;;
  *"claimed by rows disposing of it as BOTH"*) ok "(g5) AC-1 'exactly one disposition': two rows disagreeing over one site reds" ;;
  *) bad "(g5) AC-1: a site claimed by two disagreeing rows reds" "$out" ;;
esac

echo "== the register's own schema =="

D="$(new_fixture badbucket)"
sed 's/gates-signal/gates-vibes/' "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g6) a bucket outside the closed enum reds" "$out" ;;
  *"unknown bucket"*) ok "(g6) AC-1: a bucket outside the closed enum reds" ;;
  *) bad "(g6) a bucket outside the closed enum reds" "$out" ;;
esac

D="$(new_fixture yield_on_signal)"
sed "s#\(gates-signal${TAB}fail_milestone 1 \"no committed spec on the branch\"\)${TAB}-#\1${TAB}sometimes#" \
  "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g7) AC-5: a non-gates-process row carrying a yield reds" "$out" ;;
  *"Only gates-process may yield"*) ok "(g7) AC-5 direction 1: a gates-signal row with a non-empty yield cell reds" ;;
  *) bad "(g7) AC-5 direction 1: a gates-signal row with a non-empty yield cell reds" "$out" ;;
esac

D="$(new_fixture yield_names_override)"
sed "s#\(gates-llm${TAB}note_violation[^${TAB}]*\)${TAB}-#\1${TAB}spec-open-region#" \
  "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g8) AC-5: a yield cell naming an OVERRIDE_GATES value forces gates-process" "$out" ;;
  *"A row that yields IS gates-process"*) ok "(g8) AC-5 direction 2: a gates-llm row whose yield names an OVERRIDE_GATES value reds — this is the red-test-lane-made-waivable edit" ;;
  *) bad "(g8) AC-5 direction 2: a yield cell naming an OVERRIDE_GATES value reds" "$out" ;;
esac

D="$(new_fixture process_empty_yield)"
sed "s#gates-signal${TAB}\(fail_milestone 1 \"no committed spec on the branch\"\)#gates-process${TAB}\1#" \
  "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g9) AC-6: a gates-process row with an empty yield cell reds" "$out" ;;
  *"must name an OVERRIDE_GATES"*) ok "(g9) AC-6: a gates-process row carrying '-' reds — it has to say what it yields to, or that it is unwired" ;;
  *) bad "(g9) AC-6: a gates-process row with an empty yield cell reds" "$out" ;;
esac

D="$(new_fixture process_unwired)"
sed "s#gates-signal${TAB}\(fail_milestone 1 \"no committed spec on the branch\"\)${TAB}-#gates-process${TAB}\1${TAB}unwired — no OVERRIDE_GATES value exists for this yet#" \
  "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "(g10) AC-6/OR-2: 'unwired — <reason>' is an accepted yield form"
else bad "(g10) AC-6/OR-2: 'unwired — <reason>' is an accepted yield form" "$out"; fi

D="$(new_fixture notagate_why)"
sed "s#not-a-gate${TAB}\(envfail ${TAB}-${TAB}\)environment refusal — fixture.#not-a-gate${TAB}\1looks fine to me.#" \
  "$D/scripts/gate-buckets.tsv" > "$D/t" && mv "$D/t" "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g11) AC-1: a not-a-gate row must say what it is INSTEAD" "$out" ;;
  *"must open with what the site IS instead"*) ok "(g11) AC-1: a not-a-gate row whose why names none of the three reds" ;;
  *) bad "(g11) AC-1: a not-a-gate row must say what it is INSTEAD" "$out" ;;
esac

D="$(new_fixture malformed)"
printf '%s%sgates-signal%sonly-three-fields\n' "$LG::fail_milestone" "$TAB" "$TAB" >> "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g12) a row with the wrong field count reds" "$out" ;;
  *"malformed row"*) ok "(g12) a row with fewer than five tab-separated fields reds" ;;
  *) bad "(g12) a row with the wrong field count reds" "$out" ;;
esac

D="$(new_fixture emptycell)"
printf '%s%s%sanchor%s-%swhy\n' "$LG::fail_milestone" "$TAB" "$TAB" "$TAB" "$TAB" >> "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g12b) a row with five fields but an EMPTY one reds" "$out" ;;
  *"malformed row"*) ok "(g12b) a five-field row with an empty bucket cell reds as malformed — the field count is not the check, the field CONTENT is" ;;
  *) bad "(g12b) a row with an empty bucket cell reds as malformed" "$out" ;;
esac

D="$(new_fixture badkey)"
row "not-a-path-key" gates-signal 'x' - 'fixture.' >> "$D/scripts/gate-buckets.tsv"
row "$LG::not_a_primitive" gates-signal 'fail_milestone 1 "no committed spec' - 'fixture.' >> "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$out" in
  *"not a 'path::primitive' enforcer key"*)
    case "$out" in
      *"no such corpus pair"*) ok "(g13) a malformed key and a key naming an unscanned primitive both red" ;;
      *) bad "(g13) a key naming an unscanned primitive reds" "$out" ;;
    esac ;;
  *) bad "(g13) a malformed key reds" "$out" ;;
esac

echo "== --list is a read, not a check =="
D="$(new_fixture listonly)"
: > "$D/scripts/gate-buckets.tsv"
out="$(bash "$GUARD" --list "$D" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  n="$(printf '%s\n' "$out" | grep -c .)"
  if [ "$n" -eq 10 ]; then ok "(g14) --list prints the denominator (10 fixture sites) and checks nothing, even against an EMPTY register"
  else bad "(g14) --list prints the denominator and checks nothing" "expected 10 lines, got $n: $out"; fi
else bad "(g14) --list exits 0" "$out"; fi

echo "== structural refusals are exit 2, never a disposition disagreement =="
D="$(new_fixture nocorpusfile)"
rm -f "$D/$CC"
out="$(run_guard "$D")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'corpus file is missing'; then
  ok "(g15) a corpus file that is gone is exit 2 — the denominator cannot be computed, so nothing is a disagreement"
else bad "(g15) a missing corpus file exits 2" "rc=$rc $out"; fi

D="$(new_fixture novocab)"
grep -v '^OVERRIDE_' "$D/$OO" > "$D/t" && mv "$D/t" "$D/$OO"
out="$(run_guard "$D")"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'vacuously'; then
  ok "(g16) an empty OVERRIDE_GATES vocabulary is exit 2 — AC-5's safety arm must not pass by having nothing to compare against"
else bad "(g16) an empty yield vocabulary exits 2" "rc=$rc $out"; fi

D="$(new_fixture noregister)"
rm -f "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
case "$rc:$out" in
  0:*) bad "(g17) a missing register reds" "$out" ;;
  *"the register is missing"*) ok "(g17) a missing register reds — the denominator has nothing to be checked against" ;;
  *) bad "(g17) a missing register reds" "$out" ;;
esac

echo "== what the recipe must NOT enumerate =="
D="$(new_fixture negatives)"
out="$(bash "$GUARD" --list "$D" 2>&1)"
if printf '%s' "$out" | grep -q 'a retired site kept only as prose'; then
  bad "(g18a) a mention inside a COMMENT is not a site" "$out"
else ok "(g18a) a mention inside a comment is not enumerated"; fi
if printf '%s\n' "$out" | awk -F'\t' -v k="$OL::terminal" '$1 == k && $2 == 1 { found = 1 } END { exit found ? 1 : 0 }'; then
  ok "(g18b) terminal()'s own definition line is not enumerated"
else bad "(g18b) a helper's definition line is not a site" "$out"; fi
if printf '%s' "$out" | grep -q 'launch_note terminal'; then
  bad "(g18c) a primitive's name in ARGUMENT position is not a site" "$out"
else ok "(g18c) 'launch_note terminal \"…\"' — the name in argument position — is not enumerated"; fi
if printf '%s\n' "$out" | awk -F'\t' -v k="$OL::envfail" '$1 == k && $2 == 3 { found = 1 } END { exit found ? 1 : 0 }'; then
  ok "(g18d) envfail()'s one-line definition is excluded from the TERMINAL enumeration too — the exclusion is by the file's whole primitive set, not by the primitive being scanned"
else bad "(g18d) a definition line that CALLS another primitive is not a site" "$out"; fi

echo "== the environment the guard runs in =="

out="$(bash "$GUARD" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q 'declares its yield bucket' \
   && printf '%s' "$out" | grep -q '^# Exit code = number of violations' \
   && ! printf '%s' "$out" | grep -q 'set -uo pipefail'; then
  ok "(g19) --help prints through the last header line and stops before the code"
else bad "(g19) --help prints the header and nothing past it" "rc=$rc $out"; fi

D="$(new_fixture no_tmpdir)"
out="$(env -u TMPDIR bash "$GUARD" "$D" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "(g20) with TMPDIR unset the guard still runs — its scratch files fall back to /tmp rather than to a path that does not exist"
else bad "(g20) TMPDIR unset must not break the guard" "rc=$rc $out"; fi

# The EMPTY denominator. A corpus that refuses nowhere is a legitimate state, and the guard must
# read it as "nothing to classify" rather than as one nameless unclassified site — which is what
# it becomes the moment the empty-line guard on the site loop stops holding.
D="$(new_fixture empty_corpus)"
for f in "$LG" "$LE" "$OL" "$OO" "$CC"; do
  grep -v -e 'fail_milestone 1' -e 'note_violation "' -e 'envfail "' -e 'envfail env-' \
       -e 'terminal preflight' -e 'fail "PR body' "$D/$f" > "$D/t" && mv "$D/t" "$D/$f"
done
: > "$D/scripts/gate-buckets.tsv"
out="$(run_guard "$D")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '0 enumerated refusal site(s)'; then
  ok "(g21) a corpus with no refusal sites at all is green against an empty register — an empty denominator is not one unnamed violation"
else bad "(g21) an empty denominator is green" "rc=$rc $out"; fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "check-gate-buckets-selftest: PASS ($PASS assertions)"
  exit 0
fi
echo "check-gate-buckets-selftest: FAIL ($FAILS failure(s), $PASS pass(es))" >&2
exit 1
