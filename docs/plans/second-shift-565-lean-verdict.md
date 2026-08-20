# lean review verdict — #565

verdict=approve
run_id: review-565-3
session_id: 2f2673d7-6fb6-4e00-a639-b9c66aea55fa
rounds: 3
pr: #603
reviewed_head: 063e6a2a0e13f7dedd4d3e71132455c03d89a056
reviewed_patch_id: ad7b8eacb16df05ede32b9c6a3d71e40cd714b57
inherited_patch_id: 21e1b5cc7e479f4447c87959899b908775f7fd07
inherited_from_verdict: 6fbe381e75b48fcec5a907e1c2884f07f26eabf2
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 3 — PR #603 (issue #565)

**Verdict: approve.** Zero blockers. Round 2's sole blocker (B1) is closed, and I verified the
close from primary sources rather than taking the build session's account of it. Range read:
`6fbe381..HEAD`, inheriting patch `21e1b5cc7e47`. Panel: 4 reviewers selected, 4 returned, none
dark, all approve with zero findings.

## What this round is

Two commits since round 2, and neither changes behavior:

- **`dc5d5ef`** — the round-2 remedy, mirrored into the artifacts. Spec AC-8 restated to the
  ticket's ratified wording (`bounded by AC-7d`), AC-7d annotated with its provenance, ledger row
  **D-26** added, and the code comment at `retro-corpus.sh:346` re-pointed from `AC-8b` (which
  existed in no artifact — round 1's S1) to `AC-8`. 10 spec lines, 1 comment line.
- **`063e6a2`** — the operator's base merge of `origin/main` (`3b55bc7`), resolving the add/add
  conflict in `scripts/lockstep-manifest.tsv` that the build session correctly handed back rather
  than executing (`git merge` is deny-listed for a build session).

## B1 is closed, and closed legitimately

Round 2's blocker was **not** "the code is wrong" — round 2 measured the code as behaviourally
inert and said so. It was "AC-7d, the AC that authorizes the milestone-1–4 bound, was authored in
the implementation commit and appears in no version of the ticket." The remedy for that shape is
a human-authority action, and the operator took it.

**Verified three independent ways, none of them the build session's word:**

1. **Issue revision history.** `userContentEdits` carries the full body per revision. Testing each
   revision for the contested strings:

   | revision | editor | `AC-7d` | AC-8 reads "bounded by AC-7d" |
   | --- | --- | --- | --- |
   | 2026-08-16T20:25:13Z (creation) | `manoldonev` | absent | no |
   | 2026-08-18T18:29:35Z (intake) | `manoldonev` | absent | no |
   | **2026-08-20T15:40:54Z** | `manoldonev` | **present** | **yes** |

2. **The live ticket.** `gh issue view 565` line 63 carries AC-7d verbatim; line 64's AC-8 reads
   "…THEN the run is flagged `re-run`, **bounded by AC-7d**, and no span changes as a result."
3. **The spec mirrors it rather than re-deciding it.** `dc5d5ef` restates the spec's AC-8 to the
   ticket's wording and annotates AC-7d with who ratified it and when. D-26 records the decision,
   its author and its basis. No AC was widened, narrowed, or invented by the build session.

**And I re-measured the merits rather than inheriting round 2's measurement.** In an isolated
`mktemp` probe (never the reviewed tree), I copied `retro-corpus.sh` and widened **only line 350**
— the `re-run`/`reverifyMin` scan — to `for n in 1 2 3 4 5`, leaving line 315 (the `spans` scan,
authorized by AC-2b) untouched, and confirmed by `diff` that exactly one line moved. Both variants
ran against the live state dir, now **64** records (round 2 measured 63):

```
diff <(jq -S . narrow.json) <(jq -S . wide.json)  →  IDENTICAL on all 64 records
```

So the ratification did not paper over a behavioural difference. The bound is measurably inert,
and the ticket's own AC-2b and AC-14 already twice place milestone 5 outside the measured run —
AC-7d extends a pre-ratified principle, and now does so with the ticket's authority behind it.

**The one thing I checked for and did not find:** the build session did *not* also apply the code
remedy. Widening the loop after the ticket bounds AC-8 would have put the code back out of step
with the contract. Mirroring only was the correct half to take.

## The base merge, measured

Round 2's method, re-run on this resolution. Contribution before the merge (`8ba330c..dc5d5ef`) vs
after (`3b55bc7..HEAD`): both 9 files, `-30` deletions, removed-line sets hash **equal**
(`e28ac2bf…`). Added-line sets differ by exactly **one** line, and `comm` names it:

```
only in PRE (dropped by the resolution):  +#
only in POST (added by the resolution):   (nothing)
```

That is a bare `#` comment separator in `scripts/lockstep-manifest.tsv`. Main's own `#` above the
`contribution-compare` block was reused as the separator before the `iso-to-epoch` block, so the
branch no longer contributes its own. **No code, no data row and no comment text was lost on either
side** — both the branch's `iso-to-epoch` row and main's `tier-alphabet-parse` and
`contribution-compare` rows are intact, and `check-lockstep-pairs.sh` reports 25 pairs / 0 failed.
The residue is cosmetic and is filed as S7 below.

## Findings

| # | Sev | Site | Finding |
| --- | --- | --- | --- |
| S7 | Suggestion | `scripts/lockstep-manifest.tsv:738` | The merge resolution left the `iso-to-epoch` data row immediately followed by the `# The contribution comparison (#597 D-4)` comment with no bare-`#` separator. Across all 738 lines of the manifest this is the **only** data-row→comment-block adjacency without one, so it is a one-line deviation from the file's own convention. No parse impact (25 pairs pass). Fix it in whatever PR next appends to the file rather than spending a round on it. |

Nothing else new. The panel returned zero findings across all four reviewers; scope-completeness
returned two sub-80 suppressed notes, both AC-21 line-reference drift already covered by ledger
row **D-25**, and neither is a defect in the tree.

### Carried forward, dispositions

- **B1** (round 2, blocker) — **closed**, verified above.
- **S1** (round 1: the comment cites `AC-8b`, which exists nowhere) — **fixed** in `dc5d5ef`.
- **W4** (round 2: `retro-corpus-selftest.sh` measures 14–15s with no `tools/mutation-slow-suites.tsv`
  row) — **deliberately not fixed, and correctly so.** That file's own header states "The PR lane
  defers any guard whose killer appears here." Adding the row would buy a quieter precheck by
  trading away the `retro-corpus.sh` guard on every PR lane — exactly the coverage this PR just
  paid for. The drift is "a PRECHECK warn, never red" by the file's own contract. I re-confirmed
  the warn still fires (`measured 15s`) and that the guard is still swept. Accepting the build's
  refusal, not re-raising it.
- **W1** (`no-chronology` row says the run is excluded from "everything") — **still stands, still a
  warning.** Re-read the code: with no parseable first row `base_e` starts empty, so span(1) is
  suppressed, but `base_e` is reassigned from `satisfied(1)`, so spans 2–4 *are* still emitted.
  "Everything" therefore overstates the exclusion by the same margin round 1 named. Doc precision,
  not behaviour.
- **W2** (`rounds` is null on every current-grammar record) — **still stands.** Re-confirmed on the
  live corpus: all 8 records in the default window render `rounds` as `-`. AC-10 permits null, so
  this is not an AC violation; it is the consuming SKILL.md bullet being unreachable in practice.
- **W3** (`reverifyMin` can exceed `wallClockMin`) — **still stands, and is now vivid.** This run's
  own record: `565` reports `wallClockMin=533`, `reverifyMin=3188`. Documented as a diagnostic
  outside every sum (AC-7/AC-7c), so not a defect.
- **W5** (three comment hunks in `pipeline-cost-block.sh` vs the one the Dependencies note
  predicted) — **still stands**, informational for #546.
- **S2–S6** (round 1) — unchanged; no code moved.

## AC scoring — 34 of 34 satisfied

Scored against the committed spec, every AC every round. The change from round 2 is AC-8, which
round 2 scored unsatisfied on B1's evidence and which the ratification closes.

| AC | Score | Basis |
| --- | --- | --- |
| **AC-8** | **satisfied** | Was round 2's sole unsatisfied AC. The ticket now reads "bounded by AC-7d" (revision 2026-08-20T15:40:54Z, operator-authored, verified from the issue's own edit history), and the committed spec's AC-8 restates that wording. Code scans `1 2 3 4` at `retro-corpus.sh:350`, which is what the ratified AC specifies. Re-measured inert against all 64 live records. |
| **AC-7d** | satisfied | Both the reverify loop (`:350`) and the spans loop (`:315`) are bounded `1 2 3 4`. The AC's *provenance* was round 2's finding; that is now resolved and recorded inline in the spec plus D-26. |
| AC-2c | satisfied | **Re-verified on the live corpus, not fixtures.** `109-lean-progress` emits `spans={"1":81,"2":-58,"3":14,"4":42}` — the negative span is emitted as measured and **floored** (-58), not truncated (-57), not clamped, not dropped. |
| AC-20 | satisfied | **Re-verified by running the tool.** `retro-corpus.sh timing --window 8` against the live state dir renders 8 populated rows with spans, flags and orchestration state — not "not applicable", not empty. |
| AC-22 | satisfied | **Re-verified mechanically on this head.** Every added/removed line in the `pipeline-cost-block.sh` contribution diff is a comment; `cost-block-selftest.sh` appears in zero changed files. |
| AC-23 | satisfied | **Scored against the contribution diff, not the range.** `git diff --stat origin/main HEAD` names 9 files, none under `skills/build-lean/`, `skills/review-lean/`, `skills/run-lean/`, nor `lean-gate.sh`. The *range* `6fbe381..HEAD` does contain all four — every one of them main's, arriving via `063e6a2`. |
| AC-24 | satisfied | **Verified locally as well as in CI.** `retro-corpus-selftest.sh` under stock `/bin/bash` 3.2.57: 41 passed, 0 failed. CI `selftests (macos, bash 3.2)` also passes at this head. |
| AC-25 | satisfied | **Re-verified after the second conflict resolution.** The `iso-to-epoch` row survives intact with the BSD `-u` arm; `check-lockstep-pairs.sh` reports 25 pairs, 0 failed. |
| AC-26 | satisfied | `retro-corpus-selftest.sh`: 41 passed, 0 failed. CI `lint-and-selftests` passes at this head. |
| AC-1, AC-2, AC-2b, AC-3 … AC-7c, AC-9 … AC-19, AC-21, AC-27 | satisfied | Bases as recorded in the round-1 and round-2 records over a contribution that is byte-identical apart from `dc5d5ef`'s 11 lines; inherited by reference to patch `21e1b5cc7e47` and spot-re-checked on this head. |

