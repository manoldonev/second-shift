# lean review verdict — #362

verdict=approve
run_id: review-362-1
session_id: fd8a3f1b-52fd-4f3b-9176-54a220bc67e9
rounds: 1
pr: #365

Reviewed head: `8059cf69e62d1466ef3d2b2610c5f0fc35d3bea3` (merge of `main` into
`lean/second-shift-362`; the branch's own work is the two bot commits `3404661` + `0af69cb`).
Base: `main` @ `79d93b2`. Range reviewed: `origin/main...8059cf6` — 8 files, +612/-32.

The merge commit was verified clean: it brought in only release-owned files (CHANGELOG,
three plugin.json versions, marketplace.json, one onboarding.md ref bump) and touched none
of the branch's own source files.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `lean-gate-selftest.sh` green: jira `claim` exits 0 with no `GH_BOT` and zero tracker calls; M5 passes on a sectioned `Closes [ACME-7]` + verdict path against an EMPTY comment trail; fails when either is omitted. Re-run independently, not taken from the PR body. |
| AC-2 | satisfied | github arm behaviorally unchanged — every pre-existing case green. Independently corroborated: an adapter-default mutant reds `(k2)`, `(k3)`, `(k6)`, i.e. the github cases genuinely bind. |
| AC-3 | satisfied | `(n7)`/`(n8)` assert absent-`tracker.type` == github and that explicit github is identical; unrecognized value is `rc=2`. Hand-applied mutant flipping the default to `jira` is killed by 7 cases. |
| AC-4 | satisfied | `SKILL.md` is exactly 60 lines (cap held, case `(f)`); both tracker READMEs state the deltas; the former universal "two tracker writes" rule now reads "github only". |
| AC-5 | satisfied | `check-frozen-files.sh origin/main` clean; `check-changelog-trailer.sh origin/main` OK; two `Changelog:` trailers on the branch. No frozen file appears in the diff. |
| AC-6 | satisfied | `tools/mutation-baseline.tsv` untouched and carrying exactly the 4 `lean-gate` rows claimed. The spec's "read that green honestly" caveat is accurate — independently confirmed that behavioral coverage, not the sweep, is what kills mutants at the new sites. |
| AC-7 | satisfied | All 612 added lines scanned: no operator or consumer identity tokens. The only `XX-NN`-shaped tokens are the spec's own `AC-n` numbering. |
| AC-8 | satisfied | `docs/onboarding.md` entry-gate claim is now scoped to the GitHub tracker; a genuine staleness this change caused, fixed in the same diff. |
| AC-9 | satisfied | `scenario-liveness-selftest.sh` 56/56, including the composed `(lean-jira)` leg and both non-vacuity reds `(lean-jira-nv)` and `(lean-jira-p10)`. |

Nine of nine satisfied; none undeterminable.

## Independent verification run for this review

- Full selftest sweep **without** `SKIP_STRESS`: 274 passed, 0 failed (the configured `test`
  lane sets `SKIP_STRESS=1`, so the stress legs were exercised here deliberately).
- `shellcheck -e SC1091,SC2015,SC2181` clean on all three changed `.sh` files.
- Five hand-applied mutants at the new branch sites; three killed, two survived (below).
- Nine adversarial probes of `jira_items_section` against the real function, all matching the
  documented contract — including `###Notes` correctly NOT closing a section (CommonMark:
  it is literal text, so content after it really is still inside).

## Findings

No blockers.

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | minor | `lean-gate.sh:776` | The "any heading depth closes the section" rule is untested. Narrowing the closer to `^###[[:space:]]` **survives the entire suite** (0 failures) — verified, not predicted. The shipped behavior is correct and deliberate (the adjacent comment argues for it explicitly); what is missing is a fixture whose closing heading is a different depth from the opener. Under the narrowed form a `## Notes` section would not close, so a later `Closes [KEY]` would falsely count. |
| 2 | minor | `lean-gate.sh:822` | A bracket-less `Closes ACME-7` is never asserted as rejected. Making the brackets *optional* (`\[?$ISSUE\]?`) **survives the suite**. Note the reviewer's original form of this claim — dropping brackets entirely — is refuted: that mutant is killed by 4 cases, because it also breaks the positive fixture. |
| 3 | nit | `lean-gate.sh:412` | `ensure_progress_file` is called explicitly immediately before `append_line`, which already calls it (`:320`). Harmless and arguably self-documenting; behavior-preserving either way. |
| 4 | nit | `lean-gate.sh:96` | The `--help` range bump `2,63p` → `2,65p` is correct (line 65 is the last usage comment, line 66 is `set -uo pipefail`), but no selftest invokes `--help`, so drift there stays untested. Pre-existing gap, cosmetic surface. |

Findings 1 and 2 are thin guards on **correct** shipped behavior, not defects. Neither
falsifies AC-6, which enumerates the twelve mutants it claims killed and never asserts
exhaustive coverage of the section function. They are the natural content of a follow-up,
and per the repo's own doctrine a survivor is data rather than a red lane.

Suppressed (below threshold, recorded not acted on): `$ISSUE` is interpolated unescaped into
the `grep -E` pattern in the new jira arm — identical to the pre-existing github arm two lines
below and to path construction at `:202-204`; operator-supplied CLI argument with no remote
reach. Pre-existing pattern, consistent, not a new gap.

Two scope-reviewer notes were dismissed on inspection: it flagged the `docs/onboarding.md`
edit and the liveness-leg addition as unnamed by any AC, but AC-8 and AC-9 name them exactly.

## Reviewer panel

Seven reviewers dispatched, seven returned — no dark reviewer, no coverage gap this round.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 0 (2 suppressed, both dismissed above) |
| Security | Pass | 0 (2 suppressed, pre-existing) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 |
| Test Coverage | Pass | 0 |
| Unit Test Mutation | Pass w/ nits | 4 (2 confirmed by execution, 1 refuted as stated then confirmed in steelman form, 2 nits) |

## Strengths

- The adapter resolves `tracker.type` **once** and branches at three sites, leaving milestones
  1–4 adapter-insensitive; that boundary is what stops a second tracker authority forming.
- Fail-safe direction is chosen deliberately and argued in-code: absent ⇒ `github` (the arm
  that fails loudly), unrecognized ⇒ `rc=2` rather than a silent fall-through.
- The symmetric space-required heading rule is the non-obvious correctness call here, and both
  halves are pinned in both directions by `(n13)`/`(n14)`.
- The PR corrects two pieces of its own prior prose rather than letting them stand: that jira
  runs have **no** reconciliation backstop, and that the green `K_BUDGET=2` sweep structurally
  cannot reach the new sites. Volunteering both is the opposite of a flattering self-report.
