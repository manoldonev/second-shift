# Reviewer panel — return rate, yield and cost (#661)

What each `review-lead` panelist returned for what it cost, over a pinned corpus of review rounds,
and the per-class dispatch decision that follows. Filed under #661 as the measurement that must
exist *before* a dispatch change; the routing edit that consumes it is #667's.

This is a **judgment register with its measurement attached**, in the shape
`tools/gate-ablation-classes.tsv` established: one row per decision point, each carrying the
regression class it alone catches. It ships as markdown rather than TSV because no generator reads
it — `gate-ablation-classes.tsv` is a TSV because `gate-ablation.awk` parses it, and a register
with no consumer is the dead-weight class `prose-budget.sh`'s own header names.

## The corpus

Every **distinct blob** of `docs/plans/*-lean-verdict.md` first committed on or after **2026-08-16**
and reachable from any ref: **56 record-versions across 43 issues**, one per review round. Derive it
with

```
git log --all --diff-filter=AM --date=short --pretty='%H %ad' --name-only -- 'docs/plans/*-lean-verdict.md'
```

then `git rev-parse <sha>:<path>` per version, deduplicated on the blob.

**Dedup on the blob, not the commit.** A record committed on its lane branch and again on `main` at
merge is one round; counting commits inflates every denominator. Here 68 versions collapse to 56
rounds.

The window is the *recent* corpus, not all history: it spans the current dispatch shape, and every
round in it was read end to end rather than sampled.

## Counting rules

- **Dispatch** — the record names the panelist as selected for that round. "Not routed" and "not
  selected" are not dispatches; the records distinguish those from darkness explicitly and this
  measurement keeps the distinction.
- **Dark** — the record states the panelist emitted no usable text (`died-after-retry`, turn-budget
  cap). Counted once per round, not once per attempt.
- **Degraded** — the panelist returned, but returned an emit-truncation artifact rather than a
  reading (an "interim block; classification in progress" blocker over unverified items). Recorded
  separately: it is a return, and it is not a review.
- **Blocker raised / upheld** — raised is a finding at blocker severity (`request-changes`, `FAIL`,
  `blocker`); upheld is one the round's verdict carried as a blocker.
- **Finding carried** — a non-blocker finding (warning, minor, nit, note) the record carried, **and
  credited by name to the panelist**. Findings the record does not attribute are not counted as
  panel yield: these records are explicit when a finding is a panelist's and equally explicit when it
  is the session's own — #590 states "the three warnings below are the orchestrator's own reading of
  the diff, not reviewer findings" — so crediting the unattributed would invent yield the records
  deny. Self-suppressed sub-threshold items are not carried findings.

### Rounds excluded from the rate denominators, by class

Named rather than dropped — a denominator that silently excludes what it could not read reads as
complete coverage.

| Class | Rounds | Records | Why excluded |
| --- | --- | --- | --- |
| `count-only` | 6 | #503, #546 (`49565961`), #566, #609 (`aee802dc`), #612, #629 | The record states a panel size and a dark count but never names the roster, so no dispatch is attributable to a panelist. Their **attributed yield is still real and is not lost**: 4 findings (scope 1, test-coverage 2, security 1), 0 blockers, 0 dark. |
| `no-panel` | 2 | #539 (`2498cc28`), #643 | No panel was dispatched — an inheriting round covered directly, and a prose-only round with no code surface. |
| `no-record` | 1 | #141 | The record makes no statement about a panel at all. |

That leaves **47 roster-named rounds** carrying **260 dispatches**, which is the denominator for
everything below.

## Per-round measurement

`blockers` reads `raised / upheld`.

