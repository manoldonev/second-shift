# lean review verdict — #700

verdict=needs-work
run_id: review-700-1
session_id: 28c5de0d-fd63-43b1-80b9-a34d5e9f5478
rounds: 1
pr: #716
reviewed_head: 667f97365af28aa8393902ce6dbbff1651e2226d
reviewed_patch_id: 6d31a4247e97eee0ead4a9684deb3bc481d17a97
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #716 / issue #700

Range read: `f9eeb28..667f973` (full branch diff — round 1, nothing to inherit).
Reviewed from `/Users/mdonev/github/second-shift-worktrees/700`, verified pristine against
`origin/claude/second-shift-700` before the record was written.

**Verdict: needs-work.** Two blockers. The branch reds both correctness selftest lanes, and the
red is caused by the diff's own AC-11 deliverable; and one of the five new mutation-catalog rows
describes a regression its own `sed` does not produce, which is the one thing AC-15 exists to
prevent. Neither is in the parser: the rewrite is correct against the whole live corpus, the
fail-closed arm does what it claims, the other four catalog rows are probed kills, and both suites
the change edits are green here.

## Blockers

### B1 — `lint-and-selftests` and `selftests (macos, bash 3.2)` are red on the reviewed head, from this diff

`tools/prose-blockers-selftest.sh` fails `this repo's own tree is fully dispositioned — want '0',
got '3'` on both lanes of run `33321210185` at head `667f973`. Reproduced at the reviewed head:

```
[prose-blockers] UNDISPOSITIONED — in the tree, absent from docs/prose-blocker-triage.tsv:
  pb-15096154  plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:128
  pb-be1ceaa2  plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:140
  pb-db3589f8  plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:146
```

All three are lines this PR added — the AC-11 shape contract (`**The shapes the lean gate can
read.**`, `**Put an `OR-n` on every region.**`, `The refusal is an *environment* refusal:`). The
merge base is clean: at `f9eeb28` the census is 20 constructs, `✓ zero undispositioned`; at
`667f973` it is 23. So this is not inherited red — the PR grew the stop-tier census by exactly 3
and dispositioned none of them.

These are the correctness lanes, not the policy ones, so this is a blocker rather than a recorded
merge-boundary refusal. It is also not the trailer-only shape the carve-out is written for: the
fix adds rows to `docs/prose-blocker-triage.tsv` or rewords `SKILL.md`, either of which changes a
line this round read.

### B2 — `lean-openregions-heading-depth`'s note describes a regression its `sed` does not produce (AC-15)

The row's note reads:

> Reverts `open_regions_section` to terminating on ANY following heading, so a heading-per-region
> section yields zero non-blank content lines and reads as an empty section. A survivor would mean
> no case covers the shape whose failure mode is 'looks absent' rather than 'parses wrong'.

Its `sed` is `s#if \(RLENGTH <= depth\) insec = 0#if (0) insec = 0#`, which leaves the guarded
assignment unreachable — so the section **never terminates** and swallows everything after the
heading. That is the opposite of "terminating on ANY following heading", and it yields *more*
content, not zero.

Measured, both halves, each in its own isolated worktree at `667f973`:

| `sed` applied | killed by | expectation that moved |
| --- | --- | --- |
| the row as committed (`if (0) insec = 0`) | `(y28)` only | a *contentless* section now swallows the following `## Acceptance Criteria` body → rc=2, want rc=0 |
| the mutant the note describes (`insec = 0`) | `(y23)` only | the heading-per-region section reads as empty → rc=0, want rc=2 |

So the two mutants are killed by disjoint cases, and the case the note is about — `(y23)`, the
heading-per-region shape — **passes** under the row as committed. The row is not blind (it dies,
and it is anchor-loud), and the real regression is not uncovered (`(y23)` catches it). What is
wrong is the record: `mutation-catalog.tsv`'s own header defines the note column as "what
regression the mutant models, i.e. what a survivor would MEAN", and AC-15 requires the rows to
name "the regression classes this change introduces the risk of". This one names a class it does
not model, and the arming is pointed at a different site than the note claims.

