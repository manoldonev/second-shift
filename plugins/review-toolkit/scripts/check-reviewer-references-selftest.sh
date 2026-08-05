#!/usr/bin/env bash
# Selftest for check-reviewer-references.sh — the three-root reviewer-registry gate.
#
# Runs hermetically from the plugin dir with NO consumer repo: every root is
# supplied via env override (SECOND_SHIFT_PLUGIN_ROOT / SECOND_SHIFT_REPO_ROOT /
# SECOND_SHIFT_CONFIG) pointing at static fixtures under scripts/fixtures/ (plus a
# mktemp'd empty consumer for the config-absent case). No git repo is required.
#
# Cases (failure-class → fixture):
#   all-green            plugin + consumer-green (reviewers.add resolves)        -> exit 0
#   config-absent        plugin + empty mktemp consumer, no config              -> exit 0
#   (a) DANGLING         plugin-dangling (registry entry, no agent file)        -> exit 1
#   (b) ORPHAN           plugin + consumer-orphan (reviewer file, not in config)-> exit 1
#   (c) REMOVE-UNKNOWN   plugin + consumer-remove-unknown (removes a non-plugin)-> exit 1
#   (d) SHADOW           plugin + consumer-shadow (shadows plugin agent name)   -> exit 1
#   add+override         plugin + consumer-add-override (add + modelOverride)   -> exit 0
#   design-present       plugin-design + design-toolkit sibling root supplied   -> exit 0, no notice
#   design-absent        plugin-design + design-toolkit root unresolvable       -> exit 0 + notice
#   design-absent-scope  plugin-dangling + design-toolkit root unresolvable     -> exit 1
#   design-cache-layout  plugin-design + versioned cache siblings, NO override  -> exit 0, no notice
#   design-shadow        REAL plugin + consumer copy of a design-toolkit name   -> exit 1
#   real-panel-design-absent  REAL plugin + design-toolkit root unresolvable    -> exit 0 + notice naming BOTH
#
# The design-* cases are what make the THREE-root contract falsifiable, and they only
# work as a pair-plus-scope: design-present asserts the sibling root RESOLVED (exit 0
# AND no exemption notice) rather than merely being exempted; design-absent asserts the
# exemption fired (notice, no DANGLING); design-absent-scope asserts the exemption is
# scoped to the declared design-toolkit names — an unrelated dangling entry still denies
# while design-toolkit is absent, so "exempt everything when the root is empty" fails.
#
# Three of the cases above exist because a fixture is not the shipped artifact:
#   - design-cache-layout drives the versioned-sibling GLOB, which every override-passing
#     case short-circuits past. Its sibling check-model-tiers-selftest.sh:311-326 records
#     why: the equivalent resolver shipped at 0.1.0 handling only the marketplace-repo
#     path and UNLOCATABLE-denied every consumer commit.
#   - real-panel-design-absent occupies the one cell the fixtures cannot reach —
#     (REAL shipped panel × design-toolkit absent). The fixture panel names one of the two
#     declared names and the one real-panel case runs with design-toolkit PRESENT, so
#     without this the exemption set's second entry is unguarded: dropping it left the
#     suite green while the shipped panel exited 1 from a PreToolUse `git commit` deny.
#   - design-shadow keeps the drift tripwire (failure class d) alive for the two names the
#     panel now registers: they resolve DANGLING through the consumer-root clause and are
#     in $effective (so no ORPHAN), which is precisely how registering them could retire
#     the tripwire silently.
#
# Convention mirrors check-model-tiers-selftest.sh: ok()/fail() counters, temp dirs
# cleaned via trap. Bash 3.2 compatible (macOS).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-reviewer-references.sh"
FX="$SCRIPT_DIR/fixtures/reviewer-references"
PLUGIN="$FX/plugin"
PLUGIN_DANGLING="$FX/plugin-dangling"
[ -x "$CHECK" ] || { echo "FAIL: $CHECK not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not available"; exit 1; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT

# Run the gate in CLI mode against explicit roots. Prints exit code; captures
# stderr into $TMP/.stderr. Args: <plugin_root> <repo_root> [config_path] [design_root]
# design_root unset => the script auto-resolves the sibling design-toolkit plugin
# (what a real install does); pass a non-existent path to model "not installed".
run_cli() {
  local plugin="$1" repo="$2" config="${3:-}" design="${4:-}"
  (
    export SECOND_SHIFT_PLUGIN_ROOT="$plugin"
    export SECOND_SHIFT_REPO_ROOT="$repo"
    [ -n "$config" ] && export SECOND_SHIFT_CONFIG="$config"
    [ -n "$design" ] && export SECOND_SHIFT_DESIGN_TOOLKIT_ROOT="$design"
    bash "$CHECK" </dev/null 2>"$TMP/.stderr"
  )
}

echo "check-reviewer-references selftest"

# all-green — reviewers.add resolves to a consumer agent file
run_cli "$PLUGIN" "$FX/consumer-green" "$FX/consumer-green/.claude/second-shift.config.json"
[ $? -eq 0 ] && ok "all-green: add resolves -> exit 0" || fail "all-green expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# config-absent — empty consumer, no config => empty deltas, plugin registry backed
EMPTY_CONSUMER="$TMP/empty-consumer"; mkdir -p "$EMPTY_CONSUMER"
run_cli "$PLUGIN" "$EMPTY_CONSUMER"
[ $? -eq 0 ] && ok "config-absent: empty deltas -> exit 0" || fail "config-absent expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# (a) DANGLING — plugin registry lists db-reviewer with no agent file in either root
run_cli "$PLUGIN_DANGLING" "$EMPTY_CONSUMER"
if [ $? -eq 0 ]; then fail "(a) dangling expected exit 1"; else
  grep -q "DANGLING:.*db-reviewer" "$TMP/.stderr" && ok "(a) DANGLING: registry entry, no agent file -> exit 1 + message" \
    || fail "(a) dangling: exit 1 but no DANGLING db-reviewer line (stderr: $(cat "$TMP/.stderr"))"
fi

# (b) ORPHAN — consumer orders-reviewer.md registered nowhere (no config)
run_cli "$PLUGIN" "$FX/consumer-orphan"
if [ $? -eq 0 ]; then fail "(b) orphan expected exit 1"; else
  grep -q "ORPHAN:.*orders-reviewer" "$TMP/.stderr" && ok "(b) ORPHAN: unregistered consumer reviewer -> exit 1 + message" \
    || fail "(b) orphan: exit 1 but no ORPHAN line (stderr: $(cat "$TMP/.stderr"))"
fi

# (c) REMOVE-UNKNOWN — reviewers.remove names db-reviewer, not in plugin registry
run_cli "$PLUGIN" "$FX/consumer-remove-unknown" "$FX/consumer-remove-unknown/.claude/second-shift.config.json"
if [ $? -eq 0 ]; then fail "(c) remove-unknown expected exit 1"; else
  grep -q "REMOVE-UNKNOWN:.*db-reviewer" "$TMP/.stderr" && ok "(c) REMOVE-UNKNOWN: stale remove delta -> exit 1 + message" \
    || fail "(c) remove-unknown: exit 1 but no REMOVE-UNKNOWN line (stderr: $(cat "$TMP/.stderr"))"
fi

# (d) SHADOW — consumer security-reviewer.md shadows the plugin-shipped agent name
run_cli "$PLUGIN" "$FX/consumer-shadow"
if [ $? -eq 0 ]; then fail "(d) shadow expected exit 1"; else
  grep -q "SHADOW:.*security-reviewer" "$TMP/.stderr" && ok "(d) SHADOW: consumer shadows plugin agent -> exit 1 + message" \
    || fail "(d) shadow: exit 1 but no SHADOW line (stderr: $(cat "$TMP/.stderr"))"
fi

# add+override — reviewers.add plus a modelOverride (ignored here) stays green
run_cli "$PLUGIN" "$FX/consumer-add-override" "$FX/consumer-add-override/.claude/second-shift.config.json"
[ $? -eq 0 ] && ok "add+override: add resolves, modelOverride ignored -> exit 0" \
  || fail "add+override expected exit 0 (stderr: $(cat "$TMP/.stderr"))"

# design-present — the panel names a design-toolkit-shipped reviewer and the sibling
# root supplies its agent file. Exit 0 is necessary but NOT sufficient: the exemption
# path also exits 0, so assert the exemption notice is ABSENT — that is what pins the
# pass to sibling-root resolution rather than to the design-toolkit-absent degrade.
PLUGIN_DESIGN="$FX/plugin-design"
run_cli "$PLUGIN_DESIGN" "$EMPTY_CONSUMER" "" "$FX/design-toolkit"
if [ $? -ne 0 ]; then
  fail "design-present expected exit 0 (stderr: $(cat "$TMP/.stderr"))"
elif grep -q "design-toolkit is not installed" "$TMP/.stderr"; then
  fail "design-present: exit 0 but via the absent-toolkit exemption, not sibling-root resolution (stderr: $(cat "$TMP/.stderr"))"
else
  ok "design-present: sibling root resolves the design-toolkit agent -> exit 0, no exemption"
fi

# design-absent — same panel, design-toolkit NOT installed (the override points at a
# path that does not exist). The panel entry must degrade to a printed notice, never a
# DANGLING denial: otherwise every consumer without design-toolkit is commit-blocked.
NO_DESIGN="$TMP/no-design-toolkit"
run_cli "$PLUGIN_DESIGN" "$EMPTY_CONSUMER" "" "$NO_DESIGN"
if [ $? -ne 0 ]; then
  fail "design-absent expected exit 0 — an absent design-toolkit must not deny (stderr: $(cat "$TMP/.stderr"))"
elif grep -q "DANGLING:" "$TMP/.stderr"; then
  # `DANGLING:` with the colon — the error-line prefix. A bare `DANGLING` also matches
  # the notice's own "exempt from DANGLING" wording and would fail the case spuriously.
  fail "design-absent: exit 0 but a DANGLING line was still emitted (stderr: $(cat "$TMP/.stderr"))"
elif ! grep -q "design-toolkit is not installed.*design-faithful-reviewer" "$TMP/.stderr"; then
  fail "design-absent: exit 0 and no DANGLING, but the degrade was SILENT — no notice naming the exempt entry (stderr: $(cat "$TMP/.stderr"))"
else
  ok "design-absent: absent design-toolkit -> exit 0 + notice, no DANGLING"
fi

# design-absent-scope — the exemption is scoped to the declared design-toolkit names.
# plugin-dangling's db-reviewer has no agent file in ANY root; with design-toolkit
# equally absent it must STILL deny. Guards "empty design root => exempt everything".
run_cli "$PLUGIN_DANGLING" "$EMPTY_CONSUMER" "" "$NO_DESIGN"
if [ $? -eq 0 ]; then fail "design-absent-scope expected exit 1 — the exemption must not cover a non-design-toolkit name"; else
  grep -q "DANGLING:.*db-reviewer" "$TMP/.stderr" && ok "design-absent-scope: unrelated dangling entry still denies -> exit 1" \
    || fail "design-absent-scope: exit 1 but no DANGLING db-reviewer line (stderr: $(cat "$TMP/.stderr"))"
fi

# shipped-SKILL lockstep — the REAL plugin root must parse clean against an empty
# consumer. Fixtures alone cannot catch a rewording of the shipped SKILL.md that
# breaks the parser's anchor phrases (that exact drift shipped in 0.1.0: the
# extraction reworded the pre-flight enumeration to "the plugin-shipped panel (…)"
# while the parser still keyed on "specialist reviewer subagent types (…)",
# producing a guaranteed DRIFT deny on every consumer commit).
REAL_PLUGIN="$SCRIPT_DIR/.."
run_cli "$REAL_PLUGIN" "$EMPTY_CONSUMER"
[ $? -eq 0 ] && ok "shipped-SKILL lockstep: real plugin root parses clean -> exit 0" \
  || fail "shipped-SKILL lockstep expected exit 0 — parser anchors out of lockstep with the shipped SKILL.md (stderr: $(cat "$TMP/.stderr"))"

# real-panel-design-absent — the production cell no fixture reaches: the REAL shipped
# panel against an ABSENT design-toolkit. The exemption set is DECLARED, so every name in
# it needs a case that fails when it is dropped; the fixture panel names only one of the
# two, and the only other real-panel case runs with design-toolkit present. This is also
# the lockstep between DESIGN_TOOLKIT_PANEL and the shipped panel — nothing else compares
# them. Asserting the notice names BOTH is the half that makes a dropped entry red: exit 0
# alone is satisfied by a name that resolved, and by a name that was never in the set.
run_cli "$REAL_PLUGIN" "$EMPTY_CONSUMER" "" "$NO_DESIGN"
rc=$?
notice=$(grep "design-toolkit is not installed" "$TMP/.stderr" 2>/dev/null)
if [ $rc -ne 0 ]; then
  fail "real-panel-design-absent expected exit 0 — the shipped panel must not deny a design-toolkit-less consumer's commit (stderr: $(cat "$TMP/.stderr"))"
elif grep -q "DANGLING:" "$TMP/.stderr"; then
  fail "real-panel-design-absent: exit 0 but a DANGLING line was emitted (stderr: $(cat "$TMP/.stderr"))"
elif ! grep -q "design-faithful-reviewer" <<< "$notice" || ! grep -q "figma-faithful-reviewer" <<< "$notice"; then
  fail "real-panel-design-absent: the notice does not name BOTH shipped design-toolkit panel entries — the exemption set is out of lockstep with the panel (notice: ${notice:-<none>})"
else
  ok "real-panel-design-absent: shipped panel + absent design-toolkit -> exit 0 + notice naming both entries"
fi

# design-shadow — failure class (d) must still fire for a design-toolkit-shipped name,
# and must fire whether or not design-toolkit is installed (hence PANEL membership, not
# file presence, as the test). Run with design-toolkit ABSENT: that is the configuration
# where a file-presence test silently accepts the shadowing copy.
DESIGN_SHADOW="$TMP/consumer-design-shadow"
mkdir -p "$DESIGN_SHADOW/.claude/agents"
printf -- '---\nname: design-faithful-reviewer\ndescription: consumer copy\n---\n' \
  > "$DESIGN_SHADOW/.claude/agents/design-faithful-reviewer.md"
run_cli "$REAL_PLUGIN" "$DESIGN_SHADOW" "" "$NO_DESIGN"
if [ $? -eq 0 ]; then
  fail "design-shadow expected exit 1 — a consumer copy of a design-toolkit-shipped panel name must trip SHADOW (stderr: $(cat "$TMP/.stderr"))"
else
  grep -q "SHADOW:.*design-faithful-reviewer" "$TMP/.stderr" \
    && ok "design-shadow: consumer copy of a design-toolkit panel name -> exit 1 + SHADOW" \
    || fail "design-shadow: exit 1 but no SHADOW line for design-faithful-reviewer (stderr: $(cat "$TMP/.stderr"))"
fi

# design-cache-layout — the versioned-sibling glob in resolve_design_toolkit_root, which
# every case above short-circuits past by supplying SECOND_SHIFT_DESIGN_TOOLKIT_ROOT and
# which the real-root case never reaches (this marketplace repo ships plugins/design-toolkit
# on disk). Installed layout is cache/<mkt>/<plugin>/<version>/, so the resolver must walk
# ../../../design-toolkit/*/ and pick the NEWEST sibling that actually carries agents/.
# Three siblings make that specific: 0.0.1 has an empty agents/ (picking the oldest DANGLINGs),
# 0.0.2 is the real one, 0.0.3-broken has no agents/ at all (dropping the filter picks it,
# DESIGN_AGENTS resolves empty, and the exemption fires instead of resolution).
CACHE_MKT="$TMP/cache/mkt"
mkdir -p "$CACHE_MKT/review-toolkit/0.0.1/scripts" \
         "$CACHE_MKT/design-toolkit/0.0.1/agents" \
         "$CACHE_MKT/design-toolkit/0.0.2/agents" \
         "$CACHE_MKT/design-toolkit/0.0.3-broken"
cp "$CHECK" "$CACHE_MKT/review-toolkit/0.0.1/scripts/check-reviewer-references.sh"
cp "$FX/design-toolkit/agents/design-faithful-reviewer.md" "$CACHE_MKT/design-toolkit/0.0.2/agents/"
# Prefix assignments, not a subshell export: run_cli's exports are already subshell-scoped,
# and a second `export` of the same names would make SC2030 fire on run_cli itself. No
# SECOND_SHIFT_DESIGN_TOOLKIT_ROOT here — resolving it is the whole point of this case.
SECOND_SHIFT_PLUGIN_ROOT="$PLUGIN_DESIGN" SECOND_SHIFT_REPO_ROOT="$EMPTY_CONSUMER" \
  bash "$CACHE_MKT/review-toolkit/0.0.1/scripts/check-reviewer-references.sh" </dev/null 2>"$TMP/.stderr"
rc=$?
if [ $rc -ne 0 ]; then
  fail "design-cache-layout expected exit 0 — the versioned-sibling design-toolkit root did not resolve (stderr: $(cat "$TMP/.stderr"))"
elif grep -q "design-toolkit is not installed" "$TMP/.stderr"; then
  fail "design-cache-layout: exit 0 but via the absent-toolkit exemption — the cache sibling was not resolved (stderr: $(cat "$TMP/.stderr"))"
else
  ok "design-cache-layout: newest versioned cache sibling carrying agents/ resolves -> exit 0, no exemption"
fi

echo
echo "[check-reviewer-references-selftest] $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
