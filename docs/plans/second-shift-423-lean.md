# second-shift #423 — the claimed label is released when the tracker item closes

## Problem

`tracker.labels.claimed` is added at claim (`lean-gate.sh` → `claim-issue.sh`) and removed by
nothing. The variable reaches exactly one consumer in `lean-gate.sh`, the claim helper; there is
no removal site in either lane. `run-lean/SKILL.md` step 9's "Drop the claimed label" is prose
with no gate behind it, and the schema's own description for the field —
"added atomically at claim (and removed at terminal stages)" — asserts a removal that does not
exist.

Step 9 is also the wrong moment. Milestone 5 requires an **open** PR, so it runs strictly
pre-merge, while the issue is open with review in flight — the one moment the label is
*correct*. The stale window opens at merge, when `Closes #N` closes the issue and no session is
running to notice.

## Constraint (binding, from the issue)

- **github only.** Under `tracker.type: jira` with `writes: false` there is no claimed label and
  no tracker write; that arm is a documented no-op, not an unimplemented one.
- The testable unit is the **label-resolution + removal script**, not the workflow YAML.
- Whatever ships must be a **no-op, not an error**, on a tracker with `writes: false`.
- Removing a label that is already absent must not fail the workflow. Closing an issue that was
  never claimed is the common case.

## Binding pre-flight ledger

`.claude/pipeline-state/423-ledger.md` is binding input and **wins over the issue body** where
the two disagree. Rows that move this spec beyond the issue's own framing:

- **D-1** — the workflow strips **`tracker.labels.queue` AND `tracker.labels.claimed`**, not the
  claimed label alone. `tracker.labels.blockers` is deliberately excluded: it contains `epic`, a
  permanent classification rather than run state, and a hardcoded `epic` exception against a
  consumer-redefinable list can silently miss.
- **D-2** — the consumer files ride onboard's **existing** Step 3 item 9 acceptance. **No new
  onboard prompt.**
- **D-5** — write identity is `github.token` with `permissions: issues: write`. The bot App
  wrapper resolves against `$HOME` and is unreachable from a runner.
- **D-10** — the YAML is **not** the unit: a grep over the workflow file is the banned
  prose-presence class. This retracts the wiring pins the first draft of this spec sanctioned.
- **D-11** — the widened permission is disclosed in `.claude/SECOND-SHIFT.md`, the pre-trust
  inventory — this repo's own copy, not only the shipped template.
- **D-3** — stale `needs-*` blocker labels on closed issues stay stale. Out of scope.
- **OR-1** (`reversible-default-and-flag`) — ship the `issues: [closed]` trigger and **flag the
  verification result in the PR either way**. Reversal if the merge path does not fire: add
  `pull_request: [closed]` as a second trigger resolving the issue from the PR body.
- **OR-2** (`reversible-default-and-flag`) — rely on the jq fallback for this repo's gitignored
  config and **say so in a comment at the resolution site**.

## Chosen shape, and the config-readability constraint it resolves

A repository workflow on `issues: [closed]` calls a committed script. The trigger is
deterministic, needs no live session, and covers both lanes plus manually-closed issues.

The issue flags the real constraint: the label name is config-driven and this repo's
`.claude/second-shift.config.json` is **gitignored**, so a workflow here cannot resolve
`.tracker.labels.claimed` at run time. The issue offered two exits (hardcode the default, or
substitute the name at install). This spec takes a third that dominates both: the script
**resolves the config at run time when it is readable, and falls back to the shipped default
`in-progress` when it is not**. In a consumer repo the config *is* committed (onboard Step 8
tells the human to commit it), so the resolution is live and correct with nothing to drift —
the same posture `second-shift-ci-check.sh` already takes with the lockfile. In this repo the
config is absent from CI and the default is the operative value, which is this repo's real
label.

**One copy, not two.** This repo is the canary, so its own workflow runs the shipped template
script **in place** at `plugins/second-shift/templates/consumer/second-shift-unclaim.sh` rather
than committing a second copy under `.claude/tools/`. There is therefore no copy pair to keep
in lockstep, and this repo dogfoods the exact artifact consumers receive.

## Non-goals

- **No backlog sweep.** The 21 stale labels the issue reported are already cleared (a
  `state:closed label:in-progress` query returns zero). This ticket is the mechanism.
