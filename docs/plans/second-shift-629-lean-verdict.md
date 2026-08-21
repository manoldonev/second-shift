# lean review verdict — #629

verdict=approve
run_id: review-629-1
session_id: f79fbcf7-1262-4eb4-a6bf-e1769236ae5e
rounds: 1
pr: #632
reviewed_head: d224e861530b8e1bc8636a247b1c18b1b58aea9c
reviewed_patch_id: 5433e7b5675fd3e706c5e45cb4645bfdb8b9047b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 1, full branch range `9f2b5d00..d224e861` (11 files, +885/−13). Six reviewers ran; none went
dark. **No blockers.** The diff does what its spec says: `run-selftests.sh` measures and judges
nothing, `check-sweep-bound.sh` judges and is the only thing that reds, and the two are wired to
exactly one execution surface.

What raises this above a fixture-green review is that the enforcing lane already ran it. Three
`workflow_dispatch` runs of `nightly-guards.yml` on this branch executed the `un-deferred sweep
bound` step end-to-end and passed, printing real sums over the real tree — `96s over 60 suite(s)`
and `108s over 60 suite(s)`. The committed baseline of 106s is the mean of the three samples
(113/96/108) and the 20% allowance is about twice their observed spread, so AC-2's arithmetic is
verified against the lane it describes rather than against a fixture. The final commit changes only
the baseline file and one spec line, so the 108s measurement still describes this head: 108s against
a 127s limit.

Two claims I did not take on the diff's word, and probed instead:

- **The emitter↔parser contract is genuinely held.** `check-sweep-bound-selftest.sh` builds its logs
  with a hand-written `frame()` helper, so it cannot see the emitter move. Probed in an isolated
  worktree: swapping the frame line to `::group::pass <suite> <secs>` leaves that suite at **0
  failures** — and lights up `run-selftests-selftest.sh` with **5**, including the last-token
  assertion. The contract is covered across the pair, which is correct decomposition, not a mirror.
- **`catalog::selftest-elapsed-subsecond-floor` kills.** The PR-lane sweep never graded it (see
  warning 2). Applied by hand: `#629/AC-1: the instant suite was not charged exactly 1s` fails. Row
  is sound.

Both `tools/mutation-catalog.tsv` anchors resolve under `sed -E` — the form `mutation-sweep.sh`
applies — so neither row is drifted.

## Strengths

- **The baseline is measured on the lane that enforces it, and says so.** `selftest-sweep-baseline.tsv`
  records the date, the lane, the tree, the un-deferred count and all three raw samples, plus the
  macOS workstation figure "for contrast". A later reader can tell a real red from a re-measurement
  on other hardware without archaeology — which is the whole difference between a bound and a
  constant nobody can re-derive.
- **The allowance states what it cannot see.** Rather than presenting 20% as precision, both the
  baseline file and `docs/testing.md` name the cost: the aggregate arm resolves at two to three
  threshold-crossing suites, not one, and a single arrival is the per-suite warning's job. That is
  the honest form of a tolerance.
- **Case (f) is a real negative control.** `run-selftests-selftest.sh` nests runners over throwaway
  trees, so every honest nightly log carries `::group::` lines naming suites that exist in no repo.
  A checker reading those would red on its own undiscovered-suite arm every night and be baselined
  away within a week. The depth-0 walk is the fix and case (f) pins it against case (e).
- **Three of the five mutation survivors were closed by deleting redundancy, not by adding
  assertions** — the replay walk carrying its verdict twice, the duplicate-frame fixture that was
  defective in two ways at once, the untested default `--root` the nightly lane actually relies on.
  A guard that carries its verdict twice is unkillable by construction; dropping the second
  mechanism is the right repair.
- **The elapsed field was inserted, not appended.** `::group::pass  3s  suite` keeps the suite as the
  last whitespace-separated token, which the existing contiguity walk depends on. Appending `(3s)`
  would have made `(3s)` the suite name and broken leak detection silently, with every case green.

## Critical (must fix before merge)

None.

## Warnings (should fix)

