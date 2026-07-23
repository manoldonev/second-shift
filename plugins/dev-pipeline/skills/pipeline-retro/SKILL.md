---
name: pipeline-retro
description: 'Post-run retrospective for a dev-pipeline run: independent eval re-scoring, contract-deviation audit, and improvement routing. Run after a /dev-pipeline:run run completes (or aborts).'
---

# Pipeline Retro

Independent retrospective for a completed (or aborted) dev-pipeline run. The dev-pipeline scores its own eval at Stage 9+ — this skill exists because **the executor grading its own homework is structurally generous**. Everything here is scored from on-disk and on-GitHub artifacts by fresh context, never from the executing session's memory of itself.

**Usage:** `/pipeline-retro <issue-number>` — or no argument to use the most recently updated file in `.claude/pipeline-state/*.json`.

**Hard rules:**

- `eval-criteria.md` is LOCKED — this skill never edits it. Criteria problems become a _proposal_ in the report, acted on by the human between optimization loops.
- The original `{issue}-eval.json` is never mutated. The retro writes its own artifact.
- The independent scorer is a **fresh subagent** with no access to this conversation — it sees only the artifacts listed below.

## Step 1: Gather run artifacts

```bash
ISSUE=<n>
S=../dev-pipeline/statectl.sh
cat .claude/pipeline-state/${ISSUE}.json          # state: stages, checkpoints, deviations, failureContext
cat .claude/pipeline-state/${ISSUE}-eval.json     # the run's SELF-score
# The run report — Stage 9's durable narrative, written before the terminal
# narration so an API disconnect cannot destroy it. Absent = either a pre-schema
# run or a run that never reached Stage 9's pr-add.
[ -f ".claude/pipeline-state/${ISSUE}-report.md" ] && cat ".claude/pipeline-state/${ISSUE}-report.md"
bash ../dev-pipeline/tools/stage-times.sh ${ISSUE}   # per-stage wall times + transition gaps
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

If there is no state file, stop: nothing to retro.

## Step 2: Independent eval re-score (fresh context)

Dispatch ONE `retro-scorer` agent (Task tool) whose prompt contains: the five criteria definitions copied verbatim from [`../dev-pipeline/eval-criteria.md`](../dev-pipeline/eval-criteria.md) and the artifact contents from Step 1. The agent ([`../../agents/retro-scorer.md`](../../agents/retro-scorer.md)) carries the standing re-score rubric — score each criterion PASS/FAIL/N/A strictly by the letter, quote artifact evidence, "absence of evidence is not a PASS", and the ctx-wire-legitimacy rule — and runs on **Sonnet** via its frontmatter, so the harness binds the tier (a prose "use Sonnet" against `general-purpose` would not — it has no frontmatter and inherits the session Opus default).

Then compare against the self-score from `{issue}-eval.json`. **Every discrepancy is a finding** — either the run self-scored generously (process problem) or the criterion is ambiguous (criteria-proposal material).

## Step 3: Contract-deviation audit (in-session, checklist)

Walk the run's trail against the skill contracts. For each item answer: complied / deviated-and-surfaced / **deviated-silently** (the worst class — see the Stage 8 review-toolkit:review-lead incident that motivated this skill):

1. **Mandated loads & dispatches** — was every skill the stage files say to load actually loaded (`intake-toolkit:intake-orchestrator`, `review-toolkit:review-lead` for synthesis)? Diff `stages.N.skillsLoaded[]` (the self-reported load evidence the completion gates read) against the session audit ledger (`.claude/audit/<session>.jsonl` — `Skill` tool invocations): a skill recorded in state but absent from the ledger is a **fabricated evidence write**, strictly worse than the silent skip the gate exists to stop. Were sub-agents dispatched for real (never inlined)? Check `/audit` if available.
2. **State discipline** — every stage has `startedAt`/`completedAt`; checkpoints written at 1/5/7; boundary writes (`worktree-set`, `pr-add`) ordered before stage completion; `verifyAttempts` incremented for every fix loop (including plan-specific verification commands — see Stage 6). A Stage-6 `refactor:` commit recorded in `stages.6.qualityPass` is the advisory quality pass — an expected, disclosed, non-`verifyAttempts` event (its one-shot `--no-attempt` safety-net re-verify is not a fix loop).
3. **Comment trail** — every pipeline comment carries `run_id` + a marker from the closed enum (`state-schema.md` "Stage-comment markers"); no duplicates; failures left a comment.
4. **Bot identity** — all writes through `$GH_BOT`; label swaps add-before-remove.
5. **Deviations ledger** — does `stageCheckpoint["7"].deviations[]` plus the PR body disclose everything the diff/trail shows actually happened? Undisclosed deltas are silent deviations. (An applied Stage-6 quality-pass cleanup is disclosed via `stageCheckpoint["7"].qualityPassSummary`, not `deviations[]` — only a `reverted` outcome requires a `surprise` entry.)
6. **QA-gate integrity** (the mutation gate — the stall-prone surface). On unit-test-applicable runs, `stages.5.unitTestMutationReview` must be terminal `completed` (vocabulary: `reviewing | completed`; `executing` only on legacy pre-sequencer state files), and `mutationReviewAudit.rounds[].executions[]` must be the `mutation-gate.mjs` return ledger — the per-mutant results are **machine-attested by the workflow journal**, so an audit that disagrees with the journal (or an audit written with no corresponding Workflow dispatch) is a fabricated gate. A `budget-skipped` or `infra` overall that still closed Stage 5 with `completed` sub-status is a silent coverage gap.
7. **AC-coverage + brief-reconciliation audit** (skip when state has no `acceptanceCriteria[]` — pre-schema run). **Stacked-slice scoping (#204):** when state also carries a valid `decomposition.slices[]` partition (union of `acIds` equals the snapshot id set — else ignore it, full-ticket audit) and a non-null `currentSlice`, iterate only the union of `acIds` for slices `1..currentSlice`; a later-slice AC absent from the slice PR diff is **expected-uncovered (partition-deferred)**, not a finding. Otherwise, for every `acceptanceCriteria[].id`: is it traceable to a covering test (grep the PR diff for `(AC-n)` test titles), a diff hunk that plainly implements it, or a disclosed `deviations[]` / `— no test` traceability row? An AC with none of the three is an **undisclosed coverage gap** — finding. When `briefPath` is non-null, also check the Brief's reconciled QUARANTINE table: any `conflicts`-tagged PM claim the implementation silently followed anyway (the codebase was supposed to win) is a **silent deviation** — finding. Judgment against the surviving diff is expected here; the `(AC-n)` title convention is best-effort ("where natural"), so a covered-but-unlabeled test is satisfied by the diff-hunk leg, not flagged.
8. **Decision Ledger audit** (skip when the committed plan carries no `## Decision Ledger` — pre-convention run). A material design decision visible in the diff (new contract shape, data invariant, migration/backfill ordering, scope cut, `userId`-scope posture) with no ledger row and no `deviations[]` disclosure is an **undisclosed material decision** — finding. In-pipeline plans may only carry `codebase-derived` / `deferred` provenance (user-provenance rows come from a pre-flight `.claude/pipeline-state/{issue}-ledger.md`); a `user-answered` / `user-delegated` row with no backing pre-flight ledger file is a **fabrication-class** finding.

