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

echo "[prose-budget-selftest] shell path (#552)"

# The shell path measures comment DENSITY, not size, and its coverage verdict is computed
# independently of markdown's. S1/S4 are the matched pair that pins the asymmetry:
#   S1  a root with markdown and zero .sh   -> n/a     (NOT vacuous — AC-4)
#   S4  a root whose every .sh is excluded  -> vacuous (the scan looked at nothing but fixtures)
# Collapsing S1 into vacuous is the failure AC-4 names: it would red every markdown-only
# consumer on a path they cannot remediate, since having no shell is not a defect.

# --- S1 (AC-4): markdown present, zero shell files -> n/a, never vacuous -----
R="$(mkrepo s1)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta gamma\n' > "$R/.claude/skills/x.md"
run_tool "$R"
if (( RC == 0 )) && grep -q 'shell: n/a — no shell files' <<< "$OUT" \
   && ! grep -q 'vacuous shell coverage' <<< "$OUT"; then
  ok "S1 a root with markdown and no .sh reports shell n/a, not vacuous"
else
  bad "S1 expected rc=0 + shell n/a + no shell-vacuous marker; rc=$RC output: $(head -5 <<< "$OUT")"
fi

# --- S2 (AC-1/AC-6): a measured shell file reports the four fields -----------
# 6 total, 5 non-blank, 3 comment lines (the shebang counts — AC-1 says ANY ^[[:space:]]*#).
# 3/5 = 60.0%. The fields are asserted by value, so a denominator that silently became
# total-lines (3/6 = 50.0%) fails here rather than passing as a rounding difference.
R="$(mkrepo s2)"
mkdir -p "$R/.claude/skills"
printf '#!/usr/bin/env bash\n# one\n\n# two\ntrue\nfalse\n' > "$R/.claude/skills/m.sh"
run_tool "$R" --report
if grep -qE 'skills/m\.sh +6 +5 +3 +60\.0%' <<< "$OUT"; then
  ok "S2 a measured shell file reports total/non-blank/comments/ratio (6 5 3 60.0%)"
else
  bad "S2 expected '6 5 3 60.0%' for m.sh; output: $(grep 'm.sh' <<< "$OUT")"
fi

# --- S2b (AC-6): the ratio ROUNDS half up, it does not truncate --------------
# S2's 3/5 is exactly 60.0%, where rounding and truncation agree — so on its own it cannot see
# this. 5 comment lines over 9 non-blank is 55.55…%: truncating gives 55.5%, rounding gives
# 55.6%. AC-6 states 541 for lean-gate.sh's 2494/4612, which is the rounded value (truncation
# gives 540), and lean-gate.sh is the ONLY one of the three motivating files where the two forms
# differ — so a truncating implementation reproduces two thirds of the ticket's table and still
# violates the AC. This case is the one that notices.
R="$(mkrepo s2b)"
mkdir -p "$R/.claude/skills"
printf '# 1\n# 2\n# 3\n# 4\n# 5\ntrue\ntrue\ntrue\ntrue\n' > "$R/.claude/skills/r.sh"
run_tool "$R" --report
if grep -qE 'skills/r\.sh +9 +9 +5 +55\.6%' <<< "$OUT"; then
  ok "S2b 5/9 reports 55.6% — the ratio rounds half up rather than truncating"
else
  bad "S2b expected 55.6% (rounded) for 5/9, not 55.5% (truncated); output: $(grep 'r.sh' <<< "$OUT")"
fi

# --- S3 (AC-6): ratio growth past tolerance fails, additively in points ------
# Baseline 1/2 = 50.0%, grown to 5/6 = 83.3% — a +33.3pp jump, past the +5pp default. The
# marker is 'FAIL ratio grew', deliberately not a superstring of markdown's 'FAIL grew'.
R="$(mkrepo s3)"
mkdir -p "$R/.claude/skills"
printf '# c\ntrue\n' > "$R/.claude/skills/g.sh"
printf 'seed prose\n' > "$R/.claude/skills/seed.md"
(cd "$R" && bash "$TOOL" --update-baseline >/dev/null 2>&1)
printf '# c\n# c\n# c\n# c\n# c\ntrue\n' > "$R/.claude/skills/g.sh"
run_tool "$R"
if (( RC != 0 )) && grep -q 'FAIL ratio grew' <<< "$OUT"; then
  ok "S3 comment-ratio growth past the +5pp tolerance fails"
