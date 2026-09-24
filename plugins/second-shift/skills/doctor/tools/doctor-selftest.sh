#!/usr/bin/env bash
# doctor-selftest.sh — hermetic selftest for doctor.sh (no claude binary, no network).
# All data sources are env-injected files; the install tree is a fake cache under mktemp.
set -euo pipefail
# Hermetic: both are overrides doctor's helpers honor, and a caller's value would clobber the fixtures.
unset SECOND_SHIFT_EXTENSION_MANIFEST SECOND_SHIFT_TIER_DOC
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$HERE/doctor.sh"; FIX="$HERE/doctor-fixtures"; FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }

# --- cross-plugin sibling resolution -------------------------------------------------------
# The --report context-coverage scenario reaches review-toolkit, another plugin, as a root. A fixed
# `$HERE/../../../../review-toolkit` hop holds only in the monorepo: installed, this file lives at
# <cache>/<marketplace>/second-shift/<version>/skills/doctor/tools, so the resolution runs two
# rungs — monorepo path, then the HIGHEST cache version carrying the marker (plugins are versioned
# independently, so the sibling is rarely at this plugin's version). There is no skip rung: a
# miss is a counted failure below.
#
# resolve_sibling_plugin_root <this-plugin-root> <name> <marker-subpath> — echoes the sibling root.
resolve_sibling_plugin_root() {
  local anchor="$1" name="$2" marker="$3" cand
  cand="$(cd "$anchor/../$name" 2>/dev/null && pwd)" || cand=""
  if [[ -n "$cand" && -d "$cand/$marker" ]]; then printf '%s\n' "$cand"; return 0; fi
  # Per-field numeric sort, ASCENDING + `tail -1`: glob order is lexical (9.0.0 above 10.0.0), and
  # BSD sort ignores a global `-r` once per-key modifiers are present.
  for cand in "$anchor"/../../"$name"/*/; do
    [[ -d "$cand/$marker" ]] || continue
    printf '%s\t%s\n' "$(basename "$cand")" "$(cd "$cand" && pwd)"
  done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-
}
scenario() { # $1 label, $2 plugin-list fixture, $3 settings fixture, $4 marketplace fixture,
             # $5 expected exit code, $6 expected substring in output,
             # $7 (optional) lock fixture — default lock-v1.json
             # $8 (optional) config fixture — default config-valid.json
             # $9 (optional) SECOND_SHIFT_CONFIG_GRILL override. Empty is indistinguishable
             #    from unset — doctor reads it as `${SECOND_SHIFT_CONFIG_GRILL:-…}` — so every
             #    pre-existing call site keeps resolving the real checker unchanged.
  local root="$TMP/$1"; mkdir -p "$root/.claude"
  cp "$FIX/${7:-lock-v1.json}" "$root/.claude/second-shift.lock.json"
  cp "$FIX/${8:-config-valid.json}" "$root/.claude/second-shift.config.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/$3" > "$root/.claude/settings.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/$2" > "$TMP/$1-pluglist.json"
  local out rc=0
  out="$(DOCTOR_REPO_ROOT="$root" DOCTOR_PLUGIN_LIST_FILE="$TMP/$1-pluglist.json" \
         DOCTOR_MARKETPLACE_LIST_FILE="$FIX/$4" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
         SECOND_SHIFT_CONFIG_GRILL="${9:-}" \
         bash "$DOCTOR" 2>&1)" || rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$5" ]] && grep -qF "$6" <<< "$out"; then check "$1" 0
  else check "$1 (rc=$rc want $5; grep '$6' failed)" 1; echo "$out" | sed 's/^/      /' | head -12; fi
}
report() { # $1 label, $2 config fixture, $3 extra-present (optional), $4 extra-present2 (optional), $5 must-be-absent (optional)
  local root="$TMP/$1"; mkdir -p "$root/.claude"
  cp "$FIX/lock-v1.json" "$root/.claude/second-shift.lock.json"
  cp "$FIX/$2" "$root/.claude/second-shift.config.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/settings-green.json" > "$root/.claude/settings.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/plugin-list-green.json" > "$TMP/$1-pluglist.json"
  local out rc=0 ok=1 want
  out="$(DOCTOR_REPO_ROOT="$root" DOCTOR_PLUGIN_LIST_FILE="$TMP/$1-pluglist.json" \
         DOCTOR_MARKETPLACE_LIST_FILE="$FIX/marketplace-list-pinned.json" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
         bash "$DOCTOR" --report 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0                              # report mode always exits 0
  # Every bundle carries the five sections + the nested check run's summary line.
  for want in "### doctor output" "### claude plugin list --json" "### redacted config" "### context coverage (review-context sections)" "### pipeline-state excerpt" "[doctor] summary:"; do
    grep -qF "$want" <<< "$out" || ok=0
  done
  [[ -z "${3:-}" ]] || grep -qF "$3" <<< "$out" || ok=0
  [[ -z "${4:-}" ]] || grep -qF "$4" <<< "$out" || ok=0
  if [[ -n "${5:-}" ]] && grep -qF "$5" <<< "$out"; then ok=0; fi
  if [[ "$ok" -eq 1 ]]; then check "$1" 0; else check "$1 (rc=$rc)" 1; echo "$out" | sed 's/^/      /' | head -20; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo '{}' > "$TMP/empty-user-settings.json"
# Fake install tree mirroring the cache layout. Skill dir names are REAL plugin skill names —
# the shadow scan compares against these basenames.
INSTALL="$TMP/cache"
mkdir -p "$INSTALL/dev-pipeline/2.1.0/skills/run" "$INSTALL/dev-pipeline/2.1.0/tools" \
         "$INSTALL/review-toolkit/2.0.2/skills/review-lead" \
         "$INSTALL/intake-toolkit/2.0.0/skills/intake" \
         "$INSTALL/audit-toolkit/2.0.0/skills/audit" \
         "$INSTALL/second-shift/1.0.0/skills/onboard" \
         "$INSTALL/second-shift/1.0.0/skills/doctor" \
         "$INSTALL/review-toolkit/2.0.2/workflows"
# A current review-toolkit carries the fan-out; without these every scenario would FAIL the
# upgrade-skew check. The skew scenario points at its own install dir that lacks them.
: > "$INSTALL/review-toolkit/2.0.2/workflows/code-review.mjs"
: > "$INSTALL/review-toolkit/2.0.2/model-tiering.md"
# The stub echoes the tier doc it was handed, so a scenario can see what doctor passed.
# shellcheck disable=SC2016 # emitting a literal stub script — $1 must not expand here
printf '#!/usr/bin/env bash\necho "config-lint: OK ($1) tier-doc=${SECOND_SHIFT_TIER_DOC:-unset}"\n' > "$INSTALL/dev-pipeline/2.1.0/tools/config-lint.sh"
# An older dev-pipeline install still carries claims-lint.sh. Doctor no longer runs it, so a copy
# that fails must not move any scenario's exit code (every green scenario below reds if it does).
printf '#!/usr/bin/env bash\necho "claims-lint: expired claim"; exit 1\n' > "$INSTALL/dev-pipeline/2.1.0/tools/claims-lint.sh"

echo "doctor selftest:"
scenario green            plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "summary: 0 failed"
# config-lint reads the tier alphabet from the review-toolkit that is ENABLED, not whichever
# cached copy its own resolver would find.
scenario tier-doc         plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "tier-doc=$INSTALL/review-toolkit/2.0.2/model-tiering.md"
# --- extension file names ----------------------------------------------------------------
# No .claude/second-shift/ at all: the check says nothing, not even "clean".
if grep -qi "extension" <<< "$LAST_OUT"; then check "no .claude/second-shift/ adds no extension line" 1
else check "no .claude/second-shift/ adds no extension line" 0; fi
mkdir -p "$TMP/ext-typo/.claude/second-shift"
: > "$TMP/ext-typo/.claude/second-shift/blocker-mutants.md.md"
scenario ext-typo         plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 ".claude/second-shift/blocker-mutants.md.md matches no known extension name"
mkdir -p "$TMP/ext-allowed/.claude/second-shift/api-testing"
: > "$TMP/ext-allowed/.claude/second-shift/api-testing/orders.md"
printf 'api-testing/*.md\n' > "$TMP/ext-allowed/.claude/second-shift/.known-extensions"
scenario ext-allowed      plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "summary: 0 failed"
if grep -qi "extension" <<< "$LAST_OUT"; then check "a clean extension check prints nothing" 1
else check "a clean extension check prints nothing" 0; fi
# A missing manifest is a broken install, never a clean pass.
mkdir -p "$TMP/ext-no-manifest/.claude/second-shift"
: > "$TMP/ext-no-manifest/.claude/second-shift/security-rules.md"
SECOND_SHIFT_EXTENSION_MANIFEST="$TMP/no-such-manifest.txt" \
scenario ext-no-manifest  plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "extension lint cannot run: manifest not found: $TMP/no-such-manifest.txt"
# A check that dies before naming any file (here: an unreadable allowlist) is not a clean pass.
mkdir -p "$TMP/ext-crash/.claude/second-shift"
: > "$TMP/ext-crash/.claude/second-shift/blocker-mutants.md.md"
: > "$TMP/ext-crash/.claude/second-shift/.known-extensions"
chmod 000 "$TMP/ext-crash/.claude/second-shift/.known-extensions"
if [[ -r "$TMP/ext-crash/.claude/second-shift/.known-extensions" ]]; then
  echo "  SKIP ext-crash (running as root: chmod 000 does not bar reads)"
else
  scenario ext-crash      plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "extension check could not run (rc=1)"
fi
# --- a review-toolkit that predates the fan-out move -----------------------------------------
# Plugins update one at a time and none declares a dependency, so a new dev-pipeline or
# intake-toolkit can sit beside a review-toolkit that still lacks workflows/ and the alphabet.
mkdir -p "$INSTALL/predates/review-toolkit/2.0.2"
scenario rt-predates      plugin-list-rt-predates.json settings-green.json marketplace-list-pinned.json 1 "review-toolkit 2.0.2 predates the fan-out move — update all second-shift plugins together (/second-shift:local-dev-refresh)"
# ...and nothing reads that fan-out when dev-pipeline and intake-toolkit are both disabled.
scenario rt-predates-unused plugin-list-rt-predates-unused.json settings-green.json marketplace-list-pinned.json 0 "summary: 0 failed"
scenario missing-plugin   plugin-list-missing.json settings-green.json     marketplace-list-pinned.json  1 "claude plugin install dev-pipeline@second-shift"
# The two drift branches under a PROJECT-scope record. Both greps name the arm's own string
# rather than the "marketplace update" / "ahead of the lockfile" prefixes both arms share —
# those matched the user-scope arm too, so a swapped branch read as green.
scenario version-behind   plugin-list-behind.json  settings-green.json     marketplace-list-pinned.json  1 "claude plugin install dev-pipeline@second-shift --scope project"
scenario version-ahead    plugin-list-ahead.json   settings-green.json     marketplace-list-pinned.json  1 "settings pin v9.9.0 resolves the older catalog"
# ...and the same two branches under a USER-scope record, where the project-scope string is not
# a weaker fix but a NO-OP: `install` no-ops as "already installed" on the behind branch, and on
# the ahead branch there is no project pin behind the record for a reinstall to resolve against.
# second-shift@second-shift is the user-scope entry in every fixture here.
scenario user-behind      plugin-list-user-behind.json settings-green.json marketplace-list-pinned.json  1 "claude plugin update second-shift@second-shift"
scenario user-ahead       plugin-list-user-ahead.json  settings-green.json marketplace-list-pinned.json  1 "claude plugin marketplace add manoldonev/second-shift@v9.9.0"
scenario user-ahead-no-reinstall plugin-list-user-ahead.json settings-green.json marketplace-list-pinned.json 1 "Do not reinstall"
# A project record shadowed by a user record. The fixture's `lastUpdated` ordering is the whole
# point: the user record is the NEWER one, so the retired `sort_by(.lastUpdated) | last` resolver
# graded 2.1.0 and reported OK — the verdict must now describe the project record (2.0.1), which
# is what actually loads.
scenario shadowed-verdict plugin-list-shadowed.json settings-green.json    marketplace-list-pinned.json  1 "installed 2.0.1, lockfile wants 2.1.0"
scenario shadowed-warn    plugin-list-shadowed.json settings-green.json    marketplace-list-pinned.json  1 "the project-scope record (2.0.1) is redundant"
# The caveat is load-bearing, not decoration: the spurious committed-settings diff is one of the
# two symptoms the ticket reports, so the uninstall must never be printed without its recovery.
scenario shadowed-caveat  plugin-list-shadowed.json settings-green.json    marketplace-list-pinned.json  1 "git checkout -- .claude/settings.json && git status"
# Severity, isolated. Both records at the wanted version, so there is no drift FAIL to hide
# behind: the redundancy WARN must still print AND the exit code must stay 0. A FAIL here would
# take every repo on a user-scope machine non-zero for a condition whose remediation edits a
# committed file.
scenario shadowed-warn-only plugin-list-shadowed-aligned.json settings-green.json marketplace-list-pinned.json 0 "the project-scope record (2.1.0) is redundant"
scenario ref-drift        plugin-list-green.json   settings-ref-drift.json marketplace-list-pinned.json  1 "settings ref (v9.8.0) and lockfile ref (v9.9.0) disagree"
scenario refless-shadow   plugin-list-green.json   settings-green.json     marketplace-list-refless.json 0 "ref-less"
# canary form: lockfile pins "latest" → presence-only; a DRIFTED install (behind fixture)
# must still be green — version comparison is skipped by definition.
scenario latest-lock      plugin-list-behind.json  settings-green.json     marketplace-list-pinned.json  0 "lockfile tracks latest" lock-latest.json
# WARN-only scenarios (exit stays 0): shadow skill + opt-out.
# Extra files are pre-created under $TMP/<label> BEFORE the scenario call
# (scenario's mkdir -p tolerates the existing tree). The shadow uses the REAL
# colliding name: dev-pipeline ships skills/run.
mkdir -p "$TMP/shadow-skill/.claude/skills/run"
scenario shadow-skill     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "shadows plugin-shipped"
# An opt-out is informational for every plugin: audit-toolkit off with dev-pipeline on (both
# fixtures leave it on) warns and exits 0, since nothing in the lane reads the audit ledger.
mkdir -p "$TMP/opt-out/.claude"; cp "$FIX/settings-optout.local.json" "$TMP/opt-out/.claude/settings.local.json"
scenario opt-out          plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "audit-toolkit disabled in settings.local.json — you're opting out"
# ...and the SAME flip in the COMMITTED settings.json — the file onboard writes and therefore
# where a hand edit actually lands; a scan of the local/user pair alone says nothing here.
scenario opt-out-committed plugin-list-green.json  settings-optout-committed.json marketplace-list-pinned.json 0 "audit-toolkit disabled in settings.json — you're opting out"
# --- config grill ---------------------------------------------------------------------------
# A grill finding is ADVISORY: it prints as a WARN with its proposal and must NOT move the exit
# code — the config has no key to declare a deliberate opt-out in, so a FAIL would hold a repo
# non-zero forever. Vehicle: T4.design-liverender. The fixture config sets design.provider with
# no liveRender, over a fixture root that is not a git work tree — the check's "outside a
# readable work tree the finding stands" branch fires unconditionally there.
scenario grill-finding    plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "WARN  config grill [T4.design-liverender]" lock-v1.json config-grill-finding.json
# ...and the clean counterpart, so the WARN above is not a constant.
scenario grill-clean      plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "config grill: no findings"
# A notEvaluated entry is NOT a finding: no proposal. It renders as a note. The doctor fixture
# root is not a git work tree, so the trigger-2 check lands here by construction.
scenario grill-noteval    plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "config grill not evaluated [T2.webComponentGlobs]"
# The two DEGRADE branches. Neither can produce a wrong verdict — both are `warn`, so neither
# moves the exit code — and that is exactly why they need pinning: a broken integration reads
# as green, and the scenarios above all run the real checker successfully, so nothing else here
# would notice if either branch stopped saying anything at all.
printf '#!/usr/bin/env bash\nexit 9\n' > "$TMP/grill-broken.sh"
scenario grill-degraded-rc      plugin-list-green.json settings-green.json marketplace-list-pinned.json 0 \
  "config grill could not run against" lock-v1.json config-valid.json "$TMP/grill-broken.sh"
scenario grill-degraded-missing plugin-list-green.json settings-green.json marketplace-list-pinned.json 0 \
  "config-grill.sh not found next to doctor" lock-v1.json config-valid.json "$TMP/no-such-grill.sh"

# --- keys configVersion 3 removed ------------------------------------------------------------
# Each removed key is its own FAIL naming the key and the migration doc, independently of
# config-lint (which the stub above always passes, so every FAIL here is doctor's own). The
# fixture carries all seven plus configVersion 2: eight FAILs, one per edit.
for want in "configVersion is 2" "config: topology was removed in configVersion 3" \
            "config: gates was removed" "move webComponentGlobs to reviewers.webComponentGlobs" \
            "config: grillWaivers was removed" "config: design.liveRender.tolerancePx was removed" \
            "config: design.liveRender.cwd was removed" "config: commands.app.lintAutofixes was removed" \
            "docs/migrations/v2-to-v3.md"; do
  scenario "stale-key: $want" plugin-list-green.json settings-green.json marketplace-list-pinned.json 8 "$want" lock-v1.json config-v2-stale.json
done

# --- consumer CI from the retired verdict-record lane ---------------------------------------
# An installed evidence workflow / delta guard reads a record the lane no longer writes: one FAIL
# for the set, naming every file. The unclaim pair is current and must stay silent.
mkdir -p "$TMP/stale-ci/.github/workflows" "$TMP/stale-ci/.claude/tools"
: > "$TMP/stale-ci/.github/workflows/second-shift-ci.yml"
: > "$TMP/stale-ci/.claude/tools/second-shift-delta-guard.sh"
scenario stale-ci         plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 ".github/workflows/second-shift-ci.yml .claude/tools/second-shift-delta-guard.sh"
# A LANE_VERDICT_SUFFIX reference in the consumer's OWN workflow is the same staleness under a
# name doctor cannot guess.
mkdir -p "$TMP/stale-suffix/.github/workflows"
printf 'env:\n  LANE_VERDICT_SUFFIX: -verdict.md\n' > "$TMP/stale-suffix/.github/workflows/ci.yml"
scenario stale-suffix     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "stale second-shift CI from the retired verdict-record lane: .github/workflows/ci.yml"
# A nested checkout under .claude/worktrees is another branch's tree, not this repo's install.
mkdir -p "$TMP/stale-nested/.claude/worktrees/x/.claude/tools"
printf 'LANE_VERDICT_SUFFIX=-verdict.md\n' > "$TMP/stale-nested/.claude/worktrees/x/.claude/tools/second-shift-delta-guard.sh"
scenario stale-nested     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "summary: 0 failed"
mkdir -p "$TMP/unclaim-kept/.github/workflows"
: > "$TMP/unclaim-kept/.github/workflows/second-shift-unclaim.yml"
scenario unclaim-kept     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "summary: 0 failed"

# A config that is not JSON is named as such, not left to degrade into silent 7.x reads.
scenario config-malformed plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "is not valid JSON" lock-v1.json config-malformed.txt

# --report bundle: sections present (incl. the nested check run's summary) + exit 0.
report report-sections    config-valid.json
# --report redaction: secret-shaped keys masked, non-secret identifier preserved.
report report-redaction   config-with-secret.json  "***REDACTED***" "119943793" "SUPER_SECRET_VALUE"
# --report state excerpt. A detached run's log is preferred over a foreground run's directory —
# keyed on the CLASS, not on mtime: the log here is deliberately the OLDER entry, so selecting by
# mtime alone lists the directory and reds this case. The tail carries the terminal slug.
lroot="$TMP/report-run"; mkdir -p "$lroot/.claude/pipeline-state/run-77/20260101T000000Z-1"
cp "$FIX/lock-v1.json" "$lroot/.claude/second-shift.lock.json"
cp "$FIX/config-valid.json" "$lroot/.claude/second-shift.config.json"
sed -e "s#__ROOT__#$lroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/settings-green.json" > "$lroot/.claude/settings.json"
sed -e "s#__ROOT__#$lroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/plugin-list-green.json" > "$TMP/report-run-pluglist.json"
: > "$lroot/.claude/pipeline-state/run-77/20260101T000000Z-1/checks-1.1.log"
{ printf '2026-01-02T03:04:05Z [run] terminal: checks-red-spent — run-era-abort-reason
'
  printf 'terminal: checks-red-spent
'; } > "$lroot/.claude/pipeline-state/88-lean-run-20260102T030405Z-1.log"
touch -t 202001010000 "$lroot/.claude/pipeline-state/88-lean-run-20260102T030405Z-1.log"  # OLDER than the run dir
run_report() { DOCTOR_REPO_ROOT="$lroot" DOCTOR_PLUGIN_LIST_FILE="$TMP/report-run-pluglist.json" \
  DOCTOR_MARKETPLACE_LIST_FILE="$FIX/marketplace-list-pinned.json" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
  bash "$DOCTOR" --report 2>&1; }
lout="$(run_report)"
if grep -qF "run-era-abort-reason" <<< "$lout" \
   && grep -qF "88-lean-run-20260102T030405Z-1.log" <<< "$lout" \
   && ! grep -qF "checks-1.1.log" <<< "$lout" \
   && ! grep -qF "no pipeline runs recorded" <<< "$lout"; then check "report-state-excerpt-log-preferred" 0
else check "report-state-excerpt-log-preferred" 1; echo "$lout" | sed 's/^/      /' | head -20; fi

# ...and WITHIN the log class, newest wins. THE NEWER FILE MUST SORT BEFORE THE OLDER ONE: a
# flipped emptiness test in the -nt accumulator degenerates it into "take the LAST entry in glob
# order", which a newer file sorting last would satisfy by coincidence.
printf 'newer-run-marker
' > "$lroot/.claude/pipeline-state/11-lean-run-20260202T030405Z-1.log"
lout2="$(run_report)"
if grep -qF "newer-run-marker" <<< "$lout2" \
   && ! grep -qF "run-era-abort-reason" <<< "$lout2"; then check "report-state-excerpt-log-newest" 0
else check "report-state-excerpt-log-newest" 1; echo "$lout2" | sed 's/^/      /' | head -20; fi

# A foreground run leaves no log — only its run directory, whose listing is the excerpt.
rm -f "$lroot"/.claude/pipeline-state/*-lean-run-*.log
lout3="$(run_report)"
if grep -qF "run-77/20260101T000000Z-1" <<< "$lout3" \
   && grep -qF "checks-1.1.log" <<< "$lout3"; then check "report-state-excerpt-run-dir" 0
else check "report-state-excerpt-run-dir" 1; echo "$lout3" | sed 's/^/      /' | head -20; fi

# --report context-coverage section: resolved (real review-toolkit) emits a coverage line;
# unresolved (env empty + fake-cache pluglist install path has no script) emits the fallback.
RT_REAL="$(resolve_sibling_plugin_root "$HERE/../../.." review-toolkit scripts || true)"
# A miss here used to be invisible: the "resolved" scenario below simply degraded into the
# unresolved one and failed with a message about the fallback line, naming the symptom rather
# than the cause. Assert the resolution itself so the failure says what actually broke.
[[ -n "$RT_REAL" ]] && check "review-toolkit sibling root resolved" 0 \
  || check "review-toolkit sibling root resolved (looked under $HERE/../../../../ and ../../../../../<ver>/)" 1
ccroot="$TMP/cc"; mkdir -p "$ccroot/.claude/second-shift"
cp "$FIX/lock-v1.json" "$ccroot/.claude/second-shift.lock.json"
cp "$FIX/config-valid.json" "$ccroot/.claude/second-shift.config.json"
sed -e "s#__ROOT__#$ccroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/settings-green.json" > "$ccroot/.claude/settings.json"
sed -e "s#__ROOT__#$ccroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/plugin-list-green.json" > "$TMP/cc-pluglist.json"
printf '# Review context — cc\n\n## Stack\nNext.js + Postgres.\n' > "$ccroot/.claude/second-shift/review-context.md"
ccenv=(DOCTOR_REPO_ROOT="$ccroot" DOCTOR_PLUGIN_LIST_FILE="$TMP/cc-pluglist.json"
       DOCTOR_MARKETPLACE_LIST_FILE="$FIX/marketplace-list-pinned.json" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json")
ccout="$(env "${ccenv[@]}" SECOND_SHIFT_REVIEW_TOOLKIT_ROOT="$RT_REAL" bash "$DOCTOR" --report 2>&1)" || true
grep -q "context-coverage:" <<< "$ccout" && check "context-coverage resolved -> coverage line" 0 \
  || { check "context-coverage resolved -> coverage line" 1; echo "$ccout" | grep -A2 'context coverage' | sed 's/^/      /'; }
ccout2="$(env "${ccenv[@]}" SECOND_SHIFT_REVIEW_TOOLKIT_ROOT="" bash "$DOCTOR" --report 2>&1)" || true
grep -q "review-toolkit not resolved" <<< "$ccout2" && check "context-coverage unresolved -> fallback line" 0 \
  || { check "context-coverage unresolved -> fallback line" 1; echo "$ccout2" | grep -A2 'context coverage' | sed 's/^/      /'; }

if [[ "$FAILS" -gt 0 ]]; then echo "doctor selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "doctor selftest: all green"
