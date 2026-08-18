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
SB_REGISTER="$SANDBOX/tools/capability-parity.tsv"
mkdir -p "$SANDBOX/tools"
cp "$CHECKER" "$SANDBOX/tools/"

# Three fixture stage docs; content is irrelevant (the coverage clause is file-level by
# design — D-14), only their paths are.

P='plugins/dev-pipeline/retired'

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
#
# The delta row's MISSING trailing newline is load-bearing, do not tidy it. The guard reads its
# register with `while IFS= read -r line || [[ -n "$line" ]]`, and that `||` exists for exactly
# one reason: a final line with no terminator makes `read` return 1, so without the second
# operand the last row would never be judged. Every other fixture here is newline-terminated,
# which left the clause dark — flipping `||` to `&&` kept all 14 cases green, and the nightly
# sweep of record surfaced it as `capability-parity-check.sh::logic::2` (#585). Unterminated,
# this case is the one that dies when the idiom breaks: the mutant drops the delta row, the
# off-enum disposition goes unjudged, and the guard exits 0 where 1 is asserted.
write_register 'delta capability\t%s/1-alpha.md\tdeferred\tnote d' "$P"
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
printf '# nothing but a header\n' > "$SB_REGISTER"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(j) an emptied register reds" \
  || bad "(j) empty register did NOT red — rc=$rc"

# ---- (l) the enum lint is unconditional (D-16) --------------------------------------------
write_register 'delta capability\t%s/1-alpha.md\tdeferred\tnote d\n' "$P"
rc=$(run_guard)
[[ "$rc" -eq 1 ]] \
  && ok "(l) an off-enum disposition reds" \
  || bad "(l) off-enum disposition passed — rc=$rc"

# ---- (m) rows are permanent record: a cited path need not exist ---------------------------
write_register 'delta capability\t%s/99-retired.md, plugins/dev-pipeline/retired/gone.sh\tdropped\tits paths died with #348\n' "$P"
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
