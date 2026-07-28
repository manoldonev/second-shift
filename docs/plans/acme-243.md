# Plan: operator-authorized `--force` — the §2 mechanism (#243, PR 1 of 2)

## Context

Issue #243 (stacked-PR slice 1 of 2, per the intake decomposition): every `--force` waiver must become reason-carrying, durably recorded, terminal-blocking, and impossible in autonomous mode. Today `--force` is a bare boolean that *skips guard evaluation entirely* — `cmd_set_stage` runs `stage_completion_preconditions` only when `force -ne 1` (`plugins/dev-pipeline/skills/run/statectl.sh:985-989`), `require_mutable` folds the force bit into its refusal condition (`statectl.sh:300-306`), and `require_eval_file` early-returns at `statectl.sh:336`. Nothing distinguishes an operator's crash-recovery from an executor waiving its own gate, and after the fact the state file looks identical to a clean run's.

This slice builds the mechanism: guards become id+message-emitting predicates evaluated on both paths, `--force` requires `--force-reason`, every fired-guard bypass appends to `waivers[]`, the mode rides state (`init --mode`) so autonomous runs cannot force at all, and `mark-completed` refuses to terminalize a waived run without explicit `--accept-waivers`. Slice 2 (PR 2) adds the §1 evidence legs and §3 stage-file receipts on top of this scheme.

All line anchors below were verified at the branch base `b17e953`.

## Assumptions

- The intake decisions on the issue thread (comment `stage: intake`, run `2026-07-28T215244Z-local-b864ca82`) are binding: waiver transport folds into the invocation's single `atomic_write`; `.mode` re-stamp writes `.mode` only (no `lastUpdatedAt` bump, exempt from the terminal-state guard — the `pipeline-session-add` precedent at `statectl.sh:2288-2300`); `reclaim-staleness` waivers are deliberately terminal-blocking; the byte-pinned refusal texts keep their now-incomplete `--force for crash-recovery` hints.
- `gen-statectl-validators.sh` regeneration is NOT needed: no generated closed-enum table changes; the guard-id vocabulary is hand-maintained in `state-schema.md` (the `stage-substatus` triple-table posture).
- The selftest sweep runs four-way parallel (`xargs -P 4`, CLAUDE.md Verification) — all new selftest cases keep the per-suite `mktemp` state-dir isolation that makes that safe.

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

Rows hydrated verbatim from `.claude/pipeline-state/243-ledger.md` (main checkout). D-2, D-5, D-8, D-9, D-11, D-14 (report-check half), D-15 govern slice-2 work and are carried for ledger completeness; this slice implements D-1, D-3, D-4, D-6, D-10, D-12, D-13 and the state half of D-14.

## Affected files

