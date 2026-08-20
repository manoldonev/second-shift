# lean review verdict — #565

verdict=needs-work
run_id: review-565-2
session_id: b430f288-a8e2-4240-b05b-652a6d4decd6
rounds: 2
pr: #603
reviewed_head: fe8334e40cfed71d90871ce1ee62bb4a8be17e99
reviewed_patch_id: 21e1b5cc7e479f4447c87959899b908775f7fd07
inherited_patch_id: ea3675e7844a6f6a86e3fdc2414b691a4fb32352
inherited_from_verdict: 201784e8c3d6c0b19e4a64773f7ae0b616bfd2a9
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR #603 (issue #565)

**Verdict: needs-work.** One blocker (B1), from the scope-completeness gate, verified
independently before being adopted. Range read: `201784e..HEAD` — the base merge, inheriting
patch `ea3675e7844a`. Panel: 4 reviewers selected, 4 returned; none dark.

## What this round actually is

Round 1 predicted this round would be a **re-stamp of an already-approved diff** "unless the
resolution touches more than the manifest append". It does not, and I measured that rather than
assuming it:

- `git diff 8ba330c fe8334e` (contribution on top of main) and `git diff 06e48be 201784e`
  (pre-merge contribution) are both 9 files / 980 insertions / 30 deletions.
- Their **added-line sets and removed-line sets hash identically**
  (`695b7e09…` / `3039307742e6…`). The only textual difference between the two diffs is the
  `lockstep-manifest.tsv` hunk header and one leading context line, because main appended a
  `tier-alphabet-parse` row above ours. `patch-id --stable` hashes context, which is exactly why
  the re-stamp is unavoidable for a zero-contribution-delta resolution.

So no new branch code exists. The blocker below is **not** new code — it is a contract-integrity
defect that was present in round 1 and that round 1's scope gate passed over. Round 2 finding it
is inheritance working as specified: the delta bounds what I read, never what I must find.

## Findings

| # | Sev | Site | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | `plugins/dev-pipeline/tools/retro-corpus.sh:350`; `docs/plans/second-shift-565-lean.md` AC-7d | **AC-8 is narrowed relative to the ticket by a spec amendment authored in the implementation commit.** Issue #565's AC-8 reads "WHEN **any** `\| milestone-N \| started` or `\| milestone-N \| concluded` row is timestamped after that milestone's `satisfied` row THEN the run is flagged `re-run`", unbounded. The implementation scans `for n in 1 2 3 4`. The AC that authorizes that bound — AC-7d — appears **nowhere in the issue body**; it was added to the committed spec in `d7a78cb`, *the same commit that added the code it authorizes*. The pre-implementation spec (`fc812f4`) carried AC-8 unbounded, identical to the ticket. review-lean names this shape a blocker in its own right: "a spec amended after the fact to match the diff is itself a blocker." |
| W4 | Warning | `tools/mutation-slow-suites.tsv` | New, and caused by this PR: `mutation-sweep-pr` warns `retro-corpus-selftest.sh` measured **14s** (≥ the 5s bar) with no row recording it, so the PR lane keeps sweeping its guard. Benign in direction (more coverage, more cost — never less), and the file's own header says membership drift "is a PRECHECK warn, never red; this committed copy updates by ordinary PR". Not a blocker; noting it because this PR is what pushed the suite over the bar (+415 lines). |
| W5 | Warning | `plugins/dev-pipeline/tools/pipeline-cost-block.sh:187,195,451` | #565's Dependencies note predicted the overlap with #546 would be "one comment hunk in one file". The diff carries **three** comment hunks — the D-36 annotation plus the `LOCKSTEP-BEGIN/END iso-to-epoch` markers AC-25 requires. AC-22 is still satisfied (every changed line is a comment; verified). Worth telling #546's author to expect the wider surface. |

### Carried forward from round 1, unchanged

The contribution is byte-identical, so none of round 1's findings were addressed and none were
re-introduced — they simply persist. W1 (`no-chronology` row overstates exclusion as
"everything"), W2 (`rounds` is null on every current-grammar record, so the Step 3 bullet
consuming it is unreachable on the live corpus), W3 (`reverifyMin` can exceed `wallClockMin`),
and S1–S6 all still stand as written in the round-1 record. S1 is the same defect B1 points at
from the other side: the code comment cites `(AC-7d/AC-8b)` and **`AC-8b` does not exist** in any
artifact — the ticket, the spec, or the tree.

