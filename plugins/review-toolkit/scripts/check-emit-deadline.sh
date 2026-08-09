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
# somebody already tried to fix by raising the number — plus any agent explicitly
# enrolled via DEADLINE_AT_DEFAULT below):
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
# Agents AT or BELOW the default cap are USUALLY not required to carry a deadline: they are
# meant to be held by the dispatch-time bounding nudge instead, which is
# check-bounded-exploration.sh's jurisdiction. The two lints are complements — that one
# polices "explore less" for the bounded agents, this one polices "write sooner" for the
# exhaustive ones that cannot take a bounding nudge without losing the coverage that is
# their deliverable.
#
# THE GAP BETWEEN THEM. That division assumes every default-cap agent's dispatch site
# actually appends a nudge. plan-reviewer's does not — its dispatch declares the nudge
# dormant on purpose:
#
#   // bounded-exploration-dormant: BOUNDED_PLAN_GROUNDING -- defined for probe lockstep;
#   // deliberately not appended (measured no-nudge arm)
#       — plugins/dev-pipeline/skills/run/workflows/plan-review.mjs
#
# So plan-reviewer was held by NEITHER lint: unbounded at dispatch (deliberately, as the
# measurement control) and unlinted here (because it sits exactly at the cap). It died at
# the cap without emitting while this lint reported clean. DEADLINE_AT_DEFAULT is the
# narrow fix: it brings a NAMED default-cap agent into jurisdiction without extending the
# requirement to the whole panel. Enrollment lives here, in the lint, rather than as a
# marker in the agent doc, so removing one is visible in this file's diff instead of being
# a one-line silent edit in somebody's prose — the same reason the exemption above must
# state a reason.
#
# spec-reviewer (#283) is a SECOND demonstrated case, of a different shape: its dispatch
# site (intake-review.mjs) does append a dispatch-time nudge (PROGRESSIVE_EMIT), so it is
# not held by neither lint the way plan-reviewer was — but the nudge alone did not prevent
# the observed death (run #273: two dark attempts, both at the turn cap with zero output,
# while a WEAKER nudge, BOUNDED_SPEC_GROUNDING, was already in place). The belt-and-
# suspenders lesson from security-reviewer/scope-completeness-reviewer/unit-test-mutation-
# reviewer holds here too: the dispatch-time nudge and the agent-doc deadline are
# independent mitigations, and a demonstrated death earns both, not either.
#

# Usage: check-emit-deadline.sh [agents-dir ...]   (default: every plugins/*/agents dir)
# Env:   DEADLINE_AT_DEFAULT   space-separated agent names (basename, no .md) to lint even
#                              at the default cap. Overridable so fixtures can exercise the
#                              mechanism without depending on who is really enrolled.
# Exit 0 = clean, 1 = violations.

set -uo pipefail

# The panel default cap. An agent at or below this is bounded at dispatch instead —
# UNLESS it is enrolled below.
DEFAULT_CAP=15

# Agents held to the deadline contract despite sitting at (or below) the default cap.
# Space-separated basenames, matched WHOLE — never as substrings: `plan-reviewer` is a
# substring of both `unit-test-plan-reviewer` and `figma-faithful-plan-reviewer`, and a
# substring match would silently conscript agents nobody enrolled.
#
# Add a name only on a DEMONSTRATED death — an agent observed hitting its cap without
# emitting — never prophylactically. Enrolling the whole default-cap panel is a different
# (and much larger) decision than fixing an agent known to be falling through the gap.
DEADLINE_AT_DEFAULT="${DEADLINE_AT_DEFAULT:-plan-reviewer spec-reviewer}"

FAIL=0
CHECKED=0
# Names from DEADLINE_AT_DEFAULT actually matched by a scanned file, so an enrollment that
# resolves to nothing can be reported rather than silently doing nothing.
ENROLLED_SEEN=""
FILES_SEEN=0

