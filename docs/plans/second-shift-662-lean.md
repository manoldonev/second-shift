# #662 — pass-cache rows for the suites whose input closures actually enumerate

## What lands

`tools/selftest-cache-inputs.tsv` gains row sets for two suites:

| Suite | Measured | Rows |
| --- | --- | --- |
| `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` | 212s (2026-08-30) | 15 |
| `scripts/check-lean-chain-selftest.sh` | 67s (2026-08-21) | 3 |

279s of declared-input cost, against the 414s the pre-flight receipt projected across three
suites. The third — `tools/mutation-sweep-selftest.sh`, 135s — is dropped: the derivation below
shows its closure is the repo's whole tracked `*.sh` set, which is the exact condition #461 used
to drop `scenario-liveness-selftest.sh`. See D-1.

No runner change, no mechanism change. Rows and prose only.

## Where the benefit lands, stated honestly

The ticket's premise — that the lean lane's milestone-3 sweep "pays ~4–6 cold minutes" for these
suites, and that this is what pushes headless runs past the turn boundary — is false, and the
spec does not inherit it. The lane's `test` command omits `--full`, so `run-selftests.sh` applies
the slow-suite table and DEFERS every suite at or above the 9s threshold — which is every suite
rowed here. The lane never runs them, so no cache can save time it does not spend. The benefit is
the two CI selftest jobs, which pass `--full --cache-dir`; PRs hit through `restore-keys` against
markers a push to `main` wrote. D-5, D-9.

## The derivations

Both closures were read out of the suites, not copied from the ticket. Every resolution was
followed until it terminated; each row-comment block in the TSV records where.

### `lean-gate-selftest.sh` — terminates, 15 rows

Depth 1, read by the suite itself: `lean-gate.sh` (subject), `SKILL.md` (the (f) line-cap case),
`tools/fixture-stamp.sh` (sourced), `plugins/audit-toolkit/hooks/audit-tool-calls.sh` (the (d5)
writer-half case), `tools/run-selftests.sh` (the (ic6)/(ic7) composed-sweep cases),
`tools/gate-ablation-adjudication.tsv` and `tools/gate-ablation-classes.tsv` (the (ac1c)/(ac1d)
static-classification cases), and `plugins/dev-pipeline/tools/operator-override.sh` (the (yo)
override-artifact cases).

Depth 2, resolved by `lean-gate.sh` at run time: `branch-prefix.sh` and
`plugins/dev-pipeline/tools/resolve-sibling.sh` (both sourced), `claim-issue.sh`,
`pipeline-cost-block.sh`, and — through `resolve_sibling` — the cross-plugin
`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`.

Depth 3: `claim-issue.sh` resolves `gh-bot.sh`, which resolves an out-of-repo wrapper under
`$HOME`. The closure terminates there, per D-8. Nothing else at depth 2 resolves a further
script: every other `*.sh` mention in those files is prose.

Two things deliberately outside the closure, both recorded in the TSV: `node_modules/.bin/prettier`,
which the (fp5) live-oracle case uses opportunistically and skips when absent — it is untracked, so
it has no blob id, and CI never installs it; and `.claude/second-shift.config.json`, which the
suite references zero times (D-11).

### `check-lean-chain-selftest.sh` — terminates, 3 rows

