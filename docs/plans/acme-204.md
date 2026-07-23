# Plan: slice-scoped gates for the stacked-prs path (#204)

## Context / problem framing

The `stacked-prs` verdict is functionally dead: every gate added after the outer loop landed grades slice N against the **full ticket**, so slice 1 of any decomposition whose ACs span slices exits through the Stage-8 `scope-blocker-no-code-remedy` short-circuit (`plugins/dev-pipeline/skills/run/stages/8-code-review.md` § "Scope blocker with no code remedy") → `codeReviewExhausted: true` → outer-loop STOP (`plugins/dev-pipeline/skills/run/stages/1-intake.md:335-339`). Secondary: plan-lint Check 3 (`plugins/dev-pipeline/skills/run/tools/plan-lint.sh:146-161`) forces a slice plan to row every full-ticket AC. Root cause: the intake orchestrator's coverage back-check computes an AC→slice partition (`plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md:242`) that is never persisted — state carries only the flat `acceptanceCriteria[]` snapshot (`plugins/dev-pipeline/skills/run/state-schema.md:67`).

Fix: persist the partition write-once at intake; make plan-lint, the Stage-8 scope gate, and the retro AC audit slice-scoped without weakening final-slice completeness; add a verdict-path liveness selftest over the mechanical gate chain.

## Assumptions

- The partition is part of the Stage-1 intent snapshot: written once, before any code exists, by the same trust model as `acceptanceCriteria[]`. A run can never author or edit it mid-flight.
- The stacked branch for slice N contains slices 1..N cumulatively (each slice branches from the prior — `stages/1-intake.md` outer-loop branch derivation), so grading the union of ACs for slices 1..N against a diff anchored at slice 1's base is honest.
- Intake decisions recorded on the issue (comment 2026-07-23): partition arrives at the scope reviewer via the **state file on disk**, never the dispatch prompt; integrity checks key on the **snapshot** AC set; drift ⇒ full-ticket fallback (fail-closed); partition keyed by **slice index**; "slice 1's base" = configured `topology.repos.<host>.baseBranch`.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Partition delivery channel to scope-completeness-reviewer | Reviewer reads `<repo-root>/.claude/pipeline-state/<key>.json` directly (path derived from the ticket key it fetched itself, mirroring its existing config read at `plugins/review-toolkit/agents/scope-completeness-reviewer.md:31`); dispatch prompt may name the path but is never content authority | codebase-derived |
| D-2 | Snapshot-vs-live AC drift handling in the partition-integrity check | Union of `slices[].acIds` must equal the snapshot AC-id set, AND the snapshot set must equal the AC set the reviewer derives from the live body; any mismatch voids slice-scoping and the reviewer grades the full ticket (fail-closed) | codebase-derived |
| D-3 | Partition keying and precedence vs the decomposition plan file | Keyed by 1-based slice index (same index space as `currentSlice`); state partition is authoritative for AC scoping only; the plan file stays authoritative for slice content/branch derivation | codebase-derived |
| D-4 | Non-AC scope items (prose deliverables outside the AC section) on non-final slices | Graded only on the final slice (currentSlice == partition length); Noted (not `[unsatisfied]`) on earlier slices — final-slice completeness enforcement unchanged | codebase-derived |
| D-5 | Partition mutability | Write-once: `slice-partition-set` refuses an overwrite without `--force` (same posture as the terminal-state guard); prevents mid-run scope narrowing | codebase-derived |
| D-6 | Where the graded-union derivation lives | Shared helper `tools/slice-scope.sh` used by Stage-8 in-session assembly and the liveness selftest; the scope reviewer re-derives independently via jq per its inline-copy discipline (same pattern as its byte-matched AC-fallback copy) | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — new subcommand `cmd_slice_partition_set` [NEW function] + dispatch entry (pattern: `cmd_slice_set`, statectl.sh:1028)
- `plugins/dev-pipeline/skills/run/state-schema.md` — document `decomposition.slices[].acIds` under a new "Stacked-PR AC partition" heading in the Intake intent snapshot family
- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — Check 3 slice mode (universe = current slice's `acIds` when partition + non-null `currentSlice` present; a row for another slice's AC is a violation)
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — traceability rule: stacked mode keys the table by the current slice's AC subset (lockstep with the lint, same PR)
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` — scope-gate slice mode: dedicated `SCOPE_BASE` derivation (merge-base of HEAD and `origin/<BASE_BRANCH_CFG>`, distinct from the per-slice `WORKTREE_BASE` at 8-code-review.md:89-96) + pass `scopeBase`/`statePath` in the Workflow args
- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — accept optional `scopeBase` + `statePath` args; scope-completeness-reviewer's range uses `scopeBase...head` when provided (other reviewers keep `base...head`); its prompt names the state-file path only
- `plugins/review-toolkit/agents/scope-completeness-reviewer.md` — new "Stacked-slice partition (state-snapshot evidence)" section: read partition from the state file, run the D-2 integrity checks, grade union 1..currentSlice, D-4 non-AC-item rule, full-ticket fallback on any integrity failure
- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` — `stacked-prs` verdict (Step 6) returns the AC→slice map structurally and persists it via `statectl slice-partition-set` before returning control
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — Step 1.D: on a `stacked-prs` verdict persist the partition alongside `intake-brief`; outer-loop note pointing at the slice-scoped gates
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — Step 3 audit item 7: when state carries a partition, iterate only the union for slices 1..currentSlice; later-slice ACs are expected-uncovered, not findings
- `plugins/dev-pipeline/skills/run/tools/slice-scope.sh` [NEW] — emits graded AC union + integrity verdict for a state file (+ optional `--slice N`)
- `plugins/dev-pipeline/skills/run/tools/verdict-path-liveness-selftest.sh` [NEW] — the verdict-path liveness scenario test (glob-discovered by CI; no registration)

