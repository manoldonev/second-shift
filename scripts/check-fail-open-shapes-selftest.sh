#!/usr/bin/env bash
#
# check-fail-open-shapes-selftest.sh — behavioral coverage for scripts/check-fail-open-shapes.sh.
#
# INVARIANT GUARDED: the guard and its disposition table check EACH OTHER. An enumerated site
# with no row reds (g2); a row whose anchor no longer resolves reds (g3); a row that outlived
# its site reds (g4); a reverted conversion reds (g5). A guard with only the happy path would
# pass while the table quietly stopped describing the tree — which is the failure mode the
# whole denominator-as-artifact design exists to prevent.
#
# The negative direction is equally load-bearing: (g9) through (g12) pin what the recipe must
# NOT enumerate. A scanner that reds on the `printf | grep -q` shape #522 already owns, or on
# `||`, would be turned off within a week, and then it guards nothing.
#
# TECHNIQUE: fixture trees under mktemp, each with its own scripts/fail-open-sites.tsv, handed
# to the REAL guard as its repo root. No production file is written.
#
# Operator-safe: no gh, no network. bash-3.2-safe. Runs in CI via the '*-selftest.sh' loop.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${FAIL_OPEN_GUARD:-$HERE/check-fail-open-shapes.sh}"

PASS=0
FAILS=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAILS=$((FAILS + 1)); echo "  FAIL: $1" >&2; }

