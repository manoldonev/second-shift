# lean review verdict — #643

verdict=approve
run_id: review-643-4
session_id: f173bdc2-50ed-4e3c-b082-f7c760b76173
rounds: 4
pr: #651
reviewed_head: 20631d15fb7af8d685119bf039d563423987e175
reviewed_patch_id: ce73150e591fd87decca57b09b48fe4265593791
inherited_patch_id: 9be967198e3b1a186895d7a6f21798add520ae6f
inherited_from_verdict: 0bdb7a828faa0a38404343ec3863b27d82e87ab0
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 4 — a discharge round, and it re-stamps. Inheriting patch `9be96719`. The gate's delta range
is `0bdb7a8..HEAD`, which now includes round 3's own verdict commit; the three **deliverable** files
are byte-identical to `debf203` (`git diff --stat debf203..HEAD` on them is empty), so the reading
that matters this round is round 3's blocker and nothing else.

**Round 3's single blocker is discharged, and the discharge is complete.** It was operator-owned
with no branch remedy, and it was closed the way the lane's precedent says such a blocker closes:
on the tracker, out of band, with the branch untouched.

## B-10 — discharged, verified against the issue body

#650 `updatedAt` is `2026-08-23T15:09:40Z`, against `createdAt` `11:56:15Z` — the body has moved,
and it moved **after** round 3's verdict commit (`2026-08-23T18:04:33+03:00` = `15:04:33Z`). Each of
the four figures B-10 named was checked against the **committed audit at this head**, not against
round 3's own record:

| B-10 named | #650 now says | Audit at this head |
| --- | --- | --- |
| `M1ᵗ` "0.88–0.91" | "**0.873–0.905**, both ends in the keep row, over the corrected 63-spawn corpus" | `0.873–0.905`, 63 spawns |
| "four of five" transport failures | "four of the **six** transport failures pre-date #566" | `:241` "Four of the six T failures are pre-#566" |
| post-fix corpus "three spawns" | "the post-#566 corpus is **nine spawns with two T** (`0.778`, the reshape row)" | `:250`, `:291` — nine spawns, two T, `0.778`, B |
| class `M` a real cost (four rows) | "**two confirmed of the four first assigned**" | `M` = 2 |

Two things were added that B-10 asked for and one that it did not:

- **The `D-12` routing now exists in the ticket it routes to.** New scope item 5 wires the mid-run
  staleness re-check, cites `lean-gate.sh:2502` by line, and states correctly that the shape is
  round 2's corrected class-`M` finding — "spawns alive across their ticket's close — is this
  defect, not mis-dispatch". It also settles the arm-dependence question B-10 did not raise:
  "Lands with whichever arm survives; under arm A it still lands, because the manual lane has the
  same hole." That is the right call and it is the one that stops this item dying with the
  scheduler.
- **The launch unit is now carried too** — "launch floor 18, launch-level bound 0.667", matching
  `:233` and `:290`. B-10 did not list this among the four stale figures because #650's original
  text omitted it rather than misstating it; carrying it is a strict improvement.
- **Round 3's warning W-7 is carried into the inheritance**, which is more than the warning asked
  for. The body now says the two reclassified spawns "also carry a documented cost while sitting in
  `clean`". W-7 asked for that clause on the audit's *Robustness* row so #650 would inherit the
  caveat with the number; the operator put it in #650 directly, which reaches the same reader by a
  shorter path.

The body also carries its own provenance — a dated refresh note under the heading and a footer line
naming the round it discharges — so a later reader can tell the figures were restated after review
rather than written that way.

## What did not change, and is confirmed not to have

- **The branch.** Only round 3's verdict commit sits on top of `debf203`. The three deliverable
  files are unchanged.
- **B-8's remedy.** The re-point comments on #617/#638/#639 are still the `2026-08-23T14:24:4xZ`
  set and are still the latest comment on each — nothing regressed them.
- **#643's body.** `updatedAt` `14:33:44Z`, i.e. untouched since before round 3.

