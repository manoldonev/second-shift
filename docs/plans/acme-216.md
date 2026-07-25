# Plan — #216: extend scenario-liveness reach (circuit breaker, exhausted-review terminal, be-fe-pair, boundary header)

## Context

`plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` **[VERIFIED]** is the repo's only composed-path harness — it exists because the stacked-prs path died in #204 with every per-tool selftest green. Its own reach is now the gap: it drives 1 of 16 declared `failureContext.reason` paths, and three composed paths (circuit breaker, exhausted-review terminal, be-fe-pair) sit in the exact all-green-units/unproven-composition posture stacked-prs had before #204.

This ticket adds three scenarios, one extracted tool plus its scenario, and a boundary list in the harness header so the next reach audit is a diff rather than a re-derivation.

## Assumptions

1. **The harness composes executables, not prose.** Its header states this scope boundary already (lines 19–22): agent-prose gates appear only as their mechanical shadows — the state writes their outcomes produce. Every scenario below is bound by it.
2. **`scenario-lib.sh` **[VERIFIED]** needs no new stage helper.** `write_verify_sidecar` already takes an optional repo id (`$2`), which is the only per-repo affordance the be-fe-pair scenario needs from the lib; the pair's stage-6 leg is scenario-specific composition and belongs in the harness.
3. **No production behavior changes.** This is a `tests:` ticket. The one production edit is `stages/1-intake.md` **[VERIFIED]** rewiring to call the tool extracted from it — a refactor with identical semantics, not a behavior change.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | AC-1 calls for a "composed verifyctl → breaker → mark-failed chain", but is the breaker predicate composable at all? | No — and the scenario must say so rather than fake it. Verified: `verifyctl.sh` **[VERIFIED]** evaluates `count >= 2` *before* charging, so the counter is monotonic and exit 4 is idempotent; `statectl.sh` **[VERIFIED]** `cmd_verify_attempts` exposes only `--incr` (no reset/decrement); the sidecar carries `{runId, headSha, chargedHead, at, failedClasses, status}` and no clean-run marker. The trigger in `stages/6-verify.md` **[VERIFIED]** ("two consecutive budget exhaustions with no clean run in between") is therefore *not derivable from persisted state*. Building a breaker-predicate tool would be a product change, out of scope here. So AC-1 drives the real chain to the edge of prose — real verifyctl, real charging, two real consecutive exit-4s — then performs the `mark-failed` write, and the scenario comment states plainly that the breaker *decision* stays agent-prose. Anything else would be a harness-authored predicate reading as coverage: the tautology scope item 6 forbids. | codebase-derived |
| D-2 | The ticket says "double TEST_FAILURE" produces exhaustion. Does it? | No. Two failing runs charge the counter to 2; the exhaustion verdict (exit 4) surfaces on the *third* invocation, because the `count >= 2` check precedes the charge. The scenario drives charge → charge → exit-4 → exit-4. Each charge additionally requires a fresh HEAD: `verifyctl.sh` writes `chargedHead` before incrementing and skips charging when `chargedHead == HEAD`, so the scenario commits a fix between runs — which is what the real Stage-5→6 fix loop does anyway. | codebase-derived |
| D-3 | Where does the AC-5 tool cut, given `stages/1-intake.md`'s block mixes three legs? | The tool owns the **precedence** leg and the **all-pushed short-circuit**; the remote-seed leg (`git fetch` / `git ls-remote`) stays in the stage doc, delegating to the already-tested `tools/max-pushed-slice.sh` **[VERIFIED]**. This keeps the bare-remote fixture — named MISSING in the ticket's own evidence and absent from its scope — out of this PR. The stage doc is rewritten to invoke the tool (the `max-pushed-slice.sh` precedent), so no second copy of the rule survives and no `scripts/lockstep-manifest.tsv` **[VERIFIED]** row is needed. | codebase-derived |
| D-4 | Can the tool take `max-pushed` as a plain argument? | Not without changing production behavior: the stage doc computes `MAX_N` only inside the `else` branch, so a required argument would force a network round-trip on every stacked resume even when the persisted value wins. The tool instead emits a **verdict line** (`persisted` \| `seed` \| `all-pushed` \| `need-max-pushed`) mirroring `tools/slice-scope.sh` **[VERIFIED]**, and the caller supplies `--max-pushed` on a second call only when the first returns `need-max-pushed`. Semantics preserved exactly. | codebase-derived |
| D-5 | AC-3 says "a terminal write" without naming a state — is a per-repo stage-8 write enough? | No; that reading is satisfied by the per-tool coverage that already exists (`stage7-perrepo-checkpoint-selftest.sh` / `stage8-perrepo-review-selftest.sh` **[VERIFIED]**), so the AC would pass while leaving its own target gap open. Binding reading: top-level `status: "completed"` via `mark-completed`. Verified viable — `set-stage` stage 8 accepts a `crossBoundaryReviews`/`skippedReviews` entry for both its round-count and its review-lead skill-load gates, and `mark-completed` is topology-agnostic (stages 1–9 complete + eval + report). | codebase-derived |
| D-6 | Does the boundary list ship as one list? | Two labeled groups. "Out of reach by contract" (design mode, stage 10, the stacked-prs terminal leg blocked on #211) versus "uncovered, tracked". A flat list lets the next reach audit diff a clean header and read deferred debt as deliberate exclusion — the exact failure the header exists to prevent. | codebase-derived |

## Affected files

- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` **[VERIFIED]** — header boundary list; four new scenario blocks.
- `plugins/dev-pipeline/skills/run/tools/start-slice.sh` **[NEW]** — the extracted precedence tool.
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` **[VERIFIED]** — slice-derivation pre-check block rewired to invoke the tool.
- `docs/plans/acme-216.md` **[NEW]** — this plan.

## Reuse inventory

- `plugins/dev-pipeline/skills/run/scenario-lib.sh` **[VERIFIED]** — `reset_state`, `sct` / `sct_rc` / `sct_err`, `complete_stage`, `write_report`, `write_eval`, `write_verify_sidecar` (its `$2` repo arg serves the pair scenario), `VALID_PAYLOAD`.
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` **[VERIFIED]** — the yarn PATH-shim + synthetic-repo + config-fixture technique the circuit-breaker scenario reproduces (a fixture recipe, not production logic — no mirror-harness concern).
- `plugins/dev-pipeline/skills/run/tools/max-pushed-slice.sh` **[VERIFIED]** — stays the seed-leg derivation; the new tool does not absorb it.
- `plugins/dev-pipeline/skills/run/tools/slice-scope.sh` **[VERIFIED]** — the verdict-line-on-stdout convention `start-slice.sh` copies.

No new shared helper is introduced.

## Implementation steps

1. **`tools/start-slice.sh` [NEW].** `start-slice.sh <state-path> <total-slices> [--max-pushed N]`. Reads `.currentSlice` from the state file. Emits verdict on line 1, `START_SLICE` on line 2 where applicable:
   - non-null `currentSlice` → `persisted` + that value (precedence — never consults `--max-pushed`);
   - else no `--max-pushed` → `need-max-pushed` (the caller's signal to do the remote derivation);
   - else `max-pushed >= total-slices` → `all-pushed` (no value line);
   - else → `seed` + `max-pushed + 1`.

   Exit 0 on any verdict; exit 2 on usage/IO (missing state file, non-integer argument), matching `slice-scope.sh`.
2. **Rewire `stages/1-intake.md`.** Replace the precedence/short-circuit lines of the slice-derivation pre-check with the two-call invocation from D-4, keeping `git fetch` + `git ls-remote` + `max-pushed-slice.sh` in the doc as the seed leg. The `all-pushed` verdict keeps its existing "nothing to do" stop.
3. **AC-5 scenario.** Drive `start-slice.sh` for all four verdicts against real state files written by `statectl`: persisted wins (even with a contradicting `--max-pushed`, which is the precedence assertion proper), `need-max-pushed`, `seed`, `all-pushed`. Add the non-vacuity leg: with `currentSlice` deleted, the same call must NOT return `persisted`.
4. **AC-1 circuit-breaker scenario.** Build the fixture (synthetic git repo, `yarn` PATH shim driven by a `FAIL_TEST` marker, monorepo config fixture, state seeded with an absolute `worktreePath` via raw `jq` as `verifyctl-selftest.sh` does). Then, per D-1/D-2: commit a non-inert change and run `verifyctl.sh run` → `TEST_FAILURE` charged to 1; fix-commit + run → 2; fix-commit + run → exit 4 `budget-exhausted`; fix-commit + run → exit 4 again, the second consecutive exhaustion with no clean run between. Mark stage 6 started, then `mark-failed --reason approach-failure-circuit-breaker --stage 6` composed via `build-failure-context`, and assert terminal `status: failed`, the recorded reason, and `stages."6".status == "failed"`. Non-vacuity: with the marker cleared, the same fixture must not produce exit 4. The block's comment states that the breaker decision is agent-prose and that what is asserted is its state shadow.
5. **AC-2 exhausted-review scenario.** Full green run through stage 7, then stage 8 driven manually with `review-rounds --set 3 --exhausted` (plus the skill-load and comment receipts `complete_stage` would have planted), stage 9, report + eval, and `mark-completed` **accepted** with `status: completed` — proving the terminal gates do not reject a review-exhausted run. Non-vacuity: the same run with stage 9 left incomplete is refused.
6. **AC-3 be-fe-pair scenario.** Seed `targetRepos` and per-repo worktrees, walk stages 1–5, drive stage 6 with a per-repo `verify-summary-set --repo` and a per-repo sidecar for **every** target (the gate iterates `targetRepos`), write a per-repo stage-7 checkpoint via `build-checkpoint-7-perrepo`, satisfy stage 8 through the secondary repo's `cross-boundary-review-add` / `skipped-review-add` escape hatch, complete stage 9, and assert `mark-completed` accepted with top-level `status: completed` (D-5). Non-vacuity: drop one target's sidecar and stage 6 must not complete.
7. **AC-4 header boundary list.** Extend the header with the two labeled groups from D-6, naming the #211 dependency for the stacked-prs terminal leg.
8. **Commit** with a `Changelog:` trailer (`CLAUDE.md` requires one on every `plugins/**` PR). Verb `test:` → patch bump.

## Test strategy

Verify-after: this ticket *is* test infrastructure, so the deliverable and its verification are the same artifact — the new scenarios must be green, and each carries a **non-vacuity leg** proving it can still fail (the harness's existing `(ns3)`/`(ns4)` posture, and the property whose absence is how #204 stayed green).

Bash 3.2 compatibility binds every new scenario, not only AC-1 (the macOS CI lane runs all selftests): no associative arrays, no `local -n`, no `mapfile`.

No unit-test surface: this repo configures `unitTestScope: null`, so there is no mutation surface and the gate skips.

AC-4 is verified by diff review, not an automated check — its deliverable is header prose, and this repo bans prose-presence guards outright.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Circuit-breaker scenario reaches terminal `failed` via the composed chain | 4 | `scenario-liveness-selftest.sh` circuit-breaker block (AC-1), incl. non-vacuity |
| AC-2 | Exhausted-review scenario reaches terminal `completed` through stage 9 | 5 | `scenario-liveness-selftest.sh` exhausted-review block (AC-2), incl. non-vacuity |
| AC-3 | be-fe-pair scenario reaches a terminal write via per-repo stage-7/8 state | 6 | `scenario-liveness-selftest.sh` be-fe-pair block (AC-3), incl. non-vacuity |
| AC-4 | Header enumerates out-of-reach paths incl. the #211 dependency | 7 | — no test (infra-only) |
| AC-5 | Persisted-currentSlice precedence driven through the extracted tool | 1, 2, 3 | `scenario-liveness-selftest.sh` start-slice block (AC-5), incl. non-vacuity |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh
```

## Risks / rollback notes

- **The circuit-breaker fixture is the heaviest addition** — it runs real `verifyctl` against a synthetic repo, so it is the most likely source of a slow or platform-sensitive case. Mitigation: reuse `verifyctl-selftest.sh`'s proven shim shape verbatim rather than inventing one; the shim never runs a real suite.
- **`stages/1-intake.md` is the only production edit.** If the rewiring is wrong, stacked-PR slice derivation breaks. Mitigation: the tool's four verdicts are driven by the AC-5 scenario, and the seed leg it delegates to is unchanged and already tested.
- Rollback is per-commit; no migration, no state-schema change, no new `failureContext.reason`.

## Out-of-scope

- The **stacked-prs terminal leg** — blocked on #211's per-slice stage machine (the ticket is explicit that faking it is not acceptable). Recorded in the header per AC-4.
- A **breaker-predicate tool** and any new state field representing "no clean run in between" (D-1) — a product change.
- The **bare-remote fixture** (`git init --bare` + pushed slice branches) for the seed leg (D-3).
- The **Workflow `.mjs` runtime shim**, the `gh` PATH shim, and the remaining canned-fixture inventory from the ticket's evidence — separate items of #213.

Unverified references: none.
