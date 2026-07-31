#!/usr/bin/env bash
# ledger-corroborate.sh — harness-corroboration verdict for one claim class.
#
# Given a claimed evidence set and a ledger excerpt on stdin, decide whether the
# harness actually wrote rows backing the claim. Pure logic behind a stdin/env
# seam: no state file, no git, no network — every arm is fixture-testable.
#
# The point is that `statectl`'s completion preconditions read only fields the
# executing agent itself wrote. This tool supplies the independent half: rows the
# audit hook wrote, which the agent cannot mint.
#
# Usage:
#   ledger-corroborate.sh --class skill|stage-file|workflow|subagent-stop \
#     [--claims '<json string array>'] [--since <ISO-8601 Z>] [--min-count <n>]
#   < ledger-excerpt.jsonl
#
# Emits `<verdict>\t<detail>` on stdout; exit 0 for every verdict (a non-zero exit
# is reserved for usage/parse errors, so callers can distinguish "the tool broke"
# from "the evidence is missing"). Verdicts:
#
#   vacuous       nothing was claimed — the leg does not apply. NEVER a refusal:
#                 most stages record no skill loads at all, and refusing them
#                 would block every ordinary run.
#   corroborated  every claimed item has a matching admissible row.
#   degraded      >=1 admissible row, but all of them carry an empty-or-absent
#                 `target` — the ledger is too old (audit-toolkit <= 2.0.1) to
#                 identify what the call ran on. Not a refusal; not a clean pass.
#   refused       a claim was made and the rows do not back it: zero admissible
#                 rows, or a claim with no match.
#
# ORDER IS LOAD-BEARING: row count is tested BEFORE targets. `[] | all(.target ==
# "")` is `true` in jq, so an all-empty test evaluated first would report
# `degraded` on zero rows — failing open in exactly the fabricated-evidence case
# this tool exists to catch.
#
# Admissibility, per class (see the ticket's D-17/D-18/D-19):
#   skill/stage-file/workflow  main-loop rows only (`subagent == ""`). Subagent
#                              tool calls land in the SAME session-keyed ledger
#                              file as the main loop, so an unfiltered query lets
#                              a subagent's row satisfy a claim the main loop
#                              never made.
#   subagent-stop              filters on the EVENT NAME with no subagent
#                              constraint — the deliberate carve-out. `event`
#                              comes from the hook's `.hook_event_name`, and a
#                              main-loop `Agent` call mints
#                              `event: "PostToolUse"`, never a `SubagentStop`
#                              row, so the carve-out admits nothing a main-loop
#                              call can forge. Do NOT "tighten" it with
#                              `subagent != ""`: that field is harness-owned and
#                              silently-failing, empty on ~18% of corpus rows.
#
# Windowing: `--since` is the lower bound (upper bound is always now — the
# completion preconditions evaluate BEFORE `completedAt` is written). The
# stage-file leg passes NO `--since` and is windowless by design: the executor
# must read `stages/N-*.md` before it can run the mark-started that writes
# `startedAt`, so `readTs < startedAt` by construction, and at Stage 1 the read
# precedes `statectl init` itself. A lower bound at any state anchor would refuse
# a run that genuinely did the work.
#
# `target` normalization is `.target // ""` throughout: absent (pre-2.1.0 rows),
# empty (the current hook's `--arg`, which always emits a string key), and a
# defensive literal `null` are one case.
set -euo pipefail

die() { printf '[ledger-corroborate] %s\n' "$1" >&2; exit "${2:-3}"; }

CLASS=""
CLAIMS="[]"
SINCE=""
MIN_COUNT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --class)     CLASS="${2:-}"; shift 2 ;;
    --claims)    CLAIMS="${2:-}"; shift 2 ;;
    --since)     SINCE="${2:-}"; shift 2 ;;
    --min-count) MIN_COUNT="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,60p' "$0"; exit 0 ;;
    *)           die "unknown arg '$1'" ;;
  esac
done

case "$CLASS" in
  skill|stage-file|workflow|subagent-stop) ;;
  "") die "--class is required (skill|stage-file|workflow|subagent-stop)" ;;
  *)  die "unknown --class '$CLASS' (skill|stage-file|workflow|subagent-stop)" ;;
esac

jq -e 'type == "array" and (all(type == "string"))' <<< "$CLAIMS" >/dev/null 2>&1 \
  || die "--claims must be a JSON array of strings, got: $CLAIMS"

