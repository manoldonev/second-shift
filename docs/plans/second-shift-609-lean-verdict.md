# lean review verdict — #609

verdict=approve
run_id: review-609-2
session_id: d2b69ee9-c35e-4bc5-b894-3e9e3edad780
rounds: 2
pr: #614
reviewed_head: 231c9628cab259dcf0c09fd999b703af224404fc
reviewed_patch_id: ddde8f6109a9c092bb2c22aad6c6dd858558fa44
inherited_patch_id: 3c23f90156e0011eccf9a617d15d453ae06c0eca
inherited_from_verdict: 461f7e269abbb7a93c7b8ff6de6173e58f12ad23
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 2, inheriting round 1's coverage of patch `3c23f90156e0`. Delta `461f7e26..231c9628` — one fix
commit, 4 files, +68/-13. Round 1's single blocker (C-1: the suite green on macOS, `emit` exiting 139
under the ubuntu lane's awk) is **resolved, with evidence on the lane that gates the merge**. No new
blockers. Approve.

Round 1's five suggestions: S-1, S-2, S-3 and S-4 are addressed and each of the three code-bearing
ones is now guarded by a case that fails when the fix is reverted (probed below). S-5 was a nit about
a column header and is untaken — fine.

Panel: 5/5 reviewers returned, none dark. Zero findings at or above the confidence threshold from any
of them; the one 85 (scope-completeness) is explicitly recorded as requiring no change.

## Evidence for C-1's closure

CI run `32416881388` at the reviewed head:

| job | round 1 (`228e5955`) | round 2 (`231c9628`) |
| --- | --- | --- |
| `lint-and-selftests` → *run all selftests* (ubuntu) | `FAIL … (rc=1)`, 13 cases | **pass** — `pass tools/gate-ablation-selftest.sh`, `ALL CASES PASSED` |
| `mutation-sweep-pr` | `RED: unrunnable pair`, `mutants_applied 0` | **pass** — `applied=11 killed=11 survived=0` |
| `selftests (macos, bash 3.2)` | pass | pass |

The second row is the one that matters beyond the red build: round 1's finding was that the guard
shipped with zero mutants proving it can fail. It is now scored, and kills every mutant applied.

**The fix is complete, not merely sufficient for the fixture.** The crash class is a read that also
creates the element it reads, landing on a node a prior `printf` released. `seed_counters()` runs as
the first statement of `report()`, before any output, and seeds every counter rendering touches
(`fire`, `fire_verb`, `mech_n`, `dec_n`, `eval_s`, `eval_cov`, `rework_s`, `rework_cov`, `false_red`,
`repeat_n`, `n_advisory`). I enumerated every array subscript read from the rendering section onward
and checked the remainder: `cls_*` and `f_*` are assigned by construction; `keep_when`/`keep_key`/
`fr_when`/`fr_key` are read only past an `in` guard, and `in` does not create; and the two nested
reads round 1 flagged as suspects, `adj_note[keep_key[gp]]` and `adj_cite[fr_key[gp]]`, are safe
because `key` is only ever a value proven `in adj_dec`, and `adj_dec`/`adj_fr`/`adj_cite`/`adj_note`
are assigned together per row and so share one key set. No creation-on-read site remains in the
rendering path.

**"No cell moves" is verified, not asserted.** `docs/gate-ablation.md` was last written at `c3ed9071`
and was not regenerated this round, so the committed report predates the seeding. `check` regenerates
it with the seeded code and reproduces it byte-for-byte over the real 52-record corpus — that is a
direct measurement that seeding changed nothing. It also holds by reading: `total_fr()` and
`total_repeat()` sum values (`t += …`) rather than counting keys, so added zeros are inert, and
`advisory_by_ms()` guards on `> 0`.

## Probes — each new guard fails when its fix is reverted

Run in an isolated worktree at the reviewed head, scored by case id.

