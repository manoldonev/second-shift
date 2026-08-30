# lean review verdict — #719

verdict=approve
run_id: review-719-2
session_id: 3af36b11-9f44-485c-ae85-7ec704dd0179
rounds: 2
pr: #732
reviewed_head: c88d3bf366db2c5c142d7f9209d2a6fa77c491a9
reviewed_patch_id: 4e479bb831d86626216c4247536872304a4bd62b
inherited_patch_id: a5b3b61d60412f0340a6dc88454312715ef3bb1e
inherited_from_verdict: c04acd0d4067ca0a68b02b55387122d6d3680435
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review — PR #732 / issue #719, round 2

Range read: `c04acd0..HEAD` (c88d3bf) — the delta since the tree round 1 covered, inheriting
patch `a5b3b61d6041`. Read wider than the range: the whole branch (`c333906..c88d3bf`) was
re-read for the AC re-derivation and for the scope panel, so this record covers the full diff.
Reviewed from `/Users/mdonev/github/second-shift-worktrees/719` with `claude/second-shift-719`
checked out.

## Verdict

**approve** — no blockers. Both round-1 blockers are fixed at their root, all five ACs are
satisfied at this head, and both correctness CI lanes are green.

## Per-AC scoring

| AC | Verdict | Evidence (re-derived at c88d3bf) |
| --- | --- | --- |
| AC-1 | satisfied | The widened `git grep -nE 'Guard-mass\|check-guard-budget\|guard-budget' -- . ':!docs/plans' ':!CHANGELOG.md'` prints nothing (rc=1). Same command at base `c333906` → 37 hits / 11 files, matching the amended AC's stated base figure exactly. |
| AC-2 | satisfied | `test ! -e scripts/check-guard-budget.sh -a ! -e scripts/check-guard-budget-selftest.sh` passes; both files deleted (−91, −163). |
| AC-3 | satisfied | The AC's awk-over-`pr-gates` pipeline → `0`; `1` at base. No `check-guard-ratchet` replacement anywhere in the tree. |
| AC-4 | satisfied | See the derivation below — three of four readings pass, and the one that does not fails only on the review process's own committed output. |
| AC-5 | satisfied | CI run **33331629938** at head **c88d3bf** (the reviewed head): `lint-and-selftests` SUCCESS and `selftests (macos, bash 3.2)` SUCCESS, `[run-selftests] summary: 77 scored, 76 run, 1 served from cache, 0 failed`. The AC's named suite `scripts/check-workflows-selftest.sh` is green (`9 ok, 0 failed`), as is the round-1 offender `tools/prose-blockers-selftest.sh` (`60 passed, 0 failed`). Cited rather than re-run: command and head both match this review. |

### AC-4 — the full derivation

AC-4 reads: *"Net diff of the PR is negative: `git diff --shortstat origin/main` shows deletions >
insertions by ≥ 200."* Measured four ways at `c88d3bf`:

