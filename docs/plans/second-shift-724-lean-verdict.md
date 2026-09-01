# lean review verdict — #724

verdict=approve
run_id: review-724-6
session_id: 1d1a974c-5120-477e-961b-8c63603600f9
rounds: 6
pr: #761
reviewed_head: 6b46ea508906b2b21fec9c9aea7a88140117e9c4
reviewed_patch_id: 6f6d52e60d519c0482802f9f67636088629b4ad4
inherited_patch_id: ff054c3cb5e887190586ed41194163afd9c87153
inherited_from_verdict: 40bdf144f9e5c194c593df1fd0d181dfa299117f
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:maintainability-reviewer
model: unknown
capabilities: pr-marker

# Review round 6 — PR #761 (issue #724)

Range read: `40bdf144..HEAD`, one file (`docs/consumer-eval.md`), inheriting patch `ff054c3c`
from round 3's record. **Read wider than the range**: the whole of `docs/consumer-eval.md`
(231 lines), `docs/releasing.md`, `CLAUDE.md`'s pointer, the committed spec, and all 19
`*-lean-launches.tsv` ledgers, because this round's job is an approve over the whole branch and
the delta bounds only the reading.

Rounds 4 and 5 were handed back un-spent and wrote no record — correctly, because the lane's one
open blocker was an operator ratification that no session in it was permitted to answer. This
round is the first since round 3 to certify anything.

## What changed the verdict

Round 3's single blocker was AC-10: the consumer-repo bootstrap replay had not run, the
precondition sat under the issue's **Dependencies** rather than **Deferred**, nothing linked a
follow-up, and `docs/plans/second-shift-724-lean-intent-gap.md` read `ratified: no`. Three review
rounds refused to score it away, and that was right — it was never the build's call.