It also falsifies the "each was probed" claim for this row specifically — the PR body says the
rows were "applied to an isolated worktree and the paired suite run — rather than credited by
construction", and a probe that was run *and read* would have shown `(y28)` where the note
predicts `(y23)`.

Cheapest fix: change the `sed` to `s#if \(RLENGTH <= depth\) insec = 0#insec = 0#`, which models
the actual pre-#700 behaviour and is killed by `(y23)` — measured above, so no new probe is owed.
Correcting the note to describe an unbounded section instead is also sound, but leaves the
heading-depth *reversion* unarmed by any row.

## Recorded, not blocking

### R1 — `pr-gates` is red on `guard-budget` (+385 lines, no `Guard-mass:` trailer)

`[guard-budget] ✗ guard/test shell mass grew by 385 lines with no reason recorded: base 54189
(ff3f6f8), HEAD 54574.` This is a policy gate the merge boundary already holds, so it is recorded
here and does not by itself move the verdict. It needs `Guard-mass: +385 <reason>` on one of the
branch's commits.

## Findings (non-blocking)

### F1 — the fail-closed arm does not fire on a section that MIXES a readable row with an unreadable one

`open_regions_defects` reports `unenumerable` only when the section yields **zero** rows. A
section carrying one parseable row plus a region in an unrecognized shape parses the first, is
non-empty, and clears silently — the fourth-form fail-open the code's own comment says the arm
exists to stop. Measured at the reviewed head:

```
## Open regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | foo | reversible-default-and-flag |

1. OR-2 — bar, pause-and-ask and nobody owns it
```
→ `ROWS=[OR-1 reversible-default-and-flag]`, `DEFECTS=[]`, milestone 1 CLEARS with a live
`pause-and-ask` region unread.

This is not an unmet `AC-n`: D-1 ratified the predicate as "zero `OR-n` rows in any recognized
shape", AC-5 states it the same way, and the code implements exactly that. The finding is that the
PR body's framing — "Shape coverage alone still fails open on the next unanticipated form; this is
what stops that" — is stronger than what shipped. The arm stops the next unanticipated form only
when it is the *only* form in the section.

### F2 — a bullet naming two ids enumerates only the first

`flush()` uses `match(buf, /OR-[0-9]+/)`, so `- OR-1 and OR-2: both stay
reversible-default-and-flag` emits `OR-1` and drops `OR-2` entirely — it can never be reported
dispositionless or pause-and-ask under its own name. Because `disp_of` scans the whole bullet, a
`pause-and-ask` anywhere in such a bullet still refuses, but under the wrong id. Zero occurrences
in the live corpus; worth a comment at the `match()` rather than code.

### F3 — a disposition on a nested SUB-bullet is read as "no disposition"

```
- **OR-1** — the ordering guarantee
  - Disposition: pause-and-ask
```
The sub-bullet matches the bullet rule before the continuation rule, so it flushes `OR-1` with an
empty disposition → `nodisp OR-1` → rc=2. Fail-closed, so not a defect in the safety direction,
but the new `interviewing-baseline` text says "continuation lines included" without saying a
nested bullet is not one — an author following the doc gets a refusal it does not predict.

### F4 — `open_regions_defects`' exit status is discarded

Both call sites read it through `<<EOF $(open_regions_defects …) EOF`, so a non-zero return (an
awk failure, a `grep` error rc=2) reaches the caller as an empty defect list and the check clears.
The realistic paths all fail closed (`open_region_rows` returning empty ⇒ `unenumerable`), so this
is low risk, but it is the same shape as the rc-in-a-subshell hazard `cmd_1`'s own comment calls
out for `check_pause_and_ask`. The security reviewer flagged it at confidence 40.

### F5 — AC-9's "every unenumerable SOURCE" is not pinned

`(y26)` pins two regions in one message from one source; `(y24)` and `(y30)` pin each source
separately. No case drives a defective ledger and a defective issue body in the same run, which is
the half of AC-9 that says "every source". The code appends with the same `${defects:+$defects; }`
idiom in both blocks so it is very likely right — but AC-9 is scored `satisfied (partially
pinned)` rather than fully verified by the suite.

