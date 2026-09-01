# lean review verdict — #700

verdict=approve
run_id: review-700-2
session_id: f0dca896-cc78-4b0f-a34b-62ee4008d6e5
rounds: 2
pr: #716
reviewed_head: 4fe450c8e6f3c31b68d7d4f58ed99ec32c25e8cb
reviewed_patch_id: c1dace94684f23df8e561c4b3019ae215dceb547
inherited_patch_id: 6d31a4247e97eee0ead4a9684deb3bc481d17a97
inherited_from_verdict: e5bcdfd9b6430e02f20aa8a4d6f6324938a33ac4
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #716 / issue #700

Range read: `e5bcdfd..4fe450c`, inheriting the coverage of patch `6d31a4247e97` (round 1).
Reviewed from `/Users/mdonev/github/second-shift-worktrees/700`, verified identical to
`origin/claude/second-shift-700` before the record was written. Round 1's findings were read
first.

**Verdict: approve.** Both round-1 blockers are fixed, and each fix was re-derived here rather
than taken from the fix commit's own account. `lean-gate.sh` and both edited suites are unchanged
since round 1, so the parser evidence from that round carries; what is new in this delta is four
record files, and every claim they make was checked.

## Round-1 blockers — both discharged

### B1 — three undispositioned prose constructs redding both correctness lanes: FIXED

The fix adds three rows to `docs/prose-blocker-triage.tsv` and leaves
`interviewing-baseline/SKILL.md` untouched — the cheaper of the two remedies round 1 named, and
the one that does not re-stale the AC-11 prose that round read.

Re-derived at the reviewed head rather than inherited: `bash tools/prose-blockers.sh check` reports
`census: 23 construct(s) over 51 file(s)` and `✓ zero undispositioned constructs`, and
`bash tools/prose-blockers.sh census` emits `pb-15096154` / `pb-be1ceaa2` / `pb-db3589f8` at
exactly the three sites the new rows name (`SKILL.md:128`, `:140`, `:146`). The ids are
content-derived, so this is the check that they were computed against the shipped prose and not
transcribed.

CI oracle at this head — command and head both match, so cited rather than re-run:
run `33324495676` @ `4fe450c`, `lint-and-selftests` **success** with
`prose-blockers-selftest.sh: 60 passed, 0 failed` and `[run-selftests] summary: 78 scored, 77 run,
1 served from cache, 0 failed` (the cached suite is `cost-block-selftest.sh`, unrelated);
`selftests (macos, bash 3.2)` **success**. Both suites this PR edits ran in that sweep —
`pass 167s lean-gate-selftest.sh`, `pass 67s scenario-liveness-selftest.sh` — so the green is not
the slow-suite-deferring shape.

The three rows are substantively right, not merely present. Each is `gate-backed` / `pointer-kept`
with an enforcer that resolves: `open_regions_defects` (:2998), `open_region_rows` (:2929) and
`cmd_1` (:3488) all exist in `lean-gate.sh`. `tools/prose-blockers.sh:105` says the guard verifies
the enforcer PATH and explicitly not the named subcommand, so those three names are checked here or
nowhere. The "prose restates a gate but is kept because its audience writes the section in an
intake session no build gate is running in" reading is the one `pb-2253f5d9` and `pb-30bb039d`
already take.

### B2 — the `lean-openregions-heading-depth` note describing a mutant its `sed` does not produce: FIXED

The row's program is now `s#if \(RLENGTH <= depth\) insec = 0#insec = 0#`. Probed here in a
throwaway `git worktree --detach` at `4fe450c`, applied the way `tools/mutation-sweep.sh:1852`
applies it (`sed -E -e`):

- not byte-identical (no anchor drift), and the diff is exactly one line:
  `insec && /^#+[[:space:]]/ { match($0, /^#+/); if (RLENGTH <= depth) insec = 0 }` →
  `insec && /^#+[[:space:]]/ { match($0, /^#+/); insec = 0 }`
- `bash -n` valid
- `lean-gate-selftest.sh` against it produces
  `FAIL: (y23) expected rc=2 naming an unenumerable section, got 0` — the heading-per-region case,
  which is the shape the note claims the row models. 457 cases passed; `(y23)` was the only
  failure in the run.