| probe | mutation | cases that failed |
| --- | --- | --- |
| P0 | none (baseline) | none, rc=0 |
| P1 | flip the eval-cost tiebreak in `worse()` | `(s)` — and only `(s)` |
| P2 | delete the committed-report scrub call | `(m5)` — and only `(m5)` |
| P3 | restore round 1's narrow absolute-path anchor | `(l3)` — and only `(l3)` |
| P5 | widen the anchor so a letter before the slash matches | `(l4)` among others |
| P4 | remove `seed_counters()` — the C-1 fix itself | **none, rc=0** |

P1–P3 establish that S-3, S-2 and S-1 are each guarded rather than merely fixed. P5 establishes that
`(l4)` is a live over-match guard and not a case that passes under every anchor.

P4 is the honest limit, and it is inherent rather than a gap to fill: the C-1 regression class is a
gawk heap bug, and no case runnable under the one-true-awk on this host can detect its return. Its
only coverage is the ubuntu job running the suite. The file header now says exactly that, in place of
the round-1 comment whose reasoning pointed at the lane that stayed green.

## Local verification

From the checkout of the reviewed head: `gate-ablation.sh check` clean (the committed block
reproduces from the pinned corpus, and the newly added committed-report scrub passes on the real
artifact); `gate-ablation-selftest.sh` all cases passed; `shellcheck -e SC1091,SC2015,SC2181` clean on
both shell files. Branch carries no `plugins/**` path and no release-owned file; `pr-gates` confirms
frozen-files clean and the changelog trailer not required.

## Strengths

- **The fix is diagnosed, not patched around.** The commit names the mechanism (an 8-byte
  heap-use-after-free in `r_force_number`), the surfacing exit codes on each platform, and the
  reason the tail of the report went missing rather than the run dying loudly. The header comment is
  corrected in the same commit, which is what stops the next edit from repeating the inference.
- **Seeding is the right shape of fix.** It removes the class rather than the instance, and it is
  simultaneously the honest description of the tables — every declared point has a row whether or not
  it fired, and each seeded value is the zero that row already prints.
- **The three suggestion fixes each arrived with a case.** S-1, S-2 and S-3 could all have been
  landed as silent one-liners; each instead has a probe-confirmed guard, and `(l4)` is a negative case
  that pins the widened anchor against over-matching rather than only against under-matching.
- **The spec annotation is honest.** F-5 gains a note that its two counts predate the corpus pin and
  names the shipped split; it is a Findings-section correction, not an acceptance criterion edited
  after the fact to match the diff.

## Critical (must fix before merge)

*(none)*

## Warnings (should fix)

*(none)*

## Suggestions (consider)

- **S-2 carry-forward — the manifest is still outside the scrub.** `check` now scrubs both the
  generated block and the committed report, which is the half round 1 asked for. The corpus manifest
  is named alongside the report in D-2's "no session ids and no absolute local paths" clause and is
  scrubbed by neither, nor is it scrubbed at `manifest` write time. It is clean today — I ran both
  scrub patterns over it directly and neither matched — and its content is structurally record ids
  plus hashes, so this is residual coverage rather than a defect. A third `scrub` call would close it.
- **The path anchor still has two evading shapes.** `-` and `/` are excluded from the
  preceding-character class, so a path glued directly behind a hyphen or a second slash is not
  matched. Security filed this at 70 and suppressed it; I agree with the suppression. The scrub is
  accidental-leakage hygiene over a report this tool generates itself, and both shapes require a
  deliberately crafted adjudication cell.
- **The PR body's case count is stale.** It says 39; the suite now carries 45 `check` invocations
  after this round's four additions. Cosmetic, and the PR body is not a gated artifact.
- **The tri-awk byte-identity claim is broader than what is verifiable here.** The commit reports
  identical output under one-true-awk, mawk 1.3.4 and gawk 5.2.1. CI proves gawk 5.2.1 over the
  fixture, and I reproduced the committed report under one-true-awk over the real corpus. The real
  corpus under gawk is unverified — and unreachable in practice, since the records are host-local to a
  macOS machine, so nothing rests on it. Recorded so the claim's support is visible.
