#!/usr/bin/env bash
# check-lockstep-pairs-selftest.sh — verifies check-lockstep-pairs.sh actually catches drift,
# and that its DISCOVERY enrols the right sites and only those.
#
# The mutation idiom (per scripts/check-intake-tracker-namespaces-selftest.sh): green on the
# real tree, RED after a mutation. A guard that has never been observed failing is
# indistinguishable from one that cannot fail — which is precisely the prose-presence class
# this script's subject replaces.
#
# Cases (b) onward run against SYNTHETIC fixture trees rather than a copy of the repo. Since
# #604 the checker takes no manifest, so there is no row set to drive a copy from; a fixture
# tree also lets a case state exactly one property, which a repo copy cannot.
#
# ## Why this file never writes a marker literally
#
# Discovery walks the tree, and this file is IN the tree. A whole-line `LOCKSTEP-BEGIN demo`
# inside a heredoc here would be a real site to the checker, in a group of one, and would red
# the repo. So every fixture marker is assembled at runtime from $MARK below, and the token
# never appears contiguously in this source. Case (n) is the standing guard on that: it asserts
# no anchor in the live tree is sited only in this file.
#
# Exit code = number of failed checks (repo selftest convention).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECKER="$HERE/check-lockstep-pairs.sh"

[[ -x "$CHECKER" ]] || { echo "[lockstep-selftest] FATAL: $CHECKER not executable"; exit 99; }

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d -t lockstep-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM

# The marker token, never spelled contiguously in this source — see the header.
MARK="LOCKSTEP"
B="$MARK-BEGIN"
E="$MARK-END"

run() { bash "$CHECKER" "$1" >"$TMP/out" 2>&1; echo $?; }
out() { cat "$TMP/out"; }

# tree <name> — a fresh empty fixture root, echoed.
tree() { local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }

# sh_block <file> <anchor> <relation-or-empty> <body...> — write a shell-comment marked block.
sh_block() {
  local f="$1" anchor="$2" rel="$3"; shift 3
  mkdir -p "$(dirname "$f")"
  {
    echo "# prelude that is not part of the block"
    if [[ -n "$rel" ]]; then echo "# $B $anchor $rel"; else echo "# $B $anchor"; fi
    printf '%s\n' "$@"
    echo "# $E $anchor"
  } >> "$f"
}

echo "[lockstep-selftest]"

# ---- (a) the LIVE corpus is green ------------------------------------------------------
# Non-vacuity for everything below: the grammar, the exclusion and the size-1 rule are all
# asserted against synthetic trees, and this is the one case that says the real tree satisfies
# them. It is also what would catch a marker accidentally pasted into any file in the repo.
rc=$(run "$ROOT")
if [[ "$rc" -eq 0 ]]; then
  ok "(a) the live tree is green"
else
  bad "(a) the live tree is RED — rc=$rc; run 'bash scripts/check-lockstep-pairs.sh'"
  out | sed 's/^/      /' >&2
fi

# ---- (b) a two-site verbatim group passes ----------------------------------------------
d=$(tree b)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
rc=$(run "$d")
[[ "$rc" -eq 0 ]] \
  && ok "(b) a two-site verbatim group passes" \
  || { bad "(b) a correct two-site group went RED (rc=$rc)"; out | sed 's/^/      /' >&2; }

# ---- (c) verbatim drift is caught ------------------------------------------------------
d=$(tree c)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|z'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -q 'DRIFTED'; then
  ok "(c) verbatim: a one-token drift goes RED (rc=$rc)"
else
  bad "(c) verbatim drift NOT caught — the guard cannot fail"
fi

# ---- (c2) verbatim ignores indentation and line wrapping -------------------------------
# The relation is over tokens, not layout. If this reds, normalize() has been narrowed and
# every legitimate re-indent becomes a false failure.
d=$(tree c2)
sh_block "$d/a.sh" demo "" "  VALUE='x|y'   TAIL=1"
sh_block "$d/b.sh" demo "" "VALUE='x|y'" "TAIL=1"
rc=$(run "$d")
[[ "$rc" -eq 0 ]] \
  && ok "(c2) verbatim tolerates re-indentation and re-wrapping" \
  || { bad "(c2) a whitespace-only difference was reported as drift (rc=$rc)"; out | sed 's/^/      /' >&2; }

