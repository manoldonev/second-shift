# lean review verdict — #528

verdict=approve
run_id: review-528-4
session_id: 1ee8ee43-762c-4c67-a4f5-32bbaf3c2c8c
rounds: 4
pr: #540
reviewed_head: 836f6bc0ffd2414d9ab7f764f6f197801ede1f91
reviewed_patch_id: 2ddc709cfbf5d62f6b6daf7c72eaa7b378d68136
inherited_patch_id: 599b69a59c15e6f930a92829e49d7ddbb7bca846
inherited_from_verdict: 6c7d2c18a66ffead831b5132f950bc38d116ce08
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 4 — PR #540 (#528), `review-528-4`

Range read: `6c7d2c1..HEAD` (`836f6bc`), inheriting the coverage of patch `599b69a59c15` recorded
by `review-528-3`. Read wider than the range: the full branch (`e583994...HEAD`) went to the panel
so the scope gate could score every AC, and the prior record's findings were read first.

Panel: security, performance, maintainability, complexity, test-coverage, unit-test-mutation,
scope-completeness — **7 selected, 7 returned, 0 dark**. a11y + design-fidelity not routed: no
changed path matched the web-component surface (this repo configures none, and the diff is shell
and markdown).

**Verdict: approve.** No blockers. All four ACs **satisfied**. Round 3's single blocker (B5) is
closed and independently certified by a relocation probe, not a deletion probe. One warning is
new and real — the mirror half of the summary-class split is guarded by nothing — and it is scored
a warning rather than a blocker for the reason set out under W1.

---

## Round-3 findings: verified closed

**B5 — `(l4)` could not fail for a relocation of the warn out of the precheck. CLOSED.**
Certified by re-running round 3's own probe verbatim, in an isolated worktree at `836f6bc`, scored
by case id:

```
A  baseline                                    (l4) existence ok / placement ok / summary ok / control ok   rc=0
B  warn computed in the precheck, EMITTED
   from finish() — text and condition
   byte-identical                              (l4) existence ok / placement FAIL / summary ok / control ok  rc=1
      FAIL (l4) drift warn did not precede the pool line (warn=6 pool=1)
```

The existence assertion staying **ok** under B is what proves the probe was a relocation and not a
deletion — the distinction the whole finding rested on. Only the placement assertion moved, so the
two new assertions are orthogonal rather than redundant.

The assertion is also sound for a stronger reason than the comment beside it gives. The comment
argues from stream direction (stderr cannot be buffered ahead of stdout). It does not need to: the
drift warn (`tools/mutation-sweep.sh:1684`) and the `pool:` line (`:1758`) are both emitted by the
**main process**, sequentially, with the precheck loop entirely ahead of the pool manifest. Ordering
is deterministic, not merely probable, so the case cannot flake on a loaded runner.

**N4 — the aggregate line prescribed the wrong remedy. CLOSED**, by classifying at the call site
(`warn_baseline`) rather than by rewording. The classification is **complete**: an exhaustive grep
of `tools/mutation-sweep.sh` finds exactly three `warn` call sites — `:1684` (slow-list drift,
correctly generic) and `:1866`/`:1882` (both baseline-remedy, both converted). Nothing was missed
in either direction.

**N5 — `MUTATION_SWEEP_SLOW_THRESHOLD_S`'s blast radius. CLOSED**; the comment now says it moves
the PR lane's deferral set and names the export-leak precedent.

**N6 — the bump verb. CLOSED**; the PR title is now `feat(dev-pipeline): …`, so the squash subject
derives a minor.

**N1/N2/N3 — carried since round 2. OWNED.** Filed as **#543**, open, with all three findings
restated in full and four acceptance criteria including "any ordinals re-keyed by the above are
re-baselined in the same change, from the nightly sweep rather than the PR lane". This is what
round 3 asked for — file the follow-up or take the re-baseline — and it is an addition to the spec,
not a retrofit: the only removals in the spec hunk are prettier's `*x*`→`_x_` reflow and the
replacement of the `(l4)` description that B5 falsified.

**Suggestions 1 and 2 — CLOSED.** The slow-list header now reads "PRECHECK warn" and says why; the
warn text now reads "does not record it at or above that bar", which matches `is_slow()`'s actual
predicate (`suite_seconds "$1" >= SLOW_THRESHOLD_S`, true for a below-bar row as well as an absent
one).

---

## Warnings

### W1 — the baseline arm of the new summary is guarded by nothing, and the regression it admits is N4 itself

`finish()` now branches on `BL_WARNINGS`. The `BL_WARNINGS == 0` arm is asserted by `(l4)`'s new
third assertion. The `BL_WARNINGS > 0` arm — `"$WARNINGS warning(s), $BL_WARNINGS of them stale
baseline row(s) — shrink the baseline."` — is asserted by nothing, and neither is
`warn_baseline()`'s increment.

Confirmed by execution, not by reading. Third probe, same isolated-worktree method:

```
C  warn_baseline() { warn "$@"; }   (the BL_WARNINGS increment dropped)
   -> mutation-sweep-selftest.sh: ALL CASES PASSED, rc=0
```

Found independently by `unit-test-mutation-reviewer` (confidence 90) from a cold read, which adds
the sharper version: case `(d)` **already puts a run into `WARNINGS=2 BL_WARNINGS=2`** via both
converted call sites, and asserts only the individual `WARN:` substrings (`now KILLED`,
`no longer resolves`) — which `warn()` prints regardless of the bookkeeping. The literals
`stale baseline row` and `not one of them` appear nowhere in the suite. So reverting *one* call
site, dropping the increment, or garbling `:752`'s message are all silent, and the consequence runs
in the harmful direction: a run with stale baseline rows telling the operator "the baseline is not
one of them".