- **No milestone-5 enforcement.** Rejected in the issue: wrong moment, and session-dependent.
- **No `lean-reconcile.sh` arm.** It is pre-merge-only, so it can detect a stale claim but never
  release one.
- **No reopen handling.** Re-adding the label when a closed issue is reopened is a different
  contract with a different trigger; out of scope.
- **No branch-protection or required-check configuration.** As with the existing evidence
  workflow, the file ships and the repo admin owns the protection rules.

## Acceptance criteria

**AC-1.** `plugins/second-shift/templates/consumer/second-shift-unclaim.sh` ships as the
testable unit. Invoked as `second-shift-unclaim.sh <issue-number>`, it resolves **both** run-state
labels and removes each from that issue (D-1): `.tracker.labels.claimed` (default `in-progress`)
and `.tracker.labels.queue` (default `ready-for-dev`). `.tracker.labels.blockers` is **not**
touched. Config resolution mirrors `lean-gate.sh`'s seam exactly: the config path is
`${SECOND_SHIFT_CONFIG:-<root>/.claude/second-shift.config.json}` where `<root>` is
`${SECOND_SHIFT_REPO_ROOT:-$(git rev-parse --show-toplevel)}`, and each name comes from its key
when the file is readable and the key non-null, else its shipped default. **An absent or
unparseable config is not an error** — it is this repo's normal state — and resolution falls
through to the defaults.

**AC-2.** Three no-op arms each exit **0**, issue **zero** `gh` calls that mutate, and print one
line naming the arm:

- a. `.tracker.writes` is `false` (any tracker type),
- b. `.tracker.type` is present and is not `github` (D-8),
- c. the issue does not carry a given label — decided per label.

Arm (c) is decided by reading the issue's labels **once** first, so the common case — a closing
issue carrying neither label — performs no write at all rather than relying on a tolerated error.

**AC-3.** Each removal is a REST `DELETE` against
`repos/{owner}/{repo}/issues/<n>/labels/<label>` with the label **percent-encoded** for the path
(`jq -rn --arg s … '$s|@uri'`), so a configured label containing a space or `/` is removed
rather than 404ing. The repo is resolved by `gh` from `GH_REPO`; the script takes no repo
argument.

**AC-4.** Failure classification, so neither a race nor a broken token is misreported:

- a `DELETE` that fails **because the label is already absent** (HTTP 404 / "Label does not
  exist") is success — the read-then-delete is not atomic (D-9);
- any other `DELETE` failure makes the script exit **1**;
- **a failure on one label never skips the other.** Both are always attempted, and the exit is
  worst-wins;
- a failure to **read** the issue's labels exits **1** — an unreadable issue must not be
  reported as "not claimed";
- a missing or non-numeric issue number exits **2** (usage). The numeric check is also what
  keeps the argument out of an API path unvalidated.

**AC-5.** `.github/workflows/unclaim-on-close.yml` is this repo's own instance: it triggers on
`issues: [closed]` (D-7), declares `permissions: { contents: read, issues: write }` with
`GH_TOKEN` from `github.token` (D-5), checks out the repo, and runs
`plugins/second-shift/templates/consumer/second-shift-unclaim.sh` with `GH_TOKEN`, `GH_REPO` and
the issue number passed through `env:` — never `${{ }}`-interpolated into the `run:` body, per
this repo's existing injection discipline in `ci.yml`.

**AC-6.** `plugins/second-shift/templates/consumer/second-shift-unclaim.yml` is the consumer
template with the same trigger, permissions, token and env discipline, differing only in that it
calls `.claude/tools/second-shift-unclaim.sh` — the path onboard copies the script to.

**AC-7.** `/second-shift:onboard` emits both consumer files under its **existing** Step 3 item 9
acceptance — **no new prompt** (D-2). That question's text covers the unclaim workflow; Step 7's
emit block copies `second-shift-unclaim.sh` → `.claude/tools/` (executable bit kept) and
`second-shift-unclaim.yml` → `.github/workflows/`, both **verbatim** (nothing is substituted at
install — the script reads the committed config at run time); Step 8's commit reminder lists
them. The emit block states that this workflow **writes** to issues, unlike the read-only
evidence workflow, and that a repo whose Actions workflow permissions are read-only must switch
to read-and-write. Under a non-github tracker the unclaim half is skipped.

**AC-8.** `plugins/second-shift/templates/consumer/second-shift-unclaim-selftest.sh` is a
hermetic behavioral selftest next to the tool — no network, `gh` stubbed on `PATH` recording its
argv and returning a per-label controlled status. It covers every arm of AC-1 through AC-4,
asserting on the recorded argv **and** the exit code, and **contains no grep over either
workflow YAML** (D-10 retracts the wiring pins). Every assertion is probed by mutating the
production file and confirming it flips red; an assertion no mutant can red is deleted rather
than kept.

**AC-9.** Doc updates, AC-scoped:

- `plugins/dev-pipeline/skills/run-lean/SKILL.md` step 9 no longer instructs the session to drop
  the claimed label, and names where the drop now happens. The file stays within its 60-line cap.
- `schema/second-shift.config.schema.json`'s `tracker.labels.claimed` description no longer
  claims removal "at terminal stages" and describes the real mechanism. Description-only: no
  `configVersion` change, no migration doc.
- `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` **and this repo's own
  `.claude/SECOND-SHIFT.md`** disclose the `issues: write` scope (D-11); `docs/onboarding.md` and
  `docs/team-rollout.md` list the new optional committed files alongside the evidence pair.

**AC-10.** `.claude/prose-budget.baseline.tsv` is **spliced, never regenerated**: only rows for
markdown files this change actually grows past tolerance are advanced, and every other row is
byte-identical to its pre-change value. `prose-budget.sh --report` shows no row this change
introduced as over budget.

**AC-11.** The OR-2 disposition is honored in code: the resolution site carries a comment saying
this repo relies on the jq fallback because its own config is gitignored, and naming the symptom
if the two ever diverge.

**AC-12.** The OR-1 disposition is honored in the handoff: the PR states the trigger's
verification status **explicitly, either way**, and names the reversal (`pull_request: [closed]`
as a second trigger resolving the issue from the PR body) so a workflow that never fires on the
dominant path cannot read as shipped.

**AC-13.** `scripts/check-workflows-selftest.sh` also parses the consumer workflow templates
under `plugins/second-shift/templates/consumer/*.yml`. This is a **parse**, not a wiring grep —
it fails on a syntax error a diff reader would not see, and it is the only thing standing between
a malformed template and every consumer that installs it. Neither that gate nor CI's actionlint
walks anything outside `.github/workflows/` today.

## Test tier

Per `CLAUDE.md`'s tier map:

- AC-1 through AC-4 are one script's behavior against fixtures → a **per-tool behavioral
  selftest** (AC-8), same-named and next to the tool, matching the
  `second-shift-ci-check.sh` / `second-shift-ci-check-selftest.sh` precedent.
- **Why no `scenario-liveness-selftest.sh` scenario.** The scenarios there compose `lean-gate.sh`
  verdict paths inside a run. This script is not reachable from any gate: it runs post-merge, in
  GitHub Actions, with no session and no `lean-gate.sh` invocation, triggered by a tracker event
  the harness never observes. There is no composed verdict path to extend — which is the same
  fact that made milestone-5 enforcement the wrong fix.
- **No YAML wiring pins.** An earlier draft of this spec sanctioned them under the narrowed
  mjs-seam grep exception, copying `second-shift-ci-check-selftest.sh`'s `yml:` cases. **D-10
  retracts that**, and the ledger wins. The workflow files are covered only by what already
  covers YAML syntax — `check-workflows-selftest.sh` and CI's actionlint for
  `.github/workflows/`, extended by AC-13 to reach the consumer templates. The wiring itself
  (trigger, permissions, invoked path) is therefore unguarded by construction; that is the
  ledger's call, and the PR says so rather than leaving it to be discovered.
- AC-9 is prose in markdown → **nothing** is written for it; a grep asserting a literal is
  present in a `.md` is the banned class.
- No `tools/mutation-catalog.tsv` row: the new guard is covered by its own paired suite, which
  the diff-scoped sweep picks up by name. Any survivor is re-baselined in this same diff.

## Release metadata

- Bump: **minor**. A new deterministic close-out mechanism plus a new onboard-emitted artifact
  is new capability, and per `CLAUDE.md` this repo's AI tooling *is* the product, so the honest
  verb is `feat:`. The level derives from the squash subject, so the **PR title** must carry
  `feat(second-shift): …`.
- `Changelog:` trailer: consumer-visible (a new emitted workflow and a behavior change), so a
  real trailer — not `none`.
