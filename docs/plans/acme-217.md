# Plan: acme-217 — E2E null-model full-run replay

## Context

The repo's test pyramid (`docs/testing.md`) has an E2E row marked **Planned**: no test drives a
whole pipeline run with real tool execution at the mechanical seams. Every tier below it exists —
per-tool selftests, the lockstep manifest, `scenario-liveness-selftest.sh` for composed verdict
paths, and (since PR 1 of this epic) `workflows/runtime-shim-selftest.mjs` for production Workflow
`.mjs` bodies. What is missing is the tier that composes them into one run.

The gap is concrete. `scenario-lib.sh`'s `complete_stage` **hand-plants** every comment receipt as a
literal `https://github.example/c/<marker>` URL, so nothing anywhere exercises claim → comment-add →
pr-add against a `gh` that actually returns an `html_url`. The `git ls-remote | awk |
max-pushed-slice.sh` slice derivation is likewise uncovered as a *composition* — only its stdin
parse is tested. And the crash-recovery resume sequence (`pause-add` → `pipeline-session-add` →
stage-8 re-entry) exists only as three isolated per-command cases, never as a resume.

This PR adds the E2E tier: `e2e-replay-selftest.sh`, deterministic and model-free, riding the
existing CI discovery glob.

## Assumptions

- The replay asserts the **mechanical shadow** of prose gates, never the prose itself. A model-free
  CI cannot execute a stage document; this is stated in the harness header, not implied.
- The dev-pipeline's own config here has `unitTestScope: null`, so this repo has no mutation
  surface. The Stage-5 leg fabricates its own args (the same posture
  `runtime-shim-selftest.mjs` already takes with `{worktree: '/tmp/wt', …}`), so the gate is
  exercised regardless of the host config.
- Both CI lanes provide `node` (`workflows-mjs-selftest.sh` makes a missing node a hard FAIL rather
  than a skip), so the `.mjs` legs cannot silently no-op.

## Decision Ledger

