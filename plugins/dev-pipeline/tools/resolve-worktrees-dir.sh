#!/usr/bin/env bash
# resolve-worktrees-dir.sh — single source of truth for a repo's pipeline-worktree base
# directory (config `topology.repos.<id>.worktreesDir`). Every call site that used to
# interpolate `${WORKTREES_DIR}` (or a locally-derived `WTDIR`) inline routes through
# this script instead. Its one live caller today is `preflight.sh`'s advisory report:
# #348 deleted the staged lane, and with it the other five (the intake step's pin, the
# worktree step's be-fe-pair loop and its single-repo block — worktree-add plus a
# separate statectl-persist fence — and the cleanup step's intake-pin backstop). The
# lean lane cuts its worktree by hand per `build-lean` step 3, so it is not a caller.
#
# `worktreesDir` is documented as OPTIONAL with a default of `../<repo>-worktrees`
# (schema/second-shift.config.schema.json) — but before this script existed, three call
# call sites never derived `WORKTREES_DIR` at
# all; the doc's `${WORKTREES_DIR}` interpolation just expanded empty, composing an
# absolute-root path (`/intake-pin-<n>`). Cleanup swallowed the resulting failure via an
# unconditional discard-and-continue — a completed run (#230) left `intake-pin-230`
# behind with zero signal (issue #237).
#
# Usage: resolve-worktrees-dir.sh <config-path> [repo-id]
#   repo-id omitted: auto-detect the HOST repo — the topology.repos entry whose `path`
#   is ".". Given: resolve that specific repo's entry (used by the be-fe-pair loop and
#   by preflight.sh, both of which iterate every configured repo, not just the host).
#
# Output contract: on success, the resolved worktrees dir (repo-root-relative, no
# trailing slash) on stdout, exit status zero. On failure — config unreadable, jq
# missing, or the requested/host repo entry does not exist — nothing on stdout, a named
# reason on stderr, a non-zero exit status. FAIL CLOSED: every caller MUST check the
# exit code before composing a path from the output; none may fall back to an empty
# variable.

set -u

CONFIG="${1:-}"
REPO_ID="${2:-}"

fail() { echo "resolve-worktrees-dir: $*" >&2; exit 1; }

[ -n "$CONFIG" ] || fail "usage: resolve-worktrees-dir.sh <config-path> [repo-id]"
[ -f "$CONFIG" ] || fail "config file not found: $CONFIG"
command -v jq >/dev/null 2>&1 || fail "jq is required."

if [ -z "$REPO_ID" ]; then
  REPO_ID="$(jq -r '(.topology.repos // {}) | to_entries[] | select(.value.path == ".") | .key' "$CONFIG" 2>/dev/null | head -n1)"
  [ -n "$REPO_ID" ] || fail "no topology.repos entry with path \".\" in $CONFIG — cannot resolve the host repo's worktrees dir."
fi

EXISTS="$(jq -r --arg r "$REPO_ID" '.topology.repos[$r] // empty' "$CONFIG" 2>/dev/null)"
[ -n "$EXISTS" ] || fail "no topology.repos.\"$REPO_ID\" entry in $CONFIG."

WTDIR="$(jq -r --arg r "$REPO_ID" '.topology.repos[$r].worktreesDir // empty' "$CONFIG" 2>/dev/null)"
[ -n "$WTDIR" ] || WTDIR="../${REPO_ID}-worktrees"

# Defensive backstop: the two lines above cannot produce an empty WTDIR once REPO_ID is
# non-empty, but a caller must never operate at filesystem root, so refuse rather than
# emit one on any future edit that breaks that invariant.
[ -n "$WTDIR" ] || fail "resolved worktrees dir is empty for repo \"$REPO_ID\" — refusing to compose a root-anchored path."

printf '%s\n' "$WTDIR"