## Why B1 is a blocker and not a warning — and what I checked before saying so

I did not take the gate's word for it. Three independent checks, all confirming:

1. **Issue body.** `gh issue view 565` — AC-8 is unbounded. AC-2b bounds only `spans`; AC-14
   bounds only `over-24h`. There is no AC-7d and no milestone-5 bound on `re-run`/`reverifyMin`.
2. **Commit archaeology.** `git show fc812f4:…second-shift-565-lean.md` has **no** AC-7d;
   `d7a78cb` — the implementation commit — introduces it. The spec did not lead the code here.
3. **Live-corpus measurement.** In an isolated probe (`/tmp`, never the reviewed tree) I widened
   *only* line 350 to `for n in 1 2 3 4 5` and ran both variants against the real 63-record
   corpus. Output is **identical on all 63 records** — same `re-run` flag (19/63 either way),
   same `reverifyMin`. 28 records carry milestone-5 rows, but none carries a
   `milestone-5 | satisfied` followed by a later `started`/`concluded`, so the widened arm is
   never exercised.

Check 3 is the fair-minded half, and it cuts **for** the change on the merits: the narrowing is
provably inert, and AC-2b/AC-14 in the ticket already twice establish that milestone 5 sits
outside the measured run, so AC-7d extends a pre-ratified principle rather than inventing cover
for a bug. That is a genuinely strong argument, and it is why this is stated as a
contract-integrity blocker rather than a behavioral one.

It is still a blocker. The rule exists to stop the shape where the implementation defines the
contract, and here the implementation commit literally authored the AC that permits it, on a
repo whose product *is* enforcement integrity. Inertness bears on impact, not on whether the
divergence happened; discounting a verified blocker because it is cheap is the softening
review-lean forbids. It also cost real accuracy: the code comment cites a nonexistent `AC-8b`,
which is what an amendment written in a hurry looks like.

**There is a code remedy, and check 3 proves it is safe.** Widening line 350 to `1 2 3 4 5`
makes the implementation match the ticket's AC-8 literally with a measured-zero blast radius
across the whole corpus (and AC-7d then comes out of the spec, or is restated as applying to
`reverifyMin` only). The alternative — amending #565's body to bound AC-8 to milestones 1–4 and
fixing the `AC-8b` citation — is the operator's call, not an agent's: editing a ticket's
acceptance criteria is a human-authority action. Either closes B1. I have deliberately not
picked for you.

## AC scoring — 33 of 34 satisfied, 1 unsatisfied

Scored against the **committed spec**, every AC every round. Unchanged from round 1 except AC-8,
which I am scoring differently on evidence round 1 did not surface. Round 1's bases for the other
33 were re-checked against this head and still hold; the ones I re-verified mechanically this
round are marked.