This is `tools/mutation-sweep.sh`, which carries a `tools/mutation-exclusions.tsv` row — the harness
never sweeps itself — so no mutant will ever second-guess this suite. As in round 3, the companion
suite is the whole net.

**Why a warning and not a blocker.** Round 3 scored N4 — the *live, shipping* instance of this exact
defect class — a warning. A coverage gap admitting a warning-class regression cannot outrank the
warning it mirrors. The line is advisory `info()` output: `warn()` never touches `RC`, so no verdict
path, lane outcome or merge decision reads it. And the round's stated guard is live and its spec
describes it accurately — the Tests section claims only that the third assertion "pins that the
warning summary does not prescribe the baseline for a warn that is not a baseline row", which is
exactly what it does. That absence of over-claim is what separates this from B5, where the spec
asserted a coverage the case did not have.

**Do not take it in this PR.** The fix is one grep on output case `(d)` already captures and costs
no re-baselining (`mutation-sweep-selftest.sh` is the killer for no other guard; `mutation-sweep.sh`
is excluded). But any commit here voids this record and spends a fifth round on a three-line guard
for a prose line. It belongs on the next touch of this file, or alongside #543.

### W2 — the PR body has no account of rounds 3 and 4

The body carries "Review round 1" and "Review round 2" sections and folds round 3's work into AC-4,
but nothing describes round 3's or round 4's changes as rounds, and its closing line still reads
"10 probes across three rounds" — now four rounds and twelve probes. The committed spec is current,
so the evidence chain is intact; this is what a human opening the PR reads. Costs no round to fix
(it is not a commit).

## Suggestions

- `(l4)`'s boundary is still `sleep 1.2` against a threshold of 1 (carried from round 3). The
  existence assertion is safe either way — elapsed is 1 or 2, both `-ge 1` — and the file is never
  mutated, so this stays theoretical. The round did fix the real half of it: the `sleep` is now
  committed, so the case measures its own fixture rather than incidental setup overhead.

## Verified

- **Kill probes**, isolated worktrees at `836f6bc`, scored by case id — A (baseline) rc=0 all pass;
  B (relocation) rc=1, placement assertion alone red; C (classification dropped) rc=0, all pass.
- **Classification completeness**: three `warn` call sites in `tools/mutation-sweep.sh`, all in the
  correct class. `finish()`'s branching is total over `WARNINGS`/`BL_WARNINGS` and correct in merge
  and shard modes, where the baseline warns are unreachable.
- **No re-baselining owed**: `tools/mutation-sweep.sh` is mutation-excluded and
  `tools/mutation-sweep-selftest.sh` appears in no `mutation-pair-map.tsv` row as another guard's
  killer, and in no `mutation-baseline.tsv` / `mutation-catalog.tsv` row.
- **CI on this exact head** (run 31819146357): `lint-and-selftests` **pass**,
  `selftests (macos, bash 3.2)` **pass**, `mutation-sweep-pr` **pass**. `pr-gates` red on **one**
  arm only — *lean chain reconciliation*, the expected pre-review state; frozen-files, changelog
  trailer and pipeline-chain all pass.
- **The sweep green is a scored one, by arithmetic**: `fixture-stamp.sh` 4/4 + `reap-lean-fixtures.sh`
  7/7 + `run-selftests.sh` 14/14 = the 25 mutants, plus 2 distinct prechecks = the 27 verdicts the
  run claims. 0 survivors, 23s wall. Two guards deferred, only one of them by this branch.
- **Base is current**: `refs/pull/540/merge` has parents `e583994` + `836f6bc`, and `e583994` is
  `origin/main`'s tip, so the run covers main's newest copy of everything it read.
- `shellcheck -e SC1091,SC2015,SC2181` clean on both changed scripts.
- Scope-completeness gate: **PASS**.

One note on the drift warn's own liveness, for the record rather than as a finding: this head's
CI sweep emitted **no** warn, because `run-selftests-selftest.sh`'s precheck measured under the 5s
bar this time (round 3's run had it at 7s). The suite sits on the boundary, so the spec's "one warn
is left standing, deliberately" is true of some runs and not others. Advisory either way, and the
guard is `(l4)`, not the live run.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** — orphans reaped, age-and-ownership guarded, never deletes a live lane's fixture | **satisfied** | Untouched by this round's delta; inherited from patch `599b69a59c15`, where the shared-expression fix and both default floors were kill-probed. Fresh evidence on this head rather than inherited: `fixture-stamp.sh` 4/4 and `reap-lean-fixtures.sh` 7/7, 0 survivors. |
| **AC-2** — `append_satisfied` + `heal_progress_run_id` atomic, no blocking waiter | **satisfied** | Untouched by the delta; inherited. `append_satisfied` stays append-only, so `progress_token()`'s soundness argument is true rather than standing while false. N1's over-claiming comment is now owned by #543. |
| **AC-3** — resolved config path announced | **satisfied** | Untouched by the delta; inherited, with `(rc5)`/`(rc5a)`/`(rc6)` probed in earlier rounds. |
| **AC-4** — the PR-lane sweep completes inside its budget, by the rule the repo already has | **satisfied** | Green and scored on this head (23s, 27 verdicts, 0 survivors, not the deferred-everything kind). This round closes the guard gap in its second half: the drift warn's **precheck placement** is now assertable and was proved to fail on relocation. W1 is a hole in the guard for a neighboring branch, not a gap in this AC. |
