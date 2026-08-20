# lean review verdict — #566

verdict=needs-work
run_id: review-566-2
session_id: dda9a792-17ce-459b-8217-1e67444f5741
rounds: 2
pr: #621
reviewed_head: 6b236d2524b66625208b800499bd1e5c659f72c3
reviewed_patch_id: 35012eada9cdc8ff1ce371101a8a038dcbf73f85
inherited_patch_id: fae4fa7dfb8499c182ce16ea5341e9ac6ead8920
inherited_from_verdict: 45f8f24739a862055e3241bc55ae0c11d2d8f74b
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2 of PR 621 (#566 — the milestone-3 supervision deletion). **needs-work**, 12/12 ACs
satisfied, **2 blockers outside the AC set**, 4 warnings.

Range read: `45f8f24..HEAD`, inheriting patch `fae4fa7dfb84` (round 1's coverage). That range is
dominated by the base merge, so I also read the branch's whole contribution against the **new**
base — `ab0a2d6..HEAD`, 20 files, +916/−2641 — which is where both blockers live. Panel 5/6
usable; `maintainability-reviewer` went dark.

## Round 1's blocker is genuinely closed

`e0d1129a` restored the register: `LEAN_GATE_OBSERVE` carries its own ``NOT IN `SEAM_SCRUB` `` and
`subset-of` sentences again, the six orphaned continuation lines are gone, and
`LEAN_GATE_ANY_TREE`'s tail now names *one* seam above it instead of counting two. `--help`'s
hardcoded range is 279 at this head, which is correct — `set -uo pipefail` is line 280 — and case
`(w)` is a genuinely two-sided guard (it asserts the last header line is present **and** that
`set -uo pipefail` is absent), so both truncation and overrun red. Four of round 1's six warnings
are addressed in the same commit.

## B-1 — the lane-registry deletion left a live consumer behind, and it arrived through the merge

`tools/gate-ablation.sh:95` (main's #614, merged into this branch at `6b236d2`) defaults its
corpus-exclusion input to `$STATE_DIR/lean-lanes.tsv` and reads it in `live_lanes()`. **This PR
deletes everything that writes that file** — `lane-registry.sh`, `lane_register`,
`lane_deregister`, and `LANE_REGISTRY`/`LEAN_LANE_REGISTRY` in `lean-gate.sh` (verified: zero live
matches at this head).

The failure is silent, not loud. `live_lanes()` is `[ -f "$LANES" ] || return 0`, so after this
merges the manifest's automatic in-flight exclusion is permanently empty and the header renders
`from the lane registry: none` — which is indistinguishable from the true-negative case it was
written for. Its own comment states the design: *"Two exclusion sources, and both are needed. The
lane registry is reaped by pid… `--exclude` is the operator's half of that."* Only the operator's
half survives, so an operator cutting a manifest while a lane is in flight now hashes that lane's
still-growing record into the corpus and gets `emit`'s drift refusal instead of an exclusion.

**Invisible to every gate.** It is in no diff a reader looks at — it arrived via the merge's other
parent, so the branch's own diff never shows it, and `G delta` cannot show it either because
`gate-ablation.sh` was unchanged between `45f8f24` and this head. AC-2's identifier grep cannot see
it: the list names `lane-registry.sh`, and this consumer spells the coupling `lean-lanes.tsv`. And
`tools/gate-ablation-selftest.sh` cases `(q)`/`(q2)`/`(q3)` stay green because they write their own
fixture registry via `--lanes`, while case `(r2)` asserts the absent-registry path renders `none` —
so the suite is fully green with the shipped default now unreachable. Same class as PR 606 round 2,
and the same reasoning applies: the obligation to reconcile lands on whoever merges the base in.

Remedy is small and belongs in this PR: either drop the registry source from `gate-ablation.sh`
(the `LANES` default, `live_lanes()`, the `from the lane registry:` header line and cases
`(q)`/`(q3)`), leaving `--exclude` as the single documented source; or keep the seam and state at
the call site that the registry is retired, so the `none` is honest.

## B-2 — round 1's orphaned-prose defect recurs in `cmd_3`, in the same file

`lean-gate.sh:3854-3858`. The deletion removed the `lane_apply_job_ceiling` call and left its
three-line `#526` rationale in place, where it re-parents onto the next live statement:

```
cmd_3() {
  local cmd rc any_verifying=0
  # #526. BEFORE the first lane child of any kind, since the whole point is that every one of
  # them inherits the ceiling — the setup lanes below, the fixed keys, extraLanes, and the
  # render pre-command cmd_3_render runs at the end.
  # #563. Beside the ceiling and before the same first child, for the same inheritance reason.
  lane_apply_selftest_cache
```

This is round 1's B-1 exactly, one level over: the deletion removed the SUBJECT and left the
PREDICATE. A reader now sees "the whole point is that every one of them inherits **the ceiling**"
given as the reason for a call that hands down a **cache directory** — a false statement about
live code — and #563's "Beside the ceiling" has zero antecedent, the same zero-antecedent shape
round 1 blocked on. The distinguishing test round 1 recorded applies in the blocking direction:
the surviving prose is false about a live statement, not merely lost.

It is a blocker on the same basis as round 1's, and it is not gate-lawyering to say so, because
B-1 already costs this round: the two want one commit. `AC-2`'s grep structurally cannot catch it —
the prose spells the concept "the ceiling", never `LEAN_JOB_CEILING`. Found by
`scope-completeness-reviewer` at confidence 95; I confirmed it by reading the site.

## Warnings

- **W-1 — `--ticket-source lane-registry` outlives the registry it names.** The merge imported
  #611, which accepts `argument|lane-branch|lane-registry` (`lean-gate.sh:464-465`), documents it
  in the usage header (`:79`), explains it at `:637`, and pins it in `lean-gate-selftest.sh:6483-6495`
  case `(tk10a)`. `SKILL.md:17` instructs the caller to *"pass the key you derived with
  `--ticket-source lane-branch|lane-registry`"*. Nothing breaks — the gate never reads the registry,
  it only records the label and checks it against the branch — which is why this is a warning and
  not part of B-1. But an operator is told to declare provenance from a machine-global registry this
  repo no longer has, and `:637` describes that registry in the **present tense** (*"`lean-lanes.tsv`
  is one machine-global file every worktree of every lane shares — it can be stale"*). Cheapest
  honest fix is amending `:637` to say the registry is retired and the label is now caller-asserted
  provenance only. Independently found by `scope-completeness-reviewer` (88) and suppressed by
  `complexity-reviewer` (60) as out of its domain.
- **W-2 — AC-4's gate-side half has no committed guard.** The runner side is thoroughly covered
  (`tools/run-selftests-selftest.sh:793-844`: default-on naming with path+cost+reason, `--full` as
  opt-out, the `--exclude`/table dedupe keeping `EXPECTED=DISCOVERED-EXCLUDED` honest, the stale-row
  hard error). No `lean-gate-selftest.sh` case asserts the gate side. I scored AC-4 satisfied
  because `cmd_3` execs the consumer's `test` string through `bash -c` with inherited stdout, so the
  replay is a passthrough rather than a separate behavior — and because I **measured** it rather
  than inferring it (below). Worth one gate-side case in a follow-up, not a re-spend here.
- **W-3 — the PR body's net-bash figure has drifted.** It states 369 added / 2,549 deleted /
  −2,180. Measured at this head against the new base: **383 / 2,566 / −2,183**. The merge and the
  fix commit moved it. AC-7(d) asks only that the body state a strongly-negative delta, so this is
  cosmetic — but a PR-body number is what a reader quotes.
- **W-4 — `mutation-sweep-pr` is green and graded nothing, again.** `PR mode graded NOTHING: all 3
  in-scope guard(s) deferred to nightly, 0 swept (multi-suite union: 1, slow suite: 2)`. Round 2's
  only executable change is `lean-gate.sh`'s `--help` range, no `tools/mutation-catalog.tsv` row
  anchors that line, and every catalog anchor resolves identically at this head and at the base
  (I ran the same anchor check against both trees; the eight rows my BSD-`sed` harness flags are
  flagged identically at `ab0a2d6`, so they are harness artifacts, not drift). So the build's
  scoped re-sweep from round 1 still covers, and no re-sweep is owed this round — but the green
  badge is not what establishes that.

## Coverage gap

`review-toolkit:maintainability-reviewer` went **dark** (died-after-retry: turn-budget, no text on
either attempt). Its domain — comment/prose coherence against live code — is precisely where both
blockers live, so this round's coverage of that dimension came from `scope-completeness-reviewer`
and from my own reading rather than from the reviewer that owns it. Merge readiness below is
assessed without it. The other five returned: security `approve` (0 findings, 2 suppressed),
performance `approve` (0), complexity `approve` (0 findings, 2 suppressed — both deferred to the
correctness domain and both are B-1/W-1), test-coverage `approve` (0), scope-completeness
`approve-with-nits` (4).

## Verification run at this head

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — **clean**.
- `bash scripts/check-lockstep-pairs.sh` — **26 anchors, 0 failed** (22 at round 1; main added
  four). The `seam-scrub subset` row `lean-gate.sh ⊆ preflight.sh` passes, which is what the
  restored register sentence is held to.
- Every `*.json` through `jq empty` — clean.
- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`
  — the **default, bounded** path, which CI never exercises: `71 discovered, 13 excluded, 58 to
  run`, `58 scored, 58 run, 0 served from cache, 0 failed`, rc=0, **26.6s wall**. That one run is
  live evidence for AC-1's reap fit, AC-4's per-suite named deferral, and AC-10's default-on
  application and `--exclude`/table composition.
- CI on the exact reviewed head `6b236d2`: `lint-and-selftests` ✅, `selftests (macos, bash 3.2)`
  ✅, `mutation-sweep-pr` ✅ (see W-4), `release-pr-gates` skipped, `pr-gates` ❌ — failing **only**
  at step 6, `lean chain reconciliation`, on the verdict record this round replaces. Steps 3, 4
  and 5 (frozen files, changelog trailer, pipeline chain) all pass. Expected pre-review.
- The base merge dropped nothing: for all four files main and this branch both touched, every line
  main added at `80276e7..ab0a2d6` is present at this head except three the PR deliberately changed
  (`--help`'s range, the usage string dropping `m3-run`, one `scenario-liveness` line).

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — milestone 3 is a single blocking call, `cmd_3` reached from `run_milestone`'s dispatch | satisfied | The `3) cmd_3 ;;` arm is present in `run_milestone`'s inner `case`; zero `&`/`setsid`/`nohup`/`python3 -c` in the function. Reap fit **measured by me at 26.6s** on this tree, against the ~120s reap. |
| AC-2 — the supervision stratum is gone | satisfied | All 23 identifiers grepped repo-wide: every hit is in `CHANGELOG.md` or `docs/plans/**`, none in live code, selftests, workflows or the register TSVs. `lane-registry.sh` and `lane-registry-selftest.sh` deleted. The `lean-lanes.tsv` consumer of B-1 is outside this AC's enumerated list — carried as a blocker, not scored here. |
| AC-3 — one fix attempt per red, `rc=4` on the 4th preserved | satisfied | `lean-gate-selftest.sh` `(c1)` exit sequence `5554`, `(c2)` the `budget-exhausted` record; composed by `scenario-liveness-selftest.sh` `(lean-budget)` on the same sequence plus "an exhausted milestone records no satisfied line". |
| AC-4 — each deferred suite named on stdout with path and reason; a deferral neither reds nor charges budget nor trips discovered/ran | satisfied | Measured live, 13 `deferred:` lines each carrying path, measured cost and the table's reason; `58 scored, 58 run` with `71 discovered, 13 excluded` — the invariant holds because the exclusion is computed before dispatch; rc=0. Gate-side guard gap carried as W-2. |
| AC-5 — merge boundary untouched; workflows carry only the `--full` additions | satisfied | `scripts/check-lean-chain.sh` and `plugins/dev-pipeline/tools/lean-evidence.sh` carry **no diff** against the base. `.github/workflows/*` carries exactly 4 changed lines, all `--full` insertions at the `run-selftests.sh` call sites (`ci.yml` ×2, `nightly-guards.yml` ×2), and nothing else. `pr-gates` is unedited. |
| AC-6 — scenario-liveness composes the new milestone-3 verdict path; kill/rejoin cases removed | satisfied | Milestone 3 composes into `all` on several verdict paths — `(lean-el-red)`, `(lean-zv-red)`, the zero-verify-lane skip at `:299`, and the infra-death leg at `:1578-1737`; a new leg asserts the evaluation is now bounded inline (*"if the detached runner ever comes back, `sleep 20` is still running here and this check fails"*). The detached-runner drivers are gone — proven by AC-2's clean grep, not by counting cases. −98/+86 on the file. |
| AC-7 — baseline, catalog, lockstep, net delta | satisfied | (a) no `tools/mutation-baseline.tsv` change is owed: no row keys deleted code, and the two `lean-gate.sh` survivors are content-keyed and unmoved. (b) **all seven** catalog rows deleted, verified line-by-line in the diff, including the `lean-gate-m3-pid-outlives` row the build's scoped sweep found. (c) VOID with its reasoning stated; substitute verified — `check-lockstep-pairs.sh` green at 26 anchors. (d) the body states a strongly-negative delta; the figure itself has drifted by 3 lines — W-3. |
| AC-8 — no CI/network read on any milestone-3 path | satisfied | The `lean-gate.sh` diff against the base adds no `gh`, `curl`, `GH_CLI` or `CURL_CLI` line anywhere. |
| AC-9 — `infra_token` prints `m3infra-v3:<n>` from `unclosed_count 3` alone; scheduler body unchanged | satisfied | `lean-gate.sh:2312-2321`: `unclosed="$(unclosed_count 3)"`, negative floored to 0, `printf 'm3infra-v3:%s\n'`; the `"N runner record(s), M live"` diagnostic is gone and the surviving diagnostic is on stderr. `orchestrate-lean.sh`'s whole diff is **one comment line** (`m3infra-v2:0`→`v3:0`) and its comparison at `:785` is `[ "$infra_after" = "$infra_before" ]` — pure string equality, no prefix literal anywhere in the scheduler. D-2 holds. |
| AC-10 — the committed table applied by default, `--full` opts out, stale row is a hard error, `--full`/`--exclude` compose | satisfied | Applied by default in my run with no flag; `--full` is what CI passes and CI is green; `--exclude` composed with the table (the explicitly-excluded suite is also a table row and the count stayed 13, so the dedupe holds). Stale-row hard error covered by `run-selftests-selftest.sh`. |
| AC-11 — `CLAUDE.md`, `docs/testing.md`, `SKILL.md` re-derived | satisfied | `CLAUDE.md:60` carries `--full`; `docs/testing.md`'s headline recipe now reads `--full` with the bounded default explained (round 1's W on that headline is closed); `SKILL.md`'s milestone-3 claim is rewritten and states `bash G 3` runs inline bounded by `tools/selftest-slow-suites.tsv`. **49 lines**, under the 60-line cap. |
| AC-12 — behavior-preserving elsewhere | satisfied | `lint-and-selftests` (which runs `--full`, so it covers all 71 suites including the 13 the bounded check defers) and `selftests (macos, bash 3.2)` are both green on the exact reviewed head. |

## What to do

Both blockers are one commit's work in `lean-gate.sh` and `tools/gate-ablation.sh`. B-1 is the one
that matters: it is a real, silent, permanent degradation of a tool merged the day before this
branch's base advanced, and no gate in this repo will catch it — not the diff, not CI, not
`gate-ablation-selftest.sh`, not AC-2's grep. Fix it here, where it is visible, rather than leaving
it for whoever next cuts an ablation corpus and cannot work out why their manifest excludes
nothing.
