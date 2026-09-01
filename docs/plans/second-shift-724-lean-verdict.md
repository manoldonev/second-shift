# lean review verdict — #724

verdict=needs-work
run_id: review-724-3
session_id: 4fc1d3bc-7776-4082-9f63-77dfac8eb0f2
rounds: 3
pr: #761
reviewed_head: 0bd12eb9a0d21391715c496a2ea220cc93ea444d
reviewed_patch_id: ff054c3cb5e887190586ed41194163afd9c87153
inherited_patch_id: aa4f4ee3275935bf33b7563b7cc3f47389289ac0
inherited_from_verdict: 812e6f855b12a0f3d0e2601337cd81fa7f5b76e4
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 3 — PR #761 (issue #724)

Range read: `812e6f85..HEAD` — the round-3 fix commit `0bd12eb9`, one file
(`docs/consumer-eval.md`), inheriting patch `aa4f4ee3` from round 2's record. **Read wider than
the range**, deliberately: this ticket's two prior rounds both turned on a statement of a rule
somewhere the reviewer's citation did not point, so I re-read the whole of `docs/consumer-eval.md`
at this head, grepped the corpus for every statement of the `launchToMerged` rule, re-verified the
new paragraph's central claim against `orchestrate-lean.sh`, and re-ran the launch-ledger sweep
across all 18 ledgers rather than the four the PR body cites.

Reviewed head: `0bd12eb9a0d21391715c496a2ea220cc93ea444d`. Docs-only.

