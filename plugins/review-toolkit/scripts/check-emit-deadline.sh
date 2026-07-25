#!/usr/bin/env bash
# check-emit-deadline.sh — an agent that raised its turn cap must also carry an emit
# deadline. Raising `maxTurns` alone is not a fix and this lint exists to say so
# mechanically, because prose did not hold it (#183).
#
# WHY THIS EXISTS: an agent whose mandate is exhaustive ("enumerate every scope item",
# "propose mutants for every changed module") spends its whole turn budget exploring and
# dies at the cap having emitted nothing. The caller gets an empty result, records the
# domain as unreviewed, and the gate silently does not run. The instinctive fix is to
# raise the cap. It does not work, and that has now been measured twice:
#
#   #175 raised scope-completeness-reviewer and unit-test-mutation-reviewer 15 -> 30.
#   At the NEW cap, scope-completeness-reviewer died on BOTH attempts of a standalone
#   review-lead run — 31 and 33 tool calls, final text "I'll fetch the issue and the
#   diff.", agents_error 0. Identical signature, 16 tool calls later.
#
#   The control is security-reviewer, in that same fan-out: same model (opus), same
#   effort, HALF the cap (maxTurns 15) — and it completed. The difference is that its
#   doc carries "By turn 10 (of your 15 maximum) you MUST be writing the report."
#
# The variable is the DEADLINE, not the budget. An agent told to be exhaustive and never
# told when to stop will spend any finite budget, so every cap is a wall it walks into.
# A deadline is the only thing that makes the agent write before the wall.
#
# THE RULE (applies to agents above the panel default cap — i.e. exactly the agents
# somebody already tried to fix by raising the number):
#
#   1. The body must carry a turn-numbered deadline: "turn <D> (of your <N> maximum)".
#   2. D < N — a deadline at or past the cap is not a deadline.
#   3. D <= ceil(2N/3) — the deadline must leave real room to write. This is what makes
#      a cap bump useless on its own: raise N and the ratio check drags D up with it, so
#      you cannot buy exploration without also buying a stricter write-by turn.
#   4. The N cited in the body must MATCH the frontmatter cap. This is the anti-drift
#      half: bump `maxTurns: 30` -> `45` and forget the doc, and the doc still says
#      "of your 30 maximum" — mismatch, red. A silent cap bump is not expressible.
#
# ESCAPE HATCH — a declared, reasoned waiver, never a silent one:
#
#   <!-- emit-deadline-exempt: <reason> -->
#
# The separator is ASCII `--`-free on purpose (it sits inside an HTML comment); the
# reason must be non-empty, mirroring the declared-waiver idiom in
# check-bounded-exploration.sh.
#
# Agents AT or BELOW the default cap are not required to carry a deadline: they are held
# by the dispatch-time bounding nudge instead, which is check-bounded-exploration.sh's
# jurisdiction. The two lints are complements — that one polices "explore less" for the
# bounded agents, this one polices "write sooner" for the exhaustive ones that cannot
# take a bounding nudge without losing the coverage that is their deliverable.
#
# Usage: check-emit-deadline.sh [agents-dir ...]   (default: every plugins/*/agents dir)
# Exit 0 = clean, 1 = violations.

set -uo pipefail

# The panel default cap. An agent at or below this is bounded at dispatch instead.
DEFAULT_CAP=15

FAIL=0
CHECKED=0

# Resolve the roots to scan. Explicit args win; otherwise walk up from this script to the
# repo root and take every plugins/*/agents dir that exists.
if [ "$#" -gt 0 ]; then
  ROOTS="$*"
