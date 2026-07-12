#!/usr/bin/env bash
# exitplan-ledger-gate.sh — PreToolUse hook on ExitPlanMode.
#
# Blocks ExitPlanMode when the session's plan lacks a well-formed
# `## Decision Ledger` section (contract: interviewing-baseline skill;
# lint: plan-interview/tools/ledger-lint.sh).
#
# Blocking idiom: this hook blocks via `exit 2` (stderr shown to the model) —
# the plan-mode hook contract. This differs from acme's Bash-matcher hooks
# (check-model-tiers.sh, check-reviewer-references.sh), which emit
# `permissionDecision:"deny"` JSON. Both are honored by Claude Code; the
# divergence is intentional (this hook matches `ExitPlanMode`, not `Bash`, so
# it never over-matches and needs no self-gate on the command string).
#
# Plan-content resolution order:
#   1. tool_input.plan in the hook payload (plan markdown inline)
#   2. a plan-file path field in the payload (tool_input.plan_path /
#      plan_file_path / file_path)
#   3. fallback: files in the consumer repo's plans dir (git toplevel +
#      config paths.plansDir, default .claude/plans; $HOME/.claude/plans when
#      not in a git repo) with mtime newer than the session transcript's
#      CREATION time (BSD find -newermB). Exactly one candidate → lint it;
#      zero or multiple → warn-and-allow. Never lint a stale file silently:
#      a single old plan with an old ledger must not false-PASS.
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
  echo "Fix: run the plan-interview skill (interviewing-baseline contract); trivial work adds the explicit empty form: 'No material decisions — all choices codebase-derived.'" >&2
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
for field in '.tool_input.plan_path' '.tool_input.plan_file_path' '.tool_input.file_path'; do
  P=$(jq -r "$field // empty" <<<"$PAYLOAD" 2>/dev/null || true)
  if [[ -n "$P" && -f "$P" ]]; then
    run_lint "$P" "payload $field"
  fi
done

# --- 3. fallback: session-fresh plan files -------------------------------------
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null || true)

# Anchor the plans dir on the CONSUMER repo (git toplevel via --git-common-dir,
# worktree-safe), with config paths.plansDir (default .claude/plans). Falls back
# to $HOME/.claude/plans when not in a git repo. Mirrors statectl's state_dir.
resolve_plans_dir() {
  local root="" common_dir cfg rel=".claude/plans"
  if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
    root="$SECOND_SHIFT_REPO_ROOT"
  elif common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
    common_dir="$(cd "$common_dir" && pwd)"
    root="$(dirname "$common_dir")"
  fi
  if [[ -n "$root" ]]; then
    cfg="${SECOND_SHIFT_CONFIG:-$root/.claude/second-shift.config.json}"
    if [[ -f "$cfg" ]]; then
      rel="$(jq -r '.paths.plansDir // ".claude/plans"' "$cfg" 2>/dev/null)" \
        || rel=".claude/plans"
    fi
    printf '%s\n' "$root/$rel"
    return 0
  fi
  printf '%s\n' "$HOME/.claude/plans"
}
PLANS_DIR="$(resolve_plans_dir)"
[[ -d "$PLANS_DIR" ]] || allow_warn "no plans dir at $PLANS_DIR"
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || allow_warn "no transcript_path in payload to anchor freshness"

CANDIDATES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && CANDIDATES+=("$f")
done < <(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -newermB "$TRANSCRIPT" 2>/dev/null || true)

if (( ${#CANDIDATES[@]} == 1 )); then
  run_lint "${CANDIDATES[0]}" "session-fresh plan ${CANDIDATES[0]}"
elif (( ${#CANDIDATES[@]} == 0 )); then
  allow_warn "no plan file newer than the session transcript's creation"
else
  allow_warn "ambiguous: ${#CANDIDATES[@]} session-fresh plan files"
fi
