#!/usr/bin/env bash
# pipeline-doctor.sh — pre-flight environment verification for the dev-pipeline.
#
# Run before the first pipeline run on a new machine, and after any environment
# change (gh upgrade, key rotation, OS update). Catches in seconds the failures
# that otherwise surface mid-run: missing bot wrapper, gh GraphQL/feature
# breakage, missing labels, and a broken toolkit on this machine.
#
# Usage:
#   bash "${CLAUDE_PLUGIN_ROOT}/tools/pipeline-doctor.sh"
#   (outside plugin execution, resolve the root first:
#    claude plugin list --json | jq -r '.[] | select(.id == "dev-pipeline@second-shift") | .installPath')
#
# Exit code: number of FAILED checks (0 = ready). WARN lines are informational
# (degraded-but-runnable, e.g. cost tracking off) and do not affect the exit code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Marketplace plugins/ dir — sibling plugins (review-toolkit, intake-toolkit) live
# here; their selftests are reached script-relative (they are NOT in the consumer repo).
PLUGINS_DIR="$(cd "$PLUGIN_DIR/.." && pwd)"

# Same directory, not a sibling plugin — this one ships with us under every layout, so it
# needs none of resolve_sibling's machinery below.
# shellcheck source=checked-call.sh
. "$SCRIPT_DIR/checked-call.sh"

