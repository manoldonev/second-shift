#!/usr/bin/env bash
# plain-review.sh — the record-blind plain review for the review skills (/dev-pipeline:review,
# /review-toolkit:review-lead): one headless session that reviews the diff and the ticket and cannot reach the
# decision record or the plan. It is run.sh's plain session: the same prompt file, tree, permissions and draft rule.
#
# Usage:
#   plain-review.sh enabled [<config>]   true|false: run.joinedReview, default true; exit 2 on any other value
#   plain-review.sh run --worktree <dir> --base <ref> --head <sha> --out <dir> [--plans-dir <dir>]
#                       [--ticket <file> | --jira-key <KEY>] [--record <name>] [--model <m>] [--timeout <s>]
#                       [--deny-read <path>]...
#     --ticket: the ticket's text, every line naming the plans dir or --record dropped. --jira-key: the session may
#     call getJiraIssue (read only) for that key and no other tracker tool. With neither, it reviews the diff alone.
#     Writes <out>/verdict.md, <out>/ticket (true|false), <out>/result.json, <out>/start and <out>/end (epoch
#     seconds), and <out>/why on a failure. Exit 0 a draft · 1 no draft (<out>/why says why) · 2 usage.
# Env: PLAIN_CLAUDE (default claude) is the session binary.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$HERE/../skills/run/plain-review.md"
JIRA_TOOLS="mcp__atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__claude_ai_Atlassian_Rovo__getJiraIssue"
usage() { sed -n '5,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

enabled() {
  local cfg="${1:-${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}}" v=""
  [ -f "$cfg" ] && v="$(jq -r 'if .run.joinedReview == null then "" else (.run.joinedReview | tostring) end' "$cfg" 2>/dev/null)"
  case "$v" in
    ''|true) echo true ;;
    false) echo false ;;
    *) echo "plain-review: run.joinedReview must be true or false, got '$v'" >&2; return 2 ;;
  esac
}

# With no ticket, each body line a header `ticket-only: <prefix>` names is dropped, with the blank line after it.
# index(), never a regex, so no text in a value is read as a pattern
prompt() { # prompt <draft-path> <ticket-file> <diff-file> <true|false: a ticket is given>
  awk -v out="$1" -v tf="$2" -v df="$3" -v ticket="$4" '
    function fill(s, k, v,   i, o) { o = ""; while ((i = index(s, k)) > 0) { o = o substr(s, 1, i - 1) v; s = substr(s, i + length(k)) } return o s }
    !body { if ($0 == "---") body = 1; else if (index($0, "ticket-only: ") == 1) only[++no] = substr($0, 14); next }
    skip && $0 == "" { skip = 0; next }
    { skip = 0 }
    ticket != "true" { for (k = 1; k <= no; k++) if (index($0, only[k]) == 1) { skip = 1; next } }
    $0 == "{ticket}" { while ((getline l < tf) > 0) print l; next }
    $0 == "{diff}" { while ((getline l < df) > 0) print l; next }
    { print fill($0, "{out}", out) }' "$PROMPT_FILE"
}

physical() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

