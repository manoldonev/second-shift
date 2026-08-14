# lean review verdict — #528

verdict=needs-work
run_id: review-528-3
session_id: 85b7c491-709b-465d-9108-f9a9fc1e16a1
rounds: 3
pr: #540
reviewed_head: b06d38e484dd2c0144ebcc55a8b7c5a2253a8963
reviewed_patch_id: 599b69a59c15e6f930a92829e49d7ddbb7bca846
inherited_patch_id: 9a22f54e9aadc9f43aa518456af8c1e10141478f
inherited_from_verdict: cf8ede8c149d7d2d31c4b59c4838e9425e178c19
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 3 — PR #540 (#528), `review-528-3`

Range read: `cf8ede8..HEAD` (`b06d38e`), inheriting the coverage of patch `9a22f54e9aad` recorded
by `review-528-2`. Read wider than the range where the delta was misleading: the full branch
(`e583994...HEAD`) went to the panel so the scope gate could score every AC, and the prior record's
findings were read first.

Panel: security, performance, maintainability, complexity, test-coverage, unit-test-mutation,
scope-completeness — 7 selected, **6 returned, 1 dark**. `test-coverage-reviewer` died after its
automatic retry (`turn-budget: agent emitted no text on either attempt`), so the test-coverage
dimension was not reviewed by an agent this round; the finding below is own-probed and the round is
not void.

**Verdict: needs-work.** One blocker. Round 2's carried B2 is **closed and measured** — the
lane is green on this exact head, with a scored result set rather than an everything-deferred
vacuous one. All four ACs score **satisfied**. The blocker is outside the AC set: the new `(l4)`
case cannot fail for the one property AC-4's second half exists to establish.

---

## Blockers

### B5 — `(l4)` cannot fail for a relocation of the warn out of the precheck

The spec's Tests section says of the new case: *"asserted while only the precheck has run, which is
the placement the whole change is about."* It is not. `(l4)` runs the sweep with `--mode full` to
completion and greps the merged output for the warn's text, so a warn emitted from `finish()` — the
placement round 3 correctly identified as *"structurally the one that never arrives"* — passes it
unchanged.

Probed in an isolated worktree at `b06d38e`, scored by case id:

```
baseline                                  (l4) ok / ok        suite rc=0   111s
P1  warn block deleted outright           (l4) FAIL / ok      suite rc=1   110s
P3  same condition, same message text,
    emitted from finish() instead         (l4) ok  / ok       suite rc=0   110s
```

P1 says the case is live for the warn's *existence* and for its conditionality — that half is real
guard, and the control is well built (it holds the fixture, the sleep and the threshold fixed and
changes only the row). P3 says the case is blind to *where the warn is emitted*, which is the entire
delta between this fix and the promise the file header had been making unfulfilled since it was
written. Nothing else covers it: `tools/mutation-sweep.sh` carries a `tools/mutation-exclusions.tsv`
row (the harness never sweeps itself), so no mutant of that line is ever applied and the companion
suite is the only guard there is.

The production behavior is correct — CI's own log has the warn at `15:27:21.229` and `pool:` at
`15:27:21.233`, ahead of the report by 15s. The defect is that the guard would not notice if that
stopped being true.

One assertion closes it, on the output `(l4)` already captures:

```bash
WLN="$(awk '/slow-list drift/{print NR; exit}' <<<"$OUT")"
PLN="$(awk '/\[mutation-sweep\] pool:/{print NR; exit}' <<<"$OUT")"
if [[ -n "$WLN" && -n "$PLN" && $WLN -lt $PLN ]]; then
  ok "the warn precedes the pool, so a job killed by its own ceiling has already said why"
else
  bad "(l4) drift warn did not precede the pool line (warn=$WLN pool=$PLN)"
fi
```

`<<<` rather than a pipe, deliberately: this suite is `set -uo pipefail` and `| grep -q` scores a
match as a miss there. Kill-probe it with the P3 shape above, not by deleting the warn — P1 already
passes and would certify nothing new. If the stdout/stderr interleaving proves non-deterministic
under load, anchor on the report table header (`^guard\tstatus\t`) instead of `pool:`; it is 15
seconds later and the ordering is unambiguous.

