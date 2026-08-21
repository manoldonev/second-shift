# lean review verdict — #610

verdict=approve
run_id: review-610-6
session_id: cb511abb-d451-470a-b02f-cb5a890196c6
rounds: 6
pr: #625
reviewed_head: 19bcf3d16eebb47fbf603121a3049156e764954e
reviewed_patch_id: 1c9881a92b07c256eae6ceb18f533e7d8f1d9f8b
inherited_patch_id: 2fdaa7e1632779034b769fd677264073073f3c7d
inherited_from_verdict: 76530462630e0f96211348910be6146c69a5e317
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 6, inheriting round 5's coverage of patch `2fdaa7e16327`. Delta read: `76530462..HEAD` —
the fifth `origin/main` merge, the record correction that closes round 5's blocker, and the
slow-table row that merge obliged. I read wider than the range, as every round on this PR has:
the whole branch contribution against the merge-base (`origin/main...HEAD`, 18 files), because a
merge commit puts main's own files in the delta and reading only the range confuses them for this
branch's work.

Verdict: **approve** — all 7 ACs satisfied, no blockers. Round 5's blocker is fixed exactly as the
operator specified, the base drift that cost rounds 2, 4 and 5 finally costs nothing, and the one
rule the merge imported that this branch was violating is obeyed rather than argued with.

## Round 5's blocker is closed, and closed on the data the operator supplied

Three rows asserted a promotion two now-closed tickets had disowned. All three are now
`deleted | pointer-kept` with an empty enforcer.

**The tracker states reproduce.** Checked directly: #622 `OPEN`; #623 `CLOSED / NOT_PLANNED`;
#624 `CLOSED / NOT_PLANNED`. Both closing comments close on a finding that the rule *cannot become
a control*, not that it was deferred — which is what makes `deleted` the honest disposition rather
than a convenient one.

**The replacement text is the operator's, not the lane's.** `pb-21641fc1` and `pb-ce91bffc` carry
the #610 comment's tab-separated rows verbatim. `pb-3bdd8454` takes the judgment the operator
explicitly declined to make for the lane — AC-2 documents `deleted` as "never a control", and a
reader could argue this construct is instead "worth enforcing but unenforceable here". The note
states the reading instead of flattening it: never a control, **and the rule's desirability is not
what settles that**, because no surface on this skill's path can enforce it at all. That is the
right answer to a question that was left open, and it is written where the next reader will find
it.

**Both substantive claims in those notes verified independently, not taken on the note's word:**

| Claim | Checked | Result |
| --- | --- | --- |
| `ticketTag` unreachable — `onboard` never emits it | `grep -rn ticketTag plugins/second-shift/skills/onboard/` | 0 hits |
| No enforcement surface on `figma-iterate`'s path | `ls plugins/design-toolkit/hooks` | absent |

**No other row can rot the same way.** One issue-shaped enforcer remains in the whole record —
`pb-0426581f` → `#622`, open. The dispositions now read 30 `gate-backed` / 1 `promoted` /
4 `deleted` over 35 rows, and `check` is rc=0 at 13 constructs over 26 files.

## The re-dispositioned rows still carry live coverage — probed, not assumed

The risk in moving a row to `deleted` is that it becomes inert: a parking slot nothing grades.
It does not. Probed in an isolated detached worktree at the reviewed head, each mutation applied
alone and reverted:

| Mutation | Result |
| --- | --- |
| shipped head | rc=0, `✓ zero undispositioned constructs` |
| **`pb-21641fc1`'s construct deleted from the tree** (its 3 prose lines) | **rc=3, `STALE — the row expects a surviving construct, the tree has none`** |
| `pb-21641fc1` action `pointer-kept` → `prose-deleted`, prose surviving | rc=3, `UNPRUNED — recorded prose-deleted, still in the tree` |
| `pb-3bdd8454` disposition `deleted` → `promoted`, enforcer still empty | rc=4, `line 49: promoted row names no enforcer` |
| `pb-ce91bffc` restored to `promoted / filed / #623` (a CLOSED ticket) | **rc=0 — the round-5 gap, still open by construction** |

Row two is mine to add: rounds 5 and the operator both probed the *legality* of the pairing
(rows three and four), and neither probed whether the pairing leaves the row graded. It does —
these three rows are as live as any `pointer-kept` row in the record, and the disposition change
did not buy silence.

