# lean review verdict — #670

verdict=approve
run_id: review-670-2
session_id: 3795abca-c230-43cf-a7a2-bd58114f464e
rounds: 2
pr: #728
reviewed_head: 13af5e2d83ad5c5ecbfaec98b1e437842c638fe3
reviewed_patch_id: ecbef971a7d5f3809985519a86c7fd524f3df6d7
inherited_patch_id: e6c645925724127402db1d9c00c8441c42ad5d4d
inherited_from_verdict: 0f45b3f7fa15c14c3057d34730f061357e60bbf8
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2. Delta `0f45b3f..HEAD` — `docs/plans/second-shift-670-lean.md`, `docs/testing.md`,
`lean-gate-selftest.sh`, `scenario-liveness-selftest.sh` — inheriting the coverage of patch
`e6c645925724` (round 1, `51ba24e`). `lean-gate.sh` is byte-identical to the tree round 1
approved on substance, so the production fix is inherited; everything read this round is the
evidence round 1 blocked on. Read wider than the delta anyway: the reviewer panel ran over the
whole branch `ff3f6f8..13af5e2`, and AC-4's and AC-7's oracles were re-derived at head rather
than inherited.

Both round-1 blockers are fixed, and both fixes were verified by building the world each
assertion names and watching it red. Both round-1 warnings are fixed and likewise measured.
No blockers. Verdict: **approve**.

## Findings

| # | Sev | Site | Finding |
| --- | --- | --- | --- |
| N1 | note | `scenario-liveness-selftest.sh:2281` | `co_mg_all` counts `--state all` by bare substring where its sibling classifies by argv shape. Measured attributable at head; structurally the weaker half of the same lesson the fix commit states. |
| N2 | note | `docs/testing.md:893` | The inserted paragraph left the pre-existing sentence un-rewrapped mid-line — 153 chars against the file's ~98-column wrap. |
| N3 | note (pre-existing, outside the delta) | `scripts/gate-buckets.tsv:138` | Describes `resolve_open_pr` as "either found exactly one open PR for this branch or it did not", which is loose against open-or-merged. Unchanged by this PR and not matched by AC-4's oracle. |

### Round-1 blockers, re-measured

**B1 — the non-vacuity assertion that passed in the world it named. CLOSED.**
The `grep -q -- '--state open'` is gone, replaced by two cases that each fail in their own
world. Both mutants were run, each in its own detached worktree cut from `13af5e2`:

- **M1, restore `cmd_mark`'s pre-#670 `--state open` resolver** (10 lines back into
  `lean-gate.sh`, `resolve_open_pr` call replaced by the original `PR_FILE`/`pr list --state
  open` block): `[scenario-liveness] summary: 75 passed, 2 failed`.
  `(lean-closeout-merged-live)` reds **in its own vocabulary** —
  `--state all=4 gate-side --state open=2 scheduler --state open --jq=1, expected >=1/0/>=1`.
  That is the sentence a reader can act on; round 1's version of this assertion stayed green
  under the same mutant.
- **M3, delete the fake's whole `*"--state open"*` arm** — verbatim the mutant that left round
  1's suite at 76 passed, 0 failed: `76 passed, 1 failed`.
  `(lean-closeout-merged-fixture)` reds with `--state open returned length=1 (want 0)`.

The argv classification is sound on the half that does the killing. `awk '/pr list/ &&
/--state open/ && !/--jq/'` separates a gate-side narrowing from the scheduler's
`resolve_pr` (`orchestrate-lean.sh:731`), which always carries `--jq`; the restored resolver
adds two lines that carry none, and that is what the zero counts.

The fixture case is not shadowed by an earlier arm — the trap round 1 fell into. The fake's
`pr` arms are ordered `--json number,state` → `--jq` → `--state open` → catch-all, and the
probe's argv is `pr list --head B --state open --json number,url,body,isDraft,state --limit 20`:
it carries neither `--json number,state` nor `--jq`, so it reaches the third arm. That field
list is also **exactly** `resolve_open_pr`'s own (`lean-gate.sh:4971`), so the case pins the arm
with the shape the consumer actually sends. It sets `RE_GH_LOG=/dev/null`, so it cannot
contaminate the log the case above reads.

**B2 — AC-4's oracle returning 1 at its own head. CLOSED.**
Run verbatim from the worktree root: **0 matches at `13af5e2`**, **7 at `ff3f6f8`** — one per
row of the AC's table. Fixed on the doc side, which is the right side: `docs/testing.md`'s
declined-coupling row now states the falsified premise in indirect speech and says in the row
itself why. Widening the exclusion list to `':!docs/testing.md'` would have bought the same
zero while blinding a live doc to a real regression, and the spec now records that as the
reason rather than leaving it implicit.