# Resolve a sibling-plugin file across BOTH layouts the doctor runs from:
#   monorepo checkout:  <PLUGINS_DIR>/<sib>/<rel>              (PLUGINS_DIR = .../plugins)
#   version-keyed install cache: <cacheroot>/<sib>/<ver>/<rel>  (PLUGINS_DIR = <cacheroot>/<this-plugin>)
# Tries the monorepo path, then this plugin's own version in the cache, then the newest sibling
# version that has the file. Prints the first hit; returns non-zero if none exists.
# >>> resolve-sibling
resolve_sibling() { # $1 = sibling plugin name, $2 = path under that plugin
  local sib="$1" rel="$2" cand v cacheroot myver
  cand="$PLUGINS_DIR/$sib/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  cacheroot="$(cd "$PLUGINS_DIR/.." 2>/dev/null && pwd)" || return 1
  myver="$(basename "$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)")"
  cand="$cacheroot/$sib/$myver/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  # Highest version FIRST — this loop takes the first hit, so the sort must descend. Per-key
  # `r` modifiers, not a global `-r`: BSD sort ignores the global flag once per-key modifiers
  # are present, which would walk the versions ASCENDING and return the oldest sibling. The
  # plain `sort -r` this replaces was lexical, and ranked 9.0.0 above 10.0.0.
  # shellcheck disable=SC2012  # version dirs are alphanumeric (X.Y.Z); ls is safe and 3.2-portable here
  for v in $(ls -1 "$cacheroot/$sib" 2>/dev/null | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
    cand="$cacheroot/$sib/$v/$rel"; [[ -f "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}
# <<< resolve-sibling

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

# --- Consumer config (tracker-aware, PM-aware doctor, #17) ----------------------
# Doctor reads the consumer config first: the gh/bot/label sections gate on
# tracker.type, and the toolchain probes derive from the configured command table
# (not a hardcoded yarn). Absent config => github/yarn defaults (backward-compatible).
CFG="${SECOND_SHIFT_CONFIG:-$REPO_ROOT/.claude/second-shift.config.json}"
# Same state dir the stale-claims section (block 8) resolves later — computed here
# too (not hoisted/shared) so this early use doesn't reorder that section's own
# config read relative to $CFG's definition above.
STATE_DIR="$REPO_ROOT/.claude/pipeline-state"
[[ -f "$CFG" ]] && STATE_DIR="$REPO_ROOT/$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$CFG" 2>/dev/null)"
TRACKER_TYPE=github
[[ -f "$CFG" ]] && TRACKER_TYPE=$(jq -r '.tracker.type // "github"' "$CFG" 2>/dev/null || echo github)

# Bot wrapper resolution is deferred to block 3 (via tools/gh-bot.sh — #92).
# GH_BOT is bound there after classification so disabled/unset-var/missing-file
# each get a distinct remediation instead of a single empty-path FAIL.
GH_BOT=""

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

# node — hard dep of the PIPELINE ITSELF: the Workflow gates (code-review.mjs at
# Stage 8, mutation-gate.mjs) run under node regardless of the consumer's language.
if node --version >/dev/null 2>&1; then
  ok "node invokable ($(node --version 2>/dev/null)) — Workflow gates (code-review.mjs / mutation-gate.mjs)"
elif command -v node >/dev/null 2>&1; then
  bad "node is on PATH but 'node --version' fails to run — a broken nvm/shell wrapper? The pipeline's Bash sees the same failure. Fix the shell init, or put an absolute node bin dir on PATH"
else
  bad "node not invokable in this non-interactive shell — the Workflow gates (code-review.mjs, mutation-gate.mjs) need it; if nvm-managed, login-shell aliases don't apply to the pipeline's Bash. Put an absolute node bin dir on PATH"
fi

# Package managers / tools the CONFIGURED commands invoke (first word of each
# command in commands.<host>.*) — probe THESE, not a hardcoded yarn (#17). A pnpm
# / poetry repo probes pnpm / poetry; a yarn repo probes yarn. Each is a hard dep
# of the SUITE lane that references it (FAIL if referenced but not invokable).
CMD_TOOLS=""
[[ -f "$CFG" ]] && CMD_TOOLS=$(jq -r '
  [ (.commands // {}) | .[]
    | ( .lint,.typecheck,.test,.testFile,.build,.format )
    , ( (.lanes // [])      | .[] | (.commands // [])[] )
    , ( (.extraLanes // []) | .[] | (.commands // [])[] ) ]
  | map(select(type=="string" and length>0) | ltrimstr(" ") | split(" ")[0])
  | map(select(. != "bash" and . != "true" and . != "cd" and . != "env" and . != "npx"))
  | unique | .[]' "$CFG" 2>/dev/null)
if [[ -z "$CMD_TOOLS" ]]; then
  warn "no consumer command table found at $CFG — skipping package-manager probes (config-lint owns the hard fail on a missing/invalid config; doctor is advisory)"
else
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    if "$tool" --version >/dev/null 2>&1; then
      ok "command tool '$tool' invokable ($("$tool" --version 2>/dev/null | head -1))"
    elif command -v "$tool" >/dev/null 2>&1; then
      bad "'$tool' is on PATH but '$tool --version' fails in this non-interactive shell — the SUITE lane that runs it will see the same failure (fix the shell init / corepack / venv activation)"
    else
      bad "'$tool' not invokable — a configured command (commands.<host>.*) uses it, but the pipeline's non-interactive shell can't run it. Install it or fix PATH"
    fi
  done <<< "$CMD_TOOLS"
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

# Sections 2-4 (gh auth, gh feature probes, bot wrapper, required labels) are
# GitHub-tracker-only (#17). A jira consumer has no gh queue / App bot / GitHub
# label vocabulary — gate on tracker.type rather than FAILing forever on gh/bot/
# labels it never uses (which masked real FAILs by inflating the count).
if [[ "$TRACKER_TYPE" == "github" ]]; then

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

checked_match -e '--head' -- gh pr list --help
case $? in
  0) ok "gh pr list --head supported" ;;
  1) warn "gh pr list lacks --head (old gh) — Stage 9 duplicate guard must use REST: gh api 'repos/{owner}/{repo}/pulls?head={owner}:BRANCH'" ;;
  *) warn "could not probe 'gh pr list --help' (exit $CHECKED_MATCH_RC) — --head support is UNKNOWN, not missing. Re-run the doctor once gh works rather than routing Stage 9 around a capability that may be there" ;;
esac

# --- 3. Bot wrapper -------------------------------------------------------------
# >>> bot-resolve (classification + bind — extracted by pipeline-doctor-selftest.sh) >>>
# DOCTOR_BOT_RESOLVER is the selftest seam; production leaves it unset.
_BOT_RESOLVER="${DOCTOR_BOT_RESOLVER:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gh-bot.sh}"
_bot_status="unset-var"
_bot_path=""
if [[ -f "$_BOT_RESOLVER" ]]; then
  _bot_status="$(bash "$_BOT_RESOLVER" --status 2>/dev/null || echo unset-var)"
  _bot_path="$(bash "$_BOT_RESOLVER" --path 2>/dev/null || true)"
fi
case "$_bot_status" in
  disabled)
    ok "bot check skipped (tracker.bot.enabled is not true)"
    GH_BOT=""
    ;;
  ok)
    GH_BOT="$_bot_path"
    # Selftest sets DOCTOR_BOT_SKIP_PROBE=1 to exercise classification without a mint.
    if [[ "${DOCTOR_BOT_SKIP_PROBE:-}" == "1" ]]; then
      ok "bot wrapper resolved at $GH_BOT"
    else
      repos=$("$GH_BOT" api /installation/repositories --jq '[.repositories[].full_name] | join(", ")' 2>/dev/null)
      if [[ -n "$repos" ]]; then
        ok "bot wrapper mints tokens (access: $repos)"
      else
        bad "bot wrapper exists but failed to mint an installation token — key revoked/expired? Re-run tools/install-gh-bot.sh with a fresh key"
      fi
    fi
    ;;
  unset-var)
    _env_name="GH_BOT"
    [[ -f "${CFG:-}" ]] && _env_name="$(jq -r '.tracker.bot.envVar // "GH_BOT"' "$CFG" 2>/dev/null || echo GH_BOT)"
    bad "bot env var '${_env_name}' is unset and no wrapper resolved from config/default — export ${_env_name} (e.g. .claude/settings.local.json env block), set tracker.bot.wrapperPath, or run tools/install-gh-bot.sh"
    GH_BOT=""
    ;;
  missing-file)
    bad "bot wrapper missing at ${_bot_path:-?} — bootstrap with tools/install-gh-bot.sh <private-key.pem>"
    GH_BOT=""
    ;;
  not-executable)
    bad "bot wrapper at ${_bot_path:-?} is not executable — chmod +x it, or re-run tools/install-gh-bot.sh"
    GH_BOT=""
    ;;
  *)
    bad "bot wrapper unresolved (status=${_bot_status})"
    GH_BOT=""
    ;;