else
  bad "S3 expected non-zero rc + 'FAIL ratio grew'; rc=$RC output: $(head -8 <<< "$OUT")"
fi

# --- S3b (AC-6): the SAME growth passes under a tolerance wide enough --------
# Proves the tolerance is actually consulted rather than the FAIL being unconditional, and that
# it is read in POINTS: 34 points admits the +33.3pp jump above.
OUT="$(cd "$R" && PROSE_SHELL_TOLERANCE_PP=34 bash "$TOOL" 2>&1)"; RC=$?
if (( RC == 0 )) && ! grep -q 'FAIL ratio grew' <<< "$OUT"; then
  ok "S3b PROSE_SHELL_TOLERANCE_PP=34 admits the same +33.3pp growth (points, not percent)"
else
  bad "S3b expected rc=0 with no ratio failure at 34pp; rc=$RC output: $(head -5 <<< "$OUT")"
fi

# --- S4 (AC-4/AC-9): every .sh excluded -> genuinely vacuous ------------------
# The scan DID match shell files; the fixture filter ate all of them. That is the state where a
# green would be meaningless, and it is the only shell state that earns a vacuous FAIL.
R="$(mkrepo s4)"
mkdir -p "$R/plugins/foo/skills/tool/thing-fixtures"
printf 'prose\n' > "$R/plugins/foo/skills/real.md"
printf '# fixture\ntrue\n' > "$R/plugins/foo/skills/tool/thing-fixtures/f.sh"
run_tool "$R"
if (( RC != 0 )) && grep -q 'FAIL vacuous shell coverage' <<< "$OUT" \
   && ! grep -q 'shell: n/a' <<< "$OUT"; then
  ok "S4 a root whose every .sh is fixture-excluded fails as shell-vacuous"
else
  bad "S4 expected non-zero rc + shell-vacuous marker + no shell n/a; rc=$RC output: $(head -6 <<< "$OUT")"
fi

# --- S5 (AC-2): tools/ is scanned, and it is the divergence from prose_roots --
# tools/run-selftests.sh is one of the three files #552 exists to measure and lives under none
# of .claude/skills, .claude/agents, plugins/*/skills, plugins/*/agents. Reusing prose_roots()
# unchanged would silently omit it while every other assertion here still passed.
R="$(mkrepo s5)"
mkdir -p "$R/tools"
printf '# c\ntrue\n' > "$R/tools/t.sh"
run_tool "$R" --report
if grep -q 'tools/t.sh' <<< "$OUT"; then
  ok "S5 tools/ is scanned for shell even with no skills/ or agents/ root (AC-2)"
else
  bad "S5 expected tools/t.sh in the shell table; output: $(head -8 <<< "$OUT")"
fi

# --- S5b (AC-4): a tools/-only repo still REACHES a shell coverage verdict ----
# The markdown path reports n/a here and USED TO `exit 0` on that branch, which meant the shell
# path's coverage verdict, staleness check and summary were never reached in exactly the repo
# shape S5 describes. Independence is what AC-4 buys, and it is the SUMMARY that proves it:
# asserting the table row instead would pass under the old early exit, because the shell table
# is printed above the coverage block and survives a short-circuit below it.
run_tool "$R"
if [[ "$(tail -1 <<< "$OUT")" == *"coverage: md n/a, sh measured"* ]]; then
  ok "S5b markdown n/a no longer short-circuits the shell coverage verdict"
else
  bad "S5b expected a summary reading 'md n/a, sh measured'; got: $(tail -1 <<< "$OUT")"
fi

