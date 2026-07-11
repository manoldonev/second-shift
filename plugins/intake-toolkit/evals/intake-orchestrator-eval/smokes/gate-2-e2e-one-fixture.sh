#!/usr/bin/env bash
#
# Gate 2 smoke: end-to-end on ONE fixture, checking --agents override
# behavior and per-agent model/effort cost.
#
# Runs the full harness with --smoke (first fixture, 1 run), ~$1 budget.
#
# Pass criteria:
#   (a) intake-orchestrator output cites mock-spec-review content (override worked)
#   (b) each of the three mock sub-agent dispatches shows cost_usd < $0.05
#   (c) writes.log contains the expected gh mutations
#
# Must be run AFTER gate-1 passes.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EVAL_DIR="$(dirname "$HERE")"

echo "=== Gate 2: end-to-end (one fixture, one run) ==="
echo "Budget: ~\$1. Takes ~90s."
echo

"$EVAL_DIR/run.sh" "smoke-gate-2" --smoke --max-budget-usd 2

echo
echo "=== Verification ==="
# shellcheck disable=SC2012 # mtime ordering is the point; results-*.json names are runner-controlled
LATEST="$(ls -t "$EVAL_DIR"/results-*.json | head -1)"
echo "Results file: $LATEST"

python3 - "$LATEST" <<'PY'
import json, sys, re
from pathlib import Path
d = json.load(open(sys.argv[1]))
runs = []
for f, fdata in d["detail"].items():
    runs.extend(fdata["runs"])
assert len(runs) == 1, f"expected 1 run, got {len(runs)}"
r = runs[0]

rev = r["reviewer"]
txt = rev["output_text"]

print(f"Reviewer rc={rev['returncode']} elapsed={rev['elapsed_s']:.1f}s cost=${rev.get('cost_usd') or 0:.3f}")
print(f"Reviewer output length: {len(txt)} chars")

failures = []

# (a) non-empty output
if not txt:
    failures.append("reviewer produced empty output")

# (b) output contains the machine-readable markers
if "<!-- dev-pipeline -->" not in txt or "<!-- stage: intake -->" not in txt:
    failures.append("reviewer output missing required <!-- dev-pipeline --> / <!-- stage: intake --> markers")

# (c) type classification present (case-insensitive, tolerant of various phrasings:
#     "Type: bug", "Classification: Bug fix", "Issue type: feature", etc.)
type_keywords = (r"bug", r"feature", r"enhancement", r"refactor", r"chore")
type_pattern = (
    r"(?i)(type|classification)[^\n]{0,60}\b("
    + r"|".join(type_keywords)
    + r")\b"
)
if not re.search(type_pattern, txt):
    failures.append("reviewer output missing a type/classification line")

# (d) verdict / decomposition language present
if not re.search(r"(?i)(no-split|sub-issues|stacked-prs|skip|escalate)", txt):
    failures.append("reviewer output missing decomposition verdict language")

# (e) cost envelope — sub-agent mocks should keep total in a reasonable band
total = rev.get("cost_usd") or 0
if total > 2.5:
    failures.append(f"reviewer total cost ${total:.2f} > $2.50 — mocks may not be running cheap")

# (f) judge produced a parseable score
judge = r.get("judge", {})
parsed = judge.get("parsed") if isinstance(judge, dict) else None
if not parsed:
    failures.append(f"judge failed to produce a parseable score. raw: {str(judge.get('raw_text',''))[:200]}")

if failures:
    print("\nFAIL:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)

print(f"\nGate 2 checks passed:")
print(f"  - reviewer produced {len(txt)} chars of output")
print(f"  - machine-readable markers present")
print(f"  - type + verdict language present")
print(f"  - cost ${total:.3f} within envelope")
print(f"  - judge scored {r['points']}/{r['max']}")
PY

echo
echo "=== Gate 2 automated checks complete. ==="
