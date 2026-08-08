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

**P1/P2 posture:** stated in block form — receipts and outcome gates. Until the stage-machinery
deletion lands, the staged path remains in-tree solely as rollback and ablation control (the pin is
the last stage-carrying release, recorded on the deletion PR when it merges); new work runs the lean
lane. P10 is mechanically enforced rather than owed: the lean lane's verdict record is written by a
separate top-level review session carrying its own identity, and a record carrying the build run's
identity — or naming the build session as its author — is refused both in-gate and at the merge
boundary. The in-build reviewer is deleted, and with it the dispatch-failure fallback that let a
build session write its own verdict; that debt is closed, not tolerated.

**P7 posture:** prospective — it binds decompositions from its statement onward. It lands
*substitutively*: the existing prose copies of the don't-split-for-splitting rule are replaced by
this single anchor, rather than a new copy being added beside them.

## The trust boundary

Nothing inside the session is proof. The agent executes with file access, so local artifacts — state
files, receipts, even the hook-written audit ledger — are at best tamper-*evident*. The
tamper-*proof* line is the merge boundary: CI checks plus branch protection, which the agent cannot
edit from a run.

P3 is satisfied by **three-record reconciliation**: (a) the hook-written tool ledger
(harness-recorded, outside model control); (b) the harness-written run records (progress and
verdict records in the lean lane; statectl receipts and state in the staged lane); (c) the
tracker trail and PR artifacts. The three are reconciled mechanically, with CI as the terminal
verifier. Forging any one record is possible; forging all three consistently is what
reconciliation makes detectable.

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

### A third constant, deleted rather than defended

`pr-gates` used to carry a third constant, `LEAN_BRANCH_PREFIX`, for the lean harness's
merge-boundary gate (`scripts/check-lean-chain.sh`). It was unreconciled against the gitignored
runtime config in the same way as the two above, and the argument for tolerating it was that the gate
did not classify on the prefix *alone* — a lean-marked spec in the PR diff was a second, artifact-derived
trigger, so a stale or emptied prefix could not silently exempt a lean PR.

That constant is gone. Both lanes now write `<branchPrefix><key>` (#413), so a branch name carries no
lane identity to classify on at all, and the gate applies on the committed artifact: a non-fixture
`*-<key>-lean.md` in the PR's own diff, keyed to the PR's own issue. `check-pipeline-chain.sh`
excludes on the identical rule. The DROPPED manifest entry that recorded the constant's residual risk
is replaced by a real lockstep row (`lean-spec-suffix`) comparing the one literal the two gates now
share.

The generalizable rule, and the reason this is worth recording next to the limitation it escapes: a
CI constant is self-neutralizable when it is the **sole** applicability input. Giving a check a
second, artifact-derived trigger blunts that; making the artifact the **only** trigger removes the
constant, and that residual with it. The two pipeline constants above are still the weaker
arrangement, and they remain the T0 residual of record.

**What removing the constant did not remove.** Deleting a constant retires the constant's failure
mode, not every failure mode at that boundary — and the replacement introduced one of its own, which
is recorded here because the first version of this section claimed otherwise. The rule now lives in
two gates that derive the same key from **different sources**: `check-lean-chain.sh` from the PR
body's `Closes #N`, `check-pipeline-chain.sh` from the branch. Disjointness — *no PR is claimed by
both* — was the property designed for, and it holds. Its complement — *every PR is claimed by at
least one* — is a different property, was never asserted, and did not follow: where the two keys
disagreed, each gate handed the PR to the other and neither read the evidence, printing a confident
hand-off on both sides. `check-lean-chain.sh` step 4b closes it by refusing rather than declining
whenever the diff commits the branch key's spec. The invariant that actually holds is **no PR is
exempt from both**, with exactly-one only where the two keys agree.

The lesson generalizes past this boundary, and it is the one worth carrying: when a single
classification is split across two checks, the thing to hold in lockstep is the **key derivation**,
not only the pattern the key feeds. Two gates can agree perfectly about the rule and still both stand
down, because they disagree about what they are applying it to.

**And the lesson had to be applied before it was believed.** The paragraph above shipped as prose one
round before the derivation gap it describes false-red the very PR carrying it: the lane asserts
`Closes #<issue>` appears *at least once* in the body, the boundary gate resolved the *first* match,
and a body quoting the token in prose — this section's own counterexample — handed the gate a phantom
key. Hardening a consequence promotes every latent looseness in its inputs: step 4b converted what had
been a silent decline into a hard fail, and the loose input became a lane-stopper the same day. The
gate now resolves to the branch key whenever the body closes it, so the two derivations agree by
construction rather than by coincidence. Recording it because the sequence is the point — a lockstep
note that is only a note describes a coupling; it does not hold one.