### F6 — `tools/selftest-suite-timings.tsv` is not refreshed

The row for `lean-gate-selftest.sh` still reads `141 2026-08-20`. The suite gained ~200 lines
including `(y33)`'s 3000-line fixture; measured 215s cold here. Well clear of both consumer
thresholds either way, so nothing breaks — but the milestone-3 turn bound is computed from this
file.

### F7 — commit verb

The branch is three `fix:` commits. The middle one adds a new gate contract (a third milestone-1
verdict path) and carries a `Migration:` line in its `Changelog:`. Under CLAUDE.md's "use the
honest verb" that reads closer to `feat:`. Calling the repair of a fail-open `fix:` is defensible;
flagging it so the bump level is a decision rather than an accident.

## Dismissed

**`scope-completeness-reviewer`, confidence 88 — "issue #700's third shape (heading-per-region) is
not enumerated".** Correct on the facts and dismissed on authority. Issue #700 says "Not intaken
… Needs intake before it can be run", so its `## Scope` is a pre-intake sketch, and the pre-flight
interview is what refines it. `D-8` is an `intent`-kind row with `user-answered` provenance, it is
present in the pre-flight receipt (`.claude/pipeline-state/700-ledger.md:20`) and not only in the
committed spec, and `ledger-lint --reconcile` — which binds intent-row provenance — ran clean at
milestone 1 (progress record, `2026-08-30T15:08:22Z | milestone-1 | satisfied`). The committed
spec carries the departure in both its `## Scope boundary` and D-8. That is the pre-flight ledger
overriding the ticket's own wording, which is the documented order of authority, so the item is
deferred by an operator decision rather than by the build session's own judgment.

## What was measured, not taken on trust

**The whole live corpus, old parser vs new.** Every issue body in the repo (344 fetched) was
scanned for an `## Open regions` section: 17 carry one. Both parsers were sourced under
`LEAN_GATE_LIB=1` from an isolated worktree at `667f973` and run over all 17, plus all 43 on-disk
pre-flight receipts that carry the section.

| Issue | old ids | new ids | new rows | defects |
| --- | --- | --- | --- | --- |
| 372, 375 | OR-2 / OR-1 | unchanged | table, parse | — |
| 374, 381, 553, 622, 636, 637 | — | — | all `reversible-default-and-flag` | — |
| 554 | — | **OR-2** | bullet | — |
| 638 (open) | — | **OR-1** | bullet | — |
| 639 (open) | — | **OR-1** | bullet, continuation line | — |
| 694 | — | **OR-1, OR-2** | bullet | — |
| 640 (open) | — | — | OR-1/OR-2 flag, OR-3 empty | `nodisp OR-3` |
| 363, 426, 427, 441 | — | — | none | `unenumerable` |