**Run caveat, stated rather than papered over.** That run did not reach its own summary line: it
hung after ~14 minutes inside an unrelated network-touching case (`lean-gate.sh … claim 8`), with
a second lane's probe (`second-shift-worktrees/670-mut`) running concurrently on this machine. It
covered 458 of the suite's ~566 cases, and I killed it by PID and restored the mutant. The prefix
it did cover contains the entire `(y19)`–`(y33)` open-regions block, which is where any additional
killer of a mutation to `open_regions_section` would have to be; the ~108 unreached cases are the
`(pc)`/`(pg)`/`(ac)`/`(if)` progress, milestone-4 and in-flight blocks, none of which touch that
function. So "killed, by `(y23)`" is measured; "by `(y23)` and nothing else, suite-wide" rests on
that prefix plus round 1's independent measurement of the same mutant at `667f973`, where
`lean-gate.sh` was byte-identical.

The note's own claim also checks out against the base. At `f9eeb28` the line read
`insec && /^#+[[:space:]]/ { insec = 0 }` (`lean-gate.sh:2886`), so "reverts
`open_regions_section` to terminating on ANY following heading" describes the pre-#700 behaviour
exactly — the `match($0, /^#+/)` the mutant leaves behind sets `RSTART`/`RLENGTH` and changes no
control flow.

This row has no PR-lane oracle either way: `mutation-sweep-pr` passed in **12s** on run
`33324495676`, which for a 212s-rated suite means it deferred these rows and graded none of them.
The probe above is the only thing standing behind the row.

## Also fixed this round

- **R1 (round 1, recorded-not-blocking) — `guard-budget`.** `4fe450c` carries a `Guard-mass: +385`
  trailer, and the gate is now green at this head: `[guard-budget] ✓ guard/test shell mass: base
  54358, HEAD 54743 (delta +385), covered by a 'Guard-mass:' trailer.` The delta figure is
  unchanged from round 1 even though the base moved (54189→54358), which is what the trailer's own
  "the figure is the branch's" claim asserts.
- **F6 — `tools/selftest-suite-timings.tsv`.** The `lean-gate-selftest.sh` row moves
  `141 / 2026-08-20` → `212 / 2026-08-30`. The commit's claim that no consumer decision moves is
  verified: `mutation-sweep.sh` thresholds at 5s and `run-selftests.sh` / `check-sweep-bound.sh` at
  9s, so the suite was deferred at 141 and is deferred at 212; and `check-sweep-bound.sh`'s
  aggregate ratchet sums only the **un-deferred** subset (`:147-231`) against the
  `# baseline-seconds 106` directive, which this diff does not touch. Round 1 independently
  measured 215s cold; CI measured 167s on the Linux runner. Nothing keys on the precision.

## `pr-gates` is red, and that is expected state

The only failing step is `lean chain reconciliation`:
`[lean-chain] ✗ verdict record … reads 'verdict=needs-work', not 'verdict=approve'`. That arm
requires an approving record to exist, so it cannot be green before this round writes one. Not a
finding.

## Findings (non-blocking)

### N1 — AC-15 was amended this round; it strengthens rather than launders, but say so out loud

The delta adds to AC-15: *"A row's note must name the regression its own `sed` produces: a note
describing a different mutant is what a probe that was run and READ would have caught, so the note
is part of what the probe checks."* This codifies round 1's B2 into the spec.

Flagged because "a spec amended after the fact to match the diff is itself a blocker" is the rule,
and this is an amendment made between rounds. It is not that shape: it **adds** an obligation
rather than relaxing one, and the diff satisfies AC-15's *original* wording independently — the
`sed` was corrected, not the criterion. `ledger-lint --reconcile` is clean at this head
(`9 bound, 9 carried, 0 departure(s)`), and the amendment is AC prose, not a ledger re-decision.
Scored `satisfied` on the pre-amendment text, so the amendment is not load-bearing for the verdict.

### N2 — D-8's deferral still lives only in the spec and receipt, not the issue body

`scope-completeness-reviewer` raised this again at confidence 88 (its own verdict: approve,
non-blocking): issue #700's Scope asks for "at minimum: table row, bullet, and a
heading-per-region", and no heading-per-region *parser* is written. Same disposition as round 1,
re-checked at the current head rather than inherited: `D-8` is present in the pre-flight receipt
(`.claude/pipeline-state/700-ledger.md:20`) with `user-answered` provenance and `intent` kind,
carried verbatim into the committed spec (`:114`) and its `## Scope boundary` (`:98`), and
`ledger-lint --reconcile` binds it clean. The receipt's mtime (18:14) predates both round-2
commits, so it is not a record edited to fit the fix. The pre-flight ledger overriding the
ticket's own wording is the documented order of authority. The reviewer's suggested remedy —
editing the issue body's acceptance criteria — is a human-authority action, so it is recorded, not
actioned.

