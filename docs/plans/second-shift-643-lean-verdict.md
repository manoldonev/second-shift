# lean review verdict — #643

verdict=needs-work
run_id: review-643-3
session_id: f173bdc2-50ed-4e3c-b082-f7c760b76173
rounds: 3
pr: #651
reviewed_head: debf2036be45fbad15d3ceb8b1ee99c4a2f03e24
reviewed_patch_id: ce73150e591fd87decca57b09b48fe4265593791
inherited_patch_id: 9be967198e3b1a186895d7a6f21798add520ae6f
inherited_from_verdict: 0bdb7a828faa0a38404343ec3863b27d82e87ab0
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3, inheriting patch `9be96719`. Delta read: `0bdb7a8..HEAD` — two commits
(`4a6e265`, `debf203`), three files, docs-only. Round 2's findings were read first, and each of
its three blockers and three warnings was re-checked against the fix from source rather than
taken on the PR body's word.

**All three round-2 blockers are closed, and all three warnings are discharged.** The correction
that closed B-7 is the strongest work on this branch: it re-derived two classifications from the
gate's own progress records, recomputed every dependent reading before writing it up, and caught
an operator-supplied datapoint that was a local clock read as UTC. Every figure in it reproduces.

**The headline is unchanged and undisturbed by three rounds of review.** The prediction was
pre-registered, refuted by its author's own corpus, and every reading still lands in arm B or
arm C. Arm A remains unreachable.

One blocker remains, and it is not on the branch: **#650 — the ticket that inherits this
instrument — states the instrument's findings from before round 1 corrected them.**

## Round 2's three blockers — all verified closed

| # | Round-2 blocker | Status |
| --- | --- | --- |
| B-7 | two of four class-`M` rows contradicted by the logs they cite | **CLOSED, verified from source.** `533-lean-progress.md` line 12 carries an *accepted* `entry` at `2026-08-16T16:29:11Z`; PR #556 merged `17:35:50Z` — 66 min 39 s later. Milestones 1/2/3/4 reach `satisfied` at `16:52:12Z`/`16:52:17Z`/`16:58:38Z`/`17:33:57Z`, all before the merge, and only milestone 5 fails `17:41:10Z` "no open PR found for branch claude/second-shift-533"; teardown `17:42:18Z`. `530-lean-progress.md`'s final block runs milestone 1 `18:45:00Z` → milestone 3 `rc=1` `18:53:48Z`, straddling #530's close at `18:52:03Z`. Both reclassified `clean`. `530-5` and `549-6` survive the check: I read all four log openings, and the discriminator holds. |
| B-8 | #617/#638/#639 sequenced behind a ticket that no longer owns the decision (carried from round 1's B-6) | **CLOSED, verified against the API, not the cited links.** Re-point comments `5386499756` (#617), `5386500134` (#638), `5386500226` (#639), created `2026-08-23T14:24:42/47/48Z` — after round 2's verdict commit (`14:18:09Z`) — `created_at == updated_at` on all three, never edited. Each names #650, and each states that #643 closing on PR #651's merge does *not* unblock the ticket. That is the whole remedy, not a partial one. Discharged by the operator outside the branch, as `D-11` records. |
| B-9 | the decision table is two-valued at exactly `M1ᵗ = 0.80` | **CLOSED, verified.** Revision 4 is **appended**: `git diff --numstat` on the pre-registration is `47 0` — forty-seven lines added, zero removed, so `R3-2`, revision 2 and revision 1 all stand unedited. The B band becomes `0.50 <= M1ᵗ < 0.80`. The three bands `[0, 0.50)`, `[0.50, 0.80)`, `[0.80, 1]` are pairwise disjoint and cover `[0, 1]`, and the two `>= 0.80` rows are disjoint on attention — total **and** single-valued. |

Warnings: **W-4** — the blank line at `second-shift-643-lean.md:67` is gone; the ledger is twelve
contiguous rows (`:61`–`:72`) and renders as one table. `ledger-lint.sh` reports `12 ledger row(s)
/ OK`, though as round 2 noted it would report OK either way. **W-5** — the PR body now leads with
`0.873–0.905` and cites `:634`. **W-6** — #643's body heading reads **Operator amendment**.

## What I re-derived independently

- **The class tally, mechanically from the per-spawn rows themselves**: 49 clean / 6 T / 2 M / 3 S
  / 2 U / 1 I = 63. Matches the tally table exactly.
