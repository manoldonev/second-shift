#!/usr/bin/env bash
# doctor.sh — /second-shift:doctor: verify this repo's second-shift INSTALL/CONFIG state
# against the committed lockfile. Complements dev-pipeline's pipeline-doctor.sh (which
# checks the pipeline RUNTIME environment); this one answers "is the toolkit actually
# here, at the pinned versions, unshadowed?".
# Exit code = number of FAILs; WARNs are informational. Every FAIL prints its remediation.
# Env injection (selftest): DOCTOR_REPO_ROOT, DOCTOR_PLUGIN_LIST_FILE,
# DOCTOR_MARKETPLACE_LIST_FILE, DOCTOR_USER_SETTINGS.
set -uo pipefail

# --- arg parsing ----------------------------------------------------------
# Default (no args) = the install/config verification below; exit code = FAILs.
# --report = assemble a paste-ready feedback bundle (see emit_report); exit 0.
REPORT_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) REPORT_MODE=1; shift ;;
    -h|--help)
      echo "usage: doctor.sh [--report]"
      echo "  (no args)  verify install/config state against the lockfile; exit code = number of FAILs"
      echo "  --report   assemble a paste-ready feedback bundle (doctor output + claude plugin list --json"
      echo "             + redacted config + newest pipeline-state excerpt) for a feedback issue; exit 0"
      exit 0 ;;
    *) echo "[doctor] unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

ROOT="${DOCTOR_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOCK="$ROOT/.claude/second-shift.lock.json"
SETTINGS="$ROOT/.claude/settings.json"
LOCAL_SETTINGS="$ROOT/.claude/settings.local.json"
USER_SETTINGS="${DOCTOR_USER_SETTINGS:-$HOME/.claude/settings.json}"
MKT="second-shift"
FAILS=0
ok()   { echo "[doctor] OK    $1"; }
warn() { echo "[doctor] WARN  $1"; }
bad()  { echo "[doctor] FAIL  $1"; FAILS=$((FAILS+1)); }

# --- report mode (--report): assemble a paste-ready feedback bundle -----------
# For a zero-telemetry project, structured issues ARE the analytics. This mode
# gathers the evidence the feedback issue forms ask for in one command, so a filer
# never hand-assembles (and never pastes an UNredacted config). It never gates:
# it captures the normal check run's output but always exits 0.

# Redact secret-SHAPED keys (best-effort, defensive — the config carries no true
# secret today). Matches on the KEY name, so non-secret identifiers (clientId,
# appName, installationId) are preserved while a future token/secret/password is
# masked. jq `walk` handles nested objects (e.g. tracker.bot.app).
redact_config() { # $1 = config path
  jq 'walk(
        if type == "object" then
          with_entries(
            if (.key | ascii_downcase
                 | test("secret|token|password|passwd|passphrase|privatekey|apikey|accesskey|signingkey|authorization|bearer|pem|credential"))
            then .value = "***REDACTED***" else . end)
        else . end)' "$1" 2>/dev/null || echo "(config unreadable or invalid JSON)"
}

