#!/usr/bin/env bash
# plan-coverage.sh — the test-first plan's coverage check (#1039): every acceptance criterion the
# decision record's `## Test intent` names is tagged on at least one task of the build's plan, and the
# plan tags no id the record does not define.
#
# Usage: plan-coverage.sh [--files] <record-at-first> <plan-file>
#
# File-in and pure: it reads the two files it is handed and nothing else — no tracker, no config, no
# git. The caller hands it the record as committed at its first commit and the plan as it stands at
# the head: run.sh from git objects, the review session from `git show $FIRST:<record>` and the
# checked-out head.
#
# The AC set and the exemptions come from the record's `## Test intent` section (intake writes it;
# ledger-lint.sh --receipt checks its shape): one `ACs: AC-1 AC-2 …` line, or `ACs: none — <reason>`,
# then per id `AC-n: <behavior>`, `AC-n: exempt — <reason>`, `AC-n: holds — <existing behavior>` or
# `AC-n: unchecked — <tier and reason>` (#1040 D-4 D-11). Ids compare as exact strings; a PM-n item is
# never in the set. The ticket body is never read.
#
# The plan grammar: `## N. Group` headings, and tasks
#   - [ ] N.M Description (files) [AC-1] [AC-3]
# `[x]` is allowed and means nothing. A task's ids end its line, one bracket per id, no comma list; a
# task carrying an id is a test task, and it names its test files in the parenthetical that ends its
# description, separated by commas or spaces (#1040 D-3); a tagged task with none is red. Every line
# whose first non-blank characters are `- [` must be a task in that form, or it is reported
# unparseable by its line number, never skipped. Line order is not checked: the plan is a coverage map.
#
# A file may name one test as `file::case` (#1053 D-6, superseding #1040 D-21). The case is
# backtick-quoted whenever it holds a space, `>`, `(`, `)`, `,` or `[`:
#   (src/a.test.ts::`Importer > dup > rejects (409)`, src/b.test.ts::adds)
# Backtick spans are lexed across the whole task line before anything else reads it, so a
# description's `foo(x)` cannot hide the closing parenthetical, and a span's spaces and commas never
# split it. A case holding a backtick is unsupported. A bare case runs to the next comma (D-30), so a
# space-separated name cannot follow it. An unterminated backtick, an empty case, or a case that needs
# quoting written bare is red, unparseable, naming the task.
#
# Report, one line per AC: `covered (task N.M, …)`, `exempt`, or `exempt (tagged)` — an exempt AC
# needs no task, and one the plan tags anyway is allowed; neither counts as covered, neither is red.
# A holds or unchecked AC must be tagged like a behavior; its covered line ends `— holds` or
# `— unchecked`.
#
# --files (#1040 D-7): the same check, and on a pass stdout carries the map run.sh's
# fails-without-the-change leg reads instead of the report, one `<kind>\t<AC-n>\t<file>\t<case>` line
# (tab-separated, the case empty for a bare file; #1053 D-6) per tagged AC and named test, in plan
# order: `run` (a behavior AC: the test must fail without the change), `holds` (kept off that leg) or
# `unchecked` (noted, not run); an exempt AC's files are not listed. A red prints its RED lines as the
# report mode does; exits 2 and 3 are the report mode's.
#
# --head <record-at-head> (#1085): the record as it stands at the head, read for ONE thing — an AC
# added after the baseline. An id the plan tags that the baseline does not define but the
# head's Test intent lists is accepted, in the head's form, when the head's Decision Ledger carries at
# least one `| D-n |` row that is new or changed since the baseline with `user-answered` or
# `user-delegated` provenance: a recorded departure, which the review scores row by row. The script
# cannot tell who wrote a row — the lane's build records its own changes as `user-delegated` — so the
# covered line names each admitting row with its provenance, never a decider:
# `— added at the head under a recorded departure (D-n <provenance>, …)`. Rows are compared cell by
# cell with each cell trimmed, so a re-padded table is not a departure. With no such row the tag stays
# red, saying so. Everything else stays the baseline's: an AC the head
# drops, exempts or re-forms is still read from the baseline (#1039 D-10 — a build cannot mark the
# check passed at the head), and a head with no Test intent adds nothing. Without --head the check
# reads the baseline alone, as before.
#
# Exit: 0 pass · 1 red (stdout names every uncovered id, undefined tag and unparseable line, or the
# missing plan) · 2 an input that cannot be read, or a record whose Test intent has no readable
# `ACs:` line · 3 not-applicable (stdout says why: the record carries no Test intent, or the ticket
# has no AC block) — distinct from a pass.
set -uo pipefail

