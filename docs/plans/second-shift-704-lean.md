# #704 — design-toolkit gets evals: three fixture sets, three recorded baselines, one prompt fix

**Issue:** https://github.com/manoldonev/second-shift/issues/704 (parent #692; siblings #705, #707)

## Goal

`design-toolkit` is the only plugin with no `evals/` directory. Its three static Figma reviewers
— `figma-faithful-reviewer`, `figma-faithful-plan-reviewer`, `figma-faithful-spec-reviewer` —
have never been scored against a labeled fixture, and #692 showed each of them clearing a defect
that is statically visible in its own input.

This PR builds the **measuring instrument** and takes the **first reading**. It does not tune the
agents: that is #707.

## Scope, as re-cut at pre-flight

The pre-flight ledger (`.claude/pipeline-state/704-ledger.md`, 13 rows / 2 open regions / 11
surfaces) re-cut the ticket's acceptance criteria and is binding here (D-1). **AC-3 — the
autoresearch keep-or-revert campaign — is out of this PR**, filed as #707. Two reasons, both
recorded at pre-flight:

- The eval kit is operator-run and model-billed on a Claude subscription and never runs in CI
  (CI here is model-free by design), so no autonomous lane can spend the quota.
- The ticket's own AC-2 forbids a prompt edit before the baseline while its AC-4 *is* a prompt
  edit. Satisfying AC-3 in-PR would need two full attended measurement rounds inside one PR.

This is the ordering-inconsistency signal: an AC that forbids what another mandates. The build
order that falls out (D-11) is **fixtures + rubrics + runners → measure and record the baseline →
then the AC-4 prompt edit**. The recorded baseline is therefore the pre-AC-4 number by
construction, which is exactly what #707 needs as its comparator.

## What is being built

### Three eval directories

`plugins/design-toolkit/evals/<agent>-eval/` for each of the three agents, each carrying
`README.md`, `run.sh`, `rubric.py`, `fixtures/`, `changelog.md`, `CLOSEOUT-BASELINE.md`, and a
local `.gitignore` for `results-*.json`.

**Fixtures live inside the eval dir** (D-7). This is a deliberate departure from the majority
pattern: all four checked-in `agent-eval-kit` evals point `--fixtures-dir` at a path that does not
exist in this repo — `docs/eval-fixtures/{intake-orchestrator,review-lead,security-reviewer}` and
`docs/plans/test-fixtures`. Those fixtures lived in the originating consumer repo's
`.claude/pipeline-state/` and were never committed, so every one of them is **unrunnable as
committed**. AC-1 says "runnable"; the shape to copy is
`plugins/intake-toolkit/evals/implementability-probe-eval/fixtures/`, which keeps them in-dir.

### The synthetic design-system reference

`figma-faithful-reviewer` reads `.claude/second-shift/design-tokens/*.md`. This repo has no FE app
and no such reference, so one is committed under
`plugins/design-toolkit/evals/figma-faithful-reviewer-eval/fixtures/design-tokens/` and passed via
`--reviewer-user-prompt-template` (D-3). It carries the two surfaces the agent's rule set is
written against:

| File | Surface | What it fixes |
| --- | --- | --- |
| `acme-ui-catalog.md` | — | Figma-node → component lookup, with source paths |
| `acme-ui-design-tokens-console.md` | fixed-theme | 4px spacing base, fixed palette, type ramp |
| `acme-ui-design-tokens-storefront.md` | branded / host-relative | no value table; abstraction-only rules; RTL |

Its **structure** is modelled on two real consumer references; **nothing is copied verbatim** —
not a token value, not a palette entry, not a component name, not a path, not a sentence. The
fictional org is `Acme`, this repo's fixture anonymization convention (D-9), and second-shift is a
public repo.

### Rubric shape

The ticket grades in binary ("must Block", "must not Block") and the kit scores a weighted rubric,
so each `rubric.py` carries a **verdict dimension holding the bulk of the points** plus quality
dimensions (D-4):

