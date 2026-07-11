#!/usr/bin/env bash
# pipeline-doctor.sh — pre-flight environment verification for the dev-pipeline.
#
# Run before the first pipeline run on a new machine, and after any environment
# change (gh upgrade, key rotation, OS update). Catches in seconds the failures
# that otherwise surface mid-run: missing bot wrapper, gh GraphQL/feature
# breakage, missing labels, and a broken statectl state machine.
#
# Usage:
#   bash .claude/skills/run/tools/pipeline-doctor.sh
#
# Exit code: number of FAILED checks (0 = ready). WARN lines are informational
# (degraded-but-runnable, e.g. cost tracking off) and do not affect the exit code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Marketplace plugins/ dir — sibling plugins (review-toolkit, intake-toolkit) live
# here; their selftests are reached script-relative (they are NOT in the consumer repo).
PLUGINS_DIR="$(cd "$SKILL_DIR/../../.." && pwd)"

# Resolve a sibling-plugin file across BOTH layouts the doctor runs from:
#   monorepo checkout:  <PLUGINS_DIR>/<sib>/<rel>              (PLUGINS_DIR = .../plugins)
#   version-keyed install cache: <cacheroot>/<sib>/<ver>/<rel>  (PLUGINS_DIR = <cacheroot>/<this-plugin>)
# Tries the monorepo path, then this plugin's own version in the cache, then the newest sibling
# version that has the file. Prints the first hit; returns non-zero if none exists.
resolve_sibling() { # $1 = sibling plugin name, $2 = path under that plugin
  local sib="$1" rel="$2" cand v cacheroot myver
  cand="$PLUGINS_DIR/$sib/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  cacheroot="$(cd "$PLUGINS_DIR/.." 2>/dev/null && pwd)" || return 1
  myver="$(basename "$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)")"
  cand="$cacheroot/$sib/$myver/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  # shellcheck disable=SC2012  # version dirs are alphanumeric (X.Y.Z); ls is safe and 3.2-portable here
  for v in $(ls -1 "$cacheroot/$sib" 2>/dev/null | sort -r); do
    cand="$cacheroot/$sib/$v/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}

# Consumer repo root (state, worktrees, toolchain probes) — NOT the plugin checkout.
# SECOND_SHIFT_REPO_ROOT overrides; else the main checkout via git-common-dir
# (worktree-safe); else cwd.
if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$SECOND_SHIFT_REPO_ROOT"
elif _common="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  REPO_ROOT="$(dirname "$(cd "$_common" && pwd)")"
else
  REPO_ROOT="$(pwd)"
fi

# Bot wrapper: kept in lockstep with claim-issue.sh / install-gh-bot.sh
# ($HOME/.config/<consumer-repo-dir-basename>/gh-as-bot.sh); GH_BOT env overrides.
GH_BOT="${GH_BOT:-$HOME/.config/$(basename "$REPO_ROOT")/gh-as-bot.sh}"

FAILS=0
ok()   { echo "[doctor] OK    $1"; }
warn() { echo "[doctor] WARN  $1"; }
bad()  { echo "[doctor] FAIL  $1"; FAILS=$((FAILS+1)); }

# --- 1. Core tools -------------------------------------------------------------
for dep in gh jq git openssl curl; do
  if command -v "$dep" >/dev/null; then ok "$dep present"; else bad "$dep missing"; fi
done

echo "[doctor] info  /bin/bash is $(/bin/bash -c 'echo $BASH_VERSION') (macOS ships 3.2 — pipeline scripts must stay 3.2-compatible; the selftest below proves it)"

# --- 1b. Toolchain invokability -------------------------------------------------
# The pipeline runs every build/format/lint command through the SAME *non-interactive*
# shell this script runs in — where login-shell nvm aliases / `__init_nvm` shims do
# NOT apply. A bare `command -v node` can pass while `node --version` through a broken
# nvm/corepack wrapper fails (`__init_nvm:unalias: not enough arguments`, #149 retro).
# So probe each tool the way the pipeline INVOKES it: actually run `<tool> --version`
# from within this shell (the script is itself such a shell) and key on the EXIT CODE,
# not on `command -v`. node + yarn are hard deps (FAIL); npx/prettier/ruff degrade (WARN).