Every claim in the PR body's Verification section reproduces exactly. The four `unenumerable`
issues are all CLOSED; of the three whose reading changes and are OPEN (#638, #639, #640) none
carries `ready-for-dev`, so D-13's blast-radius claim holds. **All 43 receipts: no divergence
between old and new, and zero defects** — the receipt half of AC-8 is non-regressive on the real
corpus.

**AC-14, first half.** Every one of the 26 pre-#700 `tools/mutation-catalog.tsv` rows targeting
`lean-gate.sh` was applied with `sed -E` at the reviewed head: all 26 still change the file and
all 26 still produce `bash -n`-valid output, so none drifted. Grepping the row programs for
`open_region`/`pause_and_ask`/`insec`/`disp` matches only the five new rows — confirming the
spec's "none was anchored on this code".

**AC-14, second half + AC-13.** Both edited suites run green here, cold, with
`env -u CLAUDE_CODE_SESSION_ID`:
`lean-gate-selftest.sh` → `all green`, 215s; `scenario-liveness-selftest.sh` → `76 passed, 0
failed`. This mattered: the build's own milestone 3 was 66s (`15:51:57Z → 15:53:03Z`), which is
the slow-suite-deferring shape — neither of the two suites this PR edits was necessarily run by
the green the build recorded.

**AC-15 — the five new catalog rows, probed not credited.** `mutation-sweep-pr` passed in 12s,
which for a 141s-rated suite means it graded none of them, so each row was applied to an isolated
worktree at `667f973` and `lean-gate-selftest.sh` run against it.

| Row | rc | killed by | verdict |
| --- | --- | --- | --- |
| `lean-openregions-unenumerable-clears` | 5 | `(y23)` `(y24)` `(y30)` `(y31)` `(y33)` | killed, note accurate |
| `lean-openregions-nodisp-swallowed` | 2 | `(y25)` `(y26)` | killed, note accurate |
| `lean-openregions-heading-depth` | 1 | `(y28)` | killed, **note wrong** — see B2 |
| `lean-openregions-bullet-continuation` | 2 | `(y20)` `(y21)` | killed, note accurate |
| `lean-openregions-content-test-via-pipe` | 1 | `(y33)` | killed, note accurate |

Baseline at `667f973` with no mutant: `rc=0`, 566 passing cases, 215s. Each mutant run took
211-231s, so no verdict rests on a timeout. `(y33)` is confirmed as the **sole** killer of the
SIGPIPE mutant, which is exactly the claim commit `667f973` makes for its own existence.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `^#+[[:space:]]+open regions([[:space:]].*)?$`; `(y22)`; #636/#622 now seen in the corpus run |
| AC-2 | satisfied | depth-keyed termination; `(y23)`; mutant `lean-openregions-heading-depth` |
| AC-3 | satisfied | bullet arm + continuation folding; `(y19)`, `(y20)`, `(y21)`; #639's live continuation-line token found in the corpus run; mutant `lean-openregions-bullet-continuation` |
| AC-4 | satisfied | 0 deletions in the selftest diff, so `(y2)/(y5)/(y6)/(y12)/(y14)` are untouched and green; `(y32)`; 43/43 receipts and 4/4 table-form issues unchanged old→new |
| AC-5 | satisfied | `(y23)`, `(y24)`, `(y33)`; mutant `lean-openregions-unenumerable-clears` killed by 5 cases |
| AC-6 | satisfied | `(y25)`; #640 OR-3 reports `nodisp` on the live body; mutant `lean-openregions-nodisp-swallowed` |
| AC-7 | satisfied | `(y21)`, `(y27)`, `(y28)`; absent-section path returns 0 before any grep |
| AC-8 | satisfied | `(y29)`, `(y30)` for the ledger; the jira arm is guarded identically and is inert (`body` is empty there), though no case pins that |
| AC-9 | satisfied (partially pinned) | `(y26)` pins two regions in one message; no case pins two SOURCES in one message — see F5 |
| AC-10 | satisfied | `(y31)`; `cmd_1`'s `[ "$pa_rc" -ne 2 ] \|\| envfail` precedes `fail_milestone`; liveness leg 3g asserts the attempt counter across the composed path |
| AC-11 | satisfied, but see B1 | `interviewing-baseline` gains the two-source shape table — and the three undispositioned prose constructs that red CI |
| AC-12 | satisfied | the refusal sentence is untouched (17 deletions in `lean-gate.sh`, all inside the two rewritten functions); `(y32)` asserts it fires without the new message |
| AC-13 | satisfied | `(y19)`–`(y33)`, all through `--issue-file`/`--ledger-file`, no network |
| AC-14 | satisfied | 26/26 existing rows re-anchored clean; liveness leg 3g + 3g-nv; both suites green here |
| AC-15 | **unsatisfied** | four of five rows name the class they model; `lean-openregions-heading-depth` does not — B2 |

## Verdicts (panel)

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (1 suppressed at 40) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 0 |
| Scope Completeness | Fail | 1 blocker at 88 — dismissed above on authority |

No `## Design` section in the spec and no design provider configured for this repo, so step 5b
does not apply: `fidelity: not-applicable`.