## Reuse inventory

- `cmd_slice_set` (statectl.sh:1028) — arg-parse/validation/atomic-write template for the new subcommand (verified)
- `require_mutable` + `atomic_write` + `read_state` statectl internals — reused as-is by the new subcommand (verified: used by `cmd_slice_set`)
- `plan-lint-selftest.sh` fixture conventions (`plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh`) — extended with slice-mode fixtures (verified)
- `statectl-selftest.sh` drift-check (byte-match vs `tools/gen-statectl-validators.sh` regeneration) — guards that the new subcommand lands outside generated validator regions (verified)
- The scope reviewer's inline-copy discipline (`scope-completeness-reviewer.md:63` — byte-matched AC-fallback copy) — the same pattern carries the partition-integrity rules into the agent prose (verified)

## Implementation steps

1. **statectl**: add `cmd_slice_partition_set <issue> --json '[{"slice":1,"acIds":["AC-1",...]}, ...]'` — validates: contiguous 1-based slice indices; non-empty `acIds`; every id matches `^AC-[0-9]+$`, exists in `acceptanceCriteria[]`, and appears in exactly one slice (disjoint); refuses overwrite without `--force` (D-5). Writes `.decomposition.slices` + `lastUpdatedAt` atomically. Add dispatch entry next to `slice-set` (statectl.sh:2381).
2. **state-schema.md**: document the field, its write-once semantics, index keying (D-3), and the D-2 integrity contract (normative home for the reviewer's inline copy).
3. **Run `tools/gen-statectl-validators.sh`** and assert byte-match (no enum changes expected; the drift-check selftest case enforces).
4. **slice-scope.sh** [NEW]: given a state file (+ optional `--slice N`, default `currentSlice`), print the graded AC-id union for slices 1..N and an integrity verdict (`ok` | `no-partition` | `union-mismatch`). Pure read-only jq; used by Stage 8 assembly and the selftest.
5. **plan-lint.sh Check 3 slice mode**: when the state carries `.decomposition.slices` (non-empty) AND non-null `.currentSlice`, the Check-3 universe becomes that slice's `acIds`; rows outside it violate ("row AC-n belongs to slice M — fabricated coverage"); 1:1 within the subset. No partition / no currentSlice → unchanged full-snapshot behavior.
6. **3-write-plan.md**: traceability-rule paragraph gains the stacked-mode sentence keying the table by the current slice's subset (lockstep with step 5).
7. **8-code-review.md + code-review.mjs**: stage prose derives `SCOPE_BASE` when stacked (merge-base of HEAD and `origin/$BASE_BRANCH_CFG`) and passes `scopeBase` + `statePath` in args; the mjs applies `scopeBase...head` to scope-completeness-reviewer only and appends the state-file path (path only, no scope commentary) to its evidence prompt. Guard: `scopeBase` absent → identical current behavior (single-PR runs untouched).
8. **scope-completeness-reviewer.md**: new section — locate the state file from the repo root + the ticket key it fetched itself; run the D-2 integrity checks with jq; on `ok` grade union 1..currentSlice, mark later-slice ACs "deferred to slice M (partition)" as Notes, apply D-4 for non-AC items; on ANY failure grade the full ticket. The ignore-dispatch-prompt rule is restated unchanged.
9. **intake-orchestrator SKILL.md + 1-intake.md**: Step 6 `stacked-prs` emits the AC→slice map in its verdict payload; Stage 1 Step 1.D persists it via `slice-partition-set` right after `intake-brief` (tracker-independent — local statectl write, legal under `tracker.writes: false`).
10. **pipeline-retro SKILL.md**: scope audit item 7 by the partition when present.
11. **verdict-path-liveness-selftest.sh** [NEW]: tmp state dir; `statectl init` → `intake-brief` (4 ACs) → `slice-partition-set` (2 slices) → `slice-set` slice 1 → assert: (a) slice-mode plan fixture rowing only slice-1 ACs passes plan-lint and the full-ticket fixture fails; (b) `slice-scope.sh` emits the slice-1 union with `ok`, and a tampered partition yields `union-mismatch`; (c) stop-condition predicate: `review-rounds --set 1` (no `--exhausted`) leaves `codeReviewExhausted` falsy → loop proceeds; `--exhausted` → stop; (d) slice 2's union equals the full snapshot (final-slice completeness). Terminal reachability of the `stacked-prs` verdict is the asserted invariant.

## Test strategy

Verify-after (infra/tooling change, no product behavior): the new liveness selftest (step 11) plus extended `plan-lint-selftest.sh` slice-mode fixtures and a `statectl-selftest.sh` case for `slice-partition-set` validation rejects (bad id, overlap, non-contiguous, overwrite-without-force). All are `*-selftest.sh` glob-discovered — model-free, per CI's design. Scenario-level liveness over per-tool fixture accretion, per the issue's item 5.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

(Stage-1 snapshot is empty — the issue body has no Acceptance Criteria heading; completion is judged against the five fix-direction items, all covered by steps 1–11.)

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash plugins/dev-pipeline/skills/run/tools/gen-statectl-validators.sh | diff - plugins/dev-pipeline/skills/run/statectl.sh
```

## Risks / rollback notes

- **Reviewer-prose drift**: the partition-integrity rules live in both `state-schema.md` (normative) and the reviewer's inline copy — mitigated by following the existing byte-matched-copy discipline; drift here degrades fail-closed (full-ticket grading), never fail-open.
- **`code-review.mjs` token guards**: `null-reviewer-selftest.mjs` asserts load-bearing tokens in the mjs; run it (it is in the selftest glob) after the edit.
- **Rollback**: revert the single PR; the new state field is additive and ignored by all pre-change consumers (absent-field guards throughout).

## Out-of-scope

- Liveness coverage for the `no-split` / `sub-issues` verdicts (issue explicitly defers: "eventually").
- The `sub-issues` success-shaped statectl terminal (tracked follow-up per SKILL.md).
- Any weakening of the scope gate's anti-negotiation rules for non-stacked runs.
- The jira decomposition-plan-file question beyond the partition itself (partition is state-persisted regardless of tracker; plan-file handling unchanged).

Unverified references: none.