## Outstanding, non-blocking

- **W-8 stands.** `second-shift-643-audit.md:196` still says the misclassification corrected
  "**below**" when *Classification correction* is at `:95`, above it. A warning, on the branch, not
  discharged and not blocking — recorded so it is not silently dropped at the merge boundary.
- **W-7's branch half stands.** The audit's *Robustness* naive row still carries no caveat clause.
  Its purpose — that #650 inherits the caveat — is served by the body edit above, so this is now
  cosmetic.
- **A pointer nit, for whenever #650's body is next touched.** It cites "audit warning W-7"; W-7 is
  a warning in the review verdict record (`second-shift-643-lean-verdict.md`), not in the audit
  file. The substance it summarises is correct. Not worth an edit of its own.

## AC scoring

Every AC is re-scored against the whole spec, per the inheritance rule. The deliverable files are
unchanged since `debf203`, where round 3 scored all eight satisfied from source; the bases below are
that reading, with AC-4 re-measured at this head because the branch gained a commit.

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — pre-registration lands before any measurement | **satisfied** | `git log --reverse` puts `f573ee3` first; `git show --stat` on it is prereg + spec only, `+210`, no measurement. |
| AC-2 — every corpus spawn classified, band stated, launch unit enumerated separately | **satisfied** | 63 rows; class tally re-derived mechanically from the rows in round 3 = 49/6/2/3/2/1, matching the tally table; both previously-contradicted rows reproduce from the progress records, the log openings and the tracker. Launch half enumerated and bounded. |
| AC-3 — no arm selected or executed | **satisfied** | No arm selected anywhere on the branch. Revision 4 restates that no arm is selected here and that this corpus's band does not touch the endpoint it rules on. #650 — which now carries the corrected figures — is where selection happens. |
| AC-4 — `run-selftests.sh --full --exclude install-topology` green | **satisfied** | Re-run by me at this head `20631d1`: `74 scored, 74 run, 0 served from cache, 0 failed`, rc 0, cold. Round 3's run at `debf203` was equally green; the intervening commit adds one markdown file and discovers no suite. No orphaned selftest. |
| AC-5 — front-door truth | **satisfied** | Departed per `D-3`; vacuous — the branch is four markdown files and moves no front door. |
| AC-6 — `Changelog:` trailer | **satisfied** | Every commit on the branch carries one. |
| AC-7 — the follow-up is filed and linked | **satisfied** | #650 OPEN, `ready-for-dev`, linked from the PR body and from `D-1`/`D-2`/`D-3`, carrying AC-2's campaign (scope 1–2), AC-3's execution (scope 3), and now `D-12`'s staleness wiring (scope 5). Its body's accuracy — scored separately as B-10 in round 3 — is now discharged. |
| AC-8 — every row carries the evidence that produced its class | **satisfied** | All 63 rows carry evidence; the two rows whose evidence had contradicted its source were re-derived and verified in round 3 from the progress records and the tracker. |

## Verdict

**approve.** Four rounds: round 1 found six blockers, round 2 three, round 3 one, round 4 none. Every
one is closed, and none was closed by softening it — the corpus was re-enumerated (57 → 63), two
classifications were reversed against their author's own evidence line, the decision table was made
single-valued by an appended revision rather than an edit, and the last blocker was discharged on
the tracker with the branch untouched.

The headline survived all four rounds unchanged and is the reason this slice was worth the rounds:
the prediction was pre-registered at `11:31:08Z`, twenty minutes before the branch existed; it was
refuted by its author's own corpus; and every defensible reading of that corpus — naive,
pessimistic, optimistic, rubric-unamended, mis-dispatch-charged, launch-level, post-#566 — lands in
arm B or arm C. Arm A is unreachable. What #650 inherits is now an instrument whose findings it
states correctly.

Panel: none dispatched, the same call as rounds 2 and 3 and for the same reason — no code surface,
and this round's question was a tracker-body discharge that only direct verification can answer.