Row five is the anti-vacuity control and it is worth stating plainly: **the fix corrected the
data, not the mechanism.** A `filed` row naming a closed ticket still reads green. That is D-8's
declared boundary — the record's authority stops at "the named enforcer resolves" — and AC-6 and
D-9 both forbid wiring a standing guard in this slice, so nothing is owed here. It is carried
below as a warning so the phase-2 register inherits it as a known rather than rediscovering it.

## The base merge is clean, and the enforcer it could have invalidated survives

Fifth merge of `origin/main`, one conflict, resolved as the union exactly as the commit message
says — verified in the combined diff: main's re-measured `run-selftests-selftest.sh	12` row and
this branch's `prose-blockers-selftest.sh	15` row both present in `mutation-slow-suites.tsv`.

**#630 was the live risk and it does not bite.** That merge changed
`plugins/intake-toolkit/skills/plan-interview/tools/dup-scan.sh`, which `pb-5c1cd975` names as its
enforcer (`dup-scan.sh::exit-2`) across four lockstep-pinned sites. #630 moved the numeric
`--issue` guard below the tracker-type check so a jira key reaches the not-applicable arm — it
narrowed **which inputs** produce rc 2 and left **what rc 2 means** untouched. The exit-2 arms are
all still there, the pinned prose still says "the scan could not run. Hard-stop", and
`scripts/check-lockstep-pairs.sh` reads 29 anchors, 0 failed. The row's claim is intact. This is
the class that cost round 5 a round, checked in the direction it would have come from.

**The merge mints no census work**: 13 constructs, 35 rows, rc=0 over the merged tree.

## The imported rule is obeyed, and the deferral it asks for is sound

#632 landed `tools/check-sweep-bound.sh` and a 9s membership threshold on
`tools/selftest-slow-suites.tsv` while this PR sat in review — a rule this branch's own new suite
was violating without a line of it changing. Adding the row is the right call and the measurement
behind it is honest:

- Threshold directive reads `# threshold-seconds	9`. The row records 15.
- Measured alone at the reviewed head, in an isolated worktree, box load ~3.0: **14.88s wall,
  8.02u + 6.53s**. Independently reproducing the build's 15.41s / 8.42u+7.05s, and the CPU split
  confirms it is the suite's own work rather than co-run inflation. Membership is the rule
  applying, not a hand-pick around it.
- **Soundness is unaffected**, verified rather than assumed: both `ci.yml` selftest jobs and both
  `nightly-guards.yml` wholesale lanes pass `--full`, which opts the table out entirely. The row
  narrows the local pre-PR sweep and nothing else. The cost is signal latency on this branch's own
  new guard, which the commit message states outright.
- It also keeps main's brand-new `selftest-sweep-baseline.tsv` honest **without** re-baselining it:
  that 106s was measured over the un-deferred set, and deferring a newly-arrived suite leaves that
  set exactly as measured rather than growing it by 15s. Re-baselining instead would have been the
  worse move and the branch did not make it.

`tools/prose-blockers.sh` and `tools/prose-blockers-selftest.sh` are byte-identical to the round-5
reviewed head (`git diff --quiet dfa2f20f HEAD` on both). The suite runs 56/0. Round 5's
`applied=8 killed=8 survived=0` override sweep therefore still describes this head; re-running an
identical sweep over identical bytes would have bought nothing.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `census` emits id / comma-joined sites / excerpt over the pinned corpus; reproducible across runs; tiers reported (`stop=13`, `bold=59`, `all=227`, "excludes 214 wider"); `prose-blockers-selftest.sh` 56/0. Unchanged this round, inherited from patch `2fdaa7e16327`. |
| AC-2 | satisfied | 13 censused constructs, 35 rows, every construct dispositioned (`check` rc=0). The three re-dispositioned rows each carry the one-line never-a-control reason. The all-dark-panel rule (`pb-94ee597a`) still triages like any row — operative site whole, duplicate pruned. |
| AC-3 | satisfied | `check`'s UNRESOLVED arm green. No rule reaches `deleted` while a gate enforces it: verified for all three new ones (no hooks dir, no reachable config, every intake-exit home prose-invoked). `pb-5c1cd975`'s enforcer re-verified against the #630 change. |
| AC-4 | satisfied | One `promoted` row remains, enforcer `#622`, open. The three dropped promotions are recorded in the rows' own notes and in both closing comments — dropped, not silently dropped. |
| AC-5 | satisfied | Six columns enforced by the MALFORMED arm (field count, both enums, the enforcer-non-empty rule) — probed rc=4 on two distinct violations. Reversibility declared in the header; ids and sites regenerate from `census`. |
| AC-6 | satisfied | `check` rc=0 with zero undispositioned; rc=3 probed on the UNDISPOSITIONED-adjacent, UNPRUNED and STALE arms. No standing CI guard wired, per D-9. One wording caveat below — it does not change the score. |
| AC-7 | satisfied | Header names #553 / #554 / #566 / #541 per residual. Both baselines regenerated for every file the prune moves (9 md rows, 2 shell rows). Measured comparison below. |

