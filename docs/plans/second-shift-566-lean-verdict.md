# lean review verdict — #566

verdict=needs-work
run_id: review-566-3
session_id: 9a8cc3c4-0b0b-4e44-b734-a15929cec422
rounds: 3
pr: #621
reviewed_head: f81bccf9e0cf90d0e999c5c177059dacee411e8c
reviewed_patch_id: 1c24c7d5ddb8a5c7df725f0560fc090b1171ce92
inherited_patch_id: 35012eada9cdc8ff1ce371101a8a038dcbf73f85
inherited_from_verdict: dd02b16bf863622ca6869237b844c4738a6de43c
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3 of PR 621 (#566 — the milestone-3 supervision deletion). **needs-work**, 12/12 ACs
satisfied, **1 blocker outside the AC set** (one class, three sites), 3 warnings.

Range read: `dd02b16..HEAD`, inheriting patch `35012eada9cd` (round 2's coverage). That range is
dominated by the base merge of `origin/main` (`7377057`, importing #627 and #590), so I also read
the branch's whole contribution against the current base — `42dfb2a...HEAD`, 23 files,
+938/−2701. Panel 6/6, none dark.

## Round 2's blockers are genuinely closed

**B-1 closed, and closed the better of the two ways offered.** `tools/gate-ablation.sh` no longer
has a registry source at all: the `LANES` default, `--lanes`, `live_lanes()` and the three-line
attribution header are gone, `--exclude` is the single source, and the one surviving header line
says so in as many words. The tool header and `docs/gate-ablation.md`'s regeneration recipe both
name who declares live lanes now and what happens to one you forget. **Probed, not read:** in an
isolated worktree I reinstated the `$STATE_DIR/lean-lanes.tsv` default into the exclusion set —
`(q)`, `(q2)` and `(r)` all red. The re-pointed `(q)` is the case that matters: it plants a stale
`lean-lanes.tsv` in the fixture state dir, which is the state every machine that ran a pre-#566
lane is actually in, and asserts nothing is excluded behind the operator's back. `(q3)` closes the
argv half — `--lanes` now reaches the `*)` arm and exits 2 rather than being a silent no-op. No
stale `--lanes` caller survives anywhere in the tree, and nothing in CI invokes the tool.

**B-2 closed, and the replacement comment is checkable rather than plausible.** `cmd_3`'s `#526`
rationale is rewritten as #563's own placement reason, and its factual claim — that
`lane_apply_selftest_cache` is now the only *assignment* appended to `SEAM_SCRUB_ENV`, every other
entry being a `-u` scrub — verifies: the only `+=` sites are `LEAN_SELFTEST_CACHE_DIR=` /
`=$store` inside that function (`:2096`, `:2103`) and the `-u` scrub at `:3427`.

**W-1 closed** (the D-5 paragraph is past-tense and states that `--ticket-source lane-registry` is
now a caller-asserted label backed by no file). **W-3 closed** — the body's net-bash figure is now
exact: I measured `441 added / 2,626 deleted / −2,185` against `42dfb2a`, which is what it claims.
**W-4 is closed by circumstance**: `mutation-sweep-pr` finally graded something this round
(`tools/gate-ablation.sh` 10 applied / 10 killed / 0 survived), because the fix landed in a file
whose paired suite carries no `tools/mutation-slow-suites.tsv` row. Three guards are still
deferred. W-2 (no gate-side guard for AC-4's replay half) stands as a follow-up, not re-raised.

**The round-3 base merge was hand-resolved correctly.** `--help`'s hardcoded `sed -n '2,Np'` is
**297**, which I re-derived independently on the merged file: line 297 is the last header line and
line 298 is `set -uo pipefail`. Neither side's number survived a merge that both shrank and grew
the header, and case `(w)` is genuinely two-sided (asserts the last header line present **and**
`set -uo pipefail` absent), so both truncation and overrun red. The usage strings and the
subcommand `case` are the correct union: `close-out` in, `m3-run` out. #627's hand-rolled `env`
case in `tools/run-selftests-selftest.sh` — which arrived carrying #526's `LEAN_JOB_CEILING` scrub
— is re-pointed at `LEAN_SELFTEST_CACHE_DIR` and made two-sided. **Probed:** dropping the
`-u LEAN_SELFTEST_CACHE_DIR` scrub reds the case.

## BLOCKER — the deletion falsified a live selftest's prose, and this is the third round of that same class

`plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`, three sites. This PR retired
milestone 3's separate 8-interruption budget (`INTERRUPTED_BUDGET_M3`) and put every milestone on
the single `INTERRUPTED_BUDGET=5`. It rewrote `(ib2)` to assert the new bound — and left the block
that contains `(ib2)`, and a second block 4,500 lines away, describing the bound it deleted.

**1. The `(ib)` block header, `:1218-1224` — contradicted by the case the PR added five lines
below it.**

```
# ---- (ib) #527 AC-4: the INTERRUPTED budget is per-milestone ----------------------
# … Once an infra kill stops charging a fix attempt the lane re-spawns, and each dead
# spawn leaves another unclosed `started` row that nothing decrements …
#
# The discriminator is the SAME COUNT answered two ways: 5 unclosed rows exhausts
# milestone 1 and does not exhaust milestone 3.
```

The budget is no longer per-milestone; there is no lane re-spawn; and `(ib2)` — added by this
diff, immediately below — asserts precisely that 5 unclosed rows **does** exhaust milestone 3.
A green suite states both.

**2. `(ib3)`, `:1268-1274` — round 1's B-1 shape verbatim, one line below an edit this PR made.**
The comment opens `# ...and the larger bound is a BOUND, not an absence of one.` That ellipsis
continues `(ib2)`'s **old** text (*"it runs, on its own 8-bound"*), which this diff replaced — so
the diff removed the antecedent and left the continuation, exactly as round 1's deleted register
header did. Its pass string, `"(ib3) AC-4: milestone 3 still hard-stops once its own budget is
spent"`, names a budget that no longer exists, and the case is now strictly subsumed by `(ib2)`:
seeding 8 unclosed rows under a 5-bound asserts nothing that seeding 5 does not already assert.

**3. `(if7)`, `:5810-5817`.**

```
# EIGHT unconcluded rows, and the ninth call refuses: no body, no new started row, rc=4.
#
# Eight, not five, since #527: milestone 3 carries its own larger interrupted budget,
# because an infrastructure kill no longer charges a fix attempt and each dead re-spawn
# leaves another unclosed row here. The 5-bound is still asserted, on a milestone that
# keeps it — (if11) and (ib1) both drive milestone 1 — so the split is pinned from both
# sides rather than relaxed.
```

Every clause is false at this head: milestone 3 carries no larger budget, nothing re-spawns, and
there is no split to pin from both sides. It sits two blocks below `(if6)`, which asserts
`interrupted 1/5` **on milestone 3**. The pass string — *"the 9th evaluation past 8 unconcluded
rows returns 4"* — advertises an 8-bound to anyone reading the green log.

**Why this is the blocker class and not a nit.** Round 1 blocked on a deletion that removed an
entry's header and left its tail attached to a live variable, and recorded the distinguishing test
in its own verdict: *when the surviving prose makes a false statement about live code, it is a
blocker, not a warning*. Round 2 applied that test again to `cmd_3`'s orphaned `#526` rationale.
These three sites are the same defect a third time, and site 2 is the strongest instance yet — the
build edited the case directly above it. Round 2 also recorded the generalization this round
should have been read against: **a fix commit that closes one instance of a class has not closed
the class** — after rewriting `(ib2)`, the file needed a sweep for the deleted subject's *concept
words* (`per-milestone`, `larger bound`, `its own budget`, `re-spawn`), not just its identifier.
`AC-2`'s grep is structurally blind here for the same reason it was in round 2: the prose spells
the concept, never `INTERRUPTED_BUDGET_M3`.

**Coverage is not lost, and I want that on the record so the fix is scoped correctly.** `(ib2)`
seeds 5 and so still catches a regression that re-raises milestone 3's bound; `(if7)` and `(ib3)`
seed 8 and merely cannot discriminate. So this is a prose-and-narration defect, not a hole in the
guard set. The remedy is correspondingly small and belongs in one commit: rewrite the `(ib)`
header and `(if7)`'s rationale to the single 5-bound, re-seed or retire `(if7)`'s 8, and either
delete `(ib3)` as subsumed or re-point it at something that still discriminates.

**Nothing mechanical was ever going to catch it.** `lean-gate-selftest.sh` is on this PR's own
`tools/selftest-slow-suites.tsv` (141s), so the bounded milestone-3 check skips it; the PR-lane
mutation sweep defers it to nightly; and CI only runs it, which proves the assertions pass, not
that they describe the code. A human reader is the entire net here — which is the argument
`AC-6` already makes for the sibling file (*"removed rather than left asserting deleted
machinery"*).

## Warnings

- **W-1 — AC-2's round-3 amendment enumerates two permitted live matches; there are three.** The
  amendment says *"Two live matches are permitted and both are named here"* — `(q)`'s fixture
  registry and `lean-gate.sh`'s D-5 paragraph. A third exists at this head:
  `tools/run-selftests-selftest.sh:173`, *"It carried #526's `LEAN_JOB_CEILING` scrub on the same
  reasoning until #566 deleted the ceiling"* — a live match of `LEAN_JOB_CEILING` in a **selftest**,
  a location the base clause says the grep must never hit. **Warning, not blocker, and the reason
  is the amendment's own operative test:** it says *no live match may be a COUPLING*, and this one
  is past-tense provenance prose, not a coupling. Every actionable clause of AC-2 stays true —
  which is #604 round 3's distinguishing test — so what is stale is the bookkeeping ("two"), not
  the predicate. It is worth one sentence in the spec because the build wrote this comment itself,
  in this round, while amending the very AC that forbids the identifier. I re-ran all 25 tokens
  against the merged tree: this is the only unenumerated live match.
- **W-2 — `docs/gate-ablation.md`'s new paragraph understates what the registry supplied.** It
  says the committed pin *"was cut against three (546 609 611); two of them were found
  automatically, by a lane registry that #566 retired"*. The committed manifest header says
  otherwise: `from the lane registry: 546 609 611`, `named by --exclude: 546`. The registry found
  **all three**; two of them would have been *missed without it*. The practical takeaway the
  paragraph is making — name every live lane by hand now — is right, and the stale three-line
  header in `docs/gate-ablation-manifest.tsv` is inert (`emit` skips `#` lines) and honestly
  disclosed by this very paragraph, which is why neither is a blocker. But the sentence as written
  invites a reader to think the operator's own list already covered a third of the set.
- **W-3 — `docs/testing.md:50`'s "four in-repo callers" of `--exclude` is unchanged from the base
  and still omits `CLAUDE.md`'s recipe**, which passes `--exclude tools/install-topology-selftest.sh`
  too. Pre-existing, identical at `42dfb2a`, and the enumeration that follows it names exactly the
  four CI/nightly jobs it means — noted so a later re-derivation does not read it as this PR's
  arithmetic.

## Verification run at this head

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — **clean** (rc=0).
- Every `*.json` through `jq empty` — **clean**.
- `bash scripts/check-lockstep-pairs.sh` — **27 anchors, 0 failed**.
- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude
  tools/install-topology-selftest.sh` — the **default, bounded** path, which CI never exercises:
  `71 discovered, 13 excluded, 58 to run`, `58 scored, 58 run, 0 served from cache, 0 failed`,
  rc=0, **27.3s wall** against the ~120s reap. Live evidence for AC-1's reap fit, AC-4's per-suite
  named deferral (13 `deferred:` lines, each carrying path, measured cost and the table's reason)
  and AC-10's default-on application and `--exclude`/table dedupe.
- **Catalog anchors, at BOTH trees.** I applied all 62 `tools/mutation-catalog.tsv` seds to their
  guards at `f81bccf` and at `42dfb2a` and `comm`'d the no-op sets: **zero no-ops at either**. No
  re-anchor is owed, and the count is reported two-tree so a harness artifact cannot be read as
  drift.
- **AC-2's full grep re-run on the MERGED tree** — all 23 code identifiers plus the amendment's
  `lean-lanes.tsv` and `live_lanes`. Every hit is in `CHANGELOG.md` or `docs/plans/**` except the
  two permitted live matches and the one carried as W-1.
- **Two probes in an isolated worktree** (`/private/tmp/566-probe-r3`, detached at the reviewed
  head): reinstating `gate-ablation.sh`'s registry read reds `(q)`/`(q2)`/`(r)`; dropping
  `run-selftests-selftest.sh`'s `-u LEAN_SELFTEST_CACHE_DIR` scrub reds the `SELFTEST_JOBS` case.
- CI on the exact reviewed head `f81bccf`: `lint-and-selftests` ✅, `selftests (macos, bash 3.2)`
  ✅, `mutation-sweep-pr` ✅ (10/10/0 on `tools/gate-ablation.sh`; `lean-gate.sh`,
  `orchestrate-lean.sh` and `run-selftests.sh` deferred), `release-pr-gates` skipped, `pr-gates`
  ❌ — failing **only** at step 6, `lean chain reconciliation`, on the verdict record this round
  replaces. Steps 3, 4 and 5 pass. Expected pre-review.
- Base is current: `HEAD..origin/main` is **0** commits, PR is `MERGEABLE`, head unchanged
  (`f81bccf`) between the start of this review and the writing of this record.

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — this is shell tooling with no rendered
surface`, and I verified the disarm rather than accepting it: `.claude/second-shift.config.json`
carries no `design` key at all, so no provider is configured and there is no handoff frame or RS
table to score against.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — milestone 3 is a single blocking call, `cmd_3` reached from `run_milestone`'s dispatch | satisfied | The `3) cmd_3 ;;` arm is present in both of `run_milestone`'s inner `case`s (observe and normal), with the `*)` envfail retained; no `&`/`setsid`/`nohup` on the path. Reap fit **measured by me at 27.3s** on this tree. `scenario-liveness-selftest.sh`'s `(lean-inline-m3-nv)` composes it: a group kill leaves no lane child alive, so a re-detach reds. |
| AC-2 — the supervision stratum is gone | satisfied | All 25 identifiers (23 code + the amendment's `lean-lanes.tsv`/`live_lanes`) grepped repo-wide on the merged tree; the only live matches are the two the amendment names, plus the past-tense provenance comment carried as W-1, which is not a coupling. `lane-registry.sh` and `lane-registry-selftest.sh` deleted. |
| AC-3 — one fix attempt per red, `rc=4` on the 4th preserved | satisfied | Unchanged since round 2's reading; re-read at this head. `run_milestone` resolves one `budget` and reuses it for the announce, the observe prediction and the refusal; `(ib1)`/`(ib2)`/`(ib3)`, `(if6)`/`(if7)`/`(if7b)`/`(if11)` drive it. The blocker above is about how those cases are NARRATED, not about the behavior they assert. |
| AC-4 — each deferred suite named on stdout with path and reason; a deferral neither reds nor charges budget nor trips discovered/ran | satisfied | Measured live: 13 `deferred:` lines each carrying path, measured cost and reason; `58 scored, 58 run` against `71 discovered, 13 excluded`, rc=0. Gate-side guard gap still carried as round 2's W-2 follow-up. |
| AC-5 — merge boundary untouched; workflows carry only the `--full` additions | satisfied | `scripts/check-lean-chain.sh` and `plugins/dev-pipeline/tools/lean-evidence.sh` carry **no diff** against `42dfb2a`. `.github/workflows/*` carries exactly 4 changed lines, all `--full` insertions at the four `run-selftests.sh` call sites (`ci.yml` ×2, `nightly-guards.yml` ×2). `pr-gates` unedited. |
| AC-6 — scenario-liveness composes the new milestone-3 verdict path; kill/rejoin cases removed | satisfied | The `#566` scenario at `:1995-2095` composes the inline evaluation end to end AND carries its own non-vacuity leg: the happy path asserts a closed started/concluded pair with `m3infra-v3:0`, and the kill leg asserts the same read moves to `m3infra-v3:1` with `started` and no `concluded`, after proving nothing outlived the group kill. Every surviving `detach`/`rejoin` mention in that file is an assertion that detaching is gone. |
| AC-7 — baseline, catalog, lockstep, net delta | satisfied | (a) nothing owed — `tools/mutation-baseline.tsv` carries no row naming `lane-registry.sh` or any `m3_*`/`LEAN_JOB_CEILING` site; the two `lean-gate.sh` survivors are content-keyed and unmoved. (b) all **seven** catalog rows absent at this head, and all 62 remaining anchors resolve at HEAD and at the base. (c) VOID with its reasoning stated; substitute verified green at 27 anchors. (d) the body's `−2,185 (441/2,626)` is exactly what I measured. |
| AC-8 — no CI/network read on any milestone-3 path | satisfied | No `gh`, `curl`, `GH_CLI` or `CURL_CLI` reachable from `cmd_3` or `run_milestone`; the base merge's new `close-out` network calls are milestone-5/step-9 and outside the milestone-3 path. |
| AC-9 — `infra_token` prints `m3infra-v3:<n>` from `unclosed_count 3` alone; scheduler body unchanged | satisfied | `lean-gate.sh:2339-2350` prints `m3infra-v3:%s`, never empty, with the runner-record diagnostic gone. `orchestrate-lean.sh`'s **entire** diff against the base is one comment line (`m3infra-v2:0`→`v3:0`); `infra_token()`'s body is byte-identical. Guarded by `(ir1)`/`(ir3)`/`(ir4)` and composed by `(lean-inline-m3)`/`(lean-inline-m3-nv)`. |
| AC-10 — the committed table applied by default, `--full` opts out, stale row is a hard error, `--full`/`--exclude` compose | satisfied | Applied by default in my own run with no flag; the explicitly-excluded suite is also a table row and `EXCLUDED` stayed 13, so the dedupe holds and `EXPECTED = DISCOVERED − EXCLUDED` is honest. `--full` is what CI passes and CI is green. Stale-row hard error covered by `run-selftests-selftest.sh`'s `slow-table:` block. |
| AC-11 — `CLAUDE.md`, `docs/testing.md`, `SKILL.md` re-derived | satisfied | `CLAUDE.md:60` carries `--full`; `docs/testing.md`'s headline recipe reads `--full` with the bounded default explained at `:17-21` and a caller table at `:74-79`; `SKILL.md:42` states milestone 3 runs inline bounded by `tools/selftest-slow-suites.tsv`. **49 lines**, under the 60-line cap. The selftest comments in the blocker are outside this AC's three named targets. |
| AC-12 — behavior-preserving elsewhere | satisfied | Both CI selftest jobs run `--full` (all 71 suites, including the 13 the bounded check defers) and are green on the exact reviewed head; my bounded 58-suite run is green independently. |

## What to do

One commit in `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`. Rewrite the `(ib)`
block header and `(if7)`'s rationale to the single 5-bound; re-seed or retire `(if7)`'s 8; delete
`(ib3)` as subsumed by `(ib2)` or re-point it at a property that still discriminates. Then grep
the file once more for the deleted subject's concept words rather than its identifier —
`per-milestone`, `larger bound`, `its own budget`, `re-spawn`, `the split` — because that is the
sweep that would have caught all three sites at once. While you are there, add the third permitted
live match to AC-2's amendment (W-1) and correct `docs/gate-ablation.md`'s "two of them" (W-2);
both are one sentence each and neither is worth a round on its own.