- **Every mtime in the correction, proved against the epoch** rather than trusted to a format flag
  (`date -u -r "$(stat -f %m …)"`): `533-1` = 1786902144 = `17:42:24Z`, `530-4` = `18:54:18Z`,
  `530-5` = `18:54:46Z` (28 s later), `549-5` = `20:54:07Z`, `549-6` = `20:54:38Z`. All five as
  stated. The audit's parenthetical — that reading `533-1`'s stamp as UTC "turns a seven-minute
  overhang into a three-hour one" — is correct, and stating the `+0300` offset in the file is the
  right disposition for a datapoint that arrived wrong.
- **Every tracker timestamp**: PR #556 `17:35:50Z`, #533 `17:35:51Z`, #530 `18:52:03Z`, PR #560
  `20:49:37Z`, #549 `20:49:38Z`.
- **All four log openings.** `530-4` and `533-1` discover the closure mid-run; `530-5` opens "Issue
  #530 is already **closed and merged**" and `549-6` opens with a state table reading `CLOSED` /
  `MERGED` / "none for 549 (already swept)". The discriminator is sound. I note for the record that
  `530-4`'s *first line* ("Issue #530 is already done") reads like the arrival shape and only its
  second paragraph disambiguates — the classification does not rest on that, because the progress
  record decides it mechanically, and the file cites the progress record.
- **Every arithmetic claim in the recompute.** Naive `49/63 = 0.778`; `M1ᵗ` `55/63 = 0.873` and
  `57/63 = 0.905`; both-`M`-charged `53/63 = 0.841` and `55/63 = 0.873`; `D-5`-unamended
  `54/63 = 0.857` – `0.905`; launch floor `12/18 = 0.667`; post-#566 `7/9 = 0.778`. The claim that
  `M1ᵗ` and the `D-5`-unamended row are **untouched** is correct and non-obvious: both rows count
  `M` and `clean` on the same side, so moving two rows between them cancels exactly.
- **The staleness routing.** `lean-gate.sh:2502` returns `7` on `CLOSED`, and `run-lean/SKILL.md:54`
  states in the orchestrator's own words that the check "runs at the spawn boundary and has no
  channel into a live spawn" — which corroborates the audit's claim that nothing calls it between
  milestones, from a source outside the audit.
- **No stale figure survives in a committed file.** Every remaining `0.746` / `0.810–0.841` /
  `0.88–0.91` occurrence is either a stated before→after transition, the immutable round-2 verdict,
  or revision 3's historical record of its own move.
- **AC-4 by execution at this head** and **AC-1's ordering** — below.

## Blockers

### B-10 — #650 states this instrument's findings from before round 1 corrected them

`D-12` routes work to #650 and `AC-7` makes it the follow-up that owns the campaign and the arm
selection. Its body has **not been edited since it was created**: `updatedAt` is
`2026-08-23T11:56:15Z`, identical to `createdAt`, which is *before* round 1's corpus correction
landed. Its section headed **"What #643 established"** therefore states four figures the committed
audit now contradicts:

| #650 says | The committed audit says |
| --- | --- |
| "Spawn-level `M1ᵗ` is **0.88–0.91**" | `0.873–0.905` |
| "**four of five** transport failures pre-date #566" | four of **six** — `T` is 6 |
| "leaving a post-fix corpus of **three spawns**" | **nine** spawns, 2 T, `M1ᵗ = 0.778` |
| "class M — mis-dispatch onto already-merged issues — is a real scheduler cost" (four rows) | `M` is **2**; the other two are a *different* defect with a different remedy |

The third row is the one that matters. The post-#566 set is the only part of this corpus measuring
the transport as it exists today and, by the audit's own words, "the part that reads worst for the
scheduler". A reader who believes it is three spawns rather than nine will judge the freshest
evidence roughly three times thinner than it is — and #650's opening instruction is "**Do not
re-litigate the criterion**", which actively discourages going back to check.

The fourth row compounds it: `D-12` says the uncalled `lean-gate.sh:2502` staleness re-check is
"routed to **#650**", and #650's body contains no mention of staleness, `2502`, a mid-run re-check,
or the shape at all (`grep -i` returns nothing). The routing exists in this branch's ledger and in
the audit's limitation 3; it does not exist in the ticket it routes to.

This is round 1's **B-5** in a new place. There the blocker was that #643's body still stated ACs
this slice had departed from; the remedy was a body amendment and it was accepted as closing it.
Here the ticket that *inherits the instrument* misstates what the instrument found, on figures two
rounds of review moved. The instrument is this slice's entire deliverable, and an inheritance that
carries the pre-correction numbers is the one way its value leaks.

**No branch change is required and none should be made.** Like B-8, this is a tracker-side remedy
with no code counterpart: refresh "What #643 established" against the committed audit, and add the
staleness shape `D-12` assigns to it. Recorded as outstanding and owned by the operator, carried to
the merge boundary per round 1's rule for a scope blocker with no code remedy.

