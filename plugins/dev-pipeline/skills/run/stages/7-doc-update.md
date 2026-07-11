# Stage 7. Doc Update (in-session, no Task dispatch)

In-session structured pass — no `Task` hop. Scans `.project/` docs (and `CLAUDE.md`, `.claude/agents/`) for references to files or APIs touched in Stage 5, identifies stale documentation, and applies surgical diffs.

Full protocol — change-area → affected-docs map, stale criteria, severity classification, report template, and pipeline-level handling — lives in [`doc-update.md`](../doc-update.md). On invocation, read that file and follow it; do not re-derive the protocol from this section.

At Stage 7 completion the skill body writes the Stage 7 checkpoint, then proceeds **in-process** to Stage 8. The checkpoint hydrates Stage 8's review context and is load-bearing for crash recovery.

**Under `DEV_PIPELINE_MODE=interactive`:** if the doc-update pass finds Blockers, present them to the user inline and ask whether to apply, defer, or abort. Otherwise proceed.

#### Write the Stage 7 checkpoint (both modes)

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 7 begins with `statectl set-stage "$ISSUE_NUMBER" 7 --status started` BEFORE the doc-update scan and the checkpoint write. This stage is checkpoint-centric, so the start write is easy to skip; doing so leaves `stages.7.startedAt` unwritten (`set-stage ... --status completed` then errors with "cannot complete stage 7 with no startedAt"), and even if recovered after the fact, the recorded window collapses to ~0 min with the real doc-update work mis-attributed to the Stage 6→7 gap (a state-discipline deviation `/pipeline-retro` flags). Write `started` first.

Then write the checkpoint before handing off or proceeding. The payload carries `docUpdaterFindings` alongside `verifySummary` (both produced by earlier stages and surfaced to Stage 8 review-toolkit:review-lead). **Source `--verify-summary` from the persisted top-level field** — `VERIFY_SUMMARY_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.verifySummary')"` — not from an in-session value: Stage 6 wrote it via `verify-summary-set`, and a crash-recovery resume into Stage 7 has no in-session Stage-6 result, so the state field is the only copy that survives. (Note: `build-checkpoint-7 --verify-summary` expects a JSON object; on an INERT-lane run the top-level field is the skipped-string — wrap it as `{"lane":"INERT","note":"<string>"}` when composing the checkpoint.)

```bash
# Quality-pass disclosure: composed FROM STATE (crash-recovery safe), defaults {}.
QUALITY_PASS_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.stages."6".qualityPass // {}')"

CHECKPOINT_JSON=$(statectl.sh build-checkpoint-7 \
  --issue "$ISSUE_NUMBER" \
  --branch "$BRANCH" \
  --head "$HEAD_SHA" \
  --worktree "$WORKTREE_PATH" \
  --plan "$PLAN_PATH" \
  --changed-files "$CHANGED_FILES_JSON" \
  --verify-summary "$VERIFY_SUMMARY_JSON" \
  --deviations "$DEVIATIONS_JSON" \
  --free-note "$FREE_NOTE" \
  --plan-risks "$PLAN_RISKS_JSON" \
  --doc-updater-findings "$DOC_UPDATER_FINDINGS" \
  --quality-pass-summary "$QUALITY_PASS_JSON")

statectl.sh checkpoint "$ISSUE_NUMBER" 7 --json "$CHECKPOINT_JSON"
```

The builder validates the payload's flat schema eagerly (ticketKey matches; `branch`/`headSha`/`worktreePath` are non-empty strings; `deviations[].kind` values are in the closed enum) before emitting to stdout — schema errors surface at construction, not at write. `cmd_checkpoint` re-validates as defense in depth, then writes atomically with the writer-suffixed tmp file. `docUpdaterFindings` is free-form markdown — `""` for the no-findings case.

Mark Stage 7 completed (`statectl set-stage "$ISSUE_NUMBER" 7 --status completed`), then proceed in-process to Stage 8. (The `currentStage == 7` + `stages.7.status == "completed"` state is also what a crash-recovery resume detects to re-enter at Stage 8 in a fresh session after an interruption.)

**`deviations[]` discipline:** Each entry is `{kind, planSection, file?, line?, note}` where `kind` is one of `"scope-creep" | "alternate-approach" | "deferred" | "surprise"`. Empty array is acceptable when implementation matched the plan exactly; an empty array PLUS empty `freeNote` triggers a soft warning ("checkpoint produced no observable signal") in the eval ledger. **Quality-pass reverted outcome:** when `stages.6.qualityPass.outcome == "reverted"`, additionally append a `{kind: "surprise"}` deviation naming the reverted cleanup — the reset left no branch trace, so this ledger entry is the only disclosure. An `applied` outcome is disclosed via `qualityPassSummary` alone, not `deviations[]`.

#### Proceed to Stage 8 (in-process)

After the checkpoint write above:

1. **Post the issue comment** via `$GH_BOT issue comment`: `stage: doc-update, status: completed`.
2. **Continue in-process to Stage 8** in the same session. Stage 8 reads the just-written `stageCheckpoint["7"]` from state and begins the review loop.

---

_Stage 7 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