# --- S6 (AC-5/AC-8): shell rows land in their OWN file, markdown untouched ----
R="$(mkrepo s6)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta\n' > "$R/.claude/skills/a.md"
printf '# c\ntrue\n' > "$R/.claude/skills/a.sh"
run_tool "$R" --update-baseline
# Stripping comments first is load-bearing: the markdown baseline's own header carries the
# literal `prose-budget.sh --update-baseline`, so a naive scan for '.sh' matches the header and
# reports a leak that is not there. Only DATA rows can leak a path.
#
# The strip is captured into a variable rather than piped into the match, and that is the
# difference between a real assertion and a fail-open one: this suite runs under `pipefail`, so
# a matcher that exits early on success can SIGPIPE its producer and hand the pipeline 141 —
# which `!` then reads as "no leak" in exactly the case where a leak exists.
MD_ROWS="$(grep -v '^#' "$R/.claude/prose-budget.baseline.tsv")"
if [[ -f "$R/.claude/prose-budget-shell.baseline.tsv" ]] \
   && grep -q 'skills/a.sh' "$R/.claude/prose-budget-shell.baseline.tsv" \
   && ! grep -q '\.sh' <<< "$MD_ROWS"; then
  ok "S6 shell rows go to prose-budget-shell.baseline.tsv, never into the markdown TSV"
else
  bad "S6 shell rows were not separated from the markdown baseline (rc=$RC)"
fi

# --- S7: no shell baseline is a NEW/warn state, never a failure --------------
# Mirrors T8b on the markdown side. There is no shipped shell stub, so absence of the file is
# the whole fallback — if it hard-failed, every consumer would be red until they ran an update.
R="$(mkrepo s7)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta\n' > "$R/.claude/skills/a.md"
printf '# c\ntrue\n' > "$R/.claude/skills/a.sh"
run_tool "$R"
if (( RC == 0 )) && grep -q 'no shell baseline' <<< "$OUT" && ! grep -q 'FAIL' <<< "$OUT"; then
  ok "S7 a missing shell baseline warns and never fails"
else
  bad "S7 expected rc=0 + 'no shell baseline' note + no FAIL; rc=$RC output: $(head -5 <<< "$OUT")"
fi

# --- S8 (AC-11): the summary line stays last and names BOTH tolerances -------
# pipeline-doctor.sh reads the OK message with `tail -1`. A per-path summary would leave the
# markdown counts unreadable there, and a line still claiming only "+5%" would misattribute the
# tolerance for half of what the counts cover.
if [[ "$(tail -1 <<< "$OUT")" == *"tolerance: md +5% words, sh +5pp ratio"* ]]; then
  ok "S8 the last line is one combined summary naming both tolerances"
else
  bad "S8 last line did not carry both tolerances: $(tail -1 <<< "$OUT")"
fi

# --- S9 (AC-11): shell staleness is reported and routed apart from markdown --
R="$(mkrepo s9)"
mkdir -p "$R/.claude/skills"
printf 'alpha beta\n' > "$R/.claude/skills/a.md"
printf '# c\ntrue\n' > "$R/.claude/skills/a.sh"
(cd "$R" && bash "$TOOL" --update-baseline >/dev/null 2>&1)
{
  printf '# path\ttotal\tnonblank\tcomments\tratio_tenths\n'
  printf 'tools/vanished.sh\t10\t8\t4\t500\n'
} > "$R/.claude/prose-budget-shell.baseline.tsv"
run_tool "$R"
if grep -q 'FAIL stale shell baseline' <<< "$OUT" \
   && ! grep -q 'FAIL stale baseline' <<< "$OUT" \
   && ! grep -q 'vacuous' <<< "$OUT"; then
  ok "S9 an all-unresolvable shell baseline fails on its own marker, not markdown's"
else
  bad "S9 expected shell-stale marker alone; rc=$RC output: $(head -8 <<< "$OUT")"
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
SH_VACUOUS_PAT='FAIL vacuous shell coverage'
SH_STALE_PAT='FAIL stale shell baseline'
SH_GROW_PAT='FAIL ratio grew'
# The literal doctor's "nothing was measured" short-circuit branches on. It is deliberately
# NOT NA_PAT: the markdown marker alone is emitted by a repo whose shell files WERE measured,
# and branching on it reported that repo as having nothing to measure (#552 review r1).
DOCTOR_NA_PAT='coverage: md n/a, sh n/a'

