# The Pipeline Manifesto

Operator-stated, non-negotiable. Every enforcement decision in this repo is judged against these
ten principles.

This document is a **judgment aid for humans and reviews — it is not itself a gate**, and no lint
polices it. P5 forbids prose-presence guards, and a lint that checked for this file's wording would
be the first thing it forbids.

## The ten principles

- **P1 — The artifact chain is the unit of work.** Every change travels receipt to receipt — intake
  record, build artifacts (PR, green checks), independent review verdict, human merge. Blocks are
  coupled only by committed or posted artifacts, never by one block invoking another's internals. No partial chains, no shortcuts, no "just this once."
- **P2 — The agent has no discretion over outcomes and boundaries.** Receipts and gates are
  contracts, not suggestions. Skipping, thinning, forging, or reinterpreting an outcome gate must be
  *impossible*, not discouraged. The path between receipts is the model's own — prescribing it is
  scaffolding the next model generation deletes (P6).
- **P3 — Proof, not honesty.** The agent's account of its own compliance — comments, reports,
  self-scores — is not evidence. Compliance is established by records the agent does not control,
  reconciled mechanically.
- **P4 — As much as it takes, and none more.** Time, tokens, compute: the pipeline spends what the
  work needs. Overspend is waste; *underspend is a divergence signal* — both are anomalies against
  the measured corpus.
- **P5 — Every word earns its place.** Scripts, skills, and docs say what is necessary and nothing
  more. A rule enforced by a gate does not also live as prose; a reminder is not a control.
- **P6 — Ride the current model, don't fight the last one.** Workarounds for model pathologies carry
  their measured basis; when the model generation changes, the basis is re-measured and dead
  workarounds are deleted (with a canary). Model upgrades are harvested — context management, effort
  control — not merely survived.
- **P7 — Split only what must be split.** Every sub-issue is a full pipeline run, and runs are
  expensive. Decomposition produces as many issues as necessary and no more: a slice that cannot
  justify its own run merges into its neighbor. Thin slices are waste, not rigor.
- **P8 — Human intent is discovered, not transmitted.** Nobody holds a complete picture of what they want
  until something concrete pushes back. A spec produced in one pass can satisfy every stated
  requirement and still build the wrong thing, because the requirements that mattered only surface
  through reaction. Intake never leads with a finished draft: decisions go to the human one at a
  time, and the receipt names what remains open instead of claiming it knows everything.
- **P9 — Requirements are underspecified.** One line of request carries dozens of unstated choices —
  ask for search and you have implicitly asked about ranking, index staleness, typo tolerance, and
  who may see which results — most of which the requester holds no opinion on until a working
  version forces one. Resolving the whole tree in a single pass locks wrong guesses in where they
  compound; resolving each decision as it surfaces keeps every correction cheap. A gap found
  mid-build is normal operation: it is written into the record as a departure — the row edited,
  naming who decided and why — never as a silent choice.
- **P10 — Verification requires a different mode than generation.** The session that produced a piece of work is
  structurally the wrong one to evaluate it: judging your own output means confirming the choices
  that shaped it, and a stronger model inherits the same conflict, because the bias lives in the
  arrangement, not in the intelligence. Generation and evaluation run in separate contexts, and
  neither writes the other's record.

**P1/P2 posture:** stated in block form — receipts and a scheduler. `/dev-pipeline:run` drives
`run.sh`, which authors nothing: it commits the intake record as the branch's first commit, runs
every check itself after each build, and reads the record's rows and checks from that first commit,
never from the head the build controls. P10 is mechanically enforced rather than owed: the verdict
comes from a fresh review session, and the scheduler accepts a verdict comment only if it was
posted inside that session's window, never edited, and names the current head. The build session
is told never to post one, and it has exited before the review starts.

**P7 posture:** prospective — it binds decompositions from its statement onward. It lands
*substitutively*: the existing prose copies of the don't-split-for-splitting rule are replaced by
this single anchor, rather than a new copy being added beside them.

