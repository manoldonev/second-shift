# lean review verdict — #566

verdict=approve
run_id: review-566-4
session_id: e7b34dff-7f8d-4b36-be15-c2a4ae011c91
rounds: 4
pr: #621
reviewed_head: 7c5ce61810bd538d396adc769d135eeb2860a73a
reviewed_patch_id: 39490020616e7dc8b14b244ef32254618d88d014
inherited_patch_id: 1c24c7d5ddb8a5c7df725f0560fc090b1171ce92
inherited_from_verdict: 55b9ad87d5f6ef2a66460e9b147d278d15913a81
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 4 of PR 621 (#566 — milestone 3 stops running the full sweep locally). Verdict
**approve**: 12/12 acceptance criteria satisfied, **no blockers**, one warning.

Range read: `55b9ad8..HEAD` (the round-3 verdict record to this head), inheriting the coverage
of patch `1c24c7d5ddb8` recorded by round 3. Two commits: `27e9b9e`, the round-3 blocker fix, and
`7c5ce61`, a merge of `origin/main` at `c4a8dd2` (#626). Panel 6/6, none dark, zero findings —
the substance below is my own reading, and I read wider than the delta wherever a base merge could
hide a consumer.

## The round-3 blocker is closed, and closed at all three sites

Round 3 blocked on the orphaned-prose class recurring a third time: retiring milestone 3's
separate 8-interruption budget rewrote `lean-gate-selftest.sh` `(ib2)` and left the `(ib)` block
header above it, `(ib3)` below it and `(if7)` 4,500 lines away all still narrating the deleted
bound. All three are fixed, and the fix does more than correct prose:

| site | state at this head |
| --- | --- |
| the `(ib)` block header (`:1225-1237`) | rewritten to separate what #566 retired — the larger **value**, which existed only because milestone 3 ran detached — from what it did not, the per-milestone **scoping** of the count. It now names `(ib3)` as the case pinning that half, and says why `(ib1)`/`(ib2)` structurally cannot: each seeds the milestone it then asks about. |
| `(ib3)` (`:1281-1292`) | **re-pointed, not deleted.** Seeds 5 unclosed rows at milestone **3** and asks milestone **1**, expecting `rc=0`, no exhaustion row and no interruption notice. |
| `(if7)`/`(if7b)` (`:5930-5960`) | re-seeded from 8 to exactly 5; `(if7b)`'s "past the cap" reworded to "at or past the cap", which is what a seed **at** the bound makes true. |
| `(ib1)`'s pass string | no longer says milestone 1 "keeps" the bound. |

**I verified `(ib3)`'s negative assertion is not vacuous.** `! grep -q 'never concluded'` pins a
string the gate really emits — `lean-gate.sh:5089`, `"$unclosed earlier evaluation(s) began and
never concluded (interrupted $unclosed/$budget)"`. So the case is two-sided against a repo-wide
counter: at the bound it would red on `rc`, below the bound it would red on the announce.

**The re-seeding argument checks out deductively, so I did not need the 141s probe.** At a loosened
6-bound the new `(if7)` reds — 5 unclosed no longer exhausts, so `rc` is 0 where 4 is required —
while the old seed-8 shape still produces `rc=4`, one `interrupted-exhausted | 8 unconcluded` row
and 9 `started` rows, and passes. The PR body's third probe row is right: at 8 the case
discriminated nothing `(ib2)` did not.

**I ran `lean-gate-selftest.sh` myself at this head, cold, without `SKIP_STRESS` — all green.**
That matters more than usual here: this PR's own `tools/selftest-slow-suites.tsv` defers this suite
(141s) from the bounded local check, and the PR mutation lane defers `lean-gate.sh` to nightly, so
this is the round's only direct execution of the file it edits.

**I read the fix's neighbours, which is where this class has survived three times.** `(ib1)` above,
the `(ir)` block below, `(if6)` (`interrupted 1/5` on milestone 3), `(if8)`, `(if11)` (5 seeds on
milestone 1) — all consistent with a single 5-bound. Nothing in `lean-gate-selftest.sh` now
narrates a milestone-3-specific budget.

## Both round-3 warnings are closed

**W-1 (the AC that enumerated its own exemptions).** AC-2 now states the **predicate** — no live
match may be a coupling; past-tense provenance prose and deliberate negative fixtures are not — and
lists the matches *as of a head* rather than as a bound. I ran the full 25-identifier grep on the
merged tree: exactly three live matches, and they are the three the AC names
(`tools/gate-ablation-selftest.sh:256,261`, the `(q)` negative fixture;
`lean-gate.sh:657`, the past-tense D-5 paragraph; `tools/run-selftests-selftest.sh:181`, the
past-tense scrub provenance). Everything else is `CHANGELOG.md` or `docs/plans/**`.

This is an in-commit AC amendment, so it is worth saying which kind: it neither strengthens nor
weakens the operative test, it drops a bookkeeping bound the operative test never depended on. Not
the amended-to-match-the-diff class.

**W-2 (`docs/gate-ablation.md`).** Corrected against the committed manifest header, which I read:
`# from the lane registry: 546 609 611` / `# named by --exclude: 546`. The new sentence says the
operator's `--exclude` named one and the registry found all three, so on the surviving recipe the
other two would have been missed — which is a stronger statement of what the retirement costs than
the one it replaces. `tools/gate-ablation.sh:124` now emits a single header line, and the committed
manifest keeps its three historical ones; the doc is what reconciles them.

## The base merge, checked the way rounds 2 and 3 taught

`7c5ce61` merges #626 (attendance/operator-override). Round 2's blocker arrived exactly this way —
through the other merge parent, in no diff — so I checked the merge on its own terms rather than
crediting the auto-merge.

- **No imported consumer of anything this PR deletes.** The AC-2 grep above runs on the *merged*
  tree. Beyond it I swept by concept word (`detach`, `rejoin`, `lane registry`, `job ceiling`,
  `runner record`, `own budget`, `larger bound`) across every live `*.sh`/`*.md`/`*.yml`/`*.tsv`/
  `*.mjs`: every live hit is past-tense provenance or an unrelated `git worktree --detach`.
- **The three conflict resolutions are correct unions.** `tools/mutation-slow-suites.tsv` keeps
  #626's two new rows (`lean-evidence-selftest.sh` 26s, `check-lean-chain-selftest.sh` 67s) *and*
  this branch's re-measurements (`lean-gate-selftest.sh` 141s, `scenario-liveness-selftest.sh` 68s,
  `mutation-sweep-selftest.sh` 135s). `build-lean/SKILL.md` keeps both #626's attendance clause on
  rule 41 and #566's milestone-3 rewrite on rule 42. `tools/run-selftests-selftest.sh`'s driver
  comment carries both policies.
- **The six re-pointed scrub sites.** #626 brought six direct `env` invocations carrying
  `-u LEAN_JOB_CEILING` — an identifier AC-2 forbids in a selftest — and they are re-pointed at
  `-u LEAN_SELFTEST_CACHE_DIR` rather than deleted. I checked the substitution against
  `tools/run-selftests.sh:254`: the env store activates only when argv named no `--cache-dir`, so
  at the three sites that pass one the scrub is inert, and at the three that do not it prevents an
  ambient store from switching the cache on mid-case. Correct in both directions. (See W-1 below
  for the PR body's stated reason, which is not.)
- **`--help`'s hardcoded range re-derived on the merged header**: `sed -n '2,297p'`, first
  non-comment line still 298 (`set -uo pipefail`). #626's four added lines land at 299+, so neither
  side moved the header. Two-sided guard `(w)` ran green in my suite run.
- **AC-5 measured as contribution, not as diff.** `scripts/check-lean-chain.sh`,
  `plugins/dev-pipeline/tools/lean-evidence.sh`, `pr-gates.yml`, `operator-override.sh`,
  `.claude/lean-overrides.tsv` and `docs/pipeline-manifesto.md` all carry **zero** diff against
  `c4a8dd2`. The merge brought them; this PR contributes nothing to them.

## What I ran at this head

| check | result |
| --- | --- |
| `tools/run-selftests.sh --exclude tools/install-topology-selftest.sh` (the **bounded default**) | **59 scored, 59 run, 0 served from cache, 0 failed**, `real 26.7s`; `72 discovered, 13 excluded, 59 to run` |
| `lean-gate-selftest.sh` alone, cold, no `SKIP_STRESS` | all green |
| `scripts/check-lockstep-pairs.sh` | **28 anchors, 0 failed** |
| all 62 `tools/mutation-catalog.tsv` seds applied at HEAD **and** at `c4a8dd2` | identical no-op sets at both trees — no anchor drift |
| the seven AC-7(b) catalog rows | all absent |
| AC-2's 25-identifier grep on the merged tree | 3 live matches, all permitted |

The bounded run is the one worth keeping: **CI only ever runs `--full`, so the default path still
has no CI coverage at all**, and one command scores AC-1's reap fit (26.7s against a ~120s reap),
AC-4's per-suite named deferral listing (13 lines, each carrying path and the table's reason, with
the discovered/ran invariant intact) and AC-10's default-on application. It also demonstrates
AC-10's compose clause live: the table's rows and my explicit `--exclude` resolved to 13 exclusions
with no conflict and no double-count.

CI at `7c5ce61`: `lint-and-selftests` ✅, `selftests (macos, bash 3.2)` ✅ — both run `--full`, which
is AC-12's before/after evidence. `mutation-sweep-pr` ✅ (`gate-ablation.sh` 10/10/0; `lean-gate.sh`,
`orchestrate-lean.sh` and `run-selftests.sh` deferred to nightly). `pr-gates` ❌ **only** at step 6,
`lean chain reconciliation` — the missing verdict record, which this commit supplies; steps 3/4/5
green.

