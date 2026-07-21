# Stage 4. Plan Review (single pass, sequenced Workflow)

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 4 begins with `statectl set-stage "$ISSUE_NUMBER" 4 --status started` BEFORE the pre-dispatch steps below.

The plan gates — `plan-reviewer`, design FE-spec review (designDriven runs), unit-test plan review (strengthen surface) — run as ONE deterministically-sequenced Workflow dispatch (`workflows/plan-review.mjs`). The script chains them strictly serially with first-block short-circuit, enforces the trinary→action mapping in JS, and returns a single consolidated verdict — the mandated dispatches cannot be individually skipped or paraphrased. The plan-reviewer emits a single trinary verdict — no revise-and-re-review loop.

## Pre-dispatch (in-session — the script cannot read files)

1. **Plan-structure hard gate (mechanical check precedes agent spend).** Run the plan lint over the committed plan + the state snapshot. Stage 3 already ran it advisorily with a 2-attempt fix budget; a failure here is final → abort:

   ```bash
   MAIN_ROOT="$(dirname "$(cd "$(git -C "$WORKTREE" rev-parse --git-common-dir)" && pwd)")"
   # Resolve the plan path from config (paths.plansDir + stageParams.planFilePattern; defaults preserve the literal)
   PLAN_DIR="$(jq -r '.paths.plansDir // "docs/plans"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "docs/plans")"
   PLAN_PAT="$(jq -r '.stageParams.planFilePattern // "{plansDir}/acme-{issueKey}{slice}.md"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "{plansDir}/acme-{issueKey}{slice}.md")"
   PLAN_REL="$(printf '%s' "$PLAN_PAT" | sed -e "s|{plansDir}|$PLAN_DIR|" -e "s|{issueKey}|$ISSUE_NUMBER|" -e "s|{slice}|${SLICE_SUFFIX:-}|")"
   LINT_STDERR="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/plan-lint.sh" \
     "$WORKTREE/$PLAN_REL" \
     "$(statectl.sh state-path "$ISSUE_NUMBER")" 2>&1 1>/dev/null)" || {
     statectl.sh mark-failed "$ISSUE_NUMBER" \
       --reason plan-structure-invalid --stage 4 \
       --json "$(statectl.sh build-failure-context \
         --reason plan-structure-invalid --stage 4 --kv-lines violations="$LINT_STDERR")"
     # comment (stage: plan-review, status: blocked), keep worktree, STOP rc=0
   }
   ```

   Note for the plan-reviewer dispatch below: structural/coverage-row presence is now mechanical — the reviewer judges mapping _quality_, not section/row presence.
2. **Skip-plausibility check (in-session, no dispatch).** When `unitTestSurface.action == "skip"`: verify `skipReason` is plausible and affected files confirm no behavior change in the configured `unitTestScope` surface (acme: `apps/api/src/**`).
3. **Assemble applicability flags from state** so the script's gate skips are deterministic:
   - `design.enabled = stageCheckpoint["1"].designDriven == true`; when enabled, `design.provider` = `stageCheckpoint["1"].designSource.provider` (selects the spec rubric) and `design.specPath` = the Stage-3 FE-spec artifact (`docs/design-specs/<screen>-spec.md`).
   - `unitTests.enabled = (unitTestSurface.applicable && unitTestSurface.action == "strengthen")`.
   - `planGates` = the config `planGates` (EP-8) whose `surface` glob matches a path in the plan's **Affected files/modules** section (a planGate with no `surface` always applies). Pass the applicable set `[{name, surface, agent}]`; an empty set is fine (no additive plan gates). These run after the built-in gates and are additive-only — a `block` cannot waive a built-in gate.
