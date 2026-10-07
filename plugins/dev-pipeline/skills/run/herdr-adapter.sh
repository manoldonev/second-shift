#!/usr/bin/env bash
# herdr-adapter.sh — the bundled RUN_WATCH_CMD: a herdr workspace per ticket for a --detach run. Optional, off by default.
#
# usage: herdr-adapter.sh <issue> <repo> <detach-log> <worktree>   the watch call run.sh makes, once per launch
#        herdr-adapter.sh watch                                    the log pane (top): the log, live, and the sidebar state
#        herdr-adapter.sh transcript                               the transcript pane (below): the current session, turn by turn
#
# The watch call finds the workspace labeled `<repo>#<issue>` or creates it without taking focus, opens a new tab for this
# launch (the log pane at its root, the transcript pane split below it with the larger share) and, with
# RUN_WATCH_EDITOR=code|cursor, opens the worktree in that editor. The panes take their inputs only from the --env
# variables SS_LOG, SS_ISSUE and SS_ADAPTER: the text typed into a pane is fixed, so a log path carrying ' or $ or a
# space is never parsed by a shell. Every call names its workspace, tab and pane by the ids its own calls returned.
#
# It is a consumer of the run's log and nothing more: it never creates or removes a worktree, never starts or stops the
# herdr server, never types into a session and never closes the workspace (the operator does). run.sh reads nothing back.
# The sidebar state is cosmetic: a custom: source is a soft overlay herdr does not treat as authoritative.
#
# env:  HERDR_BIN          the herdr binary (default herdr; tests inject a fake)
#       RUN_WATCH_EDITOR   code | cursor: `<editor> -n <worktree>` once per launch; unset = no editor
# exit: 0 the tab is open · 1 a herdr call failed (run.sh logs it as one `watch:` line) · 2 usage
set -uo pipefail
HERDR="${HERDR_BIN:-herdr}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SOURCE=custom:second-shift
die() { echo "herdr-adapter: $*" >&2; exit 1; }

# ---------------------------------------------------------------- the log pane
# Reads the log from its first line and keeps following it, printing every line. A `round N of M` line reports working;
# the BARE `terminal: <slug>` line (run.sh writes each slug twice, the second time alone on its line) reports idle on
# approved and blocked with the slug otherwise; `detached run exited rc=N` ends it, blocked with the code when no
# terminal line came first (a run that died, or was killed, without one).
follow() { # follow <file> <callback> — calls <callback> <line> per complete line from the first; stops when it returns 1
  local buf="" l
  until [ -f "$1" ]; do sleep 0.5; done
  exec 3< "$1"
  while :; do
    if IFS= read -r l <&3; then "$2" "$buf$l" || break; buf=""
    else buf="$buf$l"; sleep 0.5; fi
  done
  exec 3<&-
}
report() { # report <state> <message>
  "$HERDR" pane report-agent "$PANE" --source "$SOURCE" --agent "ss-$SS_ISSUE" --state "$1" --message "$2" >/dev/null 2>&1 \
    || echo "herdr-adapter: could not report '$1' to pane $PANE" >&2
}
TERMINAL=""
watch_line() {
  printf '%s\n' "$1"
  if [[ "$1" =~ round\ ([0-9]+)\ of\ ([0-9]+) ]]; then report working "round ${BASH_REMATCH[1]} of ${BASH_REMATCH[2]}"; fi
  if [[ "$1" =~ ^terminal:\ ([^[:space:]]+)$ ]]; then
    TERMINAL="${BASH_REMATCH[1]}"
    if [ "$TERMINAL" = approved ]; then report idle approved; else report blocked "$TERMINAL"; fi
  fi
  if [[ "$1" =~ detached\ run\ exited\ rc=([0-9]+)$ ]]; then
    [ -n "$TERMINAL" ] || report blocked "exited rc=${BASH_REMATCH[1]} with no terminal line"
    return 1
  fi
}
cmd_watch() {
  : "${SS_LOG:?SS_LOG is unset}" "${SS_ISSUE:?SS_ISSUE is unset}"
  PANE="${HERDR_PANE_ID:?HERDR_PANE_ID is unset: run this inside a herdr pane}"
  follow "$SS_LOG" watch_line
  echo "[second-shift] the run has exited; this pane keeps its output"
}

