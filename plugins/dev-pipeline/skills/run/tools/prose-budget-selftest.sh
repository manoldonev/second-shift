#!/usr/bin/env bash
#
# Self-test for the instruction-prose budget ratchet (tools/prose-budget.sh).
#
# WHY this exists (#145): prose-budget.sh shipped without a selftest, in violation of the
# repo rule that every checked-in script pairs with one — and that is precisely how it came
# to match 0 files and report a green for an unknown number of runs. A gate that measures
# nothing looks identical to a gate that passes, so nothing surfaced it. This test's core
# job is to make that state impossible to reintroduce silently.
#
# The three coverage states are the heart of it, and T1/T7 are a matched pair:
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
STUB="$SCRIPT_DIR/prose-budget.baseline.tsv"
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

echo "[prose-budget-selftest] baseline handling"

# --- T6 (AC-5): --update-baseline writes repo-local, not the plugin stub -----
R="$(mkrepo t6)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
STUB_BEFORE="$(cksum < "$STUB")"
run_tool "$R" --update-baseline
if [[ -f "$R/.claude/prose-budget.baseline.tsv" ]] && (( RC == 0 )); then
  ok "T6 --update-baseline writes <repo>/.claude/prose-budget.baseline.tsv"
else
  bad "T6 expected repo-local baseline written; rc=$RC output: $(head -3 <<< "$OUT")"
fi
if [[ "$(cksum < "$STUB")" == "$STUB_BEFORE" ]]; then
  ok "T6b the shipped plugin stub is left untouched"
else
  bad "T6b --update-baseline modified the shipped stub — consumers would inherit these rows"
fi

# --- T9: --update-baseline refuses to snapshot nothing -----------------------
# Writing an empty baseline is how the false green gets cemented.
R="$(mkrepo t9)"
mkdir -p "$R/.claude/skills"          # root exists, no files
run_tool "$R" --update-baseline
if (( RC != 0 )) && [[ ! -f "$R/.claude/prose-budget.baseline.tsv" ]]; then
  ok "T9 --update-baseline refuses an empty snapshot and writes nothing"
else
  bad "T9 expected refusal + no file written; rc=$RC"
fi

# --- T9b: PROSE_ALLOW_EMPTY_BASELINE is the sanctioned override for T9 -------
# Converted from a spelling-pin to a behavioral case (#214). The old check grepped the
# tool's source for the variable NAME, which proves nothing about the hatch working —
# and it was the ONLY coverage of the escape hatch anywhere in the tree, so deleting it
# outright would have let the hatch be removed silently while prose-budget.sh:118 still
# instructs operators to set it, stranding a legitimately instruction-layer-free consumer
# at the refusal above.
R="$(mkrepo t9b)"
mkdir -p "$R/.claude/skills"          # same empty-root state T9 refuses
OUT="$(cd "$R" && PROSE_ALLOW_EMPTY_BASELINE=1 bash "$TOOL" --update-baseline 2>&1)"; RC=$?
if (( RC == 0 )) && [[ -f "$R/.claude/prose-budget.baseline.tsv" ]]; then
  ok "T9b PROSE_ALLOW_EMPTY_BASELINE=1 permits the empty snapshot (rc 0, baseline written)"
else
  bad "T9b escape hatch did not permit the empty snapshot; rc=$RC file=$([[ -f "$R/.claude/prose-budget.baseline.tsv" ]] && echo yes || echo no)"
fi

# --- T4 (AC-3): stale rows in a repo-local baseline are reported -------------
R="$(mkrepo t4)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
(cd "$R" && bash "$TOOL" --update-baseline >/dev/null 2>&1)
printf 'gone/away.md\t10\t50\t0\n' >> "$R/.claude/prose-budget.baseline.tsv"
run_tool "$R"
if grep -q 'stale baseline row' <<< "$OUT" && grep -q 'gone/away.md' <<< "$OUT"; then
  ok "T4 unresolvable baseline row is reported as stale"
else
  bad "T4 expected a stale-row report; output: $(head -5 <<< "$OUT")"
fi

# --- T4b: all-rows-unresolvable is the #145 signature -> FAIL ----------------
R="$(mkrepo t4b)"
mkdir -p "$R/.claude/skills" "$R/.claude"
printf 'one two three\n' > "$R/.claude/skills/a.md"
{
  printf '# path\twords\tchars\tnarrative_nnn\n'
  printf '.claude/agents/vanished.md\t10\t50\t0\n'
} > "$R/.claude/prose-budget.baseline.tsv"
run_tool "$R"
if (( RC != 0 )) && grep -q 'FAIL stale baseline' <<< "$OUT"; then
  ok "T4b baseline whose every row is unresolvable fails (the #145 signature)"
else
  bad "T4b expected non-zero rc + stale-baseline FAIL; rc=$RC output: $(head -5 <<< "$OUT")"
fi

# --- T8: falling back to the stub never fails --------------------------------
# The stub describes no repo, so unresolved rows there carry no signal. It must also
# genuinely carry zero rows — the state that made it behave as a live baseline.
if [[ "$(grep -vc '^#' "$STUB")" == "0" ]]; then
  ok "T8 the shipped stub is header-only (zero rows)"