| Issue | Record blob | Class | Dispatched | Dark | Degraded | Blockers | Findings carried |
| --- | --- | --- | --- | --- | --- | --- | --- |
| #503 | `1f270725` | count-only | — | — | — | — | scope:1 |
| #539 | `2498cc28` | no-panel | — | — | — | — | — |
| #539 | `2d46f482` | named | sec,perf,comp,pipe,maint,scope,tcov | tcov | — | — | maint:1 |
| #533 | `40e350a3` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #531 | `741149e0` | named | sec,perf,maint,comp,tcov,scope | tcov | — | scope:1 / — | scope:1 |
| #530 | `b3afa4f9` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #549 | `e0b89af0` | named | maint,scope | — | — | scope:2 / — | — |
| #552 | `2c82ac43` | named | sec,perf,maint,tcov,scope | — | — | — | scope:1 |
| #348 | `939292be` | named | sec,maint,tcov,scope | — | — | — | scope:3 |
| #569 | `c648c7a4` | named | sec,perf,maint,comp,tcov,scope | — | — | scope:1 / — | scope:1 |
| #542 | `225df91e` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #574 | `239303cc` | named | sec,perf,maint,scope | — | — | — | scope:1 |
| #563 | `5b5afe76` | named | sec,perf,maint,comp,tcov,scope | — | — | — | scope:1 |
| #562 | `b4bc357b` | named | sec,perf,maint,comp,tcov,scope,utm | tcov | — | — | — |
| #579 | `2a6544da` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #517 | `74b4988d` | named | sec,perf,maint,comp,tcov,scope | — | — | — | scope:3 |
| #585 | `b90cd788` | named | sec,perf,maint,comp,tcov,scope,utm | — | — | — | — |
| #604 | `016c1d9a` | named | sec,perf,maint,scope | — | — | — | — |
| #575 | `11ba6fbd` | named | sec,perf,maint,comp,tcov,scope | tcov | scope | scope:1 / — | — |
| #582 | `236a1f1d` | named | sec,perf,maint,comp,tcov,scope | — | — | — | tcov:1 |
| #580 | `272a705c` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #583 | `32d48a3a` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #597 | `3cf6fe1c` | named | sec,perf,maint,comp,tcov,scope | — | — | — | tcov:1 |
| #546 | `49565961` | count-only | — | — | — | — | tcov:2 |
| #546 | `52ea3c79` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #351 | `62cb87f6` | named | sec,maint,comp,tcov,scope | — | — | scope:1 / — | maint:1,tcov:1 |
| #565 | `9b52b1d8` | named | maint,comp,tcov,scope | — | — | — | — |
| #609 | `aee802dc` | count-only | — | — | — | — | sec:1 |
| #611 | `c45a65cb` | named | sec,perf,maint,comp,tcov,scope | — | — | — | maint:1 |
| #597 | `dd242bd3` | named | sec,perf,maint,tcov,scope,utm | — | — | — | maint:1,tcov:1,utm:2 |
| #141 | `e45768a9` | no-record | — | — | — | — | — |
| #581 | `f501e6ac` | named | maint,scope | — | — | — | — |
| #613 | `01c73c85` | named | sec,perf,maint,comp,tcov,scope | tcov | — | — | sec:1 |
| #610 | `0950f4bb` | named | sec,perf,maint,comp,tcov,scope | — | — | — | tcov:1 |
| #590 | `34104ff9` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |
| #609 | `4c9ee9b3` | named | sec,maint,comp,tcov,scope | — | — | — | — |
| #566 | `55f7fb0d` | count-only | — | — | — | — | — |
| #613 | `6c619cd7` | named | sec,perf,maint,comp,tcov,scope | — | — | — | sec:1 |
| #612 | `94208b25` | count-only | — | — | — | — | — |
| #610 | `9fc3c8e9` | named | sec,perf,maint,comp,tcov,scope,utm | — | — | utm:1 / — | utm:1 |
| #629 | `a16c0b2a` | count-only | — | — | — | — | — |
| #610 | `a67bde1c` | named | sec,maint,comp,tcov,scope,utm | — | — | scope:1 / scope:1 | scope:1 |
| #610 | `a7d522f8` | named | sec,maint,comp,tcov,scope,utm | — | — | — | utm:1,scope:1 |
| #610 | `fb8f5812` | named | sec,perf,maint,comp,tcov,scope,utm | tcov | — | — | — |
| #610 | `fc57325a` | named | sec,perf,maint,comp,tcov,scope,utm | tcov | — | — | utm:1 |
| #643 | `3afdc678` | no-panel | — | — | — | — | — |
| #641 | `b41d2a4f` | named | maint,comp,tcov,scope | tcov | — | scope:1 / — | scope:2 |
| #650 | `e5bac9e2` | named | sec,perf,maint,comp,tcov,scope | tcov | scope | — | sec:1 |
| #647 | `525503d0` | named | sec,perf,maint,comp,tcov,scope | — | — | — | scope:2 |
| #642 | `5409d1b3` | named | sec,maint,comp,tcov,scope,utm | — | — | scope:1 / scope:1 | utm:1 |
| #636 | `c0cfc997` | named | sec,perf,maint,comp,tcov,scope | — | — | — | tcov:1,scope:1 |
| #642 | `d0f2a988` | named | sec,perf,maint,comp,tcov,scope,utm | maint,tcov,utm | — | scope:1 / scope:1 | — |
| #642 | `d71043e2` | named | maint,scope | — | — | — | — |
| #647 | `dea10754` | named | sec,perf,maint,comp,tcov,scope | — | — | sec:2 / sec:2 | — |
| #644 | `3f2e503e` | named | maint,scope | — | — | scope:2 / — | scope:1 |
| #637 | `843f68ef` | named | sec,perf,maint,comp,tcov,scope | — | — | — | — |