The suite reads `scripts/check-lean-chain.sh` (subject) and exports `LEAN_EVIDENCE` at
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` — the same payload the gate would
resolve by default. `lean-evidence.sh` resolves no sibling; the closure terminates at depth 2.
Every other file the suite touches is written under its own `mktemp` tree.

### `mutation-sweep-selftest.sh` — does NOT terminate

Its case (j) enumerates `git ls-files '*.sh'` over the whole repository and, for each result,
tests whether a same-stem `-selftest.sh` file exists. Its case (k)/(l) `grep`s the CONTENT of
every tracked `*-selftest.sh` for literal `/tmp` redirects, and reads six committed
`mutation-*.tsv` / `selftest-suite-timings.tsv` files. Its verdict therefore moves when any `.sh`
file anywhere in the tree is added, removed or edited.

That set cannot be declared as file rows, and directory rows cannot express it either: the
universe is `git ls-files`, so it is the tracked set, while a directory row contributes every
regular file beneath it including untracked ones — a different question. Declaring the repo root
would bust on every PR, so the row could never hit while adding a stale-path liability. The
sanctioned direction for a closure that cannot be enumerated stably is to ship no row and let the
suite always run.

## Acceptance Criteria

- AC-1: `tools/selftest-cache-inputs.tsv` carries a complete input closure for
  `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` and
  `scripts/check-lean-chain-selftest.sh`. Each set names the suite itself, the script under test,
  every checked-in file the suite reads, and every file those resolve at run time, to termination.
- AC-2: demonstrated hit — two consecutive `tools/run-selftests.sh --full --cache-write
  --cache-dir <tmp> --exclude tools/install-topology-selftest.sh` runs over an unchanged tree, the
  second reporting both rowed suites as served from cache.
- AC-3: demonstrated miss — touching one declared input of each rowed suite, at depth 2 or deeper
  and never the suite or its subject, re-runs exactly that suite on the next sweep and leaves the
  other cached.
- AC-4: no change to `tools/run-selftests.sh` or to any other file of the cache mechanism. The
  diff is the TSV plus prose.
- AC-5: the branch carries a `Changelog:` trailer.
- AC-6: two stale statements are corrected — `docs/testing.md`'s claim that the lean lane's store
  speeds a sweep it never runs, and `tools/selftest-cache-inputs.tsv`'s header citation of
  `tools/mutation-slow-suites.tsv`, deleted in #641.
- AC-7: `tools/mutation-sweep-selftest.sh` gains no row, and the TSV header records the derivation
  that ruled it out, so the next contributor reads why rather than re-deriving it.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does `scenario-liveness-selftest.sh` get a row, as AC-1 names | DEPARTURE — the rule is carried, its suite count is not. `scenario-liveness-selftest.sh` still gets no row, for exactly the reason D-1 gives. Deriving the other three showed `tools/mutation-sweep-selftest.sh` meets the same test: its case (j) enumerates `git ls-files '*.sh'` over the whole repo and its TSV-family lint greps every tracked `*-selftest.sh`, so its composed set is the repo and cannot be enumerated stably either. AC-1 is therefore TWO suites, not three: `lean-gate-selftest.sh` and `scripts/check-lean-chain-selftest.sh`. 279s rowed, 135s left cold in the same safe direction D-1 chose. | user-answered |
| D-2 | How `lean-gate-selftest.sh`'s input closure is derived | Exact file rows, following every `$here/`-style resolution out of every declared script until it terminates, to depth 3 — `lean-gate.sh` resolves `pipeline-cost-block.sh`, which resolves `gh-bot.sh`. Each row-comment block names where the closure terminated, per the mandate in `docs/testing.md`. Directory rows were rejected: they bust on any edit under `build-lean/`, which is where most of this repo's PRs land. | user-answered |
| D-3 | Sweep shape for the AC-2 hit and AC-3 miss demonstrations | `--full --cache-write --cache-dir <tmp> --exclude tools/install-topology-selftest.sh`, in the `nohup` harness-tracked background shape CLAUDE.md mandates for long calls. `--full` is load-bearing and stays. The excluded suite has no row, so excluding it cannot change what AC-2 or AC-3 prove, and it removes 584s per sweep. | user-answered |
| D-4 | Which declared input each AC-3 miss-demo moves | A depth-2-or-deeper input per suite — never the suite itself and never its `<stem>.sh` subject, both of which the runner already enforces mechanically, so moving them restates a mechanized rule. For `lean-gate` that means `gh-bot.sh` (depth 3) or the cross-plugin `ledger-lint.sh`. | user-answered |
| D-5 | How BUILD handles the ticket's false lean-lane premise | Proceed with the row work; the spec restates the benefit at its real site — the two CI selftest jobs — and DROPS the #628 turn-boundary claim rather than inheriting it. See D-9 for the measurement that falsifies it. | user-answered |
| D-6 | Scope of prose corrections under AC-4 | Correct two stale statements: `docs/testing.md`'s pass-cache savings sentence, which this branch falsifies and which is already wrong, and the `selftest-cache-inputs.tsv` header's citation of `tools/mutation-slow-suites.tsv`, deleted in #641. AC-4 freezes `run-selftests.sh` and the cache mechanism; prose is neither, and both files stay untouched. | user-answered |
| D-7 | AC-2's command as the ticket writes it | Unsatisfiable as written. `--cache-dir` READS and only `--cache-write` RECORDS (`tools/run-selftests.sh:251-255`, docs property 3), so two consecutive `--cache-dir`-only runs both miss and no hit can ever be demonstrated. AC-2 is amended to carry `--cache-write`. Forced by the mechanism, not a choice. | codebase-derived |
| D-8 | Where a closure terminates when a resolution leaves the repo | At the out-of-repo file, not beyond it — #461's precedent for `gh-bot.sh`, recorded in the TSV header: "It resolves an out-of-repo wrapper under `$HOME`, so the closure terminates there." | codebase-derived |
| D-9 | Can the lean lane's milestone-3 sweep benefit at all | No. Its `test` command omits `--full`, so `tools/run-selftests.sh:211-224` applies the slow-suite table and DEFERS every suite at or above the 9s threshold — all three rowed suites included. Milestone 3 never runs them, so no cache can save it time it does not spend. `:190` states the design outright: "the only caller that WANTS the bound is lean-gate.sh milestone 3." The benefit is CI-only: both selftest jobs pass `--full --cache-dir` (`ci.yml:121`, `:414`) and PRs hit via `restore-keys` against markers a main push wrote. | codebase-derived |
| D-10 | Does `check-sweep-bound.sh` interact with cached frames | No. It is invoked from `nightly-guards.yml` and nowhere else — asserted by its own AC-5 — and the nightly passes no `--cache-dir`, so the `::group::cached  -  <suite>` frame's literal-dash elapsed field never reaches its `^[0-9]+s$` parse. Constraint for later: rowing a suite BELOW the 9s threshold would make that parse reachable and must be handled first. | codebase-derived |
| D-11 | Does the gitignored dogfood config enter `lean-gate-selftest.sh`'s closure | No. The suite references `.claude/second-shift.config.json` zero times and stages its own fixture trees, so no untracked machine-local file can enter the key. This matters because a declared input that does not exist reds the sweep with `rc=2`, and that file is absent on CI. | codebase-derived |
| D-12 | Cost figures the spec carries | Re-measured at the current head: `lean-gate-selftest.sh` is 212s (measured 2026-08-30), not the 141s the ticket cites from 2026-08-20/21. With `tools/mutation-sweep-selftest.sh` dropped at D-1, the rowed total is 279s serial — 212s plus `check-lean-chain-selftest.sh`'s 67s — not the 414s three suites would have carried, and not the ticket's implied 411s across four. | codebase-derived |
| D-13 | Why only `cost-block` has rows today | Not an abandoned rollout. #461's landing set was three suites; `statectl-selftest.sh` (149s of a 171s sweep, the measurement the mechanism was sized against) was deleted with the stage choreography in #568 and #577, taking its rows with it. The TSV header's "landing set" prose is historical. | codebase-derived |

Two rows are carried verbatim although a detail inside them reads against the receipt's
three-suite set rather than this branch's two. Neither reverses a decision, so neither is a
departure: D-9's "all three rowed suites included" is true of the receipt's set and its answer —
the lean lane cannot benefit — is unchanged at two; and D-2's illustrative chain names
`pipeline-cost-block.sh` as what resolves `gh-bot.sh`, where the derivation above found it
resolves no sibling at all and `claim-issue.sh` is the depth-2 script that reaches it. D-2's
actual instruction — exact file rows, every resolution followed to termination, each termination
recorded in a row comment, no directory rows — is what the closure was built by, and it is still
a depth-3 closure.

## Open regions from the pre-flight receipt

| ID | Region | Where it stands |
| --- | --- | --- |
| OR-1 | No mechanized guard catches a helper added LATER to a declared closure | Default taken: no guard. AC-4 freezes the mechanism, and the nightly wholesale leg runs both lanes with no store, so an under-declaration surfaces within a day against a tree nobody is waiting on. Flagged in the PR body as a residual. |
| OR-2 | Whether `lean-gate-selftest.sh`'s closure actually terminates once derived in full | It does — 15 rows, terminating at the out-of-repo `$HOME` wrapper `gh-bot.sh` resolves. The failure the region was written to catch did materialize, on a suite it did not name: `tools/mutation-sweep-selftest.sh`. It is handled the way the region says to handle it — no row, reported, not shipped under-declared. |

OR-2's disposition in the receipt is operator-resolved, and the build session cannot close it.
The derivation above is the answer; the resolving comment on the issue is the operator's.

## Demonstrations

Recorded after the rows land — AC-2's hit and AC-3's per-suite miss, both from the sweep shape
D-3 fixes.
