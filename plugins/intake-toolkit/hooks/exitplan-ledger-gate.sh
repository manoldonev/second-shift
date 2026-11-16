#!/usr/bin/env bash
# exitplan-ledger-gate.sh — PreToolUse hook on ExitPlanMode.
#
# Blocks ExitPlanMode when the session's plan lacks a well-formed
# `## Decision Ledger` section (contract: interviewing-baseline skill;
# lint: plan-interview/tools/ledger-lint.sh).
#
# Blocking idiom: this hook blocks via `exit 2` (stderr shown to the model) —
# the plan-mode hook contract. This differs from the Bash-matcher hooks
# (check-model-tiers.sh, check-reviewer-references.sh), which emit
# `permissionDecision:"deny"` JSON. Both are honored by Claude Code; the
# divergence is intentional (this hook matches `ExitPlanMode`, not `Bash`, so
# it never over-matches and needs no self-gate on the command string).
#
# Plan-content resolution order:
#   1. tool_input.plan in the hook payload (Claude Code injects the plan
#      markdown from the plan file before the hook runs)
#   2. tool_input.planFilePath, the injected path of that plan file
#   3. fallback: files in Claude Code's plans directory (the plansDirectory
#      setting, relative to the project root; unset, or resolving outside the
#      project root, ~/.claude/plans) with a timestamp newer than the session
#      transcript's creation. Prefers birth time (`find -newermB`, BSD); GNU find has no
#      -newermB, so the hook probes once and falls back to mtime (`-newer`) —
#      a weaker signal, but a working tier instead of a permanently vacuous
#      one. Exactly one candidate → lint it; zero → warn-and-allow;
#      multiple → ambiguous, warn-and-allow. A scan that ERRORS is distinct
#      from a scan that finds zero candidates: it fails CLOSED (block),
#      because treating a broken scan as "found nothing" hides the
#      break. Never lint a stale file silently: a single old plan with an
#      old ledger must not false-PASS.
#
# Escape hatch: PLAN_INTERVIEW_SKIP=1 allows without linting.
# Exit: 0 allow, 2 block (stderr shown to the model). Never exit 1.
set -uo pipefail

PAYLOAD="$(cat || true)"

if [[ "${PLAN_INTERVIEW_SKIP:-0}" == "1" ]]; then
  echo "ledger-gate: skipped via PLAN_INTERVIEW_SKIP=1" >&2
  exit 0
fi

# Both this hook and ledger-lint ship in this plugin — resolve the lint
# script-relative, not from the consumer repo. (The consumer-repo anchor is
# for runtime state like plan files, resolved below.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../skills/plan-interview/tools/ledger-lint.sh"
if [[ ! -x "$LINT" ]]; then
  echo "ledger-gate: ledger-lint.sh not found/executable at $LINT — allowing (fix the install)" >&2
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "ledger-gate: jq unavailable — allowing" >&2; exit 0; }

allow_warn() { echo "ledger-gate: $1 — allowing without lint" >&2; exit 0; }

block() {
  echo "ledger-gate: BLOCKED — the plan has no valid Decision Ledger." >&2
  echo "$1" >&2
  echo "Fix: run the plan-interview skill (interviewing-baseline contract); trivial work adds the explicit empty form: 'No decisions to record. The code settles every choice.'" >&2
  echo "Escape hatch (deliberate override only): PLAN_INTERVIEW_SKIP=1." >&2
  exit 2
}

# Distinct from block(): this is not a ledger-content verdict, it's "freshness could
# not be determined at all". Fails closed for the same reason block() does (never
# silently allow), but with wording that does not claim anything about the ledger.
block_scan_error() {
  echo "ledger-gate: BLOCKED — tier-3 candidate scan failed, freshness cannot be trusted." >&2
  echo "$1" >&2
  echo "Escape hatch (deliberate override only): PLAN_INTERVIEW_SKIP=1." >&2
  exit 2
}

run_lint() {
  local target="$1"
  local out
  if out=$("$LINT" "$target" 2>&1); then
    echo "ledger-gate: OK ($2)" >&2
    exit 0
  else
    block "$out"
  fi
}

