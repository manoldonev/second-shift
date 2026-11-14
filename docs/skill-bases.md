# Skill bases (P6)

> Population: dogfood repo only; not evidence about consumer repos.

`docs/pipeline-manifesto.md` P6 asks that a workaround carry its measured basis. This table is the
register of which skills and agents have one. The evidence behind it was removed from the tree and
is kept at tag `v17.14.1`: `git show v17.14.1:docs/skill-ablation.md`, and
`git ls-tree -r --name-only v17.14.1 docs/plans/skill-ablation/` for the runs.

## Measured

| skill | lines when measured | basis | date |
| --- | --- | --- | --- |
| `intake-toolkit/plan-interview` + `interviewing-baseline` | 312 | **keep.** A bare session recalled 6 of 20 operator-answered ledger rows (0.30; 6 of 17 pre-flight rows, 0.35). Registered threshold: under 10 of 20 is keep. The delta: bare surfaces design decisions; the interview surfaces scope-boundary decisions. 9 of the 14 missed rows are that class, and 5 of them are `DEPARTURE` rows. | 2026-08-24 |

The basis binds the 312 lines that were measured. Every line added to these two skills since then is
unmeasured.

The other measured subjects, `build-lean` and `review-lean`, are retired. So is `pr-revision`, which
was rated unmeasured.

## Inherited, not re-measured

Each basis below was measured on an earlier model generation, with fixtures that are no longer in
the repo. Each report is at tag `v17.14.1`, at the path given in its row.

| rule | basis | date |
| --- | --- | --- |
| `intake/split.md` counterfactual test (*would I group the same way if the cap were 10?*) | It replaced an absolute "never merge to fit the cap" rule in `intake-orchestrator`: 92.4% → 95.0% (+2.6 pp, 30 runs over 10 fixtures, LLM judge), kept. It recovered the two fixtures the absolute rule regressed. The closeout baseline at that prompt, after fixture and rubric corrections, was 99.8% over 50 runs. `plugins/intake-toolkit/evals/intake-orchestrator-eval/FINAL-REPORT.md` and `CLOSEOUT-BASELINE.md`. | 2026-04-19 |
| `review-toolkit/plan-reviewer`: the calibration examples, the non-negotiable Blockers and "Empty review is a valid output" | 94.2% → 98.7% (+4.5 pp over two kept rounds, 10 adversarial fixtures, LLM judge). A third round (pre-emit checklist) was never validated. `plugins/review-toolkit/evals/plan-reviewer-eval/FINAL-REPORT.md`. | 2026-04-18 |
| `review-toolkit/security-reviewer`: the Severity Calibration, the Non-Negotiable Critical findings, "Empty Review is a Valid Output" and the Pre-Emit Gate | 86.4% → 96.5% (+10.1 pp, n=72, LLM judge), kept. A second round narrowed the multi-tenant trigger, and only part of it ran (n=54). `plugins/review-toolkit/evals/security-reviewer-eval/FINAL-REPORT.md`. | 2026-05-08 |

## Unmeasured — no basis

No skill or agent below may be credited with a pass. When the study closed, the measured surfaces
were 487 of 4,951 shipped lines: about 90% of the product had no basis re-measured against the
current model generation.

- `intake-toolkit/intake`, `split.md` (was `intake-orchestrator`): the 2026-08-24 study reached no
  decomposition metric. Only the counterfactual test has the inherited basis above.
- `intake-toolkit/intake`, `requirements.md` (was `intake-interviewer`): no sample ran its path.
- `review-toolkit/review-lead`
- `second-shift/onboard`
- `design-toolkit/figma-faithful`
- Every other shipped skill and agent, including each one added since 2026-08-24, and each rule
  added to an agent above after its row's date.

## Apparatus findings

- **`--allowedTools` does not bound a session; `--tools` does.** `--allowedTools` pre-approves the
  tools it names and removes none. `--tools "Read,Grep,Glob"` leaves only those built-ins. It does
  not remove MCP tools; `--strict-mcp-config` does that, so a bounded arm needs both flags. Measured
  on CLI 2.1.263, 2026-09-08. Every earlier arm that used `--allowedTools` ran unbounded.
- **Routing prose is apparatus-bound.** With `review-lead` and its agents discoverable, a one-shot
  review session used them in 0 of 3 runs. A unit whose function is routing to an implementation
  that the harness does not load scores `not-reached — no basis`, never `no-effect`.
