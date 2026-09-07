#!/usr/bin/env bash
# lane-bench-arm.sh — the lane bench's arm wrapper. Used as `LEAN_SPAWN_BIN`, it loads one
# second-shift ref into the lane's payload sessions and is otherwise invisible.
#
# WHY A WRAPPER AND NOT A FLAG. An arm is a git worktree of second-shift at a commit
# (docs/lane-bench.md), and the only way to put that worktree in front of a payload session is
# `--setting-sources ''` plus one `--plugin-dir` per plugin directory in it. The scheduler has no
# opinion about plugins and should not grow one for a bench, so the flags are appended by a handle
# the bench substitutes for the session binary. `orchestrate-lean.sh` routes EVERY control-plane
# call through `$SPAWN_BIN` — the dispatch, `agents --json --all`, and `stop <id>` — so this
# script has to serve all three and may only touch the first.
#
# TRANSPARENT, AND THAT IS A CONTRACT, NOT A COURTESY. The scheduler parses the session id out of
# the child's `backgrounded · <id> · <name>` line by field position, so a single byte of this
# script's own on stdout would break every spawn. It `exec`s: the child's stdout, its stderr and
# its exit status are this process's, with nothing wrapped around them.
#
# WHAT IT DOES NOT ADD. No `--settings` block: the scheduler writes its own, carrying the per-role
# `LEAN_RUN_MODEL` and the forwarded `SECOND_SHIFT_CONFIG`, and a second one here would replace it
# rather than merge with it (#811 D-26, OR-4's default of none). No `--bare` either — it kills
# subscription auth — and a caller that passes one is not refused: the decision belongs to the
# caller, not to a handle.
#
#   LEAN_ARM_MANIFEST   required. One plugin directory per line, absolute. Written per cell by
#                       `lane-bench.sh run`; there are no checked-in manifests.
#   LEAN_ARM_ADD_DIRS   optional. One absolute directory per line, appended as `--add-dir` on a
#                       session dispatch only — the worktrees directory the lane gate builds in.
#                       The series records what it was set to (lane-bench SERIES.md, OR-4).
#   LEAN_ARM_ALLOWED_TOOLS  optional. One tool name per line, passed as `--allowedTools` on a
#                       session dispatch only — the harness tools the gate's flow reaches for
#                       (`EnterWorktree`, `ExitWorktree`). Recorded beside the directories.
#
# EXIT: whatever the session binary exits · 2 a refusal on stderr, nothing exec'd.
set -uo pipefail

die() { echo "[lane-bench-arm] $*" >&2; exit 2; }

# VALIDATED ON EVERY INVOCATION, dispatch or not. A bench whose manifest is unreadable is
# misconfigured for the whole cell, and letting `agents` and `stop` succeed against it would mean
# the run only discovers that at the moment it spawns — after the issue is filed and the receipt
# written. The refusal is about the bench's configuration, not about this argv.
MANIFEST="${LEAN_ARM_MANIFEST:-}"
[ -n "$MANIFEST" ] || die "LEAN_ARM_MANIFEST is unset — this wrapper exists to load an arm's plugin directories and has none to load. Set it, or use the session binary directly."
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] \
  || die "LEAN_ARM_MANIFEST names no readable file: $MANIFEST"

# Read whole, then validated, then appended — an entry that names nothing must refuse BEFORE the
# first flag is appended, so a partly-built argv can never reach the session binary.
ENTRIES=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  ENTRIES+=("$line")
done < "$MANIFEST"

[ "${#ENTRIES[@]}" -gt 0 ] || die "LEAN_ARM_MANIFEST is empty: $MANIFEST — an arm with no plugin directory is not the skeleton, it is no kit at all"

for d in "${ENTRIES[@]}"; do
  [ -d "$d" ] || die "the manifest names a directory that does not exist: $d (from $MANIFEST)"
done

# A SESSION DISPATCH, AND NOTHING ELSE, GETS THE FLAGS. `agents --json --all` and `stop <id>` are
# control-plane calls on the same handle: appending `--plugin-dir` to either would at best be
# ignored and at worst make the call unparseable, and the scheduler counts an unreadable listing
# against the payload.
DISPATCH=0
for a in "$@"; do
  case "$a" in --bg|-p|--print) DISPATCH=1; break ;; esac
done

if [ "$DISPATCH" -eq 1 ]; then
  # APPENDED, never inserted: the scheduler's own argv — permission mode, model, name,
  # disallowed tools, settings block, and the prompt as the trailing positional — reaches the
  # binary byte-for-byte in its own order, and this script's contribution is a suffix a reader of
  # `ps` can see whole.
  set -- "$@" --setting-sources ''
  for d in "${ENTRIES[@]}"; do
    set -- "$@" --plugin-dir "$d"
  done
  # THE ONE GRANT (lane-bench #2, epic OR-4). Under `--setting-sources ''` a payload runs with no
  # permission grants at all, and `--permission-mode auto` alone stops the BUILD session the moment
  # the gate works inside the lane worktree — a sibling of the checkout, outside the session's
  # cwd — so the dry run ended `blocked` with no PR. `LEAN_ARM_ADD_DIRS` names the directories to
  # allow, one absolute path per line, appended as `--add-dir` on a dispatch and on nothing else.
  # It is the bench's to set, identical across arms, and recorded in the series' SERIES.md; empty
  # means no grant, which is the pre-dry-run behaviour.
  if [ -n "${LEAN_ARM_ADD_DIRS:-}" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && set -- "$@" --add-dir "$d"
    done <<< "$LEAN_ARM_ADD_DIRS"
  fi
  # THE OTHER GRANT, same dry run: with the directory allowed the BUILD session still ended
  # `blocked` — on `EnterWorktree`, the harness tool it reached for to move into the lane
  # worktree, which asks for approval under empty setting sources whatever the permission mode.
  # `LEAN_ARM_ALLOWED_TOOLS` names tools to allow, one per line, passed as one `--allowedTools`
  # on a dispatch and on nothing else. Allowed, not disallowed: the payload keeps the tool set the
  # harness gives it, identically in every arm.
  if [ -n "${LEAN_ARM_ALLOWED_TOOLS:-}" ]; then
    set -- "$@" --allowedTools
    while IFS= read -r t; do
      [ -n "$t" ] && set -- "$@" "$t"
    done <<< "$LEAN_ARM_ALLOWED_TOOLS"
  fi
fi

exec claude "$@"