# Newest pipeline-state file → the abort-relevant fields. The "state-file excerpt"
# the feedback forms ask for is exactly the .failureContext statectl writes on a
# fail-fast abort. Guards the glob against literal-pattern expansion when the dir
# is empty/absent (a fresh clone has no runs).
state_excerpt() {
  local dir="$ROOT/.claude/pipeline-state" newest="" f
  if [[ -d "$dir" ]]; then
    for f in "$dir"/*.json; do
      [[ -e "$f" ]] || continue                       # no-match glob → skip
      [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
    done
  fi
  if [[ -n "$newest" ]]; then
    echo "// $(basename "$newest")"
    jq '{ticketKey, status, currentStage, failureContext}' "$newest" 2>/dev/null \
      || echo "(state file unreadable or invalid JSON)"
  else
    echo "no pipeline runs recorded (.claude/pipeline-state/ is empty or absent)"
  fi
}

emit_report() {
  local conf="$ROOT/.claude/second-shift.config.json" pluglist
  if [[ -n "${DOCTOR_PLUGIN_LIST_FILE:-}" ]]; then pluglist="$(cat "$DOCTOR_PLUGIN_LIST_FILE")"
  else pluglist="$(claude plugin list --json 2>/dev/null)" || pluglist="[]"; fi

  echo "## second-shift feedback report"
  echo
  echo "Paste this whole block into your feedback issue. Sensitive-shaped config values are auto-redacted — review before posting."
  echo
  echo "### doctor output"
  echo '```'
  bash "$0" 2>&1 || true          # nested no-arg run: the normal checks (inherits DOCTOR_* injections)
  echo '```'
  echo
  echo "### claude plugin list --json"
  echo '```json'
  echo "$pluglist"
  echo '```'
  echo
  echo "### redacted config (.claude/second-shift.config.json)"
  echo '```json'
  if [[ -f "$conf" ]]; then redact_config "$conf"; else echo "(no config found at $conf)"; fi
  echo '```'
  echo
  echo "### pipeline-state excerpt (newest run)"
  echo '```json'
  state_excerpt
  echo '```'
}

if [[ "$REPORT_MODE" -eq 1 ]]; then emit_report; exit 0; fi

# --- 0. prerequisites -----------------------------------------------------
for dep in jq git; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep present" || bad "$dep missing — install it first"
done
# `claude` is only a hard dep when we must ASK it for data; with injected data
# files (selftest/CI — no claude binary on runners) its absence is not a failure.
if command -v claude >/dev/null 2>&1; then ok "claude present"
elif [[ -n "${DOCTOR_PLUGIN_LIST_FILE:-}" ]]; then ok "claude not needed (injected data)"
else bad "claude missing — doctor needs 'claude plugin list --json'"; fi
command -v gh >/dev/null 2>&1 && ok "gh present" || warn "gh missing — fine for doctor, required by onboard/pipeline"

# --- data sources ----------------------------------------------------------
if [[ -n "${DOCTOR_PLUGIN_LIST_FILE:-}" ]]; then PLUGLIST="$(cat "$DOCTOR_PLUGIN_LIST_FILE")"
else PLUGLIST="$(claude plugin list --json 2>/dev/null)" || PLUGLIST="[]"; fi
# Marketplace registrations: JSON is the primary source (claude plugin marketplace
# list --json → [{name, source, repo, ref?, installLocation}]; ref omitted when
# ref-less). Text output is kept ONLY as a runtime fallback if --json errors.
if [[ -n "${DOCTOR_MARKETPLACE_LIST_FILE:-}" ]]; then MKTLIST="$(cat "$DOCTOR_MARKETPLACE_LIST_FILE")"
else MKTLIST="$(claude plugin marketplace list --json 2>/dev/null)" \
  || MKTLIST="$(claude plugin marketplace list 2>/dev/null)" || MKTLIST=""; fi

# --- 1. lockfile + settings presence ---------------------------------------
[[ -f "$LOCK" ]] && jq empty "$LOCK" 2>/dev/null \
  && ok "lockfile present + parses" \
  || { bad "no valid $LOCK — run /second-shift:onboard (it writes the lockfile)"; echo "[doctor] summary: $FAILS failed check(s)"; exit "$FAILS"; }
SETTINGS_OK=0
if [[ -f "$SETTINGS" ]]; then SETTINGS_OK=1; ok "project settings present"
else bad "no $SETTINGS — run /second-shift:onboard"; fi

LOCK_REF="$(jq -r '.marketplace.ref // ""' "$LOCK")"
SET_REF=""
[[ "$SETTINGS_OK" -eq 1 ]] && SET_REF="$(jq -r --arg m "$MKT" '.extraKnownMarketplaces[$m].source.ref // ""' "$SETTINGS" 2>/dev/null)"

# --- 2. settings ref ↔ lockfile ref lockstep (skip when settings missing:
#        one root cause, one FAIL — the exit code is a count of distinct problems) ---
if [[ "$SETTINGS_OK" -eq 1 ]]; then
  if [[ -n "$SET_REF" && "$SET_REF" == "$LOCK_REF" ]]; then ok "settings ref == lockfile ref ($LOCK_REF)"
  elif [[ -z "$SET_REF" ]]; then bad "settings has no marketplace ref pin — re-run /second-shift:onboard (or add \"ref\": \"$LOCK_REF\")"
  else bad "settings ref ($SET_REF) and lockfile ref ($LOCK_REF) disagree — a half-done upgrade; make one PR carry both (fix: align settings + lockfile, then claude plugin marketplace update $MKT)"
  fi
fi

# --- 3. per-plugin install state vs lockfile ---------------------------------
NEED_RESTART=0
semver_lt() { # $1 < $2 ?
  [[ "$1" == "$2" ]] && return 1
  local first; first="$(printf '%s\n%s\n' "${1#v}" "${2#v}" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
  [[ "$first" == "${1#v}" ]]
}
for p in $(jq -r '.plugins | keys[]' "$LOCK"); do
  want="$(jq -r --arg p "$p" '.plugins[$p]' "$LOCK")"
  entry="$(jq -c --arg id "$p@$MKT" --arg root "$ROOT" \
    '[.[] | select(.id==$id and ((.projectPath // "") == $root or .scope=="user" or .scope=="local"))] | sort_by(.lastUpdated // "") | last // empty' <<< "$PLUGLIST")"
  if [[ -z "$entry" ]]; then
    enabled_in_settings=false
    [[ "$SETTINGS_OK" -eq 1 ]] && enabled_in_settings="$(jq -r --arg k "$p@$MKT" '.enabledPlugins[$k] // false' "$SETTINGS" 2>/dev/null)"
    if [[ "$enabled_in_settings" == "true" ]]; then
      bad "$p: enabled in project settings but NOT installed (fresh clone / skipped trust prompt — the most common state). Fix: claude plugin install $p@$MKT --scope project"
    else
      bad "$p: in the lockfile but neither installed nor enabled here. Fix: claude plugin install $p@$MKT --scope project"
    fi
    NEED_RESTART=1; continue
  fi
  have="$(jq -r '.version' <<< "$entry")"
  # "latest" = the canary form (the marketplace repo consuming itself, lockfile ref
  # "main"): presence-only — any installed version is correct by definition.
  if [[ "$want" == "latest" ]]; then ok "$p @ $have installed (lockfile tracks latest — canary)"; continue; fi
  if [[ "$have" == "$want" ]]; then ok "$p @ $want installed"
  elif semver_lt "$have" "$want"; then
    bad "$p: installed $have, lockfile wants $want. Fix: claude plugin marketplace update $MKT && claude plugin install $p@$MKT --scope project"; NEED_RESTART=1
  else
    bad "$p: installed $have is ahead of the lockfile ($want) — rollback case. Fix: claude plugin marketplace update $MKT (settings pin $LOCK_REF resolves the older catalog) && claude plugin install $p@$MKT --scope project"; NEED_RESTART=1
  fi
done

# --- 4. ref-less user-scope marketplace shadow --------------------------------
LOCK_REPO="$(jq -r '.marketplace.repo' "$LOCK")"
if jq -e 'type == "array"' <<< "$MKTLIST" >/dev/null 2>&1; then
  mkt_entry="$(jq -c --arg m "$MKT" '[.[] | select(.name==$m)] | last // empty' <<< "$MKTLIST")"
  if [[ -z "$mkt_entry" ]]; then
    warn "marketplace '$MKT' not found in claude plugin marketplace list — trust prompt skipped? Fix: claude plugin marketplace add $LOCK_REPO"
  else
    mkt_ref="$(jq -r '.ref // empty' <<< "$mkt_entry")"
    if [[ -n "$mkt_ref" ]]; then ok "marketplace registration carries a ref ($mkt_ref)"
    else warn "a ref-less registration of '$MKT' shadows the project pin ON THIS MACHINE (typical on the maintainer's machine). Teammates are protected by the project ref. To align: claude plugin marketplace remove $MKT && claude plugin marketplace add $LOCK_REPO — CAUTION: removing a marketplace from its last scope uninstalls ALL its plugins; reinstall right after"
    fi
  fi
else
  # text fallback (--json unavailable at runtime)
  if grep -q "($LOCK_REPO@" <<< "$MKTLIST"; then ok "marketplace registration carries a ref"
  elif grep -q "($LOCK_REPO)" <<< "$MKTLIST"; then
    warn "a ref-less registration of '$MKT' shadows the project pin ON THIS MACHINE (typical on the maintainer's machine). Teammates are protected by the project ref. To align: claude plugin marketplace remove $MKT && claude plugin marketplace add $LOCK_REPO — CAUTION: removing a marketplace from its last scope uninstalls ALL its plugins; reinstall right after"
  else
    warn "marketplace '$MKT' not found in claude plugin marketplace list — trust prompt skipped? Fix: claude plugin marketplace add $LOCK_REPO"
  fi
fi

# --- 5. shadow scan: repo-local names colliding with plugin-shipped names ------
for p in $(jq -r '.plugins | keys[]' "$LOCK"); do
  entry_path="$(jq -r --arg id "$p@$MKT" --arg root "$ROOT" \
    '[.[] | select(.id==$id and ((.projectPath // "") == $root or .scope=="user" or .scope=="local"))] | sort_by(.lastUpdated // "") | last | .installPath // empty' <<< "$PLUGLIST")"
  [[ -z "$entry_path" || ! -d "$entry_path" ]] && continue
  for sk in "$entry_path"/skills/*/; do
    [[ -d "$sk" ]] || continue
    name="$(basename "$sk")"
    if [[ -d "$ROOT/.claude/skills/$name" ]]; then
      warn "repo-local .claude/skills/$name shadows plugin-shipped $p:$name — deleting it MID-SESSION invalidates the skill registry; delete, commit, then START A FRESH SESSION (docs/namespaces.md)"
    fi
  done
  for ag in "$entry_path"/agents/*.md; do
    [[ -f "$ag" ]] || continue
    name="$(basename "$ag")"
    [[ -f "$ROOT/.claude/agents/$name" ]] && warn "repo-local .claude/agents/$name shadows plugin-shipped $p agent — same collision rules as skills"
  done
done
ok "shadow scan complete"

# --- 6. opt-out scan (informational, once, never shaming) ----------------------
for f in "$LOCAL_SETTINGS" "$USER_SETTINGS"; do
  [[ -f "$f" ]] || continue
  opted="$(jq -r --arg m "@$MKT" '(.enabledPlugins // {}) | to_entries[] | select(.value==false and (.key | endswith($m))) | .key' "$f" 2>/dev/null)"
  for k in $opted; do
    pname="${k%@*}"
    warn "$pname disabled in $(basename "$f") — you're opting out of its capabilities (see .claude/SECOND-SHIFT.md inventory). That's sanctioned; doctor won't mention it again this run."
  done
done

# --- 7. config-lint -------------------------------------------------------------
CONF="$ROOT/.claude/second-shift.config.json"
if [[ ! -f "$CONF" ]]; then
  bad "no $CONF — run /second-shift:onboard"
else
  DP_PATH="$(jq -r --arg id "dev-pipeline@$MKT" --arg root "$ROOT" \
    '[.[] | select(.id==$id and ((.projectPath // "") == $root or .scope=="user" or .scope=="local"))] | sort_by(.lastUpdated // "") | last | .installPath // empty' <<< "$PLUGLIST")"
  LINT="$DP_PATH/skills/run/tools/config-lint.sh"
  if [[ -n "$DP_PATH" && -f "$LINT" ]]; then
    if out="$(bash "$LINT" "$CONF" 2>&1)"; then ok "config-lint: $(tail -1 <<< "$out")"
    else
      bad "config-lint violations — fix .claude/second-shift.config.json:"
      # while-read (not sed<<<) — SC2001-clean under the CI shellcheck flags
      n=0; while IFS= read -r line; do echo "[doctor]        $line"; n=$((n+1)); [[ "$n" -ge 10 ]] && break; done <<< "$out"
    fi
  else
    warn "dev-pipeline not installed — config-lint skipped (install it, then re-run doctor)"
  fi
fi

# --- 8. verdict ------------------------------------------------------------------
[[ "$NEED_RESTART" -eq 1 ]] && echo "[doctor] note  after installing/updating plugins, RESTART the session — component registration happens at session start"
echo "[doctor] summary: $FAILS failed check(s)"
exit "$FAILS"