# node — hard dep: the Stage 6 SUITE lane and every yarn command need it.
if node --version >/dev/null 2>&1; then
  ok "node invokable ($(node --version 2>/dev/null)) in this non-interactive shell"
elif command -v node >/dev/null 2>&1; then
  bad "node is on PATH but 'node --version' fails to run — a broken nvm/shell wrapper? The pipeline's Bash sees the same failure. Fix the shell init, or put an absolute node bin dir on PATH"
else
  bad "node not invokable in this non-interactive shell — if nvm-managed, login-shell aliases don't apply to the pipeline's Bash; put an absolute node bin dir on PATH. Stage 6 SUITE lane + all yarn commands need it"
fi

# yarn (4.x via corepack) — hard dep: the package manager for every SUITE-lane command.
if yarn --version >/dev/null 2>&1; then
  ok "yarn invokable ($(yarn --version 2>/dev/null)) in this non-interactive shell"
elif command -v yarn >/dev/null 2>&1; then
  bad "yarn is on PATH but 'yarn --version' fails to run — broken corepack/nvm wrapper? Stage 6 SUITE lane cannot run. Fix the shell init, or run 'corepack enable'"
else
  bad "yarn not invokable in this non-interactive shell — enable it with 'corepack enable' (the repo pins yarn@4 via packageManager). Stage 6 SUITE lane needs it"
fi

# npx — WARN: one-off tool runner; absolute-path (node_modules/.bin/<tool>) fallback exists.
if npx --version >/dev/null 2>&1; then
  ok "npx invokable ($(npx --version 2>/dev/null))"
else
  warn "npx not invokable in this non-interactive shell — fall back to absolute-path invocation (node_modules/.bin/<tool>) for any npx-run tool"
fi

# repo-local prettier — WARN: the Stage 6 inert-lane 'prettier --check' format gate.
PRETTIER_BIN="$REPO_ROOT/node_modules/.bin/prettier"
if [[ -x "$PRETTIER_BIN" ]] && "$PRETTIER_BIN" --version >/dev/null 2>&1; then
  ok "repo-local prettier runnable (Stage 6 inert-lane format check)"
else
  warn "repo-local prettier not runnable at node_modules/.bin/prettier — run 'yarn install'; Stage 6's inert-lane 'prettier --check' is skipped otherwise"
fi

# ruff — WARN, gated on Python under pipeline scope. "In scope" = a pyproject.toml
# outside any node_modules or .claude directory exists (CLAUDE.md rule 9 runs ruff
# on Python changes).
# Prune any directory named node_modules or .claude at any depth (the worktrees live
# under .claude) so the find stays fast.
PY_IN_SCOPE=$(find "$REPO_ROOT" \( -name node_modules -o -name .claude \) -prune -o \
  -name pyproject.toml -print 2>/dev/null | head -1)
if [[ -n "$PY_IN_SCOPE" ]]; then
  if ruff --version >/dev/null 2>&1; then
    ok "ruff invokable ($(ruff --version 2>/dev/null)) for Python under pipeline scope"
  else
    warn "ruff not invokable but Python is under pipeline scope (${PY_IN_SCOPE#"$REPO_ROOT"/}) — CLAUDE.md rule 9 'ruff format'/'ruff check --fix' can't run; hand-verify Python changes (install via 'brew install ruff' or 'uv tool install ruff')"
  fi
else
  ok "no Python under pipeline scope — ruff probe skipped"
fi

# --- 2. gh auth + feature probes ------------------------------------------------
if gh auth status >/dev/null 2>&1; then ok "gh auth"; else bad "gh auth status failed — run gh auth login"; fi

