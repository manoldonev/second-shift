# lean review verdict — #662

verdict=approve
run_id: review-662-2
session_id: 4f71b23e-fd13-441a-946a-3ecd5b980c9f
rounds: 2
pr: #742
reviewed_head: b844892412f906a01452f62f02f98fcd03a4b2ff
reviewed_patch_id: 92a461b4780685f2a63241db1352dd5eaaeb5d76
inherited_patch_id: a3219145d6467f16a84809456fdf69acebebf38b
inherited_from_verdict: 8bd9a5d3421b8014502c79c53152c19e2fd6bc6f
fidelity: not-applicable
panel: none
model: opus
capabilities: pr-marker

Round 2 over the delta `8bd9a5d3..HEAD` (3 files: the spec, `docs/testing.md`,
`tools/selftest-cache-inputs.tsv`), inheriting the coverage of patch `a3219145d646`. The
reviewer panel was dispatched over the WHOLE branch diff (`origin/main...b8448924`) rather
than the delta — the branch is four files, so reading everything was cheaper than reasoning
about what inheritance permitted.

Round 1's blocker B1 is fixed and the fix is non-vacuous. The diff is data and prose, so the
review is again an independent re-derivation of both closures rather than a code read: an
under-declared closure is still the one defect this branch can ship, and it is invisible in
the diff by construction.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `docs/testing.md:1536` | A fourth shipped sentence still teaches the dead resolution AC-9 was written to retire, and carries a second stale fact the branch itself supersedes. Not an unmet AC — AC-9's two named sites are corrected — but the spec and PR body claim the sweep was complete, and it was not. |
| S1 | suggestion | `tools/selftest-cache-inputs.tsv:117-127` | The `DELIBERATELY OUT` block records two of the graded-tree non-rows the branch's own rule generates, and not the three that rule finds in `tools/run-selftests.sh`. |
| N1 | nit | `tools/selftest-cache-inputs.tsv:106` | "Nothing at depth 2 resolves a further file" contradicts the opening clause of its own sentence. |

### W1 — one more sentence teaching the resolution #584 deleted

`docs/testing.md:1534-1537`, in the **mutation-sweep** verdict-cache section (untouched by this
branch):

> "A third file can flip a verdict with the guard and all its suites byte-identical:
> `lean-gate.sh` shells out to four sibling scripts, and `cost-block-selftest.sh` reaches
> `pipeline-cost-block.sh`'s own resolution of `gh-bot.sh`."

Both halves are stale, and this branch is what supersedes them:

- `pipeline-cost-block.sh` resolves `gh-bot.sh` nowhere. Verified at this head: `grep -c gh-bot`
  returns 0, and its only variable-rooted paths are `$MAIN_ROOT/.claude/second-shift.config.json`
  and `$HOME/.claude/otel-metrics/metrics.jsonl`. `git log -S'gh-bot'` on that path dates the
  removal to #584 (`d3449568`) — the same derivation AC-9 records.
- "**four** sibling scripts" is the issue body's figure. This branch's own derivation establishes
  **seven** beside-the-subject constructions in `lean-gate.sh` (`:281`, `:583`, `:2499`, `:3484`,
  `:3488`, `:3509`, `:5536`), six `.sh` and one `.md`, which is the count the TSV header and
  `docs/testing.md`'s contract now both carry.

**Why it is recorded rather than waved through.** The branch ships, as new doctrine at
`docs/testing.md:479-482`, precisely the rule this sentence violates: *"A stale row is cheap; a
stale example teaches the next row-adder to derive against something that is not there, which is
why this paragraph now points at a resolution the tree still makes."* An instance of that defect
survives 1050 lines below the doctrine, in the same file.

The claim that outran the diff is in two places a human reads. The spec
(`docs/plans/second-shift-662-lean.md:157-163`): *"Three shipped sentences still asserted the
resolution"* — the enumeration is the TSV header, the `cost-block-selftest.sh` row comment, and
`docs/testing.md`'s contract twice; `:1536` is a fourth and is not in it. The PR body: *"all now
teach from the chain this branch derived, which is live."* Not all.