CI at this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr`
pass. `pr-gates` fails on exactly two arms — the verdict record reading `needs-work` (the
pre-approve state, not a finding) and the intent-gap record reading `ratified: no` (blocker 1).
`lean-evidence.sh check --key 724` reports those same two and no third. **No correctness lane is
red.**

## Round 2's findings, re-checked

- **Blocker 1 (column contract carried the falsified rule).** **Fixed, and fixed everywhere.** I
  did not re-read the anchor I gave — I grepped the corpus for every statement of the rule. Three
  copies exist and all three now agree: `docs/consumer-eval.md:96` (metrics table), `:202` (column
  contract), `docs/plans/second-shift-724-lean.md:173` (spec Data Contracts). `grep -rn
  "non-rejected"` across the tree returns exactly one hit — inside round 2's own verdict record,
  quoting the old rule as a finding, which is a review artifact and not a prescription.
- **Finding 3 (the false closure sentence, major).** **Fixed.** "When either is itself the last
  spawning group at or before the merge, it did produce the PR and it is the start" is deleted,
  and the case it got wrong is now stated explicitly and correctly as its own paragraph at
  `:140-145`. See "What I verified" — I confirmed its central claim in the producer's control
  flow rather than accepting it. **Partially, though:** the deleted sentence was one of two
  statements of the same over-generalization, and the other one — the topic sentence at
  `:106-107` — survived untouched. That is finding 2, and it is structurally the identical
  mistake the round-2 blocker was about: a rule stated twice, corrected in one copy.
- **Findings 2 (AC-10), and round 1's findings 3 and 4.** AC-10 is unchanged and is blocker 1
  below. Round 1's D-9 and placeholder fixes remain in place.

## Findings

| # | Severity | Anchor | Finding |
| --- | --- | --- | --- |
| 1 | **blocker** | whole-PR (`docs/plans/second-shift-724-lean-intent-gap.md`) | **AC-10 remains unsatisfied, and the decision is still parked with the operator.** No consumer-repo replay has run; all four metrics read `unavailable`. The intent-gap record still reads `ratified: no` with an empty `ratified_by:`, and no ratifying comment exists on #724 or on this PR — the newest comment on the issue is the build's own ask at `2026-09-01T07:12:23Z`. I re-read the issue's own AC-10 text to test whether its "or a named reason it was unavailable" clause already licenses this, and it does not: the issue's **Dependencies** section spells out what that clause was written for — "Until it does, the `usd` column reads `unavailable` — which is a recorded gap, not a blocker on this ticket" — i.e. a per-metric escape for the one metric with no mechanism yet, not an escape from the replay itself. AC-10's subject is "one fixture ticket **run** through this recipe"; the run is the deliverable and it has not happened. The precondition that blocks it sits under **Dependencies**, not **Deferred**, with no linked follow-up, so nothing this round can read defers it. Not the build's to resolve — its handling was correct and complete — but not something a review can score satisfied either. |
| 2 | major | `docs/consumer-eval.md:106-107` | **The paragraph's topic sentence still over-generalizes, and its own bullet contradicts it four lines later.** `:106-107` opens "Three shapes are not that run. What disqualifies **each** is being **superseded by a later spawning group**". That is false of the first of the three: `:113-114` says the spawned-nothing shape "is the one shape that is never the start **even when it is the last group**" — disqualified by the absent `spawn` row, not by supersession — and `:123` then narrows correctly to "**The last two** are disqualified only by that supersession." So the section states, in three places, two incompatible accounts of what disqualifies the first bullet. This is the same false-generalization slot that has now shipped in three consecutive rounds: round 1's was the exclusion enumeration, round 2's was the closing sentence ("it did produce the PR and it is the start"), and round 2's fix deleted that closing sentence while leaving the topic sentence in front of it saying the same wrong thing. **Not a blocker** — the operative mechanic is unambiguous and correct (`:126-128` and the awk's `f[2] in spawned` both key on the absent `spawn` row), so no reader computes a wrong figure from it. One word: `each` → `the last two of these`. |
| 3 | major | `docs/consumer-eval.md:143-145` | **The new fallback keys on message prose, and that prose has already changed once inside this repo's own corpus.** The paragraph instructs: "take the group carrying `terminal … approved … on PR #<n>`". Across all 18 ledgers in the state dir, 15 carry an `approved` terminal — and **2 of the 15 do not carry the string the instruction matches on**: `#636` and `#637` write column 5 as bare `approved rc=0`, with no `— done — #N approved on PR #M.` suffix; the other 13 carry it. So the anchor is a message-text substring whose grammar demonstrably rots, on a document whose entire purpose is a rule applied unchanged release after release. The durable anchor is already present in every one of the 15: the slug `approved` at the head of column 5. This is the same lesson round 2's own fix banked — "prefer keying the rule on the observable property over any enumeration of slugs, which rots" — applied one level less far, since message prose rots faster than a slug does. A one-clause edit. |
| 4 | nit | `docs/consumer-eval.md:126-145` | **Two merged tickets in the corpus have no spawning group at all, and the document does not say what to record for them.** `#644` and `#668` (both closed) consist entirely of `attended-build-turn` / `attended-review-turn` (`rc=9`), `preflight-rejected` and `dry-run` groups — not one `spawn` row between them. The primary rule ("keep the groups that spawned") returns empty and the new fallback finds no `approved` terminal, so `launchToMerged` is uncomputable while the ticket nonetheless merged. The column contract admits `null`, and AC-7's null-metric-set rule is scoped to tickets that *did not* merge, so the case falls between the two. Low value for the eval specifically — a lane driven entirely through attended turns is arguably not a valid datapoint anyway — but the document currently leaves the maintainer to invent the answer. Worth one sentence whenever finding 3 is edited. |
| 5 | nit | `docs/consumer-eval.md:130-138` | **The awk block states the rule without pointing at the exception that follows it.** `:96` and `:202` abbreviate the rule and the awk implements it exactly; the post-approve caveat that falsifies it in one case sits at `:140-145`, *below* the snippet. This is explicitly **not** round 2's contradiction returning — the summary cells are abbreviations of the same rule rather than a competing one, and the caveat is in the section a maintainer computing the metric actually reads. But a maintainer who copies the snippet and stops has no signal there is more. Half a clause on the block. |

## Panel

`review-toolkit:scope-completeness-reviewer` returned `request-changes`, independently reaching the
same blocker on AC-10 and the same conclusion that round 2's blocker 1 is fixed everywhere the rule
is prescribed. Findings 2 and 5 are its catches, both verified by me before adoption — finding 2
against the three contradicting lines in the file, and I am carrying it a step further than the
panel did by naming it as the third consecutive appearance of the same slot rather than a fresh
slip. It also corroborated the AC-3 `rounds` amendment from a direction neither prior round used:
`retro-corpus.sh:382` greps `round=[0-9]+`, and `grep -c 'round='` returns **0** on the five most
recent progress records, so the AC's prescribed source is structurally null rather than merely
unpopulated on the runs round 1 sampled.

Not routed, and why: no changed path matches `stageParams.webComponentGlobs`, the spec carries no
`## Design` section (unarmed, so `fidelity: not-applicable` is the honest value rather than a
default), and a six-file prose diff with nothing under `.claude/` and no
`review-context/security-reviewer.md` in the repo leaves the collapsed dimensions and security to
the lead pass.

