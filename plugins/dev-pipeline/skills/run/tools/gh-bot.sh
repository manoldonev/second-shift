#!/usr/bin/env bash
# gh-bot.sh — single resolver + passthrough for the GitHub App bot wrapper.
#
# Three modes over one ladder (issue #92):
#   gh-bot.sh <args…>   resolve, then exec the wrapper with <args…>
#   gh-bot.sh --path    print the resolved wrapper path; exit 0 only when status=ok
#                       (still prints the path on missing-file / not-executable so
#                       install-gh-bot.sh can learn the destination before writing)
#   gh-bot.sh --status  print one classification token, always exit 0:
#                       disabled | ok | unset-var | missing-file | not-executable
#
# Ladder (claim-issue.sh was the most complete copy — worktree-safe root + ~ expansion):
#   1. the env var named by config tracker.bot.envVar (default GH_BOT), read
#      indirectly — keeps the mock seam claim-selftest / cost-block-selftest inject
#   2. config tracker.bot.wrapperPath, ~-expanded
#   3. $HOME/.config/<consumer-repo-dir-basename>/gh-as-bot.sh
#
# disabled short-circuits before rung 1: a bot-disabled repo never picks up a
# wrapper from the environment (cost-block-selftest AC-4 stray-var guard).
#
# Env:
#   SECOND_SHIFT_CONFIG     override config path
#   SECOND_SHIFT_REPO_ROOT  override the consumer repo root (basename + config default)
#
# bash 3.2 compatible (macOS ships it; claim-selftest runs there).

set -uo pipefail

MODE="passthrough"
case "${1:-}" in
  --path)   MODE="path";   shift ;;
  --status) MODE="status"; shift ;;
  --help|-h)
    sed -n '2,24p' "$0"
    exit 0
    ;;
esac

# --- resolve consumer root (worktree-safe) ------------------------------------
_root="${SECOND_SHIFT_REPO_ROOT:-}"
if [[ -z "$_root" ]]; then
  _common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n "$_common" ]]; then
    # Absolute-ize relative common-dir (linked worktrees report absolute; bare .git is relative).
    case "$_common" in
      /*) : ;;
      *)  _common="$(pwd)/$_common" ;;
    esac
    _root="$(cd "$_common/.." 2>/dev/null && pwd)" || _root=""
  fi
fi

_cfg="${SECOND_SHIFT_CONFIG:-}"
if [[ -z "$_cfg" && -n "$_root" ]]; then
  _cfg="$_root/.claude/second-shift.config.json"
fi

_enabled="false"
_env_var_name="GH_BOT"
_wrap_cfg=""
if [[ -n "$_cfg" && -f "$_cfg" ]] && command -v jq >/dev/null 2>&1; then
  _enabled="$(jq -r '.tracker.bot.enabled // false' "$_cfg" 2>/dev/null || echo false)"
  _t="$(jq -r '.tracker.bot.envVar // empty' "$_cfg" 2>/dev/null || true)"
  [[ -n "$_t" && "$_t" != "null" ]] && _env_var_name="$_t"
  _wrap_cfg="$(jq -r '.tracker.bot.wrapperPath // empty' "$_cfg" 2>/dev/null || true)"
  [[ "$_wrap_cfg" == "null" ]] && _wrap_cfg=""
fi
[[ "$_enabled" == "true" ]] || _enabled="false"

# --- classify -----------------------------------------------------------------
# Path formation always runs so --path can serve install-gh-bot.sh (destination
# before the file exists). Status classification is separate: disabled short-
# circuits BEFORE rung 1 so a bot-disabled repo never picks up a stray env var
# (cost-block-selftest AC-4).
_status="unset-var"
_path=""
_env_val=""

if [[ "$_enabled" == "true" ]]; then
  # Rung 1: indirect read of the configured env var name (not a hardcoded GH_BOT).
  eval "_env_val=\"\${${_env_var_name}:-}\""
fi

if [[ -n "$_env_val" ]]; then
  _path="$_env_val"
elif [[ -n "$_wrap_cfg" ]]; then
  # Rung 2: config wrapperPath, ~-expanded.
  _path="${_wrap_cfg/#\~/$HOME}"
elif [[ -n "$_root" ]]; then
  # Rung 3: install-gh-bot default location.
  _path="$HOME/.config/$(basename "$_root")/gh-as-bot.sh"
else
  _path=""
fi

if [[ "$_enabled" != "true" ]]; then
  _status="disabled"
elif [[ -z "$_path" ]]; then
  _status="unset-var"
elif [[ -x "$_path" ]]; then
  _status="ok"
elif [[ -e "$_path" ]]; then
  _status="not-executable"
else
  # Path formed but absent. When no rung supplied a concrete override and the
  # env var is empty, prefer unset-var so remediation names the env var +
  # settings.local.json rather than install-gh-bot (the historical empty-path
  # failure mode). A configured wrapperPath or an explicit env value that
  # points at a missing file is missing-file.
  if [[ -z "$_env_val" && -z "$_wrap_cfg" ]]; then
    _status="unset-var"
  else
    _status="missing-file"
  fi
fi

case "$MODE" in
  status)
    printf '%s\n' "$_status"
    exit 0
    ;;
  path)
    if [[ -n "$_path" ]]; then
      printf '%s\n' "$_path"
    fi
    if [[ "$_status" == "ok" ]]; then
      exit 0
    fi
    exit 1
    ;;
  passthrough)
    if [[ "$_status" != "ok" ]]; then
      echo "[gh-bot] cannot exec wrapper (status=$_status${_path:+ path=$_path})" >&2
      case "$_status" in
        disabled)
          echo "[gh-bot]   tracker.bot.enabled is not true — writes should use plain gh, not the bot wrapper." >&2
          ;;
        unset-var)
          echo "[gh-bot]   env var '${_env_var_name}' is unset and no wrapper resolved from config/default." >&2
          echo "[gh-bot]   Export ${_env_var_name} (e.g. in .claude/settings.local.json env block), or set tracker.bot.wrapperPath, or run tools/install-gh-bot.sh." >&2
          ;;
        missing-file)
          echo "[gh-bot]   wrapper missing at ${_path} — bootstrap with tools/install-gh-bot.sh <private-key.pem>" >&2
          ;;
        not-executable)
          echo "[gh-bot]   wrapper at ${_path} is not executable — chmod +x it, or re-run tools/install-gh-bot.sh." >&2
          ;;
      esac
      exit 1
    fi
    exec "$_path" "$@"
    ;;
esac
