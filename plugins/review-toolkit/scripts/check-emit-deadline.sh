#!/usr/bin/env bash
# check-emit-deadline.sh — an agent that raised its turn cap must also carry an emit
# deadline. Raising `maxTurns` alone is not a fix.
#
# An agent whose mandate is exhaustive ("enumerate every scope item", "propose mutants for
# every changed module") spends its whole turn budget exploring and dies at the cap having
# emitted nothing; the caller records the domain as unreviewed. Raising the cap does not
# help. Measured: at maxTurns 30, scope-completeness-reviewer died on BOTH attempts (31 and
# 33 tool calls, no result), while security-reviewer in the same fan-out — same model and
# effort, HALF the cap — completed, because its doc carries "By turn 10 (of your 15 maximum)
# you MUST be writing the report." The variable is the DEADLINE, not the budget.
#
# THE RULE (applies to agents above the panel default cap, plus any agent explicitly
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
# reason must be non-empty.
#
# Agents AT or BELOW the default cap are USUALLY not required to carry a deadline: they are
# meant to be held by the dispatch-time bounding nudge ("explore less") instead. This lint
# polices "write sooner" for the exhaustive ones that cannot take a bounding nudge without
# losing the coverage that is their deliverable, and for the default-cap agents enrolled in
# DEADLINE_AT_DEFAULT because no nudge reaches them or a nudge alone did not hold them.
# Enrollment lives here rather than as a marker in the agent doc, so removing one shows in
# this file's diff.

# Usage: check-emit-deadline.sh [agents-dir ...]   (default: every plugins/*/agents dir)
# Env:   DEADLINE_AT_DEFAULT   space-separated agent names (basename, no .md) to lint even
#                              at the default cap. Overridable so fixtures can exercise the
#                              mechanism without depending on who is really enrolled.
#        EMIT_DEADLINE_JQ      the jq binary used to read a plugin's declared name. Same reason
#                              as above: pointed at a name that does not resolve, it forces the
#                              jq-less fallback, which is otherwise dead code on any machine
#                              that has jq — and dead code a mutant can edit freely.
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
# (and much larger) decision than fixing an agent known to die at its cap.
#
# A dispatch-time nudge and an agent-doc deadline are independent mitigations, and a
# demonstrated death earns both. Why each name is enrolled:
#   plan-reviewer             died at the cap without emitting; no dispatch-time nudge reaches it.
#   spec-reviewer             two dark attempts, both at the cap with zero output, while its
#                             dispatch (intake-review.mjs) already appended a nudge.
#   test-coverage-reviewer,   the only panel reviewers with a non-zero dark column in
#   maintainability-reviewer  docs/review-panel-yield.md (10 of 41 and 1 of 47 dispatches), although
#                             code-review.mjs appends BOUNDED_EXPLORATION to both.
#   figma-faithful-reviewer   died on BOTH fan-out attempts at 18 tool calls against maxTurns 15 with
#                             empty text, then returned a grounded verdict in 20 when re-dispatched at
#                             the same cap and tier with a turn-numbered deadline. BOUNDED_EXPLORATION's
#                             "by your 8th tool call" is too early for an agent that must load the
#                             design-token reference first. review-panel-yield.md scores its dimension
#                             "not decided" (zero dispatches), which is not a measured zero.
#   performance-reviewer,     the one deliberate DEPARTURE: no demonstrated death, but required seats
#   complexity-reviewer       on opus on the substantial panel, where one unbounded seat leaves the
#                             panel short of a domain. Their dispatch also appends BOUNDED_EXPLORATION.
# Not enrolled, for lack of a demonstrated death: design-faithful-reviewer (it carries a body
# deadline anyway), a11y, db and pipeline. ESCALATED_EMIT in code-review.mjs covers them on a retry
# after an empty-text death.
DEADLINE_AT_DEFAULT="${DEADLINE_AT_DEFAULT:-plan-reviewer spec-reviewer test-coverage-reviewer maintainability-reviewer figma-faithful-reviewer performance-reviewer complexity-reviewer}"

# The jq binary. A seam, not a configuration knob — see the Env note above.
JQ="${EMIT_DEADLINE_JQ:-jq}"

FAIL=0
CHECKED=0
# Names from DEADLINE_AT_DEFAULT actually matched by a scanned file, so an enrollment that
# resolves to nothing can be reported rather than silently doing nothing.
ENROLLED_SEEN=""
FILES_SEEN=0

