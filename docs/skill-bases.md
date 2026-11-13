# Skill bases (P6)

> Population: dogfood repo only; not evidence about consumer repos.

`docs/pipeline-manifesto.md` P6 asks that a skill carry a measured basis. This table is the register
of which skills have one. The study behind it is in git history:
`git log --all -- docs/skill-ablation.md docs/plans/skill-ablation/`.

## Measured

| skill | lines when measured | basis | date |
| --- | --- | --- | --- |
| `intake-toolkit/plan-interview` + `interviewing-baseline` | 312 | **keep.** A bare session recalled 6 of 20 operator-answered ledger rows (0.30; 6 of 17 pre-flight rows, 0.35). Registered threshold: under 10 of 20 is keep. The delta: bare surfaces design decisions; the interview surfaces scope-boundary decisions. 9 of the 14 missed rows are that class, and 5 of them are `DEPARTURE` rows. | 2026-08-24 |

The other measured subjects, `build-lean` and `review-lean`, are retired. So is `pr-revision`, which
was rated unmeasured.

## Inherited, not re-measured

| rule | basis | date |
| --- | --- | --- |
| `intake/split.md` counterfactual test (*would I group the same way if the cap were 10?*) | It replaced an absolute "never merge to fit the cap" rule in `intake-orchestrator`: 92.4% → 95.0% (+2.6 pp, 30 runs over 10 fixtures, LLM judge), kept. It recovered the two fixtures the absolute rule regressed. The closeout baseline at that prompt, after fixture and rubric corrections, was 99.8% over 50 runs. The fixtures are gone; the reports are in `git log --all -- plugins/intake-toolkit/evals/intake-orchestrator-eval/`. | 2026-04-19 |

## Unmeasured — no basis

No skill below may be credited with a pass.

- `intake-toolkit/intake`, `split.md` (was `intake-orchestrator`): the 2026-08-24 study reached no
  decomposition metric. Only the counterfactual test has the inherited basis above.
- `intake-toolkit/intake`, `requirements.md` (was `intake-interviewer`): no sample ran its path.
- `review-toolkit/review-lead`
- `second-shift/onboard`
- `design-toolkit/figma-faithful`
- Every other shipped skill, including each skill added since 2026-08-24.

## Apparatus findings

- **`--allowedTools` does not bound a session; `--tools` does.** `--allowedTools` pre-approves the
  tools it names and removes none. `--tools "Read,Grep,Glob"` leaves only those built-ins. It does
  not remove MCP tools; `--strict-mcp-config` does that, so a bounded arm needs both flags. Measured
  on CLI 2.1.263, 2026-09-08. Every earlier arm that used `--allowedTools` ran unbounded.
- **Routing prose is apparatus-bound.** With `review-lead` and its agents discoverable, a one-shot
  review session used them in 0 of 3 runs. A unit whose function is routing to an implementation
  that the harness does not load scores `not-reached — no basis`, never `no-effect`.