# The cardinality classes count rows instead of matching claim strings, so their
# "claim" is a count. Default 1 — one dispatch is the minimum a claim implies.
if [[ -n "$MIN_COUNT" ]]; then
  [[ "$MIN_COUNT" =~ ^[0-9]+$ ]] || die "--min-count must be a non-negative integer, got: $MIN_COUNT"
else
  case "$CLASS" in
    workflow|subagent-stop) MIN_COUNT=1 ;;
    *)                      MIN_COUNT=0 ;;
  esac
fi

# `-R -s` slurps stdin as one string so a malformed line can be dropped rather
# than aborting the whole read: a ledger is append-only from a hook that may be
# killed mid-write, and one torn trailing line must not make a whole run
# unverifiable. `fromjson? // empty` is the per-line tolerance.
VERDICT_LINE=$(jq -R -s -r \
  --arg class "$CLASS" \
  --argjson claims "$CLAIMS" \
  --arg since "$SINCE" \
  --argjson want "$MIN_COUNT" '
  def bn: (. // "") | split("/") | last // "";
  def norm: (.target // "");

  [ split("\n")[] | select(length > 0) | (fromjson? // empty) ] as $rows

  # Class admissibility. The subagent-stop arm deliberately omits the
  # `subagent == ""` filter; every other arm requires it.
  | (if   $class == "skill"     then [ $rows[] | select((.tool // "") == "Skill"    and ((.subagent // "") == "")) ]
     elif $class == "stage-file" then [ $rows[] | select((.tool // "") == "Read"     and ((.subagent // "") == "")) ]
     elif $class == "workflow"   then [ $rows[] | select((.tool // "") == "Workflow" and ((.subagent // "") == "")) ]
     else                             [ $rows[] | select((.event // "") == "SubagentStop") ]
     end) as $classed

  | (if $since == "" then $classed else [ $classed[] | select((.ts // "") >= $since) ] end) as $adm

  # What was claimed: a string set for the matching classes, a count for the
  # cardinality classes.
  | (if $class == "skill" or $class == "stage-file" then ($claims | length) else $want end) as $claimed

  | if $claimed == 0 then
      "vacuous\tno claim of this class — leg does not apply"

    # Zero-rows arm FIRST (see the order note in the header).
    elif ($adm | length) == 0 then
      "refused\tclaimed \($claimed) item(s) of class \($class) but the joined ledger holds no admissible row"

    # All-empty-target arm. Skipped for subagent-stop, which is cardinality-only
    # and never reads `target` — every current-hook SubagentStop row carries
    # `target: ""`, so applying it there would degrade every single run.
    elif ($class != "subagent-stop") and ([ $adm[] | norm ] | all(. == "")) then
      "degraded\t\($adm | length) admissible \($class) row(s), all with an empty or absent target (ledger predates audit-toolkit 2.1.0)"

    elif $class == "skill" then
      ([ $adm[] | norm ]) as $t
      | ([ $claims[] | select(. as $c | ($t | index($c)) == null) ]) as $miss
      | (if ($miss | length) == 0 then "corroborated\t\($claims | length) skill claim(s) matched"
         else "refused\tno main-loop Skill row for: \($miss | join(", "))" end)

    elif $class == "stage-file" then
      # Basename EQUALITY, not suffix-matching: `x9-open-pr.md` must not satisfy
      # a `9-open-pr.md` claim.
      ([ $adm[] | (norm | bn) ]) as $t
      | ([ $claims[] | select(. as $c | ($t | index($c)) == null) ]) as $miss
      | (if ($miss | length) == 0 then "corroborated\t\($claims | length) stage-file claim(s) matched"
         else "refused\tno main-loop Read row for: \($miss | join(", "))" end)

    elif $class == "workflow" then
      # The hook records `scriptPath` and falls back to `name`; match both arms.
      ([ $adm[] | select(((norm | bn) == "code-review.mjs") or (norm == "code-review")) ] | length) as $n
      | (if $n >= $claimed then "corroborated\t\($n) code-review Workflow row(s) for \($claimed) claimed round(s)"
         else "refused\t\($n) code-review Workflow row(s) but \($claimed) review round(s) claimed" end)

    else
      ($adm | length) as $n
      | (if $n >= $claimed then "corroborated\t\($n) SubagentStop row(s), \($claimed) required"
         else "refused\t\($n) SubagentStop row(s) but \($claimed) required" end)
    end
') || die "jq failed while evaluating the ledger excerpt" 2

printf '%s\n' "$VERDICT_LINE"