# ---- (c3) token BOUNDARIES are part of the contract --------------------------------------
# normalize() COLLAPSES whitespace runs; it must not DELETE them. These two blocks are equal
# under deletion and different under collapse, so a weakened normalize passes them and the
# guard stops discriminating exactly where a re-indent ends and a re-tokenization begins.
d=$(tree c3)
sh_block "$d/a.sh" demo "" "AB CD"
sh_block "$d/b.sh" demo "" "ABC D"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(c3) a token-boundary difference is drift, not whitespace (rc=$rc)" \
  || bad "(c3) normalize() deletes whitespace instead of collapsing it — token boundaries are unguarded"

# ---- (d) a THIRD site joins the same group and is compared -----------------------------
# The manifest expressed a triple as two rows against one canonical leg. Discovery has no
# such shape — the group is the group — so this asserts the third member is really read.
d=$(tree d)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
sh_block "$d/c.sh" demo "" "VALUE='x|WRONG'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -q 'c\.sh'; then
  ok "(d) a third site joins the group and its drift is caught"
else
  bad "(d) the third member of a group was not compared"
fi

# ---- (e) a group of ONE fails, naming the file and the anchor --------------------------
# The property no central register could have: a marker whose counterpart never existed.
d=$(tree e)
sh_block "$d/lonely.sh" orphan-anchor "" "VALUE='x|y'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -q 'orphan-anchor' && out | grep -q 'lonely\.sh'; then
  ok "(e) a size-1 anchor FAILS, naming both the anchor and the file (rc=$rc)"
else
  bad "(e) a size-1 anchor did not fail, or failed without naming the site"
  out | sed 's/^/      /' >&2
fi

# ---- (f) a DELETED marker is never a silent skip ---------------------------------------
# Same intent as the pre-#604 case, reached from the other side: removing one leg's BEGIN
# drops the group to one member, which (e)'s rule reds. A deleted PAIR is the known trade,
# stated in docs/testing.md — this asserts the one-sided deletion is still loud.
d=$(tree f)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
grep -v "$B demo" "$d/b.sh" > "$d/b.tmp" && mv "$d/b.tmp" "$d/b.sh"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(f) deleting ONE leg's marker reds (rc=$rc) — never a silent skip" \
  || bad "(f) a deleted marker was treated as a skip — the guard can be disabled by deletion"

# ---- (g) subset-of: a legitimate narrowing passes --------------------------------------
d=$(tree g)
sh_block "$d/wide.sh"   enum superset "VALUE='a|b|c'"
sh_block "$d/narrow.sh" enum subset   "VALUE='a|c'"
rc=$(run "$d")
[[ "$rc" -eq 0 ]] \
  && ok "(g) subset-of tolerates a legitimate narrowing" \
  || { bad "(g) subset-of rejected a valid subset (rc=$rc)"; out | sed 's/^/      /' >&2; }

# ---- (h) subset-of: a token absent from the superset is caught -------------------------
d=$(tree h)
sh_block "$d/wide.sh"   enum superset "VALUE='a|b|c'"
sh_block "$d/narrow.sh" enum subset   "VALUE='a|INVENTED'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -q 'INVENTED'; then
  ok "(h) subset-of: a token absent from the superset goes RED (rc=$rc)"
else
  bad "(h) subset-of violation NOT caught"
fi

# ---- (i) the relation is DIRECTIONAL -----------------------------------------------------
# Swapping which side claims `superset` must red on the same two files that pass in (g).
# Without this, a relation token that was read but never acted on would still pass (g).
d=$(tree i)
sh_block "$d/wide.sh"   enum subset   "VALUE='a|b|c'"
sh_block "$d/narrow.sh" enum superset "VALUE='a|c'"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(i) subset-of is directional — reversing the roles reds (rc=$rc)" \
  || bad "(i) the direction is not read: superset and subset are interchangeable"

