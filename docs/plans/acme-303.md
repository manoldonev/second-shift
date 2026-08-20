# Plan — #303: `/dev-pipeline:run-lean`, outcome-gated lean harness (experimental)

## Context / problem framing

Per-run cost of the full `run` pipeline is the binding constraint today. #303 extracts the
run-lean track from the #284 ablation epic and pulls it forward as a daily driver, on the
argument that the harness is useful independently of when the ablation study runs.

The operating principle is **outcome-gated, not process-prescribed**: five ordered
milestone gates assert *artifacts*, and the harness says nothing about the path between
them. The expensive design thinking happens BEFORE the run (plan-interview / grill-me /
intake), and its residue is the `ready-for-dev` label plus an optional pre-flight ledger.
In-run quality spend is concentrated in exactly one place — the independent review at
milestone 4.

The load-bearing asymmetry (D-47): **lean-in-run is not lean-in-enforcement.** Every in-run
record is written by the agent being checked, so it is at best tamper-evident. The binding
evidence contract therefore lives at the model-free merge boundary, where it costs zero run
tokens: a CI chain gate over committed artifacts, a committed (not local) verdict record,
and reconciliation keys the operator-side `lean-reconcile.sh` checks before merge.

Nothing in `run`'s behavior changes; backwards compatibility is structural (a new sibling
skill plus one additive flag).

## Assumptions

1. **The intake fan-out's `spec-reviewer` verdict was obtained via a manual fallback.** The
   in-workflow dispatch died dark twice (empty result at the turn cap). The review was
   recovered and its findings are folded in below; five gaps were resolved at intake and
   are treated here as settled.
2. **`paths` is unset in the runtime config**, so `paths.plansDir` → `docs/plans` and
   `paths.pipelineStateDir` → `.claude/pipeline-state` (schema defaults). The lean artifacts
   are placed accordingly. Consumers that set these keys get the configured values; nothing
   is hardcoded.
3. **`commands.second-shift.unitTestScope` is null**, so this ticket has no mutation
   surface in the unit-test sense and `unitTestSurface` is `skip`. The repo's own
   `tools/mutation-sweep.sh` (shell-guard mutation) is a separate mechanism and *is* in play.
4. **`$CLAUDE_CODE_SESSION_ID` is the session identity** for AC-14's ledger predicate.
   Verified at intake: the variable is set, the main-checkout-anchored
   `.claude/audit/<id>.jsonl` exists and is non-empty, and `cost-tracking-setup.md` states
   that UUID is the same value the OTel exporter tags as `session.id`. An unset variable is
   a fail-closed refusal, which is what AC-14 asks for.
5. **`check-model-tiers.sh` scans a fixed list of six named tables** under
   `skills/run/workflows/`; it does not glob-discover. A table-less `lean-review.mjs` in a
   new directory is therefore not scanned, and a `reviewers.modelOverrides` entry with no
   agent file behind it cannot raise `DANGLING`. This is what makes D-2's "zero model
   claims" and AC-11's "no schema change" simultaneously satisfiable.
6. **This ticket's own delivery PR is a pipeline PR** on `claude/second-shift-303` and will
   carry lean-shaped fixture files. AC-13's exclusion arm is what keeps it from being
   double-classified — the plan treats that as a first-class test case, not an afterthought.

## Decision Ledger

Hydrated verbatim from the pre-flight ledger at
`.claude/pipeline-state/303-ledger.md` (49 rows, binding per D-11).