[[ -f "$GUARD" ]] || { echo "check-fail-open-shapes-selftest: FAIL — guard not found at $GUARD" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fail-open-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

TAB="$(printf '\t')"

# new_fixture <name> — a tree with one live site and a row that disposes of it.
new_fixture() {
  local d="$WORK/$1"
  mkdir -p "$d/scripts" "$d/tools"
  cat > "$d/tools/probe.sh" <<'EOF'
#!/usr/bin/env bash
if some-producer --list | grep -q wanted; then echo yes; fi
EOF
  printf '# fixture table\n' > "$d/scripts/fail-open-sites.tsv"
  printf 'tools/probe.sh%ssafe%ssome-producer --list | grep -q wanted%sfixture: dispositioned.\n' \
    "$TAB" "$TAB" "$TAB" >> "$d/scripts/fail-open-sites.tsv"
  printf '%s' "$d"
}

run_guard() { bash "$GUARD" "$1" 2>&1; }

echo "== the real tree =="

# THIS is how the guard reaches CI. It has no ci.yml registration — like
# stack-generality-lint.sh, it runs because CI globs `*-selftest.sh`, so if no case pointed it
# at the actual repo it would only ever grade fixtures and the production tree would go
# unchecked while every case stayed green.
out="$(bash "$GUARD" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then
  ok "(g0) THE REPO ITSELF: every enumerated site is dispositioned, no banned shapes"
else
  bad "(g0) the repo is not clean (rc=$rc). Convert the site, or add its row to scripts/fail-open-sites.tsv:
$out"
fi

echo "== the guard and the table check each other =="

D="$(new_fixture clean)"
out="$(run_guard "$D")"; rc=$?
[[ $rc -eq 0 ]] \
  && ok "(g1) a tree whose every enumerated site is dispositioned -> rc 0" \
  || bad "(g1) expected rc 0, got $rc: $out"

D="$(new_fixture unclassified)"
cat >> "$D/tools/probe.sh" <<'EOF'
if другой-producer --check | grep -qi other; then echo yes; fi
EOF
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'UNCLASSIFIED' <<<"$out"; then
  ok "(g2) a NEW command-producer site with no row -> red, named UNCLASSIFIED"
else bad "(g2) expected a red naming UNCLASSIFIED, rc=$rc: $out"; fi

D="$(new_fixture drift)"
# Same site, but the row's anchor no longer appears anywhere in the file.
printf '# fixture table\ntools/probe.sh%ssafe%ssome-producer --list | grep -q GONE%sfixture: drifted anchor.\n' \
  "$TAB" "$TAB" "$TAB" > "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'ANCHOR DRIFT' <<<"$out"; then
  ok "(g3) a row whose anchor no longer resolves -> ANCHOR DRIFT, not a silent pass"
else bad "(g3) expected ANCHOR DRIFT, rc=$rc: $out"; fi

D="$(new_fixture outlived)"
# The site is gone (converted by hand) but the row still calls it `safe`. Its anchor still
# RESOLVES — the producer survived the conversion — so the drift check passes and only the
# outlived check can catch this.
cat > "$D/tools/probe.sh" <<'EOF'
#!/usr/bin/env bash
checked_match -e wanted -- some-producer --list
EOF
printf '# fixture table\ntools/probe.sh%ssafe%ssome-producer --list%sfixture: excuse outlived its site.\n' \
  "$TAB" "$TAB" "$TAB" > "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'outlived what it excused' <<<"$out"; then
  ok "(g4) a 'safe' row whose site is gone -> red; an excuse cannot outlive the thing it excused"
else bad "(g4) expected 'outlived what it excused', rc=$rc: $out"; fi

D="$(new_fixture reverted)"
# A `converted` row whose anchor is ALSO the live pipeline — i.e. the conversion was undone.
printf '# fixture table\ntools/probe.sh%sconverted%ssome-producer --list | grep -q wanted%sfixture: claims converted.\n' \
  "$TAB" "$TAB" "$TAB" > "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q "marked 'converted' but its anchor still covers a live" <<<"$out"; then
  ok "(g5) a reverted conversion -> red; 'converted' is a claim the enumeration can refute"
else bad "(g5) expected the reverted-conversion red, rc=$rc: $out"; fi

D="$(new_fixture baddisp)"
printf '# fixture table\ntools/probe.sh%sprobably-fine%ssome-producer --list | grep -q wanted%sfixture.\n' \
  "$TAB" "$TAB" "$TAB" > "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'unknown disposition' <<<"$out"; then
  ok "(g6) a disposition outside the closed vocabulary -> red"
else bad "(g6) expected 'unknown disposition', rc=$rc: $out"; fi

D="$(new_fixture malformed)"
printf '# fixture table\ntools/probe.sh%ssafe%ssome-producer --list | grep -q wanted\n' "$TAB" "$TAB" \
  > "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'malformed row' <<<"$out"; then
  ok "(g7) a row missing its 'why' -> red; a disposition with no stated mechanism is not one"
else bad "(g7) expected 'malformed row', rc=$rc: $out"; fi

D="$(new_fixture notable)"
rm -f "$D/scripts/fail-open-sites.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -ge 1 ]] && grep -q 'disposition table is missing' <<<"$out"; then
  ok "(g8) no table at all -> red; the denominator must have something to be checked against"
else bad "(g8) expected the missing-table red, rc=$rc: $out"; fi

echo "== the pgrep-count leg =="

D="$(new_fixture pgrepcount)"
# shellcheck disable=SC2016  # fixture TEXT — the '$' must reach the file unexpanded.
printf '#!/usr/bin/env bash\nn="$(pgrep -fc "$PAT" 2>/dev/null || echo 0)"\n' > "$D/tools/count.sh"
out="$(run_guard "$D")"; rc=$?
# shellcheck disable=SC2016  # matching the guard's literal message, backticks and all.
if [[ $rc -ge 1 ]] && grep -q 'counting `pgrep -c` form' <<<"$out"; then
  ok "(g9) \`pgrep -fc\` -> red, whether or not anyone has written the '|| echo 0' yet"
else bad "(g9) expected the pgrep-count red, rc=$rc: $out"; fi

D="$(new_fixture pgrepok)"
# shellcheck disable=SC2016  # fixture TEXT.
printf '#!/usr/bin/env bash\nn="$(pgrep -f "$PAT" 2>/dev/null | wc -l | tr -d " ")"\n' > "$D/tools/count.sh"
out="$(run_guard "$D")"; rc=$?
[[ $rc -eq 0 ]] \
  && ok "(g10) the sanctioned \`pgrep -f … | wc -l\` is NOT red — the leg bans the counting form, not pgrep" \
  || bad "(g10) expected rc 0 on the sanctioned form, got $rc: $out"

echo "== what the recipe must NOT enumerate =="

D="$(new_fixture notsites)"
cat >> "$D/tools/probe.sh" <<'EOF'
printf '%s\n' "$KNOWN" | grep -Fxq "$1"        # variable producer: #522 owns this shape
some-producer --list || grep -q wanted /dev/null # `||` is not a pipe
EOF
mkdir -p "$D/docs/plans"
# shellcheck disable=SC2016  # fixture TEXT.
printf 'A verdict record quoting `historic-producer --list | grep -q wanted`.\n' > "$D/docs/plans/old-lean-verdict.md"
# A .tsv is data everywhere in this repo, and tools/mutation-catalog.tsv is a corpus of
# DELIBERATELY BROKEN shell: a row describing the reintroduction of either banned shape must
# not red the guard for describing it. Both shapes, in one table, on purpose — and the arm
# that excuses them anchors on the path separator, because these lines reach it as
# `relpath:line:text` and a `\.tsv$` would have tested the end of the TEXT.
# shellcheck disable=SC2016  # fixture TEXT.
printf 'some-id%stools/x.sh%ss#a#b#%sa note about `other-producer | grep -q x` and `pgrep -fc`\n' \
  "$TAB" "$TAB" "$TAB" > "$D/tools/mutation-catalog.tsv"
out="$(run_guard "$D")"; rc=$?
if [[ $rc -eq 0 ]]; then
  ok "(g11) a printf producer, a \`||\`, docs/plans/ prose and .tsv corpus rows are all outside the denominator"
else bad "(g11) expected rc 0 — the recipe over-matched: $out"; fi

echo "== --list IS the denominator =="

D="$(new_fixture listing)"
listing="$(bash "$GUARD" --list "$D")"
n="$(printf '%s\n' "$listing" | grep -c . || true)"
if [[ "$n" -eq 1 ]] && grep -q 'tools/probe.sh' <<<"$listing"; then
  ok "(g12) --list prints exactly the live sites (1), keyed file<TAB>line<TAB>text"
else bad "(g12) expected 1 site naming tools/probe.sh, got $n: $listing"; fi

cat >> "$D/tools/probe.sh" <<'EOF'
if another-producer --check | grep -q more; then echo yes; fi
EOF
n2="$(bash "$GUARD" --list "$D" | grep -c . || true)"
[[ "$n2" -eq 2 ]] \
  && ok "(g13) a new site moves the denominator (1 -> 2) — the recipe is what counts, not a frozen number" \
  || bad "(g13) expected 2 sites after adding one, got $n2"

# --list must never gate: it is a reporting mode, and a caller piping it somewhere must not
# have to strip a verdict line or interpret an exit code.
bash "$GUARD" --list "$D" >/dev/null 2>&1
lrc=$?
[[ $lrc -eq 0 ]] \
  && ok "(g14) --list exits 0 even on a tree with unclassified sites — it reports, it does not judge" \
  || bad "(g14) --list exited $lrc on an unclassified tree"

echo
echo "[check-fail-open-shapes-selftest] $([ "$FAILS" -eq 0 ] && echo 'all green' || echo "$FAILS failed") — $PASS passed, $FAILS failed"
exit $((FAILS > 0))