## CI — green for the first time on a mergeable head

Round 1 approved at zero CI (born `CONFLICTING`); round 2 got the first real signal but re-broke on
the second base advance. At `063e6a2` the PR is `MERGEABLE` and:

| check | result |
| --- | --- |
| `lint-and-selftests` | **pass** (3m53s) |
| `selftests (macos, bash 3.2)` | **pass** (6m37s) |
| `mutation-sweep-pr` | **pass** (1m41s) |
| `pr-gates` | fail — **stale verdict only** |

`pr-gates`' only finding is that the committed record still reads `verdict=needs-work`, which is
precisely what this round replaces. Every other evidence artifact passes.

**The mutation sweep is not vacuous.** It reports **21 verdicts computed by running a paired
suite**, 0 served from cache, with both changed guards swept — `pipeline-cost-block.sh`
10 applied / 6 killed / 4 survived, `retro-corpus.sh` 9 / 7 / 2. No baseline-absent survivor. Its
one WARN is W4 above, accepted.

**No re-anchor obligation.** `tools/mutation-catalog.tsv` carries no row anchored on
`retro-corpus.sh`, and both `pipeline-cost-block.sh` anchors (`cost-block-cache-numerator`,
`cost-block-tier-unknown-fallback`) target executable lines this PR's comment-only diff does not
touch — re-confirmed literally in this tree.