# ---------------------------------------------------------------- the transcript pane
# Follows the log's `session: <role> <attempt> <uuid> <glob>` lines and renders the newest session's transcript one line
# per event: an assistant text block (its first line), a tool call (its name and key argument), a failed tool result.
# Thinking, successful results, every other entry type, a user entry with string content and any sidechain entry are
# skipped. A line that is not JSON, or lacks the fields of an event it would render, is one `[unparsed]` line.
# shellcheck disable=SC2016  # jq program text
RENDER='
  def cut: .[0:120];
  def firstline: (split("\n") | map(select(test("\\S"))) | .[0]) // "";
  def key($n; $i):
    if ($n == "Read" or $n == "Edit" or $n == "Write") then $i.file_path
    elif $n == "Bash" then $i.command
    elif ($n == "Grep" or $n == "Glob") then $i.pattern
    else "" end;
  def keyed($n): ["Read", "Edit", "Write", "Bash", "Grep", "Glob"] | any(. == $n);
  def unparsed: "\($p) [unparsed]";
  def result_text: if type == "string" then . elif type == "array" then (map(select(type == "object" and .type == "text") | .text | strings) | join("\n")) else "" end;
  (try fromjson catch null) as $e
  | if ($e | type) != "object" then unparsed
    elif $e.isSidechain == true then empty
    elif $e.type == "assistant" then
      if ($e.message.content | type) != "array" then unparsed
      else $e.message.content[]
        | if type != "object" then unparsed
          elif .type == "text" then (if (.text | type) == "string" then "\($p) \(.text | firstline | cut)" else unparsed end)
          elif .type == "tool_use" then
            (.name) as $n
            | if ($n | type) != "string" then unparsed
              elif keyed($n) | not then "\($p) \($n)"
              elif (key($n; .input // {}) | type) != "string" then unparsed
              else "\($p) \($n) \(key($n; .input) | firstline | cut)" end
          else empty end
      end
    elif $e.type == "user" then
      if ($e.message.content | type) == "string" then empty
      elif ($e.message.content | type) != "array" then unparsed
      else $e.message.content[] | select(type == "object" and .type == "tool_result" and .is_error == true)
        | "\($p) ERROR \(.content | result_text | firstline | cut)"
      end
    else empty end'
render() { # render <prefix> — stdin: raw transcript lines
  jq -rR --arg p "$1" "$RENDER" 2>/dev/null || echo "$1 [unparsed]"
}
T_LABEL=""; T_UUID=""; T_GLOB=""; T_FILE=""; T_BUF=""; T_WAITING=0; T_EXITED=0
t_resolve() { # t_resolve [quiet] — opens the current session's transcript once it exists; says once that it is waiting
  local f
  [ -n "$T_LABEL" ] && [ -z "$T_FILE" ] || return 0
  # the glob is built here from the uuid, never re-parsed from the log line: a home path with a space stays one word
  for f in "$HOME"/.claude*/projects/*/"$T_UUID".jsonl; do [ -f "$f" ] && { T_FILE="$f"; exec 4< "$f"; return 0; }; done
  [ -n "${1:-}" ] || [ "$T_WAITING" -eq 1 ] || { echo "[$T_LABEL] waiting for its transcript ($T_GLOB)"; T_WAITING=1; }
}
t_drain() { # renders every complete line the current transcript has gained
  local l batch=""
  [ -n "$T_FILE" ] || return 0
  while IFS= read -r l <&4; do batch="$batch$T_BUF$l"$'\n'; T_BUF=""; done
  T_BUF="$T_BUF$l"
  [ -z "$batch" ] || printf '%s' "$batch" | render "[$T_LABEL]"
}
t_leave() { # done with the current session: what is left of it is rendered, or said to be missing
  [ -n "$T_LABEL" ] || return 0
  t_resolve quiet; t_drain
  if [ -n "$T_FILE" ]; then [ -z "$T_BUF" ] || printf '%s\n' "$T_BUF" | render "[$T_LABEL]"; exec 4<&-
  else echo "no transcript for $T_LABEL"; fi
  T_LABEL=""; T_UUID=""; T_FILE=""; T_BUF=""; T_WAITING=0
}
transcript_line() {
  if [[ "$1" =~ \ session:\ ([a-z]+)\ ([^[:space:]]+)\ ([0-9a-f-]+)\ ([^[:space:]]+)$ ]]; then
    t_leave
    T_LABEL="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; T_UUID="${BASH_REMATCH[3]}"; T_GLOB="${BASH_REMATCH[4]}"
    echo "──── $T_LABEL · session $T_UUID ────"
  elif [[ "$1" =~ detached\ run\ exited\ rc=[0-9]+$ ]]; then
    T_EXITED=1; return 1
  fi
}
cmd_transcript() {
  : "${SS_LOG:?SS_LOG is unset}"
  local buf="" l
  until [ -f "$SS_LOG" ]; do sleep 0.5; done
  exec 3< "$SS_LOG"
  while :; do # one pass: every new log line, then whatever the current transcript gained
    while IFS= read -r l <&3; do transcript_line "$buf$l" || break; buf=""; done
    buf="$buf$l"
    [ "$T_EXITED" -eq 0 ] || break
    t_resolve; t_drain
    sleep 0.5
  done
  exec 3<&-
  t_leave
  echo "[second-shift] the run has exited; this pane keeps its output"
}

# ---------------------------------------------------------------- the watch call
cmd_open() {
  local issue="$1" repo="$2" log="$3" wt="$4" label ws out tab root below
  [ -f "$log" ] || die "no run log at $log"
  [ -d "$wt" ] || die "no worktree at $wt"
  # a launch from inside a herdr pane carries that pane's ids; nothing here may fall back to them (run.sh drops them too)
  unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
  label="$repo#$issue"
  out="$("$HERDR" workspace list 2>&1)" || die "workspace list failed: $out"
  ws="$(jq -r --arg l "$label" '[.result.workspaces[]? | select(.label == $l) | .workspace_id] | first // empty' <<<"$out" 2>/dev/null)" \
    || die "workspace list did not answer JSON: $out"
  if [ -z "$ws" ]; then
    out="$("$HERDR" workspace create --cwd "$wt" --label "$label" --no-focus 2>&1)" || die "workspace create failed: $out"
    ws="$(jq -r '.result.workspace.workspace_id // empty' <<<"$out" 2>/dev/null)"; [ -n "$ws" ] || die "workspace create returned no id: $out"
  fi
  local envs=(--env "SS_LOG=$log" --env "SS_ISSUE=$issue" --env "SS_ADAPTER=$SELF")
  out="$("$HERDR" tab create --workspace "$ws" --cwd "$wt" --label "$(basename "$log" .log)" "${envs[@]}" --no-focus 2>&1)" || die "tab create failed: $out"
  tab="$(jq -r '.result.tab.tab_id // empty' <<<"$out" 2>/dev/null)"; root="$(jq -r '.result.root_pane.pane_id // empty' <<<"$out" 2>/dev/null)"
  [ -n "$tab" ] && [ -n "$root" ] || die "tab create returned no tab or root pane id: $out"
  # shellcheck disable=SC2016  # fixed text: the pane's own shell expands $SS_ADAPTER from its --env
  out="$("$HERDR" pane run "$root" 'bash "$SS_ADAPTER" watch' 2>&1)" || die "pane run (watch) failed: $out"
  # D-24: the transcript pane below the log pane, with the larger share (the ratio is the first pane's)
  out="$("$HERDR" pane split "$root" --direction down --ratio 0.35 --cwd "$wt" "${envs[@]}" --no-focus 2>&1)" || die "pane split failed: $out"
  below="$(jq -r '.result.pane.pane_id // empty' <<<"$out" 2>/dev/null)"; [ -n "$below" ] || die "pane split returned no pane id: $out"
  # shellcheck disable=SC2016  # fixed text, as above
  out="$("$HERDR" pane run "$below" 'bash "$SS_ADAPTER" transcript' 2>&1)" || die "pane run (transcript) failed: $out"
  echo "herdr: workspace $ws ($label), tab $tab: log pane $root, transcript pane $below"
  case "${RUN_WATCH_EDITOR:-}" in
    "") : ;;
    code|cursor) "$RUN_WATCH_EDITOR" -n "$wt" >/dev/null 2>&1 < /dev/null || die "$RUN_WATCH_EDITOR -n $wt failed" ;;
    *) echo "herdr-adapter: RUN_WATCH_EDITOR='$RUN_WATCH_EDITOR' is not code or cursor; no editor opened" >&2 ;;
  esac
}

case "${1:-}" in
  watch) cmd_watch ;;
  transcript) cmd_transcript ;;
  -h|--help) awk 'NR>1 && /^set -uo pipefail/{exit} NR>1' "$0" ;;
  *) [ $# -eq 4 ] || { echo "usage: herdr-adapter.sh <issue> <repo> <detach-log> <worktree> | watch | transcript" >&2; exit 2; }
     cmd_open "$@" ;;
esac
