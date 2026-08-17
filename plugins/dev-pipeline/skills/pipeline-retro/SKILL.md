---
name: pipeline-retro
description: 'Post-run retrospective for a dev-pipeline run: independent eval re-scoring, contract-deviation audit, and improvement routing. Run after a /dev-pipeline:run-lean run completes (or aborts); also reads the pre-#348 staged-run corpus.'
---

# Pipeline Retro

Independent retrospective for a completed (or aborted) dev-pipeline run. The dev-pipeline scores its own eval at Stage 9+ — this skill exists because **the executor grading its own homework is structurally generous**. Everything here is scored from on-disk and on-GitHub artifacts by fresh context, never from the executing session's memory of itself.

**Usage:** `/pipeline-retro <issue-number>` — or no argument to use the most recently updated run across both schema eras (`retro-corpus.sh corpus --window 1 --json`, #347).

**Hard rules:**

- `eval-criteria.md` is LOCKED — this skill never edits it. Criteria problems become a _proposal_ in the report, acted on by the human between optimization loops.
- The original `{issue}-eval.json` is never mutated. The retro writes its own artifact.
- The independent scorer is a **fresh subagent** with no access to this conversation — it sees only the artifacts listed below.

## Step 1: Gather run artifacts

**Era-aware (#347).** The two schemas' artifacts do not overlap — determine which one this
run left behind before gathering anything, rather than assuming stage files:

```bash
ISSUE=<n>
if [ -f ".claude/pipeline-state/${ISSUE}-lean-progress.md" ]; then
  ERA=artifact
elif [ -f ".claude/pipeline-state/${ISSUE}.json" ]; then
  ERA=stage
else
  echo "no run artifacts for #${ISSUE} — nothing to retro"; exit 0
fi
```

### era: stage (full-pipeline run)

This era's runs predate #348, which deleted the staged lane. Everything below reads the
**historical corpus as files** — `cat`/`jq` over the state JSON — and calls no deleted
tool; that is what keeps the stage era retro-able after the machinery is gone.

```bash
cat .claude/pipeline-state/${ISSUE}.json          # state: stages, checkpoints, deviations, failureContext
cat .claude/pipeline-state/${ISSUE}-eval.json     # the run's SELF-score
# The run report — Stage 9's durable narrative, written before the terminal
# narration so an API disconnect cannot destroy it. Absent = either a pre-schema
# run or a run that never reached Stage 9's pr-add.
[ -f ".claude/pipeline-state/${ISSUE}-report.md" ] && cat ".claude/pipeline-state/${ISSUE}-report.md"
bash "${CLAUDE_PLUGIN_ROOT}/tools/stage-times.sh" ${ISSUE}   # per-stage wall times + transition gaps
gh api "repos/{owner}/{repo}/issues/${ISSUE}/comments" --jq '[.[] | {user: .user.login, body}]'   # run_id-marked trail
PR_URL=$(jq -r '.prs | to_entries[0].value.url // empty' .claude/pipeline-state/${ISSUE}.json)
# PR diff + commits (if a PR exists): gh pr diff / gh api .../pulls/N/commits
# Plan file: from stageCheckpoint["7"].planPath (read at the PR's head commit if the worktree is gone)

# Intent snapshot (both survive worktree deletion — main-repo + state artifacts):
jq -r '.briefPath // "null"' .claude/pipeline-state/${ISSUE}.json          # Product-Essence Brief (nullable)
[ -f ".claude/pipeline-state/${ISSUE}-brief.md" ] && cat ".claude/pipeline-state/${ISSUE}-brief.md"
jq -c '.acceptanceCriteria // []' .claude/pipeline-state/${ISSUE}.json     # Stage-1 AC snapshot [{id,text,negative,source}]
# Absent .acceptanceCriteria = pre-schema run → skip the AC-coverage audit item (7) in Step 3.
```

### era: artifact (lean/block run — #347)

The artifact schema: progress record, committed verdict record, hook ledger, PR/tracker
trail (`docs/pipeline-manifesto.md` P3's three-record reconciliation). No `{issue}.json`,
no `{issue}-eval.json` self-score, no stage checkpoints — `lean-gate.sh`'s five milestone
gates ARE this run's completion evidence.

```bash
cat .claude/pipeline-state/${ISSUE}-lean-progress.md   # milestone rows (satisfied/attempt/absent, started/concluded), run_id:, session_id:, model:
VREL=$(grep -oE 'verdict_record:[[:space:]]*\S+' .claude/pipeline-state/${ISSUE}-lean-progress.md | awk '{print $2}')
cat "$VREL"                                             # committed verdict record: verdict=, run_id:, session_id:, rounds:, model:
gh api "repos/{owner}/{repo}/issues/${ISSUE}/comments" --jq '[.[] | {user: .user.login, body}]'   # claim + closing comment trail
# The branch is `<tracker.branchPrefix><key>` — the same namespace the staged lane uses (#413).
# Read the composed name off the record rather than rebuilding it: under jira the key is
# lowercased, so `<branch_prefix>${ISSUE}` resolves a branch that does not exist.
BR=$(grep -oE '^branch:[[:space:]]*\S+' .claude/pipeline-state/${ISSUE}-lean-progress.md | awk '{print $2}')
# Every record written before the lane began emitting `branch:` lacks the key, so REFUSE on an
# empty BR rather than falling through: `gh pr list --head ""` is not an error, it answers rc=0
# with the newest open PR in the repo, and the retro would then read a different run's evidence.
if [ -n "$BR" ]; then PR_URL=$(gh pr list --head "$BR" --state all --json url --jq '.[0].url // empty')
else echo "progress record predates the branch: key — resolve the PR from the issue's trail" >&2; fi
# PR diff + commits (if a PR exists): gh pr diff / gh api .../pulls/N/commits
# Hook ledger: .claude/audit/<session-id>.jsonl for each session_id named in the progress
# record (build) and the verdict record (review) — two ledgers, not one, per P10.
# Spec/AC set: the committed docs/plans/{repo-slug}-${ISSUE}-lean.md, its numbered AC-n
# entries stand in for state .acceptanceCriteria[] in Step 3 item 7.
```

## Step 2: Independent eval re-score (fresh context)

**era: artifact — skip this step.** The five `eval-criteria.md` criteria assume a staged run
(`stages.N`, `stageCheckpoint`); this issue does not invent a milestones→criteria mapping
(disposition: pause-and-ask — the operator owns the eval frame, #347's own open region). No
self-score exists to compare against and no independent score is produced. Route a single
`Criteria proposal` in Step 5 ("eval-criteria.md has no block/lean-run mapping yet") the
first time an artifact-era retro reaches this step in a given window — check Step 5's
dedup-against-open-issues search first so repeat retros don't re-propose it.

**era: stage** — dispatch ONE `retro-scorer` agent (Task tool) whose prompt contains: the five criteria definitions copied verbatim from [`../../eval-criteria.md`](../../eval-criteria.md) and the artifact contents from Step 1. The agent ([`../../../review-toolkit/agents/retro-scorer.md`](../../../review-toolkit/agents/retro-scorer.md)) carries the standing re-score rubric — score each criterion PASS/FAIL/N/A strictly by the letter, quote artifact evidence, "absence of evidence is not a PASS", and the ctx-wire-legitimacy rule — and runs on **Sonnet** via its frontmatter, so the harness binds the tier (a prose "use Sonnet" against `general-purpose` would not — it has no frontmatter and inherits the session Opus default).

**Empty-return failure mode.** This dispatch carries no emit deadline, retry, or darkness detection — unlike the Workflow fan-out's `check-emit-deadline.sh` stack, which does not cover a Task-tool dispatch. A `retro-scorer` call that completes with no text (a silent dark return, or a `maxTurns` cutoff) is a named failure, not a run with nothing to score: before doing anything else, resume the *same* agent (its transcript, not a fresh dispatch) and instruct it to emit its verdict from the evidence already gathered, with no further tool calls. This recovered two independently observed dark returns at a fraction of the original dispatch's cost (#271: the #244 run, 78k tokens / 26 tool calls / no output, resumed in 14s / 0 tool calls; the #243 run, 20 tool calls / no output, resumed successfully) — the analysis was sitting in the transcript, only its emission was lost. This resume is scoped to this dispatch: it is not a general Agent-tool-dispatch policy, and `retro-scorer` is deliberately staying off the Workflow substrate — that would buy the emit-deadline stack but adds StructuredOutput-staller surface for what is structurally a single dispatch, not worth it for the resume fix already closing the gap.

If the resumed dispatch **also** returns empty, do not fall back to the self-score and do not silently proceed as if scored. Record it in Step 4 as its own environment-friction item, and carry `DARK — no output after resume` into Step 6's score-comparison table for every criterion (never a blank cell, never the self-score standing in for it).

Then compare against the self-score from `{issue}-eval.json`. **Every discrepancy is a finding** — either the run self-scored generously (process problem) or the criterion is ambiguous (criteria-proposal material). A `DARK` independent score is itself a discrepancy: it means no comparison was possible, not that the self-score is uncontested.

## Step 3: Contract-deviation audit (in-session, checklist)

Walk the run's trail against the skill contracts. For each item answer: complied / deviated-and-surfaced / **deviated-silently** (the worst class — see the Stage 8 review-toolkit:review-lead incident that motivated this skill):

**era: artifact — items 1, 2, 5, 6 read N/A**, not skipped-silently: they audit stage
mechanics (`stages.N.skillsLoaded[]`, stage checkpoints, `stageCheckpoint["7"].deviations[]`,
`stages.5.unitTestMutationReview`) that `lean-gate.sh`'s outcome-gated milestones do not
produce by design (build-lean is "OUTCOME-gated, not process-prescribed" — its own header).
Re-auditing milestone satisfaction here would test lean-gate.sh's own gate against itself;
its selftest already owns that. **Item 3 also reads N/A for `artifact`**, superseded by
`lean-reconcile.sh`, the operator-run pre-merge check that already does this reconciliation
for lean records (run-identity consistency across claim comment, progress record, and
verdict record) — this retro does not duplicate it. Items 4, 7, 8 apply to both eras; for
`artifact`, item 7 reads AC-n from the committed lean spec (`docs/plans/{repo-slug}-{issue}
-lean.md`) instead of state `.acceptanceCriteria[]`, and item 8 reads the Decision Ledger
(if any) from that same spec instead of "the committed plan".

1. **Mandated loads & dispatches** — was every skill the stage files say to load actually loaded (`intake-toolkit:intake-orchestrator`, `review-toolkit:review-lead` for synthesis)? Diff `stages.N.skillsLoaded[]` (the self-reported load evidence the completion gates read) against the session audit ledger (`.claude/audit/<session>.jsonl` — `Skill` tool invocations, whose `target` field carries the skill name, making this an identity diff rather than only a count): a skill recorded in state but absent from the ledger is a **fabricated evidence write**, strictly worse than the silent skip the gate exists to stop. For Stage 8 the *ordering* is now gate-enforced — `comment-add --marker code-review` refuses until the `review-lead` load is recorded — so what still needs eyes is the residual that gate cannot see: compare the ledger's `Skill` timestamp against the synthesis comment's `created_at`, and treat a load that post-dates the published synthesis as a deviation even though the receipt was accepted afterwards. Were sub-agents dispatched for real (never inlined)? Check `/audit` if available.
2. **State discipline** — every stage has `startedAt`/`completedAt`; checkpoints written at 1/5/7; boundary writes (`worktree-set`, `pr-add`) ordered before stage completion; `verifyAttempts` incremented for every fix loop (including plan-specific verification commands — see Stage 6). A Stage-6 `refactor:` commit recorded in `stages.6.qualityPass` is the advisory quality pass — an expected, disclosed, non-`verifyAttempts` event (its one-shot `--no-attempt` safety-net re-verify is not a fix loop).
3. **Comment trail** — every pipeline comment carries `run_id` + a marker from the closed enum (`state-schema.md` "Stage-comment markers"); no duplicates; failures left a comment.
4. **Bot identity** — all writes through `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"`; label swaps add-before-remove.
5. **Deviations ledger** — does `stageCheckpoint["7"].deviations[]` plus the PR body disclose everything the diff/trail shows actually happened? Undisclosed deltas are silent deviations. (An applied Stage-6 quality-pass cleanup is disclosed via `stageCheckpoint["7"].qualityPassSummary`, not `deviations[]` — only a `reverted` outcome requires a `surprise` entry.)
6. **QA-gate integrity** (the mutation gate — the stall-prone surface). On unit-test-applicable runs, `stages.5.unitTestMutationReview` must be terminal `completed` (vocabulary: `reviewing | completed`; `executing` only on legacy pre-sequencer state files), and `mutationReviewAudit.rounds[].executions[]` must be the `mutation-gate.mjs` return ledger — the per-mutant results are **machine-attested by the workflow journal**, so an audit that disagrees with the journal (or an audit written with no corresponding Workflow dispatch) is a fabricated gate. A `budget-skipped` or `infra` overall that still closed Stage 5 with `completed` sub-status is a silent coverage gap.
7. **AC-coverage + brief-reconciliation audit** (skip when state has no `acceptanceCriteria[]` — pre-schema run). For every `acceptanceCriteria[].id`: is it traceable to a covering test (grep the PR diff for `(AC-n)` test titles), a diff hunk that plainly implements it, or a disclosed `deviations[]` / `— no test` traceability row? An AC with none of the three is an **undisclosed coverage gap** — finding. When `briefPath` is non-null, also check the Brief's reconciled QUARANTINE table: any `conflicts`-tagged PM claim the implementation silently followed anyway (the codebase was supposed to win) is a **silent deviation** — finding. Judgment against the surviving diff is expected here; the `(AC-n)` title convention is best-effort ("where natural"), so a covered-but-unlabeled test is satisfied by the diff-hunk leg, not flagged.
8. **Decision Ledger audit** (skip when the committed plan carries no `## Decision Ledger` — pre-convention run). A material design decision visible in the diff (new contract shape, data invariant, migration/backfill ordering, scope cut, `userId`-scope posture) with no ledger row and no `deviations[]` disclosure is an **undisclosed material decision** — finding. In-pipeline plans may only carry `codebase-derived` / `deferred` / `ticket-sourced` provenance (the remaining user-provenance rows come from a pre-flight `.claude/pipeline-state/{issue}-ledger.md`); a `user-answered` / `user-delegated` row with no backing pre-flight ledger file is a **fabrication-class** finding, as is a `ticket-sourced` row whose Resolution cites no comment URL.

## Step 4: Environment friction log

List every mid-run improvisation the trail reveals (REST fallbacks, version workarounds, missing tools, degraded sub-steps like `costBlockApplied: skipped-*`). For each: is it covered by a [`pipeline-doctor.sh`](../../tools/pipeline-doctor.sh) check or canonical-form doc yet? If not, it becomes a routed improvement below.

**era: stage** — also read the `stage-times.sh` output against expectations: an inert-diff run that still paid the configured verify suite (Stage 6 ≳ 4 min on a docs/shell-only diff), large inter-stage gaps (synchronous posting of non-gating comments), or a stage whose recorded window is implausibly short (work done before `set-stage N --status started` — a state-discipline deviation for Step 3) are all findings. **era: artifact** has no per-stage timing table to check against — `retro-corpus.sh`/`stage-envelopes.sh` are `perf-retro`'s territory (cross-run), and this per-run step has nothing stage-shaped to read.

Scope boundary: this step reads **this run's** timing for anomalies. Cross-run trend analysis — the aggregated per-stage profile and the ranked optimization candidates it supports — is `/dev-pipeline:perf-retro`, not this step.

## Step 5: Route improvements

**Dedup against already-routed findings FIRST.** Before routing (or directly fixing) anything, check whether a prior retro already routed the same finding — otherwise the same item gets both queued and separately fixed. Search open dev-pipeline issues and the `ready-for-dev` queue:

```bash
gh issue list --state open --search 'pipeline-retro in:body' --json number,title,body \
  --jq '.[] | {number, title}'   # prior retro-routed issues; grep their bodies for your finding
```

If a finding is already covered by an open issue: do **not** re-file or silently re-fix it. Reconcile instead — comment on that issue noting the new datapoint (and, if you did land a fix, which item it resolves so it isn't done twice). Only then proceed to the routes below for genuinely new findings.

**Enforcement-mechanism ladder (apply to every drift-class finding).** When a finding shows the executing LLM bent or forgot a written rule, propose the CHEAPEST mechanism on this ladder that closes it — and say which rung you chose and why the cheaper rungs don't suffice:

1. **Gate precondition on evidence shape** — can a milestone assertion refuse the outcome because the evidence a compliant run necessarily produces is absent? Cheapest; no new artifacts. (Precedent: `lean-gate.sh`'s per-milestone preconditions and its `4`/`5` terminal gates.)
2. **Bash helper owning commands + bookkeeping** — the rule governs _command execution_ (suites, git, gh, counters): a helper runs the commands and does its own accounting, removing the honesty burden entirely. (Precedent: `lean-gate.sh` owning the milestone fix-attempt budget; `is-inert-diff.sh`; `claim-issue.sh`.)
3. **`.mjs` Workflow sequencer** — ONLY when the rule sequences _multiple agent dispatches_ with enum verdicts; the script enforces the ordering/verdict mapping and returns one auditable ledger. (Precedent: `plan-review.mjs`, `code-review.mjs`.) Do not reach for this before exhausting rungs 1–2 — it buys observability the cheaper rungs already give, at higher cost, and each schema-forced dispatch adds StructuredOutput-staller surface.
4. **Retro audit + accept** — the rule is judgment (deviations completeness, plan grounding quality): scripting it produces compliance theater; this skill IS the enforcement. Route as process note.

Proposing "more prose" for a bent rule is the anti-pattern this ladder exists to stop — prose is what already failed.

Every finding from Steps 2–4 gets exactly one route — **do not leave findings unrouted** — but **routing is not artifact production**: `Record only` (the retro report itself) satisfies routing, and it is the **default** route. The report is on disk and greppable; a finding that matters will recur and arrive at the next retro with two datapoints instead of one. **A zero-new-issues retro is the expected outcome, not a failure to route.** (Observed failure mode this exists to stop: consecutive retros each minting 2+ speculative issues, growing a backlog faster than it can be burned down.)

**Meaningful-issue bar.** The `GitHub issue` route is legal only when ALL three hold:

1. **Recurred, or actively corrupts** a gate, artifact, or eval — never "could theoretically". One clean occurrence of anything is `Record only`.
2. **The fix is known.** No "investigate X" issues — an un-root-caused observation is `Record only` until someone (this retro or a later session) has done the five minutes of diagnosis that makes it actionable.
3. **Not already covered** by an open issue (the dedup step above) — recurrence of a covered finding is a one-line datapoint comment on that issue, which is exactly the signal that bumps its priority.

Drift-class findings pick their ladder rung first, then land in `Record only`, `Skill-file edit`, or `GitHub issue` per the bar and size as usual.

**Approval gate (no-auto-commit):** routing decides _what_ each finding needs; it does **not** authorize the write. Before any git commit, branch push, or GitHub issue/PR creation, **present the proposed routes and get explicit user approval** — then apply only the approved ones. Writing the retro report itself (Step 6, a gitignored `.claude/pipeline-state/` file) and read-only dedup queries need no approval. If running fully unattended (no user to ask), record each actionable route as **proposed** in the report and stop short of the write.

**Unattended addition — verdict-less open PRs (#347).** A fully-unattended pass also runs
`bash "${CLAUDE_PLUGIN_ROOT}/tools/retro-corpus.sh" open-prs` and folds its
`verdictLess: true` rows into the report as the operator-visible backlog signal: open lean
PRs whose linked issue carries no comment yet referencing the expected verdict-record path —
a review that never landed, not (necessarily) a broken run. Read-only, so it needs no
approval either; still proposed-only if it were ever to route further (it does not on its
own — it is a report line, not a finding that gets routed).

| Route             | When                                                                                        | Action                                                                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Record only       | **Default.** Single occurrence, un-root-caused, or speculative — fails any meaningful-issue bar | Finding stays in the retro report (Step 6). No further artifact. Recurrence at a later retro re-tests the bar with the prior report as evidence. |
| Datapoint comment | Finding is covered by an open issue and recurred this run                                   | One-line `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"` comment on that issue citing this run — the recurrence signal that bumps its priority. Never a new issue.             |
| Skill-file edit   | Small doc/contract fix, no design needed                                                    | On approval: apply (prettier, commit via bot identity), reference the retro in the commit body. Commit on a branch, not the base branch directly. |
| GitHub issue      | Passes ALL THREE meaningful-issue bars, and needs code/tooling change or design > ~30 min   | `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"` create issue; label `ready-for-dev` only if genuinely pipeline-able, else leave unlabeled                                      |
| Doctor check      | Environment friction that pre-flight could catch, seen more than once                       | Edit `pipeline-doctor.sh` + its selftest expectations                                                                                    |
| Criteria proposal | Eval criterion ambiguous/mis-calibrated                                                     | Proposal text in the report ONLY — never edit `eval-criteria.md`                                                                         |
| Process note      | Behavioral lapse by the executing model                                                     | Surface to the user; they decide whether it becomes a CLAUDE.md/skill guardrail                                                          |

## Step 6: Write the report

Write `.claude/pipeline-state/{issue}-retro.md`. **era: artifact** — the header names the era
and the Score-comparison section states plainly that Step 2 was skipped (no mapping, no
self-score) rather than leaving the table empty with no explanation:

```markdown
# Retro: #{issue} ({run_id}, era: {stage|artifact})

## Score comparison

| Criterion | Self | Independent | Evidence (independent) |
| --------- | ---- | ----------- | ---------------------- |

`Independent` is `DARK — no output after resume` (never a blank cell, never the self-score)
for every criterion when Step 2's resumed dispatch also returned empty.

Discrepancies: {n} — {each explained}

## Deviation audit

{complied / deviated-and-surfaced / deviated-silently per checklist item, with evidence}

## Environment friction

{list, each with doctor/doc coverage status}

## Routed improvements

{route → concrete action taken or issue/proposal link}

## Verdict

{2-4 sentences: was the run's self-assessment honest? what single change most improves the next run?}
```

Finish by giving the user the score-comparison table, the silent-deviation count AND the waiver count side by side (the headline numbers — both target 0; a `waivers[]` entry is an operator-authorized bypass audited at the same altitude as a silent deviation, #243), and the routed-improvements list inline in the conversation. For a waived run, additionally verify each PR body carries the `<!-- pipeline-waivers -->` block — a waived run whose PR body lacks it is a finding (the acceptance flow requires the amend before `--accept-waivers`).