### Carried from round 1, unaddressed and still non-blocking

`lean-gate.sh` is unchanged, so these stand exactly as round 1 wrote them and are not re-argued
here: **F1** the fail-closed arm does not fire on a section mixing one readable row with an
unreadable region (matches D-1/AC-5 as ratified; the PR body's framing is broader than what
shipped); **F2** a bullet naming two ids enumerates only the first; **F3** a disposition on a
nested sub-bullet reads as "no disposition" (fail-closed, but the new doc does not predict it);
**F4** `open_regions_defects`' exit status is discarded at both call sites; **F5** AC-9's "every
unenumerable SOURCE" has no case driving two defective sources in one run; **F7** the branch's
`fix:` verb on a commit that adds a new gate contract reads closer to `feat:` under CLAUDE.md's
honest-verb rule — a bump-level decision for the merge dialog, not a blocker.

## AC scoring

Every AC scored against the whole spec. Where the evidence is round 1's, it is because the code it
rests on is byte-identical at this head — not because it was inherited unexamined.

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | round 1: relaxed heading regex, `(y22)`, #636/#622 seen in the live-corpus replay; `lean-gate.sh` unchanged, suite green in CI at `4fe450c` |
| AC-2 | satisfied | round 1: depth-keyed termination, `(y23)`; and the `lean-openregions-heading-depth` mutant re-probed here kills via `(y23)` |
| AC-3 | satisfied | round 1: bullet arm + continuation folding, `(y19)`–`(y21)`, #639's live continuation token |
| AC-4 | satisfied | round 1: zero deletions in the selftest diff; 43/43 receipts and 4/4 table-form issues unchanged old→new |
| AC-5 | satisfied | round 1: `(y23)`, `(y24)`, `(y33)`; `lean-openregions-unenumerable-clears` killed by five cases |
| AC-6 | satisfied | round 1: `(y25)`; #640's OR-3 reports `nodisp` on the live body |
| AC-7 | satisfied | round 1: `(y21)`, `(y27)`, `(y28)` |
| AC-8 | satisfied | round 1: `(y29)`, `(y30)`; all 43 on-disk receipts non-regressive |
| AC-9 | satisfied (partially pinned) | round 1: `(y26)` pins two regions in one message; no case pins two SOURCES — F5 |
| AC-10 | satisfied | round 1: `(y31)`, `cmd_1`'s `[ "$pa_rc" -ne 2 ] \|\| envfail` ahead of `fail_milestone`, liveness leg 3g |
| AC-11 | satisfied | the `interviewing-baseline` shape contract is unchanged from round 1, and its three stop-tier constructs are now dispositioned: census `23 / ✓ zero undispositioned` here, `prose-blockers-selftest.sh` 60/0 and both correctness lanes green at `4fe450c` |
| AC-12 | satisfied | round 1: the refusal sentence is untouched; `(y32)` |
| AC-13 | satisfied | round 1: `(y19)`–`(y33)` all via `--issue-file`/`--ledger-file`; `lean-gate-selftest.sh` green in CI at this head |
| AC-14 | satisfied | round 1: 26/26 pre-#700 rows re-anchored and `bash -n` valid, none anchored on this code; both edited suites green in CI at this head |
| AC-15 | **satisfied** | all five rows now name the class they model. The corrected `lean-openregions-heading-depth` was probed at this head, not credited by construction — one-line change, `bash -n` valid, killed by `(y23)`, the case the note is about. `mutation-sweep-pr`'s 12s pass confirms the row still has no PR-lane oracle, which is why the probe was run |

## Verdicts (panel)

Reviewed range `e5bcdfd..4fe450c` — four record files, no executable surface.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Security | Pass | 0 | 2 suppressed at 15–20 |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Scope Completeness | Pass | 1 minor, non-blocking | 88 — N2 |

`complexity-reviewer` was not selected (delta below the Medium bar). `a11y-reviewer` and the
design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs`, which is unset in this repo's config and resolves to the default
`apps/web/**/*.{tsx,jsx}`. No reviewer went dark.

No `## Design` section in the spec and no design provider configured, so step 5b does not apply:
`fidelity: not-applicable`.
