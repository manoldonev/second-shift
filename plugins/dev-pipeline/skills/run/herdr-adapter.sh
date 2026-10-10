#!/usr/bin/env bash
# herdr-adapter.sh — the bundled RUN_WATCH_CMD: a herdr workspace per ticket for a --detach run, and a launcher for the
# operator's interactive builds and reviews. Optional, off by default.
#
# usage: herdr-adapter.sh <issue> <repo> <detach-log> <worktree>   the watch call run.sh makes, once per launch
#        herdr-adapter.sh watch                                    the log pane (top): the log, live, and the sidebar state
#        herdr-adapter.sh transcript                               the transcript pane (below): the current session, turn by turn
#        herdr-adapter.sh build <ticket>...                        an interactive /dev-pipeline:build session per ticket
#        herdr-adapter.sh review <pr>                              a fresh /dev-pipeline:review session in the PR's ticket workspace
#
# build and review run from any checkout of the repo (or a subdirectory of one). The main checkout is the physical parent
# of `git rev-parse --path-format=absolute --git-common-dir`, the repo slug its basename; tracker.type comes from
# SECOND_SHIFT_CONFIG, else <main>/.claude/second-shift.config.json, default github. A ticket is a positive integer under
# github, a key such as PROJ-12 under jira (tracker.keyPattern, when set, as run.sh checks it). Each ticket gets the
# workspace labeled `<repo>#<ticket>` (found by label, else created without focus, on the main checkout) and a new `build`
# tab whose pane runs, once its shell has drawn (10 s at most), the fixed text
#   env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:build $SS_ISSUE" --add-dir "$SS_WT"
# with SS_WT the worktree run.sh will cut (${RUN_WORKTREE_ROOT:-<parent of main>/<repo>-worktrees}/<ticket>), SS_ISSUE
# and SS_ADAPTER (this script) as --env, and RUN_WORKTREE_ROOT forwarded when set. The prompt precedes --add-dir, which
# is variadic. One ticket failing does not stop the others. With RUN_WATCH_EDITOR=code|cursor, a detached waiter opens
# the worktree once it appears (one waiter per ticket at a time); after SS_EDITOR_WAIT_SECS (default 300) it gives up
# and writes one line to ${TMPDIR:-/tmp}/herdr-adapter-<repo>-<ticket>-editor.log. review resolves the PR's one ticket
# (github: gh's closingIssuesReferences; jira: `Closes [<KEY>]` under the body's `### Jira Items` heading) and opens a
# `review` tab running `env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:review $SS_PR"`. Neither writes to run.sh, the
# lane, the record or the tracker; their herdr calls are workspace list/create, tab create, pane wait-output and pane run.
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
# env:  HERDR_BIN            the herdr binary (default herdr; tests inject a fake)
#       RUN_WATCH_EDITOR     code | cursor: `<editor> -n <worktree>` once per launch; unset = no editor
#       SS_EDITOR_WAIT_SECS  build's editor wait bound in seconds (default 300)
# exit: 0 the tab is open · 1 a herdr call failed (run.sh logs it as one `watch:` line) · 2 usage
#       build: 0 every ticket opened · 1 any failed · 2 usage · review: 0 opened · 1 failed, or no single ticket · 2 usage
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
# per event: an assistant text block (its first line), a tool call (its name and key argument), a failed tool result —
# `ERROR <first line>` for a permission denial only, `exit <code> <next line>` for a non-zero exit, `failed <first line>`
# for any other tool error (#964 D-5 D-6), so a clean run shows no ERROR line.
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
        | (.content | result_text | split("\n") | map(select(test("\\S")))) as $ls | ($ls[0] // "") as $f
        | if ($f | startswith("Permission for this tool use was denied") or startswith("Permission to use ")) then "\($p) ERROR \($f | cut)"
          elif ($f | test("^Exit code [0-9]+")) then "\($p) exit \($f | capture("^Exit code (?<n>[0-9]+)").n)\(if $ls[1] then " " + $ls[1] else "" end | cut)"
          else "\($p) failed \($f | cut)" end
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
ws_for() { # ws_for <label> <cwd> — sets WS to the workspace labeled <label>, else one created unfocused on <cwd>.
  # On a failed call it sets WHY and the caller's $out (the call's answer) and returns 1.
  out="$("$HERDR" workspace list 2>&1)" || { WHY="workspace list failed"; return 1; }
  WS="$(jq -r --arg l "$1" '[.result.workspaces[]? | select(.label == $l) | .workspace_id] | first // empty' <<<"$out" 2>/dev/null)" \
    || { WHY="workspace list did not answer JSON"; return 1; }
  [ -z "$WS" ] || return 0
  out="$("$HERDR" workspace create --cwd "$2" --label "$1" --no-focus 2>&1)" || { WHY="workspace create failed"; return 1; }
  WS="$(jq -r '.result.workspace.workspace_id // empty' <<<"$out" 2>/dev/null)"; [ -n "$WS" ] || { WHY="workspace create returned no id"; return 1; }
}
cmd_open() {
  local issue="$1" repo="$2" log="$3" wt="$4" label ws out tab root below
  [ -f "$log" ] || die "no run log at $log"
  [ -d "$wt" ] || die "no worktree at $wt"
  # a launch from inside a herdr pane carries that pane's ids; nothing here may fall back to them (run.sh drops them too)
  unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
  label="$repo#$issue"
  ws_for "$label" "$wt" || die "$WHY: $out"; ws="$WS"
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

# ---------------------------------------------------------------- build and review: the operator's own sessions
usage() { echo "herdr-adapter: $*" >&2; echo "usage: herdr-adapter.sh build <ticket>... | review <pr>" >&2; exit 2; }
repo_context() { # sets MAIN SLUG TRACKER KEY_PATTERN from the checkout the call runs in (D-23), the config as run.sh reads it
  local common cfg
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || usage "not inside a git checkout"
  MAIN="$(cd "$common/.." 2>/dev/null && pwd -P)" || usage "cannot resolve the main checkout from $common"
  SLUG="$(basename "$MAIN")"
  cfg="${SECOND_SHIFT_CONFIG:-$MAIN/.claude/second-shift.config.json}"; TRACKER=github; KEY_PATTERN=""
  if [ -f "$cfg" ]; then
    jq -e . "$cfg" >/dev/null 2>&1 || usage "$cfg is present but not JSON"
    TRACKER="$(jq -r '.tracker.type // "github"' "$cfg")"; KEY_PATTERN="$(jq -r '.tracker.keyPattern // empty' "$cfg")"
  fi
  case "$TRACKER" in github|jira) : ;; *) usage "tracker.type '$TRACKER' is not github or jira" ;; esac
}
valid_ticket() { # the key run.sh would accept: tracker.keyPattern when set, then a github number or a jira key's shape
  if [ -n "$KEY_PATTERN" ] && ! printf '%s' "$1" | grep -qiE "^($KEY_PATTERN)$"; then return 1; fi
  if [ "$TRACKER" = github ]; then [[ "$1" =~ ^[1-9][0-9]*$ ]]; else [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_]*-[1-9][0-9]*$ ]]; fi
}
fail() { echo "herdr-adapter: $label: $* (${out//$'\n'/ })" >&2; } # one line naming the ticket: open_tab's $label and $out
open_tab() { # open_tab <ticket> <tab label> <fixed text> <--env args...> — prints one failure line and returns 1 on any failed call
  local tlabel="$2" text="$3" label="$SLUG#$1" ws out tab pane; shift 3
  ws_for "$label" "$MAIN" || { fail "$WHY"; return 1; }; ws="$WS"
  out="$("$HERDR" tab create --workspace "$ws" --cwd "$MAIN" --label "$tlabel" "$@" --no-focus 2>&1)" || { fail "tab create failed"; return 1; }
  tab="$(jq -r '.result.tab.tab_id // empty' <<<"$out" 2>/dev/null)"; pane="$(jq -r '.result.root_pane.pane_id // empty' <<<"$out" 2>/dev/null)"
  [ -n "$tab" ] && [ -n "$pane" ] || { fail "tab create returned no tab or root pane id"; return 1; }
  # D-27: a login shell still loading its rc files may drop typed text; wait for its first output, then type anyway (OR-2)
  "$HERDR" pane wait-output "$pane" --regex '\S' --timeout 10000 >/dev/null 2>&1 \
    || echo "herdr-adapter: $label: did not see the shell in pane $pane ready within 10 s; typing the command anyway" >&2
  out="$("$HERDR" pane run "$pane" "$text" 2>&1)" || { fail "pane run failed"; return 1; }
  echo "herdr: $label: workspace $ws, tab $tab ($tlabel), pane $pane"
}
start_editor_waiter() { # start_editor_waiter <ticket> <worktree> — D-32 D-33: detached, one per ticket at a time
  local tmp="${TMPDIR:-/tmp}" lock pid secs
  case "${RUN_WATCH_EDITOR:-}" in
    "") return 0 ;;
    code|cursor) : ;;
    *) echo "herdr-adapter: RUN_WATCH_EDITOR='$RUN_WATCH_EDITOR' is not code or cursor; no editor opened" >&2; return 0 ;;
  esac
  secs="${SS_EDITOR_WAIT_SECS:-300}"
  [[ "$secs" =~ ^[0-9]+$ ]] || { echo "herdr-adapter: SS_EDITOR_WAIT_SECS='$secs' is not a whole number of seconds; waiting 300" >&2; secs=300; }
  tmp="${tmp%/}"; lock="$tmp/herdr-adapter-$SLUG-$1-editor.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    pid="$(cat "$lock/pid" 2>/dev/null)"
    # a lock whose waiter is gone (killed, or the machine slept through it) is stale; one with no pid yet is being taken
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$lock"; mkdir "$lock" 2>/dev/null || return 0
    else echo "herdr: $SLUG#$1: an editor waiter for $2 is already waiting"; return 0; fi
  fi
  command -v perl >/dev/null 2>&1 || { rm -rf "$lock"; echo "herdr-adapter: $SLUG#$1: no perl to detach the editor waiter; no editor opened" >&2; return 0; }
  nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' -- \
    bash "$SELF" editor-wait "$RUN_WATCH_EDITOR" "$2" "$tmp/herdr-adapter-$SLUG-$1-editor.log" "$lock" "$secs" > /dev/null 2>&1 < /dev/null &
  { echo "$!" > "$lock/pid"; } 2>/dev/null   # a waiter that found the worktree at once has already released the lock
}
cmd_editor_wait() { # the detached waiter: <editor> <worktree> <give-up log> <lock> <bound in seconds, checked by the launcher>
  local editor="$1" wt="$2" log="$3" lock="$4" secs="$5" t=0
  until [ -d "$wt" ]; do
    if [ "$t" -ge "$secs" ]; then
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) the worktree $wt never appeared within ${secs}s; no editor opened" >> "$log"
      rm -rf "$lock"; return 1
    fi
    sleep 1; t=$((t+1))
  done
  "$editor" -n "$wt" >/dev/null 2>&1 < /dev/null || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $editor -n $wt failed" >> "$log"
  rm -rf "$lock"
}
cmd_build() {
  local t seen=" " rc=0 wt
  [ $# -gt 0 ] || usage "build needs at least one ticket"
  repo_context
  for t in "$@"; do valid_ticket "$t" || usage "'$t' is not a $TRACKER ticket"; done
  # a launch from inside a herdr pane carries that pane's ids; nothing here may fall back to them
  unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
  for t in "$@"; do
    case "$seen" in *" $t "*) continue ;; esac   # D-25: herdr does not keep labels unique, so a ticket opens once
    seen="$seen$t "
    wt="${RUN_WORKTREE_ROOT:-$(dirname "$MAIN")/$SLUG-worktrees}/$t"
    local envs=(--env "SS_WT=$wt" --env "SS_ISSUE=$t" --env "SS_ADAPTER=$SELF")
    [ -z "${RUN_WORKTREE_ROOT:-}" ] || envs+=(--env "RUN_WORKTREE_ROOT=$RUN_WORKTREE_ROOT")
    # shellcheck disable=SC2016  # fixed text: the pane's own shell expands $SS_ISSUE and $SS_WT from its --env
    if open_tab "$t" build 'env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:build $SS_ISSUE" --add-dir "$SS_WT"' "${envs[@]}"
    then start_editor_waiter "$t" "$wt"; else rc=1; fi
  done
  return "$rc"
}
cmd_review() {
  local pr="${1:-}" out tickets n
  [ $# -eq 1 ] && [[ "$pr" =~ ^[1-9][0-9]*$ ]] || usage "review takes one PR number"
  repo_context
  if [ "$TRACKER" = github ]; then
    out="$(gh pr view "$pr" --json closingIssuesReferences 2>&1)" || die "gh pr view $pr failed: ${out//$'\n'/ }"
    tickets="$(jq -r '[.closingIssuesReferences[]?.number | tostring] | unique | .[]' <<<"$out" 2>/dev/null)" \
      || die "gh pr view $pr did not answer JSON: $out"
  else # the review skill's rule: `Closes [<KEY>]` under the `### Jira Items` heading, any depth, until the next heading
    out="$(gh pr view "$pr" --json body 2>&1)" || die "gh pr view $pr failed: ${out//$'\n'/ }"
    tickets="$(jq -r '.body // ""' <<<"$out" 2>/dev/null | awk '
        { l = tolower($0) }
        l ~ /^#+[[:space:]]+jira items[[:space:]]*$/ { on = 1; next }
        on && l ~ /^#+[[:space:]]/ { on = 0 }
        on { s = $0; while (match(s, /[Cc][Ll][Oo][Ss][Ee][Ss][[:space:]]+\[[A-Za-z][A-Za-z0-9_]*-[0-9]+\]/)) {
               k = substr(s, RSTART, RLENGTH); sub(/^[^[]*\[/, "", k); sub(/\]$/, "", k); print k; s = substr(s, RSTART + RLENGTH) } }' | sort -u)"
  fi
  n="$(grep -c . <<<"$tickets")"
  [ "$n" -gt 0 ] || die "PR #$pr closes no ticket ($([ "$TRACKER" = github ] && echo 'closingIssuesReferences is empty' || echo 'no Closes [<KEY>] under ### Jira Items')); nothing opened"
  [ "$n" -eq 1 ] || die "PR #$pr closes $n tickets ($(tr '\n' ' ' <<<"$tickets" | sed 's/ $//')); nothing opened"
  valid_ticket "$tickets" || die "PR #$pr closes '$tickets', which is not a $TRACKER ticket; nothing opened"
  unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
  # shellcheck disable=SC2016  # fixed text: the pane's own shell expands $SS_PR from its --env
  open_tab "$tickets" review 'env -u CLAUDE_CONFIG_DIR claude "/dev-pipeline:review $SS_PR"' --env "SS_PR=$pr"
}

case "${1:-}" in
  build) shift; cmd_build "$@"; exit $? ;;
  review) shift; cmd_review "$@"; exit $? ;;
  editor-wait) shift; cmd_editor_wait "$@"; exit $? ;;
  watch) cmd_watch ;;
  transcript) cmd_transcript ;;
  -h|--help) awk 'NR>1 && /^set -uo pipefail/{exit} NR>1' "$0" ;;
  *) [ $# -eq 4 ] || { echo "usage: herdr-adapter.sh <issue> <repo> <detach-log> <worktree> | watch | transcript" >&2; exit 2; }
     cmd_open "$@" ;;
esac