else
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO="$(cd "$HERE/../../.." && pwd)"
  ROOTS=""
  for d in "$REPO"/plugins/*/agents; do
    [ -d "$d" ] && ROOTS="$ROOTS $d"
  done
fi

for dir in $ROOTS; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue

    # Frontmatter cap only: the first `maxTurns:` between the opening and closing `---`.
    cap="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^maxTurns:[[:space:]]*[0-9]+/{gsub(/[^0-9]/,""); print; exit}' "$f")"
    [ -n "$cap" ] || continue
    [ "$cap" -gt "$DEFAULT_CAP" ] || continue

    CHECKED=$((CHECKED + 1))
    name="$(basename "$f")"

    # Declared waiver — must carry a non-empty reason. The reason is extracted between the
    # colon and the comment close and then trimmed, rather than matched by a character
    # class: a class permissive enough to accept a real reason also accepts the `--` of
    # `-->`, which silently turns `<!-- emit-deadline-exempt: -->` into a blanket waiver.
    exempt_line="$(grep -oE '<!--[[:space:]]*emit-deadline-exempt:.*' "$f" | head -1)"
    if [ -n "$exempt_line" ]; then
      reason="$(echo "$exempt_line" \
        | sed -e 's/.*emit-deadline-exempt:[[:space:]]*//' -e 's/[[:space:]]*--*>.*$//' -e 's/[[:space:]]*$//')"
      if [ -n "$reason" ]; then
        echo "  SKIP: $name — declared emit-deadline-exempt ($reason)"
        continue
      fi
      echo "  FAIL: $name — emit-deadline-exempt carries no reason; a waiver must state why." >&2
      FAIL=$((FAIL + 1))
      continue
    fi

    # "turn **20** (of your 30 maximum)" — markdown emphasis around either number is
    # tolerated, since both live docs bold the turn number.
    line="$(grep -oiE 'turn[[:space:]]+\*{0,2}[0-9]+\*{0,2}[[:space:]]*\([[:space:]]*of[[:space:]]+your[[:space:]]+\*{0,2}[0-9]+\*{0,2}[[:space:]]+maximum' "$f" | head -1)"
    if [ -z "$line" ]; then
      echo "  FAIL: $name — maxTurns:$cap is above the default $DEFAULT_CAP but the body declares no emit deadline." >&2
      echo "        Add: 'By **turn <D>** (of your $cap maximum) you MUST be writing the final result.'" >&2
      echo "        Raising the cap is not a fix on its own (#183) — the deadline is what makes the agent emit." >&2
      FAIL=$((FAIL + 1))
      continue
    fi

    deadline="$(echo "$line" | grep -oE '[0-9]+' | head -1)"
    cited="$(echo "$line" | grep -oE '[0-9]+' | tail -1)"

    if [ "$cited" != "$cap" ]; then
      echo "  FAIL: $name — frontmatter says maxTurns:$cap but the deadline text cites '$cited maximum'." >&2
      echo "        The cap moved and the deadline did not. Update both together, or the raise is a silent no-op." >&2
      FAIL=$((FAIL + 1))
      continue
    fi

    if [ "$deadline" -ge "$cap" ]; then
      echo "  FAIL: $name — deadline turn $deadline is not below the cap $cap; that is not a deadline." >&2
      FAIL=$((FAIL + 1))
      continue
    fi

    # ceil(2*cap/3) without bc — integer arithmetic only (CI runs stock bash 3.2).
    max_deadline=$(( (2 * cap + 2) / 3 ))
    if [ "$deadline" -gt "$max_deadline" ]; then
      echo "  FAIL: $name — deadline turn $deadline leaves too little room to write against a $cap cap (max $max_deadline)." >&2
      echo "        The write-by turn must scale with the cap, so raising the cap cannot buy exploration for free." >&2
      FAIL=$((FAIL + 1))
      continue
    fi

    echo "  ok: $name — cap $cap, writes by turn $deadline"
  done
done

if [ "$FAIL" -gt 0 ]; then
  echo "[emit-deadline] $FAIL violation(s) across $CHECKED above-default agent(s)" >&2
  exit 1
fi

echo "[emit-deadline] clean — $CHECKED above-default agent(s) carry a matching emit deadline"
exit 0