## Per-panelist aggregate

Over the 47 roster-named rounds. `cap` is the agent's `maxTurns`; `tier` is its
`REVIEWER_MODEL` entry in `plugins/dev-pipeline/workflows/code-review.mjs`.

| Panelist | tier | cap | Dispatches | Dark | Dark rate | Degraded | Blockers raised | Blockers upheld | Findings carried |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `scope-completeness-reviewer` | reasoning | 30 | 47 | 0 | 0% | 2 | 12 | **3** | 19 |
| `maintainability-reviewer` | code | 15 | 47 | 1 | 2.1% | 0 | 0 | **0** | 4 |
| `security-reviewer` | reasoning | 15 | 41 | 0 | 0% | 0 | 2 | **2** | 3 |
| `test-coverage-reviewer` | code | 15 | 41 | **10** | **24.4%** | 0 | 0 | **0** | 6 |
| `complexity-reviewer` | code | 15 | 38 | 0 | 0% | 0 | 0 | **0** | 0 |
| `performance-reviewer` | code | 15 | 35 | 0 | 0% | 0 | 0 | **0** | 0 |
| `unit-test-mutation-reviewer` | code | 30 | 10 | 1 | 10% | 0 | 1 | **0** | 6 |
| `pipeline-reviewer` | code | 15 | 1 | 0 | 0% | 0 | 0 | **0** | 0 |
| **total** | | | **260** | **12** | 4.6% | 2 | 15 | **5** | 38 |

Two facts carry every decision below.

**Blockers are concentrated in two panelists.** All 5 upheld blockers are theirs —
`scope-completeness-reviewer` 3, `security-reviewer` 2. Across the other six panelists' 172
dispatches, one blocker was raised at all (`unit-test-mutation-reviewer`, #610 `9fc3c8e9`, refuted
on execution and not upheld) and none survived into a verdict. The
core four (`performance`, `maintainability`, `complexity`, `test-coverage`) are **not** zero-yield —
they carried 10 non-blocker findings between them — but their blocker column is zero, and a
non-blocker finding does not gate a merge.