# Projects-classic GraphQL deprecation breaks `gh issue edit` / `gh issue comment`
# / `gh issue view --json` on some gh-version + repo combinations. Probe with a
# read; if it trips, all writes must use the REST forms in SKILL.md Bot Identity.
first_issue=$(gh api "repos/{owner}/{repo}/issues?per_page=1&state=all" --jq '.[0].number' 2>/dev/null)
if [[ -n "${first_issue:-}" ]]; then
  if gh issue view "$first_issue" --json labels >/dev/null 2>&1; then
    ok "gh issue --json path works (GraphQL)"
  else
    warn "gh issue edit/comment/--json hit the Projects-classic GraphQL deprecation — use the REST forms in SKILL.md Bot Identity (the skill documents them as canonical)"
  fi
else
  warn "no issues found to probe the gh GraphQL path"
fi

if gh pr list --help 2>/dev/null | grep -q -- '--head'; then
  ok "gh pr list --head supported"
else
  warn "gh pr list lacks --head (old gh) — Stage 9 duplicate guard must use REST: gh api 'repos/{owner}/{repo}/pulls?head={owner}:BRANCH'"
fi

# --- 3. Bot wrapper -------------------------------------------------------------
if [[ -x "$GH_BOT" ]]; then
  repos=$("$GH_BOT" api /installation/repositories --jq '[.repositories[].full_name] | join(", ")' 2>/dev/null)
  if [[ -n "$repos" ]]; then
    ok "bot wrapper mints tokens (access: $repos)"
  else
    bad "bot wrapper exists but failed to mint an installation token — key revoked/expired? Re-run tools/install-gh-bot.sh with a fresh key"
  fi
else
  bad "bot wrapper missing at $GH_BOT — bootstrap with tools/install-gh-bot.sh <private-key.pem>"
fi

# --- 4. Required labels ---------------------------------------------------------
required_labels=(ready-for-dev needs-spec-work needs-plan-review needs-intake-review in-progress epic)
have_labels=$(gh api "repos/{owner}/{repo}/labels?per_page=100" --jq '.[].name' 2>/dev/null)
for l in "${required_labels[@]}"; do
  if grep -qx "$l" <<< "$have_labels"; then ok "label '$l'"; else bad "label '$l' missing — create it before running the pipeline"; fi
done

# --- 5. statectl state machine (the safety net must work on THIS machine) -------
if out=$(bash "$SKILL_DIR/statectl-selftest.sh" 2>&1); then
  ok "statectl selftest: $(tail -1 <<< "$out" | sed 's/\[self-test\] //')"
else
  bad "statectl selftest FAILED — the state machine (incl. mark-failed failure paths) is broken on this machine. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5b. Stage 8 dark-reviewer retry contract (#168) ----------------------------
# Validates code-review.mjs's null/dark-reviewer handling (retry decision + the
# drift-guard that the production script still carries the load-bearing tokens).
# Gate on invocation (not `command -v`) for the same reason as section 1b: a node
# that resolves on PATH but fails to run would error inside the selftest subprocess
# and emit a misleading "selftest FAILED" — when 1b already reported the real cause.
if node --version >/dev/null 2>&1; then
  if out=$(node "$SKILL_DIR/workflows/null-reviewer-selftest.mjs" 2>&1); then
    ok "null-reviewer selftest: $(tail -1 <<< "$out")"
  else
    bad "null-reviewer selftest FAILED — the Stage 8 dark-reviewer contract is broken (or code-review.mjs drifted). Output tail:"
    tail -5 <<< "$out" | sed 's/^/[doctor]        /'
  fi
else
  warn "node not invokable — skipping null-reviewer selftest (Stage 8 dark-reviewer contract unverified on this machine; see the node FAIL in section 1b for the cause)"
fi

# --- 5c. slice-derivation selftest (Stage 1 stacked-PR slice math + 1-intake.md tokens) ---
if out=$(bash "$SCRIPT_DIR/slice-derivation-selftest.sh" 2>&1); then
  ok "slice-derivation selftest: $(tail -1 <<< "$out")"
else
  bad "slice-derivation selftest FAILED — Stage 1 stacked-PR slice derivation (or its 1-intake.md load-bearing tokens) drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5d. reviewer-drift gate selftest (real-commit self-gate + registry lockstep) ---
