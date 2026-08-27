# lean review verdict — #694

verdict=needs-work
run_id: review-694-1
session_id: e522ce46-d951-4347-b470-0e1bf30ce9d3
rounds: 1
pr: #701
reviewed_head: 4343498bc53f4e658ce3fcd48967defd15dbd336
reviewed_patch_id: 4472a86437f3f0148e0db71cb62abc44d0f250d3
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #701 (issue #694), head `4343498b`

Range read: `609a22cf..4343498b` (full branch diff — root round, nothing to inherit).
Panel: 6 of 6 returned, none dark (security, performance, complexity, test-coverage,
scope-completeness, maintainability). Design fidelity: **not-applicable** — the committed spec
`docs/plans/second-shift-694-lean.md` declares no `## Design` section, so step 5b does not arm.

**Verdict: `needs-work`** — 3 blockers. Two of them are the same fix landing wrong (AC-4), and
one is a coverage gap proven by mutation (AC-6). The gate itself is correct: every arm I probed
behaves as documented, and both new `tools/mutation-catalog.tsv` rows are honestly graded.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | Blocker | `plugins/design-toolkit/**` (4 sites) | The AC-4 rewrite introduces the `dev-pipeline:` namespace token into design-toolkit, which `docs/namespaces.md` rule 3(a) forbids. `lint-and-selftests` is RED on it. |
| B2 | Blocker | `plugins/design-toolkit/agents/figma-faithful-reviewer.md:39` | AC-4 missed a family member: it still defers to "a deferred pixel-diff gate" — the gate AC-4 says may not be named. |
| B3 | Blocker | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3814,3838` | Two of `plan_violations()`'s five malformed shapes have no `(dp*)` case. Both are fail-open when neutered, and the suite stays green. AC-6 asks for "each malformed shape". |
| W1 | Warning | `docs/testing.md:782-791` | The declined-coupling note justifies D-10 in one direction only; a plan-only edit does restale the render receipt. |
| W2 | Warning | PR body / commit `63e181aa` | The `(dp*)` case count is stated three different ways, and one enumerated shape has no case. |

### B1 — the AC-4 fix violates `docs/namespaces.md` rule 3(a), and CI is red on it

`lint-and-selftests` step 15, *namespace direction check (docs/namespaces.md rule 3)*, fails
(run 33086021046, job 98565746233, head `4343498b`, conclusion `failure`). Rule 3(a) greps for the
literal `dev-pipeline:` token across the four toolkit plugins and exits 1 on any hit. The AC-4
deferral rewrite introduces four:

- `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md:56`
- `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md:64`
- `plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md:33`
- `plugins/design-toolkit/skills/figma-faithful/SKILL.md:205`

Measured: `git grep 'dev-pipeline:' origin/main -- plugins/design-toolkit plugins/review-toolkit
plugins/intake-toolkit plugins/audit-toolkit` returns **nothing**; the same grep at `4343498b`
returns exactly those four. Wholly diff-introduced.

This is not a merge-boundary policy red of the `guard-budget` / `Changelog:` / frozen-files kind.
Those name something the run was going to do anyway; this one names content the diff just wrote,
and it sits in the correctness lane. (The rest of that job is green — step 9 *run all selftests*
passed, as did the `selftests (macos, bash 3.2)` job.)

**Remedy, and it is small.** Name the lane bare, which is what every other toolkit already does:
`plugins/review-toolkit/skills/review-lead/SKILL.md:190` writes "`review-lean`'s design-sighted
fidelity arm", and `plugins/intake-toolkit/skills/plan-interview/SKILL.md:61` writes "an autonomous
`run-lean <issue>` run". Dropping `/dev-pipeline:` from the four sites keeps every sentence AC-4
asks for and clears the rule. The reader is still unambiguously named.

### B2 — AC-4 stops one file short of the family

AC-4: *"every deferral in the `figma-faithful` reviewer family names an owner that can actually run
on the lean lane, or says plainly that none can. … none may name a gate that does not exist."*

`plugins/design-toolkit/agents/figma-faithful-reviewer.md:39`, under **Hard limits**, still reads:

> You cannot verify a value MATCHES the design. … That needs the Figma node dump (**a deferred
> pixel-diff gate**), which you do not have.

That is the forbidden construct verbatim, in the third member of the three-agent
`figma-faithful-*` family — and one that IS dispatched on the lean lane, as review-lead's
design-fidelity dimension under `design.provider: figma`. The diff proves the author read this
construct as in scope: the identical sentence was rewritten in **both** siblings
(`figma-faithful-plan-reviewer.md:64`, `figma-faithful-spec-reviewer.md:33`) to name the
design-sighted review session and to add "no such gate exists in this repo". This file was simply
not visited. The PR body meanwhile asserts the work is complete: *"Every deferral in the reviewer
family now names a reachable owner, or says none exists."*

Fix it the same way the siblings were fixed — and without reintroducing B1's token.

### B3 — two of five malformed shapes are unguarded, and both fail OPEN

`plan_violations()` emits five distinct violation shapes. Three have a case; two have none:

| shape | site | case |
| --- | --- | --- |
| no table declares the column | `lean-gate.sh:3858,3859` | `(dp2)` |
| a short row | `lean-gate.sh:3847` | `(dp4)` |
| an empty cell | `lean-gate.sh:3852` | `(dp3)` |
| **the table carries no data row** | `lean-gate.sh:3814-3815` | **none** |
| **no delimiter row under the header** | `lean-gate.sh:3838-3839` | **none** |

AC-6 asks that the suite cover *"each malformed shape"*. Probed rather than argued, in an isolated
detached worktree at `4343498b` (never the reviewed one):

1. **Direct probe of the predicate.** Extracting `plan_violations()` and running it over crafted
   plans, at HEAD and under each mutant:
   - a `| node | dimensions | overflow |` table with a delimiter row and **zero data rows** —
     HEAD: `the table declaring a "dimensions" column carries no data row`; with `:3814` neutered
     to `if (0) {`: **`<NONE>`**.
   - the same table with **no delimiter row** and two data rows — HEAD: `…has no delimiter row
     under its header`; with `:3838` neutered: **`<NONE>`**.
   Both mutants turn a refusal into a clean pass, so neither arm is cosmetic.
2. **Suite verdict under each mutant.** Full `lean-gate-selftest.sh`, env scrubbed
   (`env -u CLAUDE_CODE_SESSION_ID -u LEAN_ATTEND_MODE -u LEAN_RUN_MODEL -u
   LEAN_SPAWN_PERMISSION_MODE -u RUN_ID`), one mutant per worktree:

   | tree | assertions | failures | suite rc |
   | --- | ---: | ---: | ---: |
   | unmutated baseline | 549 | 0 | 0 |
   | `:3814` → `if (0) {` (no-data-row arm) | 549 | **0 — SURVIVES** | **0** |
   | `:3838` → `if (0) {` (delimiter arm) | 549 | **0 — SURVIVES** | **0** |

   The `(dp*)` block ran identically in all three (same 12 assertions, all green) — the mutants are
   inside the block's blast radius and it does not see them.

The no-data-row shape is not an exotic one. It is the ticket's own headline failure restated: the
issue was filed on *"a plan that records no control dimensions at all"*, and a `dimensions` table
with a header and no rows is exactly that, passing the gate written to catch it. Two `(dp*)` cases
in the shape of `(dp3)`/`(dp4)` close it.

### W1 — the declined-coupling note is one-directional

`docs/testing.md:782-791` (and the mirroring comment at `lean-gate-selftest.sh`'s `dplan_sync`)
justify not excluding the plan from `render_patch_id()` with: *"it only goes stale when non-plan,
non-receipt code moved — which stales the receipt anyway."* That is true of `plan_patch_id()`. The
reverse is unstated and does happen: the plan **is** inside `render_patch_id()`, so a plan-only
commit — filling a `why this component` cell after a plan-review finding, no code change — moves
the render id and restales the receipt, forcing a full re-render nothing else asked for. No
livelock (the receipt is excluded from both identities, so it settles in one pass), and D-10's
lockstep rationale against `check-lean-chain.sh` still carries the decision on its own. The note
just claims more than the code delivers; one sentence.

### W2 — the case count is stated three ways

PR body: "gains 12 `(dp*)` cases". Commit `63e181aa`'s `Guard-mass:` trailer: "11
lean-gate-selftest cases". Measured: **10 case ids** (`dp0`–`dp9`) carrying **12** pass/fail
assertions. Separately, the PR body enumerates the covered malformed shapes as "(missing column,
empty cell, short row, **no delimiter**, no header line)" — there is no delimiter-row case (B3).

## Recorded, not blocking

- **`pr-gates` is red on step 7 only** — *lean chain reconciliation*, which requires
  `verdict=approve`. Expected state for an unreviewed lean PR, not a finding. Steps 3-6 (frozen
  files, `Changelog:` trailer, guard budget, pipeline chain reconciliation) are all green.
- **`mutation-sweep-pr` is green in 12s and graded nothing here.** `lean-gate-selftest.sh` is
  slow-listed in `tools/selftest-suite-timings.tsv`, so the PR-lane sweep defers it. I probed both
  new catalog rows by hand instead, same isolated-worktree method as B3:
  - `lean-plan-arm-uncalled` (`design_plan_gate; rc=$?` → `rc=0`) — **killed**: 539/549, 10
    failures (`dp1`-`dp8` and their partners), suite rc 10.
  - `lean-plan-empty-cell-waived` (`if (cell[i] == "") {` → `if (0) {`) — **killed**: 548/549,
    1 failure, exactly `(dp3)`, suite rc 1.
  Both rows are live and precisely anchored; the PR body's hand-probe claim reproduces.
- **A panel finding I dismissed.** maintainability-reviewer reported, at confidence 92, a literal
  `[REDACTED]` placeholder in the comment at `lean-gate.sh:3953`, citing its own `git show`.
  Measured: `grep -c 'REDACTED'` returns **0** against both the worktree file and the committed
  blob `4343498b:plugins/dev-pipeline/skills/build-lean/lean-gate.sh`. It is an artifact of the
  reviewing harness's output filter, which also rewrote the `(dpN)` case ids in my own selftest
  logs. No defect. Security, performance, complexity, test-coverage and scope-completeness
  returned zero findings each.

## Acceptance criteria

Scored against the committed spec `docs/plans/second-shift-694-lean.md`, every `AC-n` re-derived
this round.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — armed spec owes a committed, `planned_from`-stamped plan at `<plansDir>/<key>-lean-plan.md`; milestone 3 refuses before the render pass on absence / malformed table / stale binding; same arming predicate and `design_was_armed` lock | **satisfied** | `PLAN_MANIFEST_REL` (`lean-gate.sh:830`), `plan_patch_id()` (`:982`), `design_plan_gate()` (`:3884`) called as the first statement of the ARMED block in `cmd_3_render` (`:3960`), after the `design_state()` case and after the `armed` record is appended. `(dp0)` pins the AND half of arming, `(dp1)` absence on the absent budget, `(dp6)` the stamp-and-commit cycle reds before the harness is called once, `(dp7)` staleness converging, `(dp8)` the disarm lock. `scenario-liveness-selftest.sh`'s `(lean-design-plan)` composes it. |
| AC-2 — plan review reports a control-bearing screen whose plan records no dimension row; inverted to the silent case | **satisfied** | `figma-faithful-plan-reviewer.md:88` (with `:32`) adds a `[Blocker]` on "no dimension row at all", alongside the retained repeating/wrapping-group `[Warning]`. |
| AC-3 — plan review reports a component whose rendered affordances exceed the frame with no note that it is intended | **satisfied** | New `### Component-resolution suitability` section, `figma-faithful-plan-reviewer.md:92-110`; the affordance-excess and name-match-only `[Blocker]`s. |
| AC-4 — every deferral in the family names a lane-reachable owner or says none exists; none names a target that `N/A`s every lean-lane input; none names a gate that does not exist | **unsatisfied** | B2: `figma-faithful-reviewer.md:39` still names the non-existent pixel-diff gate. B1: the two rewrites that did land name their owner with a token `docs/namespaces.md` rule 3(a) forbids in a toolkit, and CI is red on it. The interactive-lane-only marking of `figma-faithful-spec-reviewer` and the "copy capture has no lean-lane owner" statement are both correct and are the good half of this AC. |
| AC-5 — `figma-faithful` step 7 describes the artifact (path, tables, `planned_from`) and the asserting milestone | **satisfied** | `figma-faithful/SKILL.md:179-213` — path, the stamp cycle including the re-read obligation, both required columns, the every-cell/no-short-row rule, and the explicit statement that nothing here checks correctness. Replaces the #693 placeholder. |
| AC-6 — `lean-gate-selftest.sh` covers AC-1 (arming, absence, **each malformed shape**, the stamp cycle, staleness, the disarm lock) and `scenario-liveness-selftest.sh` carries the composed leg | **unsatisfied** | The liveness leg is present and real (`(lean-design-plan)`, both halves). Three of five malformed shapes are covered; two are not, and both fail open — B3, measured. |
| AC-7 — `docs/live-render.md` and `build-lean/SKILL.md` describe the plan gate where they describe the render receipt | **satisfied** | `docs/live-render.md:112-133` (the plan first, then the render, with the budget split); `build-lean/SKILL.md:27`. |

## Strengths

- **The three-identity derivation is the strongest thing here.** `plan_patch_id()` is structurally
  identical to `render_patch_id()` — same merge-base, same `patch-id --stable`, same
  print-nothing-on-failure contract — with each of its three exclusions independently motivated,
  and the declined symmetric change on `render_patch_id()` is recorded in `docs/testing.md`'s
  *Couplings considered and declined* rather than left for a future reader to rediscover. The
  `#436` skew it avoids is real and is invisible from either side.
- **The budget split is applied, not asserted.** Absence / missing header / stale stamp are
  `block_milestone`, a malformed table is `fail_milestone`, and `(dp1)` and `(dp2)` pin the
  attempt counter on each side rather than just the exit code.
- **`dplan_sync()` stamps through production.** The fixture never derives a patch id itself, and
  the comment says why — it would agree with a broken gate forever. It also save-and-restores the
  real progress file so the attempt counters the other cases assert on stay byte-identical. That
  is the harder and correct construction.
- **The fenced-example carve-out was found by probing.** `(dp9)` exists because a plan quoting the
  shape the gate's own refusal tells you to write would otherwise be refused for quoting it — the
  one red an author cannot act on.
- **Both new mutation-catalog rows are precisely anchored**, and the bracket-expression fix for
  BSD `sed -E` (`[$][?]`) is the right call, not a workaround.

## Re-entry

B1 and B2 are prose edits in `plugins/design-toolkit/`; B3 is two `(dp*)` cases modelled on
`(dp3)`/`(dp4)`. None of the three touches `lean-gate.sh`'s executable surface, so a round-2 delta
should be small. Fixing B1 will turn `lint-and-selftests` green; `pr-gates` stays red until a
verdict of `approve` exists, by design.
