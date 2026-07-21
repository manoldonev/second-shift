# Plan — #169: BOUNDED_EXPLORATION on every schema-carrying dispatcher, with a lint that keeps it there

## Context / problem framing

The `StructuredOutput` staller kills a schema-forced subagent before it emits. The mechanism is
already measured and recorded in `plugins/dev-pipeline/skills/run/workflows/code-review.mjs`
(the `ROOT CAUSE` block, lines 114-157): reviewers exhaust their turn budget **grounding the
absence of findings** — opening files across the whole input to prove nothing is wrong — and die
before the structured call. The probe that settled it also falsified the alternatives: prose
framing (`STRUCTURED_OUTPUT_FIRST`) moved the rate 2/8 to 2/8, relocating the instruction into
the inherited `reviewer-baseline` doc cured 0 of 6, and a model-tier bump only halved it at twice
the cost. Only the **dispatch-time** `BOUNDED_EXPLORATION` nudge cured it: ~50% to 0/12, with ~45%
fewer tokens.

That nudge ships on exactly one dispatcher. `plan-review.mjs` carries the full mitigation stack
#82 asked for (`STRUCTURED_OUTPUT_MANDATE`, `dispatchSchemaAgent` with `retries = 2`, a 15-minute
`withCeiling`) and still failed **6 dispatches out of 6** on run `2026-07-21T110723Z`, aborting
`/dev-pipeline:run 165` at Stage 4. #82 copied the measured non-fixes and missed the measured fix.

This plan closes the gap on the dispatchers where it is measurable, declares a waiver everywhere
it is deliberately absent, and lands a lint so the omission cannot recur silently. Per the #160
report across 23 retros, no deviation class ever stopped recurring from a prose strengthening —
only from a mechanical gate. The lint is what makes this one stay fixed.

## Assumptions

- The Workflow runtime surfaces **no turn count** in an `agent()` result, and the rejection string
  is identical for a stochastic death and a turn-budget wall. Verified: the only discriminator in
  the codebase is `isNoStructuredOutputError` (`plan-review.mjs:52`, `unit-tests.mjs:102`, the
  latter commented "the only signal the runtime surfaces"). No turn-count discriminator is invented
  here.
- `maxTurns` is not settable from a Workflow script — the `agent()` options surface exposes
  `label`, `phase`, `schema`, `model`, `effort`, `isolation`, `agentType` and nothing else. So the
  prompt is the only available lever.
- Workflow scripts cannot `import`, so shared constants are re-stated per file. This is the same
  constraint `check-model-tiers.sh` exists to police for model tiers.