Editing either file is free of re-baselining: `tools/mutation-sweep.sh` is excluded, and
`mutation-sweep-selftest.sh` is the killer for nothing else, so no ordinal re-keys.

---

## Round-2 findings: verified closed

**B2 (carried since round 1) — the PR-lane sweep. Closed, and the green is a scored one.**
Run 31814538141, job 94812920907, head `b06d38e` — the commit this record names:

| | round-1/2 heads | this head |
| --- | --- | --- |
| outcome | timeout ×3, no result set | **success, 23s wall** |
| mutants | 50 / 50 / 53 | 25 |
| verdicts | none, ever | 27 |
| survivors | — | 0 |

Not a vacuous everything-deferred green: three guards were genuinely swept
(`fixture-stamp.sh` 4/4, `reap-lean-fixtures.sh` 7/7, `run-selftests.sh` 14/14 = the 25 mutants,
plus 2 distinct precheck runs = the 27 verdicts, which reconciles exactly). Two guards deferred, and
only one of them by this diff: `lean-gate.sh` on the new slow-suites row, `orchestrate-lean.sh` on a
pre-existing multi-suite union. The base is current — `refs/pull/540/merge` has parents
`e583994` + `b06d38e` and `e583994` is `origin/main`'s tip, so the run covers main's newest copy of
everything it read.

The diagnosis behind it holds on re-reading: `killer_bound_for()` prefers the run's own MEASURED
seconds over the TSV, so the 147s row does not change any nightly bound — it changes only the
PR-lane `is_slow` deferral, which is exactly the intended lever and nothing else. The `docs/testing.md`
citation the spec leans on is real and pre-existing (`:711–713`, "not graded on your PR" /
"expect to re-baseline from the nightly"), so the accepted cost is the repo's own stated one rather
than a new argument written to fit.

The round-2 correction is honest: the spec no longer claims the early bail bought the lane anything,
and says the bail is kept because it is free and correct. That is the right way to retire a
superseded diagnosis.

**The spec amendment is an addition, not a retrofit.** The only removal in the hunk is the
over-claiming justification for the round-2 bail, replaced by a narrower true one. AC-4 was added
and met.

---

## Warnings

- **N4 — the warn's aggregate line now prescribes the wrong remedy, and it is live on CI today.**
  Before this diff `warn()` had exactly two call sites, both baseline rows, which is why
  `finish()` reads `"$WARNINGS warning(s) — shrink the baseline."`. The drift warn is a third,
  unrelated class, so today's green run ends with `1 warning(s) — shrink the baseline.` when the
  baseline needs nothing. Same shape as B4 and N1 — an in-tree instruction the diff falsified.
  A separate counter, or rewording to "see above", closes it.
- **N5 — `MUTATION_SWEEP_SLOW_THRESHOLD_S`'s blast radius is wider than the comment it ships with.**
  The comment says it exists so the companion suite can trip the drift warn on a one-second fixture.
  The same variable also gates `is_slow()` (`:436`), which is what the PR lane's
  `deferred-to-nightly` decision reads (`:899`), and what a `--seed` run publishes against
  (`:1817`, `:1825`). Nothing sets it in CI and the selftest scopes it non-exporting, so there is no
  live leak path — but this repo has already been bitten by a gate seam exported into a nested real
  invocation. Say in the comment that it also moves deferral. (Independently found by the
  unit-test-mutation reviewer, confidence 82.)
- **N1/N2/N3 (carried from round 2) are now structurally harder to close, and that is a cost of
  AC-4 rather than a reason to keep carrying them.** Round 3's stated reason for deferring them was
  that `lean-gate.sh`'s survivor ordinals could not be re-keyed at PR time — which the deferral has
  now made permanent, not temporary. A one-sentence comment fix is not going to get cheaper next
  round. Either take them with a nightly re-baseline, or file the follow-up so they stop floating.
