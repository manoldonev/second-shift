# Stage 7. Doc Update (in-session, no Task dispatch)

In-session structured pass — no `Task` hop. Scans the repo's declared documentation roots (and `CLAUDE.md`, `.claude/agents/`) for references to files or APIs touched in Stage 5, identifies stale documentation, and applies surgical diffs.

Full protocol — change-area → affected-docs map, stale criteria, severity classification, report template, and pipeline-level handling — lives in [`doc-update.md`](../doc-update.md). On invocation, read that file and follow it; do not re-derive the protocol from this section.

At Stage 7 completion the skill body writes the Stage 7 checkpoint, then proceeds **in-process** to Stage 8. The checkpoint hydrates Stage 8's review context and is load-bearing for crash recovery.

**Under `DEV_PIPELINE_MODE=interactive`:** if the doc-update pass finds Blockers, present them to the user inline and ask whether to apply, defer, or abort. Otherwise proceed.

#### Write the Stage 7 checkpoint (both modes)

**First, mark the stage started** — per the global Stage write convention (SKILL.md), Stage 7 begins with `statectl set-stage "$ISSUE_NUMBER" 7 --status started` BEFORE the doc-update scan and the checkpoint write. This stage is checkpoint-centric, so the start write is easy to skip; doing so leaves `stages.7.startedAt` unwritten (`set-stage ... --status completed` then errors with "cannot complete stage 7 with no startedAt"), and even if recovered after the fact, the recorded window collapses to ~0 min with the real doc-update work mis-attributed to the Stage 6→7 gap (a state-discipline deviation `/pipeline-retro` flags). Write `started` first.

Then write the checkpoint before handing off or proceeding. The payload carries `docUpdaterFindings` alongside `verifySummary` (both produced by earlier stages and surfaced to Stage 8 review-toolkit:review-lead). **Source `--verify-summary` from the persisted top-level field** — `VERIFY_SUMMARY_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.verifySummary')"` — not from an in-session value: Stage 6 wrote it via `verify-summary-set`, and a crash-recovery resume into Stage 7 has no in-session Stage-6 result, so the state field is the only copy that survives. (Note: `build-checkpoint-7 --verify-summary` expects a JSON object; on an INERT-lane run the top-level field is the skipped-string — wrap it as `{"lane":"INERT","note":"<string>"}` when composing the checkpoint.)

