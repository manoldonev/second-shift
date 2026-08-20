#!/usr/bin/env bash
# capability-parity-check-selftest.sh — behavioral suite for tools/capability-parity-check.sh.
#
# The guard's whole value is that it REDS on a deletion or a missing decision, so every red
# path is driven here rather than asserted in prose. Cases run against a throwaway sandbox
# TREE, not the real register: the guard resolves the tree root from the REGISTER's location, so
# a copy under $SANDBOX/tools/ makes $SANDBOX the root and the fixture files under
# $SANDBOX/plugins/ the entire universe successor tokens resolve against. That is what the
# no-`git grep` decision (#575 D-7) buys — the sandbox is a plain mktemp tree with no repo, and
# the dispatch probe still returns a real verdict in it. The real tree is checked once (case a)
# and never mutated.
#
# Two cases are about SCOPE rather than a violation: (l) pins that the enum lint is
# unconditional, and (m) pins that a row citing a deleted PATH is still valid — rows are
# permanent record, and the path cell is a historical citation. The successor cell is the
# opposite and cases (t)/(u) pin that it is checked against today's tree.
#
# Case (cc) is the #348 exhibit made permanent: an `already-covered` row naming an engine that
# EXISTS but that nothing dispatches. That is precisely the shape rows 56/61/63 wore, and the
# shape the pre-#575 guard was green on. If a future edit makes the probe fail open, (cc) is
# what notices; (dd)/(ee)/(ff) pin the three ways the probe could go green for the wrong reason.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HERE/capability-parity-check.sh"
REGISTER="$HERE/capability-parity.tsv"

[[ -f "$CHECKER" ]] || { echo "[capability-parity-selftest] FATAL: $CHECKER missing"; exit 99; }
[[ -f "$REGISTER" ]] || { echo "[capability-parity-selftest] FATAL: $REGISTER missing"; exit 99; }

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t capability-parity-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "[capability-parity-selftest]"

# ---- (a) green on the real tree -------------------------------------------------------
rc=$(bash "$CHECKER" >/dev/null 2>&1; echo $?)
[[ "$rc" -eq 0 ]] \
  && ok "(a) real register is clean — shape, enum and every successor claim resolve" \
  || bad "(a) real register is RED — rc=$rc; run 'bash tools/capability-parity-check.sh'"

# ---- sandbox ---------------------------------------------------------------------------
SANDBOX="$TMP/tree"
SB_REGISTER="$SANDBOX/tools/capability-parity.tsv"
mkdir -p "$SANDBOX/tools"
cp "$CHECKER" "$SANDBOX/tools/"

# `P` is the retired staged path prefix the fixture rows CITE. Nothing at these paths exists and
# nothing creates them — that is the point of case (m): the path cell is a citation, not a claim.

P='plugins/dev-pipeline/retired'

# ---- fixture tree the SUCCESSOR cells resolve against -------------------------------------
#
# Five files, each earning its place:
#   ENFORCER  a plain successor that exists (the shape 21 of the 22 real claiming rows wear).
#   ENGINE    a .mjs successor WITH a dispatcher — the green side of the probe.
#   ORPHAN    a .mjs successor no file dispatches at all — the #348 shape, case (cc).
#   HARNESSED a .mjs successor dispatched ONLY from a selftest harness — case (dd).
#   DISPATCHER the one production file that dispatches ENGINE by scriptPath. Rewritable, so
#             (ee)/(ff) can break the dispatch two different ways without touching anything else.
ENFORCER='plugins/dev-pipeline/skills/build-lean/lean-gate.sh'
ENGINE='plugins/dev-pipeline/workflows/engine.mjs'
ORPHAN='plugins/dev-pipeline/workflows/orphan.mjs'
HARNESSED='plugins/dev-pipeline/workflows/harnessed.mjs'
DISPATCHER="$SANDBOX/plugins/dev-pipeline/skills/build-lean/SKILL.md"
HARNESS="$SANDBOX/plugins/dev-pipeline/workflows/harness-selftest.mjs"

mkdir -p "$SANDBOX/plugins/dev-pipeline/skills/build-lean" "$SANDBOX/plugins/dev-pipeline/workflows"
: > "$SANDBOX/$ENFORCER"
: > "$SANDBOX/$ENGINE"
: > "$SANDBOX/$ORPHAN"
: > "$SANDBOX/$HARNESSED"