No pre-flight `/plan-interview` ledger backs this ticket. The five decisions below were resolved at
intake from the codebase and are restated here as the binding record.

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What "receipt produced by an executed tool" means, and which shim seam mints it | Two seams, not one: `GH_BOT` override for wrapper calls, `gh` PATH shim for bare-`gh` sites. Claim leg executes production `claim-issue.sh`; comment/PR legs mint the URL through an executed shim while the invocation shape stays harness-owned, declared in the header | codebase-derived |
| D-2 | Whether the bare fixture remote and a stacked replay are in scope | Fixture remote stays, scoped to the slice-derivation *composition* only; no stacked replay (blocked on #211) | codebase-derived |
| D-3 | How a shell harness composes with the `.mjs` runtime shim | Extract the shim internals into `workflows/runtime-shim-lib.mjs` (non-glob name, `scenario-lib.sh` precedent); both the existing shim selftest and the new leg driver import it | codebase-derived |
| D-4 | Where the crash-recovery scenario lands relative to `scenario-liveness-selftest.sh` | Lands in the new E2E file; the liveness debt-register bullet is updated in the same PR so it stops claiming the gap | codebase-derived |
| D-5 | Whether any of #108's L0/L1 consumer tier ships here | No CI or workflow changes; the new suite rides the existing glob. Consumer tier ships under #108 | ticket-sourced (issue #217 Scope: "adopt #108 as filed … No new design here") |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh` **[NEW]** — the harness
- `plugins/dev-pipeline/skills/run/workflows/runtime-shim-lib.mjs` **[NEW]** — extracted shim internals
- `plugins/dev-pipeline/skills/run/workflows/e2e-workflow-leg.mjs` **[NEW]** — stage-4/5/8 leg driver
- `plugins/dev-pipeline/skills/run/e2e-replay-fixtures/` **[NEW]** — canned stage-1 verdict payloads
- `plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs` — refactored to import the lib
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — debt-register bullet updated
- `docs/testing.md` — E2E tier row flips from *Planned* to *Established*
- `CLAUDE.md` — the two new non-glob helpers join the covered-under-a-differently-named-suite list

## Reuse inventory

Every mechanic below already exists; this PR composes them rather than inventing shapes.

- `plugins/dev-pipeline/skills/run/scenario-lib.sh` — `reset_state`, `write_eval`, `write_report`,
  `write_verify_sidecar`, `VALID_PAYLOAD`. Sourced by absolute path resolved from `BASH_SOURCE`
  before any `cd`, per its own contract header.
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` — the `gh` PATH-shim-plus-call-log
  shape (`$GH_LOG`, `case "$1 $2"` dispatch, `chmod +x`, `export PATH="$MOCKBIN:$PATH"`).
- `plugins/dev-pipeline/skills/run/tools/claim-selftest.sh` — the `GH_BOT=<mock>` wrapper-injection
  seam that `claim-issue.sh` honors (explicit override wins).
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` — the marker-file-driven shim behavior
  switch and the synthetic-git-repo fixture shape.
- `plugins/dev-pipeline/skills/run/statectl.sh` — `init`, `set-stage`, `checkpoint`,
  `build-checkpoint-7`, `comment-add`, `pr-add`, `pause-add`, `pipeline-session-add`,
  `review-rounds`, `plan-review-set`, `verify-summary-set`, `mark-completed`, `state-path`.
- `plugins/dev-pipeline/skills/run/tools/max-pushed-slice.sh` — the slice parse, driven here through
  its documented `git ls-remote … | awk '{print $2}' |` composition.
- `STATECTL_STATE_DIR` — the fixture state-dir seam both `statectl.sh` and `verifyctl.sh` honor.

New helpers introduced: `runtime-shim-lib.mjs` and `e2e-workflow-leg.mjs`, both tagged `[NEW]`
above. `runtime-shim-lib.mjs` is an extraction, not an invention — no existing module exports
`makeRunner`/`makeFakeAgent` (`runtime-shim-selftest.mjs` exports only `stripMeta`, line 74).

## Implementation steps

1. **Extract `workflows/runtime-shim-lib.mjs`.** Move `stripMeta`, `makeRunner`, `makeFakeAgent`,
   the `parallel`/`pipeline` runtime doubles, `noop`, and `makeBudget` out of
   `runtime-shim-selftest.mjs` and export them. The filename deliberately does not match the
   `*-selftest.*` discovery glob — the same reason `scenario-lib.sh` is named as it is — and the
   header says so.
2. **Add the `workflow` global to `makeRunner`.** `plan-review.mjs` and `mutation-gate.mjs`
   (mutation-gate.mjs:101) both call the `workflow()` global, which the current 7-parameter wrapper
   does not inject — those two bodies would die with a `ReferenceError` under the existing shim.
   Append `workflow` as the **eighth, trailing** parameter so every existing positional call site
   keeps working with `workflow === undefined`.
3. **Refactor `runtime-shim-selftest.mjs` to import the lib.** No case changes, no assertion
   changes — a pure move. Its `PASS`/`FAIL` counts must be identical before and after.
4. **Add `e2e-replay-fixtures/`** with one canned stage-1 verdict payload per verdict shape
   (`no-split.json`, `stacked-prs.json`), each carrying verdict + `preflight` attestation + AC
   snapshot + `briefPath`, and `stacked-prs.json` additionally carrying `slicePartition`.
5. **Add `workflows/e2e-workflow-leg.mjs`.** Imports the lib; drives production `plan-review.mjs`
   (stage 4), `mutation-gate.mjs` (stage 5) and `code-review.mjs` (stage 8) with canned agent
   behavior queues; prints one JSON line per leg (`{stage, overall, …}`) on stdout for the shell to
   consume with `jq`. Takes the leg name as `argv[2]` so the harness drives one at a time.
6. **Add `e2e-replay-selftest.sh` — scenario 1, the no-split replay.** Build the two shims (a
   `GH_BOT` mock wrapper and a `gh` PATH shim, both logging to a call log and returning canned
   `html_url`s), a `STATECTL_STATE_DIR` fixture dir, and a synthetic git repo. Then walk stages 1–9:
   `statectl init`; execute production `claim-issue.sh` under the mock wrapper; mint each mandated
   receipt (`claimed`, `intake`, `plan`, `doc-update`, `code-review`, `pr`) by *executing* the shim
   and piping its `html_url` into `statectl comment-add`; feed step 5's leg verdicts into
   `plan-review-set` and `review-rounds`; build the stage-7 payload with `statectl
   build-checkpoint-7` (not the inline `VALID_PAYLOAD` literal); mint the PR URL through the shim
   into `pr-add`; `write_eval` + `write_report`; assert `mark-completed` is **accepted** and that no
   receipt in the final state matches the hand-planted `github.example` literal.
7. **Scenario 2 — the negative case.** Before minting the `pr` receipt, assert `set-stage 9 --status
   completed` is **refused**; then mint it and assert acceptance. This is the red-on-mutation demo
   that proves scenario 1's green is not vacuous.
8. **Scenario 3 — crash-recovery resume.** From a run left at `currentStage: 7` / stage 7 completed,
   assert `pause-add` is the first write and its span anchors on the prior `lastUpdatedAt`, then
   `pipeline-session-add` with a second session id, then stage-8 re-entry hydrating from
   `stageCheckpoint["7"]`, through to a terminal write.
9. **Scenario 4 — slice derivation against a real remote.** `git init --bare`, push
   `<prefix><KEY>`, `-pr2`, `-pr9`, `-pr10`, then execute the documented composition
   `git ls-remote --heads origin "<prefix><KEY>*" | awk '{print $2}' | max-pushed-slice.sh <KEY>`
   and assert it derives 10, not 2 — the lexicographic-ordering trap the `(mps10)` parse case
   already pins, now proven end-to-end through real `ls-remote` output.
10. **Update the registers.** Edit `scenario-liveness-selftest.sh`'s "(B) Uncovered, TRACKED"
    crash-recovery bullet to name this file as the owner; flip `docs/testing.md`'s E2E row to
    *Established*; add `runtime-shim-lib.mjs` and `e2e-workflow-leg.mjs` to CLAUDE.md's
    covered-under-a-differently-named-suite list.

## Test strategy

Verify-after — this PR *is* test infrastructure, so the deliverable and its verification are the
same artifact. Two obligations beyond "it passes":

- **Non-vacuity (step 7).** The harness contains its own red demo: a completion gate refused with a
  receipt absent, then accepted once minted. A harness that only ever asserts green is
  indistinguishable from one that cannot fail.
- **Refactor safety (step 3).** `runtime-shim-selftest.mjs`'s pass count must be byte-identical
  before and after the extraction. Recorded in the commit body per the repo's red-on-mutation idiom.

No `unitTestScope` is configured for this repo, so there is no mutation surface and the Stage-5
mutation gate does not apply to the change itself.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-1 | No-split replay reaches terminal `completed`, receipts minted by an executed tool | 5, 6, 7 | `e2e-replay-selftest.sh` scenario 1 + the no-`github.example` assertion (AC-1) |
| AC-2 | Crash-recovery replay resumes through stage-8 re-entry to a terminal write | 8 | `e2e-replay-selftest.sh` scenario 3 (AC-2) |
| AC-3 | Runtime in single-digit seconds, green on both CI lanes | 1–10 | — no test (non-functional) |

AC-3 carries the escape hatch deliberately: a wall-clock assertion inside the harness is flaky under
CI load. Runtime is measured at verification and reported in the PR body instead.

## Verification commands

```bash
# The new suite alone, plus the one it refactors.
bash plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh
bash plugins/dev-pipeline/skills/run/workflows/workflows-mjs-selftest.sh

# Repo gates (CLAUDE.md Verification).
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# AC-3 measurement (reported, not asserted in-harness).
time bash plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh
```

Bash 3.2 compatibility is a hard constraint (the macos `selftests-bash32` lane runs stock
`/bin/bash`): no associative arrays, no `mapfile`, no `${var^^}`.

## Risks / rollback notes

- **The extraction (steps 1–3) touches a landed suite.** If the import refactor changes
  `runtime-shim-selftest.mjs`'s behavior at all, the epic loses its runtime tier. Mitigated by the
  identical-pass-count check; rollback is reverting to the inlined helpers, which costs only the new
  E2E file's `.mjs` legs.
- **The `workflow` global (step 2) is an append.** Inserting it anywhere but last would silently
  shift every existing positional argument — `args` would arrive as `log`, and cases would fail for
  reasons that look like production bugs.
- **Shim drift.** The comment/PR invocation shapes are harness-owned (D-1) and can drift from the
  stage docs without any test going red. Accepted and declared in the harness header rather than
  papered over; the alternative — extracting production posting tools — is a hot-path change well
  outside a test PR.
- Rollback for the whole PR is deleting the new files and reverting four small edits. No production
  pipeline code changes, so a revert cannot affect a live run.

## Out-of-scope

- **A stacked-PR full replay.** Blocked on #211 (`scenario-liveness-selftest.sh:47-52`): per-slice
  stage-machine semantics are single-PR-scoped, so slice 2 has no defined re-entry and the harness
  would be asserting against itself. Only the slice-*derivation* composition lands here.
- **Extracting `post-comment.sh` / `open-pr.sh` from the stage prose.** A production change to the
  pipeline's hot path; not required by AC-1 as written (D-1).
- **Migrating `scenario-lib.sh`'s inline payloads onto the new fixtures.** That shared lib backs two
  existing suites; re-pointing it is a refactor with its own blast radius, not part of adding a tier.
- **Any CI or workflow change, including #108's L0/L1 consumer lanes** (D-5).
- **Driving `intake-review.mjs` or `design-sync.mjs`** — stage 1 and design mode are outside the
  four stages this replay walks; design mode is contractually interactive and fail-closes headless.

Unverified references: none — every path above was confirmed by read or grep against the branch
base, and the four new artifacts carry `[NEW]`.
