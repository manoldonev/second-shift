# lean review verdict — #719

verdict=needs-work
run_id: review-719-1
session_id: f7753c86-96fc-4caa-adff-267c9cdd8bf2
rounds: 1
pr: #732
reviewed_head: d8a91965c5aec44d5ae29b7f60a38051780ca2b2
reviewed_patch_id: a5b3b61d60412f0340a6dc88454312715ef3bb1e
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review — PR #732 / issue #719, round 1

Range read: `c333906..HEAD` (d8a9196) — FULL branch diff (root round, nothing to inherit).
Reviewed from `/Users/mdonev/github/second-shift-worktrees/719` with `claude/second-shift-719`
checked out.

## Verdict

**needs-work** — two blockers. AC-5 is unsatisfied and both correctness CI lanes are red at the
reviewed head.

## Per-AC scoring

| AC | Verdict | Evidence (re-derived at d8a9196) |
| --- | --- | --- |
| AC-1 | satisfied | `git grep -nE 'Guard-mass\|check-guard-budget' -- . ':!docs/plans' ':!CHANGELOG.md'` prints nothing (rc=1); same command at c333906 → 29 hits. |
| AC-2 | satisfied | `test ! -e scripts/check-guard-budget.sh -a ! -e scripts/check-guard-budget-selftest.sh` passes; both files deleted (−91, −163). |
| AC-3 | satisfied | The AC's awk-over-`pr-gates` pipeline → `0`; same pipeline over `c333906:.github/workflows/ci.yml` → `1`. No `check-guard-ratchet` replacement anywhere. |
| AC-4 | satisfied | `12 files changed, 77 insertions(+), 304 deletions(-)` → net −227, ≥ 200. |
| AC-5 | **unsatisfied** | `tools/prose-blockers-selftest.sh` reds at this head. CI run 33329811036 at d8a9196: `lint-and-selftests` FAIL and `selftests (macos, bash 3.2)` FAIL, `FAILED suites: tools/prose-blockers-selftest.sh (rc=1)`, `77 scored, 76 run, 1 served from cache, 1 failed (0 infrastructure)`. Reproduced locally (`want '0', got '3'`). `check-workflows-selftest.sh` — the AC's second half — is green. |

## Blockers

### B1 — AC-5 unsatisfied: the branch reds `tools/prose-blockers-selftest.sh`

