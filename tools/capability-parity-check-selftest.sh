#!/usr/bin/env bash
# capability-parity-check-selftest.sh — behavioral suite for tools/capability-parity-check.sh.
#
# The guard's whole value is that it REDS on a deletion or a missing decision, so every red
# path is driven here rather than asserted in prose. Cases run against a throwaway sandbox
# TREE, not the real register: the guard resolves its repo root from its own location, so a
# copy under $SANDBOX/tools/ makes $SANDBOX the root and the fixture stage docs the file
# universe. The real tree is checked once (case a) and never mutated.
#
# Two cases are about the guard's LIFETIME rather than a violation: (k) and (l) pin that the
# coverage clause going vacuous after #348 does not take the enum lint with it, and (m) pins
# that a row citing a deleted path is still valid — rows are permanent record.
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
  && ok "(a) real register is clean against the real stage docs" \
  || bad "(a) real register is RED — rc=$rc; run 'bash tools/capability-parity-check.sh'"

# ---- sandbox ---------------------------------------------------------------------------
SANDBOX="$TMP/tree"
SB_STAGES="$SANDBOX/plugins/dev-pipeline/skills/run/stages"
SB_REGISTER="$SANDBOX/tools/capability-parity.tsv"
mkdir -p "$SANDBOX/tools" "$SB_STAGES"
cp "$CHECKER" "$SANDBOX/tools/"

# Three fixture stage docs; content is irrelevant (the coverage clause is file-level by
# design — D-14), only their paths are.
for n in 1-alpha 2-beta 3-gamma; do : > "$SB_STAGES/$n.md"; done

P='plugins/dev-pipeline/skills/run/stages'

