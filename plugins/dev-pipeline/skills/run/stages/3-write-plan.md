# Stage 3. Write Implementation Plan

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 3 begins with `statectl set-stage "$ISSUE_NUMBER" 3 --status started` BEFORE reading the issue and authoring the plan file below. Plan authoring takes real time, so deferring the started-write until the closing state writes collapses `stages.3` to a 0:00 window with the authoring work mis-attributed to the Stage 2→3 gap (a state-discipline deviation `/pipeline-retro` flags; `set-stage ... --status completed` also errors with "cannot complete stage 3 with no startedAt" if `startedAt` is missing). Write `started` first.

- Read the full issue body + referenced files from the codebase.
- Bootstrap context: read the repo's `CLAUDE.md` and any repo-local session-state conventions it defines (see its CLAUDE.md).
- **Plan file naming (resolved from config).** The plan directory is `paths.plansDir` (default `docs/plans`) and the file pattern is `stageParams.planFilePattern` (default `{plansDir}/acme-{issueKey}{slice}.md`). Resolve once into `$PLAN_REL` (worktree-relative); every plan-path reference below — and in Stage 4/5 — resolves the same way:
  ```bash
  PLAN_DIR="$(jq -r '.paths.plansDir // "docs/plans"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "docs/plans")"
  PLAN_PAT="$(jq -r '.stageParams.planFilePattern // "{plansDir}/acme-{issueKey}{slice}.md"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "{plansDir}/acme-{issueKey}{slice}.md")"
  # {slice} = "" for a single PR, "-pr${N}" for stacked slice N
  PLAN_REL="$(printf '%s' "$PLAN_PAT" | sed -e "s|{plansDir}|$PLAN_DIR|" -e "s|{issueKey}|$ISSUE_NUMBER|" -e "s|{slice}|${SLICE_SUFFIX:-}|")"
  ```
  - **Single PR:** `$PLAN_REL` (slice empty, e.g. `docs/plans/acme-228.md`)
  - **Stacked PR slice N:** `$PLAN_REL` with `SLICE_SUFFIX=-pr${N}` — plan scope constrained to this slice; references the decomposition plan from the intake comment for context.
- **Resume:** if `$WORKTREE/$PLAN_REL` already exists, skip to Stage 4 (Plan Review).
- Write plan to `$WORKTREE/$PLAN_REL`.
- **Commit the plan into the branch immediately** (bot identity, `docs:` — the plan is Markdown, so it rides the INERT lane and the pre-commit hook skips type-check). This is the first commit on the branch, before any implementation. It guarantees the plan reaches the PR/the base branch like the other `docs/plans/*.md` — committing it only at Stage 10 risks it being stranded if the PR is merged before the late push lands (acme-228 retro). Resume-safe: skip if the plan file is already tracked at HEAD.
  ```bash
  git -C "$WORKTREE" add "$PLAN_REL"
  # bot-commit.sh resolves the bot git identity from config `tracker.bot` (a bare
  # `git commit` would silently commit as the operator — SKILL.md "Bot Identity").
  bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/bot-commit.sh" -C "$WORKTREE" -m "docs(dev-pipeline): plan for #${ISSUE_NUMBER}"
  ```
