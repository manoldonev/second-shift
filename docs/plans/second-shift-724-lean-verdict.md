# lean review verdict — #724

verdict=needs-work
run_id: review-724-2
session_id: b12349aa-a63f-48e0-840e-7cff2e4f9b1a
rounds: 2
pr: #761
reviewed_head: ccd2888f33dad0a29bfd7c50614a1317f83b6e65
reviewed_patch_id: aa4f4ee3275935bf33b7563b7cc3f47389289ac0
inherited_patch_id: 5c7dc64c81ff361be9d7cb72e6743067988b802c
inherited_from_verdict: dfbc711169a9ae1f29979e3efb8fa6f77f7a4ac6
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 2 — PR #761 (issue #724)

Range read: `dfbc7111..HEAD` — the round-2 fix commits `18f9d5c1` and `ccd2888f`, inheriting
patch `5c7dc64c` from round 1's record. Read wider than the range: the whole of
`docs/consumer-eval.md` at this head, round 1's committed findings, and the launch-ledger
corpus the fix's demonstration rests on.

Reviewed head: `ccd2888f33dad0a29bfd7c50614a1317f83b6e65`. Docs-only.

Panel: `review-toolkit:scope-completeness-reviewer` (returned `request-changes`). Trivial-inert
prose diff, nothing under `.claude/`, so the four collapsed dimensions plus security were the
lead pass's. a11y + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (unset, default `apps/web/**/*.{tsx,jsx}`), and the spec carries
no `## Design` section — the run is unarmed. `security-reviewer` not selected: no security
surface in a prose diff and no `.claude/second-shift/review-context/security-reviewer.md` in the
repo; the lead pass owned the dimension.

CI at this head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass. `pr-gates` fails on exactly two lines — the verdict record reading
`needs-work` (the pre-approve state, not a finding) and the intent-gap record reading
`ratified: no` (blocker 2 below). No correctness lane is red.

## Round 1's blockers, re-checked

- **Finding 1 (start rule).** Fixed *in the metrics section*, and the fix is good work — see
  Strengths. **Not fixed in the column contract**, which still carries the falsified rule. That
  is blocker 1.
- **Finding 2 (AC-10).** Correctly parked, correctly asked. Not resolved. Blocker 2.
- **Finding 3 (D-9 unmarked departure, major).** Fixed at `docs/plans/second-shift-724-lean.md:208` —
  D-9 now reads `DEPARTURE — …` and routes the decision to the intent-gap record.
- **Finding 4 (`<stateDir>`/`<key>` placeholders, nit).** Fixed at `:89-91` and `:98`. Verified
  the `<key>` derivation against `lean-gate.sh` (`HOST_Q` selects the `topology.repos` key whose
  `path` is `.`; `VERDICT_REL="$PLANS_DIR/$REPO_SLUG-$ISSUE-lean-verdict.md"`) — the doc's
  statement is exact.

## Findings

| # | Severity | Anchor | Finding |
| --- | --- | --- | --- |
| 1 | **blocker** | `docs/consumer-eval.md:196` | **The round-1 blocker survives in the shipped document.** The metrics table at `:96` was corrected to "the `launch` row of the **last launch group that spawned anything** at or before the merge". The **column contract** — the table a maintainer reads when filling a results row — was not: `:196` still reads `first non-rejected \`launch\` row → PR \`mergedAt\``. That is verbatim the rule round 1 blocked, and which this PR's own body measures as wrong by **13:10–15:16** on all four cited tickets. The document now prescribes two contradictory sources for its headline metric, so AC-3's "prescribes its exact source" is not met by either reading. The parallel table in the spec (`docs/plans/second-shift-724-lean.md:173`) *was* updated, which is what makes the omission legible as a missed second edit rather than a decision. One-line fix. |
| 2 | **blocker** | whole-PR (`docs/plans/second-shift-724-lean-intent-gap.md`) | **AC-10 / Scope-In bullet 4 remains unsatisfied.** No consumer-repo replay ran; all four metrics read `unavailable`. Unchanged from round 1, and the build session's handling of it this round was correct: it wrote the intent-gap record, re-measured all three preconditions rather than repeating round 1's assertion, and posted the ratification ask to #724 as the bot at `07:12:23Z` with both answers spelled out. The record still reads `ratified: no` and no operator comment has landed. AC-10's "or a named reason it was unavailable" covers a metric unreadable from a run that happened; it does not cover the absence of the run. **This one is not the build's to fix** — it needs the operator to amend #724 deferring the bootstrap with a linked follow-up, or to own the replay here. |
| 3 | major | `docs/consumer-eval.md:129-131` | **"It did produce the PR" is false for a reachable shape.** The doc disqualifies the two spawning shapes only by supersession, then closes: "When either is itself the last spawning group at or before the merge, **it did produce the PR** and it is the start." A re-launch onto an already-approved, closed-out lane — the hazard the lane is known for — spawns BUILD at `orchestrate-lean.sh:865` *before* reaching `terminal lane-closed-out` at `:971`. So it writes a `launch` row and a `spawn` row, and if it lands between the approve and the merge it is the last spawning group at or before `mergedAt`. The awk takes it, and `launchToMerged` silently reports the re-launch's wall instead of the merged run's. The `mergedAt` bound was chosen to exclude post-hoc launches; it does not exclude a post-*approve* one. Not a blocker: the rule is correct on **12 of 12** merged tickets in the recorded corpus (I ran it against every `*-lean-launches.tsv`), and the failing shape needs an operator action the lane already warns against. But the sentence asserts a sufficiency the mechanic does not have, and the fix is one clause — bound the search by the approving group, or say the rule assumes no re-launch after approve. |