# write_register <extra-rows-printf-format...> — always emits the three covering rows first.
#
# The beta row's path ORDER is load-bearing, do not tidy it: the register is written in a
# `", path"` style, so a stage doc cited in any non-first position arrives with a leading space
# and only the guard's trim makes it key as a citation. Putting the `.mjs` first is what puts
# `2-beta.md` behind that space, so every case below depends on the trim — with `2-beta.md`
# first, deleting the trim leaves all 17 cases green and the guard would red every legitimately
# covered doc that happens to be cited second.
write_register() {
  {
    printf '# fixture register\n'
    printf 'alpha capability\t%s/1-alpha.md\tported\tnote a\n' "$P"
    printf 'beta capability\tworkflows/beta.mjs, %s/2-beta.md\talready-covered\tnote b\n' "$P"
    printf 'gamma capability\t%s/3-gamma.md\tchoreography\tnote c\n' "$P"
    # shellcheck disable=SC2059 # the caller's first arg IS the format — literal \t is how
    # these fixtures spell a field separator, so it must survive as a format, not as data.
    [[ $# -gt 0 ]] && printf "$@"
  } > "$SB_REGISTER"
}

run_guard() { bash "$SANDBOX/tools/capability-parity-check.sh" "$@" >/dev/null 2>&1; echo $?; }

# ---- (b) sandbox baseline --------------------------------------------------------------
write_register
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(b) sandbox baseline is green (3 rows, 3 covered stage docs)" \
  || bad "(b) sandbox baseline is RED before any mutation — rc=$rc"

# ---- (c) AC-6: a disposition outside the enum reds --------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tdeferred\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(c) disposition outside the enum ('deferred') reds" \
  || bad "(c) off-enum disposition did NOT red — rc=$rc"

# ---- (d) an empty disposition cell reds -------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\t\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(d) empty disposition cell reds" \
  || bad "(d) empty disposition did NOT red — rc=$rc"

# ---- (e) AC-6: an uncovered stages/*.md file reds ---------------------------------------
write_register
: > "$SB_STAGES/4-delta.md"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(e) a stage doc named by no row reds (the #348 deletion gate)" \
  || bad "(e) uncovered stage doc did NOT red — rc=$rc"
rm -f "$SB_STAGES/4-delta.md"

# Covering it clears the red — the guard reacts to the register, not to the file count.
write_register 'delta capability\t%s/4-delta.md\tdropped\tnote d\n' "$P"
: > "$SB_STAGES/4-delta.md"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(e2) adding a covering row for that file clears the red" \
  || bad "(e2) covered stage doc still RED — rc=$rc"
rm -f "$SB_STAGES/4-delta.md"

# ---- (f/g/h) AC-6: malformed rows red ---------------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tdropped\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(f) a 3-field row reds" \
  || bad "(f) 3-field row did NOT red — rc=$rc"

write_register 'delta capability\t%s/1-alpha.md\tdropped\tnote d\tspare\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(g) a 5-field row reds" \
  || bad "(g) 5-field row did NOT red — rc=$rc"

# The tab-count parse, not `read -a`: a trailing tab leaves an EMPTY note cell that a
# field-splitting read would never see, so this is the case that kills a `read -a` rewrite.
write_register 'delta capability\t%s/1-alpha.md\tdropped\t\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h) a row with an empty trailing note cell reds" \
  || bad "(h) empty trailing note cell did NOT red — rc=$rc"

# An empty capability or path cell is the same violation class.
write_register '\t%s/1-alpha.md\tdropped\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h2) an empty capability cell reds" \
  || bad "(h2) empty capability cell did NOT red — rc=$rc"

write_register 'delta capability\t\tdropped\tnote d\n'
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(h3) an empty path cell reds" \
  || bad "(h3) empty path cell did NOT red — rc=$rc"

# ---- (i) a duplicate row reds ------------------------------------------------------------
write_register 'alpha capability\t%s/1-alpha.md\tdropped\tsecond opinion\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(i) a duplicate capability name reds" \
  || bad "(i) duplicate capability did NOT red — rc=$rc"

# ---- (j) an empty register reds ----------------------------------------------------------
# Asserted in the POST-#348 state (stage docs gone), where the coverage clause cannot red and
# the zero-rows check is therefore the only thing that can. Against live stage docs an empty
# register reds anyway — for uncovered files — which would let this case pass with the
# zero-rows check deleted.
mv "$SB_STAGES" "$TMP/stages-parked"
printf '# nothing but a header\n' > "$SB_REGISTER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(j) a register emptied after #348 still reds (nothing else is left to notice)" \
  || bad "(j) empty register did NOT red — rc=$rc"
mv "$TMP/stages-parked" "$SB_STAGES"

# ---- (k/l) LIFETIME: the coverage clause goes vacuous, the enum lint does not -------------
write_register
rm -rf "$SB_STAGES"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(k) with the stage docs gone the coverage clause is vacuous and the guard stays green" \
  || bad "(k) guard RED after the stage docs were deleted — rc=$rc (post-#348 state must pass)"

write_register 'delta capability\t%s/1-alpha.md\tdeferred\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(l) the enum lint still reds once the coverage clause is vacuous (unconditional, D-16)" \
  || bad "(l) off-enum disposition passed in the post-#348 state — rc=$rc"
# (k) removed the whole directory, landing on the "does not exist" branch. #348 can equally
# leave an empty stages/ behind, which is the sibling branch: still vacuous, still green, and
# the note is the only thing distinguishing it from a coverage clause that ran and found
# nothing wrong.
mkdir -p "$SB_STAGES"
write_register
out=$(bash "$SANDBOX/tools/capability-parity-check.sh" 2>&1); rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$out" == *"holds no *.md files"* ]]; } \
  && ok "(k2) an emptied-but-present stages dir is vacuous and green, and says so" \
  || bad "(k2) empty stages dir — rc=$rc, output: $out"

for n in 1-alpha 2-beta 3-gamma; do : > "$SB_STAGES/$n.md"; done

# ---- (m) rows are permanent record: a cited path need not exist ---------------------------
write_register 'delta capability\t%s/99-retired.md, plugins/dev-pipeline/skills/run/tools/gone.sh\tdropped\tits paths died with #348\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 0 ]] \
  && ok "(m) a row citing paths that no longer exist stays valid (rows outlive implementations)" \
  || bad "(m) guard RED on a row whose cited paths are gone — rc=$rc; paths must not be existence-checked"

# ---- (n) a missing register is an environment error, not a silent pass ---------------------
rc=$(run_guard "$TMP/nope.tsv"); [[ "$rc" -eq 2 ]] \
  && ok "(n) a missing register exits 2 (environment error)" \
  || bad "(n) missing register did not exit 2 — rc=$rc"

echo "[capability-parity-selftest] $PASS passed, $FAIL failed"
exit "$FAIL"