| Dimension | Points | What it measures |
| --- | ---: | --- |
| `d1_verdict_correctness` | 6 | must-Block / must-not-Block, matched against the fixture's `expected_verdict` |
| `d2_finding_grounding` | 2 | the planted defect is named, and every finding anchors to a row/line/symbol that exists in the fixture |
| `d3_no_fabrication` | 2 | no finding cites a value, row, component or file the fixture does not contain |

Total 10, aligning with the three prior campaigns. #707's "≥ 3/3 runs" then reads straight off
`per_fixture` while `overall_pct` still feeds the +10pp/3-run rule.

### Fixture inventory

**`figma-faithful-plan-reviewer-eval`** — the lean-lane translation-plan artifact shape
(`planned_from:` header, `why this component` table, `dimensions` table):

| Fixture | Planted defect | Expected |
| --- | --- | --- |
| `01-missing-dimension-rows` | control-bearing screen, `dimensions` table with no rows | `block` |
| `02-name-match-resolution` | `why this component` cell restates the layer name; resolved component renders steppers the plan never describes | `block` |
| `03-spacing-arithmetic` | `16px → gap={2}` on a 4px base; branded row uses a raw `px` | `block` |
| `04-control-clean` | complete plan, correct arithmetic, justified resolutions | `pass` |

**`figma-faithful-spec-reviewer-eval`**:

| Fixture | Planted defect | Expected |
| --- | --- | --- |
| `01-lean-spec-no-visual-contract` | lean-lane spec: token table + embedded translation plan, no Copy Index, **no visual contract** | `block` — and **not** `N/A` |
| `02-placeholder-copy` | full figma spec with bare `{Label}` placeholders left in the Copy Index | `block` |
| `03-unresolvable-node-ref` | screen referenced by a "DEV-READY" section link, not `fileKey` + `nodeId` | `block` |
| `04-control-clean` | complete figma-faithful spec | `pass` |

Fixture 01 is the AC-4 oracle: it is the shape today's agent returns `N/A` on.

**`figma-faithful-reviewer-eval`** — fixture contents ARE the diff, per the
`security-reviewer-eval/run.sh` precedent (D-8), against the synthetic reference (D-5):

| Fixture | Planted defect | Expected |
| --- | --- | --- |
| `01-branded-raw-literals` | hardcoded hex + raw `px` sizing on the **branded** surface | `revise` |
| `02-hand-rolled-primitive` | raw `<button>`/`<input>` where the catalog exports `Button`/`TextField` | `revise` |
| `03-physical-style-props` | `paddingLeft` / `marginTop` / `bgcolor` on the RTL-capable branded surface | `revise` |
| `04-control-clean` | correct tokens, palette paths, sizing helper, logical props | `approve` |

### The AC-4 prompt change

`figma-faithful-spec-reviewer`'s `N/A` condition is re-derived from "the input has no Copy Index /
Components / Screens sections" to **"the input is not a design artifact at all"**. A lean-lane spec
carrying a translation plan is in scope; the agent reviews what the input carries and names the
checks that had no input, rather than declining the whole review.

The same commit rewrites the three paragraphs in
`plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` that lean on the old behaviour
(D-2), because they become false the moment the `N/A` narrows:

1. the deferral that says the spec reviewer "returns `N/A` on any input with no Copy Index …
   which is every lean-lane spec";
2. the "its _suitability_ half is yours in both lanes, so nothing is dropped when that reviewer
   cannot run" clause;
3. the claim that copy _capture_ has "**no owner on the lean lane**".

**Component suitability stays dual-owned** — both agents may flag it. Overlap is cheaper than a
dropped check, and it is the plan reviewer's own stated rule that "every owner named below can
actually run on the lane you are dispatched from".

D-13 bounds the blast radius to those two files: grepping every `*.md`/`*.sh`/`*.mjs`/`*.json`
outside `docs/plans/`, the `N/A` behaviour is restated only in `figma-faithful-spec-reviewer.md`
(lines 21, 23, 153) and the deferral block of `figma-faithful-plan-reviewer.md`.
`figma-faithful-spec/SKILL.md` references the agent but not its `N/A` condition;
`figma-faithful/SKILL.md` and `figma-iterate/SKILL.md` do not restate it.

## What is deliberately NOT built