```bash
# Quality-pass disclosure: composed FROM STATE (crash-recovery safe), defaults {}.
QUALITY_PASS_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.stages."6".qualityPass // {}')"

# be-fe-pair DUAL-target (#48): a single Stage-7 checkpoint spans BOTH repos. When
# `.targetRepos` has more than one repo, build a per-repo manifest — one
# `build-checkpoint-7-perrepo` fragment per repo (the boundary is read from the
# `worktrees` map: Stage-2 branch + worktreePath, Stage-6 verifySummary; HEAD and the
# changed-file set are recomputed per worktree), merged and given the shared envelope.
# Single-target / non-pair runs (targetRepos absent or length 1) take the unchanged
# flat build-checkpoint-7 path in the else branch below.
# LOCKSTEP-BEGIN stage7-dual-target
TARGET_REPOS_JSON="$(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // []')"
if [[ "$(echo "$TARGET_REPOS_JSON" | jq 'length')" -gt 1 ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  TICKET_LC="$(echo "$ISSUE_NUMBER" | tr '[:upper:]' '[:lower:]')"
  CHECKPOINT_JSON=$(
    echo "$TARGET_REPOS_JSON" | jq -r '.[]' | while IFS= read -r r; do
      R_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".worktreePath")"
      R_BRANCH="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".branch")"
      R_BASE="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".base")"
      R_WT="$REPO_ROOT/$R_WT_REL"
      R_HEAD="$(git -C "$R_WT" rev-parse HEAD)"
      R_MB="$(git -C "$R_WT" merge-base HEAD "origin/$R_BASE" 2>/dev/null || git -C "$R_WT" merge-base HEAD "$R_BASE")"
      R_CHANGED="$(git -C "$R_WT" diff --name-only "$R_MB..HEAD" | jq -R . | jq -s .)"
      R_VERIFY="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".verifySummary")"
      # build-checkpoint-7-perrepo wants a JSON object; an INERT-lane verifySummary is the
      # skipped-string — wrap it (same convention as the flat --verify-summary note above).
      echo "$R_VERIFY" | jq -e 'type == "object"' >/dev/null 2>&1 \
        || R_VERIFY="$(jq -n --arg s "$R_VERIFY" '{lane:"INERT",note:$s}')"
      statectl.sh build-checkpoint-7-perrepo \
        --repo "$r" --branch "$R_BRANCH" --head "$R_HEAD" \
        --worktree "$R_WT_REL" --changed-files "$R_CHANGED" --verify-summary "$R_VERIFY"
    done \
    | jq -s 'reduce .[] as $x ({}; .perRepo += $x.perRepo)' \
    | jq --arg k "$TICKET_LC" \
         --argjson tr "$TARGET_REPOS_JSON" \
         --arg pp "$PLAN_PATH" \
         --argjson dv "$DEVIATIONS_JSON" \
         --arg fn "$FREE_NOTE" \
         --argjson prisk "$PLAN_RISKS_JSON" \
         --arg du "$DOC_UPDATER_FINDINGS" \
         --argjson qps "$QUALITY_PASS_JSON" \
         '. + {ticketKey:$k, targetRepos:$tr, planPath:$pp, deviations:$dv, freeNote:$fn, planRisks:$prisk, docUpdaterFindings:$du, qualityPassSummary:$qps}'
  )
# LOCKSTEP-END stage7-dual-target
else
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
fi

statectl.sh checkpoint "$ISSUE_NUMBER" 7 --json "$CHECKPOINT_JSON"
```

The builder validates the payload's flat schema eagerly (ticketKey matches; `branch`/`headSha`/`worktreePath` are non-empty strings; `deviations[].kind` values are in the closed enum) before emitting to stdout — schema errors surface at construction, not at write. `cmd_checkpoint` re-validates as defense in depth, then writes atomically with the writer-suffixed tmp file. `docUpdaterFindings` is free-form markdown — `""` for the no-findings case.

Mark Stage 7 completed (`statectl set-stage "$ISSUE_NUMBER" 7 --status completed`), then proceed in-process to Stage 8. (The `currentStage == 7` + `stages.7.status == "completed"` state is also what a crash-recovery resume detects to re-enter at Stage 8 in a fresh session after an interruption.)

**`deviations[]` discipline:** Each entry is `{kind, planSection, file?, line?, note}` where `kind` is one of `"scope-creep" | "alternate-approach" | "deferred" | "surprise"`. **be-fe-pair dual-target:** when `.targetRepos` has more than one repo, each entry also carries a `repo` field naming which target repo the deviation is in (so the shared ledger stays per-repo attributable); optional otherwise. Empty array is acceptable when implementation matched the plan exactly; an empty array PLUS empty `freeNote` triggers a soft warning ("checkpoint produced no observable signal") in the eval ledger. **Quality-pass reverted outcome:** when `stages.6.qualityPass.outcome == "reverted"`, additionally append a `{kind: "surprise"}` deviation naming the reverted cleanup — the reset left no branch trace, so this ledger entry is the only disclosure. An `applied` outcome is disclosed via `qualityPassSummary` alone, not `deviations[]`.

#### Proceed to Stage 8 (in-process)

After the checkpoint write above:

1. **Post the issue comment** via `$GH_BOT issue comment`: `stage: doc-update, status: completed`. Record the receipt: `"$STATECTL" comment-add "$ISSUE_NUMBER" --marker doc-update --url <html_url>` — Stage-7 completion refuses without it.
2. **Continue in-process to Stage 8** in the same session. Stage 8 reads the just-written `stageCheckpoint["7"]` from state and begins the review loop.

---

_Stage 7 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
