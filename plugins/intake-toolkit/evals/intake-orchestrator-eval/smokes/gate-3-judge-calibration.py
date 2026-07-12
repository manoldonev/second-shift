#!/usr/bin/env python3
"""
Gate 3 smoke: judge calibration.

Feeds the judge two hand-crafted intake outputs for fixture 01 (clean bug fix):
  - PERFECT: a correct intake comment + correct gh_writes. Must score 10/10.
  - BROKEN: wrong type, no gh_writes, ignores thresholds. Must score ≤4/10.

Cost: ~$0.20 (two judge calls at sonnet).

Run AFTER gate-2 passes.
"""

import asyncio
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVAL_DIR = HERE.parent
REPO = Path(
    __import__("subprocess").check_output(
        ["git", "-C", str(HERE), "rev-parse", "--show-toplevel"],
        text=True,
    ).strip()
)
# The shared agent-eval-kit lives in the review-toolkit plugin (sibling under plugins/):
# HERE = plugins/intake-toolkit/evals/intake-orchestrator-eval/smokes → parents[3] = plugins/
KIT = HERE.parents[3] / "review-toolkit" / "evals" / "agent-eval-kit"

# Load the runner module so we can reuse invoke_judge and load_rubric
spec = importlib.util.spec_from_file_location("run_eval", KIT / "run-eval.py")
re_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(re_mod)

JUDGE_SYSTEM, MAX_POINTS = re_mod.load_rubric(EVAL_DIR / "rubric.py")

FIXTURE_DIR = REPO / "docs" / "eval-fixtures" / "intake-orchestrator" / "01-clean-bug-fix"
FIXTURE = {
    "name": "01-clean-bug-fix",
    "path": str((FIXTURE_DIR / "issue-body.md").relative_to(REPO)),
    "content": (FIXTURE_DIR / "issue-body.md").read_text(),
    "expected": json.loads((FIXTURE_DIR / "expected.json").read_text()),
    "mocks": {},
    "mock_env_dir": None,
}

# Hand-crafted intake outputs
PERFECT_OUTPUT = """<!-- dev-pipeline -->
<!-- run_id: 2026-04-18T10:00:00Z-calibration-aa11bb22 -->
<!-- stage: intake -->
<!-- status: passed -->

## Intake Analysis — /activities empty-state 500

**Type**: bug
**Pipeline path**: spec review only (no decomposition)
**Spec verdict**: passed

The spec is clear, reproduction is concrete, and the fix approach is sound. No blockers from spec-reviewer. Proceeding to stage 3 (branch + implementation) with verdict: no-split.
"""
PERFECT_GH_WRITES = "\tissue comment 123 --body ...\n\tissue edit 123 --remove-label ready-for-dev --add-label in-progress --add-assignee @me\n"

BROKEN_OUTPUT = """## Intake Analysis

**Type**: feature
**Decomposition**: sub-issues (8 slices)

This bug should be decomposed into eight sub-issues covering every edge case.
"""
BROKEN_GH_WRITES = (
    "\tissue create --title slice1 --body ...\n"
    "\tissue create --title slice2 --body ...\n"
    "\tissue create --title slice3 --body ...\n"
    "\tissue create --title slice4 --body ...\n"
    "\tissue create --title slice5 --body ...\n"
    "\tissue create --title slice6 --body ...\n"
    "\tissue create --title slice7 --body ...\n"
    "\tissue create --title slice8 --body ...\n"
)


async def score(label, output_text, gh_writes):
    cfg = {
        "judge_system": JUDGE_SYSTEM,
        "judge_name": "intake-judge-calibration",
        "judge_desc": "Gate 3 calibration judge",
        "judge_model": "claude-sonnet-4-6",
        "effort": "high",
        "budget": 2.0,
        "judge_timeout_s": 400.0,
        "cwd": REPO,
        "max_points": MAX_POINTS,
    }
    fixture = {**FIXTURE, "_gh_writes_for_judge": gh_writes}
    sem = asyncio.Semaphore(1)
    result = await re_mod.invoke_judge(cfg, fixture, output_text, sem)
    parsed = result.get("parsed")
    if not parsed:
        print(f"  {label}: judge parse failed. raw:\n{result.get('raw_text', '')[:500]}")
        return None, result
    pts, _, per = re_mod.score_run(result, MAX_POINTS, sum(MAX_POINTS.values()))
    print(f"  {label}: {pts}/10")
    for k, v in per.items():
        print(f"    {k:32s} {v}")
    return pts, result


async def main():
    print("=== Gate 3: judge calibration ===")
    print(f"Rubric max: {sum(MAX_POINTS.values())}")
    print()
    print("[A] PERFECT output (expected 10/10)")
    p_pts, _ = await score("PERFECT", PERFECT_OUTPUT, PERFECT_GH_WRITES)
    print()
    print("[B] BROKEN output (expected ≤4/10)")
    b_pts, _ = await score("BROKEN", BROKEN_OUTPUT, BROKEN_GH_WRITES)
    print()

    ok = True
    if p_pts is None or p_pts < 9:
        print(f"FAIL: PERFECT got {p_pts}/10, expected 10 (tolerant of 9).")
        ok = False
    if b_pts is None or b_pts > 4:
        print(f"FAIL: BROKEN got {b_pts}/10, expected ≤4.")
        ok = False
    if ok:
        print("=== Gate 3 PASS — judge calibration acceptable. ===")
        sys.exit(0)
    else:
        print("=== Gate 3 FAIL — tighten JUDGE_SYSTEM in rubric.py before baseline. ===")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