## Warnings

- **W-7 — the naive row's label no longer describes what it counts.** *Robustness* defines the
  naive reading as "every non-clean spawn charged to the scheduler", and two spawns carrying a
  scheduler cost the file documents at length are now inside `clean`. Binning them there is the
  **right** call and I want to be explicit about why, because the opposite call is the tempting one:
  `clean` is the rubric's residual, not a class, so no bin was forced; and minting a class `L` for
  the staleness shape would be a fourth post-hoc rubric amendment moving the naive row `0.778 →
  0.746`, toward the arm this file's author predicted. Declining it is the self-adverse choice and
  the pre-registration is better for it. What is missing is one clause on that row — "two spawns
  with a documented non-transport scheduler cost sit in `clean`; see limitation 3" — so that #650
  inherits the caveat with the number instead of having to find it three sections away.
- **W-8 — a cross-reference points the wrong way.** `second-shift-643-audit.md:196` reads "the
  misclassification corrected **below**"; *Classification correction* is at `:95`, above it.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — pre-registration lands before any measurement | **satisfied** | `git log --reverse` puts `f573ee3` first; `git show --stat` on it is prereg + spec only, `+210`, no measurement. Re-verified at this head. |
| AC-2 — every corpus spawn classified, band stated, launch unit enumerated separately | **satisfied** | Was unsatisfied in round 2 on B-7. 63 rows; the class tally re-derived mechanically from the rows matches (49/6/2/3/2/1); both previously-contradicted rows now reproduce from the progress records, the log openings and the tracker. Launch half unchanged and inherited. |
| AC-3 — no arm selected or executed | **satisfied** | No arm selected anywhere in the delta. Revision 4 explicitly restates that no arm is selected here, attention is unmeasured here, and this corpus's band does not touch the endpoint it rules on. |
| AC-4 — `run-selftests.sh --full --exclude install-topology` green | **satisfied** | Run by me at the reviewed head `debf203`: `74 scored, 74 run, 0 served from cache, 0 failed`, rc 0. Cold — no `--cache-dir`. |
| AC-5 — front-door truth | **satisfied** | Departed per `D-3`; vacuous — the delta is three markdown files and moves no front door. |
| AC-6 — `Changelog:` trailer | **satisfied** | 9 commits on the branch, 9 `Changelog:` trailers. |
| AC-7 — the follow-up is filed and linked | **satisfied** | #650 is OPEN, `ready-for-dev`, linked from the PR body and from `D-1`/`D-2`/`D-3`, and its Scope section carries AC-2's campaign (items 1–2) and AC-3's execution (item 3). The AC asks that it be filed and linked; it is. Its body's *accuracy* is B-10, scored separately rather than folded in here. |
| AC-8 — every row carries the evidence that produced its class | **satisfied** | Was unsatisfied in round 2 on B-7. All 63 rows carry evidence, and the two rows whose evidence contradicted its source now carry evidence I reproduced from that source. |

## Provenance I could not verify from the branch, and how I treated it

`D-9`, `D-10`, `D-11` and `D-12` are all marked `user-answered`. Three are checkable in part and
one is not:

- **`D-11`** — verified against the API. The comments exist, are the operator's, and postdate the
  round-2 verdict.
- **`D-10`** — the *ruling* (B half-open, `0.80` falls to the `>= 0.80` rows) is unverifiable from
  the branch, and the operator attested in this round that it is theirs and was issued before the
  re-entry began. I accept the attestation and note that the ruling is independently *justified* in
  `R4-1` from the criterion's own history — `>= 0.80` has appeared inclusive and unchanged since
  revision 1 — so it does not rest on authority alone.
- **`D-9`** — the operator attested supplying the corroborating datapoint and that the
  re-derivation is the build's own. That matches what the branch shows: the operator's datapoint
  (the `533-1` mtime as a three-hour overhang) is *refuted* in the committed file, and the evidence
  that actually carries the row is the `entry` timestamp in the progress record. The row's
  `user-answered` label is generous to the operator's contribution rather than to the build's, and
  I mention it only so the reading is on the record.
- **`D-12`** — the routing decision. Not attested and not checkable; its substance originates in
  round 2's own B-7 text. Scored as bookkeeping. See B-10 for the part of it that *is* checkable and
  does not hold.

Panel: none dispatched, the same call as round 2 and for the same reason — the delta is three
markdown files with no code surface, and round 1's panel on this shape returned one reviewer that
declined the domain for want of code. Every finding this round came from re-deriving the file's
claims against the progress records, the spawn logs, the gate source and the tracker, which is the
only technique that can reach them. Recorded plainly so the choice is visible rather than implied.
