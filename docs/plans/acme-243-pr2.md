# Plan: per-stage evidence legs + stage-file receipts + waiver surfacing (#243, PR 2 of 2)

## Context

Slice 2 of the #243 stack, on top of PR 1's guard-predicate mechanism (branch base `claude/second-shift-243` @ 2d6b6e7). The §2 machinery exists; this slice makes stages 3/5/7/9 carry completion evidence on both tracker adapters (§1), adds the stage-file read receipts (§3), and finishes the waiver surfacing (report gate, PR-body flow docs, retro headline) plus the doc reconciliation the field's new load-bearing status forces. Every new leg is born as a `guard_fire` predicate with its `completion-evidence:<N>.<leg>` id — the shape PR 1 established.

Grounding is by named construct (function / case arm / heading), verified at `2d6b6e7`; line offsets are approximate and re-derived at edit time.

## Assumptions

- PR 1's contracts are fixed: `guard_fire "<id>" "<stage>" "<message>"` + `guards_settle` at the `set-stage` caller; the guard-id vocabulary lives in `state-schema.md`'s "Operator-authorized `--force`" section.
- AC-21 (usage header documents `pr-add --repo`) is **already satisfied on base** (#246) — this slice only re-verifies it; no edit.
- The intake decisions bind: `costBlockApplied` leg = recorded-non-null (`(.costBlockApplied // null) != null` — boolean `true` and every `skipped-*` string pass; only null/absent refuses); `reclaim-staleness` terminal-blocking posture is PR 1's and untouched here.
- The Stage-9 cost-block ordering contract ("MUST precede `set-stage 9 --status completed`") becomes prose in `stages/9-open-pr.md` mirroring the `pr-add` contract at `:172`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | `--force` regime in auto mode | Refused when resolved mode is `auto`; resolution ladder env-literal-if-set → state `.mode` → not-auto. Transport is STATE (`init --mode`, re-stamped on every init incl. existing-state — AC-25), not env export (harness Bash calls don't share env). Recovery = `DEV_PIPELINE_MODE=interactive` on the command itself. Semantics user-answered; transport codebase-derived (RUN_ID persistence pattern) | user-answered |
| D-2 | Stage-3 plan-path + designDriven `artifactPath` gates | Cut — Stage 4 transitively enforces both (`plan-lint.sh:66`; `statectl.sh:496-499`) | user-answered |
| D-3 | `--force-reason` trigger vs waiver-append trigger | Reason required whenever `--force` is passed (pre-dispatch scan in `main()`, `statectl.sh:2614-2626` @ b17e953); waiver appended only when a guard fired | codebase-derived |
| D-4 | Guard evaluation under `--force` | Guards become id-returning predicates evaluated on both paths; today's skip semantics (`statectl.sh:980/:299/:954`) made waiver-append unimplementable | codebase-derived |
| D-5 | §3 receipt shape + scope | Array `stages.N.stageFilesRead[]`, strict `^[1-9]-[a-z-]+\.md$`, own-file gate, stages 1–9 only (`statectl.sh:910`) | codebase-derived |
| D-6 | `mark-completed --force` vs waiver refusal | Does not bypass (mirrors `require_report_file`); self-deadlock avoided via pre-invocation `waivers[]` check | codebase-derived |
| D-7 | Read-only-tracker evidence parity | State preconditions (option b), not `comment-add --local` — no new concept | codebase-derived |
| D-8 | PR-body waiver surfacing owner/timing | Accept flow amends via idempotent `<!-- pipeline-waivers -->` block before `--accept-waivers` (cost-block marker precedent) | codebase-derived |
| D-9 | `renderVerify` transport | New `(5, renderVerify)` `stage-substatus` arm (`verified\|degraded`) written at the live-render gate — crash-recovery-resume safe; the detail-bearing checkpoint record (`{status, detail?}`) is retained as the human/retro record, gate reads the sub-status only; `checkpoint` stays replace-only | codebase-derived |
| D-10 | Previously-unlisted force escapes (`eval-criteria-shape`, `slice-partition-write-once`, `comment-receipt-ordering`) | All three get waiver ids — none declared non-waivable | codebase-derived |
| D-11 | Stage-1 AC-snapshot gate; per-slice precondition state; §3 harness attestation | Deferred (owner: maintainer; attestation unblocks when #244 lands) | deferred |
| D-12 | Waiver multiplicity + predicate message transport | Force path evaluates ALL guards, one waiver per fired guard (AC-9); predicates emit `<guard-id>\t<message>`, non-force refusal texts byte-preserved (AC-24); per-marker receipt guards emit today's joined-list message | codebase-derived |
| D-13 | `require_eval_file` guard identity | Split into `eval-criteria-shape` + `eval-resilience-evidence`; shared force early-return moves below each check | codebase-derived |
| D-14 | Post-terminal self-created waivers (AC-23 path) | Surface via state + retro only — declared accepted residue; pre-invocation reads govern EVERY waiver-reading gate (§2.4 refusal AND §2.5a report check), the alternative makes AC-23 unsatisfiable | codebase-derived |
| D-15 | Waiver surfacing scope in retro | Count beside silent-deviation headline AND flag a waived run whose PR body lacks the `<!-- pipeline-waivers -->` block (AC-17/§2.5c aligned) | codebase-derived |

Hydrated verbatim from `.claude/pipeline-state/243-ledger.md`. D-1, D-3, D-4, D-6, D-10, D-12, D-13 landed in PR 1; this slice implements D-2's residue (the stage-3 leg that survived the cut: `unitTestSurface`), D-5, D-7, D-8, D-9, D-14's report-check half, and D-15.

## Affected files

- `plugins/dev-pipeline/skills/run/statectl.sh` — the §1 legs as `guard_fire` predicates in `stage_completion_preconditions()` (case arms `3)` `:595`, `5)` `:606`, `7)` `:678`, `9)` `:681`); the `(5, renderVerify)` `stage-substatus` arm beside `5.designPlanReview` (`:2708`); `[NEW]` `cmd_stage_file_read()` mirroring `cmd_skill_load_add()` (`:2481`) with `--file` validated `^[1-9]-[a-z-]+\.md$`; the `completion-evidence:<N>.stageFileRead` own-file leg for every stage case 1–9; `require_report_file()` (`:456`) gains the `## Waivers`-section check when the pre-invocation `waivers[]` is non-empty; usage header gains the `stage-file-read` line
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — refusal cases per new leg (github AND jira-writes-off fixtures), `stage-file-read` validation + wrong-file rejection, report-gate `## Waivers` case; **plus the migration of its 91 direct `set-stage … completed` sites** — success-asserting sites gain a `stage_evidence` call; refusal-asserting sites stay untouched (protected by step 6b's leg ordering)
- `plugins/dev-pipeline/skills/run/scenario-lib.sh` — `[NEW]` `stage_evidence <key> <n>` fixture helper owning ALL new per-stage evidence writes (the `stage-file-read` receipt, stage 3's `unit-test-surface-set` skip shape when absent, stage 9's `costBlockApplied` seed via the suite's existing direct jq+mv state-edit idiom — the `lastUpdatedAt`-tamper precedent, documented in-fixture as test-only; production writes stay `pipeline-cost-block.sh`-owned). `complete_stage()` calls `stage_evidence` internally; the four consumer suites' direct completion sites call it themselves
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — the jira-adapter regression guard (config `tracker.writes: false` → stages 3/7/9 still refuse on missing evidence) + `stage_evidence` migration of **all 12 direct completion sites across every walk** (no-split, stacked, breaker, exhausted, be-fe-pair, waived-run)
- `plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh` — **12 direct completion sites migrated** via `stage_evidence` (NOT an unmodified canary; its value is exercising the real crash-recovery seams and staying green after its own mechanical migration)
- `plugins/dev-pipeline/skills/run/stage8-perrepo-review-selftest.sh` — does NOT source `scenario-lib.sh`, so its evidence is inlined: the stage loop gains a local stage-file receipt write (+ the stage-3 `unit-test-surface-set`), and the (a4) stage-8 completion gains its receipt — same evidence, direct `"$SC"` calls instead of the helper
- `plugins/dev-pipeline/skills/run/state-schema.md` — the completion-preconditions table rows 3/5/7/9 updated; the guard-id leg enumeration gains `3.unitTestSurface`, `5.renderVerify`, `7.checkpoint`, `9.costBlockApplied`, `9.prsRepoKeyed`, `<N>.stageFileRead`; `stages.N.stageFilesRead[]` + `stages.5.renderVerify` field entries; `costBlockApplied` (`:326` region) re-documented as load-bearing
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — `:336` "never blocks Stage 9 completion" revised (the field is now completion evidence; rc-2 state-unresolvable halting an auto run is the intended draconian outcome); a positive ordering contract "the cost-block sub-step MUST precede `set-stage 9 --status completed`" mirroring `:172`; the `<!-- pipeline-waivers -->` accept-flow block beside the cost-block sub-step
- `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` — `:125` "informational and is not load-bearing" revised; the rc-2 troubleshooting narrative re-framed as run-halting under auto
- `plugins/dev-pipeline/skills/run/stages/{1..9}-*.md` — one `stage-file-read` call-site line beside each stage's existing "mark the stage started" instruction (Stage 1's sits mid-file after the claim sequence)
- `plugins/dev-pipeline/skills/run/stages/5-implement.md` — `:189` region: the render-outcome record gains the derived `stage-substatus --stage 5 --key renderVerify` write beside the retained detail-bearing checkpoint record
- `plugins/dev-pipeline/skills/run/statectl.sh` header comment above `stage_completion_preconditions()` — the "Stages 3, 7, and 9 carry only the comment-receipt leg" paragraph is falsified by this slice; rewritten preserving the plan-path/`artifactPath` cut rationale
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — `:144` finish line gains the waiver count beside the silent-deviation headline; the deviation audit gains the waived-run PR-body `<!-- pipeline-waivers -->` presence check

## Reuse inventory

- `guard_fire` / `guards_settle` / `apply_waivers` + the `completion-evidence:<N>.<leg>` id scheme (PR 1) — every new leg reuses them verbatim
- `cmd_skill_load_add()` (`statectl.sh:2481`) — the dedup-append + `require_mutable` + `atomic_write` template `cmd_stage_file_read` mirrors
- The `stage-substatus` closed triple table (`:2700-2712`) — the `(5, renderVerify)` arm is one more case row
- `require_report_file()`'s marker + non-blank plausibility greps — the `## Waivers` check reuses the same shallow-grep posture
- `complete_stage()` / `write_eval` / `write_report` fixtures (`scenario-lib.sh`) — extended, not duplicated
- No new helpers outside `statectl.sh`; the one new subcommand is `stage-file-read` (tagged `[NEW]` above)

## Implementation steps

1. **§1 legs in `stage_completion_preconditions()`** (`statectl.sh:570-690`), each a `guard_fire` with its id and a writer-naming message: case `3)` gains `completion-evidence:3.unitTestSurface` (`.unitTestSurface | type == "object"`, message naming `unit-test-surface-set`); case `5)` gains `completion-evidence:5.renderVerify` (applicable iff `stageCheckpoint["1"].designDriven`; `.stages["5"].renderVerify` ∈ `verified|degraded`); case `7)` gains `completion-evidence:7.checkpoint` (`stageCheckpoint["7"] | type == "object"`); case `9)` gains `completion-evidence:9.costBlockApplied` (`(.costBlockApplied // null) != null` — boolean `true` and `skipped-*` strings pass) and `completion-evidence:9.prsRepoKeyed` (applicable iff `.targetRepos | length > 0`: every target id keyed in `.prs`).
2. **`(5, renderVerify)` substatus arm** beside `5.designPlanReview` (`:2708`): values `verified|degraded`.
3. **`[NEW]` `cmd_stage_file_read()`** + dispatch entry + usage line: `stage-file-read <issue> --stage N --file <basename>`; `--stage` `^[1-9]$`; `--file` `^[1-9]-[a-z-]+\.md$`; dedup-append to `stages.N.stageFilesRead[]`; `require_mutable` + `atomic_write` (mirrors `skill-load-add`).
4. **§3 own-file receipt leg** in every stage case 1–9: `completion-evidence:<N>.stageFileRead` — `stages.N.stageFilesRead[]` must contain a basename matching `^<N>-`; extra files recorded satisfy nothing.
5. **`require_report_file()` `## Waivers` gate**: when `(.waivers // []) | length > 0` in the state passed by `cmd_mark_completed`, additionally grep the report for a `## Waivers` heading — refuse without it (message naming the section). Wire the state json through (the function currently reads only files; give it the current-state arg from its one caller).
6. **Fixture migration — one helper, four consumer suites.** `[NEW]` `stage_evidence <key> <n>` in `scenario-lib.sh` (shape per the Affected-files entry above; the `costBlockApplied` seeding decision is FINAL — the jq+mv test-only idiom, no env hook, no `pipeline-cost-block.sh` invocation). `complete_stage()` calls it before its completion write. Migrate the direct completion sites: `statectl-selftest.sh` (91 — only success-asserting sites gain the call; refusal-asserting sites stay untouched, protected by step 6b's ordering), `scenario-liveness-selftest.sh` (12, ALL walks — no-split, stacked, breaker, exhausted, be-fe-pair, waived-run), `e2e-replay-selftest.sh` (12), `stage8-perrepo-review-selftest.sh` (3).
6b. **Leg ordering is load-bearing (the slice-2 analog of AC-24):** within every `stage_completion_preconditions()` case arm, ordering is [existing legs — comment receipts included] → [new §1 legs] → [the new `stageFileRead` receipt leg, always LAST]. "Receipt leg" in this rule means ONLY the new `stageFileRead` leg — the existing comment-receipt legs are existing legs and stay first. Non-force refusal reports the FIRST fired guard, so every existing `sct_err` message assertion stays byte-stable, and the new leg cases assert their own §1 writer-naming messages on fixtures whose earlier legs are satisfied.
7. **Call sites**: one line beside each stage file's mark-started instruction; stages/5 render write at `:189`; stages/9 cost-block ordering contract + `<!-- pipeline-waivers -->` accept flow; SKILL.md CLI surface `stage-file-read` line.
8. **Docs**: state-schema.md rows + leg enumeration + field entries + `costBlockApplied` load-bearing; cost-tracking-setup.md `:114/:125`; the `stage_completion_preconditions` header comment rewrite; pipeline-retro `:144` headline + PR-block check.
9. **Selftests**: refusal case per leg incl. a `tracker.writes:false` config fixture proving stages 3/7/9 refuse (AC-7); `stage-file-read` validation, wrong-file rejection (AC-18), stage-10 exclusion assertion (AC-19); report `## Waivers` refusal (AC-16); scenario-liveness jira zero-evidence guard + receipts on the no-split walk; full sweep green (AC-22).

## Test strategy

Shell repo, no `unitTestScope` (mutation gate off). Per-invocation invariants → `statectl-selftest.sh` (each new case carries its scenario-first justification comment); the composed jira-adapter zero-evidence path and the receipt-bearing full walk → `scenario-liveness-selftest.sh`; `e2e-replay-selftest.sh` is migrated like the others (12 sites) and its staying green post-migration is the crash-recovery-seam regression proof. AC-21 is a re-verification only (already satisfied by #246).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Stage 3 refuses without `unitTestSurface`, naming the writer | 1 | new `(l3)` refusal case |
| AC-2 | Stage 5 designDriven refuses without `stages.5.renderVerify` ∈ {verified,degraded}; resume-safe | 1, 2 | new `(l5)` cases (designDriven fixture; substatus persisted → completes) |
| AC-3 | Non-design runs complete stage 5 with no renderVerify | 1 | `(l5n)` negative case |
| AC-4 | Stage 7 refuses without `stageCheckpoint["7"]` object | 1 | `(l7)` refusal case |
| AC-5 | Stage 9 refuses on null/empty `costBlockApplied` | 1 | `(l9)` refusal case (+ `true` and `skipped-*` acceptance arms) |
| AC-6 | be-fe-pair stage 9 refuses unless `.prs` keyed per target; standalone exempt | 1 | `(l9r)` pair fixture + standalone negative |
| AC-7 | `tracker.writes:false` still refuses stages 3/7/9 on zero evidence | 1, 9 | scenario-liveness jira-adapter guard |
| AC-16 | Report lacking `## Waivers` refused while waivers non-empty | 5 | `(rw1)` case |
| AC-17 | PR-body `<!-- pipeline-waivers -->` accept flow documented; retro flags a missing block | 7, 8 | review-verified (prose flow) + retro prose; no grep guard |
| AC-18 | `stage-file-read` validates + dedup-appends; completion refuses without stage N's own file | 3, 4 | `(sfr1..3)` cases incl. wrong-file |
| AC-19 | Stage 10 carries no receipt requirement; `set-stage` stays `{1..9}` | 4 | `(sfr4)` range assertion |
| AC-20 | Retro reports waiver count beside the silent-deviation headline | 8 | review-verified (retro prose); no grep guard |
| AC-21 | Usage header documents `pr-add --repo` | — | satisfied on base (#246); re-verified during review |
| AC-22 | All three `complete_stage` consumer suites + full sweep green post-migration | 6, 9 | the sweep itself |

AC-8–AC-15 and AC-23–AC-25 are slice-1 ACs (PR #255) — plan-lint's slice mode forbids coverage-shaped rows for them here; the state partition (`decomposition.slices[]`) is the authority.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks

- **The fixture migration touches every suite that completes stages** — 118 direct sites across four suites plus the shared walk. Mitigation: ONE helper (`stage_evidence`) owns the evidence shape; per-site edits are mechanical one-line inserts; refusal-asserting sites need no edit (step 6b's ordering); the full `-P 4` sweep is the gate.
- **Stacked-slice re-entry can stale-satisfy the `9.costBlockApplied` / `stageFileRead` legs** (slice-1 residue in the overwritten-per-slice state) — declared #211 residue, not fixed here (see Out-of-scope).
- **`require_report_file` signature change** (gains the state arg) — single caller (`cmd_mark_completed`), verified by the existing report-gate cases plus `(rw1)`.
- **The jira fixture needs a config with `tracker.writes:false`** — the suite already builds per-case configs (JIRA-keyed fixtures section); reuse that idiom, no new harness.
- Rollback: revert the branch; fields additive.

## Out-of-scope

- #244 ledger `target` capture; harness-attested preconditions (§3-full).
- Stage-1 AC-snapshot non-empty gate; per-slice stage-machine semantics (#211) — including per-slice scoping of the new evidence legs (a stacked re-entry inheriting slice-1's `costBlockApplied`/receipts is #211 residue, declared not silent).
- Any change to PR 1's mechanism surfaces (`guard_fire`/scan/mode/waiver fold).

Unverified references: none.