esac
# <<< bot-resolve <<<

# Commit identity: a GITIGNORED consumer config is absent from every pipeline worktree, so
# bot-commit.sh resolves it from the main checkout (--git-common-dir). That works unattended,
# but it is worth surfacing here because it is the condition under which a stale bot-commit.sh
# (or an unset SECOND_SHIFT_CONFIG in a hand-run command) silently commits as the operator.
if [[ -f "$CFG" ]] && git -C "$REPO_ROOT" check-ignore -q "$CFG" 2>/dev/null; then
  warn "consumer config $CFG is gitignored — it will be ABSENT in pipeline worktrees. bot-commit.sh resolves it from the main checkout, so pipeline commits are fine; hand-run git commands in a worktree should export SECOND_SHIFT_CONFIG to keep the bot identity."
elif [[ -f "$CFG" ]]; then
  ok "consumer config is tracked — present in worktrees"
fi

# --- 4. Required labels ---------------------------------------------------------
# Required-label set, same precedence as the SKILL.md pre-flight gate (#11 → #17):
# tracker.labels role union (queue + claimed + blockers) when set, else the legacy
# flat stageParams.requiredLabels, else the shipped six.
required_labels=()
if [[ -f "$CFG" ]]; then
  while IFS= read -r _l; do [[ -n "$_l" ]] && required_labels+=("$_l"); done \
    < <(jq -r '(.tracker.labels // {}) | ([.queue, .claimed] + (.blockers // [])) | map(select(. != null and . != "")) | .[]' "$CFG" 2>/dev/null)
  if (( ${#required_labels[@]} == 0 )); then
    while IFS= read -r _l; do [[ -n "$_l" ]] && required_labels+=("$_l"); done \
      < <(jq -r '.stageParams.requiredLabels // empty | .[]' "$CFG" 2>/dev/null)
  fi
fi
if (( ${#required_labels[@]} == 0 )); then
  required_labels=(ready-for-dev needs-spec-work needs-plan-review needs-intake-review in-progress epic)
fi
have_labels=$(gh api "repos/{owner}/{repo}/labels?per_page=100" --jq '.[].name' 2>/dev/null)
for l in "${required_labels[@]}"; do
  if grep -qx "$l" <<< "$have_labels"; then ok "label '$l'"; else bad "label '$l' missing — create it before running the pipeline"; fi
done

else
  echo "[doctor] info  tracker.type=$TRACKER_TYPE — GitHub sections (gh auth, gh feature probes, bot wrapper, required labels) skipped (not applicable to this tracker)"
fi

# --- 4b. Internal selftest sweep — fingerprint cache -----------------------------
# Sections 5-5j re-run this TOOLKIT's own behavioral selftests (lean-gate alone is
# ~90s+) so a consumer's actual bash/jq/node — which can and does diverge from
# second-shift's own CI runner (macOS ships bash 3.2) — gets proven, not assumed.
# That guarantee is a property of (a) the installed plugin tree's CONTENTS and (b)
# the resolved interpreter VERSIONS, neither of which changes between two doctor
# runs in the same environment with nothing installed/upgraded in between — so a
# clean sweep's result is cached, fingerprinted on both, and re-verification is
# skipped on a hit. A stale/missing/mismatched fingerprint always re-runs the full
# sweep; nothing here ever widens what counts as "verified".
# >>> selftest-cache-gate (extracted by pipeline-doctor-selftest.sh) >>>
# DOCTOR_CACHE_FILE / DOCTOR_CACHE_NOW are selftest seams; production leaves them unset.
_CACHE_FILE="${DOCTOR_CACHE_FILE:-$STATE_DIR/doctor-selftest-cache.json}"
_CACHE_NOW="${DOCTOR_CACHE_NOW:-$(date -u +%s)}"
_CACHE_TTL=86400   # 24h defense-in-depth expiry; the fingerprint below is the real gate
_FP_ENV="bash:$(/bin/bash -c 'echo $BASH_VERSION') jq:$(jq --version 2>/dev/null) node:$(node --version 2>/dev/null || echo none)"
SELFTEST_CACHE_HIT=""
if [[ -f "$_CACHE_FILE" ]]; then
  _fp_tree="$(find "$PLUGINS_DIR" -type f -newer "$_CACHE_FILE" -print -quit 2>/dev/null)"
  _cached_env="$(jq -r '.env // ""' "$_CACHE_FILE" 2>/dev/null)"
  _cached_at="$(jq -r '.verifiedAt // 0' "$_CACHE_FILE" 2>/dev/null)"
  [[ "$_cached_at" =~ ^[0-9]+$ ]] || _cached_at=0
  _cache_age=$(( _CACHE_NOW - _cached_at ))
  if [[ -z "$_fp_tree" && "$_cached_env" == "$_FP_ENV" && "$_cache_age" -ge 0 && "$_cache_age" -lt "$_CACHE_TTL" ]]; then
    SELFTEST_CACHE_HIT=1
    ok "internal selftest sweep: cached clean ($(( _cache_age / 60 )) min ago, same plugin tree + interpreter versions — lean-gate/claim/config-lint/etc. skipped; delete $_CACHE_FILE to force a re-run)"
  fi
fi
# <<< selftest-cache-gate <<<

if [[ -z "$SELFTEST_CACHE_HIT" ]]; then
_FAILS_BEFORE_SWEEP=$FAILS

# --- 5. lean gate (the safety net must work on THIS machine) --------------------
# #348 retired the statectl state machine with the staged lane; the lean lane's gate is
# what a run's five milestones are asserted by, so it takes this section's place.
if out=$(bash "$PLUGIN_DIR/skills/build-lean/lean-gate-selftest.sh" 2>&1); then
  ok "lean-gate selftest: $(tail -1 <<< "$out" | sed 's/\[self-test\] //')"
else
  bad "lean-gate selftest FAILED — the lean lane's milestone gate is broken on this machine. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5b. Stage 8 dark-reviewer retry contract (#168) ----------------------------
# Validates code-review.mjs's null/dark-reviewer handling (retry decision + the
# drift-guard that the production script still carries the load-bearing tokens).
# Gate on invocation (not `command -v`) for the same reason as section 1b: a node
# that resolves on PATH but fails to run would error inside the selftest subprocess
# and emit a misleading "selftest FAILED" — when 1b already reported the real cause.
if node --version >/dev/null 2>&1; then
  if out=$(node "$PLUGIN_DIR/workflows/null-reviewer-selftest.mjs" 2>&1); then
    ok "null-reviewer selftest: $(tail -1 <<< "$out")"
  else
    bad "null-reviewer selftest FAILED — the Stage 8 dark-reviewer contract is broken (or code-review.mjs drifted). Output tail:"
    tail -5 <<< "$out" | sed 's/^/[doctor]        /'
  fi
else
  warn "node not invokable — skipping null-reviewer selftest (Stage 8 dark-reviewer contract unverified on this machine; see the node FAIL in section 1b for the cause)"
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
# and that the pre-commit hook delegates to that script. Drifting any of those trips this
# check (#228, #249).
if out=$(bash "$SCRIPT_DIR/pre-commit-typecheck-selftest.sh" 2>&1); then
  ok "pre-commit-typecheck selftest: $(tail -1 <<< "$out")"
else
  bad "pre-commit-typecheck selftest FAILED — the hook predicate or the is-inert-diff.sh lockstep drifted. Output tail:"
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
# correctly, and that its INERT_RE has not drifted from the selftest's CANONICAL_RE
# lockstep mirror (golden-master parity). This is the single source of truth the Stage-6
# lane decision and the pre-commit hook carve-out both depend on (#249).
if out=$(bash "$SCRIPT_DIR/is-inert-diff-selftest.sh" 2>&1); then
  ok "is-inert-diff selftest: $(tail -1 <<< "$out")"
else
  bad "is-inert-diff selftest FAILED — a lane classification is wrong, or INERT_RE drifted from the selftest's CANONICAL_RE mirror. Output tail:"
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

# --- 5i. lean merge-boundary evidence (portable verdict/identity/freshness) ------
# verifyctl.sh was the staged lane's deterministic verify runner and died with it (#348).
# What replaces it here is the boundary a lean run is actually judged at: lean-evidence.sh
# reads the committed verdict record's verdict, authoring identity, patch freshness and
# ratification, and a consumer's CI fetches it at its pinned ref.
if out=$(bash "$PLUGIN_DIR/skills/build-lean/lean-evidence-selftest.sh" 2>&1); then
  ok "lean-evidence selftest: $(tail -1 <<< "$out" | sed 's/\[self-test\] //')"
else
  bad "lean-evidence selftest FAILED — the merge-boundary evidence reader (verdict / identity / freshness / ratification) is broken on this machine. Output tail:"
  tail -5 <<< "$out" | sed 's/^/[doctor]        /'
fi

# --- 5j. Workflow-script syntax (wrapped node --check) ---------------------------
# Workflow scripts use a top-level return (the runtime wraps the body in an async
# function), so a bare `node --check` false-fails; wrap before checking. Gate on
# node invocability like 5b.
if node --version >/dev/null 2>&1; then
  for wfscript in code-review.mjs mutation-gate.mjs; do
    wrap=$(mktemp -t doctor-wfcheck.XXXXXX).mjs
    { echo '(async () => {'; sed 's/^export const meta/const meta/' "$PLUGIN_DIR/workflows/$wfscript"; echo '})()'; } > "$wrap"
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

# A clean sweep (no NEW failure introduced across 5-5j) refreshes the fingerprint
# cache; a dirty one leaves the existing cache file untouched (expired/absent stays
# expired/absent) so a broken toolkit is never masked by a stale "clean" record.
# >>> selftest-cache-write (extracted by pipeline-doctor-selftest.sh) >>>
if [[ "$FAILS" -eq "$_FAILS_BEFORE_SWEEP" ]]; then
  mkdir -p "$STATE_DIR" 2>/dev/null
  jq -n --arg env "$_FP_ENV" --argjson at "$_CACHE_NOW" '{env: $env, verifiedAt: $at}' \
    > "$_CACHE_FILE" 2>/dev/null || true
fi
# <<< selftest-cache-write <<<
fi   # SELFTEST_CACHE_HIT

# --- 6. Worktree base + degraded-mode notes -------------------------------------
if mkdir -p "$REPO_ROOT/.claude/worktrees" 2>/dev/null; then ok "worktree base dir writable"; else bad "cannot create $REPO_ROOT/.claude/worktrees"; fi

# >>> otel-telemetry-classify (extracted by pipeline-doctor-selftest.sh) >>>
# #432: a rotated-but-healthy machine has an empty (or freshly re-created) metrics.jsonl beside a
# full `metrics-<ts>-size.jsonl` backup, and used to read here as "no OTel metrics" — the doctor
# reporting absent telemetry on a machine that is exporting fine. Any non-empty file for the stem
# counts. $OTEL_METRICS_FILE is honored so the check tracks what pipeline-cost-block.sh resolves.
_OTEL_METRICS_LIVE="${OTEL_METRICS_FILE:-$HOME/.claude/otel-metrics/metrics.jsonl}"
_OTEL_METRICS_STEM="${_OTEL_METRICS_LIVE%.jsonl}"
_otel_backup_present() {
  local f
  for f in "$_OTEL_METRICS_STEM"-*.jsonl; do
    [[ -s "$f" ]] && return 0
  done
  return 1
}
if [[ -s "$_OTEL_METRICS_LIVE" ]]; then
  ok "OTel metrics file present — Stage 9 cost block can fire"
elif _otel_backup_present; then
  ok "OTel metrics present in a rotated backup (live file empty) — Stage 9 cost block can fire"
else
  warn "no OTel metrics at $_OTEL_METRICS_LIVE (nor any rotated backup beside it) — cost tracking will record skipped-telemetry-off (opt-in; see cost-tracking-setup.md)"
fi
# #432: the variable that actually decides whether THIS shell's sessions export anything. A run
# launched without it produces an empty cost block that cannot be recovered afterwards, and every
# other check in this section passes while it does. Doctor is where an operator looks before a
# run, which makes it the cheapest place to catch it.
case "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" in
  ""|0|false|FALSE|False)
    warn "CLAUDE_CODE_ENABLE_TELEMETRY not enabled in this shell — a session launched from here exports nothing and its cost block will be empty (unrecoverable after the run). Set it in ~/.claude/settings.json's env block; see cost-tracking-setup.md §3" ;;
  *)
    ok "CLAUDE_CODE_ENABLE_TELEMETRY enabled (this shell's sessions export cost datapoints)" ;;
esac
if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  ok "CLAUDE_CODE_SESSION_ID set (cost attribution possible)"
else
  warn "CLAUDE_CODE_SESSION_ID unset in this shell — fine inside a Claude Code session; cost tracking degrades to skipped-no-sessions otherwise"
fi
# <<< otel-telemetry-classify <<<

# Visual-capture substrate (Stage 6): the prescribed capture tool is the Playwright MCP;
# when it is absent the sanctioned fallback is headless Chrome (review-lean's capture note —
# caveat: Chrome clamps windows to ~500px min-width, so a true 375px mobile capture is
# unavailable). Neither being present is still only a WARN — capture degrades to the
# logged skip line, never a pipeline failure. `claude mcp list` may be unavailable in a
# non-interactive shell; treat that as "unknown", not "missing".
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
command -v google-chrome >/dev/null 2>&1 && CHROME_BIN="$(command -v google-chrome)"
mcp_rc=1
if command -v claude >/dev/null 2>&1; then
  checked_match -i -e playwright -- claude mcp list
  mcp_rc=$?
fi
# `claude` ABSENT is a genuine "not configured" (rc 1 above, unchanged). `claude mcp list`
# PRESENT but failing is the third state the comment above already prescribed and the old
# pipeline could not express — a non-interactive shell that cannot answer, reported as such
# instead of as a missing MCP.
case $mcp_rc in
  0) ok "Playwright MCP configured — Stage 6 visual capture uses the prescribed tool" ;;
  1) if [[ -x "$CHROME_BIN" ]]; then
       warn "Playwright MCP not configured — Stage 6 visual capture degrades to the headless-Chrome fallback (mobile viewport clamps to ~500px min-width)"
     else
       warn "neither Playwright MCP nor headless Chrome available — Stage 6 visual capture will skip (logged, non-blocking); PR bodies omit the Visual Verification section"
     fi ;;
  *) warn "could not read 'claude mcp list' (exit $CHECKED_MATCH_RC) — Playwright MCP presence is UNKNOWN, not absent. Stage 6 capture may well work; re-run the doctor from an interactive shell before assuming the fallback" ;;
esac

# --- 7. Instruction-prose budget ratchet (L2 debloat, #188) ---------------------
# Quality signal, not an environment blocker: surface prose-layer growth over the
# committed baseline (+ narrative #NNN archaeology) as WARN — it never fails pre-flight.
if pb=$(bash "$SCRIPT_DIR/prose-budget.sh" 2>&1); then
  # An n/a result is a legitimate pass, but it must not READ like a measured one —
  # "0 fail(s)" against nothing inspected is the ambiguity this check now closes.
  #
  # BOTH paths have to be n/a to claim that (#552). Branching on the markdown marker alone
  # was true until the shell ratchet existed; now a repo with tools/*.sh and no skills/ or
  # agents/ root emits that marker AND a measured shell verdict, and this branch would throw
  # the verdict away while telling the operator nothing was measured. That shape is not
  # exotic — it is every consumer whose skills and agents come from the plugin cache, i.e.
  # everyone but this repo, which is why dogfooding cannot see it. The summary line carries
  # both coverages, so branch on it and let every other combination fall through to it.
  if grep -q 'coverage: md n/a, sh n/a' <<< "$pb"; then
    ok "prose-budget: n/a — nothing to measure in this repo (no instruction layer, and no shell under the scan roots)"
  else
    ok "prose-budget: $(tail -1 <<< "$pb" | sed 's/\[prose-budget\] //')"
  fi
elif grep -q 'FAIL vacuous coverage' <<< "$pb"; then
  warn "prose-budget: VACUOUS — root(s) exist but matched 0 files, so the gate measured nothing. Fix the scan roots, then: bash \"$SCRIPT_DIR/prose-budget.sh\" --update-baseline"
  grep -E 'roots searched' <<< "$pb" | sed 's/^/[doctor]        /' | head -2
elif grep -q 'FAIL stale baseline' <<< "$pb"; then
  warn "prose-budget: STALE baseline — no row resolves against the files on disk. Regenerate: bash \"$SCRIPT_DIR/prose-budget.sh\" --update-baseline"
  grep -E 'FAIL stale baseline' <<< "$pb" | sed 's/^/[doctor]        /' | head -2
# The shell path (#552) gets its own arms rather than falling through to the growth
# fallback below. Each of its three markers is deliberately NOT a superstring of the
# markdown marker it parallels, so no branch above can claim shell output and no branch
# here can claim markdown output — which is the property T11 exists to hold.
elif grep -q 'FAIL vacuous shell coverage' <<< "$pb"; then
  warn "prose-budget: VACUOUS (shell) — root(s) matched shell files but every one was excluded, so the ratchet measured nothing. Fix the scan roots, then: bash \"$SCRIPT_DIR/prose-budget.sh\" --update-baseline"
  grep -E 'roots searched' <<< "$pb" | sed 's/^/[doctor]        /' | head -2
elif grep -q 'FAIL stale shell baseline' <<< "$pb"; then
  warn "prose-budget: STALE shell baseline — no row resolves against the .sh files on disk. Regenerate: bash \"$SCRIPT_DIR/prose-budget.sh\" --update-baseline"
  grep -E 'FAIL stale shell baseline' <<< "$pb" | sed 's/^/[doctor]        /' | head -2
elif grep -q 'FAIL ratio grew' <<< "$pb"; then
  warn "prose-budget: shell comment density grew past baseline — run: bash \"$SCRIPT_DIR/prose-budget.sh\""
  grep -E 'FAIL ratio grew' <<< "$pb" | sed 's/^/[doctor]        /' | head -5
else
  warn "prose-budget: instruction layer grew past baseline — run: bash \"$SCRIPT_DIR/prose-budget.sh\""
  grep -E 'FAIL ' <<< "$pb" | sed 's/^/[doctor]        /' | head -5
fi

# --- 8. Stale claims (orphaned in_progress runs) --------------------------------
# A run stranded by an infra drop (connection loss, 401, killed session) keeps
# its state in_progress with no owning process and is invisible to the queue.
# Surface every in_progress state file whose last write is older than 30 min,
# with the exact reclaim commands. WARN, never FAIL — an environment can be
# pipeline-ready while a previous run sits orphaned; and doctor has no process-
# liveness signal, so confirm no live session owns a run before reclaiming.
STATE_DIR_D="$REPO_ROOT/.claude/pipeline-state"
[[ -f "$CFG" ]] && STATE_DIR_D="$REPO_ROOT/$(jq -r '.paths.pipelineStateDir // ".claude/pipeline-state"' "$CFG" 2>/dev/null)"
if [[ -d "$STATE_DIR_D" ]]; then
  stale_found=0
  for sf in "$STATE_DIR_D"/*.json; do
    [[ -f "$sf" ]] || continue
    # >>> stale-claim-classify (pure — extracted and executed by tools/pipeline-doctor-selftest.sh) >>>
    # Reads only $sf, emits $stale_line (empty = not stale). The `continue` is
    # deliberate: the extracting selftest re-hosts this block inside its own loop.
    #
    # Quarantined artifacts keep their in_progress content by design (retro
    # evidence, renamed not rewritten) — they are resolved, not stale.
    case "$(basename "$sf")" in *-released-*|*-stale-*) continue ;; esac
    # Missing/unparseable lastUpdatedAt anchors at epoch → flagged as ancient
    # (matching reclaim's fail-closed posture: undeterminable is surfaced, not
    # invisible).
    stale_line=$(jq -r '
      select((.runId? | type == "string") and (.stages? | type == "object") and (.status == "in_progress"))
      | ((now - ((.lastUpdatedAt // "") | fromdateiso8601? // 0)) / 60 | floor) as $age
      | select($age >= 30)
      | "\(.ticketKey) stage=\(.currentStage // 1) last-write=\($age)min-ago"
    ' "$sf" 2>/dev/null)
    # <<< stale-claim-classify <<<
    if [[ -n "$stale_line" ]]; then
      stale_found=1
      warn "stale claim: ${stale_line} — no liveness signal available (a long silent stage looks identical); if no session owns it: resume with '/dev-pipeline:run-lean ${stale_line%% *}', or release the claim by hand with the in-progress -> queue label swap via the bot wrapper"
    fi
  done
  [[ "$stale_found" == "0" ]] && ok "no stale in_progress claims (>=30 min since last state write)"
fi

# --- 9. Over-envelope stages on the most recent run (advisory) -------------------
# The waste half of manifesto P4. Derives per-stage time envelopes from the recorded
# corpus (tools/stage-envelopes.sh — the single derivation owner; nothing is stored)
# and surfaces the most recent run's over-envelope stages.
#
# WARN, NEVER FAIL — joining sections 7 and 8 as a quality signal. This check must not
# touch $FAILS: an environment is pipeline-ready whether or not the last run was slow,
# and a pre-flight that blocked on a *previous* run's latency would be actively wrong.
#
# TIME AXIS ONLY. Cost is a post-run artifact (the Stage-9 cost block writes it after
# the work is done), so a pre-flight surface has nothing to say about it.
if [[ -d "$STATE_DIR_D" ]] && command -v jq >/dev/null 2>&1; then
  # --mtime-prefilter caps enumeration at the newest ~3N files so this stays fast on a
  # several-hundred-file state dir; final selection and ordering are still by startedAt
  # inside the tool. It is a declared best-effort superset, not a proven one (a run
  # touched recently can have started long ago) — acceptable precisely because a miss
  # here costs a missed hint and can never produce a wrong flag.
  env_out="$(bash "$SCRIPT_DIR/stage-envelopes.sh" --state-dir "$STATE_DIR_D" --mtime-prefilter --json 2>/dev/null)"
  if [[ -z "$env_out" ]] || ! jq -e . >/dev/null 2>&1 <<<"$env_out"; then
    ok "stage envelopes: n/a — corpus not derivable yet (no readable runs)"
  else
    # >>> envelope-classify (pure — extracted and executed by tools/pipeline-doctor-selftest.sh) >>>
    # Reads only $env_out. Emits through ok()/warn() and NEVER through fail(), so this
    # check cannot move the exit code — AC-4's "no gate consumes the envelope output".
    #
    # The SENTINEL DELIBERATELY SPANS THE DISPATCH, not just the jq. The never-blocking
    # property lives in which reporter each arm calls; a sentinel that stopped at the
    # jq would leave an added `fail` here unguarded, and a mutation demo proved exactly
    # that gap before this boundary was widened.
    env_lines=$(jq -r '
      .flags[] | select(.axis == "time")
      | "\(.key): \(.measured) min exceeds corpus p90 \(.p90) min (n=\(.n))"
        + (if .record then " — a new record; at this n the p90 IS the observed maximum" else "" end)
    ' <<<"$env_out" 2>/dev/null)
    # A corpus under the min-n floor is reported as a known-unknown, never as a clean
    # bill of health — the same VACUOUS distinction section 7 draws between "measured
    # nothing" and "measured, and found nothing".
    env_summary=$(jq -r '
      ([ .timeEnvelopes[] | select(.floorMet) ] | length) as $withEnv
      | if $withEnv == 0
        then "VACUOUS: no stage reached the min-n floor of \(.corpus.minN) trusted windows after leave-one-out — no envelope derived (corpus: \(.corpus.runsInWindow) run(s))"
        else "measured \($withEnv) stage envelope(s) over \(.corpus.runsInWindow) run(s), \(.trustedWindows) trusted window(s)"
        end
    ' <<<"$env_out" 2>/dev/null)
    if [[ "$env_summary" == VACUOUS:* ]]; then
      warn "stage envelopes: ${env_summary#VACUOUS: }"
    elif [[ -n "$env_lines" ]]; then
      warn "stage envelopes: the most recent run ($(jq -r '.runUnderTest.stem' <<<"$env_out")) exceeded its corpus envelope — advisory only, nothing is blocked"
      while IFS= read -r l; do [[ -n "$l" ]] && echo "[doctor]        $l"; done <<<"$env_lines"
    else
      ok "stage envelopes: $env_summary; most recent run within envelope"
    fi
    # <<< envelope-classify <<<
  fi
fi

echo "[doctor] summary: $FAILS failed check(s)"
exit "$FAILS"
