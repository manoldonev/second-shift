#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2016  # sed's '[^']*' has no ${//} form without extglob; '$(' and '`' are literal shapes looked for
# lane-permission-hook.sh — the BUILD session's PermissionRequest hook (#1048 D-6): it turns an opaque "requires
# approval" denial into a reason the session can act on.
#
# Usage (run.sh passes it in the build spawn's --settings, never the review's, never the plugin's hooks.json — D-8 D-18):
#   lane-permission-hook.sh <worktree> [<scratch-dir> [<lane-file>...]]   < PermissionRequest input JSON on stdin
#   (an empty <scratch-dir> means none; each <lane-file> is an absolute path: run.sh names the record and the plan)
#
# A PermissionRequest hook fires only on a call the allowlist would deny, so it can never block a granted command; the
# allowlist stays the only grant. It denies with one reason, the first that applies (D-12):
#   1. withheld   — a file-tool path (file_path, path), or an absolute-path word of a Bash command, that resolves (`..`
#                   and symlinks) outside the worktree and the scratch dir (D-13); /dev/null and /dev/std* are no path
#   2. compound   — a Bash command holding $( ), backticks, |, ;, &&, || or a newline, or led by cd (D-11)
#   3. lookup     — a Bash grep, find, ls, wc, head, cat or tail: the Grep, Glob or Read tool does that (D-1 D-11)
#   4. not granted — anything else: skip it and name it in the PR body
# Its one allow (D-7): Edit or Write to a file directly in <worktree>/.claude/, except settings.json and
# settings.local.json, after the same resolution; those two and any file in a subdirectory of it (agents/, skills/,
# commands/, hooks/, rules/ …), which a session loads, are denied by name. The lane files are the one exception (#1080):
# Edit or Write to exactly a named <lane-file>, after the same resolution, is allowed wherever it sits in the worktree,
# so a plansDir under .claude/ (say .claude/plans) can take the plan the scheduler requires and the record's row edits.
#
# Output: one hookSpecificOutput JSON object on stdout, exit 0. With no worktree argument or unreadable input it prints
# nothing and the permission flow proceeds as it would without the hook (a denial, under --permission-prompts none).
set -uo pipefail