# ---- (j) members that DISAGREE about the relation fail ---------------------------------
d=$(tree j)
sh_block "$d/a.sh" enum superset "VALUE='a|b'"
sh_block "$d/b.sh" enum ""       "VALUE='a|b'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -qi 'DISAGREE'; then
  ok "(j) a group whose members disagree about the relation FAILS (rc=$rc)"
else
  bad "(j) a mixed-relation group was accepted"
  out | sed 's/^/      /' >&2
fi

# ---- (j2) a subset-of group needs exactly ONE superset ---------------------------------
d=$(tree j2)
sh_block "$d/a.sh" enum superset "VALUE='a|b'"
sh_block "$d/b.sh" enum superset "VALUE='a|b'"
sh_block "$d/c.sh" enum subset   "VALUE='a'"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(j2) two supersets in one group FAILS (rc=$rc)" \
  || bad "(j2) a group with two supersets was accepted"

# ---- (k) an UNRECOGNISED relation fails rather than defaulting to verbatim --------------
# The dangerous shape: a typo that degraded to the default would leave a subset-of pair
# silently compared verbatim, or vice versa, with nothing to see.
d=$(tree k)
sh_block "$d/a.sh" enum subst "VALUE='a|b'"
sh_block "$d/b.sh" enum ""    "VALUE='a|b'"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -q 'subst'; then
  ok "(k) an unrecognised relation token FAILS, naming it (rc=$rc)"
else
  bad "(k) an unrecognised relation silently fell back to verbatim"
fi

# ---- (l) docs/plans is EXCLUDED from discovery -------------------------------------------
# Plan documents quote locksteped blocks as evidence and are supposed to drift from them.
d=$(tree l)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
sh_block "$d/docs/plans/old-plan.md" demo "" "VALUE='THIS-DRIFTED-LONG-AGO'"
rc=$(run "$d")
[[ "$rc" -eq 0 ]] \
  && ok "(l) a docs/plans quote does not join the group" \
  || { bad "(l) docs/plans was enrolled — a plan doc can now red a correct tree (rc=$rc)"; out | sed 's/^/      /' >&2; }

# ---- (l2) the exclusion is SCOPED, not a blanket docs/ skip -----------------------------
d=$(tree l2)
sh_block "$d/docs/config-schema.md" lonely-doc "" "VALUE='x|y'"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(l2) docs/ outside docs/plans/ is still walked (rc=$rc)" \
  || bad "(l2) the exclusion over-reaches — all of docs/ is being skipped"

# ---- (m) a marker NAME outside a marker is not a site -----------------------------------
# The three shapes that exist in the live tree, each of which a substring search would enrol:
# a backticked prose citation, the token inside a code argument, and a marker trailing text.
d=$(tree m)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
{
  echo "The denylist is stated once, inside the \`$B seam-scrub\` markers in lean-gate.sh."
  echo "See also \`$E seam-scrub\`."
} > "$d/prose.md"
printf "sed 's|// %s findings-schema||' \"\$TARGET\" > \"\$TARGET.m\"\n" "$B" > "$d/code.sh"
printf '# The append happens OUTSIDE the %s/%s seam-scrub markers.\n' "$B" "$E" >> "$d/code.sh"
rc=$(run "$d")
if [[ "$rc" -eq 0 ]]; then
  ok "(m) prose citations and code arguments carrying the token are not sites"
else
  bad "(m) a non-marker mention of the token was enrolled as a site (rc=$rc)"
  out | sed 's/^/      /' >&2
fi

# ---- (m2) a marker line with TRAILING TEXT fails rather than being skipped ---------------
# Fail-closed: the alternative is a site that silently vanishes on a stray edit.
d=$(tree m2)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
sh_block "$d/b.sh" demo "" "VALUE='x|y'"
printf '# %s demo verbatim -- see the note above\nX=1\n# %s demo\n' "$B" "$E" > "$d/c.sh"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -qi 'grammar'; then
  ok "(m2) a marker line with trailing text is MALFORMED, not skipped (rc=$rc)"