# Resolve the roots to scan. Explicit args win; otherwise ENUMERATE every sibling plugin's
# agents dir, in whichever topology this script is running from.
#
# WHY NOT A HOP COUNT TO THE REPO ROOT. The previous form derived `$HERE/../../..` as "the
# repo" and globbed `$REPO/plugins/*/agents`. That hop count only holds in the monorepo:
# installed, this script lives at <cache>/<marketplace>/review-toolkit/<version>/scripts, so
# the same expression lands on the marketplace root — which has no `plugins/` — and the scan
# found ZERO agents while reporting clean.
#
# THE ANCHORS. This is the enumeration cousin of `resolve_sibling_plugin_root()` in
# check-model-tiers.sh, which sits in THIS directory, so its hop constants transfer verbatim:
#   $HERE/../..      the monorepo `plugins/` dir      (its `$SCRIPT_DIR/../../<name>` rung)
#   $HERE/../../..   the install marketplace root     (its `$SCRIPT_DIR/../../../<name>/*/` rung)
# The marketplace root is already scoped to this plugin's own marketplace, so enumerating its
# children cannot reach another marketplace's plugins. install-topology-selftest.sh stages
# <root>/<plugin>/<version>/, the same relative shape.
#
# WHAT COUNTS AS A PLUGIN. The named ladders can afford a loose marker because the NAME already
# bounds them; an unbounded walk cannot. Every candidate must therefore carry
# `.claude-plugin/plugin.json` — this repo's own definition of a plugin dir, and the same glob
# install-topology-selftest.sh stages from. Without it the cache rung is just "every sibling
# directory of my grandparent", which, run from anywhere unexpected, happily enumerates
# whatever else lives there. That is not hypothetical: a probe of an earlier draft of this
# block, from a lone copy under $TMPDIR, resolved an unrelated vendor's `agents` dir.
#
# Newest version per plugin, selected LEXICALLY — glob order, so the last match wins, the same
# `sort -r`/`tail -1` semantics both house ladders use. `9.0.0` therefore outranks `10.0.0`;
# that is a shared latent defect deliberately mirrored rather than fixed here.
#
# THE TWO SHAPES ARE UNIONED, NOT TRIED IN ORDER. The named ladders can afford "first rung that
# hits wins" because a NAME tells the two layouts apart: in a cache, `review-toolkit/<name>`
# does not exist, so rung 1 misses and rung 2 runs. An enumeration has no name to miss on, and
# one level up the layouts are genuinely ambiguous — `plugins/` and `<cache>/review-toolkit/`
# are both "a directory of dirs carrying plugin.json". A first-hit ladder therefore stops at
# shape 1 from an install, where shape 1 matches MY OWN version dirs and nothing else: measured,
# that scanned review-toolkit alone and silently dropped design-toolkit and intake-toolkit —
# the same narrowing this issue is about, one level shallower. Unioning cannot narrow, and for a
# lint the safe direction is more agents scanned, never fewer. Duplicates are dropped by path.
#
# NO SKIP RUNG, AND NO EMPTY PASS. If neither shape yields an agents dir this fails loudly —
# and so does a scan that resolved roots but read no agent file out of them, because "clean, 0
# linted" is the very report this lint spent a release emitting from an install.
LIVE_SCAN=0
if [ "$#" -gt 0 ]; then
  ROOTS="$*"
else
  LIVE_SCAN=1
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOTS=""
  add_root() { # dedup by resolved path — the two shapes overlap on my own plugin
    local r
    r="$(cd "$1" 2>/dev/null && pwd)" || return 0
    case " $ROOTS " in *" $r "*) return 0 ;; esac
    ROOTS="$ROOTS $r"
  }
  # Shape 1 — sibling plugins one level up: the monorepo `plugins/<plugin>/agents`.
  for d in "$HERE"/../../*/; do
    [ -f "$d/.claude-plugin/plugin.json" ] || continue
    [ -d "$d/agents" ] && add_root "$d/agents"
  done
  # Shape 2 — sibling plugins two levels up, each version-keyed: the install cache's
  # `<marketplace>/<plugin>/<version>/agents`.
  for p in "$HERE"/../../../*/; do
    newest=""
    for v in "$p"*/; do
      [ -f "$v/.claude-plugin/plugin.json" ] || continue
      [ -d "$v/agents" ] && newest="$v"
    done
    [ -n "$newest" ] && add_root "$newest/agents"
  done
  if [ -z "$ROOTS" ]; then
    echo "[emit-deadline] FAIL: no sibling plugin agents dir found from $HERE — looked for" >&2
    echo "        \$HERE/../../*/agents (monorepo) and \$HERE/../../../*/*/agents (install cache)," >&2
    echo "        each under a dir carrying .claude-plugin/plugin.json." >&2
    echo "        Pass the agents dirs explicitly if you meant to scope the scan." >&2
    exit 1
  fi
  # Resolution is the part that silently went wrong before, so it is reported — on STDERR, so
  # stdout stays byte-identical to a run that resolved the same roots the old way.
  echo "[emit-deadline] scanning roots:$ROOTS" >&2
