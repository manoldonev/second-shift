#!/usr/bin/env bash
# second-shift-ci-check.sh — server-side evidence gate, committed into a consumer repo
# by /second-shift:onboard (#33). The gate of record is server-side CI; the committed
# thin check (second-shift-doctor.sh) is presence-only local feedback. This is the
# blocking half: it catches a half-done marketplace upgrade before it merges.
#
# Three checks against the repo's committed second-shift files:
#   (a) config-lint — validate .claude/second-shift.config.json with the config-lint.sh
#       shipped AT the pinned marketplace ref (fetched fresh; CI runners have no plugin
#       cache, so this cannot shell out to an installed plugin).
#   (b) ref lockstep — assert .claude/settings.json's marketplace ref matches
#       .claude/second-shift.lock.json's ref. A half-done upgrade PR bumps one but not
#       the other; this is the drift signal. (Ported from second-shift:doctor doctor.sh.)
#   (c) lean evidence — on a lean-lane PR, assert the merge-boundary evidence set the harness
#       is supposed to have left behind: a committed approve-verdict carrying reconciliation
#       keys, a review identity distinct from the build run's, a verdict covering THIS head,
#       and no unratified intent-gap record. Same fetch-at-pinned-ref shape as (a), against
#       lean-evidence.sh. Not applicable to an ordinary PR, which it says and moves on.
#
# WHY (c) IS HERE AND NOT ITS OWN WORKFLOW. A second workflow is a second required status check
# every adopting repo has to wire into branch protection by hand, and this file's own header
# already records that a committed workflow cannot require itself. Extending the check that is
# already required costs adopters nothing.
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
# Env seams (testing / vendored fork): SECOND_SHIFT_CONFIG_LINT and SECOND_SHIFT_LEAN_EVIDENCE
#   — paths to local copies of config-lint.sh / lean-evidence.sh. When set, the fetch is
#   skipped and the local file is run instead (the selftest's no-network seam; also lets a
#   private-fork consumer vendor either script).
#
# Check (c) additionally reads the PR context from the environment — PR_HEAD_REF, PR_HEAD_SHA,
# PR_BASE_REF, PR_BODY, PR_NUMBER, GH_REPO — which second-shift-ci.yml supplies. Never spliced
# into a `run:` line: a PR body is attacker-controllable. With no PR_HEAD_REF (a
# workflow_dispatch run) the check reports itself not applicable rather than guessing.
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

# --- the fetch-at-pinned-ref helper, shared by (a) and (c) -------------------
# ONE implementation for two fetches. The 404-is-FAIL / network-is-WARN split below is the
# whole point of this gate, and a second hand-written copy of it is where the two would
# eventually disagree — most likely by the newer one being written the lenient way.
#
# Prints the temp path of the fetched script on stdout, or nothing. $1 = label used in
# messages, $2 = repo-relative path at the pinned ref, $3 = the env-seam override (may be
# empty). The caller deletes what it gets back.
FETCHED=""
fetch_at_ref() { # fetch_at_ref <label> <path-at-ref> <seam-value>
  FETCHED=""
  if [ -n "$3" ]; then
    FETCHED="$3"                                          # test seam / vendored override
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    warn "$1: could not verify — gh not on the runner (cannot fetch $1 @ '$LOCK_REF')"
    return 1
  fi
  if [ -z "$LOCK_REPO" ] || [ -z "$LOCK_REF" ]; then
    warn "$1: could not verify — lockfile marketplace.repo/ref is empty"
    return 1
  fi
  local dest errf
  dest="$(mktemp)"
  errf="$(mktemp)"
  # onboard Step 5 uses this exact fetch-at-ref form for the not-yet-installed case.
  if gh api "repos/$LOCK_REPO/contents/$2?ref=$LOCK_REF" --jq '.content' 2>"$errf" \
       | base64 --decode > "$dest" 2>/dev/null && [ -s "$dest" ]; then
    rm -f "$errf"
    FETCHED="$dest"
    return 0
  fi
  # A 404 is NOT an infra hiccup — it means the pinned ref (or the script's path at that ref)
  # does not exist. A PR that typos/deletes the ref, or a moved path, is exactly the
  # half-done-upgrade drift this gate exists to catch; classifying it WARN would let the gate
  # pass green forever.
  if grep -qiE 'HTTP 404|Not Found' "$errf" 2>/dev/null; then
    bad "$1: $2 does not exist at ${LOCK_REPO}@${LOCK_REF} (HTTP 404) — a nonexistent pinned ref or moved path IS drift; fix the ref pin (or vendor it via the env seam)"
  else
    warn "$1: could not verify — failed to fetch $2 from ${LOCK_REPO}@${LOCK_REF} (network / auth: $(head -1 "$errf" 2>/dev/null || true))"
  fi
  rm -f "$errf" "$dest"
  return 1
}

