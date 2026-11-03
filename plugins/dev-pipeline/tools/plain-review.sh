#!/usr/bin/env bash
# plain-review.sh — the record-blind plain review: one headless session that reviews the diff and the ticket and cannot
# reach the decision record or the plan. Its parts are the only copy: run.sh's plain_* functions call them, and `run`
# composes them for the review skills (/dev-pipeline:review, /review-toolkit:review-lead).
#
# Usage:
#   plain-review.sh enabled [<config>]   true|false: run.joinedReview, default true; exit 2 on any other value
#   plain-review.sh tree <worktree> <head> <plans-dir> <dir>     the head as files, with no .git and no plans dir
#   plain-review.sh strip <plans-dir> <record-name> < <ticket>   drops every line naming the plans dir or the record
#   plain-review.sh ticket-text jira <KEY> | none                 the ticket block when the session fetches it, or has none
#   plain-review.sh prompt <draft> <ticket-file> <diff-file> <true|false: a ticket is given> [<prompt-file>]
#   plain-review.sh args <tree> <scratch> <disallowed> <bash-ms> <tracker>   the session's flags, one per line
#   plain-review.sh draft <result-json> <out>   the verdict the final message carries, fences dropped; 1 when none
#   plain-review.sh run --worktree <dir> --base <ref> --head <sha> --out <dir> [--plans-dir <dir>]
#                       [--ticket <file> | --jira-key <KEY>] [--record <name>] [--model <m>] [--timeout <s>]
#                       [--deny-read <path>]...
#     Writes <out>/verdict.md, <out>/ticket (true|false), <out>/result.json, <out>/start and <out>/end (epoch
#     seconds), and <out>/why on a failure. Exit 0 a draft · 1 no draft (<out>/why says why) · 2 usage.
# Env: PLAIN_CLAUDE (default claude) is the session binary for `run`.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE_DEFAULT="$HERE/../skills/run/plain-review.md"
JIRA_READ="mcp__atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__claude_ai_Atlassian_Rovo__getJiraIssue"
usage() { sed -n '6,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

enabled() {
  local cfg="${1:-${SECOND_SHIFT_CONFIG:-.claude/second-shift.config.json}}" v=""
  [ -f "$cfg" ] && v="$(jq -r 'if .run.joinedReview == null then "" else (.run.joinedReview | tostring) end' "$cfg" 2>/dev/null)"
  case "$v" in
    ''|true) echo true ;;
    false) echo false ;;
    *) echo "plain-review: run.joinedReview must be true or false, got '$v'" >&2; return 2 ;;
  esac
}

tree() {
  mkdir -p "$4" || return 1
  git -C "$1" archive --format=tar "$2" -- . ":(exclude)$3" | tar -x -C "$4"
}

strip() { awk -v a="$1/" -v b="$2" 'index($0, a) == 0 && (b == "" || index($0, b) == 0)'; }

# A session that cannot fetch its Jira ticket says so with a ticket-unavailable note, which verdict-join.sh reads
ticket_text() {
  case "$1" in
    jira) printf '%s\n' "Fetch ticket $2 with the getJiraIssue tool and read its summary and description. Ignore any link to a decision record or plan." \
      "If the tool cannot fetch it, review the diff alone and add the finding \`- [note] N0 ticket-unavailable — getJiraIssue could not fetch $2\`." ;;
    none) echo "No ticket is available for this change." ;;
    *) usage ;;
  esac
}

# With no ticket, each body line a header `ticket-only: <prefix>` names is dropped, with the blank line after it.
# index(), never a regex, so no text in a value is read as a pattern
prompt() {
  awk -v out="$1" -v tf="$2" -v df="$3" -v ticket="$4" '
    function fill(s, k, v,   i, o) { o = ""; while ((i = index(s, k)) > 0) { o = o substr(s, 1, i - 1) v; s = substr(s, i + length(k)) } return o s }
    !body { if ($0 == "---") body = 1; else if (index($0, "ticket-only: ") == 1) only[++no] = substr($0, 14); next }
    skip && $0 == "" { skip = 0; next }
    { skip = 0 }
    ticket != "true" { for (k = 1; k <= no; k++) if (index($0, only[k]) == 1) { skip = 1; next } }
    $0 == "{ticket}" { while ((getline l < tf) > 0) print l; next }
    $0 == "{diff}" { while ((getline l < df) > 0) print l; next }
    { print fill($0, "{out}", out) }' "${5:-$PROMPT_FILE_DEFAULT}"
}