- **[Scope] `tools/check-sweep-bound.sh:207` — AC-2's red names the largest *contributors*; issue
  #629 says the largest *growers*.** The committed spec says "contributors" and justifies the
  substitution in its Design notes, and it was written in the branch's first commit — this is not a
  spec amended after the fact to match a diff. The substitution is also forced by the issue's own
  data contract: the baseline record is the aggregate (`baseline-seconds` + `allowance-percent`),
  so no per-suite history exists to rank growth against, and "growers" is unsatisfiable without
  adding one. The intent — the red tells the reader which suites carry the sum, alongside sum,
  baseline, drift and both remedies — is met. Raised so the substitution is confirmed rather than
  passing silently, not because the diff should change.

- **[Mutation coverage] The PR lane graded one of the two new catalog rows, not both.** The
  `mutation-sweep-pr` log for this branch reads
  `tools/run-selftests.sh	deferred-to-nightly	tools/run-selftests-selftest.sh	0	0	0`
  — the paired suite is on `tools/mutation-slow-suites.tsv` (bumped 8s → 12s here), which is at or
  above that table's 5s threshold, so `catalog::selftest-elapsed-subsecond-floor` was applied zero
  times, killed zero times and reported green. The PR body's `applied=10 killed=10 survived=0`
  covers `tools/check-sweep-bound.sh` alone; read beside "Two `mutation-catalog.tsv` rows" it
  suggests both were graded. **The deferral is pre-existing** — the row was already ≥5s before this
  diff — and the nightly wholesale sweep grades it within a day, so this is not a defect introduced
  here. I closed the gap by hand rather than leaving it to the nightly: applied, and killed. No
  change requested; the PR narrative is what is slightly ahead of the evidence.

## Suggestions (consider)

- **`?s` is never fed through the checker.** A worker that dies without writing a verdict emits
  `::group::FAIL  ?s  <suite> (rc=125)`. `check-sweep-bound-selftest.sh`'s AC-4 table covers the `-`
  (cached) field and an absent field, but not `?s`; `run-selftests-selftest.sh` asserts `(rc=125)`
  and not the literal token. Both take the same `^[0-9]+s$` mismatch → `die` path, and rc=125 reds
  the sweep step so the check never runs on that lane, which is why this is a suggestion. One more
  row in the existing (e) table would close it for free.

- **`awk`'s negative-depth arm emits two marker rows, not one.** `exit` inside an awk main rule still
  runs `END`, so a stray `::endgroup::` produces `!\tnegative-depth\t-` followed by
  `!\tunbalanced-framing\t-`. The reader dies on the first, so the outcome and the message are both
  correct — noted only because the comment above it reads as though `exit` ends the program.

## Plan Compliance

Implementation matches the committed spec. Three deltas against the GitHub issue, all
**spec-declared and widening or neutral**, none reducing scope:

- The spec adds **AC-7** (`docs/testing.md` states the guard). The issue has no such AC. Delivered.
- The spec's **AC-4** adds a fourth fail-closed arm the issue does not list — *incomplete over the
  un-deferred set*. Delivered, and it is the arm case (j) exercises.
- The spec's **AC-3** says "the table's declared threshold" where the issue says "the table's 9s
  threshold". The threshold moved from prose into a `# threshold-seconds	9` directive in the same
  file; the **value is unchanged at 9**, so the issue's "Out: the table's membership rule and its 9s
  threshold" is respected — this is a representation change with one home instead of two copies, and
  the runner's existing comment arm skips the directive.

