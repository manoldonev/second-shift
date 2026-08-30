#!/usr/bin/env bash
# check-lane-class-doc-selftest.sh — verifies check-lane-class-doc.sh actually reds on drift,
# and reds fail-CLOSED on a dispatch shape it cannot model (#674).
#
# The mutation idiom (per scripts/check-lockstep-pairs-selftest.sh): green on the real tree, RED
# after a mutation. A guard never observed failing is indistinguishable from one that cannot fail
# — and for this subject that is the whole point, since the sentence it guards spent a year
# looking true.
#
# Cases (b) onward run against SYNTHETIC fixture trees. The checker reads exactly two paths under
# its root, so a fixture is those two files and nothing else — which lets each case state exactly
# one property. A copy of the repo could not: mutating one arm there also moves the others.
#
# EVERY RED CASE ASSERTS THE MESSAGE, not just the exit code. A guard that reds for the wrong
# reason is a guard that will red on the wrong day, and the exit code alone cannot tell them apart.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HERE/check-lane-class-doc.sh"

[[ -x "$CHECKER" ]] || { echo "[lane-class-selftest] FATAL: $CHECKER not executable"; exit 99; }

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t lane-class-selftest.XXXXXX) || { echo "[lane-class-selftest] FATAL: mktemp failed"; exit 99; }
trap 'rm -rf "$TMP"' EXIT INT TERM

GATE_REL="plugins/dev-pipeline/skills/build-lean/lean-gate.sh"
DOC_REL="docs/config-schema.md"

run() { bash "$CHECKER" "$1" >"$TMP/out" 2>&1; echo $?; }
out() { cat "$TMP/out"; }

# The doc-region markers, assembled at runtime. Written contiguously they would be a second
# LANE-CLASS region in the tree — harmless to this checker, which only reads docs/config-schema.md,
# but a fixture that spells its own subject's marker is one grep away from being mistaken for one.
MB="LANE-CLASS-BEGIN"
ME="LANE-CLASS-END"

# tree <name> — a fresh fixture root carrying a DEFAULT-AGREEING gate and doc, echoed.
# Each case then mutates exactly one of the two.
tree() {
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d/$(dirname "$GATE_REL")" "$d/$(dirname "$DOC_REL")"
  cat > "$d/$GATE_REL" <<'EOF'
#!/usr/bin/env bash
# a comment mentioning lane_failure_class, which is not a call site
lane_failure_class() { # lane_failure_class <lane-rc>
  case "$1" in
    "$LANE_INFRA_RC") echo "$INFRA_CLASS" ;;
    *)                echo 1 ;;
  esac
}
milestone_3() {
  for key in lint typecheck test; do
    run_lane "$key"; rc=$?
    [ "$rc" -eq 0 ] && continue
    case "$key" in
      typecheck) fail_milestone 3 "$key failed (rc=$rc)" "$(lane_failure_class "$rc")"; return $? ;;
      *) lane_advisory "$key failed (rc=$rc)" ;;
    esac
  done
}
EOF
  {
    echo "# fixture doc"
    echo "- **Exit code \`3\` is RESERVED on a verify lane.**"
    echo
    echo "  <!-- $MB -->"
    echo "  - \`typecheck\` — **reserved**: the one fixed key milestone 3 still refuses on."
    echo "  - \`lint\`, \`test\` — **not reserved**: advisory since #642."
    echo "  - \`extraLanes[]\` — **not reserved**: advisory since #642, per entry."
    echo "  - setup \`lanes[]\` — **not reserved**: SETUP-only, never a verify lane."
    echo "  <!-- $ME -->"
  } > "$d/$DOC_REL"
  printf '%s' "$d"
}

echo "[lane-class-selftest]"

# ---- (a) the LIVE tree is green -------------------------------------------------------------
# Non-vacuity for every red below, and the case that would catch the repo's own doc drifting.
# Invoked with NO ARGUMENT, which is how CI invokes it: a broken default-root resolution does not
# error, it reads two files that are not there — and that path is checked by case (l).
rc=$(bash "$CHECKER" >"$TMP/out" 2>&1; echo $?)
if [[ "$rc" -eq 0 ]]; then ok "(a) the live tree: doc and dispatch agree"
else bad "(a) the live tree should be green, got rc=$rc"; out; fi

# ---- (b) the fixture baseline is green ------------------------------------------------------
# Without this, every mutation case below could be passing for a reason the mutation did not
# introduce.
d=$(tree b); rc=$(run "$d")
if [[ "$rc" -eq 0 ]]; then ok "(b) the unmutated fixture is green"
else bad "(b) the unmutated fixture should be green, got rc=$rc"; out; fi

# ---- (c) code gains a reserved lane, doc unchanged (AC-2, code→doc direction) ----------------
d=$(tree c)
perl -0pi -e 's/      typecheck\) fail_milestone/      lint|typecheck) fail_milestone/' "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'does not mark them \*\*reserved\*\*.*lint' <<<"$(out)"; then
  ok "(c) a lane promoted back to blocking reds, naming it"
else bad "(c) expected a red naming lint as newly reserved, got rc=$rc"; out; fi