# --- 1. inline plan content ---------------------------------------------------
PLAN_INLINE=$(jq -r '.tool_input.plan // empty' <<<"$PAYLOAD" 2>/dev/null || true)
if [[ -n "$PLAN_INLINE" ]]; then
  TMP=$(mktemp "${TMPDIR:-/tmp}/ledger-gate.XXXXXX")
  trap 'rm -f "$TMP"' EXIT
  printf '%s\n' "$PLAN_INLINE" > "$TMP"
  run_lint "$TMP" "payload tool_input.plan"
fi

# --- 2. plan-file path in payload ----------------------------------------------
P=$(jq -r '.tool_input.planFilePath // empty' <<<"$PAYLOAD" 2>/dev/null || true)
if [[ -n "$P" && -f "$P" ]]; then
  run_lint "$P" "payload tool_input.planFilePath"
fi

# --- 3. fallback: session-fresh plan files -------------------------------------
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null || true)

# Claude Code's plansDirectory setting, read the way Claude Code documents it:
# the local project file beats the shared project file beats the user file, and
# a path holding a backslash or resolving outside the project root falls back
# to ~/.claude/plans. Managed settings are not read.
resolve_plans_dir() {
  local root dflt="$HOME/.claude/plans" rel="" f cand real_root real_cand
  root="${SECOND_SHIFT_REPO_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
  for f in "$root/.claude/settings.local.json" "$root/.claude/settings.json" "$HOME/.claude/settings.json"; do
    [[ -f "$f" ]] || continue
    rel="$(jq -r '.plansDirectory // empty | strings' "$f" 2>/dev/null || true)"
    [[ -n "$rel" ]] && break
  done
  if [[ -z "$rel" || "$rel" == *\\* ]]; then
    printf '%s\n' "$dflt"
    return 0
  fi
  if [[ "$rel" == /* ]]; then cand="$rel"; else cand="$root/$rel"; fi
  if [[ -d "$cand" ]]; then
    real_root="$(cd "$root" 2>/dev/null && pwd -P)"
    real_cand="$(cd "$cand" && pwd -P)"
    if [[ -z "$real_root" || ( "$real_cand" != "$real_root" && "$real_cand" != "$real_root"/* ) ]]; then
      printf '%s\n' "$dflt"
      return 0
    fi
  elif [[ "/$rel/" == */../* || ( "$rel" == /* && "$rel" != "$root"/* ) ]]; then
    printf '%s\n' "$dflt"
    return 0
  fi
  printf '%s\n' "$cand"
}
PLANS_DIR="$(resolve_plans_dir)"
[[ -d "$PLANS_DIR" ]] || allow_warn "no plans dir at $PLANS_DIR"
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || allow_warn "no transcript_path in payload to anchor freshness"

# Probe once: does this platform's find support birth-time comparison? GNU find
# rejects -newermB outright, so a self-referential probe (a dir compared to itself)
# is enough to detect it without touching real candidates.
NEWER_FLAG=-newermB
if ! find "$PLANS_DIR" -maxdepth 0 -newermB "$PLANS_DIR" >/dev/null 2>&1; then
  NEWER_FLAG=-newer
fi

# A plain redirect, not `< <(find ...)`: with process substitution, `$?` after the
# while loop reflects the last `read`'s EOF status, not find's — that would fail
# closed on every scan, including successful ones.
FIND_OUT="$(mktemp "${TMPDIR:-/tmp}/ledger-gate-find-out.XXXXXX")"
FIND_ERR="$(mktemp "${TMPDIR:-/tmp}/ledger-gate-find-err.XXXXXX")"
find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' "$NEWER_FLAG" "$TRANSCRIPT" >"$FIND_OUT" 2>"$FIND_ERR"
FIND_RC=$?
CANDIDATES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && CANDIDATES+=("$f")
done < "$FIND_OUT"
FIND_STDERR="$(cat "$FIND_ERR" 2>/dev/null)"
rm -f "$FIND_OUT" "$FIND_ERR"

if (( FIND_RC != 0 )); then
  block_scan_error "tier-3 candidate scan failed (find exit $FIND_RC, flag $NEWER_FLAG): ${FIND_STDERR:-no stderr}"
fi

if (( ${#CANDIDATES[@]} == 1 )); then
  run_lint "${CANDIDATES[0]}" "session-fresh plan ${CANDIDATES[0]}"
elif (( ${#CANDIDATES[@]} == 0 )); then
  allow_warn "no plan file newer than the session transcript's creation"
else
  allow_warn "ambiguous: ${#CANDIDATES[@]} session-fresh plan files"
fi