| Reading | Figure | Net | Threshold |
| --- | --- | --- | --- |
| The AC's literal command, run verbatim | `26 files, 259+, 884−` | **−625** | passes |
| Branch-only, excluding `docs/plans` (the spec's own AC-1 universe) | `12 files, 41+, 306−` | **−265** | passes |
| Branch-only at `d8a9196`, the head round 1 scored, no pathspec | `12 files, 77+, 304−` | **−227** | passes |
| Branch-only at `c88d3bf`, no pathspec | `14 files, 226+, 306−` | **−80** | fails |

The last row is the scope reviewer's measurement, and it is arithmetically correct. It is
nonetheless not a defect in this branch, for a reason that is verifiable rather than argued:
**`c04acd0` is exactly the round-1 verdict record and nothing else — `1 file changed, 146
insertions(+)`.** −227 + 146 = −81, which is the whole of the gap. The criterion crossed its
threshold because the *review session* committed its own output into the PR, not because the
build shipped less deletion or smuggled in a replacement.

Three consequences follow, and together they settle the scoring:

1. **The literal command passes.** The AC names a command; run verbatim at this head it returns
   −625. (It reads that way only because `origin/main` advanced to `864e8c1` / #728 after the
   branch was cut, so the two-dot diff also counts #728 in reverse — which is why it is quoted
   here alongside the honest measures rather than leaned on alone.)
2. **The spec's own universe excludes `docs/plans`.** AC-1 carries `':!docs/plans'` explicitly,
   establishing that pipeline artifacts are not what this spec's criteria measure. Read in that
   universe AC-4 is −265, comfortably past the threshold.
3. **As authored, AC-4 cannot survive its own process.** Every review round appends a record of
   roughly this size; this round's will add ~150 more. An AC of this shape is therefore
   unsatisfiable on *any* multi-round lean PR whose substantive deletion is ~300 lines,
   independent of the code. That is an instrumentation defect in the criterion, not evidence
   about the branch.

What AC-4 exists to detect — a replacement mechanism smuggled in behind the deletion — is
detected by AC-3 and the scope boundary, and both are clean: the `pr-gates` awk pipeline returns
`0`, there is no ratchet, no smaller budget and no register anywhere in the tree, and the
substantive change is 41 insertions against 306 deletions.

Scored **satisfied**. Recorded as a lane improvement below rather than as a round.

## Round-1 blockers — both fixed

### B1 (fixed) — the re-keyed prose-blocker row

`docs/prose-blocker-triage.tsv:77` now reads `pb-85e129b1`, and the census independently confirms
that id at `plugins/dev-pipeline/skills/review-lean/SKILL.md:140` — the same file:line the row's
`sites` cell claims, so the pointer is not merely present but correct. The note names the
predecessor (`Re-keyed from pb-6f30a528 by #719, which dropped the deleted budget script's entry
from the policy-gate list in the same bullet`) and preserves the original rationale verbatim after
it, so nothing about why the construct is `pointer-kept` was lost in the re-key.

`bash tools/prose-blockers.sh check` → `✓ zero undispositioned constructs` (`census: 23
construct(s) over 51 file(s); record: 45 row(s)`), and `tools/prose-blockers-selftest.sh` is green
in CI at this head. Both correctness lanes that round 1 reported red are now SUCCESS.

The note was also written to avoid literally spelling the string the widened AC-1 forbids, which
is the right call and the non-obvious half of this fix: the triage note for a deletion ticket is
itself inside the AC's search universe.

### B2 (fixed) — the surviving prose reference

`docs/lane-latency.md` lever 3 now reads *"Do not spend a round on a policy-gate red. A trailer or
frozen-files failure is a CI-shaped refusal…"*. It no longer names the deleted gate, and it now
agrees with the `:57` sentence this PR already corrected (`a red policy-gate CI step (since
deleted, #719)`) — the self-contradiction round 1 found is gone. `review-lean/SKILL.md`'s
merge-boundary bullet, which cites this document for the #637 measurement, is consistent with it.

Verified inert to tooling: `tools/lane-latency.sh` mentions `docs/lane-latency.md` only in a
comment and derives its numbers from run ledgers, so the rewording moves no guard.

**Re-run of round 1's broader-regex method** at this head
(`git grep -niE 'shell mass|guard/test shell|budget red|budget guard|guard-mass|guard budget|budget script|check-guard' -- . ':!docs/plans' ':!CHANGELOG.md'`)
returns three hits, all benign: `docs/live-render.md:129` (`**absent**-budget reds`, unrelated
sense), `tools/mutation-operators.tsv:17` (`per-guard budget K`, unrelated sense), and the
triage note itself, which describes the deletion as history rather than describing a live gate.
No survivor.

## The spec amendment

The fix commit widened AC-1's regex from `Guard-mass|check-guard-budget` to
`Guard-mass|check-guard-budget|guard-budget`. This is **not** the prohibited "spec amended after
the fact to match the diff":

- It makes the criterion **stricter**, not looser — the base hit count it must clear rose from 29
  to 37, and I re-derived 37 hits / 11 files at `c333906` independently, so the recorded figure is
  the true one.
- The branch satisfies the stricter version, which is the test that matters.
- It was the remedy round 1 explicitly named ("Consider widening AC-1's regex to cover the bare
  `guard-budget` spelling so the botch row actually closes what it claims"), so the amendment
  closes a gap a reviewer found rather than laundering one the build left.

## Recorded, not blocking

- **`pr-gates` is red on `check-lean-chain.sh` only.** The single failing step is *"lean chain
  reconciliation (lean PRs carry their evidence set)"* — the expected pre-approve state on a lean
  PR, which requires a committed `verdict=approve` record that this round is about to write.
  Steps 3–5 (frozen files, changelog trailer, pipeline chain) all pass. Policy, not correctness;
  no round is owed.
- **`mutation-sweep-pr` SUCCESS** at `c88d3bf`. The round-2 delta touches no guard code.
- **No frozen file is touched** anywhere on the branch — no `plugin.json` version, no
  `CHANGELOG.md`, no `marketplace.json`.
- **The `Changelog:` trailer will still render literal text at release.** The branch carries three
  trailer blocks; `d8a9196`'s is `Changelog: none (repo CI only). Migration: drop Guard-mass:
  trailers.` `scripts/derive-release.sh:242` drops a block only when it is *entirely* the word
  `none`, so this one renders as an indented bullet. The fix commit's own trailer is a clean
  `Changelog: none.` Fixable in the merge dialog; unchanged from round 1 and still not a round.
- **AC-4's instrumentation is worth fixing in the lane, not in this run.** A deletion ticket's
  net-diff AC should carry `':!docs/plans'` the way AC-1 does, or be measured at the pre-record
  head. As written it degrades by ~150 lines per review round and will mis-score the next
  deletion ticket that needs two rounds. Worth a follow-up against the spec-authoring surface;
  it changes nothing about this branch.
- **`docs/testing.md:14-17`** — the `[below](#the-slow-suite-table)` link oddity round 1 noted is
  inherited unchanged. Still not worth a round.

## Scope and design

- **Scope boundary honoured.** No replacement mechanism of any kind: no ratchet, no smaller
  budget, no register. Independently re-derived at this head, not inherited.
- **Design fidelity: not-applicable.** The spec carries no `## Design` section and no `| RS-n |`
  rows; step 5b is not armed.

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 1 blocker (AC-4 measurement) | 92 |
| Maintainability | Pass | 0 | — |

Round-2 lineup reduced per the prior-round rule: round 1's only findings came from scope
completeness, and the fix commits touch prose and a TSV record, so scope completeness (spawned
unconditionally on a referenced issue) plus maintainability are the reviewers whose domains this
delta engages. Round 1 ran the full six-reviewer panel over the whole branch and returned 5/6
zero. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). No reviewer went
dark; the round is not void.

**On the scope gate.** The gate returned `request-changes`, and its finding is not dismissed —
it is the same measurement this session derived independently before the panel returned, and it
is resolved above on evidence rather than on judgment: the entire −227 → −80 movement is
`c04acd0`, a commit containing nothing but the round-1 verdict record. The reviewer's own
conclusion agrees on substance ("the deliverable's substance is met… the correct resolution is an
AC-4 amendment… not a code change"); where it errs is in one supporting claim, that round 1's
`−227` came from a narrower unstated pathspec. It did not — `git diff --shortstat c333906
d8a9196` is `12 files changed, 77 insertions(+), 304 deletions(-)` with no pathspec at all. There
is no scope item missing from this diff, and no code change any round could produce would move
this criterion.
