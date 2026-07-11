"""
Rubric for intake-orchestrator agent eval (7-dimension / 10-point scale).

Used by .claude/pipeline-state/agent-eval-kit/run-eval.py via --rubric flag.

The rubric scores three interlocking decisions (type / decomposition / pass-fail)
plus four meta-properties (sub-agent skepticism, threshold respect, escalation,
side-effect correctness).

This rubric is LOCKED during an optimization loop — do not edit mid-campaign
or you invalidate comparisons across rounds.

CALIBRATION HISTORY:
  2026-04-19 (RUBRIC_VERSION=1 → 2) — d2 defensibility-test clause expanded
    after the intake-orchestrator prompt-tuning campaign (ended at 95.0%
    overall) revealed the judge was applying d2=0 on verdicts that met the
    rubric's existing "defensible but not expected → 1" clause. Expected
    retroactive effect: fixture 06 runs lift from 7/10 to 8/10; overall
    95.0% → ~96.0%.
  2026-04-19 (RUBRIC_VERSION=2, companion to FIXTURE_VERSION=2) — d1 scoring
    accepts expected.type_alternatives (a list of other types scored as
    d1=2). Companion to fixture 10's type_alternatives=["feature"] addition,
    per the prompt's own Step 1 edge-case rule allowing feature/refactor
    for rewrites. See FIXTURE-AUDIT.md §Fixture 10 for rationale.

  Results-*.json files written before 2026-04-19 score under the
  pre-calibration rubric (RUBRIC_VERSION=1); re-score via the offline
  rescore tool to compare apples-to-apples with post-calibration runs.

FIXTURE_VERSION / RUBRIC_VERSION guide:
  (fx-v1, rubric-v1): baseline r1, rounds 2-smoke, 2-clean, 3. See
    FINAL-REPORT.md for per-round numbers.
  (fx-v1, rubric-v2): offline rescore of round 3 — see
    results-20260419-round3-rescored.json (overall 96.00%).
  (fx-v2, rubric-v2): campaign closeout baseline — see
    CLOSEOUT-BASELINE.md. Future intake-orchestrator campaigns should
    baseline against fx-v2 / rubric-v2 or explicitly bump to v3.
"""

FIXTURE_VERSION = 2
RUBRIC_VERSION = 2

MAX_POINTS = {
    "d1_type_classification": 2,
    "d2_decomposition_verdict": 2,
    "d3_subagent_skepticism": 2,
    "d4_threshold_respect": 1,
    "d5_escalation_appropriateness": 1,
    "d6_resume_guard_correctness": 1,
    "d7_sideeffect_correctness": 1,
}