usage() { echo "usage: plan-coverage.sh [--files] [--head <record-at-head>] <record-at-first> <plan-file>" >&2; exit 2; }
FILES_MODE=0; HEAD_RECORD=""
while [ $# -gt 2 ]; do
  case "$1" in
    --files) FILES_MODE=1; shift ;;
    --head) [ $# -gt 3 ] || usage; HEAD_RECORD="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ $# -eq 2 ] || usage
RECORD="$1"; PLAN="$2"
# -r, never -f: a caller may hand a process substitution, which is readable but not a regular file
[ -r "$RECORD" ] && [ ! -d "$RECORD" ] || { echo "plan-coverage: cannot read the record: $RECORD" >&2; exit 2; }
rec="$(cat "$RECORD")" || { echo "plan-coverage: cannot read the record: $RECORD" >&2; exit 2; }
head_rec=""
if [ -n "$HEAD_RECORD" ]; then
  [ -r "$HEAD_RECORD" ] && [ ! -d "$HEAD_RECORD" ] || { echo "plan-coverage: cannot read the record at the head: $HEAD_RECORD" >&2; exit 2; }
  head_rec="$(cat "$HEAD_RECORD")" || { echo "plan-coverage: cannot read the record at the head: $HEAD_RECORD" >&2; exit 2; }
fi

# the scheduler's section reader (run.sh `section_of`): exact title at any depth, case-folded, ANY heading
# closes it, the FIRST such section decides
section_of() { awk -v h="$1" 'on && /^#+[[:space:]]/ {on=0; done=1} !done && tolower($0) ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {on=1; next} on'; }
has_test_intent() { grep -qiE '^#+[[:space:]]+test intent[[:space:]]*$' <<< "$1"; }

if ! has_test_intent "$rec"; then
  v="$(sed -n 's/^Receipt:[[:space:]]*v\([0-9][0-9]*\)[[:space:]]*$/\1/p' <<< "$rec" | head -n 1)"
  echo "plan-coverage: not-applicable — record v${v:-1} carries no Test intent"; exit 3
fi

# read_intent <record text> <which> -> P_ACS P_EXEMPT P_HOLDS P_UNCHECKED (space-delimited, space-padded), P_NONE; exit 2 on
# an 'ACs:' line that is not an AC set, naming <which> record
read_intent() {
  local text="$1" which="$2" line body t toks n_acs=0
  P_ACS=" "; P_EXEMPT=" "; P_HOLDS=" "; P_UNCHECKED=" "; P_NONE=0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^ACs:(.*)$ ]]; then
      n_acs=$((n_acs + 1)); body="${BASH_REMATCH[1]}"
      if [[ "$body" =~ ^[[:space:]]*none([^[:alnum:]_]|$) ]]; then P_NONE=1; continue; fi
      read -r -a toks <<< "$body"
      for t in "${toks[@]}"; do
        [[ "$t" =~ ^AC-[0-9]+$ ]] || { echo "plan-coverage: the $which Test intent 'ACs:' line carries '$t', which is not an AC id: $line" >&2; exit 2; }
        [[ "$P_ACS" == *" $t "* ]] || P_ACS="$P_ACS$t "
      done
    elif [[ "$line" =~ ^(AC-[0-9]+):[[:space:]]*[Ee]xempt([^[:alnum:]_]|$) ]]; then
      P_EXEMPT="$P_EXEMPT${BASH_REMATCH[1]} "
    elif [[ "$line" =~ ^(AC-[0-9]+):[[:space:]]*[Hh]olds([^[:alnum:]_]|$) ]]; then
      P_HOLDS="$P_HOLDS${BASH_REMATCH[1]} "
    elif [[ "$line" =~ ^(AC-[0-9]+):[[:space:]]*[Uu]nchecked([^[:alnum:]_]|$) ]]; then
      P_UNCHECKED="$P_UNCHECKED${BASH_REMATCH[1]} "
    fi
  done <<< "$(section_of 'test intent' <<< "$text")"
  [ "$n_acs" -eq 1 ] || { echo "plan-coverage: the $which Test intent carries $n_acs 'ACs:' lines — one names the AC set" >&2; exit 2; }
}
read_intent "$rec" "record's"
ACS="$P_ACS"; EXEMPT="$P_EXEMPT"; HOLDS="$P_HOLDS"; UNCHECKED="$P_UNCHECKED"
if [ "$P_NONE" -eq 1 ]; then echo "plan-coverage: not-applicable — the ticket has no AC block"; exit 3; fi
[ "$ACS" != " " ] || { echo "plan-coverage: the record's Test intent 'ACs:' line lists no id" >&2; exit 2; }

