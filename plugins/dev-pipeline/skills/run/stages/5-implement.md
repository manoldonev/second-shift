# Stage 5. Implement

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 5 begins with `statectl set-stage "$ISSUE_NUMBER" 5 --status started` BEFORE following the plan / writing code below. Implementation is real work, so deferring the started-write collapses `stages.5` to a 0:00 window, and `set-stage ... --status completed` then errors with "cannot complete stage 5 with no startedAt". Write `started` first.

**Implementer delegation (config `implementDelegates`)** — EP-7. When the config registers `implementDelegates: [{ surface, agent }, …]`, matching work items route to a delegate agent **instead of** being hand-coded inline. This **adds** an implementation path; it waives nothing — the delegate's output re-enters the pipeline through the **unchanged** Stage-5 scope-enforcement gate and every downstream gate (Stage 6 verify, Stage 8 review). **With `implementDelegates` absent (the default), skip this block entirely and follow the inline path below exactly as today** — byte-for-byte the current behavior.

- **Resolve delegates from config:** `jq -r '.implementDelegates // []' "$SECOND_SHIFT_CONFIG"`. Each entry's `surface` is a **path glob** OR the reserved surface key **`unit`** (the unit-test surface — the same work the mutation-review section below gates); its `agent` is `<plugin>:<agent>` (a companion-pack agent) or a repo-local bare name (in `.claude/agents/`).
- **Pre-flight fail-closed (note only — the check lives at pre-flight):** every configured delegate `agent` must resolve to a real agent. An **unresolvable agent is a FAIL-CLOSED at pre-flight** — the run stops before Stage 5 does any work; it never silently falls back to inline implementation.
- **Route each work item:** for each plan task / file scope, test it against the configured surfaces. If a work item matches a delegate's `surface`, **dispatch that delegate `agent` (via a subagent / `Workflow`) scoped to that surface** to implement it, instead of hand-coding it inline. Non-matching work items stay on the inline path below. A delegate handles only its matched surface — it is scoped, not a hand-off of the whole stage.
- **Downstream is unchanged:** the delegate's commits are ordinary Stage-5 commits. They flow through the normal Stage-5 completion (the scope-enforcement gate, the unit-test mutation review, the checkpoint) and then Stage 6 verify + Stage 8 review **exactly as inline commits do** — the delegate cannot waive a gate or reinterpret evidence, it only adds the work.

- Follow the plan task-by-task.
- **Check the plan's Reuse inventory (and grep) before creating any new helper** — a near-duplicate of an existing utility is the Stage-6 quality pass's top cleanup target; reusing it now is cheaper than having the pass rewrite it later.
- **Disposition every Stage 4 plan-review warning** — apply it, or record an explicit deferral (with reason) in the Stage 5 checkpoint's `deviations`. A silently un-actioned warning is exactly the deviation class retros exist to catch. **If applying a warning changes a file the plan listed under "NOT changed" (or otherwise excluded from "Affected files/modules"), reconcile the plan's file list in the same commit** — never leave the plan artifact contradicting the diff. A plan that still says "NOT changed" for a file the diff modifies reads as scope creep on review even when the change was surfaced as a deviation.
- **Track fix loops on plan-specific verification commands immediately** — if a verification command from the plan (selftest, custom script) fails during Stage 5 and you fix code or test in response, increment `statectl verify-attempts "$ISSUE_NUMBER" --incr PLAN_CMD_FAILURE` at that moment. Stage 6's rule ("a fix loop on them is a verify fix loop regardless of which stage discovered it") applies here; running the command early does not exempt the loop from tracking. Track per-occurrence and immediately — never reconstruct the count at the end of the stage (a count backfilled after the fact is itself a state-discipline deviation `/pipeline-retro` flags). **The four suite classes (`FORMAT`/`LINT_AUTOFIX`/`TYPE_ERROR`/`TEST_FAILURE`) are charged exclusively by `verifyctl.sh`** — never self-charge them here; a mid-Stage-5 fix loop on the configured test command (config `commands.<host>.test`) that still fails at Stage 6 is charged by verifyctl's re-run detection. A test-first / TDD first-red of a freshly-written test with no implementation yet is expected and never a tracked loop.
- **Test strategy is context-dependent:**
  - Behavior changes / bug fixes: prefer test-first (write failing test → implement → verify)
  - Refactors / infrastructure / config / CI: add or update tests where practical, verify through standard commands
  - **`(AC-n)` traceability convention:** when a test verifies a specific acceptance criterion from the plan's traceability table, attach the literal `(AC-n)` token where the framework can carry it — suffix the test title where the framework has one (`it('… (AC-1)', …)`), or put it in an adjacent comment where it does not (pytest: `def test_foo():  # (AC-1)`). See the `review-toolkit:mutation-review` skill. Best-effort, so the retro's AC-coverage audit can grep the diff for it.
