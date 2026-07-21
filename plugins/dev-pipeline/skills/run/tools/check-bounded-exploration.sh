#!/usr/bin/env bash
# check-bounded-exploration.sh — every schema-carrying agent() dispatch in workflows/*.mjs
# must declare, at the dispatch site, whether a bounding nudge applies.
#
# WHY THIS EXISTS: the StructuredOutput staller is turn-budget exhaustion from grounding the
# ABSENCE of findings, and the only measured cure is a DISPATCH-TIME bounding nudge (the ROOT
# CAUSE block in workflows/code-review.mjs: ~50% -> 0/12, ~45% fewer tokens; the identical text
# in the inherited reviewer-baseline doc cured 0 of 6, so placement is load-bearing). That nudge
# shipped on exactly one of six dispatchers and the omission went unnoticed for months, aborting
# a Stage-4 run 6/6. Workflow scripts cannot `import`, so the constants are necessarily re-stated
# per file — the same shape check-model-tiers.sh polices for model tiers. Prose cannot hold this
# invariant (23 retros' worth of evidence); a lint can.
#
# The check is DECLARATION-based, never text-based: a dispatch must carry a marker saying which
# disposition applies. Keying on the nudge's literal wording is impossible by construction —
# each dispatcher needs its own wording (a plan reviewer told "don't open files" would be gutted),
# so there is no shared string to grep for.
#
# GRAMMAR — one of three markers, within the lookback window above the dispatch site:
#
#   // bounded-exploration: <CONSTANT_NAME>
#       A nudge applies. <CONSTANT_NAME> must be defined in the same file (catches a marker
#       naming a nudge that was renamed or never existed).
#
#   // bounded-exploration-optout: <target> -- <reason>
#       A declared waiver. <reason> must be non-empty: the point is that the waiver is stated,
#       not silent. Legitimate cases are agents whose job IS exhaustive coverage
#       (scope-completeness-reviewer, unit-test-mutation-reviewer), produce dispatches that write
#       specs or implement screens, and the probes whose unbounded arm is the measurement control.
#
#   // bounded-exploration-delegated: <reason>
#       This site's prompt is assembled from per-entry descriptors elsewhere in the same file, so
#       the disposition is declared at those descriptors instead. The motivating case is
#       intake-review.mjs, which has ONE agent() call fed by two DISPATCH[] descriptors whose
#       dispositions are opposite (spec-reviewer nudged, codebase-explorer opted out) and which
#       sit outside the lookback window. A file using this verb must also carry at least one
#       non-delegated marker, so `delegated` cannot degrade into a blanket waiver.
#
# SEPARATOR is ASCII `--`, deliberately not an em-dash: a non-ASCII token inside a grep pattern is
# the fragility class ledger-lint.sh already suffers from.
#
# SITE DETECTION: every `schema:` key occurrence, matched ANYWHERE on the line rather than
# line-anchored, and INCLUDING descriptor objects (not just agent() opts). Both halves are
# load-bearing and were found the hard way:
#   - A line-anchored `^\s*schema:` finds 10 of the 16 real sites, missing every inline
#     `agent(prompt, { ... schema: X })` form.
#   - Treating only agent() opts as sites cannot express intake-review.mjs, where two conflicting
#     dispositions meet at one call. Counting descriptors as sites is what makes that expressible.
#
# LOOKBACK is bounded BELOW by the previous site in the same file, so one marker can never
# satisfy two adjacent sites. Six of eight files have site pairs closer together than the window
# (as little as 13 lines apart) — including the intake-review.mjs pair this grammar exists to
# separate — so an unbounded window would silently degrade the check to "at least one marker per
# window" and re-open the hole.
#
# Bash 3.2 compatible (macOS system bash): no mapfile, no associative arrays. Pairs with
# check-bounded-exploration-selftest.sh, which CI discovers by its *-selftest.sh glob.
#
# Usage: check-bounded-exploration.sh [<workflows-dir>]
#        Default dir is the sibling workflows/ of this script's skills/run root.
# Exit:  0 clean; otherwise the number of undeclared dispatch sites.

set -uo pipefail

LOOKBACK=40

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(dirname "$SCRIPT_DIR")" # skills/run
WORKFLOWS="${1:-$RUN_DIR/workflows}"

