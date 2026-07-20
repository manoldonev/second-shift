# Plan — #156: plan-lint gates Decision Ledger provenance

## Context / problem framing

In run #110's crash-recovery resume, a Decision Ledger row was authored with provenance `user-delegated` in a fully autonomous run — no human present, no backing `.claude/pipeline-state/110-ledger.md`. The retro classified it fabrication-class: a provenance value asserting a human decision that never happened. It survived `plan-lint`, `plan-review`, and the run's own deviations ledger, caught only by the retro one run too late.

The contract already exists in prose (pipeline-retro Step 3 item 8): in-pipeline plans may carry only `codebase-derived` / `deferred` provenance unless a pre-flight ledger file backs the human-attributed rows. This ticket mechanizes that prose into the existing Stage-4 mechanical gate (`plan-lint.sh`), turning the fabrication into a hard stop.

## Assumptions

- Stage 4 always invokes `plan-lint.sh` with the state-path argument (`plugins/dev-pipeline/skills/run/stages/4-plan-review.md` passes `"$(statectl.sh state-path "$ISSUE_NUMBER")"`) — verified. The no-state invocation is the selftest / ad-hoc case.
- The backing ledger file `{issue}-ledger.md` is the sibling of the state file in `.claude/pipeline-state/`, keyed by the same issue number, in the MAIN repo (`plugins/dev-pipeline/skills/run/stages/3-write-plan.md` line 28) — verified: `statectl state-path 156` → `<main>/.claude/pipeline-state/156.json`.
- The Decision Ledger table shape is `| ID | Decision | Resolution | Provenance |` (4 columns, provenance last), provenance from the closed enum `user-answered | user-delegated | codebase-derived | deferred` (`plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md`) — verified.

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-A | Is this an extension of existing ledger parsing? | No — `plan-lint.sh` today only greps for the `## Decision Ledger` heading (advisory WARN); it does not parse `\| D-n \|` rows. This adds genuinely new row-parsing, reusing the pipe-mask + `trim()` + provenance-cell idiom from `ledger-lint.sh`. | codebase-derived |
| D-B | How does `plan-lint.sh` locate `{issue}-ledger.md`? | Derive it from the already-passed `<state-path>`: `dirname(state)/$(basename state .json)-ledger.md`. No new argument, no Stage-4/3 call-site change — `state-path` is already the main-repo sibling path. | codebase-derived |
| D-C | Behavior when human-attributed rows are present but no `<state-path>` is passed (degraded/resume path)? | Fail closed — the #110 event was a crash-recovery resume, so an unresolvable-ledger case must FAIL, not silently no-op. | codebase-derived |
| D-D | Does the ledger become a mandated (hard-gated) section? | No — a plan that omits the ledger or uses the explicit-empty form still passes with at most the existing advisory WARN. The new hard-FAIL fires only on a present human-attributed provenance value lacking the backing file. | codebase-derived |
| D-E | How is provenance-enum drift across `plan-lint.sh` and `ledger-lint.sh` prevented? | The new human-attributed subset carries a mirror marker referencing the `interviewing-baseline` canonical enum (same convention as `ledger-lint.sh`'s `PROVENANCE_ENUM` comment), noting the #147 sync obligation. | codebase-derived |
| D-F | Does the check verify the ledger file actually backs the specific row? | No — existence-only, per the issue AC-2. Content verification is out of scope for this rung-2 mechanical gate. | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — add Check 4 (Decision Ledger provenance legality).
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` — add cases for AC-1/2/3, apostrophe-safe ledger parsing, and the fail-closed no-state case.

No new files. No Stage-4/Stage-3 call-site changes (D-B).

## Reuse inventory

- `trim()` (`plan-lint.sh` line 43) — quoting-safe whitespace trim; reuse for ledger cells. Verified.
- `violate()` (`plan-lint.sh` line 40) — stderr + `VIOLATIONS++` accumulator; reuse for the new hard-FAIL. Verified.
- Pipe-masking + `IFS='|' read -r -a cells` split idiom (`plan-lint.sh` Check 2, lines 88–95) — reuse verbatim for `| D-n |` rows. Verified.
- `| D-n |` anchored row grep `^\|[[:space:]]*D-[0-9]+[[:space:]]*\|` and 5–6 cell-count shape (`ledger-lint.sh` lines 55–66) — mirror for row detection. Verified.

No new helpers introduced.

Unverified references: none.

## Implementation steps

1. In `plan-lint.sh`, after Check 3 (the 1:1 snapshot check, line ~138) and before the existing advisory Decision-Ledger WARN (line ~140), add **Check 4: Decision Ledger provenance legality**:
   - Declare the human-attributed subset with a mirror marker: `HUMAN_PROVENANCE='user-answered|user-delegated'` (`# mirror of interviewing-baseline provenance enum — the human-attributed subset; keep in lockstep, see #147`).
   - Resolve the backing ledger path from `$STATE` when present: `LEDGER_FILE="$(dirname "$STATE")/$(basename "$STATE" .json)-ledger.md"`; empty when no state arg.
   - Scan `| D-n |` rows with the same anchored grep + pipe-mask + `trim()` idiom; extract `id` (`cells[1]`) and `provenance` (`cells[4]`); collect ids whose provenance matches `HUMAN_PROVENANCE`. Skip malformed rows (cell count outside 5–6) — structural ledger checks are `ledger-lint.sh`'s job.
   - If any human-attributed rows exist:
     - state present + `LEDGER_FILE` exists → pass;
     - state present + `LEDGER_FILE` absent → `violate` naming the row id(s) and the missing `$LEDGER_FILE`;
     - no state arg → `violate` (fail-closed) naming the row id(s) and that the ledger context is unresolvable.
2. In `plan-lint-selftest.sh`, add the Decision-Ledger-provenance section (build fixtures inline in `$TMP`, mirroring the existing mutant style — copy `valid-plan.md` + append a `## Decision Ledger` table; copy `valid-state.json` to `$TMP/156.json` so the sibling ledger resolves to `$TMP/156-ledger.md`):
   - AC-1 fail case; AC-2 pass-with-ledger case; AC-3 codebase-derived/deferred-only pass case; apostrophe-in-ledger-cell pass case; fail-closed no-state case; and an explicit-empty-form pass case (invariant guard).

## Test strategy

Verify-after (this is tooling/infra with no `apps/api` behavior surface; the repo configures no `unitTestScope`). The change is exercised entirely through `plan-lint-selftest.sh` (the repo's `*-selftest.sh` glob convention, discovered by CI). New cases assert exit code + named-violation substrings, following the existing `lint_rc` / `grep`-the-stderr pattern.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | FAIL on human-attributed provenance with no `{issue}-ledger.md`, naming row(s) | 1, 2 | `plan-lint-selftest.sh` (pl-n) user-delegated row + state, no sibling ledger → rc=1, err names `D-1` + missing path (AC-1) |
| AC-2 | Same plan passes when `{issue}-ledger.md` exists | 1, 2 | `plan-lint-selftest.sh` (pl-o) same plan + sibling ledger present → rc=0 (AC-2) |
| AC-3 | `codebase-derived`/`deferred`-only plans unaffected | 1, 2 | `plan-lint-selftest.sh` (pl-p) ledger with only codebase-derived/deferred rows → rc=0 (AC-3) |
| AC-4 | Selftest covers all three + apostrophe-safe ledger-cell parsing | 2 | `plan-lint-selftest.sh` (pl-r) apostrophe in a ledger cell + backing ledger → rc=0, parsing survives (AC-4); pl-n/pl-o/pl-p above |

## Verification commands

```bash
# from the repo root of the worktree
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
bash plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Risk:** promoting the ledger into the hard-gated set, false-aborting legitimate autonomous ledger-less runs. **Mitigation:** D-D — Check 4 fires only on a present human-attributed provenance value; the explicit-empty-form / missing-section invariant is covered by a dedicated selftest case, and existing pl-k/pl-l stay green.
- **Risk:** enum drift with `ledger-lint.sh` (#147). **Mitigation:** D-E mirror marker.
- **Rollback:** revert the two files; the check is additive and self-contained.

## Out-of-scope

- Verifying the ledger file's contents back the specific row (D-F — existence-only).
- Changes to `ledger-lint.sh`, the Stage-3/Stage-4 call sites, or the provenance enum itself.
- #147's new provenance value (orthogonal; when it lands it joins `HUMAN_PROVENANCE` here).