The operator answered it this session
(https://github.com/manoldonev/second-shift/issues/724#issuecomment-5498810911), ratifying the
first of the two dispositions the intent-gap record offers: **deferred**. #724's body now carries
the precondition under **Deferred** with #774 linked, #774 carries both the consumer bootstrap and
the first fixture replay, and the intent-gap record reads `ratified: yes` with the comment URL, at
commit `6b46ea50`.

**Disclosure.** That ratification commit was authored in this review session, as the operator's
relay and on their explicit in-session instruction, not by a build run. It contains no reviewable
content — a `ratified:` flag and a URL — and every claim in it is falsifiable against the linked
comment, the amended issue body and #774. It is named here rather than left for a reader to
discover in the log.

## Findings

| # | severity | finding |
| --- | --- | --- |
| 1 | resolved | AC-10's unratified bootstrap deferral — round 3's blocker, and the scope panel's blocker again this round on the same grounds ("the ratification is asserted but exists in no evidence surface"). Now landed as evidence: issue body amended, #774 filed, `ratified_by:` committed. |
| 2 | minor | `docs/plans/second-shift-724-lean.md:209` — D-10 cites `.github/workflows/release-pr.yml:94,110` for the force-push; line 94 is the `git commit`, the force-push is line **95**. Spec-only; the shipped `docs/consumer-eval.md:192-197` cites no line numbers and is correct. Not worth a round. |
| 3 | minor | `docs/consumer-eval.md:158` — "`#644` and `#668` are entirely `attended-build-turn` / `attended-review-turn`, `preflight-rejected` and `dry-run` groups" is true of the pair collectively, not of each: #644 has no `dry-run` group and #668 has no `preflight-rejected` one. Verified directly against both ledgers. The load-bearing property — zero `spawn` rows — holds on each individually, so the sentence's conclusion stands. |
| 4 | observation | AC-6's amendment redirects "columns are exactly those named under Data Contracts" from the issue's table to *this plan's* table, so as amended it can no longer be falsified against anything outside the branch. The substance (dropping `continuationCap`) is well grounded, so this is not a spec-written-to-match-the-diff case; recorded so a later release does not read AC-6 as an external contract. |

**The recurring defect class is closed.** `docs/consumer-eval.md`'s launch-group section shipped a
generalizing sentence contradicted by a later line in its own section in **every** round 1–4. A
dedicated sweep at this head — both copies of the start rule (`:96` and `:221`), the `awk` snippet
between them, every topic sentence against its own bullets, and the `mergedAt`-bound prose against
the post-approve fallback — finds none. `f539bf32` is the first head where an independent read
comes back clean, and rounds 3's findings 2–5 are all discharged.

**Corpus claims re-derived independently**, not inherited: 19 ledgers; 15 `approved` terminals;
exactly `#636`/`#637` bare and 13 PR-suffixed; `#644`/`#668` the only two with zero `spawn` rows;
all 39 terminal column-5 values conforming to `<slug> rc=<n>` plus optional ` — <message>`. Every
figure the delta asserts holds.

## CI

`lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr` are all green at
`f539bf32` — the correctness lanes, and no `AC-n` is contradicted by one. `pr-gates` is red on
exactly the two arms this round and the ratification resolve (`verdict=needs-work`, and
`intent-gap … ratified: no`); both are addressed by this record and `6b46ea50`.
`install-topology` is skipped by its path filter, as designed for a docs-only diff.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | all five stated, not merely headed: corpus obligation `docs/consumer-eval.md:19-48` (roles table `:25-31`), pinned-base recipe `:50-85`, four metric definitions `:87-99`, non-merge rule `:177-185`, recording obligation `:187-201` |
| AC-2 | satisfied | grep for consumer/org/stack identifiers over the added lines of all six changed files returns nothing; the only repo-shaped strings are `.claude/pipeline-state`, `docs/plans`, `release/next` |
| AC-3 | satisfied | all four sources prescribed — `launchToMerged` `:96` with the start rule `:101-169`, `laneWallMin` `:97`, `rounds` `:98` off the verdict record's key, `usd` `:99`. Both amendments re-measured against the tree: the four-row start-rule table reproduces exactly on the real ledgers, and `retro-corpus.sh:382` greps a `round=` token the record grammar no longer writes |
| AC-4 | satisfied | `:56-58` alternate config via `SECOND_SHIFT_CONFIG` differing in exactly one field (`topology.repos.<host>.baseBranch`); `:64-65` the default branch is neither modified nor rewound. All three code citations resolve (`orchestrate-lean.sh:357`, `lean-gate.sh:489`, `lean-gate.sh:529`) |
| AC-5 | satisfied | `:21-36` the five roles bound to `F-1`..`F-5` in that order, and the spec bodies live in the consumer repo, never here |
| AC-6 | divergent-inert | doc header `:207` and column contract `:217-228` carry the ten columns of the spec's Data Contracts, `continuationCap` dropped. measured: `orchestrate-lean.sh:332` hard-refuses `--max-continuations` with a selftest asserting the refusal at `orchestrate-lean-selftest.sh:786-789`, so the column could only ever be empty. follow-up: #718 removed the flag and the budget it bounded, so it does not return; D-16 carries the DEPARTURE |
| AC-7 | satisfied | `:180` null metric set plus the named refusal class, `outcome` = `did-not-merge:<refusal-class>`; `:183` never re-run and never dropped from the row |
| AC-8 | satisfied | `:189` comment on the release PR before it merges, `:190` rows land on `main` separately in their own doc PR, `:199-201` no stated threshold blocks a release automatically |
| AC-9 | satisfied | `docs/releasing.md` step 4 carries all three obligations — run the eval, comment the result, land the rows on `main` — inside the existing numbered flow, with the maintainer-surface block renumbered to match |
| AC-10 | divergent-inert | no consumer-repo replay ran; the PR body's bootstrap block reads `unavailable` on all four metrics with a named reason each. measured: the three preconditions re-measured and all unmet (marketplace `ref: "main"`, six plugins `"latest"`, `configVersion: 1`), so a replay today would enter a canary-shaped figure as the consumer-shaped baseline — worse than no figure; the deliverable is the protocol document, which is complete and whose computability is demonstrated against real recorded ledgers, and no shipped line depends on the replay. The precondition now sits under the issue's **Deferred** section, not **Dependencies**, by operator ratification, and the intent-gap record reads `ratified: yes` at `6b46ea50`. follow-up: #774 |
| AC-11 | satisfied | `git diff main...HEAD --name-status` is six Markdown paths — `CLAUDE.md`, `docs/consumer-eval.md`, `docs/releasing.md` and three under `docs/plans/`. Nothing under `tools/` or `scripts/`, no `*-selftest.sh` added |
| AC-12 | satisfied | `:207-210` header row and separator present with zero data rows, immediately followed by "No release has been evaluated yet — the table has no rows." — the explicit-empty form, not an omission and not a placeholder row |
| AC-13 | satisfied | `:192-197` names both erasure mechanisms and states the placement must not later be "simplified" back into the body. Verified independently: `.github/workflows/release-pr.yml:95` force-pushes `release/next` and `:111` PATCHes the body |
| AC-14 | satisfied | `:45-48` sequential, one lane at a time, with the reason — wall-clock is a compared metric and concurrent lanes contend for CPU, sweep and tracker rate limit; cites #525's single-lane assumption |
| AC-15 | divergent-inert | `:70-73` mandates build model, review model and round cap explicitly with the reason, and the invocation at `:75-78` passes all three. measured: `--max-continuations` is a hard refusal at `orchestrate-lean.sh:332`, so a launch obeying the AC as written would not start; `:80-81` states there is no continuation cap to pass. follow-up: #718 removed the flag and the continuation budget it bounded, so it does not return; D-16 carries the DEPARTURE |
| AC-16 | satisfied | `:38-43` fresh issues each release, with the mechanism as the reason — per-issue lane state is keyed on the issue number and never deleted, so `timing` would report release-to-release elapsed time |
| AC-17 | satisfied | `CLAUDE.md:174`, one pointer line between the `docs/releasing.md` and `docs/pipeline-manifesto.md` pointers |

## Verdict

**approve.** No blockers. The one blocker that stood for three rounds was an operator decision,
not a defect, and it has been taken and landed as evidence. Two minors and one observation are
recorded above; none of them is worth a seventh round on a docs-only branch, and finding 2 touches
a spec line no shipped document repeats.
