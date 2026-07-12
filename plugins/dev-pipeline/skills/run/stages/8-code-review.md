# Stage 8. Code Review Loop (max 3 iterations)

**Entry.** Stage 8 normally continues **in-process** from Stage 7 in the same session. A re-invocation that lands here after an interruption (state has `currentStage == 7` + `stages.7.status == "completed"`, fresh session) is a **crash-recovery resume**; the steps marked _(crash-recovery only)_ below apply just to it. Before any review work begins:

1. _(crash-recovery only)_ **Read RUN_ID from persisted state** via `statectl get "$ISSUE_NUMBER" '.runId'`. Reuse it as `RUN_ID` for this resumed session — comments in this session share the same `<!-- run_id: ... -->` marker as the original session, which is the entire point of persisting it. On the in-process path `RUN_ID` is already in memory; skip this read. Invariant: state file must carry top-level `runId` post-S6; missing → fail-fast before any GitHub comment write:
   ```bash
   RUN_ID=$(statectl.sh get "$ISSUE_NUMBER" '.runId')
   if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
     echo "[stage-8] state file has no top-level .runId — invariant violation; aborting before comment write" >&2
     exit 1
   fi
   ```
2. _(crash-recovery only)_ **Record the pause span — this MUST be the FIRST state mutation on resume.** A crash-recovery resume means a session died and a fresh one re-entered; the idle gap between them is a pause that would otherwise inflate the straddling stage's window and the run total. Record one closed span:
   ```bash
   bash statectl.sh pause-add "$ISSUE_NUMBER" --reason session-resume
   ```
   `pause-add` self-anchors `from = current .lastUpdatedAt` (the dying session's final write, still intact) and stamps `to = now`. It MUST run **before step 3 (`set-stage`) and step 6 (`pipeline-session-add`)** — both bump `.lastUpdatedAt`, which would zero the anchor. There is **no shared resume preamble** elsewhere; this Stage 8 entry is the sole fresh-session resume site, so this is the only place `pause-add` is called. On the in-process path there is no pause; skip this step. Consumed by `tools/stage-times.sh` to report effective (compute) time.
3. **Advance `currentStage` to 8** via `statectl set-stage "$ISSUE_NUMBER" 8 --status started`.
4. Read `stageCheckpoint["7"]` via `statectl get "$ISSUE_NUMBER" '.stageCheckpoint."7"'`. Print one-line bootstrap: `Entering Stage 8. Branch: X. Head: Y. Deviations: N. Free note: "..."`.
5. **Verify worktree validity:** `git -C "$worktreePath" rev-parse --is-inside-work-tree` must succeed. If missing or invalid, mark failed and exit:
   ```bash
   statectl.sh mark-failed "$ISSUE_NUMBER" \
     --reason worktree-missing --stage 8 \
     --json "$(statectl.sh build-failure-context \
       --reason worktree-missing --stage 8 \
       --kv worktreePath="$WORKTREE_PATH" \
       --kv hint="re-add via git worktree add")"
   # Build the failure comment in a fresh per-post temp file (mktemp — NEVER a fixed /tmp
   # name; concurrent runs collide on shared names — see SKILL.md "Multi-line comments").
   # printf (not a heredoc) writes the body — a heredoc with <!-- --> markers inside this
   # indented list code block breaks prettier's markdown fences.
   BODY=$(mktemp -t dev-pipeline-worktree-missing.XXXXXX)
   printf '%s\n' \
     '<!-- dev-pipeline -->' \
     "<!-- run_id: $RUN_ID -->" \
     '<!-- stage: code-review -->' \
     '<!-- status: failed -->' \
     '' \
     "Stage 8 could not start: the recorded worktree \`$WORKTREE_PATH\` no longer exists (manual deletion, or a fresh session resumed without it). Re-add it (\`git worktree add\`) and re-run." \
     > "$BODY"
   $GH_BOT issue comment "$ISSUE_NUMBER" --body-file "$BODY"
   rm -f "$BODY"
   # Exit cleanly (rc=0). Do NOT auto-recreate the worktree (could mask user intent).
   ```
6. _(crash-recovery only)_ **Record this resume session for cost attribution:** a crash-recovery Stage 8 session is a distinct Claude session from the Stage 1–7 one, so it records its own native session UUID:
   ```bash
   if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
     bash statectl.sh pipeline-session-add "$ISSUE_NUMBER" \
       --session-id "$CLAUDE_CODE_SESSION_ID" \
       --source interactive
   else
     echo "[stage-8] CLAUDE_CODE_SESSION_ID unset — skipping resume-session cost-attribution record"
   fi
   ```
   `$CLAUDE_CODE_SESSION_ID` is the native Claude Code session UUID the OTel exporter tags as `session.id`. On the normal in-process path the whole run is one session, already recorded at Stage 2 — do NOT add a second session id (and the resume session's UUID would differ anyway). Stage 9's cost-block sub-step unions all recorded sessions when querying OTel.
7. `cd` to `worktreePath`. Begin the Stage 8 review (Workflow dispatch — below).

Steps 3–5 (advance `currentStage`, hydrate from `stageCheckpoint["7"]`, validate the worktree) run on **both** paths; steps 1, 2, and 6 are crash-recovery only. On the in-process path Stage 8 simply continues with the context it already holds.

**DO NOT push to remote until this step completes.** All work stays local until step 9. Pushing before code review is finalized exposes unreviewed code on the remote.

**Dispatch substrate — `Workflow` script.** The reviewer fan-out runs as `agent()` calls inside `workflows/code-review.mjs`. The script owns the fan-out + the `{agentType → model}` table + the findings schema + the scope-completeness evidence-only prompt; **synthesis stays in this session** (review-toolkit:review-lead's Synthesis Rules on the caller's Opus model). Because Workflow scripts have no Bash/filesystem access, this session does the diff sizing + reviewer **selection** (which needs the diff) and passes the result in `args`.

```
for round in 1..3:
  # (a) In-session (has Bash): size + route per review-toolkit:review-lead's Reviewer Routing.
  git -C "$WORKTREE" diff --stat "$BASE".."$HEAD"   # size class + changed paths
  Select reviewers per review-toolkit:review-lead Reviewer Routing:
    - always: review-toolkit:security-reviewer, review-toolkit:performance-reviewer, review-toolkit:maintainability-reviewer
    - Medium/Large: + review-toolkit:complexity-reviewer, review-toolkit:test-coverage-reviewer
    - conditional by path: review-toolkit:db-reviewer / review-toolkit:pipeline-reviewer / review-toolkit:unit-test-mutation-reviewer, plus any repo-registered domain reviewers from config `reviewers.add` (referenced bare)
    - conditional by path: the provider-appropriate design fidelity reviewer + review-toolkit:a11y-reviewer
      when the diff touches apps/web components (apps/web/**/*.{tsx,jsx}). The design reviewer is selected by
      `stageCheckpoint["1"].designSource.provider`: **claude-design** → design-toolkit:design-faithful-reviewer;
      **figma** → design-toolkit:figma-faithful-reviewer; on a non-design run (no provider) the path trigger
      still routes design-toolkit:design-faithful-reviewer as the generic apps/web fidelity reviewer (its
      prior default). a11y-reviewer is shared. A designDriven run always hits this, since Stage 5 implemented
      apps/web from the handoff.
    - review-toolkit:scope-completeness-reviewer iff an issue/ticket is referenced — a GitHub `Closes/Part of #N`, or the run's JIRA ticket key (a JIRA run is always ticket-driven, so this reviewer spawns whenever `tracker.type: jira`). Pass `issue: "$ISSUE_NUMBER"` (the github number or the JIRA key) so the reviewer fetches the right one.

  # (b) Dispatch via the Workflow tool (this skill instruction IS the multi-agent
  #     opt-in). Pass the selected reviewer agentTypes + diff context as args:
  Workflow({
    scriptPath: "workflows/code-review.mjs",
    // The caller also passes args.config = the parsed second-shift.config.json (plugin
    // reviewers are qualified `review-toolkit:`/`design-toolkit:`; repo-local reviewers
    // from config `reviewers.add` are passed bare).
    args: { worktree: "$WORKTREE", base: "$BASE", head: "$HEAD", issue: "$ISSUE_NUMBER",
            config: CONFIG,
            reviewers: [<selected agentType strings>],
            changedFiles: [<from --stat>], prContext: "<branch/PR context; include unitTestSurface.mutationTargets when unit-test-mutation-reviewer is selected; include stageCheckpoint[\"7\"].qualityPassSummary so reviewers VERIFY the applied Stage-6 cleanups instead of re-proposing them — unapplied quality-pass suggestions[] cap at minor/nit (they were already judged out of apply scope); when .briefPath is non-null, include it for the NON-scope reviewers so they can flag plan/impl drift from the Brief's binding intent — but NEVER forward briefPath to scope-completeness-reviewer (its independence contract fetches the issue itself; feeding it derived intent would corrupt the anti-gaslighting property)>" }
  })
  # Returns { range, worktree, reviewers: [{ agentType, result|error }], budgetExhausted? }.
  # An error entry is { agentType, result: null, error }; the script auto-retries
  # ONCE a reviewer that died without StructuredOutput, and if that retry also
  # fails the entry additionally carries { retried: true, failed: true }. A reviewer
  # that exceeds the per-reviewer wall-clock ceiling (REVIEWER_CEILING_MS) reaches the
  # SAME { result: null, retried: true, failed: true } shape, plus { ceiling: true } —
  # a ceiling timeout is a sub-cause of died-after-retry, handled identically. Synthesis
  # MUST surface any result===null entry (and especially a failed:true one) as a
  # DEAD reviewer — never fold it into a clean "no findings". See the
  # "Dark-reviewer handling" subsection below for the full deterministic contract.

  # (c) Load review-toolkit:review-lead for SYNTHESIS ONLY (synthesis-only mode — its dispatch
  #     Pre-flight does not apply; the fan-out already ran in the script).
  #     Run its Synthesis Rules over the returned structured findings.
  #
  #     The Skill load is MANDATORY — there is NO inline fast-path, no matter
  #     how small or clean the finding set looks ("all approvals, one nit" is
  #     not an exemption; cheap-looking rounds are exactly where unloaded
  #     synthesis silently diverges from the Synthesis Rules). The contract
  #     summary below is a REMINDER of what review-toolkit:review-lead enforces, not a
  #     substitute for loading it. If synthesis somehow proceeded without the
  #     load, that is a process violation: say so explicitly in the round
  #     summary and in the issue comment — never paper over it.
  #
  #     Load it FRESH at THIS Stage 8, even if review-toolkit:review-lead was already loaded
  #     earlier in the same session (a prior issue in a batch / ralph-loop run,
  #     or an earlier turn in this conversation). "It's still in my context from
  #     before" is NOT an exemption — re-invoke the Skill. Relying on a stale
  #     in-context copy is the same process violation as not loading at all, and
  #     a fresh-session crash-recovery resume has no earlier load to fall back on,
  #     so the fresh invocation is the only contract that holds on every path.
  Review contract (reminder — review-toolkit:review-lead's rules are authoritative):
    - Deduplicated findings only (no reviewer overlap)
    - Severity: blocker / major / minor / nit
    - Ignore stylistic issues handled by formatter/linter
    - Prioritize: correctness > safety > maintainability
    - Max 10 actionable items per round
    - Scope Completeness Gate uses the scope-completeness-reviewer's result.

  if no blockers or majors: break   # clean path — emit the clean-path comment (below)
  Fix blocker + major findings, commit fixes, then re-run verify DIRECTLY via
  `{verifyctl} run {issue-number}` (fix-loop per Stage 6's exit-code table; the
  verify budget is shared with the initial Stage-6 run — verifyctl's sidecar
  detects the re-run and charges classes itself). The review loop NEVER calls
  `set-stage 6` — Stage 6 is already completed, and re-starting a completed
  stage is refused by the stage machine. On pass, refresh the top-level summary
  via `statectl verify-summary-set` so state matches the re-verified HEAD.
  # If a review-fix introduces an OUT-OF-PLAN change (a file/behavior not in the
  # plan — e.g. a new helper script added to satisfy a blocker), record it in the
  # single deviations ledger so the retro/eval sees it. Record it NOW — in the same
  # round, before moving on — NOT at run end. The ledger write must precede
  # mark-completed; once the run is terminal, deviations-add refuses without --force,
  # and a deviation backfilled post-completion (via --force, or at /dev-pipeline:pipeline-retro
  # time) is itself a silent deviation — exactly the class the retro counts.
  #   statectl.sh deviations-add "$ISSUE_NUMBER" \
  #     --kind <scope-creep|alternate-approach|deferred|surprise> \
  #     --note "<what changed and why>" [--file <path>] [--plan-section <s>]
  # (--stage defaults to 8 → introducedAtStage:8; appends to stageCheckpoint["7"].deviations[].)
```

### Dark-reviewer handling (deterministic)

A reviewer that produces no findings because it went **dark** (never returned a usable result) is NOT a clean "no findings". The contract is deterministic — there is **no** off-substrate improvisation. In particular: **do NOT re-dispatch a dark reviewer directly via the Agent tool**. The on-substrate retry already ran inside `code-review.mjs`; a reviewer still dark after it stays dark for this round.

Two named dark cases (do **not** infer darkness from array length alone):

1. **Died-after-retry (per-reviewer).** The reviewer is **present** in `reviewers[]` as `{ result: null, ... }`, with `{ retried: true, failed: true }` if it also failed its one automatic retry. Exactly that one reviewer is dark; the others are fine. A reviewer that exceeded the per-reviewer wall-clock ceiling (`REVIEWER_CEILING_MS`, #219 — bounds a wedged reviewer so it cannot add ~90 min to the round) reaches this **same** marker shape, additionally carrying `{ ceiling: true }`. It is a **sub-cause** of this case, not a new dark case: the coverage-gap reason stays `died-after-retry` (the `ceiling: true` flag is an optional human annotation for _why_ it went dark — "wall-clock ceiling" — never a new reason token).
2. **Budget-skipped (all-or-nothing).** The return carries `budgetExhausted: true` and `reviewers` is **empty by construction** — the fan-out never dispatched, so **every** selected reviewer (the `args.reviewers` you passed) is dark, not a partial subset.

For either case, synthesize with the reviewers you DO have and **record the coverage gap explicitly** — never silently drop it:

- In the **round summary**: name each dark reviewer and the domain left unreviewed (e.g. "maintainability + test-coverage went dark after retry — maintainability/readability and coverage for this diff were not assessed this round").
- In the **issue comment** (the `stage: code-review` comment): a short "⚠️ Coverage gap" line listing the dark reviewer(s) and reason (`died-after-retry` / `budget-exhausted`), so the gap is visible to a human, not buried.

`review-toolkit:review-lead`'s Synthesis Rules are authoritative for HOW the gap is rendered in the consolidated report (the `[Coverage gap]` line, the `Dark (no output)` Verdicts-table row, and the effect on "Ready to merge?"). This subsection is the pipeline-specific operational contract: no off-substrate re-dispatch, and surface the gap in the round summary + issue comment.

**Audit note:** the audit is observability only and does not gate the push.

### Scope blocker with no code remedy

A Scope Completeness Gate FAIL (review-toolkit:review-lead Step 4) is a hard blocker, but some scope blockers have **no code remedy** — the unsatisfied item is not something the diff can cover this round, and the only fix is (b) **recording an explicit deferral in the issue body** (e.g. an acceptance-criterion half deliberately deferred at intake). Editing a GitHub issue's acceptance criteria is a **human-authority action**: the `auto`-mode permission classifier denies it, and no agent should take it unprompted.

So when the **only** surviving blocker(s) are scope-gate items with no code remedy:

- **`auto` mode (default):** do **NOT** prompt, and do **NOT** burn the remaining rounds (re-running reviewers cannot clear an issue-scope blocker). Short-circuit straight to the exhaustion-style fallback below — this is the autonomous-faithful path; reaching for `AskUserQuestion` here would break the no-input-prompts invariant and hang a headless / `ralph-loop` run.
  - Record exhaustion at the current round: `statectl.sh review-rounds "$ISSUE" --set "$ROUND" --exhausted`.
  - Continue to step 9: draft PR (always) + `needs-deep-review` label + an **Outstanding Review Blockers** section that names each unsatisfied scope item and the recommended human remediation — cover it in a follow-up, or record the deferral in the issue body (with rationale + a linked follow-up issue) and re-run the gate.
  - Comment via `$GH_BOT issue comment`: `stage: code-review`, `status: scope-blocker-no-code-remedy` (a distinct status under the unchanged `code-review` marker — the comment status column is documentation-only, not enum-constrained, so this needs no validator regeneration; the `--set` round count carries the actual round, so this short-circuit is not misreported as three rounds of churn).
- **`interactive` mode:** the gate **may** prompt to record the deferral (consistent with the other interactive-mode gates), then re-run the gate; on decline, take the same fallback as `auto`.

A code-remediable blocker (the diff can be fixed) is unaffected — it stays in the normal fix-and-re-run loop below.

- Minor/nit fixes are best-effort within each round.
- **On the clean path (loop broke with no blockers/majors):** comment via `$GH_BOT issue comment`: `stage: code-review`, `status: passed` if the break happened in round 1, or `status: passed-after-N-rounds` (substitute the actual round count) if fixes were applied across N>1 rounds before the clean round. This is the normal terminating comment for a passing review; the `code-review` marker is identical to the exhaustion path's, so the marker-emission parity selftest is unaffected (it greps only `stage:` tokens). Then continue to step 9.
- **If still blockers after 3 rounds:**
  - Record exhaustion via `statectl`: `statectl.sh review-rounds "$ISSUE" --set 3 --exhausted` (writes `codeReviewRounds` + `codeReviewExhausted: true` in one atomic bundle).
  - Continue to step 9. The PR is already going to be draft (all PRs are draft) — additionally, on PR creation, apply the `needs-deep-review` label and include the Outstanding Review Blockers section in the body.
  - Comment via `$GH_BOT issue comment`: `stage: code-review`, `status: exhausted-after-3-rounds`.

**State:** Write the review counters via `statectl` — clean path: `statectl.sh review-rounds "$ISSUE" --set "$ROUND"` (round count 1–3); exhaustion: `--set 3 --exhausted`. The `--exhausted` flag is additive-only — the subcommand never writes `codeReviewExhausted: false`, so a later plain `--set` cannot reset a recorded exhaustion.

### be-fe-pair dual-target: secondary-repo review (`.targetRepos` has more than one repo, #48)

The main loop above reviews the **primary** target (the flat-mirror worktree that `.worktreePath` points at) exactly as any single-target run does. On a **dual `[BE]+[FE]` ticket** every OTHER target repo is also reviewed here, before Stage 9 — the secondary repo's diff must not ship unreviewed. **Skip this entire subsection** when `.targetRepos` has fewer than two entries (every single-target pair and every non-pair topology — the primary review above was the whole job).

For each repo id in `.targetRepos` that is not the primary:

```bash
PRIMARY_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" '.worktreePath')"
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ "$(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | length')" -gt 1 ]]; then
  while IFS= read -r r; do
    R_WT_REL="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".worktreePath")"
    [[ "$R_WT_REL" == "$PRIMARY_WT_REL" ]] && continue   # the primary was reviewed by the main loop above
    R_WT="$REPO_ROOT/$R_WT_REL"
    R_BASE="$(statectl.sh get "$ISSUE_NUMBER" ".worktrees.\"$r\".base")"
    R_HEAD="$(git -C "$R_WT" rev-parse HEAD)"
    R_MB="$(git -C "$R_WT" merge-base HEAD "origin/$R_BASE" 2>/dev/null || git -C "$R_WT" merge-base HEAD "$R_BASE")"
    # Clean-worktree assertion — a review over the committed state while uncommitted work is
    # invisible is misleading; hard stop, never a silent skip.
    if ! { git -C "$R_WT" diff --quiet && git -C "$R_WT" diff --cached --quiet; }; then
      echo "[stage-8] FAIL: '$r' worktree is dirty — commit/stash/discard before resuming." >&2
      exit 1
    fi
    # No diff on this repo's branch ⇒ nothing to review; record the skip and move on.
    if [[ -z "$(git -C "$R_WT" diff --name-only "$R_MB..$R_HEAD")" ]]; then
      statectl.sh skipped-review-add "$ISSUE_NUMBER" --repo "$r" --reason "no changes on this repo's branch"
      continue
    fi
    # Otherwise REVIEW IT IN-SESSION: run the SAME Workflow fan-out (workflows/code-review.mjs)
    # scoped to THIS worktree's diff — WORKTREE=$R_WT, BASE=$R_MB, HEAD=$R_HEAD. review-lead
    # Reviewer Routing selects reviewers from the diff exactly as for the primary (the
    # design/FE reviewers auto-select when the diff touches UI surfaces per config
    # `design.provider`); synthesize in-session per review-toolkit:review-lead. A surviving
    # blocker/major loops the fix-and-re-run cycle on THIS worktree before proceeding (same
    # 3-round cap as the primary). Then record the outcome:
    statectl.sh cross-boundary-review-add "$ISSUE_NUMBER" --repo "$r" --status completed-in-session
  done < <(statectl.sh get "$ISSUE_NUMBER" '.targetRepos // [] | .[]' 2>/dev/null | tr -d '"')
fi
```

**Non-blocking handoff fallback.** When a secondary repo genuinely cannot be reviewed in this session (its reviewer set is unresolvable, or an interactive-only constraint applies), record a **pending handoff** instead of the in-session review — `statectl.sh cross-boundary-review-add "$ISSUE_NUMBER" --repo "$r" --status pending --worktree "$R_WT_REL" --base "$R_MB" --head "$R_HEAD" --note "run review-lead in this repo's own session"`. Stage 9 already surfaces pending handoffs as PR "review pending" bullets. Either outcome — an in-session `completed-in-session` review, a `pending` handoff, or a `skippedReviews` no-diff record — satisfies the Stage-8 completion precondition for that repo (the escape hatch added in #48 Phase 1), so the run reaches Stage 9 with every target repo accounted for.

---

_Stage 8 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