- **N6 — the merge subject decides the bump, and the PR title carries no verb.** The branch's own
  `e54d093` is `feat(dev-pipeline):`, but a squash lands the PR title, and this one is prose — which
  derives a **patch**. The diff adds a new tool and a new gate output on `plugins/dev-pipeline/**`;
  CLAUDE.md's honest-verb rule makes that a **minor**. Costs no round to fix (it is not a commit) —
  set the squash subject to `feat(dev-pipeline): …` at merge.

## Suggestions

- `tools/mutation-slow-suites.tsv`'s header still reads *"Membership drift is a report warn"*. That
  line is the promise the fix set out to make true, and the fix deliberately did **not** honor it
  literally — the warn is a precheck warn precisely because a report warn dies with the job. One
  word, and `docs/testing.md` already explains why.
- The warn's text says the suite *"is absent from tools/mutation-slow-suites.tsv"*, but
  `! is_slow "$s"` is also true for a suite that has a row whose recorded seconds sit below the live
  threshold. The remedy printed is right either way; the diagnosis is not. (unit-test-mutation
  reviewer, confidence 80.)
- `(l4)`'s boundary is `sleep 1.2` against a threshold of `1`, so a `-ge`→`-gt` flip on the
  comparison survives whenever the truncated measurement lands on 2. Theoretical only — the file is
  never mutated — but a wider margin would make the case say what it means. (unit-test-mutation
  reviewer, confidence 82.) The case itself was stable across the three full-suite runs above, on a
  loaded machine.

## Verified

- Kill probes, isolated worktree at `b06d38e`, scored by case id: **P1** (warn deleted) → `(l4)`
  first assertion FAIL, suite rc=1. **P3** (warn relocated to `finish()`, condition and text
  unchanged) → `(l4)` both assertions ok, suite rc=0, and the case set is byte-identical to the
  baseline's. Baseline copy green (rc=0, 111s).
- `mutation-sweep-pr` **success** on the reviewed head, against a merge ref whose base parent is
  `origin/main`'s current tip. `lint-and-selftests` (ubuntu) and `selftests (macos, bash 3.2)` both
  **pass** on the same head.
- `pr-gates` red is the expected pre-review state and fails on **one** arm only — *lean chain
  reconciliation*; the frozen-files, changelog-trailer and pipeline-chain arms all pass.
- The report arithmetic reconciles: 25 mutants + 2 distinct prechecks = the 27 verdicts the run
  claims, so no guard was silently dropped from the pool.
- Scope-completeness gate: **PASS** — every AC implemented, nothing left unsatisfied.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** — orphans reaped, age-and-ownership guarded, never deletes a live lane's fixture | **satisfied** | Untouched by this round's delta; inherited from `review-528-2`'s patch `9a22f54e9aad`, where the shared-expression fix and both default floors were kill-probed live. `tools/reap-lean-fixtures.sh` and `tools/fixture-stamp.sh` are both swept green on this head (7/7 and 4/4, 0 survivors), which is fresh evidence rather than inherited. |
| **AC-2** — `append_satisfied` + `heal_progress_run_id` atomic, no blocking waiter | **satisfied** | Untouched by the delta; inherited. `(rc4a)` was probed live in round 2 and the append half stays append-only, so `progress_token`'s soundness argument is true rather than standing while false. N1 remains an over-claiming comment on the orphan sweep, carried. |
| **AC-3** — resolved config path announced | **satisfied** | Untouched by the delta; inherited, with `(rc5)`/`(rc6)`/`(rc5a)` probed across rounds 1 and 2. |
| **AC-4** — the PR-lane sweep completes inside its budget, by the rule the repo already has | **satisfied** | Met by its letter and measured on CI at this head: 23s, 27 verdicts, 0 survivors, not a deferred-everything green. The row is the repo's own documented lever, the cited `docs/testing.md` consequence is real and pre-existing, and the precheck placement of the drift warn genuinely ships and genuinely fires ahead of the pool. B5 is a hole in the guard for that placement, not a gap in the implementation. |
