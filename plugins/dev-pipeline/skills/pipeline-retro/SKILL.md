---
name: pipeline-retro
description: 'Post-run retrospective for a dev-pipeline run: independent eval re-scoring, contract-deviation audit, and improvement routing. Run after a /dev-pipeline:run-lean run completes (or aborts); also reads the pre-#348 staged-run corpus.'
---

# Pipeline Retro

Independent retrospective for a completed (or aborted) dev-pipeline run. The dev-pipeline scores its own eval — this skill exists because **the executor grading its own homework is structurally generous**. Everything here is scored from on-disk and on-GitHub artifacts by fresh context, never from the executing session's memory of itself.

**Usage:** `/pipeline-retro <issue-number>` — or no argument to use the most recently updated run (`retro-corpus.sh corpus --window 1 --json`, #347).

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

### Gather the run's artifacts

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

**Skipped.** The five `eval-criteria.md` criteria assume a staged run (`stages.N`,
`stageCheckpoint`) and no lane writes that shape. This skill does not invent a
milestones→criteria mapping — the operator owns the eval frame. Route a single
`Criteria proposal` in Step 5 ("eval-criteria.md has no lean-run mapping yet") the first
time a retro reaches this step in a given window; check Step 5's dedup-against-open-issues
search first so repeat retros don't re-propose it.

## Step 3: Contract-deviation audit (in-session, checklist)

Walk the run's trail against the skill contracts. For each item answer: complied / deviated-and-surfaced / **deviated-silently** (the worst class — see the review-toolkit:review-lead incident that motivated this skill):

Items 1 and 3 below audit mechanics `lean-gate.sh`'s outcome-gated milestones do not produce
by design (build-lean is "OUTCOME-gated, not process-prescribed" — its own header), and
run-identity reconciliation is already owned by `lean-reconcile.sh`, the operator-run
pre-merge check. Item 2 reads AC-n from the committed lean spec
(`docs/plans/{repo-slug}-{issue}-lean.md`) and item 3 reads the Decision Ledger from that
same spec.

1. **Bot identity** — all writes through `bash "${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh"`; label swaps add-before-remove.
2. **AC-coverage + brief-reconciliation audit** (skip when the spec carries no numbered AC-n). For every `acceptanceCriteria[].id`: is it traceable to a covering test (grep the PR diff for `(AC-n)` test titles), a diff hunk that plainly implements it, or a disclosed `deviations[]` / `— no test` traceability row? An AC with none of the three is an **undisclosed coverage gap** — finding. When `briefPath` is non-null, also check the Brief's reconciled QUARANTINE table: any `conflicts`-tagged PM claim the implementation silently followed anyway (the codebase was supposed to win) is a **silent deviation** — finding. Judgment against the surviving diff is expected here; the `(AC-n)` title convention is best-effort ("where natural"), so a covered-but-unlabeled test is satisfied by the diff-hunk leg, not flagged.
3. **Decision Ledger audit** (skip when the committed plan carries no `## Decision Ledger` — pre-convention run). A material design decision visible in the diff (new contract shape, data invariant, migration/backfill ordering, scope cut, `userId`-scope posture) with no ledger row and no `deviations[]` disclosure is an **undisclosed material decision** — finding. In-pipeline plans may only carry `codebase-derived` / `deferred` / `ticket-sourced` provenance (the remaining user-provenance rows come from a pre-flight `.claude/pipeline-state/{issue}-ledger.md`); a `user-answered` / `user-delegated` row with no backing pre-flight ledger file is a **fabrication-class** finding, as is a `ticket-sourced` row whose Resolution cites no comment URL.

## Step 4: Environment friction log

List every mid-run improvisation the trail reveals (REST fallbacks, version workarounds, missing tools, degraded sub-steps like `costBlockApplied: skipped-*`). For each: is it covered by a [`pipeline-doctor.sh`](../../tools/pipeline-doctor.sh) check or canonical-form doc yet? If not, it becomes a routed improvement below.

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
3. **`.mjs` Workflow sequencer** — ONLY when the rule sequences _multiple agent dispatches_ with enum verdicts; the script enforces the ordering/verdict mapping and returns one auditable ledger. (Precedent: `code-review.mjs`.) Do not reach for this before exhausting rungs 1–2 — it buys observability the cheaper rungs already give, at higher cost, and each schema-forced dispatch adds StructuredOutput-staller surface.
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

Write `.claude/pipeline-state/{issue}-retro.md`. The header names the run
and the Score-comparison section states plainly that Step 2 was skipped (no mapping, no
self-score) rather than leaving the table empty with no explanation:

```markdown
# Retro: #{issue} ({run_id})

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
