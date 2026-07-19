#!/usr/bin/env bash
# second-shift-ci-check.sh — server-side evidence gate, committed into a consumer repo
# by /second-shift:onboard (#33). The gate of record is server-side CI; the committed
# thin check (second-shift-doctor.sh) is presence-only local feedback. This is the
# blocking half: it catches a half-done marketplace upgrade before it merges.
#
# Two checks against the repo's committed second-shift files:
#   (a) config-lint — validate .claude/second-shift.config.json with the config-lint.sh
#       shipped AT the pinned marketplace ref (fetched fresh; CI runners have no plugin
#       cache, so this cannot shell out to an installed plugin).
#   (b) ref lockstep — assert .claude/settings.json's marketplace ref matches
#       .claude/second-shift.lock.json's ref. A half-done upgrade PR bumps one but not
#       the other; this is the drift signal. (Ported from second-shift:doctor doctor.sh.)
#
# Exit code = number of FAILED checks (0 = clean) — the doctor / pipeline-doctor
# convention. A non-zero exit surfaces a red check. This workflow only REPORTS; mark
# it a required status check in branch protection to actually BLOCK a merge — a
# committed workflow cannot require itself.
#
# "Couldn't verify" (a transient config-lint fetch failure, a missing runner tool) is a
# WARN, NOT a FAIL: it does not conflate an infra hiccup with a real drift/violation, so
# a network blip never red-Xes an otherwise-clean PR. ONE exception: an HTTP 404 on the
# pinned ref / linter path is a FAIL — a ref that doesn't exist (typo'd upgrade PR,
# force-deleted tag, moved linter path) IS the drift this gate exists to catch, and
# WARNing it would let the gate self-disable green forever. The lockstep check (no
# network) always runs regardless.
#
# Env seam (testing / vendored fork): SECOND_SHIFT_CONFIG_LINT — path to a local
#   config-lint.sh. When set, the fetch is skipped and this file is run instead (the
#   selftest's no-network seam; also lets a private-fork consumer vendor the linter).
#
# macOS ships /bin/bash 3.2; this script stays 3.2-compatible. No `set -e` — the
# FAILS/WARNS counters ARE the control flow (a failing check must not abort the script).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
LOCK="$ROOT/.claude/second-shift.lock.json"
SETTINGS="$ROOT/.claude/settings.json"
CONFIG="$ROOT/.claude/second-shift.config.json"
MKT="second-shift"
FAILS=0
WARNS=0
ok()   { echo "[second-shift-ci] OK    $1"; }
bad()  { echo "[second-shift-ci] FAIL  $1"; FAILS=$((FAILS+1)); }
# On a green check nobody opens the job log — surface WARNs as GitHub Actions
# annotations (PR checks tab) so "could not verify" is visible, not vanished.
warn() {
  echo "[second-shift-ci] WARN  $1"; WARNS=$((WARNS+1))
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning title=second-shift evidence::$1"
}

command -v jq >/dev/null 2>&1 || { warn "jq not found on the runner — cannot verify (install jq)"; echo "[second-shift-ci] summary: $FAILS failed, $WARNS could-not-verify"; exit "$FAILS"; }
if [ ! -f "$LOCK" ] || ! jq empty "$LOCK" 2>/dev/null; then
  bad "no valid $LOCK — run /second-shift:onboard (it writes the lockfile)"
  echo "[second-shift-ci] summary: $FAILS failed, $WARNS could-not-verify"
  exit "$FAILS"
fi

LOCK_REF="$(jq -r '.marketplace.ref // ""' "$LOCK")"
LOCK_REPO="$(jq -r '.marketplace.repo // ""' "$LOCK")"

# --- (b) settings ref <-> lockfile ref lockstep -----------------------------
# Ported from second-shift:doctor (skills/doctor/tools/doctor.sh section 2): keep the
# semantics and message aligned so client-side doctor and server-side CI agree.
if [ ! -f "$SETTINGS" ]; then
  bad "no $SETTINGS — run /second-shift:onboard"
else
  SET_REF="$(jq -r --arg m "$MKT" '.extraKnownMarketplaces[$m].source.ref // ""' "$SETTINGS" 2>/dev/null)"
  if [ -n "$SET_REF" ] && [ "$SET_REF" = "$LOCK_REF" ]; then
    ok "settings ref == lockfile ref ($LOCK_REF)"
  elif [ -z "$SET_REF" ]; then
    bad "settings has no marketplace ref pin — re-run /second-shift:onboard (or add \"ref\": \"$LOCK_REF\")"
  else
    bad "settings ref ($SET_REF) and lockfile ref ($LOCK_REF) disagree — a half-done upgrade; make one PR carry both"
  fi
fi

# --- (a) config-lint the committed config at the pinned ref -----------------
if [ ! -f "$CONFIG" ]; then
  bad "no $CONFIG — run /second-shift:onboard"
else
  LINT=""
  CLEANUP=""
  if [ -n "${SECOND_SHIFT_CONFIG_LINT:-}" ]; then
    LINT="$SECOND_SHIFT_CONFIG_LINT"                      # test seam / vendored override
  elif ! command -v gh >/dev/null 2>&1; then
    warn "config-lint: could not verify — gh not on the runner (cannot fetch config-lint @ ${LOCK_REF:-?})"
  elif [ -z "$LOCK_REPO" ] || [ -z "$LOCK_REF" ]; then
    warn "config-lint: could not verify — lockfile marketplace.repo/ref is empty"
  else
    LINT="$(mktemp)"; CLEANUP="$LINT"
    ERRF="$(mktemp)"
    LINT_PATH="plugins/dev-pipeline/skills/run/tools/config-lint.sh"
    # onboard Step 5 uses this exact fetch-at-ref form for the not-yet-installed case.
    if gh api "repos/$LOCK_REPO/contents/$LINT_PATH?ref=$LOCK_REF" --jq '.content' 2>"$ERRF" \
         | base64 --decode > "$LINT" 2>/dev/null && [ -s "$LINT" ]; then
      : # fetched
    else
      # A 404 is NOT an infra hiccup — it means the pinned ref (or the linter's path
      # at that ref) does not exist. A PR that typos/deletes the ref, or a moved
      # linter path, is exactly the half-done-upgrade drift this gate exists to
      # catch; classifying it WARN would let the gate pass green forever.
      if grep -qiE 'HTTP 404|Not Found' "$ERRF" 2>/dev/null; then
        bad "config-lint: $LINT_PATH does not exist at ${LOCK_REPO}@${LOCK_REF} (HTTP 404) — a nonexistent pinned ref or moved linter path IS drift; fix the ref pin (or vendor via SECOND_SHIFT_CONFIG_LINT)"
      else
        warn "config-lint: could not verify — failed to fetch $LINT_PATH from ${LOCK_REPO}@${LOCK_REF} (network / auth: $(head -1 "$ERRF" 2>/dev/null || true))"
      fi
      LINT=""
    fi
    rm -f "$ERRF"
  fi
  if [ -n "$LINT" ]; then
    if bash "$LINT" "$CONFIG"; then
      ok "config-lint passed against $CONFIG (@ ${LOCK_REF:-local})"
    else
      bad "config-lint reported violations in $CONFIG (see the config-lint output above)"
    fi
  fi
  [ -n "$CLEANUP" ] && rm -f "$CLEANUP"
fi

echo "[second-shift-ci] summary: $FAILS failed check(s), $WARNS could-not-verify"
exit "$FAILS"