- Probe dispatches cost real tokens (`stall-probe.mjs` meta, lines 3-4: "a REAL agent-dispatch
  probe ... NOT an offline node selftest"). The measurement budget in R-6 of the issue is accepted.

## Decision Ledger

Rows D-1 to D-8 are hydrated verbatim from the pre-flight ledger at
`.claude/pipeline-state/169-ledger.md`. Rows D-9 onward record the Stage-1 intake resolutions;
where one refines an earlier row, the Resolution cell says so.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Lint posture for dispatchers the issue does not mandate nudges for (design-sync.mjs, figma.mjs, stall-probe.mjs, tool-discipline-probe.mjs) | Declared opt-out markers with a stated reason (unprobed surface / deliberate A-B knob), NOT blind nudges — the issue guardrail says a nudge shipped without a before-after probe rate is not acceptance | user-delegated |
| D-2 | Which intake-review.mjs agents get the bounding nudge | spec-reviewer gets a bounded variant; codebase-explorer gets a declared opt-out — exploration IS its deliverable, same class as the scope-completeness-reviewer exclusion in code-review.mjs lines 149-151 | user-delegated |
| D-3 | Reconciling the plan-review bounding nudge with Gate 1 requiring every referenced path/symbol to exist | Existence checks stay exhaustive but batched (one Glob/ls sweep is cheap, not per-file opens); content-level file OPENING is sampled and finding-driven, per the issue scope item 2 wording | user-delegated |
| D-4 | Fix for the deterministic-retry waste (scope item 4) given the runtime surfaces no turn-limit signal and Date.now is unavailable in Workflow scripts | Reduce StructuredOutput-class inline retries from 2 to 1 in plan-review.mjs / unit-tests.mjs, and the single retry prepends an escalated emit-early bounding preamble — the retry is never a verbatim repeat of the attempt that hit the budget wall | user-delegated |
| D-5 | Lint shape and location (AC-3) | Site-level check: every schema-carrying agent() dispatch in workflows/*.mjs must reference a bounding-nudge constant in its prompt chain or carry a structured opt-out comment (bounded-exploration-optout: reason). Bash grep-over-mjs-text technique per tools/diff-range-selftest.sh; ships as check + selftest pair in the dev-pipeline plugin (CI discovers *-selftest.sh by glob, no registration) | codebase-derived |
| D-6 | AC-4 verification mechanism | Direct Workflow dispatch of the repo copy of plan-review.mjs against the parked run-165 worktree (../second-shift-worktrees/second-shift-165, plan docs/plans/acme-165.md) recording the overall verdict — not a full pipeline resume; resuming run 165 itself happens post-merge after local-dev-refresh installs the fixed plugin | user-delegated |
| D-7 | Probe run economics (AC-1/AC-2) | plan-reviewer at production tier (opus): BEFORE k=4 unbounded plus the already-measured run-165 6/6 cited as primary baseline; AFTER k=8 bounded (AC-2 floor). unit-tests propose child at production tier (sonnet): k=4 BEFORE, k=4 AFTER. Rates recorded in the PR body | user-delegated |
| D-8 | Scope item 5 (close #82 as superseded) | Already satisfied — #82 is CLOSED as of intake; the PR cites it, no tracker write needed | codebase-derived |
| D-9 | Which unit-tests.mjs dispatch is the probe target (the issue said propose child, which names no real dispatch) | Refines D-7: probe review-toolkit:unit-test-plan-reviewer (kind plan-review, the Stage-4 child plan-review.mjs invokes at lines 273-287, plan-shaped input). review-toolkit:unit-test-mutation-reviewer gets nudge plus lint coverage; its probe is deferred with reason (Stage-5 git-range input, off the Stage-4 abort path) | codebase-derived |
| D-10 | Lint detection grammar, given per-file wording variation is mandated and code-review.mjs builds one agent() call from four prompt branches | Marker comment adjacent to each dispatch site, never the nudge literal text: bounded-exploration: CONSTANT_NAME, or bounded-exploration-optout: target — reason. The named constant must be defined in the same file | codebase-derived |
| D-11 | Lint dispatch-site detection regex | Match the schema: key anywhere (inline and multi-line opts objects), NOT line-anchored. A line-anchored regex finds only 10 of the 16 real sites — it misses all 6 inline agent(prompt, { ... schema: X }) forms: code-review.mjs:261, figma.mjs:155 and 185, stall-probe.mjs:108, tool-discipline-probe.mjs:138, design-sync.mjs:317 | codebase-derived |
| D-16 | Site unit for descriptor-driven dispatchers, where one shared agent() call serves entries with opposite dispositions | intake-review.mjs has ONE real call site (line 245, schema: d.schema) fed by DISPATCH[] descriptors at 188 and 201 whose dispositions conflict (spec-reviewer nudge vs codebase-explorer opt-out), and the descriptors sit outside a 40-line window from 245. Resolution: every schema: occurrence is a site, descriptors included, so each descriptor carries its own disposition adjacent to it; the shared call site takes a third marker verb, bounded-exploration-delegated, and the lint requires at least one non-delegated marker in the same file | codebase-derived |
| D-17 | Commit verb | feat(dev-pipeline) — this ships a new lint script and new probe targets, i.e. new capability. Repo CLAUDE.md mandates the honest verb and #164 used feat for statectl reclaim; fix would silently downgrade a minor release to a patch. Supersedes the fix(dev-pipeline) note in the pre-flight ledger rationale | codebase-derived |
| D-12 | Probe input for the plan-shaped targets, given docs/plans/acme-165.md lives only on an unmerged branch | docs/plans/160-prose-debloat-scoping.md — already on main, 263 lines, 51 distinct file references. Pin it as path plus the commit that introduced it (521b387) rather than a bare live path, so the probe keeps the reproducibility property stall-probe.mjs lines 8-15 exist to preserve: a bare path to an editable file on main loses it. acme-165.md stays available via an explicit arg for the AC-4 live regression | codebase-derived |
| D-13 | AC-2 vacuity — an AFTER rate of 0 is satisfiable by a probe that never reproduces the stall | AC-2 is conditional on reproduction: the BEFORE unbounded arm must reach at least 3/8 for the AFTER rate to count as acceptance. A non-reproducing BEFORE arm escalates rather than ships | codebase-derived |
| D-14 | Previously undeclared waiver the lint would hit on day one | code-review.mjs unit-test-mutation-reviewer branch (lines 239-249) already omits BOUNDED_EXPLORATION deliberately — it enumerates mutants across the whole diff. It becomes a declared opt-out, not a new nudge | codebase-derived |
| D-15 | Whether the mutation-gate.mjs executors need coverage | No — they are schema-free by construction (comment at lines 156-157: the death class cannot occur without a forced call). Zero schema-carrying sites confirmed by inventory; the lint naturally finds nothing there | codebase-derived |

## Affected files/modules

All paths are worktree-relative. Every file below was confirmed present unless tagged `[NEW]`.

**Dispatchers gaining a nudge**

- `plugins/dev-pipeline/skills/run/workflows/plan-review.mjs` — new plan-shaped nudge constant, applied in both `planReviewerGate` and `planGateAgent`; retries 2 to 1 plus escalated retry preamble
- `plugins/dev-pipeline/skills/run/workflows/unit-tests.mjs` — new nudge for both kinds; retries 2 to 1 plus escalated retry preamble
- `plugins/dev-pipeline/skills/run/workflows/intake-review.mjs` — prophylactic nudge on the spec-reviewer entry only

**Dispatchers gaining declared opt-out markers only (no behavior change)**

- `plugins/dev-pipeline/skills/run/workflows/code-review.mjs` — markers for its 2 sites, covering the generic-nudge, scope-completeness and unit-test-mutation branches
- `plugins/dev-pipeline/skills/run/workflows/design-sync.mjs` — 3 sites
- `plugins/dev-pipeline/skills/run/workflows/figma.mjs` — 2 sites
- `plugins/dev-pipeline/skills/run/workflows/stall-probe.mjs` — 1 site (also extended, below)
- `plugins/dev-pipeline/skills/run/workflows/tool-discipline-probe.mjs` — 1 site

**Probe**

- `plugins/dev-pipeline/skills/run/workflows/stall-probe.mjs` — target-keyed dispatch table adding `plan-reviewer` and `unit-test-plan-reviewer` arms

**Lint**

- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration.sh` `[NEW]`
- `plugins/dev-pipeline/skills/run/tools/check-bounded-exploration-selftest.sh` `[NEW]`

**Unchanged, referenced for grounding**

- `plugins/dev-pipeline/skills/run/tools/diff-range-selftest.sh` — the offline `.mjs`-text-reading precedent
- `plugins/review-toolkit/scripts/check-model-tiers.sh` — the restated-constant lint precedent
- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` — keeps its "Proportionate grounding" principle unchanged (guardrail)
- `.github/workflows/ci.yml` — unchanged; the selftest glob at lines 39-45 picks the new selftest up with no edit
- `docs/plans/160-prose-debloat-scoping.md` — probe input

## Reuse inventory

- `dispatchSchemaAgent` — already defined in `plan-review.mjs` (lines 54-66) and `unit-tests.mjs`
  (lines 107-119); the retry change edits these in place rather than introducing a new helper.
- `isNoStructuredOutputError` — reused as-is in both files; the death-class detector is unchanged.
- `BOUNDED_EXPLORATION` — the existing constant in `code-review.mjs` (lines 152-157) and its probe
  copy in `stall-probe.mjs` (lines 88-93) stay untouched; new dispatchers get their own
  differently-worded constants, per the issue guardrail against blind-copying.
- `withCeiling` — unchanged in both `code-review.mjs` and `plan-review.mjs`; this plan does not
  touch the ceiling (it never fired in run #165).
- Selftest harness idiom — `diff-range-selftest.sh` lines 19-35 (resolve `SCRIPT_DIR`, walk up to
  `skills/run`, grep the real `workflows/` dir) is copied as the structural pattern for the new
  selftest rather than inventing a harness.
- No new shared helper is introduced. Workflow scripts cannot import, so per-file restatement is
  the required style, not a candidate for extraction.

## Implementation steps

1. **Write the lint** — `check-bounded-exploration.sh` `[NEW]`. Enumerate `workflows/*.mjs`
   excluding `*-selftest.mjs`. For each file, find every dispatch site by matching the `schema:`
   key anywhere on a line (per D-11) — **descriptor objects count as sites**, not just `agent()`
   opts (D-16). For each site, scan the preceding 40 lines for one of three markers:
   - `// bounded-exploration: <IDENT>` — a nudge applies; assert `<IDENT>` is defined in the file.
   - `// bounded-exploration-optout: <target> -- <reason>` — declared waiver; reason non-empty.
   - `// bounded-exploration-delegated: <reason>` — the prompt is assembled from per-entry
     descriptors elsewhere in this file (the `intake-review.mjs:245` shape). The lint additionally
     requires the file to carry at least one non-delegated marker, so `delegated` cannot become a
     blanket waiver.

   Report `file:line` for every uncovered site; exit non-zero on any.

   Two implementation constraints, both repo-specific: the separator in the opt-out grammar is
   **ASCII `--`**, not an em-dash — a non-ASCII token in a grep pattern is the fragility class
   `ledger-lint.sh` already suffers from; and the script must run under **bash 3.2** (no
   `mapfile`, no associative arrays), the constraint `prose-budget.sh:133` calls out and that
   CI's `selftests-bash32` lane enforces.

   **Residual limitation, stated rather than papered over:** the site unit is a dispatch site, so
   once `code-review.mjs:261` carries a marker, a future *fifth* prompt branch added to its
   if/else chain without a nudge would pass the lint. The lint closes the whole-file and
   whole-dispatcher omission (the actual #169 defect); it does not police intra-chain branch
   growth. Recorded in Risks.
2. **Write the selftest** — `check-bounded-exploration-selftest.sh` `[NEW]`. Two halves, mirroring
   `diff-range-selftest.sh`: (a) fixture cases in a temp dir proving the lint fails an uncovered
   site, fails a marker naming an undefined constant, fails an empty-reason opt-out, and passes a
   correctly-marked file; (b) a real-tree assertion running the lint against the live `workflows/`
   dir so CI fails if a future dispatch lands unmarked. Assert the site inventory is non-zero so a
   regex that silently matches nothing cannot read as green.
3. **Add the plan-shaped nudge to `plan-review.mjs`** — a new constant bounding *how* grounding
   happens: batch existence checks for the plan's referenced paths rather than opening each file,
   and open a file only to support a finding being raised. Apply in both `planReviewerGate` (line
   ~177) and `planGateAgent` (line ~207) — they build prompts independently, so a single-site edit
   would leave consumer plan gates unfixed.

   **Gate-2 carve-out.** `planReviewerGate` serves Gate 1 *and* the design FE-spec gate, whose own
   prompt (`plan-review.mjs:249-262`) demands "a completeness inventory with NO silent drops (one
   row per rendered element)" — the same exhaustiveness class that justifies the
   scope-completeness-reviewer opt-out. The nudge text must therefore exempt inventory
   completeness explicitly (bound the *codebase* grounding, never the spec's element enumeration),
   or Gate 2 gets its own variant. Sampling a completeness inventory would defeat that gate.
4. **Cut the deterministic-retry waste** — in `plan-review.mjs` and `unit-tests.mjs` **only**,
   change `dispatchSchemaAgent`'s default `retries` from 2 to 1, and have the surviving retry
   prepend an escalated emit-early bounding preamble so it is never a verbatim repeat of the
   attempt that hit the wall. `dispatchSchemaAgent` also exists in `design-sync.mjs:137` and
   `figma.mjs:93`; AC-6 scopes to two files, so those copies are deliberately untouched — do not
   sweep them with a repo-wide edit.
5. **Add the nudge to `unit-tests.mjs`** — plan-review kind gets the plan-shaped wording;
   mutation-review kind gets propose-shaped wording (bound the enumeration sweep, not the
   proposing).
6. **Add the prophylactic nudge to `intake-review.mjs`** — nudge marker on the spec-reviewer
   descriptor (line ~188), opt-out marker on the codebase-explorer descriptor (line ~201), and a
   `bounded-exploration-delegated` marker on the shared call site (line ~245) per D-16. The nudge
   text itself is appended per-descriptor in the `prompt` field, not in `dispatchIntake`, so the
   two agents keep opposite treatment through one call site.
7. **Add opt-out markers** to `code-review.mjs`, `design-sync.mjs`, `figma.mjs`, `stall-probe.mjs`,
   `tool-discipline-probe.mjs` per the disposition table in the issue's *Resolved at intake*
   section. Run the lint; it must be green across all 16 sites.
8. **Extend `stall-probe.mjs`** to a target-keyed dispatch table: each target declares its
   `agentType`, schema, prompt builder, production nudge text and default model, so an arm
   dispatches identically to production. Add `plan-reviewer` (opus) and `unit-test-plan-reviewer`
   (sonnet), both declaring a **verbatim copy of `PLAN_REVIEW_SCHEMA`** and
   **`STRUCTURED_OUTPUT_MANDATE`** — not code-review's `FINDINGS_SCHEMA` /
   `STRUCTURED_OUTPUT_FIRST`, which is what the probe appends today (`stall-probe.mjs:105`). Production
   plan-reviewer dispatches append the MANDATE (`plan-review.mjs:176`, `:206`); an arm carrying
   FIRST instead would not be measuring the dispatch that died 6/6. The existing diff-shaped
   reviewer arm keeps its current behavior as the default target.
   - **Accepted, documented gap:** the per-target default models re-state `PLAN_REVIEWER_MODEL` and
     `UNIT_TEST_MODEL`, but `check-model-tiers.sh` validates six named tables and does not cover
     `stall-probe.mjs`. Extending that lint is out of scope here; the divergence is recorded in
     Risks so a future tier change is a known — not silent — desync.
9. **Run the measurement** — BEFORE (unbounded) then AFTER (bounded) arms for both targets; record
   the rates for the PR body. **BEFORE runs at k=8, not k=4** (superseding D-7), so AC-2's
   reproduction floor of ≥3/8 is a countable rule rather than an unattainable one over 4
   dispatches. Ship the nudges only if the AFTER rate is 0/8 *and* the BEFORE arm reached ≥3/8.
   Run #165's and this run's 6/6 are corroborating context, not a substitute for the probe's own
   BEFORE arm — the arm must stand on its own.
10. **Run the AC-4 regression** — dispatch this branch's `plan-review.mjs` by absolute `scriptPath`
    against the parked run-165 worktree with `planPath` `docs/plans/acme-165.md`; record the overall
    verdict.

## Test strategy

Verify-after (infrastructure change, no product behavior). The lint is the one genuinely new
executable artifact and it is test-first: step 2's selftest fixtures are written to fail against
the step-1 lint before the markers of step 7 exist, then go green as the markers land.

The nudge edits are prompt-string changes with no unit-testable surface — their evidence is the
probe rate, not an assertion. That is the deliberate design of this issue: the measurement is the
test.

**Unit test surface:** skip. The repo config sets `commands.second-shift.unitTestScope` to `null`,
so there is no mutation surface and no co-located spec convention to satisfy.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Probe covers plan-reviewer and unit-test-plan-reviewer with production schema/prompt/nudge; BEFORE and AFTER rates in the PR body | 8, 9 | — no test (covered-by-selftest) |
| AC-2 | AFTER rate 0 over at least 8 dispatches, conditional on BEFORE reaching at least 3/8 | 9 | — no test (non-functional) |
| AC-3 | Lint fails an unmarked schema-carrying dispatch; ships with a selftest asserting fixtures and the live workflows dir | 1, 2, 7 | `check-bounded-exploration-selftest.sh` (AC-3) |
| AC-4 | acme-165.md passes Stage 4 under this branch plan-review.mjs against the parked run-165 worktree | 3, 4, 10 | — no test (infra-only) |
| AC-5 | Selftests, shellcheck and jq green; Changelog trailer present | 1-8 | repo verification suite (below) |
| AC-6 | Retries 2 to 1 in plan-review.mjs and unit-tests.mjs; surviving retry prepends an escalated preamble rather than repeating verbatim | 4 | `check-bounded-exploration-selftest.sh` drift guard asserting the retry default and the preamble token (AC-6) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash plugins/dev-pipeline/skills/run/tools/check-bounded-exploration.sh
```

## Risks / rollback notes

- **The nudge degrades plan-review quality.** A plan reviewer told to sample file references could
  miss a real grounding defect. Mitigated by wording that bounds *how* rather than *whether*
  grounding happens (D-3), and detectable in the probe's existing `avgFindings` comparison between
  the bounded and unbounded arms. Rollback is deleting one constant reference per site.
- **The BEFORE arm does not reproduce the stall.** Then AC-2 is unearned and the fix is unvalidated
  (D-13). This escalates rather than ships — the exact discipline #82 skipped.
- **The lint's regex over-matches or under-matches.** Under-matching is the dangerous direction and
  is the reason D-11 exists; the selftest asserts a non-zero site count against the live tree so a
  regex that matches nothing cannot pass as green.
- **The lint does not police intra-chain branch growth.** Its unit is a dispatch site, so a fifth
  prompt branch added to `code-review.mjs`'s if/else chain without a nudge would pass once site 261
  is marked. The claim this change earns is "a dispatcher or file cannot ship unmarked", not
  literal total coverage — stated here rather than overclaimed in the plan body.
- **`stall-probe.mjs`'s per-target model defaults sit outside `check-model-tiers.sh`.** A future
  change to `PLAN_REVIEWER_MODEL` or `UNIT_TEST_MODEL` would desync the measuring instrument from
  production without a lint failure. Accepted for this PR and recorded here; extending the tier
  lint's file list is the follow-up.
- **This run is self-referential.** Stage 4 of this very run executes the *installed*, unfixed
  `plan-review.mjs`, so it can stall on the defect being fixed. That is a delay, not a dead end: the
  run parks resumable and the stall is itself a BEFORE datapoint.

## Out-of-scope

- Any edit to `reviewer-baseline` prose as a delivery mechanism (explicit issue guardrail — the
  probe already showed baseline placement does not cure the stall).
- Re-litigating `STRUCTURED_OUTPUT_FIRST` or model tier — both are measured non-fixes for this class.
- Changing `withCeiling` or `CEILING_MS`. Run #165's dispatches ran 603 s and 509 s against a
  900 s ceiling, so the ceiling never fired and is not implicated.
- A probe arm for `unit-test-mutation-reviewer` (deferred with reason, D-9) and for the
  `design-sync.mjs` / `figma.mjs` produce dispatches (declared opt-outs, D-1).
- Resuming `/dev-pipeline:run 165` end to end — that is post-merge, after the fixed plugin is
  installed.
- Any version bump or `CHANGELOG.md` edit — release artifacts are derived at release time
  (repo CLAUDE.md, enforced by `scripts/check-frozen-files.sh`).

Unverified references: none.
