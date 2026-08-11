# lean review verdict — #493

verdict=approve
run_id: review-493-1
session_id: 3b258988-8b7d-42d4-b022-ecf35bb25b70
rounds: 1
pr: #499
reviewed_head: 7dcefa1937a6fa97fceace38cc7570599b315fd3
reviewed_patch_id: 1a0596e51b3a9381f9b41fd9289bfb3be1d8e240
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review — PR #499 (issue #493), round 1

Range read: `4bc19cc..HEAD` (FULL — chain root, nothing to inherit). Panel: 6 reviewers
dispatched via `code-review.mjs`, 6 returned, none dark. Every factual claim in the three
prose edits was re-verified against the tree by the orchestrator, not taken from the panel.

**Verdict: approve.** All three ACs satisfied. Two warnings, both in artifacts rather than in
the shipped text; neither is a blocker.

### Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `CLAUDE.md:63-65` now names "this repo's own dogfood lean-gate milestone-3 `test` lane (the gitignored `.claude/second-shift.config.json`, at a wider `--jobs 10` but the same runner — not a hand-rolled `find \| xargs` pipeline)". Verified against the real config: `commands["second-shift"].test` = `SKIP_STRESS=1 bash tools/run-selftests.sh --jobs 10 --exclude tools/install-topology-selftest.sh`. Every clause of the new sentence holds literally — same runner, `--jobs 10`, wider than the runner's `SELFTEST_JOBS` default of 4 (`tools/run-selftests.sh:83`), and not a `find \| xargs`. `--jobs` is a real flag (`tools/run-selftests.sh:138`). |
| AC-2 | satisfied | The `ci.yml` comment no longer claims a job "below". It now reads "There is no job for it in this workflow: it runs on a nightly cron in `.github/workflows/nightly-guards.yml`, and the note above the release-time derivation gates below says why." Verified: `ci.yml` defines exactly `lint-and-selftests`, `mutation-sweep-pr`, `pr-gates`, `release-pr-gates`, `selftests-bash32` — no install-topology job; `nightly-guards.yml` defines `install-topology` / `install-topology-bash32` on the cron; and the referenced note does sit at `ci.yml:211-216`, directly above the release-time derivation block, and does say why (cost = the shipped suite set run twice). The change is comment-only — 0 non-comment changed lines in `ci.yml`, and actionlint passed. |
| AC-3 | satisfied | `docs/testing.md:43-53` now says four in-repo callers and names them by job. All four verified: `lint-and-selftests` (`ci.yml:121`), `selftests-bash32` (`ci.yml:396`), `wholesale-selftests` (`nightly-guards.yml:100`), `wholesale-selftests-bash32` (`nightly-guards.yml:116`) — each inside the job it is attributed to. The suite's own nightly jobs `install-topology` / `install-topology-bash32` exist as named. The retired "runs in its own job on both lanes" clause is gone. |

Naming the callers by job rather than by line is the right call and is itself validated by the
branch: the `ci.yml` comment edit moved both citations (119 → 121, 394 → 396), so line-number
prose would have shipped stale on arrival.

### Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `docs/plans/second-shift-493-lean.md:33-35` | AC-3's own text still cites `ci.yml:119` and `ci.yml:394`. Those callers sit at `:121` and `:396` after this branch's `ci.yml` edit (+7/−5). The committed spec therefore carries the exact staleness the shipped prose was rewritten to avoid. Not a blocker — the spec is the requirements artifact, the requirement it states was met, and the operative text names jobs — but it is committed, so the next reader inherits two dead citations. |
| 2 | warning (PR body only) | PR #499 body, "Notes for review" | "the `ci.yml` comment edit shifted both by one" — it shifted both by **two** (5 comment lines replaced by 7). Fixing this is not a commit, so it costs no round. |
| 3 | observation | CI, not the diff | `lint-and-selftests` first red on this head at `tools/capability-parity-check-selftest.sh` case (a) — "real register is RED". **Re-run on the same commit: pass.** Not attributable to the diff: the guard reads only `tools/capability-parity.tsv` and `plugins/dev-pipeline/skills/run/stages/*.md`, and this branch touches neither. Green everywhere else it was checked — directly on the branch and on `main` locally, on the macOS bash-3.2 lane of the same CI run, on `main`'s CI and on sibling PRs', and in a full local `--jobs 10 --exclude install-topology` sweep on this head (73 scored / 73 run / 0 failed) deliberately left contending with another session's concurrent 10-way sweep. So the red did not reproduce under the condition most likely to provoke it. Still worth a ticket on its own account: a suite that reds non-deterministically inside a parallel sweep is the same cross-suite-interference class this ticket is about, and the run's own milestone 3 also took one red attempt (15:23:36) before satisfying (15:34:55) under the new lane. |
| 4 | nit | `docs/testing.md:43` | "four in-repo callers" counts workflow lanes; `CLAUDE.md:60`'s local recipe passes the same exclusion and is also in-repo (the install-topology section at `docs/testing.md:275` says so: "The documented local recipe excludes it too"). The explicit four-way enumeration removes any ambiguity, so this is a reading nit, not a defect. |

### CI evidence at the reviewed head (7dcefa1)

`lint-and-selftests` success · `selftests (macos, bash 3.2)` success · `mutation-sweep-pr`
success · `release-pr-gates` skipped · `pr-gates` failure at step 6 only ("lean chain
reconciliation") — the expected pre-verdict arm; every other arm of that job passed.

### Design fidelity

`not-applicable` — the spec declares no `## Design` section, and no changed path is a
web-component surface (`stageParams.webComponentGlobs` unset; default
`apps/web/**/*.{tsx,jsx}` matched nothing). `a11y-reviewer` and the design-fidelity dimension
were therefore not routed.

### Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 2 nits (one is finding 1 above, independently found; one restating that the load-bearing fix is the gitignored config — D-10's accepted cost, not a scope miss) |
| Security | Pass | 0 |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 |
| Test Coverage | Pass | 0 |

No reviewer went dark. No guard is owed: the diff has no code seam, which D-10 records as a
decision rather than an omission, and the reviewer agrees — a selftest or mutation row here
would have nothing to anchor to.
