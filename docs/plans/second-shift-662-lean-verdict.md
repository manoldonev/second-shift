# lean review verdict — #662

verdict=needs-work
run_id: review-662-1
session_id: bd74482c-656e-408b-bdde-f59a00683048
rounds: 1
pr: #742
reviewed_head: f55d6e02119ac7ea7f44e34d2a541441dd70c4fb
reviewed_patch_id: a3219145d6467f16a84809456fdf69acebebf38b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 over the full branch diff (`d901b05b..f55d6e02`, 3 files: the spec, `docs/testing.md`,
`tools/selftest-cache-inputs.tsv`). The diff is data and prose, so the review is a re-derivation
of the two declared closures rather than a code read: an under-declared closure is the one defect
this branch can ship, and it is invisible in the diff by construction.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `tools/selftest-cache-inputs.tsv:59-108` | `lean-gate-selftest.sh`'s closure omits `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md`, a file `lean-gate.sh` resolves at run time. Renaming it takes the suite from `all green` to `39 FAILURE(S)` while the declared key does not move — a stale pass. |

### B1 — the closure misses one depth-2 resolution

`lean-gate.sh:3507` defines `resolve_plan_reviewer_agent()`, which calls
`resolve_sibling design-toolkit "agents/$1.md"` (`:3514`). Two call sites reach it — `:4127`
(milestone 3, armed design lane, plan-review record absent) and `:4252` (`cmd_plan_review`) —
and the name is fixed: `design_family_plan_reviewer()` (`:3219`) returns exactly
`figma-faithful-plan-reviewer`. In a monorepo checkout `resolve_sibling`'s rung 1 is
`$PLUGINS_DIR/design-toolkit/agents/figma-faithful-plan-reviewer.md`, and rungs 2 and 3 look under
the repo root's non-existent `design-toolkit/`, so rung 1 is the only rung that can answer. The
file is therefore a run-time resolution of the suite's subject, in exactly the sense the row block
above it uses for `ledger-lint.sh` — the other cross-plugin `resolve_sibling` target, which IS
declared.

**Measured, two isolated worktrees at this head, `env -u LEAN_RUN_MODEL -u LEAN_ATTEND_MODE
-u CLAUDE_CODE_SESSION_ID -u RUN_ID`:**

| Tree | Only difference | `lean-gate-selftest.sh` |
| --- | --- | --- |
| control | none | `[lean-gate-selftest] all green` (0 failures) |
| mutant | that one file `git mv`d to `…-RENAMED.md` | `[lean-gate-selftest] 39 FAILURE(S)` |

The first failures are `(dp6)`, `(dpr1)`–`(dpr8)` — the plan-review cases, which assert the
gate's output names `design-toolkit:figma-faithful-plan-reviewer`. With the file gone the gate
`envfail`s at `:4128` instead, rc=2.

**Why that is a stale pass and not just a missing row.** `cache_manifest()`
(`tools/run-selftests.sh:456-489`) hashes the cache epoch, OS, bash major, `SKIP_STRESS`, the
runner's own blob id, the suite path, and the blob id of each declared input — nothing else. A
rename of an undeclared file moves none of those, so the key is unchanged and `cache_hit()` serves
`v1<TAB>pass`. `ci.yml:112-119` restores the store unconditionally on a PR through
`restore-keys: selftest-pass-${{ runner.os }}-`, reading markers a push to `main` wrote, so the PR
lane is the lane that would serve it. This is the vacuous hit the ticket names as the whole risk
("an input left out of the closure makes a green cache hit vacuous").

**Two things that bound it, neither of which makes AC-1 satisfied.** `scenario-liveness-selftest.sh`
carries no row and so always runs, and it reds on the same change — measured at this head, control
`80 passed, 0 failed` versus mutant `72 passed, 8 failed` — so a PR renaming that agent would still
red the sweep, via a neighbor rather than via the suite whose contract it is. And the nightly
wholesale leg (`nightly-guards.yml:59-62`) runs cold, so the gap surfaces within a day. Both are
incidental containment: the row's own declaration is what AC-1 asks for, and the fix is one line
plus a sentence in the block comment.

