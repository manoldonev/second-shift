#!/usr/bin/env bash
# doctor-selftest.sh — hermetic selftest for doctor.sh (no claude binary, no network).
# All data sources are env-injected files; the install tree is a fake cache under mktemp.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$HERE/doctor.sh"; FIX="$HERE/doctor-fixtures"; FAILS=0
check() { if [[ "$2" -eq 0 ]]; then echo "  ✓ $1"; else echo "  ✗ $1"; FAILS=$((FAILS+1)); fi; }
scenario() { # $1 label, $2 plugin-list fixture, $3 settings fixture, $4 marketplace fixture,
             # $5 expected exit code, $6 expected substring in output,
             # $7 (optional) lock fixture — default lock-v1.json
  local root="$TMP/$1"; mkdir -p "$root/.claude"
  cp "$FIX/${7:-lock-v1.json}" "$root/.claude/second-shift.lock.json"
  cp "$FIX/config-valid.json" "$root/.claude/second-shift.config.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/$3" > "$root/.claude/settings.json"
  sed -e "s#__ROOT__#$root#g" -e "s#__INSTALL__#$INSTALL#g" "$FIX/$2" > "$TMP/$1-pluglist.json"
  local out rc=0
  out="$(DOCTOR_REPO_ROOT="$root" DOCTOR_PLUGIN_LIST_FILE="$TMP/$1-pluglist.json" \
         DOCTOR_MARKETPLACE_LIST_FILE="$FIX/$4" DOCTOR_USER_SETTINGS="$TMP/empty-user-settings.json" \
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
  # Every bundle carries the four sections + the nested check run's summary line.
  for want in "### doctor output" "### claude plugin list --json" "### redacted config" "### pipeline-state excerpt" "[doctor] summary:"; do
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
scenario version-behind   plugin-list-behind.json  settings-green.json     marketplace-list-pinned.json  1 "claude plugin marketplace update second-shift"
scenario version-ahead    plugin-list-ahead.json   settings-green.json     marketplace-list-pinned.json  1 "ahead of the lockfile"
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
mkdir -p "$TMP/opt-out/.claude"; cp "$FIX/settings-optout.local.json" "$TMP/opt-out/.claude/settings.local.json"
scenario opt-out          plugin-list-green.json   settings-green.json     marketplace-list-pinned.json  0 "audit-toolkit"
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
if [[ "$FAILS" -gt 0 ]]; then echo "doctor selftest: $FAILS FAILURE(S)"; exit 1; fi
echo "doctor selftest: all green"