A deliberately broader sweep at head (`open pr|still open|pr is still open|open-only|must be
open` intersected with `milestone|close-out|unclaim|claimed|exit`, over the same three
exclusions) turns up no eighth live assertion. The one loose phrase it surfaces is N3, which
this PR does not touch.

### Round-1 warnings, re-measured

**W1 — `(pm7c)` could not fail. CLOSED, and by the cheaper of the two remedies.**
The case now runs as the already-attested `sess-mark-1` instead of `sess-mark-670`, so
`mark`'s build-session guard no longer refuses two steps in front of the subject.
**M2, delete the merged early-return from `cmd_mark`**: `(pm7c)` now reds with the marker body
in the spool — `expected NO write to a merged PR, spool=<!-- dev-pipeline -->` — where it
passed under the same mutant at round 1. `(pm7b)` reds alongside it, as expected. At head
`(pm7)`, `(pm7b)`, `(pm7c)` and `(ms11)` all pass, so reusing an attested id rather than
attesting a fifth one keeps `(ms11)`'s `| session |` row count at 3, exactly as the new comment
claims.

**W2 — AC-7 naming a suite that exists in no tree. CLOSED.** The AC now carries a runnable
re-derivation instead of a citation. Run verbatim: **26 rows, zero drift** — no `DRIFT:` line.
It applies each sed under `sed -E`, which is how `tools/mutation-sweep.sh:1852` applies them;
plain BSD `sed` would false-red four of them, and the AC now names the reason it uses `-E`.

**N1 (round 1) — the `Guard-mass:` trailer miscount.** Corrected on `13af5e2`'s own trailer
rather than by rebasing `51ba24e`, which would have moved `reviewed_head` out from under the
committed round-1 record. Right call.

### N1 — the `--state all` half is still counted by substring

`co_mg_all="$(grep -cF -e '--state all' "$CO_GH_LOG")"`. The composed lane's log carries several
components' calls — that is the whole lesson B1 taught, and the fix commit states it — and the
`--state open` half now honors it while this half does not. `cmd_entry_sweep`
(`lean-gate.sh:2516`) also emits `--state all`, and the leg's session fake does call
`g entry "$CO_KEY"`, so the contamination is reachable in principle.

**Measured, not assumed.** I instrumented a copy of the leg at head to copy `CO_GH_LOG` out
before teardown and ran it (77 passed, 0 failed). Every `--state` line in the composed lane:

```
   3  pr list --head B --state all --json number,url,body,isDraft,state --limit 20
   1  pr list --head B --state open --json number --jq .[].number
```

All three `--state all` lines are `resolve_open_pr`'s exact argv; the entry sweep's
`--json number,state` shape does not appear at all in this fixture. So the conjunct is
attributable today, and the world its pass message names as the failure — a `--pr-file`
shortcut — is unreachable by construction, since the leg passes `--pr-file` nowhere (verified:
the only two occurrences in the composed path are the comment and the pass string themselves).