if _st=$(resolve_sibling review-toolkit scripts/check-reviewer-references-selftest.sh) && out=$(bash "$_st" 2>&1); then
  ok "reviewer-drift selftest: $(tail -1 <<< "$out")"
else
  bad "reviewer-drift selftest FAILED — the reviewer-drift hook's real-commit self-gate (or the three-registry lockstep) drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5e. claim-sequence selftest (Stage 1.A claim swap helper + failed-add abort) ---
# Proves tools/claim-issue.sh ADDs in-progress, confirms the add, then DELETEs
# ready-for-dev — and aborts with ready-for-dev intact (no DELETE) on a failed add.
# This is the automated regression test #170's AC#3 could not satisfy while the swap
# was model-executed prose (#183). Drift tail also asserts SKILL.md / 1-intake.md
# call the helper rather than re-inlining the snippet.
if out=$(bash "$SCRIPT_DIR/claim-selftest.sh" 2>&1); then
  ok "claim-sequence selftest: $(tail -1 <<< "$out")"
else
  bad "claim-sequence selftest FAILED — the Stage 1.A claim swap helper (or its prose call-sites) drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5f. pre-commit type-check carve-out selftest (hook predicate + lockstep) ----
# Proves the pre-commit hook's needs_typecheck() predicate gates/skips correctly
# (incl. the .claude/**/*.{mjs,cjs} inert carve-out and the mixed-stage case), and
# that the hook carve-out stays in lockstep with the is-inert-diff.sh inert set, that
# Stage 6 delegates to that script, and that the hooks.md embedded copy matches. Drifting
# any of those trips this check (#228, #249).
if out=$(bash "$SCRIPT_DIR/pre-commit-typecheck-selftest.sh" 2>&1); then
  ok "pre-commit-typecheck selftest: $(tail -1 <<< "$out")"
else
  bad "pre-commit-typecheck selftest FAILED — the hook predicate, is-inert-diff.sh lockstep, Stage-6 delegation, or hooks.md embedded copy drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5g. model-tier lockstep selftest (.mjs tables vs agent frontmatter) ---------
# Proves check-model-tiers.sh catches drift between a dev-pipeline .mjs dispatch
# table (REVIEWER_MODEL / INTAKE_MODEL / DESIGN_MODEL / UNIT_TEST_MODEL /
# PLAN_REVIEWER_MODEL) and the dispatched agent's `model:` frontmatter, and that
# its #208 hook self-gate holds.
if _st=$(resolve_sibling review-toolkit scripts/check-model-tiers-selftest.sh) && out=$(bash "$_st" 2>&1); then
  ok "model-tier selftest: $(tail -1 <<< "$out")"
else
  bad "model-tier selftest FAILED — the .mjs model tables drifted from agent frontmatter (or the check itself drifted). Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5h. is-inert-diff classifier selftest (INERT-lane single source of truth) ---
# Proves is-inert-diff.sh classifies every inert pattern and the SUITE defaults
# correctly, and that it stays byte-identical to the canonical inline regex it
# extracted (golden-master parity). This is the single source of truth the Stage-6
# lane decision and the pre-commit hook carve-out both depend on (#249).
if out=$(bash "$SCRIPT_DIR/is-inert-diff-selftest.sh" 2>&1); then
  ok "is-inert-diff selftest: $(tail -1 <<< "$out")"
else
  bad "is-inert-diff selftest FAILED — the INERT-lane classifier drifted from the canonical regex (byte-identical broken). Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5h2. plan-lint selftest (Stage-3/4 deterministic plan structure lint) --------
if out=$(bash "$SCRIPT_DIR/plan-lint-selftest.sh" 2>&1); then
  ok "plan-lint selftest: $(tail -1 <<< "$out" | sed 's/\[plan-lint-selftest\] //')"
else
  bad "plan-lint selftest FAILED — the Stage-3/4 plan structure lint (mandated sections / AC-traceability table / 1:1 snapshot) drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5h3. ledger-lint selftest (Decision Ledger structural lint) ------------------