else
  bad "(m2) a malformed marker line was silently skipped"
  out | sed 's/^/      /' >&2
fi

# ---- (n) an UNCLOSED begin fails ----------------------------------------------------------
d=$(tree n)
sh_block "$d/a.sh" demo "" "VALUE='x|y'"
printf '# %s demo\nX=1\n' "$B" > "$d/b.sh"
rc=$(run "$d")
if [[ "$rc" -ne 0 ]] && out | grep -qi 'never closed'; then
  ok "(n) a BEGIN with no END FAILS (rc=$rc)"
else
  bad "(n) an unclosed BEGIN was not reported"
fi

# ---- (o) markdown and mjs comment syntaxes are recognised ---------------------------------
d=$(tree o)
mkdir -p "$d"
printf '<!-- %s md-demo -->\nsome shared prose\n<!-- %s md-demo -->\n' "$B" "$E" > "$d/one.md"
printf '  <!-- %s md-demo -->\n  some shared prose\n  <!-- %s md-demo -->\n' "$B" "$E" > "$d/two.md"
printf '// %s js-demo\nconst X = 1\n// %s js-demo\n' "$B" "$E" > "$d/one.mjs"
printf '// %s js-demo\nconst X = 1\n// %s js-demo\n' "$B" "$E" > "$d/two.mjs"
rc=$(run "$d")
[[ "$rc" -eq 0 ]] \
  && ok "(o) markdown <!-- --> and // markers are recognised, indented or not" \
  || { bad "(o) a comment dialect was not recognised (rc=$rc)"; out | sed 's/^/      /' >&2; }

# ---- (p) an EMPTY block fails --------------------------------------------------------------
d=$(tree p)
printf '# %s demo\n# %s demo\n' "$B" "$E" > "$d/a.sh"
printf '# %s demo\n# %s demo\n' "$B" "$E" > "$d/b.sh"
rc=$(run "$d")
[[ "$rc" -ne 0 ]] \
  && ok "(p) adjacent markers with nothing between them FAIL (rc=$rc)" \
  || bad "(p) an empty block was accepted — two empty blocks compare equal"

# ---- (q) the exit code is the number of failed anchors ------------------------------------
# The repo selftest convention, and what makes a CI step's rc readable.
d=$(tree q)
sh_block "$d/one.sh"   lonely-a "" "VALUE='x'"
sh_block "$d/two.sh"   lonely-b "" "VALUE='y'"
sh_block "$d/three.sh" lonely-c "" "VALUE='z'"
rc=$(run "$d")
[[ "$rc" -eq 3 ]] \
  && ok "(q) exit code equals the failed-anchor count (3)" \
  || bad "(q) exit code was $rc, expected 3 (the failed-anchor count)"

# ---- (r) no live anchor is sited ONLY in this file -----------------------------------------
# The standing guard on the header's rule. If a future edit writes a fixture marker literally
# instead of assembling it, discovery enrols this file, the anchor lands in a group of one,
# and case (a) reds — but with a message about a file nobody would think to look in. This
# names the cause directly.
# Asked of the CHECKER rather than of a hand-written pattern: a copy of this file, alone in a
# tree, must yield zero anchors. Re-implementing the grammar here would be a mirror harness,
# and a stricter one would red on this very paragraph.
d=$(tree r)
cp "$HERE/check-lockstep-pairs-selftest.sh" "$d/copy.sh"
rc=$(run "$d")
if [[ "$rc" -eq 0 ]] && out | grep -q '0 anchor(s) checked'; then
  ok "(r) this file yields ZERO discovery sites — fixtures assemble their markers at runtime"
else
  bad "(r) this file is itself a discovery site; a fixture marker was written literally"
  out | sed 's/^/      /' >&2
fi

echo "[lockstep-selftest] summary: $PASS passed, $FAIL failed"
exit $FAIL