That is why this is a note and not a warning: nothing reachable hides behind it. It is worth
writing down because a later fixture that gives the sweep a worktree to consider would add a
`--state all` line and the count would stop attributing, silently — one `&& !/--json number,state/`
away from being classified the way its sibling already is.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cmd_mark` resolves through `resolve_open_pr`; merged PR returns 0 and posts nothing. `(pm7b)`/`(pm7c)`/`(k7b)` drive the `GH=<stub>` seam with no `--pr-file`. M2 reds `(pm7c)`; round 1 measured M1 reding `(k7b)`/`(pm7)`/`(pm7b)`. |
| AC-2 | satisfied | The leg exists and reaches `\| milestone-5 \| satisfied`. (1) no `--pr-file` in the composed path — verified by reading; resolution crosses `pr list --state all` (3 calls, measured). (2) gate-side `--state open` = 0 at head, = 2 under M1, which reds the case. (3) `(lean-closeout-merged-fixture)` probes the arm directly, is labelled fixture-capability in both its name and its comment, and is killed by M3. |
| AC-3 | satisfied | `(k7)` now reads "resolve_open_pr accepts a MERGED PR through the --pr-file seam" — the seam only. The reachability claim moved to `(k7b)`. |
| AC-4 | satisfied | Oracle run verbatim: 0 at head, 7 at `ff3f6f8`. Broader sweep finds no eighth live site. |
| AC-5 | satisfied | `docs/testing.md`'s *Couplings considered and declined* carries the row: what is duplicated across the seven sites, why `verbatim` LOCKSTEP is wrong for seven arguments aimed at seven readers, why the #674 derive-it shape does not fit either, and the three frozen-record classes named as deliberate exclusions. |
| AC-6 | satisfied | `Changelog:` on `51ba24e` (grep-anywhere, survives the squash); verb `fix:` on both fix commits. CI's `changelog trailer guard`, `frozen files guard` and `guard budget guard` steps all green at head. |
| AC-7 | satisfied | 26 rows, zero drift, re-derived under `sed -E` + `cmp -s`. |

`Design: none` — the spec disarms design fidelity, and the disarm is justified: this repo's
config declares no `design` key at all, so there is no provider to render against. Scored
`not-applicable`, not skipped.

## Verification

**CI, cited rather than re-run** where the command and head match this review
(`13af5e2`, run 33328591971):

- `lint-and-selftests` — **pass**, 4m37s. `scenario-liveness` 77 passed / 0 failed;
  `lean-gate-selftest.sh` `pass 159s`.
- `selftests (macos, bash 3.2)` — **pass**, 6m54s. Same two suites green — which is the lane
  that matters for the new `[[ ]]`/`awk`/`grep -cF` constructs.
- `mutation-sweep-pr` — pass.
- `pr-gates` — red on **`lean chain reconciliation` alone**; every other step green. That is
  the expected pre-approval state, not a finding.

**Run locally at head and against each mutant**, each in its own detached worktree cut from
`13af5e2` inside the repo's own worktrees dir, with `CLAUDE_CODE_SESSION_ID`/`RUN_ID`/
`LEAN_RUN_MODEL`/`LEAN_ATTEND_MODE` unset:

| Tree | Suite | Result |
| --- | --- | --- |
| head | scenario-liveness | 77 passed, 0 failed |
| head + log capture | scenario-liveness | 77 passed, 0 failed |
| M1 restore `--state open` resolver | scenario-liveness | 75 passed, **2 failed** — `(lean-closeout-merged)`, `(lean-closeout-merged-live)` |
| M3 delete the fake's `--state` arm | scenario-liveness | 76 passed, **1 failed** — `(lean-closeout-merged-fixture)` |
| head | lean-gate-selftest | `(pm7)`, `(pm7b)`, `(pm7c)`, `(ms11)` all pass |
| M2 delete the merged early-return | lean-gate-selftest | exactly two red: `(pm7c)` — `expected NO write to a merged PR, spool=<!-- dev-pipeline -->` — and `(pm7b)` as expected collateral |

The two head-tree `lean-gate-selftest` runs above were read case-by-case rather than to a
summary line — the machine was running three other lanes' copies of the same suite concurrently,
and CI's `pass 159s` on both lanes at this same head is the stronger oracle for the whole-suite
green anyway.

Also clean at head: `shellcheck -e SC1091,SC2015,SC2181` over all three touched shell files;
`check-lockstep-pairs.sh` — 29 anchors checked, 0 failed.

**Reviewer panel** — 6/6 selected, none dark, over the full branch range `ff3f6f8...13af5e2`:
security, performance, maintainability, complexity, test-coverage, scope-completeness. Zero
findings from all six; two security observations below the confidence threshold, both
suppressed at source and neither about this round's delta. a11y and the design-fidelity
dimension were not routed — no changed path matches `stageParams.webComponentGlobs`
(unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).

## Assessment

Round 1's two blockers were both of one species: an assertion certifying something it never
crossed. The fix treats them as that species rather than as two incidents — it names the
general shape in the commit body, applies argv classification where attribution was the
problem, and adds a separate case, explicitly labelled as fixture-capability rather than as a
claim about the run, for the arm that is only counterfactually live. That last one is the part
that is easy to get wrong and is right here: the leg's power to kill a restored resolver rests
entirely on a fixture no lane call reaches any more, so without its own case nothing would have
noticed it rotting. Both of round 1's mutants now red, in vocabulary that points at the
defect rather than at collateral.

W1's remedy is the cheaper one of the two available and says so in the code: reusing an
already-attested session id rather than attesting a fifth, because a fifth would have moved
`(ms11)`'s row count. W2 replaced a citation to a file that does not exist with an oracle that
runs, under the same `sed -E` its consumer uses.

`lean-gate.sh` is untouched since round 1. The only note worth carrying forward is N1, and it
is one `awk` clause away from closing whenever that file is next opened — not worth a round.
