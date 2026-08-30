"""
Rubric for the figma-faithful-reviewer agent eval (3-dimension / 10-point scale).

Used by ../../../review-toolkit/evals/agent-eval-kit/run-eval.py via the --rubric flag.

This rubric is LOCKED during a campaign — editing it mid-campaign invalidates comparisons
across rounds. See ../../../dev-pipeline/eval-criteria.md for the keep-or-revert rule.

Design notes
------------
Same 6/2/2 split as the two sibling artifact-reviewer rubrics (#704 plan, D-4). The verdict
vocabulary differs: this agent is a diff reviewer under `review-toolkit:reviewer-baseline`, so it
emits a Critical/Warning/Note ladder rather than the artifact reviewers' trinary, and the verdict
is INFERRED from the severities the way the security-reviewer eval infers it.

The agent's stated calibration is "bias toward passing", and half the point of the control
fixture is that this calibration must survive. So d3 punishes a false positive on the clean
fixture harder than a missed catch: a reviewer that flags every layout container will score well
on recall and badly here, which is the right shape.

Total: 10.
"""

RUBRIC_VERSION = 1
FIXTURE_VERSION = 1

MAX_POINTS = {
    "d1_verdict_correctness": 6,
    "d2_finding_grounding": 2,
    "d3_no_fabrication": 2,
}

JUDGE_SYSTEM = """You are scoring a design-token FIDELITY review of a code diff against a 3-dimension rubric.

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
- <fixture_content>: the diff the reviewer was asked to review. The file contents ARE the diff.
- <expected>: ground truth. Keys: `expected_verdict` ("revise" | "approve"), `surface` (which of
  the two design-system surfaces the changed files belong to), `expected_findings` (array of
  strings describing the PLANTED defects; [] on a clean fixture), `must_not_flag` (array of
  strings naming code in this diff that is CORRECT and must not be raised), `layer`, `notes`
  (rationale; informational).
- <reviewer_output>: the full text the reviewer emitted.

VOCABULARY
----------
- This agent has no literal "Verdict:" line requirement. INFER it: map to "revise" if the
  reviewer raised at least one new (not `[Pre-existing]`, not `Suppressed`) Critical or Warning
  finding; map to "approve" otherwise. If a fenced JSON block follows a REVIEW_RESULT sentinel
  and carries a `verdict` key, prefer that, mapping any non-approving value to "revise".
- "Finding" = any bullet or section naming a problem. `Suppressed` entries are NOT findings for
  false-positive purposes -- the reviewer-baseline allows an explicit low-confidence parking lot.
- The reviewer's severity for these rules is Warning by design; do not penalise a Warning where
  you expected a Critical, or the reverse.

THE TWO SURFACES (this is what most fixtures turn on)
-----------------------------------------------------
The diff's file paths say which rule set applies, and `expected.surface` states it outright:
- `apps/console/**` is a FIXED-THEME surface: a 4px spacing base, a fixed palette with a hex->path
  lookup, a type ramp, and a named-constant-with-comment escape hatch for an off-scale value.
- `apps/storefront/**` is a BRANDED / HOST-RELATIVE surface: NO value table exists, a literal hex
  or `rgb()` is forbidden outright, sizing must go through the theme's `pxToRem` helper (a raw
  `px` AND a hardcoded `rem` are both defects), the font family is branded, and the surface
  renders RTL so physical style props are a correctness defect rather than a style preference.

RUBRIC
------

d1_verdict_correctness (0, 2, 4 or 6) -- the top-line call.
  6 if the inferred verdict equals `expected.expected_verdict` AND the reason is right:
    * on "revise": at least one new Critical or Warning that names a defect in
      `expected_findings` (paraphrase fine; the literal, prop, or element it concerns must be
      identifiable);
    * on "approve": zero new Criticals AND zero new Warnings.
  4 if the verdict matches but the reason is partly wrong -- e.g. "revise" reached via a finding
    NOT in `expected_findings` while the planted defects were missed; or "approve" reached but
    with a Note raised against an item in `must_not_flag`.
  2 if the verdict matches for clearly wrong reasons -- e.g. "approve" because the reviewer
    produced no findings at all on a diff full of hardcoded hexes, or "revise" reached entirely
    through fabricated findings.
  0 if the verdict is wrong ("approve" on a "revise" fixture, "revise" on an "approve" fixture),
    or if the reviewer declined to review.

d2_finding_grounding (0, 1 or 2) -- the planted defect, named and anchored.
  - If `expected_findings` is EMPTY (clean fixture): 2 if the reviewer made no Critical and no
    Warning; 1 if it made Warnings but no Criticals; 0 if it made any Critical.
  - If `expected_findings` is NON-EMPTY: 2 if EVERY listed defect is identified as a Critical or
    Warning naming the right literal / prop / element, AND anchored (a file path plus a line,
    snippet or symbol). 1 if at least one but not all are identified, or if all are identified
    but only as Notes / Suppressed / Pre-existing, or if identified with no anchor. 0 if none.
  - On fixture 02 specifically, the agent's own rule is that it must VERIFY a catalog component
    exists in the repo before flagging a hand-rolled substitute. A finding that names the real
    export or its source path scores full credit; a finding that flags without any verification
    still counts as identified, but a reviewer that SUPPRESSED the finding for want of
    verification has not identified it.

d3_no_fabrication (0, 1 or 2) -- no findings against code the diff does not contain, and no
  false positives on correct code.
  2 if EVERY Critical and Warning cites a file, symbol or literal that actually appears in the
    diff, AND none contradicts `must_not_flag`.
  1 if exactly one finding is fabricated or contradicts `must_not_flag` (e.g. flagging a theme
    unit number as a raw px, flagging a `<Stack>` layout container, or flagging the `pxToRem`
    call that IS the required abstraction).
  0 if two or more are, or if any single one is extreme (quoting a line that is not in the diff).

Scoring is strict: if you cannot verify a criterion from the review text, deduct. Do not infer
good behavior. Extra findings that are REAL cost nothing on d3. But on a fixture whose
`expected_verdict` is "approve", any Critical or Warning at all is a false positive by
construction and d1/d2 must reflect that -- that fixture exists to measure whether the agent's
"bias toward passing" calibration holds.

Return ONLY the JSON object. No prose, no markdown fences.
"""
