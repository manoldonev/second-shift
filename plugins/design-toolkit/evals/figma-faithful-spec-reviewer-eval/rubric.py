"""
Rubric for the figma-faithful-spec-reviewer agent eval (3-dimension / 10-point scale).

Used by ../../../review-toolkit/evals/agent-eval-kit/run-eval.py via the --rubric flag.

This rubric is LOCKED during a campaign — editing it mid-campaign invalidates comparisons
across rounds. See ../../../dev-pipeline/eval-criteria.md for the keep-or-revert rule.

Design notes
------------
Same 6/2/2 split as the sibling plan-reviewer and reviewer rubrics, for the reason recorded in
#704's plan (D-4): the ticket grades in binary while the kit scores a weighted rubric, so the
verdict dimension carries the bulk and "fixtures 1-3 pass >= 3/3 runs" reads straight off
`per_fixture`.

One dimension is worded differently here, and deliberately. This agent has a fourth reachable
output -- `N/A`, its explicit-input refusal -- and #704's AC-4 exists because that refusal fires
on a lean-lane spec, which is the one input shape the check "a token table is not a visual
contract" was written for. So `N/A` is scored as a WRONG VERDICT on every fixture in this set,
not as an abstention: all four fixtures are design artifacts, and declining one is the failure
being measured. The pre-AC-4 baseline is expected to score 0 on fixture 01 for exactly that
reason, and that zero is a finding, not a harness fault.

Total: 10.
"""

RUBRIC_VERSION = 1
FIXTURE_VERSION = 2  # 04-control-clean corrected; see its .expected.json notes

MAX_POINTS = {
    "d1_verdict_correctness": 6,
    "d2_finding_grounding": 2,
    "d3_no_fabrication": 2,
}

JUDGE_SYSTEM = """You are scoring a figma-faithful SPEC review against a 3-dimension rubric.

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
- <fixture_content>: the spec the reviewer was asked to review.
- <expected>: ground truth. Keys: `expected_verdict` ("block" | "pass"), `expected_findings`
  (array of strings describing the PLANTED defects; [] on a clean fixture), `must_not_flag`
  (array of strings naming things that are CORRECT or NOT-APPLICABLE in this spec and must not
  be raised as Blockers), optional `must_not_return` (a verdict string the reviewer must not
  emit), optional `acceptable_alternative_severity` (prose relaxing the severity required for a
  specific finding), `layer`, `notes` (rationale; informational).
- <reviewer_output>: the full text the spec reviewer emitted.

VOCABULARY
----------
- The agent's own trinary is `block` | `fix-and-go` | `pass`, plus `N/A` when it declines the
  input as "not a figma-faithful spec". Read the verdict from its `### Verdict:` line, or from
  the `verdict` key of the fenced JSON block after the REVIEW_RESULT sentinel, whichever is
  present. If both are present and disagree, use the JSON block.
- Map to the expected vocabulary: `block` -> "block". `fix-and-go` and `pass` -> "pass".
- **`N/A` is a WRONG verdict on every fixture in this set.** All four fixtures are design
  artifacts. If the reviewer returned `N/A`, or declined to run the checklist because the input
  "is not a figma-faithful spec" / "has no Copy Index" / "is a lean-lane spec", score
  d1 = 0 and d2 = 0 regardless of anything else it said. Score d3 on whatever findings it did
  emit (usually none, which scores 2).
- "Blocker" = a finding the reviewer itself marked `[Blocker]`, or emitted with
  `severity: blocker` in the JSON block. "Warning" = `[Warning]` / `major` / `minor`.
  "Note" = `[Note]` / `nit`.

RUBRIC
------

d1_verdict_correctness (0, 2, 4 or 6) -- the top-line call.
  6 if the mapped verdict equals `expected.expected_verdict` AND the reason is right:
    * on a "block" fixture: at least one Blocker that names a defect in `expected_findings`
      (paraphrase is fine; the section, row or node it concerns must be identifiable), unless
      `acceptable_alternative_severity` says a Warning suffices for that finding;
    * on a "pass" fixture: zero Blockers AND zero Warnings.
  4 if the verdict matches but the reason is partly wrong -- e.g. `block` reached via a Blocker
    on something NOT in `expected_findings` while a planted defect was missed; or `pass` reached
    with one Warning raised against an item listed in `must_not_flag`.
  2 if the verdict matches for clearly wrong reasons -- e.g. `pass` because the reviewer produced
    no findings at all on a spec carrying a planted Blocker-class defect, or `block` reached
    entirely through fabricated findings.
  0 if the verdict is wrong (`pass` on a "block" fixture, `block` on a "pass" fixture), or if the
    reviewer returned `N/A` / declined to review.

d2_finding_grounding (0, 1 or 2) -- the planted defect, named and anchored.
  - If the reviewer returned `N/A` or declined: 0.
  - If `expected_findings` is EMPTY (clean fixture): 2 if the reviewer raised no Blocker and no
    Warning; 1 if it raised Warnings but no Blockers; 0 if it raised any Blocker.
  - If `expected_findings` is NON-EMPTY: 2 if EVERY listed defect is identified at Blocker or
    Warning severity AND each is anchored to something concrete in the spec (a Copy Index id, a
    section name, an inventory row, a node name, a quoted string). 1 if at least one but not all
    are identified, or if all are identified but only as Notes, or if identified without any
    anchor. 0 if none are identified.

d3_no_fabrication (0, 1 or 2) -- no findings against content the spec does not contain.
  2 if EVERY Blocker and Warning cites a section, row, node or string that actually appears in
    the fixture, AND none contradicts `must_not_flag`. Restating correct content as context is
    fine; the test is whether the ASSERTED DEFECT is real.
  1 if exactly one finding is fabricated or contradicts `must_not_flag`.
  0 if two or more are, or if any single one is extreme (quoting a Copy Index row that does not
    exist).

  Note the asymmetry on `must_not_flag` entries that name an ABSENT section (for example "the
  absence of a Copy Index -- this is a lean-lane spec"): raising that absence as a Blocker IS a
  `must_not_flag` violation. Naming it as a check that had no input on this artifact shape is
  NOT -- that is the behavior the entry asks for.

Scoring is strict: if you cannot verify a criterion from the review text, deduct. Do not infer
good behavior. Extra findings that are REAL cost nothing on d3. But on a fixture whose
`expected_verdict` is "pass", any Blocker or Warning at all is a false positive by construction
and d1/d2 must reflect that.

Return ONLY the JSON object. No prose, no markdown fences.
"""