Round 4's own commit edits no guard **code**, so the PR lane's three deferrals cost this round
nothing new: the file it touches is `lean-gate-selftest.sh`, and I executed that suite directly.

## Findings

| # | severity | site | finding |
| --- | --- | --- | --- |
| W-1 | warning | PR body, "Stated plainly, because the naive port is usually scenery" | The justification given for the six re-pointed scrub sites is factually wrong about its own diff, in two ways. It says *"None of them passes `--cache-write`"* — **two of the six do**: `out.cache-norc` (`tools/run-selftests-selftest.sh:538`) and `out.env.seed` (`:707`) both pass `--cache-dir … --cache-write`. And `--cache-write` is not what makes the scrub inert anyway: `tools/run-selftests.sh:254` gates the env store on `[[ -z "$CACHE_DIR" ]]`, so it is an **explicit `--cache-dir` on argv** that makes it inert, at the three sites that pass one. At the three that do not, the scrub is not merely defense-in-depth — without it an ambient store prints `cache: activated from LEAN_SELFTEST_CACHE_DIR (recording on)` and the case records synthetic fixture results into the operator's real store, which is exactly what the driver's own comment at `:24-38` says the scrub is for. |

**Why W-1 is a warning and not a blocker**, on the test [#604 r3](https://github.com/manoldonev/second-shift/pull/606) established and round 1 of this PR applied: the shipped code is correct in both directions and strictly safer than either alternative, and the claim's operative conclusion — *"dropping the scrub reds nothing"* — is true. What is false is the reason offered for it, and it lives in PR-body prose that no operator acts on. No clause of the diff is wrong; a reader reconstructing *why* the port is safe is.

**One suppressed observation, recorded rather than raised.** `tools/selftest-slow-suites.tsv`'s
costs for `lean-evidence-selftest.sh` (11s) and `check-lean-chain-selftest.sh` (35s) were measured
on 2026-08-20, before #626 added 52 and 41 lines to those suites; `tools/mutation-slow-suites.tsv`
carries 26s and 67s for the same files, measured a day later. Both suites are already deferred by
the table either way, so no bound is at risk and nothing is actionable in this PR — the numbers are
a cost record, not a gate. Worth knowing when that table is next re-measured.

## Acceptance criteria

Scored against the committed spec `docs/plans/second-shift-566-lean.md`, every criterion every
round, against the whole branch — the delta bounded my reading, not the scoring.

| AC | score | evidence at `7c5ce61` |
| --- | --- | --- |
| AC-1 — milestone 3 is a single blocking call; no detached runner, no rejoin; `cmd_3` reached from `run_milestone`'s dispatch; reap fit measured | **satisfied** | Both dispatch `case "$n"` blocks in `run_milestone` carry `3) cmd_3 ;;` — the observe arm and the main one. `(if5b)` asserts the gate's own process-group kill leaves no lane child running, and `(lean-inline-m3)` composes the inline path end to end. Reap fit re-measured by me at this head: **26.7s** against a ~120s reap. |
| AC-2 — the supervision stratum is gone; the 25-token grep matches only `CHANGELOG.md` and `docs/plans/**` | **satisfied** | Run on the merged tree. Three live matches, all three named by the AC and all three non-couplings: a deliberate negative fixture and two past-tense provenance comments. `lane-registry.sh` and `lane-registry-selftest.sh` are deleted. |
| AC-3 — a red bounded check charges exactly one fix attempt; `rc=4` on the 4th red preserved | **satisfied** | `(ib1)`, `(ib2)`, `(if7)`, `(if7b)`, `(if11)` all green in my direct run of the suite. `(if7)` now seeds the bound exactly, so it reds under a loosened bound instead of passing under any of three. |
| AC-4 — each deferred suite named on stdout with path and reason; the gate replays it; a deferral neither reds nor charges budget nor trips the discovered/ran invariant | **satisfied** | Observed live: 13 `deferred:` lines, each carrying the repo-relative path and the table's reason column; `72 discovered, 13 excluded, 59 to run` → `59 scored, 59 run, 0 failed`, `rc=0`. |
| AC-5 — the merge boundary carries no diff; `.github/workflows/*` carries only the `--full` additions at 4 sites | **satisfied** | `check-lean-chain.sh`, `lean-evidence.sh` and `pr-gates.yml` carry **zero** contribution against `c4a8dd2`. `.github/` totals 4 changed lines: `ci.yml` ×2 and `nightly-guards.yml` ×2, every one a `--full` insertion at a `run-selftests.sh` call site. |
| AC-6 — `scenario-liveness-selftest.sh` composes the new milestone-3 verdict path; the kill/rejoin cases are removed rather than left asserting deleted machinery | **satisfied** | The `#566` scenario carries both legs at this head: `(lean-inline-m3)` asserts a closed `started`/`concluded` pair with `m3infra-v3:0` and no `spawned detached` announcement, and `(lean-inline-m3-nv)` asserts a killed evaluation moves the same read to `m3infra-v3:1`. Survived the merge, which also touched this file. |
| AC-7 — (a) dead baseline rows dropped; (b) the seven catalog rows deleted; (c) VOID; (d) the PR body states the net bash delta | **satisfied** | (b) all seven ids absent from `tools/mutation-catalog.tsv`; all 62 surviving rows resolve, with **identical** no-op sets at HEAD and at `c4a8dd2` — so the deltas are harness artifacts, not drift, and nothing is re-anchored. (c) the VOID is sound: `scripts/lockstep-manifest.tsv` was deleted by this branch's own base, and the substitute `scripts/check-lockstep-pairs.sh` is green at 28 anchors, up one from round 3 because the merge added a pair. (d) −2,168 net bash, stated. |
| AC-8 — `lean-gate.sh` reads no CI verdict; no new `gh`/network call on any milestone-3 path | **satisfied** | No `GH_CLI`, `CURL_CLI`, `gh api` or `curl` anywhere in `cmd_3`. The merge's new network-free `$OVERRIDE_TOOL` calls sit on the milestone-1 region path, not this one. |
| AC-9 — `infra_token` prints `m3infra-v3:<n>` from `unclosed_count 3` alone; the runner-record diagnostic is gone; `orchestrate-lean.sh`'s `infra_token()` body unchanged | **satisfied** | `lean-gate.sh:2354` prints `m3infra-v3:%s`, never empty. This PR's **entire** contribution to `orchestrate-lean.sh` against `c4a8dd2` is one comment line, `m3infra-v2:0` → `v3:0`; the function body is byte-identical. Guarded by `(ir1)`/`(ir3)` and composed by both `(lean-inline-m3)` legs. |
| AC-10 — the table is committed with path/cost/reason per row, applied by default, `--full` opts out, a stale row is a hard error, `--full` and `--exclude` compose | **satisfied** | Verified live on the default path, which has no CI coverage at all. The table applied without being asked for; my explicit `--exclude` composed with it to 13 exclusions, no conflict and no double-count. |
| AC-11 — `CLAUDE.md`'s recipe gains `--full`; `docs/testing.md` re-derived; `build-lean/SKILL.md`'s detach claim rewritten, under the 60-line cap | **satisfied** | `CLAUDE.md:60` and `docs/testing.md:14` both carry `--full`. `SKILL.md` rule 42 now reads "Milestone 3 used to be the exception … since #566 it is not: `bash G 3` runs inline, bounded to fit the turn by `tools/selftest-slow-suites.tsv`". **49 lines**, under the cap, and the merge kept both sides' edits. Rule 38's surviving `rc=7` claim re-checked against `lean-gate.sh:195-201` and still true — a milestone-3 seven now means the lane raised 3 and nothing else. |
| AC-12 — behavior-preserving elsewhere under `--full` | **satisfied** | Both CI selftest lanes are green at this head and both run `--full`: `lint-and-selftests` and `selftests (macos, bash 3.2)`. Independent of the PR body's own 71/71/0 figure. |

## Fidelity

`not-applicable`. The spec's `## Design` section reads `Design: none — this is shell tooling with
no rendered surface`, and I confirmed the disarm rather than taking it: `design.provider` is
unset in this repo's `.claude/second-shift.config.json`, so the disarm is not one a configured
design provider would make suspicious. No `| RS-n |` rows, no handoff link, no render receipt.

## Verdict

**approve.** Every acceptance criterion is satisfied, the round-3 blocker is closed at all three of
its sites with the coverage argument made explicit and one case pointed at a discriminator it did
not have before, both round-3 warnings are closed, and the base merge introduced no consumer of the
retired stratum. The single warning is a wrong justification in PR-body prose for a code change
that is correct — worth fixing when the body is next touched, not worth a round.