## Step 4: Environment friction log

List every mid-run improvisation the trail reveals (REST fallbacks, version workarounds, missing tools, degraded sub-steps like `costBlockApplied: skipped-*`). For each: is it covered by a [`pipeline-doctor.sh`](../dev-pipeline/tools/pipeline-doctor.sh) check or canonical-form doc yet? If not, it becomes a routed improvement below.

Also read the `stage-times.sh` output against expectations: an inert-diff run that still paid the configured verify suite (Stage 6 ≳ 4 min on a docs/shell-only diff), large inter-stage gaps (synchronous posting of non-gating comments), or a stage whose recorded window is implausibly short (work done before `set-stage N --status started` — a state-discipline deviation for Step 3) are all findings.

## Step 5: Route improvements

**Dedup against already-routed findings FIRST.** Before routing (or directly fixing) anything, check whether a prior retro already routed the same finding — otherwise the same item gets both queued and separately fixed. Search open dev-pipeline issues and the `ready-for-dev` queue:

```bash
gh issue list --state open --search 'pipeline-retro in:body' --json number,title,body \
  --jq '.[] | {number, title}'   # prior retro-routed issues; grep their bodies for your finding
```

If a finding is already covered by an open issue: do **not** re-file or silently re-fix it. Reconcile instead — comment on that issue noting the new datapoint (and, if you did land a fix, which item it resolves so it isn't done twice). Only then proceed to the routes below for genuinely new findings.

**Enforcement-mechanism ladder (apply to every drift-class finding).** When a finding shows the executing LLM bent or forgot a written rule, propose the CHEAPEST mechanism on this ladder that closes it — and say which rung you chose and why the cheaper rungs don't suffice:

1. **statectl precondition on evidence shape** — can a `set-stage`/`mark-completed` gate refuse the outcome because the evidence a compliant run necessarily produces is absent? Cheapest; no new artifacts. (Precedent: the per-stage completion preconditions, the terminal all-stages/eval gates.)
2. **Bash helper owning commands + bookkeeping** — the rule governs _command execution_ (suites, git, gh, counters): a helper runs the commands and does its own accounting, removing the honesty burden entirely. (Precedent: `verifyctl.sh` owning `verifyAttempts`; `is-inert-diff.sh`; `claim-issue.sh`.)
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

| Route             | When                                                                                        | Action                                                                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Record only       | **Default.** Single occurrence, un-root-caused, or speculative — fails any meaningful-issue bar | Finding stays in the retro report (Step 6). No further artifact. Recurrence at a later retro re-tests the bar with the prior report as evidence. |
| Datapoint comment | Finding is covered by an open issue and recurred this run                                   | One-line `$GH_BOT` comment on that issue citing this run — the recurrence signal that bumps its priority. Never a new issue.             |
| Skill-file edit   | Small doc/contract fix, no design needed                                                    | On approval: apply (prettier, commit via bot identity), reference the retro in the commit body. Commit on a branch, not the base branch directly. |
| GitHub issue      | Passes ALL THREE meaningful-issue bars, and needs code/tooling change or design > ~30 min   | `$GH_BOT` create issue; label `ready-for-dev` only if genuinely pipeline-able, else leave unlabeled                                      |
| Doctor check      | Environment friction that pre-flight could catch, seen more than once                       | Edit `pipeline-doctor.sh` + its selftest expectations                                                                                    |
| Criteria proposal | Eval criterion ambiguous/mis-calibrated                                                     | Proposal text in the report ONLY — never edit `eval-criteria.md`                                                                         |
| Process note      | Behavioral lapse by the executing model                                                     | Surface to the user; they decide whether it becomes a CLAUDE.md/skill guardrail                                                          |

## Step 6: Write the report

Write `.claude/pipeline-state/{issue}-retro.md`:

```markdown
# Retro: #{issue} ({run_id})

## Score comparison

| Criterion | Self | Independent | Evidence (independent) |
| --------- | ---- | ----------- | ---------------------- |

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

Finish by giving the user the score-comparison table, the silent-deviation count (the headline number — target is always 0), and the routed-improvements list inline in the conversation.