- **Required plan sections:**
  - Context / problem framing
  - Assumptions
  - **Decision Ledger** — _advisory-tier (NOT one of the 10 hard-linted sections below; `plan-lint.sh` only WARNS on its absence, and the explicit-empty-form / `codebase-derived` / `deferred` cases never trip the Stage-4 gate; deep structural checks are the `intake-toolkit:plan-interview` ledger-lint's job)_. **The one exception** (`plan-lint.sh` Check 4): a **present** row carrying a human-attributed provenance (`user-answered` / `user-delegated`) is a hard FAIL unless the backing `.claude/pipeline-state/{ISSUE_NUMBER}-ledger.md` exists — so authoring such a row in-pipeline without that file (the very negotiation this guards against) hard-aborts Stage 4. Contract: `intake-toolkit:interviewing-baseline`. If a pre-flight `/plan-interview` wrote `.claude/pipeline-state/{ISSUE_NUMBER}-ledger.md` (main repo, pre-worktree — same lifecycle as the Product-Essence Brief), hydrate its rows into this section **verbatim** (resolve it against the MAIN repo, since Stage 3 runs in the worktree: `MAIN_ROOT="$(dirname "$(cd "$(git -C "$WORKTREE" rev-parse --git-common-dir)" && pwd)")"`, then read `$MAIN_ROOT/.claude/pipeline-state/${ISSUE_NUMBER}-ledger.md`). Otherwise author the section in-pipeline with `codebase-derived` / `deferred` provenance ONLY — the autonomous contract forbids prompting, so `user-answered` / `user-delegated` rows can never originate inside a run; a material decision the pipeline cannot ground goes in as `deferred`, and `pipeline-retro` audits undisclosed ones. Trivial work uses the explicit empty form.
  - Affected files/modules
    - **be-fe-pair dual-target (`.targetRepos` has more than one repo, #48):** group this section **by repo** — a `### <repoId> files` subsection per target repo (repo ids from `.targetRepos`, e.g. `### be files` / `### fe files`), each path relative to THAT repo's worktree root. One plan file still covers the whole ticket (a single plan, repo-grouped file lists — not one plan per repo). Stage 5 routes each group's work to the matching worktree and commits there; Stage 7 records a per-repo checkpoint. A single-target pair or any non-pair run keeps the flat single list (no `### <repo> files` grouping).
  - **Reuse inventory** — existing helpers/utilities/services this change should reuse (each grep-verified per the grounding-tag rule below). Any helper the plan invents must be tagged `[NEW]` only after confirming no existing equivalent (the grounding-tag rule owns the `[NEW]` token semantics — this section adds the confirm-no-equivalent obligation, not a second tag vocabulary; mind the reserve-the-literal-token rule for "none" lines). `none — no new helpers introduced` is a valid entry — do not pad this section to look thorough.
  - Implementation steps (ordered, bite-sized)
  - Test strategy (test-first for behavior changes; verify-after for refactors/infra)
  - **Acceptance-criteria traceability** — a table **keyed by AC ID** mapping each acceptance criterion → covering implementation step(s) → covering test(s). One row per ID; see the traceability rule below.
  - Verification commands
  - Risks / rollback notes
  - Out-of-scope
- **Grounding tags (eval criterion 2 scores these literally):** every file path / function / class the plan references must exist in the codebase (verify by grep or read), tagged **`[NEW]`** if the plan creates it, or **`[UNVERIFIED]`** if existence could not be confirmed. Prose like "New `cmd_foo()`" does NOT satisfy the criterion — the literal `[NEW]` tag does. Zero `[UNVERIFIED]` tags may survive into Stage 6.
  - **Reserve the literal `[NEW]`/`[UNVERIFIED]` tokens for per-reference grounding tags ONLY.** Criterion 2 is grep-scored, so the bare token in a register/summary/"none" line (e.g. "`[UNVERIFIED]` none.") reads as a surviving unverified tag and trips a false FAIL. Phrase such lines without the bracketed token — write "Unverified references: none" (or "No unverified references"), not "`[UNVERIFIED]` none".

- **Acceptance-criteria traceability rule.** The table is `| AC ID | Criterion (short) | Step(s) | Test(s) |`, one row per `AC-n`. The AC set is **snapshot-authoritative**: when state carries a non-empty `acceptanceCriteria[]` (the Stage-1 intent snapshot), key the table by those exact IDs — do NOT re-derive from the live issue (it may have been edited since intake). Explicit `AC-n` labels in the snapshot win; otherwise the fallback rule ([`state-schema.md` § Intake intent snapshot](../state-schema.md) — normative) already fixed the IDs at Stage 1. Each row's Test(s) cell is either a concrete test (a `(AC-n)`-suffixed title where natural) or the exact escape hatch `— no test (<category>)` with `<category> ∈ {non-functional | infra-only | covered-by-selftest | covered-by-render-verify}`. A refactor/chore with no ACs leaves the table header present with no rows (the empty-table case the lint passes when the snapshot is empty).

- **Advisory self-lint (before the plan commit).** Run the plan structure lint and fix any violation it names (max 2 attempts, advisory — never abort here; the Stage-4 gate is the hard stop). Re-run before the plan commit, or amend the commit if a fix landed after it:

  ```bash
  # The state file lives in the MAIN checkout (crash-recovery state outlives the
  # worktree). `statectl state-path` resolves it — honoring paths.pipelineStateDir and
  # the ticket-key lowercasing — so no manual git-common-dir reconstruction is needed.
  bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/plan-lint.sh" \
    "$WORKTREE/$PLAN_REL" \
    "$(statectl.sh state-path "$ISSUE_NUMBER")"
  ```

### Unit test surface (apps/api behavior changes)

Classify whether this ticket needs mutation-resistant unit test work, then persist it for Stages 4–5. Scope is the **backend TypeScript source matched by config `commands.<host>.unitTestScope`** (the acme value — used in every `apps/api/src/**` example below — is `apps/api/src/**`; ML/Rust are out of scope — see [`unit-testing`](../../unit-testing/SKILL.md)). A repo with no `unitTestScope` configured has no mutation surface and skips the gate.

- **`skip`** when the change is FE-only, pure config/CI/docs/dependency, or otherwise has no behavior change in the configured `unitTestScope` surface (acme: `apps/api/src/**`). Include a one-line `skipReason`. A repo with no `unitTestScope` configured always skips (no mutation surface).
- **`strengthen`** when behavior in the configured `unitTestScope` surface changes (acme `apps/api/src/**`: a service/controller/worker branch, guard, or `userId`-scoped query). Then the plan's **Test strategy** section MUST also enumerate, per [`unit-testing`](../../unit-testing/SKILL.md):
  - **Mutation targets** — concrete branches/edge cases tests must kill (one per new/changed conditional; cross-user isolation when `userId`-scoped). Not generic "test the service".
  - **Mock boundary** — which collaborators are real vs mocked (mock only the Drizzle handle / external I/O).
  - **Spec paths** — co-located `*.spec.ts` to create or extend.
  - **Integration decision** — `integrationAction`: `run | skip` with reason.
- If classification is genuinely ambiguous (behavior-change vs skip unclear), abort rather than guess:
  ```bash
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason unit-test-surface-ambiguous --stage 3 \
    --json "$(statectl.sh build-failure-context \
      --reason unit-test-surface-ambiguous --stage 3 --kv-lines candidates="$CANDIDATES_LOG")"
  ```

**Persist `unitTestSurface`** before `set-stage 3 --status completed` (statectl-owned — never raw jq):

```bash
statectl.sh unit-test-surface-set "$ISSUE_NUMBER" --json '{
  "applicable": true, "action": "strengthen",
  "planPath": "'"$PLAN_REL"'",
  "modulesTouched": ["apps/api/src/..."], "specPaths": ["apps/api/src/.../*.spec.ts"],
  "mutationTargets": ["..."], "integrationAction": "skip"
}'
# skip case: --json '{"applicable":false,"action":"skip","skipReason":"FE-only / no apps/api behavior change"}'
```

- Comment via `$GH_BOT issue comment $ISSUE_NUMBER --body "..."`: `stage: plan`, `status: written`.

### Design-faithful FE spec (designDriven runs)

When `statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designDriven'` is `true`, the standard plan above is still written **and** a faithful acme FE spec is produced from the handoff — the spec is the design contract Stage 5 implements against and Stage 4 gates. Skip this entire sub-step on non-design runs (the default). **Select the engine by provider:** read `PROVIDER=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.provider')` and dispatch the matching produce engine (`implement:false` → spec only, no code). Resolve the worktree to an absolute path first (the engines have no filesystem access).

**`claude-design`** — dispatch `design-sync.mjs`:

```
PROJECT_ID=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.projectId')
SCREEN=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.screen')
Workflow({
  scriptPath: "workflows/design-sync.mjs",
  // The caller also passes args.config = the parsed second-shift.config.json.
  args: { kind: "produce", implement: false, projectId: "$PROJECT_ID", screen: "$SCREEN",
          specPath: "docs/design-specs/$SCREEN-spec.md", issue: "$ISSUE_NUMBER", config: CONFIG }
})
# Returns { kind, implement, result } | { kind, implement, failClosed } | { kind, budgetExhausted: true }.
```

**`figma`** — dispatch `figma.mjs` (BE session → FE worktree; arg contract in the workflow header):

```
FE_WT="$(git rev-parse --show-toplevel)/$(statectl get "$ISSUE_NUMBER" '.worktreePath')"   # [FE] ticket's worktree = the FE worktree (same resolution as claude-design's WT)
SCREEN=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.screen')
FIGMA_SOURCES=$(statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designSource.figmaSources')
Workflow({
  scriptPath: "workflows/figma.mjs",
  args: { kind: "produce", feWorktree: "$FE_WT", target: "design-toolkit:figma-faithful-spec",
          inputs: { figmaSources: FIGMA_SOURCES }, outputPath: "docs/design-specs/$SCREEN-spec.md",
          framesDir: ".claude/pipeline-state/$ISSUE_NUMBER-figma-frames", produceArgs: { implement: false },
          jiraKey: "$ISSUE_NUMBER" }
})
# Returns { kind, target, feWorktree, result } | { kind, target, feWorktree, budgetExhausted: true }.
# result = { status: "ok"|"error", artifactPath, committed, commitSha, summary }, optionally { infraFailure: true }.
```

Handle the result exactly like the other engine dispatches (mirrors Stage 4's unit-test plan-review posture). The two engines share the same three outcomes; note the figma envelope difference:

- **`budgetExhausted: true`** — clean skip for token budget (NOT a defect). Stop and tell the operator to re-run; do **not** `mark-failed`.
- **`result.infraFailure: true`** — the produce agent died without StructuredOutput after the engine's inline retries. Re-dispatch **once**; still infra → surface as an infra failure, never `mark-failed --reason design-source-unreachable`.
- **Handoff unreadable** — map to the single pipeline reason `design-source-unreachable`. The two engines signal this differently: **claude-design** returns `failClosed.reason` (any of the engine's four `FAIL_CLOSED` values → carry it in `engineFailClosed`); **figma** returns `result.status === "error"` (the Figma MCP was unreachable / the sparse dump did not resolve → carry the `result.summary` in `engineFailClosed`). Either way:

  ```bash
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason design-source-unreachable --stage 3 \
    --json "$(statectl.sh build-failure-context \
      --reason design-source-unreachable --stage 3 --kv engineFailClosed="$ENGINE_REASON")"
  ```

  Comment + keep worktree + STOP rc=0.

- **Success** — record the returned `artifactPath` (claude-design) / `result.artifactPath` (figma) — the FE spec — for Stage 4's gate and Stage 5's implement. The spec lives alongside the plan as an additional reviewable artifact.

---

_Stage 3 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
