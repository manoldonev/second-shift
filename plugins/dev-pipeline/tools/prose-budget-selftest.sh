#!/usr/bin/env bash
#
# Self-test for the instruction-prose narrative check (tools/prose-budget.sh).
#
# WHY this exists (#145): prose-budget.sh shipped without a selftest, in violation of the
# repo rule that every checked-in script pairs with one — and that is precisely how it came
# to match 0 files and report a green for an unknown number of runs. A gate that measures
# nothing looks identical to a gate that passes, so nothing surfaced it. This test's core
# job is to make that state impossible to reintroduce silently.
#
# #641 reshaped the tool: both committed baselines (the markdown word-count ratchet and the
# shell comment-density ratchet) are deleted — the shell half's #641 successor script was
# itself deleted outright by #719, with no replacement. What survives is the narrative #NNN
# judgment and the three-way coverage verdict (n/a / vacuous / measured), so this suite
# covers only those now. See docs/pipeline-manifesto.md's P4/P5 posture for why the ratchet
# halves are gone rather than merely untested.
#
# The three coverage states are the heart of what remains, and T1/T7 are a matched pair:
#   T1  a root exists but matched nothing        -> MUST fail    (the #145 bug)
#   T7  no root exists at all                    -> MUST pass    (the de-vendored consumer)
# Collapsing either into the other is a real regression: T1 alone lets the bug back in, T7
# alone turns every consumer permanently red with no remediation available.
#
# Pure-local: no network, no Claude CLI. Each case builds a throwaway git repo under
# `mktemp -d` (prose-budget.sh requires a git toplevel) and drives the real script against
# it. `PROSE_ROOTS` is the injection seam for root discovery.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$SCRIPT_DIR/prose-budget.sh"
DOCTOR="$SCRIPT_DIR/pipeline-doctor.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a throwaway git repo and echo its path. Callers populate it themselves.
mkrepo() {
  local d="$TMP/repo-$1"
  mkdir -p "$d"
  git -C "$d" init --quiet
  printf '%s\n' "$d"
}

# Run the tool inside a repo, capturing stdout+stderr and exit code into globals.
run_tool() {
  local repo="$1"; shift
  OUT="$(cd "$repo" && bash "$TOOL" "$@" 2>&1)"
  RC=$?
}

echo "[prose-budget-selftest] coverage states"

# --- T1 (AC-2): root exists, zero markdown -> vacuous FAIL --------------------
R="$(mkrepo t1)"
mkdir -p "$R/.claude/skills"          # root present, deliberately empty
run_tool "$R"
if (( RC != 0 )) && grep -q 'FAIL vacuous coverage' <<< "$OUT"; then
  ok "T1 root-with-no-files fails as vacuous (rc=$RC)"
else
  bad "T1 expected non-zero rc + vacuous marker; rc=$RC output: $(head -3 <<< "$OUT")"
fi

# --- T7 (AC-6, negative): no root at all -> n/a, exit 0 ----------------------
# The de-vendored consumer. A failure here is unremediable by definition: there is no
# action the repo owner could take, because having no local instruction layer is correct.
R="$(mkrepo t7)"
run_tool "$R"
if (( RC == 0 )) && grep -q 'n/a — no instruction layer' <<< "$OUT" && ! grep -q 'vacuous' <<< "$OUT"; then
  ok "T7 no-instruction-layer reports n/a and passes (rc=0)"
else
  bad "T7 expected rc=0 + n/a marker + no vacuous marker; rc=$RC output: $(head -3 <<< "$OUT")"
fi

echo "[prose-budget-selftest] layout discovery"

# --- T2 (AC-4): consumer layout still scanned --------------------------------
R="$(mkrepo t2)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta gamma\n' > "$R/.claude/skills/x.md"
run_tool "$R"
if grep -q 'skills/x.md' <<< "$OUT"; then
  ok "T2 .claude/skills is scanned (no regression for existing consumers)"
else
  bad "T2 expected .claude/skills/x.md in the table; output: $(head -5 <<< "$OUT")"
fi

