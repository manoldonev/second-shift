# The Pipeline Manifesto

Operator-stated, non-negotiable. Every enforcement decision in this repo is judged against these
ten principles.

This document is a **judgment aid for humans and reviews — it is not itself a gate**, and no lint
polices it. P5 forbids prose-presence guards, and a lint that checked for this file's wording would
be the first thing it forbids.

## The ten principles

- **P1 — The artifact chain is the unit of work.** Every change travels receipt to receipt — intake
  receipt, build artifacts (PR, green verification, progress record), independent review verdict,
  merge boundary. Blocks are coupled only by committed artifacts, never by one block invoking
  another's internals. No partial chains, no shortcuts, no "just this once."
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
  mid-build is normal operation: it routes back as an intent-gap record under its declared
  disposition, never as a silent choice.
- **P10 — Verification requires a different mode than generation.** The session that produced a piece of work is
  structurally the wrong one to evaluate it: judging your own output means confirming the choices
  that shaped it, and a stronger model inherits the same conflict, because the bias lives in the
  arrangement, not in the intelligence. Generation and evaluation run in separate contexts, and
  neither writes the other's record.

**P1/P2 posture:** stated in block form — receipts and outcome gates. The stage machinery is gone
from the tree: #348 deleted the staged `run` lane, so the lean lane is the only lane. Rollback and
the ablation's staged arm are served by a marketplace pin of the last stage-carrying release, whose
version literal is recorded in #348's `Migration:` trailer — and so in that release's changelog
entry — rather than restated here, where it would rot. P10 is mechanically enforced rather than
owed: the lean lane's verdict record is written by a
separate top-level review session carrying its own identity, and a record carrying the build run's
identity — or naming the build session as its author — is refused both in-gate and at the merge
boundary. The in-build reviewer is deleted, and with it the dispatch-failure fallback that let a
build session write its own verdict; that debt is closed, not tolerated.

**P7 posture:** prospective — it binds decompositions from its statement onward. It lands
*substitutively*: the existing prose copies of the don't-split-for-splitting rule are replaced by
this single anchor, rather than a new copy being added beside them.