- **No CI lane** (D-12). CI here is model-free by design and the kit spawns `claude -p`
  subprocesses on the operator's subscription. The precedent is stated outright in
  `plugins/intake-toolkit/evals/implementability-probe-eval/README.md`: "Operator-run and
  model-billed. Never in CI".
- **No selftest for the three `run.sh` wrappers** (D-10). `CLAUDE.md`'s coverage register lists
  "the eval runners" as a standing exception with no independent contract. `shellcheck` and
  `jq empty` still cover the new files, and `scripts/check-eval-model-identity.sh` now scans them.
- **No `review-lean` step 5b change.** #704's own Scope section declares it out; it is #705's.
- **No repair of the four pre-existing evals** whose `--fixtures-dir` is dangling. Real defect,
  found while exploring (D-7), not this ticket — recorded here so it is not lost.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does AC-3's autoresearch campaign land in this PR? | **No.** This PR lands AC-1, AC-2, AC-4, AC-5 only. AC-3's keep-or-revert campaign is re-cut into its own follow-up ticket (D-6). Rationale: the eval kit is operator-run and model-billed and never runs in CI (D-12), so no autonomous lane can spend the quota; and because AC-2 forbids a prompt edit before the baseline while AC-4 *is* a prompt edit, satisfying AC-3 in-PR would need two full attended measurement rounds. | user-answered |
