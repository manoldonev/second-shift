# lean review verdict — #759

verdict=approve
run_id: review-759-1
session_id: d0ebc8e8-299d-4f7b-8f67-795e82f54ba5
rounds: 1
pr: #772
reviewed_head: 4921871ceb7a6d7414fe07a36fe609dc41eaefbc
reviewed_patch_id: f02f43fbedccb4da728744a19b8978ac01f87551
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review — PR #772 (#759), round 1

Range reviewed: `08853051..4921871c` (root round, whole branch diff).

## Review Summary

Three commits: a lean spec, one test change across two suites, and a spec amendment that fills
the spec's own pre-declared **Liveness probe** placeholder. The change deletes `(if5b)` from
`lean-gate-selftest.sh` and hardens `(lean-inline-m3-nv)` in `scenario-liveness-selftest.sh` so the
group kill is delivered only once the lane child is observed **in** the gate's process group.

The remedy is at the cause and the spec argues down the two rejected alternatives on their merits.
I re-derived the load-bearing claim rather than reading it: in an isolated worktree cut from the
reviewed head, with #547's `setsid(2)` escape re-applied to `cmd_3`'s fixed-key lane runner, the
hardened case is the sole red (`81 passed, 1 failed`) and the unmutated control at the same head is
`82 passed, 0 failed`.

I then ran the complement, which the spec does not claim and which strengthens it: **on the
pre-change tree under the same mutant, both old guards passed.** `scenario-liveness-selftest.sh`
was `82 passed, 0 failed` and `lean-gate-selftest.sh` was `all green` — `(if5b)` explicitly
reporting "killing the gate's own process group leaves no lane child running". So the deleted case
was blind to the only detach shape this repo has ever shipped, its deletion costs no kill coverage,
and the hardened case is the first guard in the tree that catches that shape. This is a strict
coverage gain, not a red removed.

No subagent findings. `scope-completeness-reviewer` returned `approve` with no findings.

## Strengths

- **The predicate does two jobs with one check.** Waiting for the lane *in the group* removes the
  fork race (the signal cannot precede a fork that already happened) and makes absence itself the
  detach verdict — which is the `setsid` shape a second `killpg` would still have missed.
- **The budget was not widened, and the spec says why.** Any reap budget past the fixture's own
  `sleep 20` would green the case because the lane expired, retiring #566 AC-1 rather than fixing
  it. That reasoning is recorded in OR-1 against both rejected alternatives.
- **Guard mass went down while coverage went up** — net −8 excluding the spec, with no #717
  exception claimed, and the surviving guard strictly stronger than the pair it replaces.
- **The spec's ACs were not amended to fit the diff.** The only post-code spec edit fills the
  `## Liveness probe` placeholder that commit 1 already declared AC-3 would be scored against.

## Critical (must fix before merge)

None.

## Warnings (should fix)

None.

## Suggestions (consider)

- **[Test Coverage] `scenario-liveness-selftest.sh:2413-2416` — the absent-lane arm cannot tell
  "detached" from "never started" (confidence: 80).** The new arm reports
  `the lane never ran in the gate's process group — milestone 3 detached` on any path where no
  `sleep` appears in the group within 15s. A gate that dies before reaching `cmd_3` produces
  exactly that, and previously fell to the accurate
  `expected 1 started / 0 concluded, got started=0`. It fails closed and it fails loud, so this is
  a diagnosability cost on an already-red run rather than a false green — but a cheap
  discriminator (is the gate process itself still alive? does a `sleep` exist outside the group?)
  would separate the two causes and is worth a follow-up rather than a fix here.

## Plan Compliance

Implementation matches the spec. All six declared ACs are scored `satisfied` below; nothing in the
diff is outside what the spec declares, and nothing the spec declares is missing.

## Pre-existing gaps (not blocking this PR)

- `lean-gate-selftest.sh:8005-8006` — with `(if5b)` gone, `(if5)`'s reap loop still waits up to 5s
  for the group to die but nothing asserts on its outcome. It remains a legitimate settle before
  the row counts, and AC-1 explicitly requires `(if5)`'s scaffolding to be left unchanged, so
  leaving it is the correct call for this PR. Noted only because #717's ratchet is this ticket's
  own frame.

## Suppressed (below confidence threshold)

- `scenario-liveness-selftest.sh:2416` — Confidence: 70 — `pgrep -g "$te_kpg" -x sleep` couples the
  guard to the fixture's `test` command being literally `sleep`. Changing that fixture command
  would red the case rather than silently skip it, so the coupling fails in the safe direction and
  the adjacent comment names the dependency.
- `scenario-liveness-selftest.sh:2416` — Confidence: 65 — the loop sleeps 0.1s after a successful
  `pgrep`, so a first-iteration hit still costs one tick. Immaterial against a 20s fixture lane.
- Spec narrative — Confidence: 60 — the spec and PR body call the escaped budget "5s" while #759's
  body calls it "~10s". Both are defensible readings (`(if5b)`'s own loop was 50 x 0.1s; two such
  loops ran before its assertion) and neither changes the conclusion, since both are under the
  fixture's `sleep 20`.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — OK | 0 | — |
| Performance | Lead pass — OK | 0 | — |
| Complexity | Lead pass — OK | 0 | — |
| Maintainability | Lead pass — OK | 0 | — |
| Test Coverage | Lead pass — OK | 1 | 80 |