**P4/P5 posture (#641):** the asymmetry this closes — P2/P3's growth principles gate mechanically;
P4/P5's restraint principles did not, for months, despite this document saying so in its own text.
`scripts/check-guard-budget.sh` is the mechanical counterpart: it derives guard/test shell mass at
the base ref and at HEAD on every PR and reds an increase that carries no `Guard-mass:` trailer, so
P4's "none more" has a gate the way P2/P3 always did. It is a derived comparison, not a register —
nothing is committed, so nothing can drift out of sync with what the tree actually measures.

A register's rows must be judgments, not measurements. A row recording something the tree can
compute — a file's size, a suite's runtime, a count — is a cache of the repo against itself, and
nothing re-measures it, so it drifts silently while reading as authority. Measurements are taken at
the moment they are used, and what gets committed is the judgment they are checked against. A
register earns its file only when a human decided something a command cannot. (The corpus this
replaced: [`docs/testing.md`](testing.md) names which registers survive it and why.)

## The three velocity principles

Operator-stated, from running the manual lane: it is slow, over-strict, and waits in vain. These
bind **every** block of the lane — the scheduler, `build-lean`, `review-lean`, and the gates —
retrospectively, not only new code. They sit beside P1–P10 rather than inside them: P4 is about
what a run *spends*, and these are about what it *waits for*. Like the ten, they are a judgment
aid and a review criterion, not a gate; a lint that policed their wording would be the first thing
P5 forbids.

- **V1 — Velocity is a design criterion, equal to correctness.** Wall-clock on the ticket →
  mergeable-PR path counts: speed of implementation, of review, of CI, of making the PR
  mergeable. A gate that is right but slow is not done — it gets faster, moves off the critical
  path, or goes advisory. Strictness that cannot change the merge decision does not get to block —
  and which of the lane's gates that describes is now measured rather than argued:
  [`docs/gate-ablation.md`](gate-ablation.md).
- **V2 — Never idle-block on a non-prerequisite.** No session, and above all no operator, waits
  on execution whose output the next step does not directly consume. Advisory or CI-duplicated
  work runs in the background or on CI. The operator-in-the-middle wait between build and review
  is the specific latency the lane's scheduler exists to delete: build → review chains the moment
  the PR exists, with zero human latency between phases.
- **V3 — Parallel-first is an implementation requirement.** Every skill, script and gate ships
  written for parallel execution: independent work fans out (job-pooled scripts, concurrent
  dispatch, probes with no data dependency between them). Serial execution of independent steps
  is a reviewable defect, not a style choice.

**V3 posture:** it binds new code from its statement onward, and retro-binds the existing gates as
a *profiling* obligation rather than a refactor mandate — a serial-independent-step finding is
recorded with its measurement and filed, because parallelizing a 187KB gate blind is how a
correctness regression enters through a velocity door.

## The trust boundary

Nothing inside the session is proof. The agent executes with file access, so local artifacts — state
files, receipts, even the hook-written audit ledger — are at best tamper-*evident*. The
tamper-*proof* line is the merge boundary: CI checks plus branch protection, which the agent cannot
edit from a run.

P3 is satisfied by **three-record reconciliation**: (a) the hook-written tool ledger
(harness-recorded, outside model control); (b) the harness-written run records — the progress
file and the committed verdict record; (c) the
tracker trail and PR artifacts. The three are reconciled mechanically, with CI as the terminal
verifier. Forging any one record is possible; forging all three consistently is what
reconciliation makes detectable.

### Where a gate may yield to a present human, and where it may not

Every gate here fires identically whether an unsupervised model or an answering operator is
driving. Some of those gates exist only because nobody is assumed to be there — and for those, and
only those, an attended session may buy something.

The predicate is a classification, not a preference:

- **`gates-llm`** — defenses against fabrication and self-approval. These **never** yield. An
  attended session cannot approve its own work any more than an unattended one can; attendance is
  not the missing ingredient there, independence is.
- **`gates-signal`** — the refused fact is objective: a verify lane is red, a hash moved, a
  release-owned file was edited. These **never** yield either. The bucket exists because the
  predicate is not total: a red test lane is neither a fabrication defense nor premised on an
  absent human, and forcing it into `gates-process` to keep the classification binary is exactly
  how a red suite becomes operator-waivable.
- **`gates-process`** — rules whose premise is "no human is available to answer this". These
  **may** yield when the premise is false.

Which gate is which is not left to a reading: [`scripts/gate-buckets.tsv`](../scripts/gate-buckets.tsv)
declares one bucket per refusal site, and an unclassified one fails CI.

The mechanism is **affordance plus record**, and both halves are load-bearing:

1. The **affordance token** is minted by an operator running a command, never asserted by the
   session. It unlocks exactly one thing: the right to _pause and ask_ where the gate would
   otherwise reject. It buys no yield. Staleness is structural — the token binds to the run's
   identity, so a spawned payload's fresh session id can never match one — rather than a
   wall-clock TTL, which would import portability hazards for no security.
2. The **override record** is the yield's evidence: a committed file naming the gate, the run, the
   authority scope, and the operator's answer quoted verbatim. Its trust level is exactly the
   intent-gap record's — session-writable, PR-visible, merge-boundary-validated, repudiable at
   review. Nothing about it is tamper-proof, and it does not claim to be.

**The residual, stated rather than papered over.** A local gate whose code is edited to skip its
own yield bookkeeping will skip it. That is the standing local-gate posture from the section above,
not a new hole: it is tamper-evident, it arrives at review as a diff, and the merge boundary
validates every record that does reach it. What the mechanism removes is the silent yield — a run
that waved a gate through and left nothing for anyone to argue with afterwards.

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

### Rung-1 limitation, stated rather than papered over

The chain-reconciliation check (`scripts/check-pipeline-chain.sh`) reads its `branchPrefix` and
plan-path constants from `env:` entries on the `pr-gates` job, because the runtime config is
gitignored and absent in CI. Nothing reconciles those constants against the real config — a stale
`PIPELINE_BRANCH_PREFIX` matches zero branches and the check degrades to a silent no-op on every PR.

With the freeze unavailable, **rung 1 is self-neutralizable**: those constants live in
`.github/workflows/ci.yml`, the same agent-editable file the gate runs from, and no server-side
control prevents a run from editing it. The one bound that does hold is visibility — the check echoes
the resolved prefix on every not-applicable verdict, so a stale or emptied constant shows up in each
PR's log rather than passing silently.

Rung 1 is therefore **tamper-evidence, not proof**, and on this repo it is weaker than the design
assumed: every record it reads — tracker comments, the PR body, the committed plan — is agent-written,
and so is the gate's own configuration. Harness attestation is rung 2's job.

### The lean gate, which escapes the limitation outright

`pr-gates` once carried a third constant, `LEAN_BRANCH_PREFIX`, naming a separate `lean/` branch
namespace for the lean harness's merge-boundary gate (`scripts/check-lean-chain.sh`). It is retired:
both lanes now cut `<tracker.branchPrefix><key>` branches, so there is no lean namespace to name and
that gate holds **no** branch-derived applicability input at all.

Applicability is the key-matched lean spec committed in the PR's own diff — an artifact the harness
produced, read out of the diff being merged. There is no prefix to go stale and no constant to
empty, so the self-neutralization mode above has nothing to act on here: a run wanting to escape
this gate would have to remove its own spec from its own PR, which is the evidence the gate exists
to demand. `check-pipeline-chain.sh` takes the mirror-image exclusion by calling the same
classifier, so "no PR is applicable to both gates" holds by construction rather than by two
constants staying consistent with each other.

The generalizable rule, and the reason this is worth recording next to the limitation it escapes: a
CI constant is self-neutralizable when it is the **sole** applicability input. Replace it with an
artifact-derived trigger and there is no kill switch left to reach.

### What a new gate arm ships with

Both merge-boundary gates are silent when every arm is satisfied and loud only where something
could not be evaluated. A new arm therefore ships with three things, not one, and none of them is
optional:

1. **Its producer's capability stamp.** An arm enforces a contract some producer has to write. The
   arm reads that producer's generation off the run's own evidence and enforces only where the
   stamp shows a generation capable of the artifact it demands — because the arm travels by git ref
   while the producer travels by versioned install, and the two are permanently skewed on the
   branch that develops them. An arm with no stamp to read is an arm that accuses honest runs.
2. **Its not-applicable path.** Every way the arm can fail to evaluate — a producer too old, an
   input the adapter has no counterpart for, an artifact the run legitimately never wrote — emits
   exactly one class-(b) line naming the arm and one disposition from the closed vocabulary
   (`not-applicable`, `reduced-strength`, `postdated`, `inert`). Declining in silence is the vacuous
   pass every gate here refuses; declining in a violation is an accusation nothing supports.
3. **Its silence on green.** A satisfied arm prints nothing, on either stream, whether the run ends
   green or red — including when it was satisfied _vacuously_, by the other branch of a precedence
   rule. Which branch verified a contract is a source-reading question, and a job log that recites
   it buries the lines an operator is actually looking for.

The obligation is stated here rather than enforced by a test, deliberately: a guard that grepped
this paragraph would assert only that prose contains words. The enforcement is the mechanism —
`LEAN_OUTPUT_DISPOSITIONS` is a closed set both gates declare and a lockstep row binds, the emitter
refuses a disposition outside it, and both suites anchor every green-path line whole, so an arm
that starts narrating or stops disclosing reds a case rather than a paragraph.
