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

# --- T10: load-bearing tokens survive in the tool and its doctor consumer ----
# The doctor branches on these exact strings; renaming a marker without updating the
# consumer silently restores the "reads like a pass" ambiguity this fix removed.
for tok in 'prose_roots' 'FAIL vacuous coverage' 'n/a — no instruction layer' 'PROSE_ALLOW_EMPTY_BASELINE'; do
  if grep -qF -- "$tok" "$TOOL"; then
    ok "T10 prose-budget.sh still carries '$tok'"
  else
    bad "T10 prose-budget.sh lost the load-bearing token '$tok'"
  fi
done
for tok in 'FAIL vacuous coverage' 'n/a — no instruction layer'; do
  if grep -qF -- "$tok" "$DOCTOR"; then
    ok "T10 pipeline-doctor.sh still branches on '$tok'"
  else
    bad "T10 pipeline-doctor.sh no longer branches on '$tok' — the vacuous case would report as growth"
  fi
done

echo
echo "[prose-budget-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