**Darkness is concentrated in one panelist.** `test-coverage-reviewer` accounts for 10 of 12 dark
events. Its dispatch already carries `BOUNDED_EXPLORATION`, the nudge `code-review.mjs` records as
the primary and measured fix for this stall class ("took maintainability-reviewer from ~50% to
0/12"), and it still went dark on roughly one dispatch in four.

## Cost

No token meter exists, so cost is reported in **turns** — `maxTurns` is the only budget the harness
enforces per dispatch. A returning dispatch's ceiling is `cap`; a **dark** dispatch's cost is not a
ceiling but a measurement, since a dark agent ran to the cap on both the attempt and its retry by
definition.

| Panelist | Turn ceiling | Of which dark (measured, zero output) |
| --- | --- | --- |
| `scope-completeness-reviewer` | 1,410 | 0 |
| `test-coverage-reviewer` | 765 | **300** |
| `maintainability-reviewer` | 720 | 30 |
| `security-reviewer` | 615 | 0 |
| `complexity-reviewer` | 570 | 0 |
| `performance-reviewer` | 525 | 0 |
| `unit-test-mutation-reviewer` | 330 | 60 |
| `pipeline-reviewer` | 15 | 0 |
| **total** | **4,950** | **390** |

**390 turns — 7.9% of the panel's whole turn ceiling — were spent on dispatches that emitted
nothing**, and 77% of that is one panelist.

## Decisions

`decision` uses the ticket's vocabulary: `keep` (always-spawn), `demote` (dispatched only on a diff
matching its domain), `retire`. `earn_your_keep` names the regression class the panelist alone
catches — the same column `tools/gate-ablation-classes.tsv` carries, and the same discipline: a row
whose column is empty is a row that has stopped paying for itself.

