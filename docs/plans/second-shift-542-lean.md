# 542 — delta-aware consumer CI for the verdict-record commit

Issue: [#542](https://github.com/manoldonev/second-shift/issues/542)

## Problem

`review-lean` step 7 requires the verdict record to be committed, pushed to the PR's head
branch, and to be the **last** commit on it. In a consumer whose CI triggers on
`pull_request`, that push fires a second full CI run whose only content is a markdown file
the pipeline wrote itself — measured on a real consumer as a full re-run of lint, typecheck,
build, ~570 unit tests and two API-test jobs.

Worse than the waste: with `concurrency.cancel-in-progress: true` keyed on the ref, a verdict
push that lands while the code commit's run is still going **cancels it**. The result is a
cancelled run on the SHA carrying the code and a completed run on the SHA carrying only
markdown — the evidence is inverted, not merely duplicated. Reachable whenever review latency
is under CI latency.

`paths-ignore` is a no-op here: for `pull_request` events GitHub evaluates path filters against
the whole PR diff (base…head), not the incremental push, so every lean PR matches regardless.

## Direction (operator, DE 2026-08-17 — binding)

Delta-aware consumer CI: a short-circuit **guard job**, not CI suppression, and not an
off-branch verdict record.

## Acceptance criteria

**AC-1 — the guard, and why it is a job and not `[skip ci]`.**
second-shift ships a consumer CI guard that classifies the head commit: when the diff
`parent..head` is exactly the lean verdict-record path (a docs-only verdict commit at head),
it reports `skip=true` so the consumer's heavy jobs are skipped by a job-level `if:`, and the
workflow still reports on the head SHA. A job skipped by a job-level `if:` produces a check
run GitHub counts as passing for required status checks; `[skip ci]` produces **no run at
all**, leaving a required check `Expected` forever. That is why option 1 loses as a default,
and it survives only as an explicit opt-in for consumers that verifiably have no required
checks — not implemented here.

**AC-2 — the trust condition (the whole design).**
The short-circuit fires ONLY when a **completed, successful** run of the *calling* workflow
exists for the **parent** SHA, queried in-workflow via the Actions API. If the code commit's
run was cancelled (the `cancel-in-progress` hazard above), failed, or is absent — or if the
query cannot be answered at all — the guard falls through to a full run. Every unknown
resolves to `skip=false`. A short-circuit without this condition is a fail-open shape.

**AC-3 — option 2 (off-branch verdict) is REJECTED on the record.**
Moving the verdict to `git notes` / a dedicated ref / a check-run demotes it from a committed,
diffable record to a tracker-side record, and the patch-binding invariant it carries
(`reviewed_patch_id` recomputed against the branch's own diff) is load-bearing in three
places: build milestone 4 (`lean-gate.sh`), the merge boundary (`lean-evidence.sh`), and
`lean-reconcile.sh`. The verdict stays one of the committed artifacts. This rejection is
recorded in the guard script's header, where a future maintainer reaching for option 2 will
read it.

**AC-4 — the concurrency note in consumer guidance.**
Onboarding and the consumer consent doc state: for `pull_request` events, do not key
`cancel-in-progress: true` bare on the ref — a verdict push must not cancel the code SHA's
in-flight run. This closes the evidence-inversion half regardless of AC-1 adoption lag, and it
is also the condition under which AC-2's trust check falls through to a full run.

**AC-5 — selftest coverage for the guard's three verdicts.**
A behavioural selftest next to the tool covers: docs-only verdict commit + parent green →
`skip=true`; docs-only verdict commit + parent cancelled → full run; mixed diff → full run.
Plus the fail-closed unknowns (no PR context, unreadable diff, API failure, wrong workflow,
wrong event) and the emitted workflow's own wiring.

**AC-6 — docs (doc AC for AC-1/AC-2's new emitted pair).**
`docs/onboarding.md`, `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` and the
`onboard` skill are updated for the third emitted file pair: the Step 3 acceptance offer, the
Step 7 emit, and the Step 8 commit list. Without this the guard exists but no consumer ever
receives it.

## Design

Design: none — no UI surface; this is CI plumbing (shell + workflow YAML).

## Shape

New, under `plugins/second-shift/templates/consumer/`:

- `second-shift-delta-guard.sh` — the classifier. Reads the PR head SHA and the calling run's
  identity from the environment, computes `parent..head`, and writes `skip=true|false` plus a
  reason to `$GITHUB_OUTPUT`. Always exits 0: a guard that reds would red the very lane it
  exists to shorten.
- `second-shift-delta-guard.yml` — a `workflow_call` reusable workflow exposing `skip` as an
  output, so the consumer adds two lines to their existing heavy workflow rather than a job.
- `second-shift-delta-guard-selftest.sh` — AC-5.

Edited: `onboard/SKILL.md` (Step 3 item 9, Step 7, Step 8), `SECOND-SHIFT.md`,
`docs/onboarding.md`, `scripts/lockstep-manifest.tsv` (the verdict-record suffix is pinned
independently in the guard and in `lean-evidence.sh`; a one-sided rename would make the guard
classify every commit as mixed — silent, and only costing minutes, so nothing would ever
notice).
