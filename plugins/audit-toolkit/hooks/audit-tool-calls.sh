#!/usr/bin/env bash
# Append one row per tool call to a per-session JSONL ledger.
# Wired to PostToolUse / PostToolUseFailure / SubagentStop /
# UserPromptExpansion via the plugin's hooks/hooks.json — fires automatically
# once the audit-toolkit plugin is enabled. (Legacy/manual fallback for repos
# not using the plugin: templates/settings.audit-template.json.)
#
# Two roles, deliberately split. For `/audit` and `/audit-history` the ledger is
# ADVISORY — a visibility signal for manual review that blocks nothing. For pipeline
# gates it is ADMISSIBLE EVIDENCE: `target` below is what lets a completion
# precondition assert "a Read of stages/9-*.md happened inside this stage's window"
# instead of trusting the executor's own claim that it did. Nothing in THIS script
# blocks anything; it only writes rows honest enough to be checked against.

set -uo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(jq -r '.session_id // empty' <<<"$PAYLOAD")
[ -z "$SESSION_ID" ] && exit 0

CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD")
EVENT=$(jq -r '.hook_event_name // empty' <<<"$PAYLOAD")
TOOL=$(jq -r '.tool_name // empty' <<<"$PAYLOAD")
SUBAGENT=$(jq -r '.tool_input.subagent_type // .agent_type // empty' <<<"$PAYLOAD")
COMMAND_NAME=$(jq -r '.command_name // empty' <<<"$PAYLOAD")

# The identifying input, per tool — what the call ran ON, not merely that it ran.
# Without it the ledger can prove *a* Read happened somewhere in the session and
# nothing more, which is why it could not serve as gate evidence.
#
# Key names carry fallback chains for the same reason line 21 above does
# (`.tool_input.subagent_type // .agent_type`): the payload shape is the harness's
# to change, and a single wrong key fails SILENTLY — it emits "" while every
# selftest stays green, leaving the ledger looking instrumented when it is not.
# Prefer a redundant alternative to a confident guess.
#
# Bash is the one branch with real exposure. First line, 200 chars is enough to
# identify `statectl.sh set-stage …` or `yarn render:verify …` without dumping full
# argv or stdin — but it is NOT "non-secret by construction": a prefix is the worst
# window for that, since flags and env assignments precede payloads
# (`gh api -H "Authorization: Bearer …"`). What bounds the risk is the ledger's
# locality — gitignored, 0600 in a 0700 dir, never transmitted — not the slice.
# Recording an inline credential here remains possible; that is a known, accepted
# trade for keeping `/audit`'s Bash visibility.
TARGET=$(jq -r '
  if   .tool_name == "Read" or .tool_name == "Edit" or .tool_name == "Write"
  then (.tool_input.file_path // .tool_input.path // empty)
  elif .tool_name == "Bash"
  then ((.tool_input.command // "") | split("\n")[0] | .[0:200])
  elif .tool_name == "Skill"
  then (.tool_input.skill // .tool_input.skill_name // .tool_input.name // empty)
  elif .tool_name == "Workflow"
  then (.tool_input.scriptPath // .tool_input.name // empty)
  else empty end' <<<"$PAYLOAD")

OUTCOME="ok"
[ "$EVENT" = "PostToolUseFailure" ] && OUTCOME="fail"

# WHERE THE LEDGER LIVES. Anchored on the MAIN checkout, never on the directory the
# session happens to be running in. A lean run works in a linked worktree by contract,
# and every reader resolves `--git-common-dir/..`: lean-gate.sh's `entry` precondition,
# lean-reconcile.sh, statectl.sh's `ledger_dir()`. Writing beside the worktree instead
# put the ledger where none of them look, with two opposite failure modes — an honest
# run refused at `entry` for a ledger it had just written, and a verdict record naming a
# session reconcile could not resolve, which reads as a forgery signal. One directory
# per repo family is also what /audit-history's cross-session sweep already assumes.
#
# `${CLAUDE_PROJECT_DIR:-$CWD}` stays the starting point — today's precedence, unchanged;
# only what is DERIVED from it moves. The payload's `cwd` can wander per call, so it
# stays the fallback rather than the primary.
#
# Resolved per invocation, uncached: one `git rev-parse` beside the six `jq` calls and
# the `date` already here, and the result is a stable per-repo string a memo could hold
# later without moving the contract. Marginal, but unmeasured — no claim is made.
#
# The failure path is today's path, never a hard error: this script must not block a
# session (see the masthead), and lean-gate.sh's `entry` already fails closed on the
# resulting absent ledger, which is where the refusal is actionable.
# LOCKSTEP-BEGIN audit-ledger-dir
audit_ledger_dir() { # audit_ledger_dir <base-dir> — the main checkout's .claude/audit
  local base="$1" common="" root=""
  common="$(git -C "$base" rev-parse --git-common-dir 2>/dev/null)"
  if [ -n "$common" ]; then
    # `git -C` answers relative to <base>: the main checkout prints `.git` (or `../.git`
    # from a subdirectory), a linked worktree prints the main checkout's absolute path.
    case "$common" in
      /*) : ;;
      *)  common="$base/$common" ;;
    esac
    root="$(cd "$common/.." 2>/dev/null && pwd)"
  fi
  [ -n "$root" ] || root="$base"
  printf '%s\n' "$root/.claude/audit"
}
# LOCKSTEP-END audit-ledger-dir

AUDIT_DIR="$(audit_ledger_dir "${CLAUDE_PROJECT_DIR:-$CWD}")"
mkdir -p "$AUDIT_DIR" 2>/dev/null && chmod 700 "$AUDIT_DIR" 2>/dev/null
LEDGER="$AUDIT_DIR/${SESSION_ID}.jsonl"

# Atomic create-if-absent: `>>` (append) never truncates and creates the file
# when missing; `umask 077` gives a freshly created ledger mode 0600. This
# avoids the check-then-create TOCTOU of `[ ! -e ] && install -m 600 /dev/null`
# — under concurrent hook invocations sharing one session_id, two processes
# could both pass the `-e` test and `install` would truncate the ledger,
# clobbering rows written in between. Append-create has no truncation window.
( umask 077
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$SESSION_ID" \
    --arg event "$EVENT" \
    --arg tool "$TOOL" \
    --arg subagent "$SUBAGENT" \
    --arg command_name "$COMMAND_NAME" \
    --arg target "$TARGET" \
    --arg outcome "$OUTCOME" \
    '{ts:$ts, session_id:$sid, event:$event, tool:$tool, subagent:$subagent, command_name:$command_name, target:$target, outcome:$outcome}' \
    >> "$LEDGER" 2>/dev/null
)

exit 0
