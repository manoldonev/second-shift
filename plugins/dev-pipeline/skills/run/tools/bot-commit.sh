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

set -euo pipefail

DIR="."
if [[ "${1:-}" == "-C" ]]; then
  DIR="${2:?bot-commit: -C requires a directory}"
  shift 2
fi

CFG="${SECOND_SHIFT_CONFIG:-$DIR/.claude/second-shift.config.json}"
# Fall back to repo-root config when invoked from a subdir of the worktree.
if [[ ! -f "$CFG" ]]; then
  ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || echo "$DIR")"
  CFG="$ROOT/.claude/second-shift.config.json"
fi

BOT_ENABLED="false"
APP_NAME=""
if [[ -f "$CFG" ]]; then
  BOT_ENABLED="$(jq -r '.tracker.bot.enabled // false' "$CFG" 2>/dev/null || echo false)"
  APP_NAME="$(jq -r '.tracker.bot.app.appName // empty' "$CFG" 2>/dev/null || true)"
fi

if [[ "$BOT_ENABLED" != "true" || -z "$APP_NAME" ]]; then
  # Bot disabled or unconfigured — the SKILL.md contract is "commit as the repo default".
  exec git -C "$DIR" commit "$@"
fi

BOT_LOGIN="${APP_NAME}[bot]"
# --git-common-dir is RELATIVE to the repo (usually ".git") — resolve it from $DIR, never
# from the helper's own CWD (a CWD-relative cd lands the cache in whatever repo the session
# happens to sit in).
COMMON_DIR="$(cd "$DIR" && cd "$(git rev-parse --git-common-dir)" && pwd)"
CACHE="$COMMON_DIR/second-shift-bot-user-id"

BOT_ID=""
if [[ -s "$CACHE" ]]; then
  BOT_ID="$(cat "$CACHE")"
else
  BOT_ID="$(gh api "users/${BOT_LOGIN}" --jq .id 2>/dev/null || true)"
  if [[ -n "$BOT_ID" ]]; then
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
