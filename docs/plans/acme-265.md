# Plan — #265: delete the stacked-PR machinery (execution path + state/scope contracts)

## Context / problem framing

#262 retired the `stacked-prs` intake verdict. PR 1 (#263, merged) removed the emitting side: `intake-toolkit:intake-orchestrator` no longer produces a stacked verdict, and `stages/1-intake.md`'s Step 1.D no longer writes an AC→slice partition. Everything downstream of that verdict is therefore **dead by construction** — unreachable code and unreachable prose that still advertises a mode the pipeline cannot enter.

This PR deletes it. Two coupled halves:

- **Part 1 — the execution path.** The Stage-1 outer loop and its slice-derivation pre-check, Stage-2 slice-branch derivation and prior-slice worktree bases, Stage-9 non-`baseBranch` PR targeting, and the two tools that exist only to serve them (`tools/max-pushed-slice.sh`, `tools/start-slice.sh`).
- **Part 2 — the state and scope contracts.** The `decomposition` stanza, the four flat slice fields, the two `statectl` subcommands that write them, and every gate that narrowed grading to a slice (`plan-lint` Check-3 slice mode, `tools/slice-scope.sh` + its Stage-8 caller, `code-review.mjs`'s `scopeBase`, `scope-completeness-reviewer.md` Step 4c).

The two halves ship in one PR because #262 Step 4 binds them: "state-schema/statectl field retirement lands with all readers in one PR."

**What makes this non-trivial despite being a deletion:** `scenario-liveness-selftest.sh` and `e2e-replay-selftest.sh` open with tool-presence preflights that `exit 99` on a missing file. Deleting a tool without deleting its preflight line in the *same commit* turns the entire sweep red — not just that suite. #262 Step 3 is that constraint, and it is what fixes the commit boundaries below.

## Assumptions

1. **`#263` is merged.** Verified: closed 2026-07-30T10:41:53Z. The `stacked-prs` verdict is no longer emitted, so nothing this PR deletes is reachable.
2. **`{slice}` / `configVersion` work belongs to #267.** `stageParams.planFilePattern`'s `{slice}` token, its five hardcoded default-pattern literals, and the `configVersion` bump are D-12 and out of scope here. The `SLICE_SUFFIX` substitution mechanics in `stages/3-write-plan.md` and `stages/5-implement.md` survive this PR untouched.
3. **Historical artifacts are frozen.** `docs/plans/**` and `CHANGELOG.md` keep their stacked references (#262 Migration; `CHANGELOG.md` is additionally CI-frozen by `scripts/check-frozen-files.sh`). Every grep-clean bar in this ticket is read with that carve-out — see D-b.
4. **`worktreeBase` survives (#262 D-5)** and its `verifyctl.sh` / Stage-5 / Stage-6 consumers are behavior-unchanged. Only its *documentation* changes, because its current definition is written in slice terms.
5. **No behavior change to any live path.** Every deleted branch is guarded by a state field that intake no longer writes, so a single-PR run — the only kind that now exists — takes byte-identical control flow before and after.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-a | Four files reference the retired tools but are absent from the ticket's Scope list | All four are in scope. #262's own Scope already assigns two (`tools/tracker/README.md` "drop the `max-pushed-slice.sh` consumer note and stacked branch-shape prose"; `schema/second-shift.config.schema.json` "`branchPrefix` description drops the `-pr<N>` shape and the `max-pushed-slice.sh` mention"). The third, `tools/predecessor-gate.sh`'s two design-precedent comments, is rewritten to describe the stdin/args seam without the dead filename. The fourth is the **parallel adapter path** `tools/tracker/jira/README.md:36`, which carries the same "Stacked slice N: `…-pr<N>`" branch-shape prose as its github sibling — a one-repo-path edit that skips its mirror leaves the retired shape documented under the other adapter. AC-1 is satisfied by editing all four, not by narrowing the AC | ticket-sourced (#262 Scope) + codebase-derived (the jira mirror; https://github.com/manoldonev/second-shift/issues/265#issuecomment-5131986620) |
| D-b | AC-4/AC-5/AC-6 lack the historical carve-out AC-1 carries | The carve-out applies to every AC in this ticket. `docs/plans/**` and `CHANGELOG.md` are excluded from all grep-clean bars — restating #262's Migration clause so the Stage-8 scope gate reads it in-band rather than inferring it | ticket-sourced (#262 Migration; https://github.com/manoldonev/second-shift/issues/265#issuecomment-5131986620) |
| D-c | Is the `branchPrefix` schema description this PR's work or #267's? | This PR's. #262 splits `schema/second-shift.config.schema.json` into two independent items: the `branchPrefix` description (stacked-execution prose) and `planFilePattern`'s `{slice}` token (D-12 → #267). A description-only edit is not a `configVersion` change; schema lines 237–238 are untouched | ticket-sourced (#262 Scope + D-12; https://github.com/manoldonev/second-shift/issues/265#issuecomment-5131986620) |
| D-d | `worktreeBase` is preserved, but its normative definition is written in slice terms and cites `priorSliceBranch`, which this PR deletes | Rewrite the stanza to its post-retirement definition. After `slice-set` is deleted the sole remaining writer is `worktree-set --base`, which Stage 2 passes only on the be-fe-pair path — so the field is a be-fe-pair flat mirror, absent on single-repo runs, with consumers falling back to the configured base branch. The `status` bullet's `require_mutable` enumeration also drops `slice-set` | codebase-derived |
| D-e | `scenario-liveness-selftest.sh` has a second tracked-debt block beyond the one the ticket names | In scope. Header block (B) tracks the Stage-2 `currentSlice > M+1` sanity stop that Part 1 deletes; that item comes out of its three-item list in the same commit, so the header stops tracking debt for a deleted guard and the `currentSlice` token dies with it | codebase-derived |
| D-f | `code-review.mjs` carries `statePath` alongside `scopeBase`; AC-4 names only `scopeBase` | Delete both. `statePath` is documented as "optional (#204, with `scopeBase`)", is passed only by the Stage-8 slice-mode block, and its sole consumer is the stacked-slice prompt injection AC-4 explicitly retires. Keeping a param whose only reader is deleted would leave dead surface | codebase-derived |
| D-g | Commit boundaries | Two commits. Commit 1 = Part 1 (execution path + both tools + every reference, atomic per #262 Step 3). Commit 2 = Part 2 (state/scope contracts + all readers + `slice-scope.sh` + the stacked e2e legs/fixture, atomic per #262 Step 4). The e2e stacked legs ride commit 2 because leg `(sl4)` drives `slice-partition-set`, a commit-2 deletion | codebase-derived |

## Affected files/modules

All paths verified present in the worktree. Unverified references: none. No files are created, so no `[NEW]` tags appear in this plan.

**Deleted outright (4):**

- `plugins/dev-pipeline/skills/run/tools/max-pushed-slice.sh`
- `plugins/dev-pipeline/skills/run/tools/start-slice.sh`
- `plugins/dev-pipeline/skills/run/tools/slice-scope.sh`
- `plugins/dev-pipeline/skills/run/e2e-replay-fixtures/stacked-prs.json`

**Commit 1 — execution path:**

- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — `## Stacked-PR Outer Loop` through end of file (lines 314–426), plus the slice-touch threshold line (240) and the slice mention in the jira delta (16)
- `plugins/dev-pipeline/skills/run/stages/2-worktree.md` — slice-branch/suffix derivation (24–49), the `currentSlice > M+1` sanity stop (51–74), prior-slice worktree base (88–92), prior-slice fetch (133–141), stacked notes (192, 207)
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — stacked PR-base targeting (16–24, 123–155), the Stacked-PR body template (304–328), the stacked report/label/terminal notes (185, 204, 344, 346, 374, 396)
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — **two independent executor regions, both required**: the stacked-prs scenario block (296–~390, which drives `$SCOPE`) and the separate `start-slice precedence (AC-5)` section (716–780, which drives `$START_SLICE_SH`). Plus the `$SCOPE`/`$START_SLICE_SH` variable resolutions (96–97) and their exit-99 preflight lines (105–106), the header's `start-slice` scenario-map entry (25), the `BLOCKED ON #211` block (50–55), and the block-(B) `currentSlice > M+1` debt item (72–73, per D-e)
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — the `$MAXSLICE` resolution (28) + its exit-99 preflight (33), and the `(mps)` section including the `mps()` helper (391–~440)
- `plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh` — the `$MAXSLICE` resolution + exit-99 preflight (68, 75) and scenario-4 legs `(sl1)`–`(sl3)` (450–499); the header's scenario-4 description (48–52)
- `plugins/dev-pipeline/skills/run/tools/review-harness-fixtures/harness-plan-alpha.md` — the retired-tool path reference (99)
- `plugins/dev-pipeline/skills/run/tools/tracker/README.md` — the `max-pushed-slice.sh` consumer note + stacked branch shape (54) — per D-a
- `plugins/dev-pipeline/skills/run/tools/tracker/jira/README.md` — the parallel adapter's stacked branch-shape prose (36) — per D-a
- `plugins/dev-pipeline/skills/run/tools/predecessor-gate.sh` — two design-precedent comments naming the dead file (17, 38) — per D-a
- `schema/second-shift.config.schema.json` — the `branchPrefix` description (31) — per D-a/D-c
- `CLAUDE.md` — coverage-register lines for the three deleted tools (77–78); the run-#204 anecdote (118) rephrased as historical
- `docs/testing.md` — the same anecdote (42) rephrased as historical

**Commit 2 — state and scope contracts:**

- `plugins/dev-pipeline/skills/run/state-schema.md` — § Stacked-PR AC partition, § Stacked-PR slice state, the `decomposition` stanza, the four flat slice fields (94–97), the `worktreeBase` rewrite (96, per D-d), the `require_mutable` enumeration (58, per D-d), the Worktree "Stacked-PR note", and the `mark-completed` stacked sentence
- `plugins/dev-pipeline/skills/run/statectl.sh` — `cmd_slice_set` (1464–1521), `cmd_slice_partition_set` (1523–…), both dispatch rows, the usage banner (47), the `require_mutable` comment (494), the stacked-sidecar caveat (675–678)
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — the slice-set / slice-partition-set sections
- `plugins/dev-pipeline/skills/run/tools/plan-lint.sh` — Check-3 slice mode (17–20, 190–233)
- `plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` — the slice-mode cases
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` — the scope-gate slice mode block (101–117) and the `scopeBase`/`statePath` dispatch lines (148–150)
- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — the `scopeBase` + `statePath` params (104–114), `scopeRange`/`scopeBaseRef` (137–147), the stacked-slice prompt injection (355–364) — per D-f
- `plugins/review-toolkit/agents/scope-completeness-reviewer.md` — Step 4c (109–127)
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — the slice split-factor (375) and its render line (470)
- `plugins/dev-pipeline/skills/run/verifyctl.sh` — header re-attribution of `worktreeBase` to `worktree-set` (22–23), the two stacked-slice framing comments (49, 316), the stale-sidecar comment (368)
- `plugins/dev-pipeline/skills/run/SKILL.md` — the Stage-1 carry-forward row (506), the five stacked resume/idempotency rows (550–554), the two failure-mode rows (576–577), the per-slice overwrite note (618)
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — the stacked-slice scoping clause (60)
- `plugins/dev-pipeline/skills/pr-revision/SKILL.md` — the stacked-PR base check (191, 320, 371)
- `plugins/dev-pipeline/skills/run/doc-update.md` — the stacked-slice comment (34)
- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — the "Stacked PR slice N" bullet (15) and the traceability rule's slice-mode paragraph (41). **The `{slice}` / `SLICE_SUFFIX` mechanics at 10–12 stay** (assumption 2)
- `plugins/dev-pipeline/skills/run/stages/5-implement.md` — the stacked framing on the range derivation (37, 45); the `{slice}` substitution at 206–207 stays
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` — the stacked-slice framing (22, 125) and the later-slice dead-export caveat (136)
- `plugins/dev-pipeline/skills/run/stages/10-cleanup.md` — the per-slice cleanup clause (5)
- `plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh` — leg `(sl4)` (501–512) and the fixture deletion

**Confirmed false positives — no edit:**

- `plugins/review-toolkit/agents/a11y-reviewer.md` and `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` — "stacked" in the CSS/layout sense.
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/smokes/gate-1-shim-loader.sh:100,102` — the strings `05-large-feature-stacked` / `09-resume-guard-stacked` are **fixture directory names**, not machinery references. The fixtures are not deleted by this PR, so renaming them would break the smoke; #262 assigns the eval rubric to PR 1's scope. The sibling baseline docs (`FIXTURE-AUDIT.md`, `CLOSEOUT-BASELINE.md`, `FINAL-REPORT.md`) are landed records, same class as `docs/plans/`.

## Reuse inventory

`none — no new helpers introduced`. This PR only removes code; every surviving helper (`statectl.sh`'s `require_mutable`, `atomic_write`, `sget`; `verifyctl.sh`'s base-ref derivation; `plan-lint.sh`'s Check-3 full-snapshot universe) is reused exactly as-is with its slice branch excised.

One reuse decision worth naming: `tools/plan-lint.sh` Check 3 does **not** need a replacement universe — deleting slice mode makes the universe unconditionally the full AC snapshot, which is the pre-#204 behavior the code still contains. The deletion restores an existing path rather than authoring a new one.

## Implementation steps

### Commit 1 — `refactor(dev-pipeline): delete the stacked-PR execution path`

1. Delete `tools/max-pushed-slice.sh` and `tools/start-slice.sh`.
2. `stages/1-intake.md`: delete `## Stacked-PR Outer Loop` and everything below it up to the trailing footer; restore the footer. Drop the >10-files-per-slice threshold line and the slice mention in the jira delta.
3. `stages/2-worktree.md`: collapse the slice-branch derivation to the unconditional single-PR form (`BRANCH="${BRANCH_PREFIX}${ISSUE_NUMBER}"`, `BASE_BRANCH="$BASE_BRANCH_CFG"`); delete the `currentSlice > M+1` guard, the prior-slice `REPO_BASE="$WORKTREE_BASE"` branch, and the prior-slice fetch. Keep the be-fe-pair per-repo loop and the `origin/<base>` remap.
4. `stages/9-open-pr.md`: the PR base is unconditionally the host's configured `baseBranch`; delete the `prBase`/`priorSliceBranch` reads, `$STACKED_ON_LINE`, the Stacked-PR body template, and the stacked report/label/terminal notes.
5. `scenario-liveness-selftest.sh`: delete **both** executor regions — the stacked-prs scenario block *and* the separate `start-slice precedence (AC-5)` section (716–780). A grep for `$START_SLICE_SH` must return zero hits before committing; the two regions are ~400 lines apart and the second is easy to miss. Also delete the two variable resolutions + exit-99 preflight lines, the header's `start-slice` scenario-map entry, the `BLOCKED ON #211` block, and the block-(B) `currentSlice > M+1` debt item (re-count that list from three to two).
6. `statectl-selftest.sh`: delete the `$MAXSLICE` resolution, its exit-99 preflight, and the whole `(mps)` section including the `mps()` helper.
7. `e2e-replay-selftest.sh`: delete the `$MAXSLICE` resolution + preflight and scenario-4 legs `(sl1)`–`(sl3)`; update the header's scenario map.
8. Rewrite the four D-a prose sites (`tools/tracker/README.md`, `tools/tracker/jira/README.md`, `tools/predecessor-gate.sh`, `schema/second-shift.config.schema.json`) and `tools/review-harness-fixtures/harness-plan-alpha.md`.
9. `CLAUDE.md` + `docs/testing.md`: remove the register lines for all three retired tools (`slice-scope.sh` goes in commit 2, but its register line sits in the same sentence as `start-slice.sh` — remove the whole clause here and confirm commit 2 leaves no claim); rephrase the run-#204 anecdote as historical, keeping the scenario-first rationale.
10. Run the full sweep. Commit with a `Changelog:` trailer.

> Step 9 is the one place the two commits touch the same line. Removing the shared register clause in commit 1 means commit 1 briefly deletes a register line for a tool (`slice-scope.sh`) still present — that is a *stale-claim removal*, not a broken preflight, so the sweep stays green. The reverse split would leave commit 1 red.

### Commit 2 — `refactor(dev-pipeline,review-toolkit): retire the stacked AC-partition state and scope-narrowing contracts`

11. Delete `tools/slice-scope.sh` and `e2e-replay-fixtures/stacked-prs.json`.
12. `statectl.sh`: delete `cmd_slice_set`, `cmd_slice_partition_set`, both dispatch rows, the usage-banner line, and the two comment references. Confirm no `failureContext.reason` enum value is slice-scoped before touching the enum tables.
13. `state-schema.md`: delete § Stacked-PR AC partition, § Stacked-PR slice state, the `decomposition` stanza, the four flat slice fields, and the Worktree "Stacked-PR note". Rewrite `worktreeBase` per D-d and drop `slice-set` from the `require_mutable` enumeration.
14. **Regenerate and diff the statectl validators** — `bash tools/gen-statectl-validators.sh > /tmp/statectl.new && diff /tmp/statectl.new statectl.sh`. The `(r1+r5)` drift check requires a byte match after any `state-schema.md` edit; fix statectl to match the regeneration if they diverge.
15. `statectl-selftest.sh`: delete the slice-set / slice-partition-set sections.
16. `tools/plan-lint.sh` + `tools/plan-lint-selftest.sh`: delete Check-3 slice mode and its cases; the universe reverts to the full snapshot.
17. `stages/8-code-review.md` + `workflows/code-review.mjs`: delete the slice-mode block, `SCOPE_BASE`/`STATE_PATH`, the `scopeBase`/`statePath` params, `scopeRange`/`scopeBaseRef` (the scope reviewer uses `range`/`base` like every other reviewer), and the stacked-slice prompt injection.
18. `scope-completeness-reviewer.md`: delete Step 4c. **Verify the `ac-id-rule` LOCKSTEP anchors still resolve** (they sit at lines 61–63, above the deleted region — confirm, do not assume).
19. `pipeline-cost-block.sh`: delete the slice split-factor and its render line; the factor is unconditionally 1.
20. `verifyctl.sh`: re-attribute `worktreeBase` to `worktree-set` in the header; de-slice the two framing comments and the stale-sidecar comment. No behavior change.
21. Residual prose: `SKILL.md` (four sites), `pipeline-retro/SKILL.md`, `pr-revision/SKILL.md`, `doc-update.md`, `stages/3`, `stages/5`, `stages/6`, `stages/10`, and `e2e-replay-selftest.sh` leg `(sl4)`.
22. Run the full sweep + `scripts/lockstep-manifest.tsv` check. Commit with a `Changelog:` trailer.

## Test strategy

**Verify-after** — this is a pure deletion of unreachable code, so there is no behavior to test-first. No new tests are added: #262 D-9 is explicit that the stacked e2e legs are "deleted, not replaced", because a sequential sub-issue run is a plain single-PR run the existing `no-split` fixture already replays.

The guard is the existing suite set, run at **both** commit boundaries:

- `scenario-liveness-selftest.sh` and `e2e-replay-selftest.sh` fail loudly (exit 99) if a deletion and its reference land apart — this is the mechanism that makes the commit boundaries above load-bearing rather than stylistic.
- `statectl-selftest.sh`'s `(r1+r5)` drift check fails if `state-schema.md` and `statectl.sh` diverge after step 13 — the specific reason step 14 exists as its own step.
- `plan-lint-selftest.sh` proves Check 3 still grades correctly against the full snapshot with slice mode gone (AC-5).
- `scripts/lockstep-manifest.tsv` proves the `ac-id-rule` row still resolves after the Step 4c deletion (AC-6).

**No new selftest is warranted.** Per CLAUDE.md's tier map, a new per-tool fixture case must name an invariant no scenario covers; there is no new invariant here — the invariant is *absence*, and absence of a deleted branch is not something a suite can assert without re-encoding the deleted logic.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Retired tools + stacked fixture + stacked liveness scenarios gone; grep-clean (carve-out per D-b) | 1, 5, 6, 7, 8, 11 | — no test (infra-only) |
| AC-2 | Full sweep green at every commit boundary | 10, 22 | — no test (infra-only) |
| AC-3 | CLAUDE.md register makes no claim about a deleted file | 9 | — no test (infra-only) |
| AC-4 | `decomposition`, four slice fields, both statectl subcommands, `scopeBase`, Step 4c gone; `worktreeBase` remains with consumers intact | 12, 13, 17, 18, 20 | — no test (covered-by-selftest) |
| AC-5 | plan-lint grades against the full AC snapshot; selftest + runtime-shim cases pass | 16 | `plan-lint-selftest.sh` Check-3 cases |
| AC-6 | Full sweep green; lockstep `ac-id-rule` anchors resolve | 18, 22 | `scripts/lockstep-manifest.tsv` (`ac-id-rule` row) |

AC-5's "runtime-shim cases" half is **vacuously satisfied**: `workflows/runtime-shim-selftest.mjs` carries no `scopeBase` or slice cases (verified by grep — zero hits). The ticket's scope line anticipated cases that do not exist; nothing to update, and the suite must still pass.

## Verification commands

Run from the worktree root at each commit boundary:

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
node plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs
bash scripts/check-lockstep-pairs.sh
bash scripts/check-frozen-files.sh
bash scripts/check-changelog-trailer.sh
```

The zero-executor check that makes step 5's two-region deletion verifiable:

```bash
grep -rn 'MAXSLICE\|START_SLICE_SH\|\$SCOPE"\|max-pushed-slice\|start-slice\|slice-scope' \
  --include='*.sh' --include='*.mjs' . | grep -v '^\./docs/plans/'   # must be empty
```

Plus, after step 13:

```bash
bash plugins/dev-pipeline/skills/run/tools/gen-statectl-validators.sh > /tmp/statectl.new
diff /tmp/statectl.new plugins/dev-pipeline/skills/run/statectl.sh   # must be empty
```

And the AC-1/AC-4 grep bars, with the D-b carve-out applied:

```bash
grep -rEni 'stacked|max-pushed-slice|start-slice|slice-scope|slicePartition|slice-partition-set|slice-set|currentSlice|sliceBranch|priorSliceBranch|prBase|scopeBase|decomposition\.slices' . \
  --exclude-dir=.git --exclude-dir=node_modules \
  | grep -v '^\./docs/plans/' | grep -v '^\./CHANGELOG.md'
```

The `stacked` and `decomposition.slices` tokens are in the bar deliberately: the residue class this PR polices is mostly *prose* (a comment or table cell describing the retired mode), which the identifier-only tokens cannot see — that narrowness is exactly what let the jira-README mirror in D-a survive the first pass.

Expected residue after both commits: the surviving `{slice}` token sites deferred to #267, and the two confirmed CSS/layout false positives.

## Risks / rollback notes

| Risk | Mitigation |
| --- | --- |
| A deletion and its exit-99 preflight land in different commits → whole sweep red | The commit boundaries are drawn around this (D-g); step 10 and step 22 each run the full sweep before committing |
| A second, distant executor region for the same tool is missed | Realized once already in review: `scenario-liveness-selftest.sh` drives `start-slice.sh` from a section ~400 lines below the stacked-prs block. Step 5 names both regions and the zero-executor grep above is the mechanical check |
| `state-schema.md` edit desyncs the generated statectl validators | Step 14 regenerates and diffs explicitly, before the sweep |
| Deleting Step 4c disturbs the `ac-id-rule` LOCKSTEP anchors | The anchors sit above the deleted region; step 18 verifies rather than assumes, and `check-lockstep.sh` is a hard gate |
| Over-deletion: removing `worktreeBase` or `{slice}` mechanics that must survive | Explicit in assumptions 2 and 4; the grep bar above deliberately excludes `worktreeBase`, and `verifyctl.sh`/Stage-5/Stage-6 behavior is comment-only |
| A "stacked" grep hit in an unrelated sense gets edited | The two known false positives are enumerated and confirmed; any new hit is read before editing |

**Rollback:** the branch is a pure deletion against `origin/main` with no migration and no state-format change. Reverting the merge commit restores the previous tree exactly; no consumer state file needs repair, because no live run writes the deleted fields.

## Out-of-scope

- The `{slice}` `planFilePattern` token, the `configVersion` bump, and its migration doc — #267 (D-12).
- Any change to the parallel `sub-issues` path or to `predecessor-gate.sh`'s behavior (only two of its comments are reworded).
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/**` — landed baseline records; the eval rubric belongs to #262's PR-1 scope.
- `docs/plans/**` and `CHANGELOG.md` — historical landed-record artifacts (#262 Migration); `CHANGELOG.md` is additionally CI-frozen.
- Plugin `version` fields and `.claude-plugin/marketplace.json` — CI-frozen; versions are derived at release time.