## Verification run at this head

All from the lane worktree at `063e6a2`, clean and in sync with the remote (`0 0`):

- `retro-corpus-selftest.sh` — 41 passed, 0 failed, under bash 5 **and** stock `/bin/bash` 3.2.57.
- `check-lockstep-pairs.sh` — 25 pairs, 0 failed.
- `shellcheck -e SC1091,SC2015,SC2181` on all three changed shell files — clean.
- Isolated widened-scan probe over the live 64-record corpus — 0 records differ.
- Contribution line-set hashing across the merge — one `#` comment line, enumerated by `comm`.
- Issue-revision archaeology for AC-7d — three revisions, absent/absent/present.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | Pass | 0 (2 suppressed <80, both AC-21 line-ref drift covered by D-25) |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |
| Test coverage | Pass | 0 |

Reduced round-3 lineup under the prior-round-context rule: round 2's only blocker came from the
scope gate, and the fix commits are documentation plus one comment word, so security /
performance / unit-test-mutation were not re-spawned over code they already passed unchanged.
`a11y-reviewer` and the design-fidelity dimension were not routed — no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`); this is a
shell/markdown diff. Not a coverage gap. No reviewer went dark.

Design fidelity scored `not-applicable`: the spec has no `## Design` section.

## Follow-up owed at close-out

**OR-2** — 27 of 51 records stop before milestone 4 — is flagged in the spec's Open Regions and
was never in this PR's scope. It still needs a filed follow-up issue, as the PR body promises.
S7 above should be swept up by whichever PR next appends to `scripts/lockstep-manifest.tsv`.
