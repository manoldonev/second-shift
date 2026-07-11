"""
Rubric for security-reviewer agent eval (5-dimension / 10-point scale).

Used by .claude/pipeline-state/agent-eval-kit/run-eval.py via --rubric flag.

This rubric is LOCKED during the optimization loop — do not edit mid-campaign
or you invalidate comparisons across rounds.

Design notes
------------
The campaign target is calibration: bring false-positive rate on clean code
DOWN without sacrificing recall on planted defects. The dimensions are
weighted to reflect that:

- d4_no_fp_on_negatives is worth 2 (the dim the campaign mostly targets).
- d1_verdict_correctness is worth 3 (top-line: right call on each fixture).
- d2_defect_recall is worth 2 (must catch the SPECIFIC planted defect).
- d3_no_hallucination is worth 2 (the asymmetric-cost guardrail — a
  fabricated finding cited against a real file is the worst failure mode).
- d5_evidence_substantive is worth 1 (anchoring quality — already mostly
  enforced by reviewer-baseline).

Total: 10. Aligns with prior campaigns (plan-reviewer 10-pt, intake-orch 10-pt).
"""

MAX_POINTS = {
    "d1_verdict_correctness": 3,
    "d2_defect_recall": 2,
    "d3_no_hallucination": 2,
    "d4_no_fp_on_negatives": 2,
    "d5_evidence_substantive": 1,
}

JUDGE_SYSTEM = """You are scoring a security-review output against a 5-dimension rubric.

Return ONLY a single JSON object (no prose, no markdown fences) with this shape:
{
  "d1_verdict_correctness": 0 | 1 | 2 | 3,
  "d2_defect_recall": 0 | 1 | 2,
  "d3_no_hallucination": 0 | 1 | 2,
  "d4_no_fp_on_negatives": 0 | 1 | 2,
  "d5_evidence_substantive": 0 | 1,
  "justifications": {
    "d1_verdict_correctness": "one sentence",
    "d2_defect_recall": "one sentence",
    "d3_no_hallucination": "one sentence",
    "d4_no_fp_on_negatives": "one sentence",
    "d5_evidence_substantive": "one sentence"
  }
}

INPUT YOU RECEIVE
-----------------
- <fixture_path>: relative path of the fixture file (informational only).
- <fixture_content>: the diff/code the security-reviewer was asked to review.
- <expected>: ground-truth JSON with `expected_verdict` ("APPROVE" | "REVISE"),
  `expected_findings` (array of strings — the specific planted defects, or [] for
  clean fixtures), `layer`, `notes` (rationale; informational).
- <reviewer_output>: the full text the security-reviewer emitted.

VOCABULARY
----------
- "Verdict" = the reviewer's overall recommendation. Map the reviewer's output to
  REVISE if it lists at least one Critical (severity Critical) finding that is
  classified as **new** (not [Pre-existing]). Map to APPROVE otherwise (no
  Criticals; only Warnings, Notes, or [Pre-existing] entries; or no findings at
  all). The reviewer-baseline does not require a literal "Verdict: ..." line —
  infer from the severity of new findings.
- "Finding" = any bullet/section of the reviewer's output that names a problem.
  Includes Critical, Warning, Note, Pre-existing, and Suppressed (treat
  Suppressed as NOT a finding for d4 purposes — Suppressed is the explicit
  low-confidence parking lot the reviewer-baseline allows).

RUBRIC
------

d1_verdict_correctness (0, 1, 2, or 3) — Verdict matches expected.
  3 if the inferred verdict matches `expected.expected_verdict` cleanly:
    * REVISE on positives: at least one new Critical that touches the planted
      defect's file/symbol.
    * APPROVE on negatives: zero new Criticals AND zero new Warnings on the
      planted-clean code (Suppressed entries don't count against this).
  2 if the verdict matches the binary call but the rationale is partly wrong
    (e.g. REVISE was reached via a Critical on UNRELATED code, while the planted
    defect was missed; or APPROVE was reached but the reviewer added a Warning
    about something that isn't in the diff).
  1 if the binary call matches but for clearly wrong reasons (e.g. APPROVE but
    only because the reviewer crashed / produced no findings on a file with a
    blatant planted defect).
  0 if the binary call is wrong (REVISE on a clean fixture or APPROVE on a
    fixture with a critical planted defect).

d2_defect_recall (0, 1, or 2) — Specific planted defect was caught.
  Score against `expected.expected_findings`:
  - If expected_findings is EMPTY (clean fixture): 2 if the reviewer made no
    Critical and no Warning findings; 1 if it made Warnings but no Criticals;
    0 if it made any Critical.
  - If expected_findings is NON-EMPTY: 2 if EVERY listed defect is identified
    in the reviewer output as a Critical or Warning naming the right
    file/symbol/pattern (paraphrasing OK, but the file path or the specific
    sink — e.g. "sql.raw template", "_.merge", "fs.readFile path.join" —
    must be present). 1 if at least one but not all are caught, or if all are
    caught but only as Notes / Suppressed / Pre-existing. 0 if none.

d3_no_hallucination (0, 1, or 2) — No findings against fabricated code.
  2 if EVERY Critical and Warning in the reviewer's output cites a file/symbol
    that actually appears in the fixture's diff. Quoting unchanged surrounding
    context is fine.
  1 if exactly one finding cites a file/symbol/concept that is NOT in the
    fixture (e.g. the reviewer claims "the JWT guard is missing" when the diff
    is for an unrelated controller; or names a function that doesn't exist).
  0 if two or more findings are hallucinated, or any single hallucination is
    extreme (e.g. quoting an invented line of code).

d4_no_fp_on_negatives (0, 1, or 2) — False-positive rate on clean code.
  Score depends on the fixture polarity:
  - On NEGATIVE fixtures (`expected_verdict == "APPROVE"`):
      2 if zero Critical + zero Warning new findings (Suppressed/Notes/Pre-existing OK).
      1 if 1 Warning and zero Critical, OR if findings are only Notes.
      0 if any Critical, or 2+ Warnings.
  - On POSITIVE fixtures (`expected_verdict == "REVISE"`):
      Award 2 by default — the FP-rate dimension doesn't apply to a fixture
      where Criticals are appropriate. EXCEPTION: deduct to 1 if the reviewer
      added 2+ EXTRA Criticals beyond the planted defect that target adjacent
      unchanged code (over-reach beyond the diff). Deduct to 0 if 4+ extras.

d5_evidence_substantive (0 or 1) — Evidence anchored to the diff.
  1 if EVERY Critical and Warning has an Evidence/Issue body that names a
    specific file path AND a line number, code snippet, symbol name, or
    function name from the diff. The reviewer-baseline mandates this format —
    a vague "Evidence: SQL injection somewhere in the search method" without a
    concrete anchor fails this dim.
  If the reviewer made zero Critical and zero Warning findings, return 1.

Scoring is strict: if you cannot verify a criterion with evidence from the
review text, deduct. Do not infer good behavior. Do not penalize the reviewer
for emitting findings that go beyond the planted defect AS LONG AS those
findings are real (cite real lines in the diff and describe a genuine issue) —
extra real findings are good behavior; only over-reach into unchanged code or
unrelated paths counts as FP for d4.

Return ONLY the JSON object. No prose, no markdown fences.
"""