# #1085: the ids only the head defines, and the user-answered / user-delegated ledger rows new or changed since the baseline that admit them
HEAD_ACS=" "; HEAD_EXEMPT=" "; HEAD_HOLDS=" "; HEAD_UNCHECKED=" "; ADDED=" "; DEPARTURE=""
ledger_rows() { # each `| D-n |` row with every cell trimmed: a re-padded row is the same row
  grep -E '^\|[[:space:]]*D-[0-9]+[[:space:]]*\|' <<< "$1" | awk -F'|' -v OFS='|' '{ for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); print }'
}
if [ -n "$HEAD_RECORD" ] && has_test_intent "$head_rec"; then
  read_intent "$head_rec" "head record's"
  HEAD_ACS="$P_ACS"; HEAD_EXEMPT="$P_EXEMPT"; HEAD_HOLDS="$P_HOLDS"; HEAD_UNCHECKED="$P_UNCHECKED"
  for id in $HEAD_ACS; do [[ "$ACS" == *" $id "* ]] || ADDED="$ADDED$id "; done
  if [ "$ADDED" != " " ]; then
    base_rows="$(ledger_rows "$rec")"
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      grep -qxF -- "$row" <<< "$base_rows" && continue   # the same cells as a baseline row: not a departure
      prov="$(cut -d'|' -f5 <<< "$row")"
      case "$prov" in
        user-answered|user-delegated) DEPARTURE="$DEPARTURE${DEPARTURE:+, }$(cut -d'|' -f2 <<< "$row") $prov" ;;
      esac
    done <<< "$(ledger_rows "$head_rec")"
  fi
fi

if [ ! -e "$PLAN" ]; then
  echo "plan-coverage: RED: no plan — $PLAN does not exist; commit the task plan, every AC the record does not exempt tagged on a test task"
  exit 1
fi
[ -r "$PLAN" ] && [ ! -d "$PLAN" ] || { echo "plan-coverage: cannot read the plan: $PLAN" >&2; exit 2; }
plan="$(cat "$PLAN")" || { echo "plan-coverage: cannot read the plan: $PLAN" >&2; exit 2; }

