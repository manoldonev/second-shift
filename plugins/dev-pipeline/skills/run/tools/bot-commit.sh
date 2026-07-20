#!/usr/bin/env bash
# bot-commit.sh — `git commit` with the pipeline bot's git identity (SKILL.md "Bot Identity").
#
# WHY THIS EXISTS: the gh bot wrapper covers GitHub API writes only — it does NOT touch git
# user.name/user.email, so a bare `git commit` in the pipeline session silently commits as the
# operator. Observed in a retro: 4 of 5 PR commits carried the operator identity while
# only the engine-agent commit used the bot. Prose said "use the bot identity"; prose failed —
# this helper owns the command + identity resolution (enforcement-ladder rung 2).
#
# Usage: bot-commit.sh [-C <dir>] <git commit args...>
#   bot-commit.sh -C "$WT" -m "docs(dev-pipeline): plan for #42"
#
# Identity: name  = "<appName>[bot]"
#           email = "<botUserId>+<appName>[bot]@users.noreply.github.com"
# where <appName> comes from config `tracker.bot.app.appName` and <botUserId> is resolved once
# via `gh api users/<appName>[bot]` and cached in the repo's git common dir (shared across
# worktrees, never committed). Fallbacks are deliberate and NOISY-but-not-fatal: with the bot
# disabled/unconfigured it commits as the repo default (SKILL.md contract); with an
# unresolvable bot user id it warns to stderr and commits as the repo default rather than
# fabricating a wrong noreply address.
#
# CONFIG RESOLUTION (first existing file wins):
#   1. $SECOND_SHIFT_CONFIG            — explicit override, only when it names an existing file
#   2. <-C dir>/.claude/second-shift.config.json
#   3. <main checkout>/.claude/second-shift.config.json
# Candidate 3 is the load-bearing one: the consumer config is commonly gitignored, so it is
# NEVER checked out into a pipeline worktree. The main checkout is anchored via
# `--git-common-dir` → dirname — the same idiom as statectl.sh state_dir(), verifyctl.sh
# main_root(), and pipeline-cost-block.sh _repo_root(). Anchoring on `--show-toplevel` (the
# pre-#110 behavior) resolves to the WORKTREE, so every candidate missed, the bot read as
# disabled, and pipeline commits silently landed under the operator's identity — recorded in
# four separate pipeline retros before it was fixed.
#
# Two deliberate limits of the anchor, both of which degrade safely:
#   - $SECOND_SHIFT_REPO_ROOT overrides the CONFIG root only; the bot-id cache stays anchored
#     at the real --git-common-dir. The cache must live in an actual git dir to be writable and
#     worktree-shared, whereas the override exists so selftests can point config resolution at a
#     fixture. Deliberately not "parity" with verifyctl's main_root() on this point.
#   - `dirname "$COMMON_DIR"` is not the repo root under a non-standard layout (e.g.
#     `git init --separate-git-dir`). That only makes candidate 3 miss, which falls through to
#     the existing repo-default path plus a WARN — never a wrong identity.
#
# Repairing commits already mis-attributed to the operator: `git commit --amend --reset-author`
# under this helper. Plain `--amend` preserves the original author and does NOT fix it.

set -euo pipefail

DIR="."
if [[ "${1:-}" == "-C" ]]; then
  DIR="${2:?bot-commit: -C requires a directory}"
  shift 2
fi

# Anchor at the git COMMON dir (shared by every worktree) — resolved from $DIR, never from the
# helper's own CWD. Empty when $DIR is not a git repo; guarded so `set -e` cannot abort here.
COMMON_DIR=""
if COMMON_DIR="$(cd "$DIR" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"; then
  COMMON_DIR="$(cd "$DIR" && cd "$COMMON_DIR" && pwd)"
else
  COMMON_DIR=""
fi

# Config root: the override wins, else the main checkout above the common dir. See the
# CONFIG RESOLUTION note in the header for why the override does not also move the cache.
MAIN_ROOT=""
if [[ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]]; then
  MAIN_ROOT="$SECOND_SHIFT_REPO_ROOT"
elif [[ -n "$COMMON_DIR" ]]; then
  MAIN_ROOT="$(dirname "$COMMON_DIR")"
fi

# First existing candidate wins; CFG stays empty when none resolve.
CFG=""
for _cand in \
  "${SECOND_SHIFT_CONFIG:-}" \
  "$DIR/.claude/second-shift.config.json" \
  "${MAIN_ROOT:+$MAIN_ROOT/.claude/second-shift.config.json}"
do
  if [[ -n "$_cand" && -f "$_cand" ]]; then
    CFG="$_cand"
    break
  fi
done

BOT_ENABLED="false"
APP_NAME=""
if [[ -n "$CFG" ]]; then
  BOT_ENABLED="$(jq -r '.tracker.bot.enabled // false' "$CFG" 2>/dev/null || echo false)"
  APP_NAME="$(jq -r '.tracker.bot.app.appName // empty' "$CFG" 2>/dev/null || true)"
fi

if [[ "$BOT_ENABLED" != "true" || -z "$APP_NAME" ]]; then
  # Bot disabled or unconfigured — the SKILL.md contract is "commit as the repo default".
  # Say so on stderr: a silent fallback here is exactly how four runs' commits landed under
  # the operator without anyone noticing. Two distinct strings so the dangerous cause (no
  # config found anywhere) greps apart from the benign one (config found, bot deliberately
  # off). Stays rc=0 — a bot-less consumer must keep committing. Silent when $DIR is not a
  # resolvable repo, since there is no consumer context to be wrong about.
  if [[ -n "$COMMON_DIR" ]]; then
    if [[ -z "$CFG" ]]; then
      echo "[bot-commit] WARN: no second-shift config found (looked at \$SECOND_SHIFT_CONFIG, $DIR/.claude/, ${MAIN_ROOT:-<unresolved>}/.claude/) — committing with the repo default identity. If this repo DOES have a bot, its config is likely gitignored and absent from this worktree; export SECOND_SHIFT_CONFIG to the main checkout's copy." >&2
    else
      echo "[bot-commit] WARN: bot disabled in $CFG (tracker.bot.enabled is not true, or app.appName is unset) — committing with the repo default identity" >&2
    fi
  fi
  exec git -C "$DIR" commit "$@"
fi

BOT_LOGIN="${APP_NAME}[bot]"
# Reuses the COMMON_DIR hoisted above (shared across worktrees, never committed). Empty when
# $DIR is not a repo — reachable via an explicit $SECOND_SHIFT_CONFIG — so the cache is simply
# skipped rather than rooted at "/". The commit itself then fails on its own terms.
CACHE="${COMMON_DIR:+$COMMON_DIR/second-shift-bot-user-id}"

BOT_ID=""
if [[ -n "$CACHE" && -s "$CACHE" ]]; then
  BOT_ID="$(cat "$CACHE")"
else
  BOT_ID="$(gh api "users/${BOT_LOGIN}" --jq .id 2>/dev/null || true)"
  if [[ -n "$BOT_ID" && -n "$CACHE" ]]; then
    printf '%s' "$BOT_ID" > "$CACHE"
  fi
fi

if [[ -z "$BOT_ID" ]]; then
  echo "[bot-commit] WARN: could not resolve bot user id (gh api users/${BOT_LOGIN}) — committing with the repo default identity" >&2
  exec git -C "$DIR" commit "$@"
fi

exec git -C "$DIR" \
  -c user.name="$BOT_LOGIN" \
  -c user.email="${BOT_ID}+${BOT_LOGIN}@users.noreply.github.com" \
  commit "$@"
