# second-shift #348 — Delete stage choreography from main

**Issue:** [#348](https://github.com/manoldonev/second-shift/issues/348) · **Branch:** `claude/second-shift-348` · **Base:** `main`

Pre-flight ledger: `.claude/pipeline-state/348-ledger.md` (binding input — D-1…D-18, OR-1/OR-2).

## What this is

`plugins/dev-pipeline/skills/run/` is the ten-stage `statectl` choreography lane. Lean
(`build-lean` + `review-lean`, scheduled by `run-lean`) has been the default lane since v5;
`run` is kept only as an ablation control and rollback path. This PR deletes it.

The directory is not homogeneous. It also carries **shared, non-choreography tooling** that
surviving skills, the four toolkits, the consumer CI template and the repo's own guards
invoke. Relocating that tooling — and re-pointing every consumer — is a precondition of the
deletion, not a follow-up, so both live in this one PR with relocation-first commit ordering
(ledger D-1).

**BREAKING.** `/dev-pipeline:run` disappears from post-merge releases. Consumers that want it
keep the marketplace pin of the last stage-carrying release. The concrete release literal is
recorded in the PR body and on the issue **at merge** (AC-3, ledger D-9/D-18) — writing a
version literal today would be stale and would contaminate the ablation's staged arm with
post-pin improvements.

## Design

Design: none — no `design.provider` is configured for this repo, and the diff has no UI
surface. This is a deletion plus a file-relocation with consumer re-pointing.

## The survive/delete criterion

Ledger D-12, applied mechanically: **any `skills/run/` file with a live consumer outside
`skills/run/` relocates; everything else deletes.** "Live consumer" means an invocation or a
declared-path dependency from surviving code — not a mention in prose, a comment, a historical
`docs/plans/` record, `CHANGELOG.md`, or a `capability-parity.tsv` citation.

The spec's relocation list is a **floor**, re-verified here ("implementation re-verifies").
Deviations from it are enumerated below and are the review's business.

### Destination layout (ledger D-13)

| Kind | Destination |
| --- | --- |
| shell tools + their selftests + fixtures | `plugins/dev-pipeline/tools/` |
| Workflow `.mjs` + their selftests | `plugins/dev-pipeline/workflows/` |
| the two lockstep-paired docs | `plugins/dev-pipeline/` root |
| the composed liveness suite (lean legs + lane routing) | `plugins/dev-pipeline/skills/build-lean/` |

`plugins/dev-pipeline/workflows/` is already the path `pr-revision/SKILL.md:269` names in its
`scriptPath`, and the four toolkits reference workflows by bare `workflows/<name>.mjs`, so the
move brings the tree into line with prose that is already written that way. CI rule 3(b)
(`.github/workflows/ci.yml:171`) polices toolkit **content**, not the destination's existence.

## Relocation set (survivors)

`skills/run/tools/*` → `plugins/dev-pipeline/tools/`, each with its paired selftest and
fixtures:

`bot-commit.sh`, `check-bounded-exploration.sh`, `check-config-shadowing.sh`,
`check-doc-routing.sh`, `check-extensions.sh` + `extension-manifest.txt`, `checked-call.sh`,
`claim-issue.sh` (+ `claim-selftest.sh`), `claims-lint.sh` (+ fixtures), `config-lint.sh`
(+ fixtures), `gh-bot.sh`, `install-gh-bot.sh`, `is-inert-diff.sh`, `pipeline-doctor.sh`,
`predecessor-gate.sh`, `preflight.sh`, `pre-commit-typecheck-selftest.sh`, `prose-budget.sh`
(+ `prose-budget.baseline.tsv`), `resolve-worktrees-dir.sh`, `retro-corpus.sh`,
`score-review.sh` (+ `review-harness-fixtures/`), `stage-envelopes.sh`, `stage-times.sh`
(+ fixtures), `text-contract-selftest.sh`, `tracker/`, `diff-range-selftest.sh`,
`intake-readroot-selftest.sh`.

`skills/run/pipeline-cost-block.sh` (+ `cost-block-selftest.sh`) → `plugins/dev-pipeline/tools/`.

`skills/run/workflows/*` → `plugins/dev-pipeline/workflows/`: `code-review.mjs`,
`intake-review.mjs`, `design-sync.mjs` (+ selftest), `figma.mjs`, `unit-tests.mjs`,
`mutation-gate.mjs`, `stall-probe.mjs`, `tool-discipline-probe.mjs`, `runtime-shim-lib.mjs`,
`runtime-shim-selftest.mjs`, `null-reviewer-selftest.mjs`, `workflows-mjs-selftest.sh`.

`skills/run/eval-criteria.md`, `skills/run/state-schema.md` → `plugins/dev-pipeline/` root,
relocated whole. `state-schema.md` documents the on-disk format of the **historical** staged
corpus that `pipeline-retro`/`perf-retro` still read; no content edit beyond path fixes.

`skills/run/scenario-liveness-selftest.sh` → `plugins/dev-pipeline/skills/build-lean/`,
carrying only its surviving scenarios (keep list below).

`skills/run/cost-tracking-setup.md` + `otel-collector-config.yaml` →
`plugins/dev-pipeline/` root: `lean-gate.sh:2332,2336` cites the setup doc by section in
operator-facing diagnostics, and the collector config is the artifact that doc installs.

### Deviations from the spec's enumerated relocation floor

| File | Spec said | Verified | Why |
| --- | --- | --- | --- |
| `scenario-lib.sh` | relocate ("three suites drive it") | **delete** | All four surviving `complete_stage` call sites sit inside the ledger-corroboration scenario, which dies with `statectl`. `statectl-selftest.sh` and `e2e-replay-selftest.sh` — the other two drivers — both die. Zero surviving consumer. |
| `e2e-workflow-leg.mjs` + `e2e-replay-selftest.sh` + `e2e-replay-fixtures/` | relocate | **delete** | The E2E replay is a whole-**staged**-run replay driven through `statectl` (`init → stages 1..9 → mark-completed`). With `statectl` gone there is no run to replay. The production code it reached is separately covered: `claim-issue.sh` by `claim-selftest.sh`, the `.mjs` bodies by `runtime-shim-selftest.mjs`. |
| `plan-lint.sh`, `verifyctl.sh`, `plan-review.mjs` | — | **delete** | Ledger D-14: no live invoker outside `skills/run/`; the three apparent ones (`lean-gate.sh:2702`, `config-grill.sh:102`, the demotion register) are comments/prose. |
| `statectl.sh` + selftest + fixtures + `gen-statectl-validators.sh` | spec's reversible default was "keep the minimal record writer" | **delete entirely** | Ledger **D-3 override**, flagged in the PR body: zero live invokers outside `skills/run/`; `pipeline-retro`'s era-stage arm reads raw state JSON via `cat`/`jq` and never calls `statectl`; lean writes markdown progress records. |
| `ledger-corroborate.sh`, `plan-scope-paths.sh`, `tracker-reconcile-check.sh` | — | **delete** | Sole invokers are `statectl.sh`, `stages/7-doc-update.md` and `SKILL.md` respectively. `capability-parity.tsv` already dispositions the first two as `dropped`. |
| `score-review.sh` | not enumerated | **relocate** | It is the scorer half of the `stall-probe.mjs` instrument set that ledger D-2 preserves for #291's pre-registered replication; deleting it would break the same experiment D-2 protects. CLAUDE.md also grandfathers its selftest as a mutation-eval anchor. |
| `tools/capability-parity.tsv` | ledger D-15 listed it for re-keying | **left untouched** | Its own header and `capability-parity-check.sh:29` state that rows are permanent record and their paths are **historical citations, not existence-checked**. Re-keying it would destroy the deletion's audit trail. AC-1's orphan grep exempts it for this reason. |

## Deletion set

- `skills/run/SKILL.md` and `skills/run/stages/1..10*.md` — the staged `run` skill; deleting
  the directory is what removes `/dev-pipeline:run`.
- `statectl.sh`, `statectl-selftest.sh`, `statectl-selftest-fixtures/`,
  `tools/gen-statectl-validators.sh` (D-3 override).
- `verifyctl.sh`, `verifyctl-selftest.sh` (D-14).
- `tools/plan-lint.sh` + fixtures + selftest, `workflows/plan-review.mjs` (D-14).
- `scenario-lib.sh`; `e2e-replay-selftest.sh`, `e2e-replay-fixtures/`,
  `workflows/e2e-workflow-leg.mjs`.
- `stage7-perrepo-checkpoint-selftest.sh`, `stage8-perrepo-review-selftest.sh`.
- `tools/ledger-corroborate.sh` + fixtures + selftest, `tools/plan-scope-paths.sh` + fixtures
  + selftest, `tools/tracker-reconcile-check.sh` + selftest.
- `doc-update.md`, `hooks.md`, `cost-tracking-fixtures/` (statectl-state fixtures).

## Scenario keep list — OR-1's proposal

Per the spec, BUILD enumerates; the outside review round and the operator dispose. Triage,
not sweep: a scenario survives iff the verdict path it composes still reaches a terminal write
in the surviving tree.

**KEEP** (relocated to `skills/build-lean/scenario-liveness-selftest.sh`):

| Scenario | Why it survives |
| --- | --- |
| **lean legs (build-lean)** — the composed progress-line chain and gate exit codes across the three verdict paths | The only assertion site for the fix budget of 3, the 4th-red hard stop, the abort record, and counters surviving re-entry — economics pinned in prose that no `AC-n` carries. |
| **AC-15 leg** — the claim executed by the session, not by a gate | The second bot-wrapper write has no other composed check; `claim-selftest.sh` proves the label swap in isolation, never that the run performs it. |
| **lane routing (#413)** — exactly one merge-boundary gate claims any given PR | A property of the **pair** of chain gates asking `lean-evidence.sh`'s `classify()`. Each gate's own suite drives it in isolation and cannot see the two failure modes the pair has. Untouched by this deletion. |

**DROP** (the composed path they guard no longer exists):

| Scenario | Why it dies |
| --- | --- |
| no-split liveness, sub-issues carve-out, failure-path, exhausted-review, voided-review | Each composes `statectl` stage progression to a terminal `completed`/`failed` write. No `statectl`, no write. |
| be-fe-pair to terminal | The `ticketTag → targetRepos` per-repo fan-out is `dropped` in `capability-parity.tsv:46`; a pair consumer runs the lean lane once per repo. |
| circuit breaker (real `verifyctl`) | Composes `verifyctl` + `statectl` + the stage-6 budget; both components are deleted. |
| waived-run (#243), jira zero-evidence guard (#243 AC-7) | Both assert on `statectl`'s terminal-write refusal under a standing waiver / missing comment receipts. |
| predecessor gate: pre-claim ordering (AC-6) | Guards Stage 1's queue loop. `predecessor-gate.sh` itself **survives** (intake-orchestrator consumer) with `predecessor-gate-selftest.sh` intact; only the stage-1 composition dies. |
| tracker reconcile check: resume (#149) | `tracker-reconcile-check.sh` is deleted; `lean-reconcile.sh` is the lean successor and carries its own suite. |
| ledger corroboration composes to terminal (#272) | The corroboration seam is inside `statectl`'s stage-completion write. |

## Demotion register

`unit-test-plan-reviewer` keeps its agent file and loses its only automated dispatcher
(`workflows/plan-review.mjs`, Stage 4). This is a deliberate demotion to **pool** —
plan-time/interactive use via `Task` — recorded here and in the PR body so the review reads it
as a decision, not a dangling agent.

## Register and doc sweep

Re-key or remove every row/reference carrying a deleted or relocated path:

- Mutation registers: `tools/mutation-baseline.tsv`, `tools/mutation-exclusions.tsv`,
  `tools/mutation-catalog.tsv`, `tools/mutation-pair-map.tsv`, `tools/mutation-slow-suites.tsv`.
- Other path-carrying registers (ledger D-15): `tools/selftest-cache-inputs.tsv`,
  `tools/install-topology-known-red.tsv`, `tools/reap-lean-fixtures.sh`, and
  **`scripts/fail-open-sites.tsv`** — the last is outside AC-1's orphan-grep glob, so it is
  swept deliberately.
- `scripts/lockstep-manifest.tsv`: re-point survivor rows; remove or convert to **DROPPED**
  with reasoning every row whose file dies (the pairs check reds on a missing file).
- `scripts/check-intake-tracker-namespaces.sh:45`, `scripts/stack-generality-lint.sh` (+ its
  selftest), `scripts/check-pipeline-chain.sh` (+ selftest), `scripts/check-lockstep-pairs-selftest.sh`,
  `scripts/check-fail-open-shapes.sh`.
- `plugins/review-toolkit/scripts/check-model-tiers.sh` (+ selftest + fixtures),
  `check-emit-deadline.sh`, `check-scope-tracker-namespaces.sh`, `check-review-context.sh`.
- `plugins/second-shift/skills/doctor/tools/doctor.sh` (+ selftest),
  `plugins/second-shift/skills/onboard/{SKILL.md,tools/detect.sh,tools/config-grill.sh}`,
  `plugins/second-shift/templates/consumer/second-shift-{ci-check,unclaim}.sh`.
- Surviving dev-pipeline skills: `pipeline-retro/SKILL.md`, `perf-retro/SKILL.md`,
  `pr-revision/SKILL.md`, `build-lean/{SKILL.md,lean-gate.sh,lean-reconcile.sh}`,
  `hooks/pre-commit-typecheck.sh`.
- Docs: `CLAUDE.md` (verification recipe, coverage/exceptions register, tier map),
  `docs/testing.md` (the tier map CLAUDE.md defers to), `docs/pipeline-manifesto.md`
  (trust-boundary record list + the P1/P2 pin posture note), `README.md`, `docs/onboarding.md`,
  `docs/namespaces.md`, `docs/config-schema.md`, `docs/extension-points.md`,
  `docs/team-rollout.md`, plus the `plugin.json` / `marketplace.json` **descriptions**
  (`version` stays frozen).
- `.github/workflows/ci.yml` rule 3(b) pattern, which names `skills/run/`.

## Config-schema assessment (ledger D-17)

A key is stage-only iff **no surviving reader remains** after the deletion. Enumerated against
the surviving tree, not the schema:

| Key | Surviving reader | Disposition |
| --- | --- | --- |
| `stageParams.planFilePattern` | `tools/preflight.sh` | keep |
| `stageParams.inertPattern` | `tools/is-inert-diff.sh`, `tools/preflight.sh` | keep |
| `stageParams.requiredLabels` | `tools/pipeline-doctor.sh`, `intake-orchestrator` | keep |
| `stageParams.webComponentGlobs` | `review-lead/SKILL.md` (a11y + design-fidelity routing) | keep |
| `stageParams.formatGlob` | `config-grill.sh`'s `T2.formatGlob` waiver | keep — it lost its *executor* (`verifyctl`), not its reader |
| `gates.mutation` | `config-grill.sh`'s mutation-seam findings + unadopted rows | keep — the lean mutation seam is a repo-carried `tools/mutation-sweep.sh` and this is the declared intent it grades |
| `commands.<h>.unitTestScope`, `.testFile` | `workflows/mutation-gate.mjs` | keep |
| `commands.<h>.extraLanes` | `lean-gate.sh` milestone 3 (#379) | keep |
| `design.liveRender` | `lean-gate.sh` milestone 3 | keep |
| `topology.repos.<id>.ticketTag` | `run-lean/SKILL.md`, `intake-orchestrator` — advisory, no gate | keep |
| **`stageParams.visualCapture`** | **none** — Stage 6's advisory smoke-capture was its only consumer, and `config-grill.sh:161` already states it evaluates no key under it | **RETIRED** |
| `stageWorkflows` (EP-6), `implementDelegates` (EP-7), `planGates` (EP-8) | `tools/check-extensions.sh` **validates** their references; nothing **dispatches** them | keep, documented **INERT** — see below |

**`stageParams.visualCapture` is retired here**, under the established dead-key pattern: a
`config-lint.sh` `err(has(...))` naming the removal plus a `docs/migrations/` pointer, and the
property dropped from `schema/second-shift.config.schema.json`. **No `configVersion` bump** —
that pattern is what `gates.costTracking` used in v2.1.6, and `check-configversion-migration-doc.sh`
gates on the schema's `configVersion.const` changing, which it does not. Its successor for the
blocking case is `design.liveRender`, which already exists.

**The EP-6/7/8 trio is documented inert, not retired.** They lost their dispatchers (the stages)
but keep a validating reader, so by the letter of D-17 they are not reader-less. More
importantly, retiring an advertised consumer-pluggable extension surface is a product decision —
whether second-shift still offers blocking, consumer-owned gates, and what dispatches them on
the lean lane — that this deletion does not make and should not make silently. `docs/extending.md`
§3.6-3.8 now carries an INERT banner naming the cause, and the decision-guide table says so in
its Blocking? column. Filing the retirement is out of scope; the record is not.

## Acceptance criteria

- **AC-1 (oracle — CI).** The full selftest sweep is green after the deletion
  (`tools/run-selftests.sh`), and `shellcheck` + `jq empty` are clean. Plus the mechanical
  orphan check, run in the PR: a grep of every `*-selftest.sh`, `tools/*.tsv`,
  `scripts/*.tsv` and `scripts/lockstep-manifest.tsv` for any deleted or relocated
  `skills/run/` path returns empty, with exactly **two** exemptions, both stated rather than
  discovered: `tools/capability-parity.tsv`, whose rows are permanent historical citations by
  its own contract (`capability-parity-check.sh:29`) and are deliberately not existence-checked;
  and `tools/capability-parity-check-selftest.sh`, which must FABRICATE a `skills/run/stages`
  tree under its sandbox to exercise the coverage clause at all — the clause's own LIFETIME note
  forbids deleting it, so its test needs a stage doc to point at. `scripts/fail-open-sites.tsv`
  is inside this check (widened from the issue's glob per ledger D-15), and so is
  `.claude/prose-budget.baseline.tsv`, whose deleted rows were removed and whose moved rows were
  re-pointed **individually** — regenerating it wholesale would have reset a ratchet carrying 18
  pre-existing over-budget signals that have nothing to do with this change.
- **AC-2 (oracle — mutation sweep).** No baseline, exclusion, pair-map, slow-suite or catalog
  row references a deleted guard; every re-keyed row lands in this same diff, and
  `tools/mutation-sweep.sh` runs clean against the surviving guard set on the PR lane.
- **AC-3 (critic — review).** The scenario keep list is enumerated in the PR body with a
  one-line justification per kept **and** dropped scenario; the demotion register and the D-3
  `statectl` override are flagged there. The concrete pin release is recorded in the PR body
  and on the issue at merge.
- **AC-4 (oracle — CI).** Frozen-files green — no `version` or `CHANGELOG.md` edit (the major
  bump is derived from the `feat!` verb at release). A `Changelog:` trailer is present with a
  `Migration:` line naming both the pin and the relocated `config-lint.sh` path that the
  consumer CI template hardcodes.
- **AC-5 (oracle — CI).** `capability-parity-check.sh` stays green and its coverage clause
  reports itself **vacuous** (`stages/` gone) rather than violated — the success condition its
  own LIFETIME note declares.
- **AC-6 (doc).** Every doc that names deleted machinery is updated in the same diff — the
  AC-scoped doc obligation: `CLAUDE.md`, `docs/testing.md`, `docs/pipeline-manifesto.md`,
  `README.md`, `docs/{onboarding,namespaces,config-schema,extension-points,team-rollout,
  extending,live-render}.md`, and both plugin/marketplace descriptions. CLAUDE.md's coverage
  register and `tools/mutation-exclusions.tsv` move in lockstep. `docs/native-primitive-audit.md`
  is deliberately **excluded**: it is a dated audit record, and rewriting its subject would
  falsify the record.
- **AC-7 (oracle — CI).** The retirement of `stageParams.visualCapture` follows the established
  dead-key pattern end to end: `config-lint.sh` rejects it with a migration pointer, the schema
  no longer publishes it, `docs/migrations/v1-to-v2.md` carries the entry, and `configVersion`
  is unchanged — so `check-configversion-migration-doc.sh` stays green without a bump, exactly
  as `gates.costTracking`'s removal did.

## Out of scope

- Renaming `run-lean` now that `run` is gone — ledger D-4: it keeps its name here; a rename is
  its own consumer-visible ticket.
- The 14 `moot-via-348` issue closures and the post-landing recuts of #291/#240/#248/#108 —
  ledger D-8: operator acts at merge, not BUILD writes. The one in-diff successor act is
  dropping `lean-reconcile.sh`'s DEFERS-TO header (#292's successor).
- OR-2, the FE-canary merge precondition — operator-gated at merge time (ledger D-11).