fi

for dir in $ROOTS; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue

    # Frontmatter cap only: the first `maxTurns:` between the opening and closing `---`.
    cap="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^maxTurns:[[:space:]]*[0-9]+/{gsub(/[^0-9]/,""); print; exit}' "$f")"
    [ -n "$cap" ] || continue

    # Resolved BEFORE the jurisdiction gate: enrollment is keyed on the agent name, so the
    # name has to exist by the time we decide whether this agent is in scope at all.
    name="$(basename "$f")"
    agent="$(basename "$f" .md)"
    FILES_SEEN=$((FILES_SEEN + 1))

    # Whole-name membership, not a substring test.
    enrolled=0
    for e in $DEADLINE_AT_DEFAULT; do
      if [ "$agent" = "$e" ]; then
        enrolled=1
        ENROLLED_SEEN="$ENROLLED_SEEN $e"
        break
      fi
    done

    # Two ways into jurisdiction: above the default cap (the original rule, untouched), or
    # explicitly enrolled. Skip only when NEITHER holds — so this widens the gate and can
    # never narrow it.
    if [ "$cap" -le "$DEFAULT_CAP" ] && [ "$enrolled" -eq 0 ]; then
      continue
    fi

    CHECKED=$((CHECKED + 1))

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
      # Branch on WHY this agent is in jurisdiction. Telling an operator that a cap-15
      # agent "is above the default 15" is self-contradictory and unactionable.
      if [ "$cap" -gt "$DEFAULT_CAP" ]; then
        echo "  FAIL: $name — maxTurns:$cap is above the default $DEFAULT_CAP but the body declares no emit deadline." >&2
      else
        echo "  FAIL: $name — maxTurns:$cap is at the default cap, but '$agent' is enrolled in the deadline contract (DEADLINE_AT_DEFAULT) and the body declares no emit deadline." >&2
        echo "        Enrolled because its dispatch site appends no bounding nudge, so nothing else holds it." >&2
      fi
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

# An enrolled name that matched no agent file is a dead entry — a typo or a rename — and
# would otherwise be a silent no-op: the lint reports clean while the agent it was meant to
# cover goes unchecked, which is the failure this enrollment exists to fix.
#
# Live scan only. With explicit dirs the caller has deliberately scoped the scan, so an
# absent agent there carries no signal (and every fixture passes a synthetic one-agent
# dir). Also requires having seen at least one agent file, so an empty or misconfigured
# scan is not misreported as a bad enrollment.
# Resolving roots is not the same as reading agents out of them. A live scan that saw no agent
# file at all is the vacuous green in its second form — the roots looked plausible, the loop ran
# over nothing, and the lint reported clean. Fail before the enrollment check below, which is
# gated on FILES_SEEN and would otherwise stay silent on exactly this run.
if [ "$LIVE_SCAN" -eq 1 ] && [ "$FILES_SEEN" -eq 0 ]; then
  echo "[emit-deadline] FAIL: resolved agent roots but read no agent file from them:$ROOTS" >&2
  echo "        A clean verdict over zero agents is not a clean verdict." >&2
  exit 1
fi

if [ "$LIVE_SCAN" -eq 1 ] && [ "$FILES_SEEN" -gt 0 ]; then
  for e in $DEADLINE_AT_DEFAULT; do
    case " $ENROLLED_SEEN " in
      *" $e "*) ;;
      *)
        echo "  FAIL: enrolled agent '$e' (DEADLINE_AT_DEFAULT) matched no agent file in the scanned roots." >&2
        echo "        A renamed or misspelled enrollment silently lints nothing — fix the name or drop the entry." >&2
        FAIL=$((FAIL + 1))
        ;;
    esac
  done
fi

if [ "$FAIL" -gt 0 ]; then
  echo "[emit-deadline] $FAIL violation(s) across $CHECKED linted agent(s)" >&2
  exit 1
fi

echo "[emit-deadline] clean — $CHECKED linted agent(s) carry a matching emit deadline"
exit 0