4. **Resolve paths.** `WT="$(git rev-parse --show-toplevel)/$(statectl get "$ISSUE_NUMBER" '.worktreePath')"` — the workflow takes an **absolute** `worktree` (it has no filesystem access to resolve a relative path; same contract as `code-review.mjs`). `briefPath` = `statectl get "$ISSUE_NUMBER" '.briefPath'`; when non-null (an orchestrator Step-0.5 run — rare in acme), resolve it to an **absolute main-repo path** (`"$MAIN_ROOT/.claude/pipeline-state/${ISSUE_NUMBER}-brief.md"`); otherwise pass literal `null` — never worktree-relative (worktrees don't carry gitignored main-repo files).

## Dispatch

```
Workflow({
  scriptPath: "workflows/plan-review.mjs",
  // The caller also passes args.config = the parsed second-shift.config.json (repo-local
  // reviewers from config `reviewers.add` are referenced bare; plugin reviewers qualified).
  args: {
    worktree: "$WT",
    planPath: "$PLAN_REL",
    issue: "$ISSUE_NUMBER",
    config: CONFIG,
    workflowsDir: "workflows",
    design:    { enabled: <bool>, provider: "<claude-design|figma>", specPath: "docs/design-specs/<screen>-spec.md" },
    unitTests: { enabled: <bool>, planPath: "<unitTestSurface.planPath or the plan file>",
                 modulesTouched: <unitTestSurface.modulesTouched>,
                 mutationTargets: <unitTestSurface.mutationTargets> },
    planGates: [<applicable EP-8 plan gates: {name, surface, agent}>],
    briefPath: "<state.briefPath as ABSOLUTE main-repo path, or null>"
  }
})
```

When `briefPath` is non-null, the script folds it into the plan-reviewer prompt: a plan step contradicting a resolved QUARANTINE decision or user guardrail in the Brief is a Blocker.

The script runs `plan-reviewer` as a direct `agent()` (reasoning tier, full staller stack: output mandate + `BOUNDED_PLAN_GROUNDING` dispatch-time nudge + ONE escalated inline retry + 15-min ceiling — the retry count is 1, not 2, and the retry prepends an emit-early preamble rather than repeating the attempt verbatim), the design FE-spec gate as a **second plan-reviewer dispatch** over the FE-spec artifact with the provider-appropriate rubric (`design-toolkit:design-faithful-spec` for claude-design, `figma-faithful-spec` for figma — the claude-design family has no dedicated design-spec-reviewer agent, so both use the rubric-driven plan-reviewer path; `*-faithful-reviewer` agents review **code**, not specs), the unit-test gate as a nested `workflow()` into `unit-tests.mjs` (`kind: "plan-review"`) — its own budget/staller handling preserved — and then any **EP-8 `planGates`** as additive trinary plan reviewers (each dispatched with the same staller stack; strictly serial, first-block short-circuit). All built-in gates always appear in the returned `gates[]` (with `skipped` markers when not run), and each plan gate appears as `plan-gate:<name>`, so `pipeline-retro` can audit coverage.

## Verdict handling (in-session)

Apply the consolidated return `{gates[], overall}`:

| `overall`        | Action                                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pass`           | Record `planReview` (below), comment `status: passed`, `set-stage 4 --status completed`, proceed to Stage 5                                                             |
| `fix-and-go`     | Same as `pass` with comment `status: passed-with-warnings`; implementer dispositions the gates' `warnings[]` in Stage 5                                                 |
| `block`          | Fix the blocking gate's Blockers in the plan/spec, then re-dispatch the whole Workflow **once**. Still `block` → `mark-failed` with the mapped reason (table below), carrying `blockers[]` via `--kv-lines`. Interactive mode presents blockers instead. |
| `budget-skipped` | Stop; tell the operator to re-run when budget allows. Do **NOT** map to any `*-block` reason.                                                                           |
| `infra`          | Re-dispatch the Workflow once; still `infra` → surface as an infra abort (stderr posture, cite the gate's `error`). Do **NOT** map to any `*-block` reason.             |

Blocking-gate → reason mapping (the sequencer short-circuits, so exactly one gate carries `verdict: "block"`; both are existing enum members):

| Blocking gate    | `mark-failed --reason`          |
| ---------------- | ------------------------------- |
| `plan-reviewer`  | `plan-reviewer-block`           |
| `design-fe-spec` | `plan-reviewer-block` (the FE spec is part of the plan deliverable — same reason, second trigger path, per state-schema.md) |
| `unit-test-plan` | `unit-test-plan-reviewer-block` |
| `plan-gate:<name>` (EP-8) | `plan-reviewer-block` (an additive plan gate is part of the plan deliverable — same reason, no per-extension enum value) |

**On `block` (autonomous default; example — plan-reviewer):**

- Comment on issue via `$GH_BOT issue comment` with remaining Blockers (`stage: plan-review`, `status: blocked`).
- Label: `$GH_BOT issue edit $ISSUE_NUMBER --add-label needs-plan-review --remove-label in-progress` (use regular `gh` for `--remove-assignee @me` separately).
- Write the failureContext atomically:
  ```bash
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason plan-reviewer-block --stage 4 \
    --json "$(statectl.sh build-failure-context \
      --reason plan-reviewer-block --stage 4 \
      --kv-lines blockers="$BLOCKERS")"
  ```
- Keep worktree (has partial plan for manual rescue).
- **STOP** with rc=0 (the autonomous abort contract).
- **Under `DEV_PIPELINE_MODE=interactive`:** skip the `mark-failed` write; present the blockers to the user and ask how to proceed.

**Record the consolidated verdict (completion evidence).** Before `set-stage 4 --status completed`, on `pass`/`fix-and-go`:

```bash
statectl.sh plan-review-set "$ISSUE_NUMBER" --overall <pass|fix-and-go>
```

`set-stage 4 --status completed` mechanically refuses without it (statectl completion precondition) — the "mandated dispatch silently substituted" drift class is closed by the pair: one observable Workflow call + one enforced evidence write.

**State:** `stages.4.status: "completed"` + `stages.4.planReview` on `pass` / `fix-and-go`; `"failed"` on the pre-dispatch lint gate (`plan-structure-invalid`) or a gate `block` (`plan-reviewer-block` or `unit-test-plan-reviewer-block`). No `planReviewRounds` field — single-pass.

The plan-reviewer is direct-callable (carries `<!-- review-lead-skip: ... -->`) and emits a single consolidated trinary verdict per dispatch — no interactive walkthrough.

---

_Stage 4 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
