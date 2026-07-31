# Plan — #272: harness-corroborated stage preconditions

## Context / problem framing

`statectl`'s completion-evidence preconditions are **self-reported**: `stage_completion_preconditions()`
([`plugins/dev-pipeline/skills/run/statectl.sh`](../../plugins/dev-pipeline/skills/run/statectl.sh) — 17 legs
across stages 1–9) reads only fields the executing agent itself wrote via `skill-load-add`, `stage-file-read`,
and `review-rounds`. An agent that skips the mandated work and records the receipt anyway completes the stage.
`state-schema.md` already names the intended fix — "the session audit ledger … remains the independent
cross-check `pipeline-retro` Step 3 runs against it" — but that cross-check runs *after* the fact, not at the gate.

`audit-toolkit` 2.1.0 (shipped in marketplace v3.0.0) made the ledger usable as gate evidence: the hook
[`plugins/audit-toolkit/hooks/audit-tool-calls.sh`](../../plugins/audit-toolkit/hooks/audit-tool-calls.sh)
now records a per-tool `target` — the file path for `Read`, the qualified skill name for `Skill`, the
`scriptPath` for `Workflow`. This change moves that cross-check forward to the gate: before accepting a
stage-completion write, `statectl` verifies the claimed evidence against rows the **harness** wrote.

