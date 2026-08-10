#!/usr/bin/env bash
# doctor-selftest.sh — hermetic selftest for doctor.sh (no claude binary, no network).
# All data sources are env-injected files; the install tree is a fake cache under mktemp.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$HERE/doctor.sh"; FIX="$HERE/doctor-fixtures"; FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }

# --- cross-plugin sibling resolution -------------------------------------------------------
# This suite reaches two OTHER plugins: review-toolkit (as a root, to feed
# SECOND_SHIFT_REVIEW_TOOLKIT_ROOT) and dev-pipeline's claims-lint.sh (as one named file). Both
# used to be a fixed `$HERE/../../../../<name>` hop count, which holds only in the monorepo:
# installed, this file lives at <cache>/<marketplace>/second-shift/<version>/skills/doctor/tools
# and the same expression resolves to nothing — so the "resolved" scenario silently degraded
# into the unresolved one, and the claims-lint scenarios silently did not run at all.
#
# Both ladders run the house three rungs: monorepo path -> cache sibling at THIS plugin's own
# version -> newest cache version carrying the marker. The last rung is load-bearing, not a
# fallback: plugins are versioned independently, so a real install rarely has the sibling at
# this plugin's version.
#
# HOP CONSTANTS ARE RE-DERIVED, NOT COPIED. skills/doctor/tools sits three levels under the
# plugin root, so the plugins dir is four hops up and the marketplace root five —
# check-model-tiers.sh's copy, one level under its plugin root, uses two and three.
#
# Newest-version selection is LEXICAL, mirroring both house ladders (`9.0.0` outranks
# `10.0.0`). A shared latent defect, deliberately mirrored rather than fixed here.
#
# NEITHER LADDER HAS A SKIP RUNG. An unresolvable sibling is the defect these exist to remove,
# so each caller below turns a miss into a COUNTED failure.

