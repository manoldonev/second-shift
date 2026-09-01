"""
Rubric for the design-faithful-plan-reviewer agent eval (3-dimension / 10-point scale).

Used by ../../../review-toolkit/evals/agent-eval-kit/run-eval.py via the --rubric flag.

This rubric is LOCKED during a campaign — editing it mid-campaign invalidates comparisons
across rounds. See ../../../dev-pipeline/eval-criteria.md for the keep-or-revert rule.

Design notes
------------
Held to the sibling `figma-faithful-plan-reviewer-eval` rubric's 6/2/2 split deliberately: the two
instruments grade the same artifact class one family apart, and a different weighting would make
their numbers incomparable for no gain. The verdict dimension carries the bulk of the points, so a
per-fixture pass rate reads straight off `per_fixture` in the results JSON while `overall_pct`
still feeds the +10pp/3-run rule.

- d1_verdict_correctness is worth 6 (the top-line call, and the only one graded in binary).
- d2_finding_grounding is worth 2 (did it name the PLANTED defect, anchored to a real row?).
- d3_no_fabrication is worth 2 (the asymmetric-cost guardrail — a finding against a table row
  that does not exist is worse than a missed one, because it trains an author to ignore the
  reviewer).

Total: 10. Aligns with the three figma reviewer campaigns and the older kit evals.
"""

RUBRIC_VERSION = 1
FIXTURE_VERSION = 1

MAX_POINTS = {
    "d1_verdict_correctness": 6,
    "d2_finding_grounding": 2,
    "d3_no_fabrication": 2,
}

JUDGE_SYSTEM = """You are scoring a design-faithful TRANSLATION-PLAN review against a 3-dimension rubric.

Return ONLY a single JSON object (no prose, no markdown fences) with this shape:
{
  "d1_verdict_correctness": 0 | 2 | 4 | 6,
  "d2_finding_grounding": 0 | 1 | 2,
  "d3_no_fabrication": 0 | 1 | 2,
  "justifications": {
    "d1_verdict_correctness": "one sentence",
    "d2_finding_grounding": "one sentence",
    "d3_no_fabrication": "one sentence"
  }
}

INPUT YOU RECEIVE
-----------------
- <fixture_path>: relative path of the fixture (informational only).
- <fixture_content>: the translation plan the reviewer was asked to review. A design-faithful
  plan carries NO token table and no Figma values — that absence is correct, and a finding that
  demands one is a fabrication.
- <expected>: ground truth. Keys: `expected_verdict` ("block" | "pass"), `expected_findings`
  (array of strings describing the PLANTED defects; [] on a clean fixture), `must_not_flag`
  (array of strings naming things that are CORRECT in this plan and must not be raised as
  Blockers), optional `acceptable_alternative_severity` (prose relaxing the severity required
  for a specific finding), `layer`, `notes` (rationale; informational).
- <reviewer_output>: the full text the plan reviewer emitted.

VOCABULARY
----------
- The agent's own trinary is `block` | `fix-and-go` | `pass`, plus `N/A` when it declines the
  input. Read the verdict from its `### Verdict:` line, or from the `verdict` key of the fenced
  JSON block after the REVIEW_RESULT sentinel, whichever is present. If both are present and
  disagree, use the JSON block.
- Map to the expected vocabulary: `block` -> "block". `fix-and-go` and `pass` -> "pass".
  `N/A` maps to NEITHER and always scores d1 = 0.
- "Blocker" = a finding the reviewer itself marked `[Blocker]`, or emitted with
  `severity: blocker` in the JSON block. "Warning" = `[Warning]` / `major` / `minor`.
  "Note" = `[Note]` / `nit`.

RUBRIC
------

d1_verdict_correctness (0, 2, 4 or 6) -- the top-line call.
  6 if the mapped verdict equals `expected.expected_verdict` AND the reason is right:
    * on a "block" fixture: at least one Blocker that names a defect in `expected_findings`
      (paraphrase is fine; the plan row, node name or column it concerns must be identifiable),
      unless `acceptable_alternative_severity` says a Warning suffices for that finding;
    * on a "pass" fixture: zero Blockers AND zero Warnings.
  4 if the verdict matches but the reason is partly wrong -- e.g. `block` reached via a Blocker
    on something NOT in `expected_findings` while a planted defect was missed; or `pass` reached
    with one Warning raised against an item listed in `must_not_flag`.
  2 if the verdict matches for clearly wrong reasons -- e.g. `pass` because the reviewer produced
    no findings at all on a plan carrying a planted Blocker-class defect, or `block` reached
    entirely through fabricated findings.
  0 if the verdict is wrong (`pass` on a "block" fixture, `block` on a "pass" fixture), or if the
    reviewer returned `N/A` / declined to review.

d2_finding_grounding (0, 1 or 2) -- the planted defect, named and anchored.
  - If `expected_findings` is EMPTY (clean fixture): 2 if the reviewer raised no Blocker and no
    Warning; 1 if it raised Warnings but no Blockers; 0 if it raised any Blocker.
  - If `expected_findings` is NON-EMPTY: 2 if EVERY listed defect is identified at Blocker or
    Warning severity AND each is anchored to something concrete in the plan (a table row, a
    column name, a node name, a recorded value). 1 if at least one but not all are identified,
    or if all are identified but only as Notes, or if identified without any anchor. 0 if none
    are identified.

d3_no_fabrication (0, 1 or 2) -- no findings against content the plan does not contain.
  2 if EVERY Blocker and Warning cites a row, column, node, value or file that actually appears
    in the fixture, AND none contradicts `must_not_flag`. Restating correct content as context is
    fine; the test is whether the ASSERTED DEFECT is real.
  1 if exactly one finding is fabricated or contradicts `must_not_flag` (e.g. demanding a token
    map table a design-faithful plan does not mandate, or asserting a dimensions table is empty
    when it is populated).
  0 if two or more are, or if any single one is extreme (quoting a plan row that does not exist).

Scoring is strict: if you cannot verify a criterion from the review text, deduct. Do not infer
good behavior. Extra findings that are REAL (they cite actual plan content and describe a genuine
gap) are good behavior and cost nothing on d3 -- only fabrications and `must_not_flag` violations
do. But on a fixture whose `expected_verdict` is "pass", any Blocker or Warning at all is a
false positive by construction and d1/d2 must reflect that.

Return ONLY the JSON object. No prose, no markdown fences.
"""
