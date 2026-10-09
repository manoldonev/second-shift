# Intake receipt — #950

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which proposals are in scope | Retired: superseded by D-35 (P8 and companions cut after the expert panel) | user-answered | intent |
| D-2 | P10 regression eval | Dropped: no seeded-defect fixture, no eval harness, no replay. The §5 eval-fixture and negative-control criteria go with it; the prompt changes are judged in review and by later consumer reviews | user-answered | intent |
| D-3 | Decomposition | No split: one PR for P1–P9 across review-toolkit and dev-pipeline | user-answered | intent |
| D-4 | Severity of a verified-broken newly load-bearing defect (schema opened, field not persisted) on the feature's critical path | Critical; an unverified provenance row stays Warning ≥ 80 per P2 | user-delegated | intent |
| D-5 | P6 gate when it is unclear whether an AC is observable only across a service or persistence boundary | Retired: superseded by D-38 (no Verification line) | user-answered | intent |
| D-6 | Where P9 lands | The BUILD prompt in `plugins/dev-pipeline/skills/run/run.sh` (PR-body instruction near line 520), with a `run-selftest.sh` case that fails without it (CLAUDE.md: a behavior change to run.sh lands with a run-selftest case) | codebase-derived | fact |
| D-7 | Test home for `companions[]` in code-review.mjs | Retired: superseded by D-35 (code-review.mjs no longer changes) | codebase-derived | fact |
| D-8 | The "what to put here" note for consumer round-trip traps (P1) | `docs/extension-points.md` and `plugins/review-toolkit/scripts/section-catalog.txt` change in lockstep; `check-review-context-sections-selftest.sh` enforces it | codebase-derived | fact |
| D-9 | P3 reviewer-baseline mirror | `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` | codebase-derived | fact |
| D-10 | PR form | `feat(...)` title verb and a `Changelog:` trailer; no version or CHANGELOG edits (CLAUDE.md) | codebase-derived | fact |
| D-14 | `[Newly load-bearing]` label vs severity | Retired: superseded by D-37 (rule only, no label) | user-answered | intent |
| D-15 | Where the P2 provenance table sits in the report | A new `## Data provenance` report section, always emitted, using the "none: the diff consumes no newly read persisted field" line when empty | user-delegated | intent |
| D-16 | Does the P1 consumed-field arm fire in dev-pipeline review rounds | Standalone review-lead only; under the pipeline default panel db-reviewer keeps its surface triggers (SKILL.md:219 unchanged in effect, amended to say so). P2's lead-pass provenance table still applies in the lane | user-answered | intent |
| D-17 | Multi-repo dispatch shape | Retired: superseded by D-35 (companions cut) | user-answered | intent |
| D-18 | P6 gate in the lane and without a ticket | Retired: superseded by D-26 (the lead never runs probes). With no ticket there are no ACs to judge and the gate does not apply | user-answered | intent |
| D-19 | P9 optional automatic probe in the review session | Out of scope: P9 is a build-prompt obligation only | user-delegated | intent |
| D-20 | P9 enforcement | A prompt instruction in the run.sh BUILD prompt, not a model-free check: nothing model-free can decide that a field crosses a service boundary | codebase-derived | fact |
| D-21 | Consumer round-trip-trap note: new H2 or prose | Prose under the existing `Database stack` section of `docs/extension-points.md` (catalog row: `Database stack \| db-reviewer`); a new H2 is breaking-class per `section-catalog.txt` | codebase-derived | fact |
| D-22 | Output modes for `survived-by-fixture` | Retired: superseded by D-40 (no new class) | codebase-derived | fact |
| D-23 | Does a parser read the lines under Ready to merge? | Retired: superseded by D-38 (no Verification line) | codebase-derived | fact |
| D-24 | P9 run-selftest case shape | Grep the round-1 build prompt (`prompt-1.txt`) for the obligation sentence, as the probe-deletion case does (`run-selftest.sh:251`); red on main because the sentence is absent | codebase-derived | fact |
| D-25 | What counts as a persisted field for P1, P2 and P5 | A field of an entity whose schema, model, DDL or mapping lives in the repo under review or a declared companion. Third-party APIs and in-memory JSON are out. Measured on the last 60 non-release commits: fires 0/60 here, versus 4-7/60 (GitHub node_id, closingIssuesReferences, herdr ids) under the wider reading, where P5 would raise unfixable warnings on fake-gh tests | user-answered | intent |
| D-26 | Who runs P6 probes; what `executed` means | Retired: superseded by D-38 (reviewer still never runs probes; no Verification enum) | user-answered | intent |
| D-27 | Multi-repo contract details | Retired: superseded by D-35 (companions cut) | user-answered | intent |
| D-28 | Reader for the P9 build obligation | Prompt sentence only, no run.sh PR-body gate. The reader is the lane review: review-lead's lead pass applies P2's provenance table and P5's finding there, so a build that skips the round-trip test gets a finding | user-delegated | intent |
| D-29 | Scope of P6 reserved wording | The report's verdict, Verification and Reasoning lines only; grounding prose that uses verify in the checking sense is untouched | user-delegated | intent |
| D-30 | Where the `[Newly load-bearing]` severity mapping lands | Retired: superseded by D-37 (no label, no table rows) | codebase-derived | fact |
| D-31 | How reviewer-baseline mirrors P3 rule 4 | Retired: superseded by D-37 (no label to mirror; rule 4 mirrored as prose) | user-delegated | intent |
| D-32 | Selftests for `survived-by-fixture` and the Verification line | None: nothing in scripts or workflows parses either (the classification lives in the agent's output template; no script reads the report text), and prose-presence guards are disallowed | codebase-derived | fact |
| D-33 | `survived-by-fixture` despite zero historical hits | Retired: superseded by D-40 | user-delegated | intent |
| D-34 | Lane parsing of the new report surfaces | None needed: run.sh binds the verdict from the review comment's first line only; the provenance section and Verification line have no lane reader, and the review prompt already declares the default panel under which db-reviewer keeps surface triggers (consistent with D-16) | codebase-derived | fact |
| D-35 | Scope after the expert panel | P1, P2, P3, P4.1, P5, P6 and P9 as narrowed below. P8 and P4.2/4.3 (companions) cut: all ten experts said cut and no refuter saved it; the defect lived in one repo, and contract tests would not have caught it. Re-admit only on a consumer miss that only cross-repo review would catch | user-answered | intent |
| D-36 | Measures the ticket lacked | (1) A lead-pass Warning: a new cross-service lookup whose miss path only warns (no error, no alertable metric), or an id built with String() from a possibly-undefined value. (2) The extension-points Database stack note recommends consumer guards: the store rejecting undeclared fields (Mongoose strict throw or the stack's equivalent), fixtures built through the model, a round-trip spec per schema, and lint for traps catchable by syntax | user-answered | intent |
| D-37 | P3 form | Rule 4 only: a defect in unchanged code that the diff is the first to depend on is new and goes through the existing two-condition Critical trigger at its own severity. No new label and no table rows; reviewer-baseline mirrors rule 4 as prose | user-answered | intent |
| D-38 | Standing report surfaces | Keep an always-emitted `## Data provenance` section, one line when empty, as the forcing function for G2; an unverified critical-path stored field is a Warning >= 80. No `Verification:` line and no gate. Reserved wording in the verdict and Reasoning lines: end-to-end, verified and works only for what a cited test executed, otherwise statically traced; the lead may name one read-only probe for the human and never runs it | user-answered | intent |
| D-39 | P1 shape | A self-standing standalone arm (not coupled to the lead pass). db-reviewer steps, one line each: cite the persisting schema line; round-trip intent applying the consumer's trap list and asking whether the store rejects or silently drops undeclared fields; writers that bypass the schema count; state the backfill or resync cost (the existing backfill rule at db-reviewer.md:89 fires only on a shape change). No git log -S search for earlier readers | user-answered | intent |
| D-40 | P5.3 form | One sentence in the mutation reviewer's severity section: a survivor caused by fixture shape differing from persisted shape is a warning, not a note, and says so. No new classification value; the propose-mode schema and its executor are untouched | user-answered | intent |
| D-41 | P7 | Cut: restates P2's Warning >= 80 and P5's finding as a third copy; the panel split 5-5 and refuters called it low stakes either way | user-delegated | intent |
| D-42 | P9 form | One BUILD-prompt sentence: a newly read stored field or one sent across a service boundary gets a test through the real schema or model, not a hand-built fixture. No PR-body provenance row; the lane review's lead pass reads the diff | user-delegated | intent |
| D-43 | P5.1 form | Fold fixture shape vs persisted shape into the existing Silent-failure schema coupling Warning instead of a new named rule; keep the narrowed integration/e2e exemption and the cite-the-artifact dismissal rule | user-delegated | intent |
| D-11 | companions[] per-repo behavior (missing companion worktree, per-repo base/head/changedFiles, result tagging) | Retired: superseded by D-35 (companions cut) | user-answered | intent |
| D-12 | Advisory-mode mapping of the new `survived-by-fixture` class | Retired: superseded by D-40 (no new class) | user-answered | intent |
| D-13 | db-reviewer turn budget (maxTurns 15) for the new consumed-field step | parked under OR-3 | deferred | open |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-3 | db-reviewer budget for the consumed-field persistence check | reversible-default-and-flag |

- OR-3 default: keep `maxTurns: 15`; when the persisting schema cannot be located, the reviewer reports "unable to verify — pointer needed" per reviewer-baseline rather than exploring further. Cheap to reverse: one frontmatter value.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | review-lead report: `## Data provenance` section, one line when empty | decided (D-38) |
| S-2 | review-lead report: `Verification:` line under Ready to merge? | out-of-scope — dropped by D-38; reserved wording covers it |
| S-3 | review-lead report: `[Newly load-bearing]` label | out-of-scope — no label under D-37 |
| S-4 | scope-completeness-reviewer output: Cross-repo contract section | out-of-scope — companions cut by D-35 |
| S-5 | unit-test-mutation-reviewer: fixture-shape survivor severity | decided (D-40) |
| S-6 | Consumer extension-file note: round-trip traps and guards | decided (D-36) |
| S-7 | Pipeline PR body: provenance row | out-of-scope — dropped by D-42 |
| S-8 | Eval report for the seeded-defect fixture | out-of-scope — P10 dropped |
| S-9 | review-lead report: Verdicts table Repo column | out-of-scope — companions cut by D-35 |
| S-10 | Standalone review-lead companions input | out-of-scope — cut by D-35 |
| S-11 | Lead-pass Warning: silent miss path on a new cross-service lookup | decided (D-36) |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh`
- `bash plugins/review-toolkit/scripts/check-reviewer-references-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: noise-calibration opus 5/6 · downstream-readers fable 4/6 · multi-repo-dispatch opus 5/6 · verifiability fable 4/6 · premortem fable 1/6
Tally: rows added 8 · snapshot claims overturned 0 · questions added 2
Checkouts: the consumer repos from the incident not available

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | noise-calibration | P1's arm fires on 0/60 recent commits if persisted means storage the repo owns, 4-7/60 if third-party stored entities count (`scratchpad/fanout-probes/newreads.sh`) | new | became D-25 |
| F-2 | noise-calibration | The existing db-reviewer path glob already matches 13/60 commits via the config JSON schema, and lane verdicts override it as no DB layer (`SKILL.md:192`) | new | became D-25 |
| F-3 | noise-calibration | P5 would fire with no possible remedy on fake-gh tests of GitHub-owned data (#949 `minimize-verdicts.sh:43`, #947) | new | became D-25 |
| F-4 | noise-calibration | `[Newly load-bearing]` matches one past finding in 190 lane verdicts (`second-shift-440-lean-verdict.md:57`) | new | not material — calibrates the noise budget, decides nothing |
| F-5 | noise-calibration | `survived-by-fixture` matches 0 of 17 verdicts with surviving mutants; observed survivors are environment-shaped | new | became D-33 |
| F-6 | downstream-readers | The label needs rows in both reviewer-baseline tables and review-lead's normalization table (`SKILL.md:397-401`) or it has no reader | new | became D-30 |
| F-7 | downstream-readers | run.sh reads only the verdict line; no lane reader for the new report surfaces (`run.sh:690`) | new | became D-34 |
| F-8 | downstream-readers | `companions` is silently dropped today, and a repo tag inside findings would hit the three-file FINDINGS_SCHEMA lockstep (`code-review.mjs:159`) | new | became D-27 |
| F-9 | downstream-readers | A new H2 for the traps is flagged off-catalog by the preflight; an H3 under Database stack passes | already-had | D-21 |
| F-10 | multi-repo-dispatch | `companions` is silently dropped; no prompt names the second worktree (`code-review.mjs:159,191`) | already-had | D-27 (same as F-8) |
| F-11 | multi-repo-dispatch | Results and dark markers are keyed by agentType alone, so per-repo dispatch needs a repo tag on every return path (`code-review.mjs:458-463`) | new | became D-27 |
| F-12 | multi-repo-dispatch | Each companion needs its own range and file list; selftest B1 pins the single-repo return shape (`runtime-shim-selftest.mjs:153`) | new | became D-27 |
| F-13 | multi-repo-dispatch | A two-repo shim case can assert routing through recorded prompts and returned repo tags (`runtime-shim-lib.mjs:100-110`) | new | not material — test mechanics under D-7 |
| F-14 | multi-repo-dispatch | Context resolves from one root; a companion's review-context loads only if its prompt names its root (`code-review.mjs:506`) | new | became D-27 |
| F-15 | verifiability | AC-8 is guardable by grepping the round-1 build prompt (`run-selftest.sh:251`) | already-had | D-24 |
| F-16 | verifiability | A runtime-shim case with a companion is red today (no prompt names the companion, no repo tag) | already-had | D-7 |
| F-17 | verifiability | The reviewer-baseline mirror is either a verbatim LOCKSTEP block or prose in its own voice (`scripts/check-lockstep-pairs.sh:40`) | new | became D-31 |
| F-18 | verifiability | Nothing parses `survived-by-fixture` or the Verification line, so neither is observable by a selftest | new | became D-32 |
| F-19 | premortem | The P9 obligation has no mechanical reader; a build skipping it goes green unless something reads it | new | became D-28 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Which proposals are in scope | P1–P9 as written in the issue body §3, including every report, agent-output and PR-body surface they define |
    | D-2 | P10 regression eval | Dropped: no seeded-defect fixture, no eval harness, no replay. The §5 eval-fixture and negative-control criteria go with it; the prompt changes are judged in review and by later consumer reviews |
    | D-3 | Decomposition | No split: one PR for P1–P9 across review-toolkit and dev-pipeline |
    | D-4 | Severity of a verified-broken newly load-bearing defect (schema opened, field not persisted) on the feature's critical path | Critical; an unverified provenance row stays Warning ≥ 80 per P2 |
    | D-5 | P6 gate when it is unclear whether an AC is observable only across a service or persistence boundary | Report `Verification: static` and name the cheapest probe; the verdict is not capped. The reserved wording ("end-to-end", "verified", "works") still applies |
    | D-6 | Where P9 lands | The BUILD prompt in `plugins/dev-pipeline/skills/run/run.sh` (PR-body instruction near line 520), with a `run-selftest.sh` case that fails without it (CLAUDE.md: a behavior change to run.sh lands with a run-selftest case) |
    | D-7 | Test home for `companions[]` in code-review.mjs | A case in `plugins/review-toolkit/workflows/runtime-shim-selftest.mjs`, run by `workflows-mjs-selftest.sh` |
    | D-8 | The "what to put here" note for consumer round-trip traps (P1) | `docs/extension-points.md` and `plugins/review-toolkit/scripts/section-catalog.txt` change in lockstep; `check-review-context-sections-selftest.sh` enforces it |
    | D-9 | P3 reviewer-baseline mirror | `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` |
    | D-10 | PR form | `feat(...)` title verb and a `Changelog:` trailer; no version or CHANGELOG edits (CLAUDE.md) |
    | D-14 | `[Newly load-bearing]` label vs severity | A tag that does not set severity on its own: severity follows D-4; the reviewer-baseline label→schema table gains a row mapping it to the finding's own severity, never `nit` |
    | D-15 | Where the P2 provenance table sits in the report | A new `## Data provenance` report section, always emitted, using the "none: the diff consumes no newly read persisted field" line when empty |
    | D-16 | Does the P1 consumed-field arm fire in dev-pipeline review rounds | Standalone review-lead only; under the pipeline default panel db-reviewer keeps its surface triggers (SKILL.md:219 unchanged in effect, amended to say so). P2's lead-pass provenance table still applies in the lane |
    | D-17 | Multi-repo dispatch shape | `worktree/base/head` stay the primary repo; `companions[]` are extras. Selected domain reviewers run once per repo with a `repo` tag on every result; scope-completeness-reviewer runs once over the union of diffs. Standalone review-lead takes companions as an explicit input (path + branch per paired repo); the lane always passes none |
    | D-18 | P6 gate in the lane and without a ticket | Probe (1) schema/model round-trip in a throwaway script and probe (3) the repo's integration tier count as `executed`, so a lane review can reach Yes; with no ticket there are no ACs to judge and the gate does not apply |
    | D-19 | P9 optional automatic probe in the review session | Out of scope: P9 is a build-prompt obligation only |
    | D-20 | P9 enforcement | A prompt instruction in the run.sh BUILD prompt, not a model-free check: nothing model-free can decide that a field crosses a service boundary |
    | D-21 | Consumer round-trip-trap note: new H2 or prose | Prose under the existing `Database stack` section of `docs/extension-points.md` (catalog row: `Database stack \|
    | D-22 | Output modes for `survived-by-fixture` | Advisory output only; the propose-mode schema stays `survived \|
    | D-23 | Does a parser read the lines under Ready to merge? | No lane parser does; only the review-lead synthesis eval's `rubric.py` reads the verdict line, so a separate `Verification:` line breaks nothing |
    | D-11 | companions[] per-repo behavior (missing companion worktree, per-repo base/head/changedFiles, result tagging) | parked under OR-1 |
    | D-12 | Advisory-mode mapping of the new `survived-by-fixture` class | parked under OR-2 |
    | D-13 | db-reviewer turn budget (maxTurns 15) for the new consumed-field step | parked under OR-3 |
    | D-24 | P9 run-selftest case shape | grep the round-1 build prompt for the obligation sentence, as the existing probe-deletion case does (run-selftest.sh:251) |