# Lives in the intake-toolkit plugin (plan-interview skill), not dev-pipeline — reach
# it script-relative via the sibling-plugins dir, not the consumer repo.
if _st=$(resolve_sibling intake-toolkit skills/plan-interview/tools/ledger-lint-selftest.sh) && out=$(bash "$_st" 2>&1); then
  ok "ledger-lint selftest: $(tail -1 <<< "$out" | sed 's/\[ledger-lint-selftest\] //')"
else
  bad "ledger-lint selftest FAILED — the Decision Ledger lint (provenance enum / explicit-empty form / quoting-safe trim) drifted. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5i. verifyctl selftest (Stage 6 deterministic verify runner) ----------------
# Proves verifyctl.sh's lane derivation, failure classification, and — the
# drift-killer — the sidecar-driven verifyAttempts charging (charge-once,
# same-HEAD idempotence, budget refusal, --no-attempt read-only, INFRA never
# charged) all hold on this machine.
if out=$(bash "$SKILL_DIR/verifyctl-selftest.sh" 2>&1); then
  ok "verifyctl selftest: $(tail -1 <<< "$out" | sed 's/\[self-test\] //')"
else
  bad "verifyctl selftest FAILED — the Stage-6 verify runner (lanes / classification / attempt accounting) is broken on this machine. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5j. Workflow-script syntax (wrapped node --check) ---------------------------
# Workflow scripts use a top-level return (the runtime wraps the body in an async
# function), so a bare `node --check` false-fails; wrap before checking. Gate on
# node invocability like 5b.
if node --version >/dev/null 2>&1; then
  for wfscript in plan-review.mjs mutation-gate.mjs; do
    wrap=$(mktemp -t doctor-wfcheck.XXXXXX).mjs
    { echo '(async () => {'; sed 's/^export const meta/const meta/' "$SKILL_DIR/workflows/$wfscript"; echo '})()'; } > "$wrap"
    if node --check "$wrap" >/dev/null 2>&1; then
      ok "workflow syntax: $wfscript (wrapped node --check)"
    else
      bad "workflow syntax FAILED for $wfscript — the script will not parse under the Workflow runtime"
    fi
    rm -f "$wrap"
  done
else
  warn "node not invokable — skipping workflow-script syntax checks (see section 1b)"
fi

# --- 6. Worktree base + degraded-mode notes -------------------------------------
if mkdir -p "$REPO_ROOT/.claude/worktrees" 2>/dev/null; then ok "worktree base dir writable"; else bad "cannot create $REPO_ROOT/.claude/worktrees"; fi

if [[ -s "$HOME/.claude/otel-metrics/metrics.jsonl" ]]; then
  ok "OTel metrics file present — Stage 9 cost block can fire"
else
  warn "no OTel metrics at ~/.claude/otel-metrics/metrics.jsonl — cost tracking will record skipped-telemetry-off (opt-in; see cost-tracking-setup.md)"
fi
if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  ok "CLAUDE_CODE_SESSION_ID set (cost attribution possible)"
else
  warn "CLAUDE_CODE_SESSION_ID unset in this shell — fine inside a Claude Code session; cost tracking degrades to skipped-no-sessions otherwise"
fi

# --- 7. Instruction-prose budget ratchet (L2 debloat, #188) ---------------------
# Quality signal, not an environment blocker: surface prose-layer growth over the
# committed baseline (+ narrative #NNN archaeology) as WARN — it never fails pre-flight.
if pb=$(bash "$SCRIPT_DIR/prose-budget.sh" 2>&1); then
  ok "prose-budget: $(tail -1 <<< "$pb" | sed 's/\[prose-budget\] //')"
else
  warn "prose-budget: instruction layer grew past baseline — run: bash .claude/skills/run/tools/prose-budget.sh"
  grep -E 'FAIL ' <<< "$pb" | sed 's/^/[doctor]        /' | head -5
fi

echo "[doctor] summary: $FAILS failed check(s)"
exit "$FAILS"