- Commit after each logical chunk (conventional commits, reference issue number in body).
- **be-fe-pair dual-target (`.targetRepos` has more than one repo, #48) — implement in EVERY target worktree, commit per-repo.** A single-target pair or non-pair run implements in the one flat `worktreePath` exactly as above; skip this bullet. For a dual `[BE]+[FE]` ticket the plan's "Affected files/modules" is grouped by repo (Stage 3): work each repo's group **in that repo's own worktree**, resolved from the map — `git rev-parse --show-toplevel` + `statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"<repoId>\".worktreePath"` — and **commit in THAT worktree with `git -C <repo worktree> commit …`** (or `bot-commit.sh -C <repo worktree>`). **Never mix files from two repos in one commit** — one commit lands in exactly one repo's worktree/branch. The secondary repo's changes must actually be authored here; leaving them for later is the exact gap this closes. Everything downstream stays per-repo and unchanged: Stage 6 verifies each worktree (`verifyctl --repo`), Stage 7 records a per-repo checkpoint, Stage 8 reviews each, Stage 9 opens a PR per repo. The unit-test mutation gate below operates on the **mutation-surface repo** (the host whose config carries `commands.<host>.unitTestScope`) — the flat mirror already points `WT` at it, so that section needs no per-repo change.
- **Follow the repo's coding conventions — resolve where they live via the doc router, never a hardcoded doc path.** Stage 5's question is "which conventions apply to the code I am writing now" (the same router answers Stage 7's different question, "which docs are stale"). Resolve against the same declared doc roots, in priority order: (1) the repo's **`CLAUDE.md` context router** — the convention/reference docs it declares; (2) the optional extension **`.claude/second-shift/doc-routing.md`**; (3) fallback — grep the repo's declared doc roots for convention material and disclose that you routed conservatively. Router contract: [`doc-update.md`](../doc-update.md).

**Configuration impact check:** When adding new dependencies, verify they work with existing toolchain configuration (tsconfig, ESLint, bundler, etc.) BEFORE writing application code. If a dependency requires config changes (e.g., `moduleResolution`, `compilerOptions`, ESLint plugins):

1. Research the minimal, correct fix — not just the first thing that compiles.
2. Test the config change against the full codebase (the configured type-check and build commands, config `commands.<host>.typecheck` / `commands.<host>.build`) to catch cascading effects.
3. If the correct fix is too invasive (e.g., monorepo-wide migration), document the workaround and the future fix in an ADR or plan.
4. Never silently add workarounds to shared config files without documenting why.

---

## Unit test mutation review (when `unitTestSurface.applicable == true` and `unitTestSurface.action != "skip"`)

Runs **after** all implementation commits land (including the co-located unit tests, per the repo's configured test-file convention), before `set-stage 5 --status completed`. The worktree is clean, so the gate uses an explicit commit range. Propose + execute + verdict all run inside ONE `mutation-gate.mjs` dispatch — no in-session apply/run/revert (the executions are machine-attested by the workflow journal, not self-reported). See the `review-toolkit:mutation-review` skill for the assertion-strength conventions and blocker taxonomy.

**Worktree + range (resolve once).** The state `worktreePath` is repo-relative; resolve it to an absolute path against repo root, and derive the range against the persisted `worktreeBase` (stacked slices never diff the bare base branch):

```bash
WT="$(git rev-parse --show-toplevel)/$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"
# Config-driven per-host: the host repo id is the topology.repos entry with path ".".
# unitTestScope (acme: apps/api/src/**) bounds the backend diff; testFile ({file}
# placeholder) is the mutation gate's per-spec runner.
HOST_Q='(.topology.repos | to_entries[] | select(.value.path==".") | .key)'
# Base: persisted worktreeBase (stacked slices) else the host repo's configured
# baseBranch — NOT a hardcoded "main" (an alpha/develop-based consumer's diff range,
# and thus the mutation-gate changed-file set, would otherwise be empty/garbage and
# the blocking gate would silently waive itself). Mirror of verifyctl's base_ref.
BASE_BRANCH_CFG="$(jq -r "$HOST_Q as \$h | .topology.repos[\$h].baseBranch // \"main\"" "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo main)"
WORKTREE_BASE="$(statectl.sh get "$ISSUE_NUMBER" '.worktreeBase // empty')"
[[ -z "$WORKTREE_BASE" || "$WORKTREE_BASE" == "null" ]] && WORKTREE_BASE="$BASE_BRANCH_CFG"
HEAD="$(git -C "$WT" rev-parse HEAD)"
BASE="$(git -C "$WT" merge-base HEAD "origin/${WORKTREE_BASE}" 2>/dev/null || git -C "$WT" merge-base HEAD "$WORKTREE_BASE")"
# Schema contract (commands.<host>.{unitTestScope,testFile}): null/absent = OFF /
# no per-spec runner. Resolve with `// empty` — NEVER an acme literal fallback: a
# hardcoded `apps/api/src/**` / `yarn --cwd apps/api test {file}` on a pytest repo
# scopes the diff to a nonexistent path (gate self-waives) or runs yarn on Python
# (rc 127 → every mutant INFRA → run halts). See issue #9.
UNIT_SCOPE="$(jq -r "$HOST_Q as \$h | .commands[\$h].unitTestScope // empty" "$SECOND_SHIFT_CONFIG" 2>/dev/null)"
TEST_FILE_CMD="$(jq -r "$HOST_Q as \$h | .commands[\$h].testFile // empty" "$SECOND_SHIFT_CONFIG" 2>/dev/null)"
# gates.mutation is an explicit off-switch (#15): false disables the gate even
# when a mutation surface (unitTestScope) is configured. Absent/true = honor the
# unitTestScope contract below. `// empty` ⇒ absent resolves empty (not "false").
MUTATION_GATE="$(jq -r '.gates.mutation // empty' "$SECOND_SHIFT_CONFIG" 2>/dev/null)"

# gates.mutation:false ⇒ gate OFF regardless of surface. Else null/absent
# unitTestScope ⇒ no mutation surface ⇒ gate OFF (record + skip the dispatch
# below). Gate ON but null testFile ⇒ no per-spec runner ⇒ FAIL CLOSED (never a
# silent green, never a hardcoded yarn).
if [[ "$MUTATION_GATE" == "false" ]]; then
  echo "[stage-5] unit-test mutation gate OFF: gates.mutation is false (explicit off-switch, overrides unitTestScope)."
  statectl.sh stage-substatus "$ISSUE_NUMBER" --stage 5 --key unitTestMutationReview --value completed
  # SKIP the mutation-gate dispatch below; proceed to `set-stage 5 --status completed`.
elif [[ -z "$UNIT_SCOPE" || "$UNIT_SCOPE" == "null" ]]; then
  echo "[stage-5] unit-test mutation gate OFF: commands.<host>.unitTestScope is null/absent (no mutation surface)."
  statectl.sh stage-substatus "$ISSUE_NUMBER" --stage 5 --key unitTestMutationReview --value completed
  # SKIP the mutation-gate dispatch below; proceed to `set-stage 5 --status completed`.
elif [[ -z "$TEST_FILE_CMD" || "$TEST_FILE_CMD" == "null" ]]; then
  echo "[stage-5] FAIL (fail-closed): mutation gate is enabled (commands.<host>.unitTestScope='$UNIT_SCOPE') but commands.<host>.testFile is null — no per-spec runner, so mutants cannot be executed. Set testFile to your per-spec template (e.g. \"pytest {file}\") or set unitTestScope null to disable the gate. NOT defaulting to the acme yarn form." >&2
  exit 1
fi
CHANGED_BACKEND_FILES="$(git -C "$WT" diff --name-only "${BASE}..${HEAD}" -- "$UNIT_SCOPE")"
```

Recompute `HEAD` (and `CHANGED_BACKEND_FILES`) before any re-dispatch after test-strengthening commits.

1. **Dispatch the mutation gate (ONE call — propose, execute, verdict all inside).** `statectl stage-substatus "$ISSUE_NUMBER" --stage 5 --key unitTestMutationReview --value reviewing`, then dispatch. `mutation-gate.mjs` nests the propose call (`unit-tests.mjs`, propose-only, own staller mitigations) and executes each blocker mutant via a sequential **schema-free** executor agent (apply via Edit → run spec → revert → plain-text `MUTANT_RESULT` line parsed in the script — no StructuredOutput anywhere in the execution phase). Propose `infraFailure` gets ONE in-script re-dispatch.

   ```
   Workflow({
     scriptPath: "workflows/mutation-gate.mjs",
     // The caller also passes args.config = the parsed second-shift.config.json.
     args: { worktree: "$WT", base: "$BASE", head: "$HEAD", issue: "$ISSUE_NUMBER",
             config: CONFIG,
             testFileCommand: "$TEST_FILE_CMD",   // resolved from commands.<host>.testFile
             workflowsDir: "workflows",
             round: 1,
             inputs: { modulesTouched: <unitTestSurface.modulesTouched>,
                       specPaths: <unitTestSurface.specPaths>,
                       changedBackendFiles: [<paths from CHANGED_BACKEND_FILES>],
                       mutationTargets: <unitTestSurface.mutationTargets> } }
   })
   # Returns { overall, round, proposalSummary, mockAuditFindings, executions[], mutationScore, survivedMutants[] }.
   ```

2. **Post-gate worktree assertion (always, before anything else):** `git -C "$WT" status --porcelain`; if dirty (an executor died on the LAST mutant — the script has no Bash to clean up after it), `git -C "$WT" checkout -- .`. Defense-in-depth, stated explicitly: the script aborts its loop on a ceiling-orphaned executor, this assertion heals a dead last executor, and Stage-6 verify is the backstop if both are missed (mutated source fails the suite); a ceiling orphan could theoretically re-dirty the tree after this checkout — the three layers are accepted as sufficient.

3. **Apply the returned `overall`:**

   | `overall`           | Action                                                                                                                                          |
   | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
   | `budget-skipped`    | Stop; tell the operator to re-run when budget allows. Do **not** `mark-failed`.                                                                 |
   | `infra`             | Stop; surface to the operator (the in-script re-dispatch already happened). **Never** `mark-failed --reason unit-test-mutation-reviewer-block`. |
   | `survived-blockers` | Round loop (step 4).                                                                                                                            |
   | `pass`              | Address `mockAuditFindings` (warning+) inline if any, run affected tests, commit if changed. Continue to step 5.                                |

4. **Round loop (max 2 rounds, in-session judgment):** strengthen tests per each `survivedMutants[].suggestedFix`, run the affected specs, commit `test:`, recompute `HEAD`/`BASE`/changed files, dispatch `mutation-gate.mjs` again with `round: 2` (fresh Workflow invocation — full re-propose on the new range; survivor-only re-execution would trust round-1 proposals against specs they never saw). Round 2 still `survived-blockers` → `mark-failed --reason unit-test-mutation-reviewer-block --stage 5` (carry `mutationScore` + survived mutants via `build-failure-context --kv-lines`), keep worktree, STOP rc=0.

5. **Persist the audit from the ledger, then close the sub-status:**

   ```bash
   statectl.sh mutation-audit-set "$ISSUE_NUMBER" \
     --json '{"rounds":[{"round":1,"executions":[...],"mutationScore":{"killed":N,"survived":0}}],"finalDisposition":"pass"}'
   statectl.sh stage-substatus "$ISSUE_NUMBER" --stage 5 --key unitTestMutationReview --value completed
   ```

   The audit is composed from the workflow's returned ledger (`executions[]` per dispatch) — machine-attested, never reconstructed from memory.

**Resume** (fresh session re-entering Stage 5): read `stages.5.unitTestMutationReview` — `reviewing` → `git -C "$WT" checkout -- .` first (a dead executor can leave a half-applied mutant), then re-dispatch round 1; `executing` (legacy — pre-sequencer state files only) → treat as `reviewing`; `completed` (or absent when `action == skip`) → standard Stage-5 resume.

---

## Design-faithful implement + live-render verify (when `stageCheckpoint["1"].designDriven == true`)

On a design-driven run the screen is implemented **by the engine**, not hand-coded: the `design-toolkit:design-faithful` skill reads the handoff, writes the repo's FE-app code mirroring the nearest analog (it grounds the FE app dir, primitives, and token vocabulary from `.claude/second-shift/design-tokens/*.md`, or conservative discovery when absent — never a hardwired `apps/web`/shadcn), and commits in-session. Then a live-render verify gate compares the rendered screen against the handoff screenshots. Skip this entire section on non-design runs (the default — hand-code per the plan as above). The `designPlanReview` sub-status tracks the two phases for resume; mirrors `unitTestMutationReview`. Resolve `WT` (absolute worktree path) and `designSource` as for the other dispatches.

1. **Implement via the engine.** `statectl stage-substatus "$ISSUE_NUMBER" --stage 5 --key designPlanReview --value implementing`, then dispatch the engine selected by `PROVIDER=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.provider')`:

   **`claude-design`** — `design-sync.mjs`, `implement: true`:

   ```
   Workflow({
     scriptPath: "workflows/design-sync.mjs",
     // The caller also passes args.config = the parsed second-shift.config.json.
     // worktree anchors ALL engine reads/writes/commits to THIS ticket's worktree —
     // without it implement:true commits land on the session's default checkout, i.e.
     // the wrong branch (F26). Mirrors the figma twin's feWorktree below. $WT is the
     // absolute worktree path resolved above.
     args: { kind: "produce", implement: true, worktree: "$WT", projectId: "$PROJECT_ID", screen: "$SCREEN",
             issue: "$ISSUE_NUMBER", config: CONFIG }
   })
   # implement:true → dispatches the design-toolkit:design-faithful skill, which writes the repo's FE code + commits IN $WT.
   # Returns { kind, implement, result } | { kind, implement, failClosed } | { kind, budgetExhausted: true }.
   ```

   **`figma`** — `figma.mjs`, `produceArgs.implement: true` (writes apps/web + commits in the FE worktree). Resolve the inputs first — `FE_WT` is the `[FE]` ticket's worktree (identical to the claude-design `WT` resolution):

   ```bash
   FE_WT="$(git rev-parse --show-toplevel)/$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"
   SCREEN=$(statectl.sh get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.screen')
   FIGMA_SOURCES=$(statectl.sh get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.figmaSources')
   ```

   ```
   Workflow({
     scriptPath: "workflows/figma.mjs",
     args: { kind: "produce", feWorktree: "$FE_WT", target: "design-toolkit:figma-faithful",
             inputs: { figmaSources: FIGMA_SOURCES, bindingSpecPath: "docs/design-specs/$SCREEN-spec.md" },
             outputPath: "docs/design-specs/$SCREEN-impl.md", produceArgs: { implement: true, specFed: true },
             jiraKey: "$ISSUE_NUMBER" }
   })
   # implement:true → figma-faithful skill writes apps/web + commits in $FE_WT (committed=true, commitSha).
   # Returns { kind, target, feWorktree, result } | { kind, target, feWorktree, budgetExhausted: true }.
   ```

   - **`budgetExhausted: true`** — clean skip; stop and tell the operator to re-run. Never `mark-failed`.
   - **`result.infraFailure: true`** — agent died without StructuredOutput after the engine's inline retries. Assert a clean worktree, re-dispatch **once**; still infra → surface as infra (never `mark-failed --reason design-source-unreachable`).
   - **Handoff unreadable** → `mark-failed --reason design-source-unreachable --stage 5` with the engine detail in `--kv engineFailClosed=<r>` (same mapping as Stage 3: claude-design `failClosed.reason`; figma `result.status === "error"`). Keep worktree, STOP rc=0.
   - **Success** — the engine committed the apps/web changes (figma: in `$FE_WT`, `result.committed === true`); record the changed files.

2. **Live-render verify gate (#84).** `statectl stage-substatus "$ISSUE_NUMBER" --stage 5 --key designPlanReview --value verifying`. The gate is armed by config, not by hope: `LIVE_RENDER=$(jq -c '.design.liveRender // empty' "$SECOND_SHIFT_CONFIG")`.
   - **`liveRender` absent** → record **`render-verify-unavailable`** (detail: `unconfigured`) as a degraded, **non-blocking** condition: note it in the Stage-5 comment / for the PR body and continue. **Do NOT `mark-failed`** — it is not a `valid_failure_reason` (state-schema.md **Design Mode**). The engine's `implement:true` path already self-verifies against the bundled screenshot in-session; this gate is the pipeline-level confirmation when the consumer has wired a render harness.
   - **`liveRender` present** → run the repo-owned render command:
     1. Resolve the working checkout from `.cwd` (a `topology.repos` id; default the `fe` repo when the topology has one, else the sole repo) — and run in **that repo's ticket worktree** (`$FE_WT` for the fe repo), never the main checkout: a main-checkout dev server would render the wrong branch (same trap as F26).
     2. `.readyProbe` set → `curl -sf --max-time 5 "$READY_PROBE"`; failure → degrade `render-verify-unavailable` (detail: `readyProbe failed: <url>`) and continue — the harness's external prerequisite (e.g. a sibling BE) is not up.
     3. Derive the implemented screen's route(s) from the binding spec / plan. Contract: **`{route}` is the app-relative leaf below the feature mount path** (e.g. `prospects`) — the harness owns any shell/org prefix. Substitute `{route}` and `{out}` (absolute PNG path under `<pipelineStateDir>/<issue>-render/<route-slug>.png`) into `.command`; run once per route from the resolved worktree, generous timeout (~240s — cold vite boot is slow).
     4. Nonzero exit, or missing/zero-byte PNG → degrade `render-verify-unavailable` with the failure tail as detail; **never `mark-failed`** (harness flakiness must not abort a run).
     5. Success → `Read` the emitted PNG **and** the cached design frame (the engine's `framesDir`) and compare semantically per the figma-faithful step-9 checklist: placement (control under the right container), sizing/fill (no unintended stretch; fixed dimensions hold), truncation, default/empty state. This is a **semantic** comparison, not a pixel diff — shell chrome and real-vs-placeholder data are non-findings; an empty state is still a valid fidelity check. On a meaningful mismatch, fix in the FE worktree (an in-session fix loop — track via `statectl verify-attempts --incr PLAN_CMD_FAILURE`; the suite classes are verifyctl-owned), re-run the command, re-check.
   - Record the outcome either way in the Stage-5 comment and the Stage-5 checkpoint: `renderVerify: { status: "verified" | "degraded", detail? }`.

3. **Close the sub-status:** `statectl stage-substatus "$ISSUE_NUMBER" --stage 5 --key designPlanReview --value implemented`.

**Completion guard (load-bearing):** on a design-driven run, do **not** write `set-stage 5 --status completed` while `stages.5.designPlanReview` is non-terminal (`implementing` / `verifying`). The value must be `implemented` first. `statectl` enforces the value enum but **not** this completion-ordering rule — it lives here (mirrors the `unitTestMutationReview` completion discipline).

**Resume** (fresh session re-entering Stage 5, design-driven): read `stages.5.designPlanReview` — `implementing` → assert a clean worktree (`git -C "$WT" status --porcelain` empty; `git -C "$WT" checkout -- .` if not) then re-dispatch the engine produce-implement; `verifying` → re-run the live-render verify gate; `implemented` (or absent on non-design runs) → standard Stage-5 resume.

---

## Write the Stage 5 checkpoint (crash recovery)

After all implementation commits land — including the unit-test mutation review and any design-toolkit:design-faithful implement+verify above — and **before** `set-stage 5 --status completed`, write the Stage-5 checkpoint per SKILL.md "Stage Checkpoints — After Stage 5". It is crash-recovery only (never read on the happy path), but its absence leaves a mid-Stage-5/6 resume blind. Unlike Stage 7 there is **no `build-checkpoint-5` helper** — the Stage-1/5 checkpoints are free-shape, written directly (mirrors the Stage-7 inline checkpoint discipline in [`7-doc-update.md`](./7-doc-update.md), without the builder):

```bash
# Resolve the plan path from config (same contract as Stage 3/4; defaults preserve the literal)
PLAN_DIR="$(jq -r '.paths.plansDir // "docs/plans"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "docs/plans")"
PLAN_PAT="$(jq -r '.stageParams.planFilePattern // "{plansDir}/acme-{issueKey}{slice}.md"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "{plansDir}/acme-{issueKey}{slice}.md")"
PLAN_REL="$(printf '%s' "$PLAN_PAT" | sed -e "s|{plansDir}|$PLAN_DIR|" -e "s|{issueKey}|$ISSUE_NUMBER|" -e "s|{slice}|${SLICE_SUFFIX:-}|")"
statectl.sh checkpoint "$ISSUE_NUMBER" 5 --json '{
  "changedFiles": ["..."],
  "commits": ["<sha>"],
  "planPath": "'"$PLAN_REL"'",
  "verifyCommands": ["..."],
  "planRisks": ["..."]
}'
```

Then mark the stage completed (`statectl set-stage "$ISSUE_NUMBER" 5 --status completed`) and proceed to Stage 6.

---

_Stage 5 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