## Warnings — none blocking, nothing owed in this slice

1. **AC-6's sentence and the implementation key on different columns, and this round is the first
   where that matters.** AC-6 says `check` exits 3 naming "any row recorded `deleted` whose
   construct is still in the tree." The UNPRUNED arm keys on the **action** column
   (`prose-deleted`), not the disposition. Until this round the only `deleted` row was also
   `prose-deleted`, so the two readings coincided and the ambiguity was inert; three rows now
   carry disposition `deleted` with surviving prose and `check` exits 0. The action reading is the
   correct one — AC-2 provides `pointer-kept` precisely for surviving prose, and the operator
   ratified `deleted | pointer-kept` in writing as "the legal pairing for no gate is owed, the
   prose survives". I checked the spec was not amended to fit: AC-6's text has one commit,
   `65b1c4ba`, and has never been edited. So this is an original wording imprecision, not a
   post-hoc fit, and it is not a blocker. It is worth one clarifying clause before the phase-2
   register inherits the sentence as written.
2. **The stale-forward-pointer class is still live for exactly one row.** Probed above (case
   five): `promoted / filed / #<closed>` reads rc=0 forever. `#622` is open today, so the record
   is true today. D-8 declares this boundary and D-9 forbids closing it here; the phase-2 register
   owns it. Named so it is inherited rather than rediscovered.
3. **`prose-budget.sh` is red on the nightly lane at this head, and less red than on `main`.**
   Measured both myself in an isolated worktree: `origin/main` at `fbd10490` exits 4 with **6
   fails**; this head exits 4 with **4 fails**. This PR fixes two of main's (`review-lean`,
   `onboard`) and touches neither `QUERIES.md`, `figma-faithful-spec-reviewer.md` nor
   `capability-parity-check-selftest.sh`. `build-lean/SKILL.md` fails on both sides and this side
   is materially better — 1707 against a regenerated 1624 row here, 1930 against a stale 1488 row
   on `main`. AC-7 asks for regeneration and got it; five base merges then grew that file past the
   +5% tolerance afterwards. Nothing owed.
4. **Round 5's two carried warnings are unchanged and still owe nothing.** The PR-lane mutation
   green is vacuous by this PR's own slow-list row, graded instead by an override sweep on a
   byte-identical guard. `tools/gate-ablation*.sh` — and now `tools/check-sweep-bound*.sh` and
   `ledger-carry-forward*.sh` — arrive unbaselined from the base; they are main's files, the prune
   does not move them, and AC-7 binds only rows the prune moves.

## Review coverage

Six reviewers selected, **none dark**: security, performance, maintainability, complexity,
test-coverage, scope-completeness. All six returned `approve`. The one finding above the
confidence threshold — test-coverage, 80, that `check` is wired into no CI lane — is the
condition AC-6 and D-9 state as a deliberate decision with its reasoning, so it is dismissed as
a finding and carried as warning 2 instead.

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs` (unset, resolving to the shipped `apps/web/**/*.{tsx,jsx}`
default). This repo has no web-component surface. Not a coverage gap.

Design fidelity: `not-applicable`. The spec disarms with `Design: none — this repo configures no
design.provider`, which the repo's own config confirms — no `design` key at all. No route, no
render state, no receipt to score.

## CI at the reviewed head

`lint-and-selftests` SUCCESS, `mutation-sweep-pr` SUCCESS, `selftests (macos, bash 3.2)` SUCCESS.
`pr-gates` FAILURE on one cause only, read from the job log: the standing verdict record still
reads `verdict=needs-work` from round 5, so `lean-evidence` and `lean-chain` both refuse. That is
the expected pre-handoff shape and this record is what clears it.