# Guard: these are the literals doctor branches on. If they drift there, T10 fails; if
# they drift in the tool, the assertions below fail. Both directions are covered.
# NA_PAT is asserted against the TOOL's output only (it is a marker doctor no longer reads),
# so it is not in this loop — T11's n/a case below is what holds it.
for pat in "$VACUOUS_PAT" "$DOCTOR_NA_PAT" "$STALE_PAT" "$SH_VACUOUS_PAT" "$SH_STALE_PAT" "$SH_GROW_PAT"; do
  grep -qF -- "$pat" "$DOCTOR" || bad "T11 precondition: doctor no longer contains '$pat'"
done

# T11s: the shell markers must not be claimable by the markdown branches, which sit EARLIER in
# doctor's elif chain and would therefore win. This is a property of the literals themselves —
# 'FAIL vacuous shell coverage' does not contain 'FAIL vacuous coverage', and 'FAIL ratio grew'
# does not contain 'FAIL grew' — so assert it directly rather than inferring it from a fixture.
# Rewording either side into an overlap is the regression: doctor would then hand a shell
# failure the markdown remediation, and the operator would go fix the wrong scan roots.
if ! grep -qF -- "$VACUOUS_PAT" <<< "$SH_VACUOUS_PAT" \
   && ! grep -qF -- "$STALE_PAT" <<< "$SH_STALE_PAT" \
   && ! grep -qF -- 'FAIL grew' <<< "$SH_GROW_PAT"; then
  ok "T11s no shell marker is a superstring of the markdown marker it parallels"
else
  bad "T11s a shell marker overlaps its markdown counterpart — doctor's earlier branch would claim it"
fi

# n/a output must hit the n/a branch and NO warn branch. Nothing is measured on EITHER path
# in a bare repo, so doctor's short-circuit predicate must claim it.
R="$(mkrepo t11na)"
run_tool "$R"
if grep -qF -- "$NA_PAT" <<< "$OUT" \
   && grep -qF -- "$DOCTOR_NA_PAT" <<< "$OUT" \
   && ! grep -qF -- "$VACUOUS_PAT" <<< "$OUT" \
   && ! grep -qF -- "$STALE_PAT" <<< "$OUT" \
   && (( RC == 0 )); then
  ok "T11 n/a output routes to doctor's n/a branch only"
else
  bad "T11 n/a output did not route cleanly (rc=$RC)"
fi

# --- T11b (AC-4/AC-10): md n/a + sh measured must NOT read as "nothing to measure" ---------
# The repo shape S5/S5b describe — tools/*.sh, no skills/ or agents/ root — emits the markdown
# n/a marker AND a measured shell verdict. Doctor's short-circuit used to branch on the markdown
# marker alone, so it announced "nothing to measure" over a run that measured two files and
# raised two warnings, discarding the tail -1 summary that D-4 kept combined precisely so this
# arm could report it. Asserting the summary (S5b) is not enough on its own: this is about which
# of DOCTOR's two arms claims that summary, and only the predicate can say.
#
# Non-vacuity: the first clause is the regression. Restore the old `n/a — no instruction layer`
# predicate and this case fails on it while every other T11 case, and S5b, stay green.
R="$(mkrepo t11nasm)"
mkdir -p "$R/tools"
printf '# c\ntrue\n' > "$R/tools/t.sh"
printf '# d\n# e\ntrue\n' > "$R/tools/u.sh"
run_tool "$R"
if ! grep -qF -- "$DOCTOR_NA_PAT" <<< "$OUT" \
   && grep -qF -- 'coverage: md n/a, sh measured' <<< "$OUT" \
   && grep -qF -- "$NA_PAT" <<< "$OUT" \
   && (( RC == 0 )); then
  ok "T11b md n/a + sh measured falls through to doctor's summary arm, not its n/a arm (AC-4)"
else
  bad "T11b md-n/a-with-measured-shell routed to the 'nothing to measure' arm (rc=$RC); summary: $(tail -1 <<< "$OUT")"
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