# --- T3 (AC-1): plugin-repo layout scanned -----------------------------------
R="$(mkrepo t3)"
mkdir -p "$R/plugins/foo/agents"
printf 'delta epsilon\n' > "$R/plugins/foo/agents/y.md"
run_tool "$R"
if grep -q 'plugins/foo/agents/y.md' <<< "$OUT"; then
  ok "T3 plugins/*/agents is scanned (the layout #145 missed)"
else
  bad "T3 expected plugins/foo/agents/y.md in the table; output: $(head -5 <<< "$OUT")"
fi

# --- T3b: fixture markdown is excluded ---------------------------------------
# Fixture trees are lint INPUT DATA, not context-loaded prose; ratcheting them would fail
# the budget for editing a test fixture.
R="$(mkrepo t3b)"
mkdir -p "$R/plugins/foo/skills/tool/thing-fixtures"
printf 'real prose\n' > "$R/plugins/foo/skills/real.md"
printf 'fixture data\n' > "$R/plugins/foo/skills/tool/thing-fixtures/f.md"
run_tool "$R"
if grep -q 'skills/real.md' <<< "$OUT" && ! grep -q 'thing-fixtures' <<< "$OUT"; then
  ok "T3b *-fixtures/ markdown is excluded from the ratchet"
else
  bad "T3b expected real.md tracked and fixtures excluded; output: $(head -5 <<< "$OUT")"
fi

echo "[prose-budget-selftest] narrative #NNN"

# --- N1: a file with no #NNN reference is silent -----------------------------
R="$(mkrepo n1)"
mkdir -p "$R/.claude/skills"
printf 'nothing incident-shaped here\n' > "$R/.claude/skills/clean.md"
run_tool "$R"
if (( RC == 0 )) && ! grep -q 'narrative reference' <<< "$OUT" && grep -q '0 warning' <<< "$OUT"; then
  ok "N1 a file with no #NNN reference is silent"
else
  bad "N1 expected no #NNN flag; rc=$RC output: $(head -6 <<< "$OUT")"
fi

# --- N2: a #NNN reference is flagged as a warning, never a failure -----------
R="$(mkrepo n2)"
mkdir -p "$R/.claude/skills"
printf 'fixed in #1234 last week\n' > "$R/.claude/skills/archaeology.md"
run_tool "$R"
if (( RC == 0 )) && grep -q 'archaeology.md' <<< "$OUT" && grep -q '1 warning' <<< "$OUT"; then
  ok "N2 a narrative #NNN reference is a warning, not a FAIL (rc=0)"
else
  bad "N2 expected rc=0 + 1 warning; rc=$RC output: $(head -8 <<< "$OUT")"
fi

# --- N3: #NNN inside a fenced code block does not count ----------------------
R="$(mkrepo n3)"
mkdir -p "$R/.claude/skills"
# shellcheck disable=SC2016  # deliberately literal — no expansion wanted inside the fixture
printf 'prose\n```\nsee #1234\n```\n' > "$R/.claude/skills/fenced.md"
run_tool "$R"
if (( RC == 0 )) && ! grep -q '1 warning' <<< "$OUT"; then
  ok "N3 a #NNN reference inside a fenced code block does not count"
else
  bad "N3 expected no warning for a fenced #NNN; rc=$RC output: $(head -8 <<< "$OUT")"
fi

echo "[prose-budget-selftest] no committed baseline (#641)"

# --- B1: --update-baseline is a no-op and writes nothing ---------------------
R="$(mkrepo b1)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
run_tool "$R" --update-baseline
if (( RC == 0 )) && [[ ! -f "$R/.claude/prose-budget.baseline.tsv" ]] \
   && [[ ! -f "$R/.claude/prose-budget-shell.baseline.tsv" ]] \
   && grep -q 'no-op' <<< "$OUT"; then
  ok "B1 --update-baseline is a no-op: rc=0, no baseline file written, says so"
else
  bad "B1 expected a no-op with no file written; rc=$RC output: $(head -3 <<< "$OUT")"
fi