**Why it is not a blocker.** AC-9 is scoped by its own words to *"the depth-2 worked example that
`tools/selftest-cache-inputs.tsv`'s header and `docs/testing.md`'s contract both teach from"*.
`:1536` is in neither — it is an illustration of the *mutation* cache's unsoundness, whose
structural point (a third file can flip a verdict) survives its example dying. No AC is unmet, no
gate is affected, and the closure this branch exists to declare is correct. Refusing the round
here would buy WHEN a two-clause prose edit lands, not whether — at the price of a full
build-and-review pair.

**Remedy, for whoever next touches that section:** replace the example with the live chain
(`lean-gate.sh` -> `claim-issue.sh` -> `gh-bot.sh`, the one the pass-cache contract now teaches)
and the count with seven.

### S1 — the rule generates three non-rows the table does not record

AC-8's rule instructs: *"Grep each declared script for the paths it BUILDS FROM A VARIABLE, and
match every one against the rows below."* Applied to `tools/run-selftests.sh` — itself a declared
input of `lean-gate-selftest.sh` — it yields three graded-tree resolutions:

```
tools/run-selftests.sh:210  SLOW_SUITES="$ROOT/tools/selftest-suite-timings.tsv"
tools/run-selftests.sh:240  [[ -x "$ROOT/tools/reap-lean-fixtures.sh" ]]
tools/run-selftests.sh:407  CACHE_TSV="$ROOT/tools/selftest-cache-inputs.tsv"
```

All three are correctly **non-rows**, and I verified why rather than assuming it: the only path
by which the suite reaches this runner is `(ic6)`/`(ic7)`, which invoke it as
`bash "$IC_RUNNER" --root "$IC_SWEEP" --jobs 2` (`lean-gate-selftest.sh:1291`), so `$ROOT` is the
`mktemp` fixture tree and never this repo. That is rule (3) reaching the same verdict it reaches
for `check-frozen-files.sh` / `check-changelog-trailer.sh` — which the branch DOES record under
`DELIBERATELY OUT`.

Recording two of five is the gap. It is not a correctness defect and no AC asks for an exhaustive
non-row register, but the memory this round was written from says a derivation rule should be run
over the whole artifact and every non-row it would add recorded. Three lines in the existing block
would close it, and the third is the interesting one: `selftest-cache-inputs.tsv` declaring itself
as an input to a rowed suite is a shape worth a sentence saying it was considered and why it does
not arise.

### N1 — a sentence that contradicts its own opening clause

`tools/selftest-cache-inputs.tsv:104-107`:

> "DEPTH 3, and where it TERMINATES: claim-issue.sh resolves gh-bot.sh... **Nothing at depth 2
> resolves a further file**: this is the whole live depth-3 chain in the table..."

`claim-issue.sh` is at depth 2 and resolves a further file — the same sentence says so eight words
earlier. The pre-round-2 text read "Nothing **else** at depth 2 resolves a further script"; the
rewrite dropped the "else". The trailing colon-clause makes the intent recoverable, and the
closure is unaffected. Worth one word, in a block whose job is to teach derivation.

## Round 1 findings, re-checked

| Prior | Status |
| --- | --- |
| B1 — `lean-gate-selftest.sh`'s closure omits `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` | **Fixed, non-vacuously.** The row is declared (`tools/selftest-cache-inputs.tsv:143`) and the DEPTH 2 comment names it with its existence-only property, which is what round 1 asked for beyond the row itself. Re-derived independently at this head: `resolve_plan_reviewer_agent()` (`:3507-3515`) is reached from `:4127` and `:4252`, and `design_family_plan_reviewer()` (`:3219`) has exactly one non-failing arm (`figma`), so that `.md` is the only agent path the gate can resolve — no second family, no second row owed. |

## Acceptance criteria