| ID | Panelist | Decision | Basis (row above) | earn_your_keep |
| --- | --- | --- | --- | --- |
| P-1 | `scope-completeness-reviewer` | **keep** | 47 dispatches, 3 upheld blockers, 19 findings — the only panelist with upheld blockers on more than one PR | Spec-vs-diff completeness read from the issue independently of the reviewing session's own scope interpretation. A lead pass cannot self-provide this: it is the same context judging whether it missed something. Its 2 degraded returns are an emit defect, not a yield one — it is already at cap 30 with a conforming deadline. |
| P-2 | `unit-test-mutation-reviewer` | **keep**, conditional dispatch unchanged | 10 dispatches (already domain-gated), 6 findings — the second-highest yield per dispatch | Concrete mutants proposed against the changed guards, which is a prediction no other panelist makes. Two of its three findings in #610 (`9fc3c8e9`) were refuted on execution and one survived — a hit rate that argues for keeping the *dispatch* and verifying the *findings*, which the round already does. |
| P-3 | `security-reviewer` | **demote** to surface-conditional | 41 dispatches; 2 upheld blockers, both on #647 (`dea10754`), plus 3 carried findings on #613 (`01c73c85`, `6c619cd7`) and #650 (`e5bac9e2`) | Auth / tenancy / input-construction defects. All five landed on the four rounds whose diff touched an operator-permission, override or path-rendering surface; the other **37 dispatches carried nothing**. That is the conditional's predicate firing on its own — the trigger keeps every finding the window recorded and stops paying for the rounds with no surface to review. |
| P-4 | `test-coverage-reviewer` | **demote** | 41 dispatches, 0 blockers, 6 non-blocker findings, **10 dark** — 24.4%, and 300 of the corpus's 390 wasted turns | Test-adequacy of a changed guard. Real but never blocking here, and the corpus's single largest source of wasted turns — 300 of 390. Demotion keeps it available on diffs that actually add or change tests; see the emit-deadline mitigation below, which applies whatever the dispatch decision is. |
| P-5 | `maintainability-reviewer` | **demote** | 47 dispatches, 0 blockers, 4 non-blocker findings, 1 dark | Readability defects an author cannot see in their own diff. Non-zero and non-blocking; conditional dispatch keeps it for diffs with a real readability surface rather than paying it on every prose-and-TSV round. |
| P-6 | `complexity-reviewer` | **demote** | 38 dispatches, 0 blockers, **0 findings carried** — its one item in the window (#533, confidence 55) was below threshold and dismissed | *Empty in this window.* Over-engineering and accidental abstraction. Not retired outright, because the corpus is one repo whose diffs are shell guards and prose, where the abstraction surface a complexity reviewer exists for barely occurs. |
| P-7 | `performance-reviewer` | **demote** | 35 dispatches, 0 blockers, **0 findings carried**, 0 dark | *Empty in this window.* Regressions on a hot path. This repo has no hot path, which is a fact about the corpus and not about the reviewer — see the generalization limit below. Demotion, not retirement, is what that distinction buys. |
| P-8 | `pipeline-reviewer`, `db-reviewer`, `a11y-reviewer`, design-fidelity | **not decided** | 1, 0, 0 and 0 dispatches | Undecidable on this corpus. A panelist the window never dispatched cannot be scored by it, and scoring it anyway would be exactly the anecdote AC-2 forbids. They remain conditional, unchanged. |

Every `demote` row leaves the agent in the effective registry and spawnable; none is a deletion.
**This document decides; it does not route.** The routing edit lives in #667 and cites these rows.

### What the routing edit actually did with P-4 through P-7

#667 consumed these four rows as a **collapse into review-lead's in-session lead pass**, not as the
domain-gated dispatch the `demote` vocabulary above describes. So "dispatched only on a diff
matching its domain" is not what shipped for `test-coverage`, `maintainability`, `complexity` and
`performance`: routing selects none of them at any change size, and their dimensions are reviewed
by the reviewing session against a checklist folded from their own agent files. `security-reviewer`
(P-3) shipped as written — surface-conditional. P-1, P-2 and P-8 are unchanged.

The stronger decision rests on a wider corpus than this window: #667 attributed blockers across all
248 committed verdict-record versions rather than the 56 pinned here, and found the same zero in
the blocker column for all four, with the dark surface concentrated in the same place. What that
window adds is that the reviewing session already re-derives these dimensions under the Sub-Agent
Trust Model, so the dispatch was being paid twice rather than being the only thing covering them.

That premise holds by construction on the lean lane — `review-lean` reviews from a session that did
not author the change — and it does not hold on `pr-revision`, which runs review-lead in dispatch
mode from the session that wrote the fix, making the four author self-review there. Accepted, not
fixed: that review is advisory and non-blocking by its own contract, and the four's blocker yield
is zero on both corpora, so the dimension it weakens was not paying anyway.

The measured columns above are untouched by that, and the decision is reversible in the direction
this table wrote: every panelist stays in the effective registry and stays spawnable on demand or
by config, so restoring a domain-gated dispatch for any of the four is a routing edit and nothing
more.

## Mitigation that lands with the measurement

`check-emit-deadline.sh` enrolls agents at the default cap only on a **demonstrated** death. The
dark column above is that demonstration, so `test-coverage-reviewer` (10) and
`maintainability-reviewer` (1) join `DEADLINE_AT_DEFAULT` and carry a turn-10 write-by deadline;
no panelist with a zero in that column is enrolled.

The dispatch-time bounding nudge is already on both, and did not hold — which is the shape that
lint's own header records for `spec-reviewer`, where a nudge was in place and the death happened
anyway, and its stated lesson: *"a demonstrated death earns both, not either."* Corroborating
out-of-window events for `maintainability-reviewer`, labelled as corroboration and not counted in
any rate above: #378 and #381, both `died-after-retry` at the cap.

## What this does not measure

- **Warnings the records did not attribute.** Counted as the session's own by the rule above. If
  some were a panelist's and went uncredited, every `findings carried` figure is a floor.
- **Consumer repos.** Every round here is second-shift's own dogfood: shell guards, CI workflows and
  markdown. `performance`, `db`, `pipeline` and `a11y` have almost no surface to work on in this
  tree, which is why P-6 and P-7 are `demote` and not `retire`, and why P-8 declines to decide.
- **Tokens.** No meter exists; turns are the enforced budget and the only honest unit here.