# --- B2: growing a file across two runs never fails — there is nothing to compare against ---
R="$(mkrepo b2)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
run_tool "$R"
FIRST_RC=$RC
printf 'one two three four five six seven eight nine ten eleven twelve\n' > "$R/.claude/skills/a.md"
run_tool "$R"
if (( FIRST_RC == 0 )) && (( RC == 0 )) && ! grep -qi 'grew' <<< "$OUT"; then
  ok "B2 a file growing across runs never fails — no ratchet is left to trip"
else
  bad "B2 expected both runs rc=0 with no growth failure; first_rc=$FIRST_RC rc=$RC output: $(head -6 <<< "$OUT")"
fi

# --- B3: no shell files are measured at all — nothing does, since #719 ---
R="$(mkrepo b3)"
mkdir -p "$R/.claude/skills"
printf '# lots of comments\n# more comments\n# even more\ntrue\n' > "$R/.claude/skills/dense.sh"
run_tool "$R"
if ! grep -qi 'shell\|ratio\|comment' <<< "$OUT"; then
  ok "B3 no shell path exists any more — a .sh file under a scan root is invisible to this tool"
else
  bad "B3 expected no shell-related output at all; output: $(head -10 <<< "$OUT")"
fi

echo "[prose-budget-selftest] report and summary"

# --- R1: --report prints the table and TOTAL but never exits non-zero on content -----
R="$(mkrepo r1)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
run_tool "$R" --report
if (( RC == 0 )) && grep -q 'TOTAL ' <<< "$OUT"; then
  ok "R1 --report prints a TOTAL line and exits 0"
else
  bad "R1 expected rc=0 + TOTAL line; rc=$RC output: $(head -6 <<< "$OUT")"
fi

# --- R2: an unknown argument is a usage error ---------------------------------
R="$(mkrepo r2)"
run_tool "$R" --bogus
if (( RC == 2 )); then
  ok "R2 an unknown argument is exit 2"
else
  bad "R2 expected rc=2 for an unknown argument; rc=$RC"
fi

# --- R3 (AC-11 successor): the summary line stays last and carries coverage --
R="$(mkrepo r3)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta\n' > "$R/.claude/skills/a.md"
run_tool "$R"
if [[ "$(tail -1 <<< "$OUT")" == *"coverage: md measured"* ]]; then
  ok "R3 the last line is the combined summary naming coverage"
else
  bad "R3 last line did not carry coverage: $(tail -1 <<< "$OUT")"
fi

echo "[prose-budget-selftest] doctor routing"

# --- T11: doctor's branch patterns route real tool output correctly ----------
# Take doctor's own patterns and apply them to the tool's REAL output in each state,
# asserting exactly one branch claims each. (pipeline-doctor.sh cannot be executed wholesale
# here — its other checks need gh auth and network — so the branch conditions are tested in
# isolation.)
VACUOUS_PAT='FAIL vacuous coverage'
NA_PAT='n/a — no instruction layer'
DOCTOR_NA_PAT='coverage: md n/a'

for pat in "$VACUOUS_PAT" "$DOCTOR_NA_PAT"; do
  grep -qF -- "$pat" "$DOCTOR" || bad "T11 precondition: doctor no longer contains '$pat'"
done

# n/a output must hit the n/a branch.
R="$(mkrepo t11na)"
run_tool "$R"
if grep -qF -- "$NA_PAT" <<< "$OUT" \
   && grep -qF -- "$DOCTOR_NA_PAT" <<< "$OUT" \
   && ! grep -qF -- "$VACUOUS_PAT" <<< "$OUT" \
   && (( RC == 0 )); then
  ok "T11 n/a output routes to doctor's n/a branch only"
else
  bad "T11 n/a output did not route cleanly (rc=$RC)"
fi

# vacuous output must hit the vacuous branch, not the n/a one.
R="$(mkrepo t11vac)"
mkdir -p "$R/.claude/agents"
run_tool "$R"
if grep -qF -- "$VACUOUS_PAT" <<< "$OUT" \
   && ! grep -qF -- "$NA_PAT" <<< "$OUT" \
   && (( RC != 0 )); then
  ok "T11 vacuous output routes to doctor's vacuous branch"
else
  bad "T11 vacuous output did not route to the vacuous branch (rc=$RC)"
fi

echo
echo "[prose-budget-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
