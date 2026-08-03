# Review verdicts are authored outside the build session — #345

Child of the block-decomposition epic (#343); enforces manifesto P10 mechanically.
Predecessor: #344.

## Problem

The build session authors the reviewer's dispatch and, on dispatch failure, writes the
verdict record itself. Generation authoring evaluation's record is the structural bias P10
names — a fresh context window dispatched and charter-authored by the implementer was never
independence. The in-build reviewer workflow also carries a confirmed dark-death class.

## Shape of the change

**Milestone 4 is redefined, not removed.** Numbering 1..5 stays stable and in-flight progress
files stay valid. It keeps asserting that the committed verdict record exists, reads
`verdict=approve`, and carries reconciliation keys — and additionally refuses a record whose
run identity or session identity matches the build run's, including the case where the
identity was resolved from the build session's own run-id cache.

**Identity is role-keyed.** The build run caches its id at `<issue>-run-id`; a review session
caches its own at `<issue>-review-run-id`. The verdict path never reads or writes the build
cache, so a review session that forgets to provision an identity is refused rather than
silently stamped with the build's.

**The build harness never produces the record.** `lean-review.mjs` is deleted with its
dark-death class, and the emptied `run-lean/workflows/` directory goes with it — an
empty-but-present directory would make the meta-purity lint silently vacuous.

**REVIEW is a top-level session.** Input a PR number, output the committed verdict record
(same schema, same path) plus findings on the PR. `review-lead` is the implementation; the
new `review-lean` skill is only its front door plus the harness-owned verdict write
(`lean-gate.sh verdict`), which is where the authorship refusals live.

**The merge boundary carries the same check.** `check-lean-chain.sh` refuses a PR whose
verdict-record run identity equals the bot claim comment's, or whose verdict record is
missing either reconciliation key. CI remains the terminal verifier; the in-run milestone is
fast feedback.

**`lean-reconcile.sh` re-anchors.** Its dispatch-trace check today requires a `lean-review`
row in the BUILD session's ledger — a row that can never exist once review is a separate
session. It re-anchors to the review session's own ledger: a non-empty ledger must exist for
the session id the verdict record names, and that session must not be the build session.

Needs-work loops round-trip through artifacts only: findings on the PR, a build session
(fresh or resumed) addresses them, a new review context produces the next verdict.

## Open regions, dispositions taken

- **Review identity token format** — reversible default taken: the existing run-id charset
  (`[A-Za-z0-9._-]+`) with a `review-` role prefix, conventional in the skill rather than
  enforced by the gate. Flagged: the gate enforces *separation*, not *shape*, so tightening
  the shape later is a one-line change with no artifact migration.
- **Attended vs unattended driver sweeping verdict-less open PRs** — not taken. Out of scope
  here; the candidate is the scheduled-retro runner and the decision is the operator's.

## ACs

- **AC-1** (oracle — selftest): `check-lean-chain-selftest.sh` cases — a verdict record whose
  `run_id` equals the bot claim comment's fails; a verdict record missing `session_id` fails;
  a missing verdict record fails; distinct identities carrying both keys pass.
- **AC-2** (oracle — selftest): `lean-gate-selftest.sh` milestone-4 cases — a verdict whose
  `run_id` matches the build run identity fails; a verdict whose `session_id` matches the
  build session fails; a missing verdict fails; distinct identities with both keys pass; and
  a verdict carrying the id held in the **build run-id cache file** fails even when no
  `RUN_ID` is exported.
- **AC-3** (oracle — selftest): the build gate's evaluation of milestone 4 performs **no
  write** to the verdict-record path on any fixture — asserted by checksum and mtime being
  unchanged across a full `all` sweep against a fixture worktree.
- **AC-4** (oracle — CI): the existing chain-gate cases stay green — prefix and artifact-arm
  applicability, the trust filter, the PR-open window and the fatal-constant arms unchanged.
- **AC-5** (oracle — mutation sweep): generic-survivor ordinals for every edited guard
  (`lean-gate.sh`, `check-lean-chain.sh`, `lean-reconcile.sh`,
  `check-bounded-exploration.sh`) re-baselined in the same diff; affected catalog rows
  re-anchored.
- **AC-6** (critic): the PR carries a `Changelog:` trailer.
- **AC-7** (oracle — selftest): `lean-reconcile-selftest.sh` re-anchored — fails when no
  non-empty ledger exists for the verdict record's session id; fails when that session id is
  the build session's; passes when a distinct review-session ledger exists; the
  build-ledger `lean-review` row requirement is gone.
- **AC-8** (oracle — CI): `design-sync-selftest.mjs` and `check-bounded-exploration.sh` stay
  green and non-vacuous after the workflows-directory removal — each **discovers** every
  `workflows/` directory under `skills/` and fails if one is outside the lint's scanned set,
  so the removal cannot leave a future directory silently unlinted.
- **AC-9** (oracle — selftest): `lean-gate.sh verdict` refuses when the invoking session is
  the build session, refuses when no review identity is provisioned, refuses a review
  identity equal to the build run's, and otherwise writes a record carrying `verdict=`,
  `run_id:` and `session_id:` at the pinned path. It never reads or writes
  `<issue>-run-id`.
- **AC-10** (oracle — scenario): the lean legs of `scenario-liveness-selftest.sh` compose the
  separated verdict — the all-green leg's verdict record is review-authored, and the same leg
  reds when that record carries the build run's identity.
- **AC-11** (critic — docs): `run-lean/SKILL.md` dispatches no reviewer and states that the
  verdict arrives from outside; `review-lean/SKILL.md` is the REVIEW entry; `docs/testing.md`'s
  two-workflow-directory note reflects the removal; and `docs/pipeline-manifesto.md`'s P10
  posture note no longer records the enforcement as owed-and-pending.
- **AC-12** (oracle — CI): `plugins/dev-pipeline/skills/run-lean/workflows/` is absent from
  the tree and from both lints' directory enumeration.

## ACs added by review round 1

Round 1 found the separation sound but four of its supporting properties incomplete. These
extend the definition of done rather than restate it.

- **AC-13** (oracle — selftest): the `verdict=` value is read FIRST-MATCH at all three readers,
  never counted across the file. A `verdict=needs-work` record whose summary body contains the
  literal `verdict=approve` — the shape `--summary-file` makes ordinary, and which two merged
  records already carry — is refused by milestone 4 and by the merge boundary.
- **AC-14** (oracle — selftest + scenario): the verdict record is bound to the tree it covered.
  Milestone 4 and `check-lean-chain.sh` each refuse a record that is uncommitted (never
  committed, or committed and then edited) and one with any non-record commit between its
  commit and the head; a new review round clears both. The merge boundary measures against the
  PR head commit, not the checkout's `HEAD`, which on a `pull_request` event is the merge ref.
- **AC-15** (oracle — selftest): a milestone EVALUATION never establishes the build run
  identity. Only `entry` and `claim` may write `<issue>-run-id`, so a review session running
  `bash G 4 <issue>` against an absent cache cannot seed it with its own id and permanently red
  a valid record.
- **AC-16** (oracle — selftest): the claim comment carries the build `session_id` as well as its
  `run_id`, and the merge boundary refuses a verdict naming that session even when the run ids
  differ. A claim predating this carries none; that case passes with a printed note, because
  the PR-open window makes re-posting impossible and an unfixable red is not a gate.