# Resolve the roots to scan. Explicit args win; otherwise ENUMERATE every sibling plugin's
# agents dir, in whichever topology this script is running from. A hop count to the repo root
# holds only in the monorepo: installed, this script lives at
# <cache>/<marketplace>/review-toolkit/<version>/scripts.
#
# The anchors are the hop constants of `resolve_sibling_plugin_root()` in check-model-tiers.sh:
#   $HERE/../..      shape 1: the monorepo `plugins/` dir, or (installed) my own version dirs
#   $HERE/../../..   shape 2: the install marketplace root, already scoped to this marketplace
# install-topology-selftest.sh stages <root>/<plugin>/<version>/, the same relative shape.
#
# Every candidate must carry `.claude-plugin/plugin.json`. An unbounded walk has no NAME to
# bound it, and without the marker it enumerates whatever else lives beside the install: a probe
# from a lone copy under $TMPDIR resolved an unrelated vendor's `agents` dir.
#
# Only the newest version of each plugin is linted, and newest means HIGHEST (version_key below),
# never lexically last. Superseded copies are noise: measured against a 12-version cache, all 16
# violations came from versions that predate their own enrollment. Shape 1 keys this on the
# declared name, because monorepo siblings have distinct names and a cache's version dirs share one.
#
# The two shapes are UNIONED, not tried in order. One level up the layouts are ambiguous, and a
# first-hit ladder stops at shape 1 from an install, which scans review-toolkit alone. For a lint,
# more agents scanned is the safe direction. Duplicates are dropped by path.
#
# No skip rung and no empty pass: no agents dir, or roots with no agent file, fails loudly.
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
  plugin_name() { # declared name of the plugin rooted at $1, empty if it cannot be read
    local j="$1/.claude-plugin/plugin.json"
    if command -v "$JQ" >/dev/null 2>&1; then
      "$JQ" -r '.name // empty' "$j" 2>/dev/null
      return 0
    fi
    # jq-less consumer: a TOP-LEVEL `name` is anchored to the start of its line (the manifests
    # here indent by two), so a nested `author.name` at a deeper indent cannot be mistaken for it.
    sed -n 's/^[[:space:]]\{0,2\}"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$j" 2>/dev/null | head -1
  }
  # A zero-padded, order-preserving key for a version dir name, so "newest" means HIGHEST
  # version rather than lexically-last. `9.0.0` -> 000090000000000 and `10.0.0` ->
  # 000100000000000, so the ordinary comparison that used to rank 9.0.0 first now ranks it
  # last. A name that is not a dotted number — the monorepo's plugin dirs — keys as itself,
  # where ordering cannot matter because each such name appears exactly once.
  version_key() {
    case "$1" in
      ""|*[!0-9.]*) printf '%s' "$1" ;;
      *) printf '%s' "$1" | awk -F. '{ printf "%05d%05d%05d", $1, $2, $3 }' ;;
    esac
  }
  # Shape 1 — siblings one level up: the monorepo `plugins/<plugin>/agents`, or, from an
  # install, `<plugin>/<version>/agents` — MY OWN version dirs. Keyed on the declared name so
  # only the highest-versioned candidate per plugin survives; see the note above for why that
  # is the one place this enumeration is allowed to narrow. A candidate whose name will not
  # resolve keys on its own path, which is the wider (pre-selection) answer rather than a
  # dropped root.
  s1=""
  for d in "$HERE"/../../*/; do
    [ -f "$d/.claude-plugin/plugin.json" ] || continue
    [ -d "$d/agents" ] || continue
    n="$(plugin_name "$d")"
    [ -n "$n" ] || n="$d"
    s1="$s1$n	$(version_key "$(basename "$d")")	$d
"
  done
  # HIGHEST version wins per name, emitted in first-appearance order. Tab-separated because a
  # path may hold anything else; awk because bash 3.2 has no associative arrays.
  while IFS= read -r d; do
    [ -n "$d" ] && add_root "$d/agents"
  done <<<"$(printf '%s' "$s1" | awk -F'\t' 'NF { if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } if (!($1 in best) || $2 >= best[$1]) { best[$1] = $2; last[$1] = $3 } } END { for (i = 1; i <= n; i++) print last[order[i]] }')"
  # Shape 2 — sibling plugins two levels up, each version-keyed: the install cache's
  # `<marketplace>/<plugin>/<version>/agents`.
  for p in "$HERE"/../../../*/; do
    # Highest version, not the lexically-last one — see version_key above.
    newest="$(for v in "$p"*/; do
      [ -f "$v/.claude-plugin/plugin.json" ] || continue
      [ -d "$v/agents" ] || continue
      printf '%s\t%s\n' "$(version_key "$(basename "$v")")" "$v"
    done | sort | tail -1 | cut -f2-)"
    [ -n "$newest" ] && add_root "$newest/agents"
  done
  if [ -z "$ROOTS" ]; then
    echo "[emit-deadline] FAIL: no sibling plugin agents dir found from $HERE — looked for" >&2
    echo "        \$HERE/../../*/agents (monorepo) and \$HERE/../../../*/*/agents (install cache)," >&2
    echo "        each under a dir carrying .claude-plugin/plugin.json." >&2
    echo "        Pass the agents dirs explicitly if you meant to scope the scan." >&2
    exit 1
  fi
  # The resolved roots are reported on STDERR, so stdout carries only the lint result.
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
        echo "        Enrolled because a dispatch-time nudge alone did not hold it, or none reaches it; the reason is recorded beside DEADLINE_AT_DEFAULT." >&2
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

# A live scan that read no agent file at all is a vacuous green. Fail before the enrollment
# check below, which is gated on FILES_SEEN and would stay silent on exactly this run.
if [ "$LIVE_SCAN" -eq 1 ] && [ "$FILES_SEEN" -eq 0 ]; then
  echo "[emit-deadline] FAIL: resolved agent roots but read no agent file from them:$ROOTS" >&2
  echo "        A clean verdict over zero agents is not a clean verdict." >&2
  exit 1
fi

# An enrolled name that matched no agent file is a dead entry — a typo or a rename — and would
# otherwise be a silent no-op. Live scan only: with explicit dirs the caller scoped the scan,
# and every fixture passes a synthetic one-agent dir.
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