- `plugins/dev-pipeline/skills/run/statectl.sh` — the whole mechanism (details in Implementation steps; key regions at `require_mutable()` `:300`, `require_eval_file()` `:316-380`, `require_report_file()` `:393`, `stage_completion_preconditions()` `:506-625`, monotonic guard `:963`, `cmd_set_stage` force-conditional `:985-989`, `slice-partition-set` write-once `:1268`, `cmd_mark_completed()` `:1959`, `cmd_reclaim` staleness `:2460-2475`, `comment-add` ordering guard `:2540-2543`, `cmd_init()` `:813-844`, `main()` dispatch `:2614-2626`)
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — ~40 `--force` invocation migrations + new refusal/append cases
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — one new scenario: a waived run cannot reach `completed` without `--accept-waivers`
- `plugins/dev-pipeline/skills/run/state-schema.md` — `waivers[]`, `waiversAccepted`, top-level `.mode`, the guard-id vocabulary + full leg enumeration
- `plugins/dev-pipeline/skills/run/SKILL.md` — CLI-surface lines for `init --mode` / `--accept-waivers`, and all four existing `[--force]` usage lines become `[--force --force-reason <text>]`; mode-resolution section gains the state-transport + literal-value asymmetry contract
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — Step 1.A (`:94`): the init call becomes a two-line snippet that resolves the mode inline per SKILL.md's existing resolution rule and passes it — `MODE="${DEV_PIPELINE_MODE:-auto}"` (set+valid wins; unset/empty → `auto` — the skill-level default IS correct here, at the one site that *records* the run's own mode) then `statectl init "$ISSUE_NUMBER" --run-id "$RUN_ID" --mode "$MODE"`. No new symbol: `MODE` is defined by the snippet itself, in the same code block. The re-queue idempotency note (`:204`) gains the `.mode` re-stamp carve-out
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` (`:186-187`) — the documented post-terminal `deviations-add --force` backfill becomes the attended form: `DEV_PIPELINE_MODE=interactive statectl deviations-add … --force --force-reason "<why>"` (a pipeline-owned state file carries `.mode: auto`, so the bare form would now be refused even from an operator shell)
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` (`:41`) — "`--force` is the sole bypass" becomes "a reason-carrying `--force` from an attended shell (`DEV_PIPELINE_MODE=interactive` on a pipeline-owned state) is the sole bypass"
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` (`:362`) — the `mark-completed` overwrite note gains the same attended-form phrasing; `:178`/`:364` ("not bypassed by `--force`") remain true verbatim and are left unchanged. `stages/10-cleanup.md:15`'s `git worktree remove --force` is a **git** flag, not statectl — explicitly out of blast radius
- `scripts/lockstep-manifest.tsv` — extend the **existing DROPPED comment block** covering the statectl-usage-header ↔ SKILL.md CLI-surface pair (the manifest already records that pair as DROPPED — "statectl.sh carries `[--force]` where SKILL.md does not"): the argv-scan skip-list ↔ usage-header value-taking-flags coupling is recorded there as DROPPED-with-reasoning too (no byte-anchorable literal spans the two sites; the `(fr1)` decoy selftest is the behavioral guard). No new enforced row

## Reuse inventory

- `atomic_write()`, `read_state()`, `now_iso()`, `die` / `EXIT_CODE` convention — every new write path reuses them (grep-verified `statectl.sh`)
- `require_mutable()` (`statectl.sh:300`) — becomes a predicate but keeps its name and call sites
- `pipeline-session-add`'s terminal-guard exemption (`statectl.sh:2288-2300`) — the documented precedent the `.mode` re-stamp mirrors
- `comment-add`'s `code-review` ordering guard (`statectl.sh:2540-2543`) — already the id-shape in miniature (fires only when `force -eq 0`); it is converted, not duplicated
- `sct`, `sct_rc`, `sct_err`, `reset_state`, `complete_stage` selftest helpers (`scenario-lib.sh`) — all new cases use them

New helpers are confined to `statectl.sh` (`guard_check` conventions, `resolve_mode`, the `GUARD_FIRED`/`FORCE_REASON` globals — each tagged `[NEW]` at its Implementation-steps site); no existing equivalent exists for any of them (grep-confirmed: no `resolve_mode`/`GUARD_FIRED`/`FORCE_REASON` symbols on base).

## Implementation steps

1. **Guard-predicate infrastructure** in `statectl.sh`: add `[NEW]` `guard_check()` conventions — each waivable guard becomes a function/leg that appends `"<guard-id>\t<refusal message>"` lines to a `[NEW]` `GUARD_FIRED` array variable instead of calling `die` inline. Evaluate on BOTH paths. Non-force caller: `die` with the FIRST fired guard's message, byte-unchanged (AC-24). Force caller: proceed, handing `GUARD_FIRED` to the waiver append (step 4). **`require_mutable` converts INSIDE its single definition** (`:300`) — it already receives the force flag, so it keeps its internal die on the non-force path and appends to `GUARD_FIRED` on the force path; its ~15 call sites are untouched, and a missed-site fail-open is structurally impossible (one definition, zero caller changes). Converted guards and their ids: `require_mutable` → `terminal-state`; monotonic guard (`:963`) → `monotonic-guard`; every existing leg of `stage_completion_preconditions()` → `completion-evidence:<N>.<leg>` (leg names enumerated in `state-schema.md`; `require_comment_receipts` legs per marker as `completion-evidence:<N>.commentReceipt.<marker>`, each emitting today's joined-list message); `require_eval_file` split into `eval-criteria-shape` + `eval-resilience-evidence` with the shared early-return (`:336`) moved below each check; `slice-partition-set` write-once (`:1268`) → `slice-partition-write-once`; `comment-add` code-review ordering (`:2540`) → `comment-receipt-ordering`; `cmd_reclaim` staleness (`:2460-2475`) → `reclaim-staleness`.
2. **Pre-dispatch `--force-reason` scan** in `main()` (insert after the subcommand `shift` at `:2620`, before the `case` at `:2621`): left-to-right argv scan extracting and stripping `--force-reason <text>` into a `[NEW]` `FORCE_REASON` global; skip the value token of every value-taking flag (skip-list = the usage header's value-taking flags; the coupling recorded as DROPPED-with-reasoning in the manifest's existing statectl↔SKILL.md block — the `(fr1)` decoy probe is the behavioral guard). When argv carries `--force` and `FORCE_REASON` is absent or <20 chars → `die` before any state read (AC-8). Accepted behavior change (documented in the code comment): a `--force-reason` on a subcommand with no `--force` support is stripped, not rejected.
3. **Mode transport**: `cmd_init` (`:813`) gains `--mode auto|interactive`; on the fresh path it lands in the initial document; on the existing-state early-return path (`:836-844`) it re-stamps `.mode` ONLY — no `lastUpdatedAt` bump, no other field, exempt from the terminal-state guard (AC-25, `pipeline-session-add` precedent) — **and that path's "Idempotent: … do not mutate" comment block is rewritten** to name the `.mode` re-stamp as its one documented carve-out (a comment contradicting the code is how the next auditor mis-reads it). `[NEW]` `resolve_mode()`: env `DEV_PIPELINE_MODE` if set (literal) → else state `.mode` → else empty. Every force-accepting subcommand refuses `--force` when `resolve_mode()` yields `auto`, stderr naming the recovery `DEV_PIPELINE_MODE=interactive statectl … --force --force-reason "…"` (AC-11/AC-12).
4. **`waivers[]` append**: for each `GUARD_FIRED` entry under an accepted force, append `{stage, precondition, reason: FORCE_REASON, at: now_iso, subcommand}` (`stage` null for non-stage-scoped guards) — folded into the SAME in-memory document the invocation writes, one `atomic_write` per invocation; on pure-refusal paths that would otherwise not write (e.g. a forced `set-stage` whose only effect is the bypass), the waiver append IS the write. No fired guard ⇒ no append (AC-9/AC-10).
5. **`mark-completed` waiver gates** (`:1959`): before `require_eval_file`, refuse when the PRE-invocation `waivers[]` is non-empty, listing every entry — not bypassed by `--force` (AC-14). `[NEW]` `--accept-waivers` flag: proceeds, records `waiversAccepted: {at, count}` in the same terminal write (AC-15). The AC-23 path (forced re-terminalization) reads pre-invocation `waivers[]` (empty) → succeeds, appending its own `terminal-state` waiver — declared accepted residue.
6. **Docs**: `state-schema.md` — `waivers[]` / `waiversAccepted` / `.mode` field entries + the closed guard-id vocabulary with the full per-leg enumeration beside the completion-preconditions table; rewrite `require_eval_file`'s two stale comment blocks (pre-refactor: "the two checks below the `--force` early return" and "the function already returned above"); `SKILL.md` — the `init --mode` / `--accept-waivers` CLI-surface lines, the four `[--force]` lines → `[--force --force-reason <text>]`, and the mode-resolution asymmetry sentence (statectl keys on the literal value / state, never the unset→auto default); `stages/1-intake.md:94` gains the two-line `MODE` + `init --mode` snippet, `:204` gains the re-stamp carve-out; `stages/8-code-review.md:186-187` + `stages/6-verify.md:41` + `stages/9-open-pr.md:362` get the attended-form `--force` wording per Affected files.
7. **Selftest migration + new cases** in `statectl-selftest.sh`: migrate the ~40 existing `--force` invocations to carry `--force-reason "selftest crash-recovery simulation …"` (≥20 chars); new cases — `(fr1)` `--force` w/o reason refused pre-dispatch; `(fr2)` reason <20 chars refused; `(am1)` `init --mode auto` then `--force` refused with recovery-naming stderr, env unset; `(am2)` env `DEV_PIPELINE_MODE=interactive` overrides state auto; `(am3)` `init --mode interactive` → `init --mode auto` re-stamps (AC-25) and `lastUpdatedAt` unchanged; `(wv1)` forced terminal-state bypass appends a five-field waiver; `(wv2)` forced multi-leg completion bypass appends one waiver PER fired leg and the final file carries both waivers and the stage write; `(wv3)` no-op force appends nothing; `(mc1)` `mark-completed` refuses on non-empty waivers, `--force` does not bypass; `(mc2)` `--accept-waivers` completes + records; `(mc3)` AC-23 self-waiver succeeds. Existing `sct_err` message assertions run unmodified (AC-24's proof).
8. **Scenario** in `scenario-liveness-selftest.sh`: a composed run that forces one gate mid-walk cannot reach `mark-completed` without `--accept-waivers`, and the acceptance records `waiversAccepted` — the slice-1 verdict-path extension (the jira 3/7/9 guard is slice 2's).

## Test strategy

Shell-only repo: no `unitTestScope` configured, so the mutation-review surface does not apply (`unitTestSurface.action: skip`). The test surface IS the selftest suites: per-tool refusal/append cases in `statectl-selftest.sh` (step 7), the composed waived-run scenario in `scenario-liveness-selftest.sh` (step 8), and AC-24's regression proof is the *unmodified* pre-existing `sct_err` assertions passing against the refactored guards. `e2e-replay-selftest.sh` runs unchanged in this slice (its `complete_stage` walks never force; the fixture migration is slice 2's when the new legs land).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-8 | `--force` without ≥20-char reason refused pre-dispatch | 2 | `(fr1)`, `(fr2)` |
| AC-9 | One waiver per fired guard, five fields, guard's id | 1, 4 | `(wv1)`, `(wv2)` |
| AC-10 | No-op force appends nothing; guards never skipped | 1, 4 | `(wv3)` |
| AC-11 | Resolved-auto mode refuses `--force`; stderr names recovery | 3 | `(am1)` |
| AC-12 | Unset env + no state mode keeps working; env interactive overrides | 3 | `(am2)`, plus the 40 migrated invocations passing |
| AC-13 | `init --mode` persists; refusal observable with no env | 3 | `(am1)`; SKILL.md/stage-file wiring review-verified |
| AC-14 | `mark-completed` refuses on waivers; `--force` no bypass | 5 | `(mc1)` |
| AC-15 | `--accept-waivers` completes + records | 5 | `(mc2)` |
| AC-23 | Forced re-terminalization succeeds via pre-invocation read | 5 | `(mc3)` |
| AC-24 | Non-force refusal texts byte-preserved | 1 | existing `sct_err` assertions, unmodified |
| AC-25 | `.mode` re-stamped on existing-state init; nothing else reset | 3 | `(am3)` |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks

- **The predicate refactor touches ~20 `die` sites in the hottest file in the pipeline.** Mitigation: AC-24 pins every message byte-for-byte and the existing `sct_err` assertions are the regression net; the conversion is mechanical (emit-instead-of-die), reviewed leg by leg.
- **The pre-dispatch scan mis-stripping a flag value** (`--json` payloads containing the literal `--force-reason`). Mitigation: the skip-list algorithm + a dedicated selftest probe inside `(fr1)`'s section passing `--json '{"x":"--force-reason decoy"}'`.
- **Concurrent sessions running the OLD statectl against the same state dir** while this branch is unmerged: the new fields are additive and old code ignores them; the only interaction is `waivers[]` being invisible to old `mark-completed` — acceptable during the PR window.
- Rollback: revert the branch; no data migration (all fields additive, absent on old state files).

## Out-of-scope

- §1 evidence legs (stages 3/5/7/9), the `(5, renderVerify)` substatus arm, §3 `stage-file-read` + receipts, `complete_stage()` fixture migration, the jira-adapter zero-evidence scenario, report `## Waivers` section gate, PR-body `<!-- pipeline-waivers -->` amend flow, `pipeline-retro` headline, `cost-tracking-setup.md` / `stages/9-open-pr.md` / `state-schema.md:326` cost reconciliation — all PR 2 of this stack.
- #244 ledger `target` capture and harness-attested preconditions (separate issue).

Unverified references: none.