All nine satisfied. AC-1 is scored against the spec's two-suite set, which is the operator's
decision twice over and not the build's: the pre-flight ledger's D-1 (`user-answered`, `intent`)
answers *"Does `scenario-liveness-selftest.sh` get a row, as AC-1 names"* with **No** and amends
AC-1 to three suites, and the operator then ratified `mutation-sweep-selftest.sh`'s removal by
name on the issue (2026-08-31 14:58Z).

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Both closures re-derived independently at this head, from the sources rather than from the prose. `lean-gate-selftest.sh`, 16 rows: the suite makes nine `$HERE/`-rooted references, eight of them checkout files (all declared) and the ninth an install-cache glob (`$HERE/../../../../audit-toolkit/*/hooks/...`, out of repo, dead in a monorepo checkout where `$HOOK_REPO` resolves). `lean-gate.sh` makes seven beside-the-subject constructions, all declared, one of them (`operator-override.sh`) already among the eight. Only `claim-issue.sh` goes deeper (`:65` -> `gh-bot.sh`), and `gh-bot.sh` terminates out of repo at `$HOME/.config/.../gh-as-bot.sh` (`:93,:96`) — checked, not assumed, against `operator-override.sh`, `branch-prefix.sh`, `pipeline-cost-block.sh`, `ledger-lint.sh`, `resolve-sibling.sh` and `audit-tool-calls.sh`, none of which makes one. 8 + 6 new + 1 at depth 3 + the suite itself = 16. The two graded-tree non-rows are correct: the suite names `check-frozen-files`/`check-changelog-trailer` zero times, and every one of its 59+ gate invocations `cd`s into a `$WORK` fixture — the only two real-repo reaches are topology probes (`:1307`, `:7459`) and the (fp5) prettier oracle (`:6291`), all three already recorded as out. `check-lean-chain-selftest.sh`, 3 rows: exactly two checkout reads (`$HERE/check-lean-chain.sh`, and `lean-evidence.sh` via the `LEAN_EVIDENCE` export at `:104`), and `lean-evidence.sh` resolves only `$REPO_ROOT/.claude/second-shift.config.json` — graded-tree, fixture-rooted, correctly no row. |
| AC-2 | satisfied | Sweep 2 of the build's round-2 table (`77 / 74 / 3`, both rowed suites cached). **Re-executed this round against the shipped closure**, which round 1's was not, and I verified the transfer to this head rather than accepting it: every declared input across all three rowed suites plus `tools/run-selftests.sh` has an identical blob id at `d02ea0a4` and at `b8448924`, and `cache_manifest()` (`tools/run-selftests.sh:459-489`) hashes epoch/OS/bash-major/`SKIP_STRESS` + runner blob + suite path + declared-input blobs and NOT the TSV, so all three keys are byte-identical across the prose commits. |
| AC-3 | satisfied | Sweeps 3 and 4, one per rowed suite. Sweep 3 moves `figma-faithful-plan-reviewer.md` — the row round 1 found missing — so it is evidence about the FIX and not merely about the mechanism: with the 15-row closure that same edit moved no declared blob. Non-vacuous by construction and verified here: that `.md` is declared for `lean-gate-selftest.sh` alone and `lean-evidence.sh` for `check-lean-chain-selftest.sh` alone, and neither is a suite or a mechanically-enforced subject. |
| AC-4 | satisfied | Branch diff is four files — two `docs/plans/` artifacts, `docs/testing.md`, `tools/selftest-cache-inputs.tsv`. `tools/run-selftests.sh` and every other cache-mechanism file untouched. The spec's AC-4 reads "the diff is the TSV plus prose", which is what landed; D-6 scopes the prose. |
| AC-5 | satisfied | All eleven non-merge commits carry `Changelog: none.`, and the diff touches no `plugins/**` path, so `none` is the honest value. |
| AC-6 | satisfied | Both halves verified against the tree. The lean-lane correction landed and the companion sentence seven lines below it — the round-2 amendment's subject — now agrees with it (`docs/testing.md:445-448`). The suite count reads "Three suites are rowed today" against exactly three distinct first-column values in the TSV. The mechanism behind the claim re-checked independently: `tools/selftest-suite-timings.tsv` declares `# threshold-seconds 9` and rows both new suites (212s, 67s) above it, while `cost-block-selftest.sh` has no timings row at all — so "the only one of the three this lane can serve" is exact, not approximate. |
| AC-7 | satisfied | No data row for `tools/mutation-sweep-selftest.sh`; the header carries the derivation, and the operator ratified it by name. |
| AC-8 | satisfied | The three-part rule is stated in both places a row-adder reads (`tools/selftest-cache-inputs.tsv:47-66`, `docs/testing.md:485-509`), and each part is justified against a row or non-row this table carries. I ran the rule over the table myself, which is the test part 3 exists because parts 1 and 2 failed: it reproduces all 16 lean-gate rows and all 3 chain rows, finds `lean-evidence.sh` (the row the narrow form could not reach), and correctly declines `check-frozen-files.sh`/`check-changelog-trailer.sh`. See S1 for the three non-rows it also generates that the table does not record. |
| AC-9 | satisfied | `pipeline-cost-block.sh` contains zero `gh-bot` references at this head and makes no variable-rooted sibling construction; `git log -S'gh-bot'` dates the removal to #584. Both named teaching sites now carry the live `lean-gate.sh` -> `claim-issue.sh` -> `gh-bot.sh` chain, and `cost-block-selftest.sh`'s surviving row is labeled an over-declaration and kept. Satisfied as scoped — see W1 for the fourth sentence outside that scope. |

