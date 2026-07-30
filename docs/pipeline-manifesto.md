# The Pipeline Manifesto

Operator-stated, non-negotiable. Every enforcement decision in this repo is judged against these
seven principles.

This document is a **judgment aid for humans and reviews — it is not itself a gate**, and no lint
polices it. P5 forbids prose-presence guards, and a lint that checked for this file's wording would
be the first thing it forbids.

## The seven principles

- **P1 — The pipeline is the unit of work.** Every change travels the full path — intake, plan,
  implement, verify, review, PR. No partial runs, no shortcuts, no "just this once."
- **P2 — The agent has no discretion over the path.** Stages are contracts, not suggestions.
  Skipping, reordering, thinning, or reinterpreting a stage must be *impossible*, not discouraged.
- **P3 — Proof, not honesty.** The agent's account of its own compliance — comments, reports,
  self-scores — is not evidence. Compliance is established by records the agent does not control,
  reconciled mechanically.
- **P4 — As much as it takes, and none more.** Time, tokens, compute: the pipeline spends what the
  work needs. Overspend is waste; *underspend is a divergence signal* — both are anomalies against
  the measured corpus.
- **P5 — Every word earns its place.** Scripts, skills, and stage docs say what is necessary and
  nothing more. A rule enforced by a gate does not also live as prose; a reminder is not a control.
- **P6 — Ride the current model, don't fight the last one.** Workarounds for model pathologies carry
  their measured basis; when the model generation changes, the basis is re-measured and dead
  workarounds are deleted (with a canary). Model upgrades are harvested — context management, effort
  control — not merely survived.
- **P7 — Split only what must be split.** Every sub-issue is a full pipeline run, and runs are
  expensive. Decomposition produces as many issues as necessary and no more: a slice that cannot
  justify its own run merges into its neighbor. Thin slices are waste, not rigor.

**P7 posture:** prospective — it binds decompositions from its statement onward. It lands
*substitutively*: the existing prose copies of the don't-split-for-splitting rule are replaced by
this single anchor plus a lockstep row, rather than a new copy being added beside them.

## The trust boundary

Nothing inside the session is proof. The agent executes with file access, so local artifacts — state
files, receipts, even the hook-written audit ledger — are at best tamper-*evident*. The
tamper-*proof* line is the merge boundary: CI checks plus branch protection, which the agent cannot
edit from a run.

P3 is satisfied by **three-record reconciliation**: (a) the hook-written tool ledger
(harness-recorded, outside model control), (b) statectl receipts and state, (c) the tracker trail and
PR artifacts — reconciled mechanically, with CI as the terminal verifier. Forging any one record is
possible; forging all three consistently is what reconciliation makes detectable.

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