| D-2 | How far does AC-4's `N/A` re-derivation reach? | Narrow the `N/A` condition to "the input is not a design artifact at all"; a lean-lane spec carrying a translation plan is IN scope. **Same commit** rewrites the three paragraphs in `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` that lean on the old behaviour (the "returns `N/A` on any input with no Copy Index … which is every lean-lane spec" deferral, the "its suitability half is yours in both lanes, so nothing is dropped" clause, and the "copy capture has **no owner on the lean lane**" claim). Component **suitability stays dual-owned** — both agents may flag it; overlap is cheaper than a dropped check, per the plan-reviewer's own rule that "every owner named below can actually run on the lane you are dispatched from". | user-answered |
| D-3 | Where does `figma-faithful-reviewer`'s `.claude/second-shift/design-tokens/*.md` reference come from, given this repo has none and no FE app? | DEPARTURE — redaction only; the decision is unchanged. The pre-flight receipt is gitignored (`.claude/pipeline-state/`) and this plan is public, so the receipt's Resolution cannot be carried verbatim: it cites the operator's local checkout paths and spells out the real org/package identifiers it exists to forbid. Decision as taken: commit a **synthetic** reference under the eval dir (`fixtures/design-tokens/`), path passed via `--reviewer-user-prompt-template`. Model its **structure** on two real consumer references — a catalog file plus a fixed-theme surface file (base facts / spacing scale / colour palette / typography ramp / "when this doc does NOT apply") and a branded host-relative surface file (what is branded / rules / distribution flavors / limits). **Copy nothing verbatim** — not a token value, not a palette entry, not a component name, not a path, not a sentence. No real org or package identifier appears anywhere in the fixture tree; use the repo's `Acme` convention (D-9). second-shift is a public repo. | user-answered |
| D-4 | What shape do the three `rubric.py` files take, given AC-3 grades in binary but the kit scores a weighted rubric? | A **verdict dimension carrying the bulk of the points** (`d1_verdict_correctness` — must-Block / must-not-Block, matched against the fixture's `.expected.json`), plus quality dimensions (`d2_finding_grounding`, `d3_no_fabrication`). AC-3's "≥ 3/3" then reads straight off `per_fixture` while `overall_pct` still feeds the +10pp/3-run rule. Grounded in the kit's results schema, which already writes `per_fixture.<name>.expected_verdict`. | user-answered |
| D-5 | The ticket names zero defect fixtures for `figma-faithful-reviewer`. What fills its eval dir? | Three defects derived from that agent's own checklist against the two-surface reference of D-3, plus the control: **(a)** a raw `px`/hex on the **branded** surface where the abstraction exists (the rule that defeats branding); **(b)** a hand-rolled interactive primitive where the synthetic catalog exports a real one — the agent must verify the export by grep before flagging; **(c)** a physical style prop on the RTL-capable branded surface. Exercises the fixed-theme vs branded split the reference exists to encode. | user-answered |
| D-6 | When is the re-cut AC-3 campaign ticket filed? | **At intake exit, before handoff** — cross-linked to #704 and #705. Matches how #704 itself was filed ("sibling: the lane-mandatory ticket filed alongside this one"). A re-cut recorded only in a pipeline-state file is a silent scope drop the moment this ledger is superseded. | user-answered |
| D-7 | Where do the fixtures live on disk? | **Inside** each eval dir: `plugins/design-toolkit/evals/<agent>-eval/fixtures/`, committed. Every existing kit eval points `--fixtures-dir` at a path that does not exist in this repo (`docs/eval-fixtures/{intake-orchestrator,review-lead,security-reviewer}`, `docs/plans/test-fixtures`) — all four checked-in kit evals are unrunnable as committed. AC-1 says "runnable", so do not repeat that pattern; follow `plugins/intake-toolkit/evals/implementability-probe-eval/fixtures/`. | codebase-derived |
| D-8 | How is a diff-reviewing agent fixtured with no branch checked out? | Fixture file **contents ARE the diff**, with a `--reviewer-user-prompt-template` override instructing the agent not to run `git diff`. Precedent: `plugins/review-toolkit/evals/security-reviewer-eval/run.sh:37`. Applies to `figma-faithful-reviewer`; the other two agents take an artifact path directly. | codebase-derived |
| D-9 | Anonymization convention for fixtures derived from the #692 run. | Fictional org `Acme`, per `plugins/review-toolkit/evals/security-reviewer-eval/run.sh:37` ("the diff references real Acme paths"). No real customer, product, repo or package identifier in any fixture — see [[no-mdonev-prefix-in-public-repo]]. | codebase-derived |
| D-10 | Do the three new `run.sh` wrappers need selftests? | **No.** `CLAUDE.md`'s coverage register lists "the eval runners" as a standing exception with no independent contract. `shellcheck -e SC1091,SC2015,SC2181` must still pass. Do not add a same-named selftest. | codebase-derived |
| D-11 | Build ordering, given AC-2 forbids prompt edits before the baseline and AC-4 mandates one. | Fixtures + rubrics + runners → **measure and record `CLOSEOUT-BASELINE.md` per agent** → then the AC-4 prompt edit and its D-2 lockstep. No re-measure in this PR (that is the D-1 follow-up). The baseline is therefore the pre-AC-4 number by construction. | codebase-derived |
| D-12 | Do these evals run in CI? | **Never.** CI in this repo is model-free by design; the kit spawns `claude -p` subprocesses on the operator's subscription. Precedent stated outright in `plugins/intake-toolkit/evals/implementability-probe-eval/README.md`: "Operator-run and model-billed. Never in CI". Add no workflow lane. | codebase-derived |
| D-13 | Blast radius of the D-2 lockstep beyond the two agent docs. | **Bounded to the two agent files.** Grepped every `*.md`/`*.sh`/`*.mjs`/`*.json` outside `docs/plans/`: the `N/A` behaviour is restated only in `figma-faithful-spec-reviewer.md` (lines 21, 23, 153) and the deferral block of `figma-faithful-plan-reviewer.md`. `figma-faithful-spec/SKILL.md` references the agent but not its `N/A` condition; `figma-faithful/SKILL.md` and `figma-iterate/SKILL.md` do not restate it. | codebase-derived |
| D-14 | The baseline measurement itself — how many runs, and against which agent prompts? | `--runs-per-fixture 3 --concurrency 2`, against the agent prompts **as they stand before the AC-4 edit** (D-11). Three runs is the smallest n the +10pp/3-run rule can consume, and the kit's own README asks for lower concurrency and fewer runs on iterative work; the campaign that spends more is #707's. Recorded with the run's cost, wall clock, and pinned model ids in each `CLOSEOUT-BASELINE.md`. | codebase-derived |
| D-15 | What resolves OR-1 (a baseline fixture scoring at or near 0/3)? | Nothing in this PR. OR-1's own disposition text is the answer: record the low score in `CLOSEOUT-BASELINE.md` and stop. A low baseline is the *finding this PR exists to produce*, and #707 is the ticket that acts on it — editing a prompt before its baseline lands is the one thing AC-2 exists to prevent. No operator comment is owed because no decision is being taken. | codebase-derived |
| D-16 | What resolves OR-2 (does the AC-4 narrowing change `review-lean` step 5b dispatch)? | Nothing in this PR touches `review-lean`. The narrowing changes which inputs the agent declines, not who dispatches it — and nothing dispatches `figma-faithful-spec-reviewer` on the lean lane today, so the reachable behaviour change is zero until #705 decides the lane's dispatch. Recorded rather than decided. | codebase-derived |

## Acceptance Criteria

- **AC-1** — `plugins/design-toolkit/evals/<agent>-eval/` exists for all three agents, each with
  ≥ 4 fixtures covering the shapes tabulated above (missing dimension rows; name-match component
  resolution; lean-shaped spec with no visual contract; a clean control per agent), each fixture a
  `<name>.md` + `<name>.expected.json` pair, runnable with the `agent-eval-kit` runner and no API
  key. "Runnable" is load-bearing: every `--fixtures-dir` resolves to a committed directory in
  this repo (D-7).
- **AC-2** — a `CLOSEOUT-BASELINE.md` per agent records the measured baseline pass rates, taken
  **before** the AC-4 prompt edit, in the shape of
  `plugins/intake-toolkit/evals/intake-orchestrator-eval/CLOSEOUT-BASELINE.md`: headline table,
  per-fixture table, per-dimension table, and a provenance block naming branch, agent prompt SHA,
  rubric/fixture version, and the exact invocation.
- **AC-3** — **out of scope, re-cut into #707** (D-1). Nothing in this PR runs a keep-or-revert
  campaign, and no `CLOSEOUT-BASELINE.md` here reports a post-edit re-measurement. The re-cut is
  discharged by #707 existing and cross-linking, not by anything in this diff.
- **AC-4** — `figma-faithful-spec-reviewer` no longer `N/A`s a spec that carries a translation
  plan: the `N/A` condition is re-derived to "not a design artifact at all", and the three
  paragraphs in `figma-faithful-plan-reviewer.md` that assert the old behaviour are rewritten in
  the same commit (D-2, D-13). No sentence left in either file claims the spec reviewer returns
  `N/A` on every lean-lane input, or that copy capture has no owner on the lean lane.
- **AC-5** — the `Changelog:` trailer names the prompt changes. No `version` field, no
  `CHANGELOG.md` entry, no `marketplace.json` `metadata.version` edit — `scripts/check-frozen-files.sh`
  is the enforcer and this PR must stay green under it.
- **AC-6** — the three new eval directories pass the repo's own gates:
  `scripts/check-eval-model-identity.sh` (no vendor pin, no floating alias in a model position in
  the runnable surface), `shellcheck -e SC1091,SC2015,SC2181` on the three `run.sh` wrappers, and
  `jq empty` on every `*.expected.json`.
- **AC-7** — no documentation is left stale by this change. The `N/A` behaviour is restated
  nowhere outside the two agent files (D-13), so this AC is satisfied by that measurement holding
  at the branch head, re-run rather than asserted.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | A baseline fixture scoring at or near 0/3 is evidence an agent needs a prompt fix — but AC-2 forbids editing before the baseline, D-1 removes the tuning campaign from scope, and AC-4 authorises exactly one prompt edit. | resolved — D-15 |
| OR-2 | Whether the AC-4 narrowing changes what `review-lean` step 5b or the lean-lane gate dispatches on the design arm. | resolved — D-16 |

## Follow-up owed (not filed from this lane)

- **The four dangling `--fixtures-dir` pointers.** `plugins/review-toolkit/evals/{plan-reviewer,
  review-lead,security-reviewer}-eval/run.sh` and
  `plugins/intake-toolkit/evals/intake-orchestrator-eval/run.sh` each point at a fixtures directory
  absent from this repo, so all four are unrunnable as committed. Out of scope here (D-7, S-11);
  worth a ticket.
