# Stage-6 completion requires a verifyctl attestation (#212)

## Context

`set-stage <issue> 6 --status completed` requires a `verifySummary` to be present, and — since #98 — requires an object summary to show at least one verifying lane that actually ran. Neither check asks whether anything **executed** to produce those values. `verify-summary-set` records whatever JSON the session hands it, so a run that hand-composes the verification commands reaches a completed Stage 6 that is byte-indistinguishable in state from a run that went through `verifyctl.sh`.

That is not hypothetical: on the #205 run verification was genuinely executed and genuinely green, but through raw Bash. The state file carries `verifyAttempts: null` and the run produced neither `205-verify.json` nor `205-verify.log`, while 11 of 11 compliant runs on the same machine produced both. Stage 6 completed anyway.

The attesting signal already exists and is already written by every compliant run: `verifyctl.sh` maintains a runId-scoped sidecar at `{pipelineStateDir}/{issue}-verify.json` carrying `{runId, headSha, chargedHead, at, failedClasses[], status}`. This change gates Stage-6 completion on it. Nothing new is built in the producer.

## Assumptions

- `runId` is written once by `statectl init` and never overwritten, so a sidecar carrying the current `.runId` was written by *this* run. `verifyctl.sh` already relies on exactly this comparison to self-clean stale sidecars.
- Every compliant Stage-6 path invokes `verifyctl run` at least once **without** `--no-attempt`. The safety-net re-verify in the advisory quality pass runs `--no-attempt` and writes no sidecar by contract; it always follows a charging run, so the sidecar is present regardless.
- A Stage-6 completion never legitimately happens on a red verify — the exhaustion path calls `mark-failed`, not `set-stage --status completed`. This makes a future `.status == "pass"` tightening safe, but it is not part of this change (see Out-of-scope).
- The pipeline-state dir resolution inside `statectl.sh` (`state_dir()` / `state_path()`) is the same one `verifyctl.sh` uses to place the sidecar, so both agree on the path without re-deriving it.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which sidecar filename(s) does the gate require? | Both lanes, mirroring the existing `verifySummary` precondition: a run with `targetRepos` requires `{issue}-<id>-verify.json` for **every** target id; a single-repo run requires the flat `{issue}-verify.json`. AC-1 names only the flat file, but `verifyctl.sh` derives the path as `${key_lc}${REPO_ID:+-$REPO_ID}-verify.json`, so a literal reading would hard-block every be-fe-pair Stage-6 completion. | codebase-derived |
| D-2 | How does the gate behave on a stacked run, where `runId` is constant across slices? | One sidecar per run, re-verified per slice — the issue's second option. Each slice's own `verifyctl run` overwrites the sidecar. The gate therefore cannot distinguish slice N's sidecar from slice N-1's; that residual weakness is recorded as a declared limitation in `state-schema.md` and belongs to the sibling per-slice-stage-accounting issue. Per-slice sidecars would require changing verifyctl's filename derivation, i.e. new producer behavior, contradicting the issue's own premise. | codebase-derived |
| D-3 | How do pre-sidecar-era state files terminalize? | `--force` is the sole escape hatch, consistent with AC-2 and with every neighbouring completion precondition. The issue floats gating on a "post-schema marker", but no schema/era field exists anywhere in the state schema; inventing one would again contradict "nothing new needs building". | codebase-derived |
| D-4 | Are the sidecar's `.status` and `.headSha` checked? | No. AC-1 asks only whether verifyctl ran for this run — rung 1 of the ladder. Recorded as a decision rather than an omission; tightening to `.status == "pass"` is a defensible follow-up. | deferred |

## Affected files