- **S-5 remains untaken** (round 1): "first decision-changing firing" is manifest order, which is
  numeric issue id rather than chronological. Deterministic either way and harmless on today's corpus.

## Plan compliance

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited. Report unchanged this round; the classes table, the zero-fire enumeration and the citation form are untouched by the delta, and the unmatched-reason hard failure stays pinned by `(g)`/`(g2)`/`(g3)`, now green on both lanes. |
| AC-2 | satisfied | Strengthened this round. The ranking the criterion names is now order-pinned by `(s)`, probe-confirmed to fail on a flipped comparator. Scope-completeness records at 85 that the secondary key renders as `eval s` with attempt counts appearing as a column — correct, since the attempt count is already the primary key and cannot also be its own tiebreak; it explicitly asks for no change. |
| AC-3 | satisfied | Inherited; the method section, the four write-nothing refusal classes and the 47-record stage-era count are outside the delta. |
| AC-4 | satisfied | Inherited; the lower bound of 1 firing with its citation and the separately labeled upper bound are outside the delta. |
| AC-5 | **satisfied** — was the round-1 blocker | The suite is green on ubuntu (`ALL CASES PASSED`) and on macOS bash 3.2, and the sweep now scores the pair 11 applied / 11 killed. Determinism `(b2)` and the rc=4 scrub `(l)`/`(l2)` — both unreachable on the ubuntu lane in round 1 because `emit` died first — now pass there, joined by `(l3)`/`(l4)`/`(m5)`. `check` reproduces the committed block from the pinned corpus locally, and `emit`'s rc=3 drift arm is unchanged and green. |
| AC-6 | satisfied | Inherited and re-confirmed against the delta: the manifesto pointer is untouched this round, and the branch diff carries no `plugins/**` path, so no gate, skill or principle is edited. |

No scope creep. The delta is the awk fix, the two scrub changes, the ranking pin, four selftest cases
and one spec annotation — every one of them traceable to a round-1 finding.

## Pre-existing gaps (not blocking this PR)

- The generator's logic lives mostly in `tools/gate-ablation.awk`, and the mutation sweep mutates
  shell guards, so the awk file is not swept. That is the sweep's declared scope repo-wide, not
  something this PR introduced; the suite's cases are what cover the awk.

## Suppressed (below confidence threshold)

- `tools/gate-ablation.sh` (70) — the two anchor-evading shapes; promoted to a suggestion above.
- `tools/gate-ablation.sh` (55) — the committed-report scrub runs before the later mktemp and its
  trap. Verified harmless: no temp file exists at that point, so an rc=4 there orphans nothing.
- Scope-completeness noted that the dispatched base was the round-1 verdict commit rather than the
  PR base, and judged scope against the real merge-base instead. That was the intended delta range;
  its correction means the AC scoring above rests on the whole branch, not the delta.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 1 (nit, no change required) | 85 |
| Security | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

Not selected: `performance-reviewer` under the round-2 reduced-lineup rule — it returned no findings
in round 1 and the delta's only new cost is a bounded one-pass seeding loop. `a11y-reviewer` and the
design-fidelity dimension were not routed: no changed path matched the resolved
`stageParams.webComponentGlobs` (unset, so the default). `db-reviewer`, `pipeline-reviewer` and
`unit-test-mutation-reviewer` were not triggered. No reviewer went dark.

Design fidelity is `not-applicable`: the spec arms no `## Design` section — no handoff link, no
render-state rows — and the repo configures no design provider, so the disarm needs no justification.

**Ready to merge? Yes.**

**Reasoning:** the round-1 blocker is closed on the lane that gates the merge, with the mutation
coverage it cost restored; the fix removes the crash class rather than an instance, and its
output-neutrality is measured against the real corpus rather than argued. Every AC is satisfied, the
panel is unanimous with nothing at blocking confidence, and the three suggestion fixes each ship with
a guard that fails when reverted.

`pr-gates` is red on the round-1 `needs-work` record — the expected pre-handoff state, which this
record clears.