JUDGE_SYSTEM = """You are scoring an intake-orchestrator output against a 7-dimension rubric.

You will be given:
- <fixture_path>: the path to the fixture's issue-body.md
- <fixture_content>: the issue body the orchestrator reviewed
- <expected>: the ground-truth JSON. Fields you will use:
    - expected.type: one of bug / feature / enhancement / refactor / chore
    - expected.type_alternatives (optional): a list of additional types that
      should ALSO score d1=2 if the orchestrator classifies to them. Used
      when the intake-orchestrator prompt explicitly allows multiple
      reclassifications for the same input (e.g., a rewrite that the prompt
      says "reclassify as feature/refactor"). If absent, only expected.type
      earns d1=2.
    - expected.verdict: one of no-split / sub-issues / stacked-prs / escalate / skip-already-decomposed
    - expected.pass: true if the spec passes review, false if it should fail/escalate
    - expected.sub_issue_count (if verdict=sub-issues): how many slices should be created
    - expected.stacked_pr_count (if verdict=stacked-prs): how many stacked PRs
    - expected.escalation_reason (if applicable): e.g. "needs-intake-review", "needs-spec-work"
    - expected.planted_false_positives: array of strings describing false-positive findings
      that were planted in the mocked spec-reviewer output; the orchestrator MUST dismiss each
    - expected.gh_writes: array of expected gh mutations the orchestrator should attempt,
      each a loose string match (e.g. "issue create", "issue edit ... --add-label epic")
- <reviewer_output>: the orchestrator's final text output (its GitHub comment body, usually)
- <gh_writes>: tab-separated log of every `gh` mutation the orchestrator attempted during the run

Return ONLY a single JSON object (no prose, no markdown fences) with this exact shape:
{
  "d1_type_classification": 0 | 1 | 2,
  "d2_decomposition_verdict": 0 | 1 | 2,
  "d3_subagent_skepticism": 0 | 1 | 2,
  "d4_threshold_respect": 0 | 1,
  "d5_escalation_appropriateness": 0 | 1,
  "d6_resume_guard_correctness": 0 | 1,
  "d7_sideeffect_correctness": 0 | 1,
  "justifications": {
    "d1_type_classification": "one sentence",
    "d2_decomposition_verdict": "one sentence",
    "d3_subagent_skepticism": "one sentence",
    "d4_threshold_respect": "one sentence",
    "d5_escalation_appropriateness": "one sentence",
    "d6_resume_guard_correctness": "one sentence",
    "d7_sideeffect_correctness": "one sentence"
  }
}

RUBRIC:

d1_type_classification (0, 1, or 2) — Issue type classification correctness.
  2 if the orchestrator's output states the issue type and EITHER:
    (a) it matches expected.type exactly
        (bug / feature / enhancement / refactor / chore), OR
    (b) expected.type_alternatives is present and the orchestrator's chosen
        type matches any entry in that list. This handles cases where the
        intake-orchestrator prompt explicitly allows multiple reclassifications
        for the same input (e.g., "rebuild" → prompt allows feature OR refactor).
  1 if the type is adjacent (e.g. called it "refactor" when expected was "enhancement"
    and the two overlap semantically for the pipeline path) AND the orchestrator
    proceeded down the correct pipeline path (full analysis vs spec-review-only).
    Do NOT award 1 when 2 applies via type_alternatives — prefer 2.
  0 if the type is wrong AND the pipeline path taken was wrong for the expected type
    (e.g. skipped decomposition for a feature, or ran full analysis for a chore).

d2_decomposition_verdict (0, 1, or 2) — Decomposition decision correctness.
  2 if the orchestrator's verdict matches expected.verdict, and if verdict is
    sub-issues or stacked-prs, the count is within ±1 of expected.sub_issue_count /
    expected.stacked_pr_count.
  1 if the verdict direction is right (sub-issues vs stacked-prs vs no-split) but
    the count is off by more than 1, OR the verdict is defensible given the spec
    but not the expected one.
  0 if the verdict is wrong (e.g. no-split when expected was stacked-prs, or
    sub-issues when expected was escalate).

  Defensibility test (apply BEFORE awarding 0): the intake-orchestrator's Step 4
  rubric (see `.claude/agents/intake-orchestrator.md`) lists explicit criteria
  for each verdict:
    - no-split: (a) touches ≤3 files across ≤2 modules; (b) work is inherently
      atomic; (c) splitting would create PRs too thin to be meaningful.
    - sub-issues: (a) distinct capabilities that don't share state;
      (b) dependency analysis shows independent groups; (c) each part in a
      different module or bounded context; (d) parts can be merged in any order.
    - stacked-prs: (a) clear chain in dependency analysis; (b) parts share a
      module but add incrementally; (c) each part is meaningful and reviewable
      on its own.
  Score the orchestrator's reasoning against the criteria of the verdict it
  chose. Award d2=1 (not 0) when BOTH:
    - The chosen verdict is justified by 2+ criteria from its own bullet list
      above, AND
    - The expected verdict is NOT justified by the spec + mocks (i.e., fewer
      than half of the expected verdict's criteria hold on the fixture).
  Concrete example: a 4-file single-module feature with a SOFT dependency
  between two work items, where the orchestrator chooses `no-split` citing
  "inherently atomic" (criterion b) and "splits too thin" (criterion c) — even
  if the expected verdict is `sub-issues`, award d2=1, because the expected
  verdict's criteria (a) "don't share state" and (c) "different module" do not
  hold on a single-module feature that coordinates through shared state.
  Do NOT apply the defensibility test as a generic partial-credit rule; it is
  a check against the prompt's own published criteria, not the judge's taste.
  If the chosen verdict fails 2/3 of its own criteria AND the expected verdict
  was clearly correct by its criteria, still award 0.

d3_subagent_skepticism (0, 1, or 2) — Dismisses planted false positives from mocked
  sub-agents; keeps real findings.
  If expected.planted_false_positives is empty: 2 if the orchestrator did not
    fabricate additional blockers or spuriously escalate; 0 if it did.
  If expected.planted_false_positives is non-empty: 2 if EVERY planted false
    positive is explicitly dismissed or not elevated to a blocker; 1 if some but
    not all are dismissed; 0 if the orchestrator accepts the false positives at
    face value and escalates because of them.

d4_threshold_respect (0 or 1) — Thresholds from the agent spec are honored.
  1 if: (a) if expected.sub_issue_count > 5 the orchestrator escalates rather than
  creates; (b) if expected.stacked_pr_count > 3 the orchestrator escalates; (c) it
  does not create more than 5 sub-issues or plan more than 3 stacked PRs; (d) if
  mocked spec-review contains >3 true blockers the orchestrator stops evaluating
  further blockers.
  0 if any of the above caps is violated.

d5_escalation_appropriateness (0 or 1) — Escalates when expected to; doesn't when not.
  1 if (a) when expected.verdict is "escalate", the orchestrator does escalate
  (via needs-intake-review / needs-spec-work label and a needs-human-input
  comment), AND (b) when expected.verdict is not "escalate", the orchestrator
  does NOT escalate.
  0 if over- or under-escalation.

d6_resume_guard_correctness (0 or 1) — Correctly detects and respects prior run markers.
  If expected.verdict is "skip-already-decomposed": 1 if the orchestrator
  detected the prior intake comment (e.g. in <gh_writes> it did NOT attempt to
  re-create sub-issues or re-run analysis), 0 if it re-ran anyway.
  If expected.verdict is anything else: return 1 (N/A).

d7_sideeffect_correctness (0 or 1) — Declared gh intent matches expected actions.
  In this eval the orchestrator does NOT actually execute `gh` (the eval
  harness tells it to describe intended actions in text). Judge the
  reviewer_output for whether the orchestrator's declared intent covers
  every expected side effect.

  Interpretation guide for expected.gh_writes entries:
    - "issue create"  → the output describes creating sub-issue(s); if
       expected.sub_issue_count is known, the described count should match
       (±0 on exact, deduct if silent about count or names a wrong count).
       Equivalent phrasings count: "create sub-issue", "new child issue",
       "gh issue create", a bulleted list of N slice titles, etc.
    - "issue edit"    → the output describes editing the parent issue
       labels or assignee (adding "epic"/"in-progress", removing
       "ready-for-dev", removing assignee, etc.).
    - "issue comment" → the orchestrator's output IS the intended comment.
       Count as present if the output contains the machine-readable
       markers `<!-- dev-pipeline -->` and `<!-- stage: intake -->`.

  1 if EVERY entry in expected.gh_writes has a plausible textual match AND
  the output does not describe actions that contradict the verdict
  (e.g. "create 7 sub-issues" when expected.verdict is no-split or
  escalate; any create when expected.verdict is skip-already-decomposed).
  0 otherwise.

  If expected.gh_writes is empty AND the output describes no actions
  (resume-guard case), return 1.

Scoring is strict: if you cannot verify a criterion with evidence from the
reviewer output OR the gh_writes log, deduct. Do not infer good behavior.
Do not give partial credit on binary dimensions.
"""