| ID   | Decision | Resolution | Provenance |
| ---- | -------- | ---------- | ---------- |
| D-1  | Mission priority | Dogfood daily-driver first; Arm-E fidelity yields where they conflict | user-answered |
| D-2  | Model binding | Model-agnostic skill, zero model claims, no model table in the workflow; session tier = operator's choice; lean reviewer tier via a reserved bare name in `reviewers.modelOverrides` (config entry, not a new key; #77 closed) | user-answered |
| D-3  | Extraction scope | run-lean track only; ablation setup/measurement tracks stay unfiled | user-answered |
| D-4  | Build vehicle | This issue travels the full pipeline, as-configured (epic P1 statement holds) | user-answered |
| D-5  | Rollback criterion | Substantive policy violation reaching a PR = stop + finding; quality judged per-PR | user-answered |
| D-6  | Default-switch authority | Informal switch on dogfood evidence allowed; formal promotion stays on #284 D-12 | user-answered |
| D-7  | Tracker writes | Claim comment + one closing comment (cost block + PR link); abort reuses the closing slot | user-answered |
| D-8  | Branch identity | Prefix derived from `tracker.branchPrefix`; selftest-asserted non-prefix-match vs the pipeline prefix; lean PRs answer to their own chain gate (D-45) — the earlier "zero chain evidence" resolution is struck | user-answered |
| D-9  | Spec/AC home | Configured `paths.plansDir`, lean-marked filename not matching the pipeline plan pattern; merges with the PR | user-answered |
| D-10 | AC shape | ≥ 1 numbered AC-n mechanically asserted; rest of the file free-form | user-answered |
| D-11 | Ledger hydration | Pre-flight ledger binding when present, never required | user-answered |
| D-12 | Pre-implementation review | None — existence/format gate only; no plan-reviewer dispatch | user-answered |
| D-13 | Policy gate set | frozen-files + changelog-trailer diff-scoped (the feature-PR half of pr-gates); release-only, lockstep, namespace checks excluded with stated reasons; consumer repos get detect-and-skip notices | user-answered |
| D-14 | Commit identity | bot-commit.sh; amend caveat as checklist line; no env export (worktree-safe since #110) | user-answered |
| D-15 | Scope-drift disclosure | Amend the spec/AC file (living DoD) before milestone 5; reviewer-checked, not gate-checked | user-answered |
| D-16 | Entry gate | Strict ready-for-dev reject, no prompting | user-answered |
| D-17 | Green-gate source | Config `commands.<repoSlug>` directly (lanes + non-null trio/quad); no verifyctl, no inert lane | user-answered |
| D-18 | Mutation sweep | Auto-detect `tools/mutation-sweep.sh`; run diff-scoped when present; printed skip notice | user-answered |
| D-19 | Fix budget | 3 attempts per milestone, then hard stop; increment rule per D-41 | user-answered |
| D-20 | Abort disposition | Progress file + one abort comment; worktree kept; issue left `in-progress` for manual rescue | user-answered |
| D-21 | Review shape | Single fresh-context generalist, prompt-defined in the workflow (no new agent artifact); review-lead an unmandated pool | user-answered |
| D-22 | Verdict semantics | Blocking approve-or-fix loop within the fix budget; the committed in-branch verdict record is the record of record (progress-file line is the local counter only) | user-answered |
| D-23 | Reviewer transport | Schema-free explorer + sentinel + in-script parse, `structured-emitter` fallback on parse miss, wall-clock ceiling (the measured solved transport; schema-forced single dispatch measured 7/8 deaths) | codebase-derived |
| D-24 | Progress file | Append-only markdown at configured `paths.pipelineStateDir`, lean-marked | user-answered |
| D-25 | Resume | Re-enter from progress file; idempotent gates; rebase if base moved | user-answered |
| D-26 | Attestation | Hook ledger REQUIRED at entry; all records carry RUN_ID + session reconciliation keys (audit-ready); the mechanical verifier itself rides #292 (owner: operator; due at promotion) | user-answered |
| D-27 | PR contract | Ready PR, minimal body (summary, spec link, verdict line, closes); gate-asserted at milestone 5 | user-answered |
| D-28 | Cost instrument | pipeline-cost-block.sh state-less mode (additive flag; session ids + time fence as args, progress file the carrier; session-window totals; no cost-log row per D-36; session posts it in the closing comment); collector-down stated explicitly | user-answered |
| D-29 | Doc updates | AC-scoped in the spec file; no doc-updater dispatch | user-answered |
| D-30 | Evidence bar | 3 clean merged lean PRs (≥ 1 plugins/**) before the informal default switch | user-answered |
| D-31 | Isolation | Dedicated worktree; kept on abort; removed on clean exit | user-answered |
| D-32 | Doctor blind spot | Stale lean claims invisible to pipeline-doctor — accepted, documented here; no synthetic state file (it would flip blindness into misreads) | user-answered |
| D-33 | 60-line cap | Selftest asserts `wc -l SKILL.md ≤ 60` incl. frontmatter; single-row prose-budget baseline addition, verified no other row moved | user-answered |
| D-34 | Config surface | Zero NEW keys (no schema/configVersion change); read-set per AC-11 | user-answered |
| D-35 | Gate script shape | One `lean-gate.sh` with subcommands `1..5\|all` | user-answered |
| D-36 | Corpus hygiene | Lean runs excluded from retro/eval/perf corpora by declaration; lean-marked artifacts | user-answered |
| D-37 | Spec authoring | In-session, pools unmandated; issue comments readable (blinding is ablation-only) | user-answered |
| D-38 | First dogfood targets | Deferred (owner: operator, at run time); constraint carried: ≥ 1 of first 3 touches `plugins/**` | deferred |
| D-39 | Release posture | Normal release train; experimental marking in description and changelog entry | user-answered |
| D-40 | Queue disposition | ready-for-dev on filing; pre-flight ledger written alongside | user-answered |
| D-41 | Fix-budget increment rule | Only FAILED evaluations append `attempt` lines; passes append one idempotent `satisfied` line; count = failed lines per milestone | user-answered |
| D-42 | Exit-artifact gating | Milestone 5 asserts PR + body elements + closing comment mechanically (no prose-mandated exit artifacts) | user-answered |
| D-43 | Label transitions | Claim swaps to `in-progress`; clean exit removes it; abort leaves it (run precedent) with the abort comment as signal | user-answered |
| D-44 | Milestone-2 consumer posture | Gate scripts are repo artifacts, not plugin payload: detect-and-skip with printed notice outside this repo (D-18 posture) | user-answered |
| D-45 | Lean chain gate | Sibling `check-lean-chain.sh` in pr-gates; applies on prefix-match OR lean-artifact presence (non-vacuous); requires committed spec + committed approve-verdict + `lean-claimed` trail; lands in THIS issue; dogfood-scoped — consumer-side enforcement is a promotion prerequisite | user-answered |
| D-46 | Verdict record home | Committed in-branch next to the spec, referenced in the closing comment; agent-authored hence tamper-evident (the honest ceiling), reconciled at the boundary and by #292 later | user-answered |
| D-47 | Trust posture | Lean-in-run ≠ lean-in-enforcement: integrity gates live at the model-free merge boundary (zero run tokens); agent-writable counters are cost-control only | user-answered |
| D-48 | Verdict reconciliation | Operator-side `lean-reconcile.sh` before merge (audit-ledger dispatch presence, timestamp order, RUN_ID consistency); lean-scoped forerunner that defers to #292 when it lands | user-answered |
| D-49 | Claim contract | Two bot-wrapper writes: label swap + `lean-claimed`/`run_id` marker comment (lean-distinct marker to avoid pipeline family-selection pollution) | user-answered |

**D-36 — corpus half superseded (#565).** The row above stays as written: it is a ratified
`user-answered` record of what was decided in this interview, not a live policy statement, and
rewriting it would erase the history. Only one of its two halves is still in force. The
*no-`cost-log.jsonl`-row* half is live and guarded by `cost-block-selftest.sh`'s AC-8. The
*"lean runs excluded from retro/eval/perf corpora"* half died in code with #347 (which made
`retro-corpus.sh` enumerate lean records) and is retired in prose by #565, which derives the
lean timing profile from those same records via `retro-corpus.sh timing`.

### Intake-resolved gaps (settled; carried as design constraints)

| Gap | Resolution adopted here |
| --- | --- |
| G-1 | AC-3's "and nothing else" scopes **content** assertions. The milestone-1 gate resolves the lean-marked path from the single pinned pattern (below) and asserts existence *at that path* + ≥ 1 `AC-n`. |
| G-2 | A `satisfied` line is a record, **not a cache**. `lean-gate.sh all` re-evaluates every milestone against the current tree; milestone 5 requires an `all` sweep green on the final tree. |
| G-3 | AC-9's property is **mutual**: neither prefix may be a prefix of the other; the selftest asserts both directions. |
| G-4 | AC-13 is **authoritative** over the entry-contract prose for applicability. |
| G-5 | All three lean-marked names derive from **one pinned table** (below), consumed identically by the skill and the CI gate. |

### Pinned lean-marked name table (G-5 — single source for three consumers)

Worked against this repo's config, to show the patterns resolve. The spec, verdict and
progress values are what a *lean run* of #303 would produce — this pipeline run does not
create them.

| Artifact | Pattern | Resolves to |
| --- | --- | --- |
| Branch prefix | `lean/` + `tracker.branchPrefix` with its first path segment removed | `lean/second-shift-` |
| Spec / AC file | `<plansDir>/<repoSlug>-<issueKey>-lean.md` | `second-shift-303-lean.md`, under the configured plans dir |
| Verdict record | `<plansDir>/<repoSlug>-<issueKey>-lean-verdict.md` | `second-shift-303-lean-verdict.md`, alongside it |
| Progress file | `<pipelineStateDir>/<issueKey>-lean-progress.md` (main checkout) | `.claude/pipeline-state/303-lean-progress.md` |

Derivation properties, all selftest-asserted:

- `lean/second-shift-` and `claude/second-shift-` are **mutually** non-prefix-matching, so
  `check-pipeline-chain.sh` classifies a lean PR not-applicable and `check-lean-chain.sh`
  classifies a pipeline PR not-applicable by prefix.
- The derivation errors loudly rather than returning a colliding prefix when the configured
  prefix already begins with `lean/`.
- The spec pattern does not satisfy `PIPELINE_PLAN_PATTERN` (`docs/plans/acme-{issueKey}.md`).
- The spec glob is suffix-anchored `*-lean.md`, so the verdict record (`*-lean-verdict.md`)
  is never mistaken for the spec.

## Affected files/modules

### Created

- `plugins/dev-pipeline/skills/run-lean/SKILL.md` **[NEW]** — the ≤ 60-line checklist.
- `plugins/dev-pipeline/skills/run-lean/lean-gate.sh` **[NEW]** — the five milestone gates
  plus the `entry` subcommand.
- `plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh` **[NEW]** — same-stem killer.
- `plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh` **[NEW]** — operator-side verifier.
- `plugins/dev-pipeline/skills/run-lean/lean-reconcile-selftest.sh` **[NEW]** — same-stem killer.
- `plugins/dev-pipeline/skills/run-lean/workflows/lean-review.mjs` **[NEW]** — the reviewer
  Workflow.
- `scripts/check-lean-chain.sh` **[NEW]** — the CI merge-boundary gate.
- `scripts/check-lean-chain-selftest.sh` **[NEW]** — same-stem killer.

### Modified

- `.github/workflows/ci.yml` — one step added to the existing `pr-gates` job.
- `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` — additive state-less mode.
- `plugins/dev-pipeline/skills/run/tools/cost-block-selftest.sh` — cases for the new mode.
- `plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs` — lean-review case.
- `plugins/dev-pipeline/skills/run/workflows/design-sync-selftest.mjs` — Case I glob widened
  to the sibling `run-lean/workflows/` directory (see step 9).
- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration.sh` — same widening, for
  the schema-carrying-dispatch lint (see step 9).
- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration-selftest.sh` — a case
  covering the widened directory list.
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — three additive lean legs.
- `tools/mutation-baseline.tsv` — re-key the four `pipeline-cost-block.sh` survivor rows.
- `tools/mutation-catalog.tsv` — re-anchor `cost-block-cache-numerator`.
- `scripts/lockstep-manifest.tsv` — one **DROPPED** entry for the lean-prefix constant.
- `.claude/prose-budget.baseline.tsv` — one row for `run-lean/SKILL.md`.

Unverified references: none. Every path above either exists at HEAD (verified by read) or
carries `[NEW]`.

## Reuse inventory

Every entry grep-verified against the worktree at HEAD.

| Reused artifact | Used for |
| --- | --- |
| `plugins/dev-pipeline/skills/run/tools/claim-issue.sh` | The claim label swap (AC-15) — invoked, not reimplemented; already carries the add-before-remove + confirm-before-DELETE discipline. |
| `plugins/dev-pipeline/skills/run/tools/bot-commit.sh` | All lean commits (D-14); resolves the bot identity and the main-checkout config on its own. |
| `scripts/check-frozen-files.sh`, `scripts/check-changelog-trailer.sh` | Milestone 2 shells out to both with a base ref (AC-4); confirmed both take the ref as `$1` (as `ci.yml` invokes them). |
| `tools/mutation-sweep.sh` | Milestone 3's diff-scoped sweep when present (AC-5). |
| `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` | Extended in place with the state-less mode (AC-8) rather than duplicated. |
| `plugins/dev-pipeline/skills/run/workflows/runtime-shim-lib.mjs` | Imported by the new shim case (AC-10) — the wrapper is never re-created, per the no-mirror-harness rule. |
| `scripts/check-pipeline-chain.sh` | **Pattern source only, never edited** (D-45). `check-lean-chain.sh` reuses its shape: env-only inputs, `.user.type == "Bot"` trust filter, PR-open comment windowing, exact-string run-family comparison, `--comments-file` fixture seam. |
| `plugins/audit-toolkit/hooks/audit-tool-calls.sh` | Read-only source of the audit ledger `lean-reconcile.sh` reconciles against (AC-16). |

No new shared helpers are introduced — `none — no new helpers introduced` beyond the four
scripts listed as created above, each of which is a top-level artifact required by an AC.

## Implementation steps

1. **Name derivation + progress-file primitives in `lean-gate.sh`.** Config resolution
   (`paths.plansDir`, `paths.pipelineStateDir`, `tracker.branchPrefix`, `tracker.labels`,
   `topology.repos.<repoSlug>.baseBranch`, `commands.<repoSlug>`), the pinned name table,
   the mutual non-prefix-match assertion with a loud error on collision, and the
   append-rule helpers. Progress-file header carries `run_id`, `session_id`, `issue`.
   Line shapes (pinned, greppable):
   `<iso> | milestone-<n> | attempt | <reason>` and `<iso> | milestone-<n> | satisfied`,
   plus milestone 4's `milestone-4 | verdict=<approve|needs-work> | round=<n>`.
   Attempt count = failed lines for that milestone (D-41); the 4th appended attempt on one
   milestone is the hard stop (D-19).
2. **`lean-gate.sh entry`** — AC-14's mechanical refusal: main checkout resolved via
   `git rev-parse --git-common-dir`, then a **non-empty** `.claude/audit/$CLAUDE_CODE_SESSION_ID.jsonl`.
   Directory existence is explicitly not the test. Also asserts the strict `ready-for-dev`
   posture (D-16). *Deliberate reading of AC-2: `entry` is additive to `1..5|all`, not a
   replacement — AC-14 requires a mechanical gate and D-35 requires one script.*
2a. **Claim contract (AC-15 / D-49).** The two bot-wrapper writes, implemented as the
   `SKILL.md` checklist's claim step plus a `lean-gate.sh claim <issue>` helper so the
   write pair is mechanical rather than prose: (i) the label swap via the existing
   `claim-issue.sh` with queue/claimed names from `tracker.labels`, then (ii) the claim
   comment carrying `<!-- stage: lean-claimed -->` and `<!-- run_id: ... -->`. The marker is
   **lean-distinct** — never `stage: claimed` — so it cannot pollute the pipeline chain
   gate's family selection if the same issue is later run through full `run`. RUN_ID is a
   neutral token matching the chain gate's `^[A-Za-z0-9._-]+$` charset. *This step was
   missing from the first draft; `check-lean-chain.sh` requires exactly this comment as one
   of its three evidence artifacts, so without it the CI gate would fail every lean PR.*

3. **Milestones 1–3.** M1: spec existence at the pinned path + ≥ 1 `AC-n` (G-1). M2:
   frozen-files + changelog-trailer diff-scoped against the configured `baseBranch`, with
   advisory output appended to the progress file and a printed skip notice when the scripts
   are absent (AC-4/D-44). M3: `commands.<repoSlug>` lanes-then-non-null-trio/quad with no
   inert lane, plus the diff-scoped mutation sweep when `tools/mutation-sweep.sh` exists
   (AC-5/D-18). Mind the documented `grep -c`-not-`-q` SIGPIPE class if wrapping under
   `set -o pipefail`.
4. **Milestone 4 + `lean-review.mjs`.** The workflow declares **no model table** and reads
   only `args.config.reviewers.modelOverrides` for a reserved bare `lean-reviewer` name,
   passing `model` only when present so the runtime default otherwise applies (D-2).
   Transport is the measured shape: schema-free explorer, sentinel + fenced JSON,
   in-script parse and shape-validate, `review-toolkit:structured-emitter` only on a parse
   miss, plus a wall-clock ceiling (D-23). The gate asserts the **committed** verdict record
   reads `verdict=approve` (D-22/D-46); the progress-file line is a local counter only.
5. **Milestone 5.** Progress file current, ready (non-draft) PR with `Closes #<issue>` and a
   spec link, closing comment referencing the verdict record (AC-7/D-42). Fixture seams
   (`--pr-file`, `--comments-file`) designed in, not retrofitted.
6. **`all` sweep semantics (G-2).** Evaluate 1..5 in order against the current tree, stop at
   the first failure and report it. `satisfied` lines never short-circuit evaluation.
7. **`scripts/check-lean-chain.sh` [NEW] + selftest.** Applicability per AC-13: prefix-match **OR**
   (lean-marked spec in the diff **AND** head ref not matching `PIPELINE_BRANCH_PREFIX`),
   with `fixtures/` paths excluded from the artifact scan. Reads the job-level
   `PIPELINE_BRANCH_PREFIX` already set on `pr-gates` — no second constant needed. Evidence
   set: committed spec with `AC-n`, committed `verdict=approve` record, bot-authored
   `lean-claimed` comment windowed at PR-open. Unresolvable `LEAN_BRANCH_PREFIX` is fatal,
   never exempt.
8. **`ci.yml` wiring.** One step in `pr-gates`, all inputs via `env:` (never interpolated
   into the `run:` body): `LEAN_BRANCH_PREFIX`, plus `GH_TOKEN` (`secrets.GITHUB_TOKEN`)
   and `GH_REPO` (`github.repository`) for the gate's bot-comment read, plus
   `PR_HEAD_REF` / `PR_BODY` / `PR_CREATED_AT` / `PR_BASE_REF`. The job already sets
   `PIPELINE_BRANCH_PREFIX` at job level, so the exclusion arm needs no second constant,
   and its existing `permissions:` block already grants `issues: read`.
9. **Lint coverage for the new workflow directory.** Two existing lints are anchored to
   `skills/run/workflows/` and would silently miss a workflow in a sibling directory —
   verified, not assumed:
   - `design-sync-selftest.mjs` Case I (Workflow meta literal-purity) globs
     `readdirSync(HERE)`. Its coverage is load-bearing: the shim's meta-strip is a
     balanced-brace scan whose soundness rests on this lint.
   - `check-bounded-exploration.sh` globs `"$WORKFLOWS"/*.mjs` derived from `skills/run`,
     and `lean-review.mjs`'s `structured-emitter` fallback **is** a schema-carrying
     dispatch, so it needs a declared disposition marker like every other one.

   Widen both to scan a small **list** of workflow directories rather than one hardcoded
   path, so a future third directory is one list entry in each file rather than another
   silent hole. Keeping each check with its existing owner avoids a second copy of the
   rule (the mirror-harness pattern this repo forbids).
10. **`pipeline-cost-block.sh` state-less mode (AC-8).** Flag parsing moves **ahead of** the
    required `$1` positional so existing invocations stay byte-identical in behavior;
    `--stateless --sessions <ids> --start <iso> --end <iso> [--out <file>]` emits
    session-window totals to stdout/file, amends no PR body, and writes **no**
    `cost-log.jsonl` row (D-36). Collector-down is stated explicitly in the emitted block.
11. **`lean-reconcile.sh` + selftest (AC-16).** Reviewer-dispatch presence in the session
    audit ledger, timestamps preceding the verdict commit, and RUN_ID consistency across
    claim comment / verdict record / progress file. Header states it defers to #292 on
    arrival.
12. **`run-lean/SKILL.md`** — authored last so it describes what shipped; ≤ 60 lines
    including frontmatter, description marked experimental.
13. **Registers, same diff.** Re-key the four `pipeline-cost-block.sh` survivor rows in
    `tools/mutation-baseline.tsv`; re-anchor `cost-block-cache-numerator` in
    `tools/mutation-catalog.tsv` (anchor drift is a hard red, not a baselined survivor);
    add the single `run-lean/SKILL.md` row to `.claude/prose-budget.baseline.tsv` verifying
    no other row moved (**not** a wholesale `--update-baseline`); add the DROPPED
    lockstep entry for the lean-prefix constant with its non-byte-anchorable rationale.

## Test strategy

Verify-after (infra/tooling change; no product behavior). `unitTestSurface` is **skip** — the
repo declares no `unitTestScope`, so there is no co-located unit-test mutation surface.

- **`lean-gate-selftest.sh`** — behavioral, fixture-per-milestone-verdict: each milestone's
  pass and fail arms; the append rules (a failed evaluation appends exactly one `attempt`;
  repeated passes and `all` sweeps never inflate the counter — the D-41 idempotency
  property); attempt-count derivation and the 4th-red hard stop; the `entry` gate's
  empty-ledger and missing-ledger refusals; the **mutual** non-prefix-match assertion in
  both directions plus the collision error (AC-9/G-3); `wc -l SKILL.md ≤ 60` (D-33); and
  the G-2 property that a `satisfied` milestone is still re-evaluated by `all`.
- **`check-lean-chain-selftest.sh`** — zero-network via the `--comments-file` /
  `--diff-files-file` seams, following the existing chain-gate precedent. Required cases:
  the **zero-matching-prefix-with-artifacts** case (proves the artifact trigger is
  non-vacuous), the **pipeline-prefixed-PR-carrying-a-lean-shaped-file** case (proves this
  ticket's own delivery PR is not double-classified), each missing-evidence arm, the
  fixture-path exclusion, and a fatal unresolvable `LEAN_BRANCH_PREFIX`.
- **`lean-reconcile-selftest.sh`** — dispatch-absent, timestamp-inverted, and
  RUN_ID-mismatch arms all fail; the fully consistent arm passes.
- **`runtime-shim-selftest.mjs`** — a `lean-review.mjs` case driving the **production**
  body through `runtime-shim-lib.mjs`: clean sentinel parse, parse-miss → emitter fallback,
  and the wall-clock ceiling. No hand-maintained copy of the transport.
- **`scenario-liveness-selftest.sh`** — three additive lean legs asserting the
  progress-file line chain and gate exit codes end to end: all-green → exit artifacts;
  budget-exhaust → abort record (worktree kept, issue left `in-progress`); needs-work →
  fix-loop re-entry. These legs are where the prose-only failure economics (fix budget 3,
  4th-red hard stop, abort comment) become mechanically asserted. **The all-green leg is
  also AC-15's assertion site**: the claim is executed by the session following `SKILL.md`
  rather than by a gate, so the leg asserts both bot-wrapper writes land — the label swap
  and a `lean-claimed`-markered comment carrying the run id.
- **`cost-block-selftest.sh`** — new-mode cases plus an explicit assertion that the
  state-file path is behavior-unchanged and that the state-less mode writes no
  `cost-log.jsonl` row.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | SKILL.md exists, ≤ 60 lines, experimental | 12 | `lean-gate-selftest.sh` (AC-1) 60-line assertion |
| AC-2 | `lean-gate.sh` subcommands `1..5\|all` + append rules | 1, 2, 6 | `lean-gate-selftest.sh` (AC-2) append/idempotency/derivation cases |
| AC-3 | Milestone 1 asserts spec + `AC-n` only | 3 | `lean-gate-selftest.sh` (AC-3) M1 pass/fail arms |
| AC-4 | Milestone 2 policy gates, advisory surfacing, skip notice | 3 | `lean-gate-selftest.sh` (AC-4) M2 arms incl. scripts-absent |
| AC-5 | Milestone 3 green gate + mutation-sweep auto-detect | 3 | `lean-gate-selftest.sh` (AC-5) M3 arms incl. sweep-absent |
| AC-6 | `lean-review.mjs` transport + committed verdict gating | 4 | `runtime-shim-selftest.mjs` lean-review case; `lean-gate-selftest.sh` (AC-6) verdict arms |
| AC-7 | Milestone 5 exit artifacts + label transitions | 5 | `lean-gate-selftest.sh` (AC-7) M5 arms via `--pr-file`/`--comments-file` |
| AC-8 | Cost-block state-less mode, additive | 10 | `cost-block-selftest.sh` (AC-8) new-mode + unchanged-path cases |
| AC-9 | Lean prefix derived; non-prefix-match asserted | 1 | `lean-gate-selftest.sh` (AC-9) both-direction + collision cases |
| AC-10 | Testing obligations delivered | 9, 13, all test steps | the five suites above; `.claude/prose-budget.baseline.tsv` single-row check |
| AC-11 | Zero new config keys | 1 | `lean-gate-selftest.sh` (AC-11) read-set assertion — no schema edit in the diff |
| AC-12 | No behavioral change to `run`/statectl/verifyctl | 10 | `cost-block-selftest.sh` unchanged-path case; full selftest sweep green |
| AC-13 | `check-lean-chain.sh` + CI wiring, non-vacuous | 7, 8 | `check-lean-chain-selftest.sh` (AC-13) incl. both mandated cases |
| AC-14 | Entry gate refuses without a live audit ledger | 2 | `lean-gate-selftest.sh` (AC-14) empty/missing-ledger refusals |
| AC-15 | Claim is two bot-wrapper writes | 2a | `scenario-liveness-selftest.sh` all-green leg (claim assertions) |
| AC-16 | `lean-reconcile.sh` + behavioral selftest | 11 | `lean-reconcile-selftest.sh` (AC-16) all four arms |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
bash scripts/check-lockstep-pairs.sh
BASE="$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h
                | .topology.repos[$h].baseBranch // "main"' .claude/second-shift.config.json)"
bash tools/mutation-sweep.sh --mode pr --base "origin/$BASE"
```

The selftest sweep runs **without** `SKIP_STRESS=1` locally so the stress legs are actually
exercised — CI's ubuntu lane is the only other place they run.

## Risks / rollback notes

1. **The lean prefix constant is a T0 residual, not a lockstep pair.** `LEAN_BRANCH_PREFIX`
   in `ci.yml` is unreconciled against the gitignored runtime config, exactly like
   `PIPELINE_BRANCH_PREFIX`. The compensating control is AC-13's artifact-presence trigger,
   which fires even with a zero-matching prefix. Recorded as a DROPPED lockstep entry rather
   than silently omitted.
2. **`pipeline-cost-block.sh` is a mutation-swept guard on the slow list.** Its four survivor
   rows re-key and the catalog anchor re-anchors in this diff; anchor drift is a hard red.
   Kills grade at the nightly lane, not the PR lane, so a PR-lane green is not proof the
   catalog row still kills.
3. **Three new checked-in `.sh` guards.** Each needs its same-stem selftest or the sweep reds
   on an unaccounted guard — that check is repo-wide, not diff-scoped, so it cannot be
   deferred.
3a. **Two lints are directory-anchored to `skills/run/workflows/`** (step 9). Widening them
   to a list is the fix here, but the coupling is worth naming: adding a *third* workflow
   directory later without updating both lists reintroduces the same silent hole. The two
   lists are not byte-anchorable against each other (bash array vs JS array), so this is a
   documented coupling rather than a lockstep pair.
4. **Milestone gates that shell out to repo scripts are second-shift-only.** Outside this
   repo they detect-and-skip with a printed notice (D-44); consumer-side merge-boundary
   enforcement is a named promotion prerequisite, not delivered here.
5. **Rollback** is clean: the skill is additive and experimental, and the only shared-file
   change is one additive flag. Reverting the commit removes the harness without touching
   `run`. Per D-5, any substantive policy violation reaching a PR stops the experiment.

## Out-of-scope

- Behavioral changes to `run`, its stages, `statectl`, or `verifyctl` (additive test rows
  and the additive cost-block flag are explicitly in scope).
- Pipeline-doctor awareness of lean claims (D-32 — accepted blind spot for the experiment).
- The general attestation verifier (#292 territory); `lean-reconcile.sh` is the lean-scoped
  interim that defers to it on arrival.
- Retro / eval / perf tooling changes — lean runs are out of those corpora by declaration.
- The ablation setup track and any measurement runs.
- New config keys, `configVersion` changes, and consumer docs beyond the derived changelog.