Routing notes: `security-reviewer` not selected — no auth, tenancy, session, upload or
query-construction surface in the diff and no `review-context/security-reviewer.md` in the repo;
the security dimension was covered by the lead pass. `a11y-reviewer` and the design-fidelity
dimension not routed — no changed path matched `stageParams.webComponentGlobs`
(`apps/web/**/*.{tsx,jsx}`, the default; the repo declares neither the key nor `design.provider`).
No repo `review-context.md` or per-reviewer extension file exists, so the lead pass inferred
calibration from the diff and its siblings and says so.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | The `(if5b)` block is gone as one unit — pre-image lines 8012-8026 (comment, reap loop, pass/fail pair) removed against `git show 08853051:`. No `if5b` remains anywhere under `plugins/`, `tools/`, `scripts/` or `.github/`; the only survivors are three `docs/plans/*-verdict.md` records, which AC-4 exempts as history. `(if5)` and `(if5c)` and the shared scaffolding (`set -m`, the backgrounded gate, `kill -9 -PGID`, `wait`, and `(if5)`'s own reap loop) are byte-unchanged. Suite green: `lean-gate-selftest: all green` locally at 4921871c, `pass 215s` on CI ubuntu. |
| AC-2 | satisfied | `scenario-liveness-selftest.sh:2413-2416` adds a pre-kill wait that polls `pgrep -g "$te_kpg" -x sleep` and only then delivers `kill -9 -"$te_kpg"`, so no child can enter the group after the signal. The post-kill reap loop is unchanged at 50 x 0.1s — the budget was not widened, exactly as the AC requires. Verified in the diff against the pre-image. |
| AC-3 | satisfied | Re-derived independently, not read off the spec. Isolated worktree cut from 4921871c, #547's `setsid(2)` escape re-applied to `lean-gate.sh:4871`, `git diff --numstat` 1/1 confirmed before AND after the run. Result: `FAIL: (lean-inline-m3-nv) the lane never ran in the gate's process group - milestone 3 detached`, `81 passed, 1 failed`, sole red. Unmutated control at the same head: `82 passed, 0 failed`. Complement measured too: the same mutant on the pre-change tree left `scenario-liveness` at `82 passed, 0 failed` and `lean-gate-selftest` `all green` with `(if5b)` passing, so the hardened case is the first guard in the tree that catches this shape. |
| AC-4 | satisfied | Both named comments rewritten to reference only surviving cases: `lean-gate-selftest.sh:1470` now reads `(if5) below` and `scenario-liveness-selftest.sh:2342` now reads `(if5) asserts`. Repo-wide grep confirms no other live suite comment names `(if5b)`; the three `docs/plans/*-verdict.md` hits are the history the AC exempts. |
| AC-5 | satisfied | `git diff origin/main...HEAD --numstat` excluding `docs/plans/second-shift-759-lean.md`: 12 insertions, 20 deletions, net **-8**. Negative, no exception claimed. `origin/main` is 08853051 and is also the merge-base, so the range is the branch's own work. The verdict record is not yet committed and is excluded by the AC's own wording. |
| AC-6 | satisfied | Both suites green at 4921871c on four independent runs. Locally with the known leak vars scrubbed: `[lean-gate-selftest] all green` and `[scenario-liveness] summary: 82 passed, 0 failed`. Under stock `/bin/bash` 3.2 with a 3.2 PATH shim, the liveness suite is `82 passed, 0 failed`. On CI at the same head: `pass 215s lean-gate-selftest.sh` and `pass 77s scenario-liveness-selftest.sh` in `lint-and-selftests`, and `selftests (macos, bash 3.2)` green overall. |

## CI at the reviewed head

- `selftests (macos, bash 3.2)` — pass. `mutation-sweep-pr` — pass (the catalog-anchoring guard;
  no catalog or exclusions row names either edited case as its killer, so the deletion orphans
  nothing).
- `pr-gates` — fail, on the `lean chain reconciliation` step. That is the merge boundary refusing a
  PR with no committed verdict record, i.e. the state this review exists to change. Recorded, not a
  blocker.
- `lint-and-selftests` — **pass** (4m45s), on re-run. The first attempt red on
  `plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh`, a suite this diff does
  not touch. Assessed rather than assumed before re-running: the identical suite and guard passed on
  the identical ubuntu lane at this branch's base commit 08853051 twenty-six minutes earlier, both
  suites the diff *does* change passed in the same red run (`pass 215s` and `pass 77s`), the suite
  has no `selftest-cache-inputs.tsv` row so the base green really exercised it, it is ALL PASS
  locally at this head, and its failing case (`AC-2 (empty-body)`, rc=0) is a deterministic awk pass
  over a fixture the diff cannot reach. The clean re-run on the same head confirms a flake in that
  suite. Not attributable to this branch, and not this PR's to fix — but it is a latent flake in a
  live guard and worth a ticket of its own.

**Ready to merge?** Yes

**Reasoning:** All six ACs are satisfied, three of them re-derived by measurement rather than read
off the spec, and the one probe the spec did not claim shows the change is a strict coverage gain
rather than a red removed. The single Suggestion is a diagnosability nit on an already-failing
path, not a defect in the property the ticket buys.