# The grammar, as regexes held in variables so bash reads their spaces and brackets literally
CANDIDATE_RE='^[[:space:]]*-[[:space:]]+\['                       # a line that claims to be a task
TASK_RE='^- \[[ xX]\] ([0-9]+\.[0-9]+) (.*[^[:space:]])$'         # one that is: its number, then the rest
TRAILING_ID_RE='^(.*[^[:space:]])[[:space:]]+\[(AC-[0-9]+)\]$'     # the rest, with one more id peeled off its end
STRAY_ID_RE='\[[[:space:]]*[Aa][Cc]-[0-9]'                         # an AC id left in the description: not at the end, or a comma list
FILES_RE='^(.*)\(([^()]*)\)$'                                      # the parenthetical that ends the description: the task's files
NEEDS_QUOTE='[][()>]'                                              # a bare case holding one of these must be backtick-quoted
BT='`'
mask_spans() { # mask_spans <text> -> the text with every character inside a backtick span replaced by '_', the same length
  local s="$1" out="" i ch inq=0
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    if [ "$ch" = "$BT" ]; then inq=$((1 - inq)); out="$out$ch"
    elif [ "$inq" -eq 1 ]; then out="${out}_"
    else out="$out$ch"; fi
  done
  printf '%s' "$out"
}
SPLIT_ERR=""; SPLIT_OUT=""
split_files() { # split_files <the parenthetical's text> -> SPLIT_OUT: one "<file>\t<case>" line per name; 1 and SPLIT_ERR when unparseable
  local s="$1" i ch nx inq=0 incase=0 bare=0 lastq=0 f="" c="" any=0 out="" tail
  SPLIT_ERR=""; SPLIT_OUT=""
  for ((i = 0; i <= ${#s}; i++)); do
    ch="${s:i:1}"
    # #1053 D-30: a bare case runs to the next comma or the list's end, so a space inside it is part of it and needs quoting;
    # a space still separates bare files, and a quoted case from the next name
    if [ "$i" -lt "${#s}" ] && [ "$inq" -eq 0 ] && [ "$incase" -eq 1 ] && [ "$lastq" -eq 0 ] && [ -n "$c" ] && [[ "$ch" == [[:space:]] ]]; then
      tail="${s:i}"; tail="${tail#"${tail%%[![:space:]]*}"}"
      if [ -n "$tail" ] && [ "${tail:0:1}" != , ]; then c="$c$ch"; bare=1; continue; fi
    fi
    if [ "$i" -eq "${#s}" ] || { [ "$inq" -eq 0 ] && [[ "$ch" == [,[:space:]] ]]; }; then   # a name ends
      if [ "$any" -eq 1 ]; then
        if [ "$incase" -eq 1 ] && [ -z "$c" ]; then SPLIT_ERR="'$f::' names an empty case"; return 1; fi
        if [ "$bare" -eq 1 ]; then SPLIT_ERR="the case of '$f::$c' holds a space, '>', '(', ')' or '[' and must be backtick-quoted: $f::\`$c\` (a bare case runs to the next comma)"; return 1; fi
        [ -n "$f" ] || { SPLIT_ERR="'::$c' names no file"; return 1; }
        out="$out$f"$'\t'"$c"$'\n'
      fi
      f=""; c=""; incase=0; bare=0; lastq=0; any=0; continue
    fi
    any=1
    if [ "$ch" = "$BT" ]; then inq=$((1 - inq)); lastq=$((1 - inq)); continue; fi
    lastq=0
    nx="${s:i+1:1}"
    if [ "$inq" -eq 0 ] && [ "$incase" -eq 0 ] && [ "$ch" = : ] && [ "$nx" = : ]; then incase=1; i=$((i + 1)); continue; fi
    if [ "$incase" -eq 1 ]; then
      c="$c$ch"
      # shellcheck disable=SC2053  # NEEDS_QUOTE IS a bracket glob
      if [ "$inq" -eq 0 ] && [[ "$ch" == $NEEDS_QUOTE ]]; then bare=1; fi
    else f="$f$ch"; fi
  done
  SPLIT_OUT="$out"
}
# TAGS: one "<id> <task>" line per tag, in plan order; TASK_FILES: one "<task>\t<file>\t<case>" line per name a tagged task names
TAGS=""; TASK_FILES=""; RED=0; n=0
while IFS= read -r line; do
  n=$((n + 1)); line="${line%$'\r'}"
  [[ "$line" =~ $CANDIDATE_RE ]] || continue
  if [[ ! "$line" =~ $TASK_RE ]]; then
    echo "plan-coverage: RED: line $n is unparseable — a task is '- [ ] N.M Description (files) [AC-1] [AC-3]' at the start of the line: $line"
    RED=$((RED + 1)); continue
  fi
  task="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"; ids=""
  while [[ "$rest" =~ $TRAILING_ID_RE ]]; do
    rest="${BASH_REMATCH[1]}"; ids="${BASH_REMATCH[2]} $ids"
  done
  ticks="${rest//[^$BT]/}"
  if [ $(( ${#ticks} % 2 )) -eq 1 ] && [ -n "$ids" ]; then
    echo "plan-coverage: RED: line $n is unparseable — task $task has an unterminated backtick; quote each case as file::\`case\`: $line"
    RED=$((RED + 1)); continue
  fi
  masked="$(mask_spans "$rest")"   # #1053 D-6: what a span holds is never read as a bracket, a parenthesis or a separator
  if [[ "$masked" =~ $STRAY_ID_RE ]]; then
    echo "plan-coverage: RED: line $n is unparseable — its AC ids do not end the line one bracket each ('[AC-1] [AC-3]', after a description): $line"
    RED=$((RED + 1)); continue
  fi
  [ -n "$ids" ] || continue
  files=""
  if [[ "$masked" =~ $FILES_RE ]]; then files="${rest:${#BASH_REMATCH[1]}+1:${#BASH_REMATCH[2]}}"
  elif [[ "$masked" == *::* ]]; then
    echo "plan-coverage: RED: line $n is unparseable — task $task names a case holding a space, '>', '(', ')', ',' or '[' bare; backtick-quote it as file::\`case\`: $line"
    RED=$((RED + 1)); continue
  fi
  if ! split_files "$files"; then
    echo "plan-coverage: RED: line $n is unparseable — task $task: $SPLIT_ERR"
    RED=$((RED + 1)); continue
  fi
  names="$SPLIT_OUT"
  if [ -z "$names" ]; then
    echo "plan-coverage: RED: task $task tags ${ids% } but names no test file — end its description with its test files in parentheses: '- [ ] $task Description (path/to/the.test) [AC-1]'"
    RED=$((RED + 1)); continue
  fi
  for id in $ids; do TAGS="$TAGS$id $task"$'\n'; done
  while IFS= read -r nm; do [ -z "$nm" ] || TASK_FILES="$TASK_FILES$task"$'\t'"$nm"$'\n'; done <<< "$names"
done <<< "$plan"

tasks_of() { awk -v id="$1" '$1 == id { printf "%s%s", (n++ ? ", " : ""), $2 }' <<< "$TAGS"; }
# the AC set the check scores: the baseline's, plus the head-added ids a recorded departure admits (#1085); each id's
# form (exempt, holds, unchecked) is read from the record that defines it, so the baseline still governs its own ids
SCORED="$ACS"; [ -z "$DEPARTURE" ] || SCORED="$SCORED${ADDED# }"
form_of() { # form_of <id> -> exempt | holds | unchecked | '' from the defining record
  local ex="$EXEMPT" ho="$HOLDS" un="$UNCHECKED"
  if [[ "$ACS" != *" $1 "* ]]; then ex="$HEAD_EXEMPT"; ho="$HEAD_HOLDS"; un="$HEAD_UNCHECKED"; fi
  if [[ "$ex" == *" $1 "* ]]; then echo exempt; elif [[ "$ho" == *" $1 "* ]]; then echo holds; elif [[ "$un" == *" $1 "* ]]; then echo unchecked; fi
}
covered=0; exempt=0; holds=0; unchecked=0; added=0
for id in $SCORED; do
  t="$(tasks_of "$id")"; form=""; origin=""
  [[ "$ACS" == *" $id "* ]] || origin=" — added at the head under a recorded departure ($DEPARTURE)"
  case "$(form_of "$id")" in holds) form=" — holds" ;; unchecked) form=" — unchecked" ;; esac
  if [ "$(form_of "$id")" = exempt ]; then
    exempt=$((exempt + 1))
    [ "$FILES_MODE" -eq 1 ] || if [ -n "$t" ]; then echo "plan-coverage: $id exempt (tagged: task $t)$origin"; else echo "plan-coverage: $id exempt$origin"; fi
  elif [ -n "$t" ]; then
    covered=$((covered + 1)); [ "$FILES_MODE" -eq 1 ] || echo "plan-coverage: $id covered (task $t)$form$origin"
    case "$form" in *holds) holds=$((holds + 1)) ;; *unchecked) unchecked=$((unchecked + 1)) ;; esac
    [ -z "$origin" ] || added=$((added + 1))
  else
    echo "plan-coverage: RED: $id has no test task — tag it on the task whose test proves its Test intent line"; RED=$((RED + 1))
  fi
done
while read -r id task; do
  [ -n "$id" ] || continue
  [[ "$SCORED" == *" $id "* ]] && continue
  if [[ "$ADDED" == *" $id "* ]]; then
    echo "plan-coverage: RED: task $task tags $id, which only the record at the head defines — the baseline's Test intent does not (ACs:$ACS), and no Decision Ledger row was added or changed since the baseline with user-answered or user-delegated provenance to admit it"
  else
    echo "plan-coverage: RED: task $task tags $id, which the record's Test intent does not define (ACs:$ACS)"
  fi
  RED=$((RED + 1))
done <<< "$TAGS"

if [ "$RED" -gt 0 ]; then echo "plan-coverage: RED — $RED problem(s)"; exit 1; fi
if [ "$FILES_MODE" -eq 1 ]; then # each tagged AC's files, once per AC and file, in plan order; an exempt AC's are not listed
  while read -r id task; do
    [ -n "$id" ] || continue
    kind="$(form_of "$id")"; [ "$kind" != exempt ] || continue; [ -n "$kind" ] || kind=run
    awk -F'\t' -v t="$task" -v k="$kind" -v id="$id" '$1 == t { print k "\t" id "\t" $2 "\t" $3 }' <<< "$TASK_FILES"
  done <<< "$TAGS" | awk '!seen[$0]++'
  exit 0
fi
forms=""
[ $((holds + unchecked)) -eq 0 ] || forms="$holds holds, $unchecked unchecked"
[ "$added" -eq 0 ] || forms="$forms${forms:+, }$added added at the head"
[ -z "$forms" ] || forms=" (of the covered: $forms)"
echo "plan-coverage: pass — $covered covered, $exempt exempt$forms"
exit 0