## What I verified rather than took on assertion

- **The new paragraph's central claim, in the producer's control flow.** "A re-launch onto an
  already-approved lane spawns BUILD before it ever reads the verdict" is **true**, and the order
  is unambiguous in `orchestrate-lean.sh`: the round loop runs `staleness_rc`, then `spawn BUILD`
  (`:865`), then `resolve_pr`, and only reaches `verdict_rc` at `:955`. `rc=0` there logs
  `review-skipped-approved` and falls into the close-out. So such a group does write a `launch`
  row and a `spawn` row and only then closes out, exactly as the paragraph says — which is
  precisely why the `mergedAt` bound alone does not exclude it, and why the paragraph is needed.
  The file's own `#531 D-7` header block ("THE VERDICT READ MOVES AHEAD OF THE SPAWN") documents
  the review spawn being moved, not the BUILD spawn, which is what leaves the shape reachable.
- **`terminal approved 0 "done — #$ISSUE approved on PR #$PR."` at `:1030`** — the current grammar
  does write the PR number the fallback reads, so the instruction is correct at today's head. It
  is its durability across grammar changes that finding 2 is about, not its correctness now.
- **Every statement of the `launchToMerged` rule in the tree**, by grep rather than by re-reading
  the line round 2 cited: three copies, all in agreement, plus one quotation of the old rule inside
  round 2's verdict record.
- **The approved-terminal grammar across all 18 ledgers**, printing column 5 verbatim per ticket —
  which is what surfaced findings 2 and 3, and which also shows that round 2's "12 of 12 merged
  tickets match" had `#636`, `#637`, `#644` and `#668` outside its denominator without saying so,
  because its ground truth *was* the `approved … on PR #<n>` row.
- **AC-3 against its amended text**, word for word: the AC prescribes "the `launch` row of the last
  launch group … that spawned anything at or before the merge", and both doc copies and the spec
  now state exactly that. The prose exception at `:140-145` is a named refinement of that rule, not
  a second competing rule — which is the distinction round 2's blocker turned on.
- **AC-11**, by `git diff --name-only origin/main...HEAD`: six Markdown files, nothing under
  `tools/` or `scripts/`, no `*-selftest.sh`.
- **AC-6**, by comparing the doc's header row `:188` against the spec's Data Contracts `:169-179` —
  the same ten columns in the same order.
- **AC-2**, by grepping the added lines of every changed file for consumer, org and stack
  identifiers — no hit.
- **AC-4/5/14/15/16** by reading `docs/consumer-eval.md:19-85` directly, and **AC-9** by reading
  `docs/releasing.md:44-53`, rather than inheriting round 2's reading of them.
- **The two outstanding evidence arms**, via `lean-evidence.sh check --key 724` — the verdict record
  and the intent gap, and no third surprise.
- The `[REDACTED]` token at `docs/consumer-eval.md:80` is the local output filter, not file
  content: `grep -c REDACTED` returns 0.

## Strengths

Round 2's blocker was fixed by **property, not by citation** — the failure mode that cost this
ticket its second round. All three copies of the rule were brought into agreement, not just the one
the finding anchored, which is the correction the finding was actually about. And the replacement
for the false closure sentence is the first version of that paragraph across three rounds that
survives being checked against the producer: rather than reaching for another closure clause, it
names the one case the `mergedAt` bound cannot exclude, explains the mechanism, and gives the
maintainer a concrete alternative. Deleting an overclaim and replacing it with a narrower true
statement is the right trade, and it is most of what this section needed.

