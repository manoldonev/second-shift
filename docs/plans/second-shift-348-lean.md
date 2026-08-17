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
| `cost-tracking-fixtures/` | listed under the **Deletion set** | **relocate** | Re-verified at implementation: it is not statectl-state-only. `cost-block-selftest.sh` survives the deletion and drives all four fixtures (the shared-session time-fence pair and the cross-vendor tier fixture), so deleting them would delete a live suite's only oracle. Declared here rather than left as a silent read of the deletion set. |
| `state-schema.md` | relocate, "no content edit beyond path fixes" | **relocate + historical banner** | Its siblings (`statectl.sh`, `verifyctl.sh`, `plan-scope-paths.sh`, `gen-statectl-validators.sh`) are all deleted, so there is no path to fix them *to* — the links cannot be re-pointed, only removed or declared. A banner declaring the file the pre-#348 format keeps the record legible and stops a future reader "fixing" dead links that name the machinery on purpose. The corpus `pipeline-retro`/`perf-retro` read is still in this shape. |

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
  orphan check, run in the PR, over every `*-selftest.sh`, `tools/*.tsv`, `scripts/*.tsv`,
  `scripts/lockstep-manifest.tsv` **and `.github/workflows/*.yml`**.

  The check's verdict is **"no orphaned reference"** — every `skills/run/` token that something
  actually resolves is re-pointed — **not** "the grep returns empty". It does not return empty,
  and claiming it did is how the next deletion's real orphan gets waved through (round-1 finding
  10). The surviving hits fall in seven stated classes, each a token nothing resolves:

  1. `tools/capability-parity.tsv` — rows are permanent historical citations by its own contract
     (`capability-parity-check.sh:29`), deliberately not existence-checked. Re-keying would
     destroy the audit trail this deletion exists to leave.
  2. `tools/capability-parity-check-selftest.sh` — must FABRICATE a `skills/run/stages` tree in
     its sandbox to exercise the coverage clause at all; the clause's LIFETIME note forbids
     deleting it, so its test needs a stage doc to point at.
  3. Consumer-side `.claude/`-prefixed literals exercising path matching generically —
     `is-inert-diff-selftest.sh:74`, `pre-commit-typecheck-selftest.sh:73,74`. The string is a
     *consumer's* tree, not this repo's.
  4. Fabricated version-cache layouts where the directory name is arbitrary —
     `pipeline-doctor-selftest.sh:687,693` builds a `1.0.0` cache for a version-ordering case.
  5. Prose and comments *about* the #348 move — `check-bounded-exploration-selftest.sh:389`,
     `workflows-mjs-selftest.sh:13`, `runtime-shim-lib.mjs:7`, `design-sync-selftest.mjs:49`,
     `docs/testing.md:404`, `docs/migrations/v1-to-v2.md:91`, `scripts/stack-generality-lint.sh:40`,
     and `state-schema.md`'s historical banner. Naming the old path is the point.
  6. The namespace-enforcement grep **pattern** — `.github/workflows/ci.yml:168,174` and
     `docs/namespaces.md:9,11`. `skills/run/` is a banned *token* in a denylist, not a path.
  7. `plugins/dev-pipeline/tools/review-harness-fixtures/harness-plan-alpha.md` — a frozen
     measurement instrument with deliberately planted defects, never implemented; the scorer's
     anchor-drift guard asserts its content does **not** move.

  `scripts/fail-open-sites.tsv` is inside this check (widened from the issue's glob per ledger
  D-15), and so is `.claude/prose-budget.baseline.tsv`, whose deleted rows were removed and whose
  moved rows were re-pointed **individually** — regenerating it wholesale would have reset a
  ratchet carrying 18 pre-existing over-budget signals unrelated to this change.

  The `.github/workflows/` arm is the round-1 lesson, not decoration: `nightly-guards.yml` invoked
  `prose-budget.sh` by its pre-move path and no reviewer window reached it, because #561 added that
  line to `main` **after** this branch's re-pointing commit and the rebase carried it in unswept. A
  deletion's blast radius includes CI definitions the branch never touched.

  **All three kinds of reference, not one (round-2 amendment).** The check above is keyed on the
  path prefix `skills/run/`, and this change broke three kinds of reference of which that key sees
  exactly one. Round 2 proved it: the path arm was exhaustively clean — re-verified, precisely the
  seven classes above, no eighth — while two other kinds were still broken in shipped artifacts.
  The check is therefore three checks, all run whole-tree:

  | Kind | Caught by the `skills/run/` grep? | Why |
  | --- | --- | --- |
  | a **path** into the deleted tree | yes | the token IS the path |
  | a **slash command** (`/dev-pipeline:run`) | **no** | the token contains no path at all |
  | a **relative link** whose depth changed under relocation | **no** | the link text never changes — only its resolution moves |
  | a **bare invocation** of the deleted command (`/dev-pipeline <issue>`) | **no** | it carries neither the path nor the `:run` suffix kind 2 keys on |

  - **Kind 4 — the bare command form (round-3 amendment).** Kind 2's regex keys on the `:run`
    suffix, so it is blind to the pre-namespacing invocation form `/dev-pipeline <issue>`, which
    three shipped artifacts still told a reader to run: `cost-tracking-setup.md`'s verification
    recipe, `intake/SKILL.md`'s routing table (twice), and `plan-interview/SKILL.md`'s pipeline
    pre-flight. `grep -rE '/dev-pipeline([[:space:]<`)]|$)'` finds it; the character class is what
    keeps `plugins/dev-pipeline/...` path noise out, and without it the result is unreadable.

  - **Kind 2 — the deleted command literal.** `grep -rE '/dev-pipeline:run([^-a-zA-Z]|$)'` over
    every tracked file. The negative class is load-bearing and is where a naive filter fails: an
    exclusion of `/dev-pipeline:run-lean` **hides the sharpest site**, because
    `templates/consumer/SECOND-SHIFT.md:15` names both literals on one line. Exempt only
    `CHANGELOG.md` (frozen release artifact), `docs/migrations/v1-to-v2.md` and
    `docs/onboarding.md`, which describe the removal in the past tense — naming the command is
    the point there.
  - **Kind 3 — relative-link resolution.** Resolve every relative markdown link against its own
    dirname, over every tracked `*.md`, and **run the same check at the merge-base and diff the
    two lists**: 7 of the branch-head failures predate this branch, and reporting those as this
    PR's finding is the same over-statement AC-1 was restated to stop. The residue after this
    round is 22 rows in two deliberate classes, both declared and neither shipped-doc:
    (a) the **historical plan/verdict corpus** (`docs/plans/acme-{90,93,146,272}.md` and this
    issue's own round-2 verdict record, which is the review *quoting* the links it found) — same
    contract as `capability-parity.tsv`, citations of the tree as it stood, which re-pointing
    would falsify; and (b) `plugins/dev-pipeline/state-schema.md`'s six links, dead by design
    under the banner it carries, which this round widened to name all six.
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

  The enumerated list is a floor, not the boundary — round 1 found four files of the same class
  outside it, and they are in scope: **shipped plugin docs whose copy-pasteable commands or
  `${CLAUDE_PLUGIN_ROOT}`-relative paths moved** (`cost-tracking-setup.md`,
  `cost-tracking-fixtures/README.md`, `tools/tracker/README.md`), and **relocated-verbatim docs
  whose sibling links no longer resolve** (`state-schema.md`). A doc that relocates at
  `similarity index 100%` is exactly where this rots: the move is invisible in review precisely
  because nothing in it changed. `${CLAUDE_PLUGIN_ROOT}`-relative paths are the sharp case — they
  are wrong for an *installed consumer*, not merely for this checkout.

  **Round-2 amendment — two further classes, both shipped and consumer-facing.** Round 2 found
  the floor short again, in files the panel could not structurally reach:

  1. **Artifacts advertising the deleted `run` skill or its stage vocabulary**, whatever the file
     type — the onboard template copied into every consumer repo
     (`templates/consumer/SECOND-SHIFT.md` and this repo's own `.claude/SECOND-SHIFT.md`),
     `onboard/SKILL.md`, `pipeline-retro/SKILL.md`'s frontmatter `description` (which is the text
     the skill listing shows), `schema/second-shift.config.schema.json`'s `ticketTag` description,
     and `.github/ISSUE_TEMPLATE/pipeline-aborted.yml`, whose whole shape — `failureContext`, the
     state file, "abort at Stage 6" — belonged to the deleted lane and is retargeted at the lean
     lane's progress record. `CHANGELOG.md` is exempt: a frozen release artifact recording what
     shipped.
  2. **Whole documents whose subject was the deleted lane**, not merely stale lines in them.
     `tools/tracker/README.md` carried a full operation-contract table headed "the **`run`**
     lane's"; `tracker/jira/README.md` framed its tables the same way and carried a draft-PR
     rationale that died with the manual promotion step. Both are rewritten around the surviving
     lane rather than link-patched — three broken links in one of them were the visible symptom,
     not the defect.

  **Round-3 amendment — the CONFIG layer, and a stated discriminator.** Three rounds each found
  this same class one layer further out, so the boundary is no longer an enumeration but a rule.
  A reference to deleted machinery is a **defect** iff it makes a *present-tense claim about the
  live mechanism*: the actor that resolves a config key, the guard that covers a behavior, the
  file a maintainer is told to keep in lockstep with, or the command a consumer is told to run.
  It is a deliberate **keep** iff it is one of: (a) an explicitly-dated historical statement
  ("died with the staged lane in #348"); (b) the proper name of a historical data format a
  surviving tool still reads ("a `statectl`-shaped state file"); (c) a frozen eval/review fixture
  whose content is test input (`review-harness-fixtures/`, `score-review-selftest.sh`'s
  grandfathered anchors, `dup-scan-fixtures/`); or (d) a measurement attributed to a named past
  era. The rule is what makes the residue auditable instead of re-litigated each round.

  Applied whole-tree over the deleted **tool names** (`statectl`, `verifyctl`) — which, unlike
  `Stage N`, are never legitimate in the present tense — it closes four sub-classes the
  skills/docs sweeps could not see:

  1. **The `$schema`-rendered config layer.** `schema/second-shift.config.schema.json` described
     the deleted lane as the live mechanism for **18** descriptions of keys that are live under
     lean, and these strings render in every consumer's editor as the authoritative account of a
     key they are setting. `docs/config-schema.md` mirrored three of them. Each is re-pointed to
     the reader named in the D-17 table above, not merely de-staged. The EP-6/7/8 descriptions
     additionally carry the §3.6-3.8 **INERT** banner, which had been applied to only one of the
     two consumer-facing surfaces.
  2. **False coverage claims.** A comment asserting a guard exists is read as coverage. Several
     named deleted suites: `intake-readroot-selftest.sh` said AC-5 "is guarded ... in
     `statectl-selftest.sh`" (AC-5's *subject* also died, so the guarantee is MOOT, not orphaned —
     recorded as such rather than re-homed), `retro-corpus-selftest.sh` and
     `pipeline-doctor-selftest.sh` cited deleted writers, and
     `pre-commit-typecheck-selftest.sh`'s header still advertised a `6-verify.md` contract the
     same file had already dropped at its case (1b).
  3. **Lockstep partners that no longer exist.** `preflight.sh` instructed maintainers to "keep
     this set in lockstep with verifyctl.sh" for a row the branch had already re-anchored to
     `lean-gate.sh`, and `lean-gate.sh` described `SEAM_SCRUB` as a `verbatim` row against that
     deleted file when the live row is `subset-of` against `preflight.sh`. Both directions are
     corrected, and the manifest's three DROPPED entries whose pairs died with the lane are marked
     **MOOT via #348** so they read as decision records rather than live reasoning.
  4. **A whole consumer-facing setup doc.** `cost-tracking-setup.md`'s entire operating model was
     the staged lane — a Stage-9 in-band sub-step, `statectl`'s write seam registering
     `pipelineSessions[]`, `costBlockApplied`, PR amendment. It is rewritten around the lane's
     actual invocation (`pipeline-cost-block.sh --stateless` at `build-lean` step 7, verified
     against the code): no PR amend, no recorded outcome, and no `cost-log.jsonl` row by D-36.
     The stateful path is kept and labelled a historical-record path — it has **no writer left in
     this tree**, which the doc now says outright.

  Also corrected here: `check-config-shadowing.sh`'s header contradicted the D-17 table in this
  very spec, claiming `formatGlob` and `gates.mutation` were rejected as removed keys when both
  are kept and reader-backed; and `doctor.sh`'s bundle now actually contains what the retargeted
  abort template says it does (see AC-6's blocker-1 remedy — `state_excerpt()` prefers the lean
  progress record and tails it, guarded by two new probe-verified cases).

  **A fixture whose only oracle was deleted is an orphan too.** Round 3's own sweep found
  `tools/stage-times-fixtures/acme-89-pause.json` reachable by no suite: its `(pause3)`/`(pause4)`
  cases lived in `statectl-selftest.sh`, and every case in the surviving `stage-envelopes-selftest.sh`
  generates `pauseSpans: []`. `stage-times.sh`'s pause arithmetic was therefore live, shipped and
  unguarded. The cases are **re-homed** as `(env16)`/`(env16b)` in that suite rather than dropped —
  the deletion may not silently retire a guard's subject.
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
