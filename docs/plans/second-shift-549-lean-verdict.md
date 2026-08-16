# lean review verdict — #549

verdict=approve
run_id: review-549-2
session_id: 3ef5b61c-15ae-492e-ac74-f5066937db61
rounds: 2
pr: #560
reviewed_head: 85565443106162aca710ca6319533f6114ce4867
reviewed_patch_id: 3d7c387da499bf88e3539f75ab06692f1aa8ea6e
inherited_patch_id: 07655a0bf0dbd108d5b20fa2aceb477ae68ae538
inherited_from_verdict: 574537b57076ccd28ad023438da9de4b9ac36ced
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #560 (issue #549)

**Range read:** `574537b..HEAD` — one commit, `docs/plans/second-shift-549-lean.md`.
Round 2 inherits round 1's coverage of patch `07655a0bf0db` and its findings, and re-read
the whole branch besides (two files, both docs).

**Panel:** maintainability-reviewer (approve, 0 findings) and scope-completeness-reviewer
(request-changes, 2 major). Both returned usable results — no dark reviewer this round.
Trivial-inert routing: the sole changed path is a Markdown doc outside `.claude/`, so
security / performance / complexity / test-coverage were not selected. a11y and the
design-fidelity dimension were not routed — no changed path matches
`stageParams.webComponentGlobs` (unset, resolving to the shipped `apps/web/**` default).

---

## Verdict: approve — no blocker in the reviewed patch

Round 1's blocker is discharged. Its gating half was an operator answer, and the answer
landed on the issue at `2026-08-16T20:26:22Z`: **OR-1 closed as answered, question 2 taken,
the phase-completion-contract re-scope declined, PR #560 to merge as the measurement
record.** Its buildable half — enumerating the nine receipt items a closure would dispose
of — is done in the delta, with the question-2 resolution pre-written for the whole table.