Finding 2 is worth reading as a pattern rather than a slip, because it is the third round in which
this one paragraph shipped a false generalizing sentence — and the second in which the fix
corrected one copy of a duplicated claim. The durable lesson is the one round 2 already banked and
this round shows applies to prose as well as to rules: **when a finding names a false statement,
grep for every other statement of the same claim before calling it fixed.** Here the grep is one
word (`each`), and it would have caught a sentence that has been wrong since round 1 and that
three review passes — including my own first read of this file — walked past.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | all five present: corpus obligation `:19-48`, pinned-base recipe `:50-85`, four metrics `:87-155`, non-merge rule `:158-166`, recording obligation `:168-186` |
| AC-2 | satisfied | grepped added lines of all six changed files for consumer/org/stack identifiers — no hit |
| AC-3 | satisfied | **round 2's blocker is cleared.** The amended AC prescribes "the `launch` row of the last launch group … that spawned anything at or before the merge"; `docs/consumer-eval.md:96`, `:202` and `docs/plans/second-shift-724-lean.md:173` now all state exactly that, verified by grepping every statement of the rule rather than re-reading the cited line. `rounds` (verdict record's `rounds:` key), `mergedAt` (`gh pr view`) and the `usd` fallback are sound and unchanged. Finding 2 concerns the durability of the exception paragraph's anchor, not the prescribed source |
| AC-4 | satisfied | `:52-62` alternate config via `SECOND_SHIFT_CONFIG`, exactly one differing field (`baseBranch`) with the reason a second would corrupt the series; `:70-71` default branch neither modified nor rewound |
| AC-5 | satisfied | `:20-31` the five roles bound to `F-1`..`F-5` in order; `:33-36` the specs live in the consumer repo, never here |
| AC-6 | divergent-inert | doc header `:188` and column contract `:199-210` carry the ten columns of the spec's Data Contracts, `continuationCap` dropped. measured: `orchestrate-lean.sh:332` hard-refuses `--max-continuations`, so the column could only ever be empty. follow-up: none owed — #718 removed the flag and the budget it bounded; D-16 carries the DEPARTURE |
| AC-7 | satisfied | `:158-166` null metric set plus named refusal class, `outcome: did-not-merge:<refusal-class>`, never re-run and never dropped |
| AC-8 | satisfied | `:170-171` comment on the release PR before it merges, rows land on `main` separately; `:184-186` verdict is operator judgment with no automatic threshold |
| AC-9 | satisfied | `docs/releasing.md:44-53` states all three obligations — run the eval, comment the result on the release PR, land the rows on `main` — as step 4 inside the existing numbered flow |
| AC-10 | unsatisfied | finding 1 — no consumer-repo replay ran; all four metrics `unavailable`. The issue's "or a named reason it was unavailable" clause is a per-metric escape written for `usd` (the issue's own Dependencies section says so explicitly), not an escape from the replay AC-10's subject requires. The blocking precondition sits under **Dependencies**, not **Deferred**, with no linked follow-up, and the intent-gap record reads `ratified: no` with no operator answer to the ask posted at `07:12:23Z` — so the deliverable is neither delivered nor deferred by any authority this round can read |
| AC-11 | satisfied | `git diff --name-only origin/main...HEAD` is six Markdown files; nothing under `tools/` or `scripts/`, no `*-selftest.sh` |
| AC-12 | satisfied | `:188-192` header row present with no data rows, plus the explicit "No release has been evaluated yet — the table has no rows." |
| AC-13 | satisfied | `:172-179` names both erasure mechanisms (force-push of `release/next`, `PATCH` of the body) and states the placement must not be "simplified" back into the body |
| AC-14 | satisfied | `:45-48` sequential, one lane at a time, with the contention reason and the #525 citation |
| AC-15 | divergent-inert | `:73-81` mandates build model, review model and round cap explicitly, all three recorded on the row. measured: `--max-continuations` is a hard refusal at `orchestrate-lean.sh:332`, so a launch obeying the AC as written would not start. follow-up: none owed — #718 removed the flag and the continuation budget it bounded, so it does not return; D-16 carries the DEPARTURE |
| AC-16 | satisfied | `:38-43` fresh issues each release, with the reason — per-issue lane state is keyed on the issue number and `timing` would silently report release-to-release elapsed time |
| AC-17 | satisfied | `CLAUDE.md:174`, one pointer line beside the existing per-doc pointers |

## Verdict

**needs-work** — one blocker, and it is not the document's.

The doc work asked for by rounds 1 and 2 is **done**. Blocker 1 of round 2 is fixed by property
rather than by citation, the false closure clause is gone and its replacement survives being
checked against the producer, and AC-3 is satisfied for the first time on this ticket. Findings 2
through 5 are one word, one clause, one sentence and half a clause respectively; none blocks, and
none is worth a round on its own.

The single blocker is AC-10, which has been the same blocker for three rounds and is **waiting on
an operator decision, not on the build**. The ask is posted, correct, and unanswered; the
intent-gap record reads `ratified: no`; `lean-evidence.sh` holds the PR red on exactly that arm.
Approving now would not shorten anything, because ratification writes `ratified: yes` and a
`ratified_by:` URL into a committed file — a changed line, which voids this record the moment the
operator answers. So `needs-work` costs nothing that was not already owed, and the next round
should be cheap: if the operator defers, findings 2 through 5 are the entire remaining edit.