# ---- (d) doc claims a lane the code does not route (AC-2, doc→code direction) ----------------
d=$(tree d)
perl -0pi -e 's/  - `lint`, `test` — \*\*not reserved\*\*/  - `lint` — **reserved**: made up.\n  - `test` — **not reserved**/' "$d/$DOC_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'the dispatch does not route them.*lint' <<<"$(out)"; then
  ok "(d) a doc row claiming an unrouted lane reds, naming it"
else bad "(d) expected a red naming lint as over-claimed, got rc=$rc"; out; fi

# ---- (e) call site under a different `case` subject (AC-3) -----------------------------------
# The shape a future extraLanes re-promotion would take. The derivation must refuse, not silently
# return a smaller set — which is what would let the doc read as agreeing.
d=$(tree e)
perl -0pi -e 's/    case "\$key" in/    case "\$el_name" in/' "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -qF 'subject that is not' <<<"$(out)"; then
  ok "(e) a call site under another case subject reds as underivable"
else bad "(e) expected a red naming the unmodelled subject, got rc=$rc"; out; fi

# ---- (f) call site that is not an arm label at all (AC-3) ------------------------------------
# The classifier called from ordinary code rather than from a lane arm: there is no label to read
# the lane off, so the set is underivable and the guard must say so rather than return {} and let
# the doc read as over-claiming.
d=$(tree f)
cat > "$d/$GATE_REL" <<'EOF'
#!/usr/bin/env bash
lane_failure_class() { # lane_failure_class <lane-rc>
  case "$1" in
    "$LANE_INFRA_RC") echo "$INFRA_CLASS" ;;
    *)                echo 1 ;;
  esac
}
milestone_3() {
  for key in lint typecheck test; do
    run_lane "$key"; rc=$?
    [ "$rc" -eq 0 ] && continue
    cls="$(lane_failure_class "$rc")"
    fail_milestone 3 "$key failed (rc=$rc)" "$cls"; return $?
  done
}
EOF
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -qF 'arm label on its own line' <<<"$(out)"; then
  ok "(f) a call site outside an arm label reds as underivable"
else bad "(f) expected a red naming the unmodelled shape, got rc=$rc"; out; fi

# ---- (g) a glob arm routes to the classifier (AC-3) ------------------------------------------
d=$(tree g)
perl -0pi -e 's/      typecheck\) fail_milestone/      *) fail_milestone/' "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'is a glob' <<<"$(out)"; then
  ok "(g) a glob arm reds — its members cannot be named"
else bad "(g) expected a red naming the glob arm, got rc=$rc"; out; fi

# ---- (h) zero call sites (AC-3) --------------------------------------------------------------
d=$(tree h)
perl -0pi -e 's/"\$\(lane_failure_class "\$rc"\)"/"1"/' "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'has no call sites' <<<"$(out)"; then
  ok "(h) a classifier with no callers reds"
else bad "(h) expected a red naming the dead classifier, got rc=$rc"; out; fi

# ---- (i) a fixed key with no doc row (AC-4) --------------------------------------------------
d=$(tree i)
perl -0pi -e 's/  for key in lint typecheck test; do/  for key in lint typecheck test format; do/' "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'has no row for them.*format' <<<"$(out)"; then
  ok "(i) a new fixed key with no doc row reds, naming it"
else bad "(i) expected a red naming the undocumented fixed key, got rc=$rc"; out; fi

# ---- (j) the doc region is gone (AC-2) -------------------------------------------------------
d=$(tree j)
perl -0pi -e "s/^.*$ME.*\$//m" "$d/$DOC_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'no delimited region to read' <<<"$(out)"; then
  ok "(j) a doc whose region markers are unbalanced reds"
else bad "(j) expected a red naming the missing region, got rc=$rc"; out; fi

# ---- (k) a row with no verdict, and a duplicated lane (AC-2) ---------------------------------
d=$(tree k)
perl -0pi -e 's/  - `extraLanes\[\]` — \*\*not reserved\*\*: advisory since #642, per entry\./  - `extraLanes[]` — advisory, probably.\n  - `test` — **not reserved**: said twice./' "$d/$DOC_REL"
rc=$(run "$d")
o="$(out)"
if [[ "$rc" -ge 2 ]] && grep -q 'carries neither \*\*reserved\*\* nor' <<<"$o" && grep -q 'named by more than one row' <<<"$o"; then
  ok "(k) an unverdicted row and a doubly-claimed lane each red"
else bad "(k) expected both the verdict red and the duplicate red, got rc=$rc"; out; fi

# ---- (l) a missing subject is a red, never a skip --------------------------------------------
# The failure mode the default-root resolution has: read two paths that are not there, find
# nothing, and report a clean contract over a tree never looked at.
d=$(tree l); rm -f "$d/$DOC_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'the contract doc is missing' <<<"$(out)"; then
  ok "(l) a missing contract doc reds rather than passing vacuously"
else bad "(l) expected a red for the missing doc, got rc=$rc"; out; fi

d=$(tree l2); rm -f "$d/$GATE_REL"
rc=$(run "$d")
if [[ "$rc" -ge 1 ]] && grep -q 'the dispatch is missing' <<<"$(out)"; then
  ok "(l) a missing dispatch reds rather than passing vacuously"
else bad "(l) expected a red for the missing gate, got rc=$rc"; out; fi

echo "[lane-class-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
