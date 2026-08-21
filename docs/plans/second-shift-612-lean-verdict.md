# lean review verdict — #612

verdict=approve
run_id: review-612-1
session_id: f45e2e16-1ee5-4022-8b65-b23fb3f655f0
rounds: 1
pr: #620
reviewed_head: e3908776e8bb50b19c40f60dfdbd016a024f1bd0
reviewed_patch_id: 9144e8bca9b968562a9b744f601831deb3ec7103
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full branch range (`f51f7d87..e3908776`) — no prior record to inherit from.
Panel: 7 reviewers, all returned; none dark. Zero blockers.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cf-a`/`cf-a2`/`cf-a3`/`cf-i` pin row order, id set, the dropped `Kind` cell, the surviving escaped pipe and cell padding. Confirmed beyond the fixture: all 49 on-disk pre-flight ledgers project with **zero row loss** (source `D-n` count equals projected count on every one). |
| AC-2 | satisfied | `cf-c` compares the reprojection byte-for-byte over the whole document, not just the rows; `cf-j` isolates the four-column pass-through the idempotence rests on. `cf-e`/`cf-f` assert an EMPTY stdout alongside the non-zero exit, which is the half that makes "no partial projection" a real assertion. Reprojection verified byte-identical across the 7 corpus receipts that pass `--receipt`. |
| AC-3 | satisfied | `cf-b` asserts both halves — the fixture really passes `--receipt`, so the green cannot rest on a lapsed premise. Corpus-verified: 7/7 receipt-mode-valid receipts project to plan-mode-clean output, and all 49 ledgers project lint-clean regardless. `ledger-lint.sh`'s arity semantics are byte-identical to base (the diff is comments and two lockstep markers). |
| AC-4 | satisfied | `build-lean/SKILL.md` milestone-1 step 4 names `ledger-carry-forward.sh <ledger>` as the route; the `DEPARTURE — <reason>` refusal text is unchanged. File is still 48 lines, inside the skill cap. |
| AC-5 | satisfied | Every enumerated case is present and named, plus `cf-i`/`cf-j`/`cf-k`/`cf-l`/`cf-m`. 16 cases, green under both bash 5.3 and bash 3.2. |

Design: `not-applicable` — the spec disarms with `Design: none`, and the repo's config
declares no design provider, so the disarm is justified rather than a skipped step.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `ledger-carry-forward.sh:151-152` | The emitted table header and separator are the one part of D-3's "emit the whole section" contract that **nothing asserts**. Verified by probe, in an isolated worktree: renaming the header's fourth column, and separately deleting the separator line entirely, each leaves all 16 cases green. The second mutant makes the emitted section stop being a markdown table at all — a defect every reader of the committed plan would see, and the suite would not. `cf-c`'s byte-compare cannot catch it (a mangled header reproduces itself identically), and neither can `cf-b`, because the lint scans the section heading and the `D-n` rows and ignores everything between them. One assertion on the two literals in `cf-a` closes it. |
| 2 | Suggestion | `ledger-carry-forward.sh:61` | The readability guard has no exercising case. Probed: with it removed, an existing-but-unreadable receipt exits 1 with a raw `grep: … Permission denied` on stderr instead of exiting 2 with the named IO error — precisely the confusion the guard's own comment says it exists to prevent, and the suite stays green. |
| 3 | Suggestion | `ledger-carry-forward.sh:48` | `cf-m`'s two-sided assertion is a real improvement, but it does not pin the range's **top** boundary. Probed: narrowing the range by one line still satisfies all three of its checks. Low impact — help text only. |
| 4 | Suggestion | `ledger-carry-forward.sh:51` | The duplicate-positional-argument guard is unexercised. Weaker than it first reads: with the guard removed the exit code for the tested shapes is unchanged, so the observable consequence is that a two-argument invocation silently projects the **second** file rather than refusing. |
| 5 | Suggestion | `docs/testing.md` | The helper now holds a second copy of the lint's trailing-blank-cell arity rule, deliberately in a different idiom (D-4/D-5). That reasoning lives in the plan, which is a historical artifact, not in the durable register. CLAUDE.md routes a real-but-unanchorable coupling to *Couplings considered and declined*; this one qualifies, and the section's own framing — an omitted decision is one that gets re-litigated — is the argument for adding the row. |

None of these is a blocker. Findings 1-4 are surviving mutants, which this repo treats as
data rather than as a red, and the CI sweep at this head is green with no baseline-absent
survivor. Finding 5 is a convention gap, not a defect.

Reviewer nit not carried forward: the scope reviewer flagged AC-3's phrase "the lint itself
is unchanged" against the fact that `ledger-lint.sh` is textually modified. Dismissed on the
diff — the change is two comment lines and a lockstep marker pair; `EMPTY_FORM`,
`PROVENANCE_ENUM`, `KIND_ENUM` and `normalize_arity` are byte-identical to base, and the
plan's Implementation section declares the marker addition in advance rather than
retrofitting it. AC-3's own sentence scopes the claim to arity semantics.

## Evidence gathered independently of the panel

- **The gate the helper actually feeds.** Built a minimal plan from each projection and ran
  `ledger-lint.sh --reconcile <receipt> <plan>`: 47 receipts carrying bound rows reconcile
  clean, 2 are inert, **0 red**. AC-3 only claims the plan-mode lint passes; this is the
  stronger end-to-end property the milestone-1 refusal is built on, and it holds.
- **Toolchain lanes.** Suite green under bash 3.2.57 as well as 5.3.9; shellcheck clean on
  all three touched scripts; `check-lockstep-pairs.sh` 23/23 with the new
  `ledger-empty-form` pair matched.
- **Edge probes.** CRLF rows project clean and lint clean, with the carriage return landing
  in the dropped trailing cell rather than in `Provenance`. An escaped pipe in the last
  preserved cell survives while one in the dropped `Kind` cell goes with it. A row with a
  genuinely empty `Provenance` projects and is then caught by the lint — the division of
  labor D-6 declares, working as declared.
- **CI at this exact head.** `lint-and-selftests`, `selftests (macos, bash 3.2)` and
  `mutation-sweep-pr` all pass. `pr-gates` is red for the missing verdict record alone,
  which this record supplies. The one sweep survivor, a catalog row on `ledger-lint.sh`,
  is baseline-accepted and pre-existing — not introduced here.

## Strengths

- The suite's two anti-vacuous-green moves are the real asset: asserting an **empty stdout**
  on every refusal path rather than only a non-zero exit, and asserting the `--receipt`
  premise alongside the plan-mode conclusion so a green cannot survive the premise lapsing.
- The parser is not reused from the lint, and the header says why in terms of the contract —
  the lint's parse trims and normalizes, which is disqualifying for a projector whose whole
  job is byte-preservation. That is a reasoned divergence, not an accidental second parser.
- Buffering the whole projection so a partial table can never reach a redirect is the right
  shape for the failure this helper exists to prevent.
- The empty-form copy is held by a lockstep pair rather than by prose, and the input carrying
  neither rows nor the form is refused rather than defaulted — the helper declines to assert
  something the receipt never said.