if [[ ! -d "$WORKFLOWS" ]]; then
  echo "check-bounded-exploration: FAIL — no workflows dir at $WORKFLOWS" >&2
  exit 1
fi

FAILS=0
SITES=0
FILES=0

for f in "$WORKFLOWS"/*.mjs; do
  [[ -f "$f" ]] || continue
  case "$f" in
    *-selftest.mjs) continue ;; # offline test harnesses carry no live dispatches
  esac

  # Sites in this file, in line order. A `schema:` key anywhere on the line (see SITE DETECTION) —
  # except comment lines: prose like "// No schema: the death class cannot occur" is not a
  # dispatch site, and counting it would demand markers for documentation.
  site_lines=$(grep -nE '(^|[[:space:]{(,])schema:' "$f" | grep -Ev '^[0-9]+:[[:space:]]*//' | cut -d: -f1)
  [[ -n "$site_lines" ]] || continue
  FILES=$((FILES + 1))

  # Does this file declare any non-delegated marker? Guards the `delegated` verb.
  non_delegated=$(grep -cE '//[[:space:]]*bounded-exploration(-optout)?:' "$f")

  prev=0
  for line in $site_lines; do
    SITES=$((SITES + 1))
    start=$((line - LOOKBACK))
    # Never look back past the previous site — one marker must not cover two dispatches.
    [[ "$start" -le "$prev" ]] && start=$((prev + 1))
    [[ "$start" -lt 1 ]] && start=1
    end=$((line - 1))
    prev="$line"

    window=""
    [[ "$end" -ge "$start" ]] && window=$(sed -n "${start},${end}p" "$f")

    # --- nudge marker ---
    ident=$(printf '%s\n' "$window" \
      | grep -oE '//[[:space:]]*bounded-exploration:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' \
      | sed -E 's|.*bounded-exploration:[[:space:]]*||' | tail -1)
    if [[ -n "$ident" ]]; then
      if grep -qE "(^|[[:space:]])(const|let|var)[[:space:]]+${ident}[[:space:]]*=" "$f"; then
        continue
      fi
      echo "  FAIL: $f:$line — marker names '$ident', which is not defined in this file" >&2
      FAILS=$((FAILS + 1))
      continue
    fi

    # --- declared opt-out ---
    optout=$(printf '%s\n' "$window" \
      | grep -oE '//[[:space:]]*bounded-exploration-optout:.*' | tail -1)
    if [[ -n "$optout" ]]; then
      # Require `<target> -- <reason>` with a non-empty reason.
      reason=$(printf '%s\n' "$optout" | sed -E 's|.*[[:space:]]--[[:space:]]*||')
      if [[ "$optout" == *" -- "* && -n "${reason// /}" ]]; then
        continue
      fi
      echo "  FAIL: $f:$line — opt-out must read 'bounded-exploration-optout: <target> -- <reason>' with a non-empty reason" >&2
      FAILS=$((FAILS + 1))
      continue
    fi

    # --- delegated to per-entry descriptors ---
    delegated=$(printf '%s\n' "$window" \
      | grep -oE '//[[:space:]]*bounded-exploration-delegated:.*' | tail -1)
    if [[ -n "$delegated" ]]; then
      dreason=$(printf '%s\n' "$delegated" | sed -E 's|.*bounded-exploration-delegated:[[:space:]]*||')
      if [[ -z "${dreason// /}" ]]; then
        echo "  FAIL: $f:$line — delegated marker needs a reason" >&2
        FAILS=$((FAILS + 1))
      elif [[ "$non_delegated" -eq 0 ]]; then
        echo "  FAIL: $f:$line — 'delegated' but the file declares no per-entry disposition (blanket waiver)" >&2
        FAILS=$((FAILS + 1))
      fi
      continue
    fi

    echo "  FAIL: $f:$line — schema-carrying dispatch with no bounded-exploration marker" >&2
    FAILS=$((FAILS + 1))
  done
done

if [[ "$SITES" -eq 0 ]]; then
  # A regex that matches nothing must never read as green — that is the failure mode this
  # lint exists to prevent, applied to the lint itself.
  echo "check-bounded-exploration: FAIL — no dispatch sites found in $WORKFLOWS (detection is broken)" >&2
  exit 1
fi

echo "check-bounded-exploration: $SITES dispatch site(s) across $FILES file(s), $FAILS undeclared"
exit "$FAILS"