No scope creep. Everything in the issue's "Out" list stays out: no PR-lane wiring, no cache-inputs
change, no mid-flight scheduling decision.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — elapsed on the frame line, exit-code contract unchanged | **satisfied** | `run-selftests-selftest.sh`'s `#629/AC-1` block: a red suite still reds, all 3 frames carry elapsed, the sub-second suite is charged exactly `1s`, a 2s suite reports ≥2s, the FAIL frame keeps both elapsed and `(rc=1)`, and the suite path is still the frame's last token. Live on CI: `pass  2s  tools/check-sweep-bound-selftest.sh`. Probed: an emitter shape swap reds this block 5 ways. |
| AC-2 — un-deferred serial sum vs committed baseline; red names sum, baseline, drift, contributors, both remedies | **satisfied** | Selftest (a) inside allowance, (b) breach with all five elements asserted by name, (c) both boundary directions (33s inside 30s+10%, 34s outside). Verified live on the enforcing lane: `✓ un-deferred serial sum 108s over 60 suite(s) — baseline 113s, allowance 15% (limit 129s), drift -4%`. Comparison is cross-multiplied, so the boundary is inclusive in both directions on integer bash. |
| AC-3 — per-suite overage warns by name and exits 0 | **satisfied** | Selftest (d), both arms: a suite at the threshold is named and exits 0; a suite under it warns about nothing. Case (i) drives the **live** table, so the directive going missing (exit 2) or the threshold moving (warning count changes) both red. Live: `0 per-suite warning(s)`. |
| AC-4 — absent, unparseable, incomplete, or undiscovered input all red | **satisfied** | Selftest (e) is table-driven across 8 arms: no `--log`, absent file, `-` (cached/unmeasured) field, pre-emitter frame with no elapsed, undiscovered suite, un-deferred suite with no timing, unbalanced framing, one suite framed twice. Case (f) is the negative control — nested frames inside a suite's own output are not read as timings. Case (k) covers `TMPDIR` unset, which is the path the ubuntu lane actually takes. |
| AC-5 — one execution surface, and nowhere else | **satisfied** | Selftest (h) greps `.github/workflows/*.yml` for `check-sweep-bound.sh` and requires the result to be exactly `nightly-guards.yml`. Confirmed independently against the tree. The macOS twin is deliberately excluded and the diff says why: one committed number cannot describe two machine classes. Case (j) pins the default `--root` the wiring relies on. |
| AC-6 — mutation obligations land in this diff | **satisfied** | Two `mutation-catalog.tsv` rows; both anchors verified to resolve under `sed -E`. `catalog::sweep-bound-nested-frames-read` killed on the PR lane (early exit at the first `FAIL:`). `catalog::selftest-elapsed-subsecond-floor` was `deferred-to-nightly` on the PR lane (warning 2) — applied by hand here, and killed. Five diff-scoped survivors closed, **none by baselining**, three by removing redundancy rather than adding assertions. |
| AC-7 — `docs/testing.md` states what the guard reads, where it runs, and what a re-baseline is | **satisfied** | New "The bound on what the table did *not* defer" section: the four-row behavior table, the warning-vs-red split with its reasoning, the nightly-only and single-lane rationale, the sub-second floor, and the re-baseline-is-a-reviewed-commit rule. `tools/selftest-slow-suites.tsv`'s header no longer describes the membership rule as unenforced. |

## CI

`selftests (macos, bash 3.2)` was **red on the first run** — `lean-gate-selftest.sh (rc=1)`, one case:
`(if5b) process group NNNNN still has a live member after the group kill — did milestone 3 detach?`

**Classified as a flake, not a regression, on three independent pieces of evidence:**

1. `lean-gate-selftest.sh` is **not in this diff**, and nothing this diff touches reaches that case —
   its lane command is a literal `sleep 20` from a fixture config, and `run-selftests.sh` is not on
   its path.
2. `main`'s CI at **the exact base commit** (`9f2b5d00`, run 32482107518) passed that job.
3. Re-running the job on **this exact head** passed. `lint-and-selftests` and `mutation-sweep-pr` are
   green on both runs.

The case reaps with a bounded 10s window (two 50 × 0.1s loops) after a `kill -9` on the process
group, and the suite ran at **291s against a 141s standalone measurement** — a runner under roughly
2× contention. That is the shape of a timing-bounded assertion losing a race, and it is worth a
datapoint for whoever owns `#566`/`#621`: the window is the only thing between that case and an
intermittent red. Out of scope for this PR.

`pr-gates` is red for the one expected reason and no other: `✗ no committed verdict record (a file
named *-629-lean-verdict.md)`. This record is that file.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass (with nits) | 2 | 85–88 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(`apps/web/**/*.{tsx,jsx}`) — this is a shell/CI/docs diff.

**Ready to merge?** Yes

**Reasoning:** All seven ACs satisfied, no blockers from any of six reviewers, and the guard's
arithmetic is verified against real output from the lane that enforces it rather than against
fixtures alone. The two warnings are a spec-vs-issue wording substitution the spec justified up
front and that the issue's own data contract forces, and a PR-lane mutation deferral that predates
this diff and that I closed by hand. The one red CI lane is a flake in a suite this diff does not
touch, green on re-run and green on `main` at the same base.