run() {
  local wt="" base="" head="" out="" plans="" ticket="" jira="" record="" model="" secs=3600 deny=() d
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree) wt="${2-}" ;; --base) base="${2-}" ;; --head) head="${2-}" ;; --out) out="${2-}" ;;
      --plans-dir) plans="${2-}" ;; --ticket) ticket="${2-}" ;; --jira-key) jira="${2-}" ;; --record) record="${2-}" ;;
      --model) model="${2-}" ;; --timeout) secs="${2-}" ;; --deny-read) deny+=("${2-}") ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$wt" ] && [ -n "$base" ] && [ -n "$head" ] && [ -n "$out" ] || usage
  [ -z "$ticket" ] || [ -z "$jira" ] || usage
  case "$secs" in ''|*[!0-9]*) usage ;; esac
  case "$jira" in ''|[A-Za-z]*-[0-9]*) : ;; *) usage ;; esac
  [ -n "$plans" ] || plans="$(jq -r '.paths.plansDir // empty' "${SECOND_SHIFT_CONFIG:-$wt/.claude/second-shift.config.json}" 2>/dev/null)"
  plans="${plans:-docs/plans}"
  why() { printf '%s\n' "$1" > "$out/why"; return 1; }
  mkdir -p "$out/scratch" || { echo "plain-review: cannot create $out" >&2; return 2; }
  out="$(physical "$out")"; rm -f "$out/why" "$out/verdict.md"
  mkdir -p "$out/tree" && git -C "$wt" archive --format=tar "$head" -- . ":(exclude)$plans" | tar -x -C "$out/tree" \
    || { why "the plain review's tree could not be written"; return; }
  local has=true
  if [ -n "$ticket" ]; then
    awk -v a="$plans/" -v b="$record" 'index($0, a) == 0 && (b == "" || index($0, b) == 0)' "$ticket" > "$out/ticket.md" \
      || { why "the ticket could not be read for the plain review"; return; }
  elif [ -n "$jira" ]; then
    printf '%s\n' "Fetch ticket $jira with the getJiraIssue tool and read its summary and description. Ignore any link to a decision record or plan." \
      "If the tool cannot fetch it, review the diff alone and add the finding \`- [note] N0 ticket-unavailable — getJiraIssue could not fetch $jira\`." > "$out/ticket.md"
  else
    has=false; echo "No ticket is available for this change." > "$out/ticket.md"
  fi
  echo "$has" > "$out/ticket"
  git -C "$wt" diff "$base...$head" -- . ":(exclude)$plans" > "$out/diff.diff" 2>/dev/null || { why "the diff could not be read for the plain review"; return; }
  prompt "$out/scratch/verdict.md" "$out/ticket.md" "$out/diff.diff" "$has" > "$out/prompt.md" || { why "the plain review's prompt could not be written"; return; }
  local dis allow="Read,Grep,Glob" mcp=(--strict-mcp-config) ms sets flags=()
  dis="AskUserQuestion,EnterWorktree,ExitWorktree,Agent,Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Read(/$(physical "$wt")/**)"
  for d in ${deny[@]+"${deny[@]}"}; do dis="$dis,Read(/$(physical "$d")/**)"; done
  # Under --permission-prompts none a tool outside the allowlist is refused, so the MCP servers load but only the
  # one read-only Jira call is usable
  [ -z "$jira" ] || { allow="$allow,$JIRA_TOOLS"; mcp=(); }
  ms=$(( (secs > 420 ? secs - 300 : 120) * 1000 ))
  sets="$(jq -cn --arg ms "$ms" '{env:{CLAUDE_CODE_DISABLE_BACKGROUND_TASKS:"1",BASH_DEFAULT_TIMEOUT_MS:$ms,BASH_MAX_TIMEOUT_MS:$ms}}')" \
    || { why "the plain review's settings could not be written"; return; }
  flags=(--permission-mode acceptEdits --permission-prompts none --disallowedTools "$dis" --setting-sources "user,project,local"
    ${mcp[@]+"${mcp[@]}"} --add-dir "$out/tree" --add-dir "$out/scratch" --output-format json --settings "$sets"
    --allowedTools "$allow" --max-turns 150)
  [ -z "$model" ] || flags+=(--model "$model")
  date +%s > "$out/start"
  ( cd "$out/tree" && exec env -u SECOND_SHIFT_CONFIG "${PLAIN_CLAUDE:-claude}" -p "${flags[@]}" ) < "$out/prompt.md" > "$out/result.json" 2> "$out/session.err" &
  local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$t" -ge "$secs" ]; then kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      date +%s > "$out/end"; why "the plain review ran past ${secs}s"; return; fi
    sleep 1; t=$((t + 1))
  done
  wait "$pid"; date +%s > "$out/end"
  jq -r 'select(.subtype == "success") | .result // empty' "$out/result.json" 2>/dev/null \
    | awk '/^```/ { next } !on && /^verdict: (approve|needs-work)[ \t]*$/ { on = 1 } on' > "$out/verdict.md"
  [ -s "$out/verdict.md" ] || { why "the plain review returned no verdict"; return; }
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  enabled) enabled "$@" ;;
  run) run "$@" ;;
  *) usage ;;
esac