# Only its own tree and scratch are added. Under github no MCP server loads, so no tracker or code-host tool can fetch the
# record. Under jira the servers load as they do for the lane sessions, and the allowlist grants getJiraIssue alone: every
# other MCP tool needs a grant this session never gets, and --permission-prompts none denies it
args() {
  local sets mcp=--strict-mcp-config allow="Read,Grep,Glob"
  [ "$5" = jira ] && { mcp=""; allow="$allow,$JIRA_READ"; }
  sets="$(jq -cn --arg ms "$4" '{env:{CLAUDE_CODE_DISABLE_BACKGROUND_TASKS:"1",BASH_DEFAULT_TIMEOUT_MS:$ms,BASH_MAX_TIMEOUT_MS:$ms}}')" || return 1
  printf '%s\n' --permission-mode acceptEdits --permission-prompts none --disallowedTools "$3" \
    --setting-sources "user,project,local" ${mcp:+"$mcp"} --add-dir "$1" --add-dir "$2" --output-format json \
    --settings "$sets" --allowedTools "$allow" --max-turns 150
}

draft() {
  jq -r 'select(.subtype == "success") | .result // empty' "$1" 2>/dev/null \
    | awk '/^```/ { next } !on && /^verdict: (approve|needs-work)[ \t]*$/ { on = 1 } on' > "$2"
  [ -s "$2" ]
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
  tree "$wt" "$head" "$plans" "$out/tree" || { why "the plain review's tree could not be written"; return; }
  local has=true tracker=github
  if [ -n "$ticket" ]; then strip "$plans" "$record" < "$ticket" > "$out/ticket.md" || { why "the ticket could not be read for the plain review"; return; }
  elif [ -n "$jira" ]; then tracker=jira; ticket_text jira "$jira" > "$out/ticket.md"
  else has=false; ticket_text none > "$out/ticket.md"; fi
  echo "$has" > "$out/ticket"
  git -C "$wt" diff "$base...$head" -- . ":(exclude)$plans" > "$out/diff.diff" 2>/dev/null || { why "the diff could not be read for the plain review"; return; }
  prompt "$out/scratch/verdict.md" "$out/ticket.md" "$out/diff.diff" "$has" > "$out/prompt.md" || { why "the plain review's prompt could not be written"; return; }
  local dis ms a flags=()
  dis="AskUserQuestion,EnterWorktree,ExitWorktree,Agent,Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Read(/$(physical "$wt")/**)"
  for d in ${deny[@]+"${deny[@]}"}; do dis="$dis,Read(/$(physical "$d")/**)"; done
  ms=$((secs - 300)); [ "$ms" -ge 120 ] || ms=120; ms=$((ms * 1000)); [ "$ms" -le 2147483647 ] || ms=2147483647
  while IFS= read -r a; do flags+=("$a"); done < <(args "$out/tree" "$out/scratch" "$dis" "$ms" "$tracker")
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
  draft "$out/result.json" "$out/verdict.md" || { why "the plain review returned no verdict"; return; }
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  enabled) enabled "$@" ;;
  tree) [ $# -eq 4 ] || usage; tree "$@" ;;
  strip) [ $# -eq 2 ] || usage; strip "$@" ;;
  ticket-text) [ $# -ge 1 ] || usage; ticket_text "$@" ;;
  prompt) [ $# -ge 4 ] && [ $# -le 5 ] || usage; prompt "$@" ;;
  args) [ $# -eq 5 ] || usage; args "$@" ;;
  draft) [ $# -eq 2 ] || usage; draft "$@" ;;
  run) run "$@" ;;
  *) usage ;;
esac