# --- (a) config-lint the committed config at the pinned ref -----------------
if [ ! -f "$CONFIG" ]; then
  bad "no $CONFIG — run /second-shift:onboard"
else
  if fetch_at_ref "config-lint" "plugins/dev-pipeline/skills/run/tools/config-lint.sh" "${SECOND_SHIFT_CONFIG_LINT:-}"; then
    LINT="$FETCHED"
    if bash "$LINT" "$CONFIG"; then
      ok "config-lint passed against $CONFIG (@ ${LOCK_REF:-local})"
    else
      bad "config-lint reported violations in $CONFIG (see the config-lint output above)"
    fi
    [ -z "${SECOND_SHIFT_CONFIG_LINT:-}" ] && rm -f "$LINT"
  fi
fi

# --- (c) lean-lane merge-boundary evidence ----------------------------------
# Applicability, the issue key and every arm live in the fetched payload — this side only
# supplies the PR context and maps the payload's exit code onto this file's FAIL/WARN
# vocabulary. Deliberately so: a consumer and the marketplace repo must reach the SAME verdict
# from the same bytes, and any rule restated here would be a rule that can drift out from
# under the pin.
if [ -z "${PR_HEAD_REF:-}" ]; then
  ok "lean evidence: no PR context (not a pull_request run) — not applicable"
elif fetch_at_ref "lean-evidence" "plugins/dev-pipeline/skills/build-lean/lean-evidence.sh" "${SECOND_SHIFT_LEAN_EVIDENCE:-}"; then
  EV="$FETCHED"
  bash "$EV" all
  EV_RC=$?
  # 0 = evidence complete OR not a lean PR. 1 = a real evidence violation. 2 = the payload could
  # not run — a MISSING INPUT this template is responsible for supplying, so it is drift like a
  # 404 is drift, not the transient "could not verify" a network blip earns. Failing it open would
  # waive the whole arm on a workflow that quietly stopped passing PR_BASE_REF, which is the
  # silent self-disable this file refuses everywhere else.
  #
  # THE EXIT CODE IS THE WHOLE SIGNAL on rc=0 (#443). The payload is silent when every arm is
  # satisfied, so a complete lean PR prints nothing at all above this line and the two rc=0
  # readings are told apart by the payload's one-line decline, not by a recital: a decline says
  # `lean-evidence: not-applicable`, and its absence means the evidence is complete.
  case "$EV_RC" in
    0) ok   "lean evidence: complete, or not a lean PR — a 'lean-evidence: not-applicable' line above says which" ;;
    1) bad  "lean evidence: the lean PR is missing merge-boundary evidence (see the payload output above)" ;;
    *) bad  "lean evidence: the check could not run (exit $EV_RC) — the workflow is not supplying what the payload at '$LOCK_REF' needs; a check that cannot run must not report a pass" ;;
  esac
  [ -z "${SECOND_SHIFT_LEAN_EVIDENCE:-}" ] && rm -f "$EV"
fi

echo "[second-shift-ci] summary: $FAILS failed check(s), $WARNS could-not-verify"
exit "$FAILS"