# resolve_sibling_plugin_root <anchor-dir> <name> <marker-subpath> — echoes the sibling plugin
# ROOT. The anchor is a PARAMETER rather than a read of this file's own directory variable:
# that was the only thing separating this copy from preflight-selftest.sh's, whose hop
# constants are identical, and passing it in makes the two blocks byte-identical so
# scripts/lockstep-manifest.tsv can pin them instead of leaving them held by prose.
# LOCKSTEP-BEGIN cross-plugin-sibling-plugin-root
resolve_sibling_plugin_root() {
  local anchor="$1" name="$2" marker="$3" cand
  cand="$(cd "$anchor/../../../../$name" 2>/dev/null && pwd)" || cand=""
  if [[ -n "$cand" && -d "$cand/$marker" ]]; then printf '%s\n' "$cand"; return 0; fi
  for cand in "$anchor"/../../../../../"$name"/*/; do
    [[ -d "$cand/$marker" ]] || continue
    (cd "$cand" && pwd)
  done | tail -1
}
# LOCKSTEP-END cross-plugin-sibling-plugin-root

# resolve_sibling_file <name> <path-under-that-plugin> — echoes the named FILE, rc=1 if absent.
resolve_sibling_file() {
  local sib="$1" rel="$2" cand v cacheroot myver
  cand="$HERE/../../../../$sib/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  cacheroot="$(cd "$HERE/../../../../.." 2>/dev/null && pwd)" || return 1
  myver="$(basename "$(cd "$HERE/../../.." 2>/dev/null && pwd)")"
  cand="$cacheroot/$sib/$myver/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  # shellcheck disable=SC2012  # version dirs are alphanumeric (X.Y.Z); ls is safe and 3.2-portable here
  for v in $(ls -1 "$cacheroot/$sib" 2>/dev/null | sort -r); do
    cand="$cacheroot/$sib/$v/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
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
# Fake install tree mirroring the v2 cache layout. Skill dir names are the REAL
# v2 plugin skill names (dev-pipeline ships skills/run — the shadow scan compares
# against these basenames).
INSTALL="$TMP/cache"
mkdir -p "$INSTALL/dev-pipeline/2.1.0/skills/run/tools" \
         "$INSTALL/review-toolkit/2.0.2/skills/review-lead" \
         "$INSTALL/intake-toolkit/2.0.0/skills/intake" \
         "$INSTALL/audit-toolkit/2.0.0/skills/audit" \
         "$INSTALL/second-shift/1.0.0/skills/onboard" \
         "$INSTALL/second-shift/1.0.0/skills/doctor"
# shellcheck disable=SC2016 # emitting a literal stub script — $1 must not expand here
printf '#!/usr/bin/env bash\necho "config-lint: OK ($1)"\n' > "$INSTALL/dev-pipeline/2.1.0/skills/run/tools/config-lint.sh"

echo "doctor selftest:"
scenario green            plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "summary: 0 failed"
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
# colliding name: dev-pipeline ships skills/run in v2.
mkdir -p "$TMP/shadow-skill/.claude/skills/run"
scenario shadow-skill     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "shadows plugin-shipped"
# #416/D-7: `audit-toolkit` off WHILE `dev-pipeline` is on is not an opt-out, it is a broken
# lean lane — its entry gate refuses to start without the ledger audit-toolkit's hook writes.
# This scenario asserted exit 0 until that landed; it is re-keyed, not deleted, because the
# combination it fixtures is exactly the one that produced two unattested merged runs.
mkdir -p "$TMP/opt-out/.claude"; cp "$FIX/settings-optout.local.json" "$TMP/opt-out/.claude/settings.local.json"
scenario opt-out          plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "while dev-pipeline is enabled"
# ...and the branch D-7 PRESERVES, which a single re-keyed scenario would have left untested:
# with dev-pipeline off too, there is no lane to protect and the informational warn stands.
# `false` in settings.local.json overrides the `true` settings-green.json declares, which is
# also what pins the precedence half of the predicate.
mkdir -p "$TMP/opt-out-lane-off/.claude"; cp "$FIX/settings-optout-lane-off.local.json" "$TMP/opt-out-lane-off/.claude/settings.local.json"
scenario opt-out-lane-off plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "you're opting out of its capabilities"
# ...and the SAME flip in the COMMITTED settings.json — the file onboard writes and therefore
# where a hand edit actually lands. Only the file moved: the scan read the local/user pair
# alone, so this combination exited 0 with no FAIL and no warn while the identical fixture
# above FAILed. A scenario keyed only to settings.local.json cannot tell those apart, which is
# how three shipped statements came to promise a catch that did not happen here.
scenario opt-out-committed plugin-list-green.json  settings-optout-committed.json marketplace-list-pinned.json 1 "while dev-pipeline is enabled"
# --- config grill (#441) -------------------------------------------------------------------
# A grill finding is a FAIL like every other doctor FAIL, so it must move the EXIT CODE, not
# just the text — that pairing is the whole point of D-15 and the only reason waivers have to
# exist. The fixture config sets unitTestScope, which declares mutation intent, over a fixture
# root carrying no tools/mutation-sweep.sh — coverage the config asks for and the repo cannot run.
scenario grill-finding    plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "config grill [T4.mutation-plumbing.app]" lock-v1.json config-grill-finding.json
# ...and the waived counterpart, which is what keeps a clean report REACHABLE. config-valid.json
# carries the `grillWaivers` entry for the finding its own shape would otherwise produce
# (gates.mutation absent is NOT false, so mutation reads ON over a root with no sweep). Without
# this branch the check could be suppress-everything and still pass the scenario above.
scenario grill-waived     plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "config grill: no unwaived findings"
# A notEvaluated entry is NOT a finding: no proposal, not waivable. It must render
# informationally and never touch the exit code — riding in findings[] would make a repo
# permanently non-zero with nothing it could do about it. The doctor fixture root is not a git
# work tree, so the two trigger-2 checks land here by construction.
scenario grill-noteval    plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "config grill not evaluated [T2.webComponentGlobs]"
# #449: an `unadopted` entry is the THIRD severity. It is waivable and carries a proposal, so
# unlike notEvaluated it can force a disposition — but here it must render as a NOTE and leave
# the exit code at 0. The pairing is the whole of the severity split: config-valid.json adopts
# none of the three seams, so a `bad` would take every already-green consumer non-zero on the
# first run after this ships, for a capability most will never want. Asserting the TEXT alone
# would pass just as happily on a FAIL, which is why the expected rc is 0 and the fixture
# deliberately carries no waiver for T1. The fixture's `test` lane with no repo-carried sweep
# adds a second note on the same severity, which is the point of the tier: an advisory keyed on
# durable config outlives the keys the paired FAIL is phrased in.
scenario grill-unadopted  plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "config grill unadopted [T1.extension-points]"
# ...and the waived counterpart, which is what proves the note is suppressible at all rather
# than unconditional prose: without it, "renders a note" and "always renders a note" are the
# same observation.
scenario grill-unadopted-waived plugin-list-green.json settings-green.json marketplace-list-pinned.json 0 \
  "summary: 0 failed" lock-v1.json config-t1-waived.json
uwout="$(DOCTOR_REPO_ROOT="$TMP/grill-unadopted-waived" DOCTOR_PLUGIN_LIST_FILE="$TMP/grill-unadopted-waived-pluglist.json" \
         DOCTOR_MARKETPLACE_LIST_FILE="$FIX/marketplace-list-pinned.json" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
         bash "$DOCTOR" 2>&1)" || true
if grep -qF "T1.extension-points" <<< "$uwout"; then
  check "grill-unadopted-waived: the waived entry is actually absent from the output" 1
  echo "$uwout" | grep -F "T1." | sed 's/^/      /' | head -3
else
  check "grill-unadopted-waived: the waived entry is actually absent from the output" 0
fi
# The two DEGRADE branches. Neither can produce a wrong verdict — both are `warn`, so neither
# moves the exit code — and that is exactly why they need pinning: a broken integration reads
# as green, and the three scenarios above all run the real checker successfully, so nothing
# else here would notice if either branch stopped saying anything at all.
printf '#!/usr/bin/env bash\nexit 9\n' > "$TMP/grill-broken.sh"
scenario grill-degraded-rc      plugin-list-green.json settings-green.json marketplace-list-pinned.json 0 \
  "config grill could not run against" lock-v1.json config-valid.json "$TMP/grill-broken.sh"
scenario grill-degraded-missing plugin-list-green.json settings-green.json marketplace-list-pinned.json 0 \
  "config-grill.sh not found next to doctor" lock-v1.json config-valid.json "$TMP/no-such-grill.sh"

# --report bundle: sections present (incl. the nested check run's summary) + exit 0.
report report-sections    config-valid.json
# --report redaction: secret-shaped keys masked, non-secret identifier preserved.
report report-redaction   config-with-secret.json  "***REDACTED***" "119943793" "SUPER_SECRET_VALUE"
# --report state excerpt (populated pipeline-state dir): the NEWEST run's failureContext
# surfaces; the older run does not. Exercises state_excerpt()'s -nt selection + jq extraction
# (the empty-dir branch is covered by the two scenarios above).
sroot="$TMP/report-state"; mkdir -p "$sroot/.claude/pipeline-state"
cp "$FIX/lock-v1.json" "$sroot/.claude/second-shift.lock.json"
cp "$FIX/config-valid.json" "$sroot/.claude/second-shift.config.json"
sed -e "s#__ROOT__#$sroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/settings-green.json" > "$sroot/.claude/settings.json"
sed -e "s#__ROOT__#$sroot#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/plugin-list-green.json" > "$TMP/report-state-pluglist.json"
printf '{"ticketKey":"7","status":"completed","currentStage":10,"failureContext":null}\n'  > "$sroot/.claude/pipeline-state/7.json"
printf '{"ticketKey":"42","status":"failed","currentStage":6,"failureContext":{"stage":6,"reason":"approach-failure-circuit-breaker"}}\n' > "$sroot/.claude/pipeline-state/42.json"
touch -t 202001010000 "$sroot/.claude/pipeline-state/7.json"   # force 7 older ⇒ 42 is newest, deterministically
sout="$(DOCTOR_REPO_ROOT="$sroot" DOCTOR_PLUGIN_LIST_FILE="$TMP/report-state-pluglist.json" \
        DOCTOR_MARKETPLACE_LIST_FILE="$FIX/marketplace-list-pinned.json" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
        bash "$DOCTOR" --report 2>&1)"
if grep -qF "approach-failure-circuit-breaker" <<< "$sout" \
   && grep -qF '"ticketKey": "42"' <<< "$sout" \
   && ! grep -qF "no pipeline runs recorded" <<< "$sout"; then check "report-state-excerpt" 0
else check "report-state-excerpt" 1; echo "$sout" | sed 's/^/      /' | head -20; fi

# --report context-coverage section: resolved (real review-toolkit) emits a coverage line;
# unresolved (env empty + fake-cache pluglist install path has no script) emits the fallback.
RT_REAL="$(resolve_sibling_plugin_root "$HERE" review-toolkit scripts || true)"
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

# Verified calibration claims quiet line (#68): the REAL claims-lint.sh (sibling
# plugin in this repo checkout) is copied into the fake tree — invoke-not-duplicate,
# same posture as the config-lint stub above. Runs AFTER the scenarios above so the
# copy cannot alter their claims-free expectations.
REAL_CLAIMS="$(resolve_sibling_file dev-pipeline skills/run/tools/claims-lint.sh || true)"
if [[ -n "$REAL_CLAIMS" ]]; then
  cp "$REAL_CLAIMS" "$INSTALL/dev-pipeline/2.1.0/skills/run/tools/claims-lint.sh"
  mkdir -p "$TMP/claims-ok/.claude/second-shift"
  # shellcheck disable=SC2016 # literal fence content — backticks must not expand
  printf -- '```second-shift-claims\n- id: no-auth-system\n  claim: "fixture claim"\n  reverify-by: 9999-12-31\n```\n' \
    > "$TMP/claims-ok/.claude/second-shift/review-context.md"
  scenario claims-ok      plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "claims-lint: 1 claim(s)"
  mkdir -p "$TMP/claims-expired/.claude/second-shift"
  # shellcheck disable=SC2016 # literal fence content — backticks must not expand
  printf -- '```second-shift-claims\n- id: no-auth-system\n  claim: "fixture claim"\n  reverify-by: 2020-01-01\n```\n' \
    > "$TMP/claims-expired/.claude/second-shift/review-context.md"
  scenario claims-expired plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  1 "expired or malformed severity-downgrading claim"
else
  # Was an uncounted `echo … skipped`. That print is how these two scenarios ran nowhere but
  # the monorepo while the suite reported all green — a miss laundered into a skip. It is a
  # counted failure now, through the same check/FAILS tally every other scenario uses.
  check "claims-lint sibling resolved (dev-pipeline skills/run/tools/claims-lint.sh) — claims-lint scenarios did NOT run" 1
fi
if [[ "$FAILS" -gt 0 ]]; then echo "doctor selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "doctor selftest: all green"
