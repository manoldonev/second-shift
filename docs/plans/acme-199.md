# Plan — #199: `mark-completed` forces `implementation_resilience: N/A` on an inert-lane run

## Context / problem framing

`statectl mark-completed` already refuses a terminal write unless the Post-Run Eval file exists, is plausible, and scores exactly the five locked criteria with `PASS|FAIL|N/A` values (`require_eval_file`, `plugins/dev-pipeline/skills/run/statectl.sh:317`). It does **not** cross-check any score against the run's recorded evidence, so an inert-lane run (no verifying test lane ran) can self-score `implementation_resilience: PASS` when the criterion's letter mandates `N/A`. `N/A` is excluded from the pass-rate denominator; a generous `PASS` inflates both numerator and denominator and distorts the optimization loop's cross-run pass rate. This is the one criterion whose generosity is mechanically detectable — the state file already carries whether the resilience circuit-breaker was ever exercised.

## Assumptions

- The eval file has already passed the existing shape gate by the time the new check runs, so `.criteria.implementation_resilience` is present and is one of `PASS|FAIL|N/A`.
- A completed run necessarily has `verifySummary` set (Stage-6 completion precondition), so at `mark-completed` time it is either an object (a real SUITE lane) or a non-empty skip string (inert / opt-out / when-gated miss); it is never absent on a valid non-`--force` completion.
- `TEST_FAILURE` is charged exclusively by verifyctl into `verifyAttempts` (flat) or `worktrees.<id>.verifyAttempts` (be-fe-pair).

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What discriminates an inert lane from a suite lane? | `verifySummary | type == "string"` is inert (covers all three skip-string forms: inert-diff, `allowUnverified` opt-out, when-gated miss); `type == "object"` is suite (an object necessarily passed the Stage-6 content gate, so it always has a verifying lane). Do **not** match the literal inert-diff string. | codebase-derived (state-schema.md:109; spec-reviewer finding conf 85) |
| D-2 | Cover be-fe-pair (per-repo `worktrees.<id>.*`) or defer it? | Cover. The gate reads a **union** of flat + per-repo `verifySummary`/`verifyAttempts`, treating the run as inert only when no suite-object and no `TEST_FAILURE` exist anywhere. Strict superset of AC-1/AC-2 — no suite run regresses — and avoids a silent no-op hole on multi-repo runs. | codebase-derived (statectl.sh:434, 986; spec-reviewer finding conf 82) |
| D-3 | Exact `TEST_FAILURE`-present test? | `(.verifyAttempts.TEST_FAILURE // 0) > 0` (key-absent OR zero both read as "not charged"), applied per-field in the union. | codebase-derived (statectl.sh:997; spec-reviewer finding conf 80) |
| D-4 | Does the new check honor `--force`? | Yes. It sits after the criteria-shape check inside `require_eval_file`, which returns early under `--force` (statectl.sh:327), so the new block is naturally `--force`-bypassed — same crash-recovery escape the shape check has. | codebase-derived (statectl.sh:302-327 comment block) |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — extend `require_eval_file()` with the inert-PASS refusal (no new function).
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — add AC-3 coverage (refused inert-PASS; accepted suite cases).

## Reuse inventory

- `require_eval_file()` — the existing `mark-completed` eval gate; the only choke point that reads eval criteria values. Extend it in place.
- `state` / `eval_file` locals already resolved inside `require_eval_file` (statectl.sh:319-322) — reused; the new jq reads the state file at `$state`.
- `die` + `EXIT_CODE=1` fail-closed idiom — reused verbatim for the refusal.
- selftest `complete_stage` / `write_eval` helpers — reused; new cases override Stage-6 `verifySummary` and write a `PASS`-scored eval.
- No new helpers introduced.

## Implementation steps

1. **Read the state evidence discriminator.** Inside `require_eval_file()`, after the criteria-shape check (statectl.sh:348), read `implementation_resilience` from `$eval_file`.
2. **Add the inert-PASS refusal `[NEW]`.** When the score is `PASS`, run one `jq -e` over `$state` computing `inert = (any suite-object anywhere OR any TEST_FAILURE anywhere) | not`, unioning `.verifySummary`/`.verifyAttempts` with every `.worktrees[].verifySummary`/`.worktrees[].verifyAttempts`. If inert, `EXIT_CODE=1 die` naming `implementation_resilience` and the required `N/A` (and citing `eval-criteria.md`, `--force` for crash-recovery). `FAIL`/`N/A` and all suite runs fall through untouched.
3. **Add selftest cases `[NEW]`.** In `statectl-selftest.sh`: (a) a run with an inert-string `verifySummary` + no `TEST_FAILURE` + `PASS` score → `mark-completed` rejected, message names the criterion, status stays non-completed; (b) a suite-object `verifySummary` + `PASS` → accepted; (c) an inert-string `verifySummary` but a `TEST_FAILURE` charged + `PASS` → accepted (AC-2 `TEST_FAILURE` branch).

## Test strategy

Verify-after (infra/shell change — no product runtime). Coverage is added to `statectl-selftest.sh` (the paired selftest CI discovers by glob). No `unitTestScope` is configured for this repo, so there is no TS mutation surface — `unitTestSurface.action: skip`.

- Refused inert-PASS case exercises AC-1 (the new die path).
- Suite-object accepted + inert-with-`TEST_FAILURE` accepted cases exercise AC-2 (both unaffected branches).
- Existing `mc1` happy path (suite object, `N/A` score) must still pass (regression guard).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Refuse inert-lane `PASS`, name criterion + required `N/A` | Step 2 | `(mc-ir1)` inert-string + no TEST_FAILURE + PASS → rejected, message names criterion |
| AC-2 | Suite-lane (object verifySummary OR any TEST_FAILURE) unaffected | Step 2 | `(mc-ir2)` suite-object + PASS → accepted; `(mc-ir3)` inert-string + TEST_FAILURE + PASS → accepted |
| AC-3 | `statectl-selftest.sh` covers refused + accepted cases | Step 3 | `(mc-ir1)`, `(mc-ir2)`, `(mc-ir3)` |

## Verification commands

```bash
# from repo root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
env SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/statectl-selftest.sh
```

## Risks / rollback notes

- **Over-blocking a legitimate suite run** — mitigated by D-1 (`type == "object"` ⇒ suite) and D-2/D-3 union (any TEST_FAILURE ⇒ suite). The `mc1` regression case guards this.
- **`--force` crash-recovery** — the check is bypassed under `--force` (D-4), so a resumed older-era terminalization is not re-gated.
- Rollback: revert the two-file diff; the gate is purely additive to `require_eval_file`.

## Out-of-scope

- The other four eval criteria (not mechanically detectable from state shape — stay retro-audited).
- Editing `eval-criteria.md` (LOCKED).
- Constraining the `FAIL` case (left reachable and defensive; only `PASS→N/A` is constrained).

Unverified references: none — every path/function above was read in-repo.