The self-reports stay as the fast local layer (epic #268 D-12). Corroboration is additive, fails **open**
when no ledger is resolvable (consumer-compat), and every fail-open is **visible** rather than silent — the
failure this issue exists to prevent.

## Assumptions

1. The ledger row schema is stable and lockstep-pinned
   ([`plugins/audit-toolkit/skills/audit/QUERIES.md`](../../plugins/audit-toolkit/skills/audit/QUERIES.md)
   `audit-row-fields`); this change reads it and never edits it.
2. `--arg target` in the hook always emits a string key, so current-hook rows carry `""` rather than an absent
   key; pre-2.1.0 rows omit it entirely. Both normalize to `""`.
3. `CLAUDE_CODE_SESSION_ID` equals the hook-written ledger filename stem. Verified live this run.
4. Ledger `ts` is second-precision ISO-8601 Z, so lexicographic comparison against state timestamps is sound.
5. No root-level `tools/` directory exists on `main` at `e0d2590`, so this branch carries **no** mutation
   baseline/catalog re-keying obligation. See Risks.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Precedence when several non-`corroborated` conditions hold in one write | Total order `waived` > `degraded` > `uncorroborated` > `corroborated`. The field must name the strongest departure from clean corroboration, and a fired-and-force-waived guard is a human bypass — the single most important thing for the report to surface. Resolves the intake spec review's only warning. | codebase-derived |
| D-2 | Scope of the stage-file leg | Every stage 1–9, mirroring `require_stage_file_receipt`'s own applicability, so corroboration covers exactly the members the receipt guard already scores. | codebase-derived |
| D-3 | Scope of the skill-load leg | Stages 1 and 8 only — the two stages whose preconditions mandate a named skill (`intake-toolkit:intake-orchestrator`, `review-toolkit:review-lead`). Other stages record no mandated load, so the leg is vacuous there by construction. | codebase-derived |
| D-4 | Tool interface shape | Verdict token on **stdout** (`vacuous`/`corroborated`/`degraded`/`refused`), detail on stderr, exit 0 for every verdict. Exit-code-encoded verdicts would collide with the `set -e` posture in `statectl` and make the four-way outcome awkward to test. | codebase-derived |
| D-5 | Ordering inside the tool | Count admissible rows **before** evaluating targets. `[] \| all(.target == "")` is `true` in jq, so an all-empty test evaluated first would report `degraded` on zero rows — failing open in exactly the fabricated-evidence case. | codebase-derived |
| D-6 | `stages/9-open-pr.md` in scope | The Scope list omitted it, but AC-10 requires non-`corroborated` values to reach the run report and the template carries no surface to write into. Added. | codebase-derived |
| D-7 | `AC-2b` absent from the traceability table | `statectl intake-brief` validates AC ids against `^AC-[0-9]+$` and `plan-lint.sh` keys rows on `AC-[0-9]+`; a sub-lettered id is unrepresentable in both. Its two D-14 arms are carried as named scope items under AC-1 and AC-2's rows, and covered by dedicated fixtures. | codebase-derived |
| D-8 | Per-reviewer identity in the Stage-8 legs | Deferred — the harness emits no per-agent dispatch row and anonymizes `subagent` on ~18% of rows. v1 corroborates at cardinality only. | deferred |

## Affected files/modules

**Created**

- `plugins/dev-pipeline/skills/run/tools/ledger-corroborate.sh` `[NEW]`
- `plugins/dev-pipeline/skills/run/tools/ledger-corroborate-selftest.sh` `[NEW]`
- `plugins/dev-pipeline/skills/run/tools/ledger-corroborate-fixtures/` `[NEW]` (fixture ledgers)

**Modified**

- [`plugins/dev-pipeline/skills/run/statectl.sh`](../../plugins/dev-pipeline/skills/run/statectl.sh) — ledger
  resolution, the four corroboration legs, the outcome carrier
- [`plugins/dev-pipeline/skills/run/statectl-selftest.sh`](../../plugins/dev-pipeline/skills/run/statectl-selftest.sh) — precondition + carrier cases
- [`plugins/dev-pipeline/skills/run/state-schema.md`](../../plugins/dev-pipeline/skills/run/state-schema.md) — `ledgerCorroboration` field, guard-id vocabulary, `Read`-tool constraint, `target` fact correction, session-record reconciliation
- [`plugins/dev-pipeline/skills/run/stages/1-intake.md`](../../plugins/dev-pipeline/skills/run/stages/1-intake.md) — `pipeline-session-add` call site
- [`plugins/dev-pipeline/skills/run/stages/9-open-pr.md`](../../plugins/dev-pipeline/skills/run/stages/9-open-pr.md) — report corroboration surface
- [`plugins/dev-pipeline/skills/run/cost-tracking-setup.md`](../../plugins/dev-pipeline/skills/run/cost-tracking-setup.md) — session-record reconciliation
- [`plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh`](../../plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh) — affected verdict paths

## Reuse inventory

Every entry grep-verified in the worktree:

- `guard_fire()` / `guards_settle()` / `apply_waivers()` (`statectl.sh:455`, `:459`, `:472`) — the new legs mint
  ids in the existing `completion-evidence:<N>.<leg>` namespace and inherit `waivers[]` + `--force` plumbing
  unchanged. No new bypass mechanism.
- `state_dir()` (`statectl.sh:126`) — its three-tier resolution (`STATECTL_STATE_DIR` → `SECOND_SHIFT_REPO_ROOT`
  → `git rev-parse --git-common-dir`) is the template the new ledger root mirrors.
- `require_stage_file_receipt()` (`statectl.sh:727`) — the stage-file corroboration leg reuses its applicability
  rule (`^N-` basename, "extra entries satisfy nothing") rather than inventing a second one.
- `atomic_write()` (`statectl.sh:401`) — the carrier rides the existing single write; no second write is added.
- `pipeline-session-add` (`statectl.sh:1338`) — already idempotent on session id, UUID-validating, and exempt
  from the terminal-state guard. The Stage-1 call site is a new *invocation*, not new code.
- Fixture-harness idiom from `predecessor-gate-selftest.sh` and `is-inert-diff-selftest.sh` — the new selftest
  follows their tempdir/assert shape.

New helpers introduced: `ledger_dir()`, `ledger_excerpt()` in `statectl.sh` `[NEW]`, and the
`ledger-corroborate.sh` script itself `[NEW]` — each confirmed to have no existing equivalent.

Unverified references: none.

## Implementation steps

1. **`ledger-corroborate.sh`** `[NEW]` — pure logic, stdin/env seam. Reads a JSONL ledger excerpt on **stdin**;
   takes `--class skill|stage-file|workflow|subagent-stop`, `--claims <json-array>`, `--since <ISO>` (omitted =
   windowless), `--min-count <n>`. Emits one verdict token on stdout.
   - Admissibility, per class: `skill` → `tool=="Skill"` and `(.subagent // "")==""`, windowed;
     `stage-file` → `tool=="Read"` and `(.subagent // "")==""`, **windowless** (D-18);
     `workflow` → `tool=="Workflow"` and `(.subagent // "")==""`, windowed;
     `subagent-stop` → `event=="SubagentStop"`, **no subagent constraint** (D-19), windowed.
   - Verdict order (D-5): claims empty → `vacuous`; else zero admissible rows → `refused`; else every admissible
     row's `(.target // "")` empty → `degraded`; else every claim matched → `corroborated`, otherwise `refused`.
   - Matching: `skill` exact equality on the qualified name; `stage-file` **basename equality** (not suffix —
     `x9-open-pr.md` must not satisfy a `9-open-pr.md` claim); `workflow` basename-or-name equals
     `code-review.mjs` or `code-review`, count `>= --min-count`; `subagent-stop` count `> 0`, no target match.
2. **`ledger-corroborate-selftest.sh`** `[NEW]` + fixture ledgers — the case list under Test strategy. Zero network.
3. **`ledger_dir()`** `[NEW]` in `statectl.sh` — three-tier, mirroring `state_dir()`: `$STATECTL_LEDGER_DIR`
   (fixture-only), else `$SECOND_SHIFT_REPO_ROOT`, else the `git rev-parse --git-common-dir`-derived main-checkout
   root, each suffixed `/.claude/audit`. Never the worktree — the hook writes to `CLAUDE_PROJECT_DIR` and sibling
   worktrees carry no `.claude/audit/`.
4. **`ledger_excerpt()`** `[NEW]` in `statectl.sh` — concatenates `<ledgerDir>/<sessionId>.jsonl` for each id in
   `.pipelineSessions[]`. Join is **only** through recorded session ids; no window-scan fallback. Unresolvable
   ledger dir, empty `pipelineSessions[]`, or no readable file → the D-2 fail-open.
5. **Corroboration legs** in `stage_completion_preconditions()` — fired **after** each stage's existing legs so
   current refusal messages stay byte-stable:
   - `completion-evidence:<N>.ledgerStageFile` (stages 1–9), claims = the `^N-` members of `stageFilesRead[]`
   - `completion-evidence:<N>.ledgerSkill` (stages 1, 8), claims = the mandated skill only
   - `completion-evidence:8.ledgerWorkflow`, `--min-count` = `codeReviewRounds`
   - `completion-evidence:8.ledgerSubagentStop`, cardinality `> 0`
   - The two Stage-8 legs are **vacuous** when `crossBoundaryReviews[]` or `skippedReviews[]` is non-empty,
     mirroring row 8's existing escape hatches.
   - On the fail-open path no leg fires and no refusal is possible.
6. **Outcome carrier** — a `LEDGER_CORROBORATION` shell global, seeded `corroborated`, downgraded by the D-1
   precedence as legs evaluate; set to `uncorroborated` on the fail-open. After `guards_settle "$force"`
   returns, if `GUARD_FIRED` holds any `completion-evidence:*.ledger*` id it becomes `waived`. The completed
   branch's existing jq bundle gains `.stages[$n].ledgerCorroboration = $lc` — the same atomic write, no second write.
7. **`stages/1-intake.md`** — add the `pipeline-session-add` call, `-n`-guarded on `CLAUDE_CODE_SESSION_ID`
   exactly as Stage 2's is, immediately after `statectl init` in Step 1.A and before the mark-started call.
   Without it the Stage-1 legs evaluate against an empty join set on every run.
8. **`state-schema.md`** — document `stages.N.ledgerCorroboration` and its four values; add the five new leg ids
   to the closed guard-id vocabulary (hand-maintained by that section's own rule); state the `Read`-tool
   constraint in the Stage-file read receipts stanza (prose only, no grep-guard); correct the existing claim that
   `Skill` rows carry the skill name in `target` to hold only for `audit-toolkit` >= 2.1.0; reconcile the stale
   "Stage 2 and the Stage-8 crash re-entry" session-record prose.
9. **`cost-tracking-setup.md`** — same session-record reconciliation, plus the new Stage-1 call site.
10. **`stages/9-open-pr.md`** — the run-report template gains a corroboration line listing every stage whose
    `ledgerCorroboration` is not `corroborated`; omitted entirely when all stages are clean.
11. **`statectl-selftest.sh`** — precondition cases per leg and carrier cases per arm, driven through
    `STATECTL_LEDGER_DIR`.
12. **`scenario-liveness-selftest.sh`** — extend the affected verdict paths so a composed completion reaches a
    terminal write with corroboration active.

## Test strategy

Verify-after for the doc reconciliations; test-first for the tool and the legs — the tool is pure logic over
fixture input, so its selftest is written before it.

`ledger-corroborate-selftest.sh` cases (fixture ledgers, zero network):

- corroborate-pass; refuse on zero rows **with a non-empty claim set**; **vacuous pass on an empty claim set**
- degrade on `>=1` row all-empty-or-absent target
- refuse on wrong target; refuse on out-of-window (windowed classes only)
- absent-key normalization; literal-`null` target normalization; `""` target
- path normalization across all three legitimate roots (plugin cache, worktree, main checkout)
- basename **equality**, proving `x9-open-pr.md` does not satisfy a `9-open-pr.md` claim
- subagent-row exclusion for Skill/Read/Workflow
- named-subagent `SubagentStop` rows **satisfy** the cardinality leg
- **pre-`startedAt` stage-file read corroborates** — the measured Stage-1 trap
- be-fe-pair vacuity of the Stage-8 legs

`statectl-selftest.sh` gains the precondition cases and `ledgerCorroboration` per arm, including `waived` on the
forced path and the D-1 precedence when `degraded` and `waived` co-occur. `scenario-liveness-selftest.sh`
extends the affected verdict paths per the tier map in [`docs/testing.md`](../testing.md).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Matching rows complete; mismatch/zero-rows refuses; `--force` waives and records `waived` | 1, 5, 6 | `ledger-corroborate-selftest` corroborate-pass + wrong-target refuse `(AC-1)`; `statectl-selftest` waived-path `(AC-1)` |
| AC-2 | No ledger / empty `pipelineSessions[]` / no session id completes as `uncorroborated` | 4, 6 | `statectl-selftest` fail-open arm `(AC-2)` |
| AC-3 | Stage-6 verify completion unchanged; no second gate | 5 | `statectl-selftest` stage-6 unchanged-legs assertion `(AC-3)` |
| AC-4 | Absolute/prefixed ledger paths corroborate bare-basename claims; absent `target` == empty | 1 | `ledger-corroborate-selftest` path-normalization + absent-key cases `(AC-4)` |
| AC-5 | Stage 1 records its session id, so its legs evaluate against a non-empty join set | 7 | `scenario-liveness-selftest` stage-1 corroborated path `(AC-5)` |
| AC-6 | A stage claiming no items of a class completes without refusal | 1, 5 | `ledger-corroborate-selftest` vacuous case `(AC-6)` |
| AC-7 | Non-empty `subagent` does not corroborate Skill/Read/Workflow; named `SubagentStop` does satisfy cardinality | 1 | `ledger-corroborate-selftest` subagent-exclusion + named-SubagentStop cases `(AC-7)` |
| AC-8 | Selftests and extended liveness scenarios pass; sweep green | 2, 11, 12 | full selftest sweep — see Verification commands `(AC-8)` |
| AC-9 | A pre-`startedAt` stage-file `Read` row corroborates | 1 | `ledger-corroborate-selftest` windowless-leg case `(AC-9)` |
| AC-10 | Every terminal outcome writes the carrier; non-`corroborated` reaches the run report | 6, 10 | `statectl-selftest` carrier-per-arm `(AC-10)` |

`AC-2b` carries no numeric id and so cannot key a row (D-7). Its two D-14 arms are covered by the zero-rows and
all-empty-target cases listed under AC-1 and AC-2 above, and its be-fe-pair vacuity clause by the vacuity case
listed under AC-7's leg.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
bash scripts/check-lockstep-pairs.sh
```

The selftest sweep runs **without** `SKIP_STRESS=1` — only CI's ubuntu lane exercises the stress legs, so a
local sweep that skips them under-verifies. `-P 4` is load-bearing (CLAUDE.md).

## Risks / rollback notes

- **Refusing genuine work.** The failure mode that killed rev 3's design. Mitigated structurally: the stage-file
  leg is windowless, the empty-claim set is vacuous, and every leg fails **open** when no ledger resolves. The
  `(AC-9)` fixture pins the measured trap so a future window re-introduction goes red.
- **Self-corroboration on this very run.** Adding a Stage-1 leg that this pipeline must itself satisfy means a
  bug refuses the run implementing it. The `--force` escape with a recorded waiver is the sanctioned recovery,
  and the shipped code is exercised only from the *installed cache*, not the worktree — this run's `statectl` is
  the 3.0.0 cache copy, so the branch cannot gate itself. Verified: the pipeline resolves helpers via the plugin
  cache path, never CWD-relative.
- **Same-session re-run residual.** A session is not run-scoped, so a re-run in the same terminal can be
  corroborated by the prior attempt's `Read` row. Accepted, inside the local-tamper limit #268 already states.
  Do not close it with a state-anchored lower bound — that recreates the refusal trap.
- **Rebase onto the mutation sweep.** `tools/mutation-baseline.tsv` and `tools/mutation-catalog.tsv` do not exist
  on `main` at `e0d2590` but are landing on another branch. If `main` advances past them before merge, editing
  `statectl.sh`'s guards re-keys its generic survivor ordinals and both files need re-baselining in the same diff
  (CLAUDE.md). Check at rebase time.
- **Rollback** is a clean revert: every leg is additive, the carrier is a new field no consumer requires, and no
  existing refusal message or guard id changes.

## Out-of-scope

- Per-reviewer identity in the Stage-8 legs (D-8 — deferred to #268 T2 rung 2).
- Stage-6 verify corroboration — the verifyctl attestation sidecar is the existing, stronger gate (AC-3 asserts
  it stays the sole instrument).
- Plan-artifact corroboration — no `planPath` state field exists to claim against.
- Any `QUERIES.md` edit; its row-schema block is lockstep-pinned.
- Version bumps and `CHANGELOG.md` — derived at release time, frozen in feature PRs (CLAUDE.md).
- The `intake-review.mjs` `referencedDocs` content gap surfaced at intake — a separate issue.
