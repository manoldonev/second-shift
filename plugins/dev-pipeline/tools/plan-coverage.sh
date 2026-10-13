#!/usr/bin/env bash
# plan-coverage.sh — the test-first plan's coverage check (#1039): every acceptance criterion the
# decision record's `## Test intent` names is tagged on at least one task of the build's plan, and the
# plan tags no id the record does not define.
#
# Usage: plan-coverage.sh <record-at-first> <plan-file>
#
# File-in and pure: it reads the two files it is handed and nothing else — no tracker, no config, no
# git. The caller hands it the record as committed at its first commit and the plan as it stands at
# the head: run.sh from git objects, the review session from `git show $FIRST:<record>` and the
# checked-out head.
#
# The AC set and the exemptions come from the record's `## Test intent` section (intake writes it;
# ledger-lint.sh --receipt checks its shape): one `ACs: AC-1 AC-2 …` line, or `ACs: none — <reason>`,
# then `AC-n: <behavior>` or `AC-n: exempt — <reason>` per id. Ids compare as exact strings; a PM-n
# item is never in the set. The ticket body is never read.
#
# The plan grammar: `## N. Group` headings, and tasks
#   - [ ] N.M Description (files) [AC-1] [AC-3]
# `[x]` is allowed and means nothing. A task's ids end its line, one bracket per id, no comma list; a
# task carrying an id is a test task. Every line whose first non-blank characters are `- [` must be a
# task in that form, or it is reported unparseable by its line number, never skipped. Line order is
# not checked: the plan is a coverage map.
#
# Report, one line per AC: `covered (task N.M, …)`, `exempt`, or `exempt (tagged)` — an exempt AC
# needs no task, and one the plan tags anyway is allowed; neither counts as covered, neither is red.
#
# Exit: 0 pass · 1 red (stdout names every uncovered id, undefined tag and unparseable line, or the
# missing plan) · 2 an input that cannot be read, or a record whose Test intent has no readable
# `ACs:` line · 3 not-applicable (stdout says why: the record carries no Test intent, or the ticket
# has no AC block) — distinct from a pass.
set -uo pipefail

usage() { echo "usage: plan-coverage.sh <record-at-first> <plan-file>" >&2; exit 2; }
[ $# -eq 2 ] || usage
RECORD="$1"; PLAN="$2"
# -r, never -f: a caller may hand a process substitution, which is readable but not a regular file
[ -r "$RECORD" ] && [ ! -d "$RECORD" ] || { echo "plan-coverage: cannot read the record: $RECORD" >&2; exit 2; }
rec="$(cat "$RECORD")" || { echo "plan-coverage: cannot read the record: $RECORD" >&2; exit 2; }

# the scheduler's section reader (run.sh `section_of`): exact title at any depth, case-folded, ANY heading
# closes it, the FIRST such section decides
section_of() { awk -v h="$1" 'on && /^#+[[:space:]]/ {on=0; done=1} !done && tolower($0) ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {on=1; next} on'; }

if ! grep -qiE '^#+[[:space:]]+test intent[[:space:]]*$' <<< "$rec"; then
  v="$(sed -n 's/^Receipt:[[:space:]]*v\([0-9][0-9]*\)[[:space:]]*$/\1/p' <<< "$rec" | head -n 1)"
  echo "plan-coverage: not-applicable — record v${v:-1} carries no Test intent"; exit 3
fi

ACS=" "; EXEMPT=" "; n_acs=0; none=0
while IFS= read -r line; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^ACs:(.*)$ ]]; then
    n_acs=$((n_acs + 1)); body="${BASH_REMATCH[1]}"
    if [[ "$body" =~ ^[[:space:]]*none([^[:alnum:]_]|$) ]]; then none=1; continue; fi
    read -r -a toks <<< "$body"
    for t in "${toks[@]}"; do
      [[ "$t" =~ ^AC-[0-9]+$ ]] || { echo "plan-coverage: the record's Test intent 'ACs:' line carries '$t', which is not an AC id: $line" >&2; exit 2; }
      [[ "$ACS" == *" $t "* ]] || ACS="$ACS$t "
    done
  elif [[ "$line" =~ ^(AC-[0-9]+):[[:space:]]*[Ee]xempt([^[:alnum:]_]|$) ]]; then
    EXEMPT="$EXEMPT${BASH_REMATCH[1]} "
  fi
done <<< "$(section_of 'test intent' <<< "$rec")"
[ "$n_acs" -eq 1 ] || { echo "plan-coverage: the record's Test intent carries $n_acs 'ACs:' lines — one names the AC set" >&2; exit 2; }
if [ "$none" -eq 1 ]; then echo "plan-coverage: not-applicable — the ticket has no AC block"; exit 3; fi
[ "$ACS" != " " ] || { echo "plan-coverage: the record's Test intent 'ACs:' line lists no id" >&2; exit 2; }

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
# TAGS: one "<id> <task>" line per tag, in plan order
TAGS=""; RED=0; n=0
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
  if [[ "$rest" =~ $STRAY_ID_RE ]]; then
    echo "plan-coverage: RED: line $n is unparseable — its AC ids do not end the line one bracket each ('[AC-1] [AC-3]', after a description): $line"
    RED=$((RED + 1)); continue
  fi
  for id in $ids; do TAGS="$TAGS$id $task"$'\n'; done
done <<< "$plan"

tasks_of() { awk -v id="$1" '$1 == id { printf "%s%s", (n++ ? ", " : ""), $2 }' <<< "$TAGS"; }
covered=0; exempt=0
for id in $ACS; do
  t="$(tasks_of "$id")"
  if [[ "$EXEMPT" == *" $id "* ]]; then
    exempt=$((exempt + 1))
    if [ -n "$t" ]; then echo "plan-coverage: $id exempt (tagged: task $t)"; else echo "plan-coverage: $id exempt"; fi
  elif [ -n "$t" ]; then
    covered=$((covered + 1)); echo "plan-coverage: $id covered (task $t)"
  else
    echo "plan-coverage: RED: $id has no test task — tag it on the task whose test proves its Test intent line"; RED=$((RED + 1))
  fi
done
while read -r id task; do
  [ -n "$id" ] || continue
  [[ "$ACS" == *" $id "* ]] && continue
  echo "plan-coverage: RED: task $task tags $id, which the record's Test intent does not define (ACs:$ACS)"; RED=$((RED + 1))
done <<< "$TAGS"

if [ "$RED" -gt 0 ]; then echo "plan-coverage: RED — $RED problem(s)"; exit 1; fi
echo "plan-coverage: pass — $covered covered, $exempt exempt"
exit 0