## Spec amendment check

AC-6 was widened and AC-8/AC-9 added in round 2, by the session that also wrote the diff. Checked
for the direction that would be a blocker — a spec amended after the fact to match the diff — and
all three move the other way. AC-6 was widened after round 1 scored it satisfied, because the
first correction left a contradicting sentence below it; AC-8 codifies the remedy round 1
explicitly recommended (*"Worth widening the sentence, not just adding the row"*); AC-9 is scope
the branch found by applying AC-8's own rule to the file it landed in. None weakens an obligation
and none converts an unmet AC into a met one. The two ledger rows carrying details this branch
supersedes (D-9's three-suite phrasing, D-2's illustrative chain) were left VERBATIM with the
discrepancy noted below the table, which is the right handling for `user-answered` rows.

## Reviewer panel

Six reviewers dispatched over `origin/main...b8448924`, six returned — no dark reviewer, round not
void. Security, performance, maintainability, complexity and test-coverage all returned `approve`
with no findings. `scope-completeness-reviewer` returned `request-changes` on one major finding,
**dismissed**: it read the issue body's four-suite AC-1 and could not see
`.claude/pipeline-state/662-ledger.md`, which is host-local and gitignored, so it treated D-1's
removal of `scenario-liveness-selftest.sh` as a build-session assertion. D-1 is `user-answered` /
`intent` and answers that suite by name. Its remedy — amend the issue body — is both unnecessary
and a human-authority action. Its two lesser findings dissolve with it; its independent
confirmation of the blob-id transfer is corroboration and is folded into AC-2 above.

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).

## CI at this head

`lint-and-selftests` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS, `mutation-sweep-pr` SUCCESS
(run 33422308866, head `b8448924`). The Linux job is cited rather than re-run: it is the same
`--full --cache-dir` sweep at the same head, and it is the mechanical proof this branch most
needs — `77 scored, 76 run, 1 served from cache, 0 failed`, with `lean-gate-selftest.sh` running
119s to `all green` and `check-lean-chain-selftest.sh` 26s to pass. That is every one of the 19
new rows validated against a real checkout by the runner's own four containment checks
(row shape, suite discovery, input existence, self-inclusion and subject) — the `rc=2` an
over-declared, misspelled or stale-path row would have produced.

`pr-gates` FAILURE, and it is not a finding: its only red is that the committed record still reads
`verdict=needs-work`, which is round 1's. This record supersedes it.

## Design fidelity

`not-applicable`. The repo's config declares no `design.provider` (no `design` key at all), and
the spec has no `## Design` section, so step 5b does not apply and no disarm justification is
owed.