`plugins/dev-pipeline/skills/review-lean/SKILL.md` line 140-ish (the "A merge-boundary refusal is
not a review round" bullet) had its prose rewritten to drop `guard-budget` from the policy-gate
list. Prose-blocker census ids are **content-derived**, so editing that construct re-keys it:

```
$ bash tools/prose-blockers.sh check          # at d8a9196
[prose-blockers] UNDISPOSITIONED — in the tree, absent from docs/prose-blocker-triage.tsv:
  pb-85e129b1  plugins/dev-pipeline/skills/review-lean/SKILL.md:140
[prose-blockers] STALE — the row expects a surviving construct, the tree has none:
  pb-6f30a528  (pointer-kept)
```

The same command at base `c333906` prints `✓ zero undispositioned constructs`, so this is
branch-introduced, not inherited. `docs/prose-blocker-triage.tsv:77` is the affected row
(`pb-6f30a528  gate-backed  pointer-kept  …review-lean/SKILL.md:119  .github/workflows/ci.yml::lint-and-selftests`).

This is a red **correctness** lane, not a policy one, so the merge-boundary carve-out does not
apply: `lint-and-selftests` and `selftests (macos, bash 3.2)` are both evidence about the code and
both refuse at d8a9196.

**Fix.** Re-key row 77 to `pb-85e129b1`, regenerate its `sites` cell from the census command, and
name the predecessor id in the `note` — which is exactly what the record's own header documents
("a construct whose prose this prune EDITED carries its post-prune id and names its predecessor in
the note"). Do it **last**, after the B2 edit, since any further prose change to a STOP construct
re-keys it again.

### B2 — a surviving prose reference to the deleted gate, in a file this PR edited

`docs/lane-latency.md:78`, unchanged by the branch:

```
3. **Do not spend a round on a budget red.** A guard-budget or trailer failure is a CI-shaped
   refusal that no reviewer judgement resolves; …
```

This is a live ranked-lever naming a CI gate the PR deletes. The PR rewrote the *same document* 20
lines above (`:57-58` → "a red policy-gate CI step (since deleted, #719)"), so the file now
contradicts itself, and `plugins/dev-pipeline/skills/review-lean/SKILL.md` — which cites
`docs/lane-latency.md` for that very measurement — was corrected while its source was not.

It escapes AC-1 only on spelling: the AC's regex is `Guard-mass|check-guard-budget`, and this site
spells the gate `guard-budget`. The ticket's Delete section obliges "Every reference", and its
adversarial table names "Leave prose describing the deleted script" as the botch AC-1 is supposed
to close — so the AC under-matches its own stated intent here. A broader net
(`git grep -niE 'shell mass|guard/test shell|budget red|budget guard|guard-mass'`) finds exactly
this one survivor; `tools/mutation-operators.tsv:17` ("per-guard budget K") and
`docs/live-render.md:129` ("**absent**-budget reds") are unrelated senses and are fine.

**Fix.** Rewrite lever 3 so it does not name the deleted gate — e.g. "A trailer or frozen-files
failure is a CI-shaped refusal…". Consider widening AC-1's regex to cover the bare `guard-budget`
spelling so the botch row actually closes what it claims.

## Recorded, not blocking

- **`pr-gates` is red on `check-lean-chain.sh` (step 6).** Expected pre-approve state on a lean PR
  — the lean-chain step requires a committed `verdict=approve` record. Steps 3–5 (frozen files,
  changelog trailer, pipeline chain) all pass. Not a code defect; no round is owed for it.
- **`mutation-sweep-pr` passes** (21s) at d8a9196 — nothing in the diff anchors a catalog row.
  Verified independently: `tools/mutation-catalog.tsv`, `tools/mutation-exclusions.tsv`,
  `tools/selftest-suite-timings.tsv` and `tools/selftest-cache-inputs.tsv` carry no
  `check-guard-budget` row, and `scripts/check-gate-buckets.sh` is green
  (`293 refusal site(s) across 5 file(s)` — the deleted script was never one of them). The
  ticket's "No catalog / exclusions / gate-buckets / timings rows exist for it (verified)" holds.
- **The `Changelog:` trailer will render literal text into the release notes.** The commit carries
  `Changelog: none (repo CI only). Migration: drop Guard-mass: trailers.`
  `scripts/derive-release.sh:242` drops a block only when it is *entirely* the word `none`
  (after case/whitespace/trailing-period normalization), so this block renders as an indented
  bullet body reading `none (repo CI only). Migration: drop Guard-mass: trailers.` The presence-only
  gate (`check-changelog-trailer.sh`) passes either way. Fixable in the merge dialog; not a code
  change and not a round.
- **`docs/testing.md:14-17`** — the `[below](#the-slow-suite-table)` link, previously attached to
  the `check-guard-budget.sh` clause, is now attached to "the markdown half a derived nightly
  total". The anchor resolves (`### The slow-suite table`, line 252) but that section is about
  suite timings, not the prose total. Pre-existing oddity, slightly sharpened; not worth a round.
- **Four other local sweep reds were environment, not the branch.** `lean-gate-selftest.sh`,
  `scenario-liveness-selftest.sh`, `orchestrate-lean-selftest.sh` and `operator-override-selftest.sh`
  failed in the local sweep under a shell carrying `LEAN_ATTEND_MODE` and `LEAN_RUN_MODEL` — the
  known env-leak family. Re-run under `env -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL` they are green
  (`operator-override` 36/0, `orchestrate-lean` all green, `scenario-liveness` 76/0), and CI's own
  sweep at d8a9196 names exactly one failing suite, `tools/prose-blockers-selftest.sh`. Dismissed.

## Scope and design

- **Scope boundary honoured.** No replacement mechanism of any kind was introduced — no ratchet,
  no smaller budget, no register. The deleted script had no side responsibilities: its whole body
  is `is_guard_path` / `classify_*` / `measure_*` plus the trailer escape, so nothing else was lost
  with it. Every remaining edit is prose.
- **Design fidelity: not-applicable.** The spec carries no `## Design` section and no `| RS-n |`
  rows; step 5b is not armed.

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 2 blockers, 1 minor | 85–96 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → default `apps/web/**/*.{tsx,jsx}`).

The panel's minor — "three sweep reds not confirmed within the review budget" — is resolved above
and dismissed: the clean-env re-runs plus CI's single-suite failure list settle it.