# write_dispatcher <line> — the production .md that reaches ENGINE. Its DEFAULT carries the
# needle and the basename on ONE line, which is the whole contract; (ee) and (ff) each drop one
# half and must red.
write_dispatcher() { printf '# fixture skill\n%s\n' "$1" > "$DISPATCHER"; }
write_dispatcher 'Workflow({ scriptPath: "engine.mjs", args: {} })'

# A dispatch that lives ONLY in a selftest harness is a fixture asserting itself, not
# reachability. This file names HARNESSED exactly the way the real dispatcher names ENGINE, so
# the ONLY thing separating the two is the exclusion; case (dd) is what proves that exclusion is
# doing work rather than decorating the find.
printf 'Workflow({ scriptPath: "harnessed.mjs", args: {} })\n' > "$HARNESS"

# write_register <extra-rows-printf-format...> — always emits the three covering rows first.
#
# Successor cells across the three: a plain enforcer (alpha), a dispatch-probed engine (beta),
# and the none-token (gamma). Every baseline run therefore exercises all three arms of the
# clause, so a mutant that kills any one of them cannot hide behind a green baseline.
#
# The beta row's successor SPACING is load-bearing, do not tidy it: `", "` after the comma is
# how a human writes a list, and only the guard's trim turns ` plugins/...` into a resolvable
# token. Delete the trim and this row's second token resolves as a path with a leading space,
# which no tree has — so the trim is pinned by the baseline itself rather than by a case nobody
# would think to add.
write_register() {
  {
    printf '# fixture register\n'
    printf 'alpha capability\t%s/1-alpha.md\tported\t%s\tnote a\n' "$P" "$ENFORCER"
    printf 'beta capability\tworkflows/beta.mjs, %s/2-beta.md\talready-covered\t%s, %s\tnote b\n' "$P" "$ENGINE" "$ENFORCER"
    printf 'gamma capability\t%s/3-gamma.md\tchoreography\t-\tnote c\n' "$P"
    # shellcheck disable=SC2059 # the caller's first arg IS the format — literal \t is how
    # these fixtures spell a field separator, so it must survive as a format, not as data.
    [[ $# -gt 0 ]] && printf "$@"
  } > "$SB_REGISTER"
}

run_guard() { bash "$SANDBOX/tools/capability-parity-check.sh" "$@" >/dev/null 2>&1; echo $?; }
# stdout only — the success line is an asserted artifact (D-11), not incidental chatter.
run_guard_out() { bash "$SANDBOX/tools/capability-parity-check.sh" 2>/dev/null; }
# stderr only — a violation MESSAGE is part of the contract when a case exists to prove the
# guard rejected for the stated reason rather than tripping over some unrelated clause.
run_guard_err() { { bash "$SANDBOX/tools/capability-parity-check.sh" >/dev/null; } 2>&1; }

# ---- (b) sandbox baseline --------------------------------------------------------------
write_register
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(b) sandbox baseline is green (3 rows: a plain successor, a dispatch-probed engine, a none-token)" \
  || bad "(b) sandbox baseline is RED before any mutation — rc=$rc"

# ---- (c) AC-6: a disposition outside the enum reds --------------------------------------
#
# The delta row's MISSING trailing newline is load-bearing, do not tidy it. The guard reads its
# register with `while IFS= read -r line || [[ -n "$line" ]]`, and that `||` exists for exactly
# one reason: a final line with no terminator makes `read` return 1, so without the second
# operand the last row would never be judged. Every other fixture here is newline-terminated,
# which left the clause dark — flipping `||` to `&&` kept all 14 cases green, and the nightly
# sweep of record surfaced it as `capability-parity-check.sh::logic::2` (#585). Unterminated,
# this case is the one that dies when the idiom breaks: the mutant drops the delta row, the
# off-enum disposition goes unjudged, and the guard exits 0 where 1 is asserted.
write_register 'delta capability\t%s/1-alpha.md\tdeferred\t-\tnote d' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(c) disposition outside the enum ('deferred') reds" \
  || bad "(c) off-enum disposition did NOT red — rc=$rc"

# ---- (d) an empty disposition cell reds -------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\t\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(d) empty disposition cell reds" \
  || bad "(d) empty disposition did NOT red — rc=$rc"

# ---- (f/g/h) AC-6: malformed rows red ---------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tdropped\t-\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(f) a 4-field row — the pre-#575 schema, note where successor now sits — reds" \
  || bad "(f) 4-field row did NOT red — rc=$rc; a register still on the 4-column shape must not pass"

write_register 'delta capability\t%s/1-alpha.md\tdropped\t-\tnote d\tspare\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(g) a 6-field row reds" \
  || bad "(g) 6-field row did NOT red — rc=$rc"

# The tab-count parse, not `read -a`: a trailing tab leaves an EMPTY note cell that a
# field-splitting read would never see, so this is the case that kills a `read -a` rewrite.
write_register 'delta capability\t%s/1-alpha.md\tdropped\t-\t\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h) a row with an empty trailing note cell reds" \
  || bad "(h) empty trailing note cell did NOT red — rc=$rc"

# An empty capability or path cell is the same violation class.
write_register '\t%s/1-alpha.md\tdropped\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h2) an empty capability cell reds" \
  || bad "(h2) empty capability cell did NOT red — rc=$rc"

write_register 'delta capability\t\tdropped\t-\tnote d\n'
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h3) an empty path cell reds" \
  || bad "(h3) empty path cell did NOT red — rc=$rc"

# ---- (i) a duplicate row reds ------------------------------------------------------------
write_register 'alpha capability\t%s/1-alpha.md\tdropped\t-\tsecond opinion\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(i) a duplicate capability name reds" \
  || bad "(i) duplicate capability did NOT red — rc=$rc"

# ---- (j) an empty register reds ----------------------------------------------------------
printf '# nothing but a header\n' > "$SB_REGISTER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(j) an emptied register reds" \
  || bad "(j) empty register did NOT red — rc=$rc"

# ---- (l) the enum lint is unconditional (D-16) --------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tdeferred\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(l) an off-enum disposition reds" \
  || bad "(l) off-enum disposition passed — rc=$rc"

# ---- (m) rows are permanent record: a cited PATH need not exist ----------------------------
#
# The path cell only. Cases (s)/(t)/(t2) are its mirror image on the successor cell, which is a
# live claim about today's tree — the register holds both a historical citation and a current
# claim, and the guard has to treat them oppositely.
write_register 'delta capability\t%s/99-retired.md, plugins/dev-pipeline/retired/gone.sh\tdropped\t-\tits paths died with #348\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(m) a row citing paths that no longer exist stays valid (rows outlive implementations)" \
  || bad "(m) guard RED on a row whose cited paths are gone — rc=$rc; paths must not be existence-checked"

# ---- (n) a missing register is an environment error, not a silent pass ---------------------
rc=$(run_guard "$TMP/nope.tsv"); [[ "$rc" -eq 2 ]] \
  && ok "(n) a missing register exits 2 (environment error)" \
  || bad "(n) missing register did not exit 2 — rc=$rc"

# =========================================================================================
# SUCCESSOR CLAUSE (#575). Everything below drives the half that tests whether a row's
# disposition is TRUE, not merely well-formed.
# =========================================================================================

# ---- (o) AC-3: an empty successor cell reds -----------------------------------------------
#
# Not "reds because the row is short" — the field count is right, the cell is blank. Blank must
# never read as "no successor": a backfill that skipped a row would otherwise pass silently, and
# recording "none" is a decision spelled `-`.
write_register 'delta capability\t%s/1-alpha.md\tdropped\t\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(o) an empty successor cell reds (blank is not a silent 'none')" \
  || bad "(o) empty successor cell did NOT red — rc=$rc"

# ---- (p) AC-4: 'already-covered' naming no successor reds ----------------------------------
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(p) an 'already-covered' row with successor '-' reds" \
  || bad "(p) 'already-covered' with no successor did NOT red — rc=$rc"

# ---- (q) AC-4: 'ported' naming no successor reds -------------------------------------------
#
# `ported` has zero rows in the real register today and the enum outlives its data, so this arm
# has no live exhibit to protect it. Without this case the whole `ported` half could be deleted
# and every other case would stay green.
write_register 'delta capability\t%s/1-alpha.md\tported\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(q) a 'ported' row with successor '-' reds" \
  || bad "(q) 'ported' with no successor did NOT red — rc=$rc"

# ---- (r) AC-4 does not over-reach: 'dropped' with '-' is green -----------------------------
#
# The require arm is per-disposition on purpose. A guard that demanded a successor from every row
# would force the 15 genuinely-successorless rows to invent one, which is the failure this ticket
# describes running in reverse.
write_register 'delta capability\t%s/1-alpha.md\tdropped\t-\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(r) a 'dropped' row with successor '-' stays green (require is by disposition)" \
  || bad "(r) 'dropped' with '-' RED — rc=$rc; only coverage-asserting dispositions require a successor"

# ---- (s) AC-5: an 'already-covered' successor that does not exist reds ---------------------
write_register 'delta capability\t%s/1-alpha.md\talready-covered\tplugins/dev-pipeline/tools/gone.sh\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(s) a named successor that does not exist reds" \
  || bad "(s) missing successor did NOT red — rc=$rc"

# ---- (t) AC-5: check by PRESENCE — a 'dropped' row's successor is checked too --------------
#
# This is the case the ticket's own proposal would not have written. Rows 56/61/63 stopped being
# false by moving OUT of the checked class, not by becoming true; six `dropped` rows still assert
# a survivor in prose. Delete the by-presence arm and the guard reverts to grading exactly the
# rows that already got fixed.
write_register 'delta capability\t%s/1-alpha.md\tdropped\tplugins/dev-pipeline/tools/gone.sh\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(t) a 'dropped' row naming a successor that does not exist reds (check by presence)" \
  || bad "(t) 'dropped' successor went unchecked — rc=$rc; a claim is a claim whatever the disposition"

# ---- (t2) and so is a 'choreography' row's -------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tchoreography\tplugins/dev-pipeline/tools/gone.sh\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(t2) a 'choreography' row naming a successor that does not exist reds" \
  || bad "(t2) 'choreography' successor went unchecked — rc=$rc"

# ---- (u) AC-5: ALL tokens must resolve, not just the first ---------------------------------
#
# The first token resolves, so a guard that stops at the head of the list is green here. That is
# the assert-more-than-you-test shape one comma over.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s,plugins/dev-pipeline/tools/gone.sh\tnote d\n' "$P" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(u) a multi-token cell whose SECOND token is missing reds" \
  || bad "(u) only the first successor token was checked — rc=$rc"

# ...and one message per failing token, not one per row (D-16).
write_register 'delta capability\t%s/1-alpha.md\talready-covered\tplugins/a/gone.sh,plugins/b/gone.sh\tnote d\n' "$P"
n=$(run_guard_err | grep -c "does not exist")
[[ "$n" -eq 2 ]] \
  && ok "(u2) two dead tokens produce two messages, not one" \
  || bad "(u2) expected 2 'does not exist' messages, got $n; a fixed first failure would hide the second"

# ---- (v) AC-5: spaces around the comma are trimmed -----------------------------------------
#
# The baseline already depends on this (the beta row), so this case exists to say WHY out loud
# rather than to add coverage: a list is written with `", "` and the trim is what makes the
# second token a path instead of a path with a leading space.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t %s ,  %s \tnote d\n' "$P" "$ENFORCER" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(v) surrounding spaces in a successor list are trimmed" \
  || bad "(v) a spaced successor list RED — rc=$rc; the trim is gone"

# ---- (w) AC-5: an empty token reds ---------------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s,\tnote d\n' "$P" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(w) a trailing comma (empty successor token) reds" \
  || bad "(w) trailing comma did NOT red — rc=$rc"

write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s,,%s\tnote d\n' "$P" "$ENFORCER" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(w2) a doubled comma (empty successor token) reds" \
  || bad "(w2) doubled comma did NOT red — rc=$rc"

# ---- (x) AC-5: '-' is the whole cell or it is nothing --------------------------------------
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s,-\tnote d\n' "$P" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(x) mixing the none-token with a real successor reds" \
  || bad "(x) '-' mixed into a list did NOT red — rc=$rc"

# ---- (y) AC-5: tokens are repo-relative ----------------------------------------------------
#
# /etc/hosts EXISTS on every lane this runs on, which is the point: the rejection has to come
# from the repo-relative rule, not from the path happening to be absent. An absolute token is
# green-on-my-laptop, not a claim about this tree.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t/etc/hosts\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(y) an absolute successor token reds even though the file exists" \
  || bad "(y) absolute successor accepted — rc=$rc"

# Same argument for '..': this token RESOLVES (it climbs out of the sandbox and back in), so a
# guard without the rule is green here.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t../tree/%s\tnote d\n' "$P" "$ENFORCER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(y2) a '..'-climbing successor token reds even though it resolves" \
  || bad "(y2) '..' successor accepted — rc=$rc"

# ---- (z) AC-6: a dispatched .mjs successor is green -----------------------------------------
#
# The green side of the probe, asserted on its own rather than only inside the baseline: without
# it, a probe that reds EVERYTHING would still pass every red-side case below.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s\tnote d\n' "$P" "$ENGINE"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(z) a .mjs successor with a scriptPath dispatcher is green" \
  || bad "(z) a dispatched engine RED — rc=$rc; the probe is failing closed on a reachable engine"

# ---- (cc) AC-6: THE #348 EXHIBIT — an existing but undispatched .mjs reds -------------------
#
# This is the ticket's day-one exhibit made permanent. Rows 56/61/63 asserted coverage for
# design-sync.mjs and figma.mjs; both files existed on disk the whole time and only their
# scriptPath dispatcher had died. #574 fixed those rows by flipping them to `dropped`, so the
# live red is spent — this fixture is what keeps the shape testable forever. An existence-only
# check passes it, which is exactly why D-6 put a probe behind .mjs tokens.
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s\tnote d\n' "$P" "$ORPHAN"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(cc) a .mjs successor that exists but nothing dispatches reds (the #348 shape)" \
  || bad "(cc) an undispatched engine passed — rc=$rc; existence alone would not have caught #348"

# ---- (dd) AC-6: a dispatch found only in a selftest harness does not count ------------------
write_register 'delta capability\t%s/1-alpha.md\talready-covered\t%s\tnote d\n' "$P" "$HARNESSED"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(dd) a .mjs dispatched ONLY from a selftest harness reds (a fixture is not reachability)" \
  || bad "(dd) a harness-only dispatch counted as reachability — rc=$rc"

# ---- (ee)/(ff) AC-6: the probe wants BOTH needles on ONE line -------------------------------
#
# Two ways a looser probe goes green for the wrong reason. (ee): the engine is named in prose,
# nothing dispatches it — the #348 shape wearing a mention. (ff): something IS dispatched, just
# not this engine. Both drive the BASELINE register, whose beta row names ENGINE, so the only
# thing that changed is the dispatcher's one line.
write_dispatcher 'see engine.mjs for the render contract'
write_register
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(ee) an engine merely MENTIONED, with no scriptPath on the line, reds" \
  || bad "(ee) a prose mention counted as a dispatch — rc=$rc"

write_dispatcher 'Workflow({ scriptPath: "other.mjs", args: {} })'
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(ff) a scriptPath dispatch of a DIFFERENT engine does not satisfy this row" \
  || bad "(ff) any scriptPath anywhere counted as this engine's dispatch — rc=$rc"

write_dispatcher 'Workflow({ scriptPath: "engine.mjs", args: {} })'
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(ff2) restoring the dispatcher restores green (the probe reads the tree, not a cache)" \
  || bad "(ff2) baseline did not recover after the dispatcher was restored — rc=$rc"

# ---- (gg) AC-7: the success line reports the successor work ---------------------------------
#
# An unchanged success line is byte-identical before and after a clause stops running, which is
# how the coverage half went unnoticed for a whole release. The counts are the tell.
write_register
out=$(run_guard_out)
case "$out" in
  *"3 capability row(s)"*"2 successor claim(s) resolved, 1 dispatch-probed, 1 row(s) claim none"*)
    ok "(gg) the success line reports rows, resolved claims, dispatch probes and none-claiming rows" ;;
  *)
    bad "(gg) success line does not report the successor counts — got: $out" ;;
esac

echo "[capability-parity-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
