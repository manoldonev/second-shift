# Plan: Pin Stage-1 reads to origin/<baseBranch>; downgrade the non-main-base judgment gate (#59)

## Context

Autonomous dev-pipeline runs currently reject when the main checkout sits on a branch other than the configured `baseBranch`. Intake grounding (issue #59, revised body) established that this "gate" is not a coded conditional: `non-main-base-autonomous` exists as a generated enum value (`plugins/dev-pipeline/skills/run/statectl.sh:377`), a reason-index row (`plugins/dev-pipeline/skills/run/state-schema.md:189`), and a selftest case (`plugins/dev-pipeline/skills/run/statectl-selftest.sh:359-363`); the rejection is LLM-judgment behavior driven by the SKILL.md Dynamic Context snapshot (`plugins/dev-pipeline/skills/run/SKILL.md:334-345`). The real hazard is narrower: Stage-1 intake reads (spec-reviewer, codebase-explorer, referenced docs) see whatever is checked out — including uncommitted edits — while Stage 2 cuts the work branch from `origin/<base>` (`plugins/dev-pipeline/skills/run/stages/2-worktree.md:151`). This plan pins the Stage-1 read surface to `origin/<base>` and converts the branch-mismatch reject into the predicate set decided at intake (silent / WARN / fail-closed).

Run `2026-07-12T174135Z-Mac-9f9e387b` (this issue) is the working precedent: a detached worktree + a pinned-read instruction prepended to both intake dispatch prompts, honored by both sub-agents.

## Assumptions

- The reason value `non-main-base-autonomous` is retained verbatim (AC-5); only its documented trigger semantics change. `tools/gen-statectl-validators.sh` regeneration is therefore a byte-identical no-op for `statectl.sh`.
- The prose contract in the skill files is the enforcement mechanism (this pipeline's gates are model-executed); no new shell helper is required for the gate itself.
- Single-repo (`standalone`/`monorepo`) topologies are the first cut; `be-fe-pair` pins one worktree per target repo using the same idiom and is explicitly deferred (see Out-of-scope).

## Decision Ledger

| # | Decision | Choice | Provenance | Rationale |
|---|----------|--------|------------|-----------|
| 1 | Pin mechanism | Detached worktree + `readRoot` arg threaded into dispatch prompts | codebase-derived | Sub-agents Grep/Glob a real tree; `git show` cannot serve enumeration. Reuses Stage 2's fetch-then-pin idiom (`stages/2-worktree.md:151`). Validated live in run `2026-07-12T174135Z-Mac-9f9e387b`. |
| 2 | Enum value fate | Keep `non-main-base-autonomous`; update trigger text only | codebase-derived | Renaming forces the generate-and-diff cycle (`tools/gen-statectl-validators.sh`, selftest drift check) for zero behavioral gain. |
| 3 | WARN predicates | Clean non-base branch → silent; dirty tree → WARN + proceed; pin unestablishable → fail closed | codebase-derived | Matches the issue's observed-instance analysis; avoids WARN noise on idle machines. |
| 4 | Pin-worktree teardown | Best-effort immediately after Stage 1 completes; guaranteed at Stage 10 cleanup | codebase-derived | Mirrors the existing persisted-`worktreePath` removal contract in `stages/10-cleanup.md`. |
| 5 | be-fe-pair pinning | Deferred to the dual-target program (#48 series) | deferred | Dual-target Stage-3..7 work is mid-flight; adding per-repo pins now would collide with it. |

## Affected files

All paths repo-relative; all exist at `origin/main` @ `2a9c962` unless tagged `[NEW]`.

1. `plugins/dev-pipeline/skills/run/workflows/intake-review.mjs` — add `readRoot` arg + prompt prefix.
2. `plugins/dev-pipeline/skills/run/stages/1-intake.md` — new Step 1.P (pin the read surface) + predicate prose.
3. `plugins/dev-pipeline/skills/run/SKILL.md` — Dynamic Context posture paragraph (WARN replaces reject).
4. `plugins/dev-pipeline/skills/run/state-schema.md` — `non-main-base-autonomous` trigger-text update (line 189 row).
5. `plugins/dev-pipeline/skills/run/eval-criteria.md` — criterion 1 dirty-base wording (lines 19-21) → pin/WARN semantics.
6. `plugins/dev-pipeline/skills/run/stages/10-cleanup.md` — remove the intake pin worktree alongside the work worktree.
7. `plugins/dev-pipeline/skills/run/tools/intake-readroot-selftest.sh` [NEW] — green-gate regression test for the `readRoot` wiring.
8. `CHANGELOG.md` — user-facing entry under Unreleased.
9. `plugins/dev-pipeline/.claude-plugin/plugin.json` — version bump (re-derive latest at bump time per repo discipline).

## Reuse inventory

- Fetch-then-pin idiom: `BASE_BRANCH="origin/$BASE_BRANCH_CFG"` remap in `stages/2-worktree.md:149-152` — Step 1.P reuses it verbatim (grep-verified).
- Prompt-assembly seam: `docsNote` prefix pattern in `intake-review.mjs:139-141` — `readRoot` note follows the same shape (grep-verified).
- Fail-fast write: `statectl.sh mark-failed --reason ... --json "$(statectl.sh build-failure-context ...)"` call shape from `stages/1-intake.md` Step 1.T (grep-verified).
- Selftest harness conventions: `*-selftest.sh` discovery via the config `commands.second-shift.test` find expression; `statectl-selftest.sh` as the style reference (grep-verified).
- No new helpers beyond the `[NEW]` selftest above — no existing equivalent found (`grep -r readroot plugins/` empty at base).

## Implementation steps

1. **`intake-review.mjs`:** destructure `readRoot = ''` from args (alongside `issueBody`, `intake-review.mjs:119-125`); build `readRootNote` (empty when unset) instructing agents to perform ALL codebase reads under `readRoot` and never the main checkout; prefix both `DISPATCH` prompts (`intake-review.mjs:174,186`) with it, ahead of the existing text.
2. **`stages/1-intake.md`:** add **Step 1.P — Pin the Stage-1 read surface** between Step 1.A (claim) and Step 1.B (intake): `git fetch origin <base>`; `git worktree add --detach <worktreesDir>/intake-pin-<issue> origin/<base>` (worktreesDir = config `topology.repos.<host>.worktreesDir`); on ANY pin failure → `mark-failed --reason non-main-base-autonomous --json "$(build-failure-context --reason non-main-base-autonomous --kv pinError=...)"` and stop (interactive mode prompts instead); pass the absolute pin path as `readRoot` in the intake Workflow args; referenced-doc reads resolve under it; best-effort `git worktree remove` after the Stage-1 completion write. Document the predicates: clean non-base branch → silent; dirty tree → WARN ("a human appears to be mid-work in this checkout") surfaced in the run report, then proceed.
3. **`SKILL.md` Dynamic Context (line 334):** replace the implicit reject expectation with the pin posture — a non-base current branch is NOT a reject once Step 1.P pins reads; dirty tree → WARN + proceed; only a failed pin fails closed.
4. **`state-schema.md:189`:** trigger text → "Stage-1 read pin to origin/<base> could not be established in autonomous mode (fetch or pin-worktree creation failed). Interactive mode offers an escape hatch."
5. **`eval-criteria.md:19-21`:** PASS = run pinned Stage-1 reads to the configured base (or surfaced a pin failure); dirty tree handled by WARN-and-proceed; FAIL = intake read an unpinned non-base tree without the WARN/fail-closed posture firing.
6. **`stages/10-cleanup.md`:** after the work-worktree removal, remove `<worktreesDir>/intake-pin-<issue>` if present (`git worktree remove --force ... 2>/dev/null || true`).
7. **`tools/intake-readroot-selftest.sh` [NEW]:** assert the load-bearing tokens exist (`readRoot` destructure, prompt-prefix wiring into both DISPATCH prompts); assert `state-schema.md` still carries the `non-main-base-autonomous` row (AC-5 guard); assert the Step 1.P / Stage-10 prose anchors. Follows `statectl-selftest.sh` conventions; auto-discovered by the green-gate find. *(Deviation from the drafted plan, disclosed: the originally-planned `node --check` assertion is impossible — Workflow scripts execute in the runtime's async context and carry top-level `return` statements, a SyntaxError to node's module parser by design; grep-token assertions are the correct technique, per `null-reviewer-selftest.mjs` precedent.)*
8. **`CHANGELOG.md` + `plugin.json`:** Unreleased entry; bump dev-pipeline patch/minor after re-deriving the latest released version.
9. Run the full green gate (shellcheck lint + all selftests) per Verification commands.

## Test strategy

Verify-after (infra/contract change — no runtime product surface):

- New `intake-readroot-selftest.sh` is the mutation-resistant regression: deleting the `readRoot` destructure, dropping the prefix from either prompt, or retiring the enum row each fails a distinct assertion.
- `statectl-selftest.sh` (existing, unmodified) proves AC-5's enum retention + generator drift check.
- `shellcheck` over the new selftest. (No `node --check` on the `.mjs` — see Verification commands note.)
- Prose-contract ACs (AC-1, AC-2) are model-behavior contracts scored by `eval-criteria.md` on real runs — no in-repo test can execute them.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
|-------|-------------------|---------|---------|
| AC-1 | Clean non-base branch proceeds silently once pinned | 2, 3 | — no test (non-functional) |
| AC-2 | Dirty tree → mid-work WARN, proceed | 2, 3, 5 | — no test (non-functional) |
| AC-3 | Pin unestablishable → fail closed with retained reason | 2, 4 | — no test (covered-by-selftest) |
| AC-4 | `readRoot` threaded through intake-review.mjs + documented pin lifecycle | 1, 2, 6 | intake-readroot-selftest.sh (AC-4) |
| AC-5 | Enum neither renamed nor retired; regeneration no-op | 4, 7 | statectl-selftest.sh drift check + intake-readroot-selftest.sh row assertion (AC-5) |

## Verification commands

```bash
# in the worktree root
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# NOTE: no `node --check` on intake-review.mjs — Workflow scripts carry top-level `return`
# (async-context execution) and are not standalone-parsable; the selftest's token asserts cover the seam.
bash plugins/dev-pipeline/skills/run/tools/gen-statectl-validators.sh > /tmp/statectl.regen && diff /tmp/statectl.regen plugins/dev-pipeline/skills/run/statectl.sh && rm /tmp/statectl.regen
```

## Risks

- **Prose-gate drift:** the WARN/silent predicates are model-executed; a future skill edit could silently re-tighten them. Mitigation: eval-criteria.md wording is the scored contract; pipeline-retro audits deviations.
- **Pin worktree leakage:** a crashed run leaves `intake-pin-<issue>` behind. Mitigation: Stage-10 removal + `git worktree prune` tolerance; the dir is namespaced per issue so a leak never corrupts another run.
- **Rollback:** revert the single PR; no state-file or enum migration is involved (AC-5 keeps the enum stable in both directions).

## Out-of-scope

- `be-fe-pair` per-target-repo pinning (deferred to the #48 dual-target program; Decision Ledger row 5).
- Renaming/retiring the `non-main-base-autonomous` enum value (rejected alternative in the issue).
- Any change to Stage 2's branch-creation pinning (already correct).
- Deterministic (shell-coded) gate enforcement — the gate remains a model-executed contract like the pipeline's other routing gates.

Unverified references: none.