One defect survives and it is **not in the tree**, so it does not cost a round. It is a
precondition on the merge, recorded below.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — the probe, recorded per candidate per criterion (D-2, D-3) | **satisfied** | Strengthened this round. Candidate C's unreachable rows now render `—` with the reason, matching candidate B's own convention; candidate D's criterion (iv) carries the renderer caveat as a footnote; and the uncommitted-evidence weakness is stated outright. I re-verified the delta's falsifiable claims independently: `608e57c` did carry AC-1..AC-10, `5bd3654` carries three, and the reverted implementation is genuinely unrecoverable — no dangling object, stash or reflog entry in the store mentions `LEAN_PHASE_TRANSPORT`. |
| AC-2 — the stop, and what it is asking for (OR-1) | **satisfied** | The stop is recorded, the withdrawal of the ten-AC implementation spec is disclosed with its licensing (OR-1's intake-written `pause-and-ask`), and the two-way question is stated. The question has since been answered — see W-1, which is a staleness warning and not an AC failure: AC-2's obligation is to record the stop and what it asks for, and it does. |
| AC-3 — nothing is claimed that was not measured | **satisfied** | Verified against the diff: two documents, no behavior, no seam, no asserted improvement. D-6's exit criterion is declared unmet rather than finessed, and the delta narrows two claims rather than widening any. |

All three ACs hold, as they did at round 1. The delta only strengthens them.

---

## Merge-boundary precondition (fix before merging; no round required)

### P-1 — `Closes #549` is inside a code span, so merging will not close the issue

The PR body's trailer is written as `` `Closes #549` ``. GitHub does not honour closing
keywords inside code spans, and it hasn't: `gh pr view 560 --json closingIssuesReferences`
returns `[]`. The lane has no compensating step — `orchestrate-lean.sh` and both lean
SKILLs carry no `gh issue close`; `build-lean/SKILL.md:26` relies entirely on the keyword.

So the operator's stated outcome — *"PR #560 merges as the measurement record. This issue
closes on that merge"* — will not happen. #549 would stay open, still labelled
`in-progress`, with its claim intact.

**Why this is not a blocker and not a round.** The remedy is a PR-body edit: unbacktick the
trailer to a bare `Closes #549`, or close #549 by hand at merge. A body edit changes no line
of the tree, so it neither invalidates this record's `reviewed_patch_id` nor needs a build
session. Forcing `needs-work` here would spend two sessions to change one backtick.

**It is recorded here rather than only in the PR comment** because the merge boundary reads
this file, and a precondition that lives only in prose is not a precondition.

**Note on round 1.** B-1 read the trailer as live and blocked on the ticket auto-closing
while OR-1 was open. It never was live, so that specific mechanism was overstated — the
underlying concern (nine receipt decisions with no written disposition) was real and is now
addressed both ways.

**Lane defect worth a ticket.** Nothing in the lane verifies that a PR's closing keyword
actually resolves. A backticked, indented or fenced trailer passes every gate on the way to
merge, and the ticket silently survives its own PR. `closingIssuesReferences` being non-empty
is a one-line assertion at the merge boundary under the github adapter.

---

## Warnings

### W-1 — the merged record says the run is paused, three minutes after it stopped being

`:7` reads *"This run is PAUSED on OR-1"*, `:194` reads *"Every row below is `parked —
awaiting OR-1`"*, and `:220` reads *"the question is on the issue and the run is paused"*.
OR-1 was answered at `20:26:22Z`; head `8556544` is dated `20:23:13Z`. The document is stale
rather than negligent, but it merges stale and stays that way on `main`.

The three survivors the answer routes — **#563** (`--cache-dir` close-out re-sweep,
ready-for-dev), **#565** (perf-retro timing baseline) and **#566** (milestone-3 long-sweep
supervision) — appear nowhere in the file. I verified all three exist and are open.

**Accepted rather than blocked**, for two reasons. The disposition is recoverable without
the edit: the document's own conditional at `:194-196` resolves the whole table under
question 2 to *"closed as answered; no transport lands, so nothing here has a subject"*, and
the operator's comment on the linked issue supplies the answer in the lane's own canonical
form — a non-bot comment naming the region, which is exactly the resolution artifact
`lean-gate.sh`'s milestone-1 guard reads. And the fix is a tree edit, so it costs a full
round on a docs-only record whose every measurement is accurate. If the operator wants the
merged artifact self-consistent, the cheapest route is a follow-up docs commit on `main`
after the merge, not a round here.

### W-2 — OR-2 is a `pause-and-ask` region and nothing names it

`549-ledger.md` disposes both OR-1 and OR-2 as `pause-and-ask`. The operator's answer names
OR-1 only; no non-bot comment on #549 mentions OR-2 (checked against the guard's own
word-boundary pattern). The spec scores OR-2 "partly answered" from measurement.

Practically inert — OR-2 asks whether a yielded phase is genuinely re-invoked *under the
winning transport*, and there is no winning transport, so it dissolves with the rest of the
table under question 2. Worth knowing rather than fixing: once #556's ledger-reading guard
ships in a release, an unresolved OR-2 would refuse milestone 1 on any run reading this
ledger. Since #549 closes here, nothing reads it again.

---

## Suggestion

### S-1 — "ten argv-bound prompt assertions" undercounts

`:163` describes the `spawn_prompt` accessor as decoupling *"the selftest's ten argv-bound
prompt assertions"*. On this branch `orchestrate-lean-selftest.sh` carries **18** such
assertions across 9 call sites. "Ten" reads like a case count that drifted into an assertion
count. Nothing turns on it — the point that the accessor is a prerequisite for any transport
moving the prompt off argv is right, and is the most reusable sentence in the section.

---

## Strengths

- **The three warnings were addressed without inventing anything.** W-2 and S-1 were fixed
  by adopting a convention the document already had, and W-3 was closed the only honest way
  available — disclosed rather than regenerated, with the explicit reasoning that
  re-measuring gone transcripts would present a new measurement as the old one.
- **The parked-items table split an operator-gated blocker into the half that was
  buildable.** It also surfaced something the blocker's framing had hidden: D-4 and D-7 are
  each *partly discharged* — scored per candidate as criteria (iv) and (iii) — rather than
  merely parked, and the table says so instead of conceding a mass "not done".
- **The withdrawal disclosure names its own cost.** It records that ten ACs were withdrawn,
  that the implementation is unrecoverable, and where that lands — on the re-scope branch
  that would have reused the `spawn_prompt` accessor. Most runs would have disclosed the
  first and quietly dropped the third.
- **Every falsifiable claim I could re-measure held.** Across two rounds: CLI `2.1.233`,
  `tmux` absent, the `--bg`/`--print` refusal quoted to the word, `--tmux` requiring
  `--worktree`, the AC-1..AC-10 withdrawal at `608e57c`, and the implementation's absence
  from the object store. Nothing was rounded in the author's favour.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Maintainability | Pass | 0 | — |
| Scope Completeness | Fail | 2 | 92–95 |

Scope-completeness returned `request-changes`. Both of its findings are carried above — one
as the merge precondition P-1 (confirmed independently: `closingIssuesReferences` is `[]`),
one as W-1. Neither is a defect in the reviewed patch, and the scope gate's own subject —
whether the diff covers the issue's scope — is satisfied by OR-1's answered `pause-and-ask`,
which pre-authorised the stop at intake and has now been exercised by the operator.

Fidelity: **not-applicable** — the repo configures no design provider (`design: null`) and
the spec carries no `## Design` section, so the arming condition is not met.

## Verification cross-checks (reviewer-run)

- `check-frozen-files.sh main` — clean, no release-owned files touched.
- `check-changelog-trailer.sh main` — no `plugins/**` change; the commit carries
  `Changelog: none` regardless.
- The round-1-response commit carries the bot identity as author and committer, and the
  honest verb for a docs-only branch (`docs(dev-pipeline):`).
- `pr-gates` red at `8556544` is the expected pre-handoff shape and nothing else:
  `check-lean-chain.sh` refusing on round 1's `verdict=needs-work`. `lint-and-selftests`,
  `selftests (macos, bash 3.2)` and `mutation-sweep-pr` are all green.
- The branch edits no guard, so there are no re-keyed mutation ordinals and no
  `mutation-catalog.tsv` row to re-anchor — the document's own claim, verified.
- The parked table's nine rows reconcile against the receipt: D-1/D-4/D-5/D-7/D-8/D-10 plus
  the three `## Testing` obligations. D-11 appears as "Testing 1" without its ID; D-2/D-3 are
  discharged by AC-1, D-6 by AC-3, D-9 and D-12 under "Out of scope". Nothing is missing.
- PR head re-checked immediately before writing this record: `8556544`, matching origin,
  worktree clean.
