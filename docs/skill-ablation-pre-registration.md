# Skill-vs-bare-session ablation — pre-registration

**Registered 2026-08-24, before any result was collected.** #644. This file is written once and is
not edited afterwards; the results live in `docs/skill-ablation.md` and the raw arm outputs under
`docs/skill-ablation/`. That ordering is the point, and it is checkable:

```bash
git log --format='%h %ad %s' --date=short -- docs/skill-ablation-pre-registration.md
git log --format='%h %ad %s' --date=short -- docs/skill-ablation/
```

The first commit must precede every commit in the second listing.

## Why a pre-registration at all

The failure mode this slice exists to prevent is a rubric written loosely enough that every
incumbent passes. Every threshold below is fixed now, while the answers are unknown.

## The bare arm

A Claude Code session with no second-shift plugins loaded, in the same repository worktree, on the
same model tier:

```
printf '%s' "<prompt>" | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
  -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' [--allowedTools "Read,Grep,Glob"]
```

Verified plugin-free by probe before registration: the same invocation asked to name any
second-shift-family skill available to it answered `NO-SECOND-SHIFT-SKILLS`.

The repository's own `CLAUDE.md` auto-loads in both arms. Any scored item that `CLAUDE.md` itself
mandates is marked **non-discriminating** and credited to neither arm.

## The decision rule, common to all three comparisons

The burden of proof is on the skill.

| verdict | requires |
| --- | --- |
| `keep` | a demonstrated win for the kit arm on that comparison's outcome metric, at or beyond its threshold |
| `cut-to-delta` | no demonstrated win — the surface is cut to the part that demonstrably differs from bare |
| `delete` | the kit arm loses, or its output is not distinguishable from bare |

**Absence of evidence yields `cut-to-delta`, never `keep`.** This is what lets a small sample
terminate in a verdict instead of abstaining, and it is the only reading under which the ticket's
"roughly equal, but ours is more thorough is a loss" is actually enforceable.

---

## Comparison 1 — `build-lean` + the milestone gates vs. a bare session

### The half this slice measures, and the half it inherits

The ticket names one comparison; the surface has two separable halves.

- **The gates** are already measured. `docs/gate-ablation.md` scored every firing over a corpus
  pinned by `docs/gate-ablation-manifest.tsv`: 20 of 33 decision points never fired, 66% of
  firings are adjudicated `unchanged`, and all six keep-earners are re-run at the merge boundary.
  That evidence is **inherited and cited, not re-collected** — re-running it would spend this
  slice's budget reproducing a committed answer.
- **The skill** — `plugins/dev-pipeline/skills/build-lean/SKILL.md`, 48 lines — is what nothing has
  measured, and is what this comparison collects.

### Metric — proxy, and labelled as one

**Mandated-artifact coverage.** An end-to-end bare build does not fit a collectible turn, so the
outcome metrics the ticket names (defects reaching the PR, ticket-to-mergeable wall-clock) are out
of reach here. The proxy is: of the artifacts `build-lean` mandates, how many does a bare session
commit to unprompted, given the same ticket and the same repository?

**Registered consequence: comparison 1 cannot license a `keep`.** A proxy this far from the outcome
does not discharge the burden of proof. Its reachable verdicts are `cut-to-delta` and `delete`. It
is registered anyway because it is well-matched to the *cut* action — it identifies precisely which
mandated items a bare session already covers, and those are the cuttable ones.

### Sample — n=2, fixed now

| id | ticket | why |
| --- | --- | --- |
| C1-a | #636 | merged 2026-08-23, current generation, full artifact set committed |
| C1-b | #647 | merged 2026-08-24, current generation, full artifact set committed |

### The mandated-artifact list — fixed now, 10 items

| # | artifact | source |
| --- | --- | --- |
| M1 | a committed spec/AC file with ≥1 numbered `AC-n` | SKILL step 4 |
| M2 | a Decision Ledger carried forward from the pre-flight ledger | SKILL step 4 |
| M3 | an isolated worktree on a lane branch cut from the configured base | SKILL step 3 |
| M4 | commits attributed to the bot identity, not the operator | SKILL step 5 |
| M5 | a `Changelog:` trailer | `CLAUDE.md` — **non-discriminating** |
| M6 | a **ready** (non-draft) PR carrying summary, spec link, `Closes #N` | SKILL step 7 |
| M7 | a cost block derived from the progress record, in the PR description | SKILL step 7 |
| M8 | a PR marker carrying the run identity, posted before the review push | SKILL step 7 |
| M9 | the review authored **outside** this session, by a separate identity (P10) | SKILL step 8 |
| M10 | a close-out: cost-log row, refreshed PR block, closing comment, teardown | SKILL step 9 |

M5 is scored and reported but excluded from every threshold below, because both arms read the
`CLAUDE.md` that mandates it.

### Scoring rule

The bare arm is asked, once per sample, for the complete plan of record it will follow — every
artifact it will produce, in order — before it begins. Each of M1–M10 is scored `covered` (the plan
names that artifact or an equivalent) or `absent`. Partial credit is not available; a plan that
names "a PR" without `ready`/`Closes` scores M6 `absent` and the wording is quoted in the report.

### Thresholds — fixed now

Over the 9 discriminating items, across both samples:

| bare arm covers | verdict |
| --- | --- |
| 9/9 in both samples | `delete` — the SKILL's mandate prose changes nothing |
| anything less | `cut-to-delta` — the SKILL is cut to exactly the items bare missed |
| — | `keep` unavailable, per the registered consequence above |

---

## Comparison 2 — `review-lean` vs. a bare session review

### Metric — an outcome metric, so this comparison can license any verdict

**Recall of ground-truth blockers**, where a ground-truth blocker is one that the lane's committed
round-1 verdict record raised, the branch then fixed, and round 2 verified closed. Those are exactly
the defects that reached the PR *and* changed what shipped — the ticket's first named outcome metric,
with a pre-existing oracle that this slice did not author.

False blockers are counted alongside recall: a bare arm that finds everything by flagging everything
has not won.

### Sample — n=3 PRs, 5 ground-truth blockers, fixed now

| id | PR | reviewed head (round 1) | ground-truth blockers |
| --- | --- | --- | --- |
| C2-a | #654 (#636) | `cfba102` | 1 — the gate-bucket enumerator's command-position class omits keyword-preceded calls, so a live refusal site sits outside the denominator the guard claims is its output |
| C2-b | #657 (#647) | `f8f7c14` | 2 — B1 the settings seed writes an unignored untracked file into the tree whose cleanliness `worktree_inflight()` reads; B2 a tracked project-scope `Bash(gh:*)` is the standing grant the PR's own reasoning rejects |
| C2-c | #660 (#642) | `642a6b1` | 2 — B1 AC-3 is half-applied, two announcement-class reasons still charge the fix budget on the `close-out` path; B2 AC-3's fixture-per-reason is unsatisfied for `m5/identity-stamp` |

Each head is reachable from `refs/pull/<n>/head`; the round-1 records are readable at the verdict
commits `35e0240`, `5ba15b0`, `a3eeceb`.

### Scoring rule

One bare session per sample, given the same diff and read-only access to the same repository, asked
to review and to state its blockers. A bare finding is a **hit** on a ground-truth blocker when it
names the same mechanism and the same consequence; naming the same file with a different defect is
a miss. Every near-miss is quoted verbatim in the report and adjudicated there, so a reader can
repudiate the call rather than take it on trust.

### Thresholds — fixed now, over the 5 ground-truth blockers

| bare recall | false blockers | verdict |
| --- | --- | --- |
| ≤ 2/5 | any | `keep` |
| 3/5 or 4/5 | any | `cut-to-delta` |
| 5/5 | no more than the lane's own round-1 records raised | `delete` |
| 5/5 | more | `cut-to-delta` |

### Recorded separately, not folded into recall

P10 independence — that the verdict is authored by a session which is not the build session — is a
property of the **lane**, not of the skill's prose, and no bare-arm review can exhibit or refute it.
It is reported as a standing property with its own basis, and it is not scored here. A `delete` on
this comparison would therefore delete the skill's prose, not the separate-session boundary.

---

## Comparison 3 — `plan-interview` / `interviewing-baseline` vs. a bare session

### Scope of this comparison, and what it does not reach

The measurable artifact of the elicitation surface is the Decision Ledger. That is produced by
`plan-interview` (99 lines) and `interviewing-baseline` (213 lines). `intake-interviewer` (279) is
in scope insofar as it produces the same artifact.

`intake-orchestrator` (711 lines, the largest skill in the tree) produces **decomposition**, not a
ledger, and this metric does not reach it. Its mass is therefore **not adjudicated by this slice**
and is recorded as a named residual rather than silently credited with a pass.

### Metric — a scored elicitation rubric, the ticket's third named outcome metric

**Bare recall of operator-ratified decisions.** The reference set is the `user-answered` rows of
committed lean-spec Decision Ledgers — decisions an operator answered and a build then consumed, so
an external party validated them as load-bearing.

### The bias, and how it is neutralised

The reference ledgers were authored by the kit. The kit arm therefore scores 100% by construction,
and **that score is not admissible as evidence.** The only admissible evidence is the bare arm's
recall. `codebase-derived` rows are kit-internal and excluded from the reference set entirely.

The handicap runs the other way too, and is recorded: the reference ledger came out of a full
operator interview with codebase access, while the bare arm gets the issue body and one pass. A high
bare recall under that handicap is therefore strong evidence; a low one is weak evidence, and the
thresholds are set accordingly lenient toward the incumbent.

### Sample — n=3 tickets, 20 reference rows, fixed now

| id | ticket | `user-answered` rows |
| --- | --- | --- |
| C3-a | #650 | 7 |
| C3-b | #643 | 7 |
| C3-c | #597 | 6 |

### Scoring rule

One bare session per sample, given the issue body and read-only repository access, asked to produce
the decision ledger it would take to the operator before any implementation plan. A reference row is
**recalled** when the bare arm names the same decision — the same thing left undecided — regardless
of which resolution it proposes. Proposing a resolution is not required; surfacing the decision is
the whole claim the skill makes.

### Thresholds — fixed now, over the 20 reference rows

| bare recall | verdict |
| --- | --- |
| ≥ 16/20 (80%) | `delete` — bare surfaces what the kit surfaces |
| 10–15/20 (50–79%) | `cut-to-delta` |
| < 10/20 (50%) | `keep` |

---

## What gets recorded regardless of outcome

For every surface left standing: its re-measured P6 basis, the date, the comparison id, and the
number that carried it — so the next model generation has something to re-measure against rather
than an assertion to inherit.