else
  bad "T8 the shipped stub carries $(grep -vc '^#' "$STUB") row(s) — consumers would inherit them"
fi
R="$(mkrepo t8)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
run_tool "$R"
if (( RC == 0 )) && ! grep -q 'FAIL' <<< "$OUT"; then
  ok "T8b stub fallback yields warnings, never a failure"
else
  bad "T8b expected rc=0 and no FAIL on stub fallback; rc=$RC output: $(head -5 <<< "$OUT")"
fi

echo "[prose-budget-selftest] ratchet"

# --- T5: growth past tolerance still fails (pre-existing behavior) -----------
R="$(mkrepo t5)"
mkdir -p "$R/.claude/skills"
printf 'one two three four five\n' > "$R/.claude/skills/a.md"
(cd "$R" && bash "$TOOL" --update-baseline >/dev/null 2>&1)
printf 'one two three four five six seven eight nine ten eleven twelve\n' > "$R/.claude/skills/a.md"
run_tool "$R"
if (( RC != 0 )) && grep -q 'FAIL grew' <<< "$OUT"; then
  ok "T5 growth past tolerance still fails"
else
  bad "T5 expected non-zero rc + 'FAIL grew'; rc=$RC output: $(head -5 <<< "$OUT")"
fi

echo "[prose-budget-selftest] drift"

# T10 (6 source greps over the tool and pipeline-doctor.sh) was deleted (#214): the four
# tool-side greps were strictly weaker duplicates of T1/T7/T4b/T11, which assert the same
# markers in the tool's REAL output with an exit code; the 'prose_roots' grep pinned only a
# lowercase function name and did not even match the uppercase PROSE_ROOTS env seam; and the
# two doctor-side greps are a strict subset of T11's precondition loop below, which is kept
# precisely because pipeline-doctor.sh needs gh auth and network and so cannot be executed
# here. The one check with unique value — the PROSE_ALLOW_EMPTY_BASELINE hatch — was
# CONVERTED to the behavioral case T9b above rather than dropped.

echo "[prose-budget-selftest] doctor routing"

# --- T11: doctor's branch patterns route real tool output correctly ----------
# T10 proves the marker strings exist in both files; it does NOT prove they still MATCH.
# A reworded marker, a changed dash, or an overlapping pattern would keep T10 green while
# the vacuous case silently reported as "grew past baseline". So: take doctor's own
# patterns and apply them to the tool's REAL output in each state, asserting exactly one
# branch claims each. (pipeline-doctor.sh cannot be executed wholesale here — its other
# checks need gh auth and network — so the branch conditions are tested in isolation.)
VACUOUS_PAT='FAIL vacuous coverage'
NA_PAT='n/a — no instruction layer'
STALE_PAT='FAIL stale baseline'

# Guard: these are the literals doctor branches on. If they drift there, T10 fails; if
# they drift in the tool, the assertions below fail. Both directions are covered.
for pat in "$VACUOUS_PAT" "$NA_PAT" "$STALE_PAT"; do
  grep -qF -- "$pat" "$DOCTOR" || bad "T11 precondition: doctor no longer contains '$pat'"
done

# n/a output must hit the n/a branch and NO warn branch.
R="$(mkrepo t11na)"
run_tool "$R"
if grep -qF -- "$NA_PAT" <<< "$OUT" \
   && ! grep -qF -- "$VACUOUS_PAT" <<< "$OUT" \
   && ! grep -qF -- "$STALE_PAT" <<< "$OUT" \
   && (( RC == 0 )); then
  ok "T11 n/a output routes to doctor's n/a branch only"
else
  bad "T11 n/a output did not route cleanly (rc=$RC)"
fi

# vacuous output must hit the vacuous branch, not the generic growth fallback.
R="$(mkrepo t11vac)"
mkdir -p "$R/.claude/agents"
run_tool "$R"
if grep -qF -- "$VACUOUS_PAT" <<< "$OUT" \
   && ! grep -qF -- "$NA_PAT" <<< "$OUT" \
   && (( RC != 0 )); then
  ok "T11 vacuous output routes to doctor's vacuous branch (not the growth fallback)"
else
  bad "T11 vacuous output did not route to the vacuous branch (rc=$RC)"
fi

# stale output must hit the stale branch, not the vacuous one.
R="$(mkrepo t11stale)"
mkdir -p "$R/.claude/skills"
printf 'one two three\n' > "$R/.claude/skills/a.md"
{
  printf '# path\twords\tchars\tnarrative_nnn\n'
  printf '.claude/agents/vanished.md\t10\t50\t0\n'
} > "$R/.claude/prose-budget.baseline.tsv"
run_tool "$R"
if grep -qF -- "$STALE_PAT" <<< "$OUT" && ! grep -qF -- "$VACUOUS_PAT" <<< "$OUT"; then
  ok "T11 stale output routes to doctor's stale branch (not the vacuous branch)"
else
  bad "T11 stale output did not route to the stale branch"
fi

echo
echo "[prose-budget-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