**Remedy.** Add
`plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh<TAB>plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md`
and extend the DEPTH 2 comment to name it. The block's current sentence — "Nothing else at depth 2
resolves a further script — every other `*.sh` mention in those files is prose" — is true as
written and is what let this through: the missed resolution is a `.md`, so a `.sh`-scoped sweep of
the depth-2 files could not see it. Worth widening the sentence, not just adding the row. The cost
of declaring it is a spurious miss whenever that agent's prose changes; that is the conservative
direction and matches how `SKILL.md` is already declared for the same suite.

## Acceptance criteria

AC-1 is scored against the spec's own amendment (two suites, not the ticket's four), which the
operator ratified on the issue on 2026-08-31 ("OR-2: approved as recommended — lean-gate's closure
terminates, mutation-sweep-selftest.sh gets no row").

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **unsatisfied** | `check-lean-chain-selftest.sh`'s 3-row closure re-derived independently and is complete — its only checkout reads are `$HERE/check-lean-chain.sh` and, via the `LEAN_EVIDENCE` export at `:104`, `lean-evidence.sh`, which resolves no sibling of its own; everything else it touches it writes under its own `mktemp` tree. `lean-gate-selftest.sh`'s 15-row set is complete at depth 1 — all eight `$HERE/`-rooted reads in the suite are declared — but incomplete at depth 2: see B1. Enumerated exhaustively from the seven `BASH_SOURCE[0]`/`$0`-relative constructions in `lean-gate.sh` (`:281`, `:583`, `:2499`, `:3484`, `:3488`, `:3509`, `:5536`); six map to declared rows, `:3509` does not. |
| AC-2 | satisfied | On the build's recorded sweep table (sweep 2, unchanged tree: `77 / 74 / 3`, both suites served). Not re-executed this round. The mechanism supporting it was verified: `--cache-dir` reads and only `--cache-write` records (`run-selftests.sh:251-255`), `cache_hit()` accepts only a well-formed `v1<TAB>pass` line, and the third cached suite is `cost-block-selftest.sh`, whose rows predate this branch. |
| AC-3 | satisfied | Same basis, and non-vacuous by construction: `ledger-lint.sh` reaches `lean-gate-selftest.sh` only through `lean-gate.sh:3493`'s `resolve_sibling`, and `lean-evidence.sh` reaches `check-lean-chain-selftest.sh` only through its `LEAN_EVIDENCE` export — verified here, so each sweep moved a depth-2 input the other suite does not declare, and neither is the suite or its mechanically-enforced subject. |
| AC-4 | satisfied | The branch diff is three files — the spec, `docs/testing.md`, `tools/selftest-cache-inputs.tsv`. `tools/run-selftests.sh` and every other file of the cache mechanism are untouched. |
| AC-5 | satisfied | All three non-merge commits carry `Changelog: none.`. The diff touches no `plugins/**` path, so `none` is the honest value. |
| AC-6 | satisfied | Both corrections verified against the tree rather than read. The dogfood `test` command is `SKIP_STRESS=1 bash tools/run-selftests.sh --jobs 10 --exclude tools/install-topology-selftest.sh` — no `--full`; `tools/selftest-suite-timings.tsv` declares `# threshold-seconds 9`, and both newly-rowed suites sit above it (212s, 67s), so both are deferred before the cache is consulted, while `cost-block-selftest.sh` carries no timings row and is not. The TSV header now cites `selftest-suite-timings.tsv` and records that it replaced the deleted `tools/mutation-slow-suites.tsv`. |
| AC-7 | satisfied | No data row for `tools/mutation-sweep-selftest.sh`; the header carries the derivation. Confirmed at the source: its case (j) is `git ls-files '*.sh'` over `$REPO_ROOT` (`:2582`) and its TSV-family lint iterates `git ls-files '*-selftest.sh'` (`:2684`), so the composed set is the tracked repo and no file-or-directory row can express it. |

## CI at this head

`lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS, `mutation-sweep-pr` SUCCESS
(run 33415683064, head `f55d6e02`). Those two selftest jobs are the mechanical proof that the new
TSV rows parse, that every declared input exists on a CI checkout, and that both rowed suites are
green cold at this head — the `rc=2` failure modes an over-declared or misspelled row would have
produced.

`pr-gates` FAILURE, and it is not a finding: its only red is `[lean-evidence] ✗ no committed
verdict record`, which this record is. Not scored as a blocker.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section and the branch touches no rendered
surface, so step 5b does not apply.