## Findings dismissed

The panel raised three majors (confidence 88–92) asking for operator ratification of departures
round 1 had already dismissed on measured grounds. I re-verified each and dismiss them again, for
the same reason: **ratification is owed for a scope change, not for a correction of a
codebase-derived fact.**

- **AC-3 `rounds` source** (panel: "not sourced from `retro-corpus.sh timing` as the AC
  prescribes"). Verified by running the instrument: `timing` returns `rounds: null` on every
  recent run while `wallClockMin` beside it is populated, because its `rounds` greps a `round=`
  token the current record grammar no longer writes. AC-11 forbids fixing the instrument here.
  Pointing at a field that is structurally null is not "prescribing an exact source".
- **AC-15 continuation cap** and **AC-6 `continuationCap` column**. Verified: `--max-continuations`
  is an `envfail` at `orchestrate-lean.sh:332`. A launch obeying AC-15 literally would not start,
  and the column could only ever be empty. Scored `divergent-inert`, D-16 carries the DEPARTURE in
  the reconcile-recognized form, and the issue body correctly was **not** back-edited.

The panel also *suppressed* a note asserting round 1's finding 1 "reads as addressed at this
head". It read the metrics section and the column contract's column *count*, but not the column
contract's `launchToMerged` cell. That cell is blocker 1.

## What I verified rather than took on assertion

- **The fix's own demonstration, re-run.** I executed the document's awk against every
  `*-lean-launches.tsv` in the state dir, with each PR's real `mergedAt`, scoring against ground
  truth read independently as the group whose `terminal` says `approved … on PR #<n>`. **12 of 12
  merged tickets match** (#622, #666, #667, #704, #709, #710, #718, #719, #720, #721, #739 and
  #718's own). The two non-matches are #723 and #745, whose PRs are still open — the metric is
  undefined there by construction. The four tickets the PR body cites reproduce exactly, including
  the AC-3-literal figures and the 13–15h errors.
- **`grep -c preflight-rejected` returns 0** on all four cited ledgers, so the exclusion the AC
  names does no work on any of them — the claim that makes the demonstration probative.
- **The first group on all four cited tickets spawned and stranded** (one `spawn`, no `spawn-end`,
  no `terminal`), which is what the AC's literal rule would have taken.
- **Timestamp comparability.** Column 1 of the ledger is `2026-08-30T22:00:07Z` and `mergedAt` is
  the same fixed-width UTC form, so the awk's `f[1] <= merged` string comparison is well-defined.
- **The pre-spawn refusal classes** the doc names, against `orchestrate-lean.sh`:
  `preflight-rejected(-resumable)` `:637,:640`, `env-branch-prefix` `:662`, `dry-run` `:841`,
  `staleness-expired` `:859` — all before the BUILD spawn at `:865`. The list is illustrative and
  says so ("Several refusals"), and the rule keys on the absent `spawn` row rather than on the
  slugs, which is exactly the generalization round 1 asked for. `staleness-unreadable` `:862` is a
  fifth member the list omits; that costs nothing precisely because the enumeration is not
  load-bearing.
- **The `<key>` derivation** against `lean-gate.sh` (`HOST_Q`, `VERDICT_REL`) and the repo's own
  config — `second-shift` is the `topology.repos` key with `path: "."`.
- **The issue's Behavior §4**, which does read "the first `launch` row of **the run that produced
  the merged PR**" — so the AC-3 amendment resolves an internal inconsistency toward the issue's
  own text rather than away from it. The issue body is untouched.
- **AC-2** across all changed files: no consumer, org or stack identifier.
- **AC-6 columns**: the doc's header and the spec's Data Contracts list the same ten, in order.
- The `[REDACTED]` tokens at `docs/consumer-eval.md:80` and in the spec's amendment text are the
  local output filter, not file content — `grep -c REDACTED` returns 0.

## Strengths

The start-rule fix is the right fix, done the right way. It replaced a slug enumeration with the
**observable property** the metric actually turns on — an absent `spawn` row — which is what stops
the enumeration rotting as the terminal vocabulary grows, and it explicitly declines to claim the
list of slugs is complete. Round 2 also moved the demonstration off this ticket's own in-flight
ledger, which grows under the round measuring it, onto four **merged** tickets with real
`mergedAt` values and ground truth read independently of the rule — that is what made it
falsifiable, and it is why I could reproduce all of it in one command. And the build's handling of
AC-10 was exactly right: it re-measured the preconditions instead of citing round 1, wrote the
intent-gap record, and then actually posted the ask, which is the half round 1's build skipped.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | all five stated: corpus obligation `:19-48`, pinned-base recipe `:50-85`, four metrics `:87-150`, non-merge rule `:152-158`, recording obligation `:160-178` |
| AC-2 | satisfied | grepped all changed files and the issue body for consumer/org/stack identifiers — no hit |
| AC-3 | unsatisfied | finding 1 — the document prescribes two contradictory sources for `launchToMerged`: the corrected rule at `:96` and the falsified one at `:196`. The `rounds`, `mergedAt` and `usd` sources are sound (see Findings dismissed), and the launch-timestamp rule at `:96-139` is itself correct on 12/12 merged tickets — but a document that states both cannot be said to prescribe the exact source |
| AC-4 | satisfied | `:55-62` alternate config via `SECOND_SHIFT_CONFIG` naming the eval base; `:57-59` exactly one differing field; `:64-65` default branch neither modified nor rewound |
| AC-5 | satisfied | `:33-35` specs live in the consumer repo; `:25-31` the five roles; `:21-23` `F-1`..`F-5` bind in that order |
| AC-6 | divergent-inert | doc header `:182` and column contract `:194-205` carry the ten columns of the spec's Data Contracts, `continuationCap` dropped. measured: `orchestrate-lean.sh:332` hard-refuses `--max-continuations`, and every live launch row writes three parameters, so the column could only ever be empty. follow-up: none owed — the flag was removed in #718 and does not return; D-16 carries the DEPARTURE |
| AC-7 | satisfied | `:152-158` null metric set plus named refusal class, `outcome: did-not-merge:<refusal-class>`, never re-run and never dropped |
| AC-8 | satisfied | `:162-163` comment on the release PR before it merges, rows land on `main` separately; `:176-178` verdict is operator judgment, no automatic threshold |
| AC-9 | satisfied | `docs/releasing.md:47-54` states all three obligations inside the existing numbered flow, and the maintainer-surface block `:71-79` is renumbered consistently |
| AC-10 | unsatisfied | finding 2 — no consumer-repo replay ran; all four metrics `unavailable`. The precondition is genuinely unmet (re-verified by the build this round) but sits under the issue's **Dependencies**, not **Deferred**, with no linked follow-up. The intent-gap record reads `ratified: no` and the ratification ask is outstanding, so the deliverable is neither delivered nor deferred by any authority this round can read |
| AC-11 | satisfied | `git diff --name-only origin/main...HEAD` is six Markdown files; nothing under `tools/` or `scripts/`, no `*-selftest.sh` |
| AC-12 | satisfied | `:182-186` header row present with no data rows plus the explicit "No release has been evaluated yet — the table has no rows." |
| AC-13 | satisfied | `:166-172` names both erasure mechanisms and says the placement must not be "simplified" back into the body |
| AC-14 | satisfied | `:45-48` sequential, one lane at a time, with the contention reason and the #525 citation |
| AC-15 | divergent-inert | `:70-78` mandates build model, review model and round cap explicitly, all three recorded. measured: `--max-continuations` is an `envfail` at `orchestrate-lean.sh:332`, so a launch obeying the AC as written would not start. follow-up: none owed — #718 removed the budget the flag bounded; D-16 carries the DEPARTURE |
| AC-16 | satisfied | `:38-43` fresh issues each release, with the reason — per-issue lane state is keyed on the issue number and `timing` would silently report release-to-release elapsed time |
| AC-17 | satisfied | `CLAUDE.md:174`, one pointer line beside the existing per-doc pointers |

## Verdict

**needs-work** — two blockers. Blocker 1 is a one-line doc edit: `docs/consumer-eval.md:196` still
carries the rule round 1 falsified, while `:96` carries its replacement. Blocker 2 is not the
build's to resolve — the ask is posted and correct, and it is waiting on the operator. Finding 3
is a major worth folding into the same edit while the round-trip is happening.