**P4/P5 posture (#641, #719):** the asymmetry this closes — P2/P3's growth principles gate
mechanically; P4/P5's restraint principles did not, for months, despite this document saying so in
its own text. P4/P5 are enforced by the operator at filing time (the admission rule in [`CLAUDE.md`](../CLAUDE.md)),
not by a script; the last script that tried policed itself into an empty-trailer review round
(#637).

A register's rows must be judgments, not measurements. A row recording something the tree can
compute — a file's size, a suite's runtime, a count — is a cache of the repo against itself, and
nothing re-measures it, so it drifts silently while reading as authority. Measurements are taken at
the moment they are used, and what gets committed is the judgment they are checked against. A
register earns its file only when a human decided something a command cannot. (The corpus this
replaced: [`docs/testing.md`](testing.md) names which registers survive it and why.)

## The three velocity principles

Operator-stated, from running the manual lane: it is slow, over-strict, and waits in vain. These
bind **every** block of the lane — the scheduler, the build and review sessions, and the checks —
retrospectively, not only new code. They sit beside P1–P10 rather than inside them: P4 is about
what a run *spends*, and these are about what it *waits for*. Like the ten, they are a judgment
aid and a review criterion, not a gate; a lint that policed their wording would be the first thing
P5 forbids.

- **V1 — Velocity is a design criterion, equal to correctness.** Wall-clock on the ticket →
  mergeable-PR path counts: speed of implementation, of review, of CI, of making the PR
  mergeable. A gate that is right but slow is not done — it gets faster, moves off the critical
  path, or goes advisory. Strictness that cannot change the merge decision does not get to block.
- **V2 — Never idle-block on a non-prerequisite.** No session, and above all no operator, waits
  on execution whose output the next step does not directly consume. Advisory or CI-duplicated
  work runs in the background or on CI. The operator-in-the-middle wait between build and review
  is the specific latency the lane's scheduler exists to delete: build → checks → review chains the
  moment the PR exists, with zero human latency between phases. A red check goes straight back to
  the next build attempt with its log; nobody waits on it.
- **V3 — Parallel-first is an implementation requirement.** Every skill, script and gate ships
  written for parallel execution: independent work fans out (job-pooled scripts, concurrent
  dispatch, probes with no data dependency between them). Serial execution of independent steps
  is a reviewable defect, not a style choice.

**V3 posture:** it binds new code from its statement onward, and retro-binds the existing gates as
a *profiling* obligation rather than a refactor mandate — a serial-independent-step finding is
recorded with its measurement and filed, because parallelizing a gate blind is how a
correctness regression enters through a velocity door.

## The trust boundary

Nothing inside the session is proof. The agent executes with file access, so local artifacts — state
files, receipts, even the hook-written audit ledger — are at best tamper-*evident*. The
tamper-*proof* line is the merge: the consumer's own required CI checks, branch protection, and a
human who merges — the lane never merges its own work.

P3 is satisfied by **three-record reconciliation**: (a) the hook-written tool ledger
(harness-recorded, outside model control); (b) the scheduler's run records — the intake record at
the branch's first commit, each session's result and log, and the run block it writes on the PR;
(c) the tracker trail and PR artifacts, the verdict comment among them. The scheduler reconciles
what it can mechanically — the verdict against the review window and the head, the checks it ran
itself — and the review scores the record's rows against the code. Forging any one record is
possible; forging all three consistently is what reconciliation makes detectable.

### Nothing yields to a present human mid-run

The scheduler never prompts, and no refusal inside a run can be waived from inside it — an attended
session cannot approve its own work any more than an unattended one can; attendance is not the
missing ingredient there, independence is. The operator acts **between** runs, through levers that
leave a record: the queue label, `--resume` on a claim, a flag that departs from a default and says
why (`--review-model-basis`), or an edit to the intake record before its first commit. Once the
branch carries the record, the scheduler reads it from that first commit: a later change needs a
new branch, or a departure row the build writes and the review scores.

## T0 note — trust-boundary preconditions

The merge boundary has two halves: a protection ruleset on the default branch (landed earlier), and a
**server-side freeze** of `.github/workflows/**`. The freeze matters because `pr-gates` runs as a
step inside the very workflow it would police — for a same-repo PR an agent could neuter the step
while keeping the required check green. A CI row cannot be the enforcer of its own file.

### Mechanism: a push ruleset

The freeze is a **push**-target ruleset with a `file_path_restriction` on `.github/workflows/**` and
**no bypass actors**.

CODEOWNERS was considered and rejected: it enforces via a required approving review, which a
solo-maintainer repo cannot self-provide.

### Probe result: rejected — no server-side freeze exists on this repo

Per the probe-first discipline the ruleset was created at `enforcement: disabled` first, so an
unsupported owner type would surface as an API rejection rather than a half-applied freeze. It did.
`POST /repos/manoldonev/second-shift/rulesets` returned **HTTP 422**, verbatim:

```json
{
  "message": "Validation Failed",
  "errors": [
    "Source public repos cannot have push rules",
    "Source only org-owned repos can have push rules"
  ],
  "status": "422"
}
```

Push rulesets are unavailable for a **public, user-owned** repository. Nothing was created; the two
active rulesets remain branch-target only (`default`, `main-protection`). No fake freeze was
substituted, and no toggle procedure is documented for a control that does not exist — if push
rulesets later become available here, the mechanism above is what to create, and the sanctioned-change
procedure would be an operator toggle to `disabled` and back around each workflow edit.

**The gap is recorded as an open risk on the program epic**, including its consequence for rung 1
below. Retiring the gap means one of: transferring the repo to an organization, or finding a
server-side control that binds a user-owned public repo.

Two partial controls remain, and neither is a substitute:

- the **required-check ruleset** on the default branch, which stops a merge whose checks are red but
  cannot stop the checks themselves from being edited;
- **admin-token discipline** — the freeze is procedural rather than enforced, so a workflow edit is
  only as controlled as the operator's own review of the diff.

The `check-frozen-files.sh` advisory row exists for exactly this state: it makes a workflow edit
*visible* in the PR log without failing the run. It is fast feedback, never enforcement.

### Rung-1 limitation, kept after the rung was removed

Rung 1 was the chain-reconciliation check (`scripts/check-pipeline-chain.sh`). It read its
`branchPrefix` and plan-path constants from `env:` entries on the `pr-gates` job, because the
runtime config is gitignored and absent in CI, and nothing reconciled those constants against the
real config — a stale `PIPELINE_BRANCH_PREFIX` matched zero branches and the check degraded to a
silent no-op on every PR.

With the freeze unavailable that made **rung 1 self-neutralizable**: those constants lived in
`.github/workflows/ci.yml`, the same agent-editable file the gate ran from, and no server-side
control prevents a run from editing it. The one bound that held was visibility — the check echoed
the resolved prefix on every not-applicable verdict.

#731 deleted the check: nothing had emitted the stage-marker trail it demanded since #348, so it
was unsatisfiable while still live. The limitation stays recorded because the shape recurs — every
record such a gate reads is agent-written, and so is its own configuration. Rung 1 was
**tamper-evidence, not proof**. Harness attestation is rung 2's job.

The generalizable rule: a CI constant is self-neutralizable when it is the **sole** applicability
input. Replace it with an artifact-derived trigger and there is no kill switch left to reach.
