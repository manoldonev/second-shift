"""
Rubric for plan-reviewer agent eval (8-dimension / 10-point scale).

Used by .claude/pipeline-state/agent-eval-kit/run-eval.py via --rubric flag.

This rubric is LOCKED during an optimization loop — do not edit mid-campaign
or you invalidate comparisons across rounds.
"""

MAX_POINTS = {
    "d1_verdict": 2,
    "d2_defect_recall": 2,
    "d3_no_hallucination": 1,
    "d4_classification": 1,
    "d5_evidence_substantive": 1,
    "d6_impact_fix_substantive": 1,
    "d7_scope_discipline": 1,
    "d8_no_duplicates": 1,
}

JUDGE_SYSTEM = """You are scoring a plan-review output against an 8-dimension rubric.

Return ONLY a single JSON object (no prose, no markdown fences) with this shape:
{
  "d1_verdict": 0 | 2,
  "d2_defect_recall": 0 | 1 | 2,
  "d3_no_hallucination": 0 | 1,
  "d4_classification": 0 | 1,
  "d5_evidence_substantive": 0 | 1,
  "d6_impact_fix_substantive": 0 | 1,
  "d7_scope_discipline": 0 | 1,
  "d8_no_duplicates": 0 | 1,
  "justifications": {
    "d1_verdict": "one sentence",
    "d2_defect_recall": "one sentence",
    "d3_no_hallucination": "one sentence",
    "d4_classification": "one sentence",
    "d5_evidence_substantive": "one sentence",
    "d6_impact_fix_substantive": "one sentence",
    "d7_scope_discipline": "one sentence",
    "d8_no_duplicates": "one sentence"
  }
}

RUBRIC:

d1_verdict (0 or 2) -- Verdict correctness.
  2 if the review's final `### Verdict: ...` line matches the fixture's
  expected_verdict (APPROVE or REVISE). Else 0.

d2_defect_recall (0, 1, or 2) -- Planted defect recall.
  If planted_defects is EMPTY: 2 if the review has zero Blockers AND zero
  Warnings, 1 if it has Warnings but no Blockers, 0 if it has any Blocker.
  If planted_defects is NON-EMPTY: 2 if EVERY planted defect is flagged
  as a Blocker or Warning with a specific file/component name that
  matches the planted defect description; 1 if some but not all are
  flagged, or all are flagged but only as Notes; 0 if none.

d3_no_hallucination (0 or 1) -- No hallucinated findings.
  1 if every Blocker's Evidence cites either a file path that exists in
  the repo OR explicitly states "file does not exist". 0 if any Blocker
  references a fabricated file path as if it exists (e.g. "foo.ts:42"
  for a file that isn't in the plan and isn't in the repo).

d4_classification (0 or 1) -- Plan type classification.
  1 if the review's `Plan type` header matches the fixture's expected
  plan_type AND the review does not contain findings from irrelevant
  domain checklists (e.g., no Swagger findings on a pure web plan, no
  class-validator findings on a pure ML plan, no NestJS module findings
  on a pure infra/Docker plan).

d5_evidence_substantive (0 or 1) -- Evidence field substantive.
  1 if EVERY Blocker and Warning has an Evidence field that contains a
  file path AND one of: a grep/glob command, a line number, a code
  snippet, or the phrase "file does not exist". 0 if any Blocker or
  Warning has a bare "Evidence: plan step N says..." without repo
  grounding.
  If the review has zero Blockers and zero Warnings, return 1.

d6_impact_fix_substantive (0 or 1) -- Impact + Plan-fix substantive.
  1 if EVERY Blocker and Warning has (a) an Impact line explaining a
  concrete consequence (not vague "this could cause issues") AND (b) a
  Plan fix that names a specific step number or section to update. 0
  otherwise.
  If the review has zero Blockers and zero Warnings, return 1.

d7_scope_discipline (0 or 1) -- Scope discipline.
  1 if the review contains no findings that (a) propose alternative
  architectures, (b) question product decisions, or (c) debate
  algorithm choices -- UNLESS the finding is tied to a concrete
  integration constraint, data contract, or performance target.
  Common in-scope findings (do NOT deduct for these): missing companion
  files, contract mismatches, decorator patterns, step ordering,
  downstream consumers, performance on known hot paths, convention
  gaps.

d8_no_duplicates (0 or 1) -- No duplicate findings.
  1 if the review does not contain two findings (across Blockers,
  Warnings, Notes) that describe the same underlying issue in different
  words. 0 if there is clear duplication.

Scoring is strict: if you cannot verify a criterion with evidence from
the review text, deduct. Do not infer good behavior.
"""