- `plugins/dev-pipeline/skills/run/statectl.sh` — the new precondition and its two helpers.
- `plugins/dev-pipeline/skills/run/scenario-lib.sh` — the shared fixture plant.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — refusal + pass-path + per-repo cases.
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — the `no-split` Stage-6 leg plus its non-vacuity check.
- `plugins/dev-pipeline/skills/run/state-schema.md` — the Stage-6 gate-table row and the verifyctl-sidecar note.
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` — the stage doc states the Stage-6 completion precondition set in three places; a session reading it must be forewarned of the new refusal, and the `--no-attempt` non-attestation rule belongs beside the advisory quality pass that uses it.

## Reuse inventory

- `state_path()` (`statectl.sh`) — resolves the state file honoring `paths.pipelineStateDir` and the ticket-key lowercasing; `dirname` of it is the sidecar directory. Reused rather than reconstructing a literal `.claude/pipeline-state/`.
- `die()` / `EXIT_CODE` (`statectl.sh`) — the established refusal idiom every neighbouring precondition ends in.
- `stage_completion_preconditions()` (`statectl.sh`) — the new check is a case-`6` clause inside it, so AC-2's `--force` bypass comes free from the existing `if [[ "$force" -ne 1 ]]` short-circuit in `cmd_set_stage`; no new bypass logic is written.
- `reset_state()` / `complete_stage()` / `complete_run_vs()` (`scenario-lib.sh`) — the shared full-green-run recipe; the fixture plant goes inside it rather than being duplicated per call site.
- `sct()` (`scenario-lib.sh`) — used by the new fixture helper to read the run's `runId` back out of state.
- Three helpers are introduced: `sidecar_attests()` `[NEW]` and `require_verify_sidecar()` `[NEW]` in `statectl.sh`, and `write_verify_sidecar()` `[NEW]` in `scenario-lib.sh`. Each was confirmed to have no existing equivalent (no sidecar-reading code exists in `statectl.sh` today; `verifyctl.sh`'s own reader is inside `cmd_run` and is not sourceable).

## Implementation steps

1. Add `sidecar_attests <file> <run-id>` `[NEW]` to `statectl.sh`, above `stage_completion_preconditions`. Returns 0 iff the file exists, the run id is non-empty, and the file's `.runId` equals it. A missing file and a stale `runId` are the two distinct refusal cases AC-1 collapses into one phrase.
2. Add `require_verify_sidecar <key> <current-state-json>` `[NEW]` alongside it. It reads `runId` from the in-memory state and derives **both the directory and the filename stem** from `state_path` — `STEM="$(state_path "$key")"; STEM="${STEM%.json}"` — so the sidecar is `${STEM}-verify.json` / `${STEM}-<id>-verify.json`. Deriving the stem (not just `dirname`) is load-bearing: `verifyctl.sh` lowercases the key (`key_lc`) before composing the sidecar name, and `state_path` applies the same lowercasing plus `paths.pipelineStateDir`. Composing the filename from the raw argv `$key` instead would look for `PROJ-123-verify.json` while verifyctl wrote `proj-123-verify.json`, hard-refusing every Stage-6 completion on a JIRA-key consumer — a break second-shift's own numeric-key dogfooding cannot surface. It then branches exactly like the neighbouring `verifySummary` check: per-target for every entry of `targetRepos`, else the flat file. Each refusal `die`s naming `verifyctl.sh` as the required producer, distinguishing absent-vs-stale, and ending in the house `--force for crash-recovery` phrasing.
3. Thread the ticket key into `stage_completion_preconditions()` as a third parameter and pass `"$key"` from its single call site in `cmd_set_stage` (the function currently receives only the stage number and the state JSON, and the sidecar path needs the key). Call `require_verify_sidecar` at the end of case `6`, after the existing summary checks, so the more specific summary diagnostics still fire first.
4. Add `write_verify_sidecar <key> [repo-id]` `[NEW]` to `scenario-lib.sh`: read `runId` back from state via `sct get`, and write a plausible sidecar (`runId`, `headSha`, `chargedHead`, `at`, empty `failedClasses`, `status: "pass"`) to the fixture state dir. It must run **after** `reset_state`, which deletes `*.json` from that dir. Give it one opt-out: when `SCENARIO_SKIP_VERIFY_SIDECAR=1` it returns without writing. That flag is the mechanism step 8's non-vacuity case needs — the plant lives inside the shared recipe, so a scenario cannot simply omit it without bypassing the recipe the lib exists to hold once.
5. Call it from `complete_stage`'s case `6` and from `complete_run_vs`'s inline Stage-6 block — the two places in the shared recipe that drive a Stage-6 completion. Planting per call site instead would duplicate the recipe the lib exists to hold once.
6. Extend `statectl-selftest.sh` beside the existing `(sc5)` / `(sc5b)` / `(sc5c)` Stage-6 cases with a new block covering: absent sidecar refused; present-but-stale-`runId` refused; matching sidecar accepted; `--force` bypasses the refusal. Add a per-repo case beside `(vss-repo)` asserting a be-fe-pair run is refused when only one target's sidecar exists and accepted when both do.
7. Repair the existing Stage-6 completion assertions in `statectl-selftest.sh` that drive `set-stage 6 --status completed` directly (outside the shared recipe) by planting a sidecar first — these are pass-path assertions whose subject is a different gate, not tests of this one.
8. Extend the `no-split` scenario in `scenario-liveness-selftest.sh` with a non-vacuity check: re-run the same green ladder with `SCENARIO_SKIP_VERIFY_SIDECAR=1` set across the Stage-6 leg, and assert Stage 6 does **not** complete — so the scenario cannot stay green if the precondition is deleted. This mirrors the existing `(ns3)` non-vacuity check for the stage-9 receipt, and uses the step-4 opt-out rather than bypassing the shared recipe.
9. Update `state-schema.md`: add the attestation clause to the Stage-6 row of the completion-evidence table, and extend the verifyctl-sidecar note with the gate's dependency on it, the `--no-attempt` non-attestation rule, and the declared stacked-run limitation from D-2. Carry the same two facts into `stages/6-verify.md` — the attestation clause beside the existing "completion precondition refuses without it" sentence, and the non-attestation rule beside the advisory quality pass's `--no-attempt` safety-net paragraph.

## Test strategy

Verify-after — this is infrastructure with no runtime behavior of its own, and the gate is only observable through `statectl`'s exit code. Coverage sits in the two tiers the repo's tier map assigns:

- **Per-tool behavioral selftest** (`statectl-selftest.sh`): the refusal and pass paths of the new precondition against fixture state dirs, in the same numbered-comment style as the `(sc5)` family it sits beside. Both refusal cases are distinct assertions — an absent sidecar and a present-but-stale one fail for different reasons and must both be pinned.
- **Scenario** (`scenario-liveness-selftest.sh`): the composed `no-split` verdict path must still reach `mark-completed`, plus a non-vacuity check proving the new gate can refuse. A gate nothing composes against is a gate the next drift walks straight through.

No prose-presence guards are added: the `state-schema.md` edits are documentation of a behavior the selftests already execute, so grepping them would assert only that prose contains words.

`unitTestScope` is unconfigured for this repo, so there is no mutation surface and the unit-test gate is skipped.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Stage-6 completion refused with no current-`runId` sidecar, error names `verifyctl.sh` | 1, 2, 3 | `statectl-selftest.sh` absent-sidecar and stale-`runId` cases, asserting the refusal text names `verifyctl.sh` (AC-1) |
| AC-2 | Refusal bypassable by `--force` only | 3 | `statectl-selftest.sh` `--force` bypass case (AC-2) |
| AC-3 | A normal `verifyctl run` → `set-stage 6 --status completed` sequence is unaffected | 2, 4, 5, 7 | `statectl-selftest.sh` matching-sidecar pass case + every existing Stage-6-traversing assertion staying green (AC-3) |
| AC-4 | Selftest covers refusal + pass path; `no-split` scenario composes against the precondition | 4, 5, 6, 7, 8, 9 | `statectl-selftest.sh` new block; `scenario-liveness-selftest.sh` `no-split` leg + non-vacuity check (AC-4) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Blast radius across the existing suite.** The gate invalidates every selftest path that completes Stage 6 — the shared recipe in `scenario-lib.sh` plus the direct `set-stage 6 --status completed` call sites in `statectl-selftest.sh`. If any is missed the suite goes red loudly, not silently, so the failure mode is a visible one. Full-suite green is the gate on this change.
- **In-flight runs on this machine.** A run that already completed Stage 6 is unaffected (the precondition only fires at the completion write). A run mid-Stage-6 whose state predates the sidecar convention terminalizes via `--force`, per D-3.
- **The stacked-run weakness is real and shipped.** Per D-2 the gate is weaker on multi-slice runs than on single-PR runs. It is strictly better than today's zero attestation, and is documented as a limitation rather than presented as full coverage.
- **Rollback** is the revert of a single commit; the sidecar producer is untouched, so nothing outside `statectl.sh` changes behavior.
- **Commit contract.** This touches `plugins/**`, so the commit body carries a real `Changelog:` trailer (not `Changelog: none`) — a new hard refusal is consumer-visible. The verb is `feat:`: in this repo the AI tooling *is* the product, so a new capability takes the honest verb rather than being downgraded to a patch. No version or `CHANGELOG.md` edit — those are release-derived and frozen in a feature PR.

## Out-of-scope

- Checking the sidecar's `.status` or `.headSha` (D-4) — a follow-up tightening, deliberately not folded in.
- Per-slice sidecar attestation (D-2) — owned by the sibling per-slice-stage-accounting issue.
- Gating at `verify-summary-set` instead of at completion — the issue explicitly prefers completion, to keep `verify-summary-set` usable for the be-fe-pair per-repo path.
- Any change to `verifyctl.sh`, including making `--no-attempt` write a sidecar (which would break its documented read-only accounting posture).
- Retrofitting attestation onto historical state files.

Unverified references: none.