| AC | Score | Basis |
| --- | --- | --- |
| AC-8 | **unsatisfied** | The committed spec's AC-8 is satisfied only by reading it through AC-7d, and AC-7d is the after-the-fact amendment B1 describes. Against the contract as it stood when the code was written — and against the ticket today — the scan is narrower than the AC. Behaviorally inert (0/63 records differ), which is why it is a contract blocker rather than a defect report. |
| AC-7d | satisfied, but see B1 | Both the reverify loop and the `re-run` scan are bounded `1 2 3 4`, exactly as AC-7d states. The AC's *provenance* is the finding, not its implementation. |
| AC-23 | satisfied | **Re-verified on the merged tree.** The contribution diff (`8ba330c..fe8334e`) names nothing under `skills/build-lean/`, `skills/review-lean/`, `skills/run-lean/`, or `lean-gate.sh`. Note this AC must be scored against the *contribution* diff, not the merge range — the merge range does contain `lean-gate.sh` (#599) and both lean SKILL.mds, all of them main's, none of them this branch's. |
| AC-25 | satisfied | **Re-verified after the conflict resolution.** `scripts/lockstep-manifest.tsv` carries the `iso-to-epoch` row intact, and the resolution correctly kept *both* it and main's `tier-alphabet-parse` row. The `-u` is present on the BSD arm. |
| AC-15 | satisfied | **Re-checked against #596.** No vendor model token in `retro-corpus.sh`. `check-model-tiers.sh` (the gate #596 landed) exits 0 on this tree; its surface is the `.mjs` tier tables, so a passthrough `model` field in a shell tool is correctly out of its scope — no collision. |
| AC-22 | satisfied | Every changed line in `pipeline-cost-block.sh` is a comment. See W5 on the hunk count vs. the Dependencies prediction. |
| AC-24 | satisfied | CI `selftests (macos, bash 3.2)` passes at this head; no `declare -A`/`mapfile`/case-modification in the tool. |
| AC-26 | satisfied | CI `lint-and-selftests` passes at this head. |
| AC-1, AC-2, AC-2b, AC-2c, AC-3, AC-4, AC-5, AC-6, AC-7, AC-7b, AC-7c, AC-9 … AC-14, AC-16 … AC-21, AC-27 | satisfied | Bases as recorded in the round-1 record over the byte-identical contribution; inherited by reference to patch `ea3675e7844a` and spot-re-checked on this head. |

## Merge-state and CI — the first real build signal this PR has had

Round 1 approved a PR that had **zero** CI: it was `CONFLICTING` from birth, so `pr-gates` had
never evaluated it. The base merge fixed that, and the results are in — this is new information
round 1 could not have had, and it is clean:

- `lint-and-selftests` — pass · `selftests (macos, bash 3.2)` — pass
- `mutation-sweep-pr` — pass, and **not vacuously**: 21 verdicts computed by running a paired
  suite, both changed guards swept (`pipeline-cost-block.sh` 10 applied/6 killed/4 survived;
  `retro-corpus.sh` 9/7/2). All six survivors have baseline rows; `catalog::cost-block-cache-numerator`
  was already baselined on main pre-#565 ("seeded by the canonical seed run").
- `pr-gates` — fails on **exactly one** arm, the verdict-record freshness one
  (`ea3675e7844a` → `21e1b5cc7e47`), which is the re-stamp this round exists to perform.

**No re-anchor obligation.** `tools/mutation-catalog.tsv` carries no row anchored on
`retro-corpus.sh`, and both `pipeline-cost-block.sh` catalog anchors
(`cost-block-cache-numerator`, `cost-block-tier-unknown-fallback`) still match literally in this
tree, so this PR's guard edits disarm nothing.

**No collision from main's five arriving commits.** #596 — checked above (AC-15). #599 — changed
`lean-gate.sh`; touches nothing this branch owns, though it is why a detached review checkout no
longer works, so this round ran the gate from the lane worktree by name. #600/#602 — no
capability-parity row and no catalog/register row is owed by this diff; #602's new CLAUDE.md rule
scopes earn-your-keep to catalog rows and execution surfaces, and this PR adds neither. #598 — the
all-deferred guard is what makes the green sweep above meaningful rather than vacuous.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | **Fail** | 1 blocker (adopted as B1, after independent verification), 1 minor (adopted as W5), 2 suppressed <80 |
| Test coverage | Pass | 0 |
| Maintainability | Pass | 0 |
| Complexity | Pass | 0 |

Reduced round-2 lineup per the prior-round-context rule: round 1 had no blockers and the
contribution delta is zero, so security/performance/unit-test-mutation were not re-spawned over
byte-identical code they already passed. `a11y-reviewer` and the design-fidelity dimension were
not routed — no changed path matched `stageParams.webComponentGlobs` (unset → default
`apps/web/**/*.{tsx,jsx}`); this is a shell/markdown diff. Not a coverage gap. No reviewer went
dark.

## Verification run at this head

- Contribution-delta byte-identity across the merge: added/removed line sets hash-equal (above).
- Isolated widened-scan probe over the live 63-record corpus: 0 records differ.
- `check-model-tiers.sh`: exit 0.
- Catalog anchors for `pipeline-cost-block.sh`: both still match.
- CI at `fe8334e`: 3 jobs green, `pr-gates` red on the freshness arm only.
