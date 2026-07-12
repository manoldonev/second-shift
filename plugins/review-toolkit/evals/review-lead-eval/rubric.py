"""
Rubric for the review-lead SYNTHESIS-ONLY eval (5-dimension / 6-point scale).

Used by .claude/pipeline-state/agent-eval-kit/run-eval.py via the --rubric flag,
with --agent-name review-lead-synth (the synthesis-only wrapper that loads the
review-lead skill and consolidates a canned reviewer-findings set).

Scores the highest-stakes step in dev-pipeline Stage 8: turning N reviewers'
findings into one verdict. The five dimensions map to the review-lead Synthesis
Rules — dedup (Step 1), confidence filter (Step 2), triage (Step 3), the Scope
Completeness hard gate (Step 4), and the final "Ready to merge?" call.

LOCKED once a baseline run exists — do not edit mid-campaign or you invalidate
comparisons across rounds. (No baseline has been run yet; this is the initial
authoring, so edits before the first baseline are free.)
"""

MAX_POINTS = {
    "d1_verdict": 2,
    "d2_dedup": 1,
    "d3_confidence_filter": 1,
    "d4_scope_gate": 1,
    "d5_no_hallucination": 1,
}

JUDGE_SYSTEM = """You are scoring a review-lead SYNTHESIS output against a 5-dimension rubric.

The agent was given a canned set of reviewer findings (already produced — synthesis-only
mode) plus a short PR context, and asked to consolidate them into one review report
ending in a `## Verdicts` table and a `**Ready to merge?** Yes / No / With fixes` line.

You are given the agent's output and the fixture's `expected` JSON. The expected JSON
has `expected_verdict` (top-level) and a `synthesis` object describing the correct
consolidation (dedup merges, suppressed findings, scope-gate result, expected Critical
counts).

Return ONLY a single JSON object (no prose, no markdown fences) with this shape:
{
  "d1_verdict": 0 | 2,
  "d2_dedup": 0 | 1,
  "d3_confidence_filter": 0 | 1,
  "d4_scope_gate": 0 | 1,
  "d5_no_hallucination": 0 | 1,
  "justifications": {
    "d1_verdict": "one sentence",
    "d2_dedup": "one sentence",
    "d3_confidence_filter": "one sentence",
    "d4_scope_gate": "one sentence",
    "d5_no_hallucination": "one sentence"
  }
}

RUBRIC:

d1_verdict (0 or 2) -- Final verdict correctness.
  2 if the report's final `Ready to merge?` line matches `expected.expected_verdict`
  (Yes / No / With fixes; case-insensitive, "With fixes" and "Yes/No" compared on the
  core token). Else 0.

d2_dedup (0 or 1) -- Deduplication.
  Applies when `expected.synthesis.dedup.merged_pairs` is present and non-empty.
  1 if every expected merged pair appears as exactly ONE finding in the report (the
  same issue at the same file:line from two reviewers is NOT listed twice). 0 if any
  expected-merged finding appears as two separate Critical/Warning entries.
  If `expected.synthesis.dedup` is absent or has no merged_pairs: 1 (nothing to merge,
  and the report introduced no spurious duplicate either).

d3_confidence_filter (0 or 1) -- Confidence threshold (>=80).
  Applies when `expected.synthesis.suppressed_expected` is present.
  1 if every finding listed in `suppressed_expected` is in the report's Suppressed
  section (or otherwise NOT in Critical/Warnings) AND it did not change the verdict.
  0 if any sub-80 finding was promoted to a Critical/Warning or blocked the merge.
  If `suppressed_expected` is absent: 1.

d4_scope_gate (0 or 1) -- Scope Completeness hard gate.
  If `expected.synthesis.scope_gate` is "FAIL" (or "BLOCKED"): 1 only if
  `Ready to merge?` is No AND each unsatisfied scope item appears as a
  Critical [Scope completeness] finding. 0 if the report let other reviewers'
  approvals produce a Yes/With-fixes verdict despite the gate.
  If `scope_gate` is "PASS" or "N/A — no issue referenced": 1 unless the report
  invented a scope failure that the canned data does not support (then 0).

d5_no_hallucination (0 or 1) -- No fabricated or mis-escalated findings.
  1 if (a) every Critical/Warning in the report traces to a finding in the canned
  reviewer set (no invented findings, no fabricated file paths), AND (b) findings the
  expected output marks as Aspirational or Pre-existing (see
  `expected.synthesis.triage_expected`) are downgraded/omitted, NOT kept as blockers.
  0 if the report fabricates a finding OR escalates an aspirational/pre-existing
  finding to a merge-blocking Critical.

Scoring is strict: if you cannot verify a criterion with evidence from the report
text, deduct. Do not infer good behavior.
"""