resolve() { # resolve <absolute-path>: the physical path, `..` and symlinks resolved; a part that does not exist yet is kept as written
  local cur="" rest="$1" comp t n=0
  while [ -n "$rest" ]; do
    comp="${rest%%/*}"; if [ "$comp" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    case "$comp" in ''|.) continue ;; ..) cur="${cur%/*}"; continue ;; esac
    if [ -L "$cur/$comp" ]; then # splice the link's target in front of what is left; cur holds no link, so `..` pops lexically
      n=$((n+1)); [ "$n" -le 40 ] || return 1
      t="$(readlink "$cur/$comp")" || return 1
      case "$t" in /*) cur="" ;; esac
      rest="$t${rest:+/$rest}"
    else cur="$cur/$comp"; fi
  done
  printf '%s' "${cur:-/}"
}
decide() { # decide allow | decide deny <message>
  jq -cn --arg b "$1" --arg m "${2:-}" \
    '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:(if $b == "allow" then {behavior:$b} else {behavior:$b,message:$m} end)}}'
  exit 0
}

[ -n "${1:-}" ] || exit 0
IN="$(cat)"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$IN" || exit 0
WT="$(resolve "$1")" || exit 0
SCR=""; [ -n "${2:-}" ] && { SCR="$(resolve "$2")" || exit 0; }
LANE=(); for f in "${@:3}"; do case "$f" in /*) lf="$(resolve "$f")" || exit 0; LANE+=("$lf") ;; esac; done
TOOL="$(jq -r '.tool_name // ""' <<<"$IN")"
CWD="$(jq -r '.cwd // ""' <<<"$IN")"; case "$CWD" in /*) ;; *) CWD="$1" ;; esac

inside() { # inside <resolved-path>: under the worktree or the scratch dir
  case "$1" in "$WT"|"$WT"/*) return 0 ;; esac
  [ -n "$SCR" ] && case "$1" in "$SCR"|"$SCR"/*) return 0 ;; esac
  return 1
}
withheld() { # withheld <path-as-written> <resolved>
  decide deny "$1 resolves to $2, outside this worktree ($WT)${SCR:+ and the scratch dir ($SCR)}: it is withheld from lane sessions, and no rewrite of the call reaches it. Skip what needs it and name it in the PR body as skipped."
}
not_granted() { decide deny "$1 is not on this session's allowlist: skip it and name it in the PR body as skipped."; }

if [ "$TOOL" != Bash ]; then
  p="$(jq -r '.tool_input.file_path // .tool_input.path // ""' <<<"$IN")"
  [ -n "$p" ] || not_granted "$TOOL"
  case "$p" in /*) ;; *) p="$CWD/$p" ;; esac
  r="$(resolve "$p")" || withheld "$p" "an unresolvable path"
  inside "$r" || withheld "$p" "$r"
  case "$TOOL" in Edit|Write) for f in ${LANE[@]+"${LANE[@]}"}; do [ "$r" = "$f" ] && decide allow; done ;; esac
  case "$r" in "$WT"/.claude/*)
    rel="${r#"$WT"/.claude/}"
    case "$rel" in */*) decide deny "$p is in $WT/.claude/${rel%%/*}/, a subdirectory of the worktree's .claude/ (agents/, skills/, commands/, hooks/, rules/ …) that sessions load: lane sessions never edit it. Skip it and name it in the PR body as skipped." ;; esac
    case "$(tr '[:upper:]' '[:lower:]' <<<"$rel")" in settings.json|settings.local.json)
      decide deny "$p is the worktree's .claude/$rel, which sessions load: lane sessions never edit it. Skip it and name it in the PR body as skipped." ;;
    esac
    case "$TOOL" in Edit|Write) decide allow ;; esac ;;
  esac
  not_granted "$TOOL on $p"
fi

CMD="$(jq -r '.tool_input.command // ""' <<<"$IN")"
# 1. every absolute-path word, its quotes dropped and split at the shell's operators, redirects and an option's `=`
read -r -a words <<<"$(tr "'\"\`;|&()<>=\n" '            ' <<<"$CMD")"
for w in ${words[@]+"${words[@]}"}; do
  case "$w" in /dev/null|/dev/stdin|/dev/stdout|/dev/stderr) continue ;; /*) ;; *) continue ;; esac
  r="$(resolve "$w")" || withheld "$w" "an unresolvable path"
  inside "$r" || withheld "$w" "$r"
done
# 2. a quoted string is no operator: substitution is looked for outside single quotes, the rest outside any quotes
unsq="$(sed "s/'[^']*'//g" <<<"$CMD")"; unq="$(sed 's/"[^"]*"//g' <<<"$unsq")"
read -r -a cw <<<"$CMD"; first=""
for w in ${cw[@]+"${cw[@]}"}; do case "$w" in *=*) continue ;; *) first="$w"; break ;; esac; done
if [[ "$unsq" == *'$('* || "$unsq" == *'`'* || "$unq" == *'|'* || "$unq" == *';'* || "$unq" == *'&&'* || "$CMD" == *$'\n'* || "$first" = cd ]]; then
  decide deny "Run each shell command on its own, with absolute paths: no \$( ) or backtick substitution, no | pipe, no ; && or || chain, no cd (use git -C <dir>). Run the commands of this call one at a time, each in its own Bash call; one that is still not granted is skipped and named in the PR body as skipped."
fi
# 3. the read helpers have tools of their own
case "$first" in grep|find|ls|wc|head|cat|tail)
  decide deny "$first is not granted to lane sessions: use the Grep tool to search file contents, the Glob tool to find files by name, and the Read tool to read a file or part of one." ;;
esac
# 4.
not_granted "Bash: $CMD"
